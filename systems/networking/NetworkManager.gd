extends Node

class_name NetworkManager

# Central network manager that uses pluggable backends
# Provides a unified interface for all networking operations
# Supports switching between Local, P2P, and Dedicated Server modes

signal connection_established(peer_id: int)
signal connection_lost(peer_id: int)
signal connection_failed(error: String)
signal message_received(sender_id: int, message: Dictionary)
signal network_mode_changed(new_mode: NetworkBackend.NetworkMode)

# Current networking backend
var _current_backend: NetworkBackend = null
var _network_mode: NetworkBackend.NetworkMode = NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT

# Available backends
var _local_backend: LocalNetworkBackend
var _p2p_backend: P2PNetworkBackend
var _dedicated_server_backend: DedicatedServerBackend

# Network state
var _is_initialized: bool = false
var _connection_info: Dictionary = {}

func _ready() -> void:
	name = "NetworkManager"
	
	# Initialize all backends
	initialize_backends()
	
	# Start with local development mode (after initialization)
	if not set_network_mode(NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT):
		push_error("Failed to set initial network mode")
	
	print("NetworkManager initialized with all backends")

func initialize_backends() -> void:
	"""Initialize all networking backends"""
	if _is_initialized:
		print("DEBUG: Backends already initialized, skipping")
		return
	
	print("DEBUG: Initializing backends...")
	
	# Create backends only if they don't exist
	if not _local_backend:
		_local_backend = LocalNetworkBackend.new()
		_local_backend.name = "LocalNetworkBackend"
		add_child(_local_backend)
		print("DEBUG: LocalNetworkBackend created and added to scene tree")
	
	if not _p2p_backend:
		_p2p_backend = P2PNetworkBackend.new()
		_p2p_backend.name = "P2PNetworkBackend"
		add_child(_p2p_backend)
		print("DEBUG: P2PNetworkBackend created and added to scene tree")
	
	if not _dedicated_server_backend:
		_dedicated_server_backend = DedicatedServerBackend.new()
		_dedicated_server_backend.name = "DedicatedServerBackend"
		add_child(_dedicated_server_backend)
		print("DEBUG: DedicatedServerBackend created and added to scene tree")
	
	# Connect signals for all backends
	_connect_backend_signals(_local_backend)
	_connect_backend_signals(_p2p_backend)
	_connect_backend_signals(_dedicated_server_backend)
	print("DEBUG: Backend signals connected")
	
	_is_initialized = true
	print("DEBUG: Backends initialized, _is_initialized = " + str(_is_initialized))

func _connect_backend_signals(backend: NetworkBackend) -> void:
	"""Connect signals from a backend to our signals"""
	backend.connection_established.connect(_on_backend_connection_established)
	backend.connection_lost.connect(_on_backend_connection_lost)
	backend.connection_failed.connect(_on_backend_connection_failed)
	backend.message_received.connect(_on_backend_message_received)

# Public API
func set_network_mode(mode: NetworkBackend.NetworkMode) -> bool:
	"""Switch to a different networking mode"""
	print("DEBUG: set_network_mode called with mode: " + str(mode))
	print("DEBUG: _is_initialized = " + str(_is_initialized))
	
	if not _is_initialized:
		push_error("NetworkManager not initialized")
		return false
	
	# Disconnect current backend if connected
	if _current_backend and _current_backend.get_connection_status() != NetworkBackend.ConnectionStatus.DISCONNECTED:
		_current_backend.disconnect_network()
	
	# Switch to new backend
	match mode:
		NetworkBackend.NetworkMode.LOCAL_DEVELOPMENT:
			_current_backend = _local_backend
			print("DEBUG: Set to LOCAL_DEVELOPMENT backend")
		NetworkBackend.NetworkMode.P2P_DIRECT:
			_current_backend = _p2p_backend
			print("DEBUG: Set to P2P_DIRECT backend")
		NetworkBackend.NetworkMode.DEDICATED_SERVER:
			_current_backend = _dedicated_server_backend
			print("DEBUG: Set to DEDICATED_SERVER backend")
		_:
			push_error("Unknown network mode: " + str(mode))
			return false
	
	_network_mode = mode
	print("NetworkManager switched to mode: " + NetworkBackend.NetworkMode.keys()[mode])
	network_mode_changed.emit(mode)
	
	return true

func get_network_mode() -> NetworkBackend.NetworkMode:
	"""Get current network mode"""
	return _network_mode

