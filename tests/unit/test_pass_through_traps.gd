extends GutTest

# THE ONE-RULE WORLD: a glowing tile hurts where you STAND; a trap springs where you STEP.
# (CONQUEST.md rule 10.)
#
# Everything a tile does was landing-only until traps arrived: ON_ENTER fired for the cell a
# unit stopped on and walking across was free. This suite pins the authored exception and,
# just as importantly, pins that it stayed an exception -- a tile effect nobody ticked
# springs_on_pass on must still be free to walk over.
#
# The pieces, and why each is tested where it is:
#   * MovementResolver.path_cells -- the route a move traverses, which did not exist before
#     (a MOVE_UNIT command carries a destination, not a path). Determinism is the whole
#     point: lockstep peers and replays re-derive it independently and must agree.
#   * TileEffectSystem.preview_route -- the pure derivation the ghost, the AI and the live
#     walk all read, so the preview cannot drift from the resolution.
#   * TileEffectSystem.apply_move -- the whole terrain side of one applied move, which is
#     what GameWorldManager's unit_moved hook hands every mover in the game (the FE commit,
#     the AI relocate, and CommandApplier -- so networked peers and replays too).
#
# Consumption is asserted against the REAL CombatServices applied-effect registry rather
# than the system's injected dictionary, because extinguishing a spent trap goes through
# that registry -- an injected dict would report "still there" for a trap that really had
# been removed. It is global state, so it is cleared in BOTH hooks (tests/README rule 3).

const Guard := preload("res://tests/helpers/global_state_guard.gd")

const ORIGIN := Vector2i(0, 0)
const DEST := Vector2i(4, 0)

## Untyped on purpose (tests/README rule 3).
var _guard


# --- Doubles -----------------------------------------------------------------

## A duck-typed walker: the shape a tile effect resolves against, PLUS the two hooks the
## trap walk needs that no shared double carries -- a movement profile (so a route can be
## derived for it at all) and an owning player (so an owner-stamped trap can decide whether
## it is hostile). Deliberately local: "a unit that can be pathed" is a new shape, and
## adding either hook to a shared double would silently reroute every suite using it
## (tests/README rule 5).
class Walker:
	var team: int
	var stats: Dictionary
	var hp: int
	var statuses: Array = []
	var profile: MovementProfile = null

	## [param p_range] is written to BOTH the movement STAT and the profile's fallback
	## range, deliberately. The stat is what MovementResolver actually budgets by; the
	## matching profile range means these fixtures still read the same whether a case
	## passes the walker or only its profile.
	func _init(p_team: int, p_range: int) -> void:
		team = p_team
		stats = { "health": 100, "defense": 0, "magic_defense": 0, "movement": p_range }
		hp = 100
		profile = MovementProfile.create(
			&"walker", "Walker", CombatTypes.MovementKind.GROUND, p_range,
			MovementProfile.Shape.ORTHOGONAL)

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func heal(n: int) -> void:
		hp += n

	func add_status(condition) -> void:
		statuses.append(condition)

	func get_movement_profile() -> MovementProfile:
		return profile

	## Stand-in owner: the team int doubles as the "player" an owner-aware trap compares.
	func get_owner_player() -> int:
		return team


## A board whose tile effects are the LIVE CombatServices registry, so a consumed trap
## really disappears from it. Otherwise the minimum a route needs: placement, factions,
## relocation, and a wall set so a test can force a detour.
class TrapBoard:
	var placements: Array = []
	var walls: Dictionary = {}

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

	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell

	func is_blocked(cell: Vector2i) -> bool:
		return walls.has(cell)

	func tile_effects_at(cell: Vector2i) -> Array:
		return CombatServices.tile_effects_at(cell)


# --- Fixtures ----------------------------------------------------------------

func before_each() -> void:
	_guard = Guard.new()
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	_guard.restore()


## The authored Vine Trap, stamped as PLACED BY player 0 (so it springs on player 1) and
## laid on [param cell]. Duplicated first -- these resources are loaded once and handed to
## every cell (CONQUEST.md rule 7).
func _lay_vine_trap(cell: Vector2i) -> TileEffectResource:
	var trap: TileEffectResource = (load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource).duplicate()
	trap.owner_player = 0
	CombatServices.add_tile_effect(cell, trap)
	return trap


