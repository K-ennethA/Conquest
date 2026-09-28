extends GutTest

## A booted battle names every unit "<owner_slot>:<n>" ([NetUnitIds]) -- on ordinary maps and
## on Riftwood, in solo and in hot-seat.
##
## The ids used to be assigned by the command seam at MAP LOAD, before any player owned a unit,
## so every local battle came out "-1:0".."-1:N". They are what a replay addresses units by (and
## what its per-turn checksum hashes), so they are now assigned once ownership is known. This
## boots the REAL GameWorld scene -- the only place that setup order lives -- and reads the
## names off the live board.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const DEFAULT_SKIRMISH := "res://game/maps/resources/default_skirmish.tres"
const CASTLE_SIEGE := "res://game/maps/resources/castle_siege.tres"
const RIFTWOOD := "res://game/maps/resources/riftwood.tres"

## Untyped on purpose (tests/README rule 3).
var _guard
var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("host_squad", [])
	_guard.set_setting("selected_turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)
	# The boot mounts a ReplayRecorder, which WRITES user://replays on teardown.
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	_clear_globals()


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
	_teardown_world()
	_free_mode_runtimes()
	ReplayRecorder.recording_enabled = _prev_recording
	MatchPeerInfo.clear()
	MatchLoadouts.clear()
	_clear_globals()
	_guard.restore()


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

func _clear_globals() -> void:
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()
	if TurnSystemManager != null:
		TurnSystemManager.reset_for_new_game()
	CombatServices.clear()


func _boot_world() -> void:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	_world = world


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


func _boot_to_first_turn(map_path: String, mode: int) -> bool:
	_guard.set_setting("selected_map_path", map_path)
	_guard.set_setting("game_mode", mode)
	_boot_world()
	var started: bool = await _await_until(func() -> bool:
		var intro = _world.get_node_or_null("VersusIntro") if is_instance_valid(_world) else null
		if intro != null and intro.has_method("is_playing") and intro.is_playing():
			intro.skip()
		return TurnSystemManager != null and TurnSystemManager.has_active_turn_system())
	if get_tree() != null:
		get_tree().paused = false
	for _i in range(3):
		await get_tree().process_frame
	return started


## Assert the live board's names are the documented "<owner_slot>:<n>": every unit named, the
## slot in the name IS its owner's, the per-slot indices run 0..k-1 with no gaps, and the name
## resolves back to the unit through the battle's installed command seam.
func _assert_slot_ids(label: String) -> void:
	var board = CombatServices.board()
	assert_not_null(board, "%s: a live board" % label)
	if board == null:
		return
	var units: Array = board.all_units()
	assert_gt(units.size(), 0, "%s: the map fielded units" % label)
	var per_slot: Dictionary = {}
	var seen: Dictionary = {}
	var ns = get_node_or_null("/root/NetSession")
	var applier = ns.get("command_applier") if ns != null else null
	for u in units:
		var id: String = NetUnitIds.id_of(u)
		# A Siege creep wave can land on the opening turn; creeps are MID-MATCH arrivals, not
		# match-start units, so the match-start naming does not cover them.
		if id == "" and BotTurnDriver.is_ai_driven(u):
			continue
		var owner = u.get_owner_player()
		assert_not_null(owner, "%s: %s is owned" % [label, u.name])
		if owner == null:
			continue
		var slot: int = int(owner.player_id)
		assert_true(id.begins_with("%d:" % slot),
			"%s: %s is named '%s' -- its id carries its owner's slot %d" % [label, u.name, id, slot])
		assert_false(id.begins_with("-1:"), "%s: no unit is named with the unowned slot" % label)
		assert_false(seen.has(id), "%s: '%s' is unique" % [label, id])
		seen[id] = true
		var n: String = id.get_slice(":", 1)
		assert_true(n.is_valid_int(), "%s: a match-start id is '<slot>:<n>' ('%s')" % [label, id])
		per_slot[slot] = int(per_slot.get(slot, 0)) + 1
		if applier != null and applier.has_method("find_unit"):
			assert_eq(applier.find_unit(id), u, "%s: '%s' resolves through the command seam" % [label, id])
	for slot in per_slot.keys():
		for i in range(int(per_slot[slot])):
			assert_true(seen.has("%d:%d" % [slot, i]),
				"%s: slot %d's ids run 0..%d without gaps" % [label, slot, int(per_slot[slot]) - 1])


func test_a_solo_skirmish_names_its_units_by_owner_slot() -> void:
	var started: bool = await _boot_to_first_turn(DEFAULT_SKIRMISH, GameSettings.GameMode.SINGLE_PLAYER)
	assert_true(started, "the solo skirmish boots to its first turn")
	if started:
		_assert_slot_ids("default_skirmish / solo")


func test_a_hotseat_castle_siege_names_its_units_by_owner_slot() -> void:
	if not ResourceLoader.exists(CASTLE_SIEGE):
		pending("castle_siege map resource is not present")
		return
	var started: bool = await _boot_to_first_turn(CASTLE_SIEGE, GameSettings.GameMode.VERSUS)
	assert_true(started, "the hot-seat castle siege boots to its first turn")
	if started:
		_assert_slot_ids("castle_siege / hot-seat")


func test_riftwood_names_the_neutral_camps_on_slot_two() -> void:
	if not ResourceLoader.exists(RIFTWOOD):
		pending("riftwood map resource is not present")
		return
	var started: bool = await _boot_to_first_turn(RIFTWOOD, GameSettings.GameMode.VERSUS)
	assert_true(started, "hot-seat Riftwood boots to its first turn")
	if not started:
		return
	_assert_slot_ids("riftwood / hot-seat")
	var neutral_named: int = 0
	for u in CombatServices.board().all_units():
		if NetUnitIds.id_of(u).begins_with("2:"):
			neutral_named += 1
	assert_gt(neutral_named, 0, "the neutral jungle camps are named on their own slot, 2")
