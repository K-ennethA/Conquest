extends Control

class_name NetworkMultiplayerSetup

## Network versus: host / join by IP:port, then the collaborative lobby (players with ready
## states, map vote / coin flip, host match settings -- or, on a dedicated server, the lobby
## leader's map + turn system). All networking goes through the NetSession autoload; when the
## match starts, GameModeManager loads the battle on every machine.
##
## Two instances on one machine work out of the box: host with the default port, join
## 127.0.0.1 with the same port (see systems/net/README.md). Two machines: the host's screen
## shows its LAN address(es); the joiner's last address / port / name are remembered in
## user://net.cfg. Joining a DEDICATED server is the same Join: the server holds no seat.
##
## Presentation (built in code; the .tscn is only the root): a "You" row (name + shared port),
## side-by-side HOST and JOIN cards and two tips; once hosting / seated, those are swapped for
## the embedded [CollaborativeLobby] and the host's join address sits beside the title. Status
## and errors show colour-coded in the footer.
##
## SKIN / LOGIC SPLIT. The look lives in the `_build_*` builders, the card / field / tip
## factories and the `_present_*` / `_enter_lobby_view` / `_exit_lobby_view` / `_update_footer`
## / `_show_host_info` presenters. The flow (host, join, connect state machine, teardown,
## prefs, validation) never builds a widget: it reads the public members and asks a presenter.

## The merged lobby. Preloaded BY PATH (and used as a type through this constant), so this
## screen never depends on the global class cache knowing CollaborativeLobby yet.
const CollaborativeLobbyScript := preload("res://menus/CollaborativeLobby.gd")

# Dev-only: "Host + Auto Client" spawns a SECOND game instance (AutoClientDetector) that
# auto-joins the host. A developer two-instance testing convenience, NOT a shipping feature.
# Gated OFF by default, mirroring MainMenu.ENABLE_DEV_TEST_HARNESS: when false the button is
# hidden, KEY_2 does nothing and the handler refuses to run.
const ENABLE_HOST_AUTO_CLIENT := false

## Where the last address/port/name a player joined with is remembered, so the second
## machine does not have to re-type the host's LAN IP every single test run.
const NET_PREFS_PATH := "user://net.cfg"
## How long "Connecting..." may run before we tell the player it did not reach the host.
## Deliberately longer than the transport's own wait so the transport reports first when
## it can, and this is the backstop that guarantees the UI never hangs on "Connecting...".
const CONNECT_TIMEOUT_SEC := 8.0
const DEFAULT_PORT := 8910  # == NetSessionNode.DEFAULT_PORT
const DEFAULT_ADDRESS := "127.0.0.1"  # == NetSessionNode.DEFAULT_ADDRESS
const MODE_SELECT_SCENE := "res://menus/MultiplayerModeSelection.tscn"

const TITLE_SETUP := "Network Play"
const SUBTITLE_SETUP := "Host a lobby on this computer, or join a friend's."
const TITLE_DUEL := "Network Duel"
const SUBTITLE_DUEL := "Host a duel lobby on this computer, or join a friend's (or a duel server)."

## What this screen hosts / joins: [constant NetProtocol.MODE_CONQUEST] (the map battle) or
## [constant NetProtocol.MODE_DUEL] -- set by the Versus screen before it opens this one (like
## MatchSetup.requested_mode). It becomes [member NetSessionNode.lobby_mode]: a joiner's hello
## names it and a host of the other mode refuses the join with the reason on screen.
static var requested_mode: String = NetProtocol.MODE_CONQUEST
const IDLE_STATUS := "Host a game, or join one by address and port."

## What the join half of this screen is doing right now. Drives the status text and
## which buttons are live; there is exactly one place each state is entered.
enum ConnectState { IDLE, CONNECTING, CONNECTED, REJECTED }

# Setup widgets (public: tests and MultiplayerLauncher drive them).
var host_button: Button
var host_with_client_button: Button
var join_button: Button
var back_button: Button
## Footer "Cancel Hosting" / "Cancel" / "Leave Lobby" -- tears the session down at any stage.
var leave_button: Button
var network_buttons: Control      # the HOST / JOIN card row
var join_container: Control       # the "You" row (name + port)
var address_input: LineEdit
var port_input: LineEdit
var player_name_input: LineEdit
var status_label: Label
## "First time on two machines?" walkthrough.
var hint_label: Label
## The host's LAN join line, shown beside the title while hosting.
var host_info_label: Label

## The embedded lobby while hosting / seated, else null.
var collaborative_lobby: Control = null

