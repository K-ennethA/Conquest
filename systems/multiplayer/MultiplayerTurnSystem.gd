extends Node

class_name MultiplayerTurnSystem

# Multiplayer-aware turn system that works with existing turn systems
# Handles turn synchronization across multiple players
# Integrates with both Traditional and Speed First turn systems

signal turn_synchronized(current_player_id: int, turn_data: Dictionary)
signal turn_validation_failed(player_id: int, reason: String)
signal multiplayer_turn_started(player_id: int)
signal multiplayer_turn_ended(player_id: int)

# Core components
var _network_manager: NetworkManager
var _multiplayer_game_state: MultiplayerGameState
var _base_turn_system: Node  # The underlying turn system (Traditional or Speed First)

# Turn state
var _current_multiplayer_turn: int = 1
var _current_player_id: int = -1
var _turn_in_progress: bool = false
var _waiting_for_turn_sync: bool = false

# Player management
var _player_peer_mapping: Dictionary = {}  # peer_id -> player_id
var _player_turn_order: Array[int] = []
var _players_ready: Dictionary = {}  # player_id -> bool

# Turn validation
var _turn_actions: Array[Dictionary] = []
var _turn_timeout: float = 60.0  # 1 minute per turn
var _turn_timer: Timer

func _ready() -> void:
	name = "MultiplayerTurnSystem"
	
	# Get required components
	_network_manager = get_node("/root/NetworkManager")
	_multiplayer_game_state = get_node("/root/MultiplayerGameState")
	
	if _network_manager:
		_network_manager.message_received.connect(_on_network_message_received)
		_network_manager.connection_established.connect(_on_peer_connected)
		_network_manager.connection_lost.connect(_on_peer_disconnected)
		print("MultiplayerTurnSystem connected to NetworkManager")
	
	if _multiplayer_game_state:
		_multiplayer_game_state.action_validated.connect(_on_action_validated)
		print("MultiplayerTurnSystem connected to MultiplayerGameState")
	
	# Create turn timer
	_turn_timer = Timer.new()
	_turn_timer.wait_time = _turn_timeout
	_turn_timer.timeout.connect(_on_turn_timeout)
	_turn_timer.one_shot = true
	add_child(_turn_timer)

# Public API
func initialize_multiplayer_turns(base_turn_system: Node, player_order: Array[int]) -> void:
	"""Initialize multiplayer turn system with base turn system"""
	_base_turn_system = base_turn_system
	_player_turn_order = player_order.duplicate()
	_current_player_id = _player_turn_order[0] if _player_turn_order.size() > 0 else -1
	
	# Connect to base turn system signals
	if _base_turn_system:
		if _base_turn_system.has_signal("turn_started"):
			_base_turn_system.turn_started.connect(_on_base_turn_started)
		if _base_turn_system.has_signal("turn_ended"):
			_base_turn_system.turn_ended.connect(_on_base_turn_ended)
		if _base_turn_system.has_signal("player_turn_started"):
			_base_turn_system.player_turn_started.connect(_on_base_player_turn_started)
		if _base_turn_system.has_signal("player_turn_ended"):
			_base_turn_system.player_turn_ended.connect(_on_base_player_turn_ended)
		
		print("MultiplayerTurnSystem initialized with %s" % _base_turn_system.name)
	
	# Initialize player readiness
	for player_id in _player_turn_order:
		_players_ready[player_id] = false
	
	print("Multiplayer turns initialized for players: %s" % str(_player_turn_order))

func set_player_peer_mapping(mapping: Dictionary) -> void:
	"""Set mapping between peer IDs and player IDs"""
	_player_peer_mapping = mapping.duplicate()
	print("Player-peer mapping set: %s" % str(_player_peer_mapping))

func start_multiplayer_turn(player_id: int) -> bool:
	"""Start a turn for a specific player"""
	if _turn_in_progress:
		print("Cannot start turn: turn already in progress")
		return false
	
	if player_id not in _player_turn_order:
		print("Cannot start turn: invalid player ID %d" % player_id)
		return false
	
	_current_player_id = player_id
	_turn_in_progress = true
	_turn_actions.clear()
	
	# Start turn timer
	_turn_timer.start()
	
	# Notify all players
	_broadcast_turn_start(player_id)
	
	# Start turn in base system if we're the current player or host
	var local_peer_id = _network_manager.get_local_peer_id()
	var is_local_turn = _get_peer_for_player(player_id) == local_peer_id
	var is_host = _network_manager.is_host()
	
	if is_local_turn or is_host:
		_start_base_turn(player_id)
	
	print("Multiplayer turn started for player %d" % player_id)
	multiplayer_turn_started.emit(player_id)
	
	return true

