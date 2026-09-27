extends Control

class_name NetworkMultiplayerSetup

## Network versus: host / join by IP:port, then a lobby (players with ready states,
## host-chosen map + turn system, Start). All networking goes through the
## NetSession autoload; when the host starts, GameModeManager loads the battle on
## both machines. Two instances on one machine work out of the box: host with the
## default port, join 127.0.0.1 with the same port (see systems/net/README.md).
## Joining a DEDICATED server is the same Join: the server holds no seat, so the
## roster shows the two players; the slot-0 player picks the map / turn system
## (unless the server fixed them) and the match starts once both are ready.
##
## Presentation: a "You" row (name + shared port), then side-by-side HOST and JOIN
## cards; once connected, those are swapped for the lobby (Players card + Match
## Settings card, big Start for the host). Status and errors show inline under the
## cards, colour-coded. Built in code (the .tscn is only the root).

const DEFAULT_MAP := "res://game/maps/resources/default_skirmish.tres"

# Setup widgets.
var host_button: Button
var join_button: Button
var back_button: Button
var network_buttons: Control      # the HOST / JOIN card row
var join_container: Control       # the "You" row (name + port)
var address_input: LineEdit
var port_input: LineEdit
var player_name_input: LineEdit
var status_label: Label

# Lobby widgets (hidden until connected).
var lobby_container: Control
var _lobby_info: Label
var _players_list: VBoxContainer
var _map_dropdown: OptionButton
var _turn_dropdown: OptionButton
var _host_only_note: Label
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _map_paths: Array[String] = []
var _refreshing: bool = false
var _tip: Control


func _ready() -> void:
	# Coming back here from anywhere means no match is running: start clean.
	GameModeManager.end_network_session()

	_build_ui()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	address_input.text = NetSession.DEFAULT_ADDRESS
	port_input.text = str(NetSession.DEFAULT_PORT)
	if player_name_input.text.strip_edges() == "" or player_name_input.text == "Player":
		player_name_input.text = "Player"

	_build_lobby_ui()

	NetSession.roster_changed.connect(_on_roster_changed)
	NetSession.config_changed.connect(_on_config_changed)
	NetSession.joined.connect(_on_joined)
	NetSession.join_rejected.connect(_on_join_rejected)
	NetSession.connection_failed.connect(_on_connection_failed)
	NetSession.disconnected.connect(_on_disconnected)

	_update_status("Host a game, or join one by address and port.")
	MenuNav.focus_deferred(host_button)


# --- Layout -------------------------------------------------------------------

var _page: Dictionary


