extends Control

class_name MultiplayerModeSelection

## Versus: choose Hot-Seat (both players on this device) or Network (each player on
## their own machine). Two explanatory cards; built in code, the .tscn is only the root.

var local_multiplayer_button: Button
var network_multiplayer_button: Button
var back_button: Button


func _ready() -> void:
	var page := MenuKit.build_page(self, ["Versus"], "Play Against a Friend",
		"Two human commanders. Choose where your opponent is sitting.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	center.add_child(row)

	local_multiplayer_button = MenuKit.choice_card("Hot-Seat", "Same device",
		"Both players share this computer and take turns at the controls. No setup needed -- just pass the keyboard or controller.",
		["2 players, 1 device", "Pick turn system, map and squads next"],
		MenuTheme.GOLD, null, Vector2(440, 320))
	local_multiplayer_button.name = "LocalMultiplayerButton"
	local_multiplayer_button.pressed.connect(_on_local_multiplayer_pressed)
	row.add_child(local_multiplayer_button)

	network_multiplayer_button = MenuKit.choice_card("Network", "LAN or internet",
		"Each player runs their own copy of Conquest. One player hosts a lobby, the other joins by IP address and port.",
		["2 players, 2 devices", "Host chooses the map and turn system"],
		MenuTheme.ACCENT, null, Vector2(440, 320))
	network_multiplayer_button.name = "NetworkMultiplayerButton"
	network_multiplayer_button.pressed.connect(_on_network_multiplayer_pressed)
	row.add_child(network_multiplayer_button)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)
	MenuKit.add_standard_hints(page.hints, "Choose")

	MenuNav.focus_deferred(local_multiplayer_button)


func _on_local_multiplayer_pressed() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)  # hot-seat is always two players
	MenuNav.change_scene(self, "res://menus/TurnSystemSelection.tscn")


func _on_network_multiplayer_pressed() -> void:
	MenuNav.change_scene(self, "res://menus/NetworkMultiplayerSetup.tscn")


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, "res://menus/MainMenu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_on_local_multiplayer_pressed()
			KEY_2:
				_on_network_multiplayer_pressed()
