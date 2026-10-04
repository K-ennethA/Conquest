extends Node

## Screenshots of the WORLD MAP / QUEST TRACKING UI (docs/screenshots/world_map/). Run the scene
## (not headless -- it needs a renderer), one shot set per run:
##   godot --path . --resolution 1280x720 res://dev_scripts/world_map_shots.tscn -- desktop
##   godot --path . --resolution 1536x1024 res://dev_scripts/world_map_shots.tscn -- align
##   godot --path . --resolution 1600x720 res://dev_scripts/world_map_shots.tscn -- phone
##   godot --path . --resolution 1280x720 res://dev_scripts/world_map_shots.tscn -- hud
## "align" draws every place (secrets too) over the full painting with its name, to check each
## map_pos against the painting's labels.

const OUT := "res://docs/screenshots/world_map/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var mode: String = "desktop"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		mode = String(args[0])
	await _frames(3)
	match mode:
		"align":
			await _align()
		"phone":
			await _phone()
		"hud":
			await _hud()
		_:
			await _desktop()
	get_tree().quit()


func _state() -> StoryState:
	var s := StoryState.new()
	s.add_member("tree_grunt")
	for f in ["opening.sent_off", "opening.arrived_crownhaven", "opening.ceremony", "opening.starter_received",
			"opening.attack", "opening.ruins_seen", "opening.first_fight_won", "opening.complete", "act1.find_rowan",
			"act1.met_rowan", "rival.met"]:
		s.set_flag(f)
	for a in ["oakvale", "oakvale_ruins", "mossway", "river_crossing", "crownhaven"]:
		s.mark_visited(a)
	s.set_location("crownhaven", Vector3i(15, 20, 0), "south")
	s.respawn = {"area_id": "river_crossing", "entry": "shrine"}
	s.tracked_quest = "rival_lark"
	return s


func _desktop() -> void:
	var jm := JourneyMenu.new()
	add_child(jm)
	jm.open(_state())
	await _frames(2)
	jm.show_map()
	await _frames(2)
	jm.world_map().grab_focus()
	await _frames(6)
	_shot("map_desktop.png")
	jm.world_map().show_roads = true
	jm.world_map().focus_location("crownhaven", 2.4)
	await _frames(6)
	_shot("map_zoomed_roads.png")
	jm.set_map_mode(JourneyMenu.MAP_MODE_LIST)
	await _frames(4)
	_shot("map_places_list.png")
	jm.show_quests()
	await _frames(4)
	_shot("quests_all.png")
	jm.set_quest_filter(QuestLog.FILTER_SIDE)
	await _frames(4)
	_shot("quests_side.png")


func _phone() -> void:
	# A 20:9 phone at the MobileDisplay clamp: ~914 x 411 logical.
	get_tree().root.content_scale_factor = 1.75
	await _frames(2)
	var jm := JourneyMenu.new()
	add_child(jm)
	jm.open(_state())
	await _frames(2)
	jm.show_map()
	await _frames(3)
	jm.world_map().grab_focus()
	await _frames(6)
	_shot("map_phone.png")
	jm.world_map().select("crownhaven")
	jm.world_map().zoom_by(2.0)
	await _frames(6)
	_shot("map_phone_zoomed.png")


func _align() -> void:
	var s := _state()
	var atlas := WorldAtlas.load_default()
	for l in atlas.locations:
		if l.secret:
			s.set_flag(l.open_flag)
	var v := WorldMapView.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	v.setup(atlas, s, QuestLog.map_pins(s))
	v.card().visible = false
	await _frames(2)
	v.card().visible = false
	var labels := Control.new()
	labels.set_anchors_preset(Control.PRESET_FULL_RECT)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(labels)
	for l in atlas.locations:
		var t := Label.new()
		t.text = String(l.id)
		t.add_theme_font_size_override("font_size", 13)
		t.add_theme_color_override("font_color", Color(1, 1, 0.4))
		t.add_theme_color_override("font_outline_color", Color.BLACK)
		t.add_theme_constant_override("outline_size", 4)
		t.position = v.map_to_view(l.map_pos) + Vector2(12, 4)
		labels.add_child(t)
	await _frames(6)
	v.card().visible = false
	await _frames(2)
	_shot("map_alignment.png")


func _hud() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.22, 0.32, 0.2)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var hud := OverworldHUD.new()
	add_child(hud)
	var s := _state()
	var e: Dictionary = QuestLog.tracked_entry(s)
	hud.set_tracked_quest(e, "Crownhaven", true)
	hud.quest_toast({"kind": QuestTracker.STARTED, "title": "Trouble on the Mossway", "category": "side",
		"objective": "Cross the plank bridge on the Mossway."})
	hud.quest_toast({"kind": QuestTracker.ADVANCED, "title": "A Fellow Tester", "category": "side",
		"objective": "Win or lose, finish your first duel with Lark."})
	hud.quest_toast({"kind": QuestTracker.COMPLETED, "title": "Grow Stronger", "category": "main", "objective": ""})
	await _frames(30)
	_shot("hud_tracker_toasts.png")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _shot(file: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("[world_map_shots] saved ", OUT + file)
