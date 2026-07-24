extends AbilityCondition
class_name AllCondition

## Met only when EVERY child condition is met — the AND of a list.
##
## Composition is what keeps the condition family small: "below 30% health AND
## standing on sacred ground" is authored by nesting a [HealthBelowCondition] and
## an [OnTerrainCondition] here, rather than by writing a bespoke class for each
## pairing. Children may themselves be composites, so arbitrary expressions are
## inspector-authorable.
##
## Null children are skipped (they contribute nothing), and an empty list is met —
## "no requirements" matches the permissive base class, so a half-authored
## composite never silently disables an ability.

@export var conditions: Array[AbilityCondition] = []


func is_met(unit, board) -> bool:
	for cond in conditions:
		if cond != null and not cond.is_met(unit, board):
			return false
	return true


func describe() -> String:
	var parts: Array[String] = []
	for cond in conditions:
		if cond != null:
			parts.append(cond.describe())
	if parts.is_empty():
		return "always"
	return " and ".join(parts)
