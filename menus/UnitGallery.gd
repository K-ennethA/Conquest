extends Control

class_name UnitGallery

# Unit Gallery - Browse and view all available units

# UI Elements
@onready var back_button: Button
@onready var unit_list: ItemList
@onready var unit_display_container: VBoxContainer
@onready var unit_name_label: Label
@onready var unit_type_label: Label
@onready var unit_description: RichTextLabel
@onready var unit_portrait: TextureRect
@onready var unit_model_viewport: SubViewport
@onready var stats_container: VBoxContainer
@onready var moves_container: VBoxContainer
@onready var search_input: LineEdit
@onready var filter_option: OptionButton
@onready var sort_option: OptionButton

# Data
var all_units: Array[UnitStatsResource] = []
var filtered_units: Array[UnitStatsResource] = []
var current_unit: UnitStatsResource
var current_model_instance: Node3D

# Filter and sort options
var unit_types = ["All", "Warrior", "Archer", "Mage", "Healer", "Tank", "Scout", "Custom"]
var sort_options = ["Name", "Type", "Health", "Attack", "Defense", "Speed", "Total Stats"]

func _ready() -> void:
	_create_ui()
	_load_all_units()
	_setup_connections()
	print("Unit Gallery initialized with " + str(all_units.size()) + " units")

func _create_ui() -> void:
	"""Create the complete UI for the unit gallery"""
	# Set up main layout
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Main container
	var main_container = HBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)
	
	# Left panel - Unit list and controls
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	main_container.add_child(left_panel)
	
	# Title and back button
	var header_container = HBoxContainer.new()
	left_panel.add_child(header_container)
	
	var title = Label.new()
	title.text = "UNIT GALLERY"
	title.add_theme_font_size_override("font_size", 24)
	title.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(title)
	
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	header_container.add_child(back_button)
	
	# Search and filter controls
	var controls_container = VBoxContainer.new()
	left_panel.add_child(controls_container)
	
	# Search
	var search_label = Label.new()
	search_label.text = "Search:"
	controls_container.add_child(search_label)
	
	search_input = LineEdit.new()
	search_input.placeholder_text = "Search units..."
	controls_container.add_child(search_input)
	
	# Filter by type
	var filter_label = Label.new()
	filter_label.text = "Filter by Type:"
	controls_container.add_child(filter_label)
	
	filter_option = OptionButton.new()
	for unit_type in unit_types:
		filter_option.add_item(unit_type)
	controls_container.add_child(filter_option)
	
	# Sort options
	var sort_label = Label.new()
	sort_label.text = "Sort by:"
	controls_container.add_child(sort_label)
	
	sort_option = OptionButton.new()
	for sort_type in sort_options:
		sort_option.add_item(sort_type)
	controls_container.add_child(sort_option)
	
	# Unit list
	var list_label = Label.new()
	list_label.text = "Units:"
	controls_container.add_child(list_label)
	
	unit_list = ItemList.new()
	unit_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	unit_list.custom_minimum_size = Vector2(280, 400)
	controls_container.add_child(unit_list)
	
	# Right panel - Unit details
	var right_panel = VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_panel)
	
	_create_unit_display(right_panel)

