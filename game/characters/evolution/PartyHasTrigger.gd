extends EvolutionTrigger
class_name PartyHasTrigger

## Met while ANOTHER party member is [member character_id] -- that form, or any form of that
## line (docs/design/DECISIONS.md #26 "party composition"). Reads ctx key
## [code]party_members[/code] ([{member_id, character_id, line}], story only) and skips the
## member itself ([code]uid[/code]). A member joining raises a "party" auto-offer event.

## A roster character id or a line root ("tree_grunt" matches Barkling and Oakheart).
@export var character_id: String = ""


func is_met(ctx: Dictionary) -> bool:
	if character_id.is_empty():
		return false
	var party = ctx.get("party_members", null)
	if not (party is Array):
		return false
	var me: String = String(ctx.get("uid", ""))
	for p in party:
		if not (p is Dictionary) or String(p.get("member_id", "")) == me:
			continue
		if String(p.get("character_id", "")) == character_id or String(p.get("line", "")) == character_id:
			return true
	return false


func describe() -> String:
	var chr: CharacterResource = CharacterLibrary.get_character(StringName(character_id)) if not character_id.is_empty() else null
	return "With %s in the party" % (chr.display_name if chr != null else character_id.capitalize())


func needs_story() -> bool:
	return true


func responds_to(event: Dictionary) -> bool:
	return event_has(event, "party")


func problem() -> String:
	return "a PartyHas requirement names no character" if character_id.strip_edges().is_empty() else ""
