extends GutTest

## THE SHOP RULES ([ShopLedger], docs/design/DECISIONS.md #28): buy / sell maths, stock limits,
## story-flag gates, the three restock rules, bag room, and the per-shop bookkeeping's save
## round trip (old saves load with every merchant fully stocked). Pure: a code-built shop and a
## StoryState, no nodes, no disk.


func _shop(restock: int = ShopResource.Restock.ON_REST) -> ShopResource:
	var s := ShopResource.new()
	s.id = &"test_shop"
	s.display_name = "Test Shop"
	var stock: Array[ShopStockEntry] = [
		ShopStockEntry.make(&"mossleaf_tonic"),                        # the item's price (40), unlimited
		ShopStockEntry.make(&"dawnpetal_draught", 200, 2),              # own price, 2 per restock
		ShopStockEntry.make(&"heartwood_tonic", 0, -1, "has(\"quest.done\")"),  # flag-gated
	]
	s.stock = stock
	s.restock = restock
	s.restock_steps = 10
	return s


func _state(gold: int = 1000) -> StoryState:
	var st := StoryState.new()
	st.gold = gold
	return st


func _ids(rows: Array) -> Array:
	return rows.map(func(r: Dictionary) -> String: return String(r["item_id"]))


# --- Buying ------------------------------------------------------------------------------

func test_buy_spends_gold_and_fills_the_bag() -> void:
	var st := _state(100)
	var r: Dictionary = ShopLedger.buy(_shop(), st, "mossleaf_tonic", 2)
	assert_true(bool(r["ok"]), "two tonics bought")
	assert_eq(int(r["cost"]), 80, "at the item's own price (2 x 40)")
	assert_eq(st.gold, 20, "gold drops by the cost")
	assert_eq(st.item_count("mossleaf_tonic"), 2, "the bag gains them")


func test_not_enough_gold_changes_nothing() -> void:
	var st := _state(100)
	var r: Dictionary = ShopLedger.buy(_shop(), st, "mossleaf_tonic", 3)
	assert_false(bool(r["ok"]), "120 gold of tonics on 100 gold is refused")
	assert_eq(String(r["reason"]), ShopLedger.REASON_NOT_ENOUGH_GOLD, "not enough gold")
	assert_eq(st.gold, 100, "gold untouched")
	assert_eq(st.item_count("mossleaf_tonic"), 0, "bag untouched")
	assert_eq(ShopLedger.reason_text(String(r["reason"])), "Not enough gold.", "and the words for it")


func test_bad_requests_are_refused() -> void:
	var st := _state()
	assert_eq(String(ShopLedger.buy(_shop(), st, "mossleaf_tonic", 0)["reason"]), ShopLedger.REASON_BAD_QUANTITY, "quantity 0")
	assert_eq(String(ShopLedger.buy(_shop(), st, "verdant_banner", 1)["reason"]), ShopLedger.REASON_NOT_STOCKED, "not on the list")
	assert_eq(String(ShopLedger.buy(_shop(), st, "no_such_item", 1)["reason"]), ShopLedger.REASON_UNKNOWN_ITEM, "unknown id")


func test_a_stock_limit_sells_out() -> void:
	var shop := _shop()
	var st := _state()
	assert_eq(String(ShopLedger.buy(shop, st, "dawnpetal_draught", 3)["reason"]), ShopLedger.REASON_NOT_ENOUGH_STOCK,
		"only 2 in stock")
	assert_true(bool(ShopLedger.buy(shop, st, "dawnpetal_draught", 2)["ok"]), "buy the two")
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 0, "none left")
	assert_true(bool(r_row(shop, st, "dawnpetal_draught")["sold_out"]), "shown as sold out")
	assert_eq(String(ShopLedger.buy(shop, st, "dawnpetal_draught", 1)["reason"]), ShopLedger.REASON_SOLD_OUT, "sold out")
	assert_eq(st.gold, 600, "at its own price (2 x 200)")
	assert_eq(int(r_row(shop, st, "mossleaf_tonic")["remaining"]), -1, "an unlimited line never runs out")


func r_row(shop: ShopResource, st: StoryState, id: String) -> Dictionary:
	for r in ShopLedger.buy_rows(shop, st):
		if String(r["item_id"]) == id:
			return r
	return {}


