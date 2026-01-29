extends Node

class_name MapGridVisualizer

# Displays transparent tiles with grid lines over the entire map
# Shows full map grid normally, and highlights movement range when unit selected

@export var grid: Resource = preload("res://board/Grid.tres")

# Grid visual settings
var grid_tile_height: float = 0.3   # Height above ground
var grid_tile_size: float = 2.0     # Match actual tile size
var grid_line_width: float = 0.15   # Much thicker grid lines for visibility

# Grid state
var map_grid_tiles: Array[MeshInstance3D] = []
var grid_visible: bool = true
var user_toggled_off: bool = false
var unit_selected: bool = false
var movement_positions: Array[Vector3] = []

# Materials
var normal_tile_material: StandardMaterial3D
var movement_tile_material: StandardMaterial3D

func _ready() -> void:
	print("=== MapGridVisualizer: _ready() called ===")
	print("MapGridVisualizer: Initializing full map tile grid")
	print("MapGridVisualizer: Grid resource: " + str(grid))
	print("MapGridVisualizer: GameEvents available: " + str(GameEvents != null))
	
	_setup_materials()
	print("MapGridVisualizer: Materials setup complete")
	
	_connect_to_game_events()
	print("MapGridVisualizer: GameEvents connection attempted")
	
	# Wait a frame to ensure scene is fully loaded
	await get_tree().process_frame
	print("MapGridVisualizer: About to create grid tiles")
	_create_full_map_tile_grid()
	print("MapGridVisualizer: Grid tiles created, showing grid")
	show_grid()
	print("MapGridVisualizer: Initialization complete")

func _setup_materials() -> void:
	"""Create materials for grid tiles"""
	# Normal grid tile material (subtle transparent)
	normal_tile_material = StandardMaterial3D.new()
	normal_tile_material.albedo_color = Color(1.0, 1.0, 1.0, 0.1)  # Very transparent white
	normal_tile_material.flags_transparent = true
	normal_tile_material.flags_unshaded = true
	normal_tile_material.emission_enabled = true
	normal_tile_material.emission = Color(0.8, 0.8, 0.8, 0.05)  # Subtle glow
	normal_tile_material.no_depth_test = false
	normal_tile_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	normal_tile_material.flags_do_not_receive_shadows = true
	
	# Movement range tile material (blue transparent)
	movement_tile_material = StandardMaterial3D.new()
	movement_tile_material.albedo_color = Color(0.3, 0.7, 1.0, 0.4)  # Blue transparent
	movement_tile_material.flags_transparent = true
	movement_tile_material.flags_unshaded = true
	movement_tile_material.emission_enabled = true
	movement_tile_material.emission = Color(0.4, 0.8, 1.0, 0.3)  # Blue glow
	movement_tile_material.no_depth_test = false
	movement_tile_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	movement_tile_material.flags_do_not_receive_shadows = true
	
	print("MapGridVisualizer: Materials created")

func _connect_to_game_events() -> void:
	"""Connect to GameEvents for unit selection and movement range"""
	print("MapGridVisualizer: Attempting to connect to GameEvents...")
	if GameEvents:
		print("MapGridVisualizer: GameEvents found, connecting signals...")
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		GameEvents.movement_range_calculated.connect(_on_movement_range_calculated)
		GameEvents.movement_range_cleared.connect(_on_movement_range_cleared)
		print("MapGridVisualizer: Connected to GameEvents successfully")
	else:
		print("MapGridVisualizer: ERROR - GameEvents not found!")
		print("MapGridVisualizer: Will continue without GameEvents connections")

