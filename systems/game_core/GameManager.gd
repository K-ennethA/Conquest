extends Node

class_name GameManager

# Central game manager that handles both single-player and multiplayer games
# Provides a unified interface for game logic regardless of networking mode

signal game_started(game_mode: GameMode, players: Array)
signal game_ended(winner_id: int)
signal player_action_processed(action: Dictionary)
signal turn_changed(current_player_id: int)

enum GameMode {
	SINGLE_PLAYER,
	LOCAL_MULTIPLAYER,  # Hot-seat or split-screen
	NETWORK_MULTIPLAYER # P2P or dedicated server
}

# Core game state
var _game_mode: GameMode = GameMode.SINGLE_PLAYER
var _is_game_active: bool = false
var _current_turn_player: int = -1
var _players: Dictionary = {}  # player_id -> player_data
var _game_settings: Dictionary = {}

# System references
var _turn_system: Node = null
var _player_manager: Node = null
var _network_handler: NetworkHandler = null

func _ready() -> void:
	name = "GameManager"
	
	# Get existing systems
	_player_manager = get_node_or_null("/root/PlayerManager")
	_turn_system = TurnSystemManager.get_active_turn_system() if TurnSystemManager else null
	
	print(_get_log_prefix() + "GameManager initialized")

# Public API - Game Management
func start_single_player_game(settings: Dictionary = {}) -> bool:
	"""Start a single-player game"""
	print("Starting single-player game")
	
	_game_mode = GameMode.SINGLE_PLAYER
	_game_settings = settings
	
	# Initialize single player
	_players.clear()
	_players[0] = {
		"id": 0,
		"name": settings.get("player_name", "Player"),
		"is_local": true,
		"is_ai": false
	}
	
	# Add AI players if specified
	var ai_count = settings.get("ai_players", 1)
	for i in range(ai_count):
		_players[i + 1] = {
			"id": i + 1,
			"name": "AI Player " + str(i + 1),
			"is_local": false,
			"is_ai": true
		}
	
	return _initialize_game()

func start_local_multiplayer_game(player_names: Array[String], settings: Dictionary = {}) -> bool:
	"""Start a local multiplayer game (hot-seat)"""
	print("Starting local multiplayer game with players: %s" % str(player_names))
	
	_game_mode = GameMode.LOCAL_MULTIPLAYER
	_game_settings = settings
	
	# Initialize players
	_players.clear()
	for i in range(player_names.size()):
		_players[i] = {
			"id": i,
			"name": player_names[i],
			"is_local": true,
			"is_ai": false
		}
	
	return _initialize_game()

func start_network_multiplayer_game(network_handler: NetworkHandler, settings: Dictionary = {}) -> bool:
	"""Start a network multiplayer game"""
	print(_get_log_prefix() + "Starting network multiplayer game")
	
	_game_mode = GameMode.NETWORK_MULTIPLAYER
	_game_settings = settings
	_network_handler = network_handler
	
	# Initialize players for network multiplayer
	_players.clear()
	
	# Always create 2 players for multiplayer
	_players[0] = {
		"id": 0,
		"name": "Player 1",
		"is_local": _network_handler.is_host() if _network_handler else true,
		"is_ai": false
	}
	
	_players[1] = {
		"id": 1,
		"name": "Player 2", 
		"is_local": not _network_handler.is_host() if _network_handler else false,
		"is_ai": false
	}
	
	print(_get_log_prefix() + "Network multiplayer players initialized:")
	for player_id in _players:
		var player = _players[player_id]
		var local_indicator = " (LOCAL)" if player.is_local else " (REMOTE)"
		print(_get_log_prefix() + "  Player %d: %s%s" % [player_id, player.name, local_indicator])
	
	# Connect to network events
	if _network_handler:
		_network_handler.player_joined.connect(_on_network_player_joined)
		_network_handler.player_left.connect(_on_network_player_left)
		_network_handler.action_received.connect(_on_network_action_received)
	
	return _initialize_game()

