class_name JourneyMenu
extends CanvasLayer

## The JOURNEY MENU (Esc / Start on the overworld) -- the grove MapMenu look: a gold-framed card
## of command rows: Resume · Party · Quests · Bag · Map · Difficulty · Settings · Load · Save · Title
## (docs/design/OVERWORLD.md §4.10). Modal: in InputActions.OVERLAY_GROUP while open. The card's
## footer line is the journey summary: where you are, gold, play time and the current objective.
##
## QUESTS: the flag-derived log ([QuestLog], data in content/quests.json) -- active quests with their
## step checklist, finished ones below. MAP: the current place, where a whiteout would send you and
## every area visited (there is no world-map scene yet; this is its place in the menu).
## PARTY DETAILS: a member's "Details" opens [PartyDetailPage] (stats, equipment, moves, abilities)
## in the Party page; Equip / Unequip go through the session. SETTINGS: the shared [SettingsPanel].
## LOAD: reloads the slot's last save behind a second press.
##
## FALLEN (docs/design/DECISIONS.md #29, Classic): the Party page ends with a "Fallen" section --
## one muted card per member that fell for good, saying where and when (their growth and form are
## kept on the record; they are out of every squad, duel, heal and revive).
## DIFFICULTY (#29 refinements): the journey's tier and what it means; a Classic journey may
## LOWER to Casual behind a confirm ("you can't go back up") -- never the other way.
##
## PARTY (docs/design/DECISIONS.md #27 "evolve later"): one card per member -- HP, and for a
## member in an evolution line its REQUIREMENTS CHECKLIST per next form ([RequirementChecklist],
## branching shows every edge), an EVOLVE / PROMOTE button while an evolution is due (now, or by
## using an item the bag holds) and the HOLD toggle (no automatic prompts; the button still works).
## BAG (#26 "use an item", #28 consumables): the story bag; an item some evolution USES
## ([UseItemTrigger]) and every CONSUMABLE (heal / cure / revive) lists "Use on" buttons, one per
## member -- a consumable's button shows the member's HP and is DISABLED (with the reason) when it
## would be wasted (full HP, a healthy member for a revive, nothing to cure out of battle).
##
## The actions go through [member session] (the StoryController autoload: evolve_from_menu,
## set_member_hold, use_item_on_member); without one (tools) Hold is written straight onto the
## member. Keyboard / pad: the command rows lead right into the open page; Esc from inside a page
## returns to its row, Esc on the rows closes the menu.

const LAYER_INDEX: int = 60
const PAGE_WIDTH: float = 470.0

signal closed
signal save_requested
signal title_requested

## The journey actions ([method evolve_from_menu] etc.) -- the StoryController (duck-typed).
var session = null

var _root: Control = null
var _card: PanelContainer = null
var _rows: VBoxContainer = null
var _party_scroll: ScrollContainer = null
var _party: VBoxContainer = null
var _bag_scroll: ScrollContainer = null
var _bag: VBoxContainer = null
var _tier_scroll: ScrollContainer = null
var _tier: VBoxContainer = null
var _tier_row: Button = null
## The Difficulty page is asking "are you sure?" before lowering the tier.
var _tier_confirming: bool = false
var _status: Label = null
var _buttons: Array[Button] = []
var _state: StoryState = null
var _party_row: Button = null
var _bag_row: Button = null
var _quest_scroll: ScrollContainer = null
var _quest: VBoxContainer = null
var _quests_row: Button = null
var _map_scroll: ScrollContainer = null
var _map: VBoxContainer = null
var _map_row: Button = null
var _load_row: Button = null
var _settings: SettingsPanel = null
## The Party page shows this member's detail page ("" = the list).
var _detail_id: String = ""
## Load is waiting for its second press ("unsaved progress is lost").
var _load_confirming: bool = false
## A session call (an Evolution screen) is in flight: page input waits.
var _busy: bool = false


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "JourneyRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = ConquestTheme.build()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.BG_DEEP, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_card = PanelContainer.new()
	_card.name = "JourneyCard"
	_card.custom_minimum_size = Vector2(300, 0)
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(18)
	sb.content_margin_top = 26
	_card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(_card)
	row.add_child(_card)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_card.add_child(_rows)
	var title := ConquestTheme.title_ribbon("JOURNEY", MenuTheme.GOLD_DK, MenuTheme.FS_SUBHEADING)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(title)
	_add_row("Resume", close)
	_party_row = _add_row("Party", _toggle_party)
	_quests_row = _add_row("Quests", _toggle_quests)
	_bag_row = _add_row("Bag", _toggle_bag)
	_map_row = _add_row("Map", _toggle_map)
	_tier_row = _add_row("Difficulty", _toggle_tier)
	_add_row("Settings", func() -> void: _settings.open())
	_load_row = _add_row("Load", _on_load_pressed)
	_add_row("Save", func() -> void: save_requested.emit())
	_add_row("Title Screen", func() -> void: title_requested.emit())
	_status = MenuKit.label("", &"DimLabel", true)
	_status.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size = Vector2(264, 0)
	_rows.add_child(_status)

	_party_scroll = _page_scroll("PartyScroll")
	row.add_child(_party_scroll)
	_party = _page_box("PartyPanel")
	_party_scroll.add_child(_party)
	_bag_scroll = _page_scroll("BagScroll")
	row.add_child(_bag_scroll)
	_bag = _page_box("BagPanel")
	_bag_scroll.add_child(_bag)
	_tier_scroll = _page_scroll("TierScroll")
	row.add_child(_tier_scroll)
	_tier = _page_box("TierPanel")
	_tier_scroll.add_child(_tier)
	_quest_scroll = _page_scroll("QuestScroll")
	row.add_child(_quest_scroll)
	_quest = _page_box("QuestPanel")
	_quest_scroll.add_child(_quest)
	_map_scroll = _page_scroll("MapScroll")
	row.add_child(_map_scroll)
	_map = _page_box("MapPanel")
	_map_scroll.add_child(_map)
	# The ONE settings surface (SettingsPanel), mounted on this layer so it draws over the menu --
	# the same arrangement PauseMenu uses.
	_settings = SettingsPanel.new()
	_settings.name = "JourneySettingsPanel"
	add_child(_settings)


