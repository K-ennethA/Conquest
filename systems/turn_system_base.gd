extends Node

class_name TurnSystemBase

# Abstract base class for all turn systems
# Defines common interface and signals for turn management

# Turn system signals
signal turn_started(player: Player)
signal turn_ended(player: Player)
signal turn_system_changed(old_system: TurnSystemBase, new_system: TurnSystemBase)
signal unit_action_completed(unit: Unit, action_type: String)
signal all_units_acted()

# Turn system types
enum TurnSystemType {
	TRADITIONAL,    # Player-based turns (all units per player)
	INITIATIVE,     # Unit-based turns (speed/initiative order)
	SIMULTANEOUS,   # All players act simultaneously
	REAL_TIME       # Real-time with action points
}

# Abstract properties
var system_type: TurnSystemType
var system_name: String = "Base Turn System"
var is_active: bool = false

# Registered units and players
var registered_units: Array[Unit] = []
var registered_players: Array[Player] = []

# Current turn state
var current_turn: int = 0
var is_turn_in_progress: bool = false

func _init() -> void:
	name = "TurnSystemBase"

# Abstract methods - must be implemented by derived classes
func start_turn_system() -> void:
	"""Initialize and start the turn system"""
	push_error("start_turn_system() must be implemented by derived class")

func end_turn_system() -> void:
	"""Clean up and end the turn system"""
	push_error("end_turn_system() must be implemented by derived class")

func advance_turn() -> void:
	"""Advance to the next turn"""
	push_error("advance_turn() must be implemented by derived class")

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	push_error("can_unit_act() must be implemented by derived class")
	return false

func get_current_active_player() -> Player:
	"""Get the currently active player"""
	push_error("get_current_active_player() must be implemented by derived class")
	return null

func get_turn_order() -> Array:
	"""Get the current turn order (units or players)"""
	push_error("get_turn_order() must be implemented by derived class")
	return []

# Virtual methods - can be overridden by derived classes
func reset_turn_system() -> void:
	"""Reset the turn system to initial state (for testing purposes)"""
	# Default implementation - derived classes should override
	current_turn = 1
	is_turn_in_progress = false

# Common implementation methods
func register_unit(unit: Unit) -> void:
	"""Register a unit with the turn system"""
	if unit not in registered_units:
		registered_units.append(unit)

		# Connect to unit signals. Guard with is_connected exactly like the unit_died
		# hook below: this is the ONE wire that drives auto-end-of-turn (a unit's
		# mark_action_completed -> unit_action_completed -> _on_unit_action_completed ->
		# mark_unit_acted -> _check_turn_completion). Without the guard a unit that is
		# registered again while still connected (re-registration, or a scene-scan pass
		# that races register_player) either errors or double-fires, so the completion
		# check runs twice / not at all -- the reported "turn doesn't auto-advance"
		# flakiness. The guard makes the connection idempotent: every registered unit is
		# connected exactly once, so its completion is always observed.
		if unit.has_signal("unit_action_completed") and not unit.unit_action_completed.is_connected(_on_unit_action_completed):
			unit.unit_action_completed.connect(_on_unit_action_completed)

		# Watch for this unit's death so the turn system can drop it and re-check
		# turn completion (a side whose last actable unit dies must not stall the turn).
		if unit.has_signal("unit_died") and not unit.unit_died.is_connected(_on_registered_unit_died):
			unit.unit_died.connect(_on_registered_unit_died)

func unregister_unit(unit: Unit) -> void:
	"""Unregister a unit from the turn system"""
	if unit in registered_units:
		registered_units.erase(unit)

		# Disconnect from unit signals
		if unit.has_signal("unit_action_completed") and unit.unit_action_completed.is_connected(_on_unit_action_completed):
			unit.unit_action_completed.disconnect(_on_unit_action_completed)
		if unit.has_signal("unit_died") and unit.unit_died.is_connected(_on_registered_unit_died):
			unit.unit_died.disconnect(_on_registered_unit_died)

func _on_registered_unit_died(unit: Unit) -> void:
	"""A registered unit died. Drop it from the turn system NOW -- this fires inside
	the unit's unit_died emission, where the unit is still a valid instance
	(queue_free happens at end of frame), so we must not pass it through a deferred
	call (it would be freed by then -> 'cannot convert freed Object'). Only the
	completion re-check is deferred, since it can advance the turn (re-entrant)."""
	if unit != null and is_instance_valid(unit) and unit in registered_units:
		unregister_unit(unit)
	call_deferred("_check_turn_completion")

