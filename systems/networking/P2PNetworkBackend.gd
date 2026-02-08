extends NetworkBackend

class_name P2PNetworkBackend

# Peer-to-peer networking backend for production launch
# Uses Godot's ENetMultiplayerPeer with UPnP for NAT traversal
# Designed for 2-4 player matches with minimal server infrastructure

var _connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var _is_host: bool = false
var _local_peer_id: int = -1
var _connected_peers: Array[int] = []
var _multiplayer_api: MultiplayerAPI
var _enet_peer: ENetMultiplayerPeer
var _upnp: UPNP

# P2P specific settings
var _host_port: int = 0
var _upnp_enabled: bool = true
var _connection_timeout: float = 10.0
var _reconnection_attempts: int = 3
var _current_reconnection_attempt: int = 0

# Connection quality tracking
var _peer_latencies: Dictionary = {}  # peer_id -> latency_ms
var _peer_packet_loss: Dictionary = {}  # peer_id -> loss_rate

func _init():
	_multiplayer_api = MultiplayerAPI.create_default_interface()
	_enet_peer = ENetMultiplayerPeer.new()
	_upnp = UPNP.new()
	
	# Connect signals
	_multiplayer_api.peer_connected.connect(_on_peer_connected)
	_multiplayer_api.peer_disconnected.connect(_on_peer_disconnected)
	_multiplayer_api.connection_failed.connect(_on_connection_failed)
	_multiplayer_api.connected_to_server.connect(_on_connected_to_server)
	_multiplayer_api.server_disconnected.connect(_on_server_disconnected)

func _process(_delta: float) -> void:
	"""Poll the multiplayer API to process network events"""
	if _multiplayer_api and _multiplayer_api.has_multiplayer_peer():
		_multiplayer_api.poll()

func get_network_mode() -> NetworkMode:
	return NetworkMode.P2P_DIRECT

func start_host(port: int = 0) -> bool:
	log_network_event("Starting P2P host", "port: " + str(port))
	
	# Use random port if none specified
	if port == 0:
		port = _get_random_port()
	
	_host_port = port
	
	# Try UPnP port forwarding first
	if _upnp_enabled:
		await _setup_upnp_port_forwarding(port)
	
	# Create ENet server
	var error = _enet_peer.create_server(port, get_max_peers())
	if error != OK:
		log_network_event("P2P host start failed", "error: " + str(error))
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Failed to create P2P host: " + str(error))
		return false
	
	_multiplayer_api.multiplayer_peer = _enet_peer
	
	# CRITICAL FIX: Set peer on scene tree's multiplayer API for RPC to work
	get_tree().get_multiplayer().multiplayer_peer = _enet_peer
	
	_is_host = true
	_local_peer_id = 1  # Host is always peer 1
	_connection_status = ConnectionStatus.CONNECTED
	
	log_network_event("P2P host started", "peer_id: %d, port: %d" % [_local_peer_id, port])
	host_started.emit(port)
	connection_established.emit(_local_peer_id)
	
	return true

func join_host(address: String, port: int) -> bool:
	log_network_event("Joining P2P host", "address: %s:%d" % [address, port])
	
	_connection_status = ConnectionStatus.CONNECTING
	_current_reconnection_attempt = 0
	
	var error = _enet_peer.create_client(address, port)
	if error != OK:
		log_network_event("P2P join failed", "error: " + str(error))
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Failed to create P2P client: " + str(error))
		return false
	
	_multiplayer_api.multiplayer_peer = _enet_peer
	
	# CRITICAL FIX: Set peer on scene tree's multiplayer API for RPC to work
	get_tree().get_multiplayer().multiplayer_peer = _enet_peer
	
	_is_host = false
	
	# Start connection timeout
	_start_connection_timeout()
	
	log_network_event("Attempting P2P connection", "to %s:%d" % [address, port])
	return true