func _create_full_map_tile_grid() -> void:
	"""Create transparent tiles with grid lines for the entire map"""
	print("MapGridVisualizer: Creating full map tile grid")
	
	var grid_width = int(grid.size.x)
	var grid_height = int(grid.size.z)
	
	print("Creating " + str(grid_width) + "x" + str(grid_height) + " tile grid")
	print("Grid cell_size: " + str(grid.cell_size))
	print("Grid tile_size: " + str(grid_tile_size))
	
	var tiles_created = 0
	var total_lines_expected = 0
	
	# Create a tile for each grid position
	for x in range(grid_width):
		for z in range(grid_height):
			var grid_pos = Vector3(x, 0, z)
			print("DEBUG: Creating tile " + str(tiles_created + 1) + "/" + str(grid_width * grid_height) + " at " + str(grid_pos))
			_create_grid_tile(grid_pos)
			tiles_created += 1
			total_lines_expected += 4  # 4 border lines per tile
	
	print("MapGridVisualizer: Created " + str(tiles_created) + " tiles")
	print("MapGridVisualizer: Expected " + str(total_lines_expected) + " border lines")
	print("MapGridVisualizer: Total elements in map_grid_tiles: " + str(map_grid_tiles.size()))
	
	# Count actual tiles vs lines
	var actual_tiles = 0
	var actual_lines = 0
	for element in map_grid_tiles:
		if element and is_instance_valid(element):
			if element.name.begins_with("GridTile_"):
				actual_tiles += 1
			elif element.name.begins_with("GridLine_"):
				actual_lines += 1
	
	print("MapGridVisualizer: Actual tiles: " + str(actual_tiles))
	print("MapGridVisualizer: Actual lines: " + str(actual_lines))
	
	if actual_lines == 0:
		print("❌ CRITICAL: No border lines were created!")
	elif actual_lines < total_lines_expected:
		print("⚠️  WARNING: Missing border lines: " + str(actual_lines) + "/" + str(total_lines_expected))
	else:
		print("✓ All border lines created successfully")

func _create_grid_tile(grid_pos: Vector3) -> void:
	"""Create a single transparent grid tile with border lines"""
	var world_pos = grid.calculate_map_position(grid_pos)
	world_pos.y = grid_tile_height
	
	print("DEBUG: Creating grid tile at grid pos " + str(grid_pos) + " -> world pos " + str(world_pos))
	
	# Create the main tile mesh
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "GridTile_" + str(grid_pos.x) + "_" + str(grid_pos.z)
	
	# Create plane mesh for the tile
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(grid_tile_size, grid_tile_size)
	plane_mesh.orientation = PlaneMesh.FACE_Y
	
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = normal_tile_material
	mesh_instance.position = world_pos
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to scene and store reference
	var scene_root = get_tree().current_scene
	scene_root.add_child(mesh_instance)
	map_grid_tiles.append(mesh_instance)
	
	print("DEBUG: Created tile, now creating border lines...")
	
	# Create border lines for this tile
	_create_tile_border_lines(world_pos, grid_pos)
	
	print("DEBUG: Grid tile and border lines created for " + str(grid_pos))

func _create_tile_border_lines(world_pos: Vector3, grid_pos: Vector3) -> void:
	"""Create border lines around a tile"""
	var line_height = world_pos.y + 0.1  # Much higher above tile for better visibility
	var half_size = grid_tile_size / 2.0
	
	print("DEBUG: Creating border lines for tile at " + str(grid_pos) + " (world: " + str(world_pos) + ")")
	
	# Create line material (bright, solid white lines)
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)  # Solid white lines
	line_material.flags_transparent = false  # No transparency for maximum visibility
	line_material.flags_unshaded = true
	line_material.emission_enabled = true
	line_material.emission = Color(1.0, 1.0, 1.0, 1.0)  # Bright white glow
	line_material.no_depth_test = true  # Always visible on top
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material.flags_do_not_receive_shadows = true
	line_material.flags_disable_ambient_light = true
	
	# Create 4 border lines (top, bottom, left, right) - make them MUCH thicker for testing
	var thick_line_width = 0.3  # Very thick for visibility testing
	var lines = [
		# Top line (along X-axis, at front Z edge)
		{pos = Vector3(world_pos.x, line_height, world_pos.z - half_size), size = Vector3(grid_tile_size + thick_line_width, thick_line_width, thick_line_width)},
		# Bottom line (along X-axis, at back Z edge)
		{pos = Vector3(world_pos.x, line_height, world_pos.z + half_size), size = Vector3(grid_tile_size + thick_line_width, thick_line_width, thick_line_width)},
		# Left line (along Z-axis, at left X edge)
		{pos = Vector3(world_pos.x - half_size, line_height, world_pos.z), size = Vector3(thick_line_width, thick_line_width, grid_tile_size + thick_line_width)},
		# Right line (along Z-axis, at right X edge)
		{pos = Vector3(world_pos.x + half_size, line_height, world_pos.z), size = Vector3(thick_line_width, thick_line_width, grid_tile_size + thick_line_width)}
	]
	
	var lines_created = 0
	for i in range(lines.size()):
		var line_data = lines[i]
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "GridLine_" + str(grid_pos.x) + "_" + str(grid_pos.z) + "_" + str(i)
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = line_data.size
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		line_mesh.position = line_data.pos
		line_mesh.visible = true
		line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var scene_root = get_tree().current_scene
		if scene_root:
			scene_root.add_child(line_mesh)
			map_grid_tiles.append(line_mesh)  # Store lines with tiles for easy management
			lines_created += 1
			print("DEBUG: ✓ Created border line " + str(i) + " at " + str(line_data.pos) + " with size " + str(line_data.size))
		else:
			print("DEBUG: ❌ Failed to get scene root for line " + str(i))
	
	print("DEBUG: Created " + str(lines_created) + "/4 border lines for tile " + str(grid_pos))

