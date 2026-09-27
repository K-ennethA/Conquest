extends Control

class_name NetworkMultiplayerSetup

## Network versus: host / join by IP:port, then a minimal lobby (players, ready
## states, host-chosen map + turn system, Start). All networking goes through the
## NetSession autoload; when the host starts, GameModeManager loads the battle on
## both machines. Two instances on one machine work out of the box: host with the
## default port, join 127.0.0.1 with the same port (see systems/net/README.md).

const DEFAULT_MAP := "res://game/maps/resources/default_skirmish.tres"

@onready var host_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/HostButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/JoinButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton
@onready var network_buttons: Control = $CenterContainer/VBoxContainer/NetworkButtons

@onready var join_container: VBoxContainer = $CenterContainer/VBoxContainer/JoinContainer
@onready var join_title: Label = $CenterContainer/VBoxContainer/JoinContainer/JoinTitle
@onready var address_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/AddressContainer/AddressInput
@onready var port_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/PortContainer/PortInput
@onready var player_name_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/PlayerNameContainer/PlayerNameInput
@onready var connect_button: Button = $CenterContainer/VBoxContainer/JoinContainer/ConnectButton

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

# Lobby widgets (built in code, hidden until connected).
var lobby_container: VBoxContainer
var _lobby_info: Label
var _players_label: Label
var _map_dropdown: OptionButton
var _turn_dropdown: OptionButton
var _ready_button: CheckButton
var _start_button: Button
var _leave_button: Button
var _map_paths: Array[String] = []
var _refreshing: bool = false


func _ready() -> void:
	# Coming back here from anywhere means no match is running: start clean.
	GameModeManager.end_network_session()

	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	# Host and Join both read the fields below; the separate Connect step is gone.
	connect_button.visible = false
	join_title.text = "Connection:"
	join_container.visible = true
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
	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")


func _set_setup_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled
	for field in [address_input, port_input, player_name_input]:
		field.editable = enabled


func _update_status(text: String) -> void:
	if status_label:
		status_label.text = text


# --- Lobby --------------------------------------------------------------------

func _build_lobby_ui() -> void:
	lobby_container = VBoxContainer.new()
	lobby_container.name = "LobbyContainer"
	lobby_container.visible = false
	lobby_container.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "LOBBY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	lobby_container.add_child(title)

	_lobby_info = Label.new()
	_lobby_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(_lobby_info)

	_players_label = Label.new()
	_players_label.name = "PlayersList"
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_players_label.custom_minimum_size = Vector2(0, 60)
	lobby_container.add_child(_players_label)

	_map_dropdown = OptionButton.new()
	_map_dropdown.custom_minimum_size = Vector2(320, 36)
	var maps := MapLoader.get_available_maps()
	if maps.is_empty():
		maps.append(DEFAULT_MAP)
	for path in maps:
		var res = load(path) as MapResource
		var label: String = path.get_file().get_basename()
		if res:
			label = "%s (%dx%d)" % [res.map_name, res.width, res.height]
		_map_dropdown.add_item(label)
		_map_paths.append(path)
	var default_idx := _map_paths.find(DEFAULT_MAP)
	_map_dropdown.selected = default_idx if default_idx >= 0 else 0
	_map_dropdown.item_selected.connect(func(_i): _push_config())
	lobby_container.add_child(_labeled("Map:", _map_dropdown))

	_turn_dropdown = OptionButton.new()
	_turn_dropdown.custom_minimum_size = Vector2(320, 36)
	_turn_dropdown.add_item("Traditional (player turns)", TurnSystemBase.TurnSystemType.TRADITIONAL)
	_turn_dropdown.add_item("Speed First (unit initiative)", TurnSystemBase.TurnSystemType.INITIATIVE)
	_turn_dropdown.item_selected.connect(func(_i): _push_config())
	lobby_container.add_child(_labeled("Turns:", _turn_dropdown))

	_ready_button = CheckButton.new()
	_ready_button.text = "Ready"
	_ready_button.toggled.connect(_on_ready_toggled)
	lobby_container.add_child(_centered(_ready_button))

	_start_button = Button.new()
	_start_button.text = "START MATCH"
	_start_button.custom_minimum_size = Vector2(200, 44)
	_start_button.pressed.connect(_on_start_pressed)
	lobby_container.add_child(_centered(_start_button))

	_leave_button = Button.new()
	_leave_button.text = "Leave Lobby"
	_leave_button.pressed.connect(_on_leave_pressed)
	lobby_container.add_child(_centered(_leave_button))

	$CenterContainer/VBoxContainer.add_child(lobby_container)
	# Keep the status line + Back button below the lobby.
	$CenterContainer/VBoxContainer.move_child(lobby_container, status_label.get_index())


func _labeled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(60, 0)
	row.add_child(l)
	row.add_child(control)
	return row


func _centered(control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(control)
	return row


func _show_lobby(as_host: bool) -> void:
	network_buttons.visible = false
	join_container.visible = false
	lobby_container.visible = true
	_map_dropdown.disabled = not as_host
	_turn_dropdown.disabled = not as_host
	_start_button.visible = as_host
	_lobby_info.text = ("Hosting on port %d -- opponents join %s:%d (or this machine's LAN IP)." % [_port(), NetSession.DEFAULT_ADDRESS, _port()]) \
		if as_host else "Connected to the host."
	_refresh_lobby()


func _hide_lobby() -> void:
	lobby_container.visible = false
	network_buttons.visible = true
	join_container.visible = true
	_set_setup_enabled(true)


func _on_leave_pressed() -> void:
	GameModeManager.end_network_session()
	_hide_lobby()
	_update_status("Left the lobby.")


func _push_config() -> void:
	if not NetSession.is_host():
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
	# Clients mirror the host's choice in their (disabled) dropdowns.
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
	var lines: Array[String] = []
	for r in rows:
		var you := " (you)" if int(r["slot"]) == NetSession.local_slot() else ""
		lines.append("Player %d: %s%s -- %s" % [int(r["slot"]) + 1, r["name"], you, "READY" if r["ready"] else "not ready"])
	for s in range(rows.size(), NetSession.max_players):
		lines.append("Player %d: (waiting...)" % (s + 1))
	_players_label.text = "\n".join(lines)

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
