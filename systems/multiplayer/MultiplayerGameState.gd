extends Node

class_name MultiplayerGameState

# Manages game state synchronization across multiple players
# Handles client-side prediction, rollback, and state reconciliation
# Works with both P2P and dedicated server architectures

signal game_state_updated(state: Dictionary)
signal action_validated(action: Dictionary, is_valid: bool)
signal rollback_occurred(rollback_steps: int)

# Game state management
var _authoritative_state: Dictionary = {}
var _predicted_state: Dictionary = {}
var _state_history: Array[Dictionary] = []
var _pending_actions: Array[Dictionary] = []

# Networking
var _network_manager: NetworkManager
var _local_peer_id: int = -1
var _is_host: bool = false

# Prediction and rollback settings
var _max_history_size: int = 60  # 1 second at 60 FPS
var _prediction_enabled: bool = true
var _rollback_enabled: bool = true

# Action validation
var _action_sequence: int = 0
var _validated_actions: Dictionary = {}  # sequence_id -> action
var _pending_validation: Dictionary = {}  # sequence_id -> action

func _ready() -> void:
	name = "MultiplayerGameState"
	
	# Get network manager
	_network_manager = get_node("/root/NetworkManager")
	if _network_manager:
		_network_manager.message_received.connect(_on_network_message_received)
		_network_manager.connection_established.connect(_on_peer_connected)
		_network_manager.connection_lost.connect(_on_peer_disconnected)
		print("MultiplayerGameState connected to NetworkManager")
	else:
		print("WARNING: NetworkManager not found")

# Public API
func initialize_multiplayer_state(initial_state: Dictionary) -> void:
	"""Initialize the multiplayer game state"""
	_authoritative_state = initial_state.duplicate(true)
	_predicted_state = initial_state.duplicate(true)
	_state_history.clear()
	_pending_actions.clear()
	
	# Store initial state in history
	_add_state_to_history(_authoritative_state)
	
	print("MultiplayerGameState initialized")

func submit_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a game action for processing"""
	if not _network_manager or not _network_manager.is_multiplayer_active():
		print("Cannot submit action: multiplayer not active")
		return false
	
	# Create action with sequence number
	var action = {
		"type": action_type,
		"data": action_data,
		"sequence_id": _get_next_sequence_id(),
		"timestamp": Time.get_ticks_msec(),
		"peer_id": _local_peer_id
	}
	
	# Apply prediction locally if enabled
	if _prediction_enabled:
		_apply_predicted_action(action)
	
	# Send to other players
	var success = _network_manager.send_game_action("player_action", action)
	
	if success:
		# Store for validation
		_pending_validation[action.sequence_id] = action
		_pending_actions.append(action)
		print("Action submitted: %s (seq: %d)" % [action_type, action.sequence_id])
	
	return success

func get_current_state() -> Dictionary:
	"""Get the current game state (predicted if available, otherwise authoritative)"""
	if _prediction_enabled and not _predicted_state.is_empty():
		return _predicted_state.duplicate(true)
	else:
		return _authoritative_state.duplicate(true)

func get_authoritative_state() -> Dictionary:
	"""Get the authoritative game state"""
	return _authoritative_state.duplicate(true)

func is_action_pending(sequence_id: int) -> bool:
	"""Check if an action is still pending validation"""
	return _pending_validation.has(sequence_id)

func get_pending_actions() -> Array[Dictionary]:
	"""Get list of actions pending validation"""
	return _pending_actions.duplicate()

# State management
func _apply_predicted_action(action: Dictionary) -> void:
	"""Apply an action to the predicted state"""
	print("Applying predicted action: %s" % action.type)
	
	# Apply action to predicted state
	_predicted_state = _simulate_action(_predicted_state, action)
	
	# Emit state update
	game_state_updated.emit(_predicted_state)

func _apply_authoritative_action(action: Dictionary) -> void:
	"""Apply a validated action to the authoritative state"""
	print("Applying authoritative action: %s (seq: %d)" % [action.type, action.sequence_id])
	
	# Apply action to authoritative state
	_authoritative_state = _simulate_action(_authoritative_state, action)
	
	# Add to history
	_add_state_to_history(_authoritative_state)
	
	# Mark action as validated
	if action.has("sequence_id"):
		_validated_actions[action.sequence_id] = action
		_pending_validation.erase(action.sequence_id)
	
	# Reconcile predicted state
	if _prediction_enabled:
		_reconcile_predicted_state()
	
	# Emit state update
	game_state_updated.emit(_authoritative_state)

func _simulate_action(state: Dictionary, action: Dictionary) -> Dictionary:
	"""Simulate applying an action to a game state"""
	var new_state = state.duplicate(true)
	
	match action.type:
		"unit_move":
			_simulate_unit_move(new_state, action.data)
		"unit_attack":
			_simulate_unit_attack(new_state, action.data)
		"end_turn":
			_simulate_end_turn(new_state, action.data)
		"unit_select":
			_simulate_unit_select(new_state, action.data)
		"turn_change":
			_simulate_turn_change(new_state, action.data)
		_:
			print("Unknown action type for simulation: " + action.type)
	
	return new_state

func _simulate_unit_move(state: Dictionary, data: Dictionary) -> void:
	"""Simulate a unit movement action"""
	var unit_id = data.get("unit_id", "")
	var from_pos = data.get("from_position", Vector3.ZERO)
	var to_pos = data.get("to_position", Vector3.ZERO)
	
	if state.has("units") and state.units.has(unit_id):
		state.units[unit_id]["position"] = to_pos
		state.units[unit_id]["has_acted"] = true
		print("Simulated unit move: %s from %s to %s" % [unit_id, from_pos, to_pos])

func _simulate_unit_attack(state: Dictionary, data: Dictionary) -> void:
	"""Simulate a unit attack action"""
	var attacker_id = data.get("attacker_id", "")
	var target_id = data.get("target_id", "")
	var damage = data.get("damage", 0)
	
	if state.has("units"):
		if state.units.has(attacker_id):
			state.units[attacker_id]["has_acted"] = true
		
		if state.units.has(target_id):
			var current_health = state.units[target_id].get("health", 0)
			state.units[target_id]["health"] = max(0, current_health - damage)
			print("Simulated attack: %s -> %s for %d damage" % [attacker_id, target_id, damage])

func _simulate_end_turn(state: Dictionary, data: Dictionary) -> void:
	"""Simulate ending a player's turn"""
	var player_id = data.get("player_id", -1)
	
	if state.has("current_player"):
		# Reset unit actions for the ending player
		if state.has("units"):
			for unit_id in state.units:
				var unit = state.units[unit_id]
				if unit.get("owner_id", -1) == player_id:
					unit["has_acted"] = false
		
		# Advance to next player
		var players = state.get("players", [])
		if players.size() > 0:
			var current_index = players.find(player_id)
			var next_index = (current_index + 1) % players.size()
			state["current_player"] = players[next_index]
		
		print("Simulated end turn for player %d" % player_id)

