extends Node

# Debug script to diagnose overlay visibility issues

func _ready() -> void:
	print("=== Overlay System Debug ===")
	
	# Wait for scene initialization
	await get_tree().create_timer(1.0).timeout
	
	# Run debug tests
	_debug_scene_structure()
	_debug_camera_setup()
	_debug_lighting()
	_debug_materials()

func _debug_scene_structure() -> void:
	"""Debug scene structure and node hierarchy"""
	print("\n--- Scene Structure Debug ---")
	
	var scene_root = get_tree().current_scene
	print("Scene root: " + scene_root.name)
	print("Scene root type: " + scene_root.get_class())
	
	# Check for MovementVisualizer
	var movement_visualizer = scene_root.get_node_or_null("MovementVisualizer")
	if movement_visualizer:
		print("✓ MovementVisualizer found")
	else:
		print("✗ MovementVisualizer not found")
	
	# Count total children
	var total_children = _count_children_recursive(scene_root)
	print("Total nodes in scene: " + str(total_children))

func _count_children_recursive(node: Node) -> int:
	"""Count all children recursively"""
	var count = 1  # Count this node
	for child in node.get_children():
		count += _count_children_recursive(child)
	return count

func _debug_camera_setup() -> void:
	"""Debug camera setup and position"""
	print("\n--- Camera Debug ---")
	
	var camera = get_viewport().get_camera_3d()
	if camera:
		print("✓ Camera found: " + camera.name)
		print("Camera position: " + str(camera.global_position))
		print("Camera rotation: " + str(camera.global_rotation_degrees))
		print("Camera projection: " + ("Orthogonal" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "Perspective"))
		
		if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
			print("Camera size: " + str(camera.size))
		else:
			print("Camera FOV: " + str(camera.fov))
	else:
		print("✗ No camera found")

func _debug_lighting() -> void:
	"""Debug lighting setup"""
	print("\n--- Lighting Debug ---")
	
	var scene_root = get_tree().current_scene
	
	# Check for WorldEnvironment
	var world_env = scene_root.get_node_or_null("WorldEnvironment")
	if world_env:
		print("✓ WorldEnvironment found")
		var env = world_env.environment
		if env:
			print("Environment background mode: " + str(env.background_mode))
			print("Environment ambient light: " + str(env.ambient_light_source))
		else:
			print("✗ No Environment resource")
	else:
		print("✗ No WorldEnvironment found")
	
	# Check for DirectionalLight3D
	var lights = _find_nodes_of_type(scene_root, "DirectionalLight3D")
	print("DirectionalLight3D nodes found: " + str(lights.size()))
	
	for light in lights:
		print("  Light: " + light.name + " enabled: " + str(light.visible))

func _find_nodes_of_type(node: Node, type_name: String) -> Array:
	"""Find all nodes of a specific type"""
	var found_nodes = []
	
	if node.get_class() == type_name:
		found_nodes.append(node)
	
	for child in node.get_children():
		found_nodes.append_array(_find_nodes_of_type(child, type_name))
	
	return found_nodes

func _debug_materials() -> void:
	"""Debug material creation and properties"""
	print("\n--- Material Debug ---")
	
	# Create test material similar to MovementVisualizer
	var test_material = StandardMaterial3D.new()
	test_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)
	test_material.flags_transparent = false
	test_material.flags_unshaded = true
	test_material.emission_enabled = true
	test_material.emission = Color(0.5, 0.8, 1.0, 1.0)
	test_material.no_depth_test = true
	test_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	print("Test material created:")
	print("  Albedo: " + str(test_material.albedo_color))
	print("  Transparent: " + str(test_material.flags_transparent))
	print("  Unshaded: " + str(test_material.flags_unshaded))
	print("  Emission enabled: " + str(test_material.emission_enabled))
	print("  Emission: " + str(test_material.emission))
	print("  No depth test: " + str(test_material.no_depth_test))
	print("  Cull mode: " + str(test_material.cull_mode))

