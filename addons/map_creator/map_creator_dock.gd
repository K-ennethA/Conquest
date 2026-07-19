@tool
extends Control

# Map Creator Dock - Visual interface for creating maps
#
# Two editing surfaces stay in sync at all times:
#   * the 2D button grid (original surface - strokes, brushes, rect/bucket fill)
#   * a live 3D world view (SubViewport) that mirrors MapGallery's presentation
#     and additionally accepts palette drag-and-drop and direct painting.

# --- Tile resource palette ----------------------------------------------------
# The palette is built from the REAL TileResource files so the map records an
# actual resource path, not just a loose type string.
const TILES_DIR := "res://game/tiles/resources/"

# --- 3D world view tuning (ported verbatim from MapGallery) -------------------
const TILE_STEP := 2.0
const TILE_MESH_SIZE := Vector3(1.8, 0.3, 1.8)
const SPAWN_RADIUS := 0.35
const SPAWN_Y := 0.5  # sits on top of the tile surface

# Sentinel returned by the ray->cell pick when the ray misses the ground plane.
const NO_CELL := Vector2i(-1, -1)

# --- Spawn points -------------------------------------------------------------
# A map defines spawn POINTS, not baked-in units: a cell, the player slot that owns
# it, and what kind of spawning it does. The unit reference is optional - a "Start"
# point without one is an empty slot filled at match setup.
const NO_UNIT_TYPE := ""
const NO_UNIT_LABEL := "(none / assigned at match setup)"

# One-letter badge drawn on the 2D grid so a cell's kind reads at a glance.
const SPAWN_KIND_INITIALS := {
	"Start": "S",
	"Respawn": "R",
	"Endless": "E",
	"Reinforcement": "F"
}

# 3D marker radius multiplier per kind, so the world view distinguishes them too
# (colour still encodes the player slot).
const SPAWN_KIND_MARKER_SCALE := {
	"Start": 1.0,
	"Respawn": 1.35,
	"Endless": 1.6,
	"Reinforcement": 0.7
}

# UI Elements
var scroll_container: ScrollContainer
var main_container: VBoxContainer

# Map Info Section
var map_name_input: LineEdit
var description_input: TextEdit
var author_input: LineEdit
var difficulty_option: OptionButton
var map_type_option: OptionButton
var status_option: OptionButton

# Map Size Section
var width_input: SpinBox
var height_input: SpinBox
var resize_button: Button

# Tile Palette Section
var tile_palette_container: VBoxContainer
var tile_buttons: Array[Button] = []
var selected_tile_type: String = "NORMAL"
# Resource path of the selected palette entry ("" when the hardcoded fallback is used)
var selected_tile_resource_path: String = ""
# One entry per palette button: {type_name: String, resource_path: String,
#                                color: Color, display_name: String}
var tile_palette_entries: Array[Dictionary] = []
# type_name -> Color, harvested from the real TileResource.base_color values.
var resource_tile_colors: Dictionary = {}

# Unit Palette Section
var unit_palette_container: VBoxContainer
var unit_buttons: Array[Button] = []
var selected_unit_type: String = "WARRIOR"
var selected_player_id: int = 0
var player_selector: OptionButton
# Palette values in button order: "" (the no-unit slot) followed by unit_types.
var unit_palette_values: Array[String] = []

# Spawn Point Section - the configuration a newly placed spawn point is stamped with
var spawn_kind_option: OptionButton
var respawn_interval_input: SpinBox
var max_spawns_input: SpinBox
var spawn_turn_input: SpinBox
var selected_spawn_kind: String = MapResource.SPAWN_KIND_START
var selected_respawn_interval: int = 1
var selected_max_spawns: int = 1
var selected_spawn_turn: int = 1

# Map Grid Section
var grid_container: GridContainer
var grid_buttons: Array[Button] = []
var current_map: MapResource

# Tool Mode Section
var tool_mode_option: OptionButton
var clear_grid_button: Button
var fill_all_button: Button
var brush_size_input: SpinBox

# Painting State (drag-to-paint strokes)
var _is_painting: bool = false          # True between a left press on a cell and the left release
var _rect_anchor: Vector2i = Vector2i(-1, -1)   # Anchor cell for the Rect Fill drag, (-1,-1) when idle
var _rect_hover: Vector2i = Vector2i(-1, -1)    # Last hovered cell while dragging a rect (for tint cleanup)
var _grid_width: int = 0                # Dimensions the current grid_buttons array was built with
var _grid_height: int = 0
var _last_world_cell: Vector2i = NO_CELL # Last cell painted during a 3D-view stroke

# 3D World View Section
var world_viewport_container: SubViewportContainer
var world_viewport: SubViewport
var world_root: Node3D
var world_camera: Camera3D
var _world_span: float = TILE_STEP
# Cell -> mesh lookups so a stroke can repaint one cell instead of rebuilding.
var _tile_meshes: Dictionary = {}
var _spawn_meshes: Dictionary = {}

# Preview Section
var preview_container: VBoxContainer
var map_info_label: Label

# Action Buttons
var new_map_button: Button
var save_map_button: Button
var load_map_button: Button
var test_map_button: Button
var save_template_button: Button
var load_template_button: Button
var save_status_label: Label

# Data
var tile_types = ["NORMAL", "DIFFICULT_TERRAIN", "WATER", "WALL", "SPECIAL", "LAVA", "ICE", "SWAMP", "SACRED_GROUND", "CORRUPTED"]
var unit_types = ["WARRIOR", "ARCHER", "MAGE"]
var difficulties = ["Easy", "Normal", "Hard", "Expert"]
var map_types = ["Skirmish", "Campaign", "Custom"]
var map_statuses = ["Active", "Inactive"]
var tool_modes = ["Place Tiles", "Place Spawn", "Rect Fill", "Bucket Fill", "Erase"]

# Colors for visual feedback
var tile_colors = {
	"NORMAL": Color.WHITE,
	"DIFFICULT_TERRAIN": Color(0.6, 0.4, 0.2),
	"WATER": Color(0.2, 0.4, 0.8),
	"WALL": Color(0.3, 0.3, 0.3),
	"SPECIAL": Color(0.8, 0.8, 0.2),
	"LAVA": Color(1.0, 0.2, 0.0),
	"ICE": Color(0.8, 0.9, 1.0),
	"SWAMP": Color(0.3, 0.5, 0.2),
	"SACRED_GROUND": Color(1.0, 1.0, 0.9),
	"CORRUPTED": Color(0.4, 0.2, 0.4)
}

var unit_colors = {
	0: Color.BLUE,    # Player 1
	1: Color.RED,     # Player 2
	2: Color.GREEN,   # Player 3
	3: Color.YELLOW   # Player 4
}

func _init():
	name = "MapCreator"
	set_custom_minimum_size(Vector2(400, 800))
	_create_ui()
	_create_new_map()

func _create_ui():
	"""Create the complete UI for the map creator"""
	# Main scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll_container)
	
	main_container = VBoxContainer.new()
	main_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll_container.add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "MAP CREATOR"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)
	
	_add_separator()
	
	# Create sections
	_create_map_info_section()
	_add_separator()
	_create_map_size_section()
	_add_separator()
	_create_tool_mode_section()
	_add_separator()
	_create_tile_palette_section()
	_add_separator()
	_create_unit_palette_section()
	_add_separator()
	_create_map_grid_section()
	_add_separator()
	_create_world_3d_section()
	_add_separator()
	_create_preview_section()
	_add_separator()
	_create_action_buttons()

func _add_separator():
	"""Add a visual separator"""
	var separator = HSeparator.new()
	main_container.add_child(separator)

func _create_map_info_section():
	"""Create map information input section"""
	var section_label = Label.new()
	section_label.text = "MAP INFORMATION"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Map Name
	var name_label = Label.new()
	name_label.text = "Map Name:"
	main_container.add_child(name_label)
	
	map_name_input = LineEdit.new()
	map_name_input.placeholder_text = "e.g., Desert Battlefield"
	map_name_input.text_changed.connect(_on_map_info_changed)
	main_container.add_child(map_name_input)
	
	# Author
	var author_label = Label.new()
	author_label.text = "Author:"
	main_container.add_child(author_label)
	
	author_input = LineEdit.new()
	author_input.placeholder_text = "Your name"
	author_input.text_changed.connect(_on_map_info_changed)
	main_container.add_child(author_input)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = "Description:"
	main_container.add_child(desc_label)
	
	description_input = TextEdit.new()
	description_input.placeholder_text = "Enter map description..."
	description_input.custom_minimum_size = Vector2(0, 60)
	description_input.text_changed.connect(_on_map_info_changed)
	main_container.add_child(description_input)
	
	# Difficulty and Type
	var properties_container = HBoxContainer.new()
	main_container.add_child(properties_container)
	
	var diff_container = VBoxContainer.new()
	properties_container.add_child(diff_container)
	
	var diff_label = Label.new()
	diff_label.text = "Difficulty:"
	diff_container.add_child(diff_label)
	
	difficulty_option = OptionButton.new()
	for difficulty in difficulties:
		difficulty_option.add_item(difficulty)
	difficulty_option.selected = 1  # Normal
	difficulty_option.item_selected.connect(_on_map_info_changed)
	diff_container.add_child(difficulty_option)
	
	var type_container = VBoxContainer.new()
	properties_container.add_child(type_container)
	
	var type_label = Label.new()
	type_label.text = "Map Type:"
	type_container.add_child(type_label)
	
	map_type_option = OptionButton.new()
	for map_type in map_types:
		map_type_option.add_item(map_type)
	map_type_option.selected = 0  # Skirmish
	map_type_option.item_selected.connect(_on_map_info_changed)
	type_container.add_child(map_type_option)

	# Status: "Inactive" is a work-in-progress draft -- it saves without needing to
	# be playable yet and stays out of the in-game map lists. "Active" publishes it
	# to players, and is only allowed once the map actually validates.
	var status_container = VBoxContainer.new()
	properties_container.add_child(status_container)

	var status_label = Label.new()
	status_label.text = "Status:"
	status_container.add_child(status_label)

	status_option = OptionButton.new()
	for status_name in map_statuses:
		status_option.add_item(status_name)
	status_option.selected = 1  # Inactive - new maps start as drafts
	status_option.item_selected.connect(_on_map_info_changed)
	status_container.add_child(status_option)

