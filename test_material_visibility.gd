extends Node

# Test script to verify material visibility - press F9 to test

func _ready() -> void:
	print("🎨 Material Visibility Test Ready - Press F9 to test")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F9:
			print("F9 pressed - testing material visibility")
			_test_material_visibility()

func _test_material_visibility() -> void:
	"""Test if materials are visible on tiles"""
	
	print("=== Material Visibility Test ===")
	
	# Find the first tile
	var scene_root = get_tree().current_scene
	var map_node = scene_root.get_node_or_null("Map")
	if not map_node:
		print("❌ No Map node found")
		return
	
	var tiles_node = map_node.get_node_or_null("Tiles")
	if not tiles_node:
		print("❌ No Tiles node found")
		return
	
	if tiles_node.get_child_count() == 0:
		print("❌ No tiles found")
		return
	
	var test_tile = tiles_node.get_child(0)
	print("✅ Testing with tile: " + test_tile.name)
	
	var mesh_instance = test_tile.get_node_or_null("MeshInstance3D")
	if not mesh_instance:
		print("❌ No MeshInstance3D found in tile")
		return
	
	print("✅ Found MeshInstance3D")
	
	# Create a very obvious bright material
	var test_material = StandardMaterial3D.new()
	test_material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta, fully opaque
	test_material.flags_unshaded = true
	test_material.emission_enabled = true
	test_material.emission = Color(1.0, 0.0, 1.0, 1.0)  # Bright magenta emission
	test_material.no_depth_test = true
	
	print("🎨 Applying bright magenta material to tile...")
	
	# Store original material
	var original_material = mesh_instance.get_surface_override_material(0)
	
	# Apply test material
	mesh_instance.set_surface_override_material(0, test_material)
	
	print("✅ Material applied! The tile should now be bright magenta.")
	print("If you can't see it, there might be a rendering issue.")
	
	# Wait 5 seconds then restore
	await get_tree().create_timer(5.0).timeout
	
	print("🔄 Restoring original material...")
	mesh_instance.set_surface_override_material(0, original_material)
	
	print("=== Material Visibility Test Complete ===")
	print("If you saw a bright magenta tile, materials are working!")
	print("If not, there's a rendering/visibility issue.")