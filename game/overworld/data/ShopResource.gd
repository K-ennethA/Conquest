class_name ShopResource
extends Resource

## A MERCHANT'S SHOP (docs/design/DECISIONS.md #28, docs/design/OVERWORLD.md §4.2 / §4.8): what a
## [ShopEntity] sells, how its stock comes back, and what it pays for your items. Authored under
## game/overworld/content/shops/<id>.tres (by the story content builder) and addressed by
## [member id], which is also the key its stock bookkeeping is saved under.
##
## The rules (prices, stock, restock, selling) are [ShopLedger]'s; this is data only.
##
## SCOPE (the revision to #28): healing items, status cures, revives and the existing equipment.
## Bonding shards and evolution / promotion items are NOT stocked yet -- but nothing here is
## specific to a category: adding them later is more [member stock] lines (gated by story flags).

const DIR := "res://game/overworld/content/shops/"

## When limited stock comes back.
enum Restock {
	NEVER,          ## sold out stays sold out (a one-off find)
	ON_REST,        ## refilled after every rest (Wayshrine / healer / whiteout): [member StoryState.rests]
	EVERY_N_STEPS,  ## refilled every [member restock_steps] steps walked: [member StoryState.steps]
}

## Stable id (the save key). Never change it once shipped.
@export var id: StringName = &""
## The shop's name on the screen ("Crownhaven General Goods").
@export var display_name: String = "Shop"
## A line the merchant greets you with in the shop screen ("" = none).
@export_multiline var greeting: String = ""
@export var stock: Array[ShopStockEntry] = []
@export var restock: Restock = Restock.ON_REST
## Steps per restock for [constant Restock.EVERY_N_STEPS].
@export var restock_steps: int = 200
## Fraction of an item's price this merchant pays when you SELL; -1 = the story ruleset's
## [member StoryRuleset.sell_ratio] (CONQUEST.md rule 11: the default is a mode knob).
@export_range(-1.0, 1.0, 0.01) var sell_ratio: float = -1.0
## Whether this merchant buys at all (a Sell tab).
@export var buys_items: bool = true


static func path_for(shop_id: String) -> String:
	return "%s%s.tres" % [DIR, shop_id]


## A shipped shop by id (trusted content), or null.
static func load_by_id(shop_id: String) -> ShopResource:
	if shop_id.is_empty():
		return null
	var path: String = path_for(shop_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as ShopResource


## The stock line for [param item_id] (the first), or null.
func entry(item_id: String) -> ShopStockEntry:
	for e in stock:
		if e != null and String(e.item_id) == item_id:
			return e
	return null


## Content validation: ids, prices, conditions. Appends human-readable issues.
func validate(issues: Array[String]) -> void:
	var where: String = "shop '%s'" % String(id)
	if String(id).is_empty():
		issues.append("a shop has no id")
	var seen: Dictionary = {}
	for e in stock:
		if e == null:
			issues.append("%s: an empty stock line" % where)
			continue
		var it: ItemResource = ItemLibrary.get_item(e.item_id)
		if it == null:
			issues.append("%s: stock item '%s' does not exist" % [where, String(e.item_id)])
			continue
		if seen.has(e.item_id):
			issues.append("%s: '%s' is stocked twice" % [where, String(e.item_id)])
		seen[e.item_id] = true
		if e.unit_price() <= 0:
			issues.append("%s: '%s' has no price" % [where, String(e.item_id)])
		StoryCommand.check_condition(e.condition, issues, "%s stock '%s' condition" % [where, String(e.item_id)])
	if restock == Restock.EVERY_N_STEPS and restock_steps <= 0:
		issues.append("%s: restock_steps must be positive" % where)
