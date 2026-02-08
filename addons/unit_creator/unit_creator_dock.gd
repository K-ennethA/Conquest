@tool
extends Control

# Unit Creator Dock - Main interface for creating units

# UI Elements
var scroll_container: ScrollContainer
var main_container: VBoxContainer

# Basic Info Section
var name_input: LineEdit
var display_name_input: LineEdit
var description_input: TextEdit
var unit_type_option: OptionButton

# Stats Section
var health_input: SpinBox
var attack_input: SpinBox
var defense_input: SpinBox
var magic_input: SpinBox
var speed_input: SpinBox
var movement_input: SpinBox
var range_input: SpinBox

# Visual Section
var model_path_input: LineEdit
var model_browse_button: Button
var profile_image_input: LineEdit
var profile_browse_button: Button
var preview_container: VBoxContainer
var model_preview: SubViewport
var profile_preview: TextureRect

# Move Section
var moves_container: VBoxContainer
var available_moves_list: ItemList
var selected_moves_list: ItemList
var add_move_button: Button
var remove_move_button: Button

# Action Buttons
var create_button: Button
var save_template_button: Button
var load_template_button: Button
var clear_button: Button

# Data
var unit_types = ["Warrior", "Archer", "Mage", "Healer", "Tank", "Scout", "Custom"]
var available_moves: Array[Move] = []

func _init():
	name = "UnitCreator"
	set_custom_minimum_size(Vector2(300, 600))
	_create_ui()
	_load_available_moves()

func _create_ui():
	"""Create the complete UI for the unit creator"""
	# Main scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll_container)
	
	main_container = VBoxContainer.new()
	main_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll_container.add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "UNIT CREATOR"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)
	
	_add_separator()
	
	# Create sections
	_create_basic_info_section()
	_add_separator()
	_create_stats_section()
	_add_separator()
	_create_visual_section()
	_add_separator()
	_create_moves_section()
	_add_separator()
	_create_action_buttons()

func _add_separator():
	"""Add a visual separator"""
	var separator = HSeparator.new()
	main_container.add_child(separator)

func _create_basic_info_section():
	"""Create basic information input section"""
	var section_label = Label.new()
	section_label.text = "BASIC INFORMATION"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Unit Name
	var name_label = Label.new()
	name_label.text = "Unit Name (Internal):"
	main_container.add_child(name_label)
	
	name_input = LineEdit.new()
	name_input.placeholder_text = "e.g., elite_warrior"
	name_input.text_changed.connect(_on_name_changed)
	main_container.add_child(name_input)
	
	# Display Name
	var display_label = Label.new()
	display_label.text = "Display Name:"
	main_container.add_child(display_label)
	
	display_name_input = LineEdit.new()
	display_name_input.placeholder_text = "e.g., Elite Warrior"
	main_container.add_child(display_name_input)
	
	# Unit Type
	var type_label = Label.new()
	type_label.text = "Unit Type:"
	main_container.add_child(type_label)
	
	unit_type_option = OptionButton.new()
	for unit_type in unit_types:
		unit_type_option.add_item(unit_type)
	unit_type_option.selected = 0
	unit_type_option.item_selected.connect(_on_unit_type_changed)
	main_container.add_child(unit_type_option)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = "Description:"
	main_container.add_child(desc_label)
	
	description_input = TextEdit.new()
	description_input.placeholder_text = "Enter unit description..."
	description_input.custom_minimum_size = Vector2(0, 80)
	main_container.add_child(description_input)

