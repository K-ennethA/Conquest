extends Node

# Auto Client Detector - Autoload version
# This runs immediately when the game starts, before any scenes load

const CLIENT_FLAG_FILE = "user://auto_client.flag"

func _ready() -> void:
	# Check if flag file exists
	if FileAccess.file_exists(CLIENT_FLAG_FILE):
		_become_client()

func _become_client() -> void:
	"""Transform this instance into a client"""
	print("[CLIENT] === BECOMING CLIENT INSTANCE ===")
	
	# Delete the flag file immediately
	var removed = DirAccess.remove_absolute(CLIENT_FLAG_FILE)
	print("[CLIENT] Flag file removal result: " + str(removed))
	
	# Change the window title to make it obvious
	get_window().title = "CONQUEST - CLIENT INSTANCE"
	
	# Wait for the scene tree to be ready
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Skip the main menu and go directly to auto-join
	print("[CLIENT] Bypassing main menu, starting auto-join process...")
	_start_auto_join()

func _start_auto_join() -> void:
	"""Start the auto-join process"""
	print("[CLIENT] Setting up multiplayer settings...")

	# Set game settings
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)

	# Wait a bit for the host process to finish opening its socket.
	await get_tree().create_timer(3.0).timeout

	# Drive the REAL join flow rather than a parallel one: open the network setup screen and
	# press its Connect for it. That screen runs on NetSession (the transport the battle's
	# command seam reads) and owns the connect state machine, the version handshake and the
	# collaborative lobby. The old shortcut here dialled a separate legacy stack, which left
	# NetSession's roster empty and the battle unshared.
	get_tree().change_scene_to_file("res://menus/NetworkMultiplayerSetup.tscn")

	# change_scene_to_file is deferred, so poll (bounded) for the new scene.
	var setup: Node = null
	for _frame in range(60):
		await get_tree().process_frame
		var current: Node = get_tree().current_scene
		if current != null and current.has_method("begin_auto_join"):
			setup = current
			break

	if setup != null:
		setup.begin_auto_join("127.0.0.1", 8910, "Auto Client")
	else:
		print("[CLIENT] ERROR: network setup screen never came up (no begin_auto_join)")
		_show_error("Failed to open the network setup screen")

func _show_error(message: String) -> void:
	"""Show error message and return to menu"""
	print("[CLIENT] ERROR: " + message)
	print("[CLIENT] Returning to main menu in 3 seconds...")
	
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

# Static method to create client flag file
static func create_client_flag() -> bool:
	"""Create the client flag file"""
	print("Creating client flag file...")
	
	var file = FileAccess.open(CLIENT_FLAG_FILE, FileAccess.WRITE)
	if file:
		file.store_string("client_instance")
		file.close()
		print("Client flag file created successfully: " + CLIENT_FLAG_FILE)
		return true
	else:
		print("ERROR: Failed to create client flag file")
		return false

# Static method to launch client
static func launch_client() -> bool:
	"""Launch a client instance"""
	print("=== LAUNCHING CLIENT INSTANCE ===")
	
	# Create flag file first
	if not create_client_flag():
		return false
	
	# Get executable path
	var executable_path = OS.get_executable_path()
	print("Executable: " + executable_path)
	
	var arguments = []
	
	# Handle editor vs export
	if OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe"):
		var project_path = ProjectSettings.globalize_path("res://")
		arguments = ["--path", project_path]
		print("Editor mode - using project path: " + project_path)
	else:
		print("Export mode - no additional arguments needed")
	
	print("Launch arguments: " + str(arguments))
	
	# Launch the process
	var pid = OS.create_process(executable_path, arguments)
	
	if pid > 0:
		print("Client instance launched successfully with PID: " + str(pid))
		return true
	else:
		print("ERROR: Failed to launch client instance")
		# Clean up flag file
		DirAccess.remove_absolute(CLIENT_FLAG_FILE)
		return false