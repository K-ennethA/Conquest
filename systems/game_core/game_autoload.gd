extends Node

# Global game autoload that provides unified access to game functionality
# Works for both single-player and multiplayer seamlessly
# Uses the GameModeManager autoload

var is_initialized: bool = false

func _ready() -> void:
	name = "Game"
	
	# Wait for GameModeManager autoload to be ready
	await get_tree().process_frame
	
	# Connect signals
	_connect_signals()
	
	is_initialized = true
	print("Game autoload initialized")

# Simple API for any scene to use
func start_single_player(player_name: String = "Player", ai_count: int = 1) -> bool:
	"""Start a single-player game"""
	if not is_initialized:
		return false
	return GameModeManager.start_single_player(player_name, ai_count)

func start_local_multiplayer(player_names: Array[String]) -> bool:
	"""Start a local multiplayer game"""
	if not is_initialized:
		return false
	return GameModeManager.start_local_multiplayer(player_names)

func start_network_host(player_name: String = "Host", network_mode: String = "local") -> bool:
	"""Start hosting a network game"""
	if not is_initialized:
		return false
	return await GameModeManager.start_network_multiplayer_host(player_name, network_mode)

func join_network_game(address: String, port: int, player_name: String = "Player", network_mode: String = "local") -> bool:
	"""Join a network game"""
	if not is_initialized:
		return false
	return await GameModeManager.join_network_multiplayer(address, port, player_name, network_mode)

func end_game() -> void:
	"""End the current game"""
	if is_initialized:
		GameModeManager.end_current_game()

func submit_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a game action"""
	if not is_initialized:
		return false
	return GameModeManager.submit_action(action_type, action_data)

func is_active() -> bool:
	"""Check if a game is active"""
	if not is_initialized:
		return false
	return GameModeManager.is_game_active()

func is_my_turn() -> bool:
	"""Check if it's my turn"""
	if not is_initialized:
		return false
	return GameModeManager.is_my_turn()

func can_i_act() -> bool:
	"""Check if I can act"""
	if not is_initialized:
		return false
	return GameModeManager.can_i_act()

func get_status() -> Dictionary:
	"""Get game status"""
	if not is_initialized:
		return {}
	return GameModeManager.get_game_status()

# Compatibility methods for existing code
func is_multiplayer_active() -> bool:
	"""Check if multiplayer is active (compatibility)"""
	if not is_initialized:
		return false
	return GameModeManager.is_multiplayer_active()

func get_multiplayer_status() -> Dictionary:
	"""Get multiplayer status (compatibility)"""
	if not is_initialized:
		return {}
	return GameModeManager.get_multiplayer_status()

# Signal forwarding for easy access
signal game_started(mode)
signal game_ended(winner_id)
signal mode_changed(new_mode)

func _connect_signals() -> void:
	"""Connect game mode manager signals to autoload signals"""
	if GameModeManager:
		GameModeManager.game_started.connect(game_started.emit)
		GameModeManager.game_ended.connect(game_ended.emit)
		GameModeManager.game_mode_changed.connect(mode_changed.emit)