extends RefCounted
class_name DuelCombatant

## One party member in a [DuelRequest]. [member character_id] is always the member's
## CURRENT form (EVOLUTION's RosterLedger.form_of), and [member strength] is opaque upstream
## -- the duel applies it through [method DuelScaling.apply] only.

var member_id: String = ""
var character_id: StringName = &""
## Optional moveset override (move ids), carried for the overworld contract; M1 ignores it.
var moveset_override: Array[String] = []
## 1.0 = roster base stats (see [DuelScaling]).
var strength: float = 1.0
## Starting HP; -1 = full.
var current_hp: int = -1
var item_ids: Array[String] = []
var skin_id: String = ""


static func make(p_character_id: StringName, p_member_id: String = "") -> DuelCombatant:
	var c := DuelCombatant.new()
	c.character_id = p_character_id
	c.member_id = p_member_id if p_member_id != "" else String(p_character_id)
	return c


func to_dict() -> Dictionary:
	return {
		"member_id": member_id,
		"character_id": String(character_id),
		"moveset_override": moveset_override.duplicate(),
		"strength": strength,
		"current_hp": current_hp,
		"item_ids": item_ids.duplicate(),
		"skin_id": skin_id,
	}


## STRICT importer (CONQUEST.md rule 8): types checked, the character id must be a known
## roster id (resolved through [method CharacterLibrary.all_ids], never a path).
## Returns { success, reason, combatant }.
static func from_dict(d) -> Dictionary:
	if not (d is Dictionary):
		return _fail("combatant_not_a_dictionary")
	var raw_id = d.get("character_id", "")
	if typeof(raw_id) != TYPE_STRING and typeof(raw_id) != TYPE_STRING_NAME:
		return _fail("bad_character_id")
	var cid := StringName(String(raw_id))
	if cid == &"" or not (cid in CharacterLibrary.all_ids()):
		return _fail("unknown_character:%s" % String(raw_id))
	var c := DuelCombatant.new()
	c.character_id = cid
	c.member_id = _str(d.get("member_id", String(cid)))
	var strength = d.get("strength", 1.0)
	if typeof(strength) != TYPE_FLOAT and typeof(strength) != TYPE_INT:
		return _fail("bad_strength")
	c.strength = clampf(float(strength), 0.1, 10.0)
	var hp = d.get("current_hp", -1)
	if typeof(hp) != TYPE_FLOAT and typeof(hp) != TYPE_INT:
		return _fail("bad_current_hp")
	c.current_hp = int(hp)
	c.moveset_override = _strings(d.get("moveset_override", []))
	c.item_ids = _strings(d.get("item_ids", []))
	c.skin_id = _str(d.get("skin_id", ""))
	return {"success": true, "reason": "", "combatant": c}


static func _fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason, "combatant": null}


static func _str(v) -> String:
	return String(v) if (typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME) else ""


## A JSON array -> Array[String] (rule 3: element-wise, non-strings dropped).
static func _strings(v) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for e in v:
			if typeof(e) == TYPE_STRING or typeof(e) == TYPE_STRING_NAME:
				out.append(String(e))
	return out
