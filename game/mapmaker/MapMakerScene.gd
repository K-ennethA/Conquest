extends Control

class_name MapMakerScene

## In-game Map Maker UI.
##
## A simple, functional Control that lets a designer choose a grid size, pick a
## tile from a palette (built from the existing tile resources), paint on a grid
## preview, place spawns / objective markers, and save or load a [MapResource].
##
## MULTI-FLOOR: a floor selector ([ - ] Floor N [ + ], or Page Up / Page Down)
## picks the floor being edited; the floor below shows through ghosted so decks
## line up with what they span. On any floor you can paint / erase tiles, place
## spawns, mark STAIRS (a direction; they climb to the next floor) and add explicit
## LINKS (click the from-cell, change floor if needed, click the to-cell; clicking
## an existing link's ends again removes it). The validation list under the grid
## flags spawns on air, links / stairs into missing cells and unreachable decks.
##
## All editing logic is delegated to [MapMakerModel]; this class only builds the
## UI and translates clicks into model calls, so the heavy logic stays testable.

## Directory scanned for palette tile resources (recursively: biome folders).
const TILE_RESOURCE_DIR := "res://game/tiles/resources"
## Directory maps are saved to / loaded from.
const MAP_RESOURCE_DIR := "res://game/maps/resources"

## Editing tools available on the grid.
enum Tool { PAINT, ERASE, SPAWN, OBJECTIVE, STAIRS, LINK }

## Colors used to tint preview cells per tile type.
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

const STAIR_GLYPHS := { "north": "▲", "south": "▼", "east": "▶", "west": "◀" }
const STAIR_DIRS := ["north", "east", "south", "west"]
const LINK_KINDS := ["stairs", "ladder", "ramp"]
const CELL_SIZE := 38

var model: MapMakerModel

var _current_tool: int = Tool.PAINT
var _selected_tile_type: String = "NORMAL"
var _selected_tile_path: String = ""
var _selected_tile_id: String = ""
var _current_player_id: int = 0
## Floor being edited (0 = ground).
var current_floor: int = 0
var _stair_dir: String = "east"
var _link_kind: String = "stairs"
var _link_cost: int = 1
## First click of a link (Cells.INVALID when none pending).
var _link_from: Vector3i = Cells.INVALID
## tile_id -> base colour, for palette-resource tiles.
var _id_colors: Dictionary = {}

# UI references (built in _build_ui).
var _width_spin: SpinBox
var _height_spin: SpinBox
var _player_spin: SpinBox
var _grid_container: GridContainer
var _status_label: Label
var _name_edit: LineEdit
var _floor_label: Label
var _issues_label: RichTextLabel
var _tool_buttons: Dictionary = {}  # Tool -> Button
var _cell_buttons: Dictionary = {}  # Vector2i -> Button


