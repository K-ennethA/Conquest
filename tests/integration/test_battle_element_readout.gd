extends GutTest

## The ELEMENT readout, as it is actually DRAWN, booted from the real [GameUILayout].
##
## WHY THIS SUITE IS SHAPED LIKE THIS. Twice now a battle-UI change has passed a suite
## that read strings out of a node tree while the shipped screen showed nothing usable --
## a status chip laid out 11px wide with its text trimmed away, and a whole detail page
## allotted zero height. Both were invisible to text-only assertions. So this suite boots
## GameUILayout.tscn, drives selection through GameEvents (the path a board click takes),
## and every assertion is about RENDERED geometry: the width a badge is drawn at against
## the width its own text needs, the height the cards claim, and whether the forecast
## card's rect is still inside the 1280x720 window with its new rows on.
##
## It follows `test_battle_hud_live_unit_info.gd` exactly -- that file is the pattern.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const HOVER_PANEL_SCRIPT := preload("res://game/ui/panels/UnitHoverPanel.gd")

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

func _character(element: StringName) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.description = "A stout root-knight."
	c.element = element
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 5
	c.base_speed = 12
	c.base_movement = 3
	return c


func _unit(element: StringName) -> Unit:
	var u := Unit.new()
	u.character_resource = _character(element)
	add_child_autofree(u)  # _ready builds the controllers a live unit needs
	return u


## A move with one DamageEffect on it -- the forecast only draws its damage rows (and
## therefore the breakdown rows) for a move that can actually deal damage.
func _damaging_move(element: StringName) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"root_slam"
	m.display_name = "Root Slam"
	m.element = element
	m.accuracy = 1.0
	var hit := DamageEffect.new()
	hit.power = 20
	m.effects = [hit]
	return m


## A stubbed preview producer, injected through the panel's ONE seam. Returns a fixed
## dictionary so a matchup can be rendered without authoring a chart entry for it.
func _stub_preview(extra: Dictionary) -> Callable:
	var base: Dictionary = {
		"hit_pct": 100.0,
		"crit_pct": 0.0,
		"total": 24,
		"base": 20,
		"crit_damage": 24,
		"target_hp": 40,
		"remaining": 16,
		"lethal": false,
	}
	for key in extra:
		base[key] = extra[key]
	return func(_move, _attacker, _defender, _board = null) -> Dictionary:
		return base


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
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _rect_of(control: Control) -> Rect2:
	return Rect2(control.global_position, control.size)


func _badge_in(root: Node) -> PanelContainer:
	return root.find_child(ElementVisuals.BADGE_NAME, true, false) as PanelContainer


## Assert that [param badge] is on screen, names [param expected], and is DRAWN at least
## as wide as the text it has to draw. The last clause is the one that matters: a pill
## narrower than its label is the "small coloured dot" this project has already shipped.
func _assert_badge_reads(badge: PanelContainer, expected: String, where: String) -> void:
	assert_not_null(badge, "%s carries an element badge" % where)
	if badge == null:
		return
	assert_true(badge.visible, "%s's badge is on screen" % where)
	var label := badge.get_node(ElementVisuals.BADGE_LABEL_NAME) as Label
	assert_eq(label.text, expected, "%s's badge names the element" % where)
	var needed: float = _text_width(label)
	gut.p("%-14s badge %s   label %s   text needs %.1fpx for '%s'"
			% [where, _rect_of(badge), _rect_of(label), needed, label.text])
	assert_true(needed > 0.0, "%s's badge has real text to draw" % where)
	assert_true(label.size.x >= needed - 1.0,
			"%s's badge label is drawn at least as wide as its own text (%.1f >= %.1f)"
			% [where, label.size.x, needed])
	assert_true(badge.size.x >= needed,
			"and %s's pill is wider still, so nothing is trimmed away" % where)


# ==============================================================================
# 1. The compact battle card's element badge
# ==============================================================================

func test_the_live_card_badges_the_selected_units_element() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&"nature"))

	_assert_badge_reads(_badge_in(layout.unit_info_panel), "Nature", "the battle card")


func test_the_cards_badge_is_the_colour_the_moves_stripe_with() -> void:
	# The single-palette claim, asserted on the rendered stylebox rather than on the
	# helper: there is one element colour source and the badge came out of it.
	var layout: Control = await _build_hud()
	await _select(_unit(&"frost"))

	var badge: PanelContainer = _badge_in(layout.unit_info_panel)
	assert_not_null(badge, "the card badges a frost unit")
	if badge == null:
		return
	var box := badge.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box, "the badge is painted with its own stylebox")
	if box != null:
		assert_eq(box.border_color, ConquestTheme.element_color("frost"),
				"framed in the same hue a frost move's row stripe uses")


