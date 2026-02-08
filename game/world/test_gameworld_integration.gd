extends Node

# Comprehensive GameWorld integration test
# Tests all Phase 1 systems working together in the main game scene

func _ready():
	print("=== GameWorld Integration Test ===")
	print("Testing complete tactical combat game integration...")
	
	# Wait for scene to initialize
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Connect TurnQueue to UnitInfoPanel for portrait clicks
	_connect_ui_components()
	
	# Check what turn system was selected
	var selected_system = GameSettings.selected_turn_system
	print("Selected turn system from GameSettings: " + TurnSystemBase.TurnSystemType.keys()[selected_system])
	
	_test_scene_structure()
	_test_unit_systems()
	_test_visual_systems()
	_test_tile_systems()
	_test_player_teams()
	
	# Only run turn system tests if Traditional was selected
	# If Speed First was selected, let it run without interference
	if selected_system == TurnSystemBase.TurnSystemType.TRADITIONAL:
		print("\n--- Running Traditional Turn System Tests ---")
		# The traditional tests will run
	else:
		print("\n--- Skipping Traditional Turn System Tests (Speed First selected) ---")
	
	# Reset turn system after tests complete to ensure UI shows Turn 1
	print("\n--- Resetting Turn System After Tests ---")
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		print("Resetting turn system to initial state...")
		TurnSystemManager.reset_turn_system()
		print("Turn system reset complete - UI should now show Turn 1")
	else:
		print("No active turn system to reset")
	
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
	print("  Key S: Switch to Speed First turn system")
	print("  Key T: Switch to Traditional turn system")
	print("")
	print("Unit Actions Panel Features:")
	print("  - Select a unit to see Move and End Turn actions")
	print("  - Click 'Unit Summary' button to view detailed stats")
	print("  - Stats show current values including battle effects")
	print("  - Keyboard shortcuts: M (Move), E (End Turn), S (Summary), C (Cancel)")
	print("")
	print("Speed First UI Features:")
	print("  - Turn Queue centered with proper spacing from screen edges")
	print("  - Click unit portraits to see details")
	print("  - Use ◀ ▶ buttons to scroll through units (4 shown at a time)")
	print("  - Only current acting unit can be selected")
	print("  - Page info shows current page when scrolling needed")
	print("  - Proper margins and padding for professional appearance")

func _connect_ui_components():
	"""Connect UI components for better integration"""
	var ui_layout = get_node("../UI/GameUILayout")
	if not ui_layout:
		print("Could not find GameUILayout")
		return
	
	var turn_queue = ui_layout.get_panel("turn_queue")
	var unit_actions_panel = ui_layout.get_panel("unit_actions")
	
	if turn_queue and unit_actions_panel:
		# Connect TurnQueue portrait clicks to UnitActionsPanel (which now has unit stats)
		if not turn_queue.unit_portrait_clicked.is_connected(_on_turn_queue_portrait_clicked):
			turn_queue.unit_portrait_clicked.connect(_on_turn_queue_portrait_clicked)
		print("Connected TurnQueue to UnitActionsPanel")
		
		# Also connect hover events for better UX
		if turn_queue.has_signal("unit_portrait_hovered") and not turn_queue.unit_portrait_hovered.is_connected(_on_turn_queue_portrait_hovered):
			turn_queue.unit_portrait_hovered.connect(_on_turn_queue_portrait_hovered)
		if turn_queue.has_signal("unit_portrait_unhovered") and not turn_queue.unit_portrait_unhovered.is_connected(_on_turn_queue_portrait_unhovered):
			turn_queue.unit_portrait_unhovered.connect(_on_turn_queue_portrait_unhovered)
		print("Connected TurnQueue hover events")
	else:
		print("Could not find UI components to connect")
		if not turn_queue:
			print("  - TurnQueue not found")
		if not unit_actions_panel:
			print("  - UnitActionsPanel not found")

func _on_turn_queue_portrait_clicked(unit: Unit):
	"""Handle turn queue portrait clicks"""
	print("Turn queue portrait clicked: " + unit.get_display_name())
	
	# Select the unit to show actions panel with stats
	GameEvents.unit_selected.emit(unit, unit.global_position)

func _on_turn_queue_portrait_hovered(unit: Unit):
	"""Handle turn queue portrait hover"""
	print("Turn queue portrait hovered: " + unit.get_display_name())
	# Hover functionality is now integrated into the actions panel

func _on_turn_queue_portrait_unhovered(unit: Unit):
	"""Handle turn queue portrait unhover"""
	print("Turn queue portrait unhovered: " + unit.get_display_name())
	# Hover functionality is now integrated into the actions panel

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
			KEY_S:
				_switch_to_speed_first()
			KEY_T:
				_switch_to_traditional()

func _switch_to_speed_first():
	"""Switch to Speed First turn system for testing"""
	print("=== SWITCHING TO SPEED FIRST TURN SYSTEM ===")
	
	# Create and register Speed First system
	var speed_system = SpeedFirstTurnSystem.new()
	TurnSystemManager.register_turn_system(speed_system)
	
	# Activate it
	var success = TurnSystemManager.activate_turn_system(TurnSystemBase.TurnSystemType.INITIATIVE)
	if success:
		print("Successfully switched to Speed First turn system")
	else:
		print("Failed to switch to Speed First turn system")

func _switch_to_traditional():
	"""Switch to Traditional turn system for testing"""
	print("=== SWITCHING TO TRADITIONAL TURN SYSTEM ===")
	
	# Create and register Traditional system
	var trad_system = TraditionalTurnSystem.new()
	TurnSystemManager.register_turn_system(trad_system)
	
	# Activate it
	var success = TurnSystemManager.activate_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
	if success:
		print("Successfully switched to Traditional turn system")
	else:
		print("Failed to switch to Traditional turn system")

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
