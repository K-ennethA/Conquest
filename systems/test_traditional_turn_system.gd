extends Node

# Test script for Traditional Turn System
# Tests the complete turn system integration

var traditional_turn_system: TraditionalTurnSystem
var test_units: Array[Unit] = []

func _ready() -> void:
	print("=== Traditional Turn System Test ===")
	
	# Wait a frame for singletons to initialize
	await get_tree().process_frame
	
	# Initialize the test
	_setup_test()
	
	# Run tests
	_test_turn_system_registration()
	_test_turn_system_activation()
	_test_player_turn_management()
	_test_unit_action_tracking()
	_test_manual_turn_ending()
	
	print("=== Traditional Turn System Test Complete ===")

func _setup_test() -> void:
	"""Set up the test environment"""
	print("\n--- Setting up test environment ---")
	
	# Create traditional turn system
	traditional_turn_system = TraditionalTurnSystem.new()
	
	# Ensure PlayerManager has players
	if PlayerManager.players.is_empty():
		PlayerManager.setup_default_players()
	
	# Find test units in the scene
	_find_test_units()
	
	print("Test setup complete")

func _find_test_units() -> void:
	"""Find units in the scene for testing"""
	var scene_root = get_tree().current_scene
	test_units.clear()
	
	# Look for units in Player1 and Player2 nodes
	for player_num in range(1, 3):
		var player_node_path = "Map/Player" + str(player_num)
		var player_node = scene_root.get_node_or_null(player_node_path)
		
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					test_units.append(child)
					print("Found test unit: " + child.name)
	
	print("Found " + str(test_units.size()) + " test units")

func _test_turn_system_registration() -> void:
	"""Test turn system registration with TurnSystemManager"""
	print("\n--- Test 1: Turn System Registration ---")
	
	# Register the traditional turn system
	TurnSystemManager.register_turn_system(traditional_turn_system)
	
	# Check if it's available
	var available_systems = TurnSystemManager.get_available_turn_systems()
	var has_traditional = "TRADITIONAL" in available_systems
	
	if has_traditional:
		print("✓ Traditional turn system registered successfully")
	else:
		print("❌ Traditional turn system registration failed")
		print("Available systems: " + str(available_systems))

func _test_turn_system_activation() -> void:
	"""Test turn system activation"""
	print("\n--- Test 2: Turn System Activation ---")
	
	# Check what turn system was selected by the user
	var selected_system = GameSettings.selected_turn_system
	print("User selected turn system: " + TurnSystemBase.TurnSystemType.keys()[selected_system])
	
	# Only activate Traditional if it was actually selected
	if selected_system == TurnSystemBase.TurnSystemType.TRADITIONAL:
		# Activate traditional turn system
		var success = TurnSystemManager.activate_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
		
		if success:
			print("✓ Traditional turn system activated successfully")
			
			# Check if it's the active system
			var active_system = TurnSystemManager.get_active_turn_system()
			if active_system == traditional_turn_system:
				print("✓ Correct turn system is active")
			else:
				print("❌ Wrong turn system is active")
		else:
			print("❌ Failed to activate traditional turn system")
	else:
		print("✓ Skipping Traditional activation - user selected different system")
		print("✓ Respecting user's choice: " + TurnSystemBase.TurnSystemType.keys()[selected_system])

func _test_player_turn_management() -> void:
	"""Test player turn management"""
	print("\n--- Test 3: Player Turn Management ---")
	
	# Only run if Traditional system is active
	if not traditional_turn_system.is_active:
		print("✓ Skipping - Traditional turn system not active")
		return
	
	# Check current player
	var current_player = traditional_turn_system.get_current_active_player()
	if current_player:
		print("✓ Current player: " + current_player.get_display_name())
		
		# Check turn order
		var turn_order = traditional_turn_system.get_turn_order()
		print("✓ Turn order: " + str(turn_order.map(func(p): return p.get_display_name())))
		
		# Test turn advancement
		print("Advancing turn...")
		traditional_turn_system.advance_turn()
		
		var new_current_player = traditional_turn_system.get_current_active_player()
		if new_current_player and new_current_player != current_player:
			print("✓ Turn advanced to: " + new_current_player.get_display_name())
		else:
			print("❌ Turn advancement failed")
	else:
		print("❌ No current player found")