func test_a_unit_with_no_element_gets_no_chip_at_all() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&""))

	var badge: PanelContainer = _badge_in(layout.unit_info_panel)
	assert_not_null(badge, "the badge node exists on the card regardless")
	if badge == null:
		return
	assert_false(badge.visible,
			"but an unelemented unit shows no chip -- 'Neutral' on two thirds of the "
			+ "roster is furniture, not information")


func test_the_badge_follows_the_selection_from_one_element_to_another() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&"fire"))
	_assert_badge_reads(_badge_in(layout.unit_info_panel), "Fire", "the battle card")

	await _select(_unit(&"holy"))
	_assert_badge_reads(_badge_in(layout.unit_info_panel), "Holy", "the re-pointed card")

	await _select(_unit(&""))
	assert_false(_badge_in(layout.unit_info_panel).visible,
			"and disappears again for a unit with no element")


func test_the_badge_costs_the_pinned_card_no_height_and_no_width() -> void:
	# The card's whole budget contract: its height is PINNED, and the left column budgets
	# against that constant. A badge that pushed the card past it would silently overlap
	# the terrain card in the corner below.
	var layout: Control = await _build_hud()
	await _select(_unit(&"nature"))

	var card = layout.unit_info_panel
	var card_rect: Rect2 = _rect_of(card)
	var margin := card.get_node("MarginContainer") as Control
	gut.p("card        : %s  content=%.1f  pinned=%.1f"
			% [card_rect, card.fixed_content_height(), UnitInfoPanel.CARD_HEIGHT])
	gut.p("card margin : min=%s" % margin.get_combined_minimum_size())

	assert_true(card.fixed_content_height() <= UnitInfoPanel.CARD_HEIGHT,
			"the badged card still fits its pinned %.0fpx budget (%.1f)"
			% [UnitInfoPanel.CARD_HEIGHT, card.fixed_content_height()])
	assert_true(margin.get_combined_minimum_size().x <= card_rect.size.x + 0.5,
			"and nothing on it demands more width than the 260px column gives it")

	var badge: PanelContainer = _badge_in(card)
	var badge_rect: Rect2 = _rect_of(badge)
	assert_true(badge_rect.end.x <= card_rect.end.x + 0.5,
			"the badge ends inside the card's right edge (%.1f <= %.1f)"
			% [badge_rect.end.x, card_rect.end.x])
	assert_true(badge_rect.end.y <= card_rect.end.y + 0.5,
			"and inside its bottom edge -- nothing is cut off")


func test_the_badge_never_squeezes_the_name_off_the_card() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&"nature"))

	var card = layout.unit_info_panel
	var name_label: Label = card.unit_name_label
	var badge: PanelContainer = _badge_in(card)
	gut.p("name label  : %s   badge %s" % [_rect_of(name_label), _rect_of(badge)])
	assert_true(name_label.size.x >= _text_width(name_label) - 1.0,
			"the unit's name is still drawn in full beside the badge (%.1f for %.1fpx)"
			% [name_label.size.x, _text_width(name_label)])
	assert_false(_rect_of(name_label).intersects(_rect_of(badge)),
			"and the two never overlap on the name row")


# ==============================================================================
# 2. The detail page's identity header
# ==============================================================================

func test_the_open_detail_page_badges_the_element_in_its_header() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&"nature"))
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var header := page._card.find_child("Header", true, false) as Control
	assert_not_null(header, "the page has an identity header")
	if header == null:
		return
	_assert_badge_reads(_badge_in(header), "Nature", "the detail header")
	page.close()


func test_the_header_badge_does_not_steal_the_pages_scroll_region() -> void:
	# The page's failure mode is a body allotted no height. The header growing would take
	# that height straight out of the scroll region, so the budget is asserted, not hoped.
	var layout: Control = await _build_hud()
	await _select(_unit(&"nature"))
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var scroll := page._card.find_child("Scroll", true, false) as ScrollContainer
	var header := page._card.find_child("Header", true, false) as Control
	gut.p("page header : %s   scroll %s" % [_rect_of(header), _rect_of(scroll)])
	assert_not_null(scroll, "the page still has a scroll region")
	if scroll == null:
		return
	assert_true(scroll.size.y > 200.0,
			"and it is still allotted real height with the badge in the header (%.1f)"
			% scroll.size.y)
	assert_true(page._body.size.x > 400.0,
			"at the page's document width (%.1f)" % page._body.size.x)
	page.close()


