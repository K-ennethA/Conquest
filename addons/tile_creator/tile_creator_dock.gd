@tool
extends Control

# Tile Creator Dock - Main interface for creating tiles

# UI Elements
var scroll_container: ScrollContainer
var main_container: VBoxContainer

# Basic Info Section
var name_input: LineEdit
var description_input: TextEdit
var tile_type_option: OptionButton

# Movement Section
var movement_cost_input: SpinBox
var passable_checkbox: CheckBox
var blocks_sight_checkbox: CheckBox

# Visual Section
var color_picker: ColorPicker
var emission_checkbox: CheckBox
var emission_color_picker: ColorPicker
var metallic_slider: HSlider
var roughness_slider: HSlider
var texture_path_input: LineEdit
var texture_browse_button: Button
var model_path_input: LineEdit
var model_browse_button: Button

# Effects Section
var has_effects_checkbox: CheckBox
var effects_container: VBoxContainer
var available_effects_list: ItemList
var tile_effects_list: ItemList
var add_effect_button: Button
var remove_effect_button: Button
var effect_strength_input: SpinBox
var effect_duration_input: SpinBox

# Gameplay Section
var provides_cover_checkbox: CheckBox
var cover_bonus_input: SpinBox
var elevation_input: SpinBox
var rarity_option: OptionButton

# Preview Section
var preview_container: VBoxContainer
var preview_viewport: SubViewport
var preview_tile: MeshInstance3D

# Action Buttons
var create_button: Button
var save_template_button: Button
var load_template_button: Button
var clear_button: Button

# Data
var tile_types = ["NORMAL", "DIFFICULT_TERRAIN", "WATER", "WALL", "SPECIAL", "LAVA", "ICE", "SWAMP", "SACRED_GROUND", "CORRUPTED"]
var effect_types = []
var rarities = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
var current_tile_effects: Array[TileEffect] = []

func _init():
	name = "TileCreator"
	set_custom_minimum_size(Vector2(350, 700))
	_load_effect_types()
	_create_ui()

func _load_effect_types():
	"""Load available effect types"""
	for effect_type in TileEffect.EffectType.values():
		if effect_type != TileEffect.EffectType.NONE:
			effect_types.append(TileEffect.EffectType.keys()[effect_type])

func _create_ui():
	"""Create the complete UI for the tile creator"""
	# Main scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll_container)
	
	main_container = VBoxContainer.new()
	main_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	scroll_container.add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "TILE CREATOR"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)
	
	_add_separator()
	
	# Create sections
	_create_basic_info_section()
	_add_separator()
	_create_movement_section()
	_add_separator()
	_create_visual_section()
	_add_separator()
	_create_effects_section()
	_add_separator()
	_create_gameplay_section()
	_add_separator()
	_create_preview_section()
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
	
	# Tile Name
	var name_label = Label.new()
	name_label.text = "Tile Name:"
	main_container.add_child(name_label)
	
	name_input = LineEdit.new()
	name_input.placeholder_text = "e.g., Lava Pit"
	main_container.add_child(name_input)
	
	# Tile Type
	var type_label = Label.new()
	type_label.text = "Tile Type:"
	main_container.add_child(type_label)
	
	tile_type_option = OptionButton.new()
	for tile_type in tile_types:
		tile_type_option.add_item(tile_type)
	tile_type_option.selected = 0
	tile_type_option.item_selected.connect(_on_tile_type_changed)
	main_container.add_child(tile_type_option)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = "Description:"
	main_container.add_child(desc_label)
	
	description_input = TextEdit.new()
	description_input.placeholder_text = "Enter tile description..."
	description_input.custom_minimum_size = Vector2(0, 80)
	main_container.add_child(description_input)

func _create_movement_section():
	"""Create movement properties section"""
	var section_label = Label.new()
	section_label.text = "MOVEMENT PROPERTIES"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Movement Cost
	var cost_label = Label.new()
	cost_label.text = "Movement Cost:"
	main_container.add_child(cost_label)
	
	movement_cost_input = SpinBox.new()
	movement_cost_input.min_value = 1
	movement_cost_input.max_value = 10
	movement_cost_input.value = 1
	main_container.add_child(movement_cost_input)
	
	# Passable
	passable_checkbox = CheckBox.new()
	passable_checkbox.text = "Units can move through this tile"
	passable_checkbox.button_pressed = true
	main_container.add_child(passable_checkbox)
	
	# Blocks Line of Sight
	blocks_sight_checkbox = CheckBox.new()
	blocks_sight_checkbox.text = "Blocks line of sight"
	main_container.add_child(blocks_sight_checkbox)