func end_multiplayer_turn(player_id: int) -> bool:
	"""End the current turn"""
	if not _turn_in_progress:
		print("Cannot end turn: no turn in progress")
		return false
	
	if player_id != _current_player_id:
		print("Cannot end turn: not current player's turn (current: %d, requested: %d)" % [_current_player_id, player_id])
		return false
	
	# Validate turn actions
	if not _validate_turn_actions():
		print("Turn validation failed for player %d" % player_id)
		turn_validation_failed.emit(player_id, "Invalid turn actions")
		return false
	
	# Stop turn timer
	_turn_timer.stop()
	
	# End turn in base system
	_end_base_turn(player_id)
	
	# Broadcast turn end
	_broadcast_turn_end(player_id)
	
	# Advance to next player
	_advance_to_next_player()
	
	print("Multiplayer turn ended for player %d" % player_id)
	multiplayer_turn_ended.emit(player_id)
	
	return true

func submit_turn_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit an action during the current turn"""
	if not _turn_in_progress:
		print("Cannot submit action: no turn in progress")
		return false
	
	var local_peer_id = _network_manager.get_local_peer_id()
	var current_peer_id = _get_peer_for_player(_current_player_id)
	
	if local_peer_id != current_peer_id:
		print("Cannot submit action: not your turn")
		return false
	
	# Create turn action
	var action = {
		"type": action_type,
		"data": action_data,
		"player_id": _current_player_id,
		"turn_number": _current_multiplayer_turn,
		"timestamp": Time.get_ticks_msec()
	}
	
	# Add to turn actions
	_turn_actions.append(action)
	
	# Submit to multiplayer game state
	return _multiplayer_game_state.submit_action("turn_action", action)

func get_current_player_id() -> int:
	"""Get the current player's ID"""
	return _current_player_id

func get_current_turn_number() -> int:
	"""Get the current turn number"""
	return _current_multiplayer_turn

func is_local_player_turn() -> bool:
	"""Check if it's the local player's turn"""
	var local_peer_id = _network_manager.get_local_peer_id()
	var current_peer_id = _get_peer_for_player(_current_player_id)
	return local_peer_id == current_peer_id

func get_turn_time_remaining() -> float:
	"""Get remaining time for current turn"""
	return _turn_timer.time_left if _turn_timer else 0.0

# Player readiness
func set_player_ready(player_id: int, ready: bool) -> void:
	"""Set a player's readiness state"""
	_players_ready[player_id] = ready
	
	# Broadcast readiness state
	_broadcast_player_readiness(player_id, ready)
	
	print("Player %d readiness: %s" % [player_id, ready])

func are_all_players_ready() -> bool:
	"""Check if all players are ready"""
	for player_id in _player_turn_order:
		if not _players_ready.get(player_id, false):
			return false
	return true

func get_player_readiness() -> Dictionary:
	"""Get readiness state of all players"""
	return _players_ready.duplicate()

# Internal methods
func _start_base_turn(player_id: int) -> void:
	"""Start turn in the base turn system"""
	if not _base_turn_system:
		return
	
	# Different handling based on turn system type
	if _base_turn_system is TraditionalTurnSystem:
		# Traditional turn system - start player turn
		if _base_turn_system.has_method("start_player_turn"):
			_base_turn_system.start_player_turn(player_id)
	elif _base_turn_system is SpeedFirstTurnSystem:
		# Speed First turn system - different handling
		if _base_turn_system.has_method("set_current_acting_player"):
			_base_turn_system.set_current_acting_player(player_id)
	else:
		# Generic turn system
		if _base_turn_system.has_method("start_turn"):
			_base_turn_system.start_turn()