func _build_ui() -> void:
	_page = MenuKit.build_page(self, ["Versus"], "Network Play",
		"Host a lobby on this computer, or join a friend's.")
	var body: VBoxContainer = _page.body

	# "You" row: name + port (shared by Host and Join), inline to save height.
	var you := HBoxContainer.new()
	you.name = "YouRow"
	you.add_theme_constant_override("separation", MenuTheme.SP_M)
	join_container = you
	body.add_child(you)
	player_name_input = _field("Player", "Your name")
	player_name_input.name = "PlayerNameInput"
	player_name_input.max_length = 20
	player_name_input.custom_minimum_size.x = 240
	you.add_child(_inline_caption("YOUR NAME"))
	you.add_child(player_name_input)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	you.add_child(gap)
	port_input = _field(str(NetSession.DEFAULT_PORT), "8910")
	port_input.name = "PortInput"
	port_input.max_length = 5
	port_input.custom_minimum_size.x = 110
	you.add_child(_inline_caption("PORT"))
	you.add_child(port_input)
	var port_note := MenuKit.label("Default %d -- host and joiner must use the same port." % NetSession.DEFAULT_PORT, &"MutedLabel", true)
	port_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	you.add_child(port_note)

	# HOST / JOIN cards.
	var cards := HBoxContainer.new()
	cards.name = "NetworkButtons"
	cards.add_theme_constant_override("separation", MenuTheme.SP_XL)
	network_buttons = cards
	body.add_child(cards)

	var host := _action_card("HOST", "Start a Lobby",
		"Open a lobby on this computer. Your opponent joins using this computer's IP address and the port above.")
	cards.add_child(host["card"])
	var host_spacer := Control.new()
	host_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host["box"].add_child(host_spacer)
	host_button = MenuKit.button("Host Game", MenuKit.PRIMARY, 0, 52)
	host_button.name = "HostButton"
	host["box"].add_child(host_button)

	var join := _action_card("JOIN", "Join a Lobby",
		"Connect to a friend who is hosting, or to a dedicated server.")
	cards.add_child(join["card"])
	address_input = _field(NetSession.DEFAULT_ADDRESS, "Host IP address, e.g. 192.168.1.20")
	address_input.name = "AddressInput"
	join["box"].add_child(_labeled_field("HOST ADDRESS", address_input, 0))
	join_button = MenuKit.button("Join Game", &"", 0, 52)
	join_button.name = "JoinButton"
	join["box"].add_child(join_button)
	address_input.text_submitted.connect(func(_t: String) -> void: join_button.pressed.emit())

	# Local testing tip.
	var tip := PanelContainer.new()
	tip.name = "LocalTip"
	var tip_sb := MenuTheme.accented_card(MenuTheme.ACCENT, SIDE_LEFT, MenuTheme.PANEL_SUNK, 0.85)
	tip_sb.border_color = Color(MenuTheme.ACCENT, 0.45)
	tip_sb.ornament = OrnateStyleBox.Ornament.NONE
	tip_sb.inner_line_color = Color(MenuTheme.ACCENT, 0.18)
	tip_sb.shadow_size = 0.0
	tip_sb.corner = 8.0
	tip_sb.content_margin_top = 10
	tip_sb.content_margin_bottom = 10
	tip.add_theme_stylebox_override("panel", tip_sb)
	_tip = tip
	body.add_child(tip)
	var tip_row := HBoxContainer.new()
	tip_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	tip.add_child(tip_row)
	var tip_tag := MenuKit.label("TIP", &"SectionLabel")
	tip_tag.add_theme_color_override("font_color", MenuTheme.ACCENT)
	tip_row.add_child(tip_tag)
	var tip_text := MenuKit.label("Testing on one PC? Run two copies of Conquest: Host in one, then Join 127.0.0.1 : %d in the other." % NetSession.DEFAULT_PORT, &"DimLabel", true)
	tip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_row.add_child(tip_text)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(filler)

	status_label = MenuKit.label("", &"", true)
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.hints.add_child(status_label)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	_page.actions.add_child(back_button)


func _field(text: String, placeholder: String) -> LineEdit:
	var f := LineEdit.new()
	f.text = text
	f.placeholder_text = placeholder
	f.custom_minimum_size = Vector2(0, 46)
	f.select_all_on_focus = true
	MenuNav.hover_focus(f)
	return f


func _inline_caption(text: String) -> Label:
	var l := MenuKit.section(text)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _labeled_field(caption: String, field: Control, width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	if width > 0.0:
		v.custom_minimum_size = Vector2(width, 0)
	else:
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(MenuKit.section(caption))
	v.add_child(field)
	return v


func _action_card(tag: String, title: String, text: String) -> Dictionary:
	var card := MenuKit.card()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.SP_S)
	card.add_child(v)
	v.add_child(MenuKit.section(tag))
	v.add_child(MenuKit.label(title, &"HeadingLabel"))
	var d := MenuKit.label(text, &"DimLabel", true)
	v.add_child(d)
	return {"card": card, "box": v}


# --- Setup screen -------------------------------------------------------------

func _port() -> int:
	var p := int(port_input.text.strip_edges())
	return p if p > 0 and p < 65536 else NetSession.DEFAULT_PORT


func _player_name() -> String:
	var n := player_name_input.text.strip_edges()
	return n if n != "" else "Player"


func _on_host_pressed() -> void:
	var err: Error = NetSession.host_game(_player_name(), _port())
	if err != OK:
		_update_status("Could not host on port %d (%s). Is it already in use?" % [_port(), error_string(err)])
		return
	# Host picks the map / turn system; push the defaults now.
	_push_config()
	_show_lobby(true)
	_update_status("Hosting. Waiting for an opponent to join %s:%d ..." % [NetSession.DEFAULT_ADDRESS, _port()])


