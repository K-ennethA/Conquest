extends Control

class_name NetworkMultiplayerSetup

# Network Multiplayer Setup Menu
# Allows players to host or join network multiplayer games

# Dev-only: "Host with Client" spawns a SECOND game instance (via OS.create_process)
# that auto-joins the host. This is a developer two-instance testing convenience, NOT a
# shipping feature. Gated OFF by default, mirroring MainMenu.ENABLE_DEV_TEST_HARNESS.
# When false the button is hidden and the handler refuses to run.
const ENABLE_HOST_AUTO_CLIENT := false

## Where the last address/port/name a player joined with is remembered, so the second
## machine does not have to re-type the host's LAN IP every single test run.
const NET_PREFS_PATH := "user://net.cfg"
## How long "Connecting..." may run before we tell the player it did not reach the host.
## Deliberately longer than the transport's own wait so the transport reports first when
## it can, and this is the backstop that guarantees the UI never hangs on "Connecting...".
const CONNECT_TIMEOUT_SEC := 8.0
const DEFAULT_PORT := 8910

## What the join half of this screen is doing right now. Drives the status text and
## which buttons are live; there is exactly one place each state is entered.
enum ConnectState { IDLE, CONNECTING, CONNECTED, REJECTED }

@onready var host_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/HostButton
@onready var host_with_client_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/HostWithClientButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/JoinButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

@onready var join_container: VBoxContainer = $CenterContainer/VBoxContainer/JoinContainer
@onready var address_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/FormCard/FormMargin/FormGrid/AddressInput
@onready var port_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/FormCard/FormMargin/FormGrid/PortInput
@onready var player_name_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/FormCard/FormMargin/FormGrid/PlayerNameInput
@onready var connect_button: Button = $CenterContainer/VBoxContainer/JoinContainer/ConnectButton

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
## "First time on two machines?" walkthrough. Optional so an older copy of the scene
## (or a test that builds this Control by hand) still works.
@onready var hint_label: Label = get_node_or_null("CenterContainer/VBoxContainer/HintLabel") as Label

# Game mode manager for unified multiplayer
# Using the autoload singleton
var game_mode_manager: Node

# Lobby state
var is_hosting: bool = false
# True whenever a host/lobby flow is active (plain Host or dev Host-with-Client). While
# true, ESC and the on-screen Cancel button tear the server peer down and return here.
var is_host_active: bool = false
# On-screen Cancel button shown over the lobby while hosting (created lazily).
var host_cancel_button: Button = null
var connected_players: Array[String] = []
var lobby_container: VBoxContainer
var players_list_label: Label
var start_game_button: Button

# --- Join/host hardening state ----------------------------------------------
## Current join state (see [enum ConnectState]).
var connect_state: int = ConnectState.IDLE
## Wall-clock deadline for the current connect attempt, in engine ticks. Only read
## while [member connect_state] is CONNECTING.
var _connect_deadline_msec: int = 0
## Big always-on-top label that keeps the host's join address visible even after the
## collaborative lobby covers the setup screen (created lazily, like the Cancel button).
var host_info_label: Label = null
## The address/port/name of the join attempt in flight, kept so the signal-driven state
## transitions can name them without re-reading (and re-validating) the form.
var _join_address: String = ""
var _join_port: int = DEFAULT_PORT
var _join_player_name: String = "Player"

# --- Transport ---------------------------------------------------------------
# HOST AND JOIN RUN ON NetSession, the consolidated server-authoritative transport -- the
# SAME session the in-battle command seam reads. That is the whole point: the old path
# (GameModeManager -> MultiplayerNetworkHandler -> P2PNetworkBackend) set the scene-tree peer
# behind NetSession's back, so NetSession's roster stayed empty, is_networked_match() was
# false in battle, and two connected machines each resolved their own moves locally. Routing
# the lobby through NetSession is what makes the battle actually shared.
#
# The legacy GameModeManager is still constructed and still torn down here (it owns the
# GameManager session object other screens query); it is simply no longer the transport.

## The live NetSession autoload, or null in a bare test harness that has no autoloads.
func _net() -> Node:
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		return NetSession
	return null

## True when NetSession currently holds a live (connected) peer -- host or client.
func _net_session_live() -> bool:
	var net: Node = _net()
	return net != null and net.has_method("is_connected_session") and bool(net.is_connected_session())