# Event handlers
func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - ensure grid is visible"""
	print("MapGridVisualizer: Unit selected - ensuring grid is visible")
	unit_selected = true
	_update_grid_visibility()

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection - return to user preference"""
	print("MapGridVisualizer: Unit deselected - clearing movement range")
	unit_selected = false
	movement_positions.clear()
	_update_tile_materials()
	_update_grid_visibility()

func _on_movement_range_calculated(positions: Array[Vector3]) -> void:
	"""Handle movement range calculation - highlight blue tiles"""
	print("MapGridVisualizer: Movement range calculated - " + str(positions.size()) + " positions")
	movement_positions = positions
	_update_tile_materials()

func _on_movement_range_cleared() -> void:
	"""Handle movement range cleared"""
	print("MapGridVisualizer: Movement range cleared")
	movement_positions.clear()
	_update_tile_materials()

func _update_tile_materials() -> void:
	"""Update tile materials based on movement range"""
	var grid_width = int(grid.size.x)
	var grid_height = int(grid.size.z)
	
	print("DEBUG: Updating tile materials for " + str(grid_width) + "x" + str(grid_height) + " grid")
	print("DEBUG: Movement positions: " + str(movement_positions.size()))
	
	# Update each tile's material
	for x in range(grid_width):
		for z in range(grid_height):
			var grid_pos = Vector3(x, 0, z)
			# Calculate correct tile index - tiles are stored in row-major order
			var tile_index = x * grid_height + z
			
			# Find the actual tile (not line) for this position
			var found_tile = null
			var tile_name = "GridTile_" + str(x) + "_" + str(z)
			
			for element in map_grid_tiles:
				if element and is_instance_valid(element) and element.name == tile_name:
					found_tile = element
					break
			
			if found_tile:
				# Check if this position is in movement range
				var is_movement_tile = false
				for move_pos in movement_positions:
					if abs(move_pos.x - grid_pos.x) < 0.1 and abs(move_pos.z - grid_pos.z) < 0.1:
						is_movement_tile = true
						break
				
				# Apply appropriate material
				if is_movement_tile:
					found_tile.material_override = movement_tile_material
					print("DEBUG: Set tile " + str(grid_pos) + " to BLUE (movement)")
				else:
					found_tile.material_override = normal_tile_material
					print("DEBUG: Set tile " + str(grid_pos) + " to WHITE (normal)")
			else:
				print("DEBUG: Could not find tile for position " + str(grid_pos))

# Grid visibility controls
func show_grid() -> void:
	"""Show the map grid"""
	grid_visible = true
	for tile in map_grid_tiles:
		if tile and is_instance_valid(tile):
			tile.visible = true
	print("MapGridVisualizer: Grid shown (" + str(map_grid_tiles.size()) + " elements)")

