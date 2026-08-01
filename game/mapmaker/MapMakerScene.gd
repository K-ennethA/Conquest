extends Control

class_name MapMakerScene

## In-game Map Maker UI.
##
## Two editing surfaces sit side by side:
##   * LEFT  - a 2D button grid (paint / rect fill / bucket fill / erase / spawn /
##             objective), the tile palette, the spawn-point config and the map
##             metadata + save/load controls.
##   * RIGHT - a LIVE 3D preview inside a SubViewport that renders the map with the
##             real tile model scenes (the same way the editor dock and MapGallery
##             do), updating incrementally on every edit.
##
## All editing state lives in [MapMakerModel] (a pure, tested RefCounted); this class
## only builds the UI, translates input into model calls, and mirrors the result onto
## the two views. The 3D rendering logic is PORTED from addons/map_creator/
## map_creator_dock.gd but reads from the model rather than a MapResource, and uses no
## Editor-only APIs so it runs in the shipped game.

## Directory player-authored maps are saved to / loaded from, as inert JSON.
const CUSTOM_MAPS_DIR := "user://maps/"

## Editing tools available on the grid.
enum Tool { PAINT, RECT_FILL, BUCKET_FILL, ERASE, SPAWN, OBJECTIVE }

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

var model: MapMakerModel

# --- selection / tool state --------------------------------------------------
var _current_tool: int = Tool.PAINT
var _selected_tile_type: String = "NORMAL"
var _selected_tile_path: String = ""
var _selected_tile_id: String = ""
var _current_player_id: int = 0
var _selected_spawn_kind: String = MapResource.SPAWN_KIND_START
var _selected_character_id: String = ""
var _brush_size: int = 1

# One entry per palette button: {type_name, resource_path, tile_id, color, display_name}
var _tile_palette_entries: Array[Dictionary] = []

# --- 2D grid state -----------------------------------------------------------
var _grid_width: int = 0
var _grid_height: int = 0
var _cell_buttons: Dictionary = {}  # Vector2i -> Button
var _is_painting: bool = false
var _rect_anchor: Vector2i = NO_CELL
var _rect_hover: Vector2i = NO_CELL

# --- UI references ------------------------------------------------------------
var _width_spin: SpinBox
var _height_spin: SpinBox
var _player_spin: SpinBox
var _brush_spin: SpinBox
var _grid_container: GridContainer
var _status_label: Label
var _name_edit: LineEdit
var _author_edit: LineEdit
var _desc_edit: TextEdit
var _spawn_kind_option: OptionButton
var _character_option: OptionButton
var _tool_buttons: Dictionary = {}  # Tool -> Button

# --- 3D preview references ----------------------------------------------------
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _tile_visuals: Dictionary = {}   # Vector2i -> Node3D
var _spawn_meshes: Dictionary = {}   # Vector2i -> MeshInstance3D
var _objective_meshes: Dictionary = {}  # Vector2i -> MeshInstance3D
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


func _ready() -> void:
	if model == null:
		model = MapMakerModel.new(8, 8)
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_load_tile_palette_entries()
	_build_ui()
	_rebuild_grid()
	_build_world_3d()


func _input(event: InputEvent) -> void:
	# ESC returns to the menu (edits live in the model; saving is explicit).
	if event.is_pressed() and event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_go_back()
		return

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


# =============================================================================
#  UI construction
# =============================================================================

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_build_header(root)

	# Body: authoring column (left) | 3D preview (right).
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.split_offset = 460
	root.add_child(body)

	_build_left_column(body)
	_build_preview_column(body)


func _build_header(root: VBoxContainer) -> void:
	var header := PanelContainer.new()
	root.add_child(header)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	header.add_child(bar)

	# Back button (top-left) - the missing "back button" the request called out.
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(_go_back)
	bar.add_child(back_btn)

	var title := Label.new()
	title.text = "MAP CREATOR"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MenuTheme.style_title(title, MenuTheme.FONT_DISPLAY)
	bar.add_child(title)

	# A spacer that mirrors the Back button's width keeps the title visually centred.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(90, 0)
	bar.add_child(spacer)


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
	_build_save_load_section(col)


