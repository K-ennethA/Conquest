extends Node

class_name MultiplayerManager

# Central multiplayer manager that coordinates all multiplayer systems
# Provides a simple interface for starting/joining multiplayer games
# Handles the integration between networking, game state, and turn systems

signal multiplayer_game_started(players: Array)
signal multiplayer_game_ended(winner_id: int)
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, player_name: String)
signal connection_status_changed(status: String)

# Core components
var _network_manager: NetworkManager
var _multiplayer_game_state: MultiplayerGameState
var _multiplayer_turn_system: MultiplayerTurnSystem

# Game state
var _is_multiplayer_active: bool = false
var _game_session_id: String = ""
var _local_player_id: int = -1
var _players: Dictionary = {}  # player_id -> player_info
var _game_settings: Dictionary = {}

# Connection info for sharing
var _host_connection_info: Dictionary = {}

func _ready() -> void:
	name = "MultiplayerManager"
	
	# Initialize components
	await _initialize_components()
	
	print("MultiplayerManager initialized")

func _initialize_components() -> void:
	"""Initialize all multiplayer components"""
	print("DEBUG: MultiplayerManager initializing components...")
	
	# Create NetworkManager if it doesn't exist
	_network_manager = get_node_or_null("/root/NetworkManager")
	if not _network_manager:
		print("DEBUG: Creating new NetworkManager...")
		_network_manager = NetworkManager.new()
		_network_manager.name = "NetworkManager"
		get_tree().root.add_child(_network_manager)
		
		# Wait for the node to be ready and force initialization
		await get_tree().process_frame
		await get_tree().process_frame  # Wait an extra frame to be sure
		
		# Manually call _ready if it hasn't been called
		if not _network_manager._is_initialized:
			print("DEBUG: Manually initializing NetworkManager...")
			_network_manager.initialize_backends()
			# Set initial network mode
			_network_manager.set_network_mode(NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT)
		
		print("DEBUG: NetworkManager initialization complete")
	else:
		print("DEBUG: Found existing NetworkManager")
	
	# Create MultiplayerGameState if it doesn't exist
	_multiplayer_game_state = get_node_or_null("/root/MultiplayerGameState")
	if not _multiplayer_game_state:
		print("DEBUG: Creating new MultiplayerGameState...")
		_multiplayer_game_state = MultiplayerGameState.new()
		_multiplayer_game_state.name = "MultiplayerGameState"
		get_tree().root.add_child(_multiplayer_game_state)
	else:
		print("DEBUG: Found existing MultiplayerGameState")
	
	# Create MultiplayerTurnSystem
	print("DEBUG: Creating MultiplayerTurnSystem...")
	_multiplayer_turn_system = MultiplayerTurnSystem.new()
	add_child(_multiplayer_turn_system)
	
	# Connect signals
	print("DEBUG: Connecting component signals...")
	_connect_component_signals()
	
	print("DEBUG: All components initialized")

func _connect_component_signals() -> void:
	"""Connect signals from all components"""
	if _network_manager:
		_network_manager.connection_established.connect(_on_connection_established)
		_network_manager.connection_lost.connect(_on_connection_lost)
		_network_manager.connection_failed.connect(_on_connection_failed)
		_network_manager.message_received.connect(_on_message_received)
		_network_manager.network_mode_changed.connect(_on_network_mode_changed)
	
	if _multiplayer_turn_system:
		_multiplayer_turn_system.multiplayer_turn_started.connect(_on_multiplayer_turn_started)
		_multiplayer_turn_system.multiplayer_turn_ended.connect(_on_multiplayer_turn_ended)

# Public API - Game Management
func start_local_multiplayer_game(player_names: Array[String] = ["Player 1", "Player 2"]) -> bool:
	"""Start a local multiplayer game for development/testing"""
	print("Starting local multiplayer game with players: %s" % str(player_names))
	
	# Switch to local development mode
	if not _network_manager.set_network_mode(NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT):
		print("Failed to set local development mode")
		return false
	
	# Start hosting
	if not _network_manager.start_host(8910):
		print("Failed to start local host")
		return false
	
	# Initialize game
	_initialize_multiplayer_game(player_names)
	
	return true

