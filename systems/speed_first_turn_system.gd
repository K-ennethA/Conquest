extends TurnSystemBase

class_name SpeedFirstTurnSystem

# Speed First Turn System Implementation
# Unit-based turns where units act in order based on their speed stats (fastest first)
# Features:
# - Dynamic turn order based on current speed (including temporary modifiers)
# - Queue system prevents units from acting twice until all others have acted
# - Speed modifications can change turn order mid-round

# --- Per-unit move clock (Speed mode "speedier") ----------------------------
# A HUMAN player's unit gets a countdown the moment its turn starts; when it runs
# out the unit's turn is force-ended EXACTLY like the End Turn button (no staged
# move committed -- the UI owns that state). AI units are never clocked. The system
# is NOT in the scene tree (TurnSystemManager keeps it in a plain dictionary, never
# add_child'd), so it CANNOT run _process or a SceneTreeTimer; it therefore owns only
# the ARM/DISARM state + the expiry entry point, and the in-tree TurnTimer HUD drives
# the actual per-frame countdown and calls expire_turn_timer() when it hits zero.

## Emitted when a human unit's turn begins and the move clock should start. [param seconds]
## is the configured duration (GameSettings.speed_turn_timer_seconds). The HUD listens and
## runs the countdown.
signal turn_timer_armed(unit: Unit, seconds: float)
## Emitted whenever the move clock stops for any reason (the unit acted, the unit died
## mid-turn, the system deactivated/reset, or the clock expired). The HUD hides on this.
signal turn_timer_disarmed()
## Emitted when the clock reached zero and the turn was force-ended. Fired for consumers
## that want a flourish; the turn advance itself flows through end_turn_manually().
signal turn_timer_expired(unit: Unit)

## True while a human unit's move clock is armed. Owned here; the HUD reads/echoes it.
var turn_timer_active: bool = false
## The unit the armed clock belongs to (guards stale expiry against a re-used slot).
var turn_timer_unit: Unit = null
## The configured duration (seconds) the clock was armed with. 0 while disarmed.
var turn_timer_seconds: float = 0.0

var turn_queue: Array[Unit] = []  # Current turn queue for this round
var current_acting_unit: Unit = null
## True while a deferred kickoff (start the order once units register post-activation) is
## already pending, so a batch of same-frame registrations schedules it only once.
var _kickoff_queued: bool = false
var units_acted_this_round: Array[Unit] = []
var round_number: int = 1

# Speed modifications are now handled by BattleEffectsManager
# This ensures consistency across all turn systems

func _init() -> void:
	super._init()
	system_type = TurnSystemType.INITIATIVE
	system_name = "Speed First Turn System"

# Abstract method implementations
func start_turn_system() -> void:
	"""Initialize and start the speed first turn system"""
	is_active = true
	current_turn = 1
	round_number = 1
	is_turn_in_progress = false
	# A fresh battle gets a fresh battle-start pass (this instance is reused across
	# battles -- TurnSystemManager keeps it in a dictionary). Cleared HERE and fired
	# from _start_unit_turn, so the late-registration kickoff below still gets it.
	_battle_start_dispatched = false
	units_acted_this_round.clear()

	# Initialize BattleEffectsManager for this battle
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()

	# Calculate initial turn queue
	_calculate_turn_queue()

	# Start with first unit in queue.
	#
	# An EMPTY queue here used to bail out permanently, leaving current_acting_unit null
	# forever -- and because THIS system derives the current player from the acting unit
	# (unlike Traditional, whose current player is player-based), that made every unit
	# selectable but uncommandable for the rest of the battle. Arena hit it every time:
	# a round's actors are spawned around activation, so the system could be started
	# before any of them had registered. Now we stay ACTIVE with nothing acting and let
	# the first registration kick the order off (see register_unit / _kickoff_if_idle).
	if not turn_queue.is_empty():
		_start_unit_turn(turn_queue[0])
		_print_turn_queue()

