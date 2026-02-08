extends NetworkHandler

class_name MultiplayerNetworkHandler

# Concrete network handler that uses the existing multiplayer system
# Bridges between GameManager and the modular networking architecture

var _network_manager: NetworkManager
var _multiplayer_game_state: MultiplayerGameState
var _multiplayer_turn_system: MultiplayerTurnSystem

var _local_player_id: int = -1
var _is_initialized: bool = false

func initialize(settings: Dictionary) -> bool:
	"""Initialize the multiplayer network handler"""
	print("Initializing MultiplayerNetworkHandler...")
	
	# Get or create network manager from the scene tree
	var scene_tree = Engine.get_main_loop() as SceneTree
	if scene_tree:
		_network_manager = scene_tree.root.get_node_or_null("NetworkManager")
		if not _network_manager:
			_network_manager = NetworkManager.new()
			_network_manager.name = "NetworkManager"
			scene_tree.root.add_child(_network_manager)
			
			# Ensure it's initialized
			await scene_tree.process_frame
			if not _network_manager._is_initialized:
				_network_manager.initialize_backends()
	
	# Get or create multiplayer game state
	if scene_tree:
		_multiplayer_game_state = scene_tree.root.get_node_or_null("MultiplayerGameState")
		if not _multiplayer_game_state:
			_multiplayer_game_state = MultiplayerGameState.new()
			_multiplayer_game_state.name = "MultiplayerGameState"
			scene_tree.root.add_child(_multiplayer_game_state)
	
	# Create multiplayer turn system
	_multiplayer_turn_system = MultiplayerTurnSystem.new()
	
	# Connect signals
	_connect_signals()
	
	# Set network mode based on settings
	var network_mode = settings.get("network_mode", "local")
	match network_mode:
		"local":
			_network_manager.set_network_mode(NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT)
		"p2p":
			_network_manager.set_network_mode(NetworkBackend.NetworkMode.P2P_DIRECT)
		"server":
			_network_manager.set_network_mode(NetworkBackend.NetworkMode.DEDICATED_SERVER)
	
	_is_initialized = true
	print("MultiplayerNetworkHandler initialized")
	return true

func _connect_signals() -> void:
	"""Connect to networking signals"""
	if _network_manager:
		_network_manager.connection_established.connect(_on_connection_established)
		_network_manager.connection_lost.connect(_on_connection_lost)
		_network_manager.connection_failed.connect(_on_connection_failed)
		_network_manager.message_received.connect(_on_message_received)
	
	if _multiplayer_game_state:
		_multiplayer_game_state.game_state_updated.connect(_on_game_state_updated)
		_multiplayer_game_state.action_validated.connect(_on_action_validated)

func submit_action(action: Dictionary) -> bool:
	"""Submit an action through the multiplayer system"""
	if not _is_initialized or not _multiplayer_game_state:
		return false
	
	return _multiplayer_game_state.submit_action(action.type, action.data)

func can_player_act(player_id: int) -> bool:
	"""Check if a player can act in multiplayer"""
	if not _is_initialized:
		return false
	
	# Check with turn system
	if _multiplayer_turn_system:
		return _multiplayer_turn_system.is_local_player_turn()
	
	return player_id == _local_player_id

func disconnect_network() -> void:
	"""Disconnect from multiplayer"""
	if _network_manager:
		_network_manager.disconnect_network()

func get_connection_status() -> String:
	"""Get current connection status"""
	if not _network_manager:
		return "disconnected"
	
	var status = _network_manager.get_connection_status()
	return NetworkBackend.ConnectionStatus.keys()[status].to_lower()

func get_local_player_id() -> int:
	"""Get local player ID"""
	return _local_player_id

func is_host() -> bool:
	"""Check if local player is host"""
	if not _network_manager:
		return false
	
	return _network_manager.is_host()

func get_network_statistics() -> Dictionary:
	"""Get network performance statistics"""
	if not _network_manager:
		return {}
	
	return _network_manager.get_network_statistics()

func get_connection_info() -> Dictionary:
	"""Get connection info for sharing"""
	if not _network_manager:
		return {}
	
	return _network_manager.get_connection_info()

# Host/Join methods
func start_host(port: int = 0) -> bool:
	"""Start hosting a multiplayer game"""
	if not _network_manager:
		return false
	
	return _network_manager.start_host(port)

func join_host(address: String, port: int) -> bool:
	"""Join a hosted multiplayer game"""
	if not _network_manager:
		return false
	
	return _network_manager.join_host(address, port)

# Signal handlers
func _on_connection_established(peer_id: int) -> void:
	"""Handle connection established"""
	var log_prefix = "[HOST] " if is_host() else "[CLIENT] "
	print(log_prefix + "=== CONNECTION ESTABLISHED ===")
	print(log_prefix + "MultiplayerNetworkHandler: Peer ID: " + str(peer_id))
	print(log_prefix + "MultiplayerNetworkHandler: Is host: " + str(is_host()))
	
	# Assign player IDs based on role
	if is_host():
		_local_player_id = 0  # Host is always Player 1 (ID 0)
		print(log_prefix + "MultiplayerNetworkHandler: Host assigned as Player 1 (ID: 0)")
	else:
		_local_player_id = 1  # Client is always Player 2 (ID 1)
		print(log_prefix + "MultiplayerNetworkHandler: Client assigned as Player 2 (ID: 1)")
	
	print(log_prefix + "MultiplayerNetworkHandler: Local player ID set to: " + str(_local_player_id))
	print(log_prefix + "=== END CONNECTION ESTABLISHED ===")
	
	# Emit player joined event
	player_joined.emit(_local_player_id, "Local Player")
	
	connection_status_changed.emit("connected")

func _on_connection_lost(peer_id: int) -> void:
	"""Handle connection lost"""
	var log_prefix = "[HOST] " if is_host() else "[CLIENT] "
	print(log_prefix + "MultiplayerNetworkHandler: Connection lost with peer " + str(peer_id))
	player_left.emit(peer_id)
	
	if _network_manager.get_connected_peers().is_empty():
		connection_status_changed.emit("disconnected")

func _on_connection_failed(error: String) -> void:
	"""Handle connection failure"""
	var log_prefix = "[HOST] " if is_host() else "[CLIENT] "
	print(log_prefix + "MultiplayerNetworkHandler: Connection failed - " + error)
	connection_status_changed.emit("failed: " + error)

func _on_message_received(sender_id: int, message: Dictionary) -> void:
	"""Handle network message received"""
	match message.get("type", ""):
		"game_action":
			var action = message.get("action_data", {})
			action_received.emit(action)
		"player_joined":
			var player_data = message.get("data", {})
			player_joined.emit(sender_id, player_data.get("name", "Unknown"))
		"player_left":
			player_left.emit(sender_id)

func _on_game_state_updated(state: Dictionary) -> void:
	"""Handle game state update from multiplayer system"""
	# Forward relevant updates to GameManager
	pass

func _on_action_validated(action: Dictionary, is_valid: bool) -> void:
	"""Handle action validation from multiplayer system"""
	if is_valid:
		action_received.emit(action)
