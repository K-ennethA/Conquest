extends GutTest

## The SHIELD readout on the real, booted battle HUD.
##
## The unit suite (`unit/test_shield_readout.gd`) pins the arithmetic and the world-space
## bar. This one asks the question that arithmetic cannot answer, and that this project has
## been burned by twice: is it DRAWN? Every assertion below is about rendered geometry --
## the width a label is laid out at against the width its own text needs, the anchors and
## the pixel width of the bar's silver tail, the card's pinned height with the readout on,
## and the forecast card's rect inside the 1280x720 window with its new row shown.
##
## Boots the REAL GameUILayout.tscn and drives selection through GameEvents, i.e. exactly
## the path a click on the board takes. `test_battle_hud_live_unit_info.gd` is the pattern.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const HOVER_PANEL_SCRIPT := preload("res://game/ui/panels/UnitHoverPanel.gd")

const DESIGN := Vector2i(1280, 720)

## The fixture's ward and health, so the expected fractions are stated once.
const WARD := 15
const MAX_HP := 40

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

func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"geode"
	c.display_name = "Geode"
	c.description = "A crystal-shelled warden."
	c.base_health = MAX_HP
	c.base_attack = 20
	c.base_defense = 5
	c.base_speed = 12
	c.base_movement = 3
	return c


func _unit() -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	add_child_autofree(u)  # _ready builds the controllers a live unit needs
	return u


## A unit at 25/40 carrying a real 15-point ward, granted through the production API.
func _warded_unit() -> Unit:
	var u := _unit()
	u.take_damage(MAX_HP - 25)
	u.grant_shield(WARD)
	return u


func _damaging_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"root_slam"
	m.display_name = "Root Slam"
	m.accuracy = 1.0
	var hit := DamageEffect.new()
	hit.power = 20
	m.effects = [hit]
	return m


func _stub_preview(total: int) -> Callable:
	var base: Dictionary = {
		"hit_pct": 100.0,
		"crit_pct": 0.0,
		"total": total,
		"base": total,
		"crit_damage": total,
		"target_hp": 25,
		"remaining": maxi(0, 25 - total),
		"lethal": false,
	}
	return func(_move, _attacker, _defender, _board = null) -> Dictionary:
		return base


func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


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