func _test_unit_action_tracking() -> void:
	"""Test unit action tracking"""
	print("\n--- Test 4: Unit Action Tracking ---")
	
	# Only run if Traditional system is active
	if not traditional_turn_system.is_active:
		print("✓ Skipping - Traditional turn system not active")
		return
	
	var current_player = traditional_turn_system.get_current_active_player()
	if not current_player:
		print("❌ No current player for unit action test")
		return
	
	# Find a unit belonging to current player
	var test_unit: Unit = null
	for unit in test_units:
		if current_player.owns_unit(unit):
			test_unit = unit
			break
	
	if not test_unit:
		print("❌ No test unit found for current player")
		return
	
	print("Testing with unit: " + test_unit.get_display_name())
	
	# Check if unit can act
	var can_act_before = traditional_turn_system.can_unit_act(test_unit)
	print("Can act before action: " + str(can_act_before))
	
	if can_act_before:
		# Simulate unit action
		traditional_turn_system.mark_unit_acted(test_unit)
		
		# Check if unit can still act
		var can_act_after = traditional_turn_system.can_unit_act(test_unit)
		print("Can act after action: " + str(can_act_after))
		
		if not can_act_after:
			print("✓ Unit action tracking works correctly")
		else:
			print("❌ Unit can still act after being marked as acted")
	else:
		print("❌ Unit cannot act initially")

func _test_manual_turn_ending() -> void:
	"""Test manual turn ending"""
	print("\n--- Test 5: Manual Turn Ending ---")
	
	# Only run if Traditional system is active
	if not traditional_turn_system.is_active:
		print("✓ Skipping - Traditional turn system not active")
		return
	
	var current_player = traditional_turn_system.get_current_active_player()
	if not current_player:
		print("❌ No current player for manual turn test")
		return
	
	print("Current player before manual end: " + current_player.get_display_name())
	
	# Check if we can end turn manually
	var can_end = traditional_turn_system.can_end_turn_manually()
	print("Can end turn manually: " + str(can_end))
	
	if can_end:
		# End turn manually
		traditional_turn_system.end_turn_manually()
		
		# Check if player changed
		var new_current_player = traditional_turn_system.get_current_active_player()
		if new_current_player and new_current_player != current_player:
			print("✓ Manual turn ending works: " + new_current_player.get_display_name())
		else:
			print("❌ Manual turn ending failed")
	else:
		print("❌ Cannot end turn manually")

# Debug key inputs for testing
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	# Only handle keyboard events
	if event is InputEventKey:
		match event.keycode:
			KEY_T:
				_print_turn_system_status()
			KEY_A:
				_test_advance_turn()
			KEY_E:
				_test_end_turn_manually()
			KEY_R:
				_reset_turn_system()

func _print_turn_system_status() -> void:
	"""Print current turn system status"""
	print("\n=== Turn System Status ===")
	TurnSystemManager.print_turn_system_status()
	
	if traditional_turn_system.is_active:
		var info = traditional_turn_system.get_turn_system_info()
		print("Traditional Turn System Info:")
		for key in info:
			print("  " + key + ": " + str(info[key]))

func _test_advance_turn() -> void:
	"""Test turn advancement"""
	print("\n--- Manual Turn Advancement Test ---")
	var current_player = traditional_turn_system.get_current_active_player()
	if current_player:
		print("Before: " + current_player.get_display_name())
		traditional_turn_system.advance_turn()
		var new_player = traditional_turn_system.get_current_active_player()
		if new_player:
			print("After: " + new_player.get_display_name())

func _test_end_turn_manually() -> void:
	"""Test manual turn ending"""
	print("\n--- Manual Turn End Test ---")
	if traditional_turn_system.can_end_turn_manually():
		traditional_turn_system.end_turn_manually()
		print("Turn ended manually")
	else:
		print("Cannot end turn manually")

func _reset_turn_system() -> void:
	"""Reset turn system for testing"""
	print("\n--- Resetting Turn System ---")
	if traditional_turn_system.is_active:
		traditional_turn_system.end_turn_system()
	traditional_turn_system.start_turn_system()
	print("Turn system reset")