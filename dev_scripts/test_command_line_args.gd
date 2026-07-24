extends Node

# Test script to verify command line arguments are being passed correctly
# Add this to MainMenu scene temporarily to debug

func _ready() -> void:
	print("=== COMMAND LINE ARGS TEST ===")
	
	var args = OS.get_cmdline_args()
	print("Total arguments: " + str(args.size()))
	
	if args.size() == 0:
		print("No command line arguments found!")
		return
	
	print("All arguments:")
	for i in range(args.size()):
		print("  [" + str(i) + "]: '" + args[i] + "'")
	
	# Test the exact parsing logic from MultiplayerLauncher
	var auto_join_enabled = false
	var auto_join_address = "127.0.0.1"
	var auto_join_port = 8910
	var auto_join_player_name = "Auto Client"
	
	for i in range(args.size()):
		var arg = args[i]
		print("Processing arg[" + str(i) + "]: '" + arg + "'")
		
		match arg:
			"--multiplayer-auto-join":
				auto_join_enabled = true
				print("  -> Auto-join enabled!")
			
			"--multiplayer-address":
				if i + 1 < args.size():
					auto_join_address = args[i + 1]
					print("  -> Address set to: " + auto_join_address)
			
			"--multiplayer-port":
				if i + 1 < args.size():
					auto_join_port = int(args[i + 1])
					print("  -> Port set to: " + str(auto_join_port))
			
			"--multiplayer-player-name":
				if i + 1 < args.size():
					auto_join_player_name = args[i + 1]
					print("  -> Player name set to: " + auto_join_player_name)
		
		# Also check for combined format (--key=value)
		if arg.begins_with("--multiplayer-address="):
			auto_join_address = arg.split("=")[1]
			print("  -> Address (combined) set to: " + auto_join_address)
		elif arg.begins_with("--multiplayer-port="):
			auto_join_port = int(arg.split("=")[1])
			print("  -> Port (combined) set to: " + str(auto_join_port))
		elif arg.begins_with("--multiplayer-player-name="):
			auto_join_player_name = arg.split("=")[1]
			print("  -> Player name (combined) set to: " + auto_join_player_name)
	
	print("Final parsed values:")
	print("  Auto-join enabled: " + str(auto_join_enabled))
	print("  Address: " + auto_join_address)
	print("  Port: " + str(auto_join_port))
	print("  Player name: " + auto_join_player_name)
	
	# Check MultiplayerLauncher
	if MultiplayerLauncher:
		print("MultiplayerLauncher found!")
		print("  is_auto_join_enabled(): " + str(MultiplayerLauncher.is_auto_join_enabled()))
		var info = MultiplayerLauncher.get_auto_join_info()
		print("  get_auto_join_info(): " + str(info))
	else:
		print("ERROR: MultiplayerLauncher not found!")
	
	print("=== END COMMAND LINE ARGS TEST ===")