## A trap that SPRINGS ON PASS but does NOT halt: the second half of the design space, so
## the two flags are proven independent rather than one flag wearing two hats.
func _lay_alarm(cell: Vector2i, power: int = 7) -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"spore_alarm"
	te.display_name = "Spore Alarm"
	te.trigger = TileEffectResource.Trigger.ON_ENTER
	te.affected_factions = TileEffectResource.AffectedFactions.OCCUPANT_ENEMIES
	te.springs_on_pass = true
	te.halts_movement = false
	te.consume_on_trigger = true
	te.owner_player = 0
	var dmg := DamageEffect.new()
	dmg.power = power
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.MAGICAL
	te.effects = [dmg] as Array[MoveEffect]
	CombatServices.add_tile_effect(cell, te)
	return te


## An ordinary ON_ENTER effect that is NOT a trap -- the control case for every "pass-through
## is still free" assertion.
func _lay_plain_hazard(cell: Vector2i, power: int = 9) -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"scorch_patch"
	te.display_name = "Scorch Patch"
	te.trigger = TileEffectResource.Trigger.ON_ENTER
	te.affected_factions = TileEffectResource.AffectedFactions.OCCUPANT_ENEMIES
	te.owner_player = 0
	var dmg := DamageEffect.new()
	dmg.power = power
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.MAGICAL
	te.effects = [dmg] as Array[MoveEffect]
	CombatServices.add_tile_effect(cell, te)
	return te


## A walker (team 1, movement [param reach]) standing on ORIGIN of a fresh board.
func _corridor(reach: int = 4) -> Dictionary:
	var unit := Walker.new(1, reach)
	var board := TrapBoard.new()
	board.place(unit, ORIGIN)
	return { "unit": unit, "board": board, "system": autofree(TileEffectSystem.new()) }


# --- The route derivation ----------------------------------------------------

func test_the_derived_path_is_every_cell_the_move_steps_on() -> void:
	var fx: Dictionary = _corridor()
	var path: Array[Vector2i] = MovementResolver.new().path_cells(
		ORIGIN, DEST, fx["unit"].profile, fx["board"], fx["unit"])
	assert_eq(path.size(), 4, "a four-cell walk crosses four cells")
	assert_eq(path[0], Vector2i(1, 0), "the origin is excluded -- the unit already stands there")
	assert_eq(path[path.size() - 1], DEST, "and the destination is the last cell walked onto")


func test_the_same_board_always_derives_the_same_path() -> void:
	# Lockstep peers and replays re-derive the route independently from the destination in
	# the command, so two derivations over the same board MUST agree cell for cell.
	var fx: Dictionary = _corridor()
	var resolver := MovementResolver.new()
	var first: Array[Vector2i] = resolver.path_cells(ORIGIN, DEST, fx["unit"].profile, fx["board"], fx["unit"])
	var second: Array[Vector2i] = MovementResolver.new().path_cells(
		ORIGIN, DEST, fx["unit"].profile, fx["board"], fx["unit"])
	assert_eq(first, second, "the derived route is a function of the board, not of run order")


func test_an_unreachable_destination_derives_no_path() -> void:
	var fx: Dictionary = _corridor(2)
	var path: Array[Vector2i] = MovementResolver.new().path_cells(
		ORIGIN, DEST, fx["unit"].profile, fx["board"], fx["unit"])
	assert_true(path.is_empty(), "a destination outside the movement budget yields no route")


# --- The authored flags ------------------------------------------------------

func test_the_vine_trap_is_authored_as_a_halting_pass_trap() -> void:
	var trap := load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource
	assert_true(trap.springs_on_pass, "the Vine Trap springs on a unit merely crossing it")
	assert_true(trap.halts_movement, "and stops that unit's move dead on the trap cell")
	assert_true(trap.consume_on_trigger, "and is spent the moment it springs")


func test_every_other_shipped_tile_effect_is_still_landing_only() -> void:
	# TRAP-NESS IS AUTHORED, NEVER INFERRED. If a new effect ever needs it, the flag is
	# ticked deliberately and this list is updated deliberately with it.
	var dir := DirAccess.open("res://game/tiles/effects/resources")
	assert_not_null(dir, "the shipped tile-effect resources are on disk")
	var pass_traps: Array[String] = []
	for file_name in dir.get_files():
		if not file_name.ends_with(".tres"):
			continue
		var te = load("res://game/tiles/effects/resources/%s" % file_name)
		if te is TileEffectResource and te.springs_on_pass:
			pass_traps.append(file_name)
	assert_eq(pass_traps, ["vine_trap.tres"] as Array[String],
		"the Vine Trap is the only shipped effect that springs on pass")


