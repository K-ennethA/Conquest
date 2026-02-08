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
	
	print(_get_log_prefix() + "PlayerManager: Initializing...")
	
	# Connect to GameModeManager for multiplayer turn synchronization
	if GameModeManager:
		print(_get_log_prefix() + "PlayerManager: GameModeManager found")
		GameModeManager.game_started.connect(_on_game_mode_manager_game_started)
		GameModeManager.game_ended.connect(_on_game_mode_manager_game_ended)
		
		# Try to connect to GameManager immediately
		_try_connect_to_game_manager()
		
		# Also try again after a short delay in case GameManager isn't ready yet
		await get_tree().create_timer(0.1).timeout
		_try_connect_to_game_manager()
	else:
		print(_get_log_prefix() + "PlayerManager: WARNING - GameModeManager not found")
	
	print(_get_log_prefix() + "PlayerManager initialized")

func _try_connect_to_game_manager() -> void:
	"""Try to connect to GameManager's turn_changed signal"""
	if not GameModeManager:
		print(_get_log_prefix() + "PlayerManager: GameModeManager is null")
		return
	
	var game_manager = GameModeManager._game_manager
	if game_manager:
		print(_get_log_prefix() + "PlayerManager: GameManager found - " + str(game_manager))
		
		# Check if already connected to avoid duplicate connections
		if not game_manager.turn_changed.is_connected(_on_network_turn_changed):
			print(_get_log_prefix() + "PlayerManager: Connecting to GameManager.turn_changed signal")
			var connection_result = game_manager.turn_changed.connect(_on_network_turn_changed)
			if connection_result == OK:
				print(_get_log_prefix() + "PlayerManager: Successfully connected to GameManager.turn_changed")
			else:
				print(_get_log_prefix() + "PlayerManager: Failed to connect to GameManager.turn_changed - error: " + str(connection_result))
		else:
			print(_get_log_prefix() + "PlayerManager: Already connected to GameManager.turn_changed")
	else:
		print(_get_log_prefix() + "PlayerManager: WARNING - GameManager not found in GameModeManager")
		print(_get_log_prefix() + "PlayerManager: GameModeManager._game_manager is: " + str(GameModeManager._game_manager))

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
	
	print("Registered player: " + player.get_display_name())
	return player

func setup_default_players() -> void:
	"""Set up default 2-player game"""
	if players.size() > 0:
		print("Players already set up")
		return
	
	var player1 = register_player("Player 1")
	var player2 = register_player("Player 2")
	
	print("Default players set up: " + str(players.size()) + " players")

# Unit assignment
func assign_unit_to_player(unit: Unit, player_id: int) -> bool:
	"""Assign a unit to a specific player"""
	if player_id < 0 or player_id >= players.size():
		print("Invalid player ID: " + str(player_id))
		return false
	
	var player = players[player_id]
	player.add_unit(unit)
	
	print("Assigned unit " + unit.name + " to " + player.get_display_name())
	return true

func assign_units_by_parent() -> void:
	"""Auto-assign units based on their parent node names"""
	var scene_root = get_tree().current_scene
	
	if not scene_root:
		print("ERROR: No current scene found")
		return
	
	# Look for Player1 and Player2 nodes
	for i in range(players.size()):
		var player_node_name = "Map/Player" + str(i + 1)
		var player_node = scene_root.get_node_or_null(player_node_name)
		
		if player_node and is_instance_valid(player_node):
			print("Found player node: " + player_node_name)
			for child in player_node.get_children():
				if child is Unit and is_instance_valid(child):
					assign_unit_to_player(child, i)
		else:
			print("Player node not found or invalid: " + player_node_name)

# Game state management
func start_game() -> void:
	"""Start the game with the first player"""
	if players.is_empty():
		print("Cannot start game: No players registered")
		return
	
	if current_game_state != GameState.SETUP:
		print("Game already started")
		return
	
	current_game_state = GameState.IN_PROGRESS
	turn_number = 1
	current_player_index = 0
	
	# Don't start player turn here - let the turn system handle it
	# The TurnSystemManager will activate a turn system when game state changes
	
	game_state_changed.emit(current_game_state)
	print("Game started! Turn " + str(turn_number))

