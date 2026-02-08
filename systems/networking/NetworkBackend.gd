extends Node

class_name NetworkBackend

# Abstract base class for all networking implementations
# Provides a common interface that allows switching between P2P, local, and dedicated server modes

enum ConnectionStatus {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
	RECONNECTING,
	FAILED
}

enum NetworkMode {
	LOCAL_DEVELOPMENT,  # Two instances on same machine
	P2P_DIRECT,        # Peer-to-peer networking
	DEDICATED_SERVER   # Future: Client-server architecture
}

# Signals for network events
signal connection_established(peer_id: int)
signal connection_lost(peer_id: int)
signal connection_failed(error: String)
signal message_received(sender_id: int, message: Dictionary)
signal host_started(port: int)
signal client_connected(address: String, port: int)

# Abstract methods that must be implemented by concrete backends
func get_network_mode() -> NetworkMode:
	push_error("NetworkBackend.get_network_mode() must be implemented by subclass")
	return NetworkMode.LOCAL_DEVELOPMENT

func start_host(port: int = 0) -> bool:
	push_error("NetworkBackend.start_host() must be implemented by subclass")
	return false

func join_host(address: String, port: int) -> bool:
	push_error("NetworkBackend.join_host() must be implemented by subclass")
	return false

func send_message(message: Dictionary, target_peer: int = -1) -> bool:
	push_error("NetworkBackend.send_message() must be implemented by subclass")
	return false

func disconnect_network() -> void:
	push_error("NetworkBackend.disconnect_network() must be implemented by subclass")

func get_connection_status() -> ConnectionStatus:
	push_error("NetworkBackend.get_connection_status() must be implemented by subclass")
	return ConnectionStatus.DISCONNECTED

func get_local_peer_id() -> int:
	push_error("NetworkBackend.get_local_peer_id() must be implemented by subclass")
	return -1

func get_connected_peers() -> Array[int]:
	push_error("NetworkBackend.get_connected_peers() must be implemented by subclass")
	return []

func is_host() -> bool:
	push_error("NetworkBackend.is_host() must be implemented by subclass")
	return false

# Optional methods with default implementations
func get_peer_address(peer_id: int) -> String:
	return "unknown"

func get_connection_quality(peer_id: int) -> float:
	return 1.0  # Perfect quality by default

func supports_reconnection() -> bool:
	return false

func get_max_peers() -> int:
	return 4  # Default to 4 players max

# Utility methods
func validate_message(message: Dictionary) -> bool:
	"""Validate that a message has required fields"""
	return message.has("type") and message.has("timestamp") and message.has("sender_id")

func create_message(type: String, data: Dictionary = {}) -> Dictionary:
	"""Create a properly formatted network message"""
	return {
		"type": type,
		"timestamp": Time.get_ticks_msec(),
		"sender_id": get_local_peer_id(),
		"data": data
	}

func log_network_event(event: String, details: String = "") -> void:
	"""Log network events for debugging"""
	var mode_name = NetworkMode.keys()[get_network_mode()]
	print("[%s] %s: %s" % [mode_name, event, details])