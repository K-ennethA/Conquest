extends Node
class_name MovesetController

## Per-unit component that tracks move availability: cooldown-remaining and
## uses-left, keyed by [member MoveResource.move_id].
##
## The turn system calls [method tick_cooldowns] once per turn to count cooldowns
## down; the action system calls [method can_use] before offering a move and
## [method on_used] after resolving one. Respects both [member MoveResource.cooldown]
## and [member MoveResource.max_uses] (-1 = unlimited). Deterministic and
## side-effect free apart from the two tracking dictionaries.

## move_id -> remaining cooldown turns (0 = ready).
var _cooldowns: Dictionary = {}
## move_id -> uses already spent this battle.
var _uses_spent: Dictionary = {}


## True if [param move] can be used right now: not on cooldown and not out of
## charges. A null/invalid move is never usable.
func can_use(move: MoveResource) -> bool:
	if move == null:
		return false
	if remaining(move) > 0:
		return false
	if move.max_uses >= 0 and _spent(move.move_id) >= move.max_uses:
		return false
	return true


## Record that [param move] was used: spend a charge and start its cooldown.
func on_used(move: MoveResource) -> void:
	if move == null:
		return
	_uses_spent[move.move_id] = _spent(move.move_id) + 1
	if move.cooldown > 0:
		_cooldowns[move.move_id] = move.cooldown


## Count every active cooldown down by one turn. Call once per turn.
func tick_cooldowns() -> void:
	for move_id in _cooldowns.keys():
		var left: int = _cooldowns[move_id]
		if left > 0:
			_cooldowns[move_id] = left - 1


## Cooldown turns still remaining on [param move] (0 = ready).
func remaining(move: MoveResource) -> int:
	if move == null:
		return 0
	return int(_cooldowns.get(move.move_id, 0))


## Charges left before [param move] hits [member MoveResource.max_uses].
## Returns -1 for unlimited moves.
func uses_left(move: MoveResource) -> int:
	if move == null or move.max_uses < 0:
		return -1
	return maxi(0, move.max_uses - _spent(move.move_id))


## Forget all cooldown/use tracking (e.g. at the start of a new battle).
func reset() -> void:
	_cooldowns.clear()
	_uses_spent.clear()


func _spent(move_id: StringName) -> int:
	return int(_uses_spent.get(move_id, 0))
