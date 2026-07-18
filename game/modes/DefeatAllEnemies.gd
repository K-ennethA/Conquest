extends WinCondition
class_name DefeatAllEnemies

## MET once no living unit of a hostile faction remains.
##
## "Enemy" is any unit whose team differs from [member faction]. The classic
## skirmish objective.

## The friendly faction this objective is scored for.
@export var faction: int = 0


func evaluate(state: Dictionary) -> int:
	var units: Array = state.get("units", [])
	for u in units:
		if _team_of(u) != faction and _is_alive(u):
			return Status.ONGOING
	return Status.MET


func describe() -> String:
	return "Defeat every enemy unit"