func _create_stats_section():
	"""Create stats input section"""
	var section_label = Label.new()
	section_label.text = "UNIT STATS"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Create a grid for stats
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	main_container.add_child(stats_grid)
	
	# Health
	stats_grid.add_child(_create_label("Health:"))
	health_input = _create_spin_box(1, 999, 100)
	stats_grid.add_child(health_input)
	
	# Attack
	stats_grid.add_child(_create_label("Attack:"))
	attack_input = _create_spin_box(1, 99, 20)
	stats_grid.add_child(attack_input)
	
	# Defense
	stats_grid.add_child(_create_label("Defense:"))
	defense_input = _create_spin_box(1, 99, 15)
	stats_grid.add_child(defense_input)
	
	# Magic
	stats_grid.add_child(_create_label("Magic:"))
	magic_input = _create_spin_box(1, 99, 10)
	stats_grid.add_child(magic_input)
	
	# Speed
	stats_grid.add_child(_create_label("Speed:"))
	speed_input = _create_spin_box(1, 99, 12)
	stats_grid.add_child(speed_input)
	
	# Movement
	stats_grid.add_child(_create_label("Movement:"))
	movement_input = _create_spin_box(1, 10, 3)
	stats_grid.add_child(movement_input)
	
	# Range
	stats_grid.add_child(_create_label("Range:"))
	range_input = _create_spin_box(1, 10, 1)
	stats_grid.add_child(range_input)

func _create_visual_section():
	"""Create visual assets section"""
	var section_label = Label.new()
	section_label.text = "VISUAL ASSETS"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# 3D Model
	var model_label = Label.new()
	model_label.text = "3D Model (.glb/.gltf):"
	main_container.add_child(model_label)
	
	var model_container = HBoxContainer.new()
	main_container.add_child(model_container)
	
	model_path_input = LineEdit.new()
	model_path_input.placeholder_text = "Path to 3D model file"
	model_path_input.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	model_path_input.text_changed.connect(_on_model_path_changed)
	model_container.add_child(model_path_input)
	
	model_browse_button = Button.new()
	model_browse_button.text = "Browse"
	model_browse_button.pressed.connect(_on_browse_model)
	model_container.add_child(model_browse_button)
	
	# Profile Image
	var profile_label = Label.new()
	profile_label.text = "Profile Image (.png/.jpg):"
	main_container.add_child(profile_label)
	
	var profile_container = HBoxContainer.new()
	main_container.add_child(profile_container)
	
	profile_image_input = LineEdit.new()
	profile_image_input.placeholder_text = "Path to profile image"
	profile_image_input.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	profile_image_input.text_changed.connect(_on_profile_path_changed)
	profile_container.add_child(profile_image_input)
	
	profile_browse_button = Button.new()
	profile_browse_button.text = "Browse"
	profile_browse_button.pressed.connect(_on_browse_profile)
	profile_container.add_child(profile_browse_button)
	
	# Preview Section
	var preview_label = Label.new()
	preview_label.text = "Preview:"
	main_container.add_child(preview_label)
	
	preview_container = VBoxContainer.new()
	main_container.add_child(preview_container)
	
	# Profile image preview
	profile_preview = TextureRect.new()
	profile_preview.custom_minimum_size = Vector2(100, 100)
	profile_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	profile_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_container.add_child(profile_preview)
	
	# Model preview placeholder
	var model_preview_label = Label.new()
	model_preview_label.text = "3D Model Preview: (Will show when model is loaded)"
	model_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_container.add_child(model_preview_label)

