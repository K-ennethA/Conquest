extends GutTest

## TRAVEL BETWEEN THE BUILT-OUT TOWNS, booted for real (OverworldScene.tscn as the current scene):
## Oakvale -> the Mossway (River Crossing) -> Crownhaven -> Woodland Town and back, each hop a real
## step onto the exit tile of the shipped content, plus the road stubs that stay closed for now
## (Farm Hamlet, Deepwood Village, the Hidden Thieves Guild, the Mountain Pass). Content checks
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


func test_crownhaven_north_gate_leads_to_woodland_town_and_back() -> void:
	var ow := await _boot("crownhaven", Vector3i(9, 1, 0), "north")
	var s: StoryState = StoryController.state()
	await _step(ow, Vector2i(0, -1))
	assert_eq(s.location_area(), "woodland_town", "the north exit leads to Woodland Town")
	assert_eq(s.location_cell(), Vector3i(26, 12, 0), "arriving on the east road")
	ow = await _boot("woodland_town", s.location_cell(), "west")
	assert_eq(ow.area.area_id, &"woodland_town", "Woodland Town boots")
	assert_not_null(ow.actor("hale"), "the Warden is on his post")
	assert_not_null(ow.actor("wardens_lodge"), "the Lodge stands")
	await _drain(ow)
	assert_true(s.has_flag("woodland.arrived"), "the first visit's arrival scene played")
	# Back out the east end of the road.
	ow = await _boot("woodland_town", Vector3i(26, 12, 0), "east")
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "crownhaven", "the east road returns to Crownhaven")
	assert_eq(s.location_cell(), Vector3i(9, 1, 0), "outside the north gate")


func test_the_north_gate_is_held_until_the_opening_is_over() -> void:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	StoryFixture.sent_off(s)
	var ow := await _boot("crownhaven", Vector3i(9, 1, 0), "north")
	await _step(ow, Vector2i(0, -1))
	assert_eq(s.location_area(), "crownhaven", "the warden bars the north road during the alert")
	await _drain(ow)


func test_the_full_road_from_the_mossway_to_the_forest() -> void:
	var ow := await _boot("mossway", Vector3i(32, 6, 0), "east")
	var s: StoryState = StoryController.state()
	await _step(ow, Vector2i(1, 0))
	assert_eq(s.location_area(), "crownhaven", "the Mossway's east end opens on Crownhaven's west gate")
	assert_eq(s.location_cell(), Vector3i(1, 13, 0), "outside the gate")


func test_roads_not_yet_open_turn_you_back() -> void:
	for spec in [
		["oakvale", Vector3i(1, 12, 0), "oakvale", "the Farm Hamlet track"],
		["woodland_town", Vector3i(1, 12, 0), "woodland_town", "the road to Deepwood Village"],
		["woodland_town", Vector3i(4, 22, 0), "woodland_town", "the south trail to the Thieves Guild"],
		["crownhaven", Vector3i(28, 13, 0), "crownhaven", "the east road to the Mountain Pass"],
	]:
		StoryController.end_session()
		var step_dir := Vector2i(-1, 0)
		if spec[3].contains("south"):
			step_dir = Vector2i(0, 1)
		elif spec[3].contains("east"):
			step_dir = Vector2i(1, 0)
		var ow := await _boot(spec[0], spec[1], "west")
		var s: StoryState = StoryController.state()
		await _step(ow, step_dir)
		assert_eq(s.location_area(), spec[2], "%s stays in %s" % [spec[3], spec[2]])
		assert_true(StoryController.is_script_running() or ow.dialogue().root_control().visible,
			"%s explains itself" % spec[3])
		await _drain(ow)