func _create_visual_section():
	"""Create visual properties section"""
	var section_label = Label.new()
	section_label.text = "VISUAL PROPERTIES"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Base Color
	var color_label = Label.new()
	color_label.text = "Base Color:"
	main_container.add_child(color_label)
	
	color_picker = ColorPicker.new()
	color_picker.custom_minimum_size = Vector2(300, 200)
	color_picker.color = Color.WHITE
	color_picker.color_changed.connect(_on_color_changed)
	main_container.add_child(color_picker)
	
	# Emission
	emission_checkbox = CheckBox.new()
	emission_checkbox.text = "Enable Emission (Glow)"
	emission_checkbox.toggled.connect(_on_emission_toggled)
	main_container.add_child(emission_checkbox)
	
	var emission_color_label = Label.new()
	emission_color_label.text = "Emission Color:"
	main_container.add_child(emission_color_label)
	
	emission_color_picker = ColorPicker.new()
	emission_color_picker.custom_minimum_size = Vector2(300, 150)
	emission_color_picker.color = Color.BLACK
	emission_color_picker.visible = false
	emission_color_picker.color_changed.connect(_on_emission_color_changed)
	main_container.add_child(emission_color_picker)
	
	# Material Properties
	var metallic_label = Label.new()
	metallic_label.text = "Metallic:"
	main_container.add_child(metallic_label)
	
	metallic_slider = HSlider.new()
	metallic_slider.min_value = 0.0
	metallic_slider.max_value = 1.0
	metallic_slider.value = 0.0
	metallic_slider.step = 0.1
	metallic_slider.value_changed.connect(_on_material_changed)
	main_container.add_child(metallic_slider)
	
	var roughness_label = Label.new()
	roughness_label.text = "Roughness:"
	main_container.add_child(roughness_label)
	
	roughness_slider = HSlider.new()
	roughness_slider.min_value = 0.0
	roughness_slider.max_value = 1.0
	roughness_slider.value = 1.0
	roughness_slider.step = 0.1
	roughness_slider.value_changed.connect(_on_material_changed)
	main_container.add_child(roughness_slider)
	
	# Texture
	var texture_label = Label.new()
	texture_label.text = "Texture (Optional):"
	main_container.add_child(texture_label)
	
	var texture_container = HBoxContainer.new()
	main_container.add_child(texture_container)
	
	texture_path_input = LineEdit.new()
	texture_path_input.placeholder_text = "Path to texture file"
	texture_path_input.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	texture_container.add_child(texture_path_input)
	
	texture_browse_button = Button.new()
	texture_browse_button.text = "Browse"
	texture_browse_button.pressed.connect(_on_browse_texture)
	texture_container.add_child(texture_browse_button)