## Units can register AFTER the system starts -- an Arena round spawns its actors around
## activation, and summons arrive mid-battle. If nothing is acting yet, the newcomer must
## kick the order off, or the battle sits idle with no current acting unit (and therefore
## no current player, so nothing can be commanded).
##
## The kickoff is DEFERRED so a whole batch of units registering in the same frame is in
## the queue before it is sorted -- starting on the literal first registration would lock
## in a one-unit turn order and drop everyone spawned immediately after.
func register_unit(unit: Unit) -> void:
	super.register_unit(unit)
	if not is_active or current_acting_unit != null or _kickoff_queued:
		return
	_kickoff_queued = true
	call_deferred("_kickoff_if_idle")


func _kickoff_if_idle() -> void:
	_kickoff_queued = false
	# Re-check: the system may have been ended, or something may have started a turn in
	# the meantime (this is the whole reason it is deferred).
	if not is_active or current_acting_unit != null:
		return
	_calculate_turn_queue()
	if turn_queue.is_empty():
		return
	_start_unit_turn(turn_queue[0])
	_print_turn_queue()


func end_turn_system() -> void:
	"""Clean up and end the speed first turn system"""
	# The battle is over -- kill any running move clock (in case the acting unit's turn
	# is not in progress, so _end_unit_turn below would not run for it).
	_disarm_turn_timer()

	if current_acting_unit and is_turn_in_progress:
		_end_unit_turn(current_acting_unit)

	# End battle in BattleEffectsManager (clears all battle-scoped effects)
	if BattleEffectsManager:
		BattleEffectsManager.end_battle()

	is_active = false
	is_turn_in_progress = false
	current_acting_unit = null
	turn_queue.clear()
	units_acted_this_round.clear()
	round_number = 1


func reset_battle_state() -> void:
	"""Reset all battle-specific state (call when starting new battle)"""
	if BattleEffectsManager:
		BattleEffectsManager.reset_battle_state()

	units_acted_this_round.clear()
	turn_queue.clear()
	round_number = 1
	current_acting_unit = null
	is_turn_in_progress = false
	_disarm_turn_timer()

func advance_turn() -> void:
	"""Advance to the next unit's turn"""
	if not is_active or not current_acting_unit:
		return

	_end_unit_turn(current_acting_unit)
	_advance_to_next_unit()

func _on_registered_unit_died(unit: Unit) -> void:
	"""Speed First runs a single-unit queue and advances ONLY when the acting unit
	completes an action (mark_unit_acted). But a unit can die mid-turn WITHOUT ever
	completing one -- a lethal poison/burn tick at its own turn start, or walking onto a
	lethal hazard tile (movement fires mark_moved, not mark_action_completed). The base
	handler just unregisters it and re-checks round completion, which Speed First
	deliberately never advances from -- so without this override current_acting_unit would
	dangle at the (about-to-be-freed) dead unit, is_turn_in_progress stays true, and the
	whole match soft-locks (AI) or crashes on the next End-Turn deref. When the ACTING unit
	is the one dying, hand off to the next unit in the queue."""
	var was_acting := (unit != null and unit == current_acting_unit)
	super._on_registered_unit_died(unit)  # unregister now (still valid) + defer round re-check
	# ALWAYS drop the dead unit from the queue while the ref is still valid - a queued
	# non-acting unit killed by an AoE would otherwise sit freed in turn_queue, and the
	# TurnQueue HUD's preview (built inside the very hand-off that killed it) hard-crashes
	# dereferencing it (caught by the Speed First soak run).
	if unit != null and unit in turn_queue:
		turn_queue.erase(unit)
	if was_acting:
		# Clear the acting slot BEFORE advancing so no path (advance_turn, mark_unit_acted,
		# _advance_to_next_unit, the debug getters) can touch the freed instance. Drop it
		# from the queue by the still-valid ref, then hand off next idle frame.
		if unit in turn_queue:
			turn_queue.erase(unit)
		# The acting unit died mid-turn WITHOUT going through _end_unit_turn, so stop its
		# move clock here or the HUD would keep counting a dead unit and expire_turn_timer
		# would later dereference it.
		_disarm_turn_timer()
		current_acting_unit = null
		is_turn_in_progress = false
		call_deferred("_advance_to_next_unit")

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	if not is_active or not is_turn_in_progress:
		return false

	# A stunned unit forfeits this turn. It deliberately stays IN the turn queue and
	# still has _start_unit_turn() run for it -- that is what ticks its statuses and
	# expires the stun. It just cannot do anything while its turn is up; the human
	# ends it with the End Turn button (can_end_turn_manually is independent of this)
	# and BotTurnDriver advances past it automatically.
	if is_turn_skipped(unit):
		return false

	# A CONTROLLED unit is barred from the player exactly like a stun; the turn system
	# force-drives it against its own side instead (see _drive_controlled_units).
	if is_turn_forced_control(unit):
		return false

	# Only the current acting unit can act
	return unit == current_acting_unit

