extends GutTest

## QUEST TRACKING + THE WORLD MAP, wired for real (docs/STORY_MODE.md "World map" / "Quest
## tracking"): StoryController's transition events (quiet on load, news on a flag), the pin saved
## through set_tracked_quest, the overworld HUD tracker + quest toasts and the objective marker,
## Journey -> Quests (filters, Track, Show on map), Journey -> Map ([WorldMapView]: markers, states,
## secrets, keyboard navigation, zoom), and the quest editor panel's load / edit / save round trip.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const QuestEditorPanel := preload("res://addons/quest_editor/quest_editor_panel.gd")
const TEMP_DIR := "user://test_quest_tracking_live/"

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEMP_DIR))
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	# The booted area prewarms its neighbours in the background: settle that before the next test.
	StoryController.prewarmer().finish(StoryController)
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	QuestLog.set_definitions(null)
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _boot() -> OverworldController:
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await _frames(3)
	return w as OverworldController


## A journey past the opening standing in Crownhaven, adopted as a LOADED session (baseline taken).
func _crownhaven_journey() -> StoryState:
	var s := StoryState.new()
	StoryFixture.past_opening(s)
	s.set_location("crownhaven", Vector3i(15, 20, 0), "south")
	s.mark_visited("oakvale")
	s.mark_visited("crownhaven")
	s.respawn = {"area_id": "river_crossing", "entry": "shrine"}
	StoryController.begin_session_with(s, 0)
	return s


# --- StoryController -------------------------------------------------------------------------

func test_events_are_quiet_on_load_and_report_progress() -> void:
	var s := _crownhaven_journey()
	assert_eq(StoryController.poll_quest_events(), [], "a loaded journey is not news")
	s.set_flag("rival.met")
	var ev: Array = StoryController.poll_quest_events()
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["kind"]), QuestTracker.ADVANCED)
	assert_eq(String(ev[0]["id"]), "rival_lark")
	assert_eq(StoryController.poll_quest_events(), [], "said once")


func test_pinning_goes_through_the_session_and_into_the_save() -> void:
	var s := StoryState.new()
	StoryFixture.past_opening(s)
	s.set_location("crownhaven", Vector3i(15, 20, 0), "south")
	StoryController.begin_session_with(s, 1)
	assert_false(StoryController.set_tracked_quest("no_such_quest"), "only an active quest can be pinned")
	assert_true(StoryController.set_tracked_quest("crown_cup"))
	assert_eq(String(StoryController.tracked_quest_entry()["id"]), "crown_cup")
	var loaded: Dictionary = StorySaveManager.load_state(1)
	assert_true(bool(loaded.get("success", false)), "saved")
	assert_eq((loaded["state"] as StoryState).tracked_quest, "crown_cup", "the pin is in the save")
	assert_true(StoryController.set_tracked_quest(""), "unpin")
	assert_eq(s.tracked_quest, "")


# --- The overworld --------------------------------------------------------------------------

func test_hud_tracker_toasts_and_objective_marker() -> void:
	var s := _crownhaven_journey()
	var ow: OverworldController = await _boot()
	assert_not_null(ow, "boots")
	assert_eq(ow.hud.toast_count(), 0, "no quest toasts on load")
	assert_true(ow.hud.tracker_visible(), "the tracker shows")
	var tracked: Dictionary = QuestLog.tracked_entry(s)
	assert_eq(ow.hud.tracked_quest_id(), String(tracked["id"]))
	assert_eq(ow.hud.tracker_objective(), String(tracked["objective"]))
	# Pin the rival quest: its objective is in Crownhaven, so the HUD says "Here" and Lyra wears
	# the objective marker.
	s.tracked_quest = "rival_lark"
	ow.refresh_quest_tracker()
	assert_eq(ow.hud.tracked_quest_id(), "rival_lark")
	assert_eq(ow.hud.tracker_place(), "Here", "the objective is in this area")
	assert_eq(ow.objective_marker_actor(), "lyra", "Lyra is marked")
	s.set_flag("rival.met")
	await _frames(2)
	assert_eq(ow.hud.toast_count(), 1, "the new objective is toasted")
	assert_true(ow.hud.tracker_objective().contains("first duel"), "and tracked")


# --- Journey -> Quests / Map ---------------------------------------------------------------

func test_quests_page_filters_track_and_show_on_map() -> void:
	var s := StoryState.new()
	StoryFixture.past_opening(s)
	s.set_location("crownhaven", Vector3i(15, 20, 0), "south")
	var jm := JourneyMenu.new()
	add_child_autofree(jm)
	jm.open(s)
	await _frames(1)
	jm.show_quests()
	assert_not_null(jm.quest_card("road_to_crownhaven"), "All lists finished quests too")
	jm.set_quest_filter(QuestLog.FILTER_SIDE)
	await _frames(1)
	assert_null(jm.quest_card("road_to_crownhaven"), "Side hides the main quests")
	assert_not_null(jm.quest_card("crown_cup"), "and shows the open side quests")
	jm.set_quest_filter(QuestLog.FILTER_COMPLETED)
	await _frames(1)
	assert_not_null(jm.quest_card("road_to_crownhaven"), "Completed")
	assert_null(jm.quest_card("crown_cup"))
	jm.set_quest_filter(QuestLog.FILTER_SIDE)
	await _frames(1)
	var track: Button = jm.quest_card("crown_cup").find_child("TrackButton", true, false)
	track.pressed.emit()
	assert_eq(s.tracked_quest, "crown_cup", "Track pins it (session-less: straight onto the state)")
	assert_not_null(jm.quest_card("crown_cup").find_child("TrackedChip", true, false), "and marks it")
	var show: Button = jm.quest_card("crown_cup").find_child("ShowOnMapButton", true, false)
	assert_false(show.disabled, "the cup has a place")
	show.pressed.emit()
	await _frames(2)
	assert_true(jm.is_map_open(), "Show on map opens the map")
	assert_eq(jm.world_map().selected_id(), "crownhaven", "on the objective's place")
	assert_gt(jm.world_map().zoom(), 1.0, "zoomed in")
	assert_true(jm.world_map().has_focus(), "the map has focus")


