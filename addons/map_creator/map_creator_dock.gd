@tool
extends Control

# Map Creator Dock - Visual interface for creating maps

# UI Elements
var scroll_container: ScrollContainer
var main_container: VBoxContainer

# Map Info Section
var map_name_input: LineEdit
var description_input: TextEdit
var author_input: LineEdit
var difficulty_option: OptionButton
var map_type_option: OptionButton

# Map Size Section
var width_input: SpinBox
var height_input: SpinBox
var resize_button: Button

# Tile Palette Section
var tile_palette_container: VBoxContainer
var tile_buttons: Array[Button] = []
var selected_tile_type: String = "NORMAL"

# Unit Palette Section
var unit_palette_container: VBoxContainer
var unit_buttons: Array[Button] = []
var selected_unit_type: String = "WARRIOR"
var selected_player_id: int = 0
var player_selector: OptionButton

# Map Grid Section
var grid_container: GridContainer
var grid_buttons: Array[Button] = []
var current_map: MapResource

# Tool Mode Section
var tool_mode_option: OptionButton
var clear_grid_button: Button

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

# Data
var tile_types = ["NORMAL", "DIFFICULT_TERRAIN", "WATER", "WALL", "SPECIAL", "LAVA", "ICE", "SWAMP", "SACRED_GROUND", "CORRUPTED"]
var unit_types = ["WARRIOR", "ARCHER", "MAGE"]
var difficulties = ["Easy", "Normal", "Hard", "Expert"]
var map_types = ["Skirmish", "Campaign", "Custom"]
var tool_modes = ["Place Tiles", "Place Units", "Erase"]

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
	
	width_input = SpinBox.new()
	width_input.min_value = 3
	width_input.max_value = 15
	width_input.value = 5
	width_container.add_child(width_input)
	
	# Height
	var height_container = VBoxContainer.new()
	size_container.add_child(height_container)
	
	var height_label = Label.new()
	height_label.text = "Height:"
	height_container.add_child(height_label)
	
	height_input = SpinBox.new()
	height_input.min_value = 3
	height_input.max_value = 15
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

func _create_tile_palette_section():
	"""Create tile selection palette"""
	var section_label = Label.new()
	section_label.text = "TILE PALETTE"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	tile_palette_container = VBoxContainer.new()
	main_container.add_child(tile_palette_container)
	
	# Create tile buttons in rows of 3
	var current_row: HBoxContainer = null
	for i in range(tile_types.size()):
		if i % 3 == 0:
			current_row = HBoxContainer.new()
			tile_palette_container.add_child(current_row)
		
		var tile_type = tile_types[i]
		var button = Button.new()
		button.text = tile_type.replace("_", " ")
		button.custom_minimum_size = Vector2(80, 30)
		button.modulate = tile_colors.get(tile_type, Color.WHITE)
		button.pressed.connect(_on_tile_selected.bind(tile_type))
		
		current_row.add_child(button)
		tile_buttons.append(button)
	
	# Select first tile by default
	if tile_buttons.size() > 0:
		_on_tile_selected(tile_types[0])

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
	
	# Unit type buttons
	var unit_row = HBoxContainer.new()
	unit_palette_container.add_child(unit_row)
	
	for unit_type in unit_types:
		var button = Button.new()
		button.text = unit_type
		button.custom_minimum_size = Vector2(80, 30)
		button.modulate = unit_colors.get(selected_player_id, Color.WHITE)
		button.pressed.connect(_on_unit_selected.bind(unit_type))
		
		unit_row.add_child(button)
		unit_buttons.append(button)
	
	# Select first unit by default
	if unit_buttons.size() > 0:
		_on_unit_selected(unit_types[0])

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

func _create_grid():
	"""Create the interactive grid for map editing"""
	# Clear existing grid
	for button in grid_buttons:
		if button:
			button.queue_free()
	grid_buttons.clear()
	
	var width = int(width_input.value)
	var height = int(height_input.value)
	
	grid_container.columns = width
	
	# Create grid buttons
	for y in range(height):
		for x in range(width):
			var button = Button.new()
			button.custom_minimum_size = Vector2(30, 30)
			button.text = ""
			button.modulate = Color.WHITE
			
			# Store position in button metadata
			button.set_meta("grid_pos", Vector2i(x, y))
			button.pressed.connect(_on_grid_button_pressed.bind(Vector2i(x, y)))
			
			grid_container.add_child(button)
			grid_buttons.append(button)
	
	_update_grid_display()

func _create_new_map():
	"""Create a new empty map"""
	current_map = MapResource.new()
	current_map.map_name = "New Map"
	current_map.author = "Map Creator"
	current_map.width = 5
	current_map.height = 5
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
	print("Tool mode changed to: " + tool_modes[index])