func get_current_active_player() -> Player:
	"""Get the player who owns the currently acting unit"""
	if not current_acting_unit:
		return null

	# Find which player owns the current unit
	for player in registered_players:
		if player.owns_unit(current_acting_unit):
			return player

	return null

func get_turn_order() -> Array:
	"""Get the current turn queue (units in speed order)"""
	return turn_queue.duplicate()

# Speed First turn system specific methods
func _calculate_turn_queue() -> void:
	"""Calculate turn queue based on current unit speeds (including modifiers)"""
	turn_queue.clear()

	# Get all active units that haven't acted this round
	var available_units: Array[Unit] = []
	for unit in registered_units:
		if _is_unit_active(unit) and unit not in units_acted_this_round:
			available_units.append(unit)

	# Sort by current speed (highest first)
	available_units.sort_custom(_compare_unit_current_speed)

	turn_queue = available_units

func _print_turn_queue() -> void:
	"""Print current turn queue for debugging"""
	for i in range(turn_queue.size()):
		var unit = turn_queue[i]
		var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
		var current_speed = get_unit_current_speed(unit)
		var speed_info = str(current_speed)
		if current_speed != base_speed:
			speed_info += " (base: " + str(base_speed) + ")"

func _compare_unit_current_speed(unit_a: Unit, unit_b: Unit) -> bool:
	"""Compare two units by current speed for sorting (higher speed first)"""
	var speed_a = get_unit_current_speed(unit_a)
	var speed_b = get_unit_current_speed(unit_b)

	# If speeds are equal, use unit name for consistent ordering
	if speed_a == speed_b:
		return unit_a.get_display_name() < unit_b.get_display_name()

	return speed_a > speed_b

func get_unit_current_speed(unit: Unit) -> int:
	"""Get unit's current speed including all battle-scoped modifiers

	IMPORTANT: This does NOT modify the unit's base stats resource.
	Battle modifiers are temporary and reset when the battle ends.
	"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_current_speed(unit)
	else:
		# Fallback if BattleEffectsManager is not available
		return unit.get_stat("speed") if unit.has_method("get_stat") else 0

func add_speed_modifier(unit: Unit, modifier_name: String, speed_change: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Add a speed modifier to a unit"""
	if BattleEffectsManager:
		if speed_change > 0:
			BattleEffectsManager.apply_speed_buff(unit, modifier_name, speed_change, duration_rounds, source)
		else:
			BattleEffectsManager.apply_speed_debuff(unit, modifier_name, abs(speed_change), duration_rounds, source)

		# Recalculate turn queue if this affects turn order
		if is_active and not is_turn_in_progress:
			_calculate_turn_queue()
			_print_turn_queue()

func remove_speed_modifier(unit: Unit, modifier_name: String) -> bool:
	"""Remove a specific speed modifier from a unit"""
	if BattleEffectsManager:
		var result = BattleEffectsManager.remove_speed_effect(unit, modifier_name)

		# Recalculate turn queue if this affects turn order
		if result and is_active and not is_turn_in_progress:
			_calculate_turn_queue()
			_print_turn_queue()

		return result
	else:
		return false

func get_unit_speed_modifiers(unit: Unit) -> Array:
	"""Get all speed modifiers for a unit"""
	if BattleEffectsManager:
		return BattleEffectsManager.get_unit_speed_modifiers(unit)
	return []