func _end_base_turn(player_id: int) -> void:
	"""End turn in the base turn system"""
	if not _base_turn_system:
		return
	
	# Different handling based on turn system type
	if _base_turn_system is TraditionalTurnSystem:
		if _base_turn_system.has_method("end_player_turn"):
			_base_turn_system.end_player_turn()
	elif _base_turn_system is SpeedFirstTurnSystem:
		if _base_turn_system.has_method("end_current_turn"):
			_base_turn_system.end_current_turn()
	else:
		if _base_turn_system.has_method("end_turn"):
			_base_turn_system.end_turn()

func _advance_to_next_player() -> void:
	"""Advance to the next player in turn order"""
	var current_index = _player_turn_order.find(_current_player_id)
	var next_index = (current_index + 1) % _player_turn_order.size()
	
	# If we've completed a full round, increment turn number
	if next_index == 0:
		_current_multiplayer_turn += 1
	
	_turn_in_progress = false
	
	# Start next player's turn
	var next_player_id = _player_turn_order[next_index]
	start_multiplayer_turn(next_player_id)

func _validate_turn_actions() -> bool:
	"""Validate all actions taken during the current turn"""
	# TODO: Implement proper turn validation
	# For now, just check that actions exist
	return _turn_actions.size() > 0

func _get_peer_for_player(player_id: int) -> int:
	"""Get peer ID for a player ID"""
	for peer_id in _player_peer_mapping:
		if _player_peer_mapping[peer_id] == player_id:
			return peer_id
	return -1

func _get_player_for_peer(peer_id: int) -> int:
	"""Get player ID for a peer ID"""
	var player_id_raw = _player_peer_mapping.get(peer_id, -1)
	# Ensure we return an int (mapping values might be Strings from network)
	return int(player_id_raw) if player_id_raw is String else player_id_raw

# Network broadcasting
func _broadcast_turn_start(player_id: int) -> void:
	"""Broadcast turn start to all players"""
	var message = {
		"type": "turn_start",
		"player_id": player_id,
		"turn_number": _current_multiplayer_turn,
		"timestamp": Time.get_ticks_msec()
	}
	
	_network_manager.send_game_action("multiplayer_turn", message)

func _broadcast_turn_end(player_id: int) -> void:
	"""Broadcast turn end to all players"""
	var message = {
		"type": "turn_end",
		"player_id": player_id,
		"turn_number": _current_multiplayer_turn,
		"actions": _turn_actions,
		"timestamp": Time.get_ticks_msec()
	}
	
	_network_manager.send_game_action("multiplayer_turn", message)

func _broadcast_player_readiness(player_id: int, ready: bool) -> void:
	"""Broadcast player readiness state"""
	var message = {
		"type": "player_readiness",
		"player_id": player_id,
		"ready": ready,
		"timestamp": Time.get_ticks_msec()
	}
	
	_network_manager.send_game_action("multiplayer_turn", message)

# Network event handlers
func _on_network_message_received(sender_id: int, message: Dictionary) -> void:
	"""Handle network messages"""
	if message.get("type") == "game_action" and message.get("action_type") == "multiplayer_turn":
		_handle_multiplayer_turn_message(sender_id, message.get("action_data", {}))

func _handle_multiplayer_turn_message(sender_id: int, data: Dictionary) -> void:
	"""Handle multiplayer turn messages"""
	match data.get("type", ""):
		"turn_start":
			_handle_remote_turn_start(sender_id, data)
		"turn_end":
			_handle_remote_turn_end(sender_id, data)
		"player_readiness":
			_handle_remote_player_readiness(sender_id, data)

func _handle_remote_turn_start(sender_id: int, data: Dictionary) -> void:
	"""Handle turn start from remote player"""
	var player_id = data.get("player_id", -1)
	var turn_number = data.get("turn_number", 0)
	
	# Only accept from host or the player whose turn it is
	var is_from_host = sender_id == 1 or _network_manager.is_host()
	var is_from_current_player = _get_peer_for_player(player_id) == sender_id
	
	if not (is_from_host or is_from_current_player):
		print("Ignoring turn start from unauthorized peer %d" % sender_id)
		return
	
	# Sync turn state
	_current_player_id = player_id
	_current_multiplayer_turn = turn_number
	_turn_in_progress = true
	_turn_actions.clear()
	
	# Start turn timer
	_turn_timer.start()
	
	print("Received turn start for player %d (turn %d)" % [player_id, turn_number])
	multiplayer_turn_started.emit(player_id)
	turn_synchronized.emit(player_id, data)

