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
# Arena is no longer a top-level sibling: it lives under Solo -> Arena Run now.
@onready var map_creator_button: Button = $CenterContainer/VBoxContainer/MenuButtons/MapCreatorButton
@onready var quit_button: Button = $CenterContainer/VBoxContainer/MenuButtons/QuitButton

# Dev-only multiplayer test harnesses. These attach three dev_scripts/ nodes that each
# print a multi-line banner on _ready (and one writes a client-flag file), so they spam
# the console on EVERY normal launch. Off by default -- flip to true only when debugging
# the multiplayer auto-client/host handshake.
const ENABLE_DEV_TEST_HARNESS := false

func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	_style_chrome()

	if ENABLE_DEV_TEST_HARNESS:
		_attach_dev_test_harness()

	# Note: AutoClientDetector now runs as an autoload, so client detection
	# happens before this scene loads. If we reach here, we're not a client.
	# Connect button signals for normal menu operation
	if single_player_button:
		single_player_button.pressed.connect(_on_single_player_pressed)
		single_player_button.tooltip_text = "Solo play: Skirmish vs the AI, or an Arena roguelite run."
	if versus_button:
		versus_button.pressed.connect(_on_versus_pressed)
		versus_button.tooltip_text = "Face another player: local hot-seat or online."
	if compendium_button:
		compendium_button.pressed.connect(_on_compendium_pressed)
		compendium_button.tooltip_text = "Browse every unit, tile, status and map."
	if map_creator_button:
		map_creator_button.pressed.connect(_on_map_creator_pressed)
		map_creator_button.tooltip_text = "Build custom maps (early version)"
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)

func _style_chrome() -> void:
	"""Apply the shared gold-title / dim-caption treatment to the static labels."""
	MenuTheme.style_title(get_node_or_null("CenterContainer/VBoxContainer/Title") as Label, 40)
	MenuTheme.style_subtitle(get_node_or_null("CenterContainer/VBoxContainer/Subtitle") as Label)
	MenuTheme.style_caption(get_node_or_null("CenterContainer/VBoxContainer/Instructions") as Label)

func _attach_dev_test_harness() -> void:
	"""Attach the dev_scripts/ multiplayer test nodes. Gated behind ENABLE_DEV_TEST_HARNESS
	because each spams a banner on _ready (and test_autoclient_detector writes a client-flag
	file). Only for hands-on multiplayer handshake debugging."""
	var autoclient_test := Node.new()
	autoclient_test.name = "AutoClientDetectorTest"
	autoclient_test.set_script(load("res://dev_scripts/test_autoclient_detector.gd"))
	add_child(autoclient_test)

	var debug_test := Node.new()
	debug_test.name = "HostAutoClientDebugTest"
	debug_test.set_script(load("res://dev_scripts/test_host_auto_client_debug.gd"))
	add_child(debug_test)

	var e2e_test := Node.new()
	e2e_test.name = "EndToEndMultiplayerTest"
	e2e_test.set_script(load("res://dev_scripts/test_end_to_end_multiplayer.gd"))
	add_child(e2e_test)

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
	"""Handle Solo button press -- open the Solo mode picker (Skirmish / Arena Run)."""

	# Set up single player mode; the mode picker + Match Setup refine it from here.
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	GameSettings.set_player_count(1)  # Single player vs AI

	get_tree().change_scene_to_file("res://menus/SoloModeSelect.tscn")

func _on_versus_pressed() -> void:
	"""Handle Versus button press"""

	# Load multiplayer mode selection scene (restored)
	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")

func _on_compendium_pressed() -> void:
	"""Handle Compendium button press"""
	get_tree().change_scene_to_file("res://menus/Compendium.tscn")

func _on_map_creator_pressed() -> void:
	"""Handle Map Creator button press -- open the custom-map editor (early version)."""
	get_tree().change_scene_to_file("res://game/mapmaker/MapMakerScene.tscn")

func _on_quit_pressed() -> void:
	"""Handle Quit button press"""
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
				_on_map_creator_pressed()
			KEY_ESCAPE:
				_on_quit_pressed()