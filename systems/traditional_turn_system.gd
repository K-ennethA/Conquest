extends TurnSystemBase

class_name TraditionalTurnSystem

# Traditional Turn System Implementation
# Player-based turns where all units of a player can act before switching to next player

var current_player: Player = null
var units_acted_this_turn: Array[Unit] = []
var turn_completed_manually: bool = false
var players_had_turn_this_round: Array[Player] = []  # Track which players have had a turn this round
var just_started: bool = false  # Flag to prevent immediate turn completion on startup
var _auto_advance_pending: bool = false  # Guard so an auto-end is deferred at most once per turn

func _init() -> void:
	super._init()
	system_type = TurnSystemType.TRADITIONAL
	system_name = "Traditional Turn System"

# Abstract method implementations
func start_turn_system() -> void:
	"""Initialize and start the traditional turn system"""
	if registered_players.is_empty():
		return

	is_active = true
	current_turn = 1
	is_turn_in_progress = false
	units_acted_this_turn.clear()
	turn_completed_manually = false
	players_had_turn_this_round.clear()
	just_started = true  # Prevent immediate turn completion

	# Initialize BattleEffectsManager for this battle
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()

	# Start with first player
	current_player = registered_players[0]
	_start_player_turn(current_player)

func end_turn_system() -> void:
	"""Clean up and end the traditional turn system"""
	if current_player and is_turn_in_progress:
		_end_player_turn(current_player)

	# End battle in BattleEffectsManager (clears all battle-scoped effects)
	if BattleEffectsManager:
		BattleEffectsManager.end_battle()

	is_active = false
	is_turn_in_progress = false
	current_player = null
	units_acted_this_turn.clear()
	turn_completed_manually = false
	players_had_turn_this_round.clear()
	just_started = false

func advance_turn() -> void:
	"""Advance to the next player's turn"""
	if not is_active or not current_player:
		return

	# Don't end the current turn yet - just advance to next player
	# The next player's turn start will handle ending the previous turn
	_advance_to_next_player()

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	if not is_active or not current_player or not is_turn_in_progress:
		return false

	# Unit must belong to current player
	if not current_player.owns_unit(unit):
		return false

	# Unit must not have acted this turn (once they act, they can't act again)
	if unit in units_acted_this_turn:
		return false

	# A stunned unit forfeits this turn entirely. Checked here rather than by
	# dropping it from the player's unit list so it still gets ticked by
	# _start_player_turn's _tick_all_units_turn_start -- which is what expires the
	# stun. _check_turn_completion() reads can_unit_act() too, so a side whose only
	# remaining unit is stunned still completes its turn instead of stalling.
	if is_turn_skipped(unit):
		return false

	# A CONTROLLED unit is barred from the player exactly like a stun -- it does not get
	# to act of its own accord. The turn system force-drives it against its own side
	# instead (see _drive_controlled_units), scheduled deferred at turn start.
	if is_turn_forced_control(unit):
		return false

	# Unit must be able to act (not eliminated, has actions, etc.)
	if unit.has_method("can_act"):
		return unit.can_act()

	return true

func get_current_active_player() -> Player:
	"""Get the currently active player"""
	return current_player

func get_turn_order() -> Array:
	"""Get the current turn order (players in this case)"""
	return registered_players.duplicate()

# Traditional turn system specific methods
func _start_player_turn(player: Player) -> void:
	"""Start a specific player's turn"""
	var previous_player = current_player

	# End previous player's turn if there was one
	if previous_player and previous_player != player:
		_end_player_turn(previous_player)

	# Start new player's turn
	current_player = player
	is_turn_in_progress = true
	units_acted_this_turn.clear()
	turn_completed_manually = false
	# Clear the startup guard here (once a real player turn has begun, later
	# _check_turn_completion calls must be honored). Previously just_started was only
	# cleared inside _check_turn_completion, which swallowed the FIRST legitimate
	# completion check of the game -- so the very first player's auto-end never fired.
	just_started = false
	# New turn -> clear the deferred auto-advance guard so this player's completion can
	# schedule its own auto-end.
	_auto_advance_pending = false

	# Reset all unit actions for the new turn
	reset_all_unit_actions()

	# Tick move cooldowns and status conditions for this player's whole side
	# as it becomes active (null-safe for units without characters; idempotent
	# per turn via the shared base helper).
	_tick_all_units_turn_start(get_units_for_player(player))

	# Any unit hijacked at the top of this turn is force-driven against its own side.
	# Deferred so executing real moves (damage/deaths/signals) runs after this
	# turn-start call unwinds rather than re-entering it.
	call_deferred("_drive_controlled_units", get_units_for_player(player))

	# Notify GameManager of turn change for network synchronization
	_notify_game_manager_of_turn_change(player)

	# Emit turn started signal
	turn_started.emit(player)

