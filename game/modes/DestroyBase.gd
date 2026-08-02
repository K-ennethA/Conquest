extends WinCondition
class_name DestroyBase

## MET once no living enemy BASE structure remains; FAILED the moment our OWN base falls.
##
## The King-of-the-Hill / base-assault objective. Both sides plant an immobile
## structure (the [code]bastion[/code] roster character -- see
## [member base_character_ids]) behind their lines and field endlessly respawning
## grunts in front of it, so "clear the field" is never a reachable goal: the ONLY
## way a base-assault map ends is a base coming down. This single condition scores
## both halves of that:
##
##   - every hostile base dead  -> [constant Status.MET]    (victory)
##   - our own base dead        -> [constant Status.FAILED] (defeat, see
##                                 [method GameModeRules.evaluate] -- a FAILED win
##                                 condition IS a defeat, so the mode needs no
##                                 separate lose condition)
##
## Defeat is reported first: a mutual wipe on the same tick reads as a loss, which is
## the conservative answer and matches "you lost your base" being the thing the player
## actually feels.
##
## NEUTRALS. A base-assault map also fields a third, NEUTRAL faction (the guardian
## camps flanking the hill -- see [BaseAssaultRuntime]). Those units are objectives,
## not combatants, and must never move this condition: they are skipped explicitly
## rather than merely "not being bases", so that a future neutral structure cannot
## hand the player a win by dying. Unowned units (team < 0 -- a unit the board holds
## before ownership is assigned) are skipped for the same reason.
##
## Edge case -- a map with NO enemy base at all resolves [constant Status.ONGOING],
## never an instant win, exactly like [DefeatBoss]. The distinction "the base is dead"
## vs "there was never a base" is made by whether the [param state] still carries a
## base unit; the live wiring re-adds the just-eliminated unit to the state so the
## death is observable on the very tick it happens (see
## [code]GameWorldManager._build_win_state[/code]).

## The friendly faction this objective is scored for.
@export var faction: int = 0

## Roster [member CharacterResource.character_id]s that count as a BASE. Authored as a
## list (not a single id) so a map can field a different structure without a new
## condition class; the shipped base-assault map uses the single default.
@export var base_character_ids: Array[StringName] = [&"bastion"]


func evaluate(state: Dictionary) -> int:
	var units: Array = state.get("units", [])

	var saw_enemy_base := false
	var enemy_base_alive := false
	var saw_own_base := false
	var own_base_alive := false

	for u in units:
		if not is_base(u):
			continue
		var team: int = _team_of(u)
		if team == faction:
			saw_own_base = true
			if _is_alive(u):
				own_base_alive = true
			continue
		# Third parties never decide this objective (see the class docs).
		if _is_neutral(u) or team < 0:
			continue
		saw_enemy_base = true
		if _is_alive(u):
			enemy_base_alive = true

	# Losing your own base ends the battle even if the enemy's is already rubble.
	if saw_own_base and not own_base_alive:
		return Status.FAILED
	# No enemy base was ever present -> nothing to destroy, so this can never be won
	# by default.
	if not saw_enemy_base:
		return Status.ONGOING
	return Status.ONGOING if enemy_base_alive else Status.MET


func describe() -> String:
	return "Destroy the enemy base"


## True when [param unit] is a base structure. Duck-typed the same way
## [method DefeatBoss._is_boss] is, so it resolves on the live [Unit] (whose
## [code]character_resource.character_id[/code] names the roster entry) AND on the
## lightweight mocks the win-condition tests use (a bare [code]is_base[/code] flag or
## a bare [code]character_id[/code]).
func is_base(unit) -> bool:
	if unit == null:
		return false

	var cr = unit.get("character_resource")
	if cr != null:
		var cid = cr.get("character_id")
		if cid != null and base_character_ids.has(StringName(cid)):
			return true

	var flag = unit.get("is_base")
	if flag != null and bool(flag):
		return true

	var direct = unit.get("character_id")
	if direct != null and base_character_ids.has(StringName(direct)):
		return true

	return false


## True when [param unit] belongs to the NEUTRAL faction. Reads the owning
## [Player]'s [member Player.is_neutral] on a live unit, and a bare
## [code]is_neutral[/code] property on a mock. A unit with no owner at all is NOT
## reported neutral here -- [method evaluate] rejects it separately via its team.
static func _is_neutral(unit) -> bool:
	if unit == null:
		return false

	var direct = unit.get("is_neutral")
	if direct != null:
		return bool(direct)

	if unit.has_method("get_owner_player"):
		var owner_player = unit.get_owner_player()
		if owner_player != null:
			var flag = owner_player.get("is_neutral")
			if flag != null:
				return bool(flag)

	return false