func _on_join_pressed() -> void:
	var address := address_input.text.strip_edges()
	var err: Error = NetSession.join_game(address, _player_name(), _port())
	if err != OK:
		_update_status("Could not start connecting (%s)." % error_string(err))
		return
	_set_setup_enabled(false)
	_update_status("Connecting to %s:%d ..." % [address, _port()])


func _on_joined(_slot: int) -> void:
	_show_lobby(false)
	if NetSession.is_dedicated_server():
		# Lobby leader on a server that did not fix the map: publish our defaults.
		_push_config()
		_update_status("Connected to a dedicated server. The match starts when both players are ready.")
	else:
		_update_status("Connected. Waiting for the host to start.")


func _on_join_rejected(reason: String) -> void:
	_hide_lobby()
	var text := "The lobby is full." if reason == "lobby_full" else "A match is already in progress."
	_update_status("Join refused: " + text)


func _on_connection_failed() -> void:
	_hide_lobby()
	_update_status("Could not connect. Check the address/port and that the host is running.")


func _on_disconnected(_reason: String) -> void:
	_hide_lobby()
	_update_status("The host closed the lobby.")


func _on_back_pressed() -> void:
	GameModeManager.end_network_session()
	MenuNav.change_scene(self, "res://menus/MultiplayerModeSelection.tscn")


func _set_setup_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	for field in [address_input, port_input, player_name_input]:
		field.editable = enabled


## Status line under the page. The tone (colour) is inferred from the message.
func _update_status(text: String) -> void:
	if status_label == null:
		return
	var tone := "info"
	var t := text.to_lower()
	if t.begins_with("could not") or t.begins_with("join refused") or t.begins_with("cannot") \
			or t.begins_with("the host closed"):
		tone = "error"
	elif t.begins_with("everyone is ready") or t.begins_with("connected") or t.begins_with("starting"):
		tone = "ok"
	elif t.begins_with("host a game") or t.begins_with("left the lobby"):
		tone = ""
	MenuKit.set_status(status_label, text, tone)


# --- Lobby --------------------------------------------------------------------

func _build_lobby_ui() -> void:
	var row := HBoxContainer.new()
	row.name = "LobbyContainer"
	row.visible = false
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	lobby_container = row

	# Players card.
	var players := MenuKit.card()
	players.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(players)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", MenuTheme.SP_M)
	players.add_child(pv)
	pv.add_child(MenuKit.section("Players"))
	_lobby_info = MenuKit.label("", &"DimLabel", true)
	pv.add_child(_lobby_info)
	_players_list = VBoxContainer.new()
	_players_list.name = "PlayersList"
	_players_list.add_theme_constant_override("separation", MenuTheme.SP_S)
	pv.add_child(_players_list)
	var pfill := Control.new()
	pfill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(pfill)
	pv.add_child(HSeparator.new())
	_ready_button = Button.new()
	_ready_button.name = "ReadyButton"
	_ready_button.toggle_mode = true
	_ready_button.text = "Mark Me Ready"
	_ready_button.custom_minimum_size = Vector2(0, 50)
	_ready_button.toggled.connect(func(on: bool) -> void:
		_ready_button.text = "Ready!  (press again to cancel)" if on else "Mark Me Ready")
	_ready_button.toggled.connect(_on_ready_toggled)
	MenuNav.hover_focus(_ready_button)
	pv.add_child(_ready_button)

	# Match settings card.
	var settings := MenuKit.card()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(settings)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", MenuTheme.SP_M)
	settings.add_child(sv)
	sv.add_child(MenuKit.section("Match Settings"))

	_map_dropdown = OptionButton.new()
	_map_dropdown.name = "MapDropdown"
	_map_dropdown.custom_minimum_size = Vector2(320, 48)
	var maps := MapLoader.get_available_maps()
	if maps.is_empty():
		maps.append(DEFAULT_MAP)
	for path in maps:
		var res = load(path) as MapResource
		var label: String = path.get_file().get_basename()
		if res:
			label = "%s  (%dx%d)" % [res.map_name, res.width, res.height]
		_map_dropdown.add_item(label)
		_map_paths.append(path)
	var default_idx := _map_paths.find(DEFAULT_MAP)
	_map_dropdown.selected = default_idx if default_idx >= 0 else 0
	_map_dropdown.item_selected.connect(func(_i): _push_config())
	MenuNav.hover_focus(_map_dropdown)
	sv.add_child(_labeled_field("MAP", _map_dropdown, 0))

	_turn_dropdown = OptionButton.new()
	_turn_dropdown.name = "TurnDropdown"
	_turn_dropdown.custom_minimum_size = Vector2(320, 48)
	_turn_dropdown.add_item("Traditional  (armies take turns)", TurnSystemBase.TurnSystemType.TRADITIONAL)
	_turn_dropdown.add_item("Speed First  (units act by speed)", TurnSystemBase.TurnSystemType.INITIATIVE)
	_turn_dropdown.item_selected.connect(func(_i): _push_config())
	MenuNav.hover_focus(_turn_dropdown)
	sv.add_child(_labeled_field("TURN SYSTEM", _turn_dropdown, 0))

	_host_only_note = MenuKit.label("", &"MutedLabel", true)
	sv.add_child(_host_only_note)

	_page.body.add_child(row)
	_page.body.move_child(row, 0)

	# Footer actions for the lobby.
	_leave_button = MenuKit.button("Leave Lobby", MenuKit.GHOST, 170)
	_leave_button.name = "LeaveButton"
	_leave_button.pressed.connect(_on_leave_pressed)
	_leave_button.visible = false
	_page.actions.add_child(_leave_button)
	_start_button = MenuKit.button("Start Match  >", MenuKit.PRIMARY, 240, 54)
	_start_button.name = "StartButton"
	_start_button.pressed.connect(_on_start_pressed)
	_start_button.visible = false
	_page.actions.add_child(_start_button)


