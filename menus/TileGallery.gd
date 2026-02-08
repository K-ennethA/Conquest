extends Control

class_name TileGallery

# Tile Gallery - Browse and view all available tiles and their effects

# UI Elements
@onready var back_button: Button
@onready var tile_list: ItemList
@onready var tile_display_container: VBoxContainer
@onready var tile_name_label: Label
@onready var tile_type_label: Label
@onready var tile_description: RichTextLabel
@onready var tile_preview_viewport: SubViewport
@onready var properties_container: VBoxContainer
@onready var effects_container: VBoxContainer
@onready var search_input: LineEdit
@onready var filter_option: OptionButton
@onready var sort_option: OptionButton

# Data
var all_tiles: Array[TileResource] = []
var filtered_tiles: Array[TileResource] = []
var current_tile: TileResource
var current_tile_preview: Node3D

# Filter and sort options
var tile_types = ["All", "NORMAL", "DIFFICULT_TERRAIN", "WATER", "WALL", "SPECIAL", "LAVA", "ICE", "SWAMP", "SACRED_GROUND", "CORRUPTED"]
var sort_options = ["Name", "Type", "Movement Cost", "Rarity", "Effect Count"]

func _ready() -> void:
	_create_ui()
	_load_all_tiles()
	_setup_connections()
	print("Tile Gallery initialized with " + str(all_tiles.size()) + " tiles")

func _create_ui() -> void:
	"""Create the complete UI for the tile gallery"""
	# Set up main layout
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Main container
	var main_container = HBoxContainer.new()
	main_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)
	
	# Left panel - Tile list and controls
	var left_panel = VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(300, 0)
	left_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	main_container.add_child(left_panel)
	
	# Title and back button
	var header_container = HBoxContainer.new()
	left_panel.add_child(header_container)
	
	var title = Label.new()
	title.text = "TILE GALLERY"
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
	search_input.placeholder_text = "Search tiles..."
	controls_container.add_child(search_input)
	
	# Filter by type
	var filter_label = Label.new()
	filter_label.text = "Filter by Type:"
	controls_container.add_child(filter_label)
	
	filter_option = OptionButton.new()
	for tile_type in tile_types:
		filter_option.add_item(tile_type)
	controls_container.add_child(filter_option)
	
	# Sort options
	var sort_label = Label.new()
	sort_label.text = "Sort by:"
	controls_container.add_child(sort_label)
	
	sort_option = OptionButton.new()
	for sort_type in sort_options:
		sort_option.add_item(sort_type)
	controls_container.add_child(sort_option)
	
	# Tile list
	var list_label = Label.new()
	list_label.text = "Tiles:"
	controls_container.add_child(list_label)
	
	tile_list = ItemList.new()
	tile_list.set_v_size_flags(Control.SIZE_EXPAND_FILL)
	tile_list.custom_minimum_size = Vector2(280, 400)
	controls_container.add_child(tile_list)
	
	# Right panel - Tile details
	var right_panel = VBoxContainer.new()
	right_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	right_panel.custom_minimum_size = Vector2(500, 0)
	main_container.add_child(right_panel)
	
	_create_tile_display(right_panel)