func _create_map_size_section():
	"""Create map size configuration section"""
	var section_label = Label.new()
	section_label.text = "MAP SIZE"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	var size_container = HBoxContainer.new()
	main_container.add_child(size_container)
	
	# Width
	var width_container = VBoxContainer.new()
	size_container.add_child(width_container)
	
	var width_label = Label.new()
	width_label.text = "Width:"
	width_container.add_child(width_label)
	
	# Bounds come from MapResource so the creator can never author a size that
	# validate_map() would then reject.
	width_input = SpinBox.new()
	width_input.min_value = MapResource.MIN_MAP_SIZE
	width_input.max_value = MapResource.MAX_MAP_SIZE
	width_input.value = 5
	width_container.add_child(width_input)
	
	# Height
	var height_container = VBoxContainer.new()
	size_container.add_child(height_container)
	
	var height_label = Label.new()
	height_label.text = "Height:"
	height_container.add_child(height_label)
	
	height_input = SpinBox.new()
	height_input.min_value = MapResource.MIN_MAP_SIZE
	height_input.max_value = MapResource.MAX_MAP_SIZE
	height_input.value = 5
	height_container.add_child(height_input)
	
	# Resize Button
	resize_button = Button.new()
	resize_button.text = "RESIZE GRID"
	resize_button.pressed.connect(_on_resize_grid)
	size_container.add_child(resize_button)

func _create_tool_mode_section():
	"""Create tool mode selection section"""
	var section_label = Label.new()
	section_label.text = "TOOL MODE"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	var tool_container = HBoxContainer.new()
	main_container.add_child(tool_container)
	
	tool_mode_option = OptionButton.new()
	for mode in tool_modes:
		tool_mode_option.add_item(mode)
	tool_mode_option.selected = 0  # Place Tiles
	tool_mode_option.item_selected.connect(_on_tool_mode_changed)
	tool_container.add_child(tool_mode_option)
	
	clear_grid_button = Button.new()
	clear_grid_button.text = "CLEAR ALL"
	clear_grid_button.pressed.connect(_on_clear_grid)
	tool_container.add_child(clear_grid_button)

	fill_all_button = Button.new()
	fill_all_button.text = "FILL ALL"
	fill_all_button.tooltip_text = "Set every tile to the selected tile type (unit spawns are kept)"
	fill_all_button.pressed.connect(_on_fill_all)
	tool_container.add_child(fill_all_button)

	# Brush size row - painting applies to an NxN block anchored at the clicked cell
	var brush_container = HBoxContainer.new()
	main_container.add_child(brush_container)

	var brush_label = Label.new()
	brush_label.text = "Brush Size:"
	brush_container.add_child(brush_label)

	brush_size_input = SpinBox.new()
	brush_size_input.min_value = 1
	brush_size_input.max_value = 5
	brush_size_input.value = 1
	brush_size_input.tooltip_text = "Paints an NxN block with the clicked cell as the top-left corner"
	brush_container.add_child(brush_size_input)

	var hint_label = Label.new()
	hint_label.text = "(drag to paint, right-click to erase)"
	brush_container.add_child(hint_label)

func _load_tile_palette_entries() -> void:
	"""Scan res://game/tiles/resources/ and build one palette entry per TileResource.

	Each entry records the enum NAME string (e.g. "LAVA"), the .tres path and the
	resource's real base_color. Falls back to the legacy hardcoded type list when
	the directory is missing or contains no usable TileResource, so the palette is
	never empty.
	"""
	tile_palette_entries.clear()
	resource_tile_colors.clear()

	var type_names: Array = Tile.TileType.keys()

	if DirAccess.dir_exists_absolute(TILES_DIR):
		var dir := DirAccess.open(TILES_DIR)
		if dir:
			var file_names: Array[String] = []
			dir.list_dir_begin()
			var file_name := dir.get_next()
			while file_name != "":
				if file_name.ends_with(".tres"):
					file_names.append(file_name)
				file_name = dir.get_next()
			dir.list_dir_end()

			# Stable, readable ordering regardless of filesystem enumeration order.
			file_names.sort()

			for entry_name in file_names:
				var resource_path: String = TILES_DIR + entry_name
				if not ResourceLoader.exists(resource_path):
					continue
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

				tile_palette_entries.append({
					"type_name": type_name,
					"resource_path": resource_path,
					"color": tile_resource.base_color,
					"display_name": display_name
				})
				# Last resource for a type wins; good enough for display purposes.
				resource_tile_colors[type_name] = tile_resource.base_color

	if not tile_palette_entries.is_empty():
		return

	# Fallback: the original hardcoded type list, with no resource path attached.
	for fallback_type in tile_types:
		var fallback_name: String = str(fallback_type)
		tile_palette_entries.append({
			"type_name": fallback_name,
			"resource_path": "",
			"color": tile_colors.get(fallback_name, Color.WHITE),
			"display_name": fallback_name.replace("_", " ")
		})

func _create_tile_palette_section():
	"""Create tile selection palette from the real TileResource files"""
	var section_label = Label.new()
	section_label.text = "TILE PALETTE"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)

	tile_palette_container = VBoxContainer.new()
	main_container.add_child(tile_palette_container)

	_load_tile_palette_entries()

	# Create tile buttons in rows of 3
	var current_row: HBoxContainer = null
	for i in range(tile_palette_entries.size()):
		if i % 3 == 0:
			current_row = HBoxContainer.new()
			tile_palette_container.add_child(current_row)

		var entry: Dictionary = tile_palette_entries[i]
		var button = Button.new()
		button.text = str(entry.get("display_name", "Tile"))
		button.custom_minimum_size = Vector2(80, 30)
		button.modulate = _entry_color(entry)
		button.tooltip_text = "Click to select, or drag into the 3D world to paint"
		button.pressed.connect(_on_tile_selected.bind(i))
		# Palette buttons are drag sources only - they never accept drops
		button.set_drag_forwarding(_tile_palette_get_drag_data.bind(i), Callable(), Callable())

		if current_row:
			current_row.add_child(button)
		tile_buttons.append(button)

	# Select first tile by default
	if tile_buttons.size() > 0:
		_on_tile_selected(0)

func _create_unit_palette_section():
	"""Create unit placement palette"""
	var section_label = Label.new()
	section_label.text = "UNIT PALETTE"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	unit_palette_container = VBoxContainer.new()
	main_container.add_child(unit_palette_container)
	
	# Player selector
	var player_container = HBoxContainer.new()
	unit_palette_container.add_child(player_container)
	
	var player_label = Label.new()
	player_label.text = "Player:"
	player_container.add_child(player_label)
	
	player_selector = OptionButton.new()
	for i in range(4):
		player_selector.add_item("Player " + str(i + 1))
	player_selector.selected = 0
	player_selector.item_selected.connect(_on_player_selected)
	player_container.add_child(player_selector)
	
	# Unit type buttons. The first entry is the EMPTY slot: a spawn point placed with
	# it selected records no unit reference, which is how a map author says "this is
	# player 2's second slot, whoever they bring to the match fills it".
	unit_palette_values.clear()
	unit_palette_values.append(NO_UNIT_TYPE)
	for unit_type in unit_types:
		unit_palette_values.append(str(unit_type))

	var unit_row = HBoxContainer.new()
	unit_palette_container.add_child(unit_row)

	for i in range(unit_palette_values.size()):
		var palette_value: String = unit_palette_values[i]
		var button = Button.new()
		button.text = _unit_display_name(palette_value)
		button.custom_minimum_size = Vector2(80, 30)
		button.modulate = unit_colors.get(selected_player_id, Color.WHITE)
		button.tooltip_text = "Click to select, or drag onto the grid to place a spawn point"
		button.pressed.connect(_on_unit_selected.bind(palette_value))
		# Palette buttons are drag sources only - they never accept drops
		button.set_drag_forwarding(_palette_get_drag_data.bind(palette_value), Callable(), Callable())

		unit_row.add_child(button)
		unit_buttons.append(button)

	# Default to the first real unit type, so existing authoring habits are unchanged.
	if not unit_types.is_empty():
		_on_unit_selected(str(unit_types[0]))
	elif not unit_palette_values.is_empty():
		_on_unit_selected(unit_palette_values[0])

	_create_spawn_point_section()

