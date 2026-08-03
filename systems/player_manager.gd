extends Node

# PlayerManager Singleton
# Central management for all players, turns, and team coordination

signal player_registered(player: Player)
signal player_turn_started(player: Player)
signal player_turn_ended(player: Player)
signal game_state_changed(new_state: GameState)
signal player_eliminated(player: Player)

enum GameState {
	SETUP,        # Game is being set up
	IN_PROGRESS,  # Game is actively being played
	PAUSED,       # Game is paused
	FINISHED      # Game has ended
}

var players: Array[Player] = []
var current_player_index: int = 0
var current_game_state: GameState = GameState.SETUP
var turn_number: int = 0

## Fixed slot for the NEUTRAL faction (jungle-camp style). The two combatants are
## player 0 (the human squad) and player 1 (the enemy wave); the neutral camp lives
## at index 2 so it never collides with either. See [method ensure_neutral_player].
const NEUTRAL_PLAYER_INDEX: int = 2
## Distinct grey/gold so a neutral camp reads apart from the blue/red combatants (its
## units also fall through to PlayerMaterials.NEUTRAL grey via Unit.player_assignment).
const NEUTRAL_TEAM_COLOR: Color = Color(0.78, 0.68, 0.32, 1.0)

# Default team colors
var default_team_colors: Array[Color] = [
	Color(0.2, 0.4, 0.8, 1.0),  # Blue - Player 1
	Color(0.8, 0.2, 0.2, 1.0),  # Red - Player 2
	Color(0.2, 0.8, 0.2, 1.0),  # Green - Player 3
	Color(0.8, 0.8, 0.2, 1.0),  # Yellow - Player 4
]

func _ready() -> void:
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_action_completed.connect(_on_unit_action_completed)

	# Connect to GameModeManager for multiplayer turn synchronization
	if GameModeManager:
		GameModeManager.game_started.connect(_on_game_mode_manager_game_started)
		GameModeManager.game_ended.connect(_on_game_mode_manager_game_ended)

		# Try to connect to GameManager immediately
		_try_connect_to_game_manager()

		# Also try again after a short delay in case GameManager isn't ready yet
		await get_tree().create_timer(0.1).timeout
		_try_connect_to_game_manager()

func _try_connect_to_game_manager() -> void:
	"""Try to connect to GameManager's turn_changed signal"""
	if not GameModeManager:
		return

	var game_manager = GameModeManager._game_manager
	if game_manager:
		# Check if already connected to avoid duplicate connections
		if not game_manager.turn_changed.is_connected(_on_network_turn_changed):
			var connection_result = game_manager.turn_changed.connect(_on_network_turn_changed)

# Player registration and setup
func register_player(player_name: String = "") -> Player:
	"""Register a new player and assign team color"""
	var player_id = players.size()
	var name = player_name if player_name != "" else "Player " + str(player_id + 1)

	var player = Player.new(player_id, name)

	# Assign team color
	if player_id < default_team_colors.size():
		player.set_team_color(default_team_colors[player_id])
	else:
		# Generate random color for additional players
		player.set_team_color(Color(randf(), randf(), randf(), 1.0))

	players.append(player)

	# Connect to player signals
	player.player_state_changed.connect(_on_player_state_changed)
	player.turn_completed.connect(_on_player_turn_completed)
	player.unit_removed.connect(_on_player_unit_removed)

	player_registered.emit(player)

	return player

func setup_default_players() -> void:
	"""Set up default 2-player game"""
	if players.size() > 0:
		return

	var player1 = register_player("Player 1")
	var player2 = register_player("Player 2")

## Register (or return) the NEUTRAL faction at [constant NEUTRAL_PLAYER_INDEX] and
## stamp it is_ai + is_neutral with a distinct grey/gold colour. Idempotent -- safe
## to call every round, and safe to call before OR after the combatants are
## registered: it first fills any missing lower slots so the neutral always lands at
## its fixed index. Because the players array is then non-empty,
## [method setup_default_players] no-ops, and the single-player AI-marking pass in
## GameWorldManager._setup_players only re-asserts is_ai=true -- neither ever clears
## is_neutral or turns this player human. Returns the neutral [Player].
func ensure_neutral_player() -> Player:
	# Fill the combatant slots (0, 1) first so the neutral takes index 2, not 0.
	while players.size() < NEUTRAL_PLAYER_INDEX:
		register_player()
	var neutral: Player
	if players.size() > NEUTRAL_PLAYER_INDEX:
		neutral = players[NEUTRAL_PLAYER_INDEX]
	else:
		neutral = register_player("Neutral")
	neutral.is_ai = true
	neutral.is_neutral = true
	neutral.set_team_color(NEUTRAL_TEAM_COLOR)
	return neutral

