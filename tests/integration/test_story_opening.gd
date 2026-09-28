extends GutTest

## THE STORY OPENING, played end to end headlessly (docs/design/DECISIONS.md #12-#21; content
## from game/overworld/build/build_story_content.gd) through the real OverworldScene and a real
## booted GameWorld for the first fight:
##
##   new journey -> Oakvale (home): the mother's send-off -> the Mossway (no creature: the grass
##   hint, no encounters) -> Crownhaven: arrival -> the Researcher's ceremony (the starter joins,
##   the bonding shard) -> the raid (raiders appear, the Researcher is taken, the Sergeant runs
##   up) -> the chase to Oakvale's ruins -> the mother's fate + the Sergeant's offer -> the FIRST
##   FIGHT (tactical; the Sergeant's creature as a guest ally) -> win -> Continue Journey -> the
##   aftermath: opening.complete + the Act 1 hook, the cairn, the road open again.
##
## Scene changes are OFF on StoryController: every warp / battle hand-off records its target and
## the test boots the next scene itself. Animations off: walks, emotes and bubbles are instant.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")
const TEMP_DIR := "user://test_story_opening/"
const TEMP_BATTLE_SAVE := "user://test_story_opening_battle.json"
const FIRST_FIGHT_MAP := "res://game/overworld/content/battles/ow_oakvale_ashes.tres"
const STARTER := "tree_grunt"
const GUEST := "gem_knight"

var _guard
var _scene: Node = null
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
	_teardown()
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


# --- scenes -----------------------------------------------------------------------------

func _mount(packed: PackedScene) -> Node:
	_teardown()
	var n: Node = packed.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(n)
	get_tree().current_scene = n
	_scene = n
	return n


func _teardown() -> void:
	if _scene != null and is_instance_valid(_scene):
		get_tree().current_scene = _prev_scene
		if _scene.get_parent() != null:
			_scene.get_parent().remove_child(_scene)
		_scene.free()
	_scene = null


## Boot the overworld where the journey stands (or at [param cell] of [param area]).
func _boot(area: String = "", cell: Vector3i = Cells.INVALID, facing: String = "south") -> OverworldController:
	var s: StoryState = StoryController.state()
	if area != "":
		if area != s.location_area():
			s.on_area_changed()
		s.set_location(area, cell, facing)
	var ow := _mount(OVERWORLD_SCENE) as OverworldController
	await _frames(3)
	return ow


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _step(ow: OverworldController, dir: Vector2i) -> bool:
	var ok: bool = ow.try_step(dir)
	await _frames(3)
	return ok


## Read every line, answer every choice with [param pick], until the script ends, a battle is
## staged or the script warped away. [param each_frame] observes the scene as it plays.
func _drain(ow: OverworldController, pick: int = 0, each_frame: Callable = Callable(), max_frames: int = 1500) -> void:
	var start_area: String = StoryController.state().location_area()
	for i in range(max_frames):
		await get_tree().process_frame
		if each_frame.is_valid():
			each_frame.call()
		if StoryController.active_request() != null:
			return
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			if d.is_choosing():
				d.advance_clock(100.0)
				if d.choices_visible():
					d.choose(pick)
			else:
				d.skip()
			continue
		if not StoryController.is_script_running():
			return
		if StoryController.state().location_area() != start_area:
			return


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


func _player_side(u) -> bool:
	return u.get_parent() != null and u.get_parent().name == "Player1"


# --- THE OPENING --------------------------------------------------------------------------