func _end_player_turn(player: Player) -> void:
	"""End a specific player's turn"""
	if not player or player != current_player:
		return

	is_turn_in_progress = false

	# Fire ON_TURN_END abilities for every unit on the side that just finished --
	# the mirror of the _tick_all_units_turn_start call in _start_player_turn.
	_tick_all_units_turn_end(get_units_for_player(player))

	# Emit turn ended signal
	turn_ended.emit(player)

func _advance_to_next_player() -> void:
	"""Advance to the next player in turn order"""
	# Add current player to the list of players who have had a turn this round
	if current_player and current_player not in players_had_turn_this_round:
		players_had_turn_this_round.append(current_player)
		var player_names = []
		for p in players_had_turn_this_round:
			player_names.append(p.get_display_name())

	if registered_players.is_empty():
		return

	var current_index = registered_players.find(current_player)
	if current_index == -1:
		current_index = 0

	# Create debug list of player names
	var debug_player_names = []
	for p in players_had_turn_this_round:
		debug_player_names.append(p.get_display_name())

	# Check if all players have had a turn this round
	var all_players_had_turn = (players_had_turn_this_round.size() >= registered_players.size())

	# Find next active player
	var starting_index = current_index
	var next_index = current_index

	while true:
		next_index = (next_index + 1) % registered_players.size()

		var next_player = registered_players[next_index]

		# Check if this player can play (not eliminated, has units, etc.)
		if _can_player_take_turn_for_advance(next_player):
			# If the only eligible player is the one we started from, the turn is
			# wrapping back onto the SAME player instead of advancing. That usually
			# means the other side's units are freed/stale (second-game state bug) --
			# warn loudly rather than silently re-running the same player's turn.
			if next_player == current_player:
				push_warning("TraditionalTurnSystem: turn advance wrapped back to the same player (" + current_player.get_display_name() + ") - no other player could take a turn")

			# Increment round counter for each player switch (running counter)
			current_turn += 1

			# Check if we completed a full round (all players had a turn)
			if all_players_had_turn and next_player in players_had_turn_this_round:
				# All players have had a turn, clear the round tracking
				players_had_turn_this_round.clear()

				# Advance battle effects (use a cycle counter based on rounds)
				if BattleEffectsManager:
					var cycle_number = ((current_turn - 1) / registered_players.size()) + 1
					BattleEffectsManager.advance_round(cycle_number)

			_start_player_turn(next_player)
			break

		# Safety check to prevent infinite loop
		if next_index == starting_index:
			_handle_no_valid_players()
			break

func _can_player_take_turn_for_advance(player: Player) -> bool:
	"""Check if a player can take a turn during turn advancement (doesn't require turn to be in progress)"""
	if not player:
		return false

	# Player must not be eliminated
	if player.current_state == Player.PlayerState.ELIMINATED:
		return false

	# Player must have units that can act
	var player_units = get_units_for_player(player)

	for unit in player_units:
		# Check if unit can act without requiring turn system to be "in progress"
		if _can_unit_act_for_advance(unit, player):
			return true

	return false

func _can_unit_act_for_advance(unit: Unit, player: Player) -> bool:
	"""Check if a unit can act for a specific player during turn advancement"""
	# Unit must belong to the player
	if not player.owns_unit(unit):
		return false

	# Unit must not have acted this turn (but we're starting a new turn, so reset this check)
	# For turn advancement, we assume units haven't acted in the new turn yet

	# Unit must be able to act (not eliminated, has actions, etc.)
	if unit.has_method("can_act"):
		return unit.can_act()

	return true

func _can_player_take_turn(player: Player) -> bool:
	"""Check if a player can take a turn (requires turn system to be active)"""
	if not player:
		return false

	# Player must not be eliminated
	if player.current_state == Player.PlayerState.ELIMINATED:
		return false

	# Player must have units that can act
	var player_units = get_units_for_player(player)

	for unit in player_units:
		if can_unit_act(unit):
			return true

	return false

func _handle_no_valid_players() -> void:
	"""Handle case where no players can take turns"""
	end_turn_system()

	# Notify game that turn system ended due to no valid players
	if PlayerManager:
		PlayerManager.end_game()