func _is_unit_active(unit: Unit) -> bool:
	"""Check if a unit is active and can participate in turns"""
	# is_instance_valid (not just `if not unit`): a unit freed on death leaves a dangling
	# reference that is NOT caught by a plain null check, and calling has_method/is_alive on
	# it crashes ("previously freed"). Treat a freed unit as inactive so it's filtered out
	# of the queue everywhere this gate is used.
	if unit == null or not is_instance_valid(unit):
		return false

	# Unit must be alive/active
	if unit.has_method("is_alive") and not unit.is_alive():
		return false

	# Unit must belong to an active player
	var owner = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner = player
			break

	if not owner or owner.current_state == Player.PlayerState.ELIMINATED:
		return false

	return true

func _start_unit_turn(unit: Unit) -> void:
	"""Start a specific unit's turn"""
	# THE BATTLE-START PASS, first opened turn only (see the base class). Fired here
	# rather than in start_turn_system() because this system can start with an empty
	# queue and only receive its actors on the deferred kickoff -- this is the first
	# moment a turn genuinely opens in EITHER order. Covers every registered unit, not
	# just the one whose turn this is.
	_dispatch_battle_start_once()

	current_acting_unit = unit
	is_turn_in_progress = true

	# Reset THIS unit's per-turn action flags as its turn begins. Traditional resets
	# every one of a player's units at player-turn start (reset_all_unit_actions in
	# _start_player_turn); Speed First's analog is per-unit, since a unit's "turn" is
	# the moment it acts. Without this, has_moved_this_turn / has_acted_this_turn are
	# NEVER cleared during normal round flow, so can_move()/can_act() latch false after
	# the unit's first move/action -- breaking 1-move-per-turn gating (and the Move /
	# End-Turn buttons) in Speed First while it works in Traditional. Null-safe.
	if unit != null and unit.has_method("reset_turn_actions"):
		unit.reset_turn_actions()

	# Tick this unit's move cooldowns and status conditions as its turn begins
	# (null-safe for units without characters; idempotent per turn via the
	# shared base helper).
	_tick_unit_turn_start(unit)

	# If this unit was hijacked at the top of its turn, force-drive it against its own
	# side. Deferred so executing a real move (which can end the turn and advance the
	# queue) runs after this turn-start call unwinds rather than re-entering it.
	if is_turn_forced_control(unit):
		call_deferred("_drive_controlled_units", [unit])


	# Find the player who owns this unit
	var owner_player = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner_player = player
			break

	# Emit turn started signal with the owning player
	if owner_player:
		turn_started.emit(owner_player)

	# Arm the per-unit move clock for a HUMAN unit's turn (no-op for AI / when off).
	# Done AFTER turn_started so the HUD has already re-synced to this unit before it
	# hears the arm. Never arm a freed/invalid unit.
	if unit != null and is_instance_valid(unit):
		_arm_turn_timer(unit, owner_player)

	var speed_info = str(get_unit_current_speed(unit))
	var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
	if get_unit_current_speed(unit) != base_speed:
		speed_info += " (base: " + str(base_speed) + ")"

# --- Move-clock (turn timer) helpers ---------------------------------------

## Arm the move clock for [param unit] IF it is a human-owned unit and the clock is
## enabled. AI-owned units (owner.is_ai, which also covers neutral factions) are never
## clocked -- BotTurnDriver already paces them. Clears any prior arming first, so this is
## safe to call unconditionally at every turn start.
func _arm_turn_timer(unit: Unit, owner_player) -> void:
	_disarm_turn_timer()
	if unit == null or owner_player == null or owner_player.is_ai:
		return
	var seconds: int = _configured_turn_timer_seconds()
	if seconds <= 0:
		return  # Clock OFF -- classic behaviour, no countdown.
	turn_timer_active = true
	turn_timer_unit = unit
	turn_timer_seconds = float(seconds)
	turn_timer_armed.emit(unit, turn_timer_seconds)

