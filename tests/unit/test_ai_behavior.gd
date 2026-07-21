extends GutTest

## Tests for the stance (aggressive/defensive) + leash (anchored) behaviour added to
## the movement-aware planner [method BotController.plan]. Uses lightweight duck-typed
## mocks in the style of tests/unit/test_bot_controller.gd, extended with the AI
## behaviour contract the live [Unit] exposes (is_defensive / get_home_cell /
## get_leash_radius / get_aggro_range …). `reachable` is passed in directly, so no
## MovementResolver / live board is needed.
##
## Coverage:
##  - Aggressive + untethered advances toward a distant hostile (regression guard:
##    the historical behaviour must be byte-for-byte unchanged).
##  - Defensive + aggro 0 with a reachable-but-not-attackable hostile WAITS.
##  - Defensive + aggro N: hostile within N of home -> advances; beyond N -> holds.
##  - Leashed advance destinations never leave the leash radius of home.
##  - A defensive turret still ATTACKS anything reachable from a leashed stand cell.
##  - The same leash/stance flows through [BossController] (it calls super.plan).

# --- Mocks -----------------------------------------------------------------

class StubUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	# AI behaviour contract (mirrors the live Unit getters plan() reads).
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

	# --- AI behaviour API (subset Bot/BossController read) ---
	func get_ai_stance() -> String:
		return stance

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


# --- Small helpers ----------------------------------------------------------

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _cells(list: Array) -> Array:
	# Identity pass-through -- documents intent at call sites (an Array[Vector2i]).
	return list


# --- Aggressive + untethered: regression guard ------------------------------

