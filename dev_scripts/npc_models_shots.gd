extends Node

## Screenshots of the NPC PLACEHOLDER MODELS ([NpcLooks]; docs/screenshots/npc_models/). Run the
## scene (not headless -- it needs a renderer):
##   godot --path . --resolution 1280x720 res://dev_scripts/npc_models_shots.tscn
## Shots: Oakvale at the start (the hero's mother in Lyra's clone, villagers and a child in Wren's),
## Crownhaven's square after the opening (and the same view with the knob off: the old figures),
## its east side (Merchant Oda, Sister Odalys, Lady Merrow), the Royal Workshop during the raid
## (the raiders, tinted) and Woodland Town (Huntress Ferra, Herbalist Ilse).

const OUT := "res://docs/screenshots/npc_models/"
const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"
const OPENING := ["opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony", "opening.starter_received",
	"key.bonding_shard", "opening.attack", "opening.researcher_taken", "opening.raiders_fled", "opening.chase",
	"opening.allies_met", "opening.ruins_seen", "opening.first_fight_won", "opening.complete", "act1.find_rowan"]
const RAID := ["opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony", "opening.starter_received",
	"key.bonding_shard", "opening.attack"]

var _ow: Node = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	StoryController.scene_changes_enabled = false
	await _frames(3)
	await _shot_at(["opening.sent_off"], "oakvale", Vector3i(6, 8, 0), "south", "oakvale.png")
	await _shot_at(OPENING, "crownhaven", Vector3i(16, 13, 0), "south", "crownhaven.png")
	await _shot_at(OPENING, "crownhaven", Vector3i(16, 13, 0), "south", "crownhaven_figures_before.png", false)
	await _shot_at(OPENING, "crownhaven", Vector3i(22, 12, 0), "south", "crownhaven_east.png")
	await _shot_at(RAID, "crownhaven_workshop", Vector3i(6, 4, 0), "south", "workshop_raid.png")
	await _shot_at(OPENING, "woodland_town", Vector3i(6, 9, 0), "south", "woodland_town.png")
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	get_tree().quit()


func _shot_at(flags: Array, area: String, cell: Vector3i, facing: String, file: String, models: bool = true) -> void:
	if _ow != null and is_instance_valid(_ow):
		_ow.queue_free()
		_ow = null
		await _frames(2)
	StoryController.end_session()
	StoryController.new_journey(0)
	StoryController.ruleset().npc_models_enabled = models
	var s: StoryState = StoryController.state()
	for f in flags:
		s.set_flag(String(f), 1)
	if s.party.is_empty() and not flags.is_empty():
		s.add_member("tree_grunt", "", 6, 10)
	s.on_area_changed()
	s.set_location(area, cell, facing)
	_ow = (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	add_child(_ow)
	await _frames(40)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("[npc_models_shots] saved %s" % file)
	StoryController.ruleset().npc_models_enabled = true


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
