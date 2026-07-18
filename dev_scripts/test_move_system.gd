extends Node

# Test script for the move system

func _ready() -> void:
	print("=== MOVE SYSTEM TEST ===")
	print("This test demonstrates the new move system")
	print("")
	print("Features:")
	print("- Units can have up to 5 moves")
	print("- Moves have cooldowns, range, and area of effect")
	print("- Custom move effects with flexible function system")
	print("- Move selection UI integrated with UnitActionsPanel")
	print("")
	print("Test Instructions:")
	print("1. Select a unit in the game")
	print("2. Click the 'MOVES' button in the actions panel")
	print("3. Select a move from the list")
	print("4. Target an enemy (for damage moves) or ally (for heal/buff moves)")
	print("5. Watch the move execute and see cooldown applied")
	print("")
	print("Press F9 to run move system tests")
	print("Press F10 to create test moves for all units")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F9:
			_test_move_system()
		elif event.keycode == KEY_F10:
			_create_moves_for_all_units()

func _test_move_system() -> void:
	"""Test the move system components"""
	print("\n=== TESTING MOVE SYSTEM COMPONENTS ===")
	
	# Test 1: Create a basic move
	print("\nTest 1: Creating basic moves")
	var basic_attack = MoveFactory.create_basic_attack()
	print("✓ Created: " + basic_attack.name)
	print("  Power: " + str(basic_attack.base_power))
	print("  Range: " + str(basic_attack.range))
	print("  Cooldown: " + str(basic_attack.cooldown_turns))
	
	var fireball = MoveFactory.create_fireball()
	print("✓ Created: " + fireball.name)
	print("  Power: " + str(fireball.base_power))
	print("  Range: " + str(fireball.range))
	print("  Area: " + str(fireball.area_of_effect))
	print("  Cooldown: " + str(fireball.cooldown_turns))
	
	# Test 2: Test move manager
	print("\nTest 2: Testing MoveManager")
	var test_unit = _find_test_unit()
	if test_unit:
		var move_manager = test_unit.get_node_or_null("MoveManager")
		if not move_manager:
			move_manager = MoveManager.new()
			test_unit.add_child(move_manager)
			print("✓ Created MoveManager for " + test_unit.name)
		
		# Add some moves
		var moves_added = 0
		for move in [basic_attack, fireball, MoveFactory.create_heal()]:
			if move_manager.add_move(move):
				moves_added += 1
		
		print("✓ Added " + str(moves_added) + " moves to " + test_unit.name)
		
		# Test move info
		var moves_info = move_manager.get_moves_info()
		print("✓ Move info retrieved: " + str(moves_info.size()) + " moves")
		
		for info in moves_info:
			print("  - " + info.name + " (Available: " + str(info.available) + ")")
	else:
		print("✗ No test unit found")
	
	# Test 3: Test move effects
	print("\nTest 3: Testing move effects")
	_test_move_effects()
	
	print("\n=== MOVE SYSTEM TEST COMPLETE ===")

func _test_move_effects() -> void:
	"""Test different move effects"""
	var caster = _find_test_unit()
	var target = _find_different_test_unit(caster)
	
	if not caster or not target:
		print("✗ Need at least 2 units to test move effects")
		return
	
	print("Testing move effects with caster: " + caster.name + " and target: " + target.name)
	
	# Test basic attack
	var basic_attack = MoveFactory.create_basic_attack()
	var result = basic_attack.execute(caster, target)
	print("Basic Attack result: " + result.message)
	
	# Test heal (self-target)
	var heal = MoveFactory.create_heal()
	result = heal.execute(caster, caster)
	print("Heal result: " + result.message)
	
	# Test shield
	var shield = MoveFactory.create_shield_wall()
	result = shield.execute(caster, caster)
	print("Shield result: " + result.message)

func _create_moves_for_all_units() -> void:
	"""Create moves for all units in the scene"""
	print("\n=== CREATING MOVES FOR ALL UNITS ===")
	
	var units = _find_all_units()
	var units_updated = 0
	
	for unit in units:
		var move_manager = unit.get_node_or_null("MoveManager")
		if move_manager:
			print("Unit " + unit.name + " already has MoveManager")
			continue
		
		# Create MoveManager
		move_manager = MoveManager.new()
		unit.add_child(move_manager)
		
		# Determine unit type and add appropriate moves
		var unit_name = unit.name.to_lower()
		var moves: Array[Move] = []
		
		if "warrior" in unit_name:
			moves = MoveFactory.get_warrior_moves()
			print("✓ Added warrior moves to " + unit.name)
		elif "archer" in unit_name:
			moves = MoveFactory.get_archer_moves()
			print("✓ Added archer moves to " + unit.name)
		elif "mage" in unit_name:
			moves = MoveFactory.get_mage_moves()
			print("✓ Added mage moves to " + unit.name)
		else:
			# Default moves
			moves = [
				MoveFactory.create_basic_attack(),
				MoveFactory.create_heal(),
				MoveFactory.create_power_strike()
			]
			print("✓ Added default moves to " + unit.name)
		
		# Add moves to unit
		for move in moves:
			move_manager.add_move(move)
		
		units_updated += 1
	
	print("✓ Updated " + str(units_updated) + " units with moves")
	print("=== MOVE CREATION COMPLETE ===")

func _find_test_unit() -> Node:
	"""Find a unit for testing"""
	var units = _find_all_units()
	return units[0] if units.size() > 0 else null

func _find_different_test_unit(exclude_unit: Node) -> Node:
	"""Find a different unit for testing"""
	var units = _find_all_units()
	for unit in units:
		if unit != exclude_unit:
			return unit
	return null

func _find_all_units() -> Array[Node]:
	"""Find all units in the scene"""
	var units: Array[Node] = []
	var scene_root = get_tree().current_scene
	
	if not scene_root:
		return units
	
	var map = scene_root.get_node_or_null("Map")
	if not map:
		return units
	
	# Look for units in player folders
	for player_folder in ["Player1", "Player2"]:
		var player_node = map.get_node_or_null(player_folder)
		if player_node:
			for child in player_node.get_children():
				if child.has_method("get_node") and child.get_node_or_null("UnitStats"):
					units.append(child)
	
	return units

func _exit_tree() -> void:
	"""Clean up when exiting"""
	pass