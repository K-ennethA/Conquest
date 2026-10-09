class_name PartyDetailPage
extends RefCounted

## ONE PARTY MEMBER, in full (Journey -> Party -> Details): portrait, name / form / element / role,
## HP, Growth and evolution history, the stat table, the worn item (with Equip / Unequip from the
## bag) and its moves and abilities. A static builder like [UnitPageContent] -- which it REUSES for
## the stat table and the move / ability cards, so a creature reads the same here as in the
## Compendium -- and [JourneyMenu] owns the buttons' effects (the page only emits Callables).
##
## LEVEL + XP bar (docs/design/PROGRESSION.md) sit under HP and the stat table shows the member's stats
## AT its level; GROWTH (docs/design/EVOLUTION.md) is still the evolution currency, shown with the
## number of forms it has taken.

const PORTRAIT_PX: float = 96.0


## The page for [param m]. [param state] supplies the bag (equip choices). [param on_back],
## [param on_equip] (item_id) and [param on_unequip] are optional Callables.
static func build(m: StoryPartyMember, state: StoryState, is_lead: bool, on_back: Callable,
		on_equip: Callable, on_unequip: Callable) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = "PartyDetail"
	page.set_meta(&"member_id", m.member_id)
	page.add_theme_constant_override("separation", 8)
	var c: CharacterResource = m.character()

	var back := MenuKit.button("<  Party", MenuKit.GHOST, 110, 36)
	back.name = "BackButton"
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if on_back.is_valid():
		back.pressed.connect(on_back)
	page.add_child(back)

	# --- Header: portrait + name / form + chips ----------------------------------------
	var el_col: Color = MenuKit.element_color(String(c.element)) if c != null else MenuTheme.GOLD
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	page.add_child(head)
	var portrait := ConquestTheme.portrait(m.display_name().substr(0, 1), el_col, MenuTheme.GOLD_DK, PORTRAIT_PX)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(portrait)
	apply_portrait(portrait, c)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	head.add_child(col)
	var name_l := MenuKit.label(m.display_name(), &"SubheadingLabel")
	name_l.name = "MemberName"
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SUBHEADING)
	col.add_child(name_l)
	if c != null and c.display_name != m.display_name():
		col.add_child(_caption("Form: " + c.display_name))
	var chips := HFlowContainer.new()
	chips.name = "Chips"
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 4)
	col.add_child(chips)
	if c != null and not String(c.element).is_empty():
		chips.add_child(ConquestTheme.chip(String(c.element).capitalize(), el_col, MenuTheme.FS_CAPTION))
	chips.add_child(ConquestTheme.chip(role_of(c), MenuTheme.GOLD_DK, MenuTheme.FS_CAPTION))
	if is_lead:
		chips.add_child(ConquestTheme.chip("Lead", MenuTheme.GOLD, MenuTheme.FS_CAPTION))
	# HUMANS (docs/design/HUMANS.md): kind / hero / guest chips and the weapon.
	if m.is_hero:
		chips.add_child(ConquestTheme.chip("Hero", MenuTheme.GOLD, MenuTheme.FS_CAPTION))
	if c != null and c.is_human():
		chips.add_child(ConquestTheme.chip("Human", MenuTheme.GOLD_DK, MenuTheme.FS_CAPTION))
	if m.is_temporary():
		chips.add_child(ConquestTheme.chip("Guest", MenuTheme.GOLD_DK, MenuTheme.FS_CAPTION))
	var w: WeaponResource = m.weapon()
	if w != null:
		var reach: Vector2i = w.reach()
		var wl := _caption("Weapon: %s (%s)  ·  Might %d  ·  Hit %d%%  ·  Range %s" % [w.display_name,
			String(w.weapon_type).capitalize() if w.weapon_type != &"" else "none", w.might,
			roundi(w.hit * 100.0), str(reach.x) if reach.x == reach.y else "%d-%d" % [reach.x, reach.y]])
		wl.name = "WeaponText"
		col.add_child(wl)
	if m.wounded:
		chips.add_child(ConquestTheme.chip("Wounded", MenuTheme.TEAM_RED, MenuTheme.FS_CAPTION))

	var bar := ConquestTheme.hp_bar(12.0)
	bar.name = "HpBar"
	bar.max_value = m.max_hp()
	bar.value = m.hp_value()
	ConquestTheme.tint_hp_bar(bar, float(m.hp_value()) / float(maxi(1, m.max_hp())))
	page.add_child(bar)
	var hp := _caption("HP %d / %d" % [m.hp_value(), m.max_hp()])
	hp.name = "HpText"
	page.add_child(hp)

	# --- Level + XP (PROGRESSION.md) ------------------------------------------------
	var lv := MenuKit.label(level_line(m), &"SubheadingLabel")
	lv.name = "LevelText"
	lv.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	page.add_child(lv)
	var xp_bar := ProgressBar.new()
	xp_bar.name = "XpBar"
	xp_bar.show_percentage = false
	xp_bar.min_value = 0.0
	xp_bar.max_value = 1.0
	xp_bar.value = m.level_progress()
	xp_bar.custom_minimum_size = Vector2(0, 6)
	page.add_child(xp_bar)
	var xp := _caption(xp_line(m))
	xp.name = "XpText"
	page.add_child(xp)
	var bond := _caption(bond_line(m))
	bond.name = "BondText"
	page.add_child(bond)
	# FIELD MOVES it has learned (DECISIONS.md #92), one line -- none, no line.
	if not m.field_moves.is_empty():
		var fml := _caption(field_moves_line(m))
		fml.name = "FieldMovesText"
		page.add_child(fml)
	if c != null and not c.description.strip_edges().is_empty():
		var d := UnitPageContent.wrapped_label(c.description.strip_edges())
		d.name = "Description"
		d.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		page.add_child(d)

	# --- Growth ---------------------------------------------------------------------
	page.add_child(UnitPageContent.section_header("Growth"))
	var growth := UnitPageContent.wrapped_label(growth_line(m))
	growth.name = "GrowthLine"
	page.add_child(growth)

	# --- Stats ----------------------------------------------------------------------
	if c != null:
		page.add_child(UnitPageContent.section_header("Stats"))
		page.add_child(UnitPageContent.build_stat_table(m.leveled_character()))

	# --- Equipment ------------------------------------------------------------------
	page.add_child(UnitPageContent.section_header("Equipment"))
	page.add_child(_equipment_block(m, state, on_equip, on_unequip))

	# --- Moves + abilities -----------------------------------------------------------
	if c != null:
		if not c.get_moveset().is_empty():
			page.add_child(UnitPageContent.section_header("Moves"))
			for mv in c.get_moveset():
				if mv != null:
					page.add_child(UnitPageContent.build_move_card(mv))
		if not c.abilities.is_empty():
			page.add_child(UnitPageContent.section_header("Abilities"))
			for ab in c.abilities:
				if ab != null:
					page.add_child(UnitPageContent.build_ability_card(ab))
	return page


