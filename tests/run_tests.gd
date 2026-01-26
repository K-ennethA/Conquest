extends SceneTree

# Command line test runner for CI/CD integration
# Usage: godot --headless --script tests/run_tests.gd

func _init():
	print("Starting GUT test runner...")
	
	var gut = preload("res://addons/gut/gut.gd").new()
	
	# Configure GUT
	gut.add_directory("res://tests/unit")
	gut.add_directory("res://tests/integration")
	gut.set_log_level(gut.LOG_LEVEL_ALL_ASSERTS)
	gut.set_yield_between_tests(true)
	gut.set_export_path("res://tests/results/")
	
	# Connect to test completion
	gut.tests_finished.connect(_on_tests_finished)
	
	# Add to scene and run
	get_root().add_child(gut)
	gut.test_scripts()

func _on_tests_finished():
	print("Tests completed!")
	quit()