func end_game(winner_id: int = -1) -> void:
	"""End the current game"""
	print("Ending game, winner: %d" % winner_id)
	
	_is_game_active = false
	
	# Disconnect network handler if active
	if _network_handler:
		_network_handler.player_joined.disconnect(_on_network_player_joined)
		_network_handler.player_left.disconnect(_on_network_player_left)
		_network_handler.action_received.disconnect(_on_network_action_received)
		_network_handler = null
	
	game_ended.emit(winner_id)

# Action Processing
func submit_player_action(action_type: String, action_data: Dictionary, player_id: int = -1) -> bool:
	"""Submit a player action for processing"""
	if not _is_game_active:
		print("Cannot submit action: game not active")
		return false
	
	# Use current player if not specified
	if player_id == -1:
		player_id = _current_turn_player
	
	# Validate action based on game mode
	if not _validate_action(action_type, action_data, player_id):
		print("Action validation failed: %s" % action_type)
		return false
	
	var action = {
		"type": action_type,
		"data": action_data,
		"player_id": player_id,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Process based on game mode
	match _game_mode:
		GameMode.SINGLE_PLAYER, GameMode.LOCAL_MULTIPLAYER:
			return _process_local_action(action)
		GameMode.NETWORK_MULTIPLAYER:
			return _process_network_action(action)
	
	return false

func _validate_action(action_type: String, action_data: Dictionary, player_id: int) -> bool:
	"""Validate if an action is allowed"""
	# Check if player exists
	if not _players.has(player_id):
		print("Action rejected: invalid player ID %d (available players: %s)" % [player_id, _players.keys()])
		return false
	
	# In network multiplayer, be more permissive for now to allow testing
	if _game_mode == GameMode.NETWORK_MULTIPLAYER:
		print("Network multiplayer: allowing action %s for player %d" % [action_type, player_id])
		return true
	
	# Check if it's the player's turn
	if player_id != _current_turn_player:
		print("Action rejected: not player's turn (current: %d, submitted: %d)" % [_current_turn_player, player_id])
		return false
	
	# Validate with turn system
	if _turn_system and _turn_system.has_method("validate_action"):
		return _turn_system.validate_action(action_type, action_data, player_id)
	
	return true

func _process_local_action(action: Dictionary) -> bool:
	"""Process action in single-player or local multiplayer"""
	print("Processing local action: %s" % action.type)
	
	# Apply action to game state
	_apply_action_to_game_state(action)
	
	# Emit for UI updates
	player_action_processed.emit(action)
	
	# Check for turn advancement
	_check_turn_advancement(action)
	
	return true

func _process_network_action(action: Dictionary) -> bool:
	"""Process action in network multiplayer"""
	print("Processing network action: %s" % action.type)
	
	if not _network_handler:
		return false
	
	# Send to network handler for synchronization
	return _network_handler.submit_action(action)

func _apply_action_to_game_state(action: Dictionary) -> void:
	"""Apply an action to the game state"""
	# This is where the actual game logic happens
	# Forward to appropriate systems based on action type
	
	match action.type:
		"unit_move":
			_handle_unit_move(action.data)
		"unit_attack":
			_handle_unit_attack(action.data)
		"end_turn":
			_handle_end_turn(action.data)
		"unit_select":
			_handle_unit_select(action.data)
		_:
			print("Unknown action type: %s" % action.type)

func _handle_unit_move(data: Dictionary) -> void:
	"""Handle unit movement action"""
	var unit_id = data.get("unit_id", "")
	var from_pos = data.get("from_position", Vector3.ZERO)
	var to_pos = data.get("to_position", Vector3.ZERO)
	
	print("Unit move: %s from %s to %s" % [unit_id, from_pos, to_pos])
	
	# Emit through GameEvents for existing systems to handle
	if GameEvents:
		# Find the unit and emit the movement
		var unit = _find_unit_by_id(unit_id)
		if unit:
			GameEvents.unit_moved.emit(unit, from_pos, to_pos)

func _handle_unit_attack(data: Dictionary) -> void:
	"""Handle unit attack action"""
	var attacker_id = data.get("attacker_id", "")
	var target_id = data.get("target_id", "")
	var damage = data.get("damage", 0)
	
	print("Unit attack: %s -> %s for %d damage" % [attacker_id, target_id, damage])
	
	# Forward to combat system
	# TODO: Implement combat system integration

func _handle_end_turn(data: Dictionary) -> void:
	"""Handle end turn action"""
	var player_id = data.get("player_id", -1)
	print("End turn for player %d" % player_id)
	
	# Advance to next player
	_advance_turn()

func _handle_unit_select(data: Dictionary) -> void:
	"""Handle unit selection action"""
	var unit_id = data.get("unit_id", "")
	var player_id = data.get("player_id", -1)
	
	print("Unit selected: %s by player %d" % [unit_id, player_id])
	
	# Emit through GameEvents
	if GameEvents:
		var unit = _find_unit_by_id(unit_id)
		if unit:
			var position = unit.global_position
			GameEvents.unit_selected.emit(unit, position)

func _find_unit_by_id(unit_id: String) -> Unit:
	"""Find a unit by its ID in the current scene"""
	var scene_root = get_tree().current_scene
	
	# Look in player nodes
	for player_path in ["Map/Player1", "Map/Player2"]:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit and child.has_method("get_id") and child.get_id() == unit_id:
					return child
	
	return null

# Turn Management
func _initialize_game() -> bool:
	"""Initialize the game with current settings"""
	print("Initializing game with mode: %s" % GameMode.keys()[_game_mode])
	
	_is_game_active = true
	_current_turn_player = 0  # Start with first player
	
	# Initialize turn system if available
	if _turn_system and _turn_system.has_method("initialize_for_game_manager"):
		_turn_system.initialize_for_game_manager(self)
	
	# Emit game started
	game_started.emit(_game_mode, _players.keys())
	
	return true

func _advance_turn() -> void:
	"""Advance to the next player's turn"""
	var player_ids = _players.keys()
	if player_ids.is_empty():
		return
	
	var current_index = player_ids.find(_current_turn_player)
	var next_index = (current_index + 1) % player_ids.size()
	_current_turn_player = player_ids[next_index]
	
	print(_get_log_prefix() + "Turn advanced to player %d" % _current_turn_player)
	
	# In network multiplayer, sync the turn change
	if _game_mode == GameMode.NETWORK_MULTIPLAYER and _network_handler:
		var turn_action = {
			"type": "turn_change",
			"data": {
				"current_player": _current_turn_player,
				"timestamp": Time.get_ticks_msec()
			}
		}
		print(_get_log_prefix() + "Sending turn_change action to network")
		_network_handler.submit_action(turn_action)
	
	print(_get_log_prefix() + "Emitting turn_changed signal for player %d" % _current_turn_player)
	turn_changed.emit(_current_turn_player)

func _check_turn_advancement(action: Dictionary) -> void:
	"""Check if the turn should advance after an action"""
	# This depends on the turn system and action type
	if action.type == "end_turn":
		_advance_turn()
	elif _turn_system and _turn_system.has_method("should_advance_turn"):
		if _turn_system.should_advance_turn(action):
			_advance_turn()

# Network Event Handlers
func _on_network_player_joined(player_id: int, player_name: String) -> void:
	"""Handle player joining network game"""
	_players[player_id] = {
		"id": player_id,
		"name": player_name,
		"is_local": false,
		"is_ai": false
	}
	
	print("Network player joined: %s (ID: %d)" % [player_name, player_id])

func _on_network_player_left(player_id: int) -> void:
	"""Handle player leaving network game"""
	if _players.has(player_id):
		var player_name = _players[player_id]["name"]
		_players.erase(player_id)
		print("Network player left: %s (ID: %d)" % [player_name, player_id])

func _on_network_action_received(action: Dictionary) -> void:
	"""Handle action received from network"""
	print(_get_log_prefix() + "=== NETWORK ACTION RECEIVED ===")
	print(_get_log_prefix() + "Action type: %s" % action.type)
	print(_get_log_prefix() + "Full action: %s" % str(action))
	
	# Handle turn synchronization
	if action.type == "turn_change":
		print(_get_log_prefix() + "Processing direct turn_change action")
		var action_data = action.get("data", {})
		var new_current_player = action_data.get("current_player", -1)
		print(_get_log_prefix() + "New current player from action: %d" % new_current_player)
		
		if new_current_player != -1:
			_current_turn_player = new_current_player
			print(_get_log_prefix() + "Turn synchronized to player %d via network" % _current_turn_player)
			print(_get_log_prefix() + "Emitting turn_changed signal")
			turn_changed.emit(_current_turn_player)
		else:
			print(_get_log_prefix() + "ERROR: Invalid current_player in turn_change action")
		print(_get_log_prefix() + "=== END NETWORK ACTION (turn_change) ===")
		return
	
	# Handle nested action structure (action contains another action)
	if action.has("data") and action.data.has("type"):
		# This is a nested action structure - extract the inner action
		var inner_action = action.data
		print(_get_log_prefix() + "Processing nested action structure")
		print(_get_log_prefix() + "Inner action type: %s" % inner_action.type)
		print(_get_log_prefix() + "Inner action: %s" % str(inner_action))
		
		if inner_action.type == "turn_change":
			print(_get_log_prefix() + "Processing nested turn_change action")
			var inner_data = inner_action.get("data", {})
			var new_current_player = inner_data.get("current_player", -1)
			print(_get_log_prefix() + "New current player from nested action: %d" % new_current_player)
			
			if new_current_player != -1:
				_current_turn_player = new_current_player
				print(_get_log_prefix() + "Turn synchronized to player %d via nested network action" % _current_turn_player)
				print(_get_log_prefix() + "Emitting turn_changed signal")
				turn_changed.emit(_current_turn_player)
			else:
				print(_get_log_prefix() + "ERROR: Invalid current_player in nested turn_change action")
			print(_get_log_prefix() + "=== END NETWORK ACTION (nested turn_change) ===")
			return
		
		# Apply the inner action to game state
		_apply_action_to_game_state(inner_action)
		
		# Emit for UI updates
		player_action_processed.emit(inner_action)
		
		# Check for turn advancement
		_check_turn_advancement(inner_action)
		print(_get_log_prefix() + "=== END NETWORK ACTION (nested other) ===")
		return
	
	# Apply the action locally
	print(_get_log_prefix() + "Processing regular action")
	_apply_action_to_game_state(action)
	
	# Emit for UI updates
	player_action_processed.emit(action)
	
	# Check for turn advancement
	_check_turn_advancement(action)
	print(_get_log_prefix() + "=== END NETWORK ACTION (regular) ===")

# Public Getters
func get_game_mode() -> GameMode:
	return _game_mode

func is_game_active() -> bool:
	return _is_game_active

func get_current_player_id() -> int:
	return _current_turn_player

func get_players() -> Dictionary:
	return _players.duplicate()

func is_local_player_turn(player_id: int = -1) -> bool:
	"""Check if it's a local player's turn"""
	var check_player_id = player_id if player_id != -1 else _current_turn_player
	
	if not _players.has(check_player_id):
		return false
	
	return _players[check_player_id]["is_local"] and check_player_id == _current_turn_player

func can_player_act(player_id: int) -> bool:
	"""Check if a player can currently act"""
	if not _is_game_active:
		return false
	
	if not _players.has(player_id):
		return false
	
	# In single-player and local multiplayer, check if it's their turn
	if _game_mode != GameMode.NETWORK_MULTIPLAYER:
		return player_id == _current_turn_player
	
	# In network multiplayer, also check with network handler
	if _network_handler:
		return _network_handler.can_player_act(player_id)
	
	return player_id == _current_turn_player

# Debug and Status
func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	var prefix = "[UNKNOWN] "
	
	if _game_mode == GameMode.NETWORK_MULTIPLAYER and _network_handler:
		if _network_handler.is_host():
			prefix = "[HOST] "
		else:
			prefix = "[CLIENT] "
	else:
		prefix = "[SINGLE] "
	
	return prefix

func get_game_status() -> Dictionary:
	"""Get comprehensive game status"""
	return {
		"game_mode": GameMode.keys()[_game_mode],
		"is_active": _is_game_active,
		"current_player": _current_turn_player,
		"players": _players,
		"settings": _game_settings,
		"has_network_handler": _network_handler != null
	}