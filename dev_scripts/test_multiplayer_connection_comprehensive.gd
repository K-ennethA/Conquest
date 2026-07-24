extends Node

# Comprehensive multiplayer connection test
# This script will test both host and client connection processes

func _ready() -> void:
	print("=== COMPREHENSIVE MULTIPLAYER CONNECTION TEST ===")
	
	# Check command line arguments first
	var args = OS.get_cmdline_args()
	print("Command line arguments: " + str(args))
	
	var is_auto_join = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			is_auto_join = true
			break
	
	if is_auto_join:
		print("[CLIENT] This is a CLIENT instance (auto-join enabled)")
		await test_client_connection()
	else:
		print("[HOST] This is a HOST instance")
		await test_host_connection()

func test_host_connection() -> void:
	"""Test host connection process"""
	print("[HOST] === TESTING HOST CONNECTION ===")
	
	# Check GameModeManager
	if not GameModeManager:
		print("[HOST] ERROR: GameModeManager not found!")
		return
	
	print("[HOST] GameModeManager found: " + str(GameModeManager))
	
	# Start hosting
	print("[HOST] Starting network multiplayer host...")
	var success = await GameModeManager.start_network_multiplayer_host("Test Host", "local")
	
	print("[HOST] Host start result: " + str(success))
	
	if success:
		print("[HOST] Host started successfully!")
		
		# Get status
		var status = GameModeManager.get_game_status()
		print("[HOST] Game status: " + str(status))
		
		# Wait for client to connect
		print("[HOST] Waiting for client connection...")
		await get_tree().create_timer(10.0).timeout
		
		# Check final status
		var final_status = GameModeManager.get_game_status()
		print("[HOST] Final status: " + str(final_status))
	else:
		print("[HOST] Host failed to start!")

func test_client_connection() -> void:
	"""Test client connection process"""
	print("[CLIENT] === TESTING CLIENT CONNECTION ===")
	
	# Wait for systems to initialize
	await get_tree().create_timer(1.0).timeout
	
	# Check GameModeManager
	if not GameModeManager:
		print("[CLIENT] ERROR: GameModeManager not found!")
		return
	
	print("[CLIENT] GameModeManager found: " + str(GameModeManager))
	
	# Check MultiplayerLauncher
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	if launcher:
		print("[CLIENT] MultiplayerLauncher found: " + str(launcher))
		var auto_join_info = launcher.get_auto_join_info()
		print("[CLIENT] Auto-join info: " + str(auto_join_info))
		
		if auto_join_info.enabled:
			print("[CLIENT] Auto-join is enabled, waiting for it to complete...")
			await get_tree().create_timer(5.0).timeout
			
			# Check connection status
			var status = GameModeManager.get_game_status()
			print("[CLIENT] Connection status: " + str(status))
		else:
			print("[CLIENT] Auto-join is NOT enabled!")
	else:
		print("[CLIENT] ERROR: MultiplayerLauncher not found!")
	
	# Manual connection test
	print("[CLIENT] Testing manual connection...")
	var success = await GameModeManager.join_network_multiplayer("127.0.0.1", 8910, "Test Client", "local")
	
	print("[CLIENT] Manual connection result: " + str(success))
	
	if success:
		print("[CLIENT] Client connected successfully!")
		
		# Get status
		var status = GameModeManager.get_game_status()
		print("[CLIENT] Game status: " + str(status))
	else:
		print("[CLIENT] Client failed to connect!")