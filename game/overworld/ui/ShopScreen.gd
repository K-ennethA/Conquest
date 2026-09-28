class_name ShopScreen
extends CanvasLayer

## THE MERCHANT'S SHOP (docs/design/DECISIONS.md #28; OVERWORLD.md §4.8 "ShopScreen") -- the
## grove look at a 1280x720 base, opened by [OpenShopCommand] through the overworld host:
##
##   ribbon  <Shop name>                                         gold pill  ◆ 240
##   greeting line
##   [ BUY ] [ SELL ]                                     Q / E switch
##   ┌ item list ─────────────────────────┐ ┌ detail ───────────────────────────┐
##   │ 🧪 Mossleaf Tonic   ×2   ∞    40 g  │ │ name · category · description      │
##   │ 🌸 Dawnpetal        ×0   2 left 250 │ │ effect                             │
##   │ ...                                │ │ PARTY: what it does to each member │
##   └────────────────────────────────────┘ │ [−] Qty 2 [+]   Total 80 g         │
##                                          │ [ BUY ×2 · 80 G ]   message        │
##                                          └────────────────────────────────────┘
##   Enter Select · ←/→ Quantity · Q/E Buy/Sell · Esc Leave
##
## Keyboard / pad: up / down walk the list (focus = selection, the detail follows); Enter on a row
## moves to the CONFIRM button; left / right change the quantity (on a row or the confirm button);
## Enter on confirm buys / sells; Esc on confirm returns to the list, Esc on the list leaves;
## Q / E (cycle_prev / cycle_next) switch Buy / Sell. Mouse / touch: click a row, the +/- buttons,
## the confirm button, the tabs.
##
## Every rule is [ShopLedger]'s (stock, flag gates, restock, prices, gold, bag room); this screen
## only shows its answers -- "Not enough gold.", "Sold out", "Your bag can't hold any more". The
## party preview uses [method ConsumableEffect.preview_member], the same numbers the bag's Use
## applies. Modal: in [constant InputActions.OVERLAY_GROUP] while open (the overworld hero stands
## still, as for the Journey menu). Leaving saves the journey when anything was bought or sold.

signal closed

const LAYER_INDEX: int = 70
const TAB_BUY: int = 0
const TAB_SELL: int = 1
const LIST_WIDTH: float = 590.0
const DETAIL_WIDTH: float = 470.0

var shop: ShopResource = null
var state: StoryState = null
## The StoryController (duck-typed): ruleset() and save_game(). Optional (tools / tests).
var session = null
var tab: int = TAB_BUY
var selected_id: String = ""
var quantity: int = 1
## Something was bought or sold since the screen opened (the journey is saved on leaving).
var dirty: bool = false

var _root: Control = null
var _title: PanelContainer = null
var _gold: Label = null
var _greeting: Label = null
var _buy_tab: Button = null
var _sell_tab: Button = null
var _list: VBoxContainer = null
var _list_scroll: ScrollContainer = null
var _empty: Label = null
var _d_name: Label = null
var _d_tag: Label = null
var _d_desc: Label = null
var _d_effect: Label = null
var _party_head: Label = null
var _party_box: VBoxContainer = null
var _minus: Button = null
var _plus: Button = null
var _qty: Label = null
var _total: Label = null
var _confirm: Button = null
var _message: Label = null
var _rows: Dictionary = {}


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


# =====================================================================================
#  Public API (the host, tests)
# =====================================================================================

## Show [param p_shop] for the journey [param p_state]. [param p_session]: the StoryController.
func open(p_shop: ShopResource, p_state: StoryState, p_session = null) -> void:
	shop = p_shop
	state = p_state
	session = p_session
	dirty = false
	tab = TAB_BUY
	selected_id = ""
	quantity = 1
	if _root == null:
		_build()
	_root.visible = true
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	_set_title(shop.display_name if shop != null else "Shop")
	_greeting.text = shop.greeting if shop != null else ""
	_greeting.visible = not _greeting.text.is_empty()
	_sell_tab.visible = shop == null or shop.buys_items
	_say("", "")
	refresh()
	_focus_first_row()


func is_open() -> bool:
	return _root != null and _root.visible


