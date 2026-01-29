extends Node

class_name MovementVisualizer

# Handles visual feedback for unit movement using overlay mesh approach
# Creates floating highlight planes above tiles instead of modifying existing tile materials
# Grid lines are now handled by MapGridVisualizer

@export var grid: Resource = preload("res://board/Grid.tres")

# Visual state
var highlighted_tiles: Array[Vector3] = []
var overlay_meshes: Dictionary = {}  # position -> MeshInstance3D
var grid_line_meshes: Array[MeshInstance3D] = []  # Store grid line meshes
var full_map_tiles: Dictionary = {}  # position -> MeshInstance3D for full map coverage

# Materials for different movement states
var movement_range_material: StandardMaterial3D
var invalid_move_material: StandardMaterial3D
var path_preview_material: StandardMaterial3D
var transparent_tile_material: StandardMaterial3D  # For non-reachable tiles

# Overlay mesh settings
var overlay_height: float = 1.0  # Height above tiles
var overlay_size: float = 2.0    # Size to match tile size (2x2 units)

# Grid line settings
var grid_line_height: float = 1.1  # Slightly above overlays
var grid_line_width: float = 0.08  # Thin white lines

func _ready() -> void:
	_setup_materials()
	_connect_events()

func _setup_materials() -> void:
	"""Create materials for movement visualization"""
	# Movement range material (solid bright blue - no transparency)
	movement_range_material = StandardMaterial3D.new()
	movement_range_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Solid bright blue
	movement_range_material.flags_transparent = false  # No transparency
	movement_range_material.flags_unshaded = true  # Unshaded for consistent brightness
	movement_range_material.emission_enabled = true
	movement_range_material.emission = Color(0.5, 0.8, 1.0, 1.0)  # Very bright blue emission
	movement_range_material.no_depth_test = true  # Always visible on top
	movement_range_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	movement_range_material.flags_do_not_receive_shadows = true
	movement_range_material.flags_disable_ambient_light = true
	
	# Transparent tile material (for non-reachable positions)
	transparent_tile_material = StandardMaterial3D.new()
	transparent_tile_material.albedo_color = Color(1.0, 1.0, 1.0, 0.1)  # Very transparent white
	transparent_tile_material.flags_transparent = true
	transparent_tile_material.flags_unshaded = true
	transparent_tile_material.emission_enabled = true
	transparent_tile_material.emission = Color(0.8, 0.8, 0.8, 0.05)  # Subtle glow
	transparent_tile_material.no_depth_test = true
	transparent_tile_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	transparent_tile_material.flags_do_not_receive_shadows = true
	transparent_tile_material.flags_disable_ambient_light = true
	
	# Invalid move material (solid red)
	invalid_move_material = StandardMaterial3D.new()
	invalid_move_material.albedo_color = Color(1.0, 0.3, 0.3, 1.0)
	invalid_move_material.flags_transparent = false
	invalid_move_material.flags_unshaded = true
	invalid_move_material.emission_enabled = true
	invalid_move_material.emission = Color(1.0, 0.5, 0.5, 1.0)
	invalid_move_material.no_depth_test = true
	invalid_move_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	invalid_move_material.flags_do_not_receive_shadows = true
	invalid_move_material.flags_disable_ambient_light = true
	
	# Path preview material (solid green)
	path_preview_material = StandardMaterial3D.new()
	path_preview_material.albedo_color = Color(0.3, 1.0, 0.3, 1.0)
	path_preview_material.flags_transparent = false
	path_preview_material.flags_unshaded = true
	path_preview_material.emission_enabled = true
	path_preview_material.emission = Color(0.5, 1.0, 0.5, 1.0)
	path_preview_material.no_depth_test = true
	path_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	path_preview_material.flags_do_not_receive_shadows = true
	path_preview_material.flags_disable_ambient_light = true
	
	print("DEBUG: Materials setup complete")

func _connect_events() -> void:
	"""Connect to GameEvents for movement visualization"""
	if GameEvents:
		GameEvents.movement_range_calculated.connect(_on_movement_range_calculated)
		GameEvents.movement_range_cleared.connect(_on_movement_range_cleared)
		GameEvents.cursor_moved.connect(_on_cursor_moved)
		print("DEBUG: MovementVisualizer connected to GameEvents successfully")
	else:
		print("DEBUG: ERROR - GameEvents not found in MovementVisualizer!")

