extends GutTest

## THE TACTICAL ROUND TRIP against a REAL booted GameWorld (docs/design/OVERWORLD.md §4.6):
## StoryController stages Bram's battle -> GameWorld boots its ordinary way -> the fielded party
## units carry story member ids, carried HP and story-bag items -> the enemy is wiped ->
## GameEvents.battle_resolved -> the result is reported ONCE -> the end screen shows the story's
## "Continue Journey" -> pressing it applies rewards / flags / HP and sets the return point.
## No profile drop is rolled for a story battle and Save & Quit is not offered.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const TEMP_DIR := "user://test_story_round_trip/"
const TEMP_BATTLE_SAVE := "user://test_story_round_trip_battle.json"

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


func _bram_request() -> BattleRequest:
	var moss := load(StoryController.area_path("mossway")) as OverworldAreaResource
	var bram := moss.entity("bram") as TrainerEntity
	return bram.battle.to_request(BattleRequest.SOURCE_TRAINER, bram.encounter_id("mossway"))


func _party_units() -> Array:
	var out: Array = []
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			out.append(u)
	return out


func test_round_trip_victory() -> void:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	s.member("vineweave").current_hp = 50
	# The charm goes on Blightcap: an item can regenerate, which would blur the carried-HP check.
	s.member("blightcap").item_id = "heartwood_charm"
	var began: Dictionary = StoryController.begin_battle(_bram_request(), false)
	assert_true(bool(began["success"]), "Bram's battle stages")
	assert_true(StoryController.is_battle_active(), "armed")
	_boot_world()
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == 2)
	assert_true(up, "the battle boots with both party members tagged")
	if not up:
		return
	var vine = null
	var cap = null
	for u in _party_units():
		if String(u.get_meta(StoryBattleBridge.MEMBER_META)) == "vineweave":
			vine = u
		elif String(u.get_meta(StoryBattleBridge.MEMBER_META)) == "blightcap":
			cap = u
	assert_not_null(vine, "Vineweave carries its story member id")
	assert_eq(int(vine.current_health), 50, "and its CARRIED HP")
	assert_eq((StoryController.loadout_for_unit(vine) as Array).size(), 0, "nothing equipped -> an empty story loadout (not the profile inventory)")
	var loadout = StoryController.loadout_for_unit(cap)
	assert_eq((loadout as Array).size(), 1, "its story-bag item is its loadout")
	assert_eq(String((loadout as Array)[0].id), "heartwood_charm", "the equipped charm")
	var bsm := get_tree().get_first_node_in_group(BattleSaveManager.GROUP)
	if bsm != null:
		assert_false(bsm.can_save_now(), "Save & Quit is not offered in a story battle (M1)")

	ItemSystem.begin_battle_drop_log()
	for u in CombatServices.board().all_units():
		if not u.has_meta(StoryBattleBridge.MEMBER_META):
			u.take_damage(99999)
	var shown: bool = await _await_until(func() -> bool: return _resolved.size() > 0)
	assert_true(shown, "the battle resolves")
	assert_eq(_resolved, ["victory"], "GameEvents.battle_resolved fired ONCE with victory")
	await get_tree().process_frame
	var result: BattleResult = StoryController.last_result()
	assert_not_null(result, "the story result was built from the board")
	assert_eq(result.outcome, "victory", "a victory")
	assert_eq(result.defeated.size(), 3, "three foes defeated")
	assert_eq(ItemSystem.drops_this_battle().size(), 0, "no profile drop in a story battle")

	var screen: GameOverScreen = _world.find_children("*", "GameOverScreen", true, false)[0]
	var buttons: Array[Button] = screen.mode_action_buttons()
	assert_eq(buttons.size(), 1, "the end screen shows the story's own action")
	assert_eq(buttons[0].text, "Continue Journey", "Continue Journey")
	buttons[0].pressed.emit()
	assert_false(get_tree().paused, "the tree is unpaused")
	assert_true(s.has_flag("trainer.mossway.bram.defeated"), "Bram's defeated flag")
	assert_eq(s.gold, 100 + 120, "his purse")
	assert_ne(s.member("vineweave").current_hp, StoryPartyMember.HP_FULL, "battle HP carried back")
	assert_eq(s.location_cell(), Vector3i(19, 6, 0), "the return point")
	assert_null(StoryController.active_request(), "the battle is disarmed")
	assert_false(bool(StoryController.report_battle_result(result)["success"]), "a late second report is refused")
	assert_true((StorySaveManager.peek(1)["flags"] as Dictionary).has("trainer.mossway.bram.defeated"),
		"and the journey autosaved after the result")


func test_an_ordinary_battle_keeps_the_normal_end_screen() -> void:
	# No story battle armed: a plain skirmish on the same board must look exactly as before.
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_selected_map("res://game/overworld/content/battles/ow_mossway_clearing.tres")
	GameSettings.set_selected_squad(["vineweave"])
	_boot_world()
	var up: bool = await _await_until(func() -> bool: return TurnSystemManager.has_active_turn_system())
	assert_true(up, "boots")
	if not up:
		return
	assert_false(StoryController.is_battle_active(), "not a story battle")
	for u in CombatServices.board().all_units():
		if u.get_parent() != null and u.get_parent().name != "Player1":
			u.take_damage(99999)
	await _await_until(func() -> bool: return _resolved.size() > 0)
	await get_tree().process_frame
	var screen: GameOverScreen = _world.find_children("*", "GameOverScreen", true, false)[0]
	assert_eq(screen.mode_action_buttons().size(), 0, "no mode actions outside story")
	assert_true(screen._rematch_button.visible, "Rematch is still offered")
