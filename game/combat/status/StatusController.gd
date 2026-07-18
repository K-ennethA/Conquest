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
				pass  # fall through and add a second instance
	var instance: StatusCondition = condition.duplicate(true)
	instance.turns_left = instance.duration_turns
	_active.append(instance)
	instance.on_apply(_target(), _board())
	return instance


## Advance every active condition by one turn: apply tick effects, decrement
## finite durations, and expire any that reach 0 (firing on_expire). Permanent
## conditions (-1) tick forever. [param board] is the standard board adapter.
## Returns the combined tick event log.
func tick_all(board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var survivors: Array[StatusCondition] = []
	for condition in _active:
		for e in condition.tick(_target(), board):
			events.append(e)
		if condition.turns_left > 0:
			condition.turns_left -= 1
		if condition.turns_left == 0:
			condition.on_expire(_target(), board)
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


## Remove every condition, firing each on_expire hook. [param board] is optional.
func clear(board = null) -> void:
	for condition in _active:
		condition.on_expire(_target(), board)
	_active = []


func _find_by_id(condition_id: StringName) -> StatusCondition:
	for condition in _active:
		if condition.id == condition_id:
			return condition
	return null


func _target():
	return owner_unit if owner_unit != null else get_parent()


func _board():
	return null