func _on_movement_range_calculated(positions: Array[Vector3]) -> void:
	"""Show full map grid with movement range highlighted"""
	print("DEBUG: MovementVisualizer received movement_range_calculated signal with " + str(positions.size()) + " positions")
	
	# Clear any existing highlights
	_clear_all_highlights()
	
	# Store movement positions for reference
	highlighted_tiles = positions.duplicate()
	
	# Create full map grid with tiles and lines
	_create_full_map_grid_with_movement_range(positions)
	
	print("DEBUG: MovementVisualizer created full map grid with " + str(full_map_tiles.size()) + " tiles and " + str(grid_line_meshes.size()) + " grid lines")

func _on_movement_range_cleared() -> void:
	"""Clear movement range visualization"""
	_clear_all_highlights()

func _on_cursor_moved(position: Vector3) -> void:
	"""Handle cursor movement for path preview (if in movement mode)"""
	# This could be enhanced to show path preview from unit to cursor
	pass

func _create_overlay_at_position(position: Vector3, material: StandardMaterial3D) -> void:
	"""Create a floating overlay mesh at the specified grid position"""
	print("DEBUG: Creating overlay mesh at grid position: " + str(position))
	
	# Convert grid position to world position
	var world_pos = grid.calculate_map_position(position)
	world_pos.y += overlay_height  # Float above the tile
	
	print("DEBUG: Grid->World conversion: " + str(position) + " -> " + str(world_pos))
	print("DEBUG: Grid cell_size: " + str(grid.cell_size))
	print("DEBUG: Grid _half_cell_size: " + str(grid.cell_size / 2))
	
	# Create MeshInstance3D node
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MovementOverlay_" + str(position.x) + "_" + str(position.z)
	
	# Create plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(overlay_size, overlay_size)
	plane_mesh.orientation = PlaneMesh.FACE_Y  # Face upward
	
	print("DEBUG: Overlay size: " + str(plane_mesh.size))
	
	# Assign mesh and material
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	
	# Position the overlay
	mesh_instance.position = world_pos
	
	# Make sure it's visible
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to scene
	var scene_root = get_tree().current_scene
	scene_root.add_child(mesh_instance)
	
	# Store reference for cleanup
	overlay_meshes[position] = mesh_instance
	
	print("DEBUG: Overlay mesh created and added to scene at world pos " + str(world_pos))
	print("DEBUG: Mesh visible: " + str(mesh_instance.visible))
	print("DEBUG: Material assigned: " + str(mesh_instance.material_override != null))

func _clear_all_highlights() -> void:
	"""Clear all movement-related highlights by removing overlay meshes"""
	print("DEBUG: Clearing " + str(overlay_meshes.size()) + " overlay meshes, " + str(full_map_tiles.size()) + " full map tiles, and " + str(grid_line_meshes.size()) + " grid lines")
	
	# Clear overlay meshes (legacy system)
	for position in overlay_meshes.keys():
		var mesh_instance = overlay_meshes[position]
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	
	# Clear full map tiles
	for position in full_map_tiles.keys():
		var mesh_instance = full_map_tiles[position]
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	
	# Clear grid line meshes
	for line_mesh in grid_line_meshes:
		if line_mesh and is_instance_valid(line_mesh):
			line_mesh.queue_free()
	
	overlay_meshes.clear()
	full_map_tiles.clear()
	grid_line_meshes.clear()
	highlighted_tiles.clear()
	print("DEBUG: All overlay meshes, full map tiles, and grid lines cleared")

# Public interface
func is_highlighting_movement_range() -> bool:
	"""Check if currently showing movement range"""
	return highlighted_tiles.size() > 0

func get_highlighted_tiles() -> Array[Vector3]:
	"""Get currently highlighted tile positions"""
	return highlighted_tiles.duplicate()