func _build_metadata_section(col: VBoxContainer) -> void:
	col.add_child(_section_label("MAP INFO"))

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
	col.add_child(_section_label("TOOLS"))

	var row := HBoxContainer.new()
	col.add_child(row)
	_add_tool_button(row, "Paint", Tool.PAINT)
	_add_tool_button(row, "Rect", Tool.RECT_FILL)
	_add_tool_button(row, "Bucket", Tool.BUCKET_FILL)
	_add_tool_button(row, "Erase", Tool.ERASE)

	var row2 := HBoxContainer.new()
	col.add_child(row2)
	_add_tool_button(row2, "Spawn", Tool.SPAWN)
	_add_tool_button(row2, "Objective", Tool.OBJECTIVE)
	row2.add_child(_make_label("  Brush:"))
	_brush_spin = _make_spin(1, 3, _brush_size)
	_brush_spin.value_changed.connect(func(v: float): _brush_size = int(v))
	row2.add_child(_brush_spin)

	_highlight_tool_buttons()


func _build_palette_section(col: VBoxContainer) -> void:
	col.add_child(_section_label("TILE PALETTE"))

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
	col.add_child(_section_label("SPAWN / OBJECTIVE"))

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
	col.add_child(_section_label("MAP GRID  (drag to paint, right-click erases)"))
	var wrap := ScrollContainer.new()
	wrap.custom_minimum_size = Vector2(0, 220)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(wrap)
	_grid_container = GridContainer.new()
	wrap.add_child(_grid_container)


func _build_save_load_section(col: VBoxContainer) -> void:
	col.add_child(_section_label("SAVE / LOAD"))
	var row := HBoxContainer.new()
	col.add_child(row)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed)
	row.add_child(load_btn)

	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.text = "Ready."
	col.add_child(_status_label)


func _build_preview_column(body: HSplitContainer) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(col)

	col.add_child(_section_label("3D PREVIEW  (drag to orbit, wheel to zoom)"))

	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_disable_input = true
	_viewport_container.add_child(_viewport)

	_setup_viewport_world()

	_viewport_container.gui_input.connect(_on_preview_gui_input)


# =============================================================================
#  Tile palette
# =============================================================================

func _load_tile_palette_entries() -> void:
	## Build the palette from the REAL TileResource files (via TileCatalog), so a
	## painted cell records an actual stable tile_id. Falls back to the tile-type
	## strings if no resources are found, so the palette is never empty.
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
	_current_tool = Tool.PAINT
	_highlight_tool_buttons()
	_set_status("Tile: " + str(entry.get("display_name", _selected_tile_type)))


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

	for y in range(model.height):
		for x in range(model.width):
			var pos := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(30, 30)
			button.focus_mode = Control.FOCUS_NONE
			button.gui_input.connect(_on_cell_gui_input.bind(pos))
			button.mouse_entered.connect(_on_cell_mouse_entered.bind(pos))
			_grid_container.add_child(button)
			_cell_buttons[pos] = button
			_paint_cell_button(pos)


func _on_cell_gui_input(event: InputEvent, pos: Vector2i) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		_apply_brush(pos, _erase_at)
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	match _current_tool:
		Tool.RECT_FILL:
			_rect_anchor = pos
			_rect_hover = pos
			_tint_rect_preview()
		Tool.BUCKET_FILL:
			_bucket_fill_at(pos)
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


func _apply_brush(pos: Vector2i, action: Callable) -> void:
	for dy in range(_brush_size):
		for dx in range(_brush_size):
			var target := Vector2i(pos.x + dx, pos.y + dy)
			if not model.is_in_bounds(target):
				continue
			action.call(target)
			_refresh_cell(target)


func _paint_at(pos: Vector2i) -> void:
	model.paint_tile(pos, _selected_tile_type, _selected_tile_path, _selected_tile_id)


func _erase_at(pos: Vector2i) -> void:
	model.erase_tile(pos)
	model.remove_spawn(pos)
	model.remove_objective(pos)


func _toggle_spawn_at(pos: Vector2i) -> void:
	if model.get_spawn(pos).is_empty():
		model.place_spawn_point(pos, _current_player_id, _selected_spawn_kind, {
			"character_id": _selected_character_id,
		})
	else:
		model.remove_spawn(pos)
	_refresh_cell(pos)


func _toggle_objective_at(pos: Vector2i) -> void:
	if model.get_objective(pos).is_empty():
		model.set_objective(pos, "THRONE", _current_player_id)
	else:
		model.remove_objective(pos)
	_refresh_cell(pos)