func test_a_flag_gate_hides_the_line_until_the_story_opens_it() -> void:
	var shop := _shop()
	var st := _state()
	assert_false(_ids(ShopLedger.buy_rows(shop, st)).has("heartwood_tonic"), "gated: not listed")
	assert_eq(String(ShopLedger.buy(shop, st, "heartwood_tonic", 1)["reason"]), ShopLedger.REASON_NOT_STOCKED,
		"and not buyable")
	st.set_flag("quest.done", 1)
	assert_true(_ids(ShopLedger.buy_rows(shop, st)).has("heartwood_tonic"), "the flag opens it")
	assert_true(bool(ShopLedger.buy(shop, st, "heartwood_tonic", 1)["ok"]), "and it sells")


func test_the_bag_cap_refuses_a_full_stack() -> void:
	var rs := StoryRuleset.new()
	rs.bag_stack_cap = 3
	var st := _state()
	st.add_item("mossleaf_tonic", 2)
	var r: Dictionary = ShopLedger.buy(_shop(), st, "mossleaf_tonic", 2, rs)
	assert_eq(String(r["reason"]), ShopLedger.REASON_BAG_FULL, "2 + 2 > a cap of 3")
	assert_eq(ShopLedger.max_buy(_shop(), st, "mossleaf_tonic", rs), 1, "one more fits")


func test_max_buy_respects_gold_stock_and_room() -> void:
	var shop := _shop()
	assert_eq(ShopLedger.max_buy(shop, _state(130), "mossleaf_tonic"), 3, "130 gold buys three 40-gold tonics")
	assert_eq(ShopLedger.max_buy(shop, _state(10000), "dawnpetal_draught"), 2, "the stock limit caps it")
	assert_eq(ShopLedger.max_buy(shop, _state(10), "mossleaf_tonic"), 0, "no gold, none")


# --- Restock -------------------------------------------------------------------------------

func test_on_rest_restocks_after_a_rest() -> void:
	var shop := _shop(ShopResource.Restock.ON_REST)
	var st := _state()
	ShopLedger.buy(shop, st, "dawnpetal_draught", 2)
	st.steps += 500
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 0, "walking does not restock ON_REST")
	st.heal_party()   # a Wayshrine rest
	assert_eq(st.rests, 1, "a rest is counted")
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 2, "the rest restocked it")


func test_every_n_steps_restocks_on_the_step_clock() -> void:
	var shop := _shop(ShopResource.Restock.EVERY_N_STEPS)
	var st := _state()
	ShopLedger.buy(shop, st, "dawnpetal_draught", 2)
	st.steps += 9
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 0, "9 of 10 steps: still sold out")
	st.steps += 1
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 2, "the 10th step restocks")


func test_never_stays_sold_out() -> void:
	var shop := _shop(ShopResource.Restock.NEVER)
	var st := _state()
	ShopLedger.buy(shop, st, "dawnpetal_draught", 2)
	st.heal_party()
	st.steps += 1000
	assert_eq(int(r_row(shop, st, "dawnpetal_draught")["remaining"]), 0, "a one-off find never comes back")


# --- Selling ------------------------------------------------------------------------------

func test_sell_pays_the_ratio_of_the_price() -> void:
	var st := _state(0)
	st.add_item("mossleaf_tonic", 3)
	var r: Dictionary = ShopLedger.sell(_shop(), st, "mossleaf_tonic", 2)
	assert_true(bool(r["ok"]), "sold")
	assert_eq(int(r["gold"]), 40, "2 x (40 x 0.5)")
	assert_eq(st.gold, 40, "gold rises")
	assert_eq(st.item_count("mossleaf_tonic"), 1, "the bag loses them")


func test_the_sell_ratio_is_the_shops_else_the_rulesets() -> void:
	var shop := _shop()
	var it: ItemResource = ItemLibrary.get_item("mossleaf_tonic")
	var rs := StoryRuleset.new()
	rs.sell_ratio = 0.25
	assert_eq(ShopLedger.sell_price(shop, it, rs), 10, "the ruleset's knob: 40 x 0.25")
	shop.sell_ratio = 0.4
	assert_eq(ShopLedger.sell_price(shop, it, rs), 16, "a shop's own ratio wins: 40 x 0.4")


