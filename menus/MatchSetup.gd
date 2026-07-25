extends Control

class_name MatchSetup

## Unified pre-battle SETUP screen. Replaces the old TurnSystemSelection + MapSelection +
## ArenaSetupScreen as three separate steps with one screen: a map list + preview on the
## LEFT and a reusable [MatchConfigPanel] config column on the RIGHT. What the Start button
## launches depends on [member requested_mode], set by the caller before it changes here:
##
##   * [constant MatchConfigPanel.MODE_SKIRMISH] -- Solo vs AI. Map + Turn System + AI
##       Difficulty. Start stages the map and goes to Character Select (which loads the
##       battle itself), exactly as MapSelection did.
##   * [constant MatchConfigPanel.MODE_ARENA]    -- Solo roguelite. Turn System + Run Length.
##       The map list is hidden (Arena picks its own compact maps each round); Start
##       duplicates arena_solo.tres, writes rounds + turn system, and stages the run on
##       ArenaController before going to Character Select, exactly as ArenaSetupScreen did.
##   * [constant MatchConfigPanel.MODE_LOCAL]    -- Local hot-seat versus. Map + Turn System.
##       Start stages the map and goes to Character Select.
##
## The mode is carried in a STATIC var so it survives the scene change AND a Back trip from
## Character Select (which returns here without re-picking the mode). Every dependency is
## null-guarded; a missing autoload or ruleset shows an inline message instead of crashing.

const BASE_RULESET_PATH := "res://game/arena/rulesets/arena_solo.tres"
const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const SOLO_MODE_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"
const MP_MODE_SELECT_SCENE := "res://menus/MultiplayerModeSelection.tscn"

## The variant to build, set by the caller (SoloModeSelect / MultiplayerModeSelection)
## before change_scene. Static so it persists across the scene load and a Back trip from
## Character Select. Defaults to Skirmish so the screen is never left in an undefined mode.
## (Value literal rather than MatchConfigPanel.MODE_SKIRMISH so this static initializer
## never depends on another class's load order.)
static var requested_mode: String = "skirmish"

var _mode: String = MatchConfigPanel.MODE_SKIRMISH

# --- Map data (ported from MapSelection) ------------------------------------
var _available_maps: Array[String] = []
var _map_resources: Array[MapResource] = []
var _current_selected_map: String = ""

# --- Live node refs ---------------------------------------------------------
var _map_list: ItemList = null
var _map_name_label: Label = null
var _map_desc_label: Label = null
var _map_details_label: Label = null
var _config_panel: MatchConfigPanel = null
var _start_btn: Button = null
var _message_label: Label = null


func _ready() -> void:
	_mode = requested_mode
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()
	if _uses_map_list():
		_load_available_maps()


func _uses_map_list() -> bool:
	return _mode != MatchConfigPanel.MODE_ARENA


func _title_text() -> String:
	match _mode:
		MatchConfigPanel.MODE_ARENA:
			return "ARENA RUN"
		MatchConfigPanel.MODE_LOCAL:
			return "LOCAL VERSUS"
		_:
			return "SKIRMISH"


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 48.0
	page.offset_right = -48.0
	page.offset_top = 28.0
	page.offset_bottom = -28.0
	page.add_theme_constant_override("separation", 12)
	add_child(page)

	var title := Label.new()
	title.text = _title_text()
	page.add_child(title)
	MenuTheme.style_title(title, 34)

	var subtitle := Label.new()
	subtitle.text = "Configure your match, then begin"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 20)
	page.add_child(main)

	main.add_child(_build_left_pane())
	main.add_child(_build_right_pane())

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", Color("d87a4a"))
	_message_label.visible = false
	page.add_child(_message_label)

	page.add_child(_build_actions())


## LEFT: map list + preview for map modes; a read-only note for Arena.
func _build_left_pane() -> Control:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.58
	left.add_theme_constant_override("separation", 8)

	if not _uses_map_list():
		var note_panel := PanelContainer.new()
		note_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var note := Label.new()
		note.text = "Arena picks its own compact maps\neach round.\n\nDraft augments between fights and\nsurvive as long as you can."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		note_panel.add_child(note)
		left.add_child(note_panel)
		return left

	var list_label := Label.new()
	list_label.text = "Available Maps"
	left.add_child(list_label)

	_map_list = ItemList.new()
	_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_list.size_flags_stretch_ratio = 0.5
	_map_list.item_selected.connect(_on_map_selected)
	_map_list.item_activated.connect(_on_map_activated)
	left.add_child(_map_list)

	var preview := PanelContainer.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_stretch_ratio = 0.5
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	preview.add_child(margin)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	margin.add_child(pv)

	_map_name_label = Label.new()
	_map_name_label.text = "Select a map"
	_map_name_label.add_theme_font_size_override("font_size", 20)
	_map_name_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	pv.add_child(_map_name_label)

	_map_desc_label = Label.new()
	_map_desc_label.text = "Choose a map from the list to see its details."
	_map_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.add_child(_map_desc_label)

	_map_details_label = Label.new()
	_map_details_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(_map_details_label)

	left.add_child(preview)
	return left


## RIGHT: the reusable config column.
func _build_right_pane() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.42
	right.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "MATCH SETTINGS"
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	right.add_child(heading)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	_config_panel = MatchConfigPanel.new()
	_config_panel.custom_minimum_size = Vector2(320.0, 220.0)
	_config_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_config_panel)
	_config_panel.configure(_mode)

	right.add_child(panel)
	return right