func _create_effects_section():
	"""Create tile effects section"""
	var section_label = Label.new()
	section_label.text = "TILE EFFECTS"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Has Effects Checkbox
	has_effects_checkbox = CheckBox.new()
	has_effects_checkbox.text = "This tile has special effects"
	has_effects_checkbox.toggled.connect(_on_has_effects_toggled)
	main_container.add_child(has_effects_checkbox)
	
	# Effects Container (initially hidden)
	effects_container = VBoxContainer.new()
	effects_container.visible = false
	main_container.add_child(effects_container)
	
	# Available Effects
	var available_label = Label.new()
	available_label.text = "Available Effects:"
	effects_container.add_child(available_label)
	
	available_effects_list = ItemList.new()
	available_effects_list.custom_minimum_size = Vector2(300, 120)
	for effect_type in effect_types:
		available_effects_list.add_item(effect_type)
	effects_container.add_child(available_effects_list)
	
	# Effect Properties
	var effect_props_container = HBoxContainer.new()
	effects_container.add_child(effect_props_container)
	
	var strength_container = VBoxContainer.new()
	effect_props_container.add_child(strength_container)
	
	var strength_label = Label.new()
	strength_label.text = "Strength:"
	strength_container.add_child(strength_label)
	
	effect_strength_input = SpinBox.new()
	effect_strength_input.min_value = 1
	effect_strength_input.max_value = 10
	effect_strength_input.value = 1
	strength_container.add_child(effect_strength_input)
	
	var duration_container = VBoxContainer.new()
	effect_props_container.add_child(duration_container)
	
	var duration_label = Label.new()
	duration_label.text = "Duration (-1=Permanent):"
	duration_container.add_child(duration_label)
	
	effect_duration_input = SpinBox.new()
	effect_duration_input.min_value = -1
	effect_duration_input.max_value = 20
	effect_duration_input.value = -1
	duration_container.add_child(effect_duration_input)
	
	# Add/Remove Buttons
	var button_container = HBoxContainer.new()
	effects_container.add_child(button_container)
	
	add_effect_button = Button.new()
	add_effect_button.text = "Add Effect"
	add_effect_button.pressed.connect(_on_add_effect)
	button_container.add_child(add_effect_button)
	
	remove_effect_button = Button.new()
	remove_effect_button.text = "Remove Effect"
	remove_effect_button.pressed.connect(_on_remove_effect)
	button_container.add_child(remove_effect_button)
	
	# Tile Effects List
	var tile_effects_label = Label.new()
	tile_effects_label.text = "Tile Effects:"
	effects_container.add_child(tile_effects_label)
	
	tile_effects_list = ItemList.new()
	tile_effects_list.custom_minimum_size = Vector2(300, 100)
	effects_container.add_child(tile_effects_list)

func _create_gameplay_section():
	"""Create gameplay properties section"""
	var section_label = Label.new()
	section_label.text = "GAMEPLAY PROPERTIES"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	# Provides Cover
	provides_cover_checkbox = CheckBox.new()
	provides_cover_checkbox.text = "Provides cover to units"
	main_container.add_child(provides_cover_checkbox)
	
	# Cover Bonus
	var cover_label = Label.new()
	cover_label.text = "Cover Bonus:"
	main_container.add_child(cover_label)
	
	cover_bonus_input = SpinBox.new()
	cover_bonus_input.min_value = 0
	cover_bonus_input.max_value = 10
	cover_bonus_input.value = 0
	main_container.add_child(cover_bonus_input)
	
	# Elevation
	var elevation_label = Label.new()
	elevation_label.text = "Elevation:"
	main_container.add_child(elevation_label)
	
	elevation_input = SpinBox.new()
	elevation_input.min_value = -5
	elevation_input.max_value = 10
	elevation_input.value = 0
	main_container.add_child(elevation_input)
	
	# Rarity
	var rarity_label = Label.new()
	rarity_label.text = "Rarity:"
	main_container.add_child(rarity_label)
	
	rarity_option = OptionButton.new()
	for rarity in rarities:
		rarity_option.add_item(rarity)
	rarity_option.selected = 0
	main_container.add_child(rarity_option)

func _create_preview_section():
	"""Create tile preview section"""
	var section_label = Label.new()
	section_label.text = "PREVIEW"
	section_label.add_theme_font_size_override("font_size", 14)
	main_container.add_child(section_label)
	
	preview_container = VBoxContainer.new()
	main_container.add_child(preview_container)
	
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(300, 200)
	viewport_container.stretch = true
	preview_container.add_child(viewport_container)
	
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2(300, 200)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(preview_viewport)
	
	_setup_preview_scene()

func _setup_preview_scene():
	"""Set up the 3D preview scene"""
	# Add camera
	var camera = Camera3D.new()
	camera.position = Vector3(2, 3, 2)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	preview_viewport.add_child(camera)
	
	# Add lighting
	var light = DirectionalLight3D.new()
	light.position = Vector3(2, 3, 2)
	light.look_at(Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 1.0
	preview_viewport.add_child(light)
	
	# Add environment
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.3, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5, 1.0)
	env.ambient_light_energy = 0.3
	camera.environment = env
	
	# Add preview tile
	preview_tile = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2, 0.2, 2)
	preview_tile.mesh = mesh
	preview_viewport.add_child(preview_tile)
	
	_update_preview()

