extends NetworkBackend

class_name DedicatedServerBackend

# Dedicated server networking backend for future migration
# Provides server-authoritative gameplay with anti-cheat protection
# This is the migration target once P2P proves successful

var _connection_status: ConnectionStatus = ConnectionStatus.DISCONNECTED
var _local_peer_id: int = -1
var _server_address: String = ""
var _server_port: int = 0
var _websocket_client: WebSocketPeer
var _connection_timeout: float = 15.0
var _reconnection_attempts: int = 5
var _current_reconnection_attempt: int = 0

# Server-specific features
var _server_token: String = ""
var _match_id: String = ""
var _player_session: Dictionary = {}
var _server_latency: int = 0
var _last_ping_time: int = 0

func _init():
	_websocket_client = WebSocketPeer.new()

func get_network_mode() -> NetworkMode:
	return NetworkMode.DEDICATED_SERVER

func start_host(port: int = 0) -> bool:
	# Dedicated server mode doesn't support hosting from client
	push_error("DedicatedServerBackend: Cannot start host - clients connect to dedicated servers")
	return false

func join_host(address: String, port: int = 8080) -> bool:
	log_network_event("Connecting to dedicated server", "address: %s:%d" % [address, port])
	
	_server_address = address
	_server_port = port
	_connection_status = ConnectionStatus.CONNECTING
	_current_reconnection_attempt = 0
	
	# Connect via WebSocket
	var url = "ws://%s:%d/game" % [address, port]
	var error = _websocket_client.connect_to_url(url)
	
	if error != OK:
		log_network_event("Server connection failed", "error: " + str(error))
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Failed to connect to server: " + str(error))
		return false
	
	# Start connection timeout
	_start_connection_timeout()
	
	return true

func send_message(message: Dictionary, target_peer: int = -1) -> bool:
	if _connection_status != ConnectionStatus.CONNECTED:
		log_network_event("Server send failed", "not connected")
		return false
	
	if not validate_message(message):
		log_network_event("Server send failed", "invalid message format")
		return false
	
	# Add server-specific metadata
	message["session_token"] = _server_token
	message["match_id"] = _match_id
	message["client_timestamp"] = Time.get_ticks_msec()
	
	# Send via WebSocket
	var json_string = JSON.stringify(message)
	var error = _websocket_client.send_text(json_string)
	
	if error != OK:
		log_network_event("Server send failed", "WebSocket error: " + str(error))
		return false
	
	return true

func disconnect_network() -> void:
	log_network_event("Disconnecting from server", "")
	
	if _websocket_client:
		_websocket_client.close()
	
	_connection_status = ConnectionStatus.DISCONNECTED
	_local_peer_id = -1
	_server_token = ""
	_match_id = ""
	_player_session.clear()

func get_connection_status() -> ConnectionStatus:
	return _connection_status

func get_local_peer_id() -> int:
	return _local_peer_id

func get_connected_peers() -> Array[int]:
	# In dedicated server mode, we don't directly know about other peers
	# The server manages all peer relationships
	return []

func is_host() -> bool:
	return false  # Clients are never hosts in dedicated server mode

func supports_reconnection() -> bool:
	return true

func get_max_peers() -> int:
	return 8  # Dedicated servers can handle more players

func get_connection_quality(peer_id: int = -1) -> float:
	"""Get connection quality to server"""
	if _server_latency == 0:
		return 1.0
	
	# Calculate quality based on server latency
	var quality = 1.0 - min(_server_latency / 300.0, 1.0)  # 300ms = 0 quality
	return max(quality, 0.0)

# Dedicated server specific methods
func authenticate_with_server(username: String, password: String = "") -> bool:
	"""Authenticate with the dedicated server"""
	var auth_message = create_message("authenticate", {
		"username": username,
		"password": password,
		"client_version": "1.0.0"  # TODO: Get from project settings
	})
	
	return send_message(auth_message)

func join_match(match_id: String, match_token: String = "") -> bool:
	"""Join a specific match on the server"""
	var join_message = create_message("join_match", {
		"match_id": match_id,
		"match_token": match_token
	})
	
	return send_message(join_message)

func request_match_list() -> bool:
	"""Request list of available matches from server"""
	var request_message = create_message("request_match_list", {})
	return send_message(request_message)

func create_match(match_settings: Dictionary) -> bool:
	"""Request server to create a new match"""
	var create_message = create_message("create_match", {
		"settings": match_settings
	})
	
	return send_message(create_message)

func get_server_info() -> Dictionary:
	"""Get information about the connected server"""
	return {
		"address": _server_address,
		"port": _server_port,
		"latency": _server_latency,
		"match_id": _match_id,
		"session_token": _server_token
	}

