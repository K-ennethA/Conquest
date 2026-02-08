extends Node

# High-level manager that coordinates between single-player and multiplayer modes
# Provides a simple interface for the entire game

signal game_mode_changed(new_mode: GameManager.GameMode)
signal game_started(mode: GameManager.GameMode)
signal game_ended(winner_id: int)

var _game_manager: GameManager
var _network_handler: NetworkHandler = null

func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	var prefix = "[UNKNOWN] "
	
	# Be more defensive about accessing _network_handler and _game_manager
	if _network_handler and _network_handler.has_method("is_host"):
		if _network_handler.is_host():
			prefix = "[HOST] "
		else:
			prefix = "[CLIENT] "
	elif _game_manager and _game_manager.has_method("get_game_mode") and _game_manager.get_game_mode() == GameManager.GameMode.NETWORK_MULTIPLAYER:
		# Fallback - try to determine from local player ID
		var local_id = get_local_player_id()
		if local_id == 0:
			prefix = "[HOST] "
		elif local_id == 1:
			prefix = "[CLIENT] "
		else:
			prefix = "[PLAYER" + str(local_id) + "] "
	else:
		prefix = "[SINGLE] "
	
	return prefix

func _ready() -> void:
	name = "GameModeManager"
	
	# Create game manager
	_game_manager = GameManager.new()
	if not _game_manager:
		print("ERROR: Failed to create GameManager!")
		return
	
	add_child(_game_manager)
	
	# Connect signals
	_game_manager.game_started.connect(_on_game_started)
	_game_manager.game_ended.connect(_on_game_ended)
	_game_manager.player_action_processed.connect(_on_player_action_processed)
	_game_manager.turn_changed.connect(_on_turn_changed)
	
	print(_get_log_prefix() + "GameModeManager initialized with GameManager: " + str(_game_manager))

# Public API - Simple interface for the game
func start_single_player(player_name: String = "Player", ai_count: int = 1) -> bool:
	"""Start a single-player game"""
	var settings = {
		"player_name": player_name,
		"ai_players": ai_count
	}
	
	return _game_manager.start_single_player_game(settings)

func start_local_multiplayer(player_names: Array[String]) -> bool:
	"""Start a local multiplayer game (hot-seat)"""
	return _game_manager.start_local_multiplayer_game(player_names)

func start_network_multiplayer_host(player_name: String = "Host", network_mode: String = "p2p") -> bool:
	"""Start hosting a network multiplayer game"""
	print("[HOST] === START NETWORK MULTIPLAYER HOST ===")
	print("[HOST] Player name: " + player_name)
	print("[HOST] Network mode: " + network_mode)
	
	# Create network handler
	_network_handler = MultiplayerNetworkHandler.new()
	
	var settings = {
		"network_mode": network_mode,
		"player_name": player_name,
		"is_host": true
	}
	
	print("[HOST] Initializing network handler with settings: " + str(settings))
	
	# Initialize network handler
	var success = await _network_handler.initialize(settings)
	if not success:
		print("[HOST] ERROR: Failed to initialize network handler")
		return false
	
	print("[HOST] Network handler initialized successfully")
	
	# Start hosting on a consistent port (8910) for local development
	var host_port = 8910
	print("[HOST] Starting host on port: " + str(host_port))
	
	if not _network_handler.start_host(host_port):
		print("[HOST] ERROR: Failed to start hosting")
		return false
	
	print("[HOST] Host started successfully on port " + str(host_port))
	
	# Start game with network handler
	var game_success = _game_manager.start_network_multiplayer_game(_network_handler, settings)
	print("[HOST] Game start result: " + str(game_success))
	print("[HOST] === END START NETWORK MULTIPLAYER HOST ===")
	
	return game_success

func join_network_multiplayer(address: String, port: int, player_name: String = "Player", network_mode: String = "p2p") -> bool:
	"""Join a network multiplayer game"""
	print("[CLIENT] === JOIN NETWORK MULTIPLAYER START ===")
	print("[CLIENT] GameModeManager: join_network_multiplayer called")
	print("[CLIENT] Address: %s, Port: %d, Player: %s, Mode: %s" % [address, port, player_name, network_mode])
	
	# Create network handler
	_network_handler = MultiplayerNetworkHandler.new()
	print("[CLIENT] Created MultiplayerNetworkHandler: " + str(_network_handler))
	
	var settings = {
		"network_mode": network_mode,
		"player_name": player_name,
		"is_host": false
	}
	
	print("[CLIENT] Initializing network handler with settings: " + str(settings))
	
	# Initialize network handler
	var success = await _network_handler.initialize(settings)
	if not success:
		print("[CLIENT] ERROR: Failed to initialize network handler")
		return false
	
	print("[CLIENT] Network handler initialized successfully")
	
	# Join host
	print("[CLIENT] Attempting to join host at %s:%d" % [address, port])
	if not _network_handler.join_host(address, port):
		print("[CLIENT] ERROR: Failed to join host")
		return false
	
	print("[CLIENT] Join host call successful, waiting for connection...")
	
	# Wait for connection to establish (increased timeout for P2P)
	var max_wait_time = 5.0
	var wait_interval = 0.5
	var total_waited = 0.0
	
	while total_waited < max_wait_time:
		await get_tree().create_timer(wait_interval).timeout
		total_waited += wait_interval
		
		var connection_status = _network_handler.get_connection_status()
		print("[CLIENT] Connection status after %.1fs: %s" % [total_waited, connection_status])
		
		if connection_status == "connected":
			print("[CLIENT] Connection established successfully!")
			break
		elif connection_status.begins_with("failed"):
			print("[CLIENT] ERROR: Connection failed: %s" % connection_status)
			return false
	
	# Final check
	var final_status = _network_handler.get_connection_status()
	if final_status != "connected":
		print("[CLIENT] ERROR: Connection not established after %.1fs (status: %s)" % [max_wait_time, final_status])
		return false
	
	print("[CLIENT] Connection confirmed, starting game...")
	
	# Start game with network handler
	var game_success = _game_manager.start_network_multiplayer_game(_network_handler, settings)
	print("[CLIENT] Game start result: " + str(game_success))
	print("[CLIENT] === JOIN NETWORK MULTIPLAYER END ===")
	
	return game_success