func _handle_remote_turn_end(sender_id: int, data: Dictionary) -> void:
	"""Handle turn end from remote player"""
	var player_id = data.get("player_id", -1)
	var turn_number = data.get("turn_number", 0)
	var actions = data.get("actions", [])
	
	# Only accept from the player whose turn it is or host
	var is_from_host = sender_id == 1 or _network_manager.is_host()
	var is_from_current_player = _get_peer_for_player(player_id) == sender_id
	
	if not (is_from_host or is_from_current_player):
		print("Ignoring turn end from unauthorized peer %d" % sender_id)
		return
	
	# Stop turn timer
	_turn_timer.stop()
	
	# Sync turn actions
	_turn_actions = actions
	
	print("Received turn end for player %d with %d actions" % [player_id, actions.size()])
	multiplayer_turn_ended.emit(player_id)
	
	# If we're not the host, wait for next turn start
	if not _network_manager.is_host():
		_turn_in_progress = false

func _handle_remote_player_readiness(sender_id: int, data: Dictionary) -> void:
	"""Handle player readiness from remote player"""
	var player_id = data.get("player_id", -1)
	var ready = data.get("ready", false)
	
	# Verify sender is authorized to set this player's readiness
	var authorized_peer = _get_peer_for_player(player_id)
	if sender_id != authorized_peer and sender_id != 1:  # Allow host to set any readiness
		print("Ignoring readiness from unauthorized peer %d for player %d" % [sender_id, player_id])
		return
	
	_players_ready[player_id] = ready
	print("Player %d readiness set to %s by peer %d" % [player_id, ready, sender_id])

# Base turn system event handlers
func _on_base_turn_started(unit_or_player) -> void:
	"""Handle turn started in base system"""
	print("Base turn system started turn")

func _on_base_turn_ended(unit_or_player) -> void:
	"""Handle turn ended in base system"""
	print("Base turn system ended turn")

func _on_base_player_turn_started(player) -> void:
	"""Handle player turn started in base system"""
	print("Base turn system started player turn")

func _on_base_player_turn_ended(player) -> void:
	"""Handle player turn ended in base system"""
	print("Base turn system ended player turn")

func _on_action_validated(action: Dictionary, is_valid: bool) -> void:
	"""Handle action validation from multiplayer game state"""
	if not is_valid:
		print("Turn action validation failed: %s" % action.get("type", "unknown"))
		# Remove invalid action from turn actions
		_turn_actions = _turn_actions.filter(func(a): return a != action)

func _on_peer_connected(peer_id: int) -> void:
	"""Handle peer connection"""
	print("MultiplayerTurnSystem: Peer %d connected" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	"""Handle peer disconnection"""
	var player_id = _get_player_for_peer(peer_id)
	print("MultiplayerTurnSystem: Peer " + str(peer_id) + " (player " + str(player_id) + ") disconnected")
	
	# Handle disconnection during their turn
	if player_id == _current_player_id and _turn_in_progress:
		print("Current player disconnected, ending their turn")
		_turn_timer.stop()
		_turn_in_progress = false
		_advance_to_next_player()

func _on_turn_timeout() -> void:
	"""Handle turn timeout"""
	print("Turn timeout for player %d" % _current_player_id)
	
	# Force end the current turn
	if _turn_in_progress:
		_turn_in_progress = false
		multiplayer_turn_ended.emit(_current_player_id)
		_advance_to_next_player()

# Configuration
func set_turn_timeout(timeout_seconds: float) -> void:
	"""Set turn timeout duration"""
	_turn_timeout = timeout_seconds
	_turn_timer.wait_time = timeout_seconds
	print("Turn timeout set to %.1f seconds" % timeout_seconds)

# Debug methods
func get_debug_info() -> Dictionary:
	"""Get debug information about multiplayer turns"""
	return {
		"current_player_id": _current_player_id,
		"current_turn": _current_multiplayer_turn,
		"turn_in_progress": _turn_in_progress,
		"waiting_for_sync": _waiting_for_turn_sync,
		"turn_actions": _turn_actions.size(),
		"players_ready": _players_ready,
		"player_peer_mapping": _player_peer_mapping,
		"turn_time_remaining": get_turn_time_remaining()
	}