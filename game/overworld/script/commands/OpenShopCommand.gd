class_name OpenShopCommand
extends StoryCommand

## Open a merchant's SHOP screen and wait until the player leaves it (docs/design/OVERWORLD.md
## §4.4 "OpenShop"). The shop is a host call -- [code]host.open_shop(shop)[/code] awaits the screen
## -- so while it is up the script holds the overworld still, exactly like dialogue. With no host
## (a headless dry run) it does nothing.

@export var shop: ShopResource


func run(ctx: ScriptContext) -> void:
	if shop == null or not ctx.has_host_method(&"open_shop"):
		return
	await ctx.host.open_shop(shop)
	ctx.world_changed()


func describe() -> String:
	return "Open shop %s" % (String(shop.id) if shop != null else "(none)")


func validate(issues: Array[String]) -> void:
	if shop == null:
		issues.append("no shop")
		return
	shop.validate(issues)
