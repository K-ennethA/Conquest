extends EvolutionTrigger
class_name UseItemTrigger

## Met only at the moment [member item_id] is USED on the member from the story bag
## (docs/design/DECISIONS.md #26 "use an item"; an evolution stone): Journey -> Bag -> Use, or the
## Party page's EVOLVE when the bag holds the item ([method StoryController.use_item_on_member]).
## Reads ctx key [code]used_item[/code]; [code]bag[/code] feeds the checklist's progress. The
## item is CONSUMED when the evolution is confirmed ([member consume]); "Not now" keeps it.
##
## A story requirement ([method needs_story]): open modes have no story bag, so it is unmet there
## unless the edge skips story requirements outside story.

@export var item_id: String = ""
## Spend one on a confirmed evolution. false = a reusable key item (only shown, never spent).
@export var consume: bool = true


func is_met(ctx: Dictionary) -> bool:
	return not item_id.is_empty() and String(ctx.get("used_item", "")) == item_id


func describe() -> String:
	return "Use %s" % HeldItemTrigger.item_name(item_id)


func progress(ctx: Dictionary) -> String:
	var bag = ctx.get("bag", null)
	if not (bag is Dictionary):
		return ""
	var n: int = int((bag as Dictionary).get(item_id, 0))
	return ("%d in bag" % n) if n > 0 else "none in bag"


func needs_story() -> bool:
	return true


func used_item_id() -> String:
	return item_id


func problem() -> String:
	if item_id.strip_edges().is_empty():
		return "a UseItem requirement names no item"
	if not ItemLibrary.has_item(item_id):
		return "a UseItem requirement names unknown item '%s'" % item_id
	return ""