# Unit assignment
func assign_unit_to_player(unit: Unit, player_id: int) -> bool:
	"""Assign a unit to a specific player"""
	if player_id < 0 or player_id >= players.size():
		return false

	var player = players[player_id]
	player.add_unit(unit)

	return true

func assign_units_by_parent() -> void:
	"""Auto-assign units based on their parent node names"""
	var scene_root = get_tree().current_scene

	if not scene_root:
		return

	# Look for Player1 and Player2 nodes
	for i in range(players.size()):
		var player_node_name = "Map/Player" + str(i + 1)
		var player_node = scene_root.get_node_or_null(player_node_name)

		if player_node and is_instance_valid(player_node):
			for child in player_node.get_children():
				if child is Unit and is_instance_valid(child):
					assign_unit_to_player(child, i)

# Game state management
func start_game() -> void:
	"""Start the game with the first player"""
	if players.is_empty():
		return

	if current_game_state != GameState.SETUP:
		return

	current_game_state = GameState.IN_PROGRESS
	turn_number = 1
	current_player_index = 0

	# Don't start player turn here - let the turn system handle it
	# The TurnSystemManager will activate a turn system when game state changes

	game_state_changed.emit(current_game_state)

func reset_for_new_game() -> void:
	"""Reset per-session state so a fresh game can be set up in the same app run.

	Autoloads survive scene changes, so without this a SECOND game keeps stale
	players (with freed Unit refs in owned_units) and, critically, leaves
	current_game_state != SETUP -- which makes start_game() early-return and never
	re-emit game_state_changed(IN_PROGRESS), so TurnSystemManager never activates a
	turn system for the new session. Clearing players discards stale owned_units;
	_setup_players recreates players when the array is empty."""
	players.clear()
	current_player_index = 0
	turn_number = 0
	current_game_state = GameState.SETUP

func end_game(winner: Player = null) -> void:
	"""End the game"""
	current_game_state = GameState.FINISHED

	# Set all players to waiting state
	for player in players:
		if player.current_state != Player.PlayerState.ELIMINATED:
			player.set_state(Player.PlayerState.WAITING)

	game_state_changed.emit(current_game_state)

# Turn management
func _start_player_turn(player: Player) -> void:
	"""Start a specific player's turn"""
	# Set all other players to waiting
	for p in players:
		if p != player and p.current_state != Player.PlayerState.ELIMINATED:
			p.set_state(Player.PlayerState.WAITING)

	# Activate current player
	player.set_state(Player.PlayerState.ACTIVE)

	player_turn_started.emit(player)

func end_current_player_turn() -> void:
	"""End the current player's turn and advance to next player"""
	if current_game_state != GameState.IN_PROGRESS:
		return

	var current_player = get_current_player()
	if not current_player:
		return

	current_player.set_state(Player.PlayerState.WAITING)
	player_turn_ended.emit(current_player)

	# Advance to next player
	_advance_to_next_player()

func _advance_to_next_player() -> void:
	"""Advance to the next active player"""
	var starting_index = current_player_index

	# Find next non-eliminated player
	while true:
		current_player_index = (current_player_index + 1) % players.size()

		# If we've completed a full round, increment turn number
		if current_player_index == 0:
			turn_number += 1

		var next_player = players[current_player_index]

		# Check if this player can play
		if next_player.current_state != Player.PlayerState.ELIMINATED:
			_start_player_turn(next_player)
			break

		# Safety check to prevent infinite loop
		if current_player_index == starting_index:
			end_game()
			break

# Player queries
func get_current_player() -> Player:
	"""Get the currently active player"""
	if current_player_index >= 0 and current_player_index < players.size():
		return players[current_player_index]
	return null

func get_current_player_index() -> int:
	"""Get the current player index"""
	return current_player_index

func get_player_by_id(player_id: int) -> Player:
	"""Get player by ID"""
	if player_id >= 0 and player_id < players.size():
		return players[player_id]
	return null

func get_player_count() -> int:
	"""Get total number of players"""
	return players.size()

func get_active_player_count() -> int:
	"""Get number of non-eliminated players"""
	var count = 0
	for player in players:
		if player.current_state != Player.PlayerState.ELIMINATED:
			count += 1
	return count

func get_player_owning_unit(unit: Unit) -> Player:
	"""Find which player owns a specific unit"""
	for player in players:
		if player.owns_unit(unit):
			return player
	return null

# Validation methods
func can_player_select_unit(player: Player, unit: Unit) -> bool:
	"""Check if a player can select a specific unit"""
	if not player or not unit:
		return false

	if current_game_state != GameState.IN_PROGRESS:
		return false

	return player.can_select_unit(unit)

