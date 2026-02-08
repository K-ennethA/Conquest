extends RefCounted

class_name NetworkHandler

# Abstract network handler that provides a clean interface between GameManager and networking
# Separates networking concerns from game logic

signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int)
signal action_received(action: Dictionary)
signal connection_status_changed(status: String)

# Abstract methods that must be implemented by concrete handlers
func initialize(settings: Dictionary) -> bool:
	push_error("NetworkHandler.initialize() must be implemented by subclass")
	return false

func submit_action(action: Dictionary) -> bool:
	push_error("NetworkHandler.submit_action() must be implemented by subclass")
	return false

func can_player_act(player_id: int) -> bool:
	push_error("NetworkHandler.can_player_act() must be implemented by subclass")
	return false

func disconnect_network() -> void:
	push_error("NetworkHandler.disconnect_network() must be implemented by subclass")

func get_connection_status() -> String:
	push_error("NetworkHandler.get_connection_status() must be implemented by subclass")
	return "unknown"

func get_local_player_id() -> int:
	push_error("NetworkHandler.get_local_player_id() must be implemented by subclass")
	return -1

func is_host() -> bool:
	push_error("NetworkHandler.is_host() must be implemented by subclass")
	return false

# Utility methods with default implementations
func get_network_statistics() -> Dictionary:
	return {}

func get_connection_info() -> Dictionary:
	return {}