func register_player(player: Player) -> void:
	"""Register a player with the turn system"""
	if player not in registered_players:
		registered_players.append(player)
		
		# Register all player's units
		for unit in player.owned_units:
			register_unit(unit)

func unregister_player(player: Player) -> void:
	"""Unregister a player from the turn system"""
	if player in registered_players:
		registered_players.erase(player)
		
		# Unregister all player's units
		for unit in player.owned_units:
			unregister_unit(unit)

func validate_turn_action(unit: Unit, action_type: String) -> bool:
	"""Validate if a unit can perform an action"""
	if not unit or not is_active:
		return false

	if unit not in registered_units:
		return false

	# A unit may move only once per turn (unless granted extra movement).
	if action_type == "move" and unit.has_method("can_move") and not unit.can_move():
		return false

	return can_unit_act(unit)

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	unit_action_completed.emit(unit, action_type)
	
	# Check if turn should advance
	_check_turn_completion()

func _check_turn_completion() -> void:
	"""Check if the current turn should end (override in derived classes)"""
	pass

# Utility methods
func get_units_for_player(player: Player) -> Array[Unit]:
	"""Get all registered units for a specific player"""
	var player_units: Array[Unit] = []
	for unit in registered_units:
		# Guard against freed units left over from a prior session / dead units.
		if not is_instance_valid(unit):
			continue
		if unit.get_owner_player() == player:
			player_units.append(unit)
	return player_units

func get_active_units() -> Array[Unit]:
	"""Get all units that can currently act"""
	var active_units: Array[Unit] = []
	for unit in registered_units:
		# Guard against freed units left over from a prior session / dead units.
		if not is_instance_valid(unit):
			continue
		if can_unit_act(unit):
			active_units.append(unit)
	return active_units

func reset_all_unit_actions() -> void:
	"""Reset action states for all units"""
	for unit in registered_units:
		if unit.has_method("reset_turn_actions"):
			unit.reset_turn_actions()

# --- Turn-boundary ticking (move cooldowns + status conditions) ---
# Tracks the turn on which each unit was last ticked, keyed by unit reference.
# This keeps ticking idempotent: a unit is ticked at most once per `current_turn`
# value, so calling the helpers more than once for the same turn is harmless.
var _last_tick_turn: Dictionary = {}

# --- Stun (skip-a-turn) bookkeeping -----------------------------------------
#
# unit -> the `current_turn` value on which that unit's turn was skipped by a
# "stunned" rule flag. Both turn systems consult it from can_unit_act(), so the
# skip lands in get_active_units(), in Traditional's completion check and in the
# AI driver from ONE place.
#
# WHY A LATCH AND NOT A LIVE QUERY: this is the whole trick, and getting it wrong
# is a permanent unit lockout. A 1-turn status is decremented and EXPIRED by the
# very tick that opens the unit's turn (StatusController.tick_all decrements then
# expires at 0), so a can_unit_act() that asked "are you stunned right now?" would
# always be asking AFTER the flag had already gone -- the stun would never skip
# anything at all. So the flag is sampled at the top of the unit's turn, BEFORE
# statuses tick, and remembered for the rest of that turn.
#
# The mirror-image failure is worse and is the one worth pinning in tests: if a
# stunned unit were instead dropped from the turn order (or its tick skipped), its
# status would never tick, the stun would never expire, and the unit would be
# locked out FOREVER. Hence a stunned unit still starts its turn and still ticks
# everything -- it simply cannot act during it.
var _stun_skipped_turn: Dictionary = {}

# --- Control (forced-turn) bookkeeping --------------------------------------
#
# unit -> the `current_turn` value on which that unit was found "controlled" at the
# top of its turn. The EXACT same latch shape as the stun skip above, and for the
# same reason: Enthralled is a 1-turn status, so the tick that opens the unit's turn
# both drives the puppeteering AND expires the flag. A live query at act time would
# always be too late; sampling it at turn start (before statuses tick) is what makes
# the control land on this turn while still letting it wear off, so a unit can never
# be hijacked permanently -- the mirror of the stun lockout.
#
# Unlike a stun (which merely skips), a controlled unit is FORCED to act against its
# own side. The turn systems block the player from commanding it (can_unit_act returns
# false, exactly like a skip) and hand it to _drive_controlled_units(), which
# auto-resolves it through the AI planner with allegiance inverted.
var _control_forced_turn: Dictionary = {}

