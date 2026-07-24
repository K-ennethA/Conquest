extends Node

# Test script to verify the unified multiplayer system works correctly
# Tests the integration between GameModeManager and the multiplayer system

func _ready() -> void:
	print("=== Unified Multiplayer System Test ===")
	
	# Test the unified system
	await _test_unified_system()
	
	print("=== Test Complete ===")

func _test_unified_system() -> void:
	"""Test the unified game system"""
	print("\n--- Testing Unified Game System ---")
	
	# Get GameModeManager from autoload
	var game_mode_manager = GameModeManager
	
	# Test single-player mode
	print("\n1. Testing Single-Player Mode...")
	var success = game_mode_manager.start_single_player("Test Player", 1)
	if success:
		print("✓ Single-player game started successfully")
		
		# Test action submission
		var action_success = game_mode_manager.submit_action("unit_select", {
			"unit_id": "test_unit",
			"player_id": 0
		})
		print("✓ Action submitted: %s" % action_success)
		
		# Get status
		var status = game_mode_manager.get_game_status()
		print("✓ Game status: %s" % status.game_mode)
		
		game_mode_manager.end_current_game()
		print("✓ Single-player game ended")
	else:
		print("✗ Failed to start single-player game")
	
	# Test local multiplayer mode
	print("\n2. Testing Local Multiplayer Mode...")
	success = game_mode_manager.start_local_multiplayer(["Player 1", "Player 2"])
	if success:
		print("✓ Local multiplayer game started successfully")
		
		# Test turn-based actions
		var action_success = game_mode_manager.submit_action("end_turn", {
			"player_id": 0
		})
		print("✓ Turn action submitted: %s" % action_success)
		
		game_mode_manager.end_current_game()
		print("✓ Local multiplayer game ended")
	else:
		print("✗ Failed to start local multiplayer game")
	
	# Test network multiplayer mode (local development)
	print("\n3. Testing Network Multiplayer Mode...")
	success = await game_mode_manager.start_network_multiplayer_host("Host Player", "local")
	if success:
		print("✓ Network multiplayer host started successfully")
		
		# Test network action
		var action_success = game_mode_manager.submit_action("unit_move", {
			"unit_id": "test_unit",
			"from_position": Vector3(0, 0, 0),
			"to_position": Vector3(1, 0, 1)
		})
		print("✓ Network action submitted: %s" % action_success)
		
		# Get multiplayer status
		var mp_status = game_mode_manager.get_multiplayer_status()
		print("✓ Multiplayer status: %s" % mp_status.game_mode)
		
		game_mode_manager.end_current_game()
		print("✓ Network multiplayer game ended")
	else:
		print("✗ Failed to start network multiplayer host")
	
	print("\n--- Unified System Test Complete ---")
	
	# Clean up
	game_mode_manager.queue_free()