func end_game(winner: Player = null) -> void:
	"""End the game"""
	current_game_state = GameState.FINISHED
	
	# Set all players to waiting state
	for player in players:
		if player.current_state != Player.PlayerState.ELIMINATED:
			player.set_state(Player.PlayerState.WAITING)
	
	game_state_changed.emit(current_game_state)
	
	if winner:
		print("Game ended! Winner: " + winner.get_display_name())
	else:
		print("Game ended!")

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
	print(player.get_display_name() + "'s turn started")

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
			print("Turn " + str(turn_number) + " begins")
		
		var next_player = players[current_player_index]
		
		# Check if this player can play
		if next_player.current_state != Player.PlayerState.ELIMINATED:
			_start_player_turn(next_player)
			break
		
		# Safety check to prevent infinite loop
		if current_player_index == starting_index:
			print("All players eliminated - ending game")
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
	print("DEBUG: can_current_player_select_unit - current_player: " + (current_player.player_name if current_player else "None"))
	print("DEBUG: current_player_index: " + str(current_player_index))
	print("DEBUG: players.size(): " + str(players.size()))
	print("DEBUG: current_game_state: " + GameState.keys()[current_game_state])
	
	if not current_player:
		print("DEBUG: No current player found")
		return false
	
	# In multiplayer mode, check if the unit belongs to the local player
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		var local_player_id = GameModeManager.get_local_player_id()
		var unit_owner = get_player_owning_unit(unit)
		
		print("DEBUG: Multiplayer mode - local_player_id: " + str(local_player_id))
		print("DEBUG: Unit owner: " + (unit_owner.player_name if unit_owner else "None"))
		print("DEBUG: Unit owner ID: " + str(unit_owner.player_id if unit_owner else -1))
		
		if not unit_owner:
			print("DEBUG: Unit has no owner")
			return false
		
		if unit_owner.player_id != local_player_id:
			print("DEBUG: Unit belongs to different player (owner: " + str(unit_owner.player_id) + ", local: " + str(local_player_id) + ")")
			return false
		
		print("DEBUG: Unit belongs to local player - selection allowed")
	
	var can_select = can_player_select_unit(current_player, unit)
	print("DEBUG: can_player_select_unit result: " + str(can_select))
	return can_select

func validate_unit_action(unit: Unit) -> bool:
	"""Validate if a unit can perform an action"""
	var owner = get_player_owning_unit(unit)
	if not owner:
		return false
	
	return owner.can_control_unit(unit)

