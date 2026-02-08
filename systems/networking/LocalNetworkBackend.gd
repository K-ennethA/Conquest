extends NetworkBackend

class_name LocalNetworkBackend

# Local development networking backend
# Simulates multiplayer by running two instances on the same machine
# Uses localhost connections for rapid development and testing

var _connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var _is_host: bool = false
var _local_peer_id: int = -1
var _connected_peers: Array[int] = []
var _multiplayer_api: MultiplayerAPI
var _enet_peer: ENetMultiplayerPeer

# Development mode settings
var _simulate_latency: bool = false
var _latency_ms: int = 50
var _simulate_packet_loss: bool = false
var _packet_loss_rate: float = 0.02  # 2% packet loss

func _init():
	_multiplayer_api = MultiplayerAPI.create_default_interface()
	_enet_peer = ENetMultiplayerPeer.new()
	
	# Connect signals
	_multiplayer_api.peer_connected.connect(_on_peer_connected)
	_multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)
	_multiplayer_api.connection_failed.connect(_on_connection_failed)
	_multiplayer_api.connected_to_server.connect(_on_connected_to_server)
	_multiplayer_api.server_disconnected.connect(_on_server_disconnected)

func get_network_mode() -> NetworkMode:
	return NetworkMode.LOCAL_DEVELOPMENT

func start_host(port: int = 8910) -> bool:
	log_network_event("Starting local host", "port: " + str(port))
	print("[HOST] LocalNetworkBackend: Starting host on port " + str(port))
	
	var error = _enet_peer.create_server(port, get_max_peers())
	if error != OK:
		log_network_event("Host start failed", "error: " + str(error))
		print("[HOST] LocalNetworkBackend: create_server failed with error: " + str(error))
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Failed to create server: " + str(error))
		return false
	
	print("[HOST] LocalNetworkBackend: ENet server created successfully")
	
	_multiplayer_api.multiplayer_peer = _enet_peer
	_is_host = true
	_local_peer_id = 1  # Host is always peer 1
	_connection_status = ConnectionStatus.CONNECTED
	
	print("[HOST] LocalNetworkBackend: Host configuration complete")
	print("[HOST] LocalNetworkBackend: Local peer ID: " + str(_local_peer_id))
	print("[HOST] LocalNetworkBackend: Connection status: " + str(ConnectionStatus.keys()[_connection_status]))
	
	log_network_event("Local host started", "peer_id: " + str(_local_peer_id))
	host_started.emit(port)
	connection_established.emit(_local_peer_id)
	
	return true

func join_host(address: String = "127.0.0.1", port: int = 8910) -> bool:
	log_network_event("Joining local host", "address: %s:%d" % [address, port])
	print("[CLIENT] LocalNetworkBackend: Starting join process...")
	
	_connection_status = ConnectionStatus.CONNECTING
	print("[CLIENT] LocalNetworkBackend: Set status to CONNECTING")
	
	var error = _enet_peer.create_client(address, port)
	if error != OK:
		log_network_event("Join failed", "error: " + str(error))
		print("[CLIENT] LocalNetworkBackend: create_client failed with error: " + str(error))
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Failed to create client: " + str(error))
		return false
	
	print("[CLIENT] LocalNetworkBackend: ENet client created successfully")
	
	_multiplayer_api.multiplayer_peer = _enet_peer
	_is_host = false
	
	print("[CLIENT] LocalNetworkBackend: Multiplayer API configured")
	print("[CLIENT] LocalNetworkBackend: Attempting to connect to %s:%d" % [address, port])
	
	log_network_event("Attempting to connect", "to %s:%d" % [address, port])
	return true

func send_message(message: Dictionary, target_peer: int = -1) -> bool:
	if _connection_status != ConnectionStatus.CONNECTED:
		log_network_event("Send failed", "not connected")
		return false
	
	if not validate_message(message):
		log_network_event("Send failed", "invalid message format")
		return false
	
	# Simulate packet loss in development mode
	if _simulate_packet_loss and randf() < _packet_loss_rate:
		log_network_event("Packet dropped", "simulated packet loss")
		return true  # Return true to simulate successful send
	
	# Simulate latency in development mode
	if _simulate_latency:
		await _simulate_network_delay()
	
	# Send via RPC
	if target_peer == -1:
		_send_to_all_peers(message)
	else:
		_send_to_peer(message, target_peer)
	
	return true