func _bucket_fill_at(pos: Vector2i) -> void:
	if not model.is_in_bounds(pos):
		return
	var target_type: String = str(model.get_tile(pos).get("tile_type", "NORMAL"))
	if target_type == _selected_tile_type:
		return
	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [pos]
	visited[pos] = true
	while stack.size() > 0:
		var cell: Vector2i = stack.pop_back()
		if str(model.get_tile(cell).get("tile_type", "NORMAL")) != target_type:
			continue
		model.paint_tile(cell, _selected_tile_type, _selected_tile_path, _selected_tile_id)
		_refresh_cell(cell)
		for neighbor in [Vector2i(cell.x + 1, cell.y), Vector2i(cell.x - 1, cell.y),
				Vector2i(cell.x, cell.y + 1), Vector2i(cell.x, cell.y - 1)]:
			if model.is_in_bounds(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				stack.append(neighbor)


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
		model.paint_tile(cell, _selected_tile_type, _selected_tile_path, _selected_tile_id)
		_refresh_cell(cell)


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
	## The single sync point: repaint the 2D button AND the one 3D cell. Every edit
	## path funnels through here, so the two views can never drift and a stroke never
	## triggers a full 3D rebuild.
	_paint_cell_button(pos)
	_refresh_cell_3d(pos)


func _paint_cell_button(pos: Vector2i) -> void:
	var button: Button = _cell_buttons.get(pos)
	if button == null:
		return
	var spawn: Dictionary = model.get_spawn(pos)
	var objective: Dictionary = model.get_objective(pos)
	if not spawn.is_empty():
		var kind: String = str(spawn.get("spawn_kind", MapResource.SPAWN_KIND_START))
		var badge: String = str(SPAWN_KIND_INITIALS.get(kind, "S"))
		badge += str(int(spawn.get("player_id", 0)))
		button.text = badge
		_apply_swatch(button, _player_color(int(spawn.get("player_id", 0))))
	elif not objective.is_empty():
		button.text = "*"
		_apply_swatch(button, Color(0.95, 0.85, 0.35))
	else:
		button.text = ""
		_apply_swatch(button, _tile_color_at(pos))


func _apply_swatch(button: Button, color: Color) -> void:
	## Paint the button as a solid colour swatch. modulate alone only tints the dark
	## theme's stylebox, washing distinct tile colours into near-identical greys, so
	## the styleboxes are overridden with the real colour plus a thin border.
	button.modulate = Color.WHITE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box := StyleBoxFlat.new()
		box.bg_color = color
		if state == "hover":
			box.bg_color = color.lightened(0.15)
		elif state == "pressed":
			box.bg_color = color.darkened(0.15)
		box.set_border_width_all(1)
		box.border_color = Color(0, 0, 0, 0.4)
		button.add_theme_stylebox_override(state, box)


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
	env.background_color = Color(0.09, 0.09, 0.12, 1.0)
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
	_tile_visuals.clear()
	_spawn_meshes.clear()
	_objective_meshes.clear()

	var cols: int = maxi(model.width, 1)
	var rows: int = maxi(model.height, 1)
	_world_span = maxf(float(cols), float(rows)) * TILE_STEP
	_cam_distance = _world_span * 1.15
	_aim_camera()

	for y in range(rows):
		for x in range(cols):
			var pos := Vector2i(x, y)
			_create_tile_visual(pos)
			_sync_spawn_marker(pos)
			_sync_objective_marker(pos)


func _refresh_cell_3d(pos: Vector2i) -> void:
	if _world_root == null or not model.is_in_bounds(pos):
		return
	if _tile_visuals.has(pos):
		var stale: Node3D = _tile_visuals[pos]
		if is_instance_valid(stale):
			var parent := stale.get_parent()
			if parent:
				parent.remove_child(stale)
			stale.queue_free()
		_tile_visuals.erase(pos)
	_create_tile_visual(pos)
	_sync_spawn_marker(pos)
	_sync_objective_marker(pos)


func _create_tile_visual(pos: Vector2i) -> void:
	var visual: Node3D = _instantiate_tile_model(pos)
	if visual == null:
		var mesh := BoxMesh.new()
		mesh.size = TILE_MESH_SIZE
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _solid_material(_tile_color_at(pos))
		visual = mi
	_world_root.add_child(visual)
	visual.position = _world_position_for(pos, 0.0)
	_tile_visuals[pos] = visual


func _sync_spawn_marker(pos: Vector2i) -> void:
	var spawn: Dictionary = model.get_spawn(pos)
	if spawn.is_empty():
		if _spawn_meshes.has(pos):
			var stale: MeshInstance3D = _spawn_meshes[pos]
			if is_instance_valid(stale):
				stale.queue_free()
			_spawn_meshes.erase(pos)
		return
	var player_id: int = int(spawn.get("player_id", 0))
	var kind: String = str(spawn.get("spawn_kind", MapResource.SPAWN_KIND_START))
	var color: Color = _player_color(player_id)
	var scale_value: float = float(SPAWN_KIND_MARKER_SCALE.get(kind, 1.0))
	var radius: float = SPAWN_RADIUS * scale_value

	if _spawn_meshes.has(pos):
		var existing: MeshInstance3D = _spawn_meshes[pos]
		if is_instance_valid(existing):
			var mat := existing.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = color
			var sphere := existing.mesh as SphereMesh
			if sphere:
				sphere.radius = radius
				sphere.height = radius * 2.0
			return
		_spawn_meshes.erase(pos)

	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = _solid_material(color)
	marker.position = _world_position_for(pos, SPAWN_Y)
	_world_root.add_child(marker)
	_spawn_meshes[pos] = marker


func _sync_objective_marker(pos: Vector2i) -> void:
	var objective: Dictionary = model.get_objective(pos)
	if objective.is_empty():
		if _objective_meshes.has(pos):
			var stale: MeshInstance3D = _objective_meshes[pos]
			if is_instance_valid(stale):
				stale.queue_free()
			_objective_meshes.erase(pos)
		return
	if _objective_meshes.has(pos):
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.35, 0.7, 0.35)
	var marker := MeshInstance3D.new()
	marker.mesh = mesh
	marker.material_override = _solid_material(Color(0.95, 0.85, 0.35))
	marker.position = _world_position_for(pos, OBJECTIVE_Y)
	_world_root.add_child(marker)
	_objective_meshes[pos] = marker


