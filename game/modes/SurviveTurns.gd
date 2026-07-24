extends WinCondition
class_name SurviveTurns

## MET once [member turns] turns have elapsed. Optionally FAILED early if the
## defended faction is wiped out before the timer runs out.
##
## The "hold out" objective. Pairs naturally with a lose condition so being
## overrun before the clock ends counts as a defeat.

## Number of turns that must elapse.
@export var turns: int = 5
## The faction that must still exist when checking survival.
@export var faction: int = 0
## If true, losing every unit of [member faction] fails the objective immediately.
@export var require_survivor: bool = true


func evaluate(state: Dictionary) -> int:
	if require_survivor and not _faction_has_survivor(state):
		return Status.FAILED
	if int(state.get("turn", 0)) >= turns:
		return Status.MET
	return Status.ONGOING


func describe() -> String:
	return "Survive for %d turns" % turns


func _faction_has_survivor(state: Dictionary) -> bool:
	for u in state.get("units", []):
		if _team_of(u) == faction and _is_alive(u):
			return true
	return false
