extends Control

class_name MapMakerScene

## In-game Map Maker UI.
##
## Two editing surfaces sit side by side:
##   * LEFT  - a 2D button grid (paint / rect fill / bucket fill / erase / spawn /
##             objective / stairs / link), the tile palette, the spawn-point config,
##             the map metadata (name, author, description, weather, size), the
##             validation list and the save / load / challenge-export controls.
##   * RIGHT - a LIVE 3D preview inside a SubViewport that renders the map with the
##             real tile model scenes (the same way the editor dock and MapGallery
##             do) and the actual character models on spawn points, updating
##             incrementally on every edit.
##
## MULTI-FLOOR (docs/MULTI_FLOOR.md): a floor selector in the header ([ - ] Floor N
## [ + ], or the floor_up / floor_down actions, PgUp / PgDn by default) picks the
## floor being edited. In the 2D grid the floor below shows through ghosted so decks
## line up with what they span; the 3D preview shows every floor up to the edited
## one (like the battle cutaway). On any floor you can paint / erase tiles, place
## spawns, mark STAIRS (a direction; they climb to the next floor) and add explicit
## LINKS (click the from-cell, change floor if needed, click the to-cell; clicking an
## existing link's ends again removes it). The validation list flags spawns on air,
## links / stairs into missing cells and unreachable decks.
##
## All editing state lives in [MapMakerModel] (a pure, tested RefCounted); this class
## only builds the UI, translates input into model calls, and mirrors the result onto
## the two views. The 3D rendering logic is PORTED from addons/map_creator/
## map_creator_dock.gd but reads from the model rather than a MapResource, and uses no
## Editor-only APIs so it runs in the shipped game.
##
## OPENING / BACK: callers open the Map Maker with [method open_from], which records
## where Back / Esc returns to (the main menu's Map Creator entry and the Compendium's
## Map Maker button both use it). Opened any other way, Back goes to the main menu.

## This scene, for [method open_from].
const SCENE_PATH := "res://game/mapmaker/MapMakerScene.tscn"
## Where Back returns when no caller recorded a [member return_scene].
const DEFAULT_BACK_SCENE := "res://menus/MainMenu.tscn"
## Directory player-authored maps are saved to / loaded from, as inert JSON.
const CUSTOM_MAPS_DIR := "user://maps/"

## Scene Back / Esc returns to. Set by [method open_from]; cleared by [method go_back].
## Empty = [constant DEFAULT_BACK_SCENE].
static var return_scene: String = ""

## Editing tools available on the grid.
enum Tool { PAINT, RECT_FILL, BUCKET_FILL, ERASE, SPAWN, OBJECTIVE, STAIRS, LINK }

## Sentinel for "no cell".
const NO_CELL := Vector2i(-1, -1)

## Fallback tint per tile-type string, used only when a palette entry / resource has
## no colour of its own. The palette itself comes from TileCatalog (real resources).
const TILE_COLORS := {
	"NORMAL": Color(0.4, 0.8, 0.3),
	"DIFFICULT_TERRAIN": Color(0.6, 0.5, 0.3),
	"WATER": Color(0.3, 0.5, 0.9),
	"WALL": Color(0.4, 0.4, 0.4),
	"SPECIAL": Color(0.8, 0.6, 0.9),
	"LAVA": Color(0.9, 0.3, 0.1),
	"ICE": Color(0.7, 0.9, 1.0),
	"SWAMP": Color(0.4, 0.5, 0.3),
	"SACRED_GROUND": Color(1.0, 0.9, 0.6),
	"CORRUPTED": Color(0.5, 0.2, 0.5),
}

## Player-slot marker colours (shared with the 2D badge and the 3D marker).
const PLAYER_COLORS := {
	0: Color(0.30, 0.55, 0.95),
	1: Color(0.95, 0.35, 0.30),
	2: Color(0.35, 0.80, 0.45),
	3: Color(0.95, 0.85, 0.35),
	4: Color(0.70, 0.45, 0.90),
	5: Color(0.35, 0.85, 0.85),
	6: Color(0.95, 0.60, 0.30),
	7: Color(0.85, 0.85, 0.85),
}

## Objective marker colour (2D swatch + 3D pillar).
const OBJECTIVE_COLOR := Color(0.95, 0.85, 0.35)

const STAIR_GLYPHS := { "north": "▲", "south": "▼", "east": "▶", "west": "◀" }
const STAIR_DIRS := ["north", "east", "south", "west"]
const LINK_KINDS := ["stairs", "ladder", "ramp"]

## 2D grid cell size. Touch-readiness compromise: 30 -> 38 (still short of the 44px
## hit-target guideline, but a full zoomable canvas -- the real fix -- is a later task;
## this keeps the grid readable on desktop while being less mis-tappable).
const CELL_SIZE := 38

# --- 3D world tuning (ported from the dock) ----------------------------------
const TILE_STEP := 2.0
const TILE_MESH_SIZE := Vector3(1.8, 0.3, 1.8)
const SPAWN_RADIUS := 0.35
const SPAWN_Y := 0.5
const OBJECTIVE_Y := 0.55
const SPAWN_KIND_MARKER_SCALE := {
	"Start": 1.0,
	"Respawn": 1.35,
	"Endless": 1.6,
	"Reinforcement": 0.7,
}
const SPAWN_KIND_INITIALS := {
	"Start": "S",
	"Respawn": "R",
	"Endless": "E",
	"Reinforcement": "F",
}
# Feet-on-tile Y for a spawned character model (mirrors MapLoader.UNIT_GROUND_Y so
# the preview model rests on the tile the way the loaded map places it).
const SPAWN_MODEL_Y := 0.1
# Flat player-colour ground ring under a spawn model, carrying the player/kind info
# the bare model would otherwise lose (the 2D badge + config panel keep the rest).
const SPAWN_RING_Y := 0.16
const SPAWN_RING_HEIGHT := 0.06
const SPAWN_RING_RADIUS := 0.55
# Floating kind-initial billboard height above the spawn cell.
const SPAWN_LABEL_Y := 2.1

var model: MapMakerModel

## Floor being edited (0 = ground).
var current_floor: int = 0

# --- selection / tool state --------------------------------------------------
var _current_tool: int = Tool.PAINT
var _selected_tile_type: String = "NORMAL"
var _selected_tile_path: String = ""
var _selected_tile_id: String = ""
var _current_player_id: int = 0
var _selected_spawn_kind: String = MapResource.SPAWN_KIND_START
var _selected_character_id: String = ""
var _brush_size: int = 1
var _stair_dir: String = "east"
var _link_kind: String = "stairs"
var _link_cost: int = 1
## First click of a link (Cells.INVALID when none pending).
var _link_from: Vector3i = Cells.INVALID

# One entry per palette button: {type_name, resource_path, tile_id, color, display_name}
var _tile_palette_entries: Array[Dictionary] = []

# --- 2D grid state -----------------------------------------------------------
var _grid_width: int = 0
var _grid_height: int = 0
var _cell_buttons: Dictionary = {}  # Vector2i -> Button (shows the edited floor)
var _is_painting: bool = false
var _rect_anchor: Vector2i = NO_CELL
var _rect_hover: Vector2i = NO_CELL

# --- deferred refresh flags (one validation / link rebuild per frame at most) --
var _issues_dirty: bool = false
var _links_dirty: bool = false
var _flush_queued: bool = false

# --- UI references ------------------------------------------------------------
var _width_spin: SpinBox
var _height_spin: SpinBox
var _player_spin: SpinBox
var _brush_spin: SpinBox
var _grid_container: GridContainer
var _grid_title: Label
var _status_label: Label
var _name_edit: LineEdit
var _author_edit: LineEdit
var _desc_edit: TextEdit
var _weather_opt: OptionButton
var _floor_label: Label
var _issues_label: RichTextLabel
var _spawn_kind_option: OptionButton
var _character_option: OptionButton
var _tool_buttons: Dictionary = {}  # Tool -> Button
var _challenge_squad_spin: SpinBox
var _challenge_mode_option: OptionButton
var _challenge_survive_row: HBoxContainer
var _challenge_survive_spin: SpinBox
var _challenge_par_spin: SpinBox
var _export_challenge_btn: Button

## True once the author has typed their own par, after which [method _refresh_export_state]
## stops re-seeding it from the defender count (see [method _seed_par_from_defenders]).
var _challenge_par_touched: bool = false
## Guard so a PROGRAMMATIC par write doesn't look like the author touching the spinbox.
var _seeding_par: bool = false

# --- 3D preview references ----------------------------------------------------
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _floor_roots: Dictionary = {}       # int floor -> Node3D ("Floor_<f>", raised to its height)
var _links_root: Node3D                 # stair + link visuals (FloorDecor.make_link_visual)
var _tile_visuals: Dictionary = {}      # Vector3i -> Node3D
var _spawn_visuals: Dictionary = {}     # Vector3i -> Node3D (holder: model+ring+label, or sphere)
var _spawn_signatures: Dictionary = {}  # Vector3i -> String (skip rebuild when spawn unchanged)
var _objective_meshes: Dictionary = {}  # Vector2i -> MeshInstance3D (ground floor only)
var _world_span: float = TILE_STEP

# Camera orbit state.
var _cam_yaw: float = 0.6
var _cam_pitch: float = 0.95
var _cam_distance: float = 16.0
var _orbiting: bool = false

# --- 3D geometry caches (keyed by path, loaded once) -------------------------
var _tile_resource_cache: Dictionary = {}
var _tile_model_cache: Dictionary = {}
var _type_model_paths: Dictionary = {}
var _type_model_paths_built: bool = false
# character_id (String) -> PackedScene or null. Caches the roster model scene (and the
# "no model" answer) so placing many spawns never re-resolves the same character.
var _character_model_cache: Dictionary = {}


