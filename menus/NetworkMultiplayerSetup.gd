extends Control

class_name NetworkMultiplayerSetup

# Network Multiplayer Setup Menu
# Allows players to host or join network multiplayer games

@onready var host_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/HostButton
@onready var host_with_client_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/HostWithClientButton
@onready var join_button: Button = $CenterContainer/VBoxContainer/NetworkButtons/JoinButton
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

@onready var join_container: VBoxContainer = $CenterContainer/VBoxContainer/JoinContainer
@onready var address_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/AddressInput
@onready var port_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/PortInput
@onready var player_name_input: LineEdit = $CenterContainer/VBoxContainer/JoinContainer/PlayerNameInput
@onready var connect_button: Button = $CenterContainer/VBoxContainer/JoinContainer/ConnectButton

@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

# Game mode manager for unified multiplayer
# Using the autoload singleton
var game_mode_manager: Node

# Lobby state
var is_hosting: bool = false
var connected_players: Array[String] = []
var lobby_container: VBoxContainer
var players_list_label: Label
var start_game_button: Button

func _ready() -> void:
	# Connect button signals
	if host_button:
		host_button.pressed.connect(_on_host_pressed)
	if host_with_client_button:
		host_with_client_button.pressed.connect(_on_host_with_client_pressed)
	if join_button:
		join_button.pressed.connect(_on_join_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if connect_button:
		connect_button.pressed.connect(_on_connect_pressed)
	
	# Hide join container initially
	if join_container:
		join_container.visible = false
	
	# Set default values
	if address_input:
		address_input.text = "127.0.0.1"
	if port_input:
		port_input.text = "8910"
	if player_name_input:
		player_name_input.text = "Player"
	
	# Create lobby UI (hidden initially)
	_create_lobby_ui()
	
	# Add lobby system test for development
	var lobby_test = Node.new()
	lobby_test.name = "LobbySystemTest"
	lobby_test.set_script(load("res://test_lobby_system.gd"))
	add_child(lobby_test)
	
	# Get game mode manager from autoload
	game_mode_manager = GameModeManager
	
	# Connect signals
	game_mode_manager.game_started.connect(_on_game_started)
	game_mode_manager.game_ended.connect(_on_game_ended)
	
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
	lobby_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_title.add_theme_font_size_override("font_size", 24)
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
	"""Handle Host button press"""
	print("[HOST] Starting network multiplayer host...")
	_update_status("Starting host...")
	
	# Disable buttons while connecting
	_set_buttons_enabled(false)
	
	# Start hosting using the unified system with P2P mode
	var host_success = await game_mode_manager.start_network_multiplayer_host("Host Player", "p2p")
	
	if host_success:
		print("[HOST] Host started successfully")
		
		# Get connection info for display
		var status = game_mode_manager.get_game_status()
		var connection_info = status.get("connection_info", {})
		var port = connection_info.get("port", 8910)
		
		print("[HOST] Connection info - Port: " + str(port))
		print("[HOST] Share this address with other players: 127.0.0.1:" + str(port))
		
		# Show collaborative lobby
		_show_collaborative_lobby(true, "Host Player")
	else:
		_update_status("Failed to start host. Please try again.")
		_set_buttons_enabled(true)

func _on_host_with_client_pressed() -> void:
	"""Handle Host with Client button press - starts host and launches client instance"""
	print("Starting network multiplayer host with automatic client...")
	_update_status("Starting host with client...")
	
	# Disable buttons while setting up
	_set_buttons_enabled(false)
	
	# Start hosting using the unified system
	var host_client_success = await game_mode_manager.start_network_multiplayer_host("Host Player", "local")
	
	if host_client_success:
		print("Host started successfully, launching client...")
		
		# Get the actual port the host is using
		var status = game_mode_manager.get_game_status()
		var connection_info = status.get("connection_info", {})
		var actual_port = connection_info.get("port", 8910)
		
		print("Host is running on port: " + str(actual_port))
		
		# Launch client instance
		_launch_simple_client_instance()
		
		# Show lobby instead of auto-starting game
		_show_lobby("127.0.0.1", actual_port)
		is_hosting = true
		connected_players = ["Host Player"]
		_update_players_list()
		
		# Wait for client to connect
		_update_status("Waiting for client to connect...")
		_monitor_for_client_connection()
	else:
		_update_status("Failed to start host. Please try again.")
		_set_buttons_enabled(true)

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
	var address = address_input.text if address_input else "127.0.0.1"
	var port_text = port_input.text if port_input else "8910"
	var player_name = player_name_input.text if player_name_input else "Player"
	
	var port = int(port_text)
	if port <= 0:
		port = 8910
	
	print("[CLIENT] Joining network game at %s:%d as %s" % [address, port, player_name])
	_update_status("Connecting to " + address + ":" + str(port) + "...")
	
	# Disable buttons while connecting
	_set_buttons_enabled(false)
	
	# Join using the unified system with P2P mode
	var join_success = await game_mode_manager.join_network_multiplayer(address, port, player_name, "p2p")
	
	if join_success:
		_update_status("Connected! Waiting for lobby...")
		print("[CLIENT] Successfully joined network game")
		
		# Show collaborative lobby
		_show_collaborative_lobby(false, player_name)
	else:
		print("[CLIENT] Failed to connect to host")
		_update_status("Failed to connect. Check address and port.")
		_set_buttons_enabled(true)

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
	# The lobby needs to receive network messages
	# This will be handled through MultiplayerGameState
	print("[SETUP] Lobby message forwarding setup complete")

func _on_lobby_game_starting(map_path: String) -> void:
	"""Handle game starting from lobby"""
	print("[SETUP] Game starting with map: " + map_path)
	# Lobby handles the scene transition

func _on_back_pressed() -> void:
	"""Handle Back button press"""
	print("Returning to multiplayer mode selection")
	
	# If we're in lobby, hide it first
	if is_hosting and lobby_container and lobby_container.visible:
		_hide_lobby()
		_update_status("Choose to host or join a network game")
		return
	
	# Clean up game mode manager
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
				_on_back_pressed()

func _show_lobby(address: String, port: int) -> void:
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
		connection_info_label.text = "Host Address: %s:%d" % [address, port]
	
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
		var connected_peers = network_stats.get("connected_peers", [])
		
		# Update connected players list
		var new_player_count = connected_peers.size() + 1  # +1 for host
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
	
	# Connect to game manager signals to receive network messages
	# This will be handled by the GameManager/MultiplayerGameState
	print("[CLIENT] Message listener setup complete")
