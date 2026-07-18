extends AbilityCondition
class_name HealthBelowCondition

## Met while the unit's current health is below [member threshold] (a fraction of
## its maximum) — the backbone of "desperate" powers like last-stand defense or a
## berserk damage boost.
##
## Current and maximum health are read duck-typed so the same condition works
## against a live unit and a test mock:
##   current — a [code]hp[/code] property if present, else stat "current_health",
##             else stat "health".
##   maximum — stat "max_health" if > 0, else stat "health".
## If maximum can't be determined (0), the condition fails closed.

## Fraction of maximum health, in (0..1]. Health strictly below this is "wounded".
@export_range(0.0, 1.0, 0.01) var threshold: float = 0.3


func is_met(unit, board) -> bool:
	if unit == null:
		return false
	var max_health := _max_health(unit)
	if max_health <= 0:
		return false
	return float(_current_health(unit)) / float(max_health) < threshold


func describe() -> String:
	return "health below %d%%" % int(round(threshold * 100.0))


func _current_health(unit) -> int:
	if "hp" in unit:
		return int(unit.hp)
	if unit.has_method("get_stat"):
		var cur := int(unit.get_stat("current_health"))
		if cur > 0:
			return cur
		return int(unit.get_stat("health"))
	return 0


func _max_health(unit) -> int:
	if unit.has_method("get_stat"):
		var m := int(unit.get_stat("max_health"))
		if m > 0:
			return m
		return int(unit.get_stat("health"))
	return 0