func _simulate_unit_select(state: Dictionary, data: Dictionary) -> void:
	"""Simulate unit selection (usually just UI state)"""
	var unit_id = data.get("unit_id", "")
	var player_id = data.get("player_id", -1)
	
	state["selected_unit"] = unit_id
	state["selecting_player"] = player_id
	print("Simulated unit selection: %s by player %d" % [unit_id, player_id])

func _simulate_turn_change(state: Dictionary, data: Dictionary) -> void:
	"""Simulate a turn change action"""
	var current_player = data.get("current_player", -1)
	
	if current_player >= 0:
		state["current_player"] = current_player
		print("Simulated turn change to player %d" % current_player)

func _reconcile_predicted_state() -> void:
	"""Reconcile predicted state with authoritative state"""
	if not _rollback_enabled:
		# Just sync to authoritative state
		_predicted_state = _authoritative_state.duplicate(true)
		return
	
	# Find the point where prediction diverged from authority
	var rollback_point = _find_rollback_point()
	
	if rollback_point >= 0:
		print("Performing rollback to point %d" % rollback_point)
		
		# Rollback to authoritative state
		_predicted_state = _authoritative_state.duplicate(true)
		
		# Re-apply unvalidated actions
		var unvalidated_actions = _get_unvalidated_actions()
		for action in unvalidated_actions:
			_predicted_state = _simulate_action(_predicted_state, action)
		
		rollback_occurred.emit(unvalidated_actions.size())
	else:
		# No rollback needed, just sync
		_predicted_state = _authoritative_state.duplicate(true)

func _find_rollback_point() -> int:
	"""Find the point where prediction diverged from authority"""
	# For now, always rollback if there are unvalidated actions
	# TODO: Implement more sophisticated rollback detection
	return 0 if _pending_validation.size() > 0 else -1

func _get_unvalidated_actions() -> Array[Dictionary]:
	"""Get actions that haven't been validated yet"""
	var unvalidated: Array[Dictionary] = []
	
	for action in _pending_actions:
		if not _validated_actions.has(action.sequence_id):
			unvalidated.append(action)
	
	return unvalidated

func _add_state_to_history(state: Dictionary) -> void:
	"""Add a state to the history buffer"""
	_state_history.append(state.duplicate(true))
	
	# Limit history size
	while _state_history.size() > _max_history_size:
		_state_history.pop_front()

func _get_next_sequence_id() -> int:
	"""Get the next action sequence ID"""
	_action_sequence += 1
	return _action_sequence