func send_message(message: Dictionary, target_peer: int = -1) -> bool:
	if _connection_status != ConnectionStatus.CONNECTED:
		log_network_event("P2P send failed", "not connected")
		return false
	
	if not validate_message(message):
		log_network_event("P2P send failed", "invalid message format")
		return false
	
	# Add P2P specific metadata
	message["p2p_timestamp"] = Time.get_ticks_msec()
	message["p2p_sequence"] = _get_next_sequence_number()
	
	# Send via RPC
	if target_peer == -1:
		_send_to_all_peers(message)
	else:
		_send_to_peer(message, target_peer)
	
	return true

func _send_to_all_peers(message: Dictionary) -> void:
	"""Send message to all connected peers"""
	if not _multiplayer_api or not _multiplayer_api.multiplayer_peer:
		log_network_event("P2P send failed", "multiplayer API not ready")
		return
	
	# In Godot 4, we need to call the RPC method directly
	_receive_p2p_message.rpc(message)

func _send_to_peer(message: Dictionary, peer_id: int) -> void:
	"""Send message to specific peer"""
	if not _multiplayer_api or not _multiplayer_api.multiplayer_peer:
		log_network_event("P2P send failed", "multiplayer API not ready")
		return
	
	# In Godot 4, we need to call the RPC method directly on specific peer
	_receive_p2p_message.rpc_id(peer_id, message)

@rpc("any_peer", "call_local", "reliable")
func _receive_p2p_message(message: Dictionary) -> void:
	"""Receive P2P message via RPC"""
	if not _multiplayer_api:
		log_network_event("P2P receive failed", "multiplayer API not available")
		return
	
	var sender_id = _multiplayer_api.get_remote_sender_id()
	if sender_id == 0:
		sender_id = _local_peer_id  # Local message
	
	# Ensure sender_id is an int for string concatenation
	var sender_id_int = int(sender_id) if sender_id is String else sender_id
	
	# Update connection quality metrics
	if message.has("p2p_timestamp"):
		var latency = Time.get_ticks_msec() - message["p2p_timestamp"]
		_update_peer_latency(sender_id_int, latency)
		
	print("Sender id")
	print(type_string(typeof(sender_id)))

	print("Sender id int is")
	print(type_string(typeof(str(sender_id_int))))


	
	log_network_event("P2P message received", "from peer " + str(sender_id_int))
	message_received.emit(sender_id_int, message)

func disconnect_network() -> void:
	log_network_event("P2P disconnecting", "")
	
	# Clean up UPnP port forwarding
	if _upnp_enabled and _is_host:
		_cleanup_upnp_port_forwarding()
	
	if _enet_peer:
		_enet_peer.close()
	
	# Clean up scene tree's multiplayer API
	if get_tree() and get_tree().get_multiplayer():
		get_tree().get_multiplayer().multiplayer_peer = null
	
	_connection_status = ConnectionStatus.DISCONNECTED
	_connected_peers.clear()
	_is_host = false
	_local_peer_id = -1
	_peer_latencies.clear()
	_peer_packet_loss.clear()

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
	return 4  # P2P works well for up to 4 players

func get_connection_quality(peer_id: int) -> float:
	"""Get connection quality for a peer (0.0 = poor, 1.0 = excellent)"""
	var latency = _peer_latencies.get(peer_id, 0)
	var packet_loss = _peer_packet_loss.get(peer_id, 0.0)
	
	# Calculate quality based on latency and packet loss
	var latency_quality = 1.0 - min(latency / 500.0, 1.0)  # 500ms = 0 quality
	var packet_loss_quality = 1.0 - min(packet_loss * 10.0, 1.0)  # 10% loss = 0 quality
	
	return (latency_quality + packet_loss_quality) / 2.0

# P2P specific methods
func set_upnp_enabled(enabled: bool) -> void:
	"""Enable/disable UPnP for automatic port forwarding"""
	_upnp_enabled = enabled
	log_network_event("UPnP", "enabled: " + str(enabled))

func get_external_ip() -> String:
	"""Get external IP address for P2P connections"""
	if _upnp and _upnp.get_gateway():
		return _upnp.query_external_address()
	return ""