# Session state
var is_hosting: bool = false
## True whenever a host flow is active (plain Host or dev Host + Auto Client). While true,
## Esc / B and the footer Cancel tear the listen server down and return to the setup.
var is_host_active: bool = false
## Current join state (see [enum ConnectState]).
var connect_state: int = ConnectState.IDLE
## Where the join details are remembered (a test points this at a temp file).
var net_prefs_path: String = NET_PREFS_PATH

## Wall-clock deadline for the current connect attempt, in engine ticks. Only read
## while [member connect_state] is CONNECTING.
var _connect_deadline_msec: int = 0
var _countdown_shown: int = -1
## The address/port/name of the join attempt in flight, kept so the signal-driven state
## transitions can name them without re-reading (and re-validating) the form.
var _join_address: String = ""
var _join_port: int = DEFAULT_PORT
var _join_player_name: String = "Player"
var _hosted_port: int = DEFAULT_PORT

# Look-only references.
var _page: Dictionary = {}
var _setup_box: Control
var _host_info_strip: Control


# =============================================================================
# FLOW
# =============================================================================

## The live NetSession autoload, or null in a bare test harness that has no autoloads.
func _net() -> Node:
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		return NetSession
	return null


func _ready() -> void:
	# Coming back here from anywhere means no match is running: start clean. (The main menu
	# owns GameModeManager's one-shot menu message; it is not consumed here.)
	GameModeManager.end_network_session()
	var net: Node = _net()
	if net != null and "lobby_mode" in net:
		net.lobby_mode = NetProtocol.MODE_DUEL if is_duel() else NetProtocol.MODE_CONQUEST

	_build_ui()

	host_button.pressed.connect(_on_host_pressed)
	host_with_client_button.pressed.connect(_on_host_with_client_pressed)
	join_button.pressed.connect(_on_join_pressed)
	back_button.pressed.connect(_on_back_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	address_input.text_submitted.connect(_on_address_submitted)

	# Defaults, then let any remembered ones win (see _load_net_prefs).
	address_input.text = DEFAULT_ADDRESS
	port_input.text = str(DEFAULT_PORT)
	player_name_input.text = "Player"
	_load_net_prefs()
	hint_label.text = _first_time_hint()

	_wire_session_signals(true)

	_update_status(IDLE_STATUS)
	_update_footer()
	print("Network Multiplayer Setup initialized")
	MenuNav.focus_deferred(host_button)


func _exit_tree() -> void:
	_wire_session_signals(false)


## NetSession drives the connect state machine:
##   joined             -- we were seated; this is what "connected" actually means
##   join_rejected      -- the build gate refused us (looks like a successful connect,
##                         then vanishes, so it gets its own explicit state)
##   connection_failed  -- the socket never came up
##   disconnected       -- the host went away (or dropped us after a refusal)
##   roster_changed / peer_join_refused -- the host's status line
func _wire_session_signals(attach: bool) -> void:
	var net: Node = _net()
	if net == null:
		return
	var pairs: Array = [
		["joined", _on_net_joined],
		["join_rejected", _on_join_rejected],
		["connection_failed", _on_net_connection_failed],
		["disconnected", _on_net_disconnected],
		["roster_changed", _on_net_roster_changed],
		["peer_join_refused", _on_peer_join_refused],
	]
	for pair in pairs:
		var sig: StringName = StringName(String(pair[0]))
		var handler: Callable = pair[1]
		if not net.has_signal(sig):
			continue
		var is_bound: bool = net.is_connected(sig, handler)
		if attach and not is_bound:
			net.connect(sig, handler)
		elif not attach and is_bound:
			net.disconnect(sig, handler)


## True when this screen hosts / joins an online DUEL lobby ([member requested_mode]).
func is_duel() -> bool:
	return requested_mode == NetProtocol.MODE_DUEL


func _in_session() -> bool:
	return is_host_active or connect_state == ConnectState.CONNECTING \
		or connect_state == ConnectState.CONNECTED


# --- Host ---------------------------------------------------------------------

func _on_host_pressed() -> void:
	"""Host: open a NetSession listen server (seat 0) and show the lobby."""
	if is_host_active or connect_state == ConnectState.CONNECTING:
		return
	var port: int = int(port_input.text.strip_edges()) if port_input != null else DEFAULT_PORT
	if not _is_valid_port(port):
		_update_status("Port must be between 1024 and 65535 (the default is %d)." % DEFAULT_PORT)
		return

	print("[HOST] Starting network multiplayer host...")
	_update_status("Starting host...")
	_set_setup_enabled(false)

	var host_name: String = _host_display_name()
	var err: int = _start_net_host(host_name, port)
	if err != OK:
		print("[HOST] Host failed to start: %s" % error_string(err))
		_update_status("Could not start hosting on port %d (%s). Another copy of Conquest may already be hosting." % [port, error_string(err)])
		_set_setup_enabled(true)
		return

	print("[HOST] Host started successfully on port %d" % port)
	for lan_address in _lan_addresses():
		print("[HOST] Players on your network join: %s:%d" % [lan_address, port])

	is_hosting = true
	is_host_active = true
	_hosted_port = port
	# The other machine needs to read the join address off this screen: keep it beside the
	# title for as long as we host.
	_show_host_info(port)
	_update_status(_hosting_status(1))
	_show_collaborative_lobby(true, host_name)


## Open the listen server on NetSession. Two players max: this screen is 1v1, and a capped
## lobby means a third dialler is cleanly refused (REJECT_LOBBY_FULL) instead of silently
## occupying a slot the battle has no player for.
func _start_net_host(host_name: String, port: int) -> int:
	var net: Node = _net()
	if net == null:
		return ERR_UNAVAILABLE
	# A stale peer from a previous attempt would make create_server fail; start clean.
	net.leave()
	return int(net.host_game(host_name, port, 2))


## The host's display name. Reuses the typed / remembered name when the player set one, so
## both machines show a name the human chose rather than two "Player"s.
func _host_display_name() -> String:
	if player_name_input != null:
		var typed: String = player_name_input.text.strip_edges()
		if typed != "" and typed != "Player":
			return typed
	return "Host Player"


func _hosting_status(players: int) -> String:
	if players >= 2:
		if is_duel():
			return "Opponent connected -- pick your units, then both press Ready."
		return "Opponent connected -- vote on a map, then both press Ready."
	return "Hosting on port %d. Waiting for an opponent to join..." % _hosted_port


## Dev "Host + Auto Client": host on the normal path, then spawn a second instance that
## auto-joins it (MultiplayerLauncher presses Join on it via [method begin_auto_join]).
func _on_host_with_client_pressed() -> void:
	# Dev-only guard: refuse to spawn a second instance unless explicitly enabled
	# (defends the KEY_2 shortcut and any stray callers even though the button is hidden).
	if not ENABLE_HOST_AUTO_CLIENT:
		print("[HOST] Host + Auto Client is disabled (dev-only feature). Ignoring.")
		_update_status("Host + Auto Client is a dev-only feature (disabled).")
		return
	# Deliberately the SAME code path a human takes (NetSession listen server + collaborative
	# lobby). The harness only adds the second process; if it ever diverges from the real Host
	# button it stops testing the thing that ships.
	_on_host_pressed()
	if not is_host_active:
		return  # _on_host_pressed already explained the failure.
	if AutoClientDetector.launch_client(_hosted_port, "Client Player"):
		print("[HOST] Client instance launched")
	else:
		_update_status("Could not launch a client instance (see the log).")


# --- Join ---------------------------------------------------------------------

func _on_address_submitted(_text: String) -> void:
	if join_button != null and not join_button.disabled:
		_on_join_pressed()


## Join: validate the form, remember it, and dial through NetSession.
func _on_join_pressed() -> void:
	if connect_state == ConnectState.CONNECTING or is_host_active:
		return  # Already dialling / hosting -- a second press must not stack two attempts.

	var address: String = address_input.text.strip_edges() if address_input != null else DEFAULT_ADDRESS
	var port: int = int(port_input.text.strip_edges()) if port_input != null else DEFAULT_PORT
	var player_name: String = player_name_input.text.strip_edges() if player_name_input != null else "Player"
	if player_name == "":
		player_name = "Player"

	# Validate the shape BEFORE touching the socket: a typo'd address otherwise burns the
	# full connect timeout before saying anything useful.
	if not _is_valid_address(address):
		_update_status("That address does not look right. Use the host's LAN IP, e.g. 192.168.1.24")
		return
	if not _is_valid_port(port):
		_update_status("Port must be between 1024 and 65535 (the host's screen shows it).")
		return

	_save_net_prefs(address, port, player_name)

	print("[CLIENT] Joining network game at %s:%d as %s" % [address, port, player_name])
	connect_state = ConnectState.CONNECTING
	_join_address = address
	_join_port = port
	_join_player_name = player_name
	_connect_deadline_msec = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SEC * 1000.0)
	_countdown_shown = -1
	_update_status("Connecting to %s:%d ..." % [address, port])
	_set_setup_enabled(false)
	_update_footer()

	# Dial through NetSession -- the same session the battle reads. The hello / version
	# handshake fires the moment the socket comes up, and the outcome arrives on a signal
	# (joined / join_rejected / connection_failed), never on this call's return value:
	# join_game() only reports that the socket could be OPENED.
	var net: Node = _net()
	if net == null:
		connect_state = ConnectState.IDLE
		_update_status("Networking is unavailable in this build.")
		_set_setup_enabled(true)
		_update_footer()
		return
	net.leave()  # Drop any half-open peer from a previous attempt.
	var err: int = int(net.join_game(address, player_name, port))
	if err != OK:
		connect_state = ConnectState.IDLE
		print("[CLIENT] join_game failed immediately: %s" % error_string(err))
		_update_status("Could not open a connection to %s:%d (%s)." % [address, port, error_string(err)])
		_set_setup_enabled(true)
		_update_footer()


