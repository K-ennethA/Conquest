extends Control

class_name MainMenu

# Main menu for the tactical combat game
# Provides game mode selection (Single Player vs Versus)

@onready var single_player_button: Button = $CenterContainer/VBoxContainer/MenuButtons/SinglePlayerButton
@onready var versus_button: Button = $CenterContainer/VBoxContainer/MenuButtons/VersusButton
# One entry point for the whole in-game reference. The Unit, Tile and Map
# galleries are no longer separate menu items -- they are sections of
# Compendium.tscn, which also covers Statuses (and, later, Weather).
@onready var compendium_button: Button = $CenterContainer/VBoxContainer/MenuButtons/CompendiumButton
@onready var arena_button: Button = $CenterContainer/VBoxContainer/MenuButtons/ArenaButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/MenuButtons/QuitButton

func _ready() -> void:
	print("[DEBUG] MainMenu: _ready() called")
	theme = MenuTheme.build()  # dark Legends-style menu look
	
	# Arriving at the main menu always ends any network match: close the session
	# and restore local play, so single-player / hotseat afterwards starts clean.
	if GameModeManager:
		GameModeManager.end_network_session()
		var net_msg: String = GameModeManager.consume_menu_message()
		if net_msg != "":
			_show_status_message(net_msg)

	# Connect button signals for normal menu operation
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
	if compendium_button:
		compendium_button.pressed.connect(_on_compendium_pressed)
	if arena_button:
		arena_button.pressed.connect(_on_arena_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	print("Main Menu initialized")

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

func _on_compendium_pressed() -> void:
	"""Handle Compendium button press"""
	print("Compendium selected")
	get_tree().change_scene_to_file("res://menus/Compendium.tscn")

func _on_arena_pressed() -> void:
	"""Handle Arena button press -- open the Arena pre-run setup screen"""
	print("Arena mode selected")
	# Setup screen lets the player pick run length + turn system before ArenaController
	# starts the run (it, not this menu, launches the actual GameWorld round).
	get_tree().change_scene_to_file("res://game/arena/ui/ArenaSetupScreen.tscn")

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
				_on_compendium_pressed()
			KEY_4:
				_on_arena_pressed()
			KEY_ESCAPE:
				_on_quit_pressed()