## Stop the move clock (idempotent). Emits [signal turn_timer_disarmed] only when a clock
## was actually running so the HUD isn't churned by no-op disarms.
func _disarm_turn_timer() -> void:
	if not turn_timer_active:
		return
	turn_timer_active = false
	turn_timer_unit = null
	turn_timer_seconds = 0.0
	turn_timer_disarmed.emit()

## The configured clock duration in seconds (0 = off). Reads the GameSettings autoload by
## its GLOBAL name (NOT get_node) because this system is not in the scene tree, so a path
## lookup would fail; the global identifier resolves regardless. Null-safe for headless
## tests that run without the autoload.
func _configured_turn_timer_seconds() -> int:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and "speed_turn_timer_seconds" in GameSettings:
		return int(GameSettings.speed_turn_timer_seconds)
	return 0

## Force-end the current unit's turn because its move clock ran out. Called by the in-tree
## TurnTimer HUD when its countdown reaches zero. Ends the turn EXACTLY like the End Turn
## button (end_turn_manually) and deliberately does NOT commit any staged tentative move --
## the UI owns that state and clears it off the turn_started/ended signals advance fires.
##
## Reentrancy / stale guard: only fires when [param unit] is still the armed, currently
## acting unit whose turn is in progress. If the unit already acted this same frame,
## advance_turn has disarmed the clock and moved on, so this is a harmless no-op -- the
## queue is never advanced twice.
func expire_turn_timer(unit: Unit) -> void:
	if not is_active or not turn_timer_active:
		return
	if unit == null or unit != turn_timer_unit or unit != current_acting_unit \
			or not is_turn_in_progress:
		return
	# Disarm + announce BEFORE advancing. advance_turn -> _end_unit_turn would disarm
	# anyway, but clearing here first makes a re-entrant expire_turn_timer a no-op.
	_disarm_turn_timer()
	turn_timer_expired.emit(unit)
	end_turn_manually()

func _end_unit_turn(unit: Unit) -> void:
	"""End a specific unit's turn"""
	if not unit or unit != current_acting_unit:
		return

	# Mark unit as having acted this round
	if unit not in units_acted_this_round:
		units_acted_this_round.append(unit)

	# Fire this unit's ON_TURN_END abilities (null-safe via the shared base helper).
	_tick_unit_turn_end(unit)

	# Find the player who owns this unit
	var owner_player = null
	for player in registered_players:
		if player.owns_unit(unit):
			owner_player = player
			break

	is_turn_in_progress = false

	# Stop this unit's move clock as its turn closes (covers action-completed, Wait,
	# End Turn, and the clock-expiry advance, which all route through here).
	_disarm_turn_timer()

	# Emit turn ended signal with the owning player
	if owner_player:
		turn_ended.emit(owner_player)

func _advance_to_next_unit() -> void:
	"""Advance to the next unit in the queue"""
	# Remove current unit from queue since they've acted
	if current_acting_unit in turn_queue:
		turn_queue.erase(current_acting_unit)

	# Check if we need to start a new round
	if turn_queue.is_empty():
		_start_new_round()
		return

	# Get next unit from queue (already sorted by speed)
	var next_unit = turn_queue[0]

	# Verify unit can still act
	if _is_unit_active(next_unit) and next_unit not in units_acted_this_round:
		_start_unit_turn(next_unit)
	else:
		# Unit can't act, remove from queue and try next
		turn_queue.erase(next_unit)
		if not turn_queue.is_empty():
			_advance_to_next_unit()
		else:
			_start_new_round()

func _start_new_round() -> void:
	"""Start a new round - all units can act again"""
	round_number += 1
	current_turn += 1  # Keep turn counter for compatibility

	# Update battle effects for new round
	if BattleEffectsManager:
		BattleEffectsManager.advance_round(round_number)

	# Clear acted units for new round
	units_acted_this_round.clear()

	# Recalculate turn queue with current speeds
	_calculate_turn_queue()

	_print_turn_queue()

	# Start with first unit in new queue
	if not turn_queue.is_empty():
		_start_unit_turn(turn_queue[0])
	else:
		_handle_no_valid_units()