func _page_scroll(node_name: String) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = node_name
	s.custom_minimum_size = Vector2(PAGE_WIDTH + 16, 0)
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.follow_focus = true
	s.visible = false
	return s


func _page_box(node_name: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = node_name
	v.custom_minimum_size = Vector2(PAGE_WIDTH, 0)
	v.add_theme_constant_override("separation", 8)
	return v


func _add_row(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.replace(" ", "") + "Row"
	b.theme_type_variation = &"HudCommand"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	MenuNav.hover_focus(b)
	_rows.add_child(b)
	_buttons.append(b)
	return b


func is_open() -> bool:
	return _root.visible


func open(state: StoryState) -> void:
	_state = state
	_hide_pages_except(null)
	_detail_id = ""
	_load_confirming = false
	_refresh_summary()
	_root.visible = true
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	_root.remove_from_group(InputActions.OVERLAY_GROUP)
	closed.emit()


func set_status(text: String) -> void:
	_status.text = text


# =====================================================================================
#  Party
# =====================================================================================

func _toggle_party() -> void:
	var show: bool = not _party_scroll.visible
	_hide_pages_except(_party_scroll)
	_detail_id = ""
	_party_scroll.visible = show
	if show:
		refresh_party()
	_link_rows_to(_party_scroll if show else null)


## True while the Party page is up.
func is_party_open() -> bool:
	return _party_scroll.visible


## Open the Party page (tests, a "check your party" hint).
func show_party() -> void:
	if not _party_scroll.visible:
		_toggle_party()


## Rebuild the Party page from the journey (after an evolution / a Hold change).
func refresh_party() -> void:
	for c in _party.get_children():
		_party.remove_child(c)
		c.queue_free()
	if _state == null:
		return
	if not _detail_id.is_empty():
		var dm: StoryPartyMember = _state.member(_detail_id)
		if dm != null:
			_party.add_child(PartyDetailPage.build(dm, _state, _state.lead() == dm, show_member_detail.bind(""),
				_on_equip_pressed.bind(dm.member_id), _on_unequip_pressed.bind(dm.member_id)))
			_link_rows_to(_party_scroll)
			return
		_detail_id = ""
	var head := ConquestTheme.title_ribbon("PARTY", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_party.add_child(head)
	var ctx: Dictionary = StoryGrowth.evolution_context(_state, {"trigger": "menu"})
	for i in range(_state.party.size()):
		_party.add_child(_member_card(_state.party[i], i == 0, ctx))
	if not _state.fallen.is_empty():
		var fh := ConquestTheme.title_ribbon("FALLEN", MenuTheme.TEAM_RED, MenuTheme.FS_BODY)
		fh.name = "FallenHeading"
		fh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_party.add_child(fh)
		for f in _state.fallen:
			_party.add_child(_fallen_card(f))
	_link_rows_to(_party_scroll)


func _member_card(m: StoryPartyMember, is_lead: bool, ctx: Dictionary) -> PanelContainer:
	var c: CharacterResource = m.character()
	var el_col: Color = MenuKit.element_color(String(c.element)) if c != null else MenuTheme.GOLD
	var card := PanelContainer.new()
	card.name = "Member_" + m.member_id.replace("#", "_")
	card.set_meta(&"member_id", m.member_id)
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(el_col))
	ConquestTheme.keep_style(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var portrait := ConquestTheme.portrait(m.display_name().substr(0, 1), el_col, MenuTheme.GOLD_DK, 44)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	PartyDetailPage.apply_portrait(portrait, c)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var form_name: String = c.display_name if c != null else m.character_id.capitalize()
	var title: String = m.display_name()
	if title != form_name:
		title += "  ·  " + form_name
	var name_l := MenuKit.label(title + ("  ·  Lead" if is_lead else ""), &"SubheadingLabel")
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	col.add_child(name_l)
	var bar := ConquestTheme.hp_bar(10.0)
	bar.max_value = m.max_hp()
	bar.value = m.hp_value()
	ConquestTheme.tint_hp_bar(bar, float(m.hp_value()) / float(maxi(1, m.max_hp())))
	col.add_child(bar)
	var hp := MenuKit.label("HP %d / %d%s" % [m.hp_value(), m.max_hp(), "  ·  Wounded" if m.wounded else ""], &"DimLabel")
	hp.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(hp)
	var worn: ItemResource = ItemLibrary.get_item(m.item_id) if not m.item_id.is_empty() else null
	if worn != null:
		var gear := MenuKit.label("Holding: " + worn.display_name, &"DimLabel")
		gear.name = "Holding"
		gear.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(gear)
	var details := MenuKit.button("Details", MenuKit.GHOST, 110, 34)
	details.name = "DetailsButton"
	details.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	details.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	details.pressed.connect(show_member_detail.bind(m.member_id))
	col.add_child(details)
	_add_evolution_section(col, m, ctx)
	return card


## A FALLEN member's card: muted, no actions -- its name and form, and where / when it fell.
func _fallen_card(m: StoryPartyMember) -> PanelContainer:
	var c: CharacterResource = m.character()
	var card := PanelContainer.new()
	card.name = "Fallen_" + m.member_id.replace("#", "_")
	card.set_meta(&"fallen_member_id", m.member_id)
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(MenuTheme.TEAM_RED.darkened(0.2),
		SIDE_LEFT, MenuTheme.PANEL_SUNK))
	ConquestTheme.keep_style(card)
	card.modulate = Color(1, 1, 1, 0.82)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var portrait := ConquestTheme.portrait(m.display_name().substr(0, 1), MenuTheme.TEXT_MUTED.darkened(0.35),
		MenuTheme.BORDER, 40)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)
	var form_name: String = c.display_name if c != null else m.character_id.capitalize()
	var title: String = m.display_name()
	if title != form_name:
		title += "  ·  " + form_name
	var name_l := MenuKit.label(title + "  ·  Fallen", &"SubheadingLabel")
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	name_l.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	col.add_child(name_l)
	var where := MenuKit.label(fallen_line(m), &"DimLabel", true)
	where.name = "FellWhere"
	where.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(where)
	return card


## "Fell at the Mossway against Bram  ·  1h 05m into the journey" for a fallen member.
static func fallen_line(m: StoryPartyMember) -> String:
	var info: Dictionary = m.fallen_info
	var area_id: String = String(info.get("area_id", ""))
	var area: OverworldAreaResource = OverworldAreaResource.load_by_id(area_id) if not area_id.is_empty() else null
	var place: String = area.display_name if area != null and not area.display_name.is_empty() else area_id.capitalize()
	var out: String = "Fell"
	if not place.is_empty():
		out += " at " + place
	var foe: String = String(info.get("foe", ""))
	if not foe.is_empty():
		out += " against " + foe
	out += "  ·  %s into the journey" % StorySnapshot.format_play_time(int(info.get("play_seconds", 0)))
	var item_id: String = String(info.get("item_id", ""))
	if not item_id.is_empty():
		var item: ItemResource = ItemLibrary.get_item(item_id)
		out += "  ·  %s returned to the bag" % (item.display_name if item != null else item_id)
	return out


## The member's evolution block: checklist per next form, EVOLVE (when due) and HOLD. Nothing for
## a member in no line; "Final form" for the end of one.
func _add_evolution_section(col: VBoxContainer, m: StoryPartyMember, ctx: Dictionary) -> void:
	if not EvolutionLibrary.in_any_line(m.character_id):
		return
	var entries: Array[Dictionary] = StoryGrowth.checklists(m, ctx)
	if entries.is_empty():
		var fin := MenuKit.label("Final form", &"MutedLabel")
		fin.name = "FinalForm"
		fin.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(fin)
		return
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	col.add_child(sep)
	var checklist := RequirementChecklist.build(entries)
	col.add_child(checklist)
	var actions := HBoxContainer.new()
	actions.name = "EvolveActions"
	actions.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(actions)
	var menu: Dictionary = StoryGrowth.menu_edges(m, ctx)
	var due: Array = menu["edges"]
	if not due.is_empty():
		var verb: String = (due[0] as EvolutionResource).verb()
		var b := MenuKit.button(verb, MenuKit.PRIMARY, 130, 38)
		b.name = "EvolveButton"
		b.pressed.connect(_on_evolve_pressed.bind(m.member_id))
		actions.add_child(b)
	var hold := CheckButton.new()
	hold.name = "HoldToggle"
	hold.text = "Hold"
	hold.button_pressed = m.hold
	hold.focus_mode = Control.FOCUS_ALL
	hold.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	hold.tooltip_text = "Hold: no automatic %s prompts for %s. You can still %s from here." % [
		(due[0] as EvolutionResource).noun() if not due.is_empty() else "evolution", m.display_name(),
		(due[0] as EvolutionResource).verb().to_lower() if not due.is_empty() else "evolve"]
	hold.toggled.connect(_on_hold_toggled.bind(m.member_id))
	MenuNav.hover_focus(hold)
	actions.add_child(hold)
	if m.hold:
		var held := MenuKit.label("On hold -- no automatic prompts", &"MutedLabel")
		held.name = "HoldNote"
		held.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		held.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		actions.add_child(held)


func _on_evolve_pressed(member_id: String) -> void:
	if _busy or session == null or not session.has_method(&"evolve_from_menu"):
		return
	_busy = true
	var r: Dictionary = await session.evolve_from_menu(member_id)
	_busy = false
	if not is_inside_tree():
		return
	if bool(r.get("evolved", false)):
		set_status("%s changed form." % _member_name(member_id))
	refresh_party()
	_focus_member_control(member_id, ["EvolveButton", "HoldToggle"])


func _on_hold_toggled(on: bool, member_id: String) -> void:
	if session != null and session.has_method(&"set_member_hold"):
		session.set_member_hold(member_id, on)
	elif _state != null and _state.member(member_id) != null:
		_state.member(member_id).hold = on
	set_status(("%s is on hold: no automatic prompts." if on else "%s: automatic prompts are back on.") \
		% _member_name(member_id))
	# Rebuild (the note) once the toggle's own signal has unwound.
	call_deferred(&"_refresh_after_hold", member_id)


func _refresh_after_hold(member_id: String) -> void:
	if not is_inside_tree() or not _party_scroll.visible:
		return
	refresh_party()
	_focus_member_control(member_id, ["HoldToggle"])


## The member card of [param member_id] on the Party page (null when not shown).
func member_card(member_id: String) -> PanelContainer:
	for c in _party.get_children():
		if c is PanelContainer and c.has_meta(&"member_id") and String(c.get_meta(&"member_id")) == member_id:
			return c
	return null


func _focus_member_control(member_id: String, names: Array) -> void:
	var card := member_card(member_id)
	if card == null:
		return
	for n in names:
		var found: Array = card.find_children(String(n), "", true, false)
		if not found.is_empty() and found[0] is Control and (found[0] as Control).is_visible_in_tree():
			(found[0] as Control).grab_focus()
			return


func _member_name(member_id: String) -> String:
	var m: StoryPartyMember = _state.member(member_id) if _state != null else null
	return m.display_name() if m != null else member_id


# =====================================================================================
#  Bag
# =====================================================================================

func _toggle_bag() -> void:
	var show: bool = not _bag_scroll.visible
	_hide_pages_except(_bag_scroll)
	_bag_scroll.visible = show
	if show:
		refresh_bag()
	_link_rows_to(_bag_scroll if show else null)


func is_bag_open() -> bool:
	return _bag_scroll.visible


func show_bag() -> void:
	if not _bag_scroll.visible:
		_toggle_bag()


func refresh_bag() -> void:
	for c in _bag.get_children():
		_bag.remove_child(c)
		c.queue_free()
	if _state == null:
		return
	var head := ConquestTheme.title_ribbon("BAG", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_bag.add_child(head)
	var ids: Array = _state.bag.keys()
	ids.sort()
	var usable: PackedStringArray = StoryGrowth.usable_item_ids()
	var shown: int = 0
	for id in ids:
		var item: ItemResource = ItemLibrary.get_item(String(id))
		if item == null or _state.item_count(String(id)) <= 0:
			continue
		_bag.add_child(_item_card(item, _state.item_count(String(id)), usable.has(String(id)) or item.is_consumable()))
		shown += 1
	if shown == 0:
		var empty := MenuKit.label("Your bag is empty.", &"DimLabel")
		empty.name = "EmptyBag"
		_bag.add_child(empty)
	_link_rows_to(_bag_scroll)


func _item_card(item: ItemResource, count: int, usable: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Item_" + String(item.id)
	card.set_meta(&"item_id", String(item.id))
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(MenuTheme.GOLD))
	ConquestTheme.keep_style(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var name_l := MenuKit.label("%s  %s   ×%d" % [item.icon_hint, item.display_name, count], &"SubheadingLabel")
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	col.add_child(name_l)
	if not item.description.is_empty():
		var d := MenuKit.label(item.description, &"DimLabel", true)
		d.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(d)
	if item.is_consumable():
		var fx := MenuKit.label(item.effect_summary(), &"DimLabel", true)
		fx.name = "Effect"
		fx.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		fx.add_theme_color_override("font_color", MenuTheme.SUCCESS)
		col.add_child(fx)
	if not usable or _state.party.is_empty():
		return card
	var use_row := HFlowContainer.new()
	use_row.name = "UseOn"
	use_row.add_theme_constant_override("h_separation", MenuTheme.SP_S)
	use_row.add_theme_constant_override("v_separation", MenuTheme.SP_XS)
	col.add_child(use_row)
	var cap := MenuKit.label("Use on", &"SectionLabel")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	use_row.add_child(cap)
	for m in _state.party:
		var text: String = m.display_name()
		if item.is_consumable():
			text += "  %s" % ("KO" if ConsumableEffect.member_is_down(m) else "%d/%d" % [m.hp_value(), m.max_hp()])
		var b := MenuKit.button(text, MenuKit.GHOST, 0, 34)
		b.name = "Use_" + m.member_id.replace("#", "_")
		b.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		if item.is_consumable():
			var check: Dictionary = item.consumable.check_member(m)
			b.disabled = not bool(check["ok"])
			b.tooltip_text = ConsumableEffect.reason_text(String(check["reason"]), m.display_name()) 				if b.disabled else "Use the %s on %s." % [item.display_name, m.display_name()]
		b.pressed.connect(_on_use_pressed.bind(String(item.id), m.member_id))
		use_row.add_child(b)
	return card


func _on_use_pressed(item_id: String, member_id: String) -> void:
	if _busy or session == null or not session.has_method(&"use_item_on_member"):
		return
	_busy = true
	var r: Dictionary = await session.use_item_on_member(item_id, member_id)
	_busy = false
	if not is_inside_tree():
		return
	var item: ItemResource = ItemLibrary.get_item(item_id)
	var item_name: String = item.display_name if item != null else item_id
	var reason: String = String(r.get("reason", ""))
	match reason:
		"no_effect":
			set_status("The %s has no effect on %s." % [item_name, _member_name(member_id)])
		"no_item":
			set_status("No %s left." % item_name)
		"":
			if bool(r.get("used", false)):
				if bool(r.get("revived", false)):
					set_status("%s is back on its feet!" % _member_name(member_id))
				else:
					set_status("%s recovered %d HP." % [_member_name(member_id), int(r.get("healed", 0))])
			elif bool(r.get("evolved", false)):
				set_status("The %s was used on %s." % [item_name, _member_name(member_id)])
			else:
				set_status("Not now -- the %s stays in your bag." % item_name)
		_:
			set_status(ConsumableEffect.reason_text(reason, _member_name(member_id)))
	refresh_bag()
	var card: Node = _bag.find_child("Item_" + item_id, true, false)
	var focus: Node = card.find_child("Use_" + member_id.replace("#", "_"), true, false) if card != null else null
	if focus is Control:
		(focus as Control).grab_focus()
	elif _bag_row != null:
		_bag_row.grab_focus()


# =====================================================================================
#  Difficulty
# =====================================================================================

func _toggle_tier() -> void:
	var show: bool = not _tier_scroll.visible
	_hide_pages_except(_tier_scroll)
	_tier_scroll.visible = show
	_tier_confirming = false
	if show:
		refresh_tier()
	_link_rows_to(_tier_scroll if show else null)


func is_tier_open() -> bool:
	return _tier_scroll.visible


func show_tier() -> void:
	if not _tier_scroll.visible:
		_toggle_tier()


## Rebuild the Difficulty page: the tier, what it means, and (Classic) the way down.
func refresh_tier() -> void:
	for c in _tier.get_children():
		_tier.remove_child(c)
		c.queue_free()
	if _state == null:
		return
	var head := ConquestTheme.title_ribbon("DIFFICULTY", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_tier.add_child(head)
	var classic: bool = _state.is_classic()
	var card := PanelContainer.new()
	card.name = "TierCard"
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(
		MenuTheme.DANGER if classic else MenuTheme.EL_NATURE))
	ConquestTheme.keep_style(card)
	_tier.add_child(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_S)
	card.add_child(col)
	var name_l := MenuKit.label(StoryPermadeath.tier_name(_state.tier), &"SubheadingLabel")
	name_l.name = "TierName"
	col.add_child(name_l)
	var rs: StoryRuleset = session.ruleset() if session != null and session.has_method(&"ruleset") else null
	var blurb := MenuKit.label(StoryPermadeath.tier_blurb(_state.tier, rs), &"DimLabel", true)
	blurb.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(blurb)
	if not _state.fallen.is_empty():
		var fl := MenuKit.label("Fallen so far: %d" % _state.fallen.size(), &"MutedLabel")
		fl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(fl)
	if not _state.can_lower_tier_to(StoryState.TIER_CASUAL):
		var low := MenuKit.label("This is the gentlest tier. A journey can never move back up.", &"MutedLabel", true)
		low.name = "LowestNote"
		low.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(low)
		_link_rows_to(_tier_scroll)
		return
	if _tier_confirming:
		var warn := MenuKit.label("You can't go back up. Lower this journey to Casual for good?", &"DimLabel", true)
		warn.name = "ConfirmNote"
		warn.add_theme_color_override("font_color", MenuTheme.WARNING)
		warn.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		col.add_child(warn)
	var actions := HBoxContainer.new()
	actions.name = "TierActions"
	actions.add_theme_constant_override("separation", MenuTheme.SP_M)
	col.add_child(actions)
	if not _tier_confirming:
		var lower := MenuKit.button("Lower to Casual", MenuKit.GHOST, 190, 38)
		lower.name = "LowerTierButton"
		lower.pressed.connect(_on_lower_pressed)
		actions.add_child(lower)
	else:
		var yes := MenuKit.button("Lower to Casual", MenuKit.PRIMARY, 190, 38)
		yes.name = "ConfirmLowerButton"
		yes.pressed.connect(_on_confirm_lower)
		actions.add_child(yes)
		var no := MenuKit.button("Keep Classic", MenuKit.GHOST, 150, 38)
		no.name = "CancelLowerButton"
		no.pressed.connect(_on_cancel_lower)
		actions.add_child(no)
	_link_rows_to(_tier_scroll)


func _on_lower_pressed() -> void:
	_tier_confirming = true
	refresh_tier()
	_focus_tier_control("CancelLowerButton")
	set_status("Lowering the difficulty cannot be undone.")


func _on_cancel_lower() -> void:
	_tier_confirming = false
	refresh_tier()
	_focus_tier_control("LowerTierButton")
	set_status("The journey stays Classic.")


func _on_confirm_lower() -> void:
	var ok: bool = false
	if session != null and session.has_method(&"lower_tier"):
		ok = bool(session.lower_tier(StoryState.TIER_CASUAL).get("success", false))
	elif _state != null:
		ok = bool(_state.lower_tier(StoryState.TIER_CASUAL).get("ok", false))
	_tier_confirming = false
	refresh_tier()
	set_status("The journey is now Casual." if ok else "The difficulty could not be changed.")
	if _tier_row != null:
		_tier_row.grab_focus()


func _focus_tier_control(node_name: String) -> void:
	var found: Node = _tier.find_child(node_name, true, false)
	if found is Control:
		(found as Control).grab_focus()


# =====================================================================================
#  Focus
# =====================================================================================

## Point the command rows' "right" at the first focusable control of the open page ([param page]
## null = none open: right stays put).
func _link_rows_to(page: Control) -> void:
	var first: Control = _first_focusable(page) if page != null and page.visible else null
	for b in _buttons:
		b.focus_neighbor_right = b.get_path_to(first) if first != null and first.is_inside_tree() else NodePath("")


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL and not c.is_queued_for_deletion():
			return c
		var deeper: Control = _first_focusable(c)
		if deeper != null:
			return deeper
	return null


func _focus_in_page() -> Control:
	var f: Control = get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if f == null:
		return null
	for s in _page_scrolls():
		if s.is_ancestor_of(f):
			return f
	return null


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or _busy:
		return
	if MenuNav.is_back_event(event) or event.is_action_pressed(InputActions.MAP_MENU):
		get_viewport().set_input_as_handled()
		# Back from inside a page returns to its row; back on the rows closes the menu.
		if _settings != null and _settings.is_open():
			_settings.close()
			return
		var inside: Control = _focus_in_page()
		if inside != null and MenuNav.is_back_event(event):
			# A member's detail page backs out to the party list first.
			if not _detail_id.is_empty() and _party_scroll.is_ancestor_of(inside):
				show_member_detail("")
				return
			var row: Button = _row_for_page_of(inside)
			if row != null:
				row.grab_focus()
			return
		close()


# =====================================================================================
#  Page plumbing + journey summary
# =====================================================================================

func _page_scrolls() -> Array[ScrollContainer]:
	return [_party_scroll, _bag_scroll, _tier_scroll, _quest_scroll, _map_scroll]


## Hide every page but [param keep] (null = hide all).
func _hide_pages_except(keep: ScrollContainer) -> void:
	for s in _page_scrolls():
		if s != keep:
			s.visible = false


## The command row that opened the page [param inside] sits in (Esc from a page returns to it).
func _row_for_page_of(inside: Control) -> Button:
	if _party_scroll.is_ancestor_of(inside):
		return _party_row
	if _tier_scroll.is_ancestor_of(inside):
		return _tier_row
	if _quest_scroll.is_ancestor_of(inside):
		return _quests_row
	if _map_scroll.is_ancestor_of(inside):
		return _map_row
	return _bag_row


## The card's footer: "Oakvale  ·  Gold 120  ·  1h 02m" and the current objective underneath.
func _refresh_summary() -> void:
	if _state == null:
		_status.text = ""
		return
	var place: String = area_name(_state.location_area())
	var lines: Array[String] = ["%s%sGold %d  ·  %s" % [place, "  ·  " if not place.is_empty() else "", _state.gold,
		StorySnapshot.format_play_time(int(_state.play_seconds))]]
	var goal: String = QuestLog.current_objective(_state)
	if not goal.is_empty():
		lines.append("Objective: " + goal)
	_status.text = "\n".join(lines)
	if _load_row != null:
		_load_row.text = "Load"
		_load_row.disabled = not can_load()


## The area's display name (the session's cache when there is one), "" for an empty id.
func area_name(area_id: String) -> String:
	if area_id.is_empty():
		return ""
	if session != null and session.has_method(&"area_display_name"):
		return String(session.area_display_name(area_id))
	var a: OverworldAreaResource = OverworldAreaResource.load_by_id(area_id)
	return a.display_name if a != null and not a.display_name.is_empty() else area_id.capitalize()


# =====================================================================================
#  Party details + equipment
# =====================================================================================

## Show [param member_id]'s detail page in the Party page ("" = back to the list).
func show_member_detail(member_id: String) -> void:
	var leaving: String = _detail_id
	_detail_id = member_id
	if not _party_scroll.visible:
		_toggle_party()
	else:
		refresh_party()
	_party_scroll.scroll_vertical = 0
	if member_id.is_empty():
		var card := member_card(leaving)
		var btn: Node = card.find_child("DetailsButton", true, false) if card != null else null
		if btn is Control:
			(btn as Control).grab_focus()
	else:
		_refocus_detail(["BackButton"])


func detail_member_id() -> String:
	return _detail_id


func _on_equip_pressed(item_id: String, member_id: String) -> void:
	var r: Dictionary
	if session != null and session.has_method(&"equip_from_menu"):
		r = session.equip_from_menu(member_id, item_id)
	elif _state != null:
		r = _state.equip_item(member_id, item_id)
	else:
		return
	var item: ItemResource = ItemLibrary.get_item(item_id)
	var item_name: String = item.display_name if item != null else item_id
	if bool(r.get("ok", false)):
		set_status("%s now holds the %s." % [_member_name(member_id), item_name])
	else:
		set_status("Cannot equip the %s (%s)." % [item_name, String(r.get("reason", ""))])
	refresh_party()
	_refocus_detail(["UnequipButton"])


func _on_unequip_pressed(member_id: String) -> void:
	var ok: bool
	if session != null and session.has_method(&"unequip_from_menu"):
		ok = session.unequip_from_menu(member_id)
	else:
		ok = _state != null and _state.unequip_item(member_id)
	if ok:
		set_status("%s put its item back in the bag." % _member_name(member_id))
	refresh_party()
	_refocus_detail(["BackButton"])


func _refocus_detail(names: Array) -> void:
	for n in names:
		var found: Node = _party.find_child(String(n), true, false)
		if found is Control and (found as Control).is_visible_in_tree():
			(found as Control).grab_focus()
			return


# =====================================================================================
#  Quests
# =====================================================================================

func _toggle_quests() -> void:
	var show: bool = not _quest_scroll.visible
	_hide_pages_except(_quest_scroll)
	_quest_scroll.visible = show
	if show:
		refresh_quests()
	_link_rows_to(_quest_scroll if show else null)


func is_quests_open() -> bool:
	return _quest_scroll.visible


func show_quests() -> void:
	if not _quest_scroll.visible:
		_toggle_quests()


## Rebuild the Quests page from the flags: active quests (main first) then finished ones.
func refresh_quests() -> void:
	_clear(_quest)
	var head := ConquestTheme.title_ribbon("QUESTS", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_quest.add_child(head)
	var entries: Array = QuestLog.entries(_state) if _state != null else []
	if entries.is_empty():
		var empty := MenuKit.label("No quests yet. Talk to people and explore.", &"DimLabel", true)
		empty.name = "EmptyQuests"
		_quest.add_child(empty)
	var done_heading_added: bool = false
	for e in entries:
		if String(e["status"]) == QuestLog.STATUS_DONE and not done_heading_added:
			done_heading_added = true
			var dh := ConquestTheme.title_ribbon("COMPLETED", MenuTheme.TEXT_MUTED, MenuTheme.FS_BODY)
			dh.name = "CompletedHeading"
			dh.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			_quest.add_child(dh)
		_quest.add_child(_quest_card(e))
	_link_rows_to(_quest_scroll)


func _quest_card(e: Dictionary) -> PanelContainer:
	var done: bool = String(e["status"]) == QuestLog.STATUS_DONE
	var main: bool = String(e["category"]) == QuestLog.MAIN
	var accent: Color = MenuTheme.TEXT_MUTED if done else (MenuTheme.GOLD if main else MenuTheme.SUCCESS)
	var card := PanelContainer.new()
	card.name = "Quest_" + String(e["id"])
	card.set_meta(&"quest_id", String(e["id"]))
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(accent))
	ConquestTheme.keep_style(card)
	if done:
		card.modulate = Color(1, 1, 1, 0.8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var title := MenuKit.label(String(e["title"]), &"SubheadingLabel")
	title.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(ConquestTheme.chip("Done" if done else ("Main" if main else "Side"), accent, MenuTheme.FS_CAPTION))
	if not String(e["summary"]).is_empty():
		var s := MenuKit.label(String(e["summary"]), &"DimLabel", true)
		s.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(s)
	for step in e["steps"]:
		var sd: bool = bool(step["done"])
		var l := MenuKit.label("%s  %s" % ["[x]" if sd else "[ ]", String(step["text"])],
			&"MutedLabel" if sd else &"", true)
		l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		col.add_child(l)
	return card


# =====================================================================================
#  Map (places)
# =====================================================================================

func _toggle_map() -> void:
	var show: bool = not _map_scroll.visible
	_hide_pages_except(_map_scroll)
	_map_scroll.visible = show
	if show:
		refresh_map()
	_link_rows_to(_map_scroll if show else null)


func is_map_open() -> bool:
	return _map_scroll.visible


func show_map() -> void:
	if not _map_scroll.visible:
		_toggle_map()


## Rebuild the Map page: where you are, where a whiteout leads, every area visited and its Wayshrines.
func refresh_map() -> void:
	_clear(_map)
	var head := ConquestTheme.title_ribbon("MAP", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_map.add_child(head)
	if _state == null:
		return
	var here: String = _state.location_area()
	var respawn_id: String = String(_state.respawn.get("area_id", ""))
	var ids: Array[String] = []
	for id in _state.visited_areas:
		ids.append(id)
	if not here.is_empty() and not ids.has(here):
		ids.append(here)
	if ids.is_empty():
		var empty := MenuKit.label("You have not been anywhere yet.", &"DimLabel")
		empty.name = "EmptyMap"
		_map.add_child(empty)
	for id in ids:
		_map.add_child(_place_card(id, id == here, id == respawn_id))
	_link_rows_to(_map_scroll)


func _place_card(id: String, is_here: bool, is_rest: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Place_" + id
	card.set_meta(&"area_id", id)
	card.add_theme_stylebox_override("panel",
		MenuTheme.accented_card(MenuTheme.GOLD if is_here else MenuTheme.GOLD_DK))
	ConquestTheme.keep_style(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	card.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var name_l := MenuKit.label(area_name(id), &"SubheadingLabel")
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	if is_here:
		top.add_child(ConquestTheme.chip("You are here", MenuTheme.GOLD, MenuTheme.FS_CAPTION))
	if is_rest:
		top.add_child(ConquestTheme.chip("Rest point", MenuTheme.SUCCESS, MenuTheme.FS_CAPTION))
	var shrines: int = 0
	for key in _state.lit_wayshrines:
		if key.begins_with(id + "."):
			shrines += 1
	var detail: String = "Wayshrines lit: %d" % shrines
	var area: OverworldAreaResource = OverworldAreaResource.load_by_id(id)
	if area != null:
		detail = "%s  ·  %s" % [String(area.region_id).replace("_", " ").capitalize(), detail]
	var d := MenuKit.label(detail, &"DimLabel")
	d.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(d)
	return card


func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# =====================================================================================
#  Load
# =====================================================================================

## Is there a saved slot to go back to?
func can_load() -> bool:
	return session != null and session.has_method(&"load_last_save") and session.has_method(&"slot") \
		and int(session.slot()) > 0 and StorySaveManager.has_save(int(session.slot()))


## Load: the first press asks, the second reloads the slot's last save.
func _on_load_pressed() -> void:
	if not can_load():
		set_status("Nothing saved to load.")
		return
	if not _load_confirming:
		_load_confirming = true
		_load_row.text = "Load -- press again"
		set_status("Reload your last save? Progress since then is lost.")
		return
	_load_confirming = false
	close()
	session.load_last_save()
