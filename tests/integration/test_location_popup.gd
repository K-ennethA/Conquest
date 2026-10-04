extends GutTest

## THE LOCATION POPUP (the classic-Pokemon "you are in X" chip): a small, NON-BLOCKING name chip
## in a corner of the HUD when the hero enters a different named place. It must never pause the
## walk: no script runs, the controls stay free, and the hero can step while it shows. Interiors
## and quick hops back and forth do not get one (PlaceAnnouncer).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_location_popup/"

var _guard
var _world: Node = null
var _prev_scene: Node = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(area: String, cell: Vector3i, facing: String = "south") -> OverworldController:
	var s: StoryState = StoryController.state()
	if area != s.location_area():
		s.on_area_changed()
	s.set_location(area, cell, facing)
	_teardown()
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func test_entering_a_town_shows_a_popup_that_never_blocks_the_walk() -> void:
	var ow := await _boot("oakvale", Vector3i(10, 11, 0), "north")
	var popup := ow.hud.area_popup()
	assert_not_null(popup, "a new place gets its name chip")
	assert_eq(popup.get_node("Text").text, "OAKVALE", "naming the town")
	assert_eq(popup.mouse_filter, Control.MOUSE_FILTER_IGNORE, "the chip takes no clicks")
	assert_gt(popup.anchor_left, 0.5, "tucked into the right-hand corner, not the middle of the screen")
	assert_false(StoryController.is_script_running(), "no script runs for it")
	assert_false(ow.is_input_blocked(), "the controls are free")
	assert_false(get_tree().paused, "the tree is not paused")
	var before: Vector3i = ow.player.cell
	assert_true(ow.try_step(Vector2i(0, -1)), "the hero steps while the popup is up")
	await get_tree().process_frame
	assert_ne(ow.player.cell, before, "and actually moves")
	assert_not_null(ow.hud.area_popup(), "the popup is still showing, out of the way")


func test_a_building_interior_gets_no_popup() -> void:
	var ow := await _boot("crownhaven", Vector3i(24, 7, 0), "north")
	assert_not_null(ow.hud.area_popup(), "the city is named")
	ow = await _boot("crownhaven_workshop", Vector3i(6, 6, 0), "north")
	assert_null(ow.hud.area_popup(), "a room inside it is not")
	ow = await _boot("crownhaven", Vector3i(24, 7, 0), "south")
	assert_null(ow.hud.area_popup(), "and stepping back out does not name the city again")


func test_hopping_over_an_area_edge_and_back_does_not_repeat_the_popup() -> void:
	var ow := await _boot("oakvale_ruins", Vector3i(22, 9, 0), "east")
	assert_not_null(ow.hud.area_popup(), "the first visit names Oakvale")
	ow = await _boot("mossway", Vector3i(1, 6, 0), "east")
	assert_not_null(ow.hud.area_popup(), "a different place is named")
	ow = await _boot("oakvale_ruins", Vector3i(22, 9, 0), "west")
	assert_null(ow.hud.area_popup(), "straight back is not named again")


func test_arriving_in_a_town_never_plays_a_scene() -> void:
	# The once-only arrival narrations are gone: arriving only records the visit.
	for pair in [["river_crossing", Vector3i(1, 14, 0), "river_crossing.arrived"],
			["crownhaven", Vector3i(15, 27, 0), "opening.arrived_crownhaven"],
			["woodland_town", Vector3i(26, 12, 0), "woodland.arrived"]]:
		StoryController.state().clear_flag(pair[2])
		var ow := await _boot(pair[0], pair[1], "east")
		assert_false(StoryController.is_script_running(), "%s: no scene on arrival" % pair[0])
		assert_false(ow.is_input_blocked(), "%s: the controls are free" % pair[0])
		assert_true(StoryController.state().has_flag(pair[2]), "%s: the visit is still recorded" % pair[0])