func test_an_unelemented_unit_opens_a_page_with_no_chip() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit(&""))
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var header := page._card.find_child("Header", true, false) as Control
	assert_not_null(header, "the page has an identity header")
	if header == null:
		return
	assert_false(_badge_in(header).visible,
			"the header shows no element chip when there is no element")
	assert_true(page._name_label.size.x >= _text_width(page._name_label) - 1.0,
			"and the name still owns the row it shares with the hidden badge")
	page.close()


# ==============================================================================
# 3. The forecast's effectiveness + ability lines
# ==============================================================================

func _forecast_of(layout: Control) -> CombatForecastPanel:
	return layout.unit_actions_panel.combat_forecast_panel


func _aim(layout: Control, extra: Dictionary) -> CombatForecastPanel:
	var panel: CombatForecastPanel = _forecast_of(layout)
	panel.set_preview_source(_stub_preview(extra))
	panel.show_forecast(_unit(&"fire"), _unit(&"nature"), _damaging_move(&"fire"))
	for i in range(4):
		await get_tree().process_frame
	return panel


func test_a_strong_matchup_is_named_on_the_forecast() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 1.5, "element_label": &"strong"})

	assert_true(panel._type_value.get_parent().visible,
			"a non-neutral matchup shows the Type row")
	assert_eq(panel._type_value.text, "Strong ×1.5",
			"naming the verdict and the multiplier: %s" % panel._type_value.text)
	assert_eq(panel._type_value.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
			"in the same green a buffed stat is drawn in")
	assert_true(panel._type_value.size.x >= _text_width(panel._type_value) - 1.0,
			"and the row is drawn wide enough to read (%.1f for %.1fpx)"
			% [panel._type_value.size.x, _text_width(panel._type_value)])
	panel.hide_forecast()


func test_a_resisted_matchup_is_named_in_the_debuff_colour() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 0.75, "element_label": &"resisted"})

	assert_true(panel._type_value.get_parent().visible, "a resisted hit shows the row too")
	assert_eq(panel._type_value.text, "Resisted ×0.75",
			"stating the loss just as plainly: %s" % panel._type_value.text)
	assert_eq(panel._type_value.get_theme_color("font_color"), MoveStatVisuals.NERF_COLOR,
			"in the red a cut stat is drawn in")
	panel.hide_forecast()


func test_a_neutral_matchup_shows_no_line_at_all() -> void:
	# The common case, and the design rule for this row: no noise where there is no news.
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 1.0, "element_label": &"neutral"})

	assert_false(panel._type_value.get_parent().visible,
			"a x1.0 matchup spends none of the card's height saying 'Neutral'")
	panel.hide_forecast()


func test_an_ability_bonus_names_itself_from_the_previews_notes() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 1.0,
		"element_label": &"neutral",
		"ability_bonus_percent": 30,
		"ability_notes": ["Grass Cutter"]})

	assert_true(panel._ability_value.get_parent().visible,
			"an ability that changed this hit gets a row")
	assert_eq(panel._ability_value.text, "+30% (Grass Cutter)",
			"stating how much and which ability: %s" % panel._ability_value.text)
	assert_eq(panel._ability_value.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
			"green, because it is damage in the player's favour")
	assert_true(panel._ability_value.size.x >= _text_width(panel._ability_value) - 1.0,
			"and it is drawn wide enough to read")
	panel.hide_forecast()


func test_no_ability_bonus_shows_no_ability_row() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 1.0, "element_label": &"neutral", "ability_bonus_percent": 0})

	assert_false(panel._ability_value.get_parent().visible,
			"0% is no effect, so there is nothing to say and no row that says it")
	panel.hide_forecast()


func test_the_forecast_takes_its_damage_number_from_the_previews_total() -> void:
	# The breakdown rows explain a number this panel does not compute. It has to be the
	# previewer's final one, or the explanation is attached to the wrong figure.
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"total": 33, "remaining": 7, "element_mult": 1.5, "element_label": &"strong"})

	assert_true(panel._dmg_value.text.begins_with("33"),
			"the Damage row shows the preview's total (%s)" % panel._dmg_value.text)
	assert_eq(panel._result_value.text, "40 -> 7",
			"and the HP row the remainder it came with")
	panel.hide_forecast()