## "Lv 7" (the party page's level line).
static func level_line(m: StoryPartyMember) -> String:
	return "Lv %d" % m.level


## "XP 412  ·  100 to next level" ("Max level" at the cap).
static func xp_line(m: StoryPartyMember) -> String:
	var to_next: int = m.xp_to_next()
	if to_next <= 0:
		return "XP %d  ·  Max level" % m.xp
	return "XP %d  ·  %d to next level" % [m.xp, to_next]


## "Bond 2 / 10" (DECISIONS.md #68: it grows by fighting alongside the hero; nothing reads it yet).
static func bond_line(m: StoryPartyMember) -> String:
	return "Bond %d / %d" % [m.bond_level(), ProgressionRules.current().bond_max]


## "Field moves: Treefell" -- the field moves [param m] has learned (their shipped names; an id this
## build does not ship shows as the id).
static func field_moves_line(m: StoryPartyMember) -> String:
	var names: Array[String] = []
	for id in m.field_moves:
		var fm: FieldMoveResource = FieldMoveResource.load_by_id(id)
		names.append(fm.display_name if fm != null and not fm.display_name.is_empty() else id.capitalize())
	return "Field moves: %s" % ", ".join(names)


## "Growth 3  ·  1 evolution" -- the progression summary.
static func growth_line(m: StoryPartyMember) -> String:
	var out: String = "Growth %d" % m.growth_points()
	var history: Array = m.evolution_history()
	if history.is_empty():
		return out + "  ·  original form"
	return out + "  ·  %d evolution%s" % [history.size(), "" if history.size() == 1 else "s"]


