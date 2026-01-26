extends Node

# Comprehensive GameWorld integration test
# Tests all Phase 1 systems working together in the main game scene

func _ready():
	print("=== GameWorld Integration Test ===")
	print("Testing complete tactical combat game integration...")
	
	# Wait for scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	_test_scene_structure()
	_test_unit_systems()
	_test_visual_systems()
	_test_tile_systems()
	_test_player_teams()
	
	print("=== GameWorld Integration Test Complete ===")
	print("Manual verification:")
	print("1. 5x5 tile grid should be visible")
	print("2. 6 units total: 3 Player1 (blue), 3 Player2 (red)")
	print("3. All units should have health bars above them")
	print("4. Warriors and Archers should look different")
	print("5. Cursor should be visible and moveable")
	print("6. Use inspector to test unit health changes")
	print("")
	print("Interactive Test Keys:")
	print("  Key 1: Damage random unit by 25")
	print("  Key 2: Heal random unit by 20")
	print("  Key 3: Test tile highlighting system (random colors)")
	print("  Key 4: Reset all health and clear tile highlights")

func _test_scene_structure():
	print("\n--- Test 1: Scene Structure ---")
	
	# Check main components
	var components = [
		"UnitVisualManager",
		"Map",
		"Map/Cursor",
		"Map/Tiles",
		"Map/Player1",
		"Map/Player2"
	]
	
	for component_path in components:
		var component = get_node("../" + component_path)
		if component:
			print("✓ Found: " + component_path)
		else:
			print("❌ Missing: " + component_path)
	
	# Check tile count
	var tiles_node = get_node("../Map/Tiles")
	if tiles_node:
		var tile_count = tiles_node.get_child_count()
		print("Tile count: " + str(tile_count))
		if tile_count == 25:  # 5x5 grid
			print("✓ Correct tile count (5x5 grid)")
		else:
			print("❌ Incorrect tile count, expected 25")

func _test_unit_systems():
	print("\n--- Test 2: Unit Systems ---")
	
	var player1_units = get_node("../Map/Player1").get_children()
	var player2_units = get_node("../Map/Player2").get_children()
	
	print("Player1 units: " + str(player1_units.size()))
	print("Player2 units: " + str(player2_units.size()))
	
	var total_units = player1_units.size() + player2_units.size()
	if total_units == 6:
		print("✓ Correct total unit count (6)")
	else:
		print("❌ Incorrect unit count, expected 6, got " + str(total_units))
	
	# Test unit stats integration
	for unit in player1_units + player2_units:
		if unit.has_method("get_display_name"):
			var name = unit.get_display_name()
			var health = unit.current_health
			var max_health = unit.max_health
			print("Unit: " + name + " - Health: " + str(health) + "/" + str(max_health))
			
			if unit.unit_stats:
				print("  ✓ UnitStats component present")
			else:
				print("  ❌ UnitStats component missing")

func _test_visual_systems():
	print("\n--- Test 3: Visual Systems ---")
	
	var visual_manager = get_node("../UnitVisualManager")
	if visual_manager:
		print("✓ UnitVisualManager found")
		
		# Check if health bars were created
		var player1_units = get_node("../Map/Player1").get_children()
		var player2_units = get_node("../Map/Player2").get_children()
		
		var health_bar_count = 0
		for unit in player1_units + player2_units:
			var health_bar = _find_health_bar(unit)
			if health_bar:
				health_bar_count += 1
				print("✓ Health bar found for " + unit.name)
			else:
				print("❌ No health bar for " + unit.name)
		
		print("Health bars created: " + str(health_bar_count) + "/6")
	else:
		print("❌ UnitVisualManager not found")

func _test_tile_systems():
	print("\n--- Test 4: Tile Systems ---")
	
	var tiles_node = get_node("../Map/Tiles")
	if tiles_node:
		var sample_tile = tiles_node.get_child(0)
		if sample_tile:
			print("✓ Sample tile found: " + sample_tile.name)
			
			# Test tile functionality
			if sample_tile.has_method("is_passable"):
				var passable = sample_tile.is_passable()
				print("  Tile passable: " + str(passable))
				print("  ✓ Tile system functional")
			else:
				print("  ❌ Tile missing enhanced functionality")
			
			# Test tile highlighting
			if sample_tile.has_method("set_highlight"):
				print("  ✓ Tile highlighting system ready")
			else:
				print("  ❌ Tile highlighting not implemented")
		else:
			print("❌ No tiles found")

