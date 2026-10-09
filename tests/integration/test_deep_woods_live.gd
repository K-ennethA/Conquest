extends GutTest

## ELDROOT'S LEGEND BATTLE, LIVE (docs/design/DECISIONS.md #74 / #81): the shipped spec staged through
## StoryController on a real booted GameWorld -- the squad fields (the hero, the creatures and Lyra, a
## temporary party member: a human unit), Eldroot (the 2x2 boss) spawns at the FIXED legend level
## and its Barkling screen at their own map level; winning sets the battle's reward flag.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const TEMP_DIR := "user://test_deep_woods_live/"
const TEMP_BATTLE_SAVE := "user://test_deep_woods_live_battle.json"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true
var _resolved: Array = []


func before_all() -> void:
	BattleSaveManager.set_save_path(TEMP_BATTLE_SAVE)


func after_all() -> void:
	BattleSaveManager.delete_save()
	BattleSaveManager.set_save_path(BattleSaveManager.DEFAULT_SAVE_PATH)


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	for k in ["selected_map_path", "selected_squad", "game_mode", "ai_difficulty", "player_count",
			"player_names", "selected_turn_system"]:
		_guard.watch_setting(k)
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	_resolved = []
	GameEvents.battle_resolved.connect(_on_resolved)
	_clear_globals()


func after_each() -> void:
	if GameEvents.battle_resolved.is_connected(_on_resolved):
		GameEvents.battle_resolved.disconnect(_on_resolved)
	get_tree().paused = false
	_teardown_world()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	ReplayRecorder.recording_enabled = _prev_recording
	ReplayPlayback.end_playback()
	PortraitCache.reset()
	_clear_globals()
	_guard.restore()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_resolved(outcome, _ctx) -> void:
	_resolved.append(String(outcome))


func _clear_globals() -> void:
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()
	CombatServices.clear()
	CombatServices.match_rng = null


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
	get_tree().current_scene = _prev_scene
	if _world.get_parent() != null:
		_world.get_parent().remove_child(_world)
	_world.free()
	_world = null


func _await_until(pred: Callable, max_frames: int = 900) -> bool:
	for i in range(max_frames):
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return false


func _party_units() -> Array:
	var out: Array = []
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			out.append(u)
	return out


func _eldroot_spec() -> BattleSpec:
	var depths := load(StoryController.area_path("depths_of_the_wood")) as OverworldAreaResource
	var stack: Array = depths.entity("eldroot").on_interact.duplicate()
	while not stack.is_empty():
		var c = stack.pop_front()
		if c is StartBattleCommand and not (c is StartDuelCommand):
			return (c as StartBattleCommand).spec
		if c is StoryCommand:
			for l in (c as StoryCommand).child_lists():
				stack.append_array(l)
	return null


func test_the_legend_board_fields_the_squad_lyra_and_a_fixed_level_eldroot() -> void:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	var s: StoryState = StoryController.state()
	s.set_location("depths_of_the_wood", Vector3i(12, 6, 0), "north")
	s.member("vineweave").set_level(11)
	s.member("blightcap").set_level(9)
	assert_not_null(s.join("lyra", "", 6, 10, true, "deepwood.eldroot_beaten")["member"], "Lyra joins after Nyra (temporary)")
	var spec := _eldroot_spec()
	assert_not_null(spec, "Eldroot's battle ships")
	if spec == null:
		return
	var req: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT, "")
	spec.apply_scaling(req, s)
	var began: Dictionary = StoryController.begin_battle(req, false)
	assert_true(bool(began["success"]), "the legend battle stages")
	_boot_world()
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == 4)
	assert_true(up, "the board boots with the party tagged")
	if not up:
		return
	var legend_lv: int = 15 + ProgressionRules.current().legend_over_band
	var mine: Player = (_party_units()[0] as Unit).get_owner_player()
	var eldroot: Unit = null
	var lyra: Unit = null
	var screens: int = 0
	for u in CombatServices.board().all_units():
		var cid: String = String(u.character_resource.character_id)
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			if cid == "lyra":
				lyra = u
			continue
		if u.get_owner_player() == mine:
			continue
		elif cid == "eldroot":
			eldroot = u
		elif cid == "tree_grunt":
			screens += 1
			assert_eq(int(u.get_meta(StoryBattleBridge.LEVEL_META, 0)), 13, "a Barkling screen fights at its map level")
	assert_not_null(lyra, "Lyra fights on the player's side, deployed from the party")
	if lyra != null:
		assert_eq(lyra.get_owner_player(), mine, "on the hero's side")
		assert_eq(lyra.character_resource.kind, CharacterResource.Kind.HUMAN, "as her own human unit")
		assert_eq(int(lyra.get_meta(StoryBattleBridge.LEVEL_META, 0)), 10, "at her own level")
	assert_not_null(eldroot, "Eldroot stands on its board")
	if eldroot != null:
		assert_eq(int(eldroot.get_meta(StoryBattleBridge.LEVEL_META, 0)), legend_lv, "at the FIXED legend level")
	assert_eq(screens, 2, "two Barklings screen it")

	for u in CombatServices.board().all_units():
		if u.get_owner_player() != mine:
			u.take_damage(999999)
	var done: bool = await _await_until(func() -> bool: return _resolved.size() > 0)
	assert_true(done, "the battle resolves")
	await get_tree().process_frame
	var screen: GameOverScreen = _world.find_children("*", "GameOverScreen", true, false)[0]
	var buttons: Array[Button] = screen.mode_action_buttons()
	buttons[0].pressed.emit()
	assert_true(s.has_flag("deepwood.eldroot_beaten"), "winning sets the legend battle's flag")
	assert_false(s.party_has("eldroot"), "a beaten legend does not join the party by itself")