func _create_spawn_point_section():
	"""Controls describing WHAT KIND of spawn point the next placement creates.

	Fields that do not apply to the chosen kind are disabled rather than hidden, so
	the UI teaches which settings matter for which kind.
	"""
	var section_label = Label.new()
	section_label.text = "SPAWN POINT"
	section_label.add_theme_font_size_override("font_size", 14)
	unit_palette_container.add_child(section_label)

	# Spawn kind
	var kind_row = HBoxContainer.new()
	unit_palette_container.add_child(kind_row)

	var kind_label = Label.new()
	kind_label.text = "Spawn Kind:"
	kind_row.add_child(kind_label)

	spawn_kind_option = OptionButton.new()
	for kind in MapResource.SPAWN_KINDS:
		spawn_kind_option.add_item(str(kind))
	spawn_kind_option.selected = 0  # Start
	spawn_kind_option.tooltip_text = "Start = placed at map load. Respawn/Endless = keeps producing units. Reinforcement = arrives on a later turn."
	spawn_kind_option.item_selected.connect(_on_spawn_kind_selected)
	kind_row.add_child(spawn_kind_option)

	# Numeric settings
	var settings_row = HBoxContainer.new()
	unit_palette_container.add_child(settings_row)

	var interval_container = VBoxContainer.new()
	settings_row.add_child(interval_container)

	var interval_label = Label.new()
	interval_label.text = "Respawn Interval:"
	interval_container.add_child(interval_label)

	respawn_interval_input = SpinBox.new()
	respawn_interval_input.min_value = 1
	respawn_interval_input.max_value = 20
	respawn_interval_input.value = selected_respawn_interval
	respawn_interval_input.tooltip_text = "Turns between spawns (Respawn / Endless only)"
	respawn_interval_input.value_changed.connect(_on_respawn_interval_changed)
	interval_container.add_child(respawn_interval_input)

	var max_container = VBoxContainer.new()
	settings_row.add_child(max_container)

	var max_label = Label.new()
	max_label.text = "Max Spawns:"
	max_container.add_child(max_label)

	max_spawns_input = SpinBox.new()
	max_spawns_input.min_value = -1
	max_spawns_input.max_value = 99
	max_spawns_input.value = selected_max_spawns
	max_spawns_input.tooltip_text = "Units this point may ever produce (-1 = unlimited)"
	max_spawns_input.value_changed.connect(_on_max_spawns_changed)
	max_container.add_child(max_spawns_input)

	var turn_container = VBoxContainer.new()
	settings_row.add_child(turn_container)

	var turn_label = Label.new()
	turn_label.text = "Spawn Turn:"
	turn_container.add_child(turn_label)

	spawn_turn_input = SpinBox.new()
	spawn_turn_input.min_value = 1
	spawn_turn_input.max_value = 99
	spawn_turn_input.value = selected_spawn_turn
	spawn_turn_input.tooltip_text = "Turn this point activates (Reinforcement only)"
	spawn_turn_input.value_changed.connect(_on_spawn_turn_changed)
	turn_container.add_child(spawn_turn_input)

	_update_spawn_controls_enabled()

func _create_map_grid_section():
	"""Create the interactive map grid"""
	var section_label = Label.new()
	section_label.text = "MAP GRID"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	grid_container = GridContainer.new()
	grid_container.columns = 5  # Will be updated when grid is created
	main_container.add_child(grid_container)
	
	_create_grid()

func _create_world_3d_section():
	"""Create the live 3D world view (SubViewport) and make it a drop target"""
	var section_label = Label.new()
	section_label.text = "3D WORLD"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)

	var hint_label = Label.new()
	hint_label.text = "(drag palette tiles/units in, or paint directly)"
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_container.add_child(hint_label)

	world_viewport_container = SubViewportContainer.new()
	world_viewport_container.custom_minimum_size = Vector2(320, 320)
	world_viewport_container.stretch = true
	world_viewport_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	# The container itself must receive mouse events so drops and painting work.
	world_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	main_container.add_child(world_viewport_container)

	world_viewport = SubViewport.new()
	world_viewport.size = Vector2i(320, 320)
	world_viewport.transparent_bg = false
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Nothing inside the viewport consumes input; the container handles it all.
	world_viewport.gui_disable_input = true
	world_viewport_container.add_child(world_viewport)

	_setup_world_viewport()

	# Drop target only - the 3D view is never a drag source.
	world_viewport_container.set_drag_forwarding(
		Callable(), _world_can_drop_data, _world_drop_data)
	world_viewport_container.gui_input.connect(_on_world_gui_input)

	# Build whatever map already exists (normally nothing yet at UI-build time).
	_build_world_3d()

func _create_preview_section():
	"""Create map preview and info section"""
	var section_label = Label.new()
	section_label.text = "MAP PREVIEW"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	preview_container = VBoxContainer.new()
	main_container.add_child(preview_container)
	
	map_info_label = Label.new()
	map_info_label.text = "Map info will appear here..."
	map_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_container.add_child(map_info_label)
	
	_update_preview()

func _create_action_buttons():
	"""Create action buttons section"""
	var button_container = VBoxContainer.new()
	main_container.add_child(button_container)
	
	# Main actions row
	var main_row = HBoxContainer.new()
	main_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(main_row)
	
	new_map_button = Button.new()
	new_map_button.text = "NEW"
	new_map_button.custom_minimum_size = Vector2(80, 40)
	new_map_button.pressed.connect(_on_new_map)
	main_row.add_child(new_map_button)
	
	save_map_button = Button.new()
	save_map_button.text = "SAVE"
	save_map_button.custom_minimum_size = Vector2(80, 40)
	save_map_button.pressed.connect(_on_save_map)
	main_row.add_child(save_map_button)
	
	load_map_button = Button.new()
	load_map_button.text = "LOAD"
	load_map_button.custom_minimum_size = Vector2(80, 40)
	load_map_button.pressed.connect(_on_load_map)
	main_row.add_child(load_map_button)
	
	# Template actions row
	var template_row = HBoxContainer.new()
	template_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(template_row)
	
	save_template_button = Button.new()
	save_template_button.text = "SAVE TEMPLATE"
	save_template_button.custom_minimum_size = Vector2(100, 30)
	save_template_button.pressed.connect(_on_save_template)
	template_row.add_child(save_template_button)
	
	load_template_button = Button.new()
	load_template_button.text = "LOAD TEMPLATE"
	load_template_button.custom_minimum_size = Vector2(100, 30)
	load_template_button.pressed.connect(_on_load_template)
	template_row.add_child(load_template_button)
	
	# Test button (separate row)
	var test_row = HBoxContainer.new()
	test_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(test_row)
	
	test_map_button = Button.new()
	test_map_button.text = "TEST MAP"
	test_map_button.custom_minimum_size = Vector2(120, 40)
	test_map_button.pressed.connect(_on_test_map)
	test_row.add_child(test_map_button)

	# Status line: save/load used to report ONLY via print(), so a refused save
	# looked like the button did nothing. Every outcome now shows up right here.
	save_status_label = Label.new()
	save_status_label.text = ""
	save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status_label.custom_minimum_size = Vector2(0, 0)
	button_container.add_child(save_status_label)

func _create_grid():
	"""Create the interactive grid for map editing"""
	# Clear existing grid
	for button in grid_buttons:
		if button:
			button.queue_free()
	grid_buttons.clear()

	# Rebuilding invalidates any in-flight stroke or rect drag
	_is_painting = false
	_rect_anchor = Vector2i(-1, -1)
	_rect_hover = Vector2i(-1, -1)
	_last_world_cell = NO_CELL

	var width = int(width_input.value)
	var height = int(height_input.value)

	_grid_width = width
	_grid_height = height
	grid_container.columns = width

	# Create grid buttons
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			var button = Button.new()
			button.custom_minimum_size = Vector2(30, 30)
			button.text = ""
			button.modulate = Color.WHITE

			# Store position in button metadata
			button.set_meta("grid_pos", pos)
			# Stroke input: press starts a stroke, hover continues it while held
			button.gui_input.connect(_on_grid_cell_gui_input.bind(pos))
			button.mouse_entered.connect(_on_grid_cell_mouse_entered.bind(pos))
			# Cells are both drop targets (palette units) and drag sources (existing spawns)
			button.set_drag_forwarding(
				_grid_get_drag_data.bind(pos),
				_grid_can_drop_data.bind(pos),
				_grid_drop_data.bind(pos)
			)

			grid_container.add_child(button)
			grid_buttons.append(button)

	_update_grid_display()
	# New map / load / resize all funnel through here, so the 3D view rebuilds once.
	_build_world_3d()

func _create_new_map():
	"""Create a new empty map"""
	current_map = MapResource.new()
	current_map.map_name = "New Map"
	current_map.author = "Map Creator"
	current_map.width = 5
	current_map.height = 5
	# New maps start as drafts, so they can be saved long before they are playable.
	current_map.status = "Inactive"
	current_map.create_default_layout()
	
	_update_ui_from_map()

# Signal handlers
func _on_resize_grid():
	"""Handle grid resize"""
	var new_width = int(width_input.value)
	var new_height = int(height_input.value)
	
	if current_map:
		current_map.width = new_width
		current_map.height = new_height
		
		# Recreate layout with new size
		current_map.create_default_layout()
		
		# Clear unit spawns that are out of bounds
		var valid_spawns: Array[Dictionary] = []
		for spawn in current_map.unit_spawns:
			var pos = spawn.get("position", Vector2i(-1, -1))
			if pos.x < new_width and pos.y < new_height:
				valid_spawns.append(spawn)
		current_map.unit_spawns = valid_spawns
	
	_create_grid()
	_update_preview()