## Dev harness entry point (--multiplayer-auto-join, see systems/multiplayer_launcher.gd):
## fill the join form and press Join on the SAME path a human uses, so the two-instance
## harness can never drift from the flow that ships.
func begin_auto_join(address: String, port: int, player_name: String) -> void:
	if address_input:
		address_input.text = address
	if port_input:
		port_input.text = str(port)
	if player_name_input:
		player_name_input.text = player_name
	_on_join_pressed()


## The visible connect countdown ("Connecting to a:p ... (5s)") and the backstop that
## declares the attempt dead when the deadline runs out first. Frame-driven (no awaits), so a
## screen freed mid-attempt leaves nothing behind.
func _process(_delta: float) -> void:
	if connect_state != ConnectState.CONNECTING:
		return
	var remaining_msec: int = _connect_deadline_msec - Time.get_ticks_msec()
	if remaining_msec <= 0:
		_fail_connect(_join_address, _join_port)
		return
	var secs: int = int(ceil(remaining_msec / 1000.0))
	if secs != _countdown_shown:
		_countdown_shown = secs
		_update_status("Connecting to %s:%d ... (%ds)" % [_join_address, _join_port, secs])


## Leave CONNECTING with the "we never reached the host" explanation. Idempotent.
func _fail_connect(address: String, port: int) -> void:
	if connect_state != ConnectState.CONNECTING:
		return
	connect_state = ConnectState.IDLE
	# Drop the half-open peer, else the next Join press hits a socket that is still dialling.
	var net: Node = _net()
	if net != null:
		net.leave()
	_update_status("Could not reach %s:%d - check the address, that the host clicked Host, and that Windows Firewall allowed Conquest on both machines." % [address, port], "error")
	_set_setup_enabled(true)
	_update_footer()