func test_a_trap_describes_itself_and_an_ordinary_effect_does_not() -> void:
	var trap := load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource
	assert_eq(trap.trap_descriptor(), TileEffectResource.TRAP_DESCRIPTOR,
		"a trap carries the line every surface quotes")
	var rubble := load("res://game/tiles/effects/resources/rock_rubble.tres") as TileEffectResource
	assert_eq(rubble.trap_descriptor(), "",
		"an ordinary ON_ENTER effect has no trap line, so no panel prints one")


func test_springs_on_pass_only_counts_on_an_on_enter_effect() -> void:
	var te := TileEffectResource.new()
	te.springs_on_pass = true
	te.trigger = TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING
	assert_false(te.is_pass_trap(),
		"pass-through is about stepping onto a cell, which an occupancy tick is not")


# --- Walking over a trap -----------------------------------------------------

func test_a_pass_trap_springs_and_halts_the_move_on_its_own_cell() -> void:
	var fx: Dictionary = _corridor()
	_lay_vine_trap(Vector2i(2, 0))

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(landed, Vector2i(2, 0), "the move ends ON the trap, not at the cell it aimed for")
	assert_eq(fx["board"].cell_of(fx["unit"]), Vector2i(2, 0),
		"and the unit is really standing there -- the board was corrected, not just the answer")
	assert_eq(100 - fx["unit"].hp, 18, "the trap's damage lands in full (environmental damage never rolls)")
	assert_eq(fx["unit"].statuses.size(), 1, "and it applies exactly one status")
	assert_eq(fx["unit"].statuses[0].id, &"ensnared", "namely the hold")
	assert_true(CombatServices.tile_effects_at(Vector2i(2, 0)).is_empty(),
		"a single-use trap is spent the instant it springs")


func test_only_the_first_trap_on_a_route_ever_springs() -> void:
	var fx: Dictionary = _corridor()
	_lay_vine_trap(Vector2i(1, 0))
	_lay_vine_trap(Vector2i(3, 0))

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(landed, Vector2i(1, 0), "the walk stops at the FIRST trap it steps on")
	assert_eq(100 - fx["unit"].hp, 18, "so exactly one trap's worth of damage lands")
	assert_eq(CombatServices.tile_effects_at(Vector2i(3, 0)).size(), 1,
		"the second trap is untouched -- the unit never reached it")


func test_a_trap_that_does_not_halt_fires_and_the_move_carries_on() -> void:
	var fx: Dictionary = _corridor()
	_lay_alarm(Vector2i(2, 0))

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(landed, DEST, "springs_on_pass without halts_movement does not stop the move")
	assert_eq(100 - fx["unit"].hp, 7, "but the trap still fired as the unit crossed it")
	assert_true(CombatServices.tile_effects_at(Vector2i(2, 0)).is_empty(),
		"and was spent doing so")


func test_walking_over_an_ordinary_hazard_is_still_free() -> void:
	# The regression this whole design exists to avoid: making every ON_ENTER effect fire
	# on pass-through would turn every hazard on the map into a trap.
	var fx: Dictionary = _corridor()
	_lay_plain_hazard(Vector2i(2, 0))

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(landed, DEST, "a tile nobody authored as a trap never truncates a move")
	assert_eq(fx["unit"].hp, 100, "and hurts nobody who merely walks across it")
	assert_eq(CombatServices.tile_effects_at(Vector2i(2, 0)).size(), 1, "so it is not spent either")


func test_landing_directly_on_a_trap_still_works() -> void:
	var fx: Dictionary = _corridor()
	_lay_vine_trap(DEST)

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(landed, DEST, "a trap on the destination is a landing, not a truncation")
	assert_eq(100 - fx["unit"].hp, 18, "and springs exactly once")
	assert_true(CombatServices.tile_effects_at(DEST).is_empty(), "consuming itself as it always did")


