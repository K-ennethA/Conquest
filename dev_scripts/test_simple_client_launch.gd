extends Node

# Test script for the simple client launch approach
# Run this to test the file-based client detection

func _ready() -> void:
	print("=== SIMPLE CLIENT LAUNCH TEST ===")
	
	# Test creating and detecting the client flag file
	await test_flag_file_system()
	
	# Test launching a client instance
	await test_client_launch()
	
	print("=== END SIMPLE CLIENT LAUNCH TEST ===")

func test_flag_file_system() -> void:
	print("\n--- Testing Flag File System ---")
	
	const CLIENT_FLAG_FILE = "user://client_instance.flag"
	
	# Test creating flag file
	var file = FileAccess.open(CLIENT_FLAG_FILE, FileAccess.WRITE)
	if file:
		file.store_string("client")
		file.close()
		print("✓ Flag file created successfully")
	else:
		print("✗ Failed to create flag file")
		return
	
	# Test detecting flag file
	if FileAccess.file_exists(CLIENT_FLAG_FILE):
		print("✓ Flag file detected successfully")
	else:
		print("✗ Flag file not detected")
		return
	
	# Test removing flag file
	DirAccess.remove_absolute(CLIENT_FLAG_FILE)
	if not FileAccess.file_exists(CLIENT_FLAG_FILE):
		print("✓ Flag file removed successfully")
	else:
		print("✗ Flag file not removed")

func test_client_launch() -> void:
	print("\n--- Testing Client Launch ---")
	
	# Create a simple client launcher
	var launcher = Node.new()
	launcher.set_script(load("res://simple_client_launcher.gd"))
	add_child(launcher)
	
	print("Simple client launcher created")
	print("You can now test launching a client by calling launcher.launch_client_instance()")
	
	# Don't actually launch in test - just show it's ready
	print("Test complete - launcher ready for use")

# Add manual test trigger
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F8:
			print("F8 pressed - Running simple client launch test...")
			_ready()