func _on_tool_mode_changed(index: int):
	"""Handle tool mode change"""
	# Abandon any gesture that belonged to the previous tool
	_is_painting = false
	if _rect_anchor != Vector2i(-1, -1):
		_rect_anchor = Vector2i(-1, -1)
		_rect_hover = Vector2i(-1, -1)
		_update_grid_display()

	print("Tool mode changed to: " + tool_modes[index])

func _entry_color(entry: Dictionary) -> Color:
	"""Colour of a palette entry, guarded against a malformed dictionary"""
	var value: Variant = entry.get("color", Color.WHITE)
	if value is Color:
		return value as Color
	return Color.WHITE

func _tile_color_for(type_name: String) -> Color:
	"""Display colour for a tile type - the real resource colour wins, then the
	legacy hardcoded map, then white."""
	if resource_tile_colors.has(type_name):
		var value: Variant = resource_tile_colors[type_name]
		if value is Color:
			return value as Color

	var fallback: Variant = tile_colors.get(type_name, Color.WHITE)
	if fallback is Color:
		return fallback as Color

	return Color.WHITE

func _on_tile_selected(index: int):
	"""Handle tile palette selection (index into tile_palette_entries)"""
	if index < 0 or index >= tile_palette_entries.size():
		return

	var entry: Dictionary = tile_palette_entries[index]
	selected_tile_type = str(entry.get("type_name", "NORMAL"))
	selected_tile_resource_path = str(entry.get("resource_path", ""))

	# Update button states
	for i in range(tile_buttons.size()):
		var button := tile_buttons[i]
		if not button:
			continue
		if i >= tile_palette_entries.size():
			continue
		var button_color: Color = _entry_color(tile_palette_entries[i])
		button.modulate = button_color * 1.5 if i == index else button_color

	print("Selected tile type: " + selected_tile_type + " (" + selected_tile_resource_path + ")")

func _unit_display_name(unit_type: String) -> String:
	"""Palette label for a unit reference - the empty slot gets a spelled-out name"""
	return NO_UNIT_LABEL if unit_type.is_empty() else unit_type

func _on_unit_selected(unit_type: String):
	"""Handle unit palette selection ("" = the no-unit slot)"""
	selected_unit_type = unit_type

	# Update button states
	var base_color: Color = _player_color(selected_player_id)
	for i in range(unit_buttons.size()):
		var button := unit_buttons[i]
		if not button:
			continue
		var is_selected: bool = i < unit_palette_values.size() and unit_palette_values[i] == unit_type
		button.modulate = base_color * 1.5 if is_selected else base_color

	print("Selected unit type: " + _unit_display_name(unit_type) + " for Player " + str(selected_player_id + 1))

func _on_player_selected(index: int):
	"""Handle player selection"""
	selected_player_id = index

	# Recolour the palette for the new slot, keeping the current selection highlighted
	_on_unit_selected(selected_unit_type)

	print("Selected player: " + str(selected_player_id + 1))

# --- Spawn point configuration ------------------------------------------------

func _player_color(player_id: int) -> Color:
	"""Slot colour, guarded against an unmapped player id"""
	var value: Variant = unit_colors.get(player_id, Color.WHITE)
	if value is Color:
		return value as Color
	return Color.WHITE

func _on_spawn_kind_selected(index: int):
	"""Handle spawn kind change, re-defaulting max_spawns and re-gating the fields"""
	if index < 0 or index >= MapResource.SPAWN_KINDS.size():
		return

	selected_spawn_kind = str(MapResource.SPAWN_KINDS[index])

	# Endless means unlimited by definition; every other kind starts at a single unit.
	# Only nudge the SpinBox when it still holds the previous kind's default, so a
	# deliberate value the user typed is never stomped.
	var new_default: int = -1 if selected_spawn_kind == MapResource.SPAWN_KIND_ENDLESS else 1
	if max_spawns_input and (selected_max_spawns == -1 or selected_max_spawns == 1):
		selected_max_spawns = new_default
		max_spawns_input.value = new_default

	_update_spawn_controls_enabled()
	print("Selected spawn kind: " + selected_spawn_kind)

func _on_respawn_interval_changed(value: float):
	"""Store the respawn interval (turns between spawns)"""
	selected_respawn_interval = maxi(1, int(value))

func _on_max_spawns_changed(value: float):
	"""Store the spawn cap (-1 = unlimited)"""
	selected_max_spawns = int(value)

func _on_spawn_turn_changed(value: float):
	"""Store the turn a Reinforcement point activates"""
	selected_spawn_turn = maxi(1, int(value))

func _update_spawn_controls_enabled() -> void:
	"""Grey out the fields that are meaningless for the selected spawn kind"""
	var is_repeating: bool = selected_spawn_kind == MapResource.SPAWN_KIND_RESPAWN \
		or selected_spawn_kind == MapResource.SPAWN_KIND_ENDLESS
	var is_reinforcement: bool = selected_spawn_kind == MapResource.SPAWN_KIND_REINFORCEMENT

	if respawn_interval_input:
		respawn_interval_input.editable = is_repeating
		respawn_interval_input.modulate = Color.WHITE if is_repeating else Color(1, 1, 1, 0.45)

	if max_spawns_input:
		# A one-shot Start point always produces exactly one unit.
		var caps_apply: bool = selected_spawn_kind != MapResource.SPAWN_KIND_START
		max_spawns_input.editable = caps_apply
		max_spawns_input.modulate = Color.WHITE if caps_apply else Color(1, 1, 1, 0.45)

	if spawn_turn_input:
		spawn_turn_input.editable = is_reinforcement
		spawn_turn_input.modulate = Color.WHITE if is_reinforcement else Color(1, 1, 1, 0.45)

func _spawn_opts() -> Dictionary:
	"""Options dictionary describing the spawn point the palette currently defines"""
	return {
		"unit_type": selected_unit_type,
		"max_spawns": selected_max_spawns,
		"respawn_interval": selected_respawn_interval,
		"spawn_turn": selected_spawn_turn
	}

# --- Grid input: strokes, brushes and tools -----------------------------------

func _input(event: InputEvent) -> void:
	"""Global watch for the left mouse release that ends a paint stroke.

	A per-cell release is unreliable because the pointer is often over a different
	cell (or outside the dock entirely) by the time the button comes back up.
	"""
	if not is_visible_in_tree():
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or mouse_event.pressed:
		return

	# Rect Fill commits on release, everything else just closes the stroke
	if _rect_anchor != Vector2i(-1, -1):
		_commit_rect_fill(_rect_hover)

	if _is_painting:
		_is_painting = false
		_end_stroke()

func _on_grid_cell_gui_input(event: InputEvent, pos: Vector2i) -> void:
	"""Handle a mouse press on a single grid cell"""
	if not current_map or not _is_valid_position(pos):
		return

	if not (event is InputEventMouseButton):
		return

	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click always erases, whatever the active tool is
		_apply_brush(pos, _erase_at_position)
		_end_stroke()
		return

	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	var tool_mode: String = _get_tool_mode()

	if tool_mode == "Rect Fill":
		# Anchor the rect; the fill happens on release
		_rect_anchor = pos
		_rect_hover = pos
		_tint_rect_preview()
		return

	if tool_mode == "Bucket Fill":
		# One-shot tool - dragging must not re-flood every cell it crosses
		_bucket_fill_at_position(pos)
		_end_stroke()
		return

	_is_painting = true
	_apply_tool_at_position(pos)

func _on_grid_cell_mouse_entered(pos: Vector2i) -> void:
	"""Continue a stroke (or update the rect preview) as the pointer crosses cells"""
	if not current_map or not _is_valid_position(pos):
		return

	if _rect_anchor != Vector2i(-1, -1):
		_update_rect_preview(pos)
		return

	if not _is_painting:
		return

	_apply_tool_at_position(pos)

func _apply_tool_at_position(pos: Vector2i) -> void:
	"""Apply the active tool at a position, refreshing only the affected cells"""
	if not current_map:
		return

	var tool_mode: String = _get_tool_mode()

	match tool_mode:
		"Place Tiles":
			_apply_brush(pos, _place_tile_at_position)
		"Place Spawn":
			_apply_brush(pos, _place_spawn_at_position)
		"Bucket Fill":
			_bucket_fill_at_position(pos)
		"Erase":
			_apply_brush(pos, _erase_at_position)
		_:
			# "Rect Fill" is handled entirely by the press/release path
			pass

func _apply_brush(pos: Vector2i, cell_action: Callable) -> void:
	"""Run a per-cell action over the NxN brush block anchored at pos (top-left)"""
	var brush: int = _get_brush_size()

	for dy in range(brush):
		for dx in range(brush):
			var target = Vector2i(pos.x + dx, pos.y + dy)
			if not _is_valid_position(target):
				continue
			cell_action.call(target)
			_refresh_cell(target)

func _get_tool_mode() -> String:
	"""Name of the active tool, guarded against an unset OptionButton selection"""
	if not tool_mode_option:
		return "Place Tiles"

	var index: int = tool_mode_option.selected
	if index < 0 or index >= tool_modes.size():
		return "Place Tiles"

	return tool_modes[index]

func _get_brush_size() -> int:
	"""Current brush edge length, clamped to the supported range"""
	if not brush_size_input:
		return 1
	return clampi(int(brush_size_input.value), 1, 5)

func _is_valid_position(pos: Vector2i) -> bool:
	"""Bounds check against the map the grid was built for"""
	if not current_map:
		return false
	return pos.x >= 0 and pos.y >= 0 and pos.x < current_map.width and pos.y < current_map.height