func _create_action_buttons():
	"""Create action buttons section"""
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	main_container.add_child(button_container)
	
	create_button = Button.new()
	create_button.text = "CREATE TILE"
	create_button.custom_minimum_size = Vector2(100, 40)
	create_button.pressed.connect(_on_create_tile)
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

# Signal handlers
func _on_tile_type_changed(index: int):
	"""Handle tile type selection change"""
	_apply_tile_type_defaults(tile_types[index])
	_update_preview()

func _apply_tile_type_defaults(tile_type: String):
	"""Apply default properties based on tile type"""
	match tile_type:
		"NORMAL":
			color_picker.color = Color(0.8, 0.8, 0.8, 1.0)
			movement_cost_input.value = 1
			passable_checkbox.button_pressed = true
		"DIFFICULT_TERRAIN":
			color_picker.color = Color(0.6, 0.4, 0.2, 1.0)
			movement_cost_input.value = 2
			passable_checkbox.button_pressed = true
		"WATER":
			color_picker.color = Color(0.2, 0.4, 0.8, 1.0)
			movement_cost_input.value = 3
			passable_checkbox.button_pressed = true
			metallic_slider.value = 0.8
			roughness_slider.value = 0.1
		"WALL":
			color_picker.color = Color(0.3, 0.3, 0.3, 1.0)
			movement_cost_input.value = 10
			passable_checkbox.button_pressed = false
			blocks_sight_checkbox.button_pressed = true
			provides_cover_checkbox.button_pressed = true
			cover_bonus_input.value = 3
		"LAVA":
			color_picker.color = Color(1.0, 0.2, 0.0, 1.0)
			movement_cost_input.value = 4
			passable_checkbox.button_pressed = true
			emission_checkbox.button_pressed = true
			emission_color_picker.color = Color(1.0, 0.3, 0.0)
			has_effects_checkbox.button_pressed = true
		"ICE":
			color_picker.color = Color(0.8, 0.9, 1.0, 0.9)
			movement_cost_input.value = 1
			passable_checkbox.button_pressed = true
			metallic_slider.value = 0.9
			roughness_slider.value = 0.0
		"SWAMP":
			color_picker.color = Color(0.3, 0.5, 0.2, 1.0)
			movement_cost_input.value = 3
			passable_checkbox.button_pressed = true
		"SACRED_GROUND":
			color_picker.color = Color(1.0, 1.0, 0.9, 1.0)
			movement_cost_input.value = 1
			passable_checkbox.button_pressed = true
			emission_checkbox.button_pressed = true
			emission_color_picker.color = Color(0.9, 0.9, 0.7)
			has_effects_checkbox.button_pressed = true
		"CORRUPTED":
			color_picker.color = Color(0.4, 0.2, 0.4, 1.0)
			movement_cost_input.value = 2
			passable_checkbox.button_pressed = true
			emission_checkbox.button_pressed = true
			emission_color_picker.color = Color(0.3, 0.1, 0.3)
			has_effects_checkbox.button_pressed = true

func _on_color_changed(color: Color):
	"""Handle base color change"""
	_update_preview()

func _on_emission_toggled(enabled: bool):
	"""Handle emission toggle"""
	emission_color_picker.visible = enabled
	_update_preview()

func _on_emission_color_changed(color: Color):
	"""Handle emission color change"""
	_update_preview()

func _on_material_changed(value: float):
	"""Handle material property changes"""
	_update_preview()

func _on_has_effects_toggled(enabled: bool):
	"""Handle effects toggle"""
	effects_container.visible = enabled

