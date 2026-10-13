extends Node

## Screenshots of THE REGIONS PAST THE HEARTLANDS (docs/screenshots/regions_beyond/). Run the scene (not
## headless -- it needs a renderer):
##   godot --path . --resolution 1280x720 res://dev_scripts/regions_beyond_shots.tscn
## Shots: Beach Village (Eloi's longhouse, the piers), riding the sea, Frostpeak asleep, the inn's beds,
## the dream, Redrock, the hooded figure in the Red Desert, the cave's dead end, the hideout. Journeys go
## to a scratch save dir.

const OUT := "res://docs/screenshots/regions_beyond/"
const SAVE_DIR := "user://regions_beyond_shots/"
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
	var open: Array = OPENING + ["world.beach_road_open", "world.frostpeak_open", "world.badlands_open"]
	await _shot_at(open, "beach_village", Vector3i(19, 8, 0), "north", "beach_village.png")
	var rider: Array = open + ["beach.eloi_beaten", "fieldmove.tideride"]
	await _shot_at(rider, "beach_village", Vector3i(20, 15, 0), "east", "beach_riding.png", true)
	await _shot_at(open, "frostpeak_village", Vector3i(11, 12, 0), "north", "frostpeak_asleep.png")
	await _shot_at(open, "frostpeak_inn", Vector3i(6, 5, 0), "north", "frostpeak_inn_beds.png")
	await _shot_at(open + ["frostpeak.dreaming"], "frostpeak_dream", Vector3i(12, 10, 0), "north", "frostpeak_dream.png")
	await _shot_at(open, "redrock_village", Vector3i(12, 12, 0), "north", "redrock_village.png")
	await _shot_at(open, "red_desert", Vector3i(10, 3, 0), "south", "red_desert_figure.png")
	await _shot_at(open, "badlands_cave", Vector3i(7, 3, 0), "north", "cave_dead_end.png")
	await _shot_at(open + ["badlands.hideout_open"], "badlands_hideout", Vector3i(7, 11, 0), "north", "hideout.png")
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	get_tree().quit()


func _shot_at(flags: Array, area: String, cell: Vector3i, facing: String, file: String, ride: bool = false) -> void:
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
		var m: StoryPartyMember = s.add_member("tree_grunt", "", 6, 16)
		if ride:
			m.learn_field_move("tideride")
	s.on_area_changed()
	s.set_location(area, cell, facing)
	_ow = (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	add_child(_ow)
	await _frames(30)
	await get_tree().create_timer(TOAST_WAIT_S).timeout
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("[regions_beyond_shots] saved %s" % file)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
