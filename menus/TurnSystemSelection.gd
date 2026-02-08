extends Control

class_name TurnSystemSelection

# Turn System Selection Menu
# Allows players to choose which turn system to use for versus mode

@onready var traditional_button: Button = $CenterContainer/VBoxContainer/TurnSystemButtons/TraditionalButton
@onready var initiative_button: Button = $CenterContainer/VBoxContainer/TurnSystemButtons/InitiativeButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

# Turn system descriptions
var turn_system_descriptions = {
	"TRADITIONAL": "Player-based turns. All units of one player act before switching to the next player.",
	"INITIATIVE": "Speed-based turns. Units act in order based on their speed stats, fastest first."
}

var selected_turn_system: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL

func _ready() -> void:
	# Connect button signals
	if traditional_button:
		traditional_button.pressed.connect(_on_traditional_pressed)
	if initiative_button:
		initiative_button.pressed.connect(_on_initiative_pressed)
	# Hide unused buttons
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Set initial selection
	_update_button_states()
	_update_description()
	
	print("Turn System Selection initialized")

func _on_traditional_pressed() -> void:
	"""Handle Traditional Turn System selection"""
	selected_turn_system = TurnSystemBase.TurnSystemType.TRADITIONAL
	_update_button_states()
	_update_description()
	_start_game_with_turn_system()

func _on_initiative_pressed() -> void:
	"""Handle Initiative Turn System selection"""
	selected_turn_system = TurnSystemBase.TurnSystemType.INITIATIVE
	_update_button_states()
	_update_description()
	_start_game_with_turn_system()

func _on_simultaneous_pressed() -> void:
	"""Handle Simultaneous Turn System selection - REMOVED"""
	pass

func _on_real_time_pressed() -> void:
	"""Handle Real-Time Turn System selection - REMOVED"""
	pass

func _on_back_pressed() -> void:
	"""Handle Back button press"""
	print("Returning to main menu")
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _update_button_states() -> void:
	"""Update button visual states based on selection"""
	# Reset all buttons
	if traditional_button:
		traditional_button.modulate = Color.WHITE
	if initiative_button:
		initiative_button.modulate = Color.WHITE
	
	# Highlight selected button
	match selected_turn_system:
		TurnSystemBase.TurnSystemType.TRADITIONAL:
			if traditional_button:
				traditional_button.modulate = Color.LIGHT_BLUE
		TurnSystemBase.TurnSystemType.INITIATIVE:
			if initiative_button:
				initiative_button.modulate = Color.LIGHT_BLUE

func _update_description() -> void:
	"""Update the description text for the selected turn system"""
	var description_label = $CenterContainer/VBoxContainer/DescriptionContainer/DescriptionLabel
	if description_label:
		var system_key = TurnSystemBase.TurnSystemType.keys()[selected_turn_system]
		description_label.text = turn_system_descriptions.get(system_key, "No description available.")

func _start_game_with_turn_system() -> void:
	"""Start the game with the selected turn system"""
	print("Starting game with turn system: " + TurnSystemBase.TurnSystemType.keys()[selected_turn_system])
	
	# Store the selected turn system for the game to use
	GameSettings.selected_turn_system = selected_turn_system
	GameSettings.game_mode = GameSettings.GameMode.VERSUS
	
	# Go to map selection instead of directly to game
	get_tree().change_scene_to_file("res://menus/MapSelection.tscn")

func _show_not_implemented_message(system_name: String) -> void:
	"""Show a message for unimplemented turn systems"""
	var dialog = AcceptDialog.new()
	dialog.dialog_text = system_name + " is not yet implemented.\n\nOnly Traditional Turn System is currently available."
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
				_on_traditional_pressed()
			KEY_2:
				_on_initiative_pressed()
			KEY_ESCAPE:
				_on_back_pressed()