## Open the Map Maker from [param from] (any node of the calling screen); Back / Esc
## will return to [param back_scene] -- or, when that is empty, to the scene
## [param from] belongs to.
static func open_from(from: Node, back_scene: String = "") -> void:
	var back := back_scene
	if back.is_empty() and from != null:
		back = from.scene_file_path
		if back.is_empty() and from.is_inside_tree() and from.get_tree().current_scene != null:
			back = from.get_tree().current_scene.scene_file_path
	return_scene = back
	MenuNav.change_scene(from, SCENE_PATH)


func _ready() -> void:
	if model == null:
		model = MapMakerModel.new(8, 8)
	_load_tile_palette_entries()
	_build_ui()
	_rebuild_grid()
	_build_world_3d()
	_refresh_export_state()
	_refresh_all()


func _input(event: InputEvent) -> void:
	# A left-button RELEASE anywhere closes a paint stroke / commits a rect fill. A
	# per-cell release is unreliable because the pointer is usually over a different
	# cell by the time the button comes up.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if _rect_anchor != NO_CELL:
				_commit_rect_fill(_rect_hover)
			if _is_painting:
				_is_painting = false


func _unhandled_input(event: InputEvent) -> void:
	# Esc / pad B returns to the caller (edits live in the model; saving is explicit) --
	# but not while a text field is being edited. Only ui_cancel (not every "cancel"
	# binding) so a stray letter key can never throw away an unsaved map.
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		var focus := get_viewport().gui_get_focus_owner()
		if not (focus is LineEdit or focus is TextEdit):
			get_viewport().set_input_as_handled()
			go_back()
			return
	if _is_floor_event(event, InputActions.FLOOR_UP, KEY_PAGEUP):
		set_floor(current_floor + 1)
		get_viewport().set_input_as_handled()
	elif _is_floor_event(event, InputActions.FLOOR_DOWN, KEY_PAGEDOWN):
		set_floor(current_floor - 1)
		get_viewport().set_input_as_handled()


## The floor_up / floor_down action (rebindable, gamepad triggers), falling back to
## Page Up / Page Down when the action is not in the InputMap.
func _is_floor_event(event: InputEvent, action: StringName, fallback_key: Key) -> bool:
	if event == null or not event.is_pressed() or event.is_echo():
		return false
	if InputMap.has_action(action):
		return event.is_action_pressed(action)
	return event is InputEventKey and (event as InputEventKey).keycode == fallback_key


## Leave the Map Maker for the screen it was opened from ([member return_scene], else
## the main menu).
func go_back() -> void:
	var target := return_scene if not return_scene.is_empty() else DEFAULT_BACK_SCENE
	return_scene = ""
	if is_inside_tree():
		MenuNav.change_scene(self, target)


# =============================================================================
#  UI construction
# =============================================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Same grove look as the rest of the menus, in a compact size (this is a dense
	# editor: every toolbar must fit a 1280-wide window).
	theme = _compact_theme()

	var bg := ColorRect.new()
	bg.color = MenuTheme.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MenuTheme.SP_M)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", MenuTheme.SP_S)
	margin.add_child(root)

	_build_header(root)

	# Body: authoring column (left) | 3D preview (right).
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.split_offset = 460
	root.add_child(body)

	_build_left_column(body)
	_build_preview_column(body)

	_build_footer(root)


func _build_header(root: VBoxContainer) -> void:
	var header := MenuKit.card()
	root.add_child(header)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", MenuTheme.SP_M)
	header.add_child(bar)

	# Back first, so it is always on screen (Esc too, when no text field is being edited).
	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "< Back"
	back_btn.theme_type_variation = MenuKit.GHOST
	back_btn.tooltip_text = "Back (%s)" % _hint(&"ui_cancel", "Esc")
	back_btn.pressed.connect(go_back)
	bar.add_child(back_btn)

	var title := Label.new()
	title.text = "Map Maker"
	title.add_theme_font_override("font", MenuTheme.heading_font(1))
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# --- Floor selector -------------------------------------------------------
	var floor_tag := MenuKit.section("Floor")
	floor_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(floor_tag)
	var down_btn := Button.new()
	down_btn.name = "FloorDownButton"
	down_btn.text = " - "
	down_btn.tooltip_text = "Edit the floor below (%s)" % _hint(InputActions.FLOOR_DOWN, "PgDn")
	down_btn.pressed.connect(func(): set_floor(current_floor - 1))
	bar.add_child(down_btn)
	_floor_label = _make_label("")
	_floor_label.custom_minimum_size = Vector2(190, 0)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_floor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_floor_label)
	var up_btn := Button.new()
	up_btn.name = "FloorUpButton"
	up_btn.text = " + "
	up_btn.tooltip_text = "Edit the floor above (%s)" % _hint(InputActions.FLOOR_UP, "PgUp")
	up_btn.pressed.connect(func(): set_floor(current_floor + 1))
	bar.add_child(up_btn)


## Status line (left) + key hints (right), always on screen.
func _build_footer(root: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", MenuTheme.SP_XL)
	root.add_child(footer)

	_status_label = MenuKit.label("Ready.", &"DimLabel", true)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status_label)

	footer.add_child(MenuKit.key_hint(
		"%s / %s" % [_key_for(InputActions.FLOOR_UP, false, "PgUp"), _key_for(InputActions.FLOOR_DOWN, false, "PgDn")],
		"%s / %s" % [_key_for(InputActions.FLOOR_UP, true, "RT"), _key_for(InputActions.FLOOR_DOWN, true, "LT")],
		"Floor"))
	footer.add_child(MenuKit.key_hint(
		_key_for(&"ui_cancel", false, "Esc"), _key_for(&"ui_cancel", true, "B"), "Back"))


