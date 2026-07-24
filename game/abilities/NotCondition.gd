extends AbilityCondition
class_name NotCondition

## Met exactly when its child condition is NOT met — the inverse of one condition.
##
## Completes the composition set alongside [AllCondition] and [AnyCondition], so
## negative requirements ("while NOT on water", "while NOT wounded") are authored
## by wrapping an existing condition instead of adding an inverted twin of every
## class.
##
## A null child is treated as the permissive always-met condition, so inverting it
## yields false — an unfinished [NotCondition] is inert rather than a blanket pass.

@export var condition: AbilityCondition


func is_met(unit, board) -> bool:
	if condition == null:
		return false  # not(always) == never
	return not condition.is_met(unit, board)


func describe() -> String:
	if condition == null:
		return "never"
	return "not %s" % condition.describe()
