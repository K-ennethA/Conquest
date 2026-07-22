extends AugmentEffect
class_name ExtraActionEffect

## Grants a unit extra ACTIONS per turn -- the "move/act twice per turn" augment. Sets the
## unit's arena_extra_actions budget, which Unit.mark_action_completed consumes: while the
## budget lasts the unit doesn't end its turn on acting (and its move refreshes), so it can
## be commanded again. Isolated by design -- only units carrying this grant are affected.

## How many additional actions per turn (1 = act twice, 2 = three times, ...).
@export var extra_actions: int = 1


func apply_to_unit(unit, _run) -> void:
	if unit == null or extra_actions == 0:
		return
	if "arena_extra_actions" in unit:
		unit.arena_extra_actions += extra_actions


func describe() -> String:
	if extra_actions == 1:
		return "Act twice per turn"
	return "Take %d extra actions per turn" % extra_actions