## True if [param unit]'s turn is being skipped by a stun THIS turn. Consulted by
## both turn systems' can_unit_act() and by the AI driver.
func is_turn_skipped(unit) -> bool:
	if unit == null:
		return false
	return int(_stun_skipped_turn.get(unit, -1)) == current_turn

## True if [param unit] was hijacked (Enthralled) at the top of THIS turn and is being
## force-driven against its own side. Consulted by both turn systems' can_unit_act()
## (to bar the player from commanding it) and by the forced-control driver.
func is_turn_forced_control(unit) -> bool:
	if unit == null:
		return false
	return int(_control_forced_turn.get(unit, -1)) == current_turn

## True if any active status on [param unit] sets the "controlled" rule flag. Duck-typed
## and independently optional at every step, mirroring [method _has_stun_flag], so a
## mock exposing none of the accessors is simply never controlled.
func _has_control_flag(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_controlled") and bool(unit.is_controlled()):
		return true
	if unit.has_method("has_status_rule_flag") and bool(unit.has_status_rule_flag(&"controlled")):
		return true
	if unit.has_method("get_status_controller"):
		var controller = unit.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(&"controlled")):
			return true
	return false

## Forget all per-turn tick / stun-skip / control bookkeeping. Called by the derived
## systems' reset_turn_system(), which rewinds current_turn to 1 -- without this a
## stale entry recorded on the old turn 1 would read as a live skip/control after reset.
func clear_turn_tick_state() -> void:
	_last_tick_turn.clear()
	_stun_skipped_turn.clear()
	_control_forced_turn.clear()

## True if any active status on [param unit] sets the "stunned" rule flag.
## Duck-typed and independently optional at every step, mirroring how
## DamageEffect probes for "immobilized", so a mock exposing none of the
## accessors is simply never stunned.
func _has_stun_flag(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_stunned") and bool(unit.is_stunned()):
		return true
	if unit.has_method("has_status_rule_flag") and bool(unit.has_status_rule_flag(&"stunned")):
		return true
	if unit.has_method("get_status_controller"):
		var controller = unit.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(&"stunned")):
			return true
	return false

func _tick_unit_turn_start(unit) -> void:
	"""Advance a single unit's move cooldowns and status conditions, then fire its
	ON_TURN_START abilities.

	Null-safe for units WITHOUT characters (no MovesetController /
	StatusController / AbilitySystem) and idempotent within the same turn.
	"""
	if unit == null:
		return

	# Idempotency: never tick the same unit twice in the same turn.
	if _last_tick_turn.get(unit, -1) == current_turn:
		return
	_last_tick_turn[unit] = current_turn

	# Sample "stunned" FIRST, ahead of every tick below. The status ticks that
	# follow are what EXPIRE the stun, so by the time they have run the flag is
	# gone; latching it here is what makes the skip land on this turn while still
	# letting the stun run out (see the _stun_skipped_turn docs above).
	if _has_stun_flag(unit):
		_stun_skipped_turn[unit] = current_turn
		var who: String = unit.get_display_name() if unit.has_method("get_display_name") else str(unit)

	# Sample "controlled" alongside the stun, and for the identical reason: the status
	# ticks below EXPIRE Enthralled, so latching it here is what makes the hijack land
	# on this turn while still letting it wear off (never a permanent puppet). The
	# turn system then bars the player from the unit and force-drives it against its
	# own side (see _drive_controlled_units in each system).
	if _has_control_flag(unit):
		_control_forced_turn[unit] = current_turn
		var puppet: String = unit.get_display_name() if unit.has_method("get_display_name") else str(unit)

	# Timed STAT modifiers expire here. Unit.process_turn_start() ->
	# UnitStats.process_modifier_durations() was called by nothing in the live game
	# (only by tests), so every duration-limited modifier persisted FOREVER in a real
	# battle: a 3-turn defence buff, a 1-turn movement slow and a 5-turn range bonus
	# all became permanent the moment they were applied.
	#
	# ORDER MATTERS: this must run BEFORE status conditions tick below. A status's
	# tick can APPLY a modifier (entangled's slow does exactly that), and expiring
	# afterwards would decrement a modifier on the same turn it was granted --
	# cancelling a one-turn slow before it ever took effect.
	if unit.has_method("process_turn_start"):
		unit.process_turn_start()

	# Move cooldowns: only present when the unit has a MovesetController.
	var moveset = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
	if moveset != null and moveset.has_method("tick_cooldowns"):
		moveset.tick_cooldowns()

	# Status conditions: only present when the unit has a StatusController.
	# tick_all() requires a board; CombatServices.board() may be null, so guard.
	var status = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	if status != null and status.has_method("tick_all"):
		var board = CombatServices.board() if CombatServices else null
		if board != null:
			status.tick_all(board)

	# Character abilities: only present when the character declares some. This is
	# the one per-unit turn-start hook BOTH turn systems share -- SpeedFirst calls
	# it for the single unit whose turn began, Traditional calls it for every unit
	# on the side that just became active -- so an ON_TURN_START ability fires
	# exactly once per unit per turn in either order. Effects need a board.
	var ability_system = unit.get_ability_system() if unit.has_method("get_ability_system") else null
	if ability_system != null:
		# Ability cooldowns count down here, exactly like move cooldowns above and
		# for the same reason: one tick per unit per turn, before anything gets the
		# chance to fire. Needs no board.
		if ability_system.has_method("tick_cooldowns"):
			ability_system.tick_cooldowns()
		if ability_system.has_method("trigger"):
			var ability_board = CombatServices.board() if CombatServices else null
			if ability_board != null:
				ability_system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, ability_board)

