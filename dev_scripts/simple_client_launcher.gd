extends Node

# Simple client launcher that uses file-based communication
# This bypasses the command line argument issues

const CLIENT_FLAG_FILE = "user://client_instance.flag"

func _ready() -> void:
	print("=== SIMPLE CLIENT LAUNCHER ===")
	
	# Check if this instance should be a client
	if FileAccess.file_exists(CLIENT_FLAG_FILE):
		print("[CLIENT] Client flag file found - this is a client instance!")
		_handle_client_instance()
	else:
		print("[HOST] No client flag file - this is a host instance")

func _handle_client_instance() -> void:
	"""Handle this instance as a client"""
	print("[CLIENT] Starting client auto-join process...")
	
	# Delete the flag file so future instances aren't clients
	DirAccess.remove_absolute(CLIENT_FLAG_FILE)
	
	# Wait for systems to initialize
	await get_tree().create_timer(2.0).timeout
	
	# Set up multiplayer settings
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
	
	print("[CLIENT] Attempting to join multiplayer game...")
	
	# Try to join the host
	if GameModeManager:
		var success = await GameModeManager.join_network_multiplayer(
			"127.0.0.1", 
			8910, 
			"Auto Client", 
			"local"
		)
		
		print("[CLIENT] Join result: " + str(success))
		
		if success:
			print("[CLIENT] Successfully joined! Loading game scene...")
			await get_tree().create_timer(1.0).timeout
			get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")
		else:
			print("[CLIENT] Failed to join - returning to main menu")
	else:
		print("[CLIENT] ERROR: GameModeManager not found!")

func launch_client_instance() -> void:
	"""Launch a client instance using file-based communication"""
	print("Launching client instance with file-based communication...")
	
	# Create the client flag file
	var file = FileAccess.open(CLIENT_FLAG_FILE, FileAccess.WRITE)
	if file:
		file.store_string("client")
		file.close()
		print("Client flag file created: " + CLIENT_FLAG_FILE)
	else:
		print("ERROR: Could not create client flag file")
		return
	
	# Launch the second instance
	var executable_path = OS.get_executable_path()
	var arguments = []
	
	if OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe"):
		# Editor mode
		var project_path = ProjectSettings.globalize_path("res://")
		arguments = ["--path", project_path]
	
	print("Launching client with executable: " + executable_path)
	print("Arguments: " + str(arguments))
	
	var pid = OS.create_process(executable_path, arguments)
	
	if pid > 0:
		print("Client instance launched with PID: " + str(pid))
	else:
		print("Failed to launch client instance")
		# Clean up flag file if launch failed
		DirAccess.remove_absolute(CLIENT_FLAG_FILE)