func _build_left_column(body: HSplitContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(440, 0)
	body.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	_build_metadata_section(col)
	col.add_child(HSeparator.new())
	_build_tools_section(col)
	col.add_child(HSeparator.new())
	_build_palette_section(col)
	col.add_child(HSeparator.new())
	_build_spawn_section(col)
	col.add_child(HSeparator.new())
	_build_grid_section(col)
	col.add_child(HSeparator.new())
	_build_validation_section(col)
	col.add_child(HSeparator.new())
	_build_save_load_section(col)


func _build_metadata_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Map info"))

	var name_row := HBoxContainer.new()
	col.add_child(name_row)
	name_row.add_child(_make_label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.text = model.map_name
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(t: String): model.map_name = t)
	name_row.add_child(_name_edit)

	var author_row := HBoxContainer.new()
	col.add_child(author_row)
	author_row.add_child(_make_label("Author:"))
	_author_edit = LineEdit.new()
	_author_edit.text = model.author
	_author_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_author_edit.text_changed.connect(func(t: String): model.author = t)
	author_row.add_child(_author_edit)

	col.add_child(_make_label("Description:"))
	_desc_edit = TextEdit.new()
	_desc_edit.text = model.description
	_desc_edit.custom_minimum_size = Vector2(0, 48)
	_desc_edit.text_changed.connect(func(): model.description = _desc_edit.text)
	col.add_child(_desc_edit)

	# Battle weather (docs/WEATHER.md): a fixed weather, a dynamic mix, or the map's
	# own schedule/dynamic settings kept as-is.
	var weather_row := HBoxContainer.new()
	col.add_child(weather_row)
	weather_row.add_child(_make_label("Weather:"))
	_weather_opt = OptionButton.new()
	_weather_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weather_opt.item_selected.connect(_on_weather_selected)
	weather_row.add_child(_weather_opt)
	_sync_weather_option()

	var size_row := HBoxContainer.new()
	col.add_child(size_row)
	size_row.add_child(_make_label("Width:"))
	_width_spin = _make_spin(MapResource.MIN_MAP_SIZE, MapResource.MAX_MAP_SIZE, model.width)
	size_row.add_child(_width_spin)
	size_row.add_child(_make_label("Height:"))
	_height_spin = _make_spin(MapResource.MIN_MAP_SIZE, MapResource.MAX_MAP_SIZE, model.height)
	size_row.add_child(_height_spin)
	var resize_btn := Button.new()
	resize_btn.text = "Resize"
	resize_btn.pressed.connect(_on_resize_pressed)
	size_row.add_child(resize_btn)


func _build_tools_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Tools"))
	var group := ButtonGroup.new()

	var row := HBoxContainer.new()
	col.add_child(row)
	_add_tool_button(row, "Paint", Tool.PAINT, group)
	_add_tool_button(row, "Rect", Tool.RECT_FILL, group)
	_add_tool_button(row, "Bucket", Tool.BUCKET_FILL, group)
	_add_tool_button(row, "Erase", Tool.ERASE, group)

	var row2 := HBoxContainer.new()
	col.add_child(row2)
	_add_tool_button(row2, "Spawn", Tool.SPAWN, group)
	_add_tool_button(row2, "Objective", Tool.OBJECTIVE, group)
	_add_tool_button(row2, "Stairs", Tool.STAIRS, group)
	_add_tool_button(row2, "Link", Tool.LINK, group)

	var row3 := HBoxContainer.new()
	col.add_child(row3)
	row3.add_child(_make_label("Brush:"))
	_brush_spin = _make_spin(1, 3, _brush_size)
	_brush_spin.value_changed.connect(func(v: float): _brush_size = int(v))
	row3.add_child(_brush_spin)

	row3.add_child(_make_label("  Stairs climb:"))
	var dir_opt := OptionButton.new()
	for d in STAIR_DIRS:
		dir_opt.add_item("%s %s" % [STAIR_GLYPHS[d], d.capitalize()])
	dir_opt.select(STAIR_DIRS.find(_stair_dir))
	dir_opt.item_selected.connect(func(i: int): _stair_dir = STAIR_DIRS[i])
	row3.add_child(dir_opt)

	var row4 := HBoxContainer.new()
	col.add_child(row4)
	row4.add_child(_make_label("Link:"))
	var kind_opt := OptionButton.new()
	for k in LINK_KINDS:
		kind_opt.add_item(k.capitalize())
	kind_opt.item_selected.connect(func(i: int): _link_kind = LINK_KINDS[i])
	row4.add_child(kind_opt)
	row4.add_child(_make_label("  cost"))
	var cost_spin := _make_spin(1, 5, 1)
	cost_spin.value_changed.connect(func(v: float): _link_cost = int(v))
	row4.add_child(cost_spin)

	_highlight_tool_buttons()


func _build_palette_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Tile palette"))

	var grid := GridContainer.new()
	grid.columns = 3
	col.add_child(grid)

	for i in range(_tile_palette_entries.size()):
		var entry: Dictionary = _tile_palette_entries[i]
		var button := Button.new()
		button.text = str(entry.get("display_name", "Tile"))
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var swatch: Color = _entry_color(entry)
		_apply_swatch(button, swatch)
		button.pressed.connect(_on_palette_selected.bind(i))
		grid.add_child(button)


func _build_spawn_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Spawn / objective"))

	var player_row := HBoxContainer.new()
	col.add_child(player_row)
	player_row.add_child(_make_label("Player slot:"))
	_player_spin = _make_spin(0, 7, 0)
	_player_spin.value_changed.connect(func(v: float): _current_player_id = int(v))
	player_row.add_child(_player_spin)

	var kind_row := HBoxContainer.new()
	col.add_child(kind_row)
	kind_row.add_child(_make_label("Spawn kind:"))
	_spawn_kind_option = OptionButton.new()
	for kind in MapResource.SPAWN_KINDS:
		_spawn_kind_option.add_item(str(kind))
	_spawn_kind_option.selected = 0
	_spawn_kind_option.item_selected.connect(_on_spawn_kind_selected)
	kind_row.add_child(_spawn_kind_option)

	var char_row := HBoxContainer.new()
	col.add_child(char_row)
	char_row.add_child(_make_label("Character:"))
	_character_option = OptionButton.new()
	_character_option.add_item("(none / assigned at match setup)")
	_character_option.set_item_metadata(0, "")
	for character_id in CharacterLibrary.all_ids():
		var id_string: String = String(character_id)
		if id_string.is_empty():
			continue
		var character := CharacterLibrary.get_character(character_id)
		var label: String = id_string
		if character != null and not character.display_name.is_empty():
			label = character.display_name
		_character_option.add_item(label)
		_character_option.set_item_metadata(_character_option.get_item_count() - 1, id_string)
	_character_option.selected = 0
	_character_option.item_selected.connect(_on_character_selected)
	char_row.add_child(_character_option)


func _build_grid_section(col: VBoxContainer) -> void:
	_grid_title = MenuKit.section("Map grid")
	col.add_child(_grid_title)
	col.add_child(MenuKit.label(
		"Drag to paint; the Erase tool or right-click erases.\n"
		+ "S/R/E/F + player: spawn   * objective   ▲▶▼◀ stairs (climb)\n"
		+ "⇅ link end   · air (floor below ghosted)", &"MutedLabel", true))
	var wrap := ScrollContainer.new()
	wrap.custom_minimum_size = Vector2(0, 220)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(wrap)
	_grid_container = GridContainer.new()
	# Touch-readiness compromise: 2px separation between cells so adjacent buttons
	# don't read as one mis-tappable blob, without ballooning the grid's on-screen
	# footprint (a full zoomable canvas is a later task).
	_grid_container.add_theme_constant_override("h_separation", 2)
	_grid_container.add_theme_constant_override("v_separation", 2)
	wrap.add_child(_grid_container)


func _build_validation_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Validation"))
	_issues_label = RichTextLabel.new()
	_issues_label.bbcode_enabled = true
	_issues_label.fit_content = true
	_issues_label.scroll_active = false
	_issues_label.custom_minimum_size = Vector2(0, 24)
	_issues_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_issues_label)


func _build_save_load_section(col: VBoxContainer) -> void:
	col.add_child(MenuKit.section("Save / load"))
	var row := HBoxContainer.new()
	col.add_child(row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.theme_type_variation = MenuKit.PRIMARY
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed)
	row.add_child(load_btn)

	# --- Export as Challenge -------------------------------------------------
	# Package the current map (with its player-2+ units as AI defenders) into a
	# validated challenge JSON under user://challenges/ AND copy a share code to the
	# clipboard, so another player can import and beat it. Disabled until the map has
	# at least one player-2+ defender spawn that names a character (there is nothing to
	# defend otherwise); the status line explains why when it is.
	col.add_child(MenuKit.section("Share as challenge"))
	var squad_row := HBoxContainer.new()
	col.add_child(squad_row)
	squad_row.add_child(_make_label("Challenger squad size:"))
	_challenge_squad_spin = _make_spin(
		ChallengeCodec.MIN_SQUAD_SIZE, ChallengeCodec.MAX_SQUAD_SIZE, 4)
	squad_row.add_child(_challenge_squad_spin)

	# MODE picks what "winning" means for the challenger. Breach is the classic
	# clear-the-defense run; Survive asks them to still have a unit standing after N of
	# their own rounds. Survive's round count is only meaningful in that mode, so its row
	# is hidden entirely under Breach rather than shown greyed out.
	var mode_row := HBoxContainer.new()
	col.add_child(mode_row)
	mode_row.add_child(_make_label("Mode:"))
	_challenge_mode_option = OptionButton.new()
	_challenge_mode_option.add_item("Breach  (clear the defense)")
	_challenge_mode_option.add_item("Survive  (outlast the defense)")
	_challenge_mode_option.selected = 0
	_challenge_mode_option.item_selected.connect(_on_challenge_mode_selected)
	mode_row.add_child(_challenge_mode_option)

	_challenge_survive_row = HBoxContainer.new()
	col.add_child(_challenge_survive_row)
	_challenge_survive_row.add_child(_make_label("Rounds to survive:"))
	_challenge_survive_spin = _make_spin(
		ChallengeCodec.MIN_SURVIVE_TURNS, ChallengeCodec.MAX_SURVIVE_TURNS,
		ChallengeCodec.DEFAULT_SURVIVE_TURNS)
	_challenge_survive_row.add_child(_challenge_survive_spin)
	_challenge_survive_row.visible = false

	# PAR is the author's target clear length: the challenger scores a bonus under it and
	# loses points over it. It seeds from the defender count until the author sets it.
	var par_row := HBoxContainer.new()
	col.add_child(par_row)
	par_row.add_child(_make_label("Par (target turns):"))
	_challenge_par_spin = _make_spin(
		ChallengeCodec.MIN_PAR_TURNS, ChallengeCodec.MAX_PAR_TURNS,
		ChallengeCodec.default_par_for(0))
	_challenge_par_spin.tooltip_text = "The clear time you are aiming challengers at. Under par pays a bonus; over par costs points."
	_challenge_par_spin.value_changed.connect(_on_challenge_par_changed)
	par_row.add_child(_challenge_par_spin)

	_export_challenge_btn = Button.new()
	_export_challenge_btn.text = "Export as Challenge"
	_export_challenge_btn.pressed.connect(_on_export_challenge_pressed)
	col.add_child(_export_challenge_btn)


