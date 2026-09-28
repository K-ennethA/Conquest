class_name GiveItemCommand
extends StoryCommand

## Put an item in the STORY bag (not the profile ItemInventory -- OVERWORLD.md §4.8) and toast it.

@export var item_id: StringName = &""
@export var count: int = 1


func run(ctx: ScriptContext) -> void:
	var item: ItemResource = ItemLibrary.get_item(item_id)
	if item == null:
		return
	ctx.state.add_item(String(item_id), count)
	if ctx.has_host_method(&"toast"):
		ctx.host.toast("Found %s%s" % [item.display_name, " x%d" % count if count > 1 else ""], "item")


func describe() -> String:
	return "Give item %s x%d" % [item_id, count]


func validate(issues: Array[String]) -> void:
	if not ItemLibrary.has_item(item_id):
		issues.append("item '%s' does not exist" % item_id)
