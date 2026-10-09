extends GutTest

## WHERE THE HERO BOOTS ([method OverworldGrid.resolve_start]): a saved / arrival cell he cannot
## stand on -- out of the area's bounds (an area that shrank since the save: the old 24x30 Depths of
## the Wood is a 19x17 maze room now), impassable terrain, or a blocking entity -- puts him at the
## area's default entry (its first standable entry point, with that entry's facing) instead. Never a
## crash, never wedged in a wall.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_area_boot_start/"
const DEPTHS := "depths_of_the_wood"

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
	StoryController.state().set_flag("world.depths_of_the_wood_open", 1)


func after_each() -> void:
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _area(id: String) -> OverworldAreaResource:
	return StoryController.load_area(id)


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
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


# --- The rule (pure) ------------------------------------------------------------------------------

func test_a_standable_cell_is_kept() -> void:
	var a := _area(DEPTHS)
	var g := OverworldGrid.build(a, StoryController.state())
	var r: Dictionary = g.resolve_start(a, Vector3i(9, 9, 0), "west")
	assert_false(bool(r["moved"]), "a cell he can stand on is where he boots")
	assert_eq(r["cell"], Vector3i(9, 9, 0))
	assert_eq(String(r["facing"]), "west", "facing kept")


func test_an_out_of_bounds_or_blocked_cell_falls_back_to_the_default_entry() -> void:
	var a := _area(DEPTHS)
	var s: StoryState = StoryController.state()
	var g := OverworldGrid.build(a, s)
	var entry: Dictionary = a.entry(a.entry_ids()[0])
	# The old 24x30 Depths: a save from its south track is off the new 19x17 room.
	var r: Dictionary = g.resolve_start(a, Vector3i(12, 24, 0), "north")
	assert_true(bool(r["moved"]), "off the map: moved")
	assert_eq(String(r["reason"]), "out_of_bounds")
	assert_eq(r["cell"], entry["cell"], "to the default entry")
	assert_eq(String(r["facing"]), String(entry["facing"]), "facing as that entry says")
	# Inside the wall of trees.
	var tree := Vector3i(0, 0, 0)
	assert_false(g.is_terrain_passable(tree), "the corner is forest")
	r = g.resolve_start(a, tree, "east")
	assert_true(bool(r["moved"]) and String(r["reason"]) == "blocked", "impassable: moved")
	assert_eq(r["cell"], entry["cell"])
	# On a blocking entity (the old signpost).
	var sign_cell: Vector3i = a.entity("maze_sign").cell
	assert_false(g.is_walkable(sign_cell), "the signpost blocks its cell")
	r = g.resolve_start(a, sign_cell, "east")
	assert_eq(r["cell"], entry["cell"], "a blocked cell: the default entry")
	assert_true(g.is_walkable(r["cell"]), "where he can stand")


func test_with_no_standable_entry_the_nearest_standable_cell_is_used() -> void:
	var a := (_area(DEPTHS).duplicate() as OverworldAreaResource)
	a.entry_points = {"bad": {"cell": [0, 0, 0], "facing": "south"}}
	var g := OverworldGrid.build(a, StoryController.state())
	var r: Dictionary = g.resolve_start(a, Vector3i(40, 40, 0), "north")
	assert_true(bool(r["moved"]))
	assert_true(g.is_walkable(r["cell"]), "somewhere standable: %s" % str(r["cell"]))
	var empty := OverworldGrid.new()
	r = empty.resolve_start(null, Vector3i(3, 3, 0), "north")
	assert_false(bool(r["moved"]), "nothing standable at all: unchanged, no crash")


# --- The real boot --------------------------------------------------------------------------------

func test_an_old_save_off_the_new_room_boots_at_its_entry() -> void:
	var a := _area(DEPTHS)
	var entry: Dictionary = a.entry(a.entry_ids()[0])
	var ow := await _boot(DEPTHS, Vector3i(12, 24, 0), "north")
	assert_not_null(ow)
	assert_eq(ow.player.cell, entry["cell"], "the hero stands at the room's entry")
	var s: StoryState = StoryController.state()
	assert_eq(s.location_cell(), entry["cell"], "and the journey's location says so (the next save is sane)")
	assert_eq(s.location_facing(), String(entry["facing"]))
	assert_true(ow.try_step(Vector2i(0, -1)), "he can walk on")


func test_a_blocked_saved_cell_boots_at_the_entry() -> void:
	var a := _area(DEPTHS)
	var entry: Dictionary = a.entry(a.entry_ids()[0])
	var ow := await _boot(DEPTHS, Vector3i(0, 0, 0), "east")
	assert_eq(ow.player.cell, entry["cell"], "out of the wall of trees, at the entry")
	ow = await _boot(DEPTHS, a.entity("maze_sign").cell, "east")
	assert_eq(ow.player.cell, entry["cell"], "off the signpost's cell, at the entry")