## Leave the shop (saves the journey when something changed).
func close() -> void:
	if not is_open():
		return
	_root.visible = false
	_root.remove_from_group(InputActions.OVERLAY_GROUP)
	if dirty and session != null and is_instance_valid(session) and session.has_method(&"save_game"):
		session.save_game()
	closed.emit()


func switch_tab(p_tab: int) -> void:
	if p_tab == TAB_SELL and shop != null and not shop.buys_items:
		return
	tab = p_tab
	selected_id = ""
	quantity = 1
	_say("", "")
	refresh()
	_focus_first_row()


## Select the row of [param item_id] (the detail and the quantity follow). False when not listed.
func select(item_id: String) -> bool:
	if not _rows.has(item_id):
		return false
	if item_id != selected_id:
		quantity = 1
	selected_id = item_id
	_refresh_detail()
	_refresh_row_marks()
	return true


func set_quantity(n: int) -> void:
	quantity = clampi(n, 1, maxi(1, _max_quantity()))
	_refresh_quantity()


func change_quantity(delta: int) -> void:
	set_quantity(quantity + delta)


## Buy / sell [member quantity] of the selected item. The [ShopLedger] result ({ok, reason, ...}).
func confirm() -> Dictionary:
	if state == null or selected_id.is_empty():
		_say("Pick an item first.", "warn")
		return {"ok": false, "reason": ShopLedger.REASON_BAD_QUANTITY}
	var item: ItemResource = ItemLibrary.get_item(selected_id)
	var item_name: String = item.display_name if item != null else selected_id
	var r: Dictionary
	if tab == TAB_BUY:
		r = ShopLedger.buy(shop, state, selected_id, quantity, _ruleset())
		if bool(r["ok"]):
			_say("Bought %s%s for %d gold." % [item_name, " ×%d" % quantity if quantity > 1 else "", int(r["cost"])], "ok")
	else:
		r = ShopLedger.sell(shop, state, selected_id, quantity, _ruleset())
		if bool(r["ok"]):
			_say("Sold %s%s for %d gold." % [item_name, " ×%d" % quantity if quantity > 1 else "", int(r["gold"])], "ok")
	if bool(r["ok"]):
		dirty = true
		var keep: String = selected_id
		refresh()
		if _rows.has(keep):
			select(keep)
		else:
			_focus_first_row()
	else:
		_say(ShopLedger.reason_text(String(r["reason"])), "warn")
	return r


## The status line's text (tests).
func message() -> String:
	return _message.text if _message != null else ""


## The row button of [param item_id] (null when not listed).
func row(item_id: String) -> Button:
	return _rows.get(item_id, null)


func confirm_button() -> Button:
	return _confirm


## Rebuild the list, gold and detail from the ledger.
func refresh() -> void:
	if _root == null:
		return
	_gold.text = "◆  %d gold" % (state.gold if state != null else 0)
	_buy_tab.theme_type_variation = MenuKit.PRIMARY if tab == TAB_BUY else MenuKit.GHOST
	_sell_tab.theme_type_variation = MenuKit.PRIMARY if tab == TAB_SELL else MenuKit.GHOST
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	var rows: Array[Dictionary] = _current_rows()
	for r in rows:
		var b := _make_row(r)
		_list.add_child(b)
		_rows[String(r["item_id"])] = b
	_empty.visible = rows.is_empty()
	_empty.text = "Nothing for sale right now." if tab == TAB_BUY else "Your bag is empty."
	if not _rows.has(selected_id):
		selected_id = String(rows[0]["item_id"]) if not rows.is_empty() else ""
		quantity = 1
	_refresh_detail()
	_refresh_row_marks()


# =====================================================================================
#  Build
# =====================================================================================

