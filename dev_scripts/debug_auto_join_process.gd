extends Node

# Comprehensive debug script for auto-join process
# Add this to MainMenu scene to debug the second instance

func _ready() -> void:
	print("=== AUTO-JOIN PROCESS DEBUG ===")
	print("Debug script started at: " + str(Time.get_ticks_msec()))
	
	# Step 1: Check command line arguments
	var args = OS.get_cmdline_args()
	print("Step 1: Command line arguments (" + str(args.size()) + " total):")
	for i in range(args.size()):
		print("  [" + str(i) + "]: '" + args[i] + "'")
	
	# Step 2: Check if auto-join arguments are present
	var has_auto_join = false
	var has_path = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			has_auto_join = true
		elif arg == "--path":
			has_path = true
	
	print("Step 2: Argument analysis:")
	print("  Has --path: " + str(has_path))
	print("  Has --multiplayer-auto-join: " + str(has_auto_join))
	
	if not has_auto_join:
		print("  -> This is NOT a client instance (no --multiplayer-auto-join)")
		print("=== END DEBUG (HOST INSTANCE) ===")
		return
	
	print("  -> This IS a client instance!")
	
	# Step 3: Check autoloads
	await get_tree().process_frame
	
	print("Step 3: Checking autoloads:")
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	var game_mode_manager = get_node_or_null("/root/GameModeManager")
	var game_settings = get_node_or_null("/root/GameSettings")
	
	print("  MultiplayerLauncher: " + str(launcher))
	print("  GameModeManager: " + str(game_mode_manager))
	print("  GameSettings: " + str(game_settings))
	
	if launcher:
		print("  MultiplayerLauncher.is_auto_join_enabled(): " + str(launcher.is_auto_join_enabled()))
		print("  MultiplayerLauncher.get_auto_join_info(): " + str(launcher.get_auto_join_info()))
	
	# Step 4: Monitor the auto-join process
	print("Step 4: Monitoring auto-join process for 10 seconds...")
	
	for i in range(10):
		await get_tree().create_timer(1.0).timeout
		print("  Second " + str(i + 1) + ":")
		
		if game_mode_manager:
			var status = game_mode_manager.get_game_status()
			print("    Game mode: " + str(status.get("game_mode", "unknown")))
			print("    Is active: " + str(status.get("is_active", false)))
			print("    Network status: " + str(status.get("network_status", "unknown")))
		else:
			print("    GameModeManager still not available")
		
		# Check current scene
		var current_scene = get_tree().current_scene
		if current_scene:
			print("    Current scene: " + current_scene.name + " (" + current_scene.scene_file_path + ")")
		else:
			print("    No current scene")
	
	print("=== END AUTO-JOIN PROCESS DEBUG ===")