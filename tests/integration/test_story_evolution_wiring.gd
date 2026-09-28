extends GutTest

## EVOLUTION IN STORY against a REAL booted GameWorld (docs/STORY_MODE.md "Wiring"): a Barkling
## ("tree_grunt", Growth 2 of 3) fights Bram's tactical battle -> the end screen shows the Growth
## Continue will award -> Continue awards it into the JOURNEY's member record (not the global
## roster) -> back on the overworld the Evolution screen is offered -> Evolve -> the member
## BECOMES Oakheart (member id, item and proportional HP kept; the form is unlocked for open
## modes) -> the next story battle fields Oakheart -> save / reload keeps form and growth.

const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")
const TEMP_DIR := "user://test_story_evolution_wiring/"
const TEMP_BATTLE_SAVE := "user://test_story_evolution_wiring_battle.json"
const TEMP_ROSTER := "user://test_story_evolution_wiring_roster.json"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true
var _resolved: Array = []
var _screens: Array = []


func before_all() -> void:
	BattleSaveManager.set_save_path(TEMP_BATTLE_SAVE)
	RosterLedger.set_save_path(TEMP_ROSTER)


func after_all() -> void:
	BattleSaveManager.delete_save()
	BattleSaveManager.set_save_path(BattleSaveManager.DEFAULT_SAVE_PATH)
	if FileAccess.file_exists(TEMP_ROSTER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_ROSTER))
	RosterLedger.set_save_path(RosterLedger.DEFAULT_SAVE_PATH)


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
	RosterLedger.reset()
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	_resolved = []
	_screens = []
	GameEvents.battle_resolved.connect(_on_resolved)
	StoryController.evolution_offered.connect(_on_offered)
	_clear_globals()


func after_each() -> void:
	if GameEvents.battle_resolved.is_connected(_on_resolved):
		GameEvents.battle_resolved.disconnect(_on_resolved)
	if StoryController.evolution_offered.is_connected(_on_offered):
		StoryController.evolution_offered.disconnect(_on_offered)
	get_tree().paused = false
	_teardown_world()
	for s in _screens:
		if is_instance_valid(s):
			s.free()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	ReplayRecorder.recording_enabled = _prev_recording
	ReplayPlayback.end_playback()
	GrowthTracker.begin_battle_log()
	PortraitCache.reset()
	RosterLedger.reset()
	_clear_globals()
	_guard.restore()
	await get_tree().process_frame
	await get_tree().process_frame


func _on_resolved(outcome, _ctx) -> void:
	_resolved.append(String(outcome))


func _on_offered(screen) -> void:
	_screens.append(screen)


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
	return bool(pred.call())


func _bram_request() -> BattleRequest:
	var moss := load(StoryController.area_path("mossway")) as OverworldAreaResource
	var bram := moss.entity("bram") as TrainerEntity
	return bram.battle.to_request(BattleRequest.SOURCE_TRAINER, bram.encounter_id("mossway"))


func _party_units() -> Array:
	var out: Array = []
	if CombatServices.board() == null:
		return out
	for u in CombatServices.board().all_units():
		if u.has_meta(StoryBattleBridge.MEMBER_META):
			out.append(u)
	return out


## A journey whose party is a Barkling one Growth short of Oakheart, plus Vineweave.
func _barkling_journey() -> StoryState:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.party.clear()
	var bark: StoryPartyMember = s.add_member("tree_grunt")
	bark.add_growth(2)
	bark.item_id = "heartwood_charm"
	s.add_member("vineweave")
	s.set_location("mossway", Vector3i(19, 6, 0), "north")
	return s


## Boot the staged battle, wipe the enemy, wait for the end screen.
func _win_on_the_board(member_count: int) -> GameOverScreen:
	_boot_world()
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == member_count)
	assert_true(up, "the battle boots with the party tagged")
	if not up:
		return null
	for u in CombatServices.board().all_units():
		if not u.has_meta(StoryBattleBridge.MEMBER_META):
			u.take_damage(99999)
	assert_true(await _await_until(func() -> bool: return _resolved.size() > 0), "the battle resolves")
	await get_tree().process_frame
	return _world.find_children("*", "GameOverScreen", true, false)[0]


