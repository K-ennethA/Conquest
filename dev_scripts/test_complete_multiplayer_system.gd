extends Node

# Comprehensive test for the complete multiplayer system

func _ready() -> void:
	print("=== COMPLETE MULTIPLAYER SYSTEM TEST ===")
	
	# Test 1: Check all required autoloads
	print("\nTest 1: Autoload availability")
	_test_autoloads()
	
	# Test 2: Check AutoClientDetector
	print("\nTest 2: AutoClientDetector functionality")
	_test_client_detector()
	
	# Test 3: Check NetworkManager
	print("\nTest 3: NetworkManager functionality")
	_test_network_manager()
	
	# Test 4: Check GameModeManager
	print("\nTest 4: GameModeManager functionality")
	_test_game_mode_manager()
	
	print("\n=== COMPLETE MULTIPLAYER SYSTEM TEST COMPLETE ===")
	
	# Auto-remove after 5 seconds
	await get_tree().create_timer(5.0).timeout
	queue_free()

func _test_autoloads() -> void:
	"""Test that all required autoloads are available"""
	var autoloads = [
		"GameSettings",
		"GameModeManager", 
		"PlayerManager",
		"TurnSystemManager",
		"GameEvents"
	]
	
	for autoload_name in autoloads:
		var autoload = get_node_or_null("/root/" + autoload_name)
		if autoload:
			print("✓ " + autoload_name + " is available")
		else:
			print("✗ " + autoload_name + " is NOT available")

func _test_client_detector() -> void:
	"""Test AutoClientDetector functionality"""
	# Test class availability
	if AutoClientDetector:
		print("✓ AutoClientDetector autoload is available")
	else:
		print("✗ AutoClientDetector autoload is NOT available")
		return
	
	# Test flag file operations
	var flag_file = AutoClientDetector.CLIENT_FLAG_FILE
	print("Flag file path: " + flag_file)
	
	# Test creation
	var created = AutoClientDetector.create_client_flag()
	if created and FileAccess.file_exists(flag_file):
		print("✓ Flag file creation works")
		
		# Test cleanup
		var removed = DirAccess.remove_absolute(flag_file)
		if removed == OK:
			print("✓ Flag file cleanup works")
		else:
			print("✗ Flag file cleanup failed")
	else:
		print("✗ Flag file creation failed")

func _test_network_manager() -> void:
	"""Test NetworkManager functionality"""
	# Create a test NetworkManager
	var network_manager = NetworkManager.new()
	if network_manager:
		print("✓ NetworkManager can be created")
		
		# Test initialization
		network_manager.initialize_backends()
		if network_manager._is_initialized:
			print("✓ NetworkManager initializes successfully")
		else:
			print("✗ NetworkManager initialization failed")
		
		network_manager.queue_free()
	else:
		print("✗ NetworkManager creation failed")

func _test_game_mode_manager() -> void:
	"""Test GameModeManager functionality"""
	if GameModeManager:
		print("✓ GameModeManager autoload is available")
		
		# Test basic methods
		if GameModeManager.has_method("get_current_game_mode"):
			print("✓ GameModeManager has get_current_game_mode method")
		else:
			print("✗ GameModeManager missing get_current_game_mode method")
		
		if GameModeManager.has_method("join_network_multiplayer"):
			print("✓ GameModeManager has join_network_multiplayer method")
		else:
			print("✗ GameModeManager missing join_network_multiplayer method")
		
		if GameModeManager.has_method("start_network_multiplayer_host"):
			print("✓ GameModeManager has start_network_multiplayer_host method")
		else:
			print("✗ GameModeManager missing start_network_multiplayer_host method")
	else:
		print("✗ GameModeManager autoload is NOT available")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			# Run the complete test again
			_ready()