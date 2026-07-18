extends Node

# Test script to debug client launch issues
# This will help us verify if the client instance is starting correctly

func _ready() -> void:
	print("=== CLIENT LAUNCH DEBUG TEST ===")
	
	# Check if we're the client instance
	var args = OS.get_cmdline_args()
	print("Command line arguments: " + str(args))
	
	var is_client = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			is_client = true
			break
	
	if is_client:
		print("*** THIS IS A CLIENT INSTANCE ***")
		print("Client instance started successfully!")
		
		# Check MultiplayerLauncher
		await get_tree().create_timer(0.5).timeout
		var launcher = get_node_or_null("/root/MultiplayerLauncher")
		if launcher:
			print("MultiplayerLauncher found: " + str(launcher))
			print("Auto-join info: " + str(launcher.get_auto_join_info()))
		else:
			print("ERROR: MultiplayerLauncher not found!")
		
		# Monitor for 10 seconds
		for i in range(10):
			await get_tree().create_timer(1.0).timeout
			print("Client instance alive - second %d" % (i + 1))
			
			if GameModeManager:
				var status = GameModeManager.get_game_status()
				print("  Game status: " + str(status.get("game_mode", "unknown")))
				print("  Is active: " + str(status.get("is_active", false)))
	else:
		print("*** THIS IS THE HOST INSTANCE ***")
		print("Host instance - not a client")
	
	print("=== END CLIENT LAUNCH DEBUG ===")