# Network processing
func _process_network_messages() -> void:
	"""Process incoming messages from server"""
	if not _websocket_client:
		return
	
	_websocket_client.poll()
	
	var state = _websocket_client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_CONNECTING:
			# Still connecting
			pass
		
		WebSocketPeer.STATE_OPEN:
			if _connection_status == ConnectionStatus.CONNECTING:
				_on_server_connected()
			
			# Process incoming messages
			while _websocket_client.get_available_packet_count() > 0:
				var packet = _websocket_client.get_packet()
				var message_text = packet.get_string_from_utf8()
				_process_server_message(message_text)
		
		WebSocketPeer.STATE_CLOSING:
			# Server is closing connection
			pass
		
		WebSocketPeer.STATE_CLOSED:
			if _connection_status == ConnectionStatus.CONNECTED:
				_on_server_disconnected()

func _process_server_message(message_text: String) -> void:
	"""Process a message received from the server"""
	var json = JSON.new()
	var parse_result = json.parse(message_text)
	
	if parse_result != OK:
		log_network_event("Server message parse error", "invalid JSON")
		return
	
	var message = json.data
	if not (message is Dictionary):
		log_network_event("Server message error", "not a dictionary")
		return
	
	# Handle server-specific message types
	match message.get("type", ""):
		"authentication_result":
			_handle_authentication_result(message)
		"match_joined":
			_handle_match_joined(message)
		"match_list":
			_handle_match_list(message)
		"server_ping":
			_handle_server_ping(message)
		"error":
			_handle_server_error(message)
		_:
			# Forward game messages to the game system
			var sender_id = message.get("sender_id", 0)
			message_received.emit(sender_id, message)

func _handle_authentication_result(message: Dictionary) -> void:
	"""Handle authentication response from server"""
	var success = message.get("success", false)
	var data = message.get("data", {})
	
	if success:
		_server_token = data.get("session_token", "")
		_local_peer_id = data.get("player_id", -1)
		_player_session = data.get("session_info", {})
		log_network_event("Authentication successful", "player_id: " + str(_local_peer_id))
	else:
		var error_msg = data.get("error", "Authentication failed")
		log_network_event("Authentication failed", error_msg)
		connection_failed.emit(error_msg)

func _handle_match_joined(message: Dictionary) -> void:
	"""Handle successful match join"""
	var data = message.get("data", {})
	_match_id = data.get("match_id", "")
	log_network_event("Joined match", "match_id: " + _match_id)

func _handle_match_list(message: Dictionary) -> void:
	"""Handle match list from server"""
	var matches = message.get("data", {}).get("matches", [])
	log_network_event("Received match list", "count: " + str(matches.size()))
	# TODO: Emit signal for UI to handle match list

func _handle_server_ping(message: Dictionary) -> void:
	"""Handle ping from server and respond"""
	var server_timestamp = message.get("timestamp", 0)
	var current_time = Time.get_ticks_msec()
	
	# Calculate latency
	if _last_ping_time > 0:
		_server_latency = current_time - _last_ping_time
	
	# Send pong response
	var pong_message = create_message("server_pong", {
		"server_timestamp": server_timestamp,
		"client_timestamp": current_time
	})
	send_message(pong_message)
	
	_last_ping_time = current_time

func _handle_server_error(message: Dictionary) -> void:
	"""Handle error message from server"""
	var error_msg = message.get("data", {}).get("error", "Unknown server error")
	log_network_event("Server error", error_msg)
	connection_failed.emit(error_msg)

func _start_connection_timeout() -> void:
	"""Start connection timeout timer"""
	await Engine.get_main_loop().create_timer(_connection_timeout).timeout
	
	if _connection_status == ConnectionStatus.CONNECTING:
		log_network_event("Server connection timeout", "")
		_connection_status = ConnectionStatus.FAILED
		connection_failed.emit("Connection to server timed out")

# Signal handlers
func _on_server_connected() -> void:
	"""Called when WebSocket connection is established"""
	log_network_event("Connected to server", "")
	_connection_status = ConnectionStatus.CONNECTED
	connection_established.emit(_local_peer_id)

func _on_server_disconnected() -> void:
	"""Called when server connection is lost"""
	log_network_event("Server disconnected", "")
	
	if _connection_status == ConnectionStatus.CONNECTED:
		_connection_status = ConnectionStatus.DISCONNECTED
		
		# Try reconnection if enabled
		if _current_reconnection_attempt < _reconnection_attempts:
			_current_reconnection_attempt += 1
			log_network_event("Server reconnection attempt", str(_current_reconnection_attempt))
			_connection_status = ConnectionStatus.RECONNECTING
			# TODO: Implement reconnection logic
		else:
			connection_lost.emit(1)  # Server connection lost

# This backend needs to be processed each frame to handle WebSocket messages
func _ready() -> void:
	# Only add to scene tree if we don't already have a parent
	# NetworkManager will add us as a child, so we don't need to do it ourselves
	pass

func _process(_delta: float) -> void:
	"""Process network messages each frame"""
	_process_network_messages()
