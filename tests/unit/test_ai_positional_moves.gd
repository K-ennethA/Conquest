extends GutTest

## Tests for the AI's use of POSITIONAL (leap / landing-cell) moves in
## [method BotController.plan]. A leap move's targeting sets requires_empty_cell +
## requires_adjacent_enemy, so its AIM is an empty LANDING cell BESIDE the target,
## not the target's own occupied cell. Before this feature the AI only ever aimed at
## a target's own cell, so such a move could never pass validation and was dead weight
## in the AI's hands.
##
## Coverage:
##  - An actor whose only move is a Spore-Leap-style leap CHOOSES it and aims at an
##    EMPTY cell orthogonally adjacent to a hostile that is out of melee but in range
##    (never the hostile's own cell), casting from its current cell (no walk-first).
##  - When the hostile is boxed in on all four sides, the AI does NOT pick the leap --
##    it falls through to advance/wait with no crash.
##  - REGRESSION: an ordinary melee move still aims at the target's OWN cell exactly
##    as before (positional handling is a strict superset).
##  - A leashed actor will not select a landing cell beyond its leash radius of home,
##    even when that landing is otherwise within leap range.
##
## Uses the lightweight duck-typed StubUnit / MockBoard harness from
## tests/unit/test_ai_behavior.gd. `reachable` is passed directly, so no
## MovementResolver / live board is needed.

# --- Mocks (mirrors test_ai_behavior.gd) -----------------------------------

class StubUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var stance: String = "aggressive"
	var home: Vector2i = Vector2i(-1, -1)
	var aggro: int = 0
	var leash: int = -1

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(name: String) -> int:
		return int(stats.get(name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func get_hp() -> int:
		return hp

	func is_aggressive() -> bool:
		return stance == "aggressive"

	func is_defensive() -> bool:
		return stance == "defensive"

	func get_home_cell() -> Vector2i:
		return home

	func has_home_cell() -> bool:
		return home.x >= 0 and home.y >= 0

	func get_aggro_range() -> int:
		return aggro

	func get_leash_radius() -> int:
		return leash

	func has_leash() -> bool:
		return leash >= 0


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

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out


# --- Fixtures ---------------------------------------------------------------

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## A Spore-Leap-style positional move: it must land on an EMPTY cell orthogonally
## adjacent to an enemy (requires_empty_cell + requires_adjacent_enemy), range 1-4,
## and deals scaled physical damage. Built in code so the test needs no .tres load.
func _leap_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_leap"
	m.display_name = "Test Leap"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 4
	p.area_shape = CombatTypes.AreaShape.SINGLE
	p.area_size = 0
	p.requires_empty_cell = true
	p.requires_adjacent_enemy = true
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 7
	d.scaling_stat = "attack"
	d.scale = 0.6
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


# --- Positional: chooses the leap and aims at a landing cell -----------------

func test_ai_uses_leap_and_aims_at_empty_landing_beside_hostile() -> void:
	# Hostile is out of melee (distance 4) but within the leap's range 4. The only
	# empty, in-range landing cell orthogonally beside it is (3,0). The AI must pick
	# the leap and aim THERE -- never at the hostile's own occupied cell (4,0).
	var actor := StubUnit.new(0, { "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(4, 0))

	# reachable is irrelevant to a leap (it is cast from the current cell), but pass a
	# realistic set to prove the planner does not fold it into the leap.
	var reachable := [Vector2i(1, 0), Vector2i(2, 0)]
	var bot := BotController.new()
	var decision := bot.plan(actor, [_leap_move()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.MOVE, "the AI chooses the leap")
	assert_eq(decision["move"].move_id, &"test_leap", "the chosen move is the leap")
	assert_eq(decision["target"], enemy, "it leaps at the reachable hostile")

	var aim: Vector2i = decision["aim_cell"]
	assert_eq(aim, Vector2i(3, 0), "aims at the only empty in-range cell beside the hostile")
	assert_ne(aim, board.cell_of(enemy), "the aim is NOT the hostile's own occupied cell")
	assert_eq(_manhattan(aim, board.cell_of(enemy)), 1, "the landing cell is orthogonally adjacent to the hostile")

	# The leap is cast from the CURRENT cell: dest_cell == origin means the executor
	# relocates nothing before the leap (no double-move) -- LeapEffect does the move.
	assert_eq(decision["dest_cell"], Vector2i(0, 0), "the actor does not walk before leaping (no double-move)")


# --- Positional: no valid landing -> does not pick the leap ------------------

func test_ai_skips_leap_when_hostile_is_boxed_in() -> void:
	# Every cell orthogonally adjacent to the hostile is occupied, so there is no
	# empty landing cell and the leap cannot be used. The AI must NOT pick it; it
	# falls through to the advance branch with no crash.
	var actor := StubUnit.new(0, { "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(4, 0))
	# Box the hostile in on all four sides (allies, so they are not extra targets).
	board.place(StubUnit.new(0, {}), Vector2i(3, 0))
	board.place(StubUnit.new(0, {}), Vector2i(5, 0))
	board.place(StubUnit.new(0, {}), Vector2i(4, 1))
	board.place(StubUnit.new(0, {}), Vector2i(4, -1))

	var reachable := [Vector2i(1, 0)]
	var bot := BotController.new()
	var decision := bot.plan(actor, [_leap_move()], board, reachable)

	assert_ne(decision["action"], BotController.ActionType.MOVE, "no landing -> the leap is not chosen")
	assert_eq(decision["action"], BotController.ActionType.STEP, "falls through to advancing toward the hostile")


# --- Regression: an ordinary move still aims at the target's own cell --------

func test_ordinary_move_still_aims_at_target_cell() -> void:
	# A non-positional melee move is unchanged: it aims at the target's OWN cell.
	var actor := StubUnit.new(0, { "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))

	var bot := BotController.new()
	var decision := bot.plan(actor, [MoveLibrary.basic_strike()], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "attacks the adjacent enemy")
	assert_eq(decision["aim_cell"], board.cell_of(enemy), "aims at the target's own cell, exactly as before")
	assert_eq(decision["dest_cell"], Vector2i(0, 0), "strikes in place from the origin")


# --- Leash: a landing beyond the tether is rejected -------------------------

func test_leashed_actor_wont_leap_beyond_leash_radius() -> void:
	# The only in-range landing (3,0) sits distance 3 from home -- beyond a leash of 2.
	# A leashed actor must refuse it (and therefore not leap); the SAME actor without a
	# leash takes the leap, proving the tether is what blocked it.
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	var actor := StubUnit.new(0, { "attack": 10 })
	actor.home = Vector2i(0, 0)
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(4, 0))
	var reachable := [Vector2i(1, 0), Vector2i(2, 0)]

	# Leashed to radius 2: (3,0) is out of tether, so the leap is not selected.
	actor.leash = 2
	var bot := BotController.new()
	var leashed := bot.plan(actor, [_leap_move()], board, reachable)
	assert_ne(leashed["action"], BotController.ActionType.MOVE,
		"a leashed actor will not leap onto a landing beyond its leash radius")

	# Untethered (same geometry): the landing is now legal and the leap IS taken.
	actor.leash = -1
	var free := bot.plan(actor, [_leap_move()], board, reachable)
	assert_eq(free["action"], BotController.ActionType.MOVE, "without a leash the same leap is chosen")
	assert_eq(free["aim_cell"], Vector2i(3, 0), "and it aims at the landing the leash had excluded")