func start_p2p_multiplayer_game(player_name: String = "Host", max_players: int = 2) -> bool:
	"""Start a P2P multiplayer game"""
	print("Starting P2P multiplayer game as '%s' (max %d players)" % [player_name, max_players])
	
	# Switch to P2P mode
	if not _network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT):
		print("Failed to set P2P mode")
		return false
	
	# Start hosting
	if not _network_manager.start_host():
		print("Failed to start P2P host")
		return false
	
	# Store host info
	_host_connection_info = _network_manager.get_connection_info()
	
	# Initialize game with host player
	_initialize_multiplayer_game([player_name])
	
	print("P2P game started. Connection info: %s" % str(_host_connection_info))
	
	return true

func join_p2p_multiplayer_game(address: String, port: int, player_name: String = "Player") -> bool:
	"""Join a P2P multiplayer game"""
	print("Joining P2P game at %s:%d as '%s'" % [address, port, player_name])
	
	# Switch to P2P mode
	if not _network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT):
		print("Failed to set P2P mode")
		return false
	
	# Join host
	if not _network_manager.join_host(address, port):
		print("Failed to join P2P host")
		return false
	
	# Store player info
	_local_player_id = 1  # Will be updated when connection is established
	_players[_local_player_id] = {
		"name": player_name,
		"peer_id": -1,  # Will be updated
		"is_local": true,
		"is_ready": false
	}
	
	return true

func join_dedicated_server_game(address: String, port: int, username: String, password: String = "") -> bool:
	"""Join a dedicated server game (future implementation)"""
	print("Joining dedicated server at %s:%d as '%s'" % [address, port, username])
	
	# Switch to dedicated server mode
	if not _network_manager.set_network_mode(NetworkBackend.NetworkMode.DEDICATED_SERVER):
		print("Failed to set dedicated server mode")
		return false
	
	# Connect to server
	if not _network_manager.join_host(address, port):
		print("Failed to connect to dedicated server")
		return false
	
	# Authenticate
	if not _network_manager.authenticate_with_server(username, password):
		print("Failed to authenticate with server")
		return false
	
	return true

func disconnect_from_multiplayer() -> void:
	"""Disconnect from current multiplayer session"""
	print("Disconnecting from multiplayer")
	
	if _network_manager:
		_network_manager.disconnect_network()
	
	_cleanup_multiplayer_session()

func get_host_connection_info() -> Dictionary:
	"""Get connection info for sharing with other players"""
	return _host_connection_info.duplicate()

# Game State Management
func _initialize_multiplayer_game(player_names: Array[String]) -> void:
	"""Initialize a new multiplayer game session"""
	_game_session_id = _generate_session_id()
	_is_multiplayer_active = true
	
	# Create players
	_players.clear()
	for i in range(player_names.size()):
		var player_id = i
		_players[player_id] = {
			"name": player_names[i],
			"peer_id": 1 if i == 0 else -1,  # Host is peer 1
			"is_local": i == 0,  # First player is local for host
			"is_ready": false
		}
	
	_local_player_id = 0  # Host is player 0
	
	# Initialize game state
	var initial_state = _create_initial_game_state()
	_multiplayer_game_state.initialize_multiplayer_state(initial_state)
	
	# Initialize turn system
	var player_ids: Array[int] = []
	for key in _players.keys():
		player_ids.append(key)
	var base_turn_system = _get_base_turn_system()
	_multiplayer_turn_system.initialize_multiplayer_turns(base_turn_system, player_ids)
	
	# Set up player-peer mapping
	var mapping = {}
	for player_id in _players:
		mapping[_players[player_id]["peer_id"]] = player_id
	_multiplayer_turn_system.set_player_peer_mapping(mapping)
	
	print("Multiplayer game initialized with session ID: %s" % _game_session_id)
	multiplayer_game_started.emit(_players.keys())

