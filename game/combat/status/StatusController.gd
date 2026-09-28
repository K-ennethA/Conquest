extends Node
class_name StatusController

## Per-unit component that owns the unit's active [StatusCondition]s and advances
## them each turn.
##
## Attach one to a unit (or hold one on a mock in tests). Moves/tiles/abilities
## inflict conditions through [method add_status]; the turn system calls
## [method tick_all] as the unit's turn OPENS (fire tick effects, count down and expire
## the PROTECTIVE conditions) and [method tick_turn_end] as it CLOSES (count down and
## expire the AFFLICTIONS the unit just played a turn under). Which clock an instance
## runs on is resolved when it lands -- see [enum StatusCondition.Clock] and CONQUEST.md
## rule 6a. Ordering is deterministic (insertion order), so networked peers and replays
## resolve identically.

## The unit these conditions are attached to. The controller passes it as the
## affected target when ticking. Defaults to the parent node if unset.
var owner_unit


func _ready() -> void:
	if owner_unit == null:
		owner_unit = get_parent()


var _active: Array[StatusCondition] = []


## Add a condition to the unit. The stored instance is always a duplicate so the
## shared authoring resource is never mutated. Honors the incoming condition's
## [member StatusCondition.stacking] rule against any active condition with the
## same [member StatusCondition.id]. Returns the live instance now tracked (the
## existing one for REFRESH/IGNORE), or null if nothing was added.
func add_status(condition: StatusCondition) -> StatusCondition:
	if condition == null:
		return null
	var existing := _find_by_id(condition.id)
	if existing != null:
		match condition.stacking:
			StatusCondition.Stacking.REFRESH:
				_refresh(existing, condition)
				return existing
			StatusCondition.Stacking.IGNORE:
				return existing
			StatusCondition.Stacking.STACK:
				if _stack_cap_reached(condition):
					# At the severity ceiling. Refresh the OLDEST instance rather
					# than dropping the application on the floor: re-applying a
					# maxed poison keeps it alive on the target, it just cannot
					# make it any worse. _find_by_id returns the first (oldest)
					# match, so this is also the instance about to expire.
					_refresh(existing, condition)
					return existing
				# Otherwise fall out of the match and add another instance.
	var instance: StatusCondition = condition.duplicate(true)
	instance.turns_left = instance.duration_turns
	# duplicate() carries only STORED (exported) properties, so the applier -- runtime
	# state, like turns_left -- has to be re-stated onto the stored copy or every kill
	# by a status tick would go unattributed. See StatusCondition._source_ref.
	instance.set_source(condition.get_source())
	instance.inflicted_by_environment = condition.inflicted_by_environment
	# The clock is decided HERE, once, as it lands (and again on every refresh): who
	# inflicted it is only knowable now. No turn of the unit's has been opened under it
	# yet, so the turn in progress (if any) never counts toward an affliction.
	instance.counts_own_turns = condition.resolve_clock(_target())
	instance.own_turn_open = false
	_active.append(instance)
	instance.on_apply(_target(), _board())
	_announce(&"status_applied", instance)
	return instance