func _create_moves_section():
	"""Create moves selection section"""
	var section_label = Label.new()
	section_label.text = "UNIT MOVES (Max 5)"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	var moves_h_container = HBoxContainer.new()
	main_container.add_child(moves_h_container)
	
	# Available moves
	var available_container = VBoxContainer.new()
	available_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	moves_h_container.add_child(available_container)
	
	var available_label = Label.new()
	available_label.text = "Available Moves:"
	available_container.add_child(available_label)
	
	available_moves_list = ItemList.new()
	available_moves_list.custom_minimum_size = Vector2(120, 150)
	available_moves_list.item_selected.connect(_on_available_move_selected)
	available_container.add_child(available_moves_list)
	
	# Move buttons
	var button_container = VBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	moves_h_container.add_child(button_container)
	
	add_move_button = Button.new()
	add_move_button.text = "→"
	add_move_button.custom_minimum_size = Vector2(40, 30)
	add_move_button.pressed.connect(_on_add_move)
	button_container.add_child(add_move_button)
	
	remove_move_button = Button.new()
	remove_move_button.text = "←"
	remove_move_button.custom_minimum_size = Vector2(40, 30)
	remove_move_button.pressed.connect(_on_remove_move)
	button_container.add_child(remove_move_button)
	
	# Selected moves
	var selected_container = VBoxContainer.new()
	selected_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	moves_h_container.add_child(selected_container)
	
	var selected_label = Label.new()
	selected_label.text = "Unit Moves:"
	selected_container.add_child(selected_label)
	
	selected_moves_list = ItemList.new()
	selected_moves_list.custom_minimum_size = Vector2(120, 150)
	selected_moves_list.item_selected.connect(_on_selected_move_selected)
	selected_container.add_child(selected_moves_list)

func _create_action_buttons():
	"""Create action buttons section"""
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(button_container)
	
	create_button = Button.new()
	create_button.text = "CREATE UNIT"
	create_button.custom_minimum_size = Vector2(100, 40)
	create_button.pressed.connect(_on_create_unit)
	button_container.add_child(create_button)
	
	save_template_button = Button.new()
	save_template_button.text = "SAVE TEMPLATE"
	save_template_button.custom_minimum_size = Vector2(100, 40)
	save_template_button.pressed.connect(_on_save_template)
	button_container.add_child(save_template_button)
	
	load_template_button = Button.new()
	load_template_button.text = "LOAD TEMPLATE"
	load_template_button.custom_minimum_size = Vector2(100, 40)
	load_template_button.pressed.connect(_on_load_template)
	button_container.add_child(load_template_button)
	
	clear_button = Button.new()
	clear_button.text = "CLEAR"
	clear_button.custom_minimum_size = Vector2(80, 40)
	clear_button.pressed.connect(_on_clear_form)
	button_container.add_child(clear_button)

func _create_label(text: String) -> Label:
	"""Helper to create a label"""
	var label = Label.new()
	label.text = text
	return label

func _create_spin_box(min_val: int, max_val: int, default_val: int) -> SpinBox:
	"""Helper to create a spin box"""
	var spin_box = SpinBox.new()
	spin_box.min_value = min_val
	spin_box.max_value = max_val
	spin_box.value = default_val
	spin_box.step = 1
	return spin_box

func _load_available_moves():
	"""Load all available moves from MoveFactory"""
	available_moves = MoveFactory.get_all_moves()
	_update_available_moves_list()

func _update_available_moves_list():
	"""Update the available moves list"""
	if not available_moves_list:
		return
	
	available_moves_list.clear()
	for move in available_moves:
		if move:
			available_moves_list.add_item(move.name + " (" + Move.MoveType.keys()[move.move_type] + ")")

# Signal handlers
func _on_name_changed(new_text: String):
	"""Handle name input change"""
	# Auto-generate display name if it's empty
	if display_name_input and display_name_input.text.is_empty():
		var display_name = new_text.replace("_", " ").capitalize()
		display_name_input.text = display_name

func _on_unit_type_changed(index: int):
	"""Handle unit type selection change"""
	var selected_type = unit_types[index]
	_apply_unit_type_defaults(selected_type)