func _create_grid_lines_for_tiles(tiles: Array[Vector3]) -> void:
	"""Create white grid lines around the highlighted tiles"""
	if tiles.is_empty():
		return
	
	print("DEBUG: Creating grid lines for " + str(tiles.size()) + " tiles")
	
	# Find the bounding box of all highlighted tiles
	var min_x = tiles[0].x
	var max_x = tiles[0].x
	var min_z = tiles[0].z
	var max_z = tiles[0].z
	
	for tile in tiles:
		min_x = min(min_x, tile.x)
		max_x = max(max_x, tile.x)
		min_z = min(min_z, tile.z)
		max_z = max(max_z, tile.z)
	
	print("DEBUG: Grid bounds - X: " + str(min_x) + " to " + str(max_x) + ", Z: " + str(min_z) + " to " + str(max_z))
	
	# Create grid line material
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)  # Bright white
	line_material.flags_transparent = true
	line_material.flags_unshaded = true
	line_material.emission_enabled = true
	line_material.emission = Color(1.0, 1.0, 1.0, 0.8)  # Bright white glow
	line_material.no_depth_test = true  # Always visible on top
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material.flags_do_not_receive_shadows = true
	
	var lines_created = 0
	
	# Create horizontal lines (running along X-axis)
	for z in range(int(min_z), int(max_z) + 2):  # +2 to include the far edge
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "GridLineH_" + str(z)
		
		var box_mesh = BoxMesh.new()
		var line_length = (max_x - min_x + 1) * grid.cell_size.x
		box_mesh.size = Vector3(line_length, grid_line_width, grid_line_width)
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		
		# Position the line
		var world_center_x = (min_x + max_x) * 0.5 * grid.cell_size.x + grid.cell_size.x * 0.5
		var world_z = z * grid.cell_size.z
		line_mesh.position = Vector3(world_center_x, grid_line_height, world_z)
		
		line_mesh.visible = true
		line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var scene_root = get_tree().current_scene
		scene_root.add_child(line_mesh)
		grid_line_meshes.append(line_mesh)
		lines_created += 1
	
	# Create vertical lines (running along Z-axis)
	for x in range(int(min_x), int(max_x) + 2):  # +2 to include the far edge
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "GridLineV_" + str(x)
		
		var box_mesh = BoxMesh.new()
		var line_length = (max_z - min_z + 1) * grid.cell_size.z
		box_mesh.size = Vector3(grid_line_width, grid_line_width, line_length)
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		
		# Position the line
		var world_x = x * grid.cell_size.x
		var world_center_z = (min_z + max_z) * 0.5 * grid.cell_size.z + grid.cell_size.z * 0.5
		line_mesh.position = Vector3(world_x, grid_line_height, world_center_z)
		
		line_mesh.visible = true
		line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var scene_root = get_tree().current_scene
		scene_root.add_child(line_mesh)
		grid_line_meshes.append(line_mesh)
		lines_created += 1
	
	print("DEBUG: Created " + str(lines_created) + " grid line segments")

func _create_full_map_grid_with_movement_range(movement_positions: Array[Vector3]) -> void:
	"""Create full map grid showing all tiles with movement range highlighted"""
	print("DEBUG: Creating full map grid (5x5) with movement range highlighting")
	
	var grid_width = int(grid.size.x)  # Should be 5
	var grid_height = int(grid.size.z)  # Should be 5
	
	print("DEBUG: Grid dimensions: " + str(grid_width) + "x" + str(grid_height))
	
	# Create a tile for every position on the map
	for x in range(grid_width):
		for z in range(grid_height):
			var grid_pos = Vector3(x, 0, z)
			
			# Check if this position is in the movement range
			var is_reachable = false
			for move_pos in movement_positions:
				if abs(move_pos.x - grid_pos.x) < 0.1 and abs(move_pos.z - grid_pos.z) < 0.1:
					is_reachable = true
					break
			
			# Create tile with appropriate material
			if is_reachable:
				_create_full_map_tile_at_position(grid_pos, movement_range_material)
			else:
				_create_full_map_tile_at_position(grid_pos, transparent_tile_material)
	
	# Create grid lines for the entire map
	_create_full_map_grid_lines()
	
	print("DEBUG: Full map grid created with " + str(full_map_tiles.size()) + " tiles")

