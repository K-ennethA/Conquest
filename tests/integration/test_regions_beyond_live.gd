extends GutTest

## THE NEW REGIONS' MECHANICS, booted for real (OverworldScene.tscn): RIDING the sea move out onto the
## water at Beach Village and stepping ashore (DECISIONS.md #43), a boot on the water resuming the ride,
## the shore's hint without a rider, and Frostpeak's SLEEPERS (#95: dozing on their feet, lying in bed).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_regions_beyond_live/"
## Beach Village: a sand cell on the beach with the sea just south of it.
const SHORE := Vector3i(4, 12, 0)
const SEA := Vector3i(4, 13, 0)

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


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## A journey past the opening; [param rider] = a creature that has learned the sea move.
func _journey(rider: bool, flags: Array = []) -> StoryState:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	StoryFixture.past_opening(s)
	for f in flags:
		s.set_flag(String(f), 1)
	if rider:
		s.set_flag("fieldmove.tideride", 1)
		s.add_member("tree_grunt", "", 6, 14).learn_field_move("tideride")
	return s


func _boot(area: String, cell: Vector3i, facing: String) -> OverworldController:
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
	await _frames(2)
	return w as OverworldController


func _drain(ow: OverworldController, max_frames: int = 400) -> void:
	for i in range(max_frames):
		await get_tree().process_frame
		var d: StoryDialogue = ow.dialogue() if is_instance_valid(ow) else null
		if d != null and d.root_control().visible:
			d.skip()
			continue
		if not StoryController.is_script_running():
			return


func test_riding_out_onto_the_sea_and_stepping_back_ashore() -> void:
	_journey(true)
	var ow := await _boot("beach_village", SHORE, "south")
	await _drain(ow)
	assert_false(ow.try_step(Vector2i(0, 1)), "on foot the sea stops you")
	assert_eq(ow.player.cell, SHORE, "still on the sand")
	assert_true(ow.hud.prompt_text().ends_with("Ride"), "the shore offers the ride (%s)" % ow.hud.prompt_text())
	await ow.start_ride(&"tideride", SEA)
	assert_not_null(ow.riding(), "riding")
	assert_eq(ow.player.cell, SEA, "out on the water")
	assert_true(ow.player.is_mounted(), "on the creature's back")
	assert_true(ow.try_step(Vector2i(-1, 0)), "the water carries you on")
	await _frames(4)
	assert_eq(ow.player.cell, SEA + Vector3i(-1, 0, 0))
	assert_true(ow.riding() != null, "still riding on the water")
	assert_true(ow.try_step(Vector2i(1, 0)), "and back")
	await _frames(4)
	assert_true(ow.try_step(Vector2i(0, -1)), "back up onto the sand")
	await _frames(4)
	assert_null(ow.riding(), "stepping ashore ends the ride")
	assert_false(ow.player.is_mounted(), "the mount is gone")
	assert_false(ow.grid.is_walkable(SEA), "and the water blocks again")


func test_a_boot_on_the_water_resumes_the_ride() -> void:
	_journey(true)
	var ow := await _boot("beach_village", SEA, "south")
	assert_eq(ow.player.cell, SEA, "the hero stays out on the water")
	assert_not_null(ow.riding(), "riding")
	assert_true(ow.player.is_mounted(), "mounted")


func test_without_a_rider_the_water_is_not_a_place_to_stand() -> void:
	_journey(false)
	var ow := await _boot("beach_village", SEA, "south")
	assert_null(ow.riding(), "no ride without the move")
	assert_ne(ow.player.cell, SEA, "booted ashore instead")
	ow = await _boot("beach_village", SHORE, "south")
	await _drain(ow)
	assert_true(ow.interact(), "Confirm at the water's edge says something")
	assert_true(StoryController.is_script_running() or ow.dialogue().root_control().visible, "a hint")
	await _drain(ow)
	assert_null(ow.riding(), "and nothing more")


func test_frostpeak_sleepers_doze_and_lie_in_bed() -> void:
	_journey(false)
	var ow := await _boot("frostpeak_inn", Vector3i(6, 6, 0), "north")
	var keeper: OverworldActor = ow.actor("fp_innkeeper")
	var traveller: OverworldActor = ow.actor("fp_traveller")
	assert_true(keeper.is_asleep() and not keeper.is_lying(), "the innkeeper dozes on their feet")
	assert_true(keeper.zz_visible(), "z Z")
	assert_true(traveller.is_asleep() and traveller.is_lying(), "the traveller lies in bed")
	assert_gt(traveller.model().position.y, 0.3, "up on the mattress")
	_journey(false, ["frostpeak.awake"])
	ow = await _boot("frostpeak_inn", Vector3i(6, 6, 0), "north")
	keeper = ow.actor("fp_innkeeper")
	assert_false(keeper.is_asleep(), "awake once the town wakes")
	assert_false(keeper.zz_visible(), "no z Z")
	assert_false(ow.actor("fp_traveller").visible, "the traveller is up and gone")


func test_the_post_game_blizzard_shows_on_the_overworld() -> void:
	_journey(false)
	var ow := await _boot("frostpeak_village", Vector3i(11, 12, 0), "north")
	assert_eq(ow.area_weather(), "clear", "a clear day before the post-game")
	_journey(false, ["postgame.hidden_depths_awakened"])
	ow = await _boot("snowy_peaks", Vector3i(11, 20, 0), "north")
	assert_eq(ow.area_weather(), "blizzard", "the Snowy Peaks under a blizzard (DECISIONS.md #99)")


func test_stepping_onto_the_ice_slides_you_until_something_stops_you() -> void:
	# DECISIONS.md #102: the Frozen Cave's first floor -- one step north from the ground strip at (4, 10)
	# onto the ice slides the hero up the column to the wall at the top (4, 2).
	_journey(false, ["postgame.hidden_depths_awakened"])
	var ow := await _boot("glacier_cave", Vector3i(4, 10, 0), "north")
	await _drain(ow)
	assert_true(ow.try_step(Vector2i(0, -1)), "a step onto the ice")
	for i in range(60):
		await get_tree().process_frame
		if not ow.is_sliding() and not ow.is_moving():
			break
	assert_false(ow.is_sliding(), "the slide ends")
	assert_eq(ow.player.cell, Vector3i(4, 2, 0), "against the wall, far up the ice")
	assert_false(ow.is_input_blocked(), "and you can move again")
