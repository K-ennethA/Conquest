extends WinCondition
class_name ProtectUnit

## A standing objective: FAILED the moment the protected unit dies or leaves the
## field, ONGOING while it lives.
##
## On its own it never reports MET -- it is meant to sit alongside another win
## condition (e.g. [SurviveTurns] or [DefeatAllEnemies]) so the escort must be
## kept alive to win, or to be listed as a lose condition's counterpart. Because
## a violation returns FAILED, [GameModeRules] turns its death into a defeat.

## Identifier of the unit that must be kept alive.
@export var protected_id: StringName = &""


func evaluate(state: Dictionary) -> int:
	for u in state.get("units", []):
		if _unit_id(u) == protected_id:
			return Status.ONGOING if _is_alive(u) else Status.FAILED
	# The unit is no longer in play: treat as lost.
	return Status.FAILED


func describe() -> String:
	return "Keep %s alive" % protected_id