# Turn completion detection
func _check_turn_completion() -> void:
	"""Check if the current player's turn should end"""
	# NOTE: the old just_started early-return lived here and swallowed the first real
	# completion check. It is removed -- the is_active/current_player/is_turn_in_progress
	# guard below already blocks checks during startup (before a turn is in progress).
	if not is_active or not current_player or not is_turn_in_progress:
		return

	# If turn was completed manually, don't auto-advance
	if turn_completed_manually:
		return

	# Check if all player's units have acted
	var player_units = get_units_for_player(current_player)
	var all_acted = true
	var units_can_act = 0
	var units_acted = 0

	for unit in player_units:
		if can_unit_act(unit):
			all_acted = false
			units_can_act += 1
		else:
			units_acted += 1
			var reason = ""
			if unit in units_acted_this_turn:
				reason = " (already acted)"
			elif not current_player.owns_unit(unit):
				reason = " (not owned by current player)"
			else:
				reason = " (cannot act)"

	if all_acted:
		all_units_acted.emit()
		# Auto-end the player's turn only when enabled in settings.
		if GameSettings and GameSettings.auto_end_turn:
			if not _auto_advance_pending:
				_auto_advance_pending = true
				# Defer the advance: this check runs inside the unit's
				# mark_action_completed signal emission, and advancing synchronously here
				# would mutate turn state re-entrantly mid-signal. call_deferred runs it
				# safely after the current signal unwinds. The guard prevents scheduling
				# more than one advance for the same turn.
				call_deferred("advance_turn")

# Unit action handling
func mark_unit_acted(unit: Unit) -> void:
	"""Mark a unit as having acted this turn"""
	if unit not in units_acted_this_turn:
		units_acted_this_turn.append(unit)

		# Check if turn should end
		_check_turn_completion()

func reset_unit_actions() -> void:
	"""Reset all unit actions for the current turn"""
	units_acted_this_turn.clear()
	reset_all_unit_actions()

# Manual turn control
func end_turn_manually() -> bool:
	"""Manually end the current player's turn"""
	if not is_active or not current_player or not is_turn_in_progress:
		return false

	turn_completed_manually = true
	advance_turn()
	return true

func can_end_turn_manually() -> bool:
	"""Check if the current player can manually end their turn"""
	return is_active and current_player and is_turn_in_progress

# Override base class event handler
func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	super._on_unit_action_completed(unit, action_type)

	# Mark unit as having acted
	mark_unit_acted(unit)

# NOTE: watching unit deaths (unregister + re-check turn completion when a unit dies)
# now lives in TurnSystemBase.register_unit / _on_registered_unit_died, so BOTH the
# Traditional and Speed First systems get it. The old per-system override here was
# removed to avoid a double connection.

# Query methods
func get_units_that_acted() -> Array[Unit]:
	"""Get units that have acted this turn"""
	return units_acted_this_turn.duplicate()

func get_units_that_can_act() -> Array[Unit]:
	"""Get units that can still act this turn"""
	if not current_player:
		return []

	var can_act_units: Array[Unit] = []
	var player_units = get_units_for_player(current_player)

	for unit in player_units:
		if can_unit_act(unit):
			can_act_units.append(unit)

	return can_act_units

func get_current_turn_progress() -> Dictionary:
	"""Get information about current turn progress"""
	if not current_player:
		return {}

	var player_units = get_units_for_player(current_player)
	var acted_count = 0
	var can_act_count = 0

	for unit in player_units:
		if unit in units_acted_this_turn:
			acted_count += 1
		elif can_unit_act(unit):
			can_act_count += 1

	return {
		"current_player": current_player.get_display_name(),
		"total_units": player_units.size(),
		"units_acted": acted_count,
		"units_can_act": can_act_count,
		"turn_complete": can_act_count == 0
	}

# Turn refresh capability (for special abilities)
func refresh_unit_turn(unit: Unit) -> bool:
	"""Allow a unit to act again this turn (for special abilities)"""
	if not is_active or not current_player or not is_turn_in_progress:
		return false

	# Unit must belong to current player
	if not current_player.owns_unit(unit):
		return false

	# Remove unit from acted list if present
	if unit in units_acted_this_turn:
		units_acted_this_turn.erase(unit)
		return true

	return false

func handle_unit_turn_refresh(unit: Unit) -> void:
	"""Handle turn refresh request from BattleEffectsManager"""
	if refresh_unit_turn(unit):
		pass

