extends Node

# Debug script to test the Host + Auto Client functionality

func _ready() -> void:
	print("=== HOST + AUTO CLIENT DEBUG TEST ===")
	
	# Add the test to the scene
	var main_menu = get_tree().current_scene
	if main_menu and main_menu.name == "MainMenu":
		print("✓ Running from MainMenu scene")
		
		# Add a test button
		var test_button = Button.new()
		test_button.text = "TEST: Host + Auto Client"
		test_button.position = Vector2(10, 10)
		test_button.size = Vector2(200, 40)
		test_button.pressed.connect(_test_host_auto_client)
		
		main_menu.add_child(test_button)
		print("✓ Test button added to MainMenu")
	else:
		print("✗ Not running from MainMenu scene")
		queue_free()

func _test_host_auto_client() -> void:
	"""Test the host + auto client functionality"""
	print("\n=== TESTING HOST + AUTO CLIENT ===")
	
	# Step 1: Create flag file
	print("Step 1: Creating client flag file...")
	var success = AutoClientDetector.create_client_flag()
	print("Flag file creation result: " + str(success))
	
	if success:
		# Step 2: Launch client instance
		print("Step 2: Launching client instance...")
		var launch_success = AutoClientDetector.launch_client()
		print("Client launch result: " + str(launch_success))
		
		if launch_success:
			print("✓ Client instance should be launching now")
			print("✓ Check console for client instance output")
		else:
			print("✗ Client launch failed")
	else:
		print("✗ Flag file creation failed")
	
	print("=== HOST + AUTO CLIENT TEST COMPLETE ===")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F1:
			_test_host_auto_client()
		elif event.keycode == KEY_F2:
			# Test flag file detection
			print("\n=== TESTING FLAG FILE DETECTION ===")
			if FileAccess.file_exists(AutoClientDetector.CLIENT_FLAG_FILE):
				print("✓ Flag file exists: " + AutoClientDetector.CLIENT_FLAG_FILE)
			else:
				print("✗ Flag file does not exist")
		elif event.keycode == KEY_F3:
			# Clean up flag file
			print("\n=== CLEANING UP FLAG FILE ===")
			var removed = DirAccess.remove_absolute(AutoClientDetector.CLIENT_FLAG_FILE)
			print("Flag file removal result: " + str(removed))