extends Control

class_name MultiplayerModeSelection

# Multiplayer Mode Selection Menu
# Allows players to choose between local multiplayer and network multiplayer

@onready var local_multiplayer_button: Button = $CenterContainer/VBoxContainer/MultiplayerButtons/LocalMultiplayerButton
@onready var network_multiplayer_button: Button = $CenterContainer/VBoxContainer/MultiplayerButtons/NetworkMultiplayerButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var description_label: Label = $CenterContainer/VBoxContainer/DescriptionContainer/DescriptionLabel

# Mode descriptions
var mode_descriptions = {
	"LOCAL": "Hot-seat multiplayer on the same device. Players take turns using the same computer.",
	"NETWORK": "Online multiplayer. Play against friends over the internet or local network."
}

func _ready() -> void:
	# Connect button signals
	if local_multiplayer_button:
		local_multiplayer_button.pressed.connect(_on_local_multiplayer_pressed)
		local_multiplayer_button.mouse_entered.connect(func(): _update_description("LOCAL"))
	
	if network_multiplayer_button:
		network_multiplayer_button.pressed.connect(_on_network_multiplayer_pressed)
		network_multiplayer_button.mouse_entered.connect(func(): _update_description("NETWORK"))
	
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	# Set initial description
	_update_description("LOCAL")
	
	print("Multiplayer Mode Selection initialized")

func _on_local_multiplayer_pressed() -> void:
	"""Handle Local Multiplayer button press"""
	print("Local Multiplayer mode selected")
	
	# Set game mode to local multiplayer
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)  # Default to 2 players for local
	
	# Go to turn system selection
	get_tree().change_scene_to_file("res://menus/TurnSystemSelection.tscn")

func _on_network_multiplayer_pressed() -> void:
	"""Handle Network Multiplayer button press"""
	print("Network Multiplayer mode selected")
	
	# Go to network multiplayer setup
	get_tree().change_scene_to_file("res://menus/NetworkMultiplayerSetup.tscn")

func _on_back_pressed() -> void:
	"""Handle Back button press"""
	print("Returning to main menu")
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")

func _update_description(mode: String) -> void:
	"""Update the description text for the selected mode"""
	if description_label:
		description_label.text = mode_descriptions.get(mode, "No description available.")

# Handle input for quick navigation
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				_on_local_multiplayer_pressed()
			KEY_2:
				_on_network_multiplayer_pressed()
			KEY_ESCAPE:
				_on_back_pressed()