func _handle_no_valid_units() -> void:
	"""Handle case where no units can act"""
	end_turn_system()

	# Notify game that turn system ended due to no valid units
	if PlayerManager:
		PlayerManager.end_game()

# Turn completion detection
func _check_turn_completion() -> void:
	"""Check if all units have acted this round"""
	var active_units = 0
	var acted_units = 0

	for unit in registered_units:
		if _is_unit_active(unit):
			active_units += 1
			if unit in units_acted_this_round:
				acted_units += 1

	if active_units > 0 and acted_units >= active_units:
		all_units_acted.emit()
		# Note: Don't auto-advance here, let the current unit finish their turn

# Unit action handling
func mark_unit_acted(unit: Unit) -> void:
	"""Mark a unit as having acted and advance turn"""
	if unit == current_acting_unit:
		advance_turn()

# Manual turn control
func end_turn_manually() -> bool:
	"""Manually end the current unit's turn"""
	if not is_active or not current_acting_unit or not is_turn_in_progress:
		return false

	advance_turn()
	return true

func can_end_turn_manually() -> bool:
	"""Check if the current unit's turn can be ended manually"""
	return is_active and current_acting_unit and is_turn_in_progress

# Override base class event handler
func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	super._on_unit_action_completed(unit, action_type)

	# Mark unit as having acted and advance turn
	mark_unit_acted(unit)

# Query methods
func get_current_acting_unit() -> Unit:
	"""Get the unit that is currently acting (null if it died/was freed mid-turn, so
	callers like the TurnQueue never dereference a freed instance)."""
	if current_acting_unit != null and not is_instance_valid(current_acting_unit):
		return null
	return current_acting_unit

func get_units_that_acted_this_round() -> Array[Unit]:
	"""Get units that have acted this round"""
	return units_acted_this_round.duplicate()

func get_units_remaining_this_round() -> Array[Unit]:
	"""Get units that haven't acted this round"""
	return turn_queue.duplicate()

func get_turn_queue() -> Array[Unit]:
	"""Get the current turn queue"""
	return turn_queue.duplicate()

func get_current_round_progress() -> Dictionary:
	"""Get information about current round progress"""
	var total_active_units = 0
	for unit in registered_units:
		if _is_unit_active(unit):
			total_active_units += 1

	var acted_units = units_acted_this_round.size()
	var remaining_units = turn_queue.size()

	return {
		"current_unit": current_acting_unit.get_display_name() if is_instance_valid(current_acting_unit) else "None",
		"current_unit_speed": get_unit_current_speed(current_acting_unit) if is_instance_valid(current_acting_unit) else 0,
		"round_number": round_number,
		"total_units": total_active_units,
		"units_acted": acted_units,
		"units_remaining": remaining_units,
		"round_complete": remaining_units == 0,
		"turn_queue_preview": _get_turn_queue_preview()
	}

func _get_turn_queue_preview() -> Array[Dictionary]:
	"""Get preview of upcoming turns for UI display.

	Every entry is validity-guarded: a unit killed during the very hand-off that
	triggered this refresh (attack -> mark_unit_acted -> advance -> turn_started ->
	TurnQueue._update_display) can still sit freed inside turn_queue for this one
	call, and dereferencing it hard-crashes the engine (caught by the soak harness
	in Speed First). Freed entries are skipped, not shown."""
	var preview: Array[Dictionary] = []
	var preview_count = min(5, turn_queue.size())  # Show next 5 units

	for i in range(preview_count):
		var unit = turn_queue[i]
		if unit == null or not is_instance_valid(unit):
			continue
		preview.append({
			"name": unit.get_display_name(),
			"speed": get_unit_current_speed(unit),
			"is_current": unit == current_acting_unit
		})

	return preview

# Public API for turn manipulation (future-proofing)
func refresh_unit_turn(unit: Unit) -> bool:
	"""Allow a unit to act again this round (for special abilities)"""
	if not is_active or not _is_unit_active(unit):
		return false

	# Remove unit from acted list if present
	if unit in units_acted_this_round:
		units_acted_this_round.erase(unit)

		# If this unit isn't in the current queue, add them back based on speed
		if unit not in turn_queue:
			_insert_unit_into_queue(unit)

		return true

	return false