func _create_unit_display(parent: VBoxContainer) -> void:
	"""Create the unit display area"""
	unit_display_container = VBoxContainer.new()
	parent.add_child(unit_display_container)
	
	# Unit header
	var header_container = HBoxContainer.new()
	unit_display_container.add_child(header_container)
	
	# Unit portrait
	unit_portrait = TextureRect.new()
	unit_portrait.custom_minimum_size = Vector2(120, 120)
	unit_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	unit_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header_container.add_child(unit_portrait)
	
	# Unit basic info
	var info_container = VBoxContainer.new()
	info_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(info_container)
	
	unit_name_label = Label.new()
	unit_name_label.add_theme_font_size_override("font_size", 20)
	info_container.add_child(unit_name_label)
	
	unit_type_label = Label.new()
	unit_type_label.add_theme_font_size_override("font_size", 16)
	info_container.add_child(unit_type_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", 14)
	unit_display_container.add_child(desc_label)
	
	unit_description = RichTextLabel.new()
	unit_description.custom_minimum_size = Vector2(0, 80)
	unit_description.fit_content = true
	unit_display_container.add_child(unit_description)
	
	# 3D Model display
	var model_label = Label.new()
	model_label.text = "3D Model:"
	model_label.add_theme_font_size_override("font_size", 14)
	unit_display_container.add_child(model_label)
	
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(300, 200)
	viewport_container.stretch = true
	unit_display_container.add_child(viewport_container)
	
	unit_model_viewport = SubViewport.new()
	unit_model_viewport.size = Vector2(300, 200)
	unit_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(unit_model_viewport)
	
	# Add camera and lighting to viewport
	_setup_model_viewport()
	
	# Stats section
	var stats_label = Label.new()
	stats_label.text = "Statistics:"
	stats_label.add_theme_font_size_override("font_size", 14)
	unit_display_container.add_child(stats_label)
	
	stats_container = VBoxContainer.new()
	unit_display_container.add_child(stats_container)
	
	# Moves section
	var moves_label = Label.new()
	moves_label.text = "Available Moves:"
	moves_label.add_theme_font_size_override("font_size", 14)
	unit_display_container.add_child(moves_label)
	
	moves_container = VBoxContainer.new()
	unit_display_container.add_child(moves_container)
	
	# Initially hide unit display
	unit_display_container.visible = false

func _setup_model_viewport() -> void:
	"""Set up the 3D model viewport with camera and lighting"""
	# Add camera
	var camera = Camera3D.new()
	camera.position = Vector3(0, 1.5, 3)
	camera.look_at(Vector3(0, 1, 0), Vector3.UP)
	unit_model_viewport.add_child(camera)
	
	# Add lighting
	var light = DirectionalLight3D.new()
	light.position = Vector3(2, 3, 2)
	light.look_at(Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 1.0
	unit_model_viewport.add_child(light)
	
	# Add environment
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.3, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5, 1.0)
	env.ambient_light_energy = 0.3
	camera.environment = env

func _setup_connections() -> void:
	"""Set up signal connections"""
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	if unit_list:
		unit_list.item_selected.connect(_on_unit_selected)
	
	if search_input:
		search_input.text_changed.connect(_on_search_changed)
	
	if filter_option:
		filter_option.item_selected.connect(_on_filter_changed)
	
	if sort_option:
		sort_option.item_selected.connect(_on_sort_changed)

func _load_all_units() -> void:
	"""Load all available unit resources"""
	all_units.clear()
	
	var resources_dir = "res://game/units/resources/unit_types/"
	if not DirAccess.dir_exists_absolute(resources_dir):
		print("No unit resources directory found")
		return
	
	var dir = DirAccess.open(resources_dir)
	if not dir:
		print("Failed to open resources directory")
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var resource_path = resources_dir + file_name
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is UnitStatsResource:
					all_units.append(resource)
					print("Loaded unit: " + resource.unit_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# Apply initial filter and sort
	_apply_filters()

func _apply_filters() -> void:
	"""Apply current search, filter, and sort settings"""
	filtered_units = all_units.duplicate()
	
	# Apply search filter
	var search_text = search_input.text.to_lower() if search_input else ""
	if not search_text.is_empty():
		filtered_units = filtered_units.filter(func(unit): 
			var unit_name_match = unit.unit_name.to_lower().contains(search_text)
			var unit_type_match = false
			var description_match = false
			
			# Handle unit type (Resource or String)
			if typeof(unit.unit_type) == TYPE_OBJECT and unit.unit_type != null:
				if "display_name" in unit.unit_type:
					unit_type_match = unit.unit_type.display_name.to_lower().contains(search_text)
				else:
					unit_type_match = false
			else:
				unit_type_match = str(unit.unit_type).to_lower().contains(search_text)
			
			# Handle description
			if not unit.description.is_empty():
				description_match = unit.description.to_lower().contains(search_text)
			elif typeof(unit.unit_type) == TYPE_OBJECT and unit.unit_type != null and "description" in unit.unit_type:
				description_match = unit.unit_type.description.to_lower().contains(search_text)
			
			return unit_name_match or unit_type_match or description_match
		)
	
	# Apply type filter
	var selected_type = unit_types[filter_option.selected] if filter_option else "All"
	if selected_type != "All":
		filtered_units = filtered_units.filter(func(unit): 
			var type_name = ""
			if typeof(unit.unit_type) == TYPE_OBJECT and unit.unit_type != null:
				if "display_name" in unit.unit_type:
					type_name = unit.unit_type.display_name
				else:
					type_name = "Unknown"
			else:
				type_name = str(unit.unit_type)
			return type_name == selected_type
		)
	
	# Apply sorting
	var sort_type = sort_options[sort_option.selected] if sort_option else "Name"
	match sort_type:
		"Name":
			filtered_units.sort_custom(func(a, b): return a.unit_name < b.unit_name)
		"Type":
			filtered_units.sort_custom(func(a, b): 
				var a_type = ""
				var b_type = ""
				if typeof(a.unit_type) == TYPE_OBJECT and a.unit_type != null and "display_name" in a.unit_type:
					a_type = a.unit_type.display_name
				else:
					a_type = str(a.unit_type)
				if typeof(b.unit_type) == TYPE_OBJECT and b.unit_type != null and "display_name" in b.unit_type:
					b_type = b.unit_type.display_name
				else:
					b_type = str(b.unit_type)
				return a_type < b_type
			)
		"Health":
			filtered_units.sort_custom(func(a, b): 
				var a_health = a.max_health if "max_health" in a else a.base_health if "base_health" in a else 100
				var b_health = b.max_health if "max_health" in b else b.base_health if "base_health" in b else 100
				return a_health > b_health
			)
		"Attack":
			filtered_units.sort_custom(func(a, b): return a.base_attack > b.base_attack)
		"Defense":
			filtered_units.sort_custom(func(a, b): return a.base_defense > b.base_defense)
		"Speed":
			filtered_units.sort_custom(func(a, b): return a.base_speed > b.base_speed)
		"Total Stats":
			filtered_units.sort_custom(func(a, b): 
				var a_total = _calculate_stat_total(a)
				var b_total = _calculate_stat_total(b)
				return a_total > b_total
			)
	
	_update_unit_list()

func _calculate_stat_total(unit: UnitStatsResource) -> int:
	"""Calculate total stats for a unit, handling both formats"""
	if unit.has_method("get_stat_total"):
		return unit.get_stat_total()
	
	# Manual calculation for old format
	var health = unit.max_health if "max_health" in unit else unit.base_health if "base_health" in unit else 100
	var attack = unit.base_attack if "base_attack" in unit else 20
	var defense = unit.base_defense if "base_defense" in unit else 15
	var magic = unit.base_magic if "base_magic" in unit else 0
	var speed = unit.base_speed if "base_speed" in unit else 12
	
	return health + attack + defense + magic + speed

func _update_unit_list() -> void:
	"""Update the unit list display"""
	if not unit_list:
		return
	
	unit_list.clear()
	
	for unit in filtered_units:
		var type_name = ""
		if unit.unit_type is String:
			type_name = unit.unit_type
		else:
			# Handle Resource type or other types
			var unit_type_obj = unit.unit_type
			if unit_type_obj != null and is_instance_valid(unit_type_obj) and unit_type_obj.has_method("get_display_name"):
				type_name = unit_type_obj.get_display_name()
			else:
				type_name = str(unit.unit_type)
		
		var display_text = unit.unit_name + " (" + type_name + ")"
		unit_list.add_item(display_text)
	
	# Update count display
	if unit_list.get_item_count() == 0:
		unit_list.add_item("No units found")
		unit_list.set_item_disabled(0, true)

func _display_unit(unit: UnitStatsResource) -> void:
	"""Display detailed information for the selected unit"""
	current_unit = unit
	
	if not unit_display_container:
		return
	
	unit_display_container.visible = true
	
	# Update basic info
	if unit_name_label:
		unit_name_label.text = unit.unit_name
	
	if unit_type_label:
		# Handle both old and new unit type formats
		var type_text = ""
		var rarity_text = ""
		
		if unit.unit_type is String:
			# New format - unit_type is a String
			type_text = unit.unit_type
		else:
			# Handle Resource type or other types
			var unit_type_obj = unit.unit_type
			if unit_type_obj != null and is_instance_valid(unit_type_obj) and unit_type_obj.has_method("get_display_name"):
				# Old format - unit_type is a Resource with display_name
				type_text = unit_type_obj.get_display_name()
			else:
				type_text = str(unit.unit_type)
		
		# Handle rarity (may not exist in old format)
		if "rarity" in unit:
			rarity_text = unit.rarity
		else:
			rarity_text = "Common"
		
		unit_type_label.text = type_text + " • " + rarity_text
		
		# Color code by rarity
		match rarity_text:
			"Common":
				unit_type_label.modulate = Color.WHITE
			"Uncommon":
				unit_type_label.modulate = Color.GREEN
			"Rare":
				unit_type_label.modulate = Color.BLUE
			"Epic":
				unit_type_label.modulate = Color.PURPLE
			"Legendary":
				unit_type_label.modulate = Color.GOLD
	
	if unit_description:
		# Handle description (may be in unit_type for old format)
		var desc = ""
		if not unit.description.is_empty():
			desc = unit.description
		else:
			# Check if unit_type has description (for old format)
			var unit_type_obj = unit.unit_type
			if unit_type_obj != null and is_instance_valid(unit_type_obj) and unit_type_obj.has_method("get_description"):
				desc = unit_type_obj.get_description()
			else:
				desc = "No description available"
		unit_description.text = desc
	
	# Update portrait
	_update_unit_portrait(unit)
	
	# Update 3D model
	_update_unit_model(unit)
	
	# Update stats
	_update_unit_stats(unit)
	
	# Update moves
	_update_unit_moves(unit)

func _update_unit_portrait(unit: UnitStatsResource) -> void:
	"""Update the unit portrait image"""
	if not unit_portrait:
		return
	
	if not unit.profile_image_path.is_empty() and ResourceLoader.exists(unit.profile_image_path):
		var texture = load(unit.profile_image_path) as Texture2D
		if texture:
			unit_portrait.texture = texture
		else:
			unit_portrait.texture = null
	else:
		unit_portrait.texture = null

func _update_unit_model(unit: UnitStatsResource) -> void:
	"""Update the 3D model display"""
	if not unit_model_viewport:
		return
	
	# Clear existing model
	if current_model_instance:
		current_model_instance.queue_free()
		current_model_instance = null
	
	# Load new model if available
	if not unit.model_scene_path.is_empty() and ResourceLoader.exists(unit.model_scene_path):
		var model_scene = load(unit.model_scene_path) as PackedScene
		if model_scene:
			current_model_instance = model_scene.instantiate()
			unit_model_viewport.add_child(current_model_instance)
			
			# Position model appropriately
			current_model_instance.position = Vector3(0, 0, 0)
			
			# Add rotation animation
			var tween = create_tween()
			tween.set_loops()
			tween.tween_method(_rotate_model, 0.0, 360.0, 8.0)

func _rotate_model(angle: float) -> void:
	"""Rotate the 3D model for display"""
	if current_model_instance:
		current_model_instance.rotation_degrees.y = angle

func _update_unit_stats(unit: UnitStatsResource) -> void:
	"""Update the stats display"""
	if not stats_container:
		return
	
	# Clear existing stats
	for child in stats_container.get_children():
		child.queue_free()
	
	# Create stats grid
	var stats_grid = GridContainer.new()
	stats_grid.columns = 2
	stats_container.add_child(stats_grid)
	
	# Handle both old and new stat formats
	var health = 0
	var attack = 0
	var defense = 0
	var magic = 0
	var speed = 0
	var movement = 0
	var range_val = 0
	
	# Check for new format first
	if "max_health" in unit:
		health = unit.max_health
		attack = unit.base_attack
		defense = unit.base_defense
		magic = unit.base_magic if "base_magic" in unit else 0
		speed = unit.base_speed
		movement = unit.movement_range if "movement_range" in unit else unit.base_movement if "base_movement" in unit else 3
		range_val = unit.attack_range if "attack_range" in unit else 1
	else:
		# Old format
		health = unit.base_health if "base_health" in unit else 100
		attack = unit.base_attack if "base_attack" in unit else 20
		defense = unit.base_defense if "base_defense" in unit else 15
		magic = 0  # Old format doesn't have magic
		speed = unit.base_speed if "base_speed" in unit else 12
		movement = unit.base_movement if "base_movement" in unit else 3
		range_val = 1  # Default range for old format
	
	# Add stats
	var stats = [
		["Health", str(health)],
		["Attack", str(attack)],
		["Defense", str(defense)],
		["Magic", str(magic)],
		["Speed", str(speed)],
		["Movement", str(movement)],
		["Range", str(range_val)],
		["Total", str(health + attack + defense + magic + speed)]
	]
	
	for stat in stats:
		var label = Label.new()
		label.text = stat[0] + ":"
		stats_grid.add_child(label)
		
		var value = Label.new()
		value.text = stat[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats_grid.add_child(value)

func _update_unit_moves(unit: UnitStatsResource) -> void:
	"""Update the moves display"""
	if not moves_container:
		return
	
	# Clear existing moves
	for child in moves_container.get_children():
		child.queue_free()
	
	# For now, show placeholder since moves aren't stored in UnitStatsResource
	# In a full implementation, you'd load the unit's scene and check its MoveManager
	var moves_info = _get_unit_moves(unit)
	
	if moves_info.is_empty():
		var no_moves = Label.new()
		no_moves.text = "No moves configured"
		no_moves.modulate = Color.GRAY
		moves_container.add_child(no_moves)
	else:
		for move_info in moves_info:
			var move_label = Label.new()
			move_label.text = "• " + move_info.name + " (" + move_info.type + ")"
			moves_container.add_child(move_label)

func _get_unit_moves(unit: UnitStatsResource) -> Array[Dictionary]:
	"""Get moves for a unit (placeholder implementation)"""
	# This would ideally load the unit scene and check its MoveManager
	# For now, return default moves based on unit type
	var moves: Array[Dictionary] = []
	
	match unit.unit_type:
		"Warrior":
			moves = [
				{"name": "Basic Attack", "type": "DAMAGE"},
				{"name": "Power Strike", "type": "DAMAGE"},
				{"name": "Shield Wall", "type": "SHIELD"}
			]
		"Archer":
			moves = [
				{"name": "Basic Attack", "type": "DAMAGE"},
				{"name": "Poison Dart", "type": "DEBUFF"},
				{"name": "Power Strike", "type": "DAMAGE"}
			]
		"Mage":
			moves = [
				{"name": "Basic Attack", "type": "DAMAGE"},
				{"name": "Fireball", "type": "DAMAGE"},
				{"name": "Heal", "type": "HEAL"},
				{"name": "Earthquake", "type": "TILE_EFFECT"}
			]
		_:
			moves = [
				{"name": "Basic Attack", "type": "DAMAGE"}
			]
	
	return moves

# Signal handlers
func _on_back_pressed() -> void:
	"""Handle back button press"""
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _on_unit_selected(index: int) -> void:
	"""Handle unit selection from list"""
	if index >= 0 and index < filtered_units.size():
		var selected_unit = filtered_units[index]
		_display_unit(selected_unit)

func _on_search_changed(new_text: String) -> void:
	"""Handle search text change"""
	_apply_filters()

func _on_filter_changed(index: int) -> void:
	"""Handle filter option change"""
	_apply_filters()

func _on_sort_changed(index: int) -> void:
	"""Handle sort option change"""
	_apply_filters()

# Input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_F5:
				# Refresh unit list
				_load_all_units()
				print("Unit list refreshed")

func _exit_tree() -> void:
	"""Clean up when exiting"""
	if current_model_instance:
		current_model_instance.queue_free()
