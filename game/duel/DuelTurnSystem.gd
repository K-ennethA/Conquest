extends SpeedFirstTurnSystem
class_name DuelTurnSystem

## The duel's turn order (docs/design/DUEL_BATTLE.md §4.1): SEQUENTIAL speed order -- each
## round both combatants act once, faster first, re-sorted every round by CURRENT speed (so
## Stone Sling's slow flips the order). Everything else is [SpeedFirstTurnSystem] unchanged:
## the per-unit turn-start ticks (weather, stun / control latch, stat-mod expiry, cooldowns,
## statuses, ON_TURN_START), ON_BATTLE_START, and turn_started / turn_ended for rule-2
## listeners.
##
## Three duel differences:
## - SEEDED TIE-BREAK. Speed First breaks ties by display name, which is unstable in a mirror
##   match. Here a speed tie is decided by a per-round key hashed from the duel seed, the round
##   and the unit's stable id: a coin flip per round that is identical on every replay.
## - NO MOVE CLOCK unless the ruleset asks for one (PvP only).
## - THE DUEL DRIVES FORCED CONTROL ITSELF. A controlled (Enthralled) unit has no ally to turn
##   on in 1v1, so control acts as a stun; the owning [DuelBattle] spends that turn with a WAIT
##   command (synchronous and recorded) instead of the deferred tactical drive.
## And once the duel is DECIDED (a side has no living combatant) the queue never advances
## again, so nothing ticks after the KO.

## Domain salt for the tie-break keys (separate from every combat roll).
const _SALT_TIE := 0x546965427265616B  # "TieBreak"

## The duel seed the tie-break keys are hashed from.
var tie_seed: int = 0
## Move-clock seconds for human turns (0 = off).
var timer_seconds: int = 0


func _init() -> void:
	super._init()
	system_name = "Duel Turn System"


## The tie-break key of [param unit] in [param round_no]: a pure function of the seed, the
## round and the unit's stable id (NetUnitIds), so it is identical on every run.
func tie_key(unit, round_no: int) -> int:
	var id: String = NetUnitIds.id_of(unit)
	if id == "" and unit != null and unit.has_method("get_display_name"):
		id = unit.get_display_name()
	return MatchRng._mix([_SALT_TIE, tie_seed, round_no, hash(id)])


func _compare_unit_current_speed(unit_a: Unit, unit_b: Unit) -> bool:
	var speed_a := get_unit_current_speed(unit_a)
	var speed_b := get_unit_current_speed(unit_b)
	if speed_a != speed_b:
		return speed_a > speed_b
	var ka := tie_key(unit_a, round_number)
	var kb := tie_key(unit_b, round_number)
	if ka != kb:
		return ka > kb
	return NetUnitIds.id_of(unit_a) < NetUnitIds.id_of(unit_b)


## Keep the order stable when a unit is re-inserted mid-round (refresh_unit_turn).
func _insert_unit_into_queue(unit: Unit) -> void:
	if unit in turn_queue:
		return
	for i in range(turn_queue.size()):
		if _compare_unit_current_speed(unit, turn_queue[i]):
			turn_queue.insert(i, unit)
			return
	turn_queue.append(unit)


func _configured_turn_timer_seconds() -> int:
	return timer_seconds


## Control is resolved by the duel (a WAIT); never the tactical planner.
func _drive_controlled_units(_units: Array) -> void:
	pass


## Never advance a finished or decided duel (a deferred hand-off after the KO must not open
## the survivor's turn and tick its statuses after the result).
func _advance_to_next_unit() -> void:
	if not is_active or is_decided():
		return
	super._advance_to_next_unit()


func _start_new_round() -> void:
	if not is_active or is_decided():
		return
	super._start_new_round()


## A death never schedules a deferred hand-off here: the owning [DuelBattle] resolves every
## faint (a KO replacement pick, or the end of the duel) and then resumes the queue itself
## ([method resume_if_idle]). A deferred advance would race a replacement that arrives in the
## same frame (an AI pick) or many frames later (an online pick) -- and advance twice.
func _on_registered_unit_died(unit: Unit) -> void:
	var was_acting := unit != null and unit == current_acting_unit
	if unit != null and is_instance_valid(unit) and unit in registered_units:
		unregister_unit(unit)
	if unit != null and unit in turn_queue:
		turn_queue.erase(unit)
	if was_acting:
		_disarm_turn_timer()
		current_acting_unit = null
		is_turn_in_progress = false


# --- Party duels: switching (docs/design/DUEL_BATTLE.md §4.2) ---------------------------
#
# ORDERING. A switch is an ACTION in the sequential speed order: it resolves in the switching
# combatant's own turn slot, exactly where its move would have. The outgoing combatant's turn
# ENDS normally (its turn-end beat and affliction clocks run), it leaves the queue, and the
# incoming one joins the system already marked as having acted this round -- it takes the next
# round's order by its own speed. A KO REPLACEMENT is free and immediate: it enters before any
# other turn opens, likewise marked acted (the fainted combatant's turn this round is lost),
# and then the queue resumes.

## The acting [param out_unit] spends its turn on a switch: its turn ends (turn-end beat) and it
## leaves the system. The caller brings the incoming unit in, then calls [method advance_after_switch].
func retire_for_switch(out_unit: Unit) -> void:
	if out_unit == null or not is_instance_valid(out_unit):
		return
	if out_unit == current_acting_unit and is_turn_in_progress:
		_end_unit_turn(out_unit)
	if out_unit in registered_units:
		unregister_unit(out_unit)
	if out_unit != current_acting_unit:
		turn_queue.erase(out_unit)


## Register [param unit] (an incoming party member) WITHOUT the idle kickoff Speed First
## schedules for late arrivals, marked as having acted this round.
func adopt_incoming(unit: Unit) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var queued := _kickoff_queued
	_kickoff_queued = true   # suppress SpeedFirstTurnSystem.register_unit's deferred kickoff
	register_unit(unit)
	_kickoff_queued = queued
	if not (unit in units_acted_this_round):
		units_acted_this_round.append(unit)
	turn_queue.erase(unit)


## After a voluntary switch applied: hand the turn on (synchronously, like any spent action).
func advance_after_switch() -> void:
	if not is_active or is_turn_in_progress:
		return
	_advance_to_next_unit()


## Open the next turn when none is in progress (after a KO replacement, or once the action
## that caused a faint has resolved). A no-op while a turn is open or the duel is decided.
func resume_if_idle() -> void:
	if not is_active or is_decided() or is_turn_in_progress:
		return
	_advance_to_next_unit()


## True once fewer than two sides still field a living, registered combatant.
func is_decided() -> bool:
	var sides: Dictionary = {}
	for unit in registered_units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.has_method("is_alive") and not unit.is_alive():
			continue
		var owner = unit.get_owner_player() if unit.has_method("get_owner_player") else null
		if owner != null:
			sides[owner] = true
	return sides.size() < 2


## The current round (1-based), for the HUD.
func current_round() -> int:
	return round_number
