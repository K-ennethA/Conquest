extends AbilityCondition
class_name AnyCondition

## Met when AT LEAST ONE child condition is met — the OR of a list.
##
## The counterpart to [AllCondition]: "on water OR on lava" needs no new class,
## just two [OnTerrainCondition]s nested here. Children may themselves be
## composites (an [AnyCondition] of [AllCondition]s expresses any sum of products).
##
## Null children are skipped, and an empty list is met — matching [AllCondition]
## and the permissive base class, so an unfinished composite never blocks an
## ability outright.

@export var conditions: Array[AbilityCondition] = []


func is_met(unit, board) -> bool:
	var considered := false
	for cond in conditions:
		if cond == null:
			continue
		considered = true
		if cond.is_met(unit, board):
			return true
	return not considered


func describe() -> String:
	var parts: Array[String] = []
	for cond in conditions:
		if cond != null:
			parts.append(cond.describe())
	if parts.is_empty():
		return "always"
	return " or ".join(parts)
