extends Control

class_name MainMenu

# Main menu for the tactical combat game
# Provides game mode selection (Single Player vs Versus)

@onready var single_player_button: Button = $CenterContainer/VBoxContainer/MenuButtons/SinglePlayerButton
@onready var versus_button: Button = $CenterContainer/VBoxContainer/MenuButtons/VersusButton
@onready var unit_gallery_button: Button = $CenterContainer/VBoxContainer/MenuButtons/UnitGalleryButton
@onready var tile_gallery_button: Button = $CenterContainer/VBoxContainer/MenuButtons/TileGalleryButton
@onready var multiplayer_button: Button = $CenterContainer/VBoxContainer/MenuButtons/MultiplayerButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/MenuButtons/QuitButton

func _ready() -> void:
	print("[DEBUG] MainMenu: _ready() called")
	
	# Add AutoClientDetector test
	var autoclient_test = Node.new()
	autoclient_test.name = "AutoClientDetectorTest"
	autoclient_test.set_script(load("res://test_autoclient_detector.gd"))
	add_child(autoclient_test)
	
	# Add debug test script for development
	var debug_test = Node.new()
	debug_test.name = "HostAutoClientDebugTest"
	debug_test.set_script(load("res://test_host_auto_client_debug.gd"))
	add_child(debug_test)
	
	# Add end-to-end test script
	var e2e_test = Node.new()
	e2e_test.name = "EndToEndMultiplayerTest"
	e2e_test.set_script(load("res://test_end_to_end_multiplayer.gd"))
	add_child(e2e_test)
	
	# Note: AutoClientDetector now runs as an autoload, so client detection
	# happens before this scene loads. If we reach here, we're not a client.
	print("[SINGLE] MainMenu: Setting up normal menu")
	
	# Connect button signals for normal menu operation
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
	if unit_gallery_button:
		unit_gallery_button.pressed.connect(_on_unit_gallery_pressed)
	if tile_gallery_button:
		tile_gallery_button.pressed.connect(_on_tile_gallery_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	print("Main Menu initialized")

func _show_auto_join_status() -> void:
	"""Show auto-join connection status"""
	# Hide menu buttons
	if single_player_button:
		single_player_button.visible = false
	if versus_button:
		versus_button.visible = false
	if quit_button:
		quit_button.visible = false
	
	# Show connection status
	var info = MultiplayerLauncher.get_auto_join_info()
	var status_text = "Auto-joining multiplayer game...\nConnecting to %s:%d as %s" % [info.address, info.port, info.player_name]
	
	_show_status_message(status_text)

func _show_status_message(message: String) -> void:
	"""Show a status message on the main menu"""
	# Create a status label if it doesn't exist
	var status_label = get_node_or_null("CenterContainer/VBoxContainer/StatusLabel")
	if not status_label:
		status_label = Label.new()
		status_label.name = "StatusLabel"
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		
		var container = get_node("CenterContainer/VBoxContainer")
		if container:
			container.add_child(status_label)
	
	if status_label:
		status_label.text = message
		status_label.visible = true

func _on_single_player_pressed() -> void:
	"""Handle Single Player button press"""
	print("Single Player mode selected")
	
	# Set up single player mode
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)  # Single player vs AI
	
	# Go directly to turn system selection
	get_tree().change_scene_to_file("res://menus/TurnSystemSelection.tscn")

func _on_versus_pressed() -> void:
	"""Handle Versus button press"""
	print("Versus mode selected - opening multiplayer mode selection")
	
	# Load multiplayer mode selection scene (restored)
	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")

func _on_unit_gallery_pressed() -> void:
	"""Handle Unit Gallery button press"""
	print("Unit Gallery selected")
	get_tree().change_scene_to_file("res://menus/UnitGallery.tscn")

func _on_tile_gallery_pressed() -> void:
	"""Handle Tile Gallery button press"""
	print("Tile Gallery selected")
	get_tree().change_scene_to_file("res://menus/TileGallery.tscn")

func _on_quit_pressed() -> void:
	"""Handle Quit button press"""
	print("Quitting game")
	get_tree().quit()

func _show_not_implemented_message(message: String) -> void:
	"""Show a temporary message for unimplemented features"""
	# Create a simple popup
	var dialog = AcceptDialog.new()
	dialog.dialog_text = message
	dialog.title = "Not Implemented"
	add_child(dialog)
	dialog.popup_centered()
	
	# Remove dialog after it's closed
	dialog.confirmed.connect(func(): dialog.queue_free())

# Handle input for quick navigation
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_single_player_pressed()
			KEY_2:
				_on_versus_pressed()
			KEY_3:
				_on_unit_gallery_pressed()
			KEY_4:
				_on_tile_gallery_pressed()
			KEY_ESCAPE:
				_on_quit_pressed()