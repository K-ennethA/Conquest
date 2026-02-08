extends SceneTree

# Test runner for collaborative lobby tests
# Run from command line: godot --path . --script tests/run_collaborative_lobby_tests.gd

func _init():
	print("=== Running Collaborative Lobby Tests ===\n")
	
	# Load GUT
	var gut = load("res://addons/gut/gut.gd").new()
	root.add_child(gut)
	
	# Configure GUT
	gut.add_directory("res://tests/unit/")
	gut.include_subdirectories = false
	
	# Run tests
	gut.test_scripts([
		"res://tests/unit/test_collaborative_lobby.gd",
		"res://tests/unit/test_map_selector_panel.gd"
	])
	
	# Wait for tests to complete
	await gut.tests_finished
	
	# Print results
	print("\n=== Test Results ===")
	print("Tests Run: " + str(gut.get_test_count()))
	print("Passed: " + str(gut.get_pass_count()))
	print("Failed: " + str(gut.get_fail_count()))
	print("Pending: " + str(gut.get_pending_count()))
	
	# Exit with appropriate code
	var exit_code = 0 if gut.get_fail_count() == 0 else 1
	get_root().propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	quit(exit_code)