func start_host(port: int = 8910) -> bool:
	"""Start hosting a game"""
	if not _current_backend:
		push_error("No network backend selected")
		return false
	
	print("[HOST] NetworkManager: Starting host with " + NetworkBackend.NetworkMode.keys()[_network_mode] + " backend on port " + str(port))
	print("[HOST] NetworkManager: Current backend: " + str(_current_backend))
	
	var result = _current_backend.start_host(port)
	print("[HOST] NetworkManager: Host start result: " + str(result))
	
	return result

func join_host(address: String, port: int) -> bool:
	"""Join a hosted game"""
	if not _current_backend:
		push_error("No network backend selected")
		return false
	
	print("[CLIENT] NetworkManager: Joining host at %s:%d with %s backend" % [address, port, NetworkBackend.NetworkMode.keys()[_network_mode]])
	print("[CLIENT] NetworkManager: Current backend: " + str(_current_backend))
	print("[CLIENT] NetworkManager: Backend type: " + _current_backend.get_script().get_path())
	
	var result = _current_backend.join_host(address, port)
	print("[CLIENT] NetworkManager: Join result: " + str(result))
	
	return result

func send_game_action(action_type: String, action_data: Dictionary = {}) -> bool:
	"""Send a game action to other players"""
	if not _current_backend:
		return false
	
	var message = _current_backend.create_message("game_action", {
		"action_type": action_type,
		"action_data": action_data
	})
	
	return _current_backend.send_message(message)

func send_chat_message(text: String) -> bool:
	"""Send a chat message to other players"""
	if not _current_backend:
		return false
	
	var message = _current_backend.create_message("chat_message", {
		"text": text
	})
	
	return _current_backend.send_message(message)

func disconnect_network() -> void:
	"""Disconnect from current session"""
	if _current_backend:
		_current_backend.disconnect_network()

func get_connection_status() -> NetworkBackend.ConnectionStatus:
	"""Get current connection status"""
	if not _current_backend:
		return NetworkBackend.ConnectionStatus.DISCONNECTED
	
	return _current_backend.get_connection_status()

func get_local_peer_id() -> int:
	"""Get local player's peer ID"""
	if not _current_backend:
		return -1
	
	return _current_backend.get_local_peer_id()

func get_connected_peers() -> Array[int]:
	"""Get list of connected peer IDs"""
	if not _current_backend:
		return []
	
	return _current_backend.get_connected_peers()

func is_host() -> bool:
	"""Check if local player is the host"""
	if not _current_backend:
		return false
	
	return _current_backend.is_host()

func get_connection_info() -> Dictionary:
	"""Get connection information for sharing"""
	if not _current_backend:
		return {}
	
	var info = {
		"network_mode": NetworkBackend.NetworkMode.keys()[_network_mode],
		"is_host": is_host(),
		"peer_id": get_local_peer_id(),
		"connected_peers": get_connected_peers(),
		"connection_status": NetworkBackend.ConnectionStatus.keys()[get_connection_status()]
	}
	
	# Add mode-specific info
	if _current_backend is LocalNetworkBackend:
		var local_info = (_current_backend as LocalNetworkBackend).get_connection_info()
		info.merge(local_info)
	elif _current_backend is P2PNetworkBackend:
		var p2p_info = (_current_backend as P2PNetworkBackend).get_host_connection_info()
		info.merge(p2p_info)
	elif _current_backend is DedicatedServerBackend:
		var server_info = (_current_backend as DedicatedServerBackend).get_server_info()
		info.merge(server_info)
	
	return info

# Development mode specific methods
func enable_development_features(latency_ms: int = 50, packet_loss: float = 0.02) -> void:
	"""Enable development mode network simulation"""
	if _local_backend:
		_local_backend.set_latency_simulation(true, latency_ms)
		_local_backend.set_packet_loss_simulation(true, packet_loss)
		print("Development network simulation enabled: %dms latency, %.1f%% packet loss" % [latency_ms, packet_loss * 100])

func disable_development_features() -> void:
	"""Disable development mode network simulation"""
	if _local_backend:
		_local_backend.set_latency_simulation(false)
		_local_backend.set_packet_loss_simulation(false)
		print("Development network simulation disabled")

# P2P specific methods
func set_upnp_enabled(enabled: bool) -> void:
	"""Enable/disable UPnP for P2P mode"""
	if _p2p_backend:
		_p2p_backend.set_upnp_enabled(enabled)