func _all_text(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.find_children("*", "Label", true, false):
		parts.append((child as Label).text)
	return "\n".join(parts)


## Assert [param label] carries [param expected] and is laid out wide enough to draw it.
func _assert_reads(label: Label, expected: String, where: String) -> void:
	assert_not_null(label, "%s has the shield label" % where)
	if label == null:
		return
	assert_true(label.visible, "%s's shield number is on screen" % where)
	assert_eq(label.text, expected, "%s names the ward" % where)
	var needed: float = _text_width(label)
	gut.p("%-14s label %s  needs %.1fpx for '%s'"
			% [where, _rect_of(label), needed, label.text])
	assert_true(needed > 0.0, "%s's shield label has real text to draw" % where)
	assert_true(label.size.x >= needed - 1.0,
			"%s's shield label is drawn at least as wide as its own text (%.1f >= %.1f) -- "
			% [where, label.size.x, needed]
			+ "anything narrower is the clipped-to-a-dot failure this HUD has shipped before")


# ==============================================================================
# 1. The battle card
# ==============================================================================

func test_the_card_shows_the_ward_as_a_number_beside_the_hp_numbers() -> void:
	var layout: Control = await _build_hud()
	await _select(_warded_unit())

	var card = layout.unit_info_panel
	_assert_reads(card._shield_label, "%s%d" % [ShieldVisuals.GLYPH, WARD], "the battle card")
	assert_eq(card.health_label.text, "25/40",
			"beside untouched HP numbers -- the ward is an addition, not a rewrite")
	assert_eq(card._shield_label.get_theme_color("font_color"), ShieldVisuals.SILVER,
			"drawn in the theme's steel, the same hue as the bar segment")


func test_the_cards_hp_bar_grows_a_silver_tail_after_its_green() -> void:
	var layout: Control = await _build_hud()
	await _select(_warded_unit())

	var card = layout.unit_info_panel
	var bar: ProgressBar = card.health_bar
	var tail: ColorRect = card._shield_tail
	gut.p("card bar    : %s   tail %s anchors [%.3f, %.3f]"
			% [_rect_of(bar), _rect_of(tail), tail.anchor_left, tail.anchor_right])

	assert_true(tail.visible, "the ward is drawn on the bar, not only spelled out")
	assert_almost_eq(tail.anchor_left, 25.0 / 40.0, 0.001,
			"the tail starts exactly where the green HP fill ends")
	assert_almost_eq(tail.anchor_right, 40.0 / 40.0, 0.001,
			"and runs the ward's own 15 points at the bar's points-per-pixel")
	assert_true(tail.size.x > 1.0,
			"and it is laid out with real width, not a 1px sliver (%.1f)" % tail.size.x)
	assert_true(tail.size.x <= bar.size.x + 0.5,
			"while staying inside the bar it rides (%.1f <= %.1f)" % [tail.size.x, bar.size.x])
	assert_eq(tail.color, ShieldVisuals.SILVER, "in the shield's silver")


func test_the_ward_costs_the_pinned_card_no_height() -> void:
	# The card's height is PINNED and the left column budgets against that constant, so a
	# readout that grew it would silently overlap the terrain card below.
	var layout: Control = await _build_hud()
	await _select(_warded_unit())

	var card = layout.unit_info_panel
	var card_rect: Rect2 = _rect_of(card)
	var row: Control = card.health_label.get_parent() as Control
	gut.p("card        : %s  content=%.1f  pinned=%.1f  hp row h=%.1f"
			% [card_rect, card.fixed_content_height(), UnitInfoPanel.CARD_HEIGHT, row.size.y])

	assert_true(card.fixed_content_height() <= UnitInfoPanel.CARD_HEIGHT,
			"the warded card still fits its pinned %.0fpx budget (%.1f)"
			% [UnitInfoPanel.CARD_HEIGHT, card.fixed_content_height()])
	var label_rect: Rect2 = _rect_of(card._shield_label)
	assert_true(label_rect.end.x <= card_rect.end.x + 0.5,
			"the number ends inside the card's right edge (%.1f <= %.1f)"
			% [label_rect.end.x, card_rect.end.x])
	assert_false(label_rect.intersects(_rect_of(card.health_label)),
			"and never overlaps the HP numbers it sits beside")


func test_an_unshielded_unit_gets_exactly_the_card_that_shipped_before() -> void:
	var layout: Control = await _build_hud()
	await _select(_unit())

	var card = layout.unit_info_panel
	assert_false(card._shield_label.visible,
			"no ward, no number -- not a '◊0' and not an empty gap")
	assert_false(card._shield_tail.visible, "and no tail on the bar")
	assert_eq(card.health_bar.max_value, float(MAX_HP),
			"the bar's scale is plain max health again")
	assert_eq(card.health_bar.value, float(MAX_HP), "with the green filling all of it")


func test_spending_the_ward_returns_every_card_row_to_its_pre_shield_state() -> void:
	var layout: Control = await _build_hud()
	var unit := _warded_unit()
	await _select(unit)
	var card = layout.unit_info_panel
	assert_true(card._shield_label.visible, "the ward starts up")
	var bar_value_before: float = card.health_bar.value

	# A hit the ward eats whole, applied through the production path.
	unit.take_damage(WARD)
	await _select(unit)   # the card repaints on selection, as it does for every stat

	assert_eq(unit.current_health, 25, "the hit cost no health -- the ward ate it")
	assert_false(card._shield_label.visible, "and with the ward spent the number is gone")
	assert_false(card._shield_tail.visible, "the tail with it")
	assert_eq(card.health_bar.max_value, float(MAX_HP), "the bar's scale is plain again")
	assert_eq(card.health_bar.value, bar_value_before,
			"and the green is exactly where it was -- the ward never moved it")


# ==============================================================================
# 2. The hover card
# ==============================================================================

func _hover_panel() -> Control:
	var panel := Control.new()
	panel.set_script(HOVER_PANEL_SCRIPT)
	add_child_autofree(panel)
	return panel


func test_the_hover_card_carries_the_same_number_on_its_hp_row() -> void:
	var panel: Control = _hover_panel()
	var unit := _warded_unit()
	panel.show_for_unit(unit)
	for i in range(4):
		await get_tree().process_frame

	_assert_reads(panel._shield_label, "%s%d" % [ShieldVisuals.GLYPH, WARD], "the hover card")
	assert_eq(panel._hp_label.text, "HP 25/40", "beside the HP numbers, not instead of them")
	assert_true(panel._shield_tail.visible, "and its bar carries the tail too")
	assert_almost_eq(panel._hp_bar.value, 25.0 / 40.0, 0.001,
			"with the green fill unmoved by the ward")


func test_the_hover_card_is_unchanged_for_an_unshielded_unit() -> void:
	var panel: Control = _hover_panel()
	panel.show_for_unit(_unit())
	for i in range(4):
		await get_tree().process_frame

	assert_false(panel._shield_label.visible, "no ward, no number")
	assert_false(panel._shield_tail.visible, "and no tail")
	assert_eq(panel._hp_label.text, "HP 40/40", "just the HP line it always drew")


func test_the_hover_cards_shield_row_does_not_grow_the_card() -> void:
	# The hover card has NO fixed height -- it grows up-and-left from the corner -- so a
	# row that got taller would move the whole card. Measured against the same card
	# without a ward.
	var bare: Control = _hover_panel()
	bare.show_for_unit(_unit())
	for i in range(4):
		await get_tree().process_frame
	var bare_height: float = bare._card.size.y

	var warded: Control = _hover_panel()
	warded.show_for_unit(_warded_unit())
	for i in range(4):
		await get_tree().process_frame
	gut.p("hover card  : bare %.1f   warded %.1f" % [bare_height, warded._card.size.y])

	assert_almost_eq(warded._card.size.y, bare_height, 0.5,
			"the ward rides the existing HP row and costs the card no height")


# ==============================================================================
# 3. The detail page
# ==============================================================================

func test_the_detail_page_lists_a_shield_row_only_while_one_is_up() -> void:
	var layout: Control = await _build_hud()
	var unit := _warded_unit()
	await _select(unit)
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame

	var page: UnitDetailPage = layout.unit_detail_page
	var text: String = _all_text(page)
	assert_true(text.contains("Shield:"), "the stat table gains a Shield row")
	assert_true(text.contains("%s %d" % [ShieldVisuals.GLYPH, WARD]),
			"naming the points the ward is holding")
	assert_true(text.contains("Health:"), "directly under the Health row it belongs with")
	page.close()

	# ...and it is GONE once the ward is spent: a "Shield: 0" on every unit is furniture.
	unit.take_damage(WARD)
	await _select(unit)
	layout.unit_info_panel.open_details()
	for i in range(6):
		await get_tree().process_frame
	assert_false(_all_text(page).contains("Shield:"),
			"an unwarded unit's page has no Shield row at all")
	page.close()


# ==============================================================================
# 4. The combat forecast
# ==============================================================================

func _forecast_of(layout: Control) -> CombatForecastPanel:
	return layout.unit_actions_panel.combat_forecast_panel


func _aim_at(layout: Control, defender: Unit, total: int) -> CombatForecastPanel:
	var panel: CombatForecastPanel = _forecast_of(layout)
	panel.set_preview_source(_stub_preview(total))
	panel.show_forecast(_unit(), defender, _damaging_move())
	for i in range(4):
		await get_tree().process_frame
	return panel


func test_aiming_at_a_warded_target_says_how_much_the_ward_eats() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim_at(layout, _warded_unit(), 24)

	assert_true(panel._shield_value.get_parent().visible,
			"a warded target shows the Shield row")
	assert_eq(panel._shield_value.text, "absorbs 15 (0 left)",
			"stating the soak and what survives it: %s" % panel._shield_value.text)
	assert_eq(panel._dmg_value.text, "24",
			"while the Damage number keeps exactly the meaning it had -- the row EXPLAINS "
			+ "that number, it does not restate it")
	assert_true(panel._shield_value.size.x >= _text_width(panel._shield_value) - 1.0,
			"and the row is drawn wide enough to read (%.1f for %.1fpx)"
			% [panel._shield_value.size.x, _text_width(panel._shield_value)])
	panel.hide_forecast()


func test_a_hit_the_ward_only_partly_eats_reports_the_remainder() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim_at(layout, _warded_unit(), 10)

	assert_eq(panel._shield_value.text, "absorbs 10 (5 left)",
			"the ward survives a small hit, and the row says by how much")
	panel.hide_forecast()


func test_an_unwarded_target_shows_no_shield_row_at_all() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim_at(layout, _unit(), 24)

	assert_false(panel._shield_value.get_parent().visible,
			"the common case is silent -- a 'Shield 0' line on every aim is furniture")
	panel.hide_forecast()


func test_the_forecast_card_stays_in_the_window_with_the_shield_row_on() -> void:
	var layout: Control = await _build_hud()
	var panel: CombatForecastPanel = await _aim_at(layout, _warded_unit(), 24)

	var card: Control = panel._card
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var rect: Rect2 = _rect_of(card)
	gut.p("forecast    : %s   (viewport %s)  shield row=%s"
			% [rect, vp, panel._shield_value.get_parent().visible])

	assert_true(rect.position.y >= 0.0, "the card starts inside the top edge")
	assert_true(rect.end.y <= vp.y,
			"and ends inside the bottom edge with the Shield row on (%.1f <= %.1f)"
			% [rect.end.y, vp.y])
	assert_true(rect.end.x <= vp.x,
			"while staying inside the right edge (%.1f <= %.1f)" % [rect.end.x, vp.x])
	panel.hide_forecast()
