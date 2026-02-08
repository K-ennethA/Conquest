extends Node

# Test script to verify the client detection system is working properly

func _ready() -> void:
	print("=== CLIENT DETECTION SYSTEM TEST ===")
	
	# Test 1: Check if DirectClientDetector class is available
	print("Test 1: DirectClientDetector class availability")
	var detector = DirectClientDetector.new()
	if detector:
		print("✓ DirectClientDetector class is available")
		detector.queue_free()
	else:
		print("✗ DirectClientDetector class is NOT available")
		return
	
	# Test 2: Check flag file creation
	print("\nTest 2: Flag file creation")
	var success = DirectClientDetector.create_client_flag()
	if success:
		print("✓ Flag file created successfully")
		
		# Check if file exists
		if FileAccess.file_exists(DirectClientDetector.CLIENT_FLAG_FILE):
			print("✓ Flag file exists at: " + DirectClientDetector.CLIENT_FLAG_FILE)
			
			# Clean up
			DirAccess.remove_absolute(DirectClientDetector.CLIENT_FLAG_FILE)
			print("✓ Flag file cleaned up")
		else:
			print("✗ Flag file was not created")
	else:
		print("✗ Flag file creation failed")
	
	# Test 3: Check executable path detection
	print("\nTest 3: Executable path detection")
	var executable_path = OS.get_executable_path()
	print("Executable path: " + executable_path)
	
	if OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe"):
		print("✓ Running in editor mode")
		var project_path = ProjectSettings.globalize_path("res://")
		print("Project path: " + project_path)
	else:
		print("✓ Running in export mode")
	
	# Test 4: Check GameModeManager availability
	print("\nTest 4: GameModeManager availability")
	if GameModeManager:
		print("✓ GameModeManager is available: " + str(GameModeManager))
	else:
		print("✗ GameModeManager is NOT available")
	
	print("\n=== CLIENT DETECTION SYSTEM TEST COMPLETE ===")
	
	# Auto-remove this test script after 3 seconds
	await get_tree().create_timer(3.0).timeout
	queue_free()