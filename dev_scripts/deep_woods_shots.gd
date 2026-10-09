extends Node

## Screenshots of THE DEEP WOODS (docs/screenshots/deep_woods/). Run the scene (not headless -- it
## needs a renderer):
##   godot --path . --resolution 1280x720 res://dev_scripts/deep_woods_shots.tscn
## Shots: Deepwood Village (Nyra by her lodge, Lyra on the road), the maze's first room (the LIGHTS at
## its right exit, north), room 2's gate tree between the lights (east), room 3 (tall grass, a trainer,
## the nook's tree), and the heart of the wood with Eldroot. Journeys go to a scratch save dir.

const OUT := "res://docs/screenshots/deep_woods/"
const SAVE_DIR := "user://deep_woods_shots/"
const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"
const TOAST_WAIT_S := 9.0
const OPENING := ["opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony", "opening.starter_received",
	"key.bonding_shard", "opening.attack", "opening.researcher_taken", "opening.raiders_fled", "opening.chase",
	"opening.allies_met", "opening.ruins_seen", "opening.first_fight_won", "opening.complete", "act1.find_rowan"]

var _ow: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	StorySaveManager.set_save_dir(SAVE_DIR)
	StoryController.scene_changes_enabled = false
	await _frames(3)
	var open: Array = OPENING + ["world.deepwood_open"]
	await _shot_at(open, "deepwood_village", Vector3i(16, 9, 0), "north", "deepwood_village.png")
	await _shot_at(open, "deepwood_village", Vector3i(15, 12, 0), "east", "deepwood_lyra.png")
	var depths: Array = open + ["deepwood.nyra_beaten", "fieldmove.treefell", "world.depths_of_the_wood_open",
		"deepwood.treefell_learned"]
	await _shot_at(depths, "depths_of_the_wood", Vector3i(9, 4, 0), "north", "maze_room1_lights.png")
	await _shot_at(depths, "depths_of_the_wood_2", Vector3i(13, 8, 0), "east", "maze_room2_gate_tree.png")
	await _shot_at(depths, "depths_of_the_wood_2", Vector3i(5, 8, 0), "west", "maze_room2_dark_wrong_way.png")
	await _shot_at(depths, "depths_of_the_wood_3", Vector3i(9, 12, 0), "north", "maze_room3_forest.png")
	await _shot_at(depths, "depths_of_the_wood_heart", Vector3i(9, 6, 0), "north", "heart_eldroot.png")
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	get_tree().quit()


func _shot_at(flags: Array, area: String, cell: Vector3i, facing: String, file: String) -> void:
	if _ow != null and is_instance_valid(_ow):
		_ow.queue_free()
		_ow = null
		await _frames(2)
	StoryController.end_session()
	StoryController.new_journey(0)
	var s: StoryState = StoryController.state()
	for f in flags:
		s.set_flag(String(f), 1)
	if s.capped_count() == 0:
		s.add_member("tree_grunt", "", 6, 10)
	s.on_area_changed()
	s.set_location(area, cell, facing)
	_ow = (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	add_child(_ow)
	await _frames(30)
	# Let the session's quest toasts fade (they cover the right of the screen).
	await get_tree().create_timer(TOAST_WAIT_S).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("[deep_woods_shots] saved %s" % file)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