func _build() -> void:
	if _root != null:
		return
	_root = Control.new()
	_root.name = "ShopRoot"
	_root.theme = ConquestTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(MenuTheme.BG_DEEP, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var card := PanelContainer.new()
	card.name = "ShopCard"
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(18)
	sb.content_margin_top = 26
	card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(card)
	margin.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_S)
	card.add_child(col)

	# Header: the shop's ribbon, the gold pill.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(head)
	_title = ConquestTheme.title_ribbon("SHOP", MenuTheme.GOLD_DK, MenuTheme.FS_SUBHEADING)
	_title.name = "ShopTitle"
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var gold_pill := PanelContainer.new()
	gold_pill.name = "GoldPill"
	gold_pill.add_theme_stylebox_override("panel", MenuTheme.pill_box(Color(MenuTheme.GOLD_DK, 0.35), MenuTheme.GOLD))
	ConquestTheme.keep_style(gold_pill)
	gold_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(gold_pill)
	_gold = Label.new()
	_gold.name = "Gold"
	_gold.add_theme_font_override("font", MenuTheme.heading_font(1))
	_gold.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	_gold.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	gold_pill.add_child(_gold)

	_greeting = MenuKit.label("", &"DimLabel", true)
	_greeting.name = "Greeting"
	_greeting.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(_greeting)

	# Tabs.
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", MenuTheme.SP_S)
	col.add_child(tabs)
	_buy_tab = MenuKit.button("Buy", MenuKit.PRIMARY, 130, 38)
	_buy_tab.name = "BuyTab"
	_buy_tab.pressed.connect(func() -> void: switch_tab(TAB_BUY))
	tabs.add_child(_buy_tab)
	_sell_tab = MenuKit.button("Sell", MenuKit.GHOST, 130, 38)
	_sell_tab.name = "SellTab"
	_sell_tab.pressed.connect(func() -> void: switch_tab(TAB_SELL))
	tabs.add_child(_sell_tab)
	var tab_hint := MenuKit.key_hint("Q / E", "LB / RB", "switch")
	tab_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tabs.add_child(tab_hint)

	var rule := GroveRule.new()
	rule.custom_minimum_size = Vector2(0, 10)
	col.add_child(rule)

	# Body: the list | the detail.
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(LIST_WIDTH, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	body.add_child(left)
	left.add_child(_list_header())
	_list_scroll = ScrollContainer.new()
	_list_scroll.name = "ListScroll"
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	left.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.name = "ItemList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_list_scroll.add_child(_list)
	_empty = MenuKit.label("", &"DimLabel")
	_empty.name = "Empty"
	_empty.visible = false
	left.add_child(_empty)

	var detail := PanelContainer.new()
	detail.name = "Detail"
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail.add_theme_stylebox_override("panel", MenuTheme.inset_box())
	ConquestTheme.keep_style(detail)
	body.add_child(detail)
	var dcol := VBoxContainer.new()
	dcol.add_theme_constant_override("separation", MenuTheme.SP_XS)
	detail.add_child(dcol)
	_d_name = MenuKit.label("", &"SubheadingLabel")
	_d_name.name = "DetailName"
	dcol.add_child(_d_name)
	_d_tag = MenuKit.label("", &"SectionLabel")
	_d_tag.name = "DetailTag"
	dcol.add_child(_d_tag)
	_d_desc = MenuKit.label("", &"DimLabel", true)
	_d_desc.name = "DetailDesc"
	_d_desc.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	dcol.add_child(_d_desc)
	_d_effect = MenuKit.label("", &"", true)
	_d_effect.name = "DetailEffect"
	_d_effect.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_d_effect.add_theme_color_override("font_color", MenuTheme.SUCCESS)
	dcol.add_child(_d_effect)
	_party_head = MenuKit.section("Your party")
	_party_head.name = "PartyHead"
	dcol.add_child(_party_head)
	# The party preview scrolls (a party of six must not push the card off screen).
	var party_scroll := ScrollContainer.new()
	party_scroll.name = "PartyScroll"
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dcol.add_child(party_scroll)
	_party_box = VBoxContainer.new()
	_party_box.name = "PartyPreview"
	_party_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_box.add_theme_constant_override("separation", 3)
	party_scroll.add_child(_party_box)

	var qrow := HBoxContainer.new()
	qrow.name = "QuantityRow"
	qrow.add_theme_constant_override("separation", MenuTheme.SP_S)
	dcol.add_child(qrow)
	_minus = MenuKit.button("−", MenuKit.GHOST, 44, 36)
	_minus.name = "Minus"
	_minus.focus_mode = Control.FOCUS_NONE
	_minus.pressed.connect(func() -> void: change_quantity(-1))
	qrow.add_child(_minus)
	_qty = MenuKit.label("Qty 1", &"SubheadingLabel")
	_qty.name = "Quantity"
	_qty.custom_minimum_size = Vector2(84, 0)
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qrow.add_child(_qty)
	_plus = MenuKit.button("+", MenuKit.GHOST, 44, 36)
	_plus.name = "Plus"
	_plus.focus_mode = Control.FOCUS_NONE
	_plus.pressed.connect(func() -> void: change_quantity(1))
	qrow.add_child(_plus)
	_total = MenuKit.label("", &"")
	_total.name = "Total"
	_total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_total.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	qrow.add_child(_total)

	_confirm = MenuKit.button("Buy", MenuKit.PRIMARY, 0, 46)
	_confirm.name = "Confirm"
	_confirm.pressed.connect(func() -> void: confirm())
	dcol.add_child(_confirm)
	_message = MenuKit.label("", &"DimLabel", true)
	_message.name = "Message"
	_message.custom_minimum_size = Vector2(0, 24)
	_message.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	dcol.add_child(_message)

	# Footer hints.
	var hints := HBoxContainer.new()
	hints.name = "Hints"
	hints.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(hints)
	hints.add_child(MenuKit.key_hint("Enter", "A", "Select"))
	hints.add_child(MenuKit.key_hint("← →", "◀ ▶", "Quantity"))
	hints.add_child(MenuKit.key_hint("Esc", "B", "Back / Leave"))


func _list_header() -> MarginContainer:
	# Inset like the rows' labels (the row box's leaf marker sits in the first 30 px).
	var wrap := MarginContainer.new()
	wrap.name = "ListHeader"
	wrap.add_theme_constant_override("margin_left", 30)
	wrap.add_theme_constant_override("margin_right", 14)
	var h := HBoxContainer.new()
	wrap.add_child(h)
	h.add_theme_constant_override("separation", MenuTheme.SP_S)
	for spec in [["Item", 0.0, true], ["Owned", 72.0, false], ["Stock", 92.0, false], ["Price", 86.0, false]]:
		var l := MenuKit.section(String(spec[0]))
		if bool(spec[2]):
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size = Vector2(0, 0)
		else:
			l.custom_minimum_size = Vector2(float(spec[1]), 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(l)
	return wrap


## One list row: a focusable MenuItem button whose labels are the columns.
func _make_row(r: Dictionary) -> Button:
	var item: ItemResource = r["item"]
	var id: String = String(r["item_id"])
	var b := Button.new()
	b.name = "Row_" + id
	b.theme_type_variation = &"HudCommand"
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta(&"item_id", id)
	b.pressed.connect(_on_row_pressed.bind(id))
	b.focus_entered.connect(_on_row_focused.bind(id))
	MenuNav.hover_focus(b)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 30
	h.offset_right = -14
	h.add_theme_constant_override("separation", MenuTheme.SP_S)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var name_l := _cell("%s  %s" % [item.icon_hint, item.display_name], 0.0, HORIZONTAL_ALIGNMENT_LEFT)
	name_l.name = "Name"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_l)
	var owned := _cell("×%d" % int(r["owned"]), 72.0)
	owned.name = "Owned"
	owned.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	h.add_child(owned)
	var stock_text: String = ""
	var price_text: String = ""
	var unavailable: bool = false
	if tab == TAB_BUY:
		var left: int = int(r["remaining"])
		stock_text = "—" if left < 0 else ("Sold out" if left == 0 else "%d left" % left)
		price_text = "%d g" % int(r["price"])
		unavailable = bool(r["sold_out"])
	else:
		stock_text = ""
		price_text = "%d g" % int(r["price"]) if bool(r["sellable"]) else "—"
		unavailable = not bool(r["sellable"])
	var stock := _cell(stock_text, 92.0)
	stock.name = "Stock"
	stock.add_theme_color_override("font_color", MenuTheme.DANGER if stock_text == "Sold out" else MenuTheme.TEXT_DIM)
	h.add_child(stock)
	var price := _cell(price_text, 86.0)
	price.name = "Price"
	price.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	h.add_child(price)
	if unavailable:
		name_l.add_theme_color_override("font_color", MenuTheme.TEXT_MUTED)
	return b


func _cell(text: String, width: float, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _set_title(text: String) -> void:
	var l := _title.get_node_or_null("Text") as Label
	if l == null:
		l = _title.find_child("*", true, false) as Label
	if l != null:
		l.text = text.to_upper()


# =====================================================================================
#  Detail
# =====================================================================================

func _current_rows() -> Array[Dictionary]:
	if tab == TAB_BUY:
		return ShopLedger.buy_rows(shop, state)
	return ShopLedger.sell_rows(shop, state, _ruleset())


func _current_row() -> Dictionary:
	for r in _current_rows():
		if String(r["item_id"]) == selected_id:
			return r
	return {}


func _refresh_detail() -> void:
	var r: Dictionary = _current_row()
	var has: bool = not r.is_empty()
	for n in [_d_name, _d_tag, _d_desc, _d_effect, _party_head, _party_box, _minus, _plus, _qty, _total, _confirm]:
		(n as Control).visible = has
	if not has:
		return
	var item: ItemResource = r["item"]
	_d_name.text = "%s  %s" % [item.icon_hint, item.display_name]
	var tag: String = item.category_name()
	if tab == TAB_BUY:
		tag += "  ·  %d gold each" % int(r["price"])
	else:
		tag += "  ·  sells for %d gold each" % int(r["price"]) if bool(r["sellable"]) else "  ·  not bought here"
	_d_tag.text = tag.to_upper()
	_d_desc.text = item.description
	_d_effect.text = item.effect_summary()
	_fill_party(item)
	_refresh_quantity()


## What the item would do to each member (the party preview).
func _fill_party(item: ItemResource) -> void:
	for c in _party_box.get_children():
		_party_box.remove_child(c)
		c.queue_free()
	if state == null or state.party.is_empty():
		var none := MenuKit.label("No partner yet.", &"MutedLabel")
		none.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		_party_box.add_child(none)
		return
	for m in state.party:
		_party_box.add_child(_party_row(m, item))


func _party_row(m: StoryPartyMember, item: ItemResource) -> Control:
	var row := HBoxContainer.new()
	row.name = "Member_" + m.member_id.replace("#", "_")
	row.add_theme_constant_override("separation", MenuTheme.SP_S)
	var c: CharacterResource = m.character()
	var el: Color = MenuKit.element_color(String(c.element)) if c != null else MenuTheme.GOLD
	var crest := ConquestTheme.portrait(m.display_name().substr(0, 1), el, MenuTheme.GOLD_DK, 28)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crest)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 1)
	row.add_child(col)
	var down: bool = ConsumableEffect.member_is_down(m)
	var name_l := Label.new()
	name_l.text = "%s   %s" % [m.display_name(), "Knocked out" if down else "HP %d / %d" % [m.hp_value(), m.max_hp()]]
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(name_l)
	var effect := Label.new()
	effect.name = "Effect"
	effect.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	var good: bool = false
	if item.is_consumable():
		var p: Dictionary = item.consumable.preview_member(m)
		good = bool(p["ok"])
		if good:
			if bool(p["revived"]):
				effect.text = "Revives → HP %d / %d" % [int(p["hp_after"]), m.max_hp()]
			else:
				effect.text = "HP %d → %d  (+%d)" % [int(p["hp_before"]), int(p["hp_after"]), int(p["healed"])]
		elif String(p["reason"]) == "not_in_field":
			effect.text = "Used in battle: %s" % item.consumable.summary().to_lower()
			good = true
		else:
			effect.text = ConsumableEffect.reason_text(String(p["reason"]), m.display_name())
	elif item.is_equipment():
		var holding: ItemResource = ItemLibrary.get_item(m.item_id) if not m.item_id.is_empty() else null
		effect.text = ("Could hold it: %s" % item.effect_summary()) if holding == null \
			else "Holds %s now" % holding.display_name
		good = holding == null
	else:
		effect.text = "—"
	effect.add_theme_color_override("font_color", MenuTheme.SUCCESS if good else MenuTheme.TEXT_MUTED)
	col.add_child(effect)
	return row


