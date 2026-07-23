extends AbilityCondition
class_name UndamagedForTurnsCondition

## Met once the unit has begun [member turns] consecutive turns WITHOUT taking damage.
## Backs "reward for staying untouched" powers -- the Gem Knight's Crystalline Ward
## grants its shield after the knight weathers a few turns unscathed.
##
## The streak lives on the unit's own [AbilitySystem] (`turns_since_damaged()`), which
## bumps it at each turn start and zeroes it the instant the unit is hit. Read duck-typed
## so the same condition works against a live unit and a bare test mock:
##   - a Unit exposes get_ability_system() -> the system's turns_since_damaged()
##   - a mock may itself expose turns_since_damaged()
## Fails closed (not met) when neither is available.

## Untouched turns required before the ability may fire.
@export var turns: int = 3


func is_met(unit, _board) -> bool:
	if unit == null:
		return false
	return _streak(unit) >= turns


func describe() -> String:
	return "undamaged for %d turns" % turns


func _streak(unit) -> int:
	if unit.has_method("get_ability_system"):
		var system = unit.get_ability_system()
		if system != null and system.has_method("turns_since_damaged"):
			return int(system.turns_since_damaged())
	if unit.has_method("turns_since_damaged"):
		return int(unit.turns_since_damaged())
	return 0