func _on_tile_selected(tile_type: String):
	"""Handle tile type selection"""
	selected_tile_type = tile_type
	
	# Update button states
	for i in range(tile_buttons.size()):
		if i < tile_types.size() and tile_types[i] == tile_type:
			tile_buttons[i].modulate = tile_colors.get(tile_type, Color.WHITE) * 1.5
		else:
			var button_tile_type = tile_types[i] if i < tile_types.size() else "NORMAL"
			tile_buttons[i].modulate = tile_colors.get(button_tile_type, Color.WHITE)
	
	print("Selected tile type: " + tile_type)

func _on_unit_selected(unit_type: String):
	"""Handle unit type selection"""
	selected_unit_type = unit_type
	
	# Update button states
	for i in range(unit_buttons.size()):
		if i < unit_types.size() and unit_types[i] == unit_type:
			unit_buttons[i].modulate = unit_colors.get(selected_player_id, Color.WHITE) * 1.5
		else:
			unit_buttons[i].modulate = unit_colors.get(selected_player_id, Color.WHITE)
	
	print("Selected unit type: " + unit_type + " for Player " + str(selected_player_id + 1))

func _on_player_selected(index: int):
	"""Handle player selection"""
	selected_player_id = index
	
	# Update unit button colors
	for button in unit_buttons:
		button.modulate = unit_colors.get(selected_player_id, Color.WHITE)
	
	print("Selected player: " + str(selected_player_id + 1))

func _on_grid_button_pressed(pos: Vector2i):
	"""Handle grid button press"""
	if not current_map:
		return
	
	var tool_mode = tool_modes[tool_mode_option.selected]
	
	match tool_mode:
		"Place Tiles":
			_place_tile_at_position(pos)
		"Place Units":
			_place_unit_at_position(pos)
		"Erase":
			_erase_at_position(pos)
	
	_update_grid_display()
	_update_preview()

func _place_tile_at_position(pos: Vector2i):
	"""Place selected tile at position"""
	current_map.set_tile_at_position(pos, selected_tile_type, "")
	print("Placed " + selected_tile_type + " at " + str(pos))

func _place_unit_at_position(pos: Vector2i):
	"""Place selected unit at position"""
	current_map.set_unit_spawn_at_position(pos, selected_player_id, selected_unit_type, "")
	print("Placed " + selected_unit_type + " for Player " + str(selected_player_id + 1) + " at " + str(pos))

func _erase_at_position(pos: Vector2i):
	"""Erase tile/unit at position"""
	# Reset tile to normal
	current_map.set_tile_at_position(pos, "NORMAL", "")
	# Remove unit spawn
	current_map.remove_unit_spawn_at_position(pos)
	print("Erased at " + str(pos))

func _on_clear_grid():
	"""Clear the entire grid"""
	if not current_map:
		return
	
	# Reset all tiles to normal
	current_map.create_default_layout()
	# Clear all unit spawns
	current_map.unit_spawns.clear()
	
	_update_grid_display()
	_update_preview()
	print("Grid cleared")

func _update_grid_display():
	"""Update the visual display of the grid"""
	if not current_map:
		return
	
	for i in range(grid_buttons.size()):
		var button = grid_buttons[i]
		var pos = button.get_meta("grid_pos", Vector2i(-1, -1))
		
		if pos == Vector2i(-1, -1):
			continue
		
		# Get tile data
		var tile_data = current_map.get_tile_at_position(pos)
		var tile_type = tile_data.get("tile_type", "NORMAL")
		
		# Get unit data
		var unit_data = current_map.get_unit_spawn_at_position(pos)
		
		# Set button appearance
		if not unit_data.is_empty():
			# Show unit
			var unit_type = unit_data.get("unit_type", "WARRIOR")
			var player_id = unit_data.get("player_id", 0)
			button.text = unit_type[0]  # First letter of unit type
			button.modulate = unit_colors.get(player_id, Color.WHITE)
		else:
			# Show tile
			button.text = ""
			button.modulate = tile_colors.get(tile_type, Color.WHITE)

func _on_map_info_changed(new_text: String = ""):
	"""Handle map information changes"""
	if not current_map:
		return
	
	current_map.map_name = map_name_input.text
	current_map.author = author_input.text
	current_map.description = description_input.text
	current_map.difficulty = difficulties[difficulty_option.selected]
	current_map.map_type = map_types[map_type_option.selected]
	
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
	preview_text.append("Total Units: " + str(info.get("total_spawns", 0)))
	
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

func _on_save_map():
	"""Save the current map"""
	if not current_map:
		return
	
	if current_map.map_name.is_empty():
		print("Error: Map name is required")
		return
	
	var validation = current_map.validate_map()
	if not validation.valid:
		print("Error: Cannot save invalid map")
		for issue in validation.issues:
			print("  - " + issue)
		return
	
	var success = MapLoader.save_map(current_map, current_map.map_name)
	if success:
		print("Map saved successfully: " + current_map.map_name)
	else:
		print("Failed to save map")

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
	if success:
		print("Map ready for testing. Load it from the Map Selection menu.")
		# Could potentially launch the game scene directly here
	else:
		print("Failed to prepare map for testing")

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