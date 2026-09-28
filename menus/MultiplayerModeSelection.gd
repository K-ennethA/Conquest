extends Control

class_name MultiplayerModeSelection

## Versus mode picker, reached from MainMenu's "Versus" button: Hot-Seat (both players
## on this device), Siege (hot-seat push mode on a lane/base map) and Network (each
## player on their own machine). Grove menu look (MenuKit / MenuTheme choice cards);
## built in code, the .tscn is only the root.
##
## Hot-Seat and Siege hand off to the unified MatchSetup (map + turn system + squads);
## Network opens NetworkMultiplayerSetup (host / join, then the collaborative lobby).
##
## Keyboard: 1 = Hot-Seat, 2 = Siege, 3 = Network, Esc / B = back.
##
## LOOK-DEPENDENT: only the page chrome and the three cards (MenuKit.choice_card) --
## the handlers below are the content and stay as they are under any skin.

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const NETWORK_SETUP_SCENE := "res://menus/NetworkMultiplayerSetup.tscn"

var local_multiplayer_button: Button
var local_siege_button: Button
var network_multiplayer_button: Button
var back_button: Button


func _ready() -> void:
	var page := MenuKit.build_page(self, ["Versus"], "Play Against a Friend",
		"Two human commanders. Choose where your opponent is sitting.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	center.add_child(row)

	# 720p: three 360-wide cards + two SP_L gaps fit the page body with room to spare.
	var card_size := Vector2(360, 320)
	local_multiplayer_button = MenuKit.choice_card("Hot-Seat", "Same device",
		"Both players share this computer and take turns at the controls. No setup needed -- just pass the keyboard or controller.",
		["2 players, 1 device", "Pick map, turn system and squads next"],
		MenuTheme.GOLD, null, card_size)
	local_multiplayer_button.name = "LocalMultiplayerButton"
	local_multiplayer_button.pressed.connect(_on_local_multiplayer_pressed)
	row.add_child(local_multiplayer_button)

	local_siege_button = MenuKit.choice_card("Siege", "Same device, push mode",
		"Hot-seat on a lane map: creeps march, towers hold, and each side tries to break the other's base.",
		["2 players, 1 device", "Lane / base map preselected"],
		MenuTheme.TEAM_RED, null, card_size)
	local_siege_button.name = "LocalSiegeButton"
	local_siege_button.pressed.connect(_on_local_siege_pressed)
	row.add_child(local_siege_button)

	network_multiplayer_button = MenuKit.choice_card("Network", "LAN or internet",
		"Each player runs their own copy of Conquest. One player hosts a lobby (or both join a dedicated server); the other joins by address and port.",
		["2 players, 2 devices", "Vote on the map, bring your squad"],
		MenuTheme.ACCENT, null, card_size)
	network_multiplayer_button.name = "NetworkMultiplayerButton"
	network_multiplayer_button.pressed.connect(_on_network_multiplayer_pressed)
	row.add_child(network_multiplayer_button)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)

	MenuKit.add_standard_hints(page.hints, "Choose")
	var hint := MenuKit.label("1 Hot-Seat  •  2 Siege  •  3 Network  •  Esc back", &"MutedLabel")
	hint.name = "KeyHint"
	page.hints.add_child(hint)

	MenuNav.focus_deferred(local_multiplayer_button)


func _on_local_multiplayer_pressed() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)  # hot-seat is always two players
	# The unified Match Setup (local hot-seat variant: map + turn system + squads).
	MatchSetup.requested_mode = MatchConfigPanel.MODE_LOCAL
	MenuNav.change_scene(self, MATCH_SETUP_SCENE)


## Local hot-seat SIEGE. Same plumbing as Hot-Seat -- two players on one box -- with the
## siege variant of the setup screen, which preselects the lane/base map.
func _on_local_siege_pressed() -> void:
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)
	MatchSetup.requested_mode = MatchConfigPanel.MODE_SIEGE_LOCAL
	MenuNav.change_scene(self, MATCH_SETUP_SCENE)


func _on_network_multiplayer_pressed() -> void:
	MenuNav.change_scene(self, NETWORK_SETUP_SCENE)


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, MAIN_MENU_SCENE)


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
				_on_local_siege_pressed()
			KEY_3:
				_on_network_multiplayer_pressed()