func get_p2p_connection_quality(peer_id: int) -> float:
	"""Get P2P connection quality for a peer"""
	if _current_backend is P2PNetworkBackend:
		return (_current_backend as P2PNetworkBackend).get_connection_quality(peer_id)
	return 1.0

# Dedicated server specific methods
func authenticate_with_server(username: String, password: String = "") -> bool:
	"""Authenticate with dedicated server"""
	if _current_backend is DedicatedServerBackend:
		return (_current_backend as DedicatedServerBackend).authenticate_with_server(username, password)
	return false

func join_server_match(match_id: String, match_token: String = "") -> bool:
	"""Join a specific match on dedicated server"""
	if _current_backend is DedicatedServerBackend:
		return (_current_backend as DedicatedServerBackend).join_match(match_id, match_token)
	return false

# Signal handlers
func _on_backend_connection_established(peer_id: int) -> void:
	"""Handle connection established from backend"""
	print("NetworkManager: Connection established with peer " + str(peer_id))
	connection_established.emit(peer_id)

func _on_backend_connection_lost(peer_id: int) -> void:
	"""Handle connection lost from backend"""
	print("NetworkManager: Connection lost with peer " + str(peer_id))
	connection_lost.emit(peer_id)

func _on_backend_connection_failed(error: String) -> void:
	"""Handle connection failure from backend"""
	print("NetworkManager: Connection failed - " + error)
	connection_failed.emit(error)

func _on_backend_message_received(sender_id: int, message: Dictionary) -> void:
	"""Handle message received from backend"""
	# Ensure sender_id is an int (defensive programming)
	var sender_id_int = int(sender_id) if sender_id is String else sender_id
	
	# Process message based on type
	var message_type = message.get("type", "")
	
	match message_type:
		"game_action":
			_handle_game_action(sender_id_int, message)
		"chat_message":
			_handle_chat_message(sender_id_int, message)
		"system_message":
			_handle_system_message(sender_id_int, message)
		_:
			# Forward unknown messages to game systems
			message_received.emit(sender_id_int, message)

func _handle_game_action(sender_id: int, message: Dictionary) -> void:
	"""Handle game action messages"""
	var data = message.get("data", {})
	var action_type = data.get("action_type", "")
	var action_data = data.get("action_data", {})
	
	print("NetworkManager: Game action from peer " + str(sender_id) + " - " + str(action_type))
	
	# Forward to game systems
	message_received.emit(sender_id, {
		"type": "game_action",
		"action_type": action_type,
		"action_data": action_data,
		"sender_id": sender_id
	})

func _handle_chat_message(sender_id: int, message: Dictionary) -> void:
	"""Handle chat messages"""
	var data = message.get("data", {})
	var text = data.get("text", "")
	
	print("NetworkManager: Chat from peer " + str(sender_id) + " - " + str(text))
	
	# Forward to UI systems
	message_received.emit(sender_id, {
		"type": "chat_message",
		"text": text,
		"sender_id": sender_id
	})

func _handle_system_message(sender_id: int, message: Dictionary) -> void:
	"""Handle system messages"""
	var data = message.get("data", {})
	print("NetworkManager: System message from peer " + str(sender_id) + " - " + str(data))
	
	# Forward to appropriate systems
	message_received.emit(sender_id, message)

# Utility methods
func get_backend_info() -> Dictionary:
	"""Get information about current backend"""
	if not _current_backend:
		return {}
	
	return {
		"mode": NetworkBackend.NetworkMode.keys()[_network_mode],
		"supports_reconnection": _current_backend.supports_reconnection(),
		"max_peers": _current_backend.get_max_peers(),
		"connection_status": NetworkBackend.ConnectionStatus.keys()[get_connection_status()]
	}

func is_multiplayer_active() -> bool:
	"""Check if multiplayer is currently active"""
	return _current_backend != null and get_connection_status() == NetworkBackend.ConnectionStatus.CONNECTED

func get_network_statistics() -> Dictionary:
	"""Get network performance statistics"""
	var stats = {
		"mode": NetworkBackend.NetworkMode.keys()[_network_mode],
		"connected_peers": get_connected_peers().size(),
		"is_host": is_host(),
		"connection_status": NetworkBackend.ConnectionStatus.keys()[get_connection_status()]
	}
	
	# Add mode-specific stats
	if _current_backend is P2PNetworkBackend:
		var peers = get_connected_peers()
		var total_quality = 0.0
		for peer_id in peers:
			total_quality += get_p2p_connection_quality(peer_id)
		
		stats["average_connection_quality"] = total_quality / max(peers.size(), 1)
	
	return stats
