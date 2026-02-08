extends Node

# Final multiplayer connection test
# Run this to test the complete multiplayer system with all fixes

func _ready() -> void:
	print("=== FINAL MULTIPLAYER CONNECTION TEST ===")
	
	# Check if this is a client instance
	var args = OS.get_cmdline_args()
	var is_client = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			is_client = true
			break
	
	if is_client:
		print("[CLIENT] Running as CLIENT instance")
		await test_client_flow()
	else:
		print("[HOST] Running as HOST instance")
		await test_host_flow()

func test_host_flow() -> void:
	"""Test the complete host flow"""
	print("[HOST] === TESTING HOST FLOW ===")
	
	# Wait for initialization
	await get_tree().create_timer(0.5).timeout
	
	# Check GameModeManager
	if not GameModeManager:
		print("[HOST] ERROR: GameModeManager not found!")
		return
	
	print("[HOST] GameModeManager found: " + str(GameModeManager))
	
	# Start hosting
	print("[HOST] Starting network multiplayer host...")
	var success = await GameModeManager.start_network_multiplayer_host("Host Player", "local")
	
	print("[HOST] Host start result: " + str(success))
	
	if success:
		print("[HOST] ✓ Host started successfully!")
		
		# Get connection info
		var status = GameModeManager.get_game_status()
		print("[HOST] Game status: " + str(status))
		
		# Wait for potential client connection
		print("[HOST] Waiting 10 seconds for client connection...")
		for i in range(10):
			await get_tree().create_timer(1.0).timeout
			var current_status = GameModeManager.get_game_status()
			var network_status = current_status.get("network_status", {})
			print("[HOST] Second %d - Network status: %s" % [i + 1, str(network_status)])
		
		print("[HOST] Host test complete")
	else:
		print("[HOST] ✗ Host failed to start!")

func test_client_flow() -> void:
	"""Test the complete client flow"""
	print("[CLIENT] === TESTING CLIENT FLOW ===")
	
	# Wait for initialization
	await get_tree().create_timer(1.0).timeout
	
	# Check MultiplayerLauncher
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	if launcher:
		print("[CLIENT] MultiplayerLauncher found: " + str(launcher))
		var auto_join_info = launcher.get_auto_join_info()
		print("[CLIENT] Auto-join info: " + str(auto_join_info))
		
		if auto_join_info.enabled:
			print("[CLIENT] ✓ Auto-join is enabled")
			print("[CLIENT] Waiting for auto-join to complete...")
			
			# Wait and monitor connection
			for i in range(10):
				await get_tree().create_timer(1.0).timeout
				
				if GameModeManager:
					var status = GameModeManager.get_game_status()
					var is_active = status.get("is_active", false)
					var network_status = status.get("network_status", "unknown")
					
					print("[CLIENT] Second %d - Game active: %s, Network: %s" % [i + 1, str(is_active), str(network_status)])
					
					if is_active and network_status == "connected":
						print("[CLIENT] ✓ Successfully connected!")
						break
				else:
					print("[CLIENT] Second %d - GameModeManager not available" % [i + 1])
			
			print("[CLIENT] Auto-join test complete")
		else:
			print("[CLIENT] ✗ Auto-join is NOT enabled!")
	else:
		print("[CLIENT] ✗ MultiplayerLauncher not found!")
	
	# Manual connection test as fallback
	print("[CLIENT] Testing manual connection as fallback...")
	if GameModeManager:
		var manual_success = await GameModeManager.join_network_multiplayer("127.0.0.1", 8910, "Manual Client", "local")
		print("[CLIENT] Manual connection result: " + str(manual_success))
		
		if manual_success:
			print("[CLIENT] ✓ Manual connection successful!")
		else:
			print("[CLIENT] ✗ Manual connection failed!")
	else:
		print("[CLIENT] ✗ Cannot test manual connection - GameModeManager not found!")

# Helper function to print system status
func print_system_status() -> void:
	print("\n--- SYSTEM STATUS ---")
	print("GameModeManager: " + str(GameModeManager))
	print("MultiplayerLauncher: " + str(get_node_or_null("/root/MultiplayerLauncher")))
	print("NetworkManager: " + str(get_node_or_null("/root/NetworkManager")))
	
	if GameModeManager:
		print("Game Mode: " + str(GameModeManager.get_current_game_mode()))
		print("Is Active: " + str(GameModeManager.is_game_active()))
		print("Is Multiplayer: " + str(GameModeManager.is_multiplayer_active()))
	print("--- END STATUS ---\n")