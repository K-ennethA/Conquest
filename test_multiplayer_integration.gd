extends Node

# Test script to verify multiplayer integration with the main game flow

func _ready() -> void:
	print("=== Multiplayer Integration Test ===")
	
	# Test the flow: Main Menu -> Versus -> Network Multiplayer -> Game
	await _test_multiplayer_flow()
	
	print("=== Test Complete ===")

func _test_multiplayer_flow() -> void:
	"""Test the complete multiplayer flow"""
	print("\n--- Testing Multiplayer Integration Flow ---")
	
	# Simulate the flow that happens when user clicks Versus -> Network Multiplayer -> Host
	print("1. Setting up GameSettings for multiplayer...")
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
	
	print("2. Testing GameModeManager multiplayer host...")
	if GameModeManager:
		var success = await GameModeManager.start_network_multiplayer_host("Test Host", "local")
		if success:
			print("✓ Network multiplayer host started successfully")
			
			# Test action submission
			print("3. Testing action submission...")
			var action_success = GameModeManager.submit_action("unit_select", {
				"unit_id": "test_unit",
				"player_id": 0
			})
			print("✓ Action submitted: %s" % action_success)
			
			# Get status
			var status = GameModeManager.get_game_status()
			print("✓ Game status: %s" % status.get("game_mode", "unknown"))
			print("✓ Multiplayer active: %s" % GameModeManager.is_multiplayer_active())
			
			# Test turn checking
			print("✓ Is my turn: %s" % GameModeManager.is_my_turn())
			print("✓ Can I act: %s" % GameModeManager.can_i_act())
			
			# Clean up
			GameModeManager.end_current_game()
			print("✓ Multiplayer game ended")
		else:
			print("✗ Failed to start network multiplayer host")
	else:
		print("✗ GameModeManager not available")
	
	print("\n--- Multiplayer Integration Test Complete ---")

# Test input handling
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_T:
				print("\n--- Manual Test: Multiplayer Flow ---")
				_test_multiplayer_flow()
			KEY_H:
				_print_help()

func _print_help() -> void:
	"""Print help information"""
	print("\n=== Multiplayer Integration Test Controls ===")
	print("T - Test Multiplayer Flow")
	print("H - Show this help")
	print("===============================================\n")