## The unit's turn is OPENING: fire every active condition's tick effects, then count
## down and expire the PROTECTIVE ones (firing on_expire). AFFLICTIONS are only marked
## as having a turn open under them here -- they count down at that turn's END, in
## [method tick_turn_end]. Permanent conditions (-1) tick forever. [param board] is the
## standard board adapter. Returns the combined tick event log.
##
## Tick COUNTS are identical on both clocks: an N-turn condition fires N ticks. A
## protective one fires on its N turn starts and lapses on the Nth; an affliction fires
## on the N turn starts it is in force for and lapses as the Nth of those turns ends.
##
## A MISSED TURN END IS COUNTED HERE. An affliction still flagged open from a previous
## turn never had that turn's end counted (a turn system that re-opened the same side
## without closing it, a caller that only drives turn starts). That turn WAS played under
## it, so it is counted now, before this turn opens -- which is also what keeps a
## start-only driver firing exactly N ticks rather than N+1.
##
## RE-ENTRANCY: an on_expire hook may itself change this list -- [EnthralledStatus]
## clears the host's leftover infestation as control lapses, which calls
## [method remove_status] from inside this loop. So the list is edited IN PLACE (each
## expiring condition is erased before its hook runs) and iterated over a SNAPSHOT,
## rather than rebuilt from a survivors list at the end: rebuilding would resurrect
## exactly the conditions a hook had just removed.
func tick_all(board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for condition in _active.duplicate():
		if condition == null or not (condition in _active):
			continue  # an earlier expiry hook already took this one off the unit
		if condition.counts_own_turns and condition.own_turn_open:
			condition.own_turn_open = false
			if _count_down(condition, board):
				continue  # its last turn was the one whose end was never counted
		var tick_events: Array[Dictionary] = condition.tick(_target(), board)
		for e in tick_events:
			events.append(e)
		# AFTER the tick resolved, so the damage_dealt / unit_healed it produced have
		# already been announced and the presentation layer can attribute them here.
		_announce(&"status_ticked", condition, tick_events)
		if condition.counts_own_turns:
			condition.own_turn_open = true
		else:
			_count_down(condition, board)
	return events


## The unit's turn is CLOSING: count down every AFFLICTION the unit opened this turn
## under, expiring any that reach 0 (firing on_expire). An affliction that landed during
## this turn was never opened, so it is untouched -- the turn it arrived in is not one of
## its N. PROTECTIVE conditions ignore this beat entirely. Idempotent by construction: a
## second call finds nothing open. [param board] may be null (on_expire hooks accept it).
func tick_turn_end(board = null) -> void:
	for condition in _active.duplicate():
		if condition == null or not (condition in _active):
			continue
		if not condition.counts_own_turns or not condition.own_turn_open:
			continue
		condition.own_turn_open = false
		_count_down(condition, board)


## Take one turn off [param condition]; at 0 erase it (BEFORE its hook -- see the
## re-entrancy note on [method tick_all]), fire on_expire and announce it. Permanent (-1)
## conditions never reach 0. Returns true when it expired.
func _count_down(condition: StatusCondition, board) -> bool:
	if condition.turns_left > 0:
		condition.turns_left -= 1
	if condition.turns_left != 0:
		return false
	_active.erase(condition)
	condition.on_expire(_target(), board)
	_announce(&"status_expired", condition)
	return true


## Live conditions currently on the unit (the controller's own instances).
func get_active() -> Array[StatusCondition]:
	return _active


## True if a condition with [param condition_id] is active.
func has_status(condition_id: StringName) -> bool:
	return _find_by_id(condition_id) != null


## How many independent instances of [param condition_id] are live on the unit.
##
## 0 when absent and 1 for an ordinary REFRESH/IGNORE condition; for a
## [constant StatusCondition.Stacking.STACK] one this is its current SEVERITY, and
## it is what the status UI reads to render "Poisoned x3" rather than three
## identical badges. Exposed here (instead of leaving every caller to count
## [method get_active] itself) so severity has exactly one definition.
func stack_count(condition_id: StringName) -> int:
	var count: int = 0
	for condition in _active:
		if condition != null and condition.id == condition_id:
			count += 1
	return count


## Condition id -> live instance count, in first-applied order. The whole-unit
## version of [method stack_count], for debug/UI that renders the full list.
func stacks_by_id() -> Dictionary:
	var counts: Dictionary = {}
	for condition in _active:
		if condition == null:
			continue
		counts[condition.id] = int(counts.get(condition.id, 0)) + 1
	return counts


## True if ANY active condition sets [param flag_name] in its
## [member StatusCondition.rule_flags] (values OR together, mirroring how
## [method AbilitySystem.passive_modifiers] merges boolean rule modifiers).
##
## This is how a status expresses "your rules differ" without applying anything:
## [method Unit.can_move] asks for [code]&"immobilized"[/code], and any other
## system can ask for its own flag without this controller knowing about it.
func has_rule_flag(flag_name: StringName) -> bool:
	for condition in _active:
		if condition == null or condition.rule_flags.is_empty():
			continue
		# Author the key as a plain String in the inspector; accept either form.
		if bool(condition.rule_flags.get(String(flag_name), false)):
			return true
		if bool(condition.rule_flags.get(flag_name, false)):
			return true
	return false


## What this unit's active conditions multiply incoming damage by: the single
## most-protective REDUCTION in force times the single most-dangerous
## VULNERABILITY in force (1.0 for either side when nothing carries one).
##
## DELIBERATELY "TAKE THE STRONGEST" ON EACH SIDE, NEVER A PRODUCT OR A SUM WITHIN A
## SIDE. Compounding two same-kind reductions would let a unit re-cast its way to
## near-invulnerability (0.6 * 0.6 = 0.36), and summing is the additive-merge bug the
## passive side warns about. Exactly one reduction applies -- the best one in force --
## so stacking timed defensive buffs can refresh but never deepen, and exactly one
## vulnerability applies for the mirrored reason: two brands must never multiply into
## x1.69. [DamageEffect.damage_taken_scale_for] then combines THIS single status number
## with the defender's single passive scale (passive x status), which is one of each
## source rather than compounding one source.
##
## THE TWO SIDES DO MULTIPLY EACH OTHER, and that is the point rather than an oversight:
## a reduction and a vulnerability are OPPOSING effects from different sources, and
## "braced but branded" has to be able to land between the two. Reducing them to a single
## min/max would let whichever was authored louder silently erase the other.
##
## The vulnerability half was appended: with no condition above 1.0 this returns the
## MINIMUM exactly as it always did, so every status authored before brands existed reads
## back an unchanged number.
func status_damage_taken_scale() -> float:
	var best_reduction: float = 1.0
	var worst_vulnerability: float = 1.0
	for condition in _active:
		if condition == null:
			continue
		var scale: float = maxf(0.0, condition.damage_taken_scale)
		if scale < best_reduction:
			best_reduction = scale
		elif scale > worst_vulnerability:
			worst_vulnerability = scale
	return best_reduction * worst_vulnerability


## Remove every live instance of [param condition_id], firing each on_expire hook.
## Returns how many were removed (0 if none were present). Used by effects that
## CONSUME a status -- e.g. the infection promoting to control clears the counter it
## spent. [param board] is optional (passed to on_expire).
func remove_status(condition_id: StringName, board = null) -> int:
	# Erased BEFORE its hook runs, for the same re-entrancy reason [method tick_all]
	# documents: an on_expire may remove further conditions, and a survivors list built
	# up here would put them back.
	var doomed: Array[StatusCondition] = []
	for condition in _active:
		if condition != null and condition.id == condition_id:
			doomed.append(condition)
	for condition in doomed:
		_active.erase(condition)
	for condition in doomed:
		condition.on_expire(_target(), board)
		_announce(&"status_expired", condition)
	return doomed.size()


## Every rule flag currently set to true across the active conditions. Handy for
## debug/UI ("why can't this unit move?"); the hot path is [method has_rule_flag].
func active_rule_flags() -> Dictionary:
	var merged: Dictionary = {}
	for condition in _active:
		if condition == null:
			continue
		for key in condition.rule_flags:
			merged[key] = bool(merged.get(key, false)) or bool(condition.rule_flags[key])
	return merged


## Remove every condition, firing each on_expire hook. [param board] is optional.
func clear(board = null) -> void:
	for condition in _active:
		condition.on_expire(_target(), board)
		_announce(&"status_expired", condition)
	_active = []


## Announce a status lifecycle beat on the game-wide bus, for the PRESENTATION layer
## only (floating "POISONED" labels, tick numbers in the status' own colour, the pips
## on the world-space health bar). Nothing in the combat layer subscribes, so this is
## purely additive: with no bus, no signal, or no listener, ticking is byte-identical.
##
## Guarded end to end on purpose -- this controller runs headless in ~a dozen unit
## suites where the GameEvents autoload is absent, and a cosmetic announce must never
## be able to fail a mechanics test.
func _announce(signal_name: StringName, condition, events = null) -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	if not GameEvents.has_signal(signal_name):
		return
	if events == null:
		GameEvents.emit_signal(signal_name, _target(), condition)
	else:
		GameEvents.emit_signal(signal_name, _target(), condition, events)


## Re-apply [param incoming] onto the already-live [param existing] instance: reset the
## timer, and hand the instance to the NEW applier.
##
## Re-attributing is the deliberate half. The refresh rule says a second source must not
## deepen the effect -- it says nothing about who owns the kill, and "the last unit to
## top up the poison owns what it does from now on" is the only answer that does not
## require tracking one timer per source. It also self-heals attribution: a poison whose
## original applier has died credits nobody until somebody re-applies it.
##
## The CLOCK follows the same rule for the same reason: the refresh is a fresh application
## by the new applier, so its clock is re-resolved from that applier, and an affliction's
## fresh N counts from the unit's next turn -- a turn already open when the refresh lands
## is not one of the new N (CONQUEST.md rule 6a).
func _refresh(existing: StatusCondition, incoming: StatusCondition) -> void:
	existing.turns_left = incoming.duration_turns
	existing.set_source(incoming.get_source())
	existing.inflicted_by_environment = incoming.inflicted_by_environment
	existing.counts_own_turns = incoming.resolve_clock(_target())
	existing.own_turn_open = false


## True when [param condition] is already at its
## [member StatusCondition.max_stacks] ceiling on this unit. A negative cap (the
## default) is unbounded and never reached, which is exactly how STACK behaved
## before the cap existed. A mis-authored 0 is read as 1 so a condition can always
## land at least once.
func _stack_cap_reached(condition: StatusCondition) -> bool:
	var cap: int = condition.max_stacks
	if cap < 0:
		return false
	return stack_count(condition.id) >= maxi(1, cap)


func _find_by_id(condition_id: StringName) -> StatusCondition:
	for condition in _active:
		if condition.id == condition_id:
			return condition
	return null


func _target():
	return owner_unit if owner_unit != null else get_parent()


func _board():
	return null