# Network event handlers
func _on_network_message_received(sender_id: int, message: Dictionary) -> void:
	"""Handle network messages"""
	# Ensure sender_id is an int (defensive programming)
	var sender_id_int = int(sender_id) if sender_id is String else sender_id
	
	match message.get("type", ""):
		"game_action":
			_handle_game_action(sender_id_int, message)
		"state_sync":
			_handle_state_sync(sender_id_int, message)
		"action_validation":
			_handle_action_validation(sender_id_int, message)

func _handle_game_action(sender_id: int, message: Dictionary) -> void:
	"""Handle game action from another player"""
	var action_type = message.get("action_type", "")
	var action_data = message.get("action_data", {})
	
	# Handle lobby messages (they come wrapped in player_action)
	if action_type == "player_action":
		var inner_type = action_data.get("type", "")
		if inner_type in ["lobby_state", "map_vote", "player_ready", "game_start"]:
			print("[MULTIPLAYER] Lobby message: " + inner_type)
			_handle_lobby_message(inner_type, action_data.get("data", {}))
			return
	
	# Direct lobby messages (fallback)
	if action_type in ["lobby_state", "map_vote", "player_ready", "game_start"]:
		print("[MULTIPLAYER] Lobby message: " + action_type)
		_handle_lobby_message(action_type, action_data)
		return
	
	if action_type == "player_action":
		# This is a player action that needs to be applied
		var action = action_data
		action["peer_id"] = sender_id
		
		# If we're the host, validate and broadcast
		if _is_host:
			var is_valid = _validate_action(action)
			
			if is_valid:
				_apply_authoritative_action(action)
				_broadcast_action_validation(action, true)
			else:
				_broadcast_action_validation(action, false)
		else:
			# As a client, apply the action (assuming host validation)
			_apply_authoritative_action(action)

func _handle_state_sync(sender_id: int, message: Dictionary) -> void:
	"""Handle full state synchronization"""
	if sender_id == 1 or _is_host:  # Only accept from host
		var new_state = message.get("state", {})
		_authoritative_state = new_state
		
		if _prediction_enabled:
			_reconcile_predicted_state()
		
		print("Received state sync from host")
		game_state_updated.emit(_authoritative_state)

func _handle_action_validation(sender_id: int, message: Dictionary) -> void:
	"""Handle action validation from host"""
	if sender_id != 1 and not _is_host:  # Only accept from host
		return
	
	var sequence_id = message.get("sequence_id", -1)
	var is_valid = message.get("is_valid", false)
	var action = message.get("action", {})
	
	if _pending_validation.has(sequence_id):
		if is_valid:
			print("Action validated: seq %d" % sequence_id)
			_validated_actions[sequence_id] = action
		else:
			print("Action rejected: seq %d" % sequence_id)
			# Remove from pending actions
			_pending_actions = _pending_actions.filter(func(a): return a.sequence_id != sequence_id)
		
		_pending_validation.erase(sequence_id)
		action_validated.emit(action, is_valid)
		
		# Reconcile state
		if _prediction_enabled:
			_reconcile_predicted_state()

func _validate_action(action: Dictionary) -> bool:
	"""Validate an action (host only)"""
	# TODO: Implement proper game rule validation
	# For now, just basic checks
	
	if not action.has("type") or not action.has("data"):
		return false
	
	match action.type:
		"unit_move":
			return _validate_unit_move(action.data)
		"unit_attack":
			return _validate_unit_attack(action.data)
		"end_turn":
			return _validate_end_turn(action.data)
		"turn_change":
			return _validate_turn_change(action.data)
		_:
			return true  # Allow unknown actions for now

func _validate_unit_move(data: Dictionary) -> bool:
	"""Validate a unit movement action"""
	# Check required fields
	if not data.has("unit_id") or not data.has("to_position"):
		return false
	
	# TODO: Check if unit exists, can move, destination is valid, etc.
	return true

func _validate_unit_attack(data: Dictionary) -> bool:
	"""Validate a unit attack action"""
	# Check required fields
	if not data.has("attacker_id") or not data.has("target_id"):
		return false
	
	# TODO: Check if units exist, are in range, etc.
	return true

func _validate_end_turn(data: Dictionary) -> bool:
	"""Validate an end turn action"""
	# Check required fields
	if not data.has("player_id"):
		return false
	
	# TODO: Check if it's actually this player's turn
	return true

func _validate_turn_change(data: Dictionary) -> bool:
	"""Validate a turn change action"""
	# Check required fields
	if not data.has("current_player"):
		return false
	
	# TODO: Check if the turn change is valid
	return true

func _broadcast_action_validation(action: Dictionary, is_valid: bool) -> void:
	"""Broadcast action validation result (host only)"""
	if not _is_host:
		return
	
	var validation_message = {
		"type": "action_validation",
		"sequence_id": action.get("sequence_id", -1),
		"is_valid": is_valid,
		"action": action
	}
	
	_network_manager.send_game_action("action_validation", validation_message)