func _create_initial_game_state() -> Dictionary:
	"""Create the initial game state for multiplayer"""
	# TODO: Get actual game state from current scene
	return {
		"session_id": _game_session_id,
		"players": _players.keys(),
		"current_player": 0,
		"turn_number": 1,
		"units": {},  # Will be populated from actual game
		"map_data": {},  # Will be populated from actual map
		"game_phase": "setup"
	}

func _get_base_turn_system() -> Node:
	"""Get the base turn system from the game"""
	# Try to find existing turn system
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		return TurnSystemManager.get_active_turn_system()
	
	# Fallback: look for turn system in scene
	var scene_root = get_tree().current_scene
	var turn_system = scene_root.get_node_or_null("TurnSystem")
	if turn_system:
		return turn_system
	
	print("WARNING: No base turn system found")
	return null

func _cleanup_multiplayer_session() -> void:
	"""Clean up multiplayer session data"""
	_is_multiplayer_active = false
	_game_session_id = ""
	_local_player_id = -1
	_players.clear()
	_host_connection_info.clear()
	_game_settings.clear()

# Player Management
func add_player(peer_id: int, player_name: String) -> int:
	"""Add a new player to the game"""
	# Find next available player ID
	var player_id = _players.size()
	
	_players[player_id] = {
		"name": player_name,
		"peer_id": peer_id,
		"is_local": false,
		"is_ready": false
	}
	
	print("Player added: %s (ID: %d, Peer: %d)" % [player_name, player_id, peer_id])
	player_joined.emit(player_id, player_name)
	
	# Update turn system mapping
	_update_player_peer_mapping()
	
	return player_id

func remove_player(peer_id: int) -> void:
	"""Remove a player from the game"""
	var player_id = _get_player_id_for_peer(peer_id)
	if player_id == -1:
		return
	
	var player_name = _players[player_id]["name"]
	_players.erase(player_id)
	
	print("Player removed: %s (ID: %d, Peer: %d)" % [player_name, player_id, peer_id])
	player_left.emit(player_id, player_name)
	
	# Update turn system mapping
	_update_player_peer_mapping()

func set_player_ready(player_id: int, ready: bool) -> void:
	"""Set a player's ready state"""
	if player_id in _players:
		_players[player_id]["is_ready"] = ready
		_multiplayer_turn_system.set_player_ready(player_id, ready)
		print("Player %d (%s) ready: %s" % [player_id, _players[player_id]["name"], ready])

func get_players() -> Dictionary:
	"""Get all players in the game"""
	return _players.duplicate()

func get_local_player_id() -> int:
	"""Get the local player's ID"""
	return _local_player_id

func is_local_player_turn() -> bool:
	"""Check if it's the local player's turn"""
	return _multiplayer_turn_system.is_local_player_turn()

# Utility methods
func _get_player_id_for_peer(peer_id: int) -> int:
	"""Get player ID for a peer ID"""
	for player_id in _players:
		if _players[player_id]["peer_id"] == peer_id:
			return player_id
	return -1

func _update_player_peer_mapping() -> void:
	"""Update the player-peer mapping in turn system"""
	var mapping = {}
	for player_id in _players:
		var peer_id = _players[player_id]["peer_id"]
		if peer_id != -1:
			mapping[peer_id] = player_id
	
	_multiplayer_turn_system.set_player_peer_mapping(mapping)

func _generate_session_id() -> String:
	"""Generate a unique session ID"""
	return "session_" + str(Time.get_ticks_msec()) + "_" + str(randi())

# Network event handlers
func _on_connection_established(peer_id: int) -> void:
	"""Handle connection established"""
	print("MultiplayerManager: Connection established with peer %d" % peer_id)
	
	_local_player_id = _network_manager.get_local_peer_id()
	
	# Update connection status
	connection_status_changed.emit("connected")
	
	# If we're joining a game, request player info
	if not _network_manager.is_host():
		_request_game_info()