## A short role label from the character's authored tags, else derived from its stats: Boss, Ranged,
## Caster, Guardian or Fighter. Data first so a character can name its own role with a tag.
static func role_of(c: CharacterResource) -> String:
	if c == null:
		return "Unknown"
	if c.is_boss:
		return "Boss"
	if not c.tags.is_empty():
		return String(c.tags[0]).replace("_", " ").capitalize()
	if c.attack_range > 1:
		return "Ranged"
	if c.base_magic > c.base_attack:
		return "Caster"
	if c.base_defense + c.base_magic_defense >= c.base_attack + c.base_magic:
		return "Guardian"
	return "Fighter"


## Equipment ids the bag could put on [param m] right now (unit-scope, not what it already wears).
static func equippable_items(m: StoryPartyMember, state: StoryState) -> Array[ItemResource]:
	var out: Array[ItemResource] = []
	if state == null:
		return out
	var ids: Array = state.bag.keys()
	ids.sort()
	for id in ids:
		var item: ItemResource = ItemLibrary.get_item(String(id))
		if item == null or state.item_count(String(id)) <= 0:
			continue
		if item.is_equipment() and not item.is_team_item() and String(id) != m.item_id:
			out.append(item)
	return out


static func _equipment_block(m: StoryPartyMember, state: StoryState, on_equip: Callable,
		on_unequip: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Equipment"
	box.add_theme_constant_override("separation", 6)
	var worn: ItemResource = ItemLibrary.get_item(m.item_id) if not m.item_id.is_empty() else null
	var worn_row := HBoxContainer.new()
	worn_row.add_theme_constant_override("separation", 10)
	box.add_child(worn_row)
	var worn_l := UnitPageContent.wrapped_label(
		"%s  (%s)" % [worn.display_name, worn.effect_summary()] if worn != null else "Nothing equipped.")
	worn_l.name = "WornItem"
	worn_row.add_child(worn_l)
	if worn != null:
		var off := MenuKit.button("Unequip", MenuKit.GHOST, 0, 34)
		off.name = "UnequipButton"
		off.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		if on_unequip.is_valid():
			off.pressed.connect(on_unequip)
		worn_row.add_child(off)
	var options := equippable_items(m, state)
	if not options.is_empty():
		box.add_child(UnitPageContent.muted_label("From the bag"))
		var flow := HFlowContainer.new()
		flow.name = "EquipOptions"
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 6)
		box.add_child(flow)
		for item in options:
			var b := MenuKit.button("%s  %s" % [item.display_name, item.effect_summary()], MenuKit.GHOST, 0, 34)
			b.name = "Equip_" + String(item.id)
			b.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
			if on_equip.is_valid():
				b.pressed.connect(on_equip.bind(String(item.id)))
			flow.add_child(b)
	return box


static func _caption(text: String) -> Label:
	var l := MenuKit.label(text, &"DimLabel")
	l.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	return l


## Lay the character's real portrait over [param portrait_panel]'s monogram: the authored
## [member CharacterResource.portrait] when there is one, else the [PortraitCache] capture of its
## 3D model (async; skipped when headless, where nothing renders). The monogram stays until then.
static func apply_portrait(portrait_panel: PanelContainer, c: CharacterResource) -> void:
	if portrait_panel == null or c == null:
		return
	if c.portrait != null:
		_set_art(portrait_panel, c.portrait)
		return
	if DisplayServer.get_name() == "headless":
		return
	var cached: Texture2D = PortraitCache.get_cached(c.character_id)
	if cached != null:
		_set_art(portrait_panel, cached)
		return
	var ref: WeakRef = weakref(portrait_panel)
	PortraitCache.get_portrait(c.character_id, func(tex: Texture2D) -> void:
		var p: PanelContainer = ref.get_ref() as PanelContainer
		if tex != null and p != null:
			_set_art(p, tex))


static func _set_art(portrait_panel: PanelContainer, tex: Texture2D) -> void:
	var art := portrait_panel.get_node_or_null("Art") as TextureRect
	if art == null:
		art = TextureRect.new()
		art.name = "Art"
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_panel.clip_contents = true
		portrait_panel.add_child(art)
	art.texture = tex
	var initial := portrait_panel.get_node_or_null("Initial") as Control
	if initial != null:
		initial.visible = false
