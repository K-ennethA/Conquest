extends Node

# End-to-end test for the Host + Auto Client functionality

var test_step: int = 0
var host_started: bool = false

func _ready() -> void:
	print("=== END-TO-END MULTIPLAYER TEST ===")
	print("This test will:")
	print("1. Start a host")
	print("2. Launch a client instance")
	print("3. Verify connection")
	print("")
	print("Press F6 to start the test")
	print("Press F7 to clean up flag files")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F6:
			_start_end_to_end_test()
		elif event.keycode == KEY_F7:
			_cleanup_flag_files()

func _start_end_to_end_test() -> void:
	"""Start the complete end-to-end test"""
	print("\n=== STARTING END-TO-END TEST ===")
	test_step = 1
	
	# Step 1: Start host
	print("Step 1: Starting host...")
	_start_host()

func _start_host() -> void:
	"""Start the multiplayer host"""
	if not GameModeManager:
		print("✗ GameModeManager not available")
		return
	
	print("Starting network multiplayer host...")
	var success = await GameModeManager.start_network_multiplayer_host("Test Host", "local")
	
	if success:
		print("✓ Host started successfully")
		host_started = true
		test_step = 2
		
		# Wait a moment for host to be ready
		await get_tree().create_timer(2.0).timeout
		
		# Step 2: Launch client
		print("Step 2: Launching client instance...")
		_launch_client()
	else:
		print("✗ Host failed to start")

func _launch_client() -> void:
	"""Launch the client instance"""
	print("Creating client flag file and launching instance...")
	
	var success = AutoClientDetector.launch_client()
	
	if success:
		print("✓ Client instance launched")
		test_step = 3
		
		# Step 3: Monitor for connection
		print("Step 3: Monitoring for client connection...")
		_monitor_connection()
	else:
		print("✗ Client launch failed")

func _monitor_connection() -> void:
	"""Monitor for client connection"""
	print("Waiting for client to connect...")
	
	# Wait up to 10 seconds for connection
	var max_wait_time = 10.0
	var wait_time = 0.0
	var check_interval = 1.0
	
	while wait_time < max_wait_time:
		await get_tree().create_timer(check_interval).timeout
		wait_time += check_interval
		
		# Check if we have any connected peers
		var status = GameModeManager.get_game_status()
		var network_stats = status.get("network_stats", {})
		var connected_peers = network_stats.get("connected_peers", [])
		
		print("Connection check (%.1fs): %d peers connected" % [wait_time, connected_peers.size()])
		
		if connected_peers.size() > 0:
			print("✓ Client connected successfully!")
			print("✓ End-to-end test PASSED")
			return
	
	print("✗ Client did not connect within %d seconds" % max_wait_time)
	print("✗ End-to-end test FAILED")

func _cleanup_flag_files() -> void:
	"""Clean up any leftover flag files"""
	print("\n=== CLEANING UP FLAG FILES ===")
	
	var flag_files = [
		AutoClientDetector.CLIENT_FLAG_FILE,
		"user://client_instance.flag"  # Old flag file
	]
	
	for flag_file in flag_files:
		if FileAccess.file_exists(flag_file):
			var removed = DirAccess.remove_absolute(flag_file)
			if removed == OK:
				print("✓ Removed: " + flag_file)
			else:
				print("✗ Failed to remove: " + flag_file)
		else:
			print("- Not found: " + flag_file)
	
	print("Flag file cleanup complete")

func _exit_tree() -> void:
	"""Clean up when exiting"""
	if host_started and GameModeManager:
		GameModeManager.end_current_game()