func test_the_card_stays_inside_the_window_with_both_new_rows_on() -> void:
	# This panel has a history of leaving the screen. Both breakdown rows shown at once is
	# its tallest state, so that is the state the 720p bound is measured in.
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim(layout, {
		"element_mult": 1.5,
		"element_label": &"strong",
		"crit_pct": 25.0,
		"crit_damage": 36,
		"ability_bonus_percent": 30,
		"ability_notes": ["Grass Cutter", "Thornlust"]})

	var card: Control = panel._card
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = _rect_of(card)
	gut.p("forecast    : %s   (viewport %s)" % [rect, vp])
	gut.p("rows shown  : type=%s ability=%s crit=%s"
			% [panel._type_value.get_parent().visible,
			panel._ability_value.get_parent().visible,
			panel._crit_value.get_parent().visible])

	assert_true(panel._type_value.get_parent().visible, "the tallest state really is the "
			+ "one being measured -- Type row on")
	assert_true(panel._ability_value.get_parent().visible, "...and Ability row on")
	assert_true(rect.position.y >= 0.0, "the card starts inside the top edge")
	assert_true(rect.end.y <= vp.y,
			"and ends inside the bottom edge with both rows on (%.1f <= %.1f)"
			% [rect.end.y, vp.y])
	assert_true(rect.end.x <= vp.x,
			"while staying inside the right edge (%.1f <= %.1f)" % [rect.end.x, vp.x])
	panel.hide_forecast()


func test_a_healing_move_gets_neither_breakdown_row() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = _forecast_of(layout)
	panel.set_preview_source(_stub_preview({"element_mult": 1.5, "element_label": &"strong"}))

	var heal := MoveResource.new()
	heal.move_id = &"mend"
	heal.display_name = "Mend"
	panel.show_forecast(_unit(&"fire"), _unit(&"nature"), heal)
	for i in range(4):
		await get_tree().process_frame

	assert_false(panel._type_value.get_parent().visible,
			"a move with no damage has no matchup to explain")
	assert_false(panel._ability_value.get_parent().visible,
			"and nothing for an ability to have modified")
	panel.hide_forecast()


# ==============================================================================
# 4. The hover card's mini-chip -- added only because it costs no height
# ==============================================================================

## Duck-typed unit: the hover panel reads HP through `"current_health" in unit` guards
## and the element through get_element(), so it needs no live Unit.
class StubUnit extends Node:
	var current_health: int = 40
	var max_health: int = 60
	var _element: StringName = &""
	func _init(element: StringName = &"") -> void:
		_element = element
	func get_display_name() -> String:
		return "Stub"
	func get_element() -> StringName:
		return _element


func _hover_panel() -> Control:
	var panel := Control.new()
	panel.set_script(HOVER_PANEL_SCRIPT)
	add_child_autofree(panel)
	return panel


func test_the_hover_card_badges_the_element_on_its_existing_hp_row() -> void:
	var panel: Control = _hover_panel()
	var unit := StubUnit.new(&"nature")
	add_child_autofree(unit)
	panel.show_for_unit(unit)
	for i in range(4):
		await get_tree().process_frame

	_assert_badge_reads(_badge_in(panel), "Nature", "the hover card")
	var hp_row := panel.find_child("HPRow", true, false) as Control
	assert_not_null(hp_row, "the badge rides the HP row that was already there")
	if hp_row != null:
		assert_eq(_badge_in(panel).get_parent(), hp_row,
				"rather than a new row that would grow the card")


func test_the_hover_chip_does_not_grow_the_card() -> void:
	# The brief's condition for putting a chip here at all. The card has no fixed height
	# -- it grows up-and-left from the bottom-right corner -- so "fits in an existing row"
	# has to mean the measured height is unchanged, not that it looks about right.
	var panel: Control = _hover_panel()
	var plain := StubUnit.new(&"")
	var elemented := StubUnit.new(&"nature")
	add_child_autofree(plain)
	add_child_autofree(elemented)

	panel.show_for_unit(plain)
	for i in range(4):
		await get_tree().process_frame
	var card := panel.find_child("UnitHoverCard", true, false) as Control
	assert_not_null(card, "the hover card is built")
	if card == null:
		return
	var without: float = card.get_combined_minimum_size().y

	panel.show_for_unit(elemented)
	for i in range(4):
		await get_tree().process_frame
	var with_badge: float = card.get_combined_minimum_size().y

	gut.p("hover card  : %.1fpx without a badge, %.1fpx with one" % [without, with_badge])
	assert_true(_badge_in(panel).visible, "the badge really is showing for the comparison")
	assert_eq(with_badge, without,
			"the element chip costs the hover card no height at all (%.1f vs %.1f)"
			% [with_badge, without])
	assert_true(card.size.x <= UnitHoverPanel.PANEL_WIDTH + 0.5,
			"and no width past the card's 240px claim (%.1f)" % card.size.x)


func test_the_hover_chip_is_absent_for_an_unelemented_unit() -> void:
	var panel: Control = _hover_panel()
	var unit := StubUnit.new(&"")
	add_child_autofree(unit)
	panel.show_for_unit(unit)
	for i in range(4):
		await get_tree().process_frame

	assert_false(_badge_in(panel).visible,
			"no element, no chip -- the HP row is exactly what it was before")