func _build_actions() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	row.add_child(back)

	_start_btn = Button.new()
	_start_btn.text = "Start Run" if _mode == MatchConfigPanel.MODE_ARENA else "Start Match"
	_start_btn.theme_type_variation = &"SelectedButton"  # solid gold, prominent
	_start_btn.custom_minimum_size = Vector2(240.0, 48.0)
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.pressed.connect(_on_start_pressed)
	# Map modes need a selected map first; arena can start immediately.
	_start_btn.disabled = _uses_map_list()
	row.add_child(_start_btn)

	return row


# --- Map listing (ported from MapSelection) ---------------------------------

func _load_available_maps() -> void:
	_available_maps.clear()
	_map_resources.clear()
	if _map_list == null:
		return
	_map_list.clear()

	# Drafts (Inactive) ARE included: this is the local / single-player picker, and you must
	# be able to play-test a map you just built (mirrors MapSelection).
	_available_maps = MapLoader.get_available_maps(true)
	if _available_maps.is_empty():
		var default_map := MapLoader.create_default_map()
		MapLoader.save_map(default_map, "default_skirmish")
		_available_maps = MapLoader.get_available_maps(true)

	for map_path in _available_maps:
		var map_resource := load(map_path) as MapResource
		if map_resource == null:
			push_error("MatchSetup: Failed to load map: " + map_path)
			continue
		_map_resources.append(map_resource)
		var display_name := map_resource.map_name
		if display_name.is_empty():
			display_name = map_path.get_file().get_basename()
		if not map_resource.is_active():
			display_name += "  (draft)"
		_map_list.add_item(display_name)

	if _map_list.get_item_count() > 0:
		_map_list.select(0)
		_on_map_selected(0)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= _map_resources.size():
		return
	_current_selected_map = _available_maps[index]
	_display_map_info(_map_resources[index])
	if _start_btn != null:
		_start_btn.disabled = false


func _on_map_activated(index: int) -> void:
	_on_map_selected(index)
	_on_start_pressed()


func _display_map_info(map_resource: MapResource) -> void:
	if map_resource == null:
		return
	var info := map_resource.get_display_info()
	if _map_name_label != null:
		_map_name_label.text = info.get("name", "Unknown Map")
	if _map_desc_label != null:
		_map_desc_label.text = info.get("description", "No description available")
	if _map_details_label != null:
		var details: Array = []
		details.append("Size: " + info.get("size", "Unknown"))
		details.append("Players: " + str(info.get("players", 0)) + "/" + str(info.get("max_players", 2)))
		details.append("Difficulty: " + info.get("difficulty", "Normal"))
		details.append("Type: " + info.get("map_type", "Skirmish"))
		if not String(info.get("author", "")).is_empty():
			details.append("Author: " + info.get("author", ""))
		details.append("Units: " + str(info.get("total_spawns", 0)))
		details.append("Tiles: " + str(info.get("total_tiles", 0)))
		_map_details_label.text = "\n".join(details)


# --- Start / Back -----------------------------------------------------------

func _on_start_pressed() -> void:
	if _config_panel == null:
		return
	_config_panel.apply_settings()

	if _mode == MatchConfigPanel.MODE_ARENA:
		_start_arena()
		return
	_start_map_match()


func _start_map_match() -> void:
	if _current_selected_map.is_empty():
		_show_message("Pick a map first.")
		return
	GameSettings.set_selected_map(_current_selected_map)
	# Clear any Arena ruleset staged earlier so a map launch is never mistaken for a run.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _start_arena() -> void:
	var base: Resource = load(BASE_RULESET_PATH)
	if base == null:
		_show_message("Arena ruleset is missing -- cannot start a run.")
		return
	var arena := get_node_or_null("/root/ArenaController")
	if arena == null or not arena.has_method("prepare_run"):
		_show_message("Arena mode is not available.")
		return
	# Never mutate the shared .tres -- deep-duplicate, then write the chosen settings.
	var rs: Resource = base.duplicate(true)
	if rs == null:
		_show_message("Could not prepare the run.")
		return
	rs.total_rounds = _config_panel.get_run_length()
	rs.turn_system = _config_panel.get_turn_system()
	# Stage the ruleset and go pick a squad; Character Select calls begin_pending_run(),
	# which starts the run (and changes to the GameWorld scene) with the chosen units.
	arena.prepare_run(rs)
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_back_pressed() -> void:
	# Discard any staged arena ruleset so it can't leak into a later launch.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	if _mode == MatchConfigPanel.MODE_LOCAL:
		get_tree().change_scene_to_file(MP_MODE_SELECT_SCENE)
	else:
		get_tree().change_scene_to_file(SOLO_MODE_SELECT_SCENE)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true


# --- Keyboard ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	match event.keycode:
		KEY_ESCAPE:
			_on_back_pressed()
		KEY_ENTER, KEY_KP_ENTER:
			if _start_btn != null and not _start_btn.disabled:
				_on_start_pressed()
		KEY_UP:
			_move_map_selection(-1)
		KEY_DOWN:
			_move_map_selection(1)


func _move_map_selection(delta: int) -> void:
	if _map_list == null or _map_list.get_item_count() == 0:
		return
	var selected := _map_list.get_selected_items()
	var current := selected[0] if selected.size() > 0 else 0
	var next := clampi(current + delta, 0, _map_list.get_item_count() - 1)
	if next != current:
		_map_list.select(next)
		_on_map_selected(next)