func _max_quantity() -> int:
	if state == null or selected_id.is_empty():
		return 1
	if tab == TAB_BUY:
		return ShopLedger.max_buy(shop, state, selected_id, _ruleset())
	var r: Dictionary = _current_row()
	return int(r.get("owned", 1)) if bool(r.get("sellable", false)) else 1


func _refresh_quantity() -> void:
	var r: Dictionary = _current_row()
	if r.is_empty():
		return
	var cap: int = maxi(1, _max_quantity())
	quantity = clampi(quantity, 1, cap)
	_qty.text = "Qty %d" % quantity
	var each: int = int(r["price"])
	var total: int = each * quantity
	_minus.disabled = quantity <= 1
	_plus.disabled = quantity >= cap
	if tab == TAB_BUY:
		_total.text = "Total %d g" % total
		_confirm.text = "Buy ×%d  ·  %d g" % [quantity, total]
		var short: bool = state != null and state.gold < total
		_total.add_theme_color_override("font_color", MenuTheme.DANGER if short else MenuTheme.GOLD_LITE)
	else:
		_total.text = "You get %d g" % total if bool(r["sellable"]) else "Not bought here"
		_confirm.text = "Sell ×%d  ·  %d g" % [quantity, total]
		_total.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)


func _refresh_row_marks() -> void:
	for id in _rows:
		var b: Button = _rows[id]
		b.modulate = Color(1, 1, 1, 1) if id == selected_id else Color(0.86, 0.86, 0.86, 1)