func _tick_unit_turn_end(unit) -> void:
	"""Fire a single unit's ON_TURN_END abilities as its turn closes.

	The mirror of `_tick_unit_turn_start`, and the shared per-unit turn-END hook
	the two turn systems previously lacked: Speed First closes one unit's turn
	(`_end_unit_turn`) while Traditional closes a whole side's (`_end_player_turn`),
	so each calls this for the unit(s) it is finishing. Null-safe for units without
	an AbilitySystem, and deliberately NOT idempotency-tracked -- both systems end a
	given unit's turn exactly once.
	"""
	if unit == null:
		return
	var ability_system = unit.get_ability_system() if unit.has_method("get_ability_system") else null
	if ability_system == null or not ability_system.has_method("trigger"):
		return
	var ability_board = CombatServices.board() if CombatServices else null
	if ability_board != null:
		ability_system.trigger(AbilityTrigger.Trigger.ON_TURN_END, unit, ability_board)

func _tick_all_units_turn_start(units: Array) -> void:
	"""Convenience: tick every unit in `units` (each idempotent per turn)."""
	for unit in units:
		_tick_unit_turn_start(unit)

func _tick_all_units_turn_end(units: Array) -> void:
	"""Convenience: close out every unit in `units`."""
	for unit in units:
		_tick_unit_turn_end(unit)

# --- Forced-control resolution ----------------------------------------------
#
# The other half of the control latch: latching bars a controlled unit from being
# commanded (can_unit_act returns false), and THIS drives it against its own side.
# One shared implementation for BOTH turn systems and BOTH owners (human units the
# player can no longer command AND the AI's own units): it reuses the existing AI
# planner (BotController, with allegiance inverted via force_control) and the ordinary
# move-execution path (Unit.perform_move), then marks the unit acted so its turn ends
# and the enthralled status expires normally. If nothing hostile-to-its-allies is
# reachable it simply spends the turn -- control still wore off. Called DEFERRED from
# each system's turn start so executing a real move (damage, deaths, signals) never
# re-enters the turn-start call stack.

## Force-drive every forced-control unit in [param units] against its own side.
func _drive_controlled_units(units: Array) -> void:
	var board = CombatServices.board() if CombatServices else null
	if board == null:
		return
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if is_turn_forced_control(unit):
			_auto_resolve_control(unit, board)

