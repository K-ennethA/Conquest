extends Node

# Debug script to test what happens in the second instance
# Add this to the main scene to see if the second instance is getting the right arguments

func _ready() -> void:
	print("=== SECOND INSTANCE DEBUG ===")
	print("Instance started at: " + str(Time.get_ticks_msec()))
	
	# Check command line arguments
	var args = OS.get_cmdline_args()
	print("All command line arguments (" + str(args.size()) + "):")
	for i in range(args.size()):
		print("  [" + str(i) + "]: " + args[i])
	
	# Check for auto-join flag specifically
	var has_auto_join = false
	var has_path = false
	var address = ""
	var port = ""
	var player_name = ""
	
	for i in range(args.size()):
		var arg = args[i]
		if arg == "--multiplayer-auto-join":
			has_auto_join = true
		elif arg == "--path":
			has_path = true
		elif arg.begins_with("--multiplayer-address="):
			address = arg.split("=")[1]
		elif arg.begins_with("--multiplayer-port="):
			port = arg.split("=")[1]
		elif arg.begins_with("--multiplayer-player-name="):
			player_name = arg.split("=")[1]
	
	print("Parsed arguments:")
	print("  Has --path: " + str(has_path))
	print("  Has --multiplayer-auto-join: " + str(has_auto_join))
	print("  Address: " + address)
	print("  Port: " + port)
	print("  Player name: " + player_name)
	
	# Check if MultiplayerLauncher exists and is working
	await get_tree().create_timer(0.5).timeout
	
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	if launcher:
		print("MultiplayerLauncher found: " + str(launcher))
		print("Auto-join enabled: " + str(launcher.is_auto_join_enabled()))
		var info = launcher.get_auto_join_info()
		print("Auto-join info: " + str(info))
	else:
		print("ERROR: MultiplayerLauncher not found in autoloads!")
	
	# Check GameModeManager
	if GameModeManager:
		print("GameModeManager found: " + str(GameModeManager))
		print("Current game mode: " + str(GameModeManager.get_current_game_mode()))
	else:
		print("ERROR: GameModeManager not found!")
	
	# Monitor for a few seconds to see what happens
	for i in range(5):
		await get_tree().create_timer(1.0).timeout
		print("Second " + str(i + 1) + " - Still alive")
		
		if GameModeManager:
			var status = GameModeManager.get_game_status()
			print("  Game mode: " + str(status.get("game_mode", "unknown")))
			print("  Is active: " + str(status.get("is_active", false)))
			print("  Network status: " + str(status.get("network_status", "unknown")))
	
	print("=== END SECOND INSTANCE DEBUG ===")