## NetSession seated us. Being IN the roster is what "connected" means on this transport --
## the socket coming up only means the hello is in flight, and a build mismatch is refused
## after that point.
func _on_net_joined(slot: int) -> void:
	if connect_state != ConnectState.CONNECTING:
		return
	connect_state = ConnectState.CONNECTED
	print("[CLIENT] Successfully joined network game (slot %d)" % slot)
	if _is_dedicated_session():
		_update_status("Connected to a dedicated server at %s:%d. The match starts when both players are ready." % [_join_address, _join_port])
	else:
		_update_status("Connected to %s:%d. Waiting for the lobby..." % [_join_address, _join_port])
	_show_collaborative_lobby(false, _join_player_name)


## The socket never came up.
func _on_net_connection_failed() -> void:
	print("[CLIENT] Transport reported connection_failed")
	_fail_connect(_join_address, _join_port)


## The host went away. Harmless noise after a refusal (which owns the message) or when we
## are not in a join flow at all; otherwise it is the end of this attempt / lobby.
func _on_net_disconnected(reason: String) -> void:
	if connect_state == ConnectState.REJECTED:
		return  # _on_join_rejected already said why, and it is the more useful message.
	if connect_state == ConnectState.CONNECTING:
		_fail_connect(_join_address, _join_port)
		return
	if connect_state == ConnectState.CONNECTED:
		print("[CLIENT] Disconnected from the host (%s)" % reason)
		connect_state = ConnectState.IDLE
		_remove_lobby()
		_exit_lobby_view()
		_set_setup_enabled(true)
		_update_footer()
		_update_status("The host closed the lobby.")


## The host refused this peer (build/protocol mismatch, full lobby, match in progress).
## Arrives on the NetSession transport AFTER the socket came up, so it can land during or
## just after a seemingly successful connect -- either way it is the final word.
func _on_join_rejected(reason: String, info: Dictionary) -> void:
	connect_state = ConnectState.REJECTED
	var explanation: String = NetProtocol.describe_rejection(reason, info)
	print("[CLIENT] Join refused: " + explanation)
	# Drop any lobby we opened, and put the join form back.
	_remove_lobby()
	_exit_lobby_view()
	_set_setup_enabled(true)
	_update_footer()
	_update_status("Join refused: " + explanation, "error")


