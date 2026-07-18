extends Node

# Quick test script for multiplayer host and join functionality
# Add this to a test scene or run directly

func _ready():
	print("\n=== MULTIPLAYER HOST/JOIN TEST ===\n")
	
	# Test 1: Check if GameModeManager is available
	print("Test 1: Checking GameModeManager...")
	if GameModeManager:
		print("✓ GameModeManager found")
	else:
		print("✗ GameModeManager NOT found - check autoload")
		return
	
	# Test 2: Check if NetworkManager is available
	print("\nTest 2: Checking NetworkManager...")
	var network_manager = get_tree().root.get_node_or_null("NetworkManager")
	if network_manager:
		print("✓ NetworkManager found")
	else:
		print("⚠ NetworkManager not found - will be created on demand")
	
	# Test 3: Test host startup
	print("\nTest 3: Testing host startup...")
	print("Starting host with P2P mode...")
	var host_success = await GameModeManager.start_network_multiplayer_host("Test Host", "p2p")
	
	if host_success:
		print("✓ Host started successfully")
		
		# Get connection info
		var status = GameModeManager.get_game_status()
		print("  Game mode: " + str(status.get("game_mode", "UNKNOWN")))
		print("  Network status: " + str(status.get("network_status", "unknown")))
		
		var connection_info = status.get("connection_info", {})
		print("  Connection info: " + str(connection_info))
		
		# Test 4: Check if we can get multiplayer status
		print("\nTest 4: Checking multiplayer status...")
		var mp_status = GameModeManager.get_multiplayer_status()
		print("  Is active: " + str(mp_status.get("is_active", false)))
		print("  Local player ID: " + str(mp_status.get("local_player_id", -1)))
		
		print("\n✓ All tests passed!")
		print("\nYou can now:")
		print("1. Launch another instance of the game")
		print("2. Navigate to Network Multiplayer → Join Game")
		print("3. Use address: 127.0.0.1, port: 8910")
		
	else:
		print("✗ Host failed to start")
		print("Check console for error messages")
	
	print("\n=== TEST COMPLETE ===\n")

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_Q:
				print("\nQuitting test...")
				get_tree().quit()
			KEY_D:
				print("\n=== DEBUG INFO ===")
				if GameModeManager:
					var status = GameModeManager.get_game_status()
					print("Game Status: " + str(status))
				print("=== END DEBUG ===\n")
			KEY_H:
				print("\n=== HELP ===")
				print("Q - Quit test")
				print("D - Show debug info")
				print("H - Show this help")
				print("=== END HELP ===\n")