func test_the_opening_plays_end_to_end() -> void:
	# 1. A NEW JOURNEY: at home in Oakvale, with no creature.
	assert_true(bool(StoryController.new_journey(1)["success"]), "a new journey starts")
	var s: StoryState = StoryController.state()
	assert_eq(s.location_area(), "oakvale", "in Oakvale")
	assert_eq(s.location_cell(), Vector3i(3, 6, 0), "on the hero's doorstep")
	assert_eq(s.party.size(), 0, "with no creature of your own")

	# 2. THE SEND-OFF plays on the first boot.
	var ow := await _boot()
	assert_true(StoryController.is_script_running(), "the opening scene starts at once")
	await _drain(ow)
	assert_true(s.has_flag("opening.sent_off"), "your mother sends you to Crownhaven")
	assert_false(StoryController.is_script_running(), "and hands you the controls")

	# 3. OUT THE EAST ROAD, onto the Mossway.
	ow = await _boot("oakvale", Vector3i(22, 9, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "mossway", "the road east leads onto the Mossway")
	ow = await _boot()
	await _step(ow, Vector2i(1, 0))
	await _step(ow, Vector2i(1, 0))
	await _step(ow, Vector2i(1, 0))
	assert_true(StoryController.is_script_running(), "the grass rustles (the no-partner hint)")
	await _drain(ow)
	s.grace_steps = 0
	ow = await _boot("mossway", Vector3i(4, 2, 0), "east")
	for i in range(12):
		await _step(ow, Vector2i(1, 0) if (i / 4) % 2 == 0 else Vector2i(-1, 0))
	assert_false(StoryController.is_script_running(), "and no wild creature challenges a traveller with no partner")
	assert_false(ow.actor("bram").visible, "Bram is not on the road yet")

	# 4. INTO CROWNHAVEN.
	ow = await _boot("mossway", Vector3i(32, 6, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "crownhaven", "the Mossway's east end is Crownhaven's west gate")
	ow = await _boot()
	assert_eq(ow.hud.area_ribbon().get_node("Text").text, "CROWNHAVEN", "the ribbon names the town")
	await _drain(ow)
	assert_true(s.has_flag("opening.arrived_crownhaven"), "the arrival narration plays once")

	# 5. THE CEREMONY and THE RAID.
	ow = await _boot("crownhaven", Vector3i(24, 9, 0), "north")
	assert_eq(ow.entity_at(Vector3i(24, 8, 0)).id, &"linnea", "the Researcher waits at her workshop")
	var seen := {"raiders": false, "starter": false}
	var watch := func() -> void:
		if not is_instance_valid(ow):
			return
		var r: OverworldActor = ow.actor("raider_captain")
		if r != null and r.visible:
			seen["raiders"] = true
		var st: OverworldActor = ow.actor("starter")
		if st != null and st.visible:
			seen["starter"] = true
	assert_true(ow.interact(), "talk to the Researcher")
	await _drain(ow, 0, watch)
	assert_true(seen["starter"], "the starter appears at the ceremony")
	assert_true(seen["raiders"], "raiders storm the workshop")
	assert_eq(s.party.size(), 1, "the ceremony gives you your FIRST CREATURE")
	if s.party.size() == 1:
		assert_eq(s.party[0].character_id, STARTER, "the starter (%s)" % STARTER)
	for f in ["key.bonding_shard", "opening.starter_received", "opening.attack", "opening.researcher_taken",
			"opening.raiders_fled", "opening.chase"]:
		assert_true(s.has_flag(f), "flag %s is set" % f)
	assert_eq(s.location_area(), "oakvale_ruins", "the chase ends in Oakvale's ruins")
	assert_eq(s.location_cell(), Vector3i(21, 9, 0), "on the east road")
	assert_eq(s.respawn, {"area_id": "oakvale_ruins", "entry": "wayshrine"}, "a whiteout now wakes you in the ruins")
	assert_true(StorySaveManager.has_save(1), "the warp autosaved")

	# 6. THE RUINS: your mother's fate, the Sergeant's offer -> the FIRST FIGHT.
	ow = await _boot()
	assert_eq(ow.area.area_id, &"oakvale_ruins", "the burned village")
	await _drain(ow, 0)
	assert_true(s.has_flag("opening.ruins_seen"), "the fate scene played")
	assert_true(s.has_flag("opening.rowan_arrived"), "the Sergeant arrived")
	var req: BattleRequest = StoryController.active_request()
	assert_not_null(req, "choosing to fight stages the first battle")
	if req == null:
		return
	assert_eq(req.kind, BattleRequest.KIND_TACTICAL, "a TACTICAL battle")
	assert_eq(req.encounter_id, "story.opening.first_fight", "the first fight")
	assert_eq(req.map_path, FIRST_FIGHT_MAP, "on the mill-road board")
	assert_eq(GameSettings.selected_squad, [STARTER], "your creature fights")
	assert_true(StoryController.is_battle_active(), "a story battle is armed")

	# 7. THE BATTLE on a real GameWorld: win it.
	_clear_globals()
	_mount(WORLD_SCENE)
	var up: bool = await _await_until(func() -> bool:
		return TurnSystemManager.has_active_turn_system() and _party_units().size() == 1)
	assert_true(up, "the first fight boots with your starter tagged")
	if not up:
		return
	var guests: Array = []
	var foes: Array = []
	for u in CombatServices.board().all_units():
		if _player_side(u) and not u.has_meta(StoryBattleBridge.MEMBER_META):
			guests.append(u)
		elif not _player_side(u):
			foes.append(u)
	assert_eq(guests.size(), 1, "the Sergeant's creature fights beside you as a guest")
	if guests.size() == 1:
		assert_eq(String(guests[0].character_resource.character_id), GUEST, "his Geode")
	assert_eq(foes.size(), 3, "against the raiders' rear guard")
	for u in foes:
		u.take_damage(99999)
	var won: bool = await _await_until(func() -> bool: return _resolved.size() > 0)
	assert_true(won, "the battle resolves")
	assert_eq(_resolved, ["victory"], "in victory")
	await get_tree().process_frame
	var screens: Array = _scene.find_children("*", "GameOverScreen", true, false)
	assert_false(screens.is_empty(), "the end screen shows")
	if screens.is_empty():
		return
	var buttons: Array[Button] = (screens[0] as GameOverScreen).mode_action_buttons()
	assert_eq(buttons.size(), 1, "one story action")
	assert_eq(buttons[0].text, "Continue Journey", "Continue Journey")
	buttons[0].pressed.emit()
	assert_null(StoryController.active_request(), "the battle is disarmed")
	assert_true(s.has_flag("opening.first_fight_won"), "the win is recorded")

	# 8. THE AFTERMATH: back in the ruins, the paused script resumes on the victory.
	_clear_globals()
	ow = await _boot()
	assert_eq(ow.area.area_id, &"oakvale_ruins", "back in the ruins where you stood")
	await _drain(ow)
	assert_true(s.has_flag("opening.complete"), "the opening is complete")
	assert_true(s.has_flag("act1.find_rowan"), "and the Sergeant's hook sets up Act 1")
	assert_false(StoryController.is_script_running(), "the aftermath ran to its end")
	ow.refresh_world()
	assert_true(ow.actor("cairn").visible, "a cairn stands for the hero's mother")
	assert_false(ow.actor("rowan").visible, "the Sergeant has ridden for Crownhaven")
	assert_true((StorySaveManager.peek(1)["flags"] as Dictionary).has("opening.complete"), "and the journey saved it")

	# 9. The road is open again, and the Mossway's trainer is out.
	ow = await _boot("oakvale_ruins", Vector3i(22, 9, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "mossway", "the ruins' east road leads back to the Mossway")
	ow = await _boot()
	assert_true(ow.actor("bram").visible, "Bram now watches the road")

	# 10. The Act 1 hook: the Sergeant waits at the Crownhaven barracks.
	ow = await _boot("crownhaven", Vector3i(7, 10, 0), "north")
	await _drain(ow)
	assert_true(ow.interact(), "talk to the Sergeant at the barracks")
	await _drain(ow)
	assert_true(s.has_flag("act1.met_rowan"), "he signs you onto his detail")
