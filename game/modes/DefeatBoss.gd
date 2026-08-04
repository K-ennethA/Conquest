extends WinCondition
class_name DefeatBoss

## MET once no living BOSS unit on a hostile faction remains.
##
## The "kill the commander" objective: the battle is won the instant every enemy
## boss is dead, EVEN IF ordinary enemies (grunts, summons, parasites) are still on
## the field. "Enemy" is any unit whose team differs from [member faction]; boss-ness
## is duck-typed (see [method _is_boss]).
##
## Edge case -- a map with NO enemy boss at all resolves [constant Status.ONGOING],
## never an instant win. The distinction "the boss is dead" vs "there was never a
## boss" is made by whether the [param state] still carries a boss unit: a just-slain
## boss is a boss unit that is no longer alive (MET), whereas a bossless map presents
## no boss unit at all (ONGOING). The live wiring re-adds the just-eliminated unit to
## the state so the death is observable on the very tick it happens.

## The friendly faction this objective is scored for.
@export var faction: int = 0


func evaluate(state: Dictionary) -> int:
	var units: Array = state.get("units", [])
	var saw_enemy_boss := false
	for u in units:
		if _team_of(u) == faction:
			continue
		if not _is_boss(u):
			continue
		saw_enemy_boss = true
		if _is_alive(u):
			return Status.ONGOING
	# No LIVING enemy boss remains. If we never saw a boss at all, this map has no
	# boss to defeat -- stay ONGOING so it can never be won by default.
	if not saw_enemy_boss:
		return Status.ONGOING
	return Status.MET


func describe() -> String:
	return "Defeat the boss"


## "Defeat Eldroot the Hollow Crown" while that boss is still standing, falling back to
## the generic [method describe] when the state carries no living enemy boss to name (a
## boss already dead, a board not yet built, a briefing screen with no units to hand).
##
## Naming the boss is the whole point: "Defeat the boss" tells a player nothing they could
## not already guess, whereas the name is the unit they have to go and find on the board.
func describe_progress(state: Dictionary) -> String:
	for u in state.get("units", []):
		if _team_of(u) == faction:
			continue
		if not _is_boss(u) or not _is_alive(u):
			continue
		var display: String = _display_name_of(u)
		if display != "":
			return "Defeat %s" % display
	return describe()


## True when [param unit] is a boss. Duck-typed to match the live [Unit]
## (`is_boss()` reading `character_resource.is_boss`) while still resolving mocks
## that expose either a `character_resource.is_boss` property or a bare `is_boss`.
static func _is_boss(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_boss"):
		return bool(unit.is_boss())
	var cr = unit.get("character_resource")
	if cr != null:
		var b = cr.get("is_boss")
		if b != null:
			return bool(b)
	var direct = unit.get("is_boss")
	if direct != null:
		return bool(direct)
	return false