func _say(text: String, tone: String) -> void:
	if _message != null:
		MenuKit.set_status(_message, text, tone)


func _ruleset() -> StoryRuleset:
	if session != null and is_instance_valid(session) and session.has_method(&"ruleset"):
		var rs = session.ruleset()
		if rs is StoryRuleset:
			return rs
	return StoryRuleset.load_default()


# =====================================================================================
#  Input
# =====================================================================================

func _on_row_focused(item_id: String) -> void:
	select(item_id)


func _on_row_pressed(item_id: String) -> void:
	select(item_id)
	var r: Dictionary = _current_row()
	if tab == TAB_BUY and bool(r.get("sold_out", false)):
		_say(ShopLedger.reason_text(ShopLedger.REASON_SOLD_OUT), "warn")
		return
	if tab == TAB_SELL and not bool(r.get("sellable", false)):
		_say(ShopLedger.reason_text(ShopLedger.REASON_NO_VALUE), "warn")
		return
	_confirm.grab_focus()


func _focus_first_row() -> void:
	var target: Button = _rows.get(selected_id, null)
	if target == null and _list.get_child_count() > 0:
		target = _list.get_child(0) as Button
	# Deferred and safe: a refresh may repaint the rows before the call runs.
	if target != null:
		MenuNav.focus_deferred(target)
	elif _buy_tab != null:
		MenuNav.focus_deferred(_buy_tab)


