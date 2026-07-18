extends Node

class_name DirectClientDetector

# Direct client detector that shows clear visual feedback
# This will make it obvious when the client detection is working

const CLIENT_FLAG_FILE = "user://auto_client.flag"

func _ready() -> void:
	print("=== DIRECT CLIENT DETECTOR START ===")
	print("Checking for client flag file: " + CLIENT_FLAG_FILE)
	
	# Check if flag file exists
	if FileAccess.file_exists(CLIENT_FLAG_FILE):
		print("*** CLIENT FLAG FILE FOUND - THIS IS A CLIENT INSTANCE ***")
		_become_client()
	else:
		print("No client flag file found - this is a normal instance")
		print("=== DIRECT CLIENT DETECTOR END ===")

func _become_client() -> void:
	"""Transform this instance into a client"""
	print("[CLIENT] === BECOMING CLIENT INSTANCE ===")
	
	# Delete the flag file immediately
	var removed = DirAccess.remove_absolute(CLIENT_FLAG_FILE)
	print("[CLIENT] Flag file removal result: " + str(removed))
	
	# Change the window title to make it obvious
	get_window().title = "CONQUEST - CLIENT INSTANCE"
	
	# Hide the main menu UI
	var main_menu = get_tree().current_scene
	if main_menu:
		print("[CLIENT] Hiding main menu UI")
		main_menu.visible = false
		
		# Create a client status display
		var client_label = Label.new()
		client_label.text = "CLIENT INSTANCE\n\nConnecting to host...\nPlease wait..."
		client_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		client_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		client_label.add_theme_font_size_override("font_size", 24)
		client_label.anchors_preset = Control.PRESET_FULL_RECT
		
		main_menu.add_child(client_label)
	
	# Wait a moment for systems to initialize
	await get_tree().create_timer(2.0).timeout
	
	print("[CLIENT] Starting auto-join process...")
	_start_auto_join()

func _start_auto_join() -> void:
	"""Start the auto-join process"""
	print("[CLIENT] Setting up multiplayer settings...")
	
	# Set game settings
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)
	
	# Wait for GameModeManager
	if not GameModeManager:
		print("[CLIENT] ERROR: GameModeManager not found!")
		_show_error("GameModeManager not found!")
		return
	
	print("[CLIENT] GameModeManager found, attempting to join...")
	
	# Try to join the host
	var success = await GameModeManager.join_network_multiplayer(
		"127.0.0.1",
		8910,
		"Auto Client",
		"local"
	)
	
	print("[CLIENT] Join result: " + str(success))
	
	if success:
		print("[CLIENT] Successfully joined! Loading game...")
		_show_success("Connected! Loading game...")
		
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")
	else:
		print("[CLIENT] Failed to join host")
		_show_error("Failed to connect to host")

func _show_error(message: String) -> void:
	"""Show error message"""
	var main_menu = get_tree().current_scene
	if main_menu:
		var label = main_menu.get_node_or_null("Label")
		if label:
			label.text = "CLIENT INSTANCE\n\nERROR: " + message + "\n\nReturning to menu in 3 seconds..."
			label.modulate = Color.RED
	
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _show_success(message: String) -> void:
	"""Show success message"""
	var main_menu = get_tree().current_scene
	if main_menu:
		var label = main_menu.get_node_or_null("Label")
		if label:
			label.text = "CLIENT INSTANCE\n\n" + message
			label.modulate = Color.GREEN

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