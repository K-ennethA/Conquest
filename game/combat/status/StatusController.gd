extends Node
class_name StatusController

## Per-unit component that owns the unit's active [StatusCondition]s and advances
## them each turn.
##
## Attach one to a unit (or hold one on a mock in tests). Moves/tiles/abilities
## inflict conditions through [method add_status]; the turn system calls
## [method tick_all] once per turn to fire tick effects, decrement durations, and
## expire finished conditions. Ordering is deterministic (insertion order), so
## networked peers and replays resolve identically.

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
				existing.turns_left = condition.duration_turns
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
					existing.turns_left = condition.duration_turns
					return existing
				# Otherwise fall out of the match and add another instance.
	var instance: StatusCondition = condition.duplicate(true)
	instance.turns_left = instance.duration_turns
	_active.append(instance)
	instance.on_apply(_target(), _board())
	_announce(&"status_applied", instance)
	return instance


## Advance every active condition by one turn: apply tick effects, decrement
## finite durations, and expire any that reach 0 (firing on_expire). Permanent
## conditions (-1) tick forever. [param board] is the standard board adapter.
## Returns the combined tick event log.
func tick_all(board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var survivors: Array[StatusCondition] = []
	for condition in _active:
		var tick_events: Array[Dictionary] = condition.tick(_target(), board)
		for e in tick_events:
			events.append(e)
		# AFTER the tick resolved, so the damage_dealt / unit_healed it produced have
		# already been announced and the presentation layer can attribute them here.
		_announce(&"status_ticked", condition, tick_events)
		if condition.turns_left > 0:
			condition.turns_left -= 1
		if condition.turns_left == 0:
			condition.on_expire(_target(), board)
			_announce(&"status_expired", condition)
		else:
			survivors.append(condition)
	_active = survivors
	return events


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


## The single most-protective [member StatusCondition.damage_taken_scale] across
## every active condition -- i.e. the MINIMUM scale (1.0 when none carries one).
##
## DELIBERATELY "TAKE THE STRONGEST", NOT A PRODUCT OR A SUM. Compounding two
## same-kind reductions would let a unit re-cast its way to near-invulnerability
## (0.6 * 0.6 = 0.36), and summing is the additive-merge bug the passive side warns
## about. Exactly one reduction applies -- the best one in force -- so stacking timed
## defensive buffs can refresh but never deepen. [DamageEffect.damage_taken_scale_for]
## combines THIS single status scale with the defender's single passive scale
## (passive x status), which is one of each source, not compounding one source.
func status_damage_taken_scale() -> float:
	var best: float = 1.0
	for condition in _active:
		if condition == null:
			continue
		var scale: float = maxf(0.0, condition.damage_taken_scale)
		if scale < best:
			best = scale
	return best


## Remove every live instance of [param condition_id], firing each on_expire hook.
## Returns how many were removed (0 if none were present). Used by effects that
## CONSUME a status -- e.g. the infection promoting to control clears the counter it
## spent. [param board] is optional (passed to on_expire).
func remove_status(condition_id: StringName, board = null) -> int:
	var survivors: Array[StatusCondition] = []
	var removed: int = 0
	for condition in _active:
		if condition != null and condition.id == condition_id:
			condition.on_expire(_target(), board)
			_announce(&"status_expired", condition)
			removed += 1
		else:
			survivors.append(condition)
	_active = survivors
	return removed


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