func test_a_route_that_avoids_the_trap_costs_nothing() -> void:
	var fx: Dictionary = _corridor()
	_lay_vine_trap(Vector2i(2, 0))

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, Vector2i(0, 3), fx["board"])

	assert_eq(landed, Vector2i(0, 3), "a route down the other column never meets the trap")
	assert_eq(fx["unit"].hp, 100, "so nothing springs")
	assert_eq(CombatServices.tile_effects_at(Vector2i(2, 0)).size(), 1, "and the trap is still armed")


func test_a_trap_spares_the_side_that_laid_it_even_on_pass() -> void:
	var unit := Walker.new(0, 4)  # same "player" as the trap's owner
	var board := TrapBoard.new()
	board.place(unit, ORIGIN)
	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	_lay_vine_trap(Vector2i(2, 0))

	var landed: Vector2i = system.apply_move(unit, ORIGIN, DEST, board)

	assert_eq(landed, DEST, "the placer's own side walks over its own trap")
	assert_eq(unit.hp, 100, "taking nothing")
	assert_eq(CombatServices.tile_effects_at(Vector2i(2, 0)).size(), 1, "and leaving it armed for the enemy")


# --- Determinism -------------------------------------------------------------

func test_the_same_move_over_the_same_board_truncates_identically_twice() -> void:
	# Two peers applying the same MOVE_UNIT (which carries only the destination) to the
	# same board must independently reach the same landing cell and the same damage. Run
	# the identical scenario twice from a cleared registry, which is exactly that.
	var results: Array = []
	for _run in range(2):
		CombatServices.clear()
		var fx: Dictionary = _corridor()
		_lay_vine_trap(Vector2i(2, 0))
		var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])
		results.append({ "cell": landed, "hp": int(fx["unit"].hp) })
	assert_eq(results[0], results[1],
		"truncation is deterministic resolution -- no RNG, no clock, no scene order")


# --- The preview reads the same derivation -----------------------------------

func test_the_preview_reports_the_stop_cell_the_move_will_actually_use() -> void:
	var fx: Dictionary = _corridor()
	var trap := _lay_vine_trap(Vector2i(2, 0))

	var route: Dictionary = TileEffectSystem.preview_route(fx["unit"], ORIGIN, DEST, fx["board"])

	assert_eq(route["stop"], Vector2i(2, 0), "the preview stops the ghost on the trap")
	assert_eq(route["trap"], trap, "and names the trap it would spring")
	assert_eq(fx["unit"].hp, 100, "a preview applies nothing")
	assert_eq(CombatServices.tile_effects_at(Vector2i(2, 0)).size(), 1, "and consumes nothing")

	var landed: Vector2i = fx["system"].apply_move(fx["unit"], ORIGIN, DEST, fx["board"])
	assert_eq(landed, route["stop"], "what the preview promised is what the move resolved")


func test_a_clear_route_previews_no_trap_at_all() -> void:
	var fx: Dictionary = _corridor()
	var route: Dictionary = TileEffectSystem.preview_route(fx["unit"], ORIGIN, DEST, fx["board"])
	assert_eq(route["stop"], DEST, "an untrapped route ends where it was aimed")
	assert_null(route["trap"], "so there is nothing to warn about")


func test_a_non_halting_trap_is_still_worth_warning_about() -> void:
	var fx: Dictionary = _corridor()
	var alarm := _lay_alarm(Vector2i(2, 0))
	var route: Dictionary = TileEffectSystem.preview_route(fx["unit"], ORIGIN, DEST, fx["board"])
	assert_eq(route["stop"], DEST, "it does not truncate the move")
	assert_eq(route["trap"], alarm, "but the player is still told it will go off")


# --- AI avoidance ------------------------------------------------------------

## A driver that is in the tree (so it can read the GameSettings autoload) but inert --
## PROCESS_MODE_DISABLED keeps its beat Timer from acting on anything behind the test.
func _driver() -> BotTurnDriver:
	var driver := BotTurnDriver.new()
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	add_child_autofree(driver)
	return driver


func _reach_with_difficulty(difficulty: int) -> Array:
	_guard.set_setting("ai_difficulty", difficulty)
	var fx: Dictionary = _corridor()
	_lay_vine_trap(Vector2i(2, 0))
	var resolver := MovementResolver.new()
	var cells: Array[Vector2i] = resolver.reachable_cells(
		ORIGIN, fx["unit"].profile, fx["board"], fx["unit"])
	return _driver()._avoid_traps(
		fx["unit"], ORIGIN, fx["unit"].profile, fx["board"], resolver, cells)