func _ready() -> void:
	if model == null:
		model = MapMakerModel.new(5, 5)
	_build_ui()
	_rebuild_grid()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.11, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	# --- Top toolbar: name + dimensions ---------------------------------
	var top := HBoxContainer.new()
	root.add_child(top)

	top.add_child(_make_label("Name:"))
	_name_edit = LineEdit.new()
	_name_edit.text = model.map_name
	_name_edit.custom_minimum_size = Vector2(160, 0)
	_name_edit.text_changed.connect(func(t): model.map_name = t)
	top.add_child(_name_edit)

	top.add_child(_make_label("Width:"))
	_width_spin = _make_spin(1, MapResource.MAX_MAP_SIZE, model.width)
	top.add_child(_width_spin)

	top.add_child(_make_label("Height:"))
	_height_spin = _make_spin(1, MapResource.MAX_MAP_SIZE, model.height)
	top.add_child(_height_spin)

	var resize_btn := Button.new()
	resize_btn.text = "Resize"
	resize_btn.pressed.connect(_on_resize_pressed)
	top.add_child(resize_btn)

	# --- Floor selector ---------------------------------------------------
	top.add_child(_make_label("   Floor:"))
	var down_btn := Button.new()
	down_btn.text = " - "
	down_btn.tooltip_text = "Edit the floor below (Page Down)"
	down_btn.pressed.connect(func(): set_floor(current_floor - 1))
	top.add_child(down_btn)
	_floor_label = _make_label("")
	_floor_label.custom_minimum_size = Vector2(170, 0)
	_floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_floor_label)
	var up_btn := Button.new()
	up_btn.text = " + "
	up_btn.tooltip_text = "Edit the floor above (Page Up)"
	up_btn.pressed.connect(func(): set_floor(current_floor + 1))
	top.add_child(up_btn)

	# --- Tool + player selectors ----------------------------------------
	var tools := HBoxContainer.new()
	root.add_child(tools)
	tools.add_child(_make_label("Tool:"))
	var group := ButtonGroup.new()
	_add_tool_button(tools, "Paint", Tool.PAINT, group)
	_add_tool_button(tools, "Erase", Tool.ERASE, group)
	_add_tool_button(tools, "Spawn", Tool.SPAWN, group)
	_add_tool_button(tools, "Objective", Tool.OBJECTIVE, group)
	_add_tool_button(tools, "Stairs", Tool.STAIRS, group)
	_add_tool_button(tools, "Link", Tool.LINK, group)
	tools.add_child(_make_label("  Player:"))
	_player_spin = _make_spin(0, 7, 0)
	_player_spin.value_changed.connect(func(v): _current_player_id = int(v))
	tools.add_child(_player_spin)

	tools.add_child(_make_label("  Stairs climb:"))
	var dir_opt := OptionButton.new()
	for d in STAIR_DIRS:
		dir_opt.add_item("%s %s" % [STAIR_GLYPHS[d], d.capitalize()])
	dir_opt.select(STAIR_DIRS.find(_stair_dir))
	dir_opt.item_selected.connect(func(i): _stair_dir = STAIR_DIRS[i])
	tools.add_child(dir_opt)

	tools.add_child(_make_label("  Link:"))
	var kind_opt := OptionButton.new()
	for k in LINK_KINDS:
		kind_opt.add_item(k.capitalize())
	kind_opt.item_selected.connect(func(i): _link_kind = LINK_KINDS[i])
	tools.add_child(kind_opt)
	tools.add_child(_make_label("cost"))
	var cost_spin := _make_spin(1, 5, 1)
	cost_spin.value_changed.connect(func(v): _link_cost = int(v))
	tools.add_child(cost_spin)
	_select_tool(Tool.PAINT)

	# --- Tile palette ----------------------------------------------------
	var palette_label := _make_label("Tile Palette:")
	root.add_child(palette_label)
	var palette_scroll := ScrollContainer.new()
	palette_scroll.custom_minimum_size = Vector2(0, 44)
	palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(palette_scroll)
	var palette := HBoxContainer.new()
	palette_scroll.add_child(palette)
	_build_palette(palette)

	# --- Grid preview + validation -----------------------------------------
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 12)
	root.add_child(middle)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(scroll)

	_grid_container = GridContainer.new()
	_grid_container.add_theme_constant_override("h_separation", 2)
	_grid_container.add_theme_constant_override("v_separation", 2)
	scroll.add_child(_grid_container)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(330, 0)
	middle.add_child(side)
	side.add_child(_make_label("Legend:  P# spawn   * objective   ▲▶▼◀ stairs (climb)\n  ⇅ link end   · air (floor below ghosted)"))
	side.add_child(_make_label("Validation:"))
	_issues_label = RichTextLabel.new()
	_issues_label.bbcode_enabled = true
	_issues_label.fit_content = false
	_issues_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_issues_label)

	# --- Save / load bar -------------------------------------------------
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_pressed)
	bottom.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_on_load_pressed)
	bottom.add_child(load_btn)

	_status_label = Label.new()
	_status_label.text = "Ready"
	bottom.add_child(_status_label)
	_refresh_floor_label()


func _build_palette(container: HBoxContainer) -> void:
	# Palette entries from the standard tile-type strings.
	for tile_type in TILE_COLORS.keys():
		var button := Button.new()
		button.text = String(tile_type).capitalize()
		button.modulate = TILE_COLORS[tile_type]
		button.pressed.connect(_on_palette_type_selected.bind(String(tile_type)))
		container.add_child(button)

	# Palette entries from existing tile .tres resources (reused, not reinvented).
	for path in _scan_tile_resources():
		var res := load(path) as TileResource
		if res == null:
			continue
		_id_colors[String(res.id)] = res.base_color
		var button := Button.new()
		button.text = res.tile_name if not res.tile_name.is_empty() else path.get_file()
		button.modulate = res.base_color.lightened(0.25)
		button.pressed.connect(_on_palette_resource_selected.bind(path, res))
		container.add_child(button)


func _scan_tile_resources() -> Array[String]:
	# TileCatalog walks the biome sub-folders (forest/, common/, structures/...).
	var paths: Array[String] = []
	for p in TileCatalog.all_paths():
		paths.append(p)
	return paths