func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	MenuTheme.style_title(get_node_or_null("CenterContainer/VBoxContainer/TitleLabel") as Label, 32)
	MenuTheme.style_section_header(get_node_or_null("CenterContainer/VBoxContainer/JoinContainer/JoinTitle") as Label)
	MenuTheme.style_caption(status_label)
	MenuTheme.style_caption(hint_label)

	# Connect button signals
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if host_with_client_button:
		host_with_client_button.pressed.connect(_on_host_with_client_pressed)
		# Dev-only two-instance testing feature: hide unless explicitly enabled.
		host_with_client_button.visible = ENABLE_HOST_AUTO_CLIENT
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)
	
	# Hide join container initially
	if join_container:
		join_container.visible = false
	
	# Set default values, then let any remembered ones win (see _load_net_prefs).
	if address_input:
		address_input.text = "127.0.0.1"
	if port_input:
		port_input.text = str(DEFAULT_PORT)
	if player_name_input:
		player_name_input.text = "Player"
	_load_net_prefs()

	if hint_label:
		hint_label.text = _first_time_hint()

	# Create lobby UI (hidden initially)
	_create_lobby_ui()

	# Dev-only lobby probe. dev_scripts/ is excluded from exported builds
	# (export_presets.cfg), so this must never be a hard dependency of the menu.
	if ResourceLoader.exists("res://dev_scripts/test_lobby_system.gd"):
		var lobby_test := Node.new()
		lobby_test.name = "LobbySystemTest"
		lobby_test.set_script(load("res://dev_scripts/test_lobby_system.gd"))
		add_child(lobby_test)

	# Get game mode manager from autoload
	game_mode_manager = GameModeManager
	
	# Connect signals
	game_mode_manager.game_started.connect(_on_game_started)
	game_mode_manager.game_ended.connect(_on_game_ended)

	# NetSession is the transport, so the join state machine is driven by ITS signals:
	#   join_rejected      -- the build gate refused us (looks like a successful connect,
	#                         then vanishes, so it gets its own explicit state)
	#   roster_changed     -- we were seated; this is what "connected" actually means
	#   connection_failed  -- the socket never came up
	#   disconnected       -- the host went away (or dropped us after a refusal)
	var net: Node = _net()
	if net != null:
		if net.has_signal("join_rejected") and not net.join_rejected.is_connected(_on_join_rejected):
			net.join_rejected.connect(_on_join_rejected)
		if net.has_signal("roster_changed") and not net.roster_changed.is_connected(_on_net_roster_changed):
			net.roster_changed.connect(_on_net_roster_changed)
		if net.has_signal("connection_failed") and not net.connection_failed.is_connected(_on_net_connection_failed):
			net.connection_failed.connect(_on_net_connection_failed)
		if net.has_signal("disconnected") and not net.disconnected.is_connected(_on_net_disconnected):
			net.disconnected.connect(_on_net_disconnected)

	_update_status("Choose to host or join a network game")
	
	print("Network Multiplayer Setup initialized")

func _create_lobby_ui() -> void:
	"""Create the lobby UI elements"""
	# Create lobby container
	lobby_container = VBoxContainer.new()
	lobby_container.name = "LobbyContainer"
	lobby_container.visible = false
	
	# Add lobby title
	var lobby_title = Label.new()
	lobby_title.text = "MULTIPLAYER LOBBY"
	MenuTheme.style_title(lobby_title, 24)
	lobby_container.add_child(lobby_title)
	
	# Add spacing
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer1)
	
	# Add connection info label
	var connection_info = Label.new()
	connection_info.name = "ConnectionInfo"
	connection_info.text = "Host Address: 127.0.0.1:8910"
	connection_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(connection_info)
	
	# Add spacing
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer2)
	
	# Add map selection section
	var map_section_title = Label.new()
	map_section_title.text = "Map Selection:"
	map_section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(map_section_title)
	
	# Add map dropdown
	var map_dropdown = OptionButton.new()
	map_dropdown.name = "MapDropdown"
	map_dropdown.custom_minimum_size = Vector2(300, 40)
	
	# Populate with available maps
	var available_maps = MapLoader.get_available_maps()
	if available_maps.is_empty():
		map_dropdown.add_item("Default Skirmish (5x5)")
		map_dropdown.set_item_metadata(0, "res://game/maps/resources/default_skirmish.tres")
	else:
		for i in range(available_maps.size()):
			var map_path = available_maps[i]
			var map_resource = load(map_path) as MapResource
			if map_resource:
				var display_name = map_resource.map_name + " (" + str(map_resource.width) + "x" + str(map_resource.height) + ")"
				map_dropdown.add_item(display_name)
				map_dropdown.set_item_metadata(i, map_path)
			else:
				map_dropdown.add_item(map_path.get_file().get_basename())
				map_dropdown.set_item_metadata(i, map_path)
	
	# Select default map by default
	map_dropdown.selected = 0
	map_dropdown.item_selected.connect(_on_map_selected)
	
	# Center the dropdown
	var map_container = HBoxContainer.new()
	map_container.alignment = BoxContainer.ALIGNMENT_CENTER
	map_container.add_child(map_dropdown)
	lobby_container.add_child(map_container)
	
	# Add map info label
	var map_info_label = Label.new()
	map_info_label.name = "MapInfo"
	map_info_label.text = "A basic 5x5 map for quick battles"
	map_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_info_label.custom_minimum_size = Vector2(400, 0)
	lobby_container.add_child(map_info_label)
	
	# Add spacing
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer3)
	
	# Add players list
	var players_title = Label.new()
	players_title.text = "Connected Players:"
	players_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_container.add_child(players_title)
	
	players_list_label = Label.new()
	players_list_label.name = "PlayersList"
	players_list_label.text = "• Host Player (You)"
	players_list_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	players_list_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	players_list_label.custom_minimum_size = Vector2(0, 100)
	lobby_container.add_child(players_list_label)
	
	# Add spacing
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 20)
	lobby_container.add_child(spacer4)
	
	# Add start game button
	start_game_button = Button.new()
	start_game_button.text = "START GAME"
	start_game_button.custom_minimum_size = Vector2(200, 50)
	start_game_button.pressed.connect(_on_start_game_pressed)
	
	# Center the button
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	button_container.add_child(start_game_button)
	lobby_container.add_child(button_container)
	
	# Add lobby container to main container
	var main_container = get_node("CenterContainer/VBoxContainer")
	if main_container:
		main_container.add_child(lobby_container)
	
	# Update map info for default selection
	_update_map_info()

