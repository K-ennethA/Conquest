extends AbilityCondition
class_name AlwaysCondition

## The trivial condition: the ability is always eligible. Explicit stand-in for
## "no condition", so unconditional abilities read clearly in the inspector.


func is_met(_unit, _board) -> bool:
	return true


func describe() -> String:
	return "always"
