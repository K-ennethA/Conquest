extends Control

class_name MapMakerScene

## In-game Map Maker UI.
##
## A simple, functional Control that lets a designer choose a grid size, pick a
## tile from a palette (built from the existing tile resources), paint on a grid
## preview, place spawns / objective markers, and save or load a [MapResource].
##
## All editing logic is delegated to [MapMakerModel]; this class only builds the
## UI and translates clicks into model calls, so the heavy logic stays testable.

## Directory scanned for palette tile resources.
const TILE_RESOURCE_DIR := "res://game/tiles/resources"
## Directory maps are saved to / loaded from.
const MAP_RESOURCE_DIR := "res://game/maps/resources"

## Editing tools available on the grid.
enum Tool { PAINT, ERASE, SPAWN, OBJECTIVE }

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

var model: MapMakerModel

var _current_tool: int = Tool.PAINT
var _selected_tile_type: String = "NORMAL"
var _selected_tile_path: String = ""
var _current_player_id: int = 0

# UI references (built in _build_ui).
var _width_spin: SpinBox
var _height_spin: SpinBox
var _player_spin: SpinBox
var _grid_container: GridContainer
var _status_label: Label
var _name_edit: LineEdit
var _cell_buttons: Dictionary = {}  # Vector2i -> Button


func _ready() -> void:
	if model == null:
		model = MapMakerModel.new(5, 5)
	_build_ui()
	_rebuild_grid()


func _input(event: InputEvent) -> void:
	# The creator is reached from the main menu, so it needs a way back out.
	# ESC returns to the menu (edits live in the model; saving is explicit).
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

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
	_width_spin = _make_spin(1, 20, model.width)
	top.add_child(_width_spin)

	top.add_child(_make_label("Height:"))
	_height_spin = _make_spin(1, 20, model.height)
	top.add_child(_height_spin)

	var resize_btn := Button.new()
	resize_btn.text = "Resize"
	resize_btn.pressed.connect(_on_resize_pressed)
	top.add_child(resize_btn)

	# --- Tool + player selectors ----------------------------------------
	var tools := HBoxContainer.new()
	root.add_child(tools)
	tools.add_child(_make_label("Tool:"))
	_add_tool_button(tools, "Paint", Tool.PAINT)
	_add_tool_button(tools, "Erase", Tool.ERASE)
	_add_tool_button(tools, "Spawn", Tool.SPAWN)
	_add_tool_button(tools, "Objective", Tool.OBJECTIVE)
	tools.add_child(_make_label("  Player:"))
	_player_spin = _make_spin(0, 7, 0)
	_player_spin.value_changed.connect(func(v): _current_player_id = int(v))
	tools.add_child(_player_spin)

	# --- Tile palette ----------------------------------------------------
	var palette_label := _make_label("Tile Palette:")
	root.add_child(palette_label)
	var palette := HBoxContainer.new()
	root.add_child(palette)
	_build_palette(palette)

	# --- Grid preview ----------------------------------------------------
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_grid_container = GridContainer.new()
	scroll.add_child(_grid_container)

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
		var button := Button.new()
		button.text = res.tile_name if not res.tile_name.is_empty() else path.get_file()
		button.modulate = res.base_color
		button.pressed.connect(_on_palette_resource_selected.bind(path, res))
		container.add_child(button)


func _scan_tile_resources() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(TILE_RESOURCE_DIR)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres") and not file_name.begins_with("."):
			paths.append(TILE_RESOURCE_DIR.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	return paths


func _rebuild_grid() -> void:
	if _grid_container == null:
		return
	for child in _grid_container.get_children():
		child.queue_free()
	_cell_buttons.clear()

	_grid_container.columns = max(1, model.width)
	# Display rows top-to-bottom so higher y is lower on screen.
	for y in range(model.height - 1, -1, -1):
		for x in range(model.width):
			var pos := Vector2i(x, y)
			var button := Button.new()
			button.custom_minimum_size = Vector2(36, 36)
			button.pressed.connect(_on_cell_pressed.bind(pos))
			_grid_container.add_child(button)
			_cell_buttons[pos] = button
			_refresh_cell(pos)


func _refresh_cell(pos: Vector2i) -> void:
	var button: Button = _cell_buttons.get(pos)
	if button == null:
		return
	var tile := model.get_tile(pos)
	var tile_type: String = tile.get("tile_type", "NORMAL")
	button.modulate = TILE_COLORS.get(tile_type, Color.WHITE)

	var label := ""
	if not model.get_spawn(pos).is_empty():
		label = "P%d" % model.get_spawn(pos).get("player_id", 0)
	elif not model.get_objective(pos).is_empty():
		label = "*"
	button.text = label


func _on_cell_pressed(pos: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT:
			model.paint_tile(pos, _selected_tile_type, _selected_tile_path)
		Tool.ERASE:
			model.erase_tile(pos)
			model.remove_spawn(pos)
			model.remove_objective(pos)
		Tool.SPAWN:
			if model.get_spawn(pos).is_empty():
				model.place_spawn(pos, _current_player_id, "WARRIOR")
			else:
				model.remove_spawn(pos)
		Tool.OBJECTIVE:
			if model.get_objective(pos).is_empty():
				model.set_objective(pos, "THRONE", _current_player_id)
			else:
				model.remove_objective(pos)
	_refresh_cell(pos)


func _on_palette_type_selected(tile_type: String) -> void:
	_selected_tile_type = tile_type
	_selected_tile_path = ""
	_current_tool = Tool.PAINT
	_set_status("Selected tile: " + tile_type)


func _on_palette_resource_selected(path: String, res: TileResource) -> void:
	_selected_tile_type = Tile.TileType.keys()[res.tile_type]
	_selected_tile_path = path
	_current_tool = Tool.PAINT
	_set_status("Selected tile resource: " + res.tile_name)


func _add_tool_button(container: Node, text: String, tool_id: int) -> void:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.pressed.connect(func():
		_current_tool = tool_id
		_set_status("Tool: " + text)
	)
	container.add_child(button)


func _on_resize_pressed() -> void:
	model.set_dimensions(int(_width_spin.value), int(_height_spin.value))
	_rebuild_grid()
	_set_status("Resized to %dx%d" % [model.width, model.height])


func _on_save_pressed() -> void:
	var clean := model.map_name.to_lower().replace(" ", "_")
	if clean.is_empty():
		clean = "custom_map"
	var path := MAP_RESOURCE_DIR.path_join(clean + ".tres")
	if model.save_to_file(path):
		_set_status("Saved: " + path)
	else:
		_set_status("Save failed")


func _on_load_pressed() -> void:
	var clean := model.map_name.to_lower().replace(" ", "_")
	var path := MAP_RESOURCE_DIR.path_join(clean + ".tres")
	var loaded := MapMakerModel.load_from_file(path)
	if loaded == null:
		_set_status("Load failed: " + path)
		return
	model = loaded
	_name_edit.text = model.map_name
	_width_spin.value = model.width
	_height_spin.value = model.height
	_rebuild_grid()
	_set_status("Loaded: " + path)


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