func can_current_player_select_unit(unit: Unit) -> bool:
	"""Check if current player can select a unit"""
	var current_player = get_current_player()

	if not current_player:
		return false

	# In multiplayer mode, check if the unit belongs to the local player
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		var local_player_id = GameModeManager.get_local_player_id()
		var unit_owner = get_player_owning_unit(unit)

		if not unit_owner:
			return false

		if unit_owner.player_id != local_player_id:
			return false

	# Single-player: the human (player 0) must never select or command AI-owned
	# units -- those act only through BotTurnDriver. Selection below keys off the
	# *current* player, so during the AI's OWN turn the AI is the current player and
	# its units would pass the ownership check, letting the human drive the enemy.
	# Reject any AI-owned unit outright. (Multiplayer is already gated by local-player
	# id above; local hotseat has no AI players, so this is a no-op there.)
	if GameSettings and GameSettings.game_mode == GameSettings.GameMode.SINGLE_PLAYER:
		var ai_owner = get_player_owning_unit(unit)
		if ai_owner != null and ai_owner.is_ai:
			return false

	var can_select = can_player_select_unit(current_player, unit)
	return can_select

func validate_unit_action(unit: Unit) -> bool:
	"""Validate if a unit can perform an action"""
	var owner = get_player_owning_unit(unit)
	if not owner:
		return false

	return owner.can_control_unit(unit)

# Event handlers
func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection validation.

	Selection == inspection: any living unit may be selected (commanding is gated
	separately in UnitActionsPanel). We no longer force-deselect units the current
	player cannot command -- doing so cancelled read-only inspection of enemy units.
	Log-only now."""
	pass

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	var owner = get_player_owning_unit(unit)
	if owner:
		owner.mark_unit_acted(unit)

func _on_network_turn_changed(current_player_id: int) -> void:
	"""Handle turn changes from network multiplayer"""
	# Update local player manager state
	if current_player_id >= 0 and current_player_id < players.size():
		current_player_index = current_player_id

		# Update player states
		for i in range(players.size()):
			var player = players[i]
			var old_state = player.current_state
			if i == current_player_id:
				player.set_state(Player.PlayerState.ACTIVE)
			else:
				if player.current_state != Player.PlayerState.ELIMINATED:
					player.set_state(Player.PlayerState.WAITING)

		# Emit local signals for UI updates
		var current_player = get_current_player()
		if current_player:
			player_turn_started.emit(current_player)

func _on_game_mode_manager_game_started(mode: GameManager.GameMode) -> void:
	"""Handle game started from GameModeManager"""
	pass

func _on_game_mode_manager_game_ended(winner_id: int) -> void:
	"""Handle game ended from GameModeManager"""
	pass

func _on_player_state_changed(player: Player, old_state: Player.PlayerState, new_state: Player.PlayerState) -> void:
	"""Handle player state changes"""
	pass

func _on_player_turn_completed(player: Player) -> void:
	"""Handle player turn completion"""
	pass

func _on_player_unit_removed(player: Player, unit: Unit) -> void:
	"""Handle unit removal from player"""
	# Check if player should be eliminated
	if not player.has_units_remaining() and player.current_state != Player.PlayerState.ELIMINATED:
		player.set_state(Player.PlayerState.ELIMINATED)
		player_eliminated.emit(player)

		# Check for game end condition
		if get_active_player_count() <= 1:
			# ARENA owns round/run end (ArenaController.notify_round_ended, driven off this
			# same elimination via GameWorldManager). The normal game-over teardown here
			# deactivates the turn system mid-frame and fights that flow (it crashed on the
			# final-enemy kill), so skip it entirely during an active run.
			var arena_ctrl = get_node_or_null("/root/ArenaController")
			if arena_ctrl != null and arena_ctrl.has_method("is_active") and arena_ctrl.is_active():
				return
			var winner = null
			for p in players:
				if p.current_state != Player.PlayerState.ELIMINATED:
					winner = p
					break
			end_game(winner)

# Debug and utility
func get_game_state_info() -> Dictionary:
	"""Get current game state information"""
	var current_player = get_current_player()
	return {
		"game_state": GameState.keys()[current_game_state],
		"turn_number": turn_number,
		"current_player": current_player.get_display_name() if current_player else "None",
		"total_players": players.size(),
		"active_players": get_active_player_count(),
		"players": players.map(func(p): return p.get_debug_info())
	}

func print_game_status() -> void:
	"""Print current game status for debugging"""
	var info = get_game_state_info()

	for player in players:
		var p_info = player.get_debug_info()
