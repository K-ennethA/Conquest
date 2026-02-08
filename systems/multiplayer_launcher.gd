extends Node

# Multiplayer Launcher
# Handles command line arguments for automatic multiplayer joining

var auto_join_enabled: bool = false
var auto_join_address: String = "127.0.0.1"
var auto_join_port: int = 8910
var auto_join_player_name: String = "Auto Client"

func _ready() -> void:
	name = "MultiplayerLauncher"
	
	print("[DEBUG] MultiplayerLauncher: _ready() called")
	print("[DEBUG] Command line args: " + str(OS.get_cmdline_args()))
	
	# Parse command line arguments immediately
	_parse_command_line_args()
	
	print("[DEBUG] Auto-join enabled after parsing: " + str(auto_join_enabled))
	
	# If auto-join is enabled, start the process immediately
	if auto_join_enabled:
		print("[CLIENT] Auto-join enabled, will connect to %s:%d as %s" % [auto_join_address, auto_join_port, auto_join_player_name])
		
		# Start auto-join process immediately, don't wait
		_start_auto_join_process()
	else:
		print("[SINGLE] Auto-join NOT enabled - running as normal instance")

func _start_auto_join_process() -> void:
	"""Start the auto-join process immediately"""
	print("[CLIENT] Starting auto-join process...")
	
	# Use call_deferred to ensure we're not blocking the _ready chain
	call_deferred("_auto_join_multiplayer")

func _parse_command_line_args() -> void:
	"""Parse command line arguments for multiplayer auto-join"""
	var args = OS.get_cmdline_args()
	
	print("[DEBUG] Parsing command line arguments: " + str(args))
	
	# Reset values
	auto_join_enabled = false
	auto_join_address = "127.0.0.1"
	auto_join_port = 8910
	auto_join_player_name = "Auto Client"
	
	for i in range(args.size()):
		var arg = args[i]
		
		# Handle both separate and combined argument formats
		if arg == "--multiplayer-auto-join":
			auto_join_enabled = true
			print("[DEBUG] Auto-join enabled via command line")
		
		elif arg == "--multiplayer-address":
			if i + 1 < args.size():
				auto_join_address = args[i + 1]
				print("[DEBUG] Auto-join address set to: " + auto_join_address)
		elif arg.begins_with("--multiplayer-address="):
			auto_join_address = arg.split("=")[1]
			print("[DEBUG] Auto-join address (combined) set to: " + auto_join_address)
		
		elif arg == "--multiplayer-port":
			if i + 1 < args.size():
				auto_join_port = int(args[i + 1])
				print("[DEBUG] Auto-join port set to: " + str(auto_join_port))
		elif arg.begins_with("--multiplayer-port="):
			auto_join_port = int(arg.split("=")[1])
			print("[DEBUG] Auto-join port (combined) set to: " + str(auto_join_port))
		
		elif arg == "--multiplayer-player-name":
			if i + 1 < args.size():
				auto_join_player_name = args[i + 1]
				print("[DEBUG] Auto-join player name set to: " + auto_join_player_name)
		elif arg.begins_with("--multiplayer-player-name="):
			auto_join_player_name = arg.split("=")[1]
			print("[DEBUG] Auto-join player name (combined) set to: " + auto_join_player_name)
	
	print("[DEBUG] Final auto-join settings:")
	print("[DEBUG]   Enabled: " + str(auto_join_enabled))
	print("[DEBUG]   Address: " + auto_join_address)
	print("[DEBUG]   Port: " + str(auto_join_port))
	print("[DEBUG]   Player name: " + auto_join_player_name)

func force_auto_join() -> void:
	"""Manually force auto-join process (for debugging)"""
	print("[DEBUG] force_auto_join() called")
	auto_join_enabled = true
	_start_auto_join_process()

func _auto_join_multiplayer() -> void:
	"""Automatically join a multiplayer game"""
	print("[CLIENT] === AUTO-JOIN MULTIPLAYER START ===")
	print("[CLIENT] Auto-joining multiplayer game...")
	
	# Skip the main menu and go directly to network setup
	# Set game settings for multiplayer
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
	
	print("[CLIENT] Game settings configured for multiplayer")
	
	# Wait for GameModeManager to be ready
	await get_tree().process_frame
	
	print("[CLIENT] Attempting to join %s:%d as %s" % [auto_join_address, auto_join_port, auto_join_player_name])
	
	# Ensure GameModeManager is available
	if not GameModeManager:
		print("[CLIENT] ERROR: GameModeManager not available!")
		print("[CLIENT] Available autoloads:")
		for child in get_tree().root.get_children():
			if child.name.begins_with("Game") or child.name.begins_with("Multiplayer"):
				print("[CLIENT]   - " + child.name + ": " + str(child))
		get_tree().change_scene_to_file("res://menus/MainMenu.tscn")
		return
	
	print("[CLIENT] GameModeManager found: " + str(GameModeManager))
	
	# Wait a bit more for systems to initialize and for host to be ready
	print("[CLIENT] Waiting for host to be ready...")
	await get_tree().create_timer(2.0).timeout
	
	# Try to join multiple times with delays (host might not be ready immediately)
	var max_attempts = 3
	var success = false
	
	for attempt in range(max_attempts):
		print("[CLIENT] Join attempt " + str(attempt + 1) + " of " + str(max_attempts))
		
		success = await GameModeManager.join_network_multiplayer(
			auto_join_address, 
			auto_join_port, 
			auto_join_player_name, 
			"local"
		)
		
		print("[CLIENT] Attempt " + str(attempt + 1) + " result: " + str(success))
		
		if success:
			break
		
		if attempt < max_attempts - 1:
			print("[CLIENT] Join failed, waiting 2 seconds before retry...")
			await get_tree().create_timer(2.0).timeout
	
	if success:
		print("[CLIENT] Auto-join successful! Starting game...")
		
		# Wait a moment then load the game scene
		await get_tree().create_timer(1.0).timeout
		print("[CLIENT] Loading game scene...")
		get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")
	else:
		print("[CLIENT] Auto-join failed after " + str(max_attempts) + " attempts")
		print("[CLIENT] Showing main menu")
		get_tree().change_scene_to_file("res://menus/MainMenu.tscn")
	
	print("[CLIENT] === AUTO-JOIN MULTIPLAYER END ===")

func is_auto_join_enabled() -> bool:
	"""Check if auto-join is enabled"""
	return auto_join_enabled

func get_auto_join_info() -> Dictionary:
	"""Get auto-join connection info"""
	return {
		"enabled": auto_join_enabled,
		"address": auto_join_address,
		"port": auto_join_port,
		"player_name": auto_join_player_name
	}