## Host: somebody tried to join and was refused -- say why on the host's side too.
func _on_peer_join_refused(_peer_id: int, reason: String, info: Dictionary) -> void:
	if not is_host_active:
		return
	_update_status("A player could not join: " + NetProtocol.describe_rejection(reason, info), "warn")


func _on_net_roster_changed(roster: Dictionary) -> void:
	if is_host_active:
		_update_status(_hosting_status(roster.size()))


func _is_dedicated_session() -> bool:
	var net: Node = _net()
	return net != null and net.has_method("is_dedicated_server") and bool(net.is_dedicated_server())


# --- The embedded lobby -----------------------------------------------------------

func _show_collaborative_lobby(as_host: bool, player_name: String) -> void:
	"""Swap the setup for the collaborative lobby (initialised as host or client)."""
	print("[SETUP] Showing collaborative lobby (host: " + str(as_host) + ")")
	_remove_lobby()
	if is_duel():
		# An online DUEL lobby: roster + ready, each seat's unit, the host's stage / weather.
		var duel_lobby := DuelLobby.new()
		duel_lobby.name = "DuelLobby"
		_embed_lobby(duel_lobby)
		collaborative_lobby = duel_lobby
		_enter_lobby_view(as_host)
		duel_lobby.game_starting.connect(_on_duel_lobby_starting)
		duel_lobby.initialize(as_host, player_name)
		return
	var lobby: CollaborativeLobbyScript = CollaborativeLobbyScript.new()
	lobby.name = "CollaborativeLobby"
	_embed_lobby(lobby)  # into the tree first: its _ready builds the lobby UI
	collaborative_lobby = lobby
	_enter_lobby_view(as_host)
	lobby.game_starting.connect(_on_lobby_game_starting)
	lobby.initialize(as_host, player_name)


func _on_duel_lobby_starting() -> void:
	_update_status("Starting the duel...")


func _remove_lobby() -> void:
	if collaborative_lobby != null and is_instance_valid(collaborative_lobby):
		var parent: Node = collaborative_lobby.get_parent()
		if parent != null:
			parent.remove_child(collaborative_lobby)
		collaborative_lobby.queue_free()
	collaborative_lobby = null


func _on_lobby_game_starting(map_path: String) -> void:
	print("[SETUP] Game starting with map: " + map_path)
	var map_name: String = MapCatalog.map_name_for(map_path)
	_update_status("Starting the match on %s..." % (map_name if map_name != "" else map_path.get_file().get_basename()))


# --- Leaving ------------------------------------------------------------------

## Cancel hosting / cancel a connect / leave the lobby: close the session through
## GameModeManager (which also restores local play defaults) and restore the setup.
func _leave_session(message: String) -> void:
	print("[SETUP] Leaving the session: " + message)
	is_host_active = false
	is_hosting = false
	connect_state = ConnectState.IDLE
	_remove_lobby()
	GameModeManager.end_network_session()
	_hide_host_info()
	_exit_lobby_view()
	_set_setup_enabled(true)
	_update_footer()
	_update_status(message)
	MenuNav.focus_deferred(host_button)


func _on_leave_pressed() -> void:
	if is_host_active:
		_leave_session("Stopped hosting.")
	elif connect_state == ConnectState.CONNECTING:
		_leave_session("Connection cancelled.")
	else:
		_leave_session("Left the lobby.")


