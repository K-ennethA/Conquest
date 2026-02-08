extends Control

# Temporary debug version of MainMenu to diagnose auto-join issues
# Replace the script on MainMenu.tscn with this temporarily

func _ready() -> void:
	print("=== MAIN MENU DEBUG START ===")
	print("MainMenu _ready() called at: " + str(Time.get_ticks_msec()))
	
	# Check command line arguments immediately
	var args = OS.get_cmdline_args()
	print("Command line arguments (" + str(args.size()) + " total):")
	for i in range(args.size()):
		print("  [" + str(i) + "]: '" + args[i] + "'")
	
	# Check for auto-join flag
	var has_auto_join = false
	for arg in args:
		if arg == "--multiplayer-auto-join":
			has_auto_join = true
			break
	
	print("Has --multiplayer-auto-join flag: " + str(has_auto_join))
	
	if has_auto_join:
		print("*** THIS IS A CLIENT INSTANCE ***")
		_handle_client_instance()
	else:
		print("*** THIS IS A HOST INSTANCE ***")
		_handle_host_instance()
	
	print("=== MAIN MENU DEBUG END ===")

func _handle_client_instance():
	print("[CLIENT] Handling client instance...")
	
	# Check if MultiplayerLauncher exists
	var launcher = get_node_or_null("/root/MultiplayerLauncher")
	print("[CLIENT] MultiplayerLauncher found: " + str(launcher != null))
	
	if launcher:
		print("[CLIENT] MultiplayerLauncher.is_auto_join_enabled(): " + str(launcher.is_auto_join_enabled()))
		print("[CLIENT] MultiplayerLauncher.get_auto_join_info(): " + str(launcher.get_auto_join_info()))
		
		# If auto-join is not enabled, manually trigger it
		if not launcher.is_auto_join_enabled():
			print("[CLIENT] Auto-join not enabled, manually parsing arguments...")
			launcher._parse_command_line_args()
			print("[CLIENT] After manual parsing - is_auto_join_enabled(): " + str(launcher.is_auto_join_enabled()))
			
			if launcher.is_auto_join_enabled():
				print("[CLIENT] Manually triggering auto-join...")
				launcher._auto_join_multiplayer()
	else:
		print("[CLIENT] ERROR: MultiplayerLauncher not found!")
		print("[CLIENT] Available autoloads:")
		for child in get_tree().root.get_children():
			print("[CLIENT]   - " + child.name + ": " + str(child))
	
	# Hide menu buttons for client
	var buttons = get_node_or_null("CenterContainer/VBoxContainer/MenuButtons")
	if buttons:
		buttons.visible = false
	
	# Show client status
	var label = Label.new()
	label.text = "CLIENT INSTANCE\nAttempting to join multiplayer game..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)

func _handle_host_instance():
	print("[SINGLE] Handling host/normal instance...")
	
	# Set up normal menu buttons
	var single_player_button = get_node_or_null("CenterContainer/VBoxContainer/MenuButtons/SinglePlayerButton")
	var versus_button = get_node_or_null("CenterContainer/VBoxContainer/MenuButtons/VersusButton")
	var quit_button = get_node_or_null("CenterContainer/VBoxContainer/MenuButtons/QuitButton")
	
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _on_single_player_pressed() -> void:
	print("Single Player mode selected")
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)
	get_tree().change_scene_to_file("res://menus/TurnSystemSelection.tscn")

func _on_versus_pressed() -> void:
	print("Versus mode selected - opening multiplayer mode selection")
	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")

func _on_quit_pressed() -> void:
	print("Quitting game")
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_single_player_pressed()
			KEY_2:
				_on_versus_pressed()
			KEY_ESCAPE:
				_on_quit_pressed()