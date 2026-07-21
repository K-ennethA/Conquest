extends GutTest

# Tests for Forest Barrage -- Eldroot's 4th move, the crawling lane hazard -- and the
# two seams that make it work in play: the SpawnHazardEffect -> HazardManager signal
# (a cast resolves its first segment and requests a live vine) and the BossController
# heuristic that actually fires it (the generic planner scores a hazard at 0, so the
# boss needs a nudge to punish an aligned kiter).
#
# Mock style mirrors test_ai_behavior.gd (duck-typed stub units + a lightweight board).

# --- Mocks -----------------------------------------------------------------

class Stub:
	var team: int
	var stats: Dictionary
	var hp: int
	var boss: bool

	func _init(p_team: int, p_stats: Dictionary, p_boss: bool = false) -> void:
		team = p_team
		stats = p_stats
		hp = int(p_stats.get("health", 100))
		boss = p_boss

	func get_stat(n: String) -> int:
		return int(stats.get(n, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func get_hp() -> int:
		return hp

	func is_boss() -> bool:
		return boss


class MockBoard:
	var placements: Array = []  # { unit, cell }

	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team


# --- Content loaders -------------------------------------------------------

func _forest_barrage() -> MoveResource:
	return load("res://game/combat/moves/forest_barrage.tres") as MoveResource

func _hazard_effect_of(move: MoveResource):
	# Untyped: move.effects is Array[MoveEffect], so the subclass fields (width,
	# speed, ...) are only reachable through a dynamic variable.
	for e in move.effects:
		var fx = e
		if fx is SpawnHazardEffect:
			return fx
	return null


# ===========================================================================
# CONTENT -- the authored move
# ===========================================================================

func test_forest_barrage_is_a_ranged_lane_hazard_on_a_long_cooldown():
	var move := _forest_barrage()
	assert_eq(move.move_id, &"forest_barrage")
	assert_eq(move.cooldown, 3, "a heavy answer, not spammable")
	assert_eq(move.accuracy, 1.0, "a hazard is environmental -- it always lands")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.ENEMY, "aimed at a hostile cell")
	assert_eq(move.targeting.max_range, 6, "reaches across the lane's full length")
	assert_eq(move.targeting.area_shape, CombatTypes.AreaShape.SINGLE,
		"the aim only picks direction+distance; the effect derives the lane")

	var fx = _hazard_effect_of(move)
	assert_not_null(fx, "it carries a SpawnHazardEffect")
	assert_eq(fx.width, 5, "5-wide band")
	assert_eq(fx.speed, 2, "2 cells/turn")
	assert_eq(fx.travel_range, 6, "6 cells of travel")
	assert_eq(fx.affiliation, CombatTypes.TargetKind.ENEMY,
		"Forest Barrage hits ENEMIES only -- the boss no longer mows down its own horde")


# ===========================================================================
# CAST -- resolves the first segment and requests a live vine
# ===========================================================================

func test_casting_resolves_the_first_segment_and_requests_a_hazard():
	var move := _forest_barrage()
	var fx = _hazard_effect_of(move)
	var caster := Stub.new(0, { "attack": 24 })
	var victim := Stub.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(victim, Vector2i(1, 0))  # depth 1 of an east-aimed lane

	var aim := Vector2i(3, 0)
	var cells := move.targeting.resolve_cells(Vector2i(0, 0), aim)
	var ctx := MoveContext.new(caster, board, move, aim, cells)

	watch_signals(GameEvents)
	fx.apply(ctx)

	# First segment resolved immediately: raw = power 15 + 0.5*attack 24 = 27.
	assert_eq(victim.hp, 73, "the cast turn itself deals the first segment's damage")

	# ... and a live vine was requested via the loose GameEvents seam.
	assert_signal_emitted(GameEvents, "hazard_spawn_requested", "a vine is handed to the manager")
	var params: Array = get_signal_parameters(GameEvents, "hazard_spawn_requested")
	var hazard = params[0]
	assert_true(hazard is TravelingHazard, "the payload is the traveling vine")
	assert_false(hazard.is_expired(), "with 4 of 6 rows still to crawl after the cast segment")
	assert_eq(hazard.remaining, 4)


# ===========================================================================
# AI -- the BossController firing heuristic
# ===========================================================================

func test_boss_fires_the_lane_at_an_aligned_hostile():
	var move := _forest_barrage()
	var boss := Stub.new(0, { "attack": 24, "health": 400 }, true)
	var enemy := Stub.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(boss, Vector2i(0, 0))
	board.place(enemy, Vector2i(0, 3))  # same column -> a cardinal lane sweeps it

	var boss_ai := BossController.new()
	var decision := boss_ai.plan(boss, [move], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it acts rather than holding")
	assert_eq(decision["move"], move, "it chose the lane hazard")
	assert_eq(decision["reason"], "hazard_lane", "via the lane pre-emption, not the generic planner")
	assert_eq(decision["aim_cell"], Vector2i(0, 3), "aimed at the aligned hostile")


func test_boss_does_not_fire_the_lane_when_no_hostile_is_aligned():
	var move := _forest_barrage()
	var boss := Stub.new(0, { "attack": 24, "health": 400 }, true)
	var enemy := Stub.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(boss, Vector2i(0, 0))
	board.place(enemy, Vector2i(2, 3))  # neither same row nor same column

	var boss_ai := BossController.new()
	var decision := boss_ai.plan(boss, [move], board, [])

	# It must fall straight through to super.plan() -- never the lane pre-emption.
	assert_ne(decision.get("reason", ""), "hazard_lane",
		"an unaligned hostile does not trigger the lane")
	assert_ne(decision.get("move", null), move,
		"and the hazard move is not selected off-axis")
