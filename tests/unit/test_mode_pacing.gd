extends GutTest

## PER-MODE PACING TUNING -- [ModeTuning], the one surface the engine reads a mode's numbers
## through, and the two knobs Siege turns on with it (CONQUEST.md rule 11).
##
## The shape being pinned here is deliberately not "Siege makes units faster". It is:
##
##   * the ENGINE names a knob and supplies its own NEUTRAL value;
##   * the active MODE's ruleset resource may declare that knob, and only then does the
##     engine see a different number;
##   * a battle with NO mode armed consults no ruleset at all, so every path behaves exactly
##     as it did before the knob existed.
##
## Everything runs headless: real [Unit]s (they carry the real [StatusController] the grant
## goes through, and the real `get_stat` / `get_base_stat` pair every reader uses), a fake
## board and a fake spawner in place of the live ones -- the harness `test_siege_waves.gd`
## established.
##
## [ModeTuning]'s registration is a STATIC, so it is global state and is cleared in
## `after_each` (tests/README rule 3) -- a suite that left Siege registered would silently
## make every later suite in the run think a mode was armed.

# --- Doubles -----------------------------------------------------------------

class FakeBoard extends RefCounted:
	var cells: Dictionary = {}

	func place(unit, cell: Vector2i) -> void:
		cells[unit] = cell

	func cell_of(unit) -> Vector2i:
		return cells.get(unit, Vector2i(-999, -999))

	func all_units() -> Array:
		return cells.keys()


## Spawns REAL units, so a respawned / newly waved unit has the status controller the grant
## goes through and the real stat pair the assertions read.
##
## It does NOT build them itself: a RefCounted double cannot reach `add_child_autofree`, and a
## Node it constructed would leak (tests/README rule 2 -- the exact trap that caused most of
## this suite's historical orphans). It calls back into the test's own factory instead.
class FakeSpawner extends RefCounted:
	var board: FakeBoard = null
	var builder: Callable = Callable()
	var units: Array = []
	var calls: Array = []

	func _init(p_board: FakeBoard, p_builder: Callable) -> void:
		board = p_board
		builder = p_builder

	func spawn_and_adopt(spawn_data, player_id, hint = 0):
		var cell: Vector2i = spawn_data.get("position", Vector2i(-1, -1))
		calls.append({ "cell": cell, "player_id": player_id, "hint": hint })
		if not builder.is_valid():
			return null
		var u = builder.call(int(player_id))
		if u == null:
			return null
		units.append(u)
		if board != null:
			board.place(u, cell)
		return u


class FakeMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}


# --- Fixture -----------------------------------------------------------------

const LANE: Array = [Vector2i(1, 1), Vector2i(5, 1), Vector2i(9, 1)]
const P0_BASE := Vector2i(0, 0)
const P1_BASE := Vector2i(10, 10)

const BASE_MOVEMENT := 3


func after_each() -> void:
	# The registration is a static on ModeTuning: leaking it would make every later suite in
	# the run resolve knobs off a dead Siege ruleset.
	ModeTuning.clear()


func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = BASE_MOVEMENT
	return c


## A live unit owned by [param player_id], on the tree so its StatusController exists.
func _unit(player_id: int) -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	var p := Player.new()
	p.player_id = player_id
	u.owner_player = p
	add_child_autofree(u)
	return u


func _map() -> FakeMap:
	var m := FakeMap.new()
	m.lanes = [LANE.duplicate()]
	m.base_cells = {0: P0_BASE, 1: P1_BASE}
	return m


func _ruleset() -> SiegeRuleset:
	var rs := SiegeRuleset.new()
	rs.wave_every_rounds = 3
	rs.creeps_per_lane = 1
	rs.creep_character_ids = PackedStringArray(["tree_grunt"])
	rs.respawn_base_delay = 1
	rs.respawn_rounds_per_step = 6
	rs.respawn_max_delay = 3
	return rs


func _controller(map: FakeMap, rs: SiegeRuleset, spawner, board) -> SiegeController:
	var c := SiegeController.new()
	c.name = "ModePacingTestController"
	add_child_autofree(c)
	c.set_ruleset(rs)
	c.set_armed(true)
	c.configure_from_map(map)
	c.set_board_override(board)
	c.set_spawner_override(spawner)
	return c


func _movement(unit: Unit) -> int:
	return int(unit.get_stat("movement"))


# ==============================================================================
# 1. The surface itself
# ==============================================================================

