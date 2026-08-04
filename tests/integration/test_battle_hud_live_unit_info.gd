extends GutTest

## The LIVE unit-info path, booted from the real [GameUILayout] scene.
##
## WHY THIS SUITE EXISTS. `test_unit_battle_card.gd` and `test_unit_detail_page.gd` both
## passed while the shipped build showed neither design, because both of them ask the
## question one level too high:
##
##   * the card suite reads `ChipLabel.text` -- the STRING a chip was handed. It never
##     asked how wide the chip was DRAWN. The chip label was created with
##     `clip_text = true` + TRIM_ELLIPSIS, which makes a Label report a minimum WIDTH of
##     1px; inside an [HFlowContainer] every child is laid out at its minimum, so each
##     status chip collapsed to a ~12px coloured pill with its text clipped away. On
##     screen that is "a small green dot for poison that doesn't elaborate".
##   * the page suite reads Label text out of the node tree. It never asked whether the
##     page's scroll body was ALLOTTED any height. The card was parented to a
##     [CenterContainer], which sizes its child to the child's MINIMUM -- and a vertically
##     scrolling [ScrollContainer]'s minimum height is 0, so every section (stats, moves,
##     abilities, statuses) existed as nodes and was drawn at zero height. On screen that
##     is "clicking details doesn't show full details".
##
## So every assertion here is about what the player can SEE: the rendered size of a chip
## against the width its own text needs, and the rendered size of the page's body. Text
## assertions stay too -- but they are never the only thing a test checks.
##
## Boots the REAL GameUILayout.tscn (the pattern in test_battle_hud_layout.gd) and drives
## selection through GameEvents, i.e. exactly the path a click on the board takes.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")

const DESIGN := Vector2i(1280, 720)

var _prev_window_size: Vector2i


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func after_each() -> void:
	# Re-populating the detail page detaches and queue_free()s the previous unit's cards.
	# queue_free is deferred and GUT counts orphans before the frame ends.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Fixtures ------------------------------------------------------------------