func _on_connection_lost(peer_id: int) -> void:
	"""Handle connection lost"""
	print("MultiplayerManager: Connection lost with peer %d" % peer_id)
	
	# Remove player if they were in the game
	remove_player(peer_id)
	
	# Update connection status
	if _network_manager.get_connected_peers().is_empty():
		connection_status_changed.emit("disconnected")
		_cleanup_multiplayer_session()

func _on_connection_failed(error: String) -> void:
	"""Handle connection failure"""
	print("MultiplayerManager: Connection failed - %s" % error)
	connection_status_changed.emit("failed: " + error)
	_cleanup_multiplayer_session()

func _on_message_received(sender_id: int, message: Dictionary) -> void:
	"""Handle network messages"""
	match message.get("type", ""):
		"player_info_request":
			_handle_player_info_request(sender_id)
		"player_info_response":
			_handle_player_info_response(sender_id, message)
		"player_join_request":
			_handle_player_join_request(sender_id, message)

func _on_network_mode_changed(new_mode: NetworkBackend.NetworkMode) -> void:
	"""Handle network mode change"""
	var mode_name = NetworkBackend.NetworkMode.keys()[new_mode]
	print("MultiplayerManager: Network mode changed to %s" % mode_name)

# Game-specific message handlers
func _handle_player_info_request(sender_id: int) -> void:
	"""Handle request for player info from new connection"""
	if not _network_manager.is_host():
		return
	
	var response = {
		"type": "player_info_response",
		"session_id": _game_session_id,
		"players": _players,
		"game_settings": _game_settings
	}
	
	# TODO: Send to specific peer (need NetworkManager enhancement)
	print("Sending player info to peer %d" % sender_id)

func _handle_player_info_response(sender_id: int, message: Dictionary) -> void:
	"""Handle player info response from host"""
	var session_id = message.get("session_id", "")
	var players = message.get("players", {})
	var settings = message.get("game_settings", {})
	
	_game_session_id = session_id
	_players = players
	_game_settings = settings
	
	print("Received game info from host: session %s, %d players" % [session_id, players.size()])

func _handle_player_join_request(sender_id: int, message: Dictionary) -> void:
	"""Handle player join request"""
	if not _network_manager.is_host():
		return
	
	var player_name = message.get("player_name", "Unknown Player")
	add_player(sender_id, player_name)

func _request_game_info() -> void:
	"""Request game info from host"""
	var request = {
		"type": "player_info_request"
	}
	
	_network_manager.send_game_action("player_info_request", request)

# Turn system event handlers
func _on_multiplayer_turn_started(player_id: int) -> void:
	"""Handle multiplayer turn started"""
	print("MultiplayerManager: Turn started for player %d" % player_id)

func _on_multiplayer_turn_ended(player_id: int) -> void:
	"""Handle multiplayer turn ended"""
	print("MultiplayerManager: Turn ended for player %d" % player_id)

# Public interface for game integration
func submit_game_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a game action (for use by game systems)"""
	if not _is_multiplayer_active:
		return false
	
	return _multiplayer_turn_system.submit_turn_action(action_type, action_data)

func is_multiplayer_active() -> bool:
	"""Check if multiplayer is currently active"""
	return _is_multiplayer_active

func get_multiplayer_status() -> Dictionary:
	"""Get comprehensive multiplayer status"""
	return {
		"is_active": _is_multiplayer_active,
		"session_id": _game_session_id,
		"local_player_id": _local_player_id,
		"network_mode": NetworkBackend.NetworkMode.keys()[_network_manager.get_network_mode()] if _network_manager else "none",
		"connection_status": NetworkBackend.ConnectionStatus.keys()[_network_manager.get_connection_status()] if _network_manager else "disconnected",
		"players": _players,
		"is_host": _network_manager.is_host() if _network_manager else false,
		"current_turn_player": _multiplayer_turn_system.get_current_player_id() if _multiplayer_turn_system else -1
	}
