class_name ShopEntity
extends NpcEntity

## A MERCHANT (docs/design/OVERWORLD.md §4.2 "ShopEntity", DECISIONS.md #28): an NPC whose
## [member shop] opens when you talk to them. Talking runs the NPC's [member NpcEntity.dialogue]
## (a greeting, optional), then an [OpenShopCommand] (the shop screen; the script -- and so the
## overworld -- waits until it closes), then anything in [member OverworldEntity.on_interact].

@export var shop: ShopResource


func kind() -> StringName:
	return &"shop"


func is_interactable() -> bool:
	return shop != null or super.is_interactable()


func prompt_verb() -> String:
	return "Shop" if shop != null else "Talk"


func interact_script(_area_id: String, _state: StoryState) -> Array:
	var out: Array = []
	if dialogue != null:
		out.append(SayCommand.from_scene(dialogue))
	if shop != null:
		var open := OpenShopCommand.new()
		open.shop = shop
		out.append(open)
	out.append_array(on_interact)
	return out


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	if shop == null:
		issues.append("%s: a shop entity with no shop" % String(id))
		return
	var own: Array[String] = []
	shop.validate(own)
	for msg in own:
		issues.append("%s: %s" % [String(id), msg])