func test_with_no_mode_armed_every_knob_is_the_callers_neutral_value() -> void:
	ModeTuning.clear()
	assert_false(ModeTuning.has_mode(), "no mode is armed")
	assert_null(ModeTuning.active_ruleset(), "so there is no ruleset to read")
	assert_eq(ModeTuning.hero_move_bonus(), 0, "a plain battle grants heroes no extra movement")
	assert_eq(ModeTuning.creep_move_bonus(), 0, "nor creeps")
	assert_eq(ModeTuning.trap_expiry_rounds(), 0,
		"and a placed trap has no clock -- 0 is NEVER, which is the pre-existing behaviour")
	assert_eq(ModeTuning.get_int(&"anything_at_all", 42), 42,
		"an unknown knob is simply the caller's own fallback, never an error")


func test_an_armed_mode_answers_from_its_own_ruleset() -> void:
	var rs := _ruleset()
	rs.hero_move_bonus = 4
	rs.creep_move_bonus = 2
	rs.trap_expiry_rounds = 5
	_controller(_map(), rs, null, null)

	assert_true(ModeTuning.has_mode(), "arming the mode registers its ruleset as the active one")
	assert_eq(ModeTuning.hero_move_bonus(), 4, "the hero knob is read off the ruleset, not code")
	assert_eq(ModeTuning.creep_move_bonus(), 2, "and the creep knob separately")
	assert_eq(ModeTuning.trap_expiry_rounds(), 5, "and the trap lifetime")


func test_a_knob_is_declared_by_the_mode_not_required_of_it() -> void:
	# The generic half of the surface: the engine names a knob, and a ruleset that says nothing
	# about it still answers every knob it DOES declare. This is what lets a future mode adopt
	# one of these without adopting all of them.
	var rs := _ruleset()
	rs.hero_move_bonus = 3
	_controller(_map(), rs, null, null)

	assert_eq(ModeTuning.get_int(&"hero_move_bonus", 0), 3, "a declared knob comes off the resource")
	assert_eq(ModeTuning.get_int(&"knob_no_ruleset_has", 7), 7,
		"an undeclared one falls straight through to the engine's own neutral value")


func test_disarming_the_mode_puts_every_knob_back_to_neutral() -> void:
	var rs := _ruleset()
	rs.hero_move_bonus = 4
	var c := _controller(_map(), rs, null, null)

	assert_eq(ModeTuning.hero_move_bonus(), 4, "armed, the mode's number is live")
	c.set_armed(false)
	assert_false(ModeTuning.has_mode(), "disarming stands the surface down")
	assert_eq(ModeTuning.hero_move_bonus(), 0,
		"so the next battle in the same app run is a plain battle again")


func test_the_round_the_surface_reports_is_the_modes_own_clock() -> void:
	var c := _controller(_map(), _ruleset(), null, null)
	assert_eq(ModeTuning.current_round(), 0, "before the first turn there is no round yet")
	c.observe_round(1)
	assert_eq(ModeTuning.current_round(), 1, "the mode's counter is what the engine reads")
	c.observe_round(2)
	c.observe_round(3)
	assert_eq(ModeTuning.current_round(), 3,
		"the same counter the wave cadence and the respawn queue run on -- one clock, not three")


# ==============================================================================
# 2. Siege's shipped defaults (data, not code)
# ==============================================================================

func test_the_shipped_siege_defaults_are_the_rulesets_exports() -> void:
	var rs := SiegeRuleset.new()
	assert_eq(rs.hero_move_bonus, 2, "Siege grants its squad +2 movement out of the box")
	assert_eq(rs.creep_move_bonus, 1, "and its creeps +1 -- the squad outpaces the tide")
	assert_eq(rs.trap_expiry_rounds, 6, "a trap planted in Siege lives six rounds")


func test_the_move_bonus_tells_the_two_kinds_apart() -> void:
	var rs := SiegeRuleset.new()
	rs.hero_move_bonus = 2
	rs.creep_move_bonus = 1
	assert_eq(rs.move_bonus_for(false), 2, "a squad unit gets the hero knob")
	assert_eq(rs.move_bonus_for(true), 1, "a creep gets the creep knob")


func test_a_degenerate_trap_lifetime_reads_as_never() -> void:
	var rs := SiegeRuleset.new()
	rs.trap_expiry_rounds = -4
	assert_eq(rs.trap_lifetime(), 0,
		"a negative lifetime is 'never', not 'expired the moment it lands'")