func handle_unit_turn_refresh(unit: Unit) -> void:
	"""Handle turn refresh request from BattleEffectsManager"""
	if refresh_unit_turn(unit):
		pass

func _insert_unit_into_queue(unit: Unit) -> void:
	"""Insert a unit into the turn queue at the correct speed-based position"""
	if unit in turn_queue:
		return  # Already in queue

	var unit_speed = get_unit_current_speed(unit)
	var inserted = false

	# Find correct position based on speed (highest first)
	for i in range(turn_queue.size()):
		var queue_unit = turn_queue[i]
		var queue_speed = get_unit_current_speed(queue_unit)

		if unit_speed > queue_speed or (unit_speed == queue_speed and unit.get_display_name() < queue_unit.get_display_name()):
			turn_queue.insert(i, unit)
			inserted = true
			break

	# If not inserted, add to end
	if not inserted:
		turn_queue.append(unit)

func can_refresh_unit_turn(unit: Unit) -> bool:
	"""Check if a unit's turn can be refreshed"""
	return is_active and _is_unit_active(unit) and unit in units_acted_this_round

func get_units_eligible_for_refresh() -> Array[Unit]:
	"""Get all units that have acted and could have their turn refreshed"""
	var eligible: Array[Unit] = []
	for unit in units_acted_this_round:
		if _is_unit_active(unit):
			eligible.append(unit)
	return eligible

# Public API for speed modifications (delegates to BattleEffectsManager)
func apply_speed_buff(unit: Unit, buff_name: String, speed_increase: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed buff to a unit"""
	add_speed_modifier(unit, buff_name, speed_increase, duration_rounds, source)

func apply_speed_debuff(unit: Unit, debuff_name: String, speed_decrease: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed debuff to a unit"""
	add_speed_modifier(unit, debuff_name, -speed_decrease, duration_rounds, source)

func remove_speed_effect(unit: Unit, effect_name: String) -> bool:
	"""Remove a speed effect from a unit"""
	return remove_speed_modifier(unit, effect_name)

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
func reset_turn_system() -> void:
	"""Reset the turn system to initial state (for testing purposes)"""
	# Reset all state variables
	current_turn = 1
	round_number = 1
	is_turn_in_progress = false
	turn_queue.clear()
	units_acted_this_round.clear()
	current_acting_unit = null
	_disarm_turn_timer()
	# Drop per-turn tick / stun-skip bookkeeping: current_turn just rewound to 1, so
	# a stale entry from the previous battle's turn 1 would read as a live skip.
	clear_turn_tick_state()

	# Reset BattleEffectsManager
	if BattleEffectsManager:
		BattleEffectsManager.start_battle()  # This resets battle state

	# Reset all unit actions
	reset_all_unit_actions()

	# Recalculate turn queue and start first unit
	if not registered_units.is_empty():
		_calculate_turn_queue()
		if not turn_queue.is_empty():
			_start_unit_turn(turn_queue[0])

# Override debug info
func get_turn_system_info() -> Dictionary:
	"""Get detailed information about the speed first turn system state"""
	var base_info = super.get_turn_system_info()

	var active_effects_count = 0
	if BattleEffectsManager:
		var effects = BattleEffectsManager.get_all_active_effects()
		active_effects_count = effects.size()

	var speed_first_info = {
		"current_acting_unit": current_acting_unit.get_display_name() if is_instance_valid(current_acting_unit) else "None",
		"round_number": round_number,
		"turn_queue_size": turn_queue.size(),
		"units_acted_this_round": units_acted_this_round.size(),
		"active_battle_effects": active_effects_count,
		"round_progress": get_current_round_progress()
	}

	base_info.merge(speed_first_info)
	return base_info

func _to_string() -> String:
	"""String representation for debugging"""
	var unit_name = current_acting_unit.get_display_name() if is_instance_valid(current_acting_unit) else "No Unit"
	return system_name + " (Round " + str(round_number) + " - " + unit_name + ")"
