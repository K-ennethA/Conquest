extends Node

# Debug script to test network connection between host and client

func _ready():
	print("=== Network Connection Debug Test ===")
	
	# Wait a moment for systems to initialize
	await get_tree().create_timer(2.0).timeout
	
	test_network_connection()

func test_network_connection():
	print("\n--- Testing Network Connection ---")
	
	# Check if we're in multiplayer mode
	if GameModeManager and GameModeManager.is_multiplayer_active():
		print("✓ Multiplayer is active")
		
		var game_manager = GameModeManager._game_manager
		if game_manager:
			print("✓ GameManager found")
			
			var network_handler = game_manager._network_handler
			if network_handler:
				print("✓ NetworkHandler found")
				print("  Is host: " + str(network_handler.is_host()))
				print("  Local player ID: " + str(GameModeManager.get_local_player_id()))
				
				# Test sending a simple action
				print("\n--- Testing Action Send ---")
				var test_action = {
					"type": "test_connection",
					"data": {
						"message": "Hello from " + ("host" if network_handler.is_host() else "client"),
						"timestamp": Time.get_ticks_msec()
					}
				}
				
				var success = game_manager.submit_player_action("test_connection", test_action.data)
				print("Test action submitted: " + str(success))
				
			else:
				print("✗ NetworkHandler not found")
		else:
			print("✗ GameManager not found")
	else:
		print("✗ Multiplayer not active")
	
	print("\n--- Connection Test Complete ---")

func _input(event):
	if event.is_pressed() and event is InputEventKey:
		match event.keycode:
			KEY_F9:
				print("F9 pressed - running network test")
				test_network_connection()
			KEY_F10:
				print("F10 pressed - testing turn change manually")
				test_manual_turn_change()

func test_manual_turn_change():
	print("\n=== Manual Turn Change Test ===")
	
	if GameModeManager and GameModeManager.is_multiplayer_active():
		var game_manager = GameModeManager._game_manager
		if game_manager:
			var current_player = game_manager.get_current_player_id()
			var next_player = 1 - current_player  # Toggle between 0 and 1
			
			print("Current player: " + str(current_player))
			print("Switching to player: " + str(next_player))
			
			# Manually trigger turn change
			game_manager._current_turn_player = next_player
			game_manager.turn_changed.emit(next_player)
			
			print("Manual turn change triggered")
	else:
		print("Not in multiplayer mode")