func _apply_unit_type_defaults(unit_type: String):
	"""Apply default stats based on unit type"""
	match unit_type:
		"Warrior":
			health_input.value = 120
			attack_input.value = 25
			defense_input.value = 20
			magic_input.value = 5
			speed_input.value = 10
			movement_input.value = 3
			range_input.value = 1
		"Archer":
			health_input.value = 80
			attack_input.value = 20
			defense_input.value = 10
			magic_input.value = 8
			speed_input.value = 15
			movement_input.value = 3
			range_input.value = 4
		"Mage":
			health_input.value = 60
			attack_input.value = 10
			defense_input.value = 8
			magic_input.value = 25
			speed_input.value = 12
			movement_input.value = 2
			range_input.value = 3
		"Healer":
			health_input.value = 70
			attack_input.value = 8
			defense_input.value = 12
			magic_input.value = 20
			speed_input.value = 11
			movement_input.value = 2
			range_input.value = 2
		"Tank":
			health_input.value = 150
			attack_input.value = 15
			defense_input.value = 30
			magic_input.value = 3
			speed_input.value = 8
			movement_input.value = 2
			range_input.value = 1
		"Scout":
			health_input.value = 90
			attack_input.value = 18
			defense_input.value = 12
			magic_input.value = 10
			speed_input.value = 18
			movement_input.value = 4
			range_input.value = 2

func _on_model_path_changed(new_path: String):
	"""Handle model path change"""
	# TODO: Load and preview 3D model
	pass

func _on_profile_path_changed(new_path: String):
	"""Handle profile image path change"""
	_load_profile_preview(new_path)

func _load_profile_preview(path: String):
	"""Load and display profile image preview"""
	if path.is_empty() or not profile_preview:
		return
	
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			profile_preview.texture = texture
			print("Profile image loaded: " + path)
		else:
			print("Failed to load profile image: " + path)

func _on_browse_model():
	"""Open file dialog for 3D model"""
	var dialog = load("res://addons/unit_creator/file_browser_dialog.gd").new(
		"Select 3D Model", 
		["*.glb ; GLTF Binary Files", "*.gltf ; GLTF Text Files", "*.dae ; Collada Files"]
	)
	add_child(dialog)
	dialog.file_selected.connect(_on_model_file_selected)
	dialog.show_dialog()

func _on_browse_profile():
	"""Open file dialog for profile image"""
	var dialog = load("res://addons/unit_creator/file_browser_dialog.gd").new(
		"Select Profile Image", 
		["*.png ; PNG Images", "*.jpg ; JPEG Images", "*.jpeg ; JPEG Images", "*.webp ; WebP Images"]
	)
	add_child(dialog)
	dialog.file_selected.connect(_on_profile_file_selected)
	dialog.show_dialog()

func _on_model_file_selected(path: String):
	"""Handle model file selection"""
	model_path_input.text = path
	print("Model selected: " + path)

func _on_profile_file_selected(path: String):
	"""Handle profile image file selection"""
	profile_image_input.text = path
	_load_profile_preview(path)
	print("Profile image selected: " + path)

func _on_available_move_selected(index: int):
	"""Handle available move selection"""
	# Enable add button
	add_move_button.disabled = false

func _on_selected_move_selected(index: int):
	"""Handle selected move selection"""
	# Enable remove button
	remove_move_button.disabled = false

func _on_add_move():
	"""Add selected move to unit"""
	var selected_index = available_moves_list.get_selected_items()
	if selected_index.is_empty():
		return
	
	var move_index = selected_index[0]
	if move_index >= 0 and move_index < available_moves.size():
		var move = available_moves[move_index]
		
		# Check if already added
		for i in range(selected_moves_list.get_item_count()):
			if selected_moves_list.get_item_text(i).begins_with(move.name):
				print("Move already added: " + move.name)
				return
		
		# Check max moves limit
		if selected_moves_list.get_item_count() >= 5:
			print("Maximum 5 moves allowed")
			return
		
		# Add move
		selected_moves_list.add_item(move.name + " (" + Move.MoveType.keys()[move.move_type] + ")")
		print("Added move: " + move.name)

func _on_remove_move():
	"""Remove selected move from unit"""
	var selected_index = selected_moves_list.get_selected_items()
	if selected_index.is_empty():
		return
	
	var move_index = selected_index[0]
	var move_name = selected_moves_list.get_item_text(move_index)
	selected_moves_list.remove_item(move_index)
	print("Removed move: " + move_name)