func test_hard_ai_refuses_to_plan_a_route_through_an_armed_trap() -> void:
	var cells: Array = _reach_with_difficulty(BotController.Difficulty.HARD)
	assert_false(cells.has(Vector2i(2, 0)), "Hard will not step on a trap it can see")
	assert_false(cells.has(DEST), "nor take a route that has to cross one")
	assert_true(cells.has(Vector2i(0, 3)), "but every cell reachable without crossing it is still on the table")


func test_easy_and_normal_ai_blunder_straight_into_the_trap() -> void:
	for difficulty in [BotController.Difficulty.EASY, BotController.Difficulty.NORMAL]:
		var cells: Array = _reach_with_difficulty(int(difficulty))
		assert_true(cells.has(Vector2i(2, 0)),
			"%s reads the board no better than the tile looks" % BotController.difficulty_name(int(difficulty)))
		CombatServices.clear()


func test_a_boxed_in_hard_unit_walks_the_trap_rather_than_freezing() -> void:
	# Avoidance is a preference, not a cage: with the trap the ONLY way out, refusing it
	# would leave the unit standing still, which is a worse tell than springing the snare.
	_guard.set_setting("ai_difficulty", BotController.Difficulty.HARD)
	var fx: Dictionary = _corridor()
	var board: TrapBoard = fx["board"]
	# A one-cell doorway at (1,0); everything else around the origin is wall.
	board.walls[Vector2i(0, 1)] = true
	board.walls[Vector2i(0, -1)] = true
	board.walls[Vector2i(-1, 0)] = true
	board.walls[Vector2i(1, 1)] = true
	board.walls[Vector2i(1, -1)] = true
	_lay_vine_trap(Vector2i(1, 0))

	var resolver := MovementResolver.new()
	var cells: Array[Vector2i] = resolver.reachable_cells(ORIGIN, fx["unit"].profile, board, fx["unit"])
	var kept: Array = _driver()._avoid_traps(fx["unit"], ORIGIN, fx["unit"].profile, board, resolver, cells)

	assert_eq(kept, cells, "with no alternative route the full reachable set is kept")


func test_hard_ai_ignores_a_trap_laid_by_its_own_side() -> void:
	_guard.set_setting("ai_difficulty", BotController.Difficulty.HARD)
	var unit := Walker.new(0, 4)  # same "player" as the trap's owner -- it cannot spring it
	var board := TrapBoard.new()
	board.place(unit, ORIGIN)
	_lay_vine_trap(Vector2i(2, 0))

	var resolver := MovementResolver.new()
	var cells: Array[Vector2i] = resolver.reachable_cells(ORIGIN, unit.profile, board, unit)
	var kept: Array = _driver()._avoid_traps(unit, ORIGIN, unit.profile, board, resolver, cells)

	assert_eq(kept, cells, "a trap that cannot spring on this unit is not an obstacle to it")


# --- Exclusion support on the resolver ---------------------------------------

func test_an_excluded_cell_can_be_neither_crossed_nor_stopped_on() -> void:
	var fx: Dictionary = _corridor()
	var board: TrapBoard = fx["board"]
	board.walls[Vector2i(1, 1)] = true
	board.walls[Vector2i(1, -1)] = true
	var cells: Array[Vector2i] = MovementResolver.new().reachable_cells(
		ORIGIN, fx["unit"].profile, board, fx["unit"], { Vector2i(1, 0): true })
	assert_false(cells.has(Vector2i(1, 0)), "the excluded cell is not reachable")
	assert_false(cells.has(Vector2i(2, 0)), "and nothing behind it is either -- exclusion blocks the path")
	assert_true(cells.has(Vector2i(0, 1)), "cells reachable another way are unaffected")


func test_an_empty_exclusion_set_changes_nothing() -> void:
	var fx: Dictionary = _corridor()
	var resolver := MovementResolver.new()
	var plain: Array[Vector2i] = resolver.reachable_cells(ORIGIN, fx["unit"].profile, fx["board"], fx["unit"])
	var empty: Array[Vector2i] = resolver.reachable_cells(
		ORIGIN, fx["unit"].profile, fx["board"], fx["unit"], {})
	assert_eq(plain, empty, "the default exclusion set is the identity")