func _create_tile_display(parent: VBoxContainer) -> void:
	"""Create the tile display area"""
	tile_display_container = VBoxContainer.new()
	parent.add_child(tile_display_container)
	
	# Tile header
	var header_container = HBoxContainer.new()
	tile_display_container.add_child(header_container)
	
	# Tile basic info
	var info_container = VBoxContainer.new()
	info_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
	header_container.add_child(info_container)
	
	tile_name_label = Label.new()
	tile_name_label.add_theme_font_size_override("font_size", 20)
	info_container.add_child(tile_name_label)
	
	tile_type_label = Label.new()
	tile_type_label.add_theme_font_size_override("font_size", 16)
	info_container.add_child(tile_type_label)
	
	# Description
	var desc_label = Label.new()
	desc_label.text = "Description:"
	desc_label.add_theme_font_size_override("font_size", 14)
	tile_display_container.add_child(desc_label)
	
	tile_description = RichTextLabel.new()
	tile_description.custom_minimum_size = Vector2(0, 80)
	tile_description.fit_content = true
	tile_display_container.add_child(tile_description)
	
	# 3D Tile preview
	var preview_label = Label.new()
	preview_label.text = "3D Preview:"
	preview_label.add_theme_font_size_override("font_size", 14)
	tile_display_container.add_child(preview_label)
	
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(300, 200)
	viewport_container.stretch = true
	tile_display_container.add_child(viewport_container)
	
	tile_preview_viewport = SubViewport.new()
	tile_preview_viewport.size = Vector2(300, 200)
	tile_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(tile_preview_viewport)
	
	# Add camera and lighting to viewport
	_setup_preview_viewport()
	
	# Properties section
	var properties_label = Label.new()
	properties_label.text = "Properties:"
	properties_label.add_theme_font_size_override("font_size", 14)
	tile_display_container.add_child(properties_label)
	
	properties_container = VBoxContainer.new()
	tile_display_container.add_child(properties_container)
	
	# Effects section
	var effects_label = Label.new()
	effects_label.text = "Tile Effects:"
	effects_label.add_theme_font_size_override("font_size", 14)
	tile_display_container.add_child(effects_label)
	
	effects_container = VBoxContainer.new()
	tile_display_container.add_child(effects_container)
	
	# Initially hide tile display
	tile_display_container.visible = false

func _setup_preview_viewport() -> void:
	"""Set up the 3D tile preview viewport with camera and lighting"""
	# Add camera
	var camera = Camera3D.new()
	camera.position = Vector3(2, 3, 2)
	camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	tile_preview_viewport.add_child(camera)
	
	# Add lighting
	var light = DirectionalLight3D.new()
	light.position = Vector3(2, 3, 2)
	light.look_at(Vector3(0, 0, 0), Vector3.UP)
	light.light_energy = 1.0
	tile_preview_viewport.add_child(light)
	
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
	
	if tile_list:
		tile_list.item_selected.connect(_on_tile_selected)
	
	if search_input:
		search_input.text_changed.connect(_on_search_changed)
	
	if filter_option:
		filter_option.item_selected.connect(_on_filter_changed)
	
	if sort_option:
		sort_option.item_selected.connect(_on_sort_changed)

