extends EvolutionTrigger
class_name KnowsMoveTrigger

## Met when the member's CURRENT FORM knows [member move_id] -- its roster moveset includes it
## (docs/design/DECISIONS.md #26 "knowing a move"). Kept simple on purpose: forms have fixed
## movesets today, so this reads ctx key [code]form[/code] and the roster, nothing else. Works
## in every mode.

@export var move_id: StringName = &""

static var _names: Dictionary = {}


func is_met(ctx: Dictionary) -> bool:
	if move_id == &"":
		return false
	var chr: CharacterResource = CharacterLibrary.get_character(StringName(String(ctx.get("form", ""))))
	if chr == null:
		return false
	for m in chr.get_moveset():
		if m != null and m.move_id == move_id:
			return true
	return false


func describe() -> String:
	return "Knows %s" % move_name(move_id)


func problem() -> String:
	return "a KnowsMove requirement names no move" if move_id == &"" else ""


## The display name of [param id] from the first roster moveset that has it (cached).
static func move_name(id: StringName) -> String:
	if _names.has(id):
		return _names[id]
	var out: String = String(id).capitalize()
	for cid in CharacterLibrary.all_ids():
		var chr: CharacterResource = CharacterLibrary.get_character(cid)
		if chr == null:
			continue
		for m in chr.get_moveset():
			if m != null and m.move_id == id and not m.display_name.is_empty():
				_names[id] = m.display_name
				return m.display_name
	_names[id] = out
	return out
