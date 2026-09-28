extends Control

class_name MultiplayerModeSelection

## The VERSUS screen (Online > Versus, docs/design/DECISIONS.md #32): two human players, two
## choices.
##
##   MODE   Conquest -- the tactical map battle (today's versus)
##          Duel     -- one on one, no movement, just the moves (a [DuelBattle])
##   WHERE  Network      -- each player on their own machine: [NetworkMultiplayerSetup] (host /
##                          join / a dedicated server), then the lobby -- the mode rides the
##                          join handshake, so a Duel joiner only ever lands in a Duel lobby
##          Same device  -- hot-seat: Conquest opens the local [MatchSetup] (MODE_LOCAL: map +
##                          turn system + squads); Duel opens [DuelSetup] with two human sides
##
## Flow: pick a mode card (it stays selected -- gold frame), then a where card to go. Built in
## code (grove look: MenuKit choice cards), the .tscn is only the root.
## Keys: 1 Conquest, 2 Duel, 3 Network, 4 Same device, Esc / pad B back to Online.
##
## (Hot-seat Siege is no longer offered; the solo-vs-AI duel left the menu -- DECISIONS.md #31.)

const ONLINE_SCENE := "res://menus/OnlineHub.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const NETWORK_SETUP_SCENE := "res://menus/NetworkMultiplayerSetup.tscn"
const DUEL_SETUP_SCENE := "res://menus/DuelSetup.tscn"

const MODE_CONQUEST := NetProtocol.MODE_CONQUEST
const MODE_DUEL := NetProtocol.MODE_DUEL

## The mode the screen opens on (remembered across visits in this session).
static var last_mode: String = NetProtocol.MODE_CONQUEST

## 720p: two rows of two 500-wide cards (one-line bodies, ~160 tall) + the two captions fit
## the ~480px page body; 2 x 500 + 24 = 1024 fits the 1180 page.
const CARD_SIZE := Vector2(500, 130)

var conquest_button: Button
var duel_button: Button
var network_multiplayer_button: Button
## Same device (hot-seat). Name kept from the two-card screen.
var local_multiplayer_button: Button
var back_button: Button
var selected_mode: String = NetProtocol.MODE_CONQUEST

var _mode_group := ButtonGroup.new()
var _where_caption: Label


func _ready() -> void:
	var page := MenuKit.build_page(self, ["Online"], "Versus",
		"Two players. Choose what to play, then where your opponent is.")

	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var col := VBoxContainer.new()
	col.name = "Choices"
	col.add_theme_constant_override("separation", MenuTheme.SP_S)
	center.add_child(col)

	col.add_child(MenuKit.section("1  ·  Mode"))
	var modes := HBoxContainer.new()
	modes.name = "ModeCards"
	modes.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(modes)
	conquest_button = _mode_card("Conquest", "Map battle",
		"Squads on a battlefield: move, flank, capture.", MenuTheme.GOLD, MODE_CONQUEST)
	conquest_button.name = "ConquestCard"
	modes.add_child(conquest_button)
	duel_button = _mode_card("Duel", "One on one",
		"One unit each, no movement -- just the moves.", MenuTheme.EL_EARTH, MODE_DUEL)
	duel_button.name = "DuelCard"
	modes.add_child(duel_button)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	col.add_child(gap)
	_where_caption = MenuKit.section("2  ·  Where is your opponent?")
	_where_caption.name = "WhereCaption"
	col.add_child(_where_caption)
	var wheres := HBoxContainer.new()
	wheres.name = "WhereCards"
	wheres.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(wheres)
	network_multiplayer_button = MenuKit.choice_card("Network", "LAN or internet",
		"Host, join by address, or meet on a dedicated server.",
		[], MenuTheme.ACCENT, null, CARD_SIZE)
	network_multiplayer_button.name = "NetworkMultiplayerButton"
	network_multiplayer_button.tooltip_text = "Network  (3)"
	network_multiplayer_button.pressed.connect(_on_network_multiplayer_pressed)
	wheres.add_child(network_multiplayer_button)
	local_multiplayer_button = MenuKit.choice_card("Same device", "Hot-seat",
		"Share this screen and take turns at the controls.",
		[], MenuTheme.EL_NATURE, null, CARD_SIZE)
	local_multiplayer_button.name = "LocalMultiplayerButton"
	local_multiplayer_button.tooltip_text = "Same device  (4)"
	local_multiplayer_button.pressed.connect(_on_local_multiplayer_pressed)
	wheres.add_child(local_multiplayer_button)

	# Up / Down moves between the rows; Left / Right within a row.
	conquest_button.focus_neighbor_bottom = conquest_button.get_path_to(network_multiplayer_button)
	duel_button.focus_neighbor_bottom = duel_button.get_path_to(local_multiplayer_button)
	network_multiplayer_button.focus_neighbor_top = network_multiplayer_button.get_path_to(conquest_button)
	local_multiplayer_button.focus_neighbor_top = local_multiplayer_button.get_path_to(duel_button)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)

	MenuKit.add_standard_hints(page.hints, "Choose")
	var hint := MenuKit.label("1 Conquest  •  2 Duel  •  3 Network  •  4 Same device", &"MutedLabel")
	hint.name = "KeyHint"
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	page.hints.add_child(hint)

	select_mode(last_mode if last_mode in NetProtocol.MODES else MODE_CONQUEST)
	MenuNav.focus_deferred(duel_button if selected_mode == MODE_DUEL else conquest_button)