func _on_host_pressed() -> void:
	"""Handle Host button press: open a NetSession listen-server and show the lobby."""
	print("[HOST] Starting network multiplayer host...")
	_update_status("Starting host...")

	# Disable buttons while connecting
	_set_buttons_enabled(false)

	var port: int = DEFAULT_PORT
	var host_name: String = _host_display_name()
	var err: int = _start_net_host(host_name, port)

	if err != OK:
		print("[HOST] Host failed to start: %s" % error_string(err))
		_update_status("Could not start hosting on port %d (%s). Another copy of Conquest may already be hosting." % [port, error_string(err)])
		_set_buttons_enabled(true)
		return

	print("[HOST] Host started successfully on port " + str(port))
	for lan_address in _lan_addresses():
		print("[HOST] Players on your network join: %s:%d" % [lan_address, port])

	is_hosting = true
	_update_status(_host_join_line(port))

	# Show collaborative lobby
	_show_collaborative_lobby(true, host_name)

	# Enter host-active state and show a Cancel affordance over the lobby.
	is_host_active = true
	_show_host_cancel_button()
	# The lobby hides the status label, so the join address gets its own always-on-top
	# label -- the other machine needs to read it off this screen.
	_show_host_info(port)

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

## The host's display name. Reuses the remembered join name when the player set one, so both
## machines show a name the human chose rather than two "Player"s.
func _host_display_name() -> String:
	if player_name_input != null:
		var typed: String = player_name_input.text.strip_edges()
		if typed != "" and typed != "Player":
			return typed
	return "Host Player"

func _on_host_with_client_pressed() -> void:
	"""Handle Host with Client button press - starts host and launches client instance"""
	# Dev-only guard: refuse to spawn a second instance unless explicitly enabled
	# (defends the KEY_2 shortcut and any stray callers even though the button is hidden).
	if not ENABLE_HOST_AUTO_CLIENT:
		print("[HOST] Host-with-Client is disabled (dev-only feature). Ignoring.")
		_update_status("Host with Client is a dev-only feature (disabled).")
		return
	print("Starting network multiplayer host with automatic client...")

	# Deliberately the SAME code path a human takes (NetSession listen server + collaborative
	# lobby). The harness only adds the second process; if it ever diverges from the real Host
	# button it stops testing the thing that ships.
	_on_host_pressed()
	if not is_host_active:
		return  # _on_host_pressed already explained the failure.

	_launch_simple_client_instance()

func _launch_simple_client_instance() -> void:
	"""Launch client using AutoClientDetector system"""
	print("Launching client instance with AutoClientDetector...")
	
	# Use the AutoClientDetector system for consistency
	var success = AutoClientDetector.launch_client()
	
	if success:
		print("Client instance launched successfully")
	else:
		print("Failed to launch client instance")