func _end_stroke() -> void:
	"""Finish an edit gesture - the expensive refreshes happen once, here"""
	_last_world_cell = NO_CELL
	_update_preview()

func _place_tile_at_position(pos: Vector2i):
	"""Place selected tile at position, recording its real resource path"""
	current_map.set_tile_at_position(pos, selected_tile_type, selected_tile_resource_path)

func _place_spawn_at_position(pos: Vector2i):
	"""Place a spawn POINT at a position using the current palette configuration.

	The unit reference is optional: with the "(none)" palette entry selected this
	writes a bare slot for match setup to fill.
	"""
	if not current_map:
		return
	current_map.set_spawn_point_at_position(
		pos, selected_player_id, selected_spawn_kind, _spawn_opts())

func _resource_path_for_type(type_name: String) -> String:
	"""First palette resource path registered for a tile type, or "" if none"""
	for entry in tile_palette_entries:
		if str(entry.get("type_name", "")) == type_name:
			return str(entry.get("resource_path", ""))
	return ""

func _erase_at_position(pos: Vector2i):
	"""Erase tile/unit at position"""
	# Reset tile to normal (using the real NORMAL resource when the palette has one)
	current_map.set_tile_at_position(pos, "NORMAL", _resource_path_for_type("NORMAL"))
	# Remove unit spawn
	current_map.remove_unit_spawn_at_position(pos)

# --- Rect Fill ----------------------------------------------------------------

func _update_rect_preview(pos: Vector2i) -> void:
	"""Move the rect preview to a new hover cell, repainting the old region first"""
	if pos == _rect_hover:
		return

	var previous := _rect_hover
	_rect_hover = pos

	# Restore the cells the old rect covered, then tint the new one
	if previous != Vector2i(-1, -1):
		for cell in _get_rect_cells(_rect_anchor, previous):
			_refresh_cell(cell)

	_tint_rect_preview()

func _tint_rect_preview() -> void:
	"""Brighten every cell inside the pending rect so the region is visible"""
	if _rect_anchor == Vector2i(-1, -1) or _rect_hover == Vector2i(-1, -1):
		return

	var tint: Color = _tile_color_for(selected_tile_type) * 1.4
	for cell in _get_rect_cells(_rect_anchor, _rect_hover):
		var button := _get_button_at(cell)
		if button:
			button.modulate = tint

func _commit_rect_fill(release_pos: Vector2i) -> void:
	"""Fill the anchored rect with the selected tile type, then reset the anchor"""
	var anchor := _rect_anchor
	var corner := release_pos
	_rect_anchor = Vector2i(-1, -1)
	_rect_hover = Vector2i(-1, -1)

	if not current_map or anchor == Vector2i(-1, -1):
		return

	# If the pointer left the grid we still fill up to the last known cell
	if not _is_valid_position(corner):
		corner = anchor

	var cells := _get_rect_cells(anchor, corner)
	for cell in cells:
		current_map.set_tile_at_position(cell, selected_tile_type, selected_tile_resource_path)
		_refresh_cell(cell)

	_end_stroke()
	print("Rect filled " + str(cells.size()) + " tiles with " + selected_tile_type)

func _get_rect_cells(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	"""Inclusive cell list for the normalized rect between two corners (any drag direction)"""
	var cells: Array[Vector2i] = []
	if not current_map:
		return cells

	var min_x: int = mini(a.x, b.x)
	var max_x: int = maxi(a.x, b.x)
	var min_y: int = mini(a.y, b.y)
	var max_y: int = maxi(a.y, b.y)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell = Vector2i(x, y)
			if _is_valid_position(cell):
				cells.append(cell)

	return cells

# --- Bucket Fill --------------------------------------------------------------

func _bucket_fill_at_position(pos: Vector2i) -> void:
	"""Flood fill the contiguous 4-way region sharing the clicked cell's tile type.

	Iterative (stack based) with a visited set, so a large map can never blow the
	call stack and no cell is ever queued twice.
	"""
	if not current_map or not _is_valid_position(pos):
		return

	var origin_data: Dictionary = current_map.get_tile_at_position(pos)
	var target_type: String = origin_data.get("tile_type", "NORMAL")

	# Nothing to do - the region is already the selected type
	if target_type == selected_tile_type:
		return

	var visited: Dictionary = {}
	var stack: Array[Vector2i] = [pos]
	visited[pos] = true
	var filled: int = 0

	while stack.size() > 0:
		var cell: Vector2i = stack.pop_back()

		var cell_data: Dictionary = current_map.get_tile_at_position(cell)
		if cell_data.get("tile_type", "NORMAL") != target_type:
			continue

		current_map.set_tile_at_position(cell, selected_tile_type, selected_tile_resource_path)
		_refresh_cell(cell)
		filled += 1

		var neighbors: Array[Vector2i] = [
			Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x - 1, cell.y),
			Vector2i(cell.x, cell.y + 1),
			Vector2i(cell.x, cell.y - 1)
		]
		for neighbor in neighbors:
			if not _is_valid_position(neighbor):
				continue
			if visited.has(neighbor):
				continue
			visited[neighbor] = true
			stack.append(neighbor)

	print("Bucket filled " + str(filled) + " tiles with " + selected_tile_type)

# --- Drag and drop ------------------------------------------------------------

func _palette_get_drag_data(_at_position: Vector2, unit_type: String) -> Variant:
	"""Start a drag from a unit palette button.

	Emits the richer "spawn" payload, which carries the whole spawn point config, so
	dropping is identical to painting with the Place Spawn tool. The older "unit"
	payload is still ACCEPTED on drop, it is just no longer produced here.
	"""
	# A drag supersedes any stroke that may have started
	_is_painting = false

	var payload: Dictionary = {
		"kind": "spawn",
		"player_id": selected_player_id,
		"spawn_kind": selected_spawn_kind,
		"unit_type": unit_type,
		"max_spawns": selected_max_spawns,
		"respawn_interval": selected_respawn_interval,
		"spawn_turn": selected_spawn_turn
	}
	set_drag_preview(_make_drag_preview(_drag_preview_text(unit_type, selected_spawn_kind), selected_player_id))
	return payload

func _grid_get_drag_data(_at_position: Vector2, pos: Vector2i) -> Variant:
	"""Start a drag from a grid cell that already holds a spawn point (move gesture).

	The payload mirrors the point's OWN configuration, not the palette's, so moving a
	Reinforcement point around never silently converts it into a Start point.
	"""
	if not current_map or not _is_valid_position(pos):
		return null

	var spawn_data: Dictionary = current_map.get_unit_spawn_at_position(pos)
	if spawn_data.is_empty():
		return null

	_is_painting = false

	var normalized: Dictionary = current_map.normalize_spawn(spawn_data)
	var unit_type: String = str(normalized.get("unit_type", ""))
	var player_id: int = int(normalized.get("player_id", 0))
	var spawn_kind: String = str(normalized.get("spawn_kind", MapResource.SPAWN_KIND_START))

	var payload: Dictionary = {
		"kind": "unit_move",
		"from": pos,
		"unit_type": unit_type,
		"player_id": player_id,
		"spawn_kind": spawn_kind,
		"character_id": str(normalized.get("character_id", "")),
		"unit_resource_path": str(normalized.get("unit_resource_path", "")),
		"max_spawns": int(normalized.get("max_spawns", 1)),
		"respawn_interval": int(normalized.get("respawn_interval", 1)),
		"spawn_turn": int(normalized.get("spawn_turn", 1))
	}
	set_drag_preview(_make_drag_preview(_drag_preview_text(unit_type, spawn_kind), player_id))
	return payload

func _drag_preview_text(unit_type: String, spawn_kind: String) -> String:
	"""Label for the floating drag preview: the unit (or "Slot") plus the kind badge"""
	var unit_label: String = unit_type if not unit_type.is_empty() else "Slot"
	return unit_label + " [" + _spawn_kind_initial(spawn_kind) + "]"

func _spawn_kind_initial(spawn_kind: String) -> String:
	"""One-letter badge for a spawn kind (S/R/E/F), "S" for anything unrecognised"""
	return str(SPAWN_KIND_INITIALS.get(spawn_kind, "S"))

func _grid_can_drop_data(_at_position: Vector2, data: Variant, pos: Vector2i) -> bool:
	"""Accept only well formed tile/unit payloads landing on an in-bounds cell"""
	if not current_map or not _is_valid_position(pos):
		return false

	return _is_valid_payload(data)

func _grid_drop_data(_at_position: Vector2, data: Variant, pos: Vector2i) -> void:
	"""Place a tile, or place/relocate a unit spawn, at the dropped-on cell"""
	if not _grid_can_drop_data(_at_position, data, pos):
		return

	_apply_payload_at(data, pos)

func _make_drag_preview(preview_text: String, player_id: int) -> Control:
	"""Build the small floating label shown under the cursor during a drag"""
	var preview = Panel.new()
	preview.custom_minimum_size = Vector2(84, 26)
	preview.size = Vector2(84, 26)
	preview.modulate = _player_color(player_id)

	var label = Label.new()
	label.text = preview_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(label)

	return preview

func _tile_palette_get_drag_data(_at_position: Vector2, index: int) -> Variant:
	"""Start a drag from a tile palette button (drop target: 2D grid or 3D world)"""
	if index < 0 or index >= tile_palette_entries.size():
		return null

	# A drag supersedes any stroke that may have started
	_is_painting = false

	var entry: Dictionary = tile_palette_entries[index]
	var type_name: String = str(entry.get("type_name", "NORMAL"))
	var color: Color = _entry_color(entry)
	var display_name: String = str(entry.get("display_name", type_name))

	var payload: Dictionary = {
		"kind": "tile",
		"tile_type": type_name,
		"resource_path": str(entry.get("resource_path", "")),
		"color": color
	}
	set_drag_preview(_make_tile_drag_preview(display_name, color))
	return payload

