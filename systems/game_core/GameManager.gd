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
	NETWORK_MULTIPLAYER # Networked play — owned by NetSession, never entered here
}

# NOTE ON NETWORK_MULTIPLAYER: this manager no longer has a networked path. Host/Join run on
# the NetSession autoload (systems/net/), which is server-authoritative and applies resolved
# commands through CommandApplier on every peer. The old route into this enum value went
# through a NetworkHandler that wrapped a Dictionary-based state simulator; that whole layer
# is deleted. The enum member is kept because GameModeManager still names it when answering
# "is this a legacy network session?" — the answer is now always no, and the NetSession-aware
# prefixes in GameModeManager are what the battle UI actually reads.

# Core game state
var _game_mode: GameMode = GameMode.SINGLE_PLAYER
var _is_game_active: bool = false
var _current_turn_player: int = -1
var _players: Dictionary = {}  # player_id -> player_data
var _game_settings: Dictionary = {}

# System references
var _turn_system: Node = null
var _player_manager: Node = null

func _ready() -> void:
	name = "GameManager"

	# Get existing systems
	_player_manager = get_node_or_null("/root/PlayerManager")
	_turn_system = TurnSystemManager.get_active_turn_system() if TurnSystemManager else null

# Public API - Game Management
func start_single_player_game(settings: Dictionary = {}) -> bool:
	"""Start a single-player game"""
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

func end_game(winner_id: int = -1) -> void:
	"""End the current game"""
	_is_game_active = false
	game_ended.emit(winner_id)

# Action Processing
func submit_player_action(action_type: String, action_data: Dictionary, player_id: int = -1) -> bool:
	"""Submit a player action for processing"""
	if not _is_game_active:
		return false

	# Use current player if not specified
	if player_id == -1:
		player_id = _current_turn_player

	# Validate action based on game mode
	if not _validate_action(action_type, action_data, player_id):
		return false

	var action = {
		"type": action_type,
		"data": action_data,
		"player_id": player_id,
		"timestamp": Time.get_ticks_msec()
	}

	# Process based on game mode. NETWORK_MULTIPLAYER is unreachable here (NetSession owns
	# networked play), so the only live path is the local one.
	if _game_mode == GameMode.SINGLE_PLAYER or _game_mode == GameMode.LOCAL_MULTIPLAYER:
		return _process_local_action(action)

	return false

func _validate_action(action_type: String, action_data: Dictionary, player_id: int) -> bool:
	"""Validate if an action is allowed"""
	# Check if player exists
	if not _players.has(player_id):
		return false

	# Check if it's the player's turn
	if player_id != _current_turn_player:
		return false

	# Validate with turn system
	if _turn_system and _turn_system.has_method("validate_action"):
		return _turn_system.validate_action(action_type, action_data, player_id)

	return true

func _process_local_action(action: Dictionary) -> bool:
	"""Process action in single-player or local multiplayer"""
	# Apply action to game state
	_apply_action_to_game_state(action)

	# Emit for UI updates
	player_action_processed.emit(action)

	# Check for turn advancement
	_check_turn_advancement(action)

	return true

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

func _handle_unit_move(data: Dictionary) -> void:
	"""Handle unit movement action"""
	var unit_id = data.get("unit_id", "")
	var from_pos = data.get("from_position", Vector3.ZERO)
	var to_pos = data.get("to_position", Vector3.ZERO)

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

	# Forward to combat system
	# TODO: Implement combat system integration

func _handle_end_turn(data: Dictionary) -> void:
	"""Handle end turn action"""
	var player_id = data.get("player_id", -1)

	# Advance to next player
	_advance_turn()

func _handle_unit_select(data: Dictionary) -> void:
	"""Handle unit selection action"""
	var unit_id = data.get("unit_id", "")
	var player_id = data.get("player_id", -1)

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

	# Networked turn sync is NOT done here: NetSession bridges the live turn system's
	# turn_started straight to its own turn slot (see NetSession._activate_turn_bridge).
	turn_changed.emit(_current_turn_player)

func _check_turn_advancement(action: Dictionary) -> void:
	"""Check if the turn should advance after an action"""
	# This depends on the turn system and action type
	if action.type == "end_turn":
		_advance_turn()
	elif _turn_system and _turn_system.has_method("should_advance_turn"):
		if _turn_system.should_advance_turn(action):
			_advance_turn()

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

	return player_id == _current_turn_player

# Debug and Status
func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	return "[SINGLE] "

func get_game_status() -> Dictionary:
	"""Get comprehensive game status"""
	return {
		"game_mode": GameMode.keys()[_game_mode],
		"is_active": _is_game_active,
		"current_player": _current_turn_player,
		"players": _players,
		"settings": _game_settings
	}