func _launch_client_instance(port: int = 8910) -> void:
	"""Launch a second instance of the game that will automatically join as client"""
	print("Launching client instance...")
	
	# Get the executable path
	var executable_path = OS.get_executable_path()
	print("Executable path: " + executable_path)
	
	# Check if we're running in the editor
	if OS.is_debug_build() and executable_path.ends_with("Godot_v4.6-stable_win64.exe"):
		print("Running in editor - launching with project path")
		# When running in editor, we need to launch Godot with the project path
		var project_path = ProjectSettings.globalize_path("res://")
		var arguments = [
			"--path", project_path,
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=" + str(port),
			"--multiplayer-player-name=Client Player"
		]
		
		print("Editor mode - launching client with arguments: " + str(arguments))
		
		# Launch the process
		var pid = OS.create_process(executable_path, arguments)
		if pid > 0:
			print("Client instance launched with PID: " + str(pid))
			_update_status("Client instance launched (PID: " + str(pid) + ")")
		else:
			print("Failed to launch client instance")
			_update_status("Failed to launch client instance")
	else:
		print("Running as exported game")
		# Launch with special arguments to auto-join with the correct port
		var arguments = [
			"--multiplayer-auto-join",
			"--multiplayer-address=127.0.0.1",
			"--multiplayer-port=" + str(port),
			"--multiplayer-player-name=Client Player"
		]
		
		print("Launching client with arguments: " + str(arguments))
		
		# Launch the process
		var pid = OS.create_process(executable_path, arguments)
		if pid > 0:
			print("Client instance launched with PID: " + str(pid))
			_update_status("Client instance launched (PID: " + str(pid) + ")")
		else:
			print("Failed to launch client instance")
			_update_status("Failed to launch client instance")

func _on_join_pressed() -> void:
	"""Handle Join button press"""
	print("Showing join options...")
	
	# Show join container
	if join_container:
		join_container.visible = true
	
	# Hide main buttons
	if host_button:
		host_button.visible = false
	if host_with_client_button:
		host_with_client_button.visible = false
	if join_button:
		join_button.visible = false
	
	_update_status("Enter the host's address and port to join")

func _on_connect_pressed() -> void:
	"""Handle Connect button press"""
	if connect_state == ConnectState.CONNECTING:
		return  # Already dialling -- a second press must not stack two attempts.

	var address: String = (address_input.text if address_input else "127.0.0.1").strip_edges()
	var port_text: String = port_input.text if port_input else str(DEFAULT_PORT)
	var player_name: String = (player_name_input.text if player_name_input else "Player").strip_edges()
	if player_name == "":
		player_name = "Player"

	# Validate the shape BEFORE touching the socket: a typo'd address otherwise burns the
	# full connect timeout before saying anything useful.
	if not _is_valid_address(address):
		_update_status("That address does not look right. Use the host's LAN IP, e.g. 192.168.1.24")
		return
	var port: int = int(port_text)
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
	_update_status("Connecting to %s:%d ..." % [address, port])

	# Disable buttons while connecting
	_set_buttons_enabled(false)

	# Dial through NetSession -- the same session the battle's command seam reads. The hello /
	# version handshake fires the moment the socket comes up (NetSession._on_connected_to_server),
	# and the outcome arrives on a signal, never on this call's return value: create_client()
	# only reports that the socket could be OPENED.
	var net: Node = _net()
	if net == null:
		connect_state = ConnectState.IDLE
		_update_status("Networking is unavailable in this build.")
		_set_buttons_enabled(true)
		return
	net.leave()  # Drop any half-open peer from a previous attempt.
	var err: int = int(net.join_game(address, player_name, port))
	if err != OK:
		connect_state = ConnectState.IDLE
		print("[CLIENT] join_game failed immediately: %s" % error_string(err))
		_update_status("Could not open a connection to %s:%d (%s)." % [address, port, error_string(err)])
		_set_buttons_enabled(true)
		return

	# Countdown runs alongside the join (deliberately NOT awaited) so the player sees the
	# attempt tick down instead of a frozen "Connecting..." forever. It is the backstop for
	# the case where the transport reports nothing at all.
	_run_connect_countdown(address, port)


## NetSession seated us (or the roster moved). Being IN the roster is what "connected"
## actually means on this transport -- the socket coming up only means the hello is in
## flight, and a build mismatch is refused after that point.
func _on_net_roster_changed(_roster: Dictionary) -> void:
	if connect_state != ConnectState.CONNECTING:
		return
	var net: Node = _net()
	if net == null or net.is_server():
		return
	if int(net.local_slot()) < 0:
		return
	connect_state = ConnectState.CONNECTED
	print("[CLIENT] Successfully joined network game (slot %d)" % int(net.local_slot()))
	_update_status("Connected to %s:%d. Waiting for the lobby..." % [_join_address, _join_port])
	_show_collaborative_lobby(false, _join_player_name)


## The socket never came up.
func _on_net_connection_failed() -> void:
	print("[CLIENT] Transport reported connection_failed")
	_fail_connect(_join_address, _join_port)