func _on_create_unit():
	"""Create the unit with current settings"""
	if not _validate_input():
		return
	
	var unit_data = _collect_unit_data()
	var success = _create_unit_files(unit_data)
	
	if success:
		print("Unit created successfully: " + unit_data.name)
		# TODO: Show success dialog
	else:
		print("Failed to create unit")
		# TODO: Show error dialog

func _on_save_template():
	"""Save current settings as template"""
	var unit_data = _collect_unit_data()
	
	# Create input dialog for template name
	var input_dialog = AcceptDialog.new()
	input_dialog.title = "Save Template"
	
	var vbox = VBoxContainer.new()
	input_dialog.add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter template name:"
	vbox.add_child(label)
	
	var name_input = LineEdit.new()
	name_input.text = unit_data.name + "_template"
	name_input.placeholder_text = "template_name"
	vbox.add_child(name_input)
	
	var save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(func():
		var template_name = name_input.text
		if not template_name.is_empty():
			if UnitTemplateManager.save_template(unit_data, template_name):
				print("Template saved: " + template_name)
			else:
				print("Failed to save template")
		input_dialog.hide()
	)
	vbox.add_child(save_button)
	
	add_child(input_dialog)
	input_dialog.popup_centered()

func _on_load_template():
	"""Load template"""
	var template_dialog = load("res://addons/unit_creator/template_dialog.gd").new()
	add_child(template_dialog)
	template_dialog.template_selected.connect(_load_template_data)
	template_dialog.show_dialog()

func _load_template_data(template_name: String):
	"""Load template data into the form"""
	var template_data = UnitTemplateManager.load_template(template_name)
	
	if template_data.is_empty():
		print("Failed to load template: " + template_name)
		return
	
	# Fill form with template data
	name_input.text = template_data.get("name", "")
	display_name_input.text = template_data.get("display_name", "")
	description_input.text = template_data.get("description", "")
	
	# Set unit type
	var unit_type = template_data.get("unit_type", "Warrior")
	for i in range(unit_types.size()):
		if unit_types[i] == unit_type:
			unit_type_option.selected = i
			break
	
	# Set stats
	var stats = template_data.get("stats", {})
	health_input.value = stats.get("health", 100)
	attack_input.value = stats.get("attack", 20)
	defense_input.value = stats.get("defense", 15)
	magic_input.value = stats.get("magic", 10)
	speed_input.value = stats.get("speed", 12)
	movement_input.value = stats.get("movement", 3)
	range_input.value = stats.get("range", 1)
	
	# Set visual paths
	model_path_input.text = template_data.get("model_path", "")
	profile_image_input.text = template_data.get("profile_image_path", "")
	_load_profile_preview(profile_image_input.text)
	
	# Set moves
	selected_moves_list.clear()
	var moves = template_data.get("moves", [])
	for move_name in moves:
		# Find move type for display
		var move_type = "UNKNOWN"
		for move in available_moves:
			if move and move.name == move_name:
				move_type = Move.MoveType.keys()[move.move_type]
				break
		selected_moves_list.add_item(move_name + " (" + move_type + ")")
	
	print("Template loaded: " + template_name)

func _on_clear_form():
	"""Clear all form fields"""
	name_input.text = ""
	display_name_input.text = ""
	description_input.text = ""
	unit_type_option.selected = 0
	
	health_input.value = 100
	attack_input.value = 20
	defense_input.value = 15
	magic_input.value = 10
	speed_input.value = 12
	movement_input.value = 3
	range_input.value = 1
	
	model_path_input.text = ""
	profile_image_input.text = ""
	profile_preview.texture = null
	
	selected_moves_list.clear()
	
	print("Form cleared")

func _validate_input() -> bool:
	"""Validate user input"""
	if name_input.text.is_empty():
		print("Error: Unit name is required")
		return false
	
	if display_name_input.text.is_empty():
		print("Error: Display name is required")
		return false
	
	return true

