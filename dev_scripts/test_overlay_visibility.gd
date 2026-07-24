extends Node

# Simple test to verify overlay meshes are visible
# Creates a large, bright test overlay that should be impossible to miss

func _ready() -> void:
	print("=== Testing Overlay Visibility ===")
	
	# Wait for scene initialization
	await get_tree().create_timer(2.0).timeout
	
	# Create a test overlay
	_create_test_overlay()

func _create_test_overlay() -> void:
	"""Create a large, bright test overlay that should be very visible"""
	print("Creating test overlay...")
	
	var scene_root = get_tree().current_scene
	
	# Create MeshInstance3D
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "TestOverlay"
	
	# Create a large plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(3.0, 3.0)  # Large size
	plane_mesh.orientation = PlaneMesh.FACE_Y
	
	# Create very bright, obvious material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta, no transparency
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta emission
	material.no_depth_test = true  # Always visible on top
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.flags_transparent = false  # No transparency
	
	# Assign mesh and material
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	
	# Position at center of grid, high above ground
	mesh_instance.position = Vector3(4.0, 2.0, 4.0)  # Center of 5x5 grid, 2 units high
	
	# Make sure it's visible
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Add to scene
	scene_root.add_child(mesh_instance)
	
	print("Test overlay created at position: " + str(mesh_instance.position))
	print("Test overlay size: " + str(plane_mesh.size))
	print("Test overlay material: Bright magenta with emission")
	print("If you can't see a bright magenta square floating above the center of the grid,")
	print("there may be a camera angle or rendering issue.")
	
	# Wait 5 seconds then remove it
	await get_tree().create_timer(5.0).timeout
	
	print("Removing test overlay...")
	mesh_instance.queue_free()
	print("Test overlay removed")

func _test_grid_lines() -> void:
	"""Test grid lines with a simple pattern"""
	print("Testing grid lines with movement visualizer...")
	
	# Test positions in a small pattern
	var test_positions: Array[Vector3] = [
		Vector3(1, 0, 1),
		Vector3(2, 0, 1),
		Vector3(1, 0, 2),
		Vector3(2, 0, 2)
	]
	
	print("Emitting movement_range_calculated signal for grid line test...")
	GameEvents.movement_range_calculated.emit(test_positions)
	
	print("Grid line test overlays created - should show blue tiles with white grid lines")
	
	# Clear after 8 seconds
	await get_tree().create_timer(8.0).timeout
	
	print("Clearing grid line test...")
	GameEvents.movement_range_cleared.emit()

func _toggle_map_grid() -> void:
	"""Toggle the full map grid visibility"""
	var scene_root = get_tree().current_scene
	var map_grid = scene_root.get_node_or_null("MapGridVisualizer")
	
	if map_grid:
		map_grid.toggle_grid()
		print("Map grid toggled")
	else:
		print("MapGridVisualizer not found")

func _input(event: InputEvent) -> void:
	"""Handle input for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				print("T pressed - creating test overlay")
				_create_test_overlay()
			KEY_G:
				print("G pressed - testing grid lines")
				_test_grid_lines()
			KEY_M:
				print("M pressed - toggling map grid")
				_toggle_map_grid()