func _handle_game_start(data: Dictionary) -> void:
	"""Handle game start message from host (client-side)"""
	print("[CLIENT] Received game_start message from host")
	print("[CLIENT] Game start data: " + str(data))
	
	# Extract map and settings from host
	var map_path = data.get("map", "")
	var turn_system = data.get("turn_system", TurnSystemBase.TurnSystemType.TRADITIONAL)
	
	if map_path.is_empty():
		print("[CLIENT] ERROR: No map specified in game_start message")
		return
	
	# Update GameSettings with host's selections
	GameSettings.set_selected_map(map_path)
	GameSettings.set_turn_system(turn_system)
	GameSettings.set_game_mode(GameSettings.GameMode.MULTIPLAYER)
	
	print("[CLIENT] Map set to: " + map_path)
	print("[CLIENT] Turn system set to: " + TurnSystemBase.TurnSystemType.keys()[turn_system])
	print("[CLIENT] Loading GameWorld...")
	
	# Load the game scene
	get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")

func _handle_lobby_message(message_type: String, data: Dictionary) -> void:
	"""Handle lobby-related messages"""
	print("[MULTIPLAYER] Lobby message: " + message_type)
	print("[MULTIPLAYER] Looking for lobby in scene tree...")
	
	# Find the collaborative lobby in the scene tree
	var lobby = _find_collaborative_lobby()
	print("[MULTIPLAYER] Lobby found: " + str(lobby != null))
	
	if lobby and lobby.has_method("handle_network_message"):
		print("[MULTIPLAYER] Calling lobby.handle_network_message()")
		lobby.handle_network_message(message_type, data)
	else:
		if not lobby:
			print("[MULTIPLAYER] Warning: No collaborative lobby found to handle message")
		else:
			print("[MULTIPLAYER] Warning: Lobby found but missing handle_network_message method")

func _find_collaborative_lobby() -> Node:
	"""Find the CollaborativeLobby node in the scene tree"""
	var root = get_tree().root
	return _search_for_lobby(root)

func _search_for_lobby(node: Node) -> Node:
	"""Recursively search for CollaborativeLobby"""
	if node.get_script() and node.get_script().resource_path.ends_with("CollaborativeLobby.gd"):
		return node
	
	for child in node.get_children():
		var result = _search_for_lobby(child)
		if result:
			return result
	
	return null

func _on_peer_connected(peer_id: int) -> void:
	"""Handle peer connection"""
	_local_peer_id = _network_manager.get_local_peer_id()
	_is_host = _network_manager.is_host()
	
	print("MultiplayerGameState: Peer " + str(peer_id) + " connected (local: " + str(_local_peer_id) + ", host: " + str(_is_host) + ")")
	
	# If we're the host, send current state to new peer
	if _is_host and peer_id != _local_peer_id:
		_send_state_sync_to_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	"""Handle peer disconnection"""
	print("MultiplayerGameState: Peer %d disconnected" % peer_id)
	
	# Clean up any pending actions from this peer
	_pending_actions = _pending_actions.filter(func(a): return a.get("peer_id", -1) != peer_id)
	
	# Remove from validation tracking
	for seq_id in _pending_validation.keys():
		var action = _pending_validation[seq_id]
		if action.get("peer_id", -1) == peer_id:
			_pending_validation.erase(seq_id)

func _send_state_sync_to_peer(peer_id: int) -> void:
	"""Send full state sync to a specific peer (host only)"""
	if not _is_host:
		return
	
	var sync_message = {
		"type": "state_sync",
		"state": _authoritative_state
	}
	
	# TODO: Send to specific peer (need to extend NetworkManager)
	print("Sending state sync to peer %d" % peer_id)

# Configuration
func set_prediction_enabled(enabled: bool) -> void:
	"""Enable/disable client-side prediction"""
	_prediction_enabled = enabled
	print("Client-side prediction: " + ("enabled" if enabled else "disabled"))

func set_rollback_enabled(enabled: bool) -> void:
	"""Enable/disable rollback networking"""
	_rollback_enabled = enabled
	print("Rollback networking: " + ("enabled" if enabled else "disabled"))

func set_max_history_size(size: int) -> void:
	"""Set maximum state history size"""
	_max_history_size = max(1, size)
	print("Max history size set to: " + str(_max_history_size))

# Debug methods
func get_debug_info() -> Dictionary:
	"""Get debug information about multiplayer state"""
	return {
		"local_peer_id": _local_peer_id,
		"is_host": _is_host,
		"prediction_enabled": _prediction_enabled,
		"rollback_enabled": _rollback_enabled,
		"pending_actions": _pending_actions.size(),
		"pending_validation": _pending_validation.size(),
		"validated_actions": _validated_actions.size(),
		"state_history_size": _state_history.size()
	}