func test_growth_evolution_offer_and_the_evolved_form_fights_next() -> void:
	var s := _barkling_journey()
	var bark: StoryPartyMember = s.member("tree_grunt")
	assert_not_null(bark, "the Barkling is member 'tree_grunt' (the RosterLedger uid scheme)")
	assert_true(bool(StoryController.begin_battle(_bram_request(), false)["success"]), "Bram's battle stages")
	var screen := await _win_on_the_board(2)
	if screen == null:
		return
	# The wounded-ratio check below needs a known HP going in to the evolution.
	var rows: Array = GrowthTracker.growth_this_battle()
	var bark_row: Dictionary = {}
	for r in rows:
		if String(r.get("uid", "")) == "tree_grunt":
			bark_row = r
	assert_false(bark_row.is_empty(), "the end screen shows the Barkling's Growth")
	assert_eq(int(bark_row.get("total", 0)), 3, "3 of 3")
	assert_true(bool(bark_row.get("ready", false)), "ready to evolve")
	assert_eq(bark.growth_points(), 2, "nothing is awarded before Continue")
	assert_eq(RosterLedger.growth_of("tree_grunt"), 0, "and the GLOBAL roster is never touched by story growth")

	screen.mode_action_buttons()[0].pressed.emit()
	assert_eq(bark.growth_points(), 3, "Continue awarded the Growth into the journey's member record")
	assert_eq(s.member("vineweave").growth_points(), 1, "every surviving fielded member earns")
	_teardown_world()
	bark.current_hp = 27  # of Barkling's 55: about half
	# Back on the overworld (the host boot is simulated): the offer chain runs, then the script.
	StoryController.overworld_ready(null)
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty(), 60), "the Evolution screen is offered")
	if _screens.is_empty():
		return
	var evo: EvolutionScreen = _screens[0]
	assert_eq(evo.uid, "tree_grunt", "for the Barkling")
	assert_true(evo.is_story(), "with the story commit (the member becomes the form)")
	var res: Dictionary = evo.confirm()
	assert_true(bool(res.get("success", false)), "Evolve commits")
	evo.dismiss()
	evo.dismiss()
	await get_tree().process_frame
	assert_eq(bark.character_id, "oakheart", "the party member BECAME Oakheart")
	assert_eq(bark.member_id, "tree_grunt", "same individual (member id kept)")
	assert_eq(bark.item_id, "heartwood_charm", "its item stays on")
	assert_eq(bark.current_hp, roundi(27.0 / 55.0 * 96.0), "HP kept by ratio (55 -> 96 max)")
	assert_eq(bark.evolution_history().size(), 1, "the evolution is in its history")
	assert_true(RosterLedger.is_form_unlocked("oakheart"), "Oakheart is unlocked for the open modes too")
	assert_eq(RosterLedger.form_of("tree_grunt"), &"tree_grunt", "the open-mode Barkling is untouched")
	assert_eq(String(StorySaveManager.peek(1)["party"][0]["character_id"]), "oakheart", "and the journey saved it")

	# The next story battle fields the evolved form. (The charm comes off first: its HP bonus
	# would blur the carried-HP check, as in test_story_tactical_round_trip.)
	bark.item_id = ""
	await get_tree().process_frame
	_resolved = []
	_clear_globals()
	assert_true(bool(StoryController.begin_battle(_bram_request(), false)["success"]), "the next battle stages")
	assert_eq(StoryController.active_request().party[0]["character_id"], "oakheart", "the request fields Oakheart")
	assert_true(GameSettings.selected_squad.has("oakheart"), "the squad is staged with Oakheart")
	_boot_world()
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == 2)
	assert_true(up, "the next battle boots")
	var fielded: Unit = null
	for u in _party_units():
		if String(u.get_meta(StoryBattleBridge.MEMBER_META)) == "tree_grunt":
			fielded = u
	assert_not_null(fielded, "the member is on the board")
	if fielded != null:
		assert_eq(fielded.character_resource.character_id, &"oakheart", "as Oakheart")
		# Carried HP, not a fresh full bar (Oakheart's Nature's Blessing may already have ticked
		# a heal on the opening turn, so the floor is the carried value).
		assert_between(int(fielded.current_health), bark.current_hp, fielded.max_health - 1,
			"with its carried HP")


func test_not_now_leaves_the_member_and_offers_again_later() -> void:
	var s := _barkling_journey()
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.add_growth(1)
	StoryController.offer_pending_evolutions()
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty(), 60), "offered")
	if _screens.is_empty():
		return
	(_screens[0] as EvolutionScreen).decline()
	await get_tree().process_frame
	assert_eq(bark.character_id, "tree_grunt", "Not now changes nothing")
	assert_false(RosterLedger.is_form_unlocked("oakheart"), "and unlocks nothing")
	assert_eq(StoryGrowth.pending(s), ["tree_grunt"], "the offer stays open")


func test_save_and_reload_keeps_forms_and_growth() -> void:
	var s := _barkling_journey()
	var bark: StoryPartyMember = s.member("tree_grunt")
	bark.add_growth(1)
	var r: Dictionary = StoryGrowth.evolve(s, "tree_grunt", EvolutionLibrary.get_edge(&"tree_grunt__oakheart"))
	assert_true(bool(r["success"]), "evolves")
	assert_true(bool(StoryController.save_game()["success"]), "saves")
	var loaded: Dictionary = StorySaveManager.load_state(1)
	assert_true(bool(loaded["success"]), "reloads")
	var back: StoryPartyMember = (loaded["state"] as StoryState).member("tree_grunt")
	assert_not_null(back, "the member survives the round trip")
	assert_eq(back.character_id, "oakheart", "as its evolved form")
	assert_eq(back.line, "tree_grunt", "of its line")
	assert_eq(back.growth_points(), 3, "with its Growth")
	assert_eq(back.evolution_history().size(), 1, "and its history")
	assert_eq(StoryGrowth.pending(loaded["state"]), [], "nothing further to evolve into")


func test_a_scripted_evolve_member_command_evolves_past_the_triggers() -> void:
	var s := _barkling_journey()
	var cmd := EvolveMemberCommand.new()
	cmd.member = "tree_grunt"
	cmd.edge_id = &"tree_grunt__oakheart"
	var issues: Array[String] = []
	cmd.validate(issues)
	assert_eq(issues.size(), 0, "a valid command (%s)" % [issues])
	assert_eq(StoryGrowth.pending(s), [], "Growth 2 of 3: no evolution is due on its own")
	assert_true(StoryController.run_script([cmd]), "the script runs")
	assert_true(await _await_until(func() -> bool: return not _screens.is_empty(), 60), "the story beat offers it anyway")
	if _screens.is_empty():
		return
	(_screens[0] as EvolutionScreen).confirm()
	(_screens[0] as EvolutionScreen).dismiss()
	(_screens[0] as EvolutionScreen).dismiss()
	assert_true(await _await_until(func() -> bool: return not StoryController.is_script_running(), 60), "the script finishes")
	assert_eq(s.member("tree_grunt").character_id, "oakheart", "the member evolved past its Growth trigger")