func _rebuild_grid() -> void:
	if _grid_container == null:
		return
	for child in _grid_container.get_children():
		child.queue_free()
	_cell_buttons.clear()

	_grid_container.columns = max(1, model.width)
	# Row 0 at the TOP, like the battle camera (north / row 0 is the far side).
	for y in range(model.height):
		for x in range(model.width):
			var pos := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			button.add_theme_font_size_override("font_size", 12)
			button.pressed.connect(_on_cell_pressed.bind(pos))
			button.tooltip_text = "(%d, %d)" % [x, y]
			_grid_container.add_child(button)
			_cell_buttons[pos] = button
	_refresh_all()


func _refresh_all() -> void:
	for pos in _cell_buttons:
		_refresh_cell(pos)
	_refresh_issues()
	_refresh_floor_label()


func _tile_color(tile: Dictionary) -> Color:
	var id := str(tile.get("tile_id", ""))
	if not id.is_empty() and _id_colors.has(id):
		return (_id_colors[id] as Color).lightened(0.25)
	var path := str(tile.get("tile_resource_path", ""))
	if not path.is_empty():
		var res := TileCatalog.find(path)
		if res != null:
			return res.base_color.lightened(0.25)
	return TILE_COLORS.get(str(tile.get("tile_type", "NORMAL")), Color.WHITE)


func _refresh_cell(pos: Vector2i) -> void:
	var button: Button = _cell_buttons.get(pos)
	if button == null:
		return
	var f := current_floor
	var parts: PackedStringArray = []
	if model.has_tile(pos, f):
		_style_cell(button, _tile_color(model.get_tile(pos, f)), false)
		var st := model.get_stairs(pos, f)
		if not st.is_empty():
			parts.append(STAIR_GLYPHS.get(st, "S"))
	else:
		# Air: show the floor below, ghosted, so the deck can be lined up with it.
		var below := f - 1
		while below > 0 and not model.has_tile(pos, below):
			below -= 1
		_style_cell(button, _tile_color(model.get_tile(pos, maxi(below, 0))), true)
		parts.append("·")
	var spawn := model.get_spawn(pos, f)
	if not spawn.is_empty():
		parts.append("P%d" % int(spawn.get("player_id", 0)))
	if f == 0 and not model.get_objective(pos).is_empty():
		parts.append("*")
	var cell := Vector3i(pos.x, pos.y, f)
	if not model.get_links_at(cell).is_empty():
		parts.append("⇅")
	if cell == _link_from:
		parts.append("①")
	button.text = " ".join(parts)
	var tip := "(%d, %d) floor %d" % [pos.x, pos.y, f]
	for l in model.get_links_at(cell):
		var other: Vector3i = l["to"] if l["from"] == cell else l["from"]
		tip += "\n%s to (%d, %d) floor %d, cost %d" % [str(l["kind"]).capitalize(), other.x, other.y, other.z, int(l["cost"])]
	button.tooltip_text = tip


## Paint a grid cell: a flat swatch of the tile colour; [param ghost] (air on an
## upper floor) shows the floor below faded toward the background with a dashed-
## looking thin border.
func _style_cell(button: Button, color: Color, ghost: bool) -> void:
	var bg := Color(0.13, 0.11, 0.1)
	var fill := bg.lerp(color, 0.28) if ghost else color
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = color.darkened(0.2) if not ghost else Color(color, 0.35)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.border_color = Color(1.0, 0.85, 0.35)
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", sb)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Color(0.08, 0.06, 0.04) if not ghost and fill.get_luminance() > 0.45 else Color(0.95, 0.92, 0.85)
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.modulate = Color.WHITE


func _refresh_issues() -> void:
	if _issues_label == null:
		return
	var issues := model.validate()
	if issues.is_empty():
		_issues_label.text = "[color=#8fd18f]No problems found.[/color]"
		return
	var lines: PackedStringArray = []
	for i in issues:
		var col := "#ff7b6b" if i["level"] == "error" else "#f0c05a"
		lines.append("[color=%s]%s[/color] %s" % [col, String(i["level"]).to_upper(), i["message"]])
	_issues_label.text = "\n".join(lines)


func _refresh_floor_label() -> void:
	if _floor_label == null:
		return
	var count := model.get_floor_count() if model != null else 1
	_floor_label.text = "%d  (%s)  · %d in use" % [current_floor, FloorNav.floor_name(current_floor, maxi(count, current_floor + 1)), count]


## Switch the floor being edited (0 .. MapMakerModel.MAX_FLOOR).
func set_floor(f: int) -> void:
	current_floor = clampi(f, 0, MapMakerModel.MAX_FLOOR)
	_refresh_all()
	_set_status("Editing floor %d" % current_floor)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			set_floor(current_floor + 1)
			accept_event()
		elif event.keycode == KEY_PAGEDOWN:
			set_floor(current_floor - 1)
			accept_event()