func _focused() -> Control:
	var vp := get_viewport()
	return vp.gui_get_focus_owner() if vp != null else null


func _input(event: InputEvent) -> void:
	if not is_open() or not event.is_pressed():
		return
	var f: Control = _focused()
	var on_row: bool = f != null and _list.is_ancestor_of(f)
	# Left / right change the quantity on a row or the confirm button (before focus navigation).
	if (on_row or f == _confirm) and (event.is_action_pressed(&"ui_left") or event.is_action_pressed(&"ui_right")):
		change_quantity(-1 if event.is_action_pressed(&"ui_left") else 1)
		get_viewport().set_input_as_handled()
		return
	if MenuNav.is_next_event(event) or (event is InputEventKey and (event as InputEventKey).keycode == KEY_E and not event.is_echo()):
		switch_tab(TAB_SELL)
		get_viewport().set_input_as_handled()
		return
	if MenuNav.is_prev_event(event) or (event is InputEventKey and (event as InputEventKey).keycode == KEY_Q and not event.is_echo()):
		switch_tab(TAB_BUY)
		get_viewport().set_input_as_handled()
		return
	if MenuNav.is_back_event(event) or event.is_action_pressed(InputActions.MAP_MENU):
		get_viewport().set_input_as_handled()
		if f == _confirm:
			var back: Button = _rows.get(selected_id, null)
			if back != null:
				back.grab_focus()
				return
		close()