func _create_full_map_tile_at_position(grid_position: Vector3, material: StandardMaterial3D) -> void:
	"""Create a single tile for the full map grid"""
	var world_pos = grid.calculate_map_position(grid_position)
	world_pos.y += overlay_height  # Same height as movement overlays
	
	# Create MeshInstance3D node
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "FullMapTile_" + str(grid_position.x) + "_" + str(grid_position.z)
	
	# Create plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(overlay_size, overlay_size)
	plane_mesh.orientation = PlaneMesh.FACE_Y  # Face upward
	
	# Assign mesh and material
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	mesh_instance.position = world_pos
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to scene
	var scene_root = get_tree().current_scene
	scene_root.add_child(mesh_instance)
	
	# Store reference
	full_map_tiles[grid_position] = mesh_instance

func _create_full_map_grid_lines() -> void:
	"""Create grid lines for the entire 5x5 map"""
	print("DEBUG: Creating full map grid lines")
	
	var grid_width = int(grid.size.x)  # 5
	var grid_height = int(grid.size.z)  # 5
	
	# Create grid line material
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(1.0, 1.0, 1.0, 0.9)  # Bright white
	line_material.flags_transparent = true
	line_material.flags_unshaded = true
	line_material.emission_enabled = true
	line_material.emission = Color(1.0, 1.0, 1.0, 0.8)  # Bright white glow
	line_material.no_depth_test = true  # Always visible on top
	line_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	line_material.flags_do_not_receive_shadows = true
	
	var lines_created = 0
	
	# Create horizontal lines (running along X-axis) - 6 lines for 5 tiles
	for z in range(grid_height + 1):
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "FullMapLineH_" + str(z)
		
		var box_mesh = BoxMesh.new()
		var line_length = grid_width * grid.cell_size.x
		box_mesh.size = Vector3(line_length, grid_line_width, grid_line_width)
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		
		# Position the line at the edge of tiles
		var world_center_x = (grid_width - 1) * 0.5 * grid.cell_size.x + grid.cell_size.x * 0.5
		var world_z = z * grid.cell_size.z
		line_mesh.position = Vector3(world_center_x, grid_line_height, world_z)
		
		line_mesh.visible = true
		line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var scene_root = get_tree().current_scene
		scene_root.add_child(line_mesh)
		grid_line_meshes.append(line_mesh)
		lines_created += 1
	
	# Create vertical lines (running along Z-axis) - 6 lines for 5 tiles
	for x in range(grid_width + 1):
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "FullMapLineV_" + str(x)
		
		var box_mesh = BoxMesh.new()
		var line_length = grid_height * grid.cell_size.z
		box_mesh.size = Vector3(grid_line_width, grid_line_width, line_length)
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		
		# Position the line at the edge of tiles
		var world_x = x * grid.cell_size.x
		var world_center_z = (grid_height - 1) * 0.5 * grid.cell_size.z + grid.cell_size.z * 0.5
		line_mesh.position = Vector3(world_x, grid_line_height, world_center_z)
		
		line_mesh.visible = true
		line_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		var scene_root = get_tree().current_scene
		scene_root.add_child(line_mesh)
		grid_line_meshes.append(line_mesh)
		lines_created += 1
	
	print("DEBUG: Created " + str(lines_created) + " full map grid lines")

# Test function for manual grid line testing
func _input(event: InputEvent) -> void:
	"""Handle input for testing grid lines"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_G:
				print("G pressed - creating test grid lines")
				_test_grid_lines()

func _test_grid_lines() -> void:
	"""Create a test pattern of full map grid for visibility testing"""
	print("Creating test full map grid...")
	
	# Clear existing highlights first
	_clear_all_highlights()
	
	# Create a test movement range (2x2 area in center)
	var test_movement_positions = [
		Vector3(1, 0, 1),
		Vector3(2, 0, 1),
		Vector3(1, 0, 2),
		Vector3(2, 0, 2)
	]
	
	# Create full map grid with test movement range
	_create_full_map_grid_with_movement_range(test_movement_positions)
	
	print("Test full map grid created - should see 5x5 grid with 2x2 blue area in center")