func _collect_unit_data() -> Dictionary:
	"""Collect all unit data from the form"""
	var selected_move_names: Array[String] = []
	for i in range(selected_moves_list.get_item_count()):
		var item_text = selected_moves_list.get_item_text(i)
		var move_name = item_text.split(" (")[0]  # Extract name before type
		selected_move_names.append(move_name)
	
	return {
		"name": name_input.text,
		"display_name": display_name_input.text,
		"description": description_input.text,
		"unit_type": unit_types[unit_type_option.selected],
		"stats": {
			"health": int(health_input.value),
			"attack": int(attack_input.value),
			"defense": int(defense_input.value),
			"magic": int(magic_input.value),
			"speed": int(speed_input.value),
			"movement": int(movement_input.value),
			"range": int(range_input.value)
		},
		"model_path": model_path_input.text,
		"profile_image_path": profile_image_input.text,
		"moves": selected_move_names
	}

func _create_unit_files(unit_data: Dictionary) -> bool:
	"""Create all necessary files for the unit"""
	var unit_name = unit_data.name
	
	# Create unit resource file
	if not _create_unit_resource(unit_data):
		return false
	
	# Create unit scene file
	if not _create_unit_scene(unit_data):
		return false
	
	print("Unit files created successfully for: " + unit_name)
	return true

func _create_unit_resource(unit_data: Dictionary) -> bool:
	"""Create unit stats resource file"""
	var resource_path = "res://game/units/resources/" + unit_data.name + ".tres"
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/units/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/units/resources")
	
	# Create UnitStatsResource
	var unit_stats = UnitStatsResource.new()
	unit_stats.unit_name = unit_data.display_name
	unit_stats.unit_type = unit_data.unit_type
	unit_stats.description = unit_data.description
	unit_stats.max_health = unit_data.stats.health
	unit_stats.base_attack = unit_data.stats.attack
	unit_stats.base_defense = unit_data.stats.defense
	unit_stats.base_magic = unit_data.stats.magic
	unit_stats.base_speed = unit_data.stats.speed
	unit_stats.movement_range = unit_data.stats.movement
	unit_stats.attack_range = unit_data.stats.range
	
	# Save resource
	var result = ResourceSaver.save(unit_stats, resource_path)
	if result == OK:
		print("Unit resource created: " + resource_path)
		return true
	else:
		print("Failed to create unit resource: " + str(result))
		return false

func _create_unit_scene(unit_data: Dictionary) -> bool:
	"""Create unit scene file"""
	var scene_path = "res://game/units/scenes/" + unit_data.name + ".tscn"
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/units/scenes/"):
		DirAccess.open("res://").make_dir_recursive("game/units/scenes")
	
	# Create unit scene
	var unit_scene = PackedScene.new()
	var unit_node = Node3D.new()
	unit_node.name = unit_data.display_name.replace(" ", "")
	unit_node.set_script(load("res://tile_objects/units/unit.gd"))
	
	# Add UnitStats component
	var unit_stats = load("res://game/units/components/UnitStats.gd").new()
	unit_stats.name = "UnitStats"
	unit_stats.stats_resource = load("res://game/units/resources/" + unit_data.name + ".tres")
	unit_node.add_child(unit_stats)
	unit_stats.owner = unit_node
	
	# Add MoveManager component
	var move_manager = load("res://game/units/components/MoveManager.gd").new()
	move_manager.name = "MoveManager"
	unit_node.add_child(move_manager)
	move_manager.owner = unit_node
	
	# Add 3D model if specified
	if not unit_data.model_path.is_empty() and ResourceLoader.exists(unit_data.model_path):
		var model_scene = load(unit_data.model_path)
		if model_scene is PackedScene:
			var model_instance = model_scene.instantiate()
			unit_node.add_child(model_instance)
			model_instance.owner = unit_node
	
	# Pack and save scene
	unit_scene.pack(unit_node)
	var result = ResourceSaver.save(unit_scene, scene_path)
	
	if result == OK:
		print("Unit scene created: " + scene_path)
		return true
	else:
		print("Failed to create unit scene: " + str(result))
		return false