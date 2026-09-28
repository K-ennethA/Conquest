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