func can_refresh_unit_turn(unit: Unit) -> bool:
	"""Check if a unit's turn can be refreshed"""
	return is_active and current_player and is_turn_in_progress and current_player.owns_unit(unit) and unit in units_acted_this_turn

func get_units_eligible_for_refresh() -> Array[Unit]:
	"""Get all units that have acted and could have their turn refreshed"""
	if not current_player:
		return []

	var eligible: Array[Unit] = []
	for unit in units_acted_this_turn:
		if current_player.owns_unit(unit) and _can_unit_act_for_advance(unit, current_player):
			eligible.append(unit)
	return eligible

# Speed modification API (delegates to BattleEffectsManager)
func apply_speed_buff(unit: Unit, buff_name: String, speed_increase: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed buff to a unit"""
	if BattleEffectsManager:
		BattleEffectsManager.apply_speed_buff(unit, buff_name, speed_increase, duration_rounds, source)

func apply_speed_debuff(unit: Unit, debuff_name: String, speed_decrease: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed debuff to a unit"""
	if BattleEffectsManager:
		BattleEffectsManager.apply_speed_debuff(unit, debuff_name, speed_decrease, duration_rounds, source)

func remove_speed_effect(unit: Unit, effect_name: String) -> bool:
	"""Remove a speed effect from a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.remove_speed_effect(unit, effect_name)
	return false

func get_unit_current_speed(unit: Unit) -> int:
	"""Get unit's current speed including all battle-scoped modifiers"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_current_speed(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		return unit.get_stat("speed") if unit.has_method("get_stat") else 0

func get_unit_speed_info(unit: Unit) -> Dictionary:
	"""Get detailed speed information for a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_speed_info(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
		return {
			"base_speed": base_speed,
			"current_speed": base_speed,
			"total_modifier": 0,
			"modifiers": []
		}

# Reset mechanism for testing
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

func reset_turn_system() -> void:
	"""Reset the turn system to initial state (for testing purposes)"""
	# Reset all state variables
	current_turn = 1
	is_turn_in_progress = false
	units_acted_this_turn.clear()
	turn_completed_manually = false
	players_had_turn_this_round.clear()
	just_started = true
	# Drop per-turn tick / stun-skip bookkeeping: current_turn just rewound to 1, so
	# a stale entry from the previous battle's turn 1 would read as a live skip.
	clear_turn_tick_state()

	# Reset BattleEffectsManager
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()  # This resets battle state

	# Reset all unit actions
	reset_all_unit_actions()

	# Start with first player again
	if not registered_players.is_empty():
		current_player = registered_players[0]
		_start_player_turn(current_player)
	else:
		current_player = null

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the traditional turn system state"""
	var base_info = super.get_turn_system_info()

	var active_effects_count = 0
	if BattleEffectsManager:
		var effects = BattleEffectsManager.get_all_active_effects()
		active_effects_count = effects.size()

	var traditional_info = {
		"current_player": current_player.get_display_name() if current_player else "None",
		"units_acted_this_turn": units_acted_this_turn.size(),
		"turn_completed_manually": turn_completed_manually,
		"active_battle_effects": active_effects_count,
		"turn_progress": get_current_turn_progress()
	}

	base_info.merge(traditional_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var player_name = current_player.get_display_name() if current_player else "No Player"
	return system_name + " (Round " + str(current_turn) + " - " + player_name + ")"

func _notify_game_manager_of_turn_change(player: Player) -> void:
	"""Notify GameManager of turn change for network synchronization"""
	# Check if we're in multiplayer mode and need to sync turns
	if GameModeManager and GameModeManager.is_multiplayer_active():
		# Get the GameManager through GameModeManager
		var game_manager = GameModeManager._game_manager
		if game_manager:
			# Find the player index in the GameManager's player list
			var players = game_manager.get_players()
			var player_id = -1

			# Strategy 1: Direct player ID match (most reliable)
			if players.has(player.player_id):
				player_id = player.player_id
			else:
				# Strategy 2: Name matching (should work now with simplified names)
				for pid in players:
					var p = players[pid]
					var gm_name = p.get("name", "")

					if gm_name == player.get_display_name():
						player_id = pid
						break

			if player_id >= 0:
				game_manager._current_turn_player = player_id

				game_manager.turn_changed.emit(player_id)

				# Also trigger network sync if we're the host
				if game_manager._network_handler and game_manager._network_handler.is_host():
					var turn_action = {
						"type": "turn_change",
						"data": {
							"current_player": player_id,
							"timestamp": Time.get_ticks_msec()
						}
					}
					var success = game_manager._network_handler.submit_action(turn_action)