func end_current_game() -> void:
	"""End the current game"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in end_current_game()")
		return
	
	_game_manager.end_game()
	
	# Clean up network handler
	if _network_handler:
		_network_handler.disconnect_network()
		_network_handler = null

# Action submission - unified interface
func submit_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a player action (works for all game modes)"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in submit_action()")
		return false
	return _game_manager.submit_player_action(action_type, action_data)

# Status queries
func get_current_game_mode() -> GameManager.GameMode:
	"""Get current game mode"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in get_current_game_mode()")
		return GameManager.GameMode.SINGLE_PLAYER
	if not _game_manager.has_method("get_game_mode"):
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager missing get_game_mode method")
		return GameManager.GameMode.SINGLE_PLAYER
	return _game_manager.get_game_mode()

func is_game_active() -> bool:
	"""Check if a game is currently active"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in is_game_active()")
		return false
	return _game_manager.is_game_active()

func is_my_turn() -> bool:
	"""Check if it's the local player's turn"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in is_my_turn()")
		return false
	
	var current_mode = _game_manager.get_game_mode()
	if current_mode == GameManager.GameMode.NETWORK_MULTIPLAYER:
		var local_player_id = get_local_player_id()
		var current_player_id = _game_manager.get_current_player_id()
		print(_get_log_prefix() + "DEBUG: is_my_turn check - local_player_id: %d, current_player_id: %d" % [local_player_id, current_player_id])
		return local_player_id == current_player_id
	else:
		return _game_manager.is_local_player_turn()

func can_i_act() -> bool:
	"""Check if the local player can currently act"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in can_i_act()")
		return false
	
	var current_player = _game_manager.get_current_player_id()
	return _game_manager.can_player_act(current_player)

func get_local_player_id() -> int:
	"""Get the local player ID for this client"""
	if _network_handler and _network_handler.has_method("get_local_player_id"):
		return _network_handler.get_local_player_id()
	
	# For single player and local multiplayer, always return 0 (first player)
	return 0

func is_local_player(player_id: int) -> bool:
	"""Check if the given player ID represents the local player"""
	return player_id == get_local_player_id()

func get_game_status() -> Dictionary:
	"""Get comprehensive game status"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in get_game_status()")
		return {
			"error": "GameManager not available",
			"game_mode": "UNKNOWN",
			"is_active": false
		}
	
	var status = _game_manager.get_game_status()
	
	# Add network info if available
	if _network_handler:
		status["network_status"] = _network_handler.get_connection_status()
		status["network_stats"] = _network_handler.get_network_statistics()
		status["connection_info"] = _network_handler.get_connection_info()
	
	return status

# Signal handlers
func _on_game_started(mode: GameManager.GameMode, players: Array) -> void:
	"""Handle game started"""
	print("Game started in mode: %s with %d players" % [GameManager.GameMode.keys()[mode], players.size()])
	game_mode_changed.emit(mode)
	game_started.emit(mode)

func _on_game_ended(winner_id: int) -> void:
	"""Handle game ended"""
	print("Game ended, winner: %d" % winner_id)
	game_ended.emit(winner_id)

func _on_player_action_processed(action: Dictionary) -> void:
	"""Handle player action processed"""
	# This can be used to update UI or trigger other systems
	pass

func _on_turn_changed(current_player_id: int) -> void:
	"""Handle turn change"""
	print(_get_log_prefix() + "=== GAMEMANAGER TURN CHANGED ===")
	print(_get_log_prefix() + "GameModeManager: Turn changed to player: %d" % current_player_id)
	print(_get_log_prefix() + "GameModeManager: Current game mode: %s" % GameManager.GameMode.keys()[get_current_game_mode()])
	print(_get_log_prefix() + "GameModeManager: Is multiplayer: %s" % str(get_current_game_mode() == GameManager.GameMode.NETWORK_MULTIPLAYER))
	print(_get_log_prefix() + "=== END GAMEMANAGER TURN CHANGED ===")

# Convenience methods for existing code integration
func get_multiplayer_status() -> Dictionary:
	"""Get multiplayer status (for compatibility with existing code)"""
	var status = get_game_status()
	
	# Transform to match existing interface
	return {
		"is_active": status.get("is_active", false),
		"game_mode": status.get("game_mode", "SINGLE_PLAYER"),
		"local_player_id": status.get("current_player", -1),
		"players": status.get("players", {}),
		"network_status": status.get("network_status", "disconnected")
	}

func is_multiplayer_active() -> bool:
	"""Check if multiplayer is active (for compatibility)"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in is_multiplayer_active()")
		return false
	
	var mode = get_current_game_mode()
	return mode == GameManager.GameMode.NETWORK_MULTIPLAYER

func is_local_player_turn() -> bool:
	"""Check if it's local player's turn (for compatibility)"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in is_local_player_turn()")
		return false
	return is_my_turn()

func submit_game_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit game action (for compatibility)"""
	if not _game_manager:
		print(_get_log_prefix() + "GameModeManager: WARNING - _game_manager is null in submit_game_action()")
		return false
	return submit_action(action_type, action_data)