## Resolve one controlled unit's forced turn: plan an attack on an ally (inverted
## planner) and execute it, else spend the turn. Guarded end to end so a legacy /
## non-character unit, or one with nothing to hit, still cleanly ends its turn.
func _auto_resolve_control(unit, board) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	# Already resolved (e.g. driven once, or died mid-turn)? Nothing to do.
	if unit.has_method("can_act") and not unit.can_act():
		return
	if not (unit.has_method("perform_move") and unit.has_method("has_character") and unit.has_character()):
		_spend_forced_turn(unit)
		return

	# Mark the unit controlled for the whole of this action. Enthralled has already
	# ticked away (that is the anti-lockout), so this transient marker is what keeps
	# is_controlled() true so BOTH the planner's allegiance inversion AND the move's
	# gather-target inversion (MoveContext) treat allies as valid victims while it acts.
	if unit.has_method("set_forced_control"):
		unit.set_forced_control(true)

	var controller := BotController.new()
	controller.difficulty = _forced_control_difficulty()
	# Belt-and-suspenders inversion: force_control makes the planner treat the unit's
	# ALLIES as its targets even if is_controlled() ever read false (see
	# BotController._is_hostile).
	controller.force_control = true

	var origin: Vector2i = board.cell_of(unit)
	var reachable: Array = _control_reachable_cells(unit, origin, board)
	var decision = controller.plan(unit, unit.get_moveset(), board, reachable)
	if decision == null or decision.is_empty() \
		or int(decision.get("action", BotController.ActionType.WAIT)) != BotController.ActionType.MOVE:
		# No ally reachable -> do nothing, but the turn is still spent and control
		# still expires (the anti-lockout guarantee holds regardless of outcome).
		if unit.has_method("set_forced_control"):
			unit.set_forced_control(false)
		_spend_forced_turn(unit)
		return

	# Walk to the planned stand cell first (if any), then strike the ally from there.
	var dest: Vector2i = decision.get("dest_cell", origin)
	if dest != origin and not (unit.has_method("is_immobilized") and unit.is_immobilized()):
		board.move_unit(unit, dest)
		if GameEvents:
			GameEvents.unit_moved.emit(unit,
				Vector3(origin.x, 0, origin.y), Vector3(dest.x, 0, dest.y))
		if unit.has_method("mark_moved"):
			unit.mark_moved()

	var move = decision.get("move", null)
	var aim_cell: Vector2i = decision.get("aim_cell", board.cell_of(unit))
	var victim = decision.get("target", null)
	var slot: int = _slot_of_move(unit, move)
	if slot >= 0:
		unit.perform_move(slot, aim_cell, board)
		if GameEvents and GameEvents.has_signal(&"unit_acted_under_control"):
			GameEvents.emit_signal(&"unit_acted_under_control", unit, victim)

	# Control resolved: drop the transient marker so the unit is its own again next turn.
	if unit.has_method("set_forced_control"):
		unit.set_forced_control(false)
	_spend_forced_turn(unit)

## End a forced-control unit's turn (marks it acted, which flows turn completion /
## advance through the normal signal path).
func _spend_forced_turn(unit) -> void:
	if unit != null and is_instance_valid(unit) and unit.has_method("mark_action_completed") \
		and unit.has_method("can_act") and unit.can_act():
		unit.mark_action_completed("controlled")

## Cells a controlled unit can reach this turn, via its movement profile and the live
## board (empty when it has none -- the planner then only strikes from its own cell).
func _control_reachable_cells(unit, origin: Vector2i, board) -> Array:
	if unit.has_method("is_immobilized") and unit.is_immobilized():
		return []
	if not unit.has_method("get_movement_profile"):
		return []
	var profile = unit.get_movement_profile()
	if profile == null:
		return []
	return MovementResolver.new().reachable_cells(origin, profile, board, unit)

## Index of [param move] in [param unit]'s moveset (what perform_move expects), or -1.
func _slot_of_move(unit, move) -> int:
	if unit == null or not unit.has_method("get_moveset"):
		return -1
	var moveset: Array = unit.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			return i
	return -1

## The configured AI difficulty (NORMAL when GameSettings is unavailable, e.g. tests).
func _forced_control_difficulty() -> int:
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and "ai_difficulty" in gs:
		return int(gs.ai_difficulty)
	return BotController.Difficulty.NORMAL

# Debug and info methods
func get_turn_system_info() -> Dictionary:
	"""Get information about the current turn system state"""
	return {
		"system_type": TurnSystemType.keys()[system_type],
		"system_name": system_name,
		"is_active": is_active,
		"current_turn": current_turn,
		"is_turn_in_progress": is_turn_in_progress,
		"registered_units": registered_units.size(),
		"registered_players": registered_players.size(),
		"active_units": get_active_units().size()
	}

func _to_string() -> String:
	"""String representation for debugging"""
	return system_name + " (Turn " + str(current_turn) + ")"
