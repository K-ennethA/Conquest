extends EvolutionTrigger
class_name HeldItemTrigger

## Met while the member WEARS [member item_id] (docs/design/DECISIONS.md #26 "hold an item";
## a crest / insignia for a human class promotion, #16). Reads ctx key [code]held_item[/code]:
## the story member's equipped bag item, or in open modes the form's ItemInventory equip
## ([method RosterLedger.context_for]). Works in every mode; the item is NOT consumed.

@export var item_id: String = ""


func is_met(ctx: Dictionary) -> bool:
	return not item_id.is_empty() and String(ctx.get("held_item", "")) == item_id


func describe() -> String:
	return "Hold %s" % item_name(item_id)


## An equip changes what the member holds (an "item" auto-offer event).
func responds_to(event: Dictionary) -> bool:
	return event_has(event, "item")


func problem() -> String:
	if item_id.strip_edges().is_empty():
		return "a HeldItem requirement names no item"
	if not ItemLibrary.has_item(item_id):
		return "a HeldItem requirement names unknown item '%s'" % item_id
	return ""


## The display name of [param id] (the id itself when unknown).
static func item_name(id: String) -> String:
	var item: ItemResource = ItemLibrary.get_item(id) if not id.is_empty() else null
	return item.display_name if item != null else id.capitalize()
