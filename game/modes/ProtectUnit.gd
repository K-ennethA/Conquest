extends WinCondition
class_name ProtectUnit

## A standing objective: FAILED the moment the protected unit dies or leaves the
## field, ONGOING while it lives.
##
## On its own it never reports MET. It belongs in a rule set's LOSE conditions
## ([GameModeRules] turns a lose condition reporting FAILED into a defeat), beside the
## win conditions that actually win the battle -- "rout the enemy, and keep Elias
## alive". (As a WIN condition its FAILED is a defeat too, but it would then have to be
## MET to win, which it never is.) Maps author it as a victory-condition STRING,
## "Protect Elias" ([WinConditionLibrary] moves it to the lose side); story battles name
## it on their [BattleSpec] (`protect`) and StoryController adds it when the board is
## staged, together with the HERO rule (the main character falling is always a defeat).
##
## Which unit: [member protected_id] matches, case-insensitively, a unit's `protect_id`
## or `story_member_id` meta, its duck-typed id (get_id / unit_id / character_id / id),
## its character resource's `character_id`, or its display name. With [member faction]
## >= 0 only units of that faction count (an enemy of the same species is never the
## escort). Every matching unit must live, and none in play at all counts as lost -- the
## live wiring re-adds the just-killed unit to the state, so a death is seen on the very
## tick it happens.

## Identifier of the unit that must be kept alive (see the class docs for what matches).
@export var protected_id: StringName = &""
## The name the objective shows ("Keep Elias alive"); "" = [member protected_id].
@export var display_label: String = ""
## Only units of this faction can be the protected one (-1 = any faction).
@export var faction: int = -1


static func make(id: String, label_text: String = "", p_faction: int = -1) -> ProtectUnit:
	var p := ProtectUnit.new()
	p.protected_id = StringName(id.strip_edges())
	p.display_label = label_text.strip_edges()
	p.faction = p_faction
	return p


func evaluate(state: Dictionary) -> int:
	var seen := false
	for u in state.get("units", []):
		if not matches(u):
			continue
		seen = true
		if not _is_alive(u):
			return Status.FAILED
	# The unit is no longer in play: treat as lost.
	return Status.ONGOING if seen else Status.FAILED


## True when [param unit] is (one of) the unit(s) this objective protects.
func matches(unit) -> bool:
	if unit == null or String(protected_id).is_empty():
		return false
	if unit is Object and not is_instance_valid(unit):
		return false
	if faction >= 0 and _team_of(unit) != faction:
		return false
	var want: String = String(protected_id).to_lower()
	for key in [&"protect_id", &"story_member_id"]:
		if unit.has_meta(key) and String(unit.get_meta(key)).to_lower() == want:
			return true
	if String(_unit_id(unit)).to_lower() == want:
		return true
	var cr = unit.get("character_resource")
	if cr != null:
		var cid = cr.get("character_id")
		if cid != null and String(cid).to_lower() == want:
			return true
	var dn: String = _display_name_of(unit)
	return not dn.is_empty() and dn.to_lower() == want


## The name shown for the protected unit.
func label() -> String:
	return display_label if not display_label.is_empty() else String(protected_id).capitalize()


func describe() -> String:
	return "Keep %s alive" % label()


func is_guard() -> bool:
	return true
