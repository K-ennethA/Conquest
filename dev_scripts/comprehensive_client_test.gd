extends Node

# Comprehensive test to diagnose client auto-join issues
# Add this to any scene to test the client launch process

func _ready() -> void:
	print("=== COMPREHENSIVE CLIENT TEST ===")
	
	# Test 1: Check if we can detect client arguments
	await test_argument_detection()
	
	# Test 2: Test MultiplayerLauncher functionality
	await test_multiplayer_launcher()
	
	# Test 3: Test manual client launch
	await test_manual_launch()
	
	print("=== END COMPREHENSIVE CLIENT TEST ===")

func test_argument_detection() -> void:
	print("\n--- TEST 1: Argument Detection ---")
	
	var args = OS.get_cmdline_args()
	print("Command line arguments: " + str(args))
	
	var has_auto_join = false
	var has_path = false
	
	for arg in args:
		if arg == "--multiplayer-auto-join":
			has_auto_join = true
		elif arg == "--path":
			has_path = true
	
	print("Has --path: " + str(has_path))
	print("Has --multiplayer-auto-join: " + str(has_auto_join))
	
	if has_auto_join:
		print("✓ This instance should be a client")
	else:
		print("✗ This instance is not a client")

func test_multiplayer_launcher() -> void:
	print("\n--- TEST 2: MultiplayerLauncher Test ---")
	
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	if not launcher:
		print("✗ MultiplayerLauncher not found!")
		return
	
	print("✓ MultiplayerLauncher found: " + str(launcher))
	print("Auto-join enabled: " + str(launcher.is_auto_join_enabled()))
	print("Auto-join info: " + str(launcher.get_auto_join_info()))
	
	# Test manual parsing
	print("Testing manual argument parsing...")
	launcher._parse_command_line_args()
	print("After manual parsing - enabled: " + str(launcher.is_auto_join_enabled()))
	
	# If still not enabled, try to force it
	var args = OS.get_cmdline_args()
	var should_be_client = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			should_be_client = true
			break
	
	if should_be_client and not launcher.is_auto_join_enabled():
		print("Forcing auto-join for testing...")
		launcher.force_auto_join()

func test_manual_launch() -> void:
	print("\n--- TEST 3: Manual Launch Test ---")
	
	# Only test launching if we're not already a client
	var args = OS.get_cmdline_args()
	var is_client = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			is_client = true
			break
	
	if is_client:
		print("This is already a client instance - skipping launch test")
		return
	
	print("Testing client launch process...")
	
	var executable_path = OS.get_executable_path()
	print("Executable: " + executable_path)
	
	var is_editor = OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe")
	print("Is editor: " + str(is_editor))
	
	var launch_args = []
	
	if is_editor:
		var project_path = ProjectSettings.globalize_path("res://")
		launch_args = [
			"--path", project_path,
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=8910",
			"--multiplayer-player-name=Test Client"
		]
	else:
		launch_args = [
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=8910",
			"--multiplayer-player-name=Test Client"
		]
	
	print("Would launch with args: " + str(launch_args))
	
	# Actually launch for testing
	print("Launching test client...")
	var pid = OS.create_process(executable_path, launch_args)
	
	if pid > 0:
		print("✓ Test client launched with PID: " + str(pid))
	else:
		print("✗ Failed to launch test client")

# Add input handler for manual testing
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				print("F1 pressed - Running comprehensive test...")
				_ready()
			KEY_F2:
				print("F2 pressed - Testing MultiplayerLauncher...")
				test_multiplayer_launcher()
			KEY_F3:
				print("F3 pressed - Testing manual launch...")
				test_manual_launch()