func get_host_connection_info() -> Dictionary:
	"""Get connection info for sharing with other players"""
	if not _is_host:
		return {}
	
	var external_ip = get_external_ip()
	return {
		"address": external_ip if external_ip != "" else "127.0.0.1",
		"port": _host_port,
		"host_name": OS.get_environment("USERNAME"),
		"game_version": "1.0.0"  # TODO: Get from project settings
	}

# UPnP methods
func _setup_upnp_port_forwarding(port: int) -> void:
	"""Setup UPnP port forwarding for hosting"""
	log_network_event("Setting up UPnP", "port: " + str(port))
	
	var discover_result = _upnp.discover()
	if discover_result != UPNP.UPNP_RESULT_SUCCESS:
		log_network_event("UPnP discovery failed", "result: " + str(discover_result))
		return
	
	if _upnp.get_gateway() and _upnp.get_gateway().is_valid_gateway():
		var map_result = _upnp.add_port_mapping(port, port, "TacticalGame", "UDP")
		if map_result == UPNP.UPNP_RESULT_SUCCESS:
			log_network_event("UPnP port mapped", "port: " + str(port))
		else:
			log_network_event("UPnP port mapping failed", "result: " + str(map_result))

func _cleanup_upnp_port_forwarding() -> void:
	"""Clean up UPnP port forwarding"""
	if _upnp and _upnp.get_gateway() and _host_port > 0:
		_upnp.delete_port_mapping(_host_port, "UDP")
		log_network_event("UPnP port unmapped", "port: " + str(_host_port))

# Utility methods
func _get_random_port() -> int:
	"""Get a random port for hosting"""
	return randi_range(49152, 65535)  # Dynamic port range

var _sequence_number: int = 0
func _get_next_sequence_number() -> int:
	_sequence_number += 1
	return _sequence_number

func _update_peer_latency(peer_id: int, latency_ms: int) -> void:
	"""Update latency tracking for a peer"""
	if not _peer_latencies.has(peer_id):
		_peer_latencies[peer_id] = latency_ms
	else:
		# Use exponential moving average
		_peer_latencies[peer_id] = int(_peer_latencies[peer_id] * 0.8 + latency_ms * 0.2)

func _start_connection_timeout() -> void:
	"""Start connection timeout timer"""
	await Engine.get_main_loop().create_timer(_connection_timeout).timeout
	
	if _connection_status == ConnectionStatus.CONNECTING:
		log_network_event("P2P connection timeout", "")
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Connection timeout")

# Signal handlers
func _on_peer_connected(peer_id: int) -> void:
	log_network_event("P2P peer connected", "peer_id: " + str(peer_id))
	_connected_peers.append(peer_id)
	_peer_latencies[peer_id] = 0
	_peer_packet_loss[peer_id] = 0.0
	connection_established.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	log_network_event("P2P peer disconnected", "peer_id: " + str(peer_id))
	_connected_peers.erase(peer_id)
	_peer_latencies.erase(peer_id)
	_peer_packet_loss.erase(peer_id)
	connection_lost.emit(peer_id)

func _on_connection_failed() -> void:
	log_network_event("P2P connection failed", "")
	_connection_status = ConnectionStatus.FAILED
	
	# Try reconnection if enabled
	if _current_reconnection_attempt < _reconnection_attempts:
		_current_reconnection_attempt += 1
		log_network_event("P2P reconnection attempt", str(_current_reconnection_attempt))
		_connection_status = ConnectionStatus.RECONNECTING
		# TODO: Implement reconnection logic
	else:
		connection_failed.emit("P2P connection failed after " + str(_reconnection_attempts) + " attempts")

func _on_connected_to_server() -> void:
	log_network_event("P2P connected to host", "")
	_connection_status = ConnectionStatus.CONNECTED
	var peer_id_raw = _multiplayer_api.get_unique_id()
	_local_peer_id = int(peer_id_raw) if peer_id_raw is String else peer_id_raw
	connection_established.emit(_local_peer_id)

func _on_server_disconnected() -> void:
	log_network_event("P2P host disconnected", "")
	_connection_status = ConnectionStatus.DISCONNECTED
	_connected_peers.clear()
	_peer_latencies.clear()
	_peer_packet_loss.clear()
	connection_lost.emit(1)  # Host is peer 1