func test_world_map_markers_states_and_navigation() -> void:
	var s := StoryState.new()
	StoryFixture.past_opening(s)
	s.set_location("crownhaven", Vector3i(15, 20, 0), "south")
	s.mark_visited("oakvale")
	s.mark_visited("crownhaven")
	s.respawn = {"area_id": "river_crossing", "entry": "shrine"}
	var jm := JourneyMenu.new()
	add_child_autofree(jm)
	jm.open(s)
	await _frames(1)
	jm.show_map()
	await _frames(2)
	assert_eq(jm.map_mode(), JourneyMenu.MAP_MODE_MAP, "the painting by default")
	assert_not_null(jm.find_child("Place_crownhaven", true, false), "the place list is still built")
	var map: WorldMapView = jm.world_map()
	assert_true(map.is_visible_in_tree())
	assert_false(map.has_marker("thieves_guild"), "the secret place stays off the map")
	var here: Dictionary = map.marker_info("crownhaven")
	assert_true(bool(here["here"]) and bool(here["visited"]), "you are here")
	assert_eq(String(here["kind"]), "city")
	assert_true(bool(map.marker_info("river_crossing")["rest"]), "the Wayshrine")
	assert_false(bool(map.marker_info("river_crossing")["visited"]), "...not visited yet")
	assert_true(bool(map.marker_info("frostpeak_village")["closed"]), "a closed road")
	assert_false((map.marker_info("crownhaven")["quests"] as Array).is_empty(), "quests point at the capital")
	assert_eq(map.selected_id(), "crownhaven", "the selection starts where you are")
	var name_l: Label = map.card().find_child("PlaceName", true, false)
	assert_eq(name_l.text, "Crownhaven", "the card names it")
	# Keyboard: Down steps toward the coast; Left from Crownhaven lands in the woods.
	map.grab_focus()
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	map._gui_input(down)
	var south: String = map.selected_id()
	assert_ne(south, "crownhaven", "moved")
	assert_gt((map.marker_info(south)["pos"] as Vector2).y, (here["pos"] as Vector2).y, "south of the capital")
	map.select("crownhaven")
	var left := InputEventAction.new()
	left.action = &"ui_left"
	left.pressed = true
	map._gui_input(left)
	assert_lt((map.marker_info(map.selected_id())["pos"] as Vector2).x, (here["pos"] as Vector2).x, "west of it")
	# Zoom stays within its limits.
	map.set_zoom(100.0)
	assert_eq(map.zoom(), map.max_zoom(), "clamped high")
	map.set_zoom(0.01)
	assert_eq(map.zoom(), WorldMapView.MIN_ZOOM, "clamped low")
	# The list toggle keeps the old place cards one press away.
	jm.set_map_mode(JourneyMenu.MAP_MODE_LIST)
	assert_false(map.visible)
	assert_true((jm.find_child("PlaceList", true, false) as Control).visible)


func test_secret_place_appears_once_found() -> void:
	var s := StoryState.new()
	s.set_flag("world.thieves_guild_open")
	var map := WorldMapView.new()
	add_child_autofree(map)
	map.setup(WorldAtlas.load_default(), s, [])
	assert_true(map.has_marker("thieves_guild"), "found -> on the map")


# --- The quest editor ----------------------------------------------------------------------

func test_quest_editor_round_trips_the_file() -> void:
	var path: String = TEMP_DIR + "quests.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(QuestLog.DATA_PATH))
	f.close()
	var panel: Control = QuestEditorPanel.new()
	panel.data_path = path
	add_child_autofree(panel)
	await _frames(1)
	panel.data_path = path
	panel.reload()
	var n: int = panel.defs.size()
	assert_eq(n, QuestLog.definitions().size(), "loads every quest")
	assert_not_null(panel.find_child("QuestTree", true, false), "the grouped list")
	var at: int = panel.add_quest("main")
	assert_eq(String(panel.defs[at]["category"]), "main")
	assert_true(panel.dirty)
	panel.defs[at]["steps"][0]["flag"] = "opening.sent_off"
	panel.defs[at]["steps"][0]["text"] = "A new objective."
	assert_eq(panel.save(), OK)
	var back: Array = QuestLog.parse(FileAccess.get_file_as_string(path))
	assert_eq(back.size(), n + 1, "saved")
	assert_eq(FileAccess.get_file_as_string(path), QuestLog.to_json(back), "as canonical JSON")
	panel.select_quest(at)
	panel.move_quest(-1)
	assert_eq(panel.selected_index(), at - 1, "moved up within its group")
	panel.remove_quest()
	assert_eq(panel.defs.size(), n)
	var issues: Array = panel.validate()
	assert_eq(QuestValidator.errors(issues), [], "the shipped quests stay clean")
	assert_gt(panel.show_story_flow().size(), 0)