# ==============================================================================
# 3. The grant, on the machinery that already exists
# ==============================================================================

func test_the_grant_moves_the_stat_every_reader_already_reads() -> void:
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	var c := _controller(_map(), rs, null, null)
	var hero := _unit(0)

	assert_eq(_movement(hero), BASE_MOVEMENT, "the unit starts at its character's movement")
	assert_true(c.grant_march_bonus(hero), "the mode grants it the march bonus")
	assert_eq(_movement(hero), BASE_MOVEMENT + 2,
		"which shows up on get_stat('movement') -- the stat MovementResolver floods with, the "
		+ "AI estimates reach from and the MOV chip renders")
	assert_eq(int(hero.get_base_stat("movement")), BASE_MOVEMENT,
		"and the BASE is untouched, which is what makes the boost read as a modifier")


func test_the_grant_is_a_refresh_never_a_stack() -> void:
	# CONQUEST.md rule 6, on the path that re-grants every single round boundary: if this
	# stacked, a twenty-round Siege would end with units moving twenty cells.
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	var c := _controller(_map(), rs, null, null)
	var hero := _unit(0)

	for i in range(6):
		c.grant_march_bonus(hero)
	assert_eq(_movement(hero), BASE_MOVEMENT + 2,
		"six grants leave exactly one +2 in force")
	assert_eq(hero.get_status_controller().stack_count(ModeTuning.MARCH_STATUS_ID), 1,
		"because the second application REFRESHES the one live instance rather than adding one")


func test_the_grant_is_permanent_so_the_mode_alone_takes_it_back() -> void:
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	var c := _controller(_map(), rs, null, null)
	var hero := _unit(0)
	c.grant_march_bonus(hero)

	var controller := hero.get_status_controller()
	for i in range(10):
		controller.tick_all(null)
	assert_eq(_movement(hero), BASE_MOVEMENT + 2,
		"ten turns of ticking does not time the mode's own grant out")
	assert_true(controller.has_status(ModeTuning.MARCH_STATUS_ID), "it is still on the unit")


func test_a_zero_bonus_grants_nothing_at_all() -> void:
	var rs := _ruleset()
	rs.hero_move_bonus = 0
	var c := _controller(_map(), rs, null, null)
	var hero := _unit(0)

	assert_false(c.grant_march_bonus(hero), "a bonus of 0 is not a buff, so nothing is applied")
	assert_false(hero.get_status_controller().has_status(ModeTuning.MARCH_STATUS_ID),
		"and the unit carries no phantom status advertising a bonus it does not have")
	assert_eq(_movement(hero), BASE_MOVEMENT, "its movement is its character's, untouched")


func test_a_unit_with_no_status_controller_simply_takes_nothing() -> void:
	assert_false(ModeTuning.grant_move_bonus(null, 2), "null is not a unit")
	assert_false(ModeTuning.grant_move_bonus(RefCounted.new(), 2),
		"and a double with no StatusController degrades to today's behaviour rather than raising")


# ==============================================================================
# 4. Who gets it, in a running Siege
# ==============================================================================

func test_a_round_boundary_boosts_every_squad_unit_on_both_sides() -> void:
	var board := FakeBoard.new()
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	rs.creeps_per_lane = 0
	var c := _controller(_map(), rs, null, board)

	var mine := _unit(0)
	var theirs := _unit(1)
	board.place(mine, Vector2i(2, 2))
	board.place(theirs, Vector2i(8, 8))

	c.observe_round(1)
	assert_eq(_movement(mine), BASE_MOVEMENT + 2, "the mode paces its own side")
	assert_eq(_movement(theirs), BASE_MOVEMENT + 2, "and the other side identically -- it is the "
		+ "MAP that is long, not one player's units that are slow")


func test_a_freshly_waved_creep_marches_at_the_creep_pace_immediately() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board, _unit)
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	rs.creep_move_bonus = 1
	var c := _controller(_map(), rs, spawner, board)

	for r in range(1, 4):
		c.observe_round(r)
	assert_gt(spawner.units.size(), 0, "round 3 pushed a wave to look at")

	var creep: Unit = spawner.units[0]
	assert_true(CaptureBase.is_creep(creep), "it really is a creep")
	assert_eq(_movement(creep), BASE_MOVEMENT + 1,
		"and it gets the CREEP knob, not the hero one -- the marks are stamped before the grant")


