extends Node

# Simple test to verify AutoClientDetector is working

func _ready() -> void:
	print("=== AUTOCLIENT DETECTOR TEST ===")
	
	# Test 1: Check if AutoClientDetector autoload exists
	if AutoClientDetector:
		print("✓ AutoClientDetector autoload is available")
	else:
		print("✗ AutoClientDetector autoload is NOT available")
		return
	
	# Test 2: Test flag file creation
	print("\nTesting flag file creation...")
	var success = AutoClientDetector.create_client_flag()
	if success:
		print("✓ Flag file created successfully")
		
		# Check if it exists
		if FileAccess.file_exists(AutoClientDetector.CLIENT_FLAG_FILE):
			print("✓ Flag file exists at: " + AutoClientDetector.CLIENT_FLAG_FILE)
			
			# Clean up
			var removed = DirAccess.remove_absolute(AutoClientDetector.CLIENT_FLAG_FILE)
			if removed == OK:
				print("✓ Flag file cleaned up successfully")
			else:
				print("✗ Failed to clean up flag file")
		else:
			print("✗ Flag file was not created")
	else:
		print("✗ Flag file creation failed")
	
	print("\n=== AUTOCLIENT DETECTOR TEST COMPLETE ===")
	
	# Auto-remove after 3 seconds
	await get_tree().create_timer(3.0).timeout
	queue_free()