# Event handlers
func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection validation"""
	if not can_current_player_select_unit(unit):
		print("Cannot select unit: not owned by current player")
		GameEvents.unit_deselected.emit(unit)
		return

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	var owner = get_player_owning_unit(unit)
	if owner:
		owner.mark_unit_acted(unit)

func _on_network_turn_changed(current_player_id: int) -> void:
	"""Handle turn changes from network multiplayer"""
	print(_get_log_prefix() + "=== CLIENT TURN SYNC DEBUG ===")
	print(_get_log_prefix() + "PlayerManager: _on_network_turn_changed called!")
	print(_get_log_prefix() + "Network turn change received: player %d" % current_player_id)
	print(_get_log_prefix() + "Current local state before sync:")
	print(_get_log_prefix() + "  current_player_index: %d" % current_player_index)
	print(_get_log_prefix() + "  players.size(): %d" % players.size())
	print(_get_log_prefix() + "  GameModeManager exists: %s" % str(GameModeManager != null))
	print(_get_log_prefix() + "  Is multiplayer active: %s" % str(GameModeManager.is_multiplayer_active() if GameModeManager else false))
	
	# Update local player manager state
	if current_player_id >= 0 and current_player_id < players.size():
		print(_get_log_prefix() + "Valid player ID - updating local state")
		current_player_index = current_player_id
		
		# Update player states
		for i in range(players.size()):
			var player = players[i]
			var old_state = player.current_state
			if i == current_player_id:
				player.set_state(Player.PlayerState.ACTIVE)
				print(_get_log_prefix() + "  Set Player %d (%s) to ACTIVE (was %s)" % [i, player.player_name, Player.PlayerState.keys()[old_state]])
			else:
				if player.current_state != Player.PlayerState.ELIMINATED:
					player.set_state(Player.PlayerState.WAITING)
					print(_get_log_prefix() + "  Set Player %d (%s) to WAITING (was %s)" % [i, player.player_name, Player.PlayerState.keys()[old_state]])
		
		# Emit local signals for UI updates
		var current_player = get_current_player()
		if current_player:
			print(_get_log_prefix() + "Emitting player_turn_started for: %s" % current_player.get_display_name())
			player_turn_started.emit(current_player)
			print(_get_log_prefix() + "Turn synchronized: %s is now active" % current_player.get_display_name())
		else:
			print(_get_log_prefix() + "ERROR: Could not get current player after sync")
	else:
		print(_get_log_prefix() + "ERROR: Invalid player ID %d (valid range: 0-%d)" % [current_player_id, players.size() - 1])
	
	print(_get_log_prefix() + "=== END CLIENT TURN SYNC DEBUG ===")

func _on_game_mode_manager_game_started(mode: GameManager.GameMode) -> void:
	"""Handle game started from GameModeManager"""
	print("Game started via GameModeManager in mode: %s" % GameManager.GameMode.keys()[mode])

func _on_game_mode_manager_game_ended(winner_id: int) -> void:
	"""Handle game ended from GameModeManager"""
	print("Game ended via GameModeManager, winner: %d" % winner_id)

func _on_player_state_changed(player: Player, old_state: Player.PlayerState, new_state: Player.PlayerState) -> void:
	"""Handle player state changes"""
	print(player.get_display_name() + " state: " + Player.PlayerState.keys()[old_state] + " -> " + Player.PlayerState.keys()[new_state])

func _on_player_turn_completed(player: Player) -> void:
	"""Handle player turn completion"""
	print(player.get_display_name() + " completed their turn")

func _on_player_unit_removed(player: Player, unit: Unit) -> void:
	"""Handle unit removal from player"""
	# Check if player should be eliminated
	if not player.has_units_remaining() and player.current_state != Player.PlayerState.ELIMINATED:
		player.set_state(Player.PlayerState.ELIMINATED)
		player_eliminated.emit(player)
		
		# Check for game end condition
		if get_active_player_count() <= 1:
			var winner = null
			for p in players:
				if p.current_state != Player.PlayerState.ELIMINATED:
					winner = p
					break
			end_game(winner)

# Debug and utility
func _get_log_prefix() -> String:
	"""Get a log prefix to identify host vs client"""
	var prefix = "[UNKNOWN] "
	
	if GameModeManager and GameModeManager.is_multiplayer_active():
		var local_player_id = GameModeManager.get_local_player_id()
		if local_player_id == 0:
			prefix = "[HOST] "
		elif local_player_id == 1:
			prefix = "[CLIENT] "
		else:
			prefix = "[PLAYER" + str(local_player_id) + "] "
	else:
		prefix = "[SINGLE] "
	
	return prefix

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
	print("=== Game Status ===")
	var info = get_game_state_info()
	print("State: " + info.game_state)
	print("Turn: " + str(info.turn_number))
	print("Current Player: " + info.current_player)
	print("Active Players: " + str(info.active_players) + "/" + str(info.total_players))
	
	for player in players:
		var p_info = player.get_debug_info()
		print("  " + p_info.player_name + ": " + p_info.state + " (" + str(p_info.units_owned) + " units)")