func _test_player_teams():
	print("\n--- Test 5: Player Teams ---")
	
	var player1_units = get_node("../Map/Player1").get_children()
	var player2_units = get_node("../Map/Player2").get_children()
	
	# Check team visual distinction
	print("Checking team visual distinction...")
	
	for unit in player1_units:
		var mesh_instance = unit.get_node("MeshInstance3D")
		if mesh_instance and mesh_instance.material_override:
			var color = mesh_instance.material_override.albedo_color
			print("Player1 " + unit.name + " color: " + str(color))
			if color.b > 0.5:  # Should be blue-ish
				print("  ✓ Player1 unit has blue material")
			else:
				print("  ❌ Player1 unit doesn't have blue material")
	
	for unit in player2_units:
		var mesh_instance = unit.get_node("MeshInstance3D")
		if mesh_instance and mesh_instance.material_override:
			var color = mesh_instance.material_override.albedo_color
			print("Player2 " + unit.name + " color: " + str(color))
			if color.r > 0.5:  # Should be red-ish
				print("  ✓ Player2 unit has red material")
			else:
				print("  ❌ Player2 unit doesn't have red material")

func _find_health_bar(unit: Node) -> Node:
	"""Find the health bar child node of a unit"""
	for child in unit.get_children():
		if child.name == "HealthBar" or (child.get_script() and child.get_script().get_global_name() == "HealthBar"):
			return child
	return null

# Input handling for interactive testing
func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_test_damage_random_unit()
			KEY_2:
				_test_heal_random_unit()
			KEY_3:
				_test_tile_highlighting()
			KEY_4:
				_reset_all_health()

func _test_damage_random_unit():
	var all_units = get_node("../Map/Player1").get_children() + get_node("../Map/Player2").get_children()
	if all_units.size() > 0:
		var random_unit = all_units[randi() % all_units.size()]
		if random_unit.has_method("take_damage"):
			print("Damaging random unit: " + random_unit.name)
			random_unit.take_damage(25)

func _test_heal_random_unit():
	var all_units = get_node("../Map/Player1").get_children() + get_node("../Map/Player2").get_children()
	if all_units.size() > 0:
		var random_unit = all_units[randi() % all_units.size()]
		if random_unit.has_method("heal"):
			print("Healing random unit: " + random_unit.name)
			random_unit.heal(20)

func _test_tile_highlighting():
	var tiles_node = get_node("../Map/Tiles")
	if tiles_node:
		print("Testing tile highlighting system...")
		print("This will randomly highlight tiles with different colors:")
		print("  Green = Movement preview")
		print("  Red = Attack preview") 
		print("  Yellow = Selected tile")
		print("  Normal = No highlight")
		
		var tiles = tiles_node.get_children()
		
		# First, clear all highlights
		for tile in tiles:
			if tile.has_method("set_highlight"):
				tile.set_highlight(0)  # NONE
		
		# Then highlight some random tiles with different types
		for i in range(min(8, tiles.size())):
			var tile = tiles[randi() % tiles.size()]
			if tile.has_method("set_highlight"):
				var highlight_types = [1, 2, 3]  # MOVEMENT, ATTACK, SELECTED (skip NONE for demo)
				var highlight_names = ["MOVEMENT (green)", "ATTACK (red)", "SELECTED (yellow)"]
				var highlight_type = highlight_types[randi() % highlight_types.size()]
				tile.set_highlight(highlight_type)
				print("  Highlighted tile " + tile.name + " with " + highlight_names[highlight_type - 1])
		
		print("Press key 3 again to test more random highlights, or key 4 to reset")

func _reset_all_health():
	print("Resetting all unit health to full and clearing tile highlights...")
	
	# Reset unit health
	var all_units = get_node("../Map/Player1").get_children() + get_node("../Map/Player2").get_children()
	for unit in all_units:
		if unit.has_method("heal") and unit.has_method("get_stat"):
			var max_health = unit.get_stat("health")
			unit.heal(max_health)  # Heal to full
	
	# Clear all tile highlights
	var tiles_node = get_node("../Map/Tiles")
	if tiles_node:
		var tiles = tiles_node.get_children()
		for tile in tiles:
			if tile.has_method("set_highlight"):
				tile.set_highlight(0)  # NONE - back to normal color
		print("All tile highlights cleared")