func hide_grid() -> void:
	"""Hide the map grid"""
	grid_visible = false
	for tile in map_grid_tiles:
		if tile and is_instance_valid(tile):
			tile.visible = false
	print("MapGridVisualizer: Grid hidden")

func toggle_grid() -> void:
	"""Toggle grid visibility (user manual toggle)"""
	user_toggled_off = grid_visible  # Remember if user is turning it off
	
	if grid_visible:
		hide_grid()
	else:
		show_grid()
		user_toggled_off = false  # User turned it back on

func _update_grid_visibility() -> void:
	"""Update grid visibility based on user preference and unit selection"""
	var should_show = not user_toggled_off or unit_selected
	
	if should_show and not grid_visible:
		show_grid()
	elif not should_show and grid_visible:
		hide_grid()

func is_grid_visible() -> bool:
	"""Check if grid is currently visible"""
	return grid_visible

# Input handling
func _input(event: InputEvent) -> void:
	"""Handle global input for grid toggle"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				print("F1 pressed - toggling map grid")
				toggle_grid()
				print("Grid state - Visible: " + str(grid_visible) + ", User toggled off: " + str(user_toggled_off) + ", Unit selected: " + str(unit_selected))
			KEY_EQUAL, KEY_PLUS:  # + key
				print("+ pressed - showing map grid")
				user_toggled_off = false
				_update_grid_visibility()
			KEY_MINUS:
				print("- pressed - hiding map grid (unless unit selected)")
				user_toggled_off = true
				_update_grid_visibility()
			KEY_L:
				print("L pressed - testing line visibility")
				_test_line_visibility()

# Cleanup
func cleanup() -> void:
	"""Clean up all grid tiles and lines"""
	for tile in map_grid_tiles:
		if tile and is_instance_valid(tile):
			tile.queue_free()
	
	map_grid_tiles.clear()
	print("MapGridVisualizer: Grid cleaned up")

func _test_line_visibility() -> void:
	"""Create a test line to verify line visibility"""
	print("Creating test line for visibility check...")
	
	var test_line = MeshInstance3D.new()
	test_line.name = "TestLine"
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(4.0, 0.3, 0.3)  # Large, thick line
	
	var test_material = StandardMaterial3D.new()
	test_material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta, no transparency
	test_material.flags_unshaded = true
	test_material.emission_enabled = true
	test_material.emission = Color(1.0, 0.0, 1.0, 1.0)
	test_material.no_depth_test = true
	test_material.flags_transparent = false
	
	test_line.mesh = box_mesh
	test_line.material_override = test_material
	test_line.position = Vector3(4.0, 2.0, 4.0)  # High above center
	test_line.visible = true
	test_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var scene_root = get_tree().current_scene
	scene_root.add_child(test_line)
	
	print("Test line created at " + str(test_line.position))
	print("Should be a bright magenta line floating above the center")
	
	# Also create a test border line similar to grid lines
	var test_border = MeshInstance3D.new()
	test_border.name = "TestBorderLine"
	
	var border_mesh = BoxMesh.new()
	border_mesh.size = Vector3(2.0, 0.15, 0.15)  # Same as grid line thickness
	
	var border_material = StandardMaterial3D.new()
	border_material.albedo_color = Color(0.0, 1.0, 0.0, 1.0)  # Bright green
	border_material.flags_unshaded = true
	border_material.emission_enabled = true
	border_material.emission = Color(0.0, 1.0, 0.0, 1.0)
	border_material.no_depth_test = true
	border_material.flags_transparent = false
	
	test_border.mesh = border_mesh
	test_border.material_override = border_material
	test_border.position = Vector3(2.0, 1.5, 2.0)  # Lower, at grid level
	test_border.visible = true
	test_border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	scene_root.add_child(test_border)
	
	print("Test border line created at " + str(test_border.position))
	print("Should be a bright green line at grid level")
	
	# Remove after 5 seconds
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(test_line):
		test_line.queue_free()
		print("Test line removed")
	if is_instance_valid(test_border):
		test_border.queue_free()
		print("Test border line removed")