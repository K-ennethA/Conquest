extends Node

# High-level manager that coordinates between single-player and multiplayer modes
# Provides a simple interface for the entire game

signal game_mode_changed(new_mode: GameManager.GameMode)
signal game_started(mode: GameManager.GameMode)
signal game_ended(winner_id: int)

var _game_manager: GameManager

func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	# Networked play runs on NetSession, so the local SLOT is what distinguishes host from
	# client now (slot 0 = host). Outside a live networked match this is single-player.
	if not _netsession_is_live():
		return "[SINGLE] "
	var local_id := get_local_player_id()
	if local_id == 0:
		return "[HOST] "
	if local_id == 1:
		return "[CLIENT] "
	return "[PLAYER" + str(local_id) + "] "

func _ready() -> void:
	name = "GameModeManager"

	# Create game manager
	_game_manager = GameManager.new()
	if not _game_manager:
		return

	add_child(_game_manager)

	# Connect signals
	_game_manager.game_started.connect(_on_game_started)
	_game_manager.game_ended.connect(_on_game_ended)
	_game_manager.player_action_processed.connect(_on_player_action_processed)
	_game_manager.turn_changed.connect(_on_turn_changed)

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

# Hosting and joining live on NetSession (systems/net/NetSession.gd) — see
# menus/NetworkMultiplayerSetup.gd. This manager used to own a parallel network path built on
# a NetworkHandler wrapping a Dictionary-based state simulator; that layer is deleted, and the
# only network-facing job left here is answering ownership/turn queries from NetSession (see
# the prefixes below) plus the lobby's legacy submit_action envelope.

func end_current_game() -> void:
	"""End the current game"""
	if not _game_manager:
		return

	_game_manager.end_game()

# --- NetSession (consolidated transport) awareness ---------------------------
# Host/Join run on NetSession. On that path `_game_manager` never started a session, so the
# queries below -- which the whole battle UI reads through (UnitActionsPanel's ownership and
# turn gates, PlayerManager.can_current_player_select_unit, UnitVisualManager's "your units"
# tint) -- would answer as if this were single-player: local player 0 on BOTH machines, and
# never anyone's turn. That is what made the client unable to touch its own units.
#
# These are additive prefixes: when NetSession is not a live networked match every one of
# them falls through to exactly the previous behaviour, so solo / hotseat play is untouched.

## True when NetSession is the live, connected, multi-participant session for this process
## AND it has seated us in a slot.
func _netsession_is_live() -> bool:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return false
	if not NetSession.has_method("is_networked_match") or not NetSession.is_networked_match():
		return false
	return int(NetSession.local_slot()) >= 0

# Action submission - unified interface
func submit_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit a player action (works for all game modes)"""
	# NetSession path: this manager's GameManager session was never started, so its
	# submit_player_action refuses everything (`_is_game_active` is false) -- which would
	# dead-end the callers that use the return value purely as a permission check (e.g.
	# UnitActionsPanel's Move button). Real state changes on this path do NOT travel here:
	# they are NetProtocol commands submitted to NetSession and applied by the CommandApplier
	# on every peer. So report the local permission as granted and let the caller proceed.
	if _netsession_is_live():
		return true
	if not _game_manager:
		return false
	return _game_manager.submit_player_action(action_type, action_data)

# Status queries
func get_current_game_mode() -> GameManager.GameMode:
	"""Get current game mode"""
	if not _game_manager:
		return GameManager.GameMode.SINGLE_PLAYER
	if not _game_manager.has_method("get_game_mode"):
		return GameManager.GameMode.SINGLE_PLAYER
	return _game_manager.get_game_mode()

func is_game_active() -> bool:
	"""Check if a game is currently active"""
	if not _game_manager:
		return false
	return _game_manager.is_game_active()

func is_my_turn() -> bool:
	"""Check if it's the local player's turn"""
	# NetSession drives its turn slot off the ACTIVE turn system through the command seam's
	# turn bridge, so this returns the same verdict the server-side validator will give an
	# intent submitted right now -- the UI and the authority agree by construction.
	if _netsession_is_live():
		return NetSession.is_my_turn()

	if not _game_manager:
		return false

	return _game_manager.is_local_player_turn()

func can_i_act() -> bool:
	"""Check if the local player can currently act"""
	if not _game_manager:
		return false

	var current_player = _game_manager.get_current_player_id()
	return _game_manager.can_player_act(current_player)

func get_local_player_id() -> int:
	"""Get the local player ID for this client"""
	# NetSession path: the roster slot IS the player id (host = slot 0 = player 0, joiner =
	# slot 1 = player 1), which is the alignment the turn bridge and the battle's player
	# registration both assume.
	if _netsession_is_live():
		return int(NetSession.local_slot())

	# For single player and local multiplayer, always return 0 (first player)
	return 0

func is_local_player(player_id: int) -> bool:
	"""Check if the given player ID represents the local player"""
	return player_id == get_local_player_id()

func get_game_status() -> Dictionary:
	"""Get comprehensive game status"""
	if not _game_manager:
		return {
			"error": "GameManager not available",
			"game_mode": "UNKNOWN",
			"is_active": false
		}

	# No network keys are added here any more: connection state belongs to NetSession, and
	# every caller of this dictionary already reads the network keys with a default (they
	# were absent on the NetSession path long before this stack was removed).
	return _game_manager.get_game_status()

# Signal handlers
func _on_game_started(mode: GameManager.GameMode, players: Array) -> void:
	"""Handle game started"""
	game_mode_changed.emit(mode)
	game_started.emit(mode)

func _on_game_ended(winner_id: int) -> void:
	"""Handle game ended"""
	game_ended.emit(winner_id)

func _on_player_action_processed(action: Dictionary) -> void:
	"""Handle player action processed"""
	# This can be used to update UI or trigger other systems
	pass

func _on_turn_changed(current_player_id: int) -> void:
	"""Handle turn change"""
	pass

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
		return false

	var mode = get_current_game_mode()
	return mode == GameManager.GameMode.NETWORK_MULTIPLAYER

func is_local_player_turn() -> bool:
	"""Check if it's local player's turn (for compatibility)"""
	if not _game_manager:
		return false
	return is_my_turn()

func submit_game_action(action_type: String, action_data: Dictionary) -> bool:
	"""Submit game action (for compatibility)"""
	if not _game_manager:
		return false
	return submit_action(action_type, action_data)