func _on_back_pressed() -> void:
	# While a session is up, Back (Esc / B) leaves it instead of leaving the screen.
	if _in_session():
		_on_leave_pressed()
		return
	print("Returning to multiplayer mode selection")
	GameModeManager.end_network_session()
	MenuNav.change_scene(self, MODE_SELECT_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # digits typed into the address / port / name are text, not shortcuts
	match key.keycode:
		KEY_1:
			if _can_press(host_button):
				get_viewport().set_input_as_handled()
				_on_host_pressed()
		KEY_2:
			if ENABLE_HOST_AUTO_CLIENT and _can_press(host_with_client_button):
				get_viewport().set_input_as_handled()
				_on_host_with_client_pressed()
		KEY_3:
			if _can_press(join_button):
				get_viewport().set_input_as_handled()
				_on_join_pressed()


func _can_press(button: Button) -> bool:
	return button != null and button.is_visible_in_tree() and not button.disabled


func _set_setup_enabled(enabled: bool) -> void:
	for b in [host_button, host_with_client_button, join_button]:
		if b != null:
			(b as Button).disabled = not enabled
	for field in [address_input, port_input, player_name_input]:
		if field != null:
			(field as LineEdit).editable = enabled


## Status line in the footer. [param tone] "auto" infers it from the message.
func _update_status(text: String, tone: String = "auto") -> void:
	print_verbose("Status: " + text)
	_present_status(text, _status_tone(text) if tone == "auto" else tone)


func _status_tone(text: String) -> String:
	var t := text.to_lower()
	for prefix in ["could not", "join refused", "cannot", "the host closed", "that address",
			"port must", "networking is unavailable", "error"]:
		if t.begins_with(prefix):
			return "error"
	if t.begins_with("a player could not"):
		return "warn"
	for prefix in ["connected", "opponent connected", "starting", "everyone is ready"]:
		if t.begins_with(prefix):
			return "ok"
	for prefix in ["host a game", "left the lobby", "stopped hosting", "connection cancelled"]:
		if t.begins_with(prefix):
			return ""
	return "info"


# ---------------------------------------------------------------------------
# Two-machine helpers: the host's address, the join form's memory, validation
# ---------------------------------------------------------------------------

## Every private-range IPv4 this machine owns, i.e. the addresses another machine on the
## same router can actually dial. Loopback, link-local (169.254.x) and IPv6 are dropped:
## handing the player 127.0.0.1 or a v6 address is the single most common reason a
## two-machine test fails before it starts.
func _lan_addresses() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for address in IP.get_local_addresses():
		var text: String = String(address)
		if not text.is_valid_ip_address() or text.contains(":"):
			continue  # IPv6 (or junk) -- ENet here is dialled by IPv4.
		var octets: PackedStringArray = text.split(".")
		if octets.size() != 4:
			continue
		var first: int = int(octets[0])
		var second: int = int(octets[1])
		var is_private: bool = first == 10 \
			or (first == 172 and second >= 16 and second <= 31) \
			or (first == 192 and second == 168)
		if is_private and not result.has(text):
			result.append(text)
	return result


## The line the host reads out loud to the other machine.
func _host_join_line(port: int) -> String:
	var addresses: PackedStringArray = _lan_addresses()
	if addresses.is_empty():
		return "Hosting on port %d. No private network address found - both machines must be on the same Wi-Fi/router." % port
	var joined: PackedStringArray = PackedStringArray()
	for address in addresses:
		joined.append("%s:%d" % [address, port])
	return "Players on your network join:  %s" % "     ".join(joined)


## True when [param address] is shaped like something ENet can dial: an IPv4 literal,
## "localhost", or a plain hostname. Shape only -- reachability is the connect attempt's job.
func _is_valid_address(address: String) -> bool:
	var text: String = address.strip_edges()
	if text.is_empty() or text.length() > 253:
		return false
	if text.is_valid_ip_address():
		return not text.contains(":")  # IPv4 literal.
	if text.contains(".") and text.split(".").size() == 4 and text[0].is_valid_int():
		return false  # Looks like a botched IPv4 ("192.168.1.999") -- do not treat as a hostname.
	for i in text.length():
		var c: String = text[i]
		if not (c.is_valid_identifier() or c.is_valid_int() or c == "-" or c == "." or c == "_"):
			return false
	return true


## Ports below 1024 need admin rights on Windows; 0 and >65535 are not ports at all.
func _is_valid_port(port: int) -> bool:
	return port >= 1024 and port <= 65535


## The walkthrough for someone doing this for the first time. Short on purpose -- the
## full script is docs/NETWORK_TESTING.md.
func _first_time_hint() -> String:
	return "First time on two machines? Both machines must run the SAME build. " \
		+ "On machine A press Host and ALLOW the Windows Firewall prompt (Private networks). " \
		+ "On machine B press Join and type the address A shows."


# --- Remembered join details (user://net.cfg) --------------------------------

func _load_net_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(net_prefs_path) != OK:
		return  # Nothing saved yet -- keep the defaults.
	if address_input:
		var saved_address: String = String(cfg.get_value("join", "address", ""))
		if _is_valid_address(saved_address):
			address_input.text = saved_address
	if port_input:
		var saved_port: int = int(cfg.get_value("join", "port", DEFAULT_PORT))
		if _is_valid_port(saved_port):
			port_input.text = str(saved_port)
	if player_name_input:
		var saved_name: String = String(cfg.get_value("join", "player_name", "")).strip_edges()
		if saved_name != "":
			player_name_input.text = saved_name


func _save_net_prefs(address: String, port: int, player_name: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(net_prefs_path)  # Preserve any other sections; ignore load failure.
	cfg.set_value("join", "address", address)
	cfg.set_value("join", "port", port)
	cfg.set_value("join", "player_name", player_name)
	cfg.save(net_prefs_path)


# =============================================================================
# LOOK -- builders, factories and presenters
# =============================================================================

func _build_ui() -> void:
	_page = MenuKit.build_page(self, ["Online", "Versus"],
		TITLE_DUEL if is_duel() else TITLE_SETUP, SUBTITLE_DUEL if is_duel() else SUBTITLE_SETUP)
	var body: VBoxContainer = _page["body"]

	var setup := VBoxContainer.new()
	setup.name = "SetupBox"
	setup.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", MenuTheme.SP_M)
	body.add_child(setup)
	_setup_box = setup

	_build_you_row(setup)
	_build_action_cards(setup)
	_build_tips(setup)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup.add_child(filler)

	_build_host_info_strip()
	_build_footer()


## "You" row: name + port (shared by Host and Join), inline to save height.
func _build_you_row(parent: Control) -> void:
	var you := HBoxContainer.new()
	you.name = "YouRow"
	you.add_theme_constant_override("separation", MenuTheme.SP_M)
	join_container = you
	parent.add_child(you)
	player_name_input = _field("Player", "Your name")
	player_name_input.name = "PlayerNameInput"
	player_name_input.max_length = 20
	player_name_input.custom_minimum_size.x = 240
	you.add_child(_inline_caption("YOUR NAME"))
	you.add_child(player_name_input)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	you.add_child(gap)
	port_input = _field(str(DEFAULT_PORT), str(DEFAULT_PORT))
	port_input.name = "PortInput"
	port_input.max_length = 5
	port_input.custom_minimum_size.x = 110
	you.add_child(_inline_caption("PORT"))
	you.add_child(port_input)
	var port_note := MenuKit.label("Default %d -- host and joiner must use the same port." % DEFAULT_PORT, &"MutedLabel", true)
	port_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	you.add_child(port_note)


## HOST / JOIN cards.
func _build_action_cards(parent: Control) -> void:
	var cards := HBoxContainer.new()
	cards.name = "NetworkButtons"
	cards.add_theme_constant_override("separation", MenuTheme.SP_XL)
	network_buttons = cards
	parent.add_child(cards)

	var host := _action_card("HOST", "Start a Lobby",
		"Open a lobby on this computer. Your opponent joins using this computer's network address (shown once you host) and the port above.")
	var host_card: Control = host["card"]
	cards.add_child(host_card)
	var host_box: VBoxContainer = host["box"]
	var host_spacer := Control.new()
	host_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host_box.add_child(host_spacer)
	host_button = MenuKit.button("Host Game", MenuKit.PRIMARY, 0, 52)
	host_button.name = "HostButton"
	host_box.add_child(host_button)
	host_with_client_button = MenuKit.button("Host + Auto Client (dev)", MenuKit.GHOST, 0, 44)
	host_with_client_button.name = "HostWithClientButton"
	host_with_client_button.visible = ENABLE_HOST_AUTO_CLIENT
	host_box.add_child(host_with_client_button)

	var join := _action_card("JOIN", "Join a Lobby",
		"Connect to a friend who is hosting, or to a dedicated server.")
	var join_card: Control = join["card"]
	cards.add_child(join_card)
	var join_box: VBoxContainer = join["box"]
	address_input = _field(DEFAULT_ADDRESS, "Host IP address, e.g. 192.168.1.20")
	address_input.name = "AddressInput"
	join_box.add_child(_labeled_field("HOST ADDRESS", address_input, 0))
	join_button = MenuKit.button("Join Game", &"", 0, 52)
	join_button.name = "JoinButton"
	join_box.add_child(join_button)


## The one-PC tip and the first-time two-machine walkthrough, in ONE compact panel (two
## separate panels plus their gap pushed the footer below 720): a "ONE PC" line and a
## "TWO PCS" line, each with its own coloured tag, in the small body size.
func _build_tips(parent: Control) -> void:
	var tips := PanelContainer.new()
	tips.name = "Tips"
	tips.add_theme_stylebox_override("panel", _tip_box(MenuTheme.ACCENT))
	parent.add_child(tips)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", MenuTheme.SP_XS)
	tips.add_child(rows)
	var one_pc := _tip_line("ONE PC", "Testing on one PC? Run two copies of Conquest: Host in one, then Join 127.0.0.1 : %d in the other." % DEFAULT_PORT, MenuTheme.ACCENT)
	one_pc["row"].name = "LocalTip"
	rows.add_child(one_pc["row"])
	var two_pcs := _tip_line("TWO PCS", "", MenuTheme.GOLD)
	two_pcs["row"].name = "TwoMachineTip"
	rows.add_child(two_pcs["row"])
	hint_label = two_pcs["label"]
	hint_label.name = "HintLabel"


## One line of the tips panel: a fixed-width coloured tag + wrapped small text.
func _tip_line(tag_text: String, text: String, accent: Color) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	var tag := MenuKit.label(tag_text, &"SectionLabel")
	tag.add_theme_color_override("font_color", accent)
	tag.custom_minimum_size = Vector2(84, 0)
	row.add_child(tag)
	var body := MenuKit.label(text, &"DimLabel", true)
	body.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	return {"row": row, "label": body}


## The host's LAN join line, beside the page title (no extra height), hidden until hosting.
func _build_host_info_strip() -> void:
	var title: Label = _page["title"]
	var title_row: Node = title.get_parent()
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	var strip := PanelContainer.new()
	strip.name = "HostInfo"
	strip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip.add_theme_stylebox_override("panel", _tip_box(MenuTheme.GOLD))
	strip.visible = false
	title_row.add_child(strip)
	_host_info_strip = strip
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_M)
	strip.add_child(h)
	var tag := MenuKit.label("SHARE", &"SectionLabel")
	tag.add_theme_color_override("font_color", MenuTheme.GOLD)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tag)
	host_info_label = MenuKit.label("", &"")
	host_info_label.name = "HostInfoLabel"
	host_info_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	host_info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(host_info_label)