## The host went away. Harmless noise after a refusal (which owns the message) or when we
## are not in a join flow at all; otherwise it is the end of this attempt/session.
func _on_net_disconnected() -> void:
	if connect_state == ConnectState.REJECTED:
		return  # _on_join_rejected already said why, and it is the more useful message.
	if connect_state == ConnectState.CONNECTING:
		_fail_connect(_join_address, _join_port)
		return
	if connect_state == ConnectState.CONNECTED:
		connect_state = ConnectState.IDLE
		if collaborative_lobby and is_instance_valid(collaborative_lobby):
			collaborative_lobby.queue_free()
			collaborative_lobby = null
		if join_container:
			join_container.visible = true
		if status_label:
			status_label.visible = true
		_set_buttons_enabled(true)
		_update_status("The host closed the game.")


## Dev harness entry point (--multiplayer-auto-join, see systems/multiplayer_launcher.gd):
## fill the join form and press Connect on the SAME path a human uses, so the two-instance
## harness can never drift from the flow that ships.
func begin_auto_join(address: String, port: int, player_name: String) -> void:
	_on_join_pressed()
	if address_input:
		address_input.text = address
	if port_input:
		port_input.text = str(port)
	if player_name_input:
		player_name_input.text = player_name
	_on_connect_pressed()


## Tick the visible connect countdown until we leave the CONNECTING state, then declare
## the attempt dead if the deadline ran out first.
func _run_connect_countdown(address: String, port: int) -> void:
	while connect_state == ConnectState.CONNECTING:
		if not is_inside_tree():
			return
		var remaining_msec: int = _connect_deadline_msec - Time.get_ticks_msec()
		if remaining_msec <= 0:
			_fail_connect(address, port)
			return
		_update_status("Connecting to %s:%d ... (%ds)" % [address, port, int(ceil(remaining_msec / 1000.0))])
		await get_tree().create_timer(0.25).timeout


## Leave CONNECTING with the "we never reached the host" explanation. Idempotent.
func _fail_connect(address: String, port: int) -> void:
	if connect_state != ConnectState.CONNECTING:
		return
	connect_state = ConnectState.IDLE
	# Drop the half-open peer, else the next Connect press hits a socket that is still dialling.
	var net: Node = _net()
	if net != null:
		net.leave()
	_update_status("Could not reach %s:%d - check the address, that the host clicked Host, and that Windows Firewall allowed Conquest on both machines." % [address, port])
	_set_buttons_enabled(true)


## The host refused this peer (build/protocol mismatch, full lobby). Arrives on the
## NetSession transport AFTER the socket came up, so it can land during or just after a
## seemingly successful connect -- either way it is the final word on this attempt.
func _on_join_rejected(reason: String, info: Dictionary) -> void:
	connect_state = ConnectState.REJECTED
	var explanation: String = NetProtocol.describe_rejection(reason, info)
	print("[CLIENT] Join refused: " + explanation)
	# Drop any lobby we optimistically opened, and put the join form back.
	if collaborative_lobby and is_instance_valid(collaborative_lobby):
		collaborative_lobby.queue_free()
		collaborative_lobby = null
	if join_container:
		join_container.visible = true
	if status_label:
		status_label.visible = true
	_set_buttons_enabled(true)
	_update_status(explanation)

# Collaborative lobby
var collaborative_lobby: Control = null

func _show_collaborative_lobby(as_host: bool, player_name: String) -> void:
	"""Show the collaborative lobby"""
	print("[SETUP] Showing collaborative lobby (host: " + str(as_host) + ")")
	
	# Hide main menu
	if host_button:
		host_button.visible = false
	if host_with_client_button:
		host_with_client_button.visible = false
	if join_button:
		join_button.visible = false
	if join_container:
		join_container.visible = false
	if status_label:
		status_label.visible = false
	
	# TEMPORARY: Use simple test lobby to isolate issue
	# var test_script = load("res://menus/SimpleLobbyTest.gd")
	# if test_script:
	# 	collaborative_lobby = Control.new()
	# 	collaborative_lobby.set_script(test_script)
	# 	collaborative_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 	add_child(collaborative_lobby)
	# 	return
	
	# Create collaborative lobby directly (not from scene)
	var lobby_script = load("res://menus/CollaborativeLobby.gd")
	if not lobby_script:
		print("[SETUP] ERROR: Could not load CollaborativeLobby script")
		_update_status("Error: Could not load lobby")
		_set_buttons_enabled(true)
		return
	
	print("[SETUP] Creating lobby control node...")
	collaborative_lobby = Control.new()
	collaborative_lobby.name = "CollaborativeLobby"
	collaborative_lobby.set_script(lobby_script)
	collaborative_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(collaborative_lobby)
	
	print("[SETUP] Lobby added to scene tree, waiting for _ready...")
	
	# Wait for lobby to be ready
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame to be safe
	
	print("[SETUP] Initializing lobby...")
	
	# Initialize lobby
	if collaborative_lobby and collaborative_lobby.has_method("initialize"):
		collaborative_lobby.initialize(as_host, player_name)
		if collaborative_lobby.has_signal("game_starting"):
			collaborative_lobby.game_starting.connect(_on_lobby_game_starting)
		print("[SETUP] Lobby initialized successfully")
	else:
		print("[SETUP] ERROR: Lobby missing initialize method or lobby is null")
		_update_status("Error: Lobby initialization failed")
		_set_buttons_enabled(true)
		return
	
	# Setup network message forwarding
	_setup_lobby_message_forwarding()
	print("[SETUP] Lobby setup complete")

