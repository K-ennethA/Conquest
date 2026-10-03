extends Node

## Screenshots of ENTERABLE BUILDINGS (docs/screenshots/interiors/). Run the scene (not headless --
## it needs a renderer):
##   godot --path . --resolution 1280x720 res://dev_scripts/interior_shots.tscn
## Shots: a door marker on a facade (the Royal Workshop), an interior (the hero's home) and the
## Royal Workshop inside, with Professor Elias and the starter options during the ceremony.

const OUT := "res://docs/screenshots/interiors/"
const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"

var _ow: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	StoryController.scene_changes_enabled = false
	await _frames(3)
	await _shot_at(["opening.sent_off", "opening.arrived_crownhaven"], "crownhaven", Vector3i(24, 9, 0), "north",
		"door_workshop.png")
	await _shot_at(["opening.sent_off"], "oakvale", Vector3i(3, 7, 0), "north", "door_home.png")
	await _shot_at(["opening.sent_off"], "oakvale_home", Vector3i(5, 5, 0), "north", "interior_home.png")
	await _shot_at(["opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony"], "crownhaven_workshop",
		Vector3i(6, 4, 0), "north", "workshop_elias.png")
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
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
	s.on_area_changed()
	s.set_location(area, cell, facing)
	_ow = (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	add_child(_ow)
	await _frames(30)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("[interior_shots] saved %s" % file)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