func _send_to_all_peers(message: Dictionary) -> void:
	"""Send message to all connected peers"""
	if not _multiplayer_api or not _multiplayer_api.multiplayer_peer:
		log_network_event("Send failed", "multiplayer API not ready")
		return
	
	# In Godot 4, we need to call the RPC method directly
	_receive_network_message.rpc(message)

func _send_to_peer(message: Dictionary, peer_id: int) -> void:
	"""Send message to specific peer"""
	if not _multiplayer_api or not _multiplayer_api.multiplayer_peer:
		log_network_event("Send failed", "multiplayer API not ready")
		return
	
	# In Godot 4, we need to call the RPC method directly on specific peer
	_receive_network_message.rpc_id(peer_id, message)

@rpc("any_peer", "call_local", "reliable")
func _receive_network_message(message: Dictionary) -> void:
	"""Receive network message via RPC"""
	if not _multiplayer_api:
		log_network_event("Receive failed", "multiplayer API not available")
		return
	
	var sender_id = _multiplayer_api.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _local_peer_id  # Local message
	
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: Message received from peer " + str(sender_id))
	print(log_prefix + "LocalNetworkBackend: Message content: " + str(message))
	
	log_network_event("Message received", "from peer " + str(sender_id))
	message_received.emit(sender_id, message)

func disconnect_network() -> void:
	log_network_event("Disconnecting", "")
	
	if _enet_peer:
		_enet_peer.close()
	
	_connection_status = ConnectionStatus.DISCONNECTED
	_connected_peers.clear()
	_is_host = false
	_local_peer_id = -1

func get_connection_status() -> ConnectionStatus:
	return _connection_status

func get_local_peer_id() -> int:
	return _local_peer_id

func get_connected_peers() -> Array[int]:
	return _connected_peers.duplicate()

func is_host() -> bool:
	return _is_host

func supports_reconnection() -> bool:
	return true

func get_max_peers() -> int:
	return 2  # Local development typically just 2 players

func get_connection_info() -> Dictionary:
	"""Get connection info for sharing"""
	return {
		"port": 8910,  # Default port for local development
		"address": "127.0.0.1",
		"is_host": _is_host,
		"peer_id": _local_peer_id,
		"connected_peers": _connected_peers.duplicate(),
		"connection_status": ConnectionStatus.keys()[_connection_status]
	}

# Development mode specific methods
func set_latency_simulation(enabled: bool, latency_ms: int = 50) -> void:
	"""Enable/disable latency simulation for testing"""
	_simulate_latency = enabled
	_latency_ms = latency_ms
	log_network_event("Latency simulation", "enabled: %s, ms: %d" % [enabled, latency_ms])

func set_packet_loss_simulation(enabled: bool, loss_rate: float = 0.02) -> void:
	"""Enable/disable packet loss simulation for testing"""
	_simulate_packet_loss = enabled
	_packet_loss_rate = loss_rate
	log_network_event("Packet loss simulation", "enabled: %s, rate: %.2f" % [enabled, loss_rate])

func _simulate_network_delay() -> void:
	"""Simulate network latency for testing"""
	if _latency_ms > 0:
		await Engine.get_main_loop().create_timer(_latency_ms / 1000.0).timeout

# Signal handlers
func _on_peer_connected(peer_id: int) -> void:
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: _on_peer_connected - peer_id: " + str(peer_id))
	log_network_event("Peer connected", "peer_id: " + str(peer_id))
	_connected_peers.append(peer_id)
	connection_established.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: _on_peer_disconnected - peer_id: " + str(peer_id))
	log_network_event("Peer disconnected", "peer_id: " + str(peer_id))
	_connected_peers.erase(peer_id)
	connection_lost.emit(peer_id)

func _on_connection_failed() -> void:
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: _on_connection_failed")
	log_network_event("Connection failed", "")
	_connection_status = ConnectionStatus.FAILED
	connection_failed.emit("Connection to host failed")

func _on_connected_to_server() -> void:
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: _on_connected_to_server")
	log_network_event("Connected to server", "")
	_connection_status = ConnectionStatus.CONNECTED
	_local_peer_id = _multiplayer_api.get_unique_id()
	print(log_prefix + "LocalNetworkBackend: Local peer ID set to: " + str(_local_peer_id))
	connection_established.emit(_local_peer_id)

func _on_server_disconnected() -> void:
	var log_prefix = "[HOST] " if _is_host else "[CLIENT] "
	print(log_prefix + "LocalNetworkBackend: _on_server_disconnected")
	log_network_event("Server disconnected", "")
	_connection_status = ConnectionStatus.DISCONNECTED
	_connected_peers.clear()
	connection_lost.emit(1)  # Host is peer 1