func _setup_lobby_message_forwarding() -> void:
	"""Setup forwarding of network messages to lobby"""
	# Nothing to wire: the lobby subscribes to NetSession.lobby_message itself (the legacy
	# MultiplayerGameState relay that used to find the lobby by scene-tree search is deleted).
	print("[SETUP] Lobby message forwarding setup complete")

func _on_lobby_game_starting(map_path: String) -> void:
	"""Handle game starting from lobby"""
	print("[SETUP] Game starting with map: " + map_path)
	# Lobby handles the scene transition

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

## Keep the host's join address readable even after the collaborative lobby covers this
## screen. Same lazy always-on-top pattern as the Cancel button.
func _show_host_info(port: int) -> void:
	if host_info_label == null or not is_instance_valid(host_info_label):
		host_info_label = Label.new()
		host_info_label.name = "HostInfoLabel"
		host_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		host_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		host_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host_info_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		host_info_label.offset_left = 180
		host_info_label.offset_right = -24
		host_info_label.offset_top = 24
		host_info_label.offset_bottom = 96
		host_info_label.add_theme_font_size_override("font_size", 18)
		add_child(host_info_label)
	host_info_label.text = _host_join_line(port)
	host_info_label.visible = true
	host_info_label.move_to_front()

func _hide_host_info() -> void:
	if host_info_label and is_instance_valid(host_info_label):
		host_info_label.queue_free()
	host_info_label = null

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
	if cfg.load(NET_PREFS_PATH) != OK:
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
	cfg.load(NET_PREFS_PATH)  # Preserve any other sections; ignore load failure.
	cfg.set_value("join", "address", address)
	cfg.set_value("join", "port", port)
	cfg.set_value("join", "player_name", player_name)
	cfg.save(NET_PREFS_PATH)


func _show_host_cancel_button() -> void:
	"""Show a Cancel button over the lobby that tears down hosting at any stage."""
	if host_cancel_button and is_instance_valid(host_cancel_button):
		host_cancel_button.visible = true
		host_cancel_button.move_to_front()
		return

	host_cancel_button = Button.new()
	host_cancel_button.name = "HostCancelButton"
	host_cancel_button.text = "Cancel"
	host_cancel_button.custom_minimum_size = Vector2(140, 44)
	host_cancel_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	host_cancel_button.position = Vector2(24, 24)
	host_cancel_button.pressed.connect(_on_cancel_hosting_pressed)
	# Added last so it draws on top of the full-rect lobby control.
	add_child(host_cancel_button)
	host_cancel_button.move_to_front()

func _on_cancel_hosting_pressed() -> void:
	"""Cancel button / ESC while hosting: tear down and return to setup."""
	print("[HOST] Cancel requested - tearing down host...")
	_teardown_hosting()

func _teardown_hosting() -> void:
	"""Stop hosting, close the server peer, and restore the setup screen.

	NetSession.leave() closes the ENet peer, nulls the scene-tree multiplayer_peer and
	empties the roster, so no listener and no half-open socket outlives this screen. The
	legacy GameModeManager session is ended too -- it is no longer the transport, but it
	still owns a GameManager session object other screens query."""
	is_host_active = false
	is_hosting = false

	# Tear down the network peer (NetSession is the transport) and the legacy game session.
	var net: Node = _net()
	if net != null:
		net.leave()
	if game_mode_manager:
		game_mode_manager.end_current_game()

	# Remove the collaborative lobby if it was shown (plain Host path).
	if collaborative_lobby and is_instance_valid(collaborative_lobby):
		collaborative_lobby.queue_free()
		collaborative_lobby = null

	# Hide the legacy lobby container (dev Host-with-Client path).
	if lobby_container:
		lobby_container.visible = false
	connected_players.clear()

	# Remove the Cancel button and the host's join-address banner.
	if host_cancel_button and is_instance_valid(host_cancel_button):
		host_cancel_button.queue_free()
		host_cancel_button = null
	_hide_host_info()

	# Restore the setup screen.
	if host_button:
		host_button.visible = true
	if host_with_client_button:
		host_with_client_button.visible = ENABLE_HOST_AUTO_CLIENT
	if join_button:
		join_button.visible = true
	if status_label:
		status_label.visible = true
	_set_buttons_enabled(true)
	_update_status("Choose to host or join a network game")

