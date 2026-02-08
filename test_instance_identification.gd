extends Node

# Test script to identify which instance this is and verify dual instance setup

func _ready():
	# Wait a moment for systems to initialize
	await get_tree().create_timer(1.0).timeout
	
	print("=== INSTANCE IDENTIFICATION TEST ===")
	print("Process ID: " + str(OS.get_process_id()))
	print("Command line args: " + str(OS.get_cmdline_args()))
	
	# Check if this is an auto-join client
	if MultiplayerLauncher and MultiplayerLauncher.is_auto_join_enabled():
		print("*** THIS IS THE AUTO-JOIN CLIENT INSTANCE ***")
		var info = MultiplayerLauncher.get_auto_join_info()
		print("Auto-join info: " + str(info))
	else:
		print("*** THIS IS THE HOST INSTANCE ***")
	
	# Check multiplayer status
	if GameModeManager:
		print("GameModeManager available: true")
		if GameModeManager.is_multiplayer_active():
			print("Multiplayer active: true")
			print("Local player ID: " + str(GameModeManager.get_local_player_id()))
			
			var game_manager = GameModeManager._game_manager
			if game_manager and game_manager._network_handler:
				print("Network handler available: true")
				print("Is host: " + str(game_manager._network_handler.is_host()))
				print("Connection status: " + str(game_manager._network_handler.get_connection_status()))
			else:
				print("Network handler available: false")
		else:
			print("Multiplayer active: false")
	else:
		print("GameModeManager available: false")
	
	print("=== END INSTANCE IDENTIFICATION ===")
	
	# Set up a timer to periodically identify this instance
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.timeout.connect(_periodic_identification)
	timer.autostart = true
	add_child(timer)

func _periodic_identification():
	var instance_type = "HOST"
	if MultiplayerLauncher and MultiplayerLauncher.is_auto_join_enabled():
		instance_type = "CLIENT"
	
	print("[%s] Instance %d is alive - %s" % [instance_type, OS.get_process_id(), Time.get_datetime_string_from_system()])
	
	# Also check network status
	if GameModeManager and GameModeManager.is_multiplayer_active():
		var game_manager = GameModeManager._game_manager
		if game_manager and game_manager._network_handler:
			var status = game_manager._network_handler.get_connection_status()
			print("[%s] Network status: %s" % [instance_type, status])