func _on_cell_pressed(pos: Vector2i) -> void:
	var f := current_floor
	var cell := Vector3i(pos.x, pos.y, f)
	match _current_tool:
		Tool.PAINT:
			model.paint_tile(pos, _selected_tile_type, _selected_tile_path, f, _selected_tile_id)
		Tool.ERASE:
			model.erase_tile(pos, f)
			model.remove_spawn(pos, f)
			model.remove_links_at(cell)
			if f == 0:
				model.remove_objective(pos)
		Tool.SPAWN:
			if model.get_spawn(pos, f).is_empty():
				model.place_spawn(pos, _current_player_id, "WARRIOR", "", f)
			else:
				model.remove_spawn(pos, f)
		Tool.OBJECTIVE:
			if f != 0:
				_set_status("Objectives live on the ground floor")
			elif model.get_objective(pos).is_empty():
				model.set_objective(pos, "THRONE", _current_player_id)
			else:
				model.remove_objective(pos)
		Tool.STAIRS:
			var cur := model.get_stairs(pos, f)
			var want := "" if cur == _stair_dir else _stair_dir
			if model.set_stairs(pos, want, f):
				_set_status("Stairs cleared" if want.is_empty() else "Stairs climb %s to floor %d" % [want, f + 1])
			else:
				_set_status("Paint a tile here before adding stairs")
		Tool.LINK:
			_link_click(cell)
	_refresh_all()


## Two-click link authoring: first click picks the from-cell, the second (on any
## floor) the to-cell. Re-linking the same pair removes the link.
func _link_click(cell: Vector3i) -> void:
	if _link_from == Cells.INVALID:
		_link_from = cell
		_set_status("Link from (%d, %d) floor %d -- now click the other end (change floor if needed)" % [cell.x, cell.y, cell.z])
		return
	var from := _link_from
	_link_from = Cells.INVALID
	if from == cell:
		_set_status("Link cancelled")
		return
	if model.remove_link(from, cell):
		_set_status("Link removed")
		return
	if model.add_link(from, cell, _link_cost, _link_kind):
		_set_status("%s linked: %s -> %s" % [_link_kind.capitalize(), str(from), str(cell)])
	else:
		_set_status("Could not link those cells")


func _on_palette_type_selected(tile_type: String) -> void:
	_selected_tile_type = tile_type
	_selected_tile_path = ""
	_selected_tile_id = ""
	_select_tool(Tool.PAINT)
	_set_status("Selected tile: " + tile_type)


func _on_palette_resource_selected(path: String, res: TileResource) -> void:
	_selected_tile_type = Tile.TileType.keys()[res.tile_type]
	_selected_tile_path = path
	_selected_tile_id = String(res.id)
	_select_tool(Tool.PAINT)
	_set_status("Selected tile resource: " + res.tile_name)


func _add_tool_button(container: Node, text: String, tool_id: int, group: ButtonGroup) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.pressed.connect(func():
		_select_tool(tool_id)
		_set_status("Tool: " + text)
	)
	container.add_child(button)
	_tool_buttons[tool_id] = button


func _select_tool(tool_id: int) -> void:
	_current_tool = tool_id
	if tool_id != Tool.LINK and _link_from != Cells.INVALID:
		_link_from = Cells.INVALID
		_refresh_all()
	var b: Button = _tool_buttons.get(tool_id)
	if b != null:
		b.set_pressed_no_signal(true)


func _on_resize_pressed() -> void:
	model.set_dimensions(int(_width_spin.value), int(_height_spin.value))
	_rebuild_grid()
	_set_status("Resized to %dx%d" % [model.width, model.height])


func _on_save_pressed() -> void:
	var clean := model.map_name.to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "custom_map"
	var path := MAP_RESOURCE_DIR.path_join(clean + ".tres")
	var errors := model.validate().filter(func(i): return i["level"] == "error")
	if model.save_to_file(path):
		_set_status("Saved: " + path + ("" if errors.is_empty() else "  (%d validation errors!)" % errors.size()))
	else:
		_set_status("Save failed")


func _on_load_pressed() -> void:
	var clean := model.map_name.to_lower().replace(" ", "_")
	var path := MAP_RESOURCE_DIR.path_join(clean + ".tres")
	var loaded := MapMakerModel.load_from_file(path)
	if loaded == null:
		_set_status("Load failed: " + path)
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
		_width_spin.value = model.width
		_height_spin.value = model.height
	_rebuild_grid()


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