func _build_preview_column(body: HSplitContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(col)

	col.add_child(MenuKit.section("3D preview  (drag to orbit, wheel to zoom)"))

	var frame := MenuKit.card(&"InsetPanel")
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(frame)

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_disable_input = true
	_viewport_container.add_child(_viewport)

	_setup_viewport_world()

	_viewport_container.gui_input.connect(_on_preview_gui_input)


## MenuTheme, shrunk for a dense editor: 15px text and tighter button padding.
func _compact_theme() -> Theme:
	var t := MenuTheme.build()
	t.default_font_size = 15
	for type in ["Label", "Button", "LineEdit", "TextEdit", "OptionButton", "SpinBox", "CheckBox", "PopupMenu"]:
		t.set_font_size("font_size", type, 15)
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	for variation in ["GhostButton", "PrimaryButton"]:
		t.set_font_size("font_size", variation, 15)
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var sb := t.get_stylebox(state, type)
			if sb != null:
				var c := sb.duplicate() as StyleBox
				c.content_margin_left = 10
				c.content_margin_right = 10
				c.content_margin_top = 4
				c.content_margin_bottom = 4
				t.set_stylebox(state, type, c)
	for variation in ["GhostButton", "PrimaryButton"]:
		for state in ["normal", "hover", "pressed"]:
			var gsb := t.get_stylebox(state, variation)
			if gsb != null:
				var g := gsb.duplicate() as StyleBox
				g.content_margin_left = 10
				g.content_margin_right = 12
				g.content_margin_top = 4
				g.content_margin_bottom = 4
				t.set_stylebox(state, variation, g)
	var field := t.get_stylebox("normal", "LineEdit")
	if field != null:
		var f := field.duplicate() as StyleBox
		f.content_margin_top = 4
		f.content_margin_bottom = 4
		t.set_stylebox("normal", "LineEdit", f)
	return t


# =============================================================================
#  Tile palette
# =============================================================================

func _load_tile_palette_entries() -> void:
	## Build the palette from the REAL TileResource files (via TileCatalog, which walks
	## the biome sub-folders), so a painted cell records an actual stable tile_id. Falls
	## back to the tile-type strings if no resources are found, so it is never empty.
	_tile_palette_entries.clear()
	_type_model_paths.clear()
	_type_model_paths_built = false

	var type_names: Array = Tile.TileType.keys()

	TileCatalog.rescan()
	for resource_path in TileCatalog.all_paths():
		var resource = load(resource_path)
		if not (resource is TileResource):
			continue
		var tile_resource := resource as TileResource
		var type_index: int = int(tile_resource.tile_type)
		if type_index < 0 or type_index >= type_names.size():
			continue
		var type_name: String = str(type_names[type_index])
		var display_name: String = tile_resource.tile_name
		if display_name.is_empty():
			display_name = type_name.replace("_", " ")
		_tile_palette_entries.append({
			"type_name": type_name,
			"resource_path": resource_path,
			"tile_id": String(tile_resource.get_id()),
			"color": tile_resource.base_color,
			"display_name": display_name,
		})

	if _tile_palette_entries.is_empty():
		for type_name in type_names:
			var name_string: String = str(type_name)
			_tile_palette_entries.append({
				"type_name": name_string,
				"resource_path": "",
				"tile_id": "",
				"color": TILE_COLORS.get(name_string, Color.WHITE),
				"display_name": name_string.replace("_", " "),
			})

	# Default the selection to the first entry.
	if not _tile_palette_entries.is_empty():
		var first: Dictionary = _tile_palette_entries[0]
		_selected_tile_type = str(first.get("type_name", "NORMAL"))
		_selected_tile_path = str(first.get("resource_path", ""))
		_selected_tile_id = str(first.get("tile_id", ""))


func _on_palette_selected(index: int) -> void:
	if index < 0 or index >= _tile_palette_entries.size():
		return
	var entry: Dictionary = _tile_palette_entries[index]
	_selected_tile_type = str(entry.get("type_name", "NORMAL"))
	_selected_tile_path = str(entry.get("resource_path", ""))
	_selected_tile_id = str(entry.get("tile_id", ""))
	_select_tool(Tool.PAINT)
	_set_status("Tile: " + str(entry.get("display_name", _selected_tile_type)))


# =============================================================================
#  Floors
# =============================================================================

## Switch the floor being edited (0 .. MapMakerModel.MAX_FLOOR).
func set_floor(f: int) -> void:
	current_floor = clampi(f, 0, MapMakerModel.MAX_FLOOR)
	_rect_anchor = NO_CELL
	_rect_hover = NO_CELL
	_is_painting = false
	_refresh_all()
	_set_status("Editing floor %d" % current_floor)


func _refresh_floor_label() -> void:
	if _floor_label == null or model == null:
		return
	var count := model.get_floor_count()
	_floor_label.text = "%d  (%s)  · %d in use" % [current_floor, FloorNav.floor_name(current_floor, maxi(count, current_floor + 1)), count]
	if _grid_title != null:
		_grid_title.text = ("Map grid  -  floor %d" % current_floor).to_upper()


# =============================================================================
#  2D grid
# =============================================================================

func _rebuild_grid() -> void:
	if _grid_container == null:
		return
	for child in _grid_container.get_children():
		child.queue_free()
	_cell_buttons.clear()
	_is_painting = false
	_rect_anchor = NO_CELL
	_rect_hover = NO_CELL

	_grid_width = model.width
	_grid_height = model.height
	_grid_container.columns = max(1, model.width)

	# Row 0 at the TOP, like the battle camera (north / row 0 is the far side).
	for y in range(model.height):
		for x in range(model.width):
			var pos := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			button.add_theme_font_size_override("font_size", 12)
			button.focus_mode = Control.FOCUS_NONE
			button.gui_input.connect(_on_cell_gui_input.bind(pos))
			button.mouse_entered.connect(_on_cell_mouse_entered.bind(pos))
			_grid_container.add_child(button)
			_cell_buttons[pos] = button
			_paint_cell_button(pos)


## Repaint every 2D cell (the grid shows one floor), the validation list, the floor
## label and the 3D floor visibility. Used on floor changes, loads and the tools that
## touch several cells / floors (stairs, links).
func _refresh_all() -> void:
	for pos in _cell_buttons:
		_paint_cell_button(pos)
	_refresh_issues()
	_refresh_floor_label()
	_apply_floor_visibility()


func _on_cell_gui_input(event: InputEvent, pos: Vector2i) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_apply_brush(pos, _erase_at)
		_refresh_export_state()
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# Touch-readiness: LEFT-click/tap erases too when the Erase tool is selected
	# (right-click erase, handled above, stays as a desktop-only shortcut -- touch
	# has no right-click). Spelled out as its own branch rather than relying on the
	# `_:` default falling through to _apply_tool_at so the left-click-erases
	# contract is explicit. STAIRS and LINK are single-click tools (no drag).
	match _current_tool:
		Tool.RECT_FILL:
			_rect_anchor = pos
			_rect_hover = pos
			_tint_rect_preview()
		Tool.BUCKET_FILL:
			_bucket_fill_at(pos)
		Tool.ERASE:
			_is_painting = true
			_apply_brush(pos, _erase_at)
			_refresh_export_state()
		Tool.STAIRS:
			_stairs_at(pos)
		Tool.LINK:
			_link_click(Vector3i(pos.x, pos.y, current_floor))
		_:
			_is_painting = true
			_apply_tool_at(pos)


func _on_cell_mouse_entered(pos: Vector2i) -> void:
	if _rect_anchor != NO_CELL:
		_update_rect_preview(pos)
		return
	if _is_painting:
		_apply_tool_at(pos)


func _apply_tool_at(pos: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT:
			_apply_brush(pos, _paint_at)
		Tool.ERASE:
			_apply_brush(pos, _erase_at)
		Tool.BUCKET_FILL:
			_bucket_fill_at(pos)
		Tool.SPAWN:
			_toggle_spawn_at(pos)
		Tool.OBJECTIVE:
			_toggle_objective_at(pos)
		_:
			pass
	_refresh_export_state()


func _apply_brush(pos: Vector2i, action: Callable) -> void:
	for dy in range(_brush_size):
		for dx in range(_brush_size):
			var target := Vector2i(pos.x + dx, pos.y + dy)
			if not model.is_in_bounds(target):
				continue
			action.call(target)
			_refresh_cell(target)


func _paint_at(pos: Vector2i) -> void:
	model.paint_tile(pos, _selected_tile_type, _selected_tile_path, current_floor, _selected_tile_id)
	_enforce_terrain_over_placement(pos)
	_queue_flush(true, false)


## Erase on the edited floor: the tile (ground reverts to the default tile, an upper
## floor becomes air), the spawn standing there, every link touching the cell and --
## on the ground floor -- the objective marker.
func _erase_at(pos: Vector2i) -> void:
	var f := current_floor
	var cell := Vector3i(pos.x, pos.y, f)
	var had_link := not model.get_stairs(pos, f).is_empty() or not model.get_links_at(cell).is_empty()
	model.erase_tile(pos, f)
	model.remove_spawn(pos, f)
	model.remove_links_at(cell)
	if f == 0:
		model.remove_objective(pos)
	_queue_flush(true, had_link)


func _toggle_spawn_at(pos: Vector2i) -> void:
	var f := current_floor
	if model.get_spawn(pos, f).is_empty():
		if not _can_place_at(pos):
			_deny_placement(pos, "a unit")
			return
		model.place_spawn_point(pos, _current_player_id, _selected_spawn_kind, {
			"character_id": _selected_character_id,
		}, f)
	else:
		model.remove_spawn(pos, f)
	_refresh_cell(pos)
	_queue_flush(true, false)


## Objectives live on the ground floor only.
func _toggle_objective_at(pos: Vector2i) -> void:
	if current_floor != 0:
		_set_status("Objectives live on the ground floor")
		return
	if model.get_objective(pos).is_empty():
		if not _can_place_at(pos):
			_deny_placement(pos, "an objective")
			return
		model.set_objective(pos, "THRONE", _current_player_id)
	else:
		model.remove_objective(pos)
	_refresh_cell(pos)


## Stairs tool: toggle a stair on (pos, edited floor) climbing in the selected direction.
func _stairs_at(pos: Vector2i) -> void:
	var f := current_floor
	var cur := model.get_stairs(pos, f)
	var want := "" if cur == _stair_dir else _stair_dir
	if model.set_stairs(pos, want, f):
		_set_status("Stairs cleared" if want.is_empty() else "Stairs climb %s to floor %d" % [want, f + 1])
	else:
		_set_status("Paint a tile here before adding stairs")
	_refresh_cell(pos)
	_refresh_links_3d()
	_refresh_all()


## Two-click link authoring: first click picks the from-cell, the second (on any
## floor) the to-cell. Re-linking the same pair removes the link.
func _link_click(cell: Vector3i) -> void:
	if _link_from == Cells.INVALID:
		_link_from = cell
		_set_status("Link from (%d, %d) floor %d -- now click the other end (change floor if needed)" % [cell.x, cell.y, cell.z])
		_refresh_all()
		return
	var from := _link_from
	_link_from = Cells.INVALID
	if from == cell:
		_set_status("Link cancelled")
	elif model.remove_link(from, cell):
		_set_status("Link removed")
	elif model.add_link(from, cell, _link_cost, _link_kind):
		_set_status("%s linked: %s -> %s" % [_link_kind.capitalize(), str(from), str(cell)])
	else:
		_set_status("Could not link those cells")
	_refresh_links_3d()
	_refresh_all()


## True when a unit / objective may stand on (pos, edited floor): the ground floor uses
## the model's terrain rule ([method MapMakerModel.can_place_unit]); an upper floor also
## needs a tile there (air holds nothing) and runs the same passability rule on it.
func _can_place_at(pos: Vector2i) -> bool:
	var f := current_floor
	if f == 0:
		return model.can_place_unit(pos)
	if not model.is_in_bounds(pos) or not model.has_tile(pos, f):
		return false
	return MapMakerModel.tile_dict_is_passable(model.get_tile(pos, f), model.tile_resolver)


## Refuses a SPAWN/OBJECTIVE placement on impassable terrain (or air): a status
## message, a brief red flash on the 2D cell button, and the denied UI cue. No model
## state changes -- the caller returns right after this, so nothing needs undoing.
func _deny_placement(pos: Vector2i, what: String) -> void:
	if current_floor > 0 and not model.has_tile(pos, current_floor):
		_set_status("Can't place %s on air — paint a tile on floor %d first." % [what, current_floor])
	else:
		_set_status("Can't place %s on %s — impassable terrain." % [what, _tile_label_at(pos)])
	_flash_cell_denied(pos)
	if typeof(AudioManager) == TYPE_OBJECT and AudioManager != null and AudioManager.has_method("play_ui_back"):
		AudioManager.play_ui_back()


## Human-readable label for the tile at [param pos] on the edited floor (used in
## denial/removal status text): the resolved TileResource's authored name when one
## resolves, else the raw tile_type.
func _tile_label_at(pos: Vector2i) -> String:
	var resolved := _tile_resource_at(pos, current_floor)
	if resolved != null and not resolved.tile_name.is_empty():
		return resolved.tile_name
	var tile: Dictionary = model.get_tile(pos, current_floor)
	return str(tile.get("tile_type", "NORMAL")).capitalize()


## Brief red flash on the 2D cell button at [param pos] via a modulate tween (fades back
## to white). No-op for a cell with no button (out of bounds / not yet built).
func _flash_cell_denied(pos: Vector2i) -> void:
	var button: Button = _cell_buttons.get(pos)
	if button == null:
		return
	button.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(button, "modulate", Color.WHITE, 0.35)


## Painting an impassable tile (wall, tree, ...) OVER a cell that already carries a
## spawn or objective invalidates it. Chosen behaviour: AUTO-REMOVE the now-invalid
## marker with a status warning rather than blocking the paint stroke -- less annoying
## mid-sketch than refusing every wall/tree brush pass that happens to cross a marker,
## and the author can always re-place it once they see the warning. Called from every
## paint path (single cell / brush, bucket fill, rect fill), on the edited floor.
func _enforce_terrain_over_placement(pos: Vector2i) -> void:
	if _can_place_at(pos):
		return
	var f := current_floor
	var removed_something := false
	if not model.get_spawn(pos, f).is_empty():
		model.remove_spawn(pos, f)
		removed_something = true
	if f == 0 and not model.get_objective(pos).is_empty():
		model.remove_objective(pos)
		removed_something = true
	if removed_something:
		_set_status("Removed spawn/objective at %s — now %s (impassable)." % [
			str(pos), _tile_label_at(pos)])


## Flood-fill key of (pos, edited floor): the tile type, or "" for air on an upper floor.
func _fill_key(pos: Vector2i) -> String:
	if current_floor > 0 and not model.has_tile(pos, current_floor):
		return ""
	return str(model.get_tile(pos, current_floor).get("tile_type", "NORMAL"))


func _bucket_fill_at(pos: Vector2i) -> void:
	if not model.is_in_bounds(pos):
		return
	var target_type: String = _fill_key(pos)
	if target_type == _selected_tile_type:
		return
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [pos]
	visited[pos] = true
	while stack.size() > 0:
		var cell: Vector2i = stack.pop_back()
		if _fill_key(cell) != target_type:
			continue
		model.paint_tile(cell, _selected_tile_type, _selected_tile_path, current_floor, _selected_tile_id)
		_enforce_terrain_over_placement(cell)
		_refresh_cell(cell)
		for neighbor in [Vector2i(cell.x + 1, cell.y), Vector2i(cell.x - 1, cell.y),
				Vector2i(cell.x, cell.y + 1), Vector2i(cell.x, cell.y - 1)]:
			if model.is_in_bounds(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				stack.append(neighbor)
	_queue_flush(true, false)


# --- rect fill ---------------------------------------------------------------

func _update_rect_preview(pos: Vector2i) -> void:
	if pos == _rect_hover:
		return
	var previous := _rect_hover
	_rect_hover = pos
	if previous != NO_CELL:
		for cell in _rect_cells(_rect_anchor, previous):
			_paint_cell_button(cell)
	_tint_rect_preview()


func _tint_rect_preview() -> void:
	if _rect_anchor == NO_CELL or _rect_hover == NO_CELL:
		return
	var tint: Color = _selected_swatch_color().lightened(0.25)
	for cell in _rect_cells(_rect_anchor, _rect_hover):
		var button: Button = _cell_buttons.get(cell)
		if button:
			_apply_swatch(button, tint)


func _commit_rect_fill(release_pos: Vector2i) -> void:
	var anchor := _rect_anchor
	var corner := release_pos
	_rect_anchor = NO_CELL
	_rect_hover = NO_CELL
	if anchor == NO_CELL:
		return
	if not model.is_in_bounds(corner):
		corner = anchor
	for cell in _rect_cells(anchor, corner):
		model.paint_tile(cell, _selected_tile_type, _selected_tile_path, current_floor, _selected_tile_id)
		_enforce_terrain_over_placement(cell)
		_refresh_cell(cell)
	_refresh_export_state()
	_queue_flush(true, false)


func _rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var min_x: int = mini(a.x, b.x)
	var max_x: int = maxi(a.x, b.x)
	var min_y: int = mini(a.y, b.y)
	var max_y: int = maxi(a.y, b.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			if model.is_in_bounds(cell):
				cells.append(cell)
	return cells


# --- 2D cell rendering -------------------------------------------------------

func _refresh_cell(pos: Vector2i) -> void:
	## The single sync point: repaint the 2D button AND the one 3D cell of the edited
	## floor. Every edit path funnels through here, so the two views can never drift
	## and a stroke never triggers a full 3D rebuild.
	_paint_cell_button(pos)
	_refresh_cell_3d(pos, current_floor)


func _paint_cell_button(pos: Vector2i) -> void:
	var button: Button = _cell_buttons.get(pos)
	if button == null:
		return
	var f := current_floor
	var parts: PackedStringArray = []
	var color: Color
	var ghost := false
	if model.has_tile(pos, f):
		color = _tile_color_at(pos, f)
		var st := model.get_stairs(pos, f)
		if not st.is_empty():
			parts.append(STAIR_GLYPHS.get(st, "S"))
	else:
		# Air: show the floor below, ghosted, so the deck can be lined up with it.
		var below := f - 1
		while below > 0 and not model.has_tile(pos, below):
			below -= 1
		color = _tile_color_at(pos, maxi(below, 0))
		ghost = true
		parts.append("·")
	var spawn: Dictionary = model.get_spawn(pos, f)
	if not spawn.is_empty():
		var kind: String = str(spawn.get("spawn_kind", MapResource.SPAWN_KIND_START))
		var player_id := int(spawn.get("player_id", 0))
		parts.append(str(SPAWN_KIND_INITIALS.get(kind, "S")) + str(player_id))
		color = _player_color(player_id)
		ghost = false
	elif f == 0 and not model.get_objective(pos).is_empty():
		parts.append("*")
		color = OBJECTIVE_COLOR
	var cell := Vector3i(pos.x, pos.y, f)
	var links := model.get_links_at(cell)
	if not links.is_empty():
		parts.append("⇅")
	if cell == _link_from:
		parts.append("①")
	button.text = " ".join(parts)
	_apply_swatch(button, color, ghost)
	var tip := "(%d, %d) floor %d" % [pos.x, pos.y, f]
	for l in links:
		var other: Vector3i = l["to"] if l["from"] == cell else l["from"]
		tip += "\n%s to (%d, %d) floor %d, cost %d" % [str(l["kind"]).capitalize(), other.x, other.y, other.z, int(l["cost"])]
	button.tooltip_text = tip


## Paint [param button] as a solid colour swatch. modulate alone only tints the dark
## theme's stylebox, washing distinct tile colours into near-identical greys, so the
## styleboxes are overridden with the real colour plus a thin border (gold on hover /
## press, the grove focus colour). [param ghost] (air on an upper floor) shows the
## floor below faded toward the page ground with a faint border. The text ink flips
## for contrast on light swatches.
func _apply_swatch(button: Button, color: Color, ghost: bool = false) -> void:
	var fill := MenuTheme.BG_DEEP.lerp(color, 0.28) if ghost else color
	button.modulate = Color.WHITE
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(3)
		box.set_border_width_all(1)
		box.border_color = Color(color, 0.35) if ghost else Color(0, 0, 0, 0.4)
		if state == "hover":
			box.bg_color = fill.lightened(0.15)
			box.border_color = MenuTheme.GOLD
			box.set_border_width_all(2)
		elif state == "pressed":
			box.bg_color = fill.darkened(0.15)
			box.border_color = MenuTheme.GOLD_LITE
			box.set_border_width_all(2)
		button.add_theme_stylebox_override(state, box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := MenuTheme.INK if not ghost and fill.get_luminance() > 0.45 else MenuTheme.CREAM
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)


func _refresh_issues() -> void:
	_issues_dirty = false
	if _issues_label == null or model == null:
		return
	var issues := model.validate()
	if issues.is_empty():
		_issues_label.text = "[color=#%s]No problems found.[/color]" % MenuTheme.SUCCESS.to_html(false)
		return
	var lines: PackedStringArray = []
	for i in issues:
		var col: Color = MenuTheme.DANGER if i["level"] == "error" else MenuTheme.WARNING
		lines.append("[color=#%s]%s[/color] %s" % [col.to_html(false), String(i["level"]).to_upper(), i["message"]])
	_issues_label.text = "\n".join(lines)


## Coalesce the validation list and the 3D link rebuild to once per frame during
## drag strokes. Headless (never built / not in the tree) it does nothing.
func _queue_flush(issues: bool, links: bool) -> void:
	_issues_dirty = _issues_dirty or issues
	_links_dirty = _links_dirty or links
	if _flush_queued or not is_inside_tree():
		return
	_flush_queued = true
	call_deferred(&"_flush_deferred")


func _flush_deferred() -> void:
	_flush_queued = false
	if _links_dirty:
		_refresh_links_3d()
	if _issues_dirty:
		_refresh_issues()
		_refresh_floor_label()


# =============================================================================
#  3D preview  (ported from map_creator_dock.gd, reading the MapMakerModel)
# =============================================================================

func _setup_viewport_world() -> void:
	_world_root = Node3D.new()
	_world_root.name = "MapRoot"
	_viewport.add_child(_world_root)

	_camera = Camera3D.new()
	_camera.name = "MapCamera"
	_viewport.add_child(_camera)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = MenuTheme.BG_DEEP
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45, 1.0)
	env.ambient_light_energy = 0.5
	_camera.environment = env

	var light := DirectionalLight3D.new()
	light.name = "MapLight"
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.1
	_viewport.add_child(light)


func _build_world_3d() -> void:
	## Full rebuild. Called on new / load / resize only - a paint stroke goes through
	## _refresh_cell_3d (one cell) instead.
	if _world_root == null:
		return
	for child in _world_root.get_children():
		_world_root.remove_child(child)
		child.queue_free()
	_floor_roots.clear()
	_links_root = null
	_tile_visuals.clear()
	_spawn_visuals.clear()
	_spawn_signatures.clear()
	_objective_meshes.clear()

	var cols: int = maxi(model.width, 1)
	var rows: int = maxi(model.height, 1)
	_world_span = maxf(float(cols), float(rows)) * TILE_STEP
	_cam_distance = _world_span * 1.15
	_aim_camera()

	var floors := maxi(model.get_floor_count(), current_floor + 1)
	for f in range(floors):
		for y in range(rows):
			for x in range(cols):
				var pos := Vector2i(x, y)
				if model.has_tile(pos, f):
					_create_tile_visual(pos, f)
				_sync_spawn_marker(pos, f)
				if f == 0:
					_sync_objective_marker(pos)
	_refresh_links_3d()


## The per-floor container (created on demand), raised to the floor's height.
func _floor_root(f: int) -> Node3D:
	var existing = _floor_roots.get(f)
	if existing != null and is_instance_valid(existing):
		return existing
	var root := Node3D.new()
	root.name = "Floor_%d" % f
	root.position = Vector3(0.0, Cells.floor_y(f), 0.0)
	root.visible = f <= current_floor
	_world_root.add_child(root)
	_floor_roots[f] = root
	return root


## Show every floor up to the edited one (the battle cutaway rule), plus the links
## whose upper end is visible.
func _apply_floor_visibility() -> void:
	for f in _floor_roots:
		var root = _floor_roots[f]
		if root != null and is_instance_valid(root):
			root.visible = int(f) <= current_floor
	if _links_root != null and is_instance_valid(_links_root):
		for node in _links_root.get_children():
			node.visible = int(node.get_meta(FloorDecor.META_FLOOR, 0)) <= current_floor


func _refresh_cell_3d(pos: Vector2i, f: int) -> void:
	if _world_root == null or not model.is_in_bounds(pos):
		return
	var cell := Vector3i(pos.x, pos.y, f)
	if _tile_visuals.has(cell):
		var stale = _tile_visuals[cell]
		if stale != null and is_instance_valid(stale):
			var parent: Node = stale.get_parent()
			if parent:
				parent.remove_child(stale)
			stale.queue_free()
		_tile_visuals.erase(cell)
	if model.has_tile(pos, f):
		_create_tile_visual(pos, f)
	_sync_spawn_marker(pos, f)
	if f == 0:
		_sync_objective_marker(pos)


func _create_tile_visual(pos: Vector2i, f: int) -> void:
	var visual: Node3D = _instantiate_tile_model(pos, f)
	if visual == null:
		var mesh := BoxMesh.new()
		mesh.size = TILE_MESH_SIZE
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _solid_material(_tile_color_at(pos, f))
		visual = mi
	_floor_root(f).add_child(visual)
	visual.position = _world_position_for(pos, 0.0)
	_tile_visuals[Vector3i(pos.x, pos.y, f)] = visual


## Rebuild the stair and link visuals (FloorDecor, the same meshes the battle map
## uses): explicit links plus one per stair tile. Cheap (a handful of links) and only
## run when stairs / links change.
func _refresh_links_3d() -> void:
	_links_dirty = false
	if _world_root == null:
		return
	if _links_root != null and is_instance_valid(_links_root):
		_world_root.remove_child(_links_root)
		_links_root.queue_free()
	_links_root = Node3D.new()
	_links_root.name = "Links"
	# FloorDecor works in battle-world space (a cell centre is col*2+1); the preview is
	# centred on the origin.
	var off := _world_offsets()
	_links_root.position = Vector3(-TILE_STEP * 0.5 - off.x, 0.0, -TILE_STEP * 0.5 - off.y)
	_world_root.add_child(_links_root)
	for l in _preview_links():
		var node := FloorDecor.make_link_visual(l)
		if node != null:
			_links_root.add_child(node)
	_apply_floor_visibility()


## Explicit links plus the link every stair tile generates.
func _preview_links() -> Array[Dictionary]:
	var out: Array[Dictionary] = model.get_links()
	for f in range(model.get_floor_count()):
		for y in range(model.height):
			for x in range(model.width):
				var pos := Vector2i(x, y)
				if model.get_stairs(pos, f).is_empty():
					continue
				out.append({
					"from": Vector3i(x, y, f), "to": model.stairs_target(pos, f),
					"cost": 1, "kind": "stairs", "bidirectional": true,
				})
	return out


func _sync_spawn_marker(pos: Vector2i, f: int) -> void:
	## Render a spawn as the ACTUAL character model (when the spawn names one), sitting
	## on a flat player-colour ring with a floating kind-initial label so player/kind
	## info is never lost. Falls back to the original colour sphere when the spawn has no
	## character or its model can't load. Rebuilds only when the spawn's player/kind/
	## character actually change, so an unrelated tile edit on the same cell is a no-op.
	var cell := Vector3i(pos.x, pos.y, f)
	var spawn: Dictionary = model.get_spawn(pos, f)
	if spawn.is_empty():
		_clear_spawn_visual(cell)
		return

	var player_id: int = int(spawn.get("player_id", 0))
	var kind: String = str(spawn.get("spawn_kind", MapResource.SPAWN_KIND_START))
	var character_id: String = str(spawn.get("character_id", ""))
	var signature: String = "%d|%s|%s" % [player_id, kind, character_id]
	if _spawn_signatures.get(cell, "") == signature \
			and _spawn_visuals.has(cell) and is_instance_valid(_spawn_visuals[cell]):
		return  # nothing about the spawn changed; keep the existing visual

	_clear_spawn_visual(cell)
	var holder: Node3D = _build_spawn_visual(player_id, kind, character_id)
	holder.name = "Spawn_%d_%d_%d" % [pos.x, pos.y, f]
	_floor_root(f).add_child(holder)
	holder.position = _world_position_for(pos, 0.0)
	_spawn_visuals[cell] = holder
	_spawn_signatures[cell] = signature


## Free the spawn visual holder at [param cell] (model + ring + label, or the fallback
## sphere) and forget its signature. No-op when the cell has no spawn visual.
func _clear_spawn_visual(cell: Vector3i) -> void:
	if _spawn_visuals.has(cell):
		var holder = _spawn_visuals[cell]
		if holder != null and is_instance_valid(holder):
			var parent: Node = holder.get_parent()
			if parent:
				parent.remove_child(holder)
			holder.queue_free()
		_spawn_visuals.erase(cell)
	_spawn_signatures.erase(cell)


## Build the spawn's 3D visual as a single holder Node3D positioned at the cell.
## With a resolvable character: its model + a flat player-colour ground ring + a
## floating kind-initial billboard. Otherwise: the original colour sphere, which
## already carries the player colour and kind scale on its own.
func _build_spawn_visual(player_id: int, kind: String, character_id: String) -> Node3D:
	var holder := Node3D.new()
	var color: Color = _player_color(player_id)
	var scale_value: float = float(SPAWN_KIND_MARKER_SCALE.get(kind, 1.0))

	var character_model: Node3D = _instantiate_character_model(character_id)
	if character_model != null:
		holder.add_child(character_model)
		holder.add_child(_build_spawn_ring(color, scale_value))
		holder.add_child(_build_spawn_label(kind, color))
	else:
		holder.add_child(_build_spawn_sphere(color, scale_value))
	return holder


## Instantiate [param character_id]'s authored model, placed feet-on-tile and given the
## character's authored yaw + scale (the minimal engine-safe port of
## Unit._setup_character_model). Returns null when the id is empty, unknown, has no
## model_scene, or the scene doesn't instance to a Node3D -- the caller then falls back
## to the sphere.
func _instantiate_character_model(character_id: String) -> Node3D:
	var packed: PackedScene = _load_character_model(character_id)
	if packed == null:
		return null
	var instance = packed.instantiate()
	if not (instance is Node3D):
		if instance:
			instance.free()
		return null
	var character_model := instance as Node3D

	# Centre a multi-cell model over its footprint (zero offset for a normal 1x1), then
	# apply the authored yaw and scale about the feet-at-origin, exactly like a live unit.
	var yaw: float = 0.0
	var model_scale: float = 1.0
	var footprint := Vector2i.ONE
	var character := CharacterLibrary.get_character(character_id)
	if character != null:
		yaw = character.model_yaw_deg if "model_yaw_deg" in character else 0.0
		model_scale = character.model_scale if "model_scale" in character else 1.0
		if character.has_method("get_footprint"):
			footprint = character.get_footprint()
	character_model.position = Vector3(
		float(footprint.x - 1) * TILE_STEP * 0.5,
		SPAWN_MODEL_Y,
		float(footprint.y - 1) * TILE_STEP * 0.5)
	character_model.rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)
	character_model.scale = Vector3.ONE * maxf(0.05, model_scale)
	return character_model


## Loads (and caches) the roster model PackedScene for [param character_id]. Caches the
## null answer too, so a spawn with no character / no model never re-hits the library.
func _load_character_model(character_id: String) -> PackedScene:
	if character_id.is_empty():
		return null
	if _character_model_cache.has(character_id):
		return _character_model_cache[character_id]
	var packed: PackedScene = null
	var character := CharacterLibrary.get_character(character_id)
	if character != null and character.model_scene != null:
		packed = character.model_scene
	_character_model_cache[character_id] = packed
	return packed


## Flat player-colour ground ring under a spawn model, sized by spawn kind.
func _build_spawn_ring(color: Color, scale_value: float) -> MeshInstance3D:
	var radius: float = SPAWN_RING_RADIUS * scale_value
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = SPAWN_RING_HEIGHT
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = _solid_material(color)
	ring.position = Vector3(0.0, SPAWN_RING_Y, 0.0)
	return ring


## Floating billboard showing the spawn kind's initial (S/R/E/F) in the player colour.
func _build_spawn_label(kind: String, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = str(SPAWN_KIND_INITIALS.get(kind, "S"))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.outline_size = 10
	label.font_size = 64
	label.pixel_size = 0.012
	label.position = Vector3(0.0, SPAWN_LABEL_Y, 0.0)
	return label


## The original spawn marker: a player-colour sphere scaled by kind. Used when a spawn
## names no character (or its model can't load), where it still reads player + kind.
func _build_spawn_sphere(color: Color, scale_value: float) -> MeshInstance3D:
	var radius: float = SPAWN_RADIUS * scale_value
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = _solid_material(color)
	marker.position = Vector3(0.0, SPAWN_Y, 0.0)
	return marker


## Objective markers live on the ground floor only.
func _sync_objective_marker(pos: Vector2i) -> void:
	var objective: Dictionary = model.get_objective(pos)
	if objective.is_empty():
		if _objective_meshes.has(pos):
			var stale = _objective_meshes[pos]
			if stale != null and is_instance_valid(stale):
				stale.queue_free()
			_objective_meshes.erase(pos)
		return
	if _objective_meshes.has(pos) and is_instance_valid(_objective_meshes[pos]):
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.7, 0.35)
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = _solid_material(OBJECTIVE_COLOR)
	marker.position = _world_position_for(pos, OBJECTIVE_Y)
	_floor_root(0).add_child(marker)
	_objective_meshes[pos] = marker


# --- 3D tile resolution (mirrors MapLoader / the dock) -----------------------

func _tile_resource_at(pos: Vector2i, f: int = 0) -> TileResource:
	var tile: Dictionary = model.get_tile(pos, f)
	var tile_id: String = str(tile.get("tile_id", ""))
	if not tile_id.is_empty():
		var by_id := TileCatalog.find_by_id(StringName(tile_id))
		if by_id != null:
			return by_id
	var path: String = str(tile.get("tile_resource_path", ""))
	if not path.is_empty():
		var found := TileCatalog.find(path)
		if found != null:
			return found
	return null


func _tile_model_path_at(pos: Vector2i, f: int) -> String:
	var resolved := _tile_resource_at(pos, f)
	if resolved != null:
		return resolved.model_path
	_build_type_model_paths()
	var tile: Dictionary = model.get_tile(pos, f)
	return str(_type_model_paths.get(str(tile.get("tile_type", "NORMAL")), ""))


func _build_type_model_paths() -> void:
	if _type_model_paths_built:
		return
	_type_model_paths_built = true
	for entry in _tile_palette_entries:
		var type_name: String = str(entry.get("type_name", ""))
		if type_name.is_empty() or _type_model_paths.has(type_name):
			continue
		var path: String = str(entry.get("resource_path", ""))
		if path.is_empty():
			continue
		var tile_resource := _load_tile_resource(path)
		if tile_resource == null or tile_resource.model_path.is_empty():
			continue
		_type_model_paths[type_name] = tile_resource.model_path


func _load_tile_resource(path: String) -> TileResource:
	if path.is_empty():
		return null
	if _tile_resource_cache.has(path):
		return _tile_resource_cache[path]
	var tile_resource: TileResource = null
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is TileResource:
			tile_resource = loaded as TileResource
	_tile_resource_cache[path] = tile_resource
	return tile_resource


func _load_tile_model(scene_path: String) -> PackedScene:
	if scene_path.is_empty():
		return null
	if _tile_model_cache.has(scene_path):
		return _tile_model_cache[scene_path]
	var packed: PackedScene = null
	if ResourceLoader.exists(scene_path):
		var loaded = load(scene_path)
		if loaded is PackedScene:
			packed = loaded as PackedScene
	_tile_model_cache[scene_path] = packed
	return packed


func _instantiate_tile_model(pos: Vector2i, f: int) -> Node3D:
	var packed := _load_tile_model(_tile_model_path_at(pos, f))
	if packed == null:
		return null
	var instance = packed.instantiate()
	if instance is Node3D:
		return instance as Node3D
	if instance:
		instance.free()
	return null


func _tile_color_at(pos: Vector2i, f: int = 0) -> Color:
	var resolved := _tile_resource_at(pos, f)
	if resolved != null:
		return resolved.base_color
	var tile: Dictionary = model.get_tile(pos, f)
	return TILE_COLORS.get(str(tile.get("tile_type", "NORMAL")), Color.WHITE)


func _solid_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


# --- world-space layout + camera ---------------------------------------------

func _world_offsets() -> Vector2:
	return Vector2(
		float(model.width - 1) * TILE_STEP * 0.5,
		float(model.height - 1) * TILE_STEP * 0.5)


## Floor-local position of [param pos] (the floor's container carries its height).
func _world_position_for(pos: Vector2i, y: float) -> Vector3:
	var offsets := _world_offsets()
	return Vector3(
		float(pos.x) * TILE_STEP - offsets.x,
		y,
		float(pos.y) * TILE_STEP - offsets.y)


func _aim_camera() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		_cam_distance * cos(_cam_pitch) * sin(_cam_yaw),
		_cam_distance * sin(_cam_pitch),
		_cam_distance * cos(_cam_pitch) * cos(_cam_yaw))
	_camera.look_at_from_position(offset, Vector3.ZERO, Vector3.UP)


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_cam_distance = maxf(_world_span * 0.35, _cam_distance * 0.9)
			_aim_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_cam_distance = minf(_world_span * 4.0, _cam_distance * 1.1)
			_aim_camera()
	elif event is InputEventMouseMotion and _orbiting:
		var motion := event as InputEventMouseMotion
		_cam_yaw -= motion.relative.x * 0.01
		_cam_pitch = clampf(_cam_pitch - motion.relative.y * 0.01, 0.2, 1.5)
		_aim_camera()


# =============================================================================
#  Section handlers
# =============================================================================

func _on_spawn_kind_selected(index: int) -> void:
	if index < 0 or index >= MapResource.SPAWN_KINDS.size():
		return
	_selected_spawn_kind = str(MapResource.SPAWN_KINDS[index])
	_select_tool(Tool.SPAWN)


func _on_character_selected(index: int) -> void:
	var meta = _character_option.get_item_metadata(index)
	_selected_character_id = str(meta) if meta != null else ""
	_select_tool(Tool.SPAWN)


func _on_resize_pressed() -> void:
	model.set_dimensions(int(_width_spin.value), int(_height_spin.value))
	_rebuild_grid()
	_build_world_3d()
	_refresh_export_state()
	_refresh_all()
	_set_status("Resized to %dx%d" % [model.width, model.height])


## Weather dropdown: one entry per authored weather (fixed), "Dynamic (all)", and a
## "Custom" entry that keeps a loaded map's own schedule / dynamic settings.
func _sync_weather_option() -> void:
	if _weather_opt == null:
		return
	_weather_opt.clear()
	var s := WeatherState.normalize_settings(model.weather_settings)
	var selected := -1
	for id in Weather.all_ids():
		_weather_opt.add_item(Weather.get_weather(id).display_name)
		_weather_opt.set_item_metadata(_weather_opt.item_count - 1, String(id))
		if s["mode"] == WeatherState.MODE_FIXED and s["weather"] == id:
			selected = _weather_opt.item_count - 1
	_weather_opt.add_item("Dynamic (all)")
	_weather_opt.set_item_metadata(_weather_opt.item_count - 1, "__dynamic")
	if s["mode"] != WeatherState.MODE_FIXED:
		_weather_opt.add_item("Custom (%s)" % s["mode"])
		_weather_opt.set_item_metadata(_weather_opt.item_count - 1, "__custom")
		selected = _weather_opt.item_count - 1
	_weather_opt.select(maxi(selected, 0))


func _on_weather_selected(index: int) -> void:
	var key := String(_weather_opt.get_item_metadata(index))
	if key == "__custom":
		return
	if key == "__dynamic":
		var pool := {}
		for id in Weather.all_ids():
			pool[String(id)] = 1
		model.weather_settings = {"mode": "dynamic", "weather": "clear", "pool": pool, "change_every": 3}
	else:
		model.weather_settings = {"mode": "fixed", "weather": key}


## user://maps/<clean name>.json for the current map name.
func _custom_map_path() -> String:
	var clean := model.map_name.strip_edges().to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "custom_map"
	return CUSTOM_MAPS_DIR + clean + ".json"


func _on_save_pressed() -> void:
	# Validate before writing so on-disk maps are always loadable (import is strict).
	var res := model.to_map_resource()
	var validation: Dictionary = res.validate_map()
	if not validation.get("valid", false):
		_set_status("Not saved - " + "; ".join(validation.get("issues", [])))
		return
	var path := _custom_map_path()
	# Multi-floor problems the loader tolerates (warnings) or the author should fix.
	var errors := model.validate().filter(func(i): return i["level"] == "error")
	if model.save_to_json_file(path):
		_set_status("Saved: " + path + ("" if errors.is_empty() else "  (%d validation errors!)" % errors.size()))
	else:
		_set_status("Save failed: " + path)


func _on_load_pressed() -> void:
	var path := _custom_map_path()
	var loaded := MapMakerModel.load_from_json_file(path)
	if loaded == null:
		_set_status("Load failed (missing or invalid): " + path)
		return
	load_model(loaded)
	_set_status("Loaded: " + path)


## Replace the edited model (used by Load, and handy for tools / screenshots).
func load_model(m: MapMakerModel) -> void:
	model = m
	_link_from = Cells.INVALID
	current_floor = clampi(current_floor, 0, MapMakerModel.MAX_FLOOR)
	if _name_edit:
		_name_edit.text = model.map_name
		_author_edit.text = model.author
		_desc_edit.text = model.description
		_width_spin.value = model.width
		_height_spin.value = model.height
	_sync_weather_option()
	_rebuild_grid()
	_build_world_3d()
	_refresh_export_state()
	_refresh_all()


## Package the current map into a validated challenge: write user://challenges/<name>.json
## AND copy a share code to the clipboard. The map's player-2+ spawns become the AI defense.
func _on_export_challenge_pressed() -> void:
	if _challenge_defender_count() < 1:
		_set_status("Export needs at least one enemy defender: place your units on a player 2+ slot (with a character) first.")
		return

	var res := model.to_map_resource()
	# Structural validity is required for the map to load in a challenge; import is strict.
	var validation: Dictionary = res.validate_map()
	if not validation.get("valid", false):
		_set_status("Not exported - " + "; ".join(validation.get("issues", [])))
		return

	var squad_size := int(_challenge_squad_spin.value) if _challenge_squad_spin != null else 4
	var rules := {
		"challenger_squad_size": squad_size,
		# Phase A: the creator has no turn-system / difficulty pickers, so field sane
		# defaults (Traditional turns, Normal AI). Authors tune these in a later phase.
		"turn_system": int(TurnSystemBase.TurnSystemType.TRADITIONAL),
		"ai_difficulty": 1,
		"mode": _selected_challenge_mode(),
		# survive_turns always ships (the codec clamps and stores it either way) so an author
		# who flips a saved challenge to Survive later keeps the number they picked.
		"survive_turns": int(_challenge_survive_spin.value) if _challenge_survive_spin != null \
			else ChallengeCodec.DEFAULT_SURVIVE_TURNS,
		"par_turns": int(_challenge_par_spin.value) if _challenge_par_spin != null \
			else ChallengeCodec.default_par_for(_challenge_defender_count()),
	}
	var created := Time.get_datetime_string_from_system()
	var challenge := ChallengeCodec.build_challenge(res, model.map_name, model.author, created, rules)

	var errors := ChallengeCodec.validate(challenge)
	if not errors.is_empty():
		_set_status("Not exported - " + "; ".join(errors))
		return

	var path := ChallengeCodec.save_to_file(challenge)
	if path.is_empty():
		_set_status("Export failed: could not write the challenge file.")
		return

	var code := ChallengeCodec.encode(challenge)
	DisplayServer.clipboard_set(code)
	_set_status("Exported challenge to %s and copied the share code to your clipboard (%d chars)." % [path, code.length()])


## The mode id the OptionButton is showing ("breach" | "survive"), defaulting to breach.
func _selected_challenge_mode() -> String:
	if _challenge_mode_option == null:
		return ChallengeCodec.DEFAULT_MODE
	return ChallengeCodec.MODE_SURVIVE if _challenge_mode_option.selected == 1 \
		else ChallengeCodec.MODE_BREACH


## Show the rounds-to-survive spinbox only while Survive is the selected mode.
func _on_challenge_mode_selected(_index: int) -> void:
	if _challenge_survive_row != null:
		_challenge_survive_row.visible = _selected_challenge_mode() == ChallengeCodec.MODE_SURVIVE


## Any AUTHOR edit of par pins it, so the defender-count seeding stops overwriting it.
func _on_challenge_par_changed(_value: float) -> void:
	if not _seeding_par:
		_challenge_par_touched = true


## Seed par from the defense size (the same default the codec would apply) while the author
## has not set it themselves. Called as defenders are placed/removed, so par tracks the map
## until the moment the author takes it over.
func _seed_par_from_defenders(defenders: int) -> void:
	if _challenge_par_spin == null or _challenge_par_touched:
		return
	_seeding_par = true
	_challenge_par_spin.value = ChallengeCodec.default_par_for(defenders)
	_seeding_par = false


## Refresh the Export button's enabled state + a hint when it is off. A challenge is only
## meaningful once the map carries a player-2+ defender that names a character.
func _refresh_export_state() -> void:
	if _export_challenge_btn == null:
		return
	var defenders := _challenge_defender_count()
	_seed_par_from_defenders(defenders)
	_export_challenge_btn.disabled = defenders < 1
	_export_challenge_btn.tooltip_text = "" if defenders >= 1 else \
		"Place at least one of your units on a player 2+ slot to define the AI defense."


## Count player-2+ spawns that name a character (the AI defenders of a challenge), on
## every floor. Reads the model's spawn store directly so it stays cheap during
## drag-painting.
func _challenge_defender_count() -> int:
	var count := 0
	for spawn in model._spawns.values():
		if int(spawn.get("player_id", 0)) >= 1 and not String(spawn.get("character_id", "")).strip_edges().is_empty():
			count += 1
	return count


# =============================================================================
#  Small UI helpers
# =============================================================================

func _add_tool_button(container: Node, text: String, tool_id: int, group: ButtonGroup) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(func():
		_select_tool(tool_id)
		_set_status("Tool: " + text))
	container.add_child(button)
	_tool_buttons[tool_id] = button


## Make [param tool_id] the active tool. Leaving Link drops a half-made link; leaving
## Rect drops a pending rectangle.
func _select_tool(tool_id: int) -> void:
	_current_tool = tool_id
	if tool_id != Tool.RECT_FILL and _rect_anchor != NO_CELL:
		_rect_anchor = NO_CELL
		_rect_hover = NO_CELL
	if tool_id != Tool.LINK and _link_from != Cells.INVALID:
		_link_from = Cells.INVALID
		_refresh_all()
	_highlight_tool_buttons()


## The active tool's toggle button reads pressed and every other one released.
func _highlight_tool_buttons() -> void:
	for tool_id in _tool_buttons.keys():
		var button: Button = _tool_buttons[tool_id]
		if button:
			button.set_pressed_no_signal(tool_id == _current_tool)


func _entry_color(entry: Dictionary) -> Color:
	var value = entry.get("color", Color.WHITE)
	return value if value is Color else Color.WHITE


func _selected_swatch_color() -> Color:
	for entry in _tile_palette_entries:
		if str(entry.get("tile_id", "")) == _selected_tile_id and str(entry.get("type_name", "")) == _selected_tile_type:
			return _entry_color(entry)
	return TILE_COLORS.get(_selected_tile_type, Color.WHITE)


func _player_color(player_id: int) -> Color:
	var value = PLAYER_COLORS.get(player_id, Color.WHITE)
	return value if value is Color else Color.WHITE


## The key / button to SHOW for [param action] right now (follows rebinding and the
## active device, via [method InputActions.hint]); [param fallback] when unbound.
func _hint(action: StringName, fallback: String) -> String:
	var k := InputActions.hint(action)
	return fallback if k.is_empty() else k


## The keyboard ([param pad] false) or gamepad binding of [param action] for a
## MenuKit.key_hint cap; [param fallback] when unbound.
func _key_for(action: StringName, pad: bool, fallback: String) -> String:
	var k := InputActions.describe(action, pad)
	return fallback if k.is_empty() else k


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _make_spin(min_value: float, max_value: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = value
	return spin