func test_a_respawned_squad_unit_comes_back_at_the_modes_pace() -> void:
	var board := FakeBoard.new()
	var spawner := FakeSpawner.new(board, _unit)
	var rs := _ruleset()
	rs.hero_move_bonus = 2
	rs.creeps_per_lane = 0        # isolate respawns from waves
	var c := _controller(_map(), rs, spawner, board)

	c.observe_round(1)
	var fallen := _unit(0)
	c.handle_unit_eliminated(fallen)
	c.observe_round(2)

	assert_eq(spawner.units.size(), 1, "the unit returned on the next round")
	var returned: Unit = spawner.units[0]
	assert_eq(_movement(returned), BASE_MOVEMENT + 2,
		"a respawn is a FRESH unit with no statuses, so the mode has to hand its pace back -- "
		+ "otherwise the returning unit is the slowest thing on the board")


func test_a_plain_skirmish_grants_nobody_anything() -> void:
	# The whole neutral-default contract, from the unit's side: with no mode armed there is no
	# ruleset, no grant, and a unit's movement is exactly its character's.
	ModeTuning.clear()
	var hero := _unit(0)
	assert_eq(_movement(hero), BASE_MOVEMENT, "a skirmish unit moves at its own speed")
	assert_false(hero.get_status_controller().has_status(ModeTuning.MARCH_STATUS_ID),
		"and carries no mode status at all")


# ==============================================================================
# 5. Determinism
# ==============================================================================

func test_two_identical_runs_pace_the_board_identically() -> void:
	var signatures: Array = []
	for run in range(2):
		var board := FakeBoard.new()
		var spawner := FakeSpawner.new(board, _unit)
		var rs := _ruleset()
		rs.hero_move_bonus = 2
		rs.creep_move_bonus = 1
		var c := _controller(_map(), rs, spawner, board)
		var mine := _unit(0)
		board.place(mine, Vector2i(2, 2))

		var sig: Array = []
		for r in range(1, 10):
			c.observe_round(r)
			sig.append("%d:%d:%d" % [r, _movement(mine), spawner.units.size()])
			for u in spawner.units:
				sig.append("c%d" % _movement(u))
		signatures.append(sig)
		ModeTuning.clear()

	assert_gt((signatures[0] as Array).size(), 0, "the run produced something to compare")
	assert_eq(signatures[0], signatures[1],
		"same ruleset + same round sequence => identical pacing, every round, both kinds")


# ==============================================================================
# 6. The placement record (the pure half; the live sweep is the integration suite)
# ==============================================================================

func test_an_unstamped_tile_effect_is_authored_terrain_and_never_expires() -> void:
	var te := TileEffectResource.new()
	assert_false(te.is_runtime_placement(), "a fresh effect is not a placement")
	assert_false(te.expires(), "and carries no clock")
	assert_false(te.is_expired_on(9999), "so no round ever expires it -- lava stays lava")


func test_a_placement_freezes_its_expiry_round_at_cast_time() -> void:
	var te := TileEffectResource.new()
	te.stamp_placement(4, 6)
	assert_true(te.is_runtime_placement(), "it is a runtime placement")
	assert_eq(te.placed_round, 4, "recording the round it went down")
	assert_eq(te.expires_on_round, 10, "and the round it is due: 4 + 6")
	assert_false(te.is_expired_on(9), "one round early it is still armed")
	assert_true(te.is_expired_on(10), "it expires EXACTLY on its frozen round")
	assert_true(te.is_expired_on(30), "and stays expired -- the check is not an equality")


func test_a_placement_with_no_declared_lifetime_is_permanent() -> void:
	var te := TileEffectResource.new()
	te.stamp_placement(4, 0)
	assert_true(te.is_runtime_placement(), "it was still placed at runtime")
	assert_false(te.expires(), "but a lifetime of 0 is NEVER, the answer outside a mode that "
		+ "declares one")
	assert_false(te.is_expired_on(9999), "so it is on the board for the rest of the battle")


func test_duplicating_an_authored_effect_never_carries_a_placement_record() -> void:
	# The rule-7 half: the record is runtime state, so the shared authoring resource can never
	# be stamped by one cast and hand an expiry to every later one.
	var authored := TileEffectResource.new()
	var placed := authored.duplicate()
	placed.stamp_placement(3, 6)
	assert_eq(authored.expires_on_round, -1, "the authored resource is untouched")
	var second := authored.duplicate()
	assert_eq(second.expires_on_round, -1, "and a second placement starts with a clean record")