func _move(id: StringName, name_text: String, cooldown: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id
	m.display_name = name_text
	m.description = "Does a thing."
	m.cooldown = cooldown
	return m


func _ability(id: StringName, name_text: String, description: String) -> AbilityResource:
	var a := AbilityResource.new()
	a.id = id
	a.display_name = name_text
	a.description = description
	a.trigger = AbilityTrigger.Trigger.PASSIVE
	return a


func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.description = "A stout root-knight."
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = 3
	c.moveset = [_move(&"root_slam", "Root Slam", 3), _move(&"guard", "Guard", 0)]
	c.abilities = [
		_ability(&"grass_cutter", "Grass Cutter", "Ignores rough terrain."),
		_ability(&"deep_roots", "Deep Roots", "Cannot be pushed."),
	]
	return c


func _unit() -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	add_child_autofree(u)  # _ready builds MovesetController / StatusController / AbilitySystem
	return u


## A live unit carrying a real poisoned condition on its real StatusController.
func _poisoned_unit(turns: int = 2) -> Unit:
	var u := _unit()
	var poison := StatusCondition.new()
	poison.id = &"poisoned"
	poison.display_name = "Poisoned"
	poison.duration_turns = turns
	poison.rule_flags = {"immobilized": true}
	u.get_status_controller().add_status(poison)
	return u


## Build the real HUD and let every deferred re-budget / re-fit settle.
func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


## Select [param unit] the way the board does: through GameEvents, not by poking the panel.
func _select(unit: Unit) -> void:
	GameEvents.unit_selected.emit(unit, Vector3.ZERO)
	for i in range(6):
		await get_tree().process_frame


# --- Rendering helpers ----------------------------------------------------------

## The width [param label]'s own text needs at the size it is actually drawn.
## This is the measurement the old suites never took.
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _status_chips(card: Control) -> Array:
	var out: Array = []
	if card._status_flow == null or not is_instance_valid(card._status_flow):
		return out
	for child in card._status_flow.get_children():
		if child.get_node_or_null("ChipLabel") != null:
			out.append(child)
	return out


func _all_text(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.find_children("*", "Label", true, false):
		parts.append((child as Label).text)
	return "\n".join(parts)


# ==============================================================================
# 1. The battle card's status strip, as it is actually DRAWN
# ==============================================================================

func test_the_live_card_shows_the_selected_unit_at_all() -> void:
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit()
	await _select(unit)

	var card = layout.unit_info_panel
	assert_true(card.visible, "clicking a unit on the board puts its card on screen")
	assert_eq(card.get_current_unit(), unit, "showing the unit that was selected")


func test_a_live_status_renders_as_a_labelled_chip_not_a_coloured_dot() -> void:
	# The reported bug, stated as geometry: the chip has to be drawn wide enough to show
	# its own text. A pill narrower than its label IS the "small green dot".
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit(2)
	await _select(unit)

	var chips: Array = _status_chips(layout.unit_info_panel)
	assert_eq(chips.size(), 1, "one live condition, one chip")
	if chips.is_empty():
		return

	var chip: Control = chips[0]
	var label := chip.get_node("ChipLabel") as Label
	var needed: float = _text_width(label)
	gut.p("chip rect   : %s   label rect: %s   text needs %.1fpx for %s"
			% [Rect2(chip.global_position, chip.size),
			Rect2(label.global_position, label.size), needed, label.text])

	assert_true(needed > 0.0, "the chip's label has real text to draw")
	assert_true(label.size.x >= needed - 1.0,
			"the chip label is drawn at least as wide as its own text (%.1f >= %.1f) -- a"
			% [label.size.x, needed]
			+ " narrower pill is the coloured dot the player reported")
	assert_true(chip.size.x >= needed,
			"and the pill around it is wider still, so nothing is trimmed away")


func test_the_rendered_chip_names_the_status_its_severity_and_its_duration() -> void:
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit(2)
	# A second and third instance, so severity has something to report.
	for i in range(2):
		var extra := StatusCondition.new()
		extra.id = &"poisoned"
		extra.display_name = "Poisoned"
		extra.duration_turns = 2
		extra.stacking = StatusCondition.Stacking.STACK
		unit.get_status_controller().add_status(extra)
	await _select(unit)

	var chips: Array = _status_chips(layout.unit_info_panel)
	assert_eq(chips.size(), 1, "three instances of one status are one chip")
	if chips.is_empty():
		return

	var text: String = (chips[0].get_node("ChipLabel") as Label).text
	assert_true(text.contains(StatusVisuals.glyph_for_id(&"poisoned")),
			"the chip carries the status GLYPH: %s" % text)
	assert_true(text.contains("Poisoned"), "and names the status: %s" % text)
	assert_true(text.contains("x3"), "and its severity: %s" % text)
	assert_true(text.contains("2t"), "and how long it lasts: %s" % text)


func test_a_chip_elaborates_on_hover_without_opening_the_page() -> void:
	# "It showed a small green dot for poison but doesn't elaborate." The chip itself has
	# to say what the status DOES, not just what it is called.
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit(2)
	await _select(unit)

	var chips: Array = _status_chips(layout.unit_info_panel)
	assert_false(chips.is_empty(), "there is a chip to hover")
	if chips.is_empty():
		return

	var chip: Control = chips[0]
	var condition = StatusVisuals.active_conditions(unit)[0]
	var described: String = StatusVisuals.describe_condition(condition)
	assert_ne(described, "", "the fixture's poison has something to describe")
	assert_true(chip.tooltip_text.contains(described),
			"the chip's tooltip explains what the status does: %s" % chip.tooltip_text)
	assert_true(chip.tooltip_text.contains("Poisoned"),
			"alongside its name and duration: %s" % chip.tooltip_text)
	assert_ne(chip.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"and the chip accepts the hover, or the tooltip can never be shown")


func test_every_chip_on_a_crowded_strip_is_still_drawn_readably() -> void:
	# Four statuses, wrapping inside the strip's existing two-row budget. The strip may
	# COUNT what does not fit ("+N"); it may not shrink chips into dots to make room.
	var layout: Control = await _build_hud()
	var unit := _unit()
	var controller = unit.get_status_controller()
	for spec in [[&"poisoned", "Poisoned"], [&"burn", "Burn"],
			[&"hastened", "Hastened"], [&"fortified", "Fortified"]]:
		var c := StatusCondition.new()
		c.id = spec[0]
		c.display_name = String(spec[1])
		c.duration_turns = 2
		controller.add_status(c)
	await _select(unit)

	var card = layout.unit_info_panel
	var chips: Array = _status_chips(card)
	assert_eq(chips.size(), 4, "four distinct statuses, four chips (nothing overflows yet)")
	for chip in chips:
		var label := chip.get_node("ChipLabel") as Label
		gut.p("chip        : %-24s w=%.1f needs=%.1f" % [label.text, label.size.x, _text_width(label)])
		assert_true(label.size.x >= _text_width(label) - 1.0,
				"'%s' is drawn wide enough to read" % label.text)

	assert_true(card.fixed_content_height() <= UnitInfoPanel.CARD_HEIGHT,
			"and the crowded strip still fits the card's pinned 228px budget")
	var strip: Control = card._status_strip
	assert_eq(strip.custom_minimum_size.y, UnitInfoPanel.STATUS_STRIP_HEIGHT,
			"the strip claims exactly its two rows however many chips are in it")


func test_an_empty_strip_still_reads_as_words() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit())

	var none := layout.unit_info_panel._status_flow.get_node_or_null("NoStatuses") as Label
	assert_not_null(none, "an empty strip carries the muted 'No active effects' line")
	if none == null:
		return
	assert_true(none.size.x >= _text_width(none) - 1.0,
			"and that line is drawn wide enough to read, not clipped to nothing")


# ==============================================================================
# 2. The DETAILS flow, from the controls the player actually presses
# ==============================================================================

func test_the_battle_mounts_exactly_one_detail_page() -> void:
	var layout: Control = await _build_hud()
	assert_not_null(layout.unit_detail_page,
			"the HUD mounts the detail page -- an opener with nothing to find would stack "
			+ "a fresh overlay on the tree root instead")
	assert_eq(get_tree().get_nodes_in_group(UnitDetailPage.GROUP).size(), 1,
			"and exactly one of them")
	assert_false(layout.unit_detail_page.is_open(), "starting hidden")


func test_the_cards_details_chip_opens_the_mounted_page_on_the_selected_unit() -> void:
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit()
	await _select(unit)

	var button := layout.unit_info_panel.find_child("DetailsButton", true, false) as Button
	assert_not_null(button, "the card carries a DETAILS chip")
	button.pressed.emit()
	await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	assert_true(page.is_open(), "pressing it opens the page")
	assert_eq(page.current_unit(), unit, "on the unit the card was showing")
	page.close()


func test_the_sidebar_details_button_finds_the_same_page() -> void:
	var layout: Control = await _build_hud()
	var unit := _unit()
	await _select(unit)

	var page: UnitDetailPage = UnitDetailPage.open_for(layout.unit_actions_panel, unit)
	assert_eq(page, layout.unit_detail_page,
			"the right sidebar's opener finds the battle's page rather than mounting a second")
	assert_eq(get_tree().get_nodes_in_group(UnitDetailPage.GROUP).size(), 1,
			"so the tree still holds exactly one")
	page.close()


func test_the_open_page_actually_draws_its_body() -> void:
	# The bug, stated as geometry. Every section below existed as NODES the whole time;
	# they were allotted zero height, so the player saw a header and a Close button.
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit()
	await _select(unit)
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var card: Control = page._card
	var body: Control = page._body
	var scroll := page._card.find_child("Scroll", true, false) as ScrollContainer
	var vp: Vector2 = get_viewport().get_visible_rect().size
	gut.p("page card   : %s   (viewport %s)" % [Rect2(card.global_position, card.size), vp])
	gut.p("page scroll : %s" % Rect2(scroll.global_position, scroll.size))
	gut.p("page body   : %s (min %s)" % [Rect2(body.global_position, body.size),
			body.get_combined_minimum_size()])

	assert_true(card.size.y >= vp.y - UnitDetailPage.MARGIN * 2.0 - 0.5,
			"the page's card fills the window instead of shrinking to header + footer "
			+ "(%.1f of %.1f)" % [card.size.y, vp.y])
	assert_not_null(scroll, "the page has a scroll region")
	if scroll == null:
		return
	assert_true(scroll.size.y > 200.0,
			"and the scroll region is allotted real height to show the sections in (%.1f)"
			% scroll.size.y)
	assert_true(body.size.x > 400.0, "at the page's document width (%.1f)" % body.size.x)
	assert_true(card.size.x <= UnitDetailPage.MAX_CARD_WIDTH + 0.5,
			"while the document stays inside its readable width cap (%.1f)" % card.size.x)
	page.close()


func test_the_open_page_lists_every_move_ability_and_status_for_an_own_unit() -> void:
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit()
	await _select(unit)
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var character: CharacterResource = unit.character_resource
	var body: Control = page._body

	# Trailing wildcard, and cards named per move/ability id upstream: two siblings may not
	# share a name, and Godot's own uniquifier turns the second plain "MoveCard" into
	# "@MoveCard@41" -- which no readable pattern matches, so a name query over the page
	# quietly returned ONE card per section however many were really there.
	for child in body.get_children():
		gut.p("  body child: %-28s %s" % [child.name, (child as Control).size if child is Control else ""])
	var move_cards: Array = body.find_children("MoveCard*", "", true, false)
	var ability_cards: Array = body.find_children("AbilityCard*", "", true, false)
	var status_cards: Array = body.find_children("StatusCard*", "", true, false)
	gut.p("cards       : %d moves, %d abilities, %d statuses"
			% [move_cards.size(), ability_cards.size(), status_cards.size()])

	assert_eq(move_cards.size(), character.move_count(),
			"one card per authored move, none dropped")
	assert_eq(ability_cards.size(), character.abilities.size(),
			"one card per ability -- the section that used to be cut off entirely")
	assert_eq(status_cards.size(), 1, "and one card per active status")

	var text: String = _all_text(page)
	for expected in ["STATISTICS", "MOVES", "ABILITIES", "ACTIVE STATUSES",
			"Root Slam", "Guard", "Grass Cutter", "Deep Roots",
			"Ignores rough terrain.", "Cannot be pushed.", "Poisoned"]:
		assert_true(text.contains(expected), "the page says '%s'" % expected)

	# The stat table is the full base->effective sheet, not the card's four chips.
	for stat in ["Attack", "Defense", "Magic", "Speed", "Movement", "Range", "Health"]:
		assert_true(text.contains(stat + ":"), "the stat table has a %s row" % stat)
	page.close()


func test_every_section_of_the_open_page_is_drawn_inside_the_card() -> void:
	var layout: Control = await _build_hud()
	var unit := _poisoned_unit()
	await _select(unit)
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var card_rect := Rect2(page._card.global_position, page._card.size)
	var scroll := page._card.find_child("Scroll", true, false) as ScrollContainer
	assert_not_null(scroll, "the page scrolls its document")
	if scroll == null:
		return
	var window := Rect2(scroll.global_position, scroll.size)
	gut.p("scroll rect : %s" % window)
	assert_true(window.size.y > 200.0,
			"the scroll region is a real window onto the document, not a 0px slit (%.1f)"
			% window.size.y)

	var drawn: int = 0
	var on_screen: int = 0
	for node in page._body.find_children("*Card*", "PanelContainer", true, false):
		var control := node as Control
		if control.size.y <= 0.0 or control.size.x <= 0.0:
			continue
		drawn += 1
		assert_true(control.size.x <= card_rect.size.x + 0.5,
				"%s stays inside the page's document width" % control.name)
		if window.intersects(Rect2(control.global_position, control.size)):
			on_screen += 1
	gut.p("cards       : %d laid out, %d inside the scroll window" % [drawn, on_screen])
	assert_eq(drawn, 5,
			"two moves, two abilities and one status are all laid out with real size")
	assert_true(on_screen >= 1,
			"and the document's first cards are on screen without scrolling (%d)" % on_screen)

	# ...and the REST of it is reachable, which is the other half of "show full details":
	# a document the player cannot scroll to the end of is still a truncated page.
	scroll.scroll_vertical = 1_000_000
	for i in range(4):
		await get_tree().process_frame
	window = Rect2(scroll.global_position, scroll.size)
	var last := page._body.get_child(page._body.get_child_count() - 1) as Control
	gut.p("scrolled to : %d   last child %s %s"
			% [scroll.scroll_vertical, last.name, Rect2(last.global_position, last.size)])
	assert_true(window.intersects(Rect2(last.global_position, last.size)),
			"scrolling to the bottom reaches the last thing on the page (%s)" % last.name)
	page.close()


func test_an_inspected_enemy_gets_the_same_full_page_live() -> void:
	var layout: Control = await _build_hud()
	var enemy := _poisoned_unit()
	var player := Player.new(1, "Wildwood")
	player.is_ai = true
	enemy.owner_player = player
	await _select(enemy)

	# The exact call the sidebar's DETAILS button makes on an inspected enemy.
	var page: UnitDetailPage = UnitDetailPage.open_for(layout.unit_actions_panel, enemy)
	for i in range(6):
		await get_tree().process_frame

	assert_eq(page, layout.unit_detail_page, "the same single page serves an enemy")
	assert_true(page.is_open(), "and it opens")
	assert_true(page._body.size.y > 200.0,
			"with the same drawn body an own unit gets (%.1f)" % page._body.size.y)
	assert_eq(page._body.find_children("MoveCard*", "", true, false).size(),
			enemy.character_resource.move_count(),
			"and its whole moveset -- the page only ever reads, so an enemy is no different")

	var text: String = _all_text(page)
	assert_true(text.contains("Wildwood"), "labelled with whose unit it is")
	assert_true(text.contains("AI"), "and that it is bot-controlled")
	page.close()


func test_closing_the_page_hands_the_battle_back_untouched() -> void:
	var layout: Control = await _build_hud()
	var unit := _unit()
	await _select(unit)
	layout.unit_info_panel.open_details()
	await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	page.close()
	await get_tree().process_frame

	assert_false(page.is_open(), "the page is gone")
	assert_true(layout.unit_info_panel.visible, "the battle card is still on screen")
	assert_eq(layout.unit_info_panel.get_current_unit(), unit,
			"with the same unit selected as before")
	assert_false(get_tree().paused, "and the battle was never paused")
