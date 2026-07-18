extends Node

# Step-by-step multiplayer test
# This will test each component individually

func _ready() -> void:
	print("=== STEP-BY-STEP MULTIPLAYER TEST ===")
	
	# Step 1: Check autoloads
	await test_autoloads()
	
	# Step 2: Check NetworkManager
	await test_network_manager()
	
	# Step 3: Check GameModeManager
	await test_game_mode_manager()
	
	# Step 4: Test host creation
	await test_host_creation()
	
	print("=== TEST COMPLETE ===")

func test_autoloads() -> void:
	print("\n--- STEP 1: Testing Autoloads ---")
	
	var autoloads = [
		"GameEvents", "ResourceManager", "PlayerManager", 
		"TurnSystemManager", "GameSettings", "BattleEffectsManager",
		"GameModeManager", "MultiplayerLauncher"
	]
	
	for autoload_name in autoloads:
		var node = get_node_or_null("/root/" + autoload_name)
		if node:
			print("✓ " + autoload_name + " found: " + str(node))
		else:
			print("✗ " + autoload_name + " NOT FOUND!")
	
	await get_tree().process_frame

func test_network_manager() -> void:
	print("\n--- STEP 2: Testing NetworkManager ---")
	
	# Create NetworkManager manually if needed
	var network_manager = get_node_or_null("/root/NetworkManager")
	if not network_manager:
		print("Creating NetworkManager...")
		network_manager = NetworkManager.new()
		network_manager.name = "NetworkManager"
		get_tree().root.add_child(network_manager)
		await get_tree().process_frame
	
	print("NetworkManager: " + str(network_manager))
	print("Is initialized: " + str(network_manager._is_initialized))
	print("Current mode: " + str(network_manager.get_network_mode()))
	print("Backend info: " + str(network_manager.get_backend_info()))

func test_game_mode_manager() -> void:
	print("\n--- STEP 3: Testing GameModeManager ---")
	
	var gmm = GameModeManager
	if gmm:
		print("GameModeManager: " + str(gmm))
		print("Current game mode: " + str(gmm.get_current_game_mode()))
		print("Is game active: " + str(gmm.is_game_active()))
		print("Is multiplayer active: " + str(gmm.is_multiplayer_active()))
	else:
		print("ERROR: GameModeManager not found!")

func test_host_creation() -> void:
	print("\n--- STEP 4: Testing Host Creation ---")
	
	var gmm = GameModeManager
	if not gmm:
		print("ERROR: Cannot test host - GameModeManager not found!")
		return
	
	print("Starting network multiplayer host...")
	var success = await gmm.start_network_multiplayer_host("Test Host", "local")
	
	print("Host creation result: " + str(success))
	
	if success:
		print("Host started successfully!")
		var status = gmm.get_game_status()
		print("Game status: " + str(status))
		
		var connection_info = gmm._network_handler.get_connection_info() if gmm._network_handler else {}
		print("Connection info: " + str(connection_info))
	else:
		print("Host creation failed!")