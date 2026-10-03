extends GutTest

## TRAVEL BETWEEN THE BUILT-OUT TOWNS, booted for real (OverworldScene.tscn as the current scene):
## Oakvale -> the Mossway -> River Crossing -> Crownhaven -> the Sparse Forest -> Woodland Town and back, each hop a real
## step onto the exit tile of the shipped content, plus the road stubs that stay closed for now
## (Farm Hamlet, Deepwood Village, the Hidden Thieves Guild, Frostpeak, Mountain Base, the Badlands, Beach Village). Content checks
## (layout, props, people) live in test_overworld_content.gd.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_story_towns_travel/"

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


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(area: String, cell: Vector3i, facing: String) -> OverworldController:
	if not StoryController.has_session():
		StoryController.new_journey(1)
		StoryFixture.past_opening(StoryController.state())
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


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _step(ow: OverworldController, dir: Vector2i) -> void:
	ow.try_step(dir)
	await _frames(4)


## Read every dialogue through (bounded in frames).
func _drain(ow: OverworldController, max_frames: int = 600) -> void:
	for i in range(max_frames):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			d.skip()
			continue
		if not StoryController.is_script_running():
			return


func test_crownhaven_west_gate_leads_through_the_sparse_forest_to_woodland_town_and_back() -> void:
	var ow := await _boot("crownhaven", Vector3i(1, 13, 0), "west")
	var s: StoryState = StoryController.state()
	await _step(ow, Vector2i(-1, 0))
	assert_eq(s.location_area(), "sparse_forest", "the west gate opens on the Sparse Forest")
	assert_eq(s.location_cell(), Vector3i(26, 6, 0), "at its east end")
	ow = await _boot("sparse_forest", Vector3i(1, 6, 0), "west")
	assert_eq(ow.area.area_id, &"sparse_forest", "the Sparse Forest boots")
	assert_not_null(ow.actor("alder"), "the woodsman is in his clearing")
	await _step(ow, Vector2i(-1, 0))
	assert_eq(s.location_area(), "woodland_town", "its west end leads to Woodland Town")
	assert_eq(s.location_cell(), Vector3i(26, 12, 0), "arriving on the east road")
	ow = await _boot("woodland_town", s.location_cell(), "west")
	assert_eq(ow.area.area_id, &"woodland_town", "Woodland Town boots")
	assert_not_null(ow.actor("hale"), "the Warden is on his post")
	assert_not_null(ow.actor("wardens_lodge"), "the Lodge stands")
	await _drain(ow)
	assert_true(s.has_flag("woodland.arrived"), "the first visit's arrival scene played")
	# Back out the east end of the road, and through the forest to the city.
	ow = await _boot("woodland_town", Vector3i(26, 12, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "sparse_forest", "the east road returns to the Sparse Forest")
	ow = await _boot("sparse_forest", Vector3i(26, 6, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "crownhaven", "and the forest to Crownhaven")
	assert_eq(s.location_cell(), Vector3i(1, 13, 0), "outside the west gate")


func test_the_west_gate_is_held_until_the_opening_is_over() -> void:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	StoryFixture.sent_off(s)
	var ow := await _boot("crownhaven", Vector3i(1, 13, 0), "west")
	await _step(ow, Vector2i(-1, 0))
	assert_eq(s.location_area(), "crownhaven", "the warden bars the west road during the opening")
	await _drain(ow)


func test_the_road_home_runs_south_over_the_old_bridge() -> void:
	var ow := await _boot("mossway", Vector3i(32, 6, 0), "east")
	var s: StoryState = StoryController.state()
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "river_crossing", "the Mossway's east end opens on River Crossing")
	assert_eq(s.location_cell(), Vector3i(1, 14, 0), "on the Mossway road")
	ow = await _boot("river_crossing", Vector3i(11, 1, 0), "north")
	assert_not_null(ow.actor("hobb"), "the toll-keeper keeps the bridge")
	await _drain(ow)
	await _step(ow, Vector2i(0, -1))
	assert_eq(s.location_area(), "crownhaven", "the King's road north ends at Crownhaven")
	assert_eq(s.location_cell(), Vector3i(15, 27, 0), "outside the south gate")
	ow = await _boot("crownhaven", Vector3i(15, 28 - 1, 0), "south")
	await _step(ow, Vector2i(0, 1))
	assert_eq(s.location_area(), "river_crossing", "and the south gate's road leads back over the river")
	assert_eq(s.location_cell(), Vector3i(11, 1, 0), "onto the King's road")


func test_roads_not_yet_open_turn_you_back() -> void:
	for spec in [
		["oakvale", Vector3i(1, 12, 0), Vector2i(-1, 0), "the Farm Hamlet track"],
		["oakvale_ruins", Vector3i(1, 12, 0), Vector2i(-1, 0), "the Farm Hamlet track (after the raid)"],
		["woodland_town", Vector3i(1, 12, 0), Vector2i(-1, 0), "the road to Deepwood Village"],
		["woodland_town", Vector3i(4, 22, 0), Vector2i(0, 1), "the south trail"],
		["woodland_town", Vector3i(17, 1, 0), Vector2i(0, -1), "the north trail to Frostpeak"],
		["crownhaven", Vector3i(9, 1, 0), Vector2i(0, -1), "the Mountain Road"],
		["crownhaven", Vector3i(28, 13, 0), Vector2i(1, 0), "the Redrock road"],
		["crownhaven", Vector3i(28, 17, 0), Vector2i(1, 0), "the coast road from the harbour gate"],
		["river_crossing", Vector3i(22, 14, 0), Vector2i(1, 0), "the coast road from River Crossing"],
	]:
		StoryController.end_session()
		var ow := await _boot(spec[0], spec[1], "south")
		var s: StoryState = StoryController.state()
		await _drain(ow)
		await _step(ow, spec[2])
		assert_eq(s.location_area(), spec[0], "%s stays in %s" % [spec[3], spec[0]])
		assert_true(StoryController.is_script_running() or ow.dialogue().root_control().visible,
			"%s explains itself" % spec[3])
		await _drain(ow)
