class_name ShopStockEntry
extends Resource

## ONE LINE of a merchant's stock ([ShopResource.stock]): which item, at what price, how many,
## and when it is offered. Pure data -- [ShopLedger] owns the rules.
##
## GENERIC on purpose (DECISIONS.md #28 revision): any [ItemResource] can be stocked --
## consumables and equipment today; bonding shards and evolution / promotion items later are
## just more lines, gated by [member condition] on the story flags that make them available.

## The item ([ItemLibrary] id).
@export var item_id: StringName = &""
## Gold per unit; 0 = the item's own [member ItemResource.price].
@export var price: int = 0
## How many the merchant has between restocks; -1 = never runs out.
@export var stock_limit: int = -1
## Story-flag gate ([ConditionContext], e.g. [code]has("opening.complete")[/code]); blank = always.
## A line whose condition is false is not shown at all.
@export var condition: String = ""


static func make(p_item_id: StringName, p_price: int = 0, p_limit: int = -1, p_condition: String = "") -> ShopStockEntry:
	var e := ShopStockEntry.new()
	e.item_id = p_item_id
	e.price = p_price
	e.stock_limit = p_limit
	e.condition = p_condition
	return e


func item() -> ItemResource:
	return ItemLibrary.get_item(item_id)


## The unit price this line charges (its own, else the item's).
func unit_price() -> int:
	if price > 0:
		return price
	var it: ItemResource = item()
	return it.price if it != null else 0


func is_limited() -> bool:
	return stock_limit >= 0
