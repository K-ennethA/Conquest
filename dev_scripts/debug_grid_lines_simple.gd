extends Node

# Simple debug script to test grid line creation

func _ready() -> void:
	print("=== SIMPLE GRID LINES DEBUG ===")
	
	# Create a simple test line to verify line rendering works
	_create_test_line()
	
	# Wait and then create border lines manually
	await get_tree().create_timer(1.0).timeout
	_create_manual_border_lines()

func _create_test_line() -> void:
	"""Create a simple test line to verify basic line rendering"""
	print("Creating simple test line...")
	
	var test_line = MeshInstance3D.new()
	test_line.name = "SimpleTestLine"
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(3.0, 0.5, 0.5)  # Large, thick line
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0, 1.0)  # Bright red
	material.flags_unshaded = true
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0, 1.0)
	material.no_depth_test = true
	
	test_line.mesh = box_mesh
	test_line.material_override = material
	test_line.position = Vector3(2.0, 3.0, 2.0)  # High above center
	test_line.visible = true
	
	get_tree().current_scene.add_child(test_line)
	print("Simple test line created at " + str(test_line.position))

func _create_manual_border_lines() -> void:
	"""Manually create border lines around the center tile"""
	print("Creating manual border lines around center tile...")
	
	var center_world_pos = Vector3(5.0, 0.5, 5.0)  # Center of 5x5 grid
	var tile_size = 2.0
	var line_width = 0.3
	var line_height = center_world_pos.y + 0.2
	var half_size = tile_size / 2.0
	
	# Create bright green border lines
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(0.0, 1.0, 0.0, 1.0)  # Bright green
	line_material.flags_unshaded = true
	line_material.emission_enabled = true
	line_material.emission = Color(0.0, 1.0, 0.0, 1.0)
	line_material.no_depth_test = true
	
	# Create 4 border lines
	var lines = [
		{pos = Vector3(center_world_pos.x, line_height, center_world_pos.z - half_size), size = Vector3(tile_size, line_width, line_width)},
		{pos = Vector3(center_world_pos.x, line_height, center_world_pos.z + half_size), size = Vector3(tile_size, line_width, line_width)},
		{pos = Vector3(center_world_pos.x - half_size, line_height, center_world_pos.z), size = Vector3(line_width, line_width, tile_size)},
		{pos = Vector3(center_world_pos.x + half_size, line_height, center_world_pos.z), size = Vector3(line_width, line_width, tile_size)}
	]
	
	for i in range(lines.size()):
		var line_data = lines[i]
		var line_mesh = MeshInstance3D.new()
		line_mesh.name = "ManualBorderLine_" + str(i)
		
		var box_mesh = BoxMesh.new()
		box_mesh.size = line_data.size
		
		line_mesh.mesh = box_mesh
		line_mesh.material_override = line_material
		line_mesh.position = line_data.pos
		line_mesh.visible = true
		
		get_tree().current_scene.add_child(line_mesh)
		print("Manual border line " + str(i) + " created at " + str(line_data.pos))
	
	print("Manual border lines complete - should see green box around center tile")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_T:
				print("T pressed - creating another test line")
				_create_test_line()
			KEY_B:
				print("B pressed - creating more border lines")
				_create_manual_border_lines()