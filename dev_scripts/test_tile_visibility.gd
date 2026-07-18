extends Node

# Focused test for tile visibility - press F5 to test

func _ready() -> void:
	print("🎯 Tile Visibility Test Ready - Press F5 to test")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			print("F5 pressed - testing tile visibility")
			_test_tile_visibility()

func _test_tile_visibility() -> void:
	"""Test tile visibility with progressively more obvious materials"""
	
	print("=== Tile Visibility Test ===")
	
	# Find the first tile
	var scene_root = get_tree().current_scene
	var tiles_node = scene_root.get_node_or_null("Map/Tiles")
	
	if not tiles_node or tiles_node.get_child_count() == 0:
		print("❌ No tiles found")
		return
	
	var test_tile = tiles_node.get_child(0)
	var mesh_instance = test_tile.get_node_or_null("MeshInstance3D")
	
	if not mesh_instance:
		print("❌ No MeshInstance3D found")
		return
	
	print("✅ Testing with tile: " + test_tile.name)
	print("Original material: " + str(mesh_instance.get_surface_override_material(0)))
	
	# Test 1: Solid bright color (no transparency)
	print("\n🔵 Test 1: Solid bright blue (no transparency)")
	var solid_blue = StandardMaterial3D.new()
	solid_blue.albedo_color = Color(0.0, 0.0, 1.0, 1.0)  # Solid blue
	solid_blue.flags_unshaded = true
	mesh_instance.set_surface_override_material(0, solid_blue)
	
	await get_tree().create_timer(2.0).timeout
	
	# Test 2: Bright emission
	print("🔥 Test 2: Bright emission material")
	var emission_material = StandardMaterial3D.new()
	emission_material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)  # Magenta
	emission_material.emission_enabled = true
	emission_material.emission = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta emission
	emission_material.flags_unshaded = true
	mesh_instance.set_surface_override_material(0, emission_material)
	
	await get_tree().create_timer(2.0).timeout
	
	# Test 3: Wireframe
	print("📐 Test 3: Wireframe material")
	var wireframe_material = StandardMaterial3D.new()
	wireframe_material.flags_use_point_size = true
	wireframe_material.flags_wireframe = true
	wireframe_material.albedo_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow wireframe
	mesh_instance.set_surface_override_material(0, wireframe_material)
	
	await get_tree().create_timer(2.0).timeout
	
	# Test 4: Our movement material (enhanced)
	print("🎯 Test 4: Enhanced movement material")
	var movement_material = StandardMaterial3D.new()
	movement_material.albedo_color = Color(0.3, 0.7, 1.0, 1.0)  # Solid blue (no transparency)
	movement_material.flags_unshaded = true
	movement_material.emission_enabled = true
	movement_material.emission = Color(0.5, 0.8, 1.0, 1.0)  # Bright blue emission
	movement_material.no_depth_test = true
	mesh_instance.set_surface_override_material(0, movement_material)
	
	await get_tree().create_timer(3.0).timeout
	
	# Restore original
	print("🔄 Restoring original material")
	mesh_instance.set_surface_override_material(0, null)
	
	print("=== Test Complete ===")
	print("If you saw any colored tiles, materials work!")
	print("If you saw nothing, there's a deeper rendering issue.")