func _mode_card(title: String, tagline: String, body: String, accent: Color, mode: String) -> Button:
	var b := MenuKit.choice_card(title, tagline, body, [], accent, null, CARD_SIZE)
	b.toggle_mode = true
	b.button_group = _mode_group
	b.tooltip_text = "%s  (%d)" % [title, 1 if mode == MODE_CONQUEST else 2]
	b.pressed.connect(_on_mode_card_pressed.bind(mode))
	return b


## Select [param mode] (Conquest / Duel): its card shows selected and the where row names it.
func select_mode(mode: String) -> void:
	selected_mode = mode if mode in NetProtocol.MODES else MODE_CONQUEST
	last_mode = selected_mode
	for card in [conquest_button, duel_button]:
		if card != null:
			(card as Button).set_pressed_no_signal(card == (duel_button if selected_mode == MODE_DUEL else conquest_button))
	if _where_caption != null:
		_where_caption.text = ("2  ·  Where is your opponent?  (%s)" % NetProtocol.mode_label(selected_mode)).to_upper()


func _on_mode_card_pressed(mode: String) -> void:
	select_mode(mode)
	# Pad / keyboard: the next decision is where -- move there.
	MenuNav.focus_deferred(network_multiplayer_button)


## Same device: Conquest -> the local MatchSetup (map + turn system + squads); Duel -> the
## hot-seat DuelSetup (two human sides).
func _on_local_multiplayer_pressed() -> void:
	if selected_mode == MODE_DUEL:
		MenuNav.change_scene(self, DUEL_SETUP_SCENE)
		return
	GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
	GameSettings.set_player_count(2)  # hot-seat is always two players
	# The unified Match Setup (local hot-seat variant: map + turn system + squads).
	MatchSetup.requested_mode = MatchConfigPanel.MODE_LOCAL
	MenuNav.change_scene(self, MATCH_SETUP_SCENE)


## Network: the host / join screen, told which lobby mode to host or join.
func _on_network_multiplayer_pressed() -> void:
	NetworkMultiplayerSetup.requested_mode = selected_mode
	MenuNav.change_scene(self, NETWORK_SETUP_SCENE)


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, ONLINE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				get_viewport().set_input_as_handled()
				_on_mode_card_pressed(MODE_CONQUEST)
			KEY_2:
				get_viewport().set_input_as_handled()
				_on_mode_card_pressed(MODE_DUEL)
			KEY_3:
				get_viewport().set_input_as_handled()
				_on_network_multiplayer_pressed()
			KEY_4:
				get_viewport().set_input_as_handled()
				_on_local_multiplayer_pressed()