func _build_footer() -> void:
	status_label = MenuKit.label("", &"", true)
	status_label.name = "StatusLabel"
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hints: HBoxContainer = _page["hints"]
	hints.add_child(status_label)

	var actions: HBoxContainer = _page["actions"]
	leave_button = MenuKit.button("Leave Lobby", MenuKit.GHOST, 190)
	leave_button.name = "LeaveButton"
	leave_button.visible = false
	actions.add_child(leave_button)
	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	actions.add_child(back_button)


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


func _tip_box(accent: Color) -> OrnateStyleBox:
	var sb := MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL_SUNK, 0.85)
	sb.border_color = Color(accent, 0.45)
	sb.ornament = OrnateStyleBox.Ornament.NONE
	sb.inner_line_color = Color(accent, 0.18)
	sb.shadow_size = 0.0
	sb.corner = 8.0
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _present_status(text: String, tone: String) -> void:
	MenuKit.set_status(status_label, text, tone)


## Place the lobby where this skin wants it: filling the page body under the header.
func _embed_lobby(lobby: Control) -> void:
	lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body: VBoxContainer = _page["body"]
	body.add_child(lobby)


func _enter_lobby_view(as_host: bool) -> void:
	if _setup_box != null:
		_setup_box.visible = false
	(_page["title"] as Label).text = "Duel Lobby" if is_duel() else "Lobby"
	var subtitle: Label = _page["subtitle"]
	if is_duel():
		subtitle.text = "Pick your unit; once you have both pressed Ready the duel begins."
	elif as_host:
		subtitle.text = "Vote on a map with your opponent; once you have both pressed Ready the match begins."
	elif _is_dedicated_session():
		subtitle.text = "Both players mark themselves ready; the dedicated server starts the match."
	else:
		subtitle.text = "Vote on a map with the host; once you have both pressed Ready the match begins."
	subtitle.visible = true
	_update_footer()


func _exit_lobby_view() -> void:
	if _setup_box != null:
		_setup_box.visible = true
	(_page["title"] as Label).text = TITLE_DUEL if is_duel() else TITLE_SETUP
	(_page["subtitle"] as Label).text = SUBTITLE_DUEL if is_duel() else SUBTITLE_SETUP
	_update_footer()
	MenuNav.focus_deferred(host_button)


## Back while idle; a Cancel / Leave button while hosting, dialling or seated.
func _update_footer() -> void:
	if back_button == null or leave_button == null:
		return
	var in_session: bool = _in_session()
	back_button.visible = not in_session
	leave_button.visible = in_session
	if is_host_active:
		leave_button.text = "Cancel Hosting"
	elif connect_state == ConnectState.CONNECTING:
		leave_button.text = "Cancel"
	else:
		leave_button.text = "Leave Lobby"


func _show_host_info(port: int) -> void:
	if host_info_label != null:
		host_info_label.text = _host_join_line(port)
	if _host_info_strip != null:
		_host_info_strip.visible = true


func _hide_host_info() -> void:
	if _host_info_strip != null:
		_host_info_strip.visible = false
