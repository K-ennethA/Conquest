extends GutTest

## HOT-SEAT with an AI faction on the board -- a map's NEUTRAL camps (an is_ai player on slot 2,
## registered by BaseAssaultRuntime) or a side's Siege creeps (AI-driven units owned by a
## HUMAN). Local versus used to mount no AI driver at all, so the first time the turn reached
## the neutral faction nobody acted for it and the match sat on that turn forever; Siege creeps
## never moved.
##
## Two halves, both against real Units, a real board and real turn systems:
##   1. the DRIVER'S CONTRACT in a two-human game: it resolves the neutral faction's turn (both
##      turn systems -- under Speed First the neutral units come up interleaved by speed) and
##      hands the game on, it drives a human side's creeps on that side's turn, and it NEVER
##      acts a unit one of the two humans commands;
##   2. THE REAL BOOT: Riftwood as a hot-seat Siege battle (the reported freeze) mounts the
##      driver, fields the neutral faction as AI, and the mounted driver carries the neutral
##      turn back round to player 1.
##
## [BotTurnDriver.act_for_turn_system] is stepped directly (the exact per-unit step its Timer
## makes), so nothing here waits on the wall clock.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const SOLDIER_ID: StringName = &"test_hotseat_soldier"

## The map the freeze was reported on: neutral jungle camps on slot 2, Siege lanes.
const RIFTWOOD := "res://game/maps/resources/riftwood.tres"

## Untyped on purpose (tests/README rule 3).
var _guard
var _map_root: Node3D = null
var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard = Guard.new()
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)
	_guard.set_setting("auto_end_turn", true)
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	CharacterLibrary._cache[SOLDIER_ID] = _make_soldier()
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
	_teardown_world()
	_free_mode_runtimes()
	TurnSystemManager.active_turn_system = null
	CombatServices.clear()
	_map_root = null
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()
	ReplayRecorder.recording_enabled = _prev_recording
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	_guard.restore()
	CharacterLibrary.clear_cache()


## A Siege / base-assault boot leaves the mode layer's process-wide runtimes parented to the
## tree ROOT (they outlive scenes by design). Free them and drop the active ruleset so no later
## suite inherits an armed Siege -- or finds the root name its own stub needs already taken.
func _free_mode_runtimes() -> void:
	for node_name in [SiegeController.NODE_NAME, BaseAssaultRuntime.NODE_NAME]:
		var node = get_tree().root.get_node_or_null(NodePath(node_name))
		if node != null:
			get_tree().root.remove_child(node)
			node.free()
	ModeTuning.clear()

# =====================================================================================
#  1. The driver's contract in a two-human game
# =====================================================================================

func _make_soldier() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = SOLDIER_ID
	c.display_name = "Soldier"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 100
	c.base_attack = 20
	c.base_defense = 8
	c.base_magic = 4
	c.base_magic_defense = 8
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [_strike()] as Array[MoveResource]
	return c


func _strike() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_hotseat_strike"
	m.display_name = "Test Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = 5.0
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 10
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


