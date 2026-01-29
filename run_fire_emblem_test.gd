extends SceneTree

# Script to run the Fire Emblem overlay test
# Usage: godot --script run_fire_emblem_test.gd

func _init():
	print("=== Running Fire Emblem Overlay Movement Test ===")
	
	# Load the GameWorld scene
	var game_world_scene = load("res://game/world/GameWorld.tscn")
	if not game_world_scene:
		print("ERROR: Could not load GameWorld scene")
		quit(1)
		return
	
	print("GameWorld scene loaded successfully")
	
	# Instantiate and set as current scene
	var game_world = game_world_scene.instantiate()
	current_scene = game_world
	
	print("GameWorld scene instantiated and set as current scene")
	print("The FireEmblemOverlayTest node should run automatically")
	print("Press F6-F9 for manual tests, or wait for automatic test")
	
	# Let the scene run for a while to see the test results
	await create_timer(15.0).timeout
	
	print("=== Test completed - exiting ===")
	quit(0)