# --- 3D tile resolution (mirrors MapLoader / the dock) -----------------------

func _tile_resource_at(pos: Vector2i) -> TileResource:
	var tile: Dictionary = model.get_tile(pos)
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


func _tile_model_path_at(pos: Vector2i) -> String:
	var resolved := _tile_resource_at(pos)
	if resolved != null:
		return resolved.model_path
	_build_type_model_paths()
	var tile: Dictionary = model.get_tile(pos)
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


func _instantiate_tile_model(pos: Vector2i) -> Node3D:
	var packed := _load_tile_model(_tile_model_path_at(pos))
	if packed == null:
		return null
	var instance = packed.instantiate()
	if instance is Node3D:
		return instance as Node3D
	if instance:
		instance.free()
	return null


func _tile_color_at(pos: Vector2i) -> Color:
	var resolved := _tile_resource_at(pos)
	if resolved != null:
		return resolved.base_color
	var tile: Dictionary = model.get_tile(pos)
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
	_current_tool = Tool.SPAWN
	_highlight_tool_buttons()


func _on_character_selected(index: int) -> void:
	var meta = _character_option.get_item_metadata(index)
	_selected_character_id = str(meta) if meta != null else ""
	_current_tool = Tool.SPAWN
	_highlight_tool_buttons()


func _on_resize_pressed() -> void:
	model.set_dimensions(int(_width_spin.value), int(_height_spin.value))
	_rebuild_grid()
	_build_world_3d()
	_set_status("Resized to %dx%d" % [model.width, model.height])


func _on_save_pressed() -> void:
	# Validate before writing so on-disk maps are always loadable (import is strict).
	var res := model.to_map_resource()
	var validation: Dictionary = res.validate_map()
	if not validation.get("valid", false):
		_set_status("Not saved - " + "; ".join(validation.get("issues", [])))
		return
	var clean := model.map_name.strip_edges().to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "custom_map"
	var path := CUSTOM_MAPS_DIR + clean + ".json"
	if model.save_to_json_file(path):
		_set_status("Saved: " + path)
	else:
		_set_status("Save failed: " + path)


func _on_load_pressed() -> void:
	var clean := model.map_name.strip_edges().to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "custom_map"
	var path := CUSTOM_MAPS_DIR + clean + ".json"
	var loaded := MapMakerModel.load_from_json_file(path)
	if loaded == null:
		_set_status("Load failed (missing or invalid): " + path)
		return
	model = loaded
	_name_edit.text = model.map_name
	_author_edit.text = model.author
	_desc_edit.text = model.description
	_width_spin.value = model.width
	_height_spin.value = model.height
	_rebuild_grid()
	_build_world_3d()
	_set_status("Loaded: " + path)


func _go_back() -> void:
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


# =============================================================================
#  Small UI helpers
# =============================================================================

func _add_tool_button(container: Node, text: String, tool_id: int) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(func():
		_current_tool = tool_id
		_highlight_tool_buttons()
		_set_status("Tool: " + text))
	container.add_child(button)
	_tool_buttons[tool_id] = button


func _highlight_tool_buttons() -> void:
	for tool_id in _tool_buttons.keys():
		var button: Button = _tool_buttons[tool_id]
		if button:
			button.theme_type_variation = "SelectedButton" if tool_id == _current_tool else &""


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


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


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