func test_aggressive_untethered_advances_toward_distant_hostile() -> void:
	# Classic behaviour: no stance overrides, no leash. The unit closes its full
	# move range toward a far enemy exactly as before this feature existed.
	var actor := StubUnit.new(0, { "attack": 10 })  # aggressive, no home, leash -1
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(5, 0))

	var reachable := _cells([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	var bot := BotController.new()
	var decision := bot.plan(actor, [MoveLibrary.basic_strike()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.STEP, "advances when nothing in range")
	assert_eq(decision["dest_cell"], Vector2i(3, 0), "closes its whole move range toward the enemy")


# --- Defensive + aggro 0: turret never chases -------------------------------

func test_defensive_aggro_zero_waits_on_unattackable_hostile() -> void:
	# A hostile is reachable-adjacent-ish but cannot be struck from any reachable
	# cell, and it is nowhere near home. A pure turret (aggro 0) must HOLD, never
	# advance.
	var actor := StubUnit.new(0, { "attack": 10 })
	actor.stance = "defensive"
	actor.home = Vector2i(0, 0)
	actor.aggro = 0
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(5, 0))  # dist 5 from home; strike range is 1

	var reachable := _cells([Vector2i(1, 0), Vector2i(2, 0)])  # nearest is dist 3 from enemy
	var bot := BotController.new()
	var decision := bot.plan(actor, [MoveLibrary.basic_strike()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.WAIT, "turret holds instead of chasing")
	assert_eq(decision["reason"], "holding", "the wait reason names the defensive hold")


# --- Defensive + aggro N: wakes inside N, holds beyond -----------------------

func test_defensive_aggro_range_wakes_within_and_holds_beyond() -> void:
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	var actor := StubUnit.new(0, { "attack": 10 })
	actor.stance = "defensive"
	actor.home = Vector2i(0, 0)
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(5, 0))  # dist 5 from home; not attackable from reachable
	var reachable := _cells([Vector2i(1, 0), Vector2i(2, 0)])
	var strike := [MoveLibrary.basic_strike()]

	# Within aggro (5 <= 6): the unit wakes and advances.
	actor.aggro = 6
	var bot := BotController.new()
	var woke := bot.plan(actor, strike, board, reachable)
	assert_eq(woke["action"], BotController.ActionType.STEP, "hostile inside aggro range wakes the unit")
	assert_eq(woke["dest_cell"], Vector2i(2, 0), "it advances toward the hostile once woken")

	# Beyond aggro (5 > 4): the unit holds.
	actor.aggro = 4
	var held := bot.plan(actor, strike, board, reachable)
	assert_eq(held["action"], BotController.ActionType.WAIT, "hostile beyond aggro range -> hold")
	assert_eq(held["reason"], "holding", "held for the defensive reason")


# --- Leash: advance destinations never leave the tether ---------------------

func test_leashed_advance_never_leaves_leash_radius() -> void:
	# Aggressive but anchored: a far hostile would pull an untethered unit all the
	# way out, but the leash caps every stop at radius 2 from home.
	var actor := StubUnit.new(0, { "attack": 10 })
	actor.home = Vector2i(0, 0)
	actor.leash = 2  # aggressive stance, tethered to 2 cells from home
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(9, 0))

	# Movement range 4 could reach (4,0), but only (1,0)/(2,0) are inside the leash.
	var reachable := _cells([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	var bot := BotController.new()
	var decision := bot.plan(actor, [MoveLibrary.basic_strike()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.STEP, "still advances, just not past the tether")
	var dest: Vector2i = decision["dest_cell"]
	assert_true(_manhattan(dest, actor.home) <= 2,
		"the chosen destination (%s) stays within the leash radius of home" % dest)
	assert_eq(dest, Vector2i(2, 0), "picks the leashed cell closest to the enemy, not a farther reachable one")


# --- Defensive turret still ATTACKS from a leashed stand cell ----------------

func test_defensive_turret_attacks_reachable_hostile() -> void:
	# aggro 0 means this unit never CHASES, but the attack branch runs for every
	# stance: a hostile it can strike from a leashed stand cell is hit, not ignored.
	var actor := StubUnit.new(0, { "attack": 10 })
	actor.stance = "defensive"
	actor.home = Vector2i(0, 0)
	actor.aggro = 0
	actor.leash = 1
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))  # adjacent -> strike range 1 from origin

	var reachable := _cells([Vector2i(0, 1)])
	var bot := BotController.new()
	var decision := bot.plan(actor, [MoveLibrary.basic_strike()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.MOVE, "a reachable target is struck, not held")
	assert_eq(decision["target"], enemy, "the turret attacks the adjacent hostile")


# --- BossController inherits the same stance/leash via super.plan ------------

func test_boss_inherits_leash_filter() -> void:
	# BossController.plan just wraps super.plan (phase + expanded moveset), so the
	# leash filter must apply to it unchanged. A leashed boss advancing on a far
	# hostile must still stop inside its tether.
	var boss := StubUnit.new(0, { "attack": 10, "health": 400 })
	boss.home = Vector2i(0, 0)
	boss.leash = 2
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(boss, Vector2i(0, 0))
	board.place(enemy, Vector2i(9, 0))

	var reachable := _cells([Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)])
	var boss_ai := BossController.new()
	var decision := boss_ai.plan(boss, [MoveLibrary.basic_strike()], board, reachable)

	assert_eq(decision["action"], BotController.ActionType.STEP, "boss advances")
	var dest: Vector2i = decision["dest_cell"]
	assert_true(_manhattan(dest, boss.home) <= 2,
		"the boss's destination (%s) never leaves its leash radius" % dest)


# --- Spawn-kind default AI stance (MapLoader.resolve_default_ai_stance) -------
# Precedence: an explicit authored stance always wins; otherwise the default is
# chosen by spawn kind -- Start defenders HOLD, waves (Respawn/Endless/Reinforcement)
# CHARGE. Routes through both the initial load and every SpawnManager wave.

func test_start_spawn_defaults_to_defensive() -> void:
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_START, ""),
		"defensive",
		"a pre-placed Start enemy with no authored stance holds (defends)")


func test_wave_kinds_default_to_aggressive() -> void:
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_ENDLESS, ""),
		"aggressive",
		"Endless waves charge on arrival")
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_RESPAWN, ""),
		"aggressive",
		"Respawn replacements charge on arrival")
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_REINFORCEMENT, ""),
		"aggressive",
		"Reinforcements charge on arrival")


func test_explicit_authored_stance_overrides_the_kind_default() -> void:
	# Author override wins for Start and Reinforcement.
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_START, "aggressive"),
		"aggressive",
		"an explicit aggressive on a Start point beats the defensive default")
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_REINFORCEMENT, "defensive"),
		"defensive",
		"an explicit defensive on a Reinforcement point beats the aggressive default")


func test_endless_and_respawn_force_aggressive_over_any_authored_stance() -> void:
	# Endless/Respawn reuse one home cell, so their units must ALWAYS charge to clear
	# it -- an authored defensive is ignored, unlike every other kind.
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_ENDLESS, "defensive"),
		"aggressive",
		"an Endless point forces aggressive so it never chokes its own spawn cell")
	assert_eq(
		MapLoader.resolve_default_ai_stance(MapResource.SPAWN_KIND_RESPAWN, "defensive"),
		"aggressive",
		"a Respawn point forces aggressive for the same reason")