func _load_all_tiles() -> void:
	"""Load all available tile resources"""
	all_tiles.clear()
	
	var resources_dir = "res://game/tiles/resources/"
	if not DirAccess.dir_exists_absolute(resources_dir):
		print("No tile resources directory found")
		_create_default_tiles()
		return
	
	var dir = DirAccess.open(resources_dir)
	if not dir:
		print("Failed to open resources directory")
		_create_default_tiles()
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".tres"):
			var resource_path = resources_dir + file_name
			if ResourceLoader.exists(resource_path):
				var resource = load(resource_path)
				if resource is TileResource:
					all_tiles.append(resource)
					print("Loaded tile: " + resource.tile_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	# If no tiles found, create defaults
	if all_tiles.is_empty():
		_create_default_tiles()
	
	# Apply initial filter and sort
	_apply_filters()

func _create_default_tiles() -> void:
	"""Create default tile examples and save them as resources"""
	print("Creating default tiles for demonstration")
	
	# Ensure directory exists
	if not DirAccess.dir_exists_absolute("res://game/tiles/resources/"):
		DirAccess.open("res://").make_dir_recursive("game/tiles/resources")
	
	# Grass Plains Tile (No effects)
	var grass_tile = TileResource.new()
	grass_tile.tile_name = "Grass Plains"
	grass_tile.tile_type = Tile.TileType.NORMAL
	grass_tile.description = "Standard grassy terrain that's easy to traverse. No special effects."
	grass_tile.base_movement_cost = 1
	grass_tile.is_passable = true
	grass_tile.blocks_line_of_sight = false
	grass_tile.base_color = Color(0.4, 0.8, 0.3, 1.0)  # Green
	grass_tile.emission_enabled = false
	grass_tile.metallic = 0.0
	grass_tile.roughness = 1.0
	grass_tile.has_default_effects = false
	grass_tile.default_effects = []
	grass_tile.provides_cover = false
	grass_tile.cover_bonus = 0
	grass_tile.elevation = 0
	grass_tile.rarity = "Common"
	grass_tile.generation_weight = 1.0
	all_tiles.append(grass_tile)
	
	# Save grass tile
	var grass_result = ResourceSaver.save(grass_tile, "res://game/tiles/resources/grass_plains.tres")
	if grass_result == OK:
		print("Saved: Grass Plains tile")
	
	# Molten Lava Tile (Fire damage)
	var lava_tile = TileResource.new()
	lava_tile.tile_name = "Molten Lava"
	lava_tile.tile_type = Tile.TileType.LAVA
	lava_tile.description = "Dangerous molten rock that burns anything that steps on it. Deals 10 fire damage per turn to units standing on it."
	lava_tile.base_movement_cost = 2
	lava_tile.is_passable = true
	lava_tile.blocks_line_of_sight = false
	lava_tile.base_color = Color(1.0, 0.2, 0.0, 1.0)  # Red
	lava_tile.emission_enabled = true
	lava_tile.emission_color = Color(1.0, 0.3, 0.0)  # Orange glow
	lava_tile.metallic = 0.0
	lava_tile.roughness = 0.8
	lava_tile.has_default_effects = true
	lava_tile.provides_cover = false
	lava_tile.cover_bonus = 0
	lava_tile.elevation = 0
	lava_tile.rarity = "Rare"
	lava_tile.generation_weight = 0.3
	
	# Create fire damage effect
	var fire_effect = TileEffect.new()
	fire_effect.effect_name = "Lava Burn"
	fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	fire_effect.strength = 10  # 10 damage per turn (editable)
	fire_effect.duration = -1  # Permanent effect
	fire_effect.triggers_on_enter = true
	fire_effect.triggers_on_turn_start = true
	fire_effect.triggers_on_turn_end = false
	fire_effect.triggers_on_exit = false
	
	lava_tile.default_effects = [fire_effect]
	all_tiles.append(lava_tile)
	
	# Save lava tile
	var lava_result = ResourceSaver.save(lava_tile, "res://game/tiles/resources/molten_lava.tres")
	if lava_result == OK:
		print("Saved: Molten Lava tile with 10 fire damage per turn")
	
	# Deep Water Tile
	var water_tile = TileResource.new()
	water_tile.tile_name = "Deep Water"
	water_tile.tile_type = Tile.TileType.WATER
	water_tile.description = "Deep water that slows movement but can be crossed by most units."
	water_tile.base_movement_cost = 3
	water_tile.is_passable = true
	water_tile.blocks_line_of_sight = false
	water_tile.base_color = Color(0.2, 0.4, 0.8, 1.0)  # Blue
	water_tile.emission_enabled = false
	water_tile.metallic = 0.8
	water_tile.roughness = 0.1
	water_tile.has_default_effects = false
	water_tile.default_effects = []
	water_tile.provides_cover = false
	water_tile.cover_bonus = 0
	water_tile.elevation = -1
	water_tile.rarity = "Common"
	water_tile.generation_weight = 0.8
	all_tiles.append(water_tile)
	
	# Save water tile
	var water_result = ResourceSaver.save(water_tile, "res://game/tiles/resources/deep_water.tres")
	if water_result == OK:
		print("Saved: Deep Water tile")
	
	# Stone Wall Tile
	var wall_tile = TileResource.new()
	wall_tile.tile_name = "Stone Wall"
	wall_tile.tile_type = Tile.TileType.WALL
	wall_tile.description = "Solid stone wall that blocks movement and provides cover from attacks."
	wall_tile.base_movement_cost = 999  # Impassable
	wall_tile.is_passable = false
	wall_tile.blocks_line_of_sight = true
	wall_tile.base_color = Color(0.3, 0.3, 0.3, 1.0)  # Gray
	wall_tile.emission_enabled = false
	wall_tile.metallic = 0.2
	wall_tile.roughness = 0.9
	wall_tile.has_default_effects = false
	wall_tile.default_effects = []
	wall_tile.provides_cover = true
	wall_tile.cover_bonus = 3
	wall_tile.elevation = 2
	wall_tile.rarity = "Common"
	wall_tile.generation_weight = 0.5
	all_tiles.append(wall_tile)
	
	# Save wall tile
	var wall_result = ResourceSaver.save(wall_tile, "res://game/tiles/resources/stone_wall.tres")
	if wall_result == OK:
		print("Saved: Stone Wall tile")
	
	print("Created " + str(all_tiles.size()) + " default tiles")

func _apply_filters() -> void:
	"""Apply current search, filter, and sort settings"""
	# Safely duplicate the array, handling null values
	filtered_tiles.clear()
	for tile in all_tiles:
		if tile != null:
			filtered_tiles.append(tile)
	
	# Apply search filter
	var search_text = search_input.text.to_lower() if search_input else ""
	if not search_text.is_empty():
		filtered_tiles = filtered_tiles.filter(func(tile): 
			return tile.tile_name.to_lower().contains(search_text) or Tile.TileType.keys()[tile.tile_type].to_lower().contains(search_text) or tile.description.to_lower().contains(search_text)
		)
	
	# Apply type filter
	var selected_type = tile_types[filter_option.selected] if filter_option else "All"
	if selected_type != "All":
		filtered_tiles = filtered_tiles.filter(func(tile): 
			return Tile.TileType.keys()[tile.tile_type] == selected_type
		)
	
	# Apply sorting
	var sort_type = sort_options[sort_option.selected] if sort_option else "Name"
	match sort_type:
		"Name":
			filtered_tiles.sort_custom(func(a, b): return a.tile_name < b.tile_name)
		"Type":
			filtered_tiles.sort_custom(func(a, b): 
				return Tile.TileType.keys()[a.tile_type] < Tile.TileType.keys()[b.tile_type]
			)
		"Movement Cost":
			filtered_tiles.sort_custom(func(a, b): return a.get_movement_cost() < b.get_movement_cost())
		"Rarity":
			var rarity_order = {"Common": 0, "Uncommon": 1, "Rare": 2, "Epic": 3, "Legendary": 4}
			filtered_tiles.sort_custom(func(a, b): 
				var a_val = rarity_order.get(a.rarity, 0)
				var b_val = rarity_order.get(b.rarity, 0)
				return a_val < b_val
			)
		"Effect Count":
			filtered_tiles.sort_custom(func(a, b): 
				return a.default_effects.size() > b.default_effects.size()
			)
	
	_update_tile_list()

func _update_tile_list() -> void:
	"""Update the tile list display"""
	if not tile_list:
		return
	
	tile_list.clear()
	
	for tile in filtered_tiles:
		var type_name = Tile.TileType.keys()[tile.tile_type]
		var display_text = tile.tile_name + " (" + type_name + ")"
		tile_list.add_item(display_text)
	
	# Update count display
	if tile_list.get_item_count() == 0:
		tile_list.add_item("No tiles found")
		tile_list.set_item_disabled(0, true)

func _display_tile(tile: TileResource) -> void:
	"""Display detailed information for the selected tile"""
	current_tile = tile
	
	if not tile_display_container:
		return
	
	tile_display_container.visible = true
	
	# Update basic info
	if tile_name_label:
		tile_name_label.text = tile.tile_name
	
	if tile_type_label:
		var type_name = Tile.TileType.keys()[tile.tile_type]
		tile_type_label.text = type_name + " • " + tile.rarity
		
		# Color code by rarity
		match tile.rarity:
			"Common":
				tile_type_label.modulate = Color.WHITE
			"Uncommon":
				tile_type_label.modulate = Color.GREEN
			"Rare":
				tile_type_label.modulate = Color.BLUE
			"Epic":
				tile_type_label.modulate = Color.PURPLE
			"Legendary":
				tile_type_label.modulate = Color.GOLD
	
	if tile_description:
		tile_description.text = tile.description
	
	# Update 3D preview
	_update_tile_preview(tile)
	
	# Update properties
	_update_tile_properties(tile)
	
	# Update effects
	_update_tile_effects(tile)

func _update_tile_preview(tile: TileResource) -> void:
	"""Update the 3D tile preview"""
	if not tile_preview_viewport:
		return
	
	# Clear existing tile
	if current_tile_preview:
		current_tile_preview.queue_free()
		current_tile_preview = null
	
	# Create simple 3D preview without using the complex Tile class
	current_tile_preview = Node3D.new()
	current_tile_preview.name = "TilePreview"
	
	# Create mesh
	var mesh_instance = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(2, 0.2, 2)
	mesh_instance.mesh = mesh
	current_tile_preview.add_child(mesh_instance)
	
	# Apply material directly from TileResource
	var material = tile.create_material()
	mesh_instance.material_override = material
	
	tile_preview_viewport.add_child(current_tile_preview)
	
	# Position tile at origin
	current_tile_preview.position = Vector3(0, 0, 0)

func _update_tile_properties(tile: TileResource) -> void:
	"""Update the properties display"""
	if not properties_container:
		return
	
	# Clear existing properties
	for child in properties_container.get_children():
		child.queue_free()
	
	# Create properties grid
	var properties_grid = GridContainer.new()
	properties_grid.columns = 2
	properties_container.add_child(properties_grid)
	
	# Add properties
	var properties = [
		["Movement Cost", str(tile.get_movement_cost())],
		["Passable", "Yes" if tile.is_tile_passable() else "No"],
		["Blocks Sight", "Yes" if tile.blocks_line_of_sight else "No"],
		["Provides Cover", "Yes" if tile.provides_cover else "No"],
		["Cover Bonus", str(tile.cover_bonus) if tile.provides_cover else "N/A"],
		["Elevation", str(tile.elevation)],
		["Rarity", tile.rarity],
		["Has Effects", "Yes" if tile.has_default_effects else "No"]
	]
	
	for prop in properties:
		var label = Label.new()
		label.text = prop[0] + ":"
		properties_grid.add_child(label)
		
		var value = Label.new()
		value.text = prop[1]
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		properties_grid.add_child(value)

func _update_tile_effects(tile: TileResource) -> void:
	"""Update the effects display"""
	if not effects_container:
		return
	
	# Clear existing effects
	for child in effects_container.get_children():
		child.queue_free()
	
	if not tile.has_default_effects:
		var no_effects = Label.new()
		no_effects.text = "This tile has no special effects"
		no_effects.modulate = Color.GRAY
		effects_container.add_child(no_effects)
		return
	
	# Get effects for this tile type
	var effects = tile.create_tile_effects()
	
	if effects.is_empty():
		var no_effects = Label.new()
		no_effects.text = "No effects configured"
		no_effects.modulate = Color.GRAY
		effects_container.add_child(no_effects)
	else:
		for effect in effects:
			var effect_container = VBoxContainer.new()
			effects_container.add_child(effect_container)
			
			# Effect name and type
			var effect_header = HBoxContainer.new()
			effect_container.add_child(effect_header)
			
			var effect_name = Label.new()
			effect_name.text = "• " + effect.effect_name
			effect_name.add_theme_font_size_override("font_size", 14)
			effect_header.add_child(effect_name)
			
			var effect_type = Label.new()
			effect_type.text = "(" + TileEffect.EffectType.keys()[effect.effect_type] + ")"
			effect_type.modulate = Color.CYAN
			effect_type.set_h_size_flags(Control.SIZE_EXPAND_FILL)
			effect_type.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			effect_header.add_child(effect_type)
			
			# Effect description
			var effect_desc = Label.new()
			effect_desc.text = "  " + effect._get_effect_description()
			effect_desc.modulate = Color.LIGHT_GRAY
			effect_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			effect_container.add_child(effect_desc)
			
			# Effect properties
			var props_text = "  Strength: " + str(effect.strength)
			if effect.duration > 0:
				props_text += ", Duration: " + str(effect.duration) + " turns"
			elif effect.duration == -1:
				props_text += ", Duration: Permanent"
			else:
				props_text += ", Duration: Instant"
			
			var effect_props = Label.new()
			effect_props.text = props_text
			effect_props.modulate = Color.YELLOW
			effect_props.add_theme_font_size_override("font_size", 12)
			effect_container.add_child(effect_props)

# Signal handlers
func _on_back_pressed() -> void:
	"""Handle back button press"""
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _on_tile_selected(index: int) -> void:
	"""Handle tile selection from list"""
	if index >= 0 and index < filtered_tiles.size():
		var selected_tile = filtered_tiles[index]
		if selected_tile != null:
			_display_tile(selected_tile)
		else:
			print("Warning: Selected tile is null at index " + str(index))

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
				# Refresh tile list
				_load_all_tiles()
				print("Tile list refreshed")

func _exit_tree() -> void:
	"""Clean up when exiting"""
	if current_tile_preview:
		current_tile_preview.queue_free()