func _show_lobby(as_host: bool) -> void:
	network_buttons.visible = false
	join_container.visible = false
	_tip.visible = false
	back_button.visible = false
	lobby_container.visible = true
	_leave_button.visible = true
	var dedicated := NetSession.is_dedicated_server()
	var leader := NetSession.is_lobby_leader()
	_map_dropdown.disabled = not leader
	_turn_dropdown.disabled = not leader
	_start_button.visible = as_host
	if as_host:
		_host_only_note.text = "You are the host: choose the map and turn system, then start once both players are ready."
		_lobby_info.text = "Hosting on port %d -- opponents join %s:%d (or this machine's LAN IP)." % [_port(), NetSession.DEFAULT_ADDRESS, _port()]
	elif dedicated:
		_host_only_note.text = "You lead this lobby: choose the map and turn system." if leader \
			else "The server (or the first player) chooses the map and turn system."
		_lobby_info.text = "Connected to a dedicated server."
	else:
		_host_only_note.text = "The host chooses the map and turn system."
		_lobby_info.text = "Connected to the host."
	(_page.title as Label).text = "Lobby"
	(_page.subtitle as Label).text = "Both players mark themselves ready; the match starts automatically." if dedicated \
		else "Both players mark themselves ready, then the host starts the match."
	_refresh_lobby()
	MenuNav.focus_deferred(_ready_button)


func _hide_lobby() -> void:
	lobby_container.visible = false
	_leave_button.visible = false
	_start_button.visible = false
	network_buttons.visible = true
	join_container.visible = true
	_tip.visible = true
	back_button.visible = true
	(_page.title as Label).text = "Network Play"
	(_page.subtitle as Label).text = "Host a lobby on this computer, or join a friend's."
	_set_setup_enabled(true)
	MenuNav.focus_deferred(host_button)


func _on_leave_pressed() -> void:
	GameModeManager.end_network_session()
	_hide_lobby()
	_update_status("Left the lobby.")


func _push_config() -> void:
	if not NetSession.is_lobby_leader():
		return
	var idx := clampi(_map_dropdown.selected, 0, _map_paths.size() - 1)
	NetSession.set_match_config({
		"map_path": _map_paths[idx],
		"turn_system": _turn_dropdown.get_selected_id(),
		"auto_end_turn": true,
	})


