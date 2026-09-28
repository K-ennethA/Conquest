class_name ShopLedger
extends RefCounted

## THE SHOP RULES (docs/design/DECISIONS.md #28): what a merchant offers right now, what it costs,
## buying, selling, stock limits and restocks. PURE -- a [ShopResource] (the authored shop), the
## [StoryState] (gold, bag, flags, the per-shop bookkeeping) and a [StoryRuleset] (the economy
## knobs, CONQUEST.md rule 11); no nodes, no disk, no RNG, so every rule is unit-testable and the
## shop screen is a thin view over it.
##
##   * OFFERED: a stock line shows only while its [member ShopStockEntry.condition] (a story-flag
##     gate) holds and its item exists.
##   * PRICE: the line's own price, else the item's [member ItemResource.price].
##   * STOCK: a limited line has [member ShopStockEntry.stock_limit] units between restocks; the
##     units sold are saved per shop in [member StoryState.shops] ({shop_id: {sold, epoch}}).
##   * RESTOCK: [enum ShopResource.Restock] -- NEVER, ON_REST (the rest counter moved), or
##     EVERY_N_STEPS (another N steps walked). The shop's EPOCH is a pure function of the journey
##     (rests / steps), so a restock is deterministic and survives save / load: when the saved
##     epoch differs from the current one, the sold counts are cleared.
##   * BUY: refused (nothing changes) for an unknown / unoffered / sold-out line, a bad quantity,
##     too little gold, or a bag stack past [member StoryRuleset.bag_stack_cap].
##   * SELL: any bag item with a price, at floor(price x sell ratio) each (at least 1); the ratio
##     is the shop's, else the ruleset's. An item with no price (a key item, a catalyst) is not
##     bought back. Selling never restocks the merchant.
##
## Every result is a value ({ok, reason, ...}); nothing logs (CONQUEST.md rule 1).

const REASON_UNKNOWN_ITEM := "unknown_item"
const REASON_NOT_STOCKED := "not_stocked"
const REASON_BAD_QUANTITY := "bad_quantity"
const REASON_SOLD_OUT := "sold_out"
const REASON_NOT_ENOUGH_STOCK := "not_enough_stock"
const REASON_NOT_ENOUGH_GOLD := "not_enough_gold"
const REASON_BAG_FULL := "bag_full"
const REASON_NOT_OWNED := "not_owned"
const REASON_NO_VALUE := "no_value"
const REASON_NOT_BUYING := "not_buying"

## Default economy numbers when no ruleset is given (the StoryRuleset defaults).
const DEFAULT_SELL_RATIO := 0.5
const DEFAULT_BAG_CAP := 99


# --- Restock ---------------------------------------------------------------------------

## The restock epoch [param shop] is in on this journey (changes exactly when it restocks).
static func epoch(shop: ShopResource, state: StoryState) -> int:
	if shop == null or state == null:
		return 0
	match shop.restock:
		ShopResource.Restock.ON_REST:
			return state.rests
		ShopResource.Restock.EVERY_N_STEPS:
			return state.steps / maxi(1, shop.restock_steps)
	return 0


## The shop's saved bookkeeping, brought up to date (a restock clears the sold counts). Writes
## the record into [param state] and returns it: {"sold": {item_id: n}, "epoch": int}.
static func record(shop: ShopResource, state: StoryState) -> Dictionary:
	var key: String = String(shop.id)
	var now: int = epoch(shop, state)
	var rec = state.shops.get(key, null)
	if not (rec is Dictionary):
		rec = {"sold": {}, "epoch": now}
	if int(rec.get("epoch", now)) != now:
		rec = {"sold": {}, "epoch": now}
	if not (rec.get("sold", null) is Dictionary):
		rec["sold"] = {}
	state.shops[key] = rec
	return rec


# --- What is offered ----------------------------------------------------------------------

## True when [param entry] is shown now (its item exists and its flag gate holds).
static func is_offered(entry: ShopStockEntry, state: StoryState) -> bool:
	return entry != null and entry.item() != null and ConditionContext.evaluate(entry.condition, state)


## Units of [param entry] left before the next restock (-1 = unlimited).
static func remaining(shop: ShopResource, state: StoryState, entry: ShopStockEntry) -> int:
	if entry == null or not entry.is_limited():
		return -1
	var sold: Dictionary = record(shop, state)["sold"]
	return maxi(0, entry.stock_limit - int(sold.get(String(entry.item_id), 0)))


## The BUY list, in authored order: [{item_id, item, price, remaining (-1 = unlimited),
## limit, owned, sold_out, affordable}] -- only the lines offered now.
static func buy_rows(shop: ShopResource, state: StoryState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if shop == null or state == null:
		return out
	for e in shop.stock:
		if not is_offered(e, state):
			continue
		var left: int = remaining(shop, state, e)
		out.append({
			"item_id": String(e.item_id),
			"item": e.item(),
			"price": e.unit_price(),
			"remaining": left,
			"limit": e.stock_limit,
			"owned": state.item_count(String(e.item_id)),
			"sold_out": left == 0,
			"affordable": state.gold >= e.unit_price(),
		})
	return out


## The SELL list: every bag item, sorted by name: [{item_id, item, price (per unit paid),
## owned, sellable}].
static func sell_rows(shop: ShopResource, state: StoryState, ruleset: StoryRuleset = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for id in state.bag.keys():
		var it: ItemResource = ItemLibrary.get_item(String(id))
		var n: int = state.item_count(String(id))
		if it == null or n <= 0:
			continue
		var each: int = sell_price(shop, it, ruleset)
		out.append({"item_id": String(id), "item": it, "price": each, "owned": n,
			"sellable": each > 0 and (shop == null or shop.buys_items)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["item"] as ItemResource).display_name.naturalnocasecmp_to((b["item"] as ItemResource).display_name) < 0)
	return out


# --- Prices -------------------------------------------------------------------------------

## The sell ratio in force: the shop's own, else the ruleset's, else 0.5.
static func sell_ratio(shop: ShopResource, ruleset: StoryRuleset = null) -> float:
	if shop != null and shop.sell_ratio >= 0.0:
		return shop.sell_ratio
	return ruleset.sell_ratio if ruleset != null else DEFAULT_SELL_RATIO


## Gold paid per unit when [param item] is sold here: floor(price x ratio), at least 1 for an item
## with a price; 0 for an item with none (never bought back).
static func sell_price(shop: ShopResource, item: ItemResource, ruleset: StoryRuleset = null) -> int:
	if item == null or item.price <= 0:
		return 0
	return maxi(1, int(floor(float(item.price) * sell_ratio(shop, ruleset))))


static func bag_cap(ruleset: StoryRuleset = null) -> int:
	return ruleset.bag_stack_cap if ruleset != null else DEFAULT_BAG_CAP


## The most of [param item_id] a BUY could take now (stock, gold and bag room; 0 = none).
static func max_buy(shop: ShopResource, state: StoryState, item_id: String, ruleset: StoryRuleset = null) -> int:
	var e: ShopStockEntry = shop.entry(item_id) if shop != null else null
	if e == null or not is_offered(e, state):
		return 0
	var price: int = e.unit_price()
	var n: int = bag_cap(ruleset) - state.item_count(item_id)
	if price > 0:
		n = mini(n, state.gold / price)
	var left: int = remaining(shop, state, e)
	if left >= 0:
		n = mini(n, left)
	return maxi(0, n)


# --- Buy / sell -----------------------------------------------------------------------------

## Buy [param quantity] of [param item_id]: gold paid, bag filled, a limited line's stock spent.
## {ok, reason, cost, quantity}; a refusal changes nothing.
static func buy(shop: ShopResource, state: StoryState, item_id: String, quantity: int = 1,
		ruleset: StoryRuleset = null) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "cost": 0, "quantity": 0}
	if shop == null or state == null or ItemLibrary.get_item(item_id) == null:
		out["reason"] = REASON_UNKNOWN_ITEM
		return out
	var e: ShopStockEntry = shop.entry(item_id)
	if e == null or not is_offered(e, state):
		out["reason"] = REASON_NOT_STOCKED
		return out
	if quantity <= 0:
		out["reason"] = REASON_BAD_QUANTITY
		return out
	var left: int = remaining(shop, state, e)
	if left == 0:
		out["reason"] = REASON_SOLD_OUT
		return out
	if left > 0 and quantity > left:
		out["reason"] = REASON_NOT_ENOUGH_STOCK
		return out
	var cost: int = e.unit_price() * quantity
	if state.gold < cost:
		out["reason"] = REASON_NOT_ENOUGH_GOLD
		out["cost"] = cost
		return out
	if state.item_count(item_id) + quantity > bag_cap(ruleset):
		out["reason"] = REASON_BAG_FULL
		return out
	state.take_gold(cost)
	state.add_item(item_id, quantity)
	if e.is_limited():
		var sold: Dictionary = record(shop, state)["sold"]
		sold[item_id] = int(sold.get(item_id, 0)) + quantity
	out["ok"] = true
	out["cost"] = cost
	out["quantity"] = quantity
	return out


## Sell [param quantity] of [param item_id] from the bag. {ok, reason, gold, quantity}.
static func sell(shop: ShopResource, state: StoryState, item_id: String, quantity: int = 1,
		ruleset: StoryRuleset = null) -> Dictionary:
	var out: Dictionary = {"ok": false, "reason": "", "gold": 0, "quantity": 0}
	if shop != null and not shop.buys_items:
		out["reason"] = REASON_NOT_BUYING
		return out
	var it: ItemResource = ItemLibrary.get_item(item_id)
	if it == null or state == null:
		out["reason"] = REASON_UNKNOWN_ITEM
		return out
	if quantity <= 0:
		out["reason"] = REASON_BAD_QUANTITY
		return out
	if state.item_count(item_id) < quantity:
		out["reason"] = REASON_NOT_OWNED
		return out
	var each: int = sell_price(shop, it, ruleset)
	if each <= 0:
		out["reason"] = REASON_NO_VALUE
		return out
	state.take_item(item_id, quantity)
	state.add_gold(each * quantity)
	out["ok"] = true
	out["gold"] = each * quantity
	out["quantity"] = quantity
	return out


## The words for a refusal ("Not enough gold.").
static func reason_text(reason: String) -> String:
	match reason:
		REASON_NOT_ENOUGH_GOLD:
			return "Not enough gold."
		REASON_SOLD_OUT:
			return "Sold out -- come back after the merchant restocks."
		REASON_NOT_ENOUGH_STOCK:
			return "The merchant doesn't have that many."
		REASON_BAG_FULL:
			return "Your bag can't hold any more of that."
		REASON_NOT_OWNED:
			return "You don't have that many."
		REASON_NO_VALUE:
			return "The merchant won't buy that."
		REASON_NOT_BUYING:
			return "This merchant doesn't buy items."
		REASON_NOT_STOCKED:
			return "That isn't for sale here."
		REASON_BAD_QUANTITY:
			return "Pick how many first."
	return "That can't be done."


# --- Save --------------------------------------------------------------------------------

## A JSON-parsed "shops" block made safe ({shop_id: {sold: {item_id: int > 0}, epoch: int}});
## anything malformed is dropped (CONQUEST.md rules 3 / 8).
static func sanitize_saved(raw) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		var rec = raw[k]
		if String(k).is_empty() or not (rec is Dictionary):
			continue
		var sold: Dictionary = {}
		var raw_sold = rec.get("sold", {})
		if raw_sold is Dictionary:
			for item_id in raw_sold.keys():
				var v = raw_sold[item_id]
				var n: int = int(v) if (v is int or v is float) else 0
				if n > 0 and not String(item_id).is_empty():
					sold[String(item_id)] = n
		var ep = rec.get("epoch", 0)
		out[String(k)] = {"sold": sold, "epoch": int(ep) if (ep is int or ep is float) else 0}
	return out