func _input(event: InputEvent) -> void:
	"""Handle input for manual testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F10:
				print("F10 pressed - creating manual test overlay")
				_create_manual_test_overlay()
			KEY_F11:
				print("F11 pressed - listing all scene nodes")
				_list_all_scene_nodes()
			KEY_F12:
				print("F12 pressed - checking for existing overlays")
				_check_existing_overlays()
			KEY_A:
				print("A pressed - testing tile alignment")
				_test_tile_alignment()

func _create_manual_test_overlay() -> void:
	"""Create a manual test overlay for debugging"""
	print("Creating manual test overlay...")
	
	var scene_root = get_tree().current_scene
	
	# Create MeshInstance3D
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "ManualTestOverlay"
	
	# Create plane mesh
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(2.0, 2.0)
	plane_mesh.orientation = PlaneMesh.FACE_Y
	
	# Create very obvious material
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 0.0, 1.0)  # Bright yellow
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = Color(1.0, 1.0, 0.0, 1.0)
	material.no_depth_test = true
	material.flags_transparent = false
	
	# Assign mesh and material
	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	
	# Position at a very obvious location
	mesh_instance.position = Vector3(4.0, 3.0, 4.0)  # High above center
	mesh_instance.visible = true
	
	# Add to scene
	scene_root.add_child(mesh_instance)
	
	print("Manual test overlay created at: " + str(mesh_instance.position))
	print("Should be a bright yellow square floating high above the center")
	
	# Remove after 10 seconds
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(mesh_instance):
		mesh_instance.queue_free()
		print("Manual test overlay removed")

func _list_all_scene_nodes() -> void:
	"""List all nodes in the scene"""
	print("\n--- All Scene Nodes ---")
	var scene_root = get_tree().current_scene
	_print_node_tree(scene_root, 0)

func _print_node_tree(node: Node, depth: int) -> void:
	"""Print node tree recursively"""
	var indent = ""
	for i in range(depth):
		indent += "  "
	
	var info = indent + node.name + " (" + node.get_class() + ")"
	
	# Add position info for 3D nodes
	if node is Node3D:
		info += " pos:" + str((node as Node3D).position)
	
	# Add visibility info for MeshInstance3D
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		info += " visible:" + str(mesh_inst.visible)
		if mesh_inst.material_override:
			info += " material:yes"
		else:
			info += " material:no"
	
	print(info)
	
	# Limit depth to avoid spam
	if depth < 4:
		for child in node.get_children():
			_print_node_tree(child, depth + 1)

func _check_existing_overlays() -> void:
	"""Check for existing overlay meshes in the scene"""
	print("\n--- Checking for Existing Overlays ---")
	
	var scene_root = get_tree().current_scene
	var overlay_count = 0
	
	_find_overlays_recursive(scene_root, overlay_count)
	
	print("Total overlay meshes found: " + str(overlay_count))

func _find_overlays_recursive(node: Node, overlay_count: int) -> void:
	"""Find overlay meshes recursively"""
	if node.name.begins_with("MovementOverlay_"):
		overlay_count += 1
		print("Found overlay: " + node.name)
		
		if node is MeshInstance3D:
			var mesh_inst = node as MeshInstance3D
			print("  Position: " + str(mesh_inst.position))
			print("  Visible: " + str(mesh_inst.visible))
			print("  Has material: " + str(mesh_inst.material_override != null))
			print("  Has mesh: " + str(mesh_inst.mesh != null))
	
	for child in node.get_children():
		_find_overlays_recursive(child, overlay_count)

func _test_tile_alignment() -> void:
	"""Test overlay alignment with tiles by creating overlays at known tile positions"""
	print("\n--- Testing Tile Alignment ---")
	
	var scene_root = get_tree().current_scene
	var grid = preload("res://board/Grid.tres")
	
	# Test positions that should align with tiles
	var test_positions = [
		Vector3(0, 0, 0),  # Should align with Tile_0_0 at world pos (0,0,0)
		Vector3(1, 0, 0),  # Should align with Tile_1_0 at world pos (2,0,0)
		Vector3(2, 0, 1),  # Should align with Tile_2_1 at world pos (4,0,2)
	]
	
	print("Creating alignment test overlays...")
	
	for i in range(test_positions.size()):
		var grid_pos = test_positions[i]
		var world_pos = grid.calculate_map_position(grid_pos)
		
		print("Grid pos " + str(grid_pos) + " -> World pos " + str(world_pos))
		
		# Create test overlay
		var mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "AlignmentTest_" + str(i)
		
		var plane_mesh = PlaneMesh.new()
		plane_mesh.size = Vector2(2.0, 2.0)  # Match tile size
		plane_mesh.orientation = PlaneMesh.FACE_Y
		
		# Use different colors for each test overlay
		var colors = [Color.RED, Color.GREEN, Color.BLUE]
		var material = StandardMaterial3D.new()
		material.albedo_color = colors[i]
		material.flags_unshaded = true
		material.emission_enabled = true
		material.emission = colors[i]
		material.no_depth_test = true
		material.flags_transparent = false
		
		mesh_instance.mesh = plane_mesh
		mesh_instance.material_override = material
		mesh_instance.position = world_pos + Vector3(0, 1.0, 0)  # Float above
		mesh_instance.visible = true
		
		scene_root.add_child(mesh_instance)
		
		print("Created " + colors[i].to_html() + " overlay at world pos " + str(mesh_instance.position))
	
	print("Alignment test overlays created. They should align perfectly with tiles.")
	print("Red should be on Tile_0_0, Green on Tile_1_0, Blue on Tile_2_1")
	
	# Remove after 10 seconds
	await get_tree().create_timer(10.0).timeout
	
	print("Removing alignment test overlays...")
	for i in range(test_positions.size()):
		var overlay = scene_root.get_node_or_null("AlignmentTest_" + str(i))
		if overlay:
			overlay.queue_free()
	print("Alignment test overlays removed")