func _on_roster_changed(_roster: Dictionary) -> void:
	_refresh_lobby()


func _on_config_changed(config: Dictionary) -> void:
	# Clients mirror the host's / leader's choice in their dropdowns.
	if NetSession.is_host() or config.is_empty():
		_refresh_lobby()
		return
	_refreshing = true
	var idx := _map_paths.find(String(config.get("map_path", "")))
	if idx >= 0:
		_map_dropdown.selected = idx
	var t_idx := _turn_dropdown.get_item_index(int(config.get("turn_system", 0)))
	if t_idx >= 0:
		_turn_dropdown.selected = t_idx
	_refreshing = false
	_refresh_lobby()


func _refresh_lobby() -> void:
	if lobby_container == null or not lobby_container.visible:
		return
	var roster: Dictionary = NetSession.get_roster()
	var rows: Array = []
	for pid in roster:
		rows.append(roster[pid])
	rows.sort_custom(func(a, b): return int(a["slot"]) < int(b["slot"]))
	for c in _players_list.get_children():
		c.queue_free()
	for r in rows:
		var you := int(r["slot"]) == NetSession.local_slot()
		_players_list.add_child(_player_row(int(r["slot"]), String(r["name"]), you, bool(r["ready"])))
	for s in range(rows.size(), NetSession.max_players):
		_players_list.add_child(_player_row(s, "", false, false))

	# Reflect our own ready flag without re-sending it.
	var mine = roster.get(NetSession.local_peer_id(), {})
	_refreshing = true
	_ready_button.button_pressed = bool(mine.get("ready", false))
	_refreshing = false

	_start_button.disabled = not NetSession.can_start_match()
	if NetSession.is_host():
		if roster.size() < NetSession.max_players:
			_update_status("Waiting for an opponent to join...")
		elif not NetSession.can_start_match():
			_update_status("Waiting for both players to be ready.")
		else:
			_update_status("Everyone is ready -- start the match!")


## One lobby row: team swatch, "Player N", name (+ you), and a READY pill. An
## empty slot (name "") reads "Waiting for a player...".
func _player_row(slot: int, player_name: String, you: bool, ready: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var team := MenuTheme.TEAM_BLUE if slot == 0 else MenuTheme.TEAM_RED
	# A notched well with the seat's team colour down its edge and a heraldic crest.
	var row_sb := MenuTheme.inset_box()
	row_sb.border_color = MenuTheme.GOLD_DK if you else MenuTheme.BORDER_SOFT
	row_sb.accent_color = team if player_name != "" else Color(team, 0.3)
	row_sb.accent_width = 4.0
	row_sb.content_margin_left = 16
	row_sb.content_margin_top = 8
	row_sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", row_sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_M)
	p.add_child(h)
	var crest_letter := player_name.left(1) if player_name != "" else "?"
	var crest := MenuKit.crest(crest_letter, team if player_name != "" else MenuTheme.BORDER,
		MenuTheme.GOLD_DK if player_name != "" else MenuTheme.BORDER_SOFT, 36.0)
	h.add_child(crest)
	var tag := MenuKit.label("P%d" % (slot + 1), &"SectionLabel")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	var n := MenuKit.label(player_name + ("  (you)" if you else "") if player_name != "" else "Waiting for a player...",
		&"" if player_name != "" else &"MutedLabel")
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(n)
	if player_name != "":
		var pill := MenuKit.badge("READY" if ready else "NOT READY",
			MenuTheme.SUCCESS if ready else MenuTheme.TEXT_MUTED, ready)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(pill)
	return p


func _on_ready_toggled(on: bool) -> void:
	if not _refreshing:
		NetSession.set_ready(on)


func _on_start_pressed() -> void:
	# NetSession guards against double-starts and un-ready lobbies itself.
	if not NetSession.start_match():
		_update_status("Cannot start yet: both players must be connected and ready.")
		return
	_start_button.disabled = true
	_update_status("Starting...")


func _unhandled_input(event: InputEvent) -> void:
	if not MenuNav.is_back_event(event):
		return
	get_viewport().set_input_as_handled()
	if lobby_container != null and lobby_container.visible:
		_on_leave_pressed()
	else:
		_on_back_pressed()