func _on_back_pressed() -> void:
	"""Handle Back button press"""
	# If a host/lobby flow is active, Back cancels hosting instead of leaving the scene.
	if is_host_active:
		_teardown_hosting()
		return

	print("Returning to multiplayer mode selection")
	
	# If we're in lobby, hide it first
	if is_hosting and lobby_container and lobby_container.visible:
		_hide_lobby()
		_update_status("Choose to host or join a network game")
		return
	
	# Drop any live session (a connected client backing out) plus the legacy game session.
	var net: Node = _net()
	if net != null and _net_session_live():
		net.leave()
	if game_mode_manager:
		game_mode_manager.end_current_game()

	get_tree().change_scene_to_file("res://menus/MultiplayerModeSelection.tscn")

func _start_game_with_multiplayer() -> void:
	"""Start the game with multiplayer enabled"""
	print("Starting multiplayer game...")
	
	# Set game settings for multiplayer
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	GameSettings.set_turn_system(TurnSystemBase.TurnSystemType.TRADITIONAL)  # Default to traditional for multiplayer
	
	# Ensure we have a map selected (use default if none)
	var selected_map = GameSettings.get_selected_map()
	if selected_map.is_empty():
		print("No map selected, using default map")
		GameSettings.set_selected_map("res://game/maps/resources/default_skirmish.tres")
	else:
		print("Using selected map: " + selected_map)
	
	# Load the game scene
	get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")

func _update_status(text: String) -> void:
	"""Update status label"""
	if status_label:
		status_label.text = text
	print("Status: " + text)

func _set_buttons_enabled(enabled: bool) -> void:
	"""Enable/disable all buttons"""
	if host_button:
		host_button.disabled = not enabled
	if host_with_client_button:
		host_with_client_button.disabled = not enabled
	if join_button:
		join_button.disabled = not enabled
	if connect_button:
		connect_button.disabled = not enabled
	if back_button:
		back_button.disabled = not enabled
	if start_game_button:
		# Start game button has its own logic based on player count
		pass

# Signal handlers
func _on_game_started(mode: GameManager.GameMode) -> void:
	"""Handle game started"""
	print("Network multiplayer game started in mode: %s" % GameManager.GameMode.keys()[mode])

func _on_game_ended(winner_id: int) -> void:
	"""Handle game ended"""
	print("Network multiplayer game ended, winner: %d" % winner_id)

# Handle input for quick navigation
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_1:
				if host_button and host_button.visible:
					_on_host_pressed()
			KEY_2:
				if host_with_client_button and host_with_client_button.visible:
					_on_host_with_client_pressed()
			KEY_3:
				if join_button and join_button.visible:
					_on_join_pressed()
			KEY_ENTER:
				if connect_button and connect_button.visible:
					_on_connect_pressed()
			KEY_ESCAPE:
				if is_host_active:
					_teardown_hosting()
				else:
					_on_back_pressed()

func _show_lobby(_address: String, port: int) -> void:
	"""Show the multiplayer lobby"""
	print("Showing multiplayer lobby...")
	
	# Hide main menu buttons
	if host_button:
		host_button.visible = false
	if host_with_client_button:
		host_with_client_button.visible = false
	if join_button:
		join_button.visible = false
	if join_container:
		join_container.visible = false
	
	# Update connection info
	var connection_info_label = lobby_container.get_node_or_null("ConnectionInfo")
	if connection_info_label:
		# Show the address ANOTHER machine can dial, not the loopback one this process used.
		connection_info_label.text = _host_join_line(port)
	
	# Show lobby
	if lobby_container:
		lobby_container.visible = true
	
	_update_status("Lobby active - waiting for players to join")

func _update_players_list() -> void:
	"""Update the players list in the lobby"""
	if not players_list_label:
		return
	
	var players_text = ""
	for i in range(connected_players.size()):
		var player_name = connected_players[i]
		if i == 0:
			players_text += "• %s (Host)\n" % player_name
		else:
			players_text += "• %s\n" % player_name
	
	players_list_label.text = players_text
	
	# Enable start button only if we have at least 2 players (host + at least 1 client)
	if start_game_button:
		start_game_button.disabled = connected_players.size() < 2