func _cell_to_world(cell: Vector3i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


func _spawn(cell: Vector3i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(SOLDIER_ID)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## The hot-seat roster: TWO humans (slots 0 and 1) and the NEUTRAL faction (slot 2, is_ai +
## is_neutral -- exactly what PlayerManager.ensure_neutral_player stamps). Each human fields a
## unit; the neutral fields two camp guardians in the middle of the 5x5 board, out of reach of
## both humans so nobody's HP muddies the "who moved" assertions.
func _build_hotseat() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var p1 := Player.new(0, "Player 1")
	var p2 := Player.new(1, "Player 2")
	var neutral := Player.new(2, "Neutral")
	neutral.is_ai = true
	neutral.is_neutral = true

	var p1_unit := _spawn(Vector3i(0, 0, 0), p1)
	var p2_unit := _spawn(Vector3i(4, 4, 0), p2)
	var camp_a := _spawn(Vector3i(2, 2, 0), neutral)
	var camp_b := _spawn(Vector3i(2, 3, 0), neutral)
	if p1_unit == null or p2_unit == null or camp_a == null or camp_b == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	return {
		"p1": p1, "p2": p2, "neutral": neutral,
		"p1_unit": p1_unit, "p2_unit": p2_unit, "camp_a": camp_a, "camp_b": camp_b,
		"board": CombatServices.board(),
	}


func _make_driver() -> BotTurnDriver:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	if driver._timer != null:
		driver._timer.stop()
	return driver


func _cells(board, units: Array) -> Array:
	var out: Array = []
	for u in units:
		out.append(board.cell_of(u))
	return out


func test_traditional_hotseat_resolves_the_neutral_turn_and_never_plays_a_human() -> void:
	var s: Dictionary = await _build_hotseat()
	if s.is_empty() or s["board"] == null:
		pending("could not build the live board (roster/board unavailable)")
		return
	var board = s["board"]
	var humans: Array = [s["p1_unit"], s["p2_unit"]]
	var human_cells: Array = _cells(board, humans)

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(s["p1"])
	ts.register_player(s["p2"])
	ts.register_player(s["neutral"])
	ts.start_turn_system()
	var driver := _make_driver()

	# PLAYER 1's turn: the driver has nothing to do -- it is a human's turn, and nothing on
	# that side is AI-driven.
	assert_eq(ts.get_current_active_player(), s["p1"], "player 1 opens the battle")
	assert_false(await driver.act_for_turn_system(ts),
		"the driver never acts on a human's turn (no unit there is AI-driven)")
	assert_true(ts.end_turn_manually(), "player 1 ends their turn by hand")

	# PLAYER 2: same.
	assert_eq(ts.get_current_active_player(), s["p2"], "player 2 is up next")
	assert_false(await driver.act_for_turn_system(ts),
		"and the driver leaves the second human alone too")
	assert_true(ts.end_turn_manually(), "player 2 ends their turn by hand")

	# THE NEUTRAL TURN -- the one that used to freeze. The driver resolves it unit by unit and
	# the (deferred) auto-end hands the game back to player 1.
	assert_eq(ts.get_current_active_player(), s["neutral"], "the turn reaches the neutral faction")
	var steps: int = 0
	while ts.get_current_active_player() == s["neutral"] and steps < 12:
		await driver.act_for_turn_system(ts)
		await get_tree().process_frame
		steps += 1
	assert_eq(ts.get_current_active_player(), s["p1"],
		"the neutral turn was played out and the game came back round to player 1")
	assert_true(steps >= 2, "each neutral unit took its own step (two camp guardians)")
	assert_eq(_cells(board, humans), human_cells,
		"no human unit was moved by the driver at any point")
	assert_false(await driver.act_for_turn_system(ts),
		"and back on player 1's turn the driver is idle again")


func test_speed_first_hotseat_acts_each_neutral_unit_when_it_comes_up() -> void:
	var s: Dictionary = await _build_hotseat()
	if s.is_empty() or s["board"] == null:
		pending("could not build the live board (roster/board unavailable)")
		return
	var board = s["board"]
	var humans: Array = [s["p1_unit"], s["p2_unit"]]
	var human_cells: Array = _cells(board, humans)

	var ts := SpeedFirstTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(s["p1"])
	ts.register_player(s["p2"])
	ts.register_player(s["neutral"])
	ts.start_turn_system()
	var driver := _make_driver()

	# Walk a full round of the interleaved queue. A human unit's turn is ended by hand (as the
	# player would); a neutral unit's turn must be resolved by the driver, which is what moves
	# the queue on past it.
	var neutral_turns_resolved: int = 0
	var human_turns: int = 0
	for _i in range(16):
		var player: Player = ts.get_current_active_player()
		if player == null:
			break
		if player == s["neutral"]:
			# A move-then-strike is two driver beats (the slide, then the hit), so step until the
			# queue hands the turn on -- bounded, and that hand-off is the thing under test.
			var acting = ts.current_acting_unit
			var beats: int = 0
			while ts.current_acting_unit == acting and beats < 4:
				assert_true(await driver.act_for_turn_system(ts),
					"the driver acts the neutral unit whose turn came up")
				await get_tree().process_frame
				beats += 1
			assert_ne(ts.current_acting_unit, acting,
				"and resolving it moved the queue on -- the neutral turn never stalls")
			neutral_turns_resolved += 1
		else:
			assert_false(await driver.act_for_turn_system(ts),
				"on a HUMAN unit's turn the driver does nothing")
			ts.advance_turn()
			human_turns += 1
		if neutral_turns_resolved >= 2 and human_turns >= 2:
			break

	assert_eq(neutral_turns_resolved, 2, "both neutral guardians got (and used) their turns")
	assert_true(human_turns >= 2, "and both humans' units came up in between")
	assert_eq(_cells(board, humans), human_cells, "no human unit was ever moved by the driver")


func test_hotseat_siege_creeps_move_on_their_human_owners_turn() -> void:
	# A hot-seat Siege battle has NO AI player at all -- both sides are human -- yet each side's
	# creeps (owned by that side, marked AI-driven) must still march. This is the reason the
	# driver is mounted for every local battle rather than only when some player is AI.
	var s: Dictionary = await _build_hotseat()
	if s.is_empty() or s["board"] == null:
		pending("could not build the live board (roster/board unavailable)")
		return
	var board = s["board"]
	var p2: Player = s["p2"]
	var creep := _spawn(Vector3i(4, 3, 0), p2)
	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	board = CombatServices.board()
	SiegeController.stamp_creep(creep, [Vector3i(4, 3, 0), Vector3i(4, 0, 0)], 3)

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(s["p1"])
	ts.register_player(p2)
	ts.start_turn_system()
	var driver := _make_driver()

	assert_false(await driver.act_for_turn_system(ts),
		"on player 1's turn there is nothing AI-driven to resolve")
	ts.end_turn_manually()
	assert_eq(ts.get_current_active_player(), p2, "player 2 is up")

	var creep_cell: Vector3i = board.cell_of(creep)
	var hero_cell: Vector3i = board.cell_of(s["p2_unit"])
	assert_true(await driver.act_for_turn_system(ts),
		"the driver resolves player 2's creep on player 2's own turn")
	assert_ne(board.cell_of(creep), creep_cell, "the creep marched")
	# A march that ends next to an enemy strikes on the following beat; let it finish.
	var beats: int = 1
	while beats < 4 and await driver.act_for_turn_system(ts):
		beats += 1
	assert_lt(beats, 4, "the creep's turn is finite -- the driver then goes idle")
	assert_eq(board.cell_of(s["p2_unit"]), hero_cell, "player 2's own unit was left to player 2")
	assert_false(await driver.act_for_turn_system(ts),
		"with the creep spent, the rest of the turn belongs to the human")
	assert_eq(ts.get_current_active_player(), p2,
		"and the human's turn is NOT ended for them -- their unit is still to command")


# =====================================================================================
#  2. The real boot: Riftwood as a hot-seat Siege battle
# =====================================================================================

func _boot_world() -> Node:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	_world = world
	return world


func _teardown_world() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = null
		return
	if get_tree() != null:
		get_tree().current_scene = _prev_scene
		if _world.get_parent() != null:
			_world.get_parent().remove_child(_world)
	_world.free()
	_world = null
	_prev_scene = null


func _await_until(predicate: Callable, max_frames: int = 900) -> bool:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


## Boot [param map_path] in the current game mode and wait until its first turn is live,
## skipping the versus intro if one mounts. Returns false when the boot never got there.
func _boot_to_first_turn(map_path: String) -> bool:
	_guard.set_setting("selected_map_path", map_path)
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("host_squad", [])
	_boot_world()
	var started: bool = await _await_until(func() -> bool:
		var intro = _world.get_node_or_null("VersusIntro") if is_instance_valid(_world) else null
		if intro != null and intro.has_method("is_playing") and intro.is_playing():
			intro.skip()
		return TurnSystemManager != null and TurnSystemManager.has_active_turn_system())
	if get_tree() != null:
		get_tree().paused = false
	# Let the activation's deferred kickoff settle.
	for _i in range(3):
		await get_tree().process_frame
	return started


func test_riftwood_hotseat_boot_mounts_the_driver_and_plays_the_neutral_turn() -> void:
	if not ResourceLoader.exists(RIFTWOOD):
		pending("riftwood map resource is not present")
		return
	_guard.set_setting("selected_turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)
	var started: bool = await _boot_to_first_turn(RIFTWOOD)
	assert_true(started, "the hot-seat Riftwood battle boots to its first turn")
	if not started:
		return

	var driver = _world.get_node_or_null("BotTurnDriver")
	assert_not_null(driver, "a LOCAL VERSUS battle mounts the AI driver")
	if driver == null:
		return
	# Drive it by hand from here on (deterministic, no wall clock).
	driver._timer.stop()

	var players: Array = PlayerManager.players
	assert_eq(players.size(), 3, "Riftwood fields the two seats plus the neutral faction")
	if players.size() < 3:
		return
	assert_false(players[0].is_ai, "seat 1 is human")
	assert_false(players[1].is_ai, "seat 2 is human -- hot-seat never marks a seat AI")
	assert_true(players[2].is_ai and players[2].is_neutral, "slot 2 is the AI neutral faction")

	var ts: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	var board = CombatServices.board()
	var human_units: Array = []
	for p in [players[0], players[1]]:
		for u in p.owned_units:
			if is_instance_valid(u) and not BotTurnDriver.is_ai_driven(u):
				human_units.append(u)
	var human_cells: Array = _cells(board, human_units)

	# Hand the turn round to the neutral faction the way the two players would: each ends
	# their turn. If Siege already put creeps on the board, the driver marches a seat's own
	# creeps on that seat's turn -- and then goes idle, leaving the rest to the human.
	for seat in [players[0], players[1]]:
		assert_eq(ts.get_current_active_player(), seat, "%s is up" % seat.get_display_name())
		var creep_steps: int = 0
		while creep_steps < 60 and await driver.act_one_ai_unit():
			await get_tree().process_frame
			creep_steps += 1
		assert_eq(ts.get_current_active_player(), seat,
			"the driver never ends a human seat's turn for them")
		ts.end_turn_manually()
		await get_tree().process_frame
	assert_eq(ts.get_current_active_player(), players[2],
		"the turn reaches the neutral faction -- where the battle used to freeze")

	var steps: int = 0
	while ts.get_current_active_player() == players[2] and steps < 200:
		await driver.act_one_ai_unit()
		await get_tree().process_frame
		steps += 1
	assert_eq(ts.get_current_active_player(), players[0],
		"the mounted driver played the neutral turn out and handed it back to player 1")
	assert_eq(_cells(board, human_units), human_cells,
		"and moved none of the humans' own units doing it")