func _on_add_effect():
	"""Add selected effect to tile"""
	var selected_indices = available_effects_list.get_selected_items()
	if selected_indices.is_empty():
		return
	
	var effect_index = selected_indices[0]
	var effect_name = effect_types[effect_index]
	
	# Create new tile effect
	var tile_effect = TileEffect.new()
	tile_effect.effect_name = effect_name
	tile_effect.effect_type = effect_index + 1  # +1 because NONE is 0
	tile_effect.strength = int(effect_strength_input.value)
	tile_effect.duration = int(effect_duration_input.value)
	
	# Set appropriate triggers
	match tile_effect.effect_type:
		TileEffect.EffectType.FIRE_DAMAGE, TileEffect.EffectType.ICE_DAMAGE, TileEffect.EffectType.POISON_DAMAGE:
			tile_effect.triggers_on_enter = true
			tile_effect.triggers_on_turn_start = true
		TileEffect.EffectType.HEALING_SPRING, TileEffect.EffectType.REGENERATION_FIELD:
			tile_effect.triggers_on_enter = true
			tile_effect.triggers_on_turn_start = true
		TileEffect.EffectType.SPEED_BOOST, TileEffect.EffectType.ATTACK_BOOST, TileEffect.EffectType.DEFENSE_BOOST:
			tile_effect.triggers_on_enter = true
		TileEffect.EffectType.TRAP:
			tile_effect.triggers_on_enter = true
		_:
			tile_effect.triggers_on_enter = true
	
	current_tile_effects.append(tile_effect)
	_update_effects_list()
	print("Added effect: " + effect_name)

func _on_remove_effect():
	"""Remove selected effect from tile"""
	var selected_indices = tile_effects_list.get_selected_items()
	if selected_indices.is_empty():
		return
	
	var effect_index = selected_indices[0]
	if effect_index >= 0 and effect_index < current_tile_effects.size():
		var removed_effect = current_tile_effects[effect_index]
		current_tile_effects.remove_at(effect_index)
		_update_effects_list()
		print("Removed effect: " + removed_effect.effect_name)

func _update_effects_list():
	"""Update the tile effects list display"""
	tile_effects_list.clear()
	for effect in current_tile_effects:
		var display_text = effect.effect_name + " (Str:" + str(effect.strength) + ", Dur:" + str(effect.duration) + ")"
		tile_effects_list.add_item(display_text)

func _on_browse_texture():
	"""Open file dialog for texture"""
	# This would open a file dialog - simplified for now
	print("Browse texture clicked")

func _update_preview():
	"""Update the 3D preview"""
	if not preview_tile:
		return
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color_picker.color
	material.metallic = metallic_slider.value
	material.roughness = roughness_slider.value
	
	if emission_checkbox.button_pressed:
		material.emission_enabled = true
		material.emission = emission_color_picker.color
	
	preview_tile.material_override = material

func _on_create_tile():
	"""Create the tile with current settings"""
	if not _validate_input():
		return
	
	var tile_data = _collect_tile_data()
	var success = _create_tile_files(tile_data)
	
	if success:
		print("Tile created successfully: " + tile_data.name)
	else:
		print("Failed to create tile")

func _on_save_template():
	"""Save current settings as template"""
	var tile_data = _collect_tile_data()
	# Template saving logic would go here
	print("Save template: " + tile_data.name)

func _on_load_template():
	"""Load template"""
	# Template loading logic would go here
	print("Load template clicked")

func _on_clear_form():
	"""Clear all form fields"""
	name_input.text = ""
	description_input.text = ""
	tile_type_option.selected = 0
	movement_cost_input.value = 1
	passable_checkbox.button_pressed = true
	blocks_sight_checkbox.button_pressed = false
	color_picker.color = Color.WHITE
	emission_checkbox.button_pressed = false
	emission_color_picker.color = Color.BLACK
	metallic_slider.value = 0.0
	roughness_slider.value = 1.0
	texture_path_input.text = ""
	has_effects_checkbox.button_pressed = false
	current_tile_effects.clear()
	_update_effects_list()
	provides_cover_checkbox.button_pressed = false
	cover_bonus_input.value = 0
	elevation_input.value = 0
	rarity_option.selected = 0
	_update_preview()
	print("Form cleared")

func _validate_input() -> bool:
	"""Validate user input"""
	if name_input.text.is_empty():
		print("Error: Tile name is required")
		return false
	
	return true