func _monitor_for_client_connection() -> void:
	"""Monitor for client connections"""
	print("Monitoring for client connections...")
	
	# Check every second for new connections
	while is_hosting and lobby_container and lobby_container.visible:
		await get_tree().create_timer(1.0).timeout
		
		# Check game status for connected peers
		var status = game_mode_manager.get_game_status()
		var network_stats = status.get("network_stats", {})
		# network_stats["connected_peers"] is an int peer COUNT (see
		# NetworkManager.get_network_statistics), not an Array. Calling .size()
		# on it crashed with "Nonexistent function 'size' in base 'int'".
		# Guard both shapes to be safe.
		var connected_peers_stat = network_stats.get("connected_peers", 0)
		var peer_count := 0
		if connected_peers_stat is int:
			peer_count = connected_peers_stat
		elif connected_peers_stat is Array:
			peer_count = connected_peers_stat.size()

		# Update connected players list
		var new_player_count = peer_count + 1  # +1 for host
		if new_player_count > connected_players.size():
			# New player joined
			for i in range(connected_players.size(), new_player_count):
				connected_players.append("Player %d" % (i + 1))
			
			_update_players_list()
			_update_status("Player joined! (%d/2 players)" % connected_players.size())
			print("Client connected! Total players: %d" % connected_players.size())

func _on_start_game_pressed() -> void:
	"""Handle Start Game button press"""
	print("[HOST] Starting multiplayer game from lobby...")
	
	# Require at least 2 players (host + 1 client)
	if connected_players.size() < 2:
		_update_status("Need at least 2 players to start the game!")
		return
	
	_update_status("Starting game...")
	
	# Disable start button
	if start_game_button:
		start_game_button.disabled = true
	
	# Send "game_starting" message to all connected clients
	print("[HOST] Broadcasting game start to all clients...")
	_broadcast_game_start()
	
	# Start the game locally
	_start_game_with_multiplayer()

func _hide_lobby() -> void:
	"""Hide the lobby and return to main menu"""
	if lobby_container:
		lobby_container.visible = false
	
	# Show main menu buttons
	if host_button:
		host_button.visible = true
	if host_with_client_button:
		host_with_client_button.visible = true
	if join_button:
		join_button.visible = true
	
	# Reset state
	is_hosting = false
	connected_players.clear()
	_hide_host_info()
	_set_buttons_enabled(true)

func _on_map_selected(index: int) -> void:
	"""Handle map selection change"""
	var map_dropdown = lobby_container.get_node_or_null("MapDropdown")
	if not map_dropdown:
		return
	
	var selected_map_path = map_dropdown.get_item_metadata(index)
	print("[HOST] Map selected: " + selected_map_path)
	
	# Update GameSettings with selected map
	GameSettings.set_selected_map(selected_map_path)
	
	# Update map info display
	_update_map_info()

func _update_map_info() -> void:
	"""Update the map info label with current map details"""
	var map_info_label = lobby_container.get_node_or_null("MapInfo")
	if not map_info_label:
		return
	
	var selected_map_path = GameSettings.get_selected_map()
	if selected_map_path.is_empty():
		map_info_label.text = "No map selected"
		return
	
	# Load map resource to get info
	var map_resource = load(selected_map_path) as MapResource
	if map_resource:
		var info = map_resource.get_display_info()
		map_info_label.text = info.get("description", "No description available")
	else:
		map_info_label.text = "Map: " + selected_map_path.get_file().get_basename()

func _broadcast_game_start() -> void:
	"""Broadcast game start message to all connected clients"""
	if not game_mode_manager:
		print("[HOST] ERROR: GameModeManager not available")
		return
	
	# Ensure we have a map selected
	var selected_map = GameSettings.get_selected_map()
	if selected_map.is_empty():
		selected_map = "res://game/maps/resources/default_skirmish.tres"
		GameSettings.set_selected_map(selected_map)
	
	print("[HOST] Broadcasting game start with map: " + selected_map)
	
	# Send game start action through the multiplayer system
	var success = game_mode_manager.submit_action("game_start", {
		"map": selected_map,
		"turn_system": GameSettings.selected_turn_system
	})
	
	if success:
		print("[HOST] Game start message broadcasted to clients")
	else:
		print("[HOST] WARNING: Failed to broadcast game start message")

func _setup_client_message_listener() -> void:
	"""Setup listener for messages from host (for clients)"""
	if not game_mode_manager:
		return
	
	# Nothing to wire: incoming messages arrive on NetSession (lobby_message / action_applied),
	# not through GameManager. Kept as a no-op hook; the legacy relay is deleted.
	print("[CLIENT] Message listener setup complete")
