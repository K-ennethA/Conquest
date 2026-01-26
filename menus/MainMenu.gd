extends Control

class_name MainMenu

# Main menu for the tactical combat game
# Provides game mode selection (Single Player vs Versus)

@onready var single_player_button: Button = $CenterContainer/VBoxContainer/MenuButtons/SinglePlayerButton
@onready var versus_button: Button = $CenterContainer/VBoxContainer/MenuButtons/VersusButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/MenuButtons/QuitButton

func _ready() -> void:
	# Connect button signals
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)
	
	print("Main Menu initialized")

func _on_single_player_pressed() -> void:
	"""Handle Single Player button press"""
	print("Single Player mode selected (not implemented yet)")
	
	# TODO: Implement single player mode
	# For now, show a message
	_show_not_implemented_message("Single Player mode is not yet implemented.")

func _on_versus_pressed() -> void:
	"""Handle Versus button press"""
	print("Versus mode selected - opening turn system selection")
	
	# Load turn system selection scene
	get_tree().change_scene_to_file("res://menus/TurnSystemSelection.tscn")

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
			KEY_ESCAPE:
				_on_quit_pressed()