func _make_tile_drag_preview(display_name: String, color: Color) -> Control:
	"""Small floating swatch shown under the cursor while dragging a tile"""
	var preview = Panel.new()
	preview.custom_minimum_size = Vector2(72, 26)
	preview.size = Vector2(72, 26)
	preview.modulate = color

	var label = Label.new()
	label.text = display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.add_child(label)

	return preview

# --- 3D world view ------------------------------------------------------------
# A live render of the map inside a SubViewport, using MapGallery's layout math so
# both views agree: one BoxMesh per tile centred on the origin, SphereMesh markers
# for spawns. Full rebuilds are rare (new/load/resize/clear/fill-all); everything
# else goes through _refresh_cell_3d, which touches a single cell.

func _setup_world_viewport() -> void:
	"""Populate the SubViewport with a MapRoot, camera, light and environment"""
	if not world_viewport:
		return

	world_root = Node3D.new()
	world_root.name = "MapRoot"
	world_viewport.add_child(world_root)

	world_camera = Camera3D.new()
	world_camera.name = "MapCamera"
	# look_at_from_position orients without needing the node in-tree first
	# (plain look_at() errors before add_child()).
	world_camera.look_at_from_position(
		Vector3(0.0, _world_span * 0.9, _world_span * 0.7), Vector3.ZERO, Vector3.UP)
	world_viewport.add_child(world_camera)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.09, 0.12, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45, 1.0)
	env.ambient_light_energy = 0.45
	world_camera.environment = env

	var light := DirectionalLight3D.new()
	light.name = "MapLight"
	light.look_at_from_position(
		Vector3(_world_span * 0.6, _world_span * 1.2, _world_span * 0.4), Vector3.ZERO, Vector3.UP)
	light.light_energy = 1.1
	world_viewport.add_child(light)

func _world_offsets() -> Vector2:
	"""Centring offsets (x, z) so the grid straddles the origin"""
	if not current_map:
		return Vector2.ZERO
	return Vector2(
		float(current_map.width - 1) * TILE_STEP * 0.5,
		float(current_map.height - 1) * TILE_STEP * 0.5)

func _world_position_for(pos: Vector2i, y: float) -> Vector3:
	"""World-space position of a cell centre at a given height"""
	var offsets := _world_offsets()
	return Vector3(
		float(pos.x) * TILE_STEP - offsets.x,
		y,
		float(pos.y) * TILE_STEP - offsets.y)

func _build_world_3d() -> void:
	"""Full rebuild of the 3D view. Called on new map / load / resize / clear / fill all."""
	if not world_root:
		return

	# Free previous geometry and drop the stale cell -> mesh lookups.
	for child in world_root.get_children():
		child.queue_free()
	_tile_meshes.clear()
	_spawn_meshes.clear()

	if not current_map:
		return

	var cols: int = maxi(current_map.width, 1)
	var rows: int = maxi(current_map.height, 1)

	_world_span = maxf(float(cols), float(rows)) * TILE_STEP
	_aim_world_camera()

	for y in range(rows):
		for x in range(cols):
			var pos := Vector2i(x, y)
			_create_tile_mesh(pos)
			_sync_spawn_marker(pos)

func _create_tile_mesh(pos: Vector2i) -> void:
	"""Create the box mesh for a single cell and register it in _tile_meshes"""
	if not world_root or not current_map:
		return

	var tile_mesh := BoxMesh.new()
	tile_mesh.size = TILE_MESH_SIZE

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = tile_mesh
	mesh_instance.material_override = _solid_material(_tile_color_at(pos))
	mesh_instance.position = _world_position_for(pos, 0.0)
	world_root.add_child(mesh_instance)

	_tile_meshes[pos] = mesh_instance

func _sync_spawn_marker(pos: Vector2i) -> void:
	"""Create, recolour or free the spawn marker for a cell to match the map data"""
	if not world_root or not current_map:
		return

	var spawn_data: Dictionary = current_map.get_unit_spawn_at_position(pos)

	if spawn_data.is_empty():
		if _spawn_meshes.has(pos):
			var stale: MeshInstance3D = _spawn_meshes[pos] as MeshInstance3D
			if is_instance_valid(stale):
				stale.queue_free()
			_spawn_meshes.erase(pos)
		return

	# Colour still encodes the player slot; the marker SIZE encodes the spawn kind, so
	# a repeating point reads as bigger and a late Reinforcement as smaller.
	var normalized: Dictionary = current_map.normalize_spawn(spawn_data)
	var player_id: int = int(normalized.get("player_id", 0))
	var spawn_kind: String = str(normalized.get("spawn_kind", MapResource.SPAWN_KIND_START))
	var marker_color: Color = _player_color(player_id)
	var radius: float = SPAWN_RADIUS * _spawn_kind_marker_scale(spawn_kind)

	if _spawn_meshes.has(pos):
		var existing: MeshInstance3D = _spawn_meshes[pos] as MeshInstance3D
		if is_instance_valid(existing):
			var existing_material := existing.material_override as StandardMaterial3D
			if existing_material:
				existing_material.albedo_color = marker_color
			# Resize in place so switching a point's kind is visible without a rebuild.
			var existing_mesh := existing.mesh as SphereMesh
			if existing_mesh:
				existing_mesh.radius = radius
				existing_mesh.height = radius * 2.0
			return
		_spawn_meshes.erase(pos)

	var spawn_mesh := SphereMesh.new()
	spawn_mesh.radius = radius
	spawn_mesh.height = radius * 2.0

	var marker := MeshInstance3D.new()
	marker.mesh = spawn_mesh
	marker.material_override = _solid_material(marker_color)
	marker.position = _world_position_for(pos, SPAWN_Y)
	world_root.add_child(marker)

	_spawn_meshes[pos] = marker

func _spawn_kind_marker_scale(spawn_kind: String) -> float:
	"""3D marker radius multiplier for a spawn kind, defaulting to the Start size"""
	var value: Variant = SPAWN_KIND_MARKER_SCALE.get(spawn_kind, 1.0)
	if value is float:
		return value as float
	return 1.0

func _refresh_cell_3d(pos: Vector2i) -> void:
	"""Cheap per-cell 3D update - recolour the tile, add/remove its spawn marker.

	Deliberately never rebuilds the whole world, so drag strokes stay smooth.
	"""
	if not world_root or not current_map or not _is_valid_position(pos):
		return

	if _tile_meshes.has(pos):
		var stored: MeshInstance3D = _tile_meshes[pos] as MeshInstance3D
		if is_instance_valid(stored):
			var material := stored.material_override as StandardMaterial3D
			if material:
				material.albedo_color = _tile_color_at(pos)
		else:
			_tile_meshes.erase(pos)
			_create_tile_mesh(pos)
	else:
		_create_tile_mesh(pos)

	_sync_spawn_marker(pos)

func _tile_color_at(pos: Vector2i) -> Color:
	"""Display colour of the tile currently stored at a cell"""
	if not current_map:
		return Color.WHITE
	var tile_data: Dictionary = current_map.get_tile_at_position(pos)
	return _tile_color_for(str(tile_data.get("tile_type", "NORMAL")))

func _aim_world_camera() -> void:
	"""Re-position the camera for the current _world_span (angled top-down)"""
	if not world_camera:
		return
	world_camera.look_at_from_position(
		Vector3(0.0, _world_span * 0.9, _world_span * 0.7), Vector3.ZERO, Vector3.UP)

func _solid_material(color: Color) -> StandardMaterial3D:
	"""A simple lit material with the given albedo (one instance per mesh, so a
	per-cell recolour never bleeds into neighbouring tiles)."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat

# --- 3D picking ---------------------------------------------------------------

func _world_cell_from_local_position(local_pos: Vector2) -> Vector2i:
	"""Convert a SubViewportContainer-local point to a map cell.

	1. container-local -> SubViewport coordinates (scaled when the container stretches)
	2. build a camera ray from that viewport point
	3. intersect the ground plane y = 0
	4. invert the tile layout math to (col, row)
	5. bounds-check; NO_CELL when the ray misses or lands off the map
	"""
	if not current_map or not world_camera or not world_viewport or not world_viewport_container:
		return NO_CELL

	var container_size: Vector2 = world_viewport_container.size
	if container_size.x <= 0.0 or container_size.y <= 0.0:
		return NO_CELL

	var viewport_size := Vector2(world_viewport.size)
	var vp_pos: Vector2 = local_pos
	if world_viewport_container.stretch:
		vp_pos = Vector2(
			local_pos.x * viewport_size.x / container_size.x,
			local_pos.y * viewport_size.y / container_size.y)

	var origin: Vector3 = world_camera.project_ray_origin(vp_pos)
	var direction: Vector3 = world_camera.project_ray_normal(vp_pos)

	# Ray parallel to the ground plane - nothing to hit.
	if absf(direction.y) < 0.00001:
		return NO_CELL

	var distance: float = -origin.y / direction.y
	if distance < 0.0:
		return NO_CELL

	var point: Vector3 = origin + direction * distance

	var offsets := _world_offsets()
	var col: int = roundi((point.x + offsets.x) / TILE_STEP)
	var row: int = roundi((point.z + offsets.y) / TILE_STEP)

	var cell := Vector2i(col, row)
	if not _is_valid_position(cell):
		return NO_CELL

	return cell

# --- 3D drop target -----------------------------------------------------------

func _payload_kind(data: Variant) -> String:
	"""Kind string of a drag payload, or "" when the payload is malformed"""
	if not (data is Dictionary):
		return ""
	var payload: Dictionary = data as Dictionary
	return str(payload.get("kind", ""))

func _is_valid_payload(data: Variant) -> bool:
	"""Validate the shape of every payload kind the editor understands"""
	var kind: String = _payload_kind(data)
	if kind.is_empty():
		return false

	var payload: Dictionary = data as Dictionary

	if kind == "tile":
		return payload.has("tile_type") and payload.get("tile_type") is String

	# "spawn" is the current palette payload; "unit" is the pre-spawn-point shape and
	# is still accepted so nothing that emits it regresses (it means a Start point).
	if kind == "spawn" or kind == "unit":
		return payload.has("unit_type") and payload.has("player_id")

	if kind == "unit_move":
		return payload.has("unit_type") and payload.has("player_id") \
			and payload.get("from") is Vector2i

	return false

func _world_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	"""Accept well formed tile/unit payloads that land on an in-bounds cell"""
	if not current_map:
		return false
	if not _is_valid_payload(data):
		return false
	return _world_cell_from_local_position(at_position) != NO_CELL

func _world_drop_data(at_position: Vector2, data: Variant) -> void:
	"""Apply a dropped payload at the picked cell"""
	if not _world_can_drop_data(at_position, data):
		return

	var cell: Vector2i = _world_cell_from_local_position(at_position)
	if cell == NO_CELL:
		return

	_apply_payload_at(data, cell)

func _apply_payload_at(data: Variant, pos: Vector2i) -> void:
	"""Shared drop handling for both editing surfaces"""
	if not current_map or not _is_valid_position(pos):
		return
	if not _is_valid_payload(data):
		return

	var payload: Dictionary = data as Dictionary
	var kind: String = str(payload.get("kind", ""))

	if kind == "tile":
		var tile_type: String = str(payload.get("tile_type", "NORMAL"))
		var resource_path: String = str(payload.get("resource_path", ""))
		# Honour the brush size, exactly like the 2D painting path does.
		var place_tile := func(target: Vector2i) -> void:
			current_map.set_tile_at_position(target, tile_type, resource_path)
		_apply_brush(pos, place_tile)
		_end_stroke()
		print("Dropped tile " + tile_type + " at " + str(pos))
		return

	# Every remaining kind ("spawn", the legacy "unit", and "unit_move") writes a
	# spawn point. Missing keys fall back to the plain Start-point defaults, which is
	# exactly what a legacy "unit" payload should mean.
	var unit_type: String = str(payload.get("unit_type", ""))
	var player_id: int = int(payload.get("player_id", 0))
	var spawn_kind: String = str(payload.get("spawn_kind", MapResource.SPAWN_KIND_START))

	var opts: Dictionary = {
		"unit_type": unit_type,
		"character_id": str(payload.get("character_id", "")),
		"unit_resource_path": str(payload.get("unit_resource_path", "")),
		"max_spawns": int(payload.get("max_spawns", current_map.get_default_max_spawns(spawn_kind))),
		"respawn_interval": int(payload.get("respawn_interval", 1)),
		"spawn_turn": int(payload.get("spawn_turn", 1))
	}

	if kind == "unit_move":
		var from_value: Variant = payload.get("from", NO_CELL)
		if not (from_value is Vector2i):
			return
		var from_pos: Vector2i = from_value as Vector2i
		if from_pos == pos:
			return
		current_map.remove_unit_spawn_at_position(from_pos)
		if _is_valid_position(from_pos):
			_refresh_cell(from_pos)

	current_map.set_spawn_point_at_position(pos, player_id, spawn_kind, opts)
	_refresh_cell(pos)
	_end_stroke()
	print("Dropped " + spawn_kind + " spawn (" + _unit_display_name(unit_type) + ") for Player " + str(player_id + 1) + " at " + str(pos))

# --- Painting directly in the 3D view -----------------------------------------

func _on_world_gui_input(event: InputEvent) -> void:
	"""Mirror the 2D grid's stroke semantics against ray-picked cells.

	Press applies the active tool and opens a stroke; motion continues it (skipping
	repeats of the same cell); right-click erases. The global _input left-release
	handler closes the stroke, same as the 2D grid.
	"""
	if not current_map:
		return

	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed:
			return

		var cell: Vector2i = _world_cell_from_local_position(mouse_event.position)
		if cell == NO_CELL:
			return

		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_apply_brush(cell, _erase_at_position)
			_end_stroke()
			return

		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return

		var tool_mode: String = _get_tool_mode()

		if tool_mode == "Rect Fill":
			_rect_anchor = cell
			_rect_hover = cell
			_tint_rect_preview()
			return

		if tool_mode == "Bucket Fill":
			_bucket_fill_at_position(cell)
			_end_stroke()
			return

		_is_painting = true
		_last_world_cell = cell
		_apply_tool_at_position(cell)
		return

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion

		if _rect_anchor != NO_CELL:
			var rect_cell: Vector2i = _world_cell_from_local_position(motion_event.position)
			if rect_cell != NO_CELL:
				_update_rect_preview(rect_cell)
			return

		if not _is_painting:
			return

		var moved_cell: Vector2i = _world_cell_from_local_position(motion_event.position)
		if moved_cell == NO_CELL or moved_cell == _last_world_cell:
			return

		_last_world_cell = moved_cell
		_apply_tool_at_position(moved_cell)

func _on_clear_grid():
	"""Clear the entire grid"""
	if not current_map:
		return
	
	# Reset all tiles to normal
	current_map.create_default_layout()
	# Clear all unit spawns
	current_map.unit_spawns.clear()

	_update_grid_display()
	_build_world_3d()
	_update_preview()
	print("Grid cleared")

func _on_fill_all():
	"""Set every tile to the selected tile type, leaving unit spawns untouched"""
	if not current_map:
		return

	for y in range(current_map.height):
		for x in range(current_map.width):
			current_map.set_tile_at_position(Vector2i(x, y), selected_tile_type, selected_tile_resource_path)

	_update_grid_display()
	_build_world_3d()
	_update_preview()
	print("Filled all tiles with " + selected_tile_type)

func _update_grid_display():
	"""Update the visual display of the whole grid"""
	if not current_map:
		return

	for i in range(grid_buttons.size()):
		var button = grid_buttons[i]
		if not button:
			continue
		var pos = button.get_meta("grid_pos", Vector2i(-1, -1))

		if pos == Vector2i(-1, -1):
			continue

		_paint_button(button, pos)

func _get_button_at(pos: Vector2i) -> Button:
	"""Look up the grid button for a position, or null if it is off the grid"""
	if pos.x < 0 or pos.y < 0 or pos.x >= _grid_width or pos.y >= _grid_height:
		return null

	var index: int = pos.y * _grid_width + pos.x
	if index < 0 or index >= grid_buttons.size():
		return null

	return grid_buttons[index]

func _refresh_cell(pos: Vector2i) -> void:
	"""Repaint a single cell - used during strokes so we never redraw the whole grid.

	Also drives the matching per-cell 3D update, so every existing caller keeps the
	2D grid and the 3D world in sync for free (and never triggers a full rebuild).
	"""
	if not current_map:
		return

	var button := _get_button_at(pos)
	if button:
		_paint_button(button, pos)

	_refresh_cell_3d(pos)

func _paint_button(button: Button, pos: Vector2i) -> void:
	"""Apply the tile/unit appearance for a position to its button"""
	# Get tile data
	var tile_data = current_map.get_tile_at_position(pos)
	var tile_type = tile_data.get("tile_type", "NORMAL")

	# Get unit data
	var unit_data = current_map.get_unit_spawn_at_position(pos)

	# Set button appearance
	if not unit_data.is_empty():
		# Show the spawn point: colour is the player slot, text is the kind's initial
		# (S/R/E/F) plus the unit's first letter when the point names one. A bare "S"
		# is therefore an unassigned Start slot, filled at match setup.
		var normalized: Dictionary = current_map.normalize_spawn(unit_data)
		var unit_type: String = str(normalized.get("unit_type", ""))
		var player_id: int = int(normalized.get("player_id", 0))
		var badge: String = _spawn_kind_initial(str(normalized.get("spawn_kind", MapResource.SPAWN_KIND_START)))
		if not unit_type.is_empty():
			badge += unit_type.substr(0, 1)
		button.text = badge
		button.modulate = _player_color(player_id)
	else:
		# Show tile
		button.text = ""
		button.modulate = _tile_color_for(str(tile_type))

func _on_map_info_changed(new_text: String = ""):
	"""Handle map information changes"""
	if not current_map:
		return
	
	current_map.map_name = map_name_input.text
	current_map.author = author_input.text
	current_map.description = description_input.text
	current_map.difficulty = difficulties[difficulty_option.selected]
	current_map.map_type = map_types[map_type_option.selected]
	if status_option:
		current_map.status = map_statuses[status_option.selected]
	
	_update_preview()

func _update_ui_from_map():
	"""Update UI elements from current map data"""
	if not current_map:
		return
	
	map_name_input.text = current_map.map_name
	author_input.text = current_map.author
	description_input.text = current_map.description
	
	# Set difficulty
	for i in range(difficulties.size()):
		if difficulties[i] == current_map.difficulty:
			difficulty_option.selected = i
			break
	
	# Set map type
	for i in range(map_types.size()):
		if map_types[i] == current_map.map_type:
			map_type_option.selected = i
			break

	# Set status (Active / Inactive draft)
	if status_option:
		for i in range(map_statuses.size()):
			if map_statuses[i] == current_map.status:
				status_option.selected = i
				break

	width_input.value = current_map.width
	height_input.value = current_map.height
	
	_create_grid()
	_update_preview()

func _update_preview():
	"""Update the map preview information"""
	if not current_map or not map_info_label:
		return
	
	var info = current_map.get_display_info()
	var validation = current_map.validate_map()
	
	var preview_text = []
	preview_text.append("Name: " + info.get("name", "Unnamed"))
	preview_text.append("Size: " + info.get("size", "0x0"))
	preview_text.append("Players: " + str(info.get("players", 0)))
	preview_text.append("Difficulty: " + info.get("difficulty", "Normal"))
	preview_text.append("Spawn Points: " + str(info.get("total_spawns", 0)))

	# Break the points down by kind, listing only the kinds actually used so a plain
	# Start-only map (i.e. every map authored before spawn kinds) reads unchanged.
	var kind_counts: Variant = info.get("spawn_kinds", {})
	if kind_counts is Dictionary:
		var parts: Array[String] = []
		for kind in MapResource.SPAWN_KINDS:
			var count: int = int((kind_counts as Dictionary).get(kind, 0))
			if count > 0:
				parts.append("%s %d" % [str(kind), count])
		if not parts.is_empty():
			preview_text.append("  (" + ", ".join(parts) + ")")


	if not validation.valid:
		preview_text.append("")
		preview_text.append("ISSUES:")
		for issue in validation.issues:
			preview_text.append("• " + issue)
	
	if validation.warnings.size() > 0:
		preview_text.append("")
		preview_text.append("WARNINGS:")
		for warning in validation.warnings:
			preview_text.append("• " + warning)
	
	map_info_label.text = "\n".join(preview_text)

# Action button handlers
func _on_new_map():
	"""Create a new map"""
	_create_new_map()
	print("Created new map")

## Show a save/load outcome in the dock (and mirror it to the Output panel).
func _set_status(message: String, is_error: bool) -> void:
	if not save_status_label:
		print(message)
		return
	save_status_label.text = message
	save_status_label.add_theme_color_override(
		"font_color", Color(0.9, 0.35, 0.3) if is_error else Color(0.4, 0.8, 0.45)
	)
	print(message)


## Problems that genuinely prevent writing a valid file. Deliberately NOT the same
## as validate_map()'s full list: "needs 2 players with unit spawns" is a
## PLAYABILITY rule, and refusing to save on it meant a half-built map could not be
## saved at all. Drafts save; playability is reported as a warning instead.
func _get_save_blockers() -> Array[String]:
	var blockers: Array[String] = []
	if not current_map:
		return ["No map loaded"]

	if current_map.map_name.strip_edges().is_empty():
		blockers.append("Map name is required")
	if current_map.width < MapResource.MIN_MAP_SIZE or current_map.width > MapResource.MAX_MAP_SIZE:
		blockers.append("Width must be %d-%d (currently %d)" % [MapResource.MIN_MAP_SIZE, MapResource.MAX_MAP_SIZE, current_map.width])
	if current_map.height < MapResource.MIN_MAP_SIZE or current_map.height > MapResource.MAX_MAP_SIZE:
		blockers.append("Height must be %d-%d (currently %d)" % [MapResource.MIN_MAP_SIZE, MapResource.MAX_MAP_SIZE, current_map.height])

	for tile_data in current_map.tile_layout:
		var pos: Vector2i = tile_data.get("position", Vector2i(-1, -1))
		if pos.x < 0 or pos.x >= current_map.width or pos.y < 0 or pos.y >= current_map.height:
			blockers.append("Tile position out of bounds: %s" % str(pos))
			break

	return blockers


func _on_save_map():
	"""Save the current map"""
	if not current_map:
		_set_status("Nothing to save - create or load a map first.", true)
		return

	var blockers := _get_save_blockers()

	# Publishing as Active means players will see it, so it must actually be
	# playable. Drafts (Inactive) skip this and save in whatever state they are in.
	if current_map.status != "Inactive":
		var playable := _playability_warning()
		if playable != "":
			blockers.append(playable + " - set Status to Inactive to save it as a draft")

	if not blockers.is_empty():
		_set_status("Not saved - " + ", ".join(blockers), true)
		return

	var success = MapLoader.save_map(current_map, current_map.map_name)
	if not success:
		_set_status("Failed to write the map file (see Output for details).", true)
		return

	var clean_name := current_map.map_name.to_lower().replace(" ", "_")
	if not clean_name.ends_with(".tres"):
		clean_name += ".tres"
	var saved_path := "res://game/maps/resources/" + clean_name

	# A fresh file written to res:// does not appear in the FileSystem dock (or in
	# anything scanning the directory) until the editor rescans -- without this the
	# save looks like it did nothing.
	_rescan_editor_filesystem()

	var note := "Saved: " + saved_path
	if current_map.status == "Inactive":
		note += "  [Draft - hidden from in-game map selection until set Active]"
	_set_status(note, false)


## Non-blocking playability note, so the user still learns the map is not yet
## battle-ready even though it saved fine.
func _playability_warning() -> String:
	if not current_map:
		return ""
	var players: Dictionary = {}
	for spawn_data in current_map.unit_spawns:
		var player_id: int = int(spawn_data.get("player_id", -1))
		if player_id >= 0:
			players[player_id] = true
	if players.size() < 2:
		return "not playable yet - needs unit spawns for at least 2 players"
	return ""


## Ask the editor to rescan res:// so a newly saved map shows up immediately.
func _rescan_editor_filesystem() -> void:
	if not Engine.has_singleton("EditorInterface"):
		return
	var editor_interface: Object = Engine.get_singleton("EditorInterface")
	if editor_interface == null or not editor_interface.has_method("get_resource_filesystem"):
		return
	var fs: Object = editor_interface.call("get_resource_filesystem")
	if fs != null and fs.has_method("scan"):
		fs.call("scan")

func _on_load_map():
	"""Load an existing map"""
	var dialog = MapCreatorDialog.new(MapCreatorDialog.DialogMode.LOAD_MAP)
	add_child(dialog)
	dialog.map_selected.connect(_on_map_loaded_from_dialog)
	dialog.popup_centered()

func _on_map_loaded_from_dialog(map_path: String):
	"""Handle map loaded from dialog"""
	var loaded_map = load(map_path) as MapResource
	if loaded_map:
		current_map = loaded_map
		_update_ui_from_map()
		print("Loaded map: " + loaded_map.map_name)
	else:
		print("Failed to load map: " + map_path)

func _on_test_map():
	"""Test the current map in game"""
	if not current_map:
		return
	
	var validation = current_map.validate_map()
	if not validation.valid:
		print("Cannot test invalid map")
		for issue in validation.issues:
			print("  - " + issue)
		return
	
	# Save map temporarily for testing
	var temp_name = "temp_test_map"
	var success = MapLoader.save_map(current_map, temp_name)
	if not success:
		print("Failed to prepare map for testing")
		return

	# Launch the game in the editor's play mode. NOTE: GameWorld loads whichever
	# map the game is configured to load, so this is a "launch the game to try it"
	# button rather than a direct load of the temp map - pick it from the Map
	# Selection menu once the game is running.
	var game_scene: String = "res://game/world/GameWorld.tscn"

	if Engine.has_singleton("EditorInterface") and ResourceLoader.exists(game_scene):
		var editor_interface: Object = Engine.get_singleton("EditorInterface")
		if editor_interface and editor_interface.has_method("play_custom_scene"):
			editor_interface.call("play_custom_scene", game_scene)
			print("Launching " + game_scene + " - open Map Selection and pick '" + temp_name + "'")
			return

	# Fallback: the editor API is unreachable, so keep the original behaviour.
	print("Map ready for testing. Load it from the Map Selection menu.")

func _on_save_template():
	"""Save current map as a template"""
	if not current_map:
		return
	
	if current_map.map_name.is_empty():
		print("Error: Map name is required for template")
		return
	
	var template_name = current_map.map_name + " Template"
	var success = MapTemplateManager.save_template(current_map, template_name)
	if success:
		print("Template saved: " + template_name)
	else:
		print("Failed to save template")

func _on_load_template():
	"""Load a template and apply it to current map"""
	var dialog = MapCreatorDialog.new(MapCreatorDialog.DialogMode.LOAD_TEMPLATE)
	add_child(dialog)
	dialog.template_selected.connect(_on_template_loaded_from_dialog)
	dialog.popup_centered()

func _on_template_loaded_from_dialog(template_name: String):
	"""Handle template loaded from dialog"""
	var template_data = MapTemplateManager.load_template(template_name)
	
	if template_data.is_empty():
		print("Failed to load template: " + template_name)
		return
	
	# Apply template to current map
	if not current_map:
		_create_new_map()
	
	var success = MapTemplateManager.apply_template_to_map(template_data, current_map)
	if success:
		current_map.map_name = template_data.get("name", "Template Map")
		current_map.author = author_input.text if not author_input.text.is_empty() else "Map Creator"
		_update_ui_from_map()
		print("Template loaded: " + template_name)
	else:
		print("Failed to apply template")