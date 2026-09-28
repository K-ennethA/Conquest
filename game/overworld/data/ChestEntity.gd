class_name ChestEntity
extends OverworldEntity

## A chest: gives its loot once (flag <area>.<id>.opened), then stays open -- across a reload,
## because the flag is in the save and the actor reads it.

@export var loot_items: Array[StringName] = []
@export var loot_gold: int = 0


func kind() -> StringName:
	return &"chest"


func auto_flag(area_id: String) -> String:
	return opened_flag(area_id, String(id))


static func opened_flag(area_id: String, chest_id: String) -> String:
	return "%s.%s.opened" % [area_id, chest_id]


func is_opened(area_id: String, state: StoryState) -> bool:
	return state.has_flag(auto_flag(area_id))


func is_interactable() -> bool:
	return true


func prompt_verb() -> String:
	return "Open"


func interact_script(area_id: String, state: StoryState) -> Array:
	var out: Array = []
	if is_opened(area_id, state):
		var empty := SayCommand.new()
		empty.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, "", "The chest is empty.")])
		out.append(empty)
		return out
	var set_open := SetFlagCommand.new()
	set_open.key = auto_flag(area_id)
	set_open.value = 1
	out.append(set_open)
	for item_id in loot_items:
		var give := GiveItemCommand.new()
		give.item_id = item_id
		out.append(give)
	if loot_gold > 0:
		var g := GiveGoldCommand.new()
		g.amount = loot_gold
		out.append(g)
	out.append_array(on_interact)
	return out


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	for i in loot_items:
		if not ItemLibrary.has_item(i):
			issues.append("%s: loot item '%s' does not exist" % [String(id), i])