func _collect_tile_data() -> Dictionary:
	"""Collect all tile data from the form"""
	return {
		"name": name_input.text,
		"description": description_input.text,
		"tile_type": tile_types[tile_type_option.selected],
		"movement_cost": int(movement_cost_input.value),
		"passable": passable_checkbox.button_pressed,
		"blocks_sight": blocks_sight_checkbox.button_pressed,
		"base_color": color_picker.color,
		"emission_enabled": emission_checkbox.button_pressed,
		"emission_color": emission_color_picker.color,
		"metallic": metallic_slider.value,
		"roughness": roughness_slider.value,
		"texture_path": texture_path_input.text,
		"has_effects": has_effects_checkbox.button_pressed,
		"effects": current_tile_effects.duplicate(),
		"provides_cover": provides_cover_checkbox.button_pressed,
		"cover_bonus": int(cover_bonus_input.value),
		"elevation": int(elevation_input.value),
		"rarity": rarities[rarity_option.selected]
	}

func _create_tile_files(tile_data: Dictionary) -> bool:
	"""Create all necessary files for the tile"""
	var tile_name = tile_data.name
	
	# Create tile resource file
	if not _create_tile_resource(tile_data):
		return false
	
	# Create tile scene file
	if not _create_tile_scene(tile_data):
		return false
	
	print("Tile files created successfully for: " + tile_name)
	return true

func _create_tile_resource(tile_data: Dictionary) -> bool:
	"""Create tile resource file"""
	var resource_path = "res://game/tiles/resources/" + tile_data.name.to_lower().replace(" ", "_") + ".tres"
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/tiles/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/tiles/resources")
	
	# Create TileResource
	var tile_resource = TileResource.new()
	tile_resource.tile_name = tile_data.name
	tile_resource.description = tile_data.description
	
	# Set tile type
	var type_name = tile_data.tile_type
	for i in range(Tile.TileType.size()):
		if Tile.TileType.keys()[i] == type_name:
			tile_resource.tile_type = i
			break
	
	tile_resource.base_movement_cost = tile_data.movement_cost
	tile_resource.is_passable = tile_data.passable
	tile_resource.blocks_line_of_sight = tile_data.blocks_sight
	tile_resource.base_color = tile_data.base_color
	tile_resource.emission_enabled = tile_data.emission_enabled
	tile_resource.emission_color = tile_data.emission_color
	tile_resource.metallic = tile_data.metallic
	tile_resource.roughness = tile_data.roughness
	tile_resource.texture_path = tile_data.texture_path
	tile_resource.has_default_effects = tile_data.has_effects
	tile_resource.default_effects = tile_data.effects
	tile_resource.provides_cover = tile_data.provides_cover
	tile_resource.cover_bonus = tile_data.cover_bonus
	tile_resource.elevation = tile_data.elevation
	tile_resource.rarity = tile_data.rarity
	
	# Save resource
	var result = ResourceSaver.save(tile_resource, resource_path)
	if result == OK:
		print("Tile resource created: " + resource_path)
		return true
	else:
		print("Failed to create tile resource: " + str(result))
		return false

func _create_tile_scene(tile_data: Dictionary) -> bool:
	"""Create tile scene file"""
	var scene_path = "res://game/tiles/scenes/" + tile_data.name.to_lower().replace(" ", "_") + ".tscn"
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/tiles/scenes/"):
		DirAccess.open("res://").make_dir_recursive("game/tiles/scenes")
	
	# Create tile scene
	var tile_scene = PackedScene.new()
	var tile_node = Tile.new()
	tile_node.name = tile_data.name.replace(" ", "")
	
	# Set tile properties
	var type_name = tile_data.tile_type
	for i in range(Tile.TileType.size()):
		if Tile.TileType.keys()[i] == type_name:
			tile_node.tile_type = i
			break
	
	tile_node.base_movement_cost = tile_data.movement_cost
	tile_node.is_passable_base = tile_data.passable
	
	# Add effects
	if tile_data.has_effects:
		for effect in tile_data.effects:
			if effect:
				tile_node.add_effect(effect)
	
	# Pack and save scene
	tile_scene.pack(tile_node)
	var result = ResourceSaver.save(tile_scene, scene_path)
	
	if result == OK:
		print("Tile scene created: " + scene_path)
		return true
	else:
		print("Failed to create tile scene: " + str(result))
		return false