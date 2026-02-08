extends Node

# Multiplayer autoload script
# Makes multiplayer systems globally available throughout the game
# Provides a simple interface for any scene to use multiplayer features

var multiplayer_manager: MultiplayerManager
var is_initialized: bool = false

func _ready() -> void:
	name = "Multiplayer"
	
	# Initialize multiplayer manager
	multiplayer_manager = MultiplayerManager.new()
	add_child(multiplayer_manager)
	
	is_initialized = true
	print("Multiplayer autoload initialized")

# Convenience methods for easy access
func start_local_game(player_names: Array[String] = ["Player 1", "Player 2"]) -> bool:
	"""Start a local multiplayer game"""
	if not is_initialized:
		return false
	return multiplayer_manager.start_local_multiplayer_game(player_names)

func start_p2p_host(player_name: String = "Host", max_players: int = 2) -> bool:
	"""Start hosting a P2P game"""
	if not is_initialized:
		return false
	return multiplayer_manager.start_p2p_multiplayer_game(player_name, max_players)

func join_p2p_game(address: String, port: int, player_name: String = "Player") -> bool:
	"""Join a P2P game"""
	if not is_initialized:
		return false
	return multiplayer_manager.join_p2p_multiplayer_game(address, port, player_name)

func join_server_game(address: String, port: int, username: String, password: String = "") -> bool:
	"""Join a dedicated server game"""
	if not is_initialized:
		return false
	return multiplayer_manager.join_dedicated_server_game(address, port, username, password)

func disconnect_multiplayer() -> void:
	"""Disconnect from multiplayer"""
	if is_initialized:
		multiplayer_manager.disconnect_from_multiplayer()

func submit_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a game action"""
	if not is_initialized:
		return false
	return multiplayer_manager.submit_game_action(action_type, action_data)

func is_active() -> bool:
	"""Check if multiplayer is active"""
	if not is_initialized:
		return false
	return multiplayer_manager.is_multiplayer_active()

func is_my_turn() -> bool:
	"""Check if it's the local player's turn"""
	if not is_initialized:
		return false
	return multiplayer_manager.is_local_player_turn()

func get_status() -> Dictionary:
	"""Get multiplayer status"""
	if not is_initialized:
		return {}
	return multiplayer_manager.get_multiplayer_status()

func get_connection_info() -> Dictionary:
	"""Get host connection info for sharing"""
	if not is_initialized:
		return {}
	return multiplayer_manager.get_host_connection_info()

# Signal forwarding for easy access
signal game_started(players: Array)
signal game_ended(winner_id: int)
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, player_name: String)
signal connection_status_changed(status: String)
signal turn_started(player_id: int)
signal turn_ended(player_id: int)

func _connect_signals() -> void:
	"""Connect multiplayer manager signals to autoload signals"""
	if multiplayer_manager:
		multiplayer_manager.multiplayer_game_started.connect(game_started.emit)
		multiplayer_manager.multiplayer_game_ended.connect(game_ended.emit)
		multiplayer_manager.player_joined.connect(player_joined.emit)
		multiplayer_manager.player_left.connect(player_left.emit)
		multiplayer_manager.connection_status_changed.connect(connection_status_changed.emit)
		
		if multiplayer_manager._multiplayer_turn_system:
			multiplayer_manager._multiplayer_turn_system.multiplayer_turn_started.connect(turn_started.emit)
			multiplayer_manager._multiplayer_turn_system.multiplayer_turn_ended.connect(turn_ended.emit)