func test_items_with_no_value_are_not_bought_back() -> void:
	var st := _state(0)
	st.add_item("sunstone")
	var r: Dictionary = ShopLedger.sell(_shop(), st, "sunstone", 1)
	assert_eq(String(r["reason"]), ShopLedger.REASON_NO_VALUE, "an evolution item has no price")
	assert_eq(String(ShopLedger.sell(_shop(), st, "mossleaf_tonic", 1)["reason"]), ShopLedger.REASON_NOT_OWNED,
		"cannot sell what you do not have")
	var rows: Array[Dictionary] = ShopLedger.sell_rows(_shop(), st)
	assert_eq(rows.size(), 1, "the sell list is the bag")
	assert_false(bool(rows[0]["sellable"]), "shown as not sellable")


func test_a_shop_that_does_not_buy() -> void:
	var shop := _shop()
	shop.buys_items = false
	var st := _state(0)
	st.add_item("mossleaf_tonic")
	assert_eq(String(ShopLedger.sell(shop, st, "mossleaf_tonic", 1)["reason"]), ShopLedger.REASON_NOT_BUYING,
		"refused")


# --- Save ----------------------------------------------------------------------------------

func test_shop_stock_and_rests_survive_a_save_round_trip() -> void:
	var shop := _shop()
	var st := _state()
	st.set_location("crownhaven", Vector3i(5, 5, 0), "south")
	st.heal_party()
	ShopLedger.buy(shop, st, "dawnpetal_draught", 1)
	var text: String = JSON.stringify(StorySnapshot.to_dict(st))
	var loaded: Dictionary = StorySnapshot.from_dict(JSON.parse_string(text))
	assert_true(bool(loaded["success"]), "decodes")
	var back: StoryState = loaded["state"]
	assert_eq(back.rests, 1, "the rest counter")
	assert_eq(back.gold, st.gold, "the gold")
	assert_eq(back.item_count("dawnpetal_draught"), 1, "the bag")
	assert_eq(int(r_row(shop, back, "dawnpetal_draught")["remaining"]), 1, "the merchant still has one left")


func test_an_old_save_loads_with_every_merchant_fully_stocked() -> void:
	var old: Dictionary = StorySnapshot.to_dict(_state(55))
	old.erase("shops")
	old.erase("rests")
	var loaded: Dictionary = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(old)))
	assert_true(bool(loaded["success"]), "a save from before shops still loads")
	var st: StoryState = loaded["state"]
	assert_true(st.shops.is_empty(), "no bookkeeping")
	assert_eq(st.rests, 0, "no rests")
	assert_eq(int(r_row(_shop(), st, "dawnpetal_draught")["remaining"]), 2, "full stock")


func test_malformed_shop_bookkeeping_is_dropped() -> void:
	var clean: Dictionary = ShopLedger.sanitize_saved({"a": {"sold": {"x": 2, "y": -1, "z": "bad"}, "epoch": 3},
		"b": "junk", "": {}})
	assert_eq(clean.keys(), ["a"], "only well-formed shops survive")
	assert_eq(clean["a"]["sold"], {"x": 2}, "only positive counts")
	assert_eq(int(clean["a"]["epoch"]), 3, "the epoch")
	assert_eq(ShopLedger.sanitize_saved([1, 2]), {}, "a non-dictionary is nothing")


# --- Shipped content -------------------------------------------------------------------------

func test_the_shipped_shops_validate() -> void:
	for id in ["crownhaven_general", "mossway_pedlar"]:
		var shop := ShopResource.load_by_id(id)
		assert_not_null(shop, "%s ships" % id)
		if shop == null:
			continue
		var issues: Array[String] = []
		shop.validate(issues)
		assert_eq(issues.size(), 0, "%s validates: %s" % [id, str(issues)])
		for e in shop.stock:
			var it: ItemResource = e.item()
			assert_false(it.catalyst, "%s sells no evolution items yet (DECISIONS.md #28 revision)" % id)
	var general := ShopResource.load_by_id("crownhaven_general")
	assert_not_null(general.entry("mossleaf_tonic"), "the general store sells tonics")
	assert_true(ShopResource.load_by_id("no_such_shop") == null, "an unknown shop is null")
