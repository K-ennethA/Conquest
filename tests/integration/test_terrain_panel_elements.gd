extends GutTest

## THE TERRAIN CARD'S ELEMENT ROWS, on the REAL mounted panel.
##
## Every assertion here is read off a rendered control in a live viewport -- the panel is
## instantiated, added to the tree, given frames to settle, and then measured. A helper
## returning the right STRING is not evidence: the reported failures on this card have
## always been geometry (a clipped chip drawn as an 11px dot, a card growing off the
## bottom of the screen), and only the rendered tree can show those.
##
## What is pinned:
##   * the element BADGE exists, names the tile's element, and is WIDER THAN ITS TEXT --
##     the clip_text/1px-minimum trap ElementVisuals.fit_label exists for;
##   * the MATCHUP line appears only with a selection AND a non-neutral matchup, carries
##     the arithmetic, and is tinted with the HUD's buff/nerf pair;
##   * the damage it quotes is the tile's own tick number, not a second calculation;
##   * the card still fits MAX_HEIGHT with both rows on it, and the chip list's scroll
##     absorbs the difference.

const RESOLUTION := Vector2i(1280, 720)

const FIRE_TILE := "res://game/tiles/effects/resources/fire.tres"
const GRASS_TILE := "res://game/tiles/effects/resources/tall_grass.tres"
const MEADOW_TILE := "res://game/tiles/effects/resources/sacred_meadow.tres"

const CELL := Vector2i(3, 4)

var _prev_window_size: Vector2i
var _panel: TerrainInfoPanel


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = RESOLUTION


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func before_each() -> void:
	# CombatServices is an AUTOLOAD -- cleared in both hooks so neither a previous suite's
	# board nor this suite's tile effects leak either way (tests/README.md rule 3).
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	ElementChart.reset_chart()
	_panel = null


# --- Fixtures -----------------------------------------------------------------


## The real panel, mounted and settled.
func _mount() -> TerrainInfoPanel:
	_panel = TerrainInfoPanel.new()
	add_child_autofree(_panel)
	for i in range(6):
		await get_tree().process_frame
	return _panel


## Put [param effect_path] on [constant CELL] through the live CombatServices, which is
## the exact lookup the panel reads (applied_tile_effects_at / tile_effects_at).
func _place_effect(effect_path: String) -> TileEffectResource:
	var effect: TileEffectResource = load(effect_path)
	CombatServices.add_tile_effect(CELL, effect)
	return effect


## A live [Unit] of [param element], adopted into the tree so _ready() runs.
func _unit(element: StringName) -> Unit:
	var character := CharacterResource.new()
	character.character_id = &"test_subject"
	character.display_name = "Test Subject"
	character.element = element
	var unit := Unit.new()
	unit.character_resource = character
	add_child_autofree(unit)
	return unit


## Show the card for [constant CELL] with [param unit] selected (null = no selection), and
## let the deferred reflow land.
func _show(panel: TerrainInfoPanel, unit) -> void:
	panel.set_selected_unit(unit)
	panel.show_for_cell(CELL)
	for i in range(4):
		await get_tree().process_frame


func _badge(panel: TerrainInfoPanel) -> PanelContainer:
	return panel.find_child(ElementVisuals.BADGE_NAME, true, false) as PanelContainer


func _badge_label(panel: TerrainInfoPanel) -> Label:
	return panel.find_child(ElementVisuals.BADGE_LABEL_NAME, true, false) as Label


func _matchup(panel: TerrainInfoPanel) -> Label:
	return panel.find_child("ElementMatchupLabel", true, false) as Label


# --- The badge ----------------------------------------------------------------


func test_the_card_badges_the_tiles_element() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, null)

	var badge := _badge(panel)
	var label := _badge_label(panel)
	assert_not_null(badge, "the card carries the shared element badge widget")
	assert_true(badge.visible, "a fire tile shows its element")
	assert_eq(label.text, "Fire", "and names it with the shared element vocabulary")


func test_the_badge_is_wider_than_the_text_it_draws() -> void:
	# THE trap this assertion exists for: the badge's label is clip_text, a clipped Label
	# reports a MINIMUM WIDTH of 1px, and a SHRINK_END child of an HBox is laid out at
	# exactly its minimum -- so without ElementVisuals.fit_label the chip renders as a
	# ~11px coloured dot. Measured on the rendered node, never on the helper.
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, null)

	var label := _badge_label(panel)
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	var needed: float = font.get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	gut.p("badge label : size=%s min=%s needs=%.1f"
		% [label.size, label.custom_minimum_size, needed])

	assert_true(label.custom_minimum_size.x >= needed - 0.5,
		"the label claims at least the width its text draws at")
	assert_true(label.size.x >= needed - 0.5, "and is laid out that wide on screen")
	assert_true(_badge(panel).size.x > needed,
		"so the pill is a readable chip, not an 11px dot")


func test_terrain_nobody_elemented_shows_no_badge() -> void:
	# "No element" is not a kind of element: a chip reading "Neutral" on most of the map
	# would be furniture, not information.
	var panel: TerrainInfoPanel = await _mount()
	await _show(panel, null)
	assert_false(_badge(panel).visible, "a bare cell carries no element badge")


# --- The matchup line ----------------------------------------------------------


func test_no_matchup_line_without_a_selection() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, null)
	assert_false(_matchup(panel).visible,
		"with nobody selected there is no 'vs you' to state")


func test_a_strong_matchup_states_the_arithmetic_and_tints_it() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, _unit(&"nature"))

	var row := _matchup(panel)
	gut.p("matchup row : '%s' visible=%s" % [row.text, row.visible])
	assert_true(row.visible, "a nature unit on fire terrain is told about it")
	assert_true(row.text.contains("×1.25"),
		"the row shows the multiplier itself, not just a verdict word")
	assert_true(row.text.contains("vs you"), "and says who it is measured against")
	assert_eq(row.get_theme_color("font_color"), MoveStatVisuals.NERF_COLOR,
		"a matchup AGAINST the player is tinted with the HUD's nerf colour")


func test_a_resisted_matchup_is_tinted_in_the_players_favour() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, _unit(&"fire"))

	var row := _matchup(panel)
	assert_true(row.visible, "a fire unit at home in fire is told it takes less")
	assert_true(row.text.contains("×0.75"), "and by exactly how much")
	assert_eq(row.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
		"a matchup in the player's favour is tinted with the buff colour")


func test_a_neutral_matchup_renders_as_nothing() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, _unit(&"holy"))
	assert_false(_matchup(panel).visible,
		"fire and holy have no matchup, and the row's ABSENCE is the signal")

	await _show(panel, _unit(&""))
	assert_false(_matchup(panel).visible,
		"nor does an unelemented unit get a row saying so")


func test_the_row_follows_the_selection() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	var nature := _unit(&"nature")

	await _show(panel, nature)
	assert_true(_matchup(panel).visible, "selected: the row is up")

	panel._on_unit_deselected(nature)
	await get_tree().process_frame
	assert_false(_matchup(panel).visible,
		"deselected: the row goes away without the cursor having to move")


func test_the_quoted_damage_is_the_tiles_own_tick_number() -> void:
	# PREVIEW == REALITY (CONQUEST.md rule 9). The panel must not compute damage of its
	# own; the number in the row is TileEffectResource.damage_preview_for, which is
	# DamageMath's chain on the same environment-marked move the tick builds.
	var panel: TerrainInfoPanel = await _mount()
	var fire := _place_effect(FIRE_TILE)
	var nature := _unit(&"nature")
	await _show(panel, nature)

	var expected: int = fire.damage_preview_for(nature, CombatServices.board())
	assert_eq(expected, 19, "15 fire into nature is 15 x 1.25 = 18.75 -> 19")
	assert_true(_matchup(panel).text.contains("(%d dmg)" % expected),
		"and that is the number on the card")


func test_a_tile_that_deals_no_damage_quotes_none() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(GRASS_TILE)
	await _show(panel, _unit(&"nature"))

	var row := _matchup(panel)
	gut.p("grass row   : '%s'" % row.text)
	assert_true(row.visible, "tall grass is nature, so a nature unit has a matchup with it")
	assert_false(row.text.contains("dmg"),
		"but grass conceals rather than burns, and the card must not invent damage")
	assert_true(row.text.contains("boosts ×1.25") and row.text.contains("(+19)"),
		"it reports the BOOST instead: +15 evasion reads +19 for a nature occupant")


# --- The benefit the tile grants -----------------------------------------------
#
# The harm rows above are only half the rule. A tile that favours the selected unit is
# news too, and burying it under a chip would make the element system read as a pure tax.


func test_the_meadow_announces_its_boosted_heal_in_the_players_favour() -> void:
	var panel: TerrainInfoPanel = await _mount()
	var meadow := _place_effect(MEADOW_TILE)
	var nature := _unit(&"nature")
	await _show(panel, nature)

	var row := _matchup(panel)
	gut.p("meadow row  : '%s' visible=%s" % [row.text, row.visible])
	assert_true(row.visible, "a nature unit is told the nature meadow favours it")
	assert_true(row.text.contains("heals ×1.25"),
		"the row names WHAT the tile does and by how much, not just a verdict")
	assert_true(row.text.contains("for you"),
		"and says the boost is theirs -- 'vs you' is the harm wording")
	assert_eq(row.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
		"a boost is tinted with the HUD's buff colour, like every other good news")

	# PREVIEW == REALITY on the benefit side too: the number in the row is the same
	# home_effect_amount call the effect's own run scales through.
	var landed: int = int(meadow.home_summary_for(nature).get("landed", 0))
	assert_eq(landed, 13, "10 HP x 1.25 = 12.5 -> 13 for a nature occupant")
	assert_true(row.text.contains("(%d HP)" % landed), "and that is the number on the card")


func test_the_meadow_says_nothing_to_a_unit_it_does_not_favour() -> void:
	# The reassignment's whole point: the meadow is NATURE, so holy gets no affinity.
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(MEADOW_TILE)
	await _show(panel, _unit(&"holy"))
	assert_false(_matchup(panel).visible,
		"a holy unit has no relationship with the meadow, so the row stays away")

	await _show(panel, _unit(&""))
	assert_false(_matchup(panel).visible,
		"nor does an unelemented unit get a row saying nothing happened")


func test_the_boost_line_is_not_clipped_by_the_cards_width() -> void:
	# The row is clip_text, so an over-long phrasing would silently ellipsize the number
	# that is the entire point of it. Measured on the rendered label.
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(MEADOW_TILE)
	await _show(panel, _unit(&"nature"))

	var row := _matchup(panel)
	var font: Font = row.get_theme_font("font")
	var needed: float = font.get_string_size(
		row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, row.get_theme_font_size("font_size")).x
	gut.p("boost row   : drawn=%.1f wide, row=%.1f" % [needed, row.size.x])
	assert_true(needed <= row.size.x,
		"the whole boost line fits the card's content width without trimming")


# --- The 152px budget ----------------------------------------------------------


func test_the_card_still_fits_its_cap_with_both_element_rows() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	_place_effect(GRASS_TILE)
	await _show(panel, _unit(&"nature"))
	panel._reflow_card()
	await get_tree().process_frame

	var card: PanelContainer = panel._card
	gut.p("card        : size=%s  badge=%s  matchup=%s"
		% [card.size, _badge(panel).size, _matchup(panel).size])
	assert_true(_matchup(panel).visible, "the worst case: badge + matchup row + two chips")
	assert_true(card.size.y <= TerrainInfoPanel.MAX_HEIGHT + 0.5,
		"the card never exceeds the height the HUD reserved for it")
	assert_true(card.global_position.y + card.size.y
			<= panel.size.y - TerrainInfoPanel.MARGIN + 0.5,
		"and still sits a margin above the bottom of the screen")


func test_the_badge_costs_the_name_row_no_height() -> void:
	# The badge is only free if the row's tallest child is still the 18pt name. If a future
	# font size makes the pill taller, the budget above silently starts eating the chip
	# list -- this is what catches that.
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, null)

	var row: Control = panel.find_child("NameRow", true, false) as Control
	var name_label: Label = panel.find_child("TerrainNameLabel", true, false) as Label
	gut.p("name row    : %s  name=%s  badge=%s"
		% [row.size, name_label.size, _badge(panel).size])
	assert_true(_badge(panel).size.y <= name_label.size.y + 0.5,
		"the element pill is no taller than the name it sits beside")
	assert_true(row.size.y <= name_label.size.y + 0.5,
		"so the row is exactly as tall as it was before the badge existed")


func test_the_chip_list_absorbs_the_extra_rows() -> void:
	var panel: TerrainInfoPanel = await _mount()
	for path in [FIRE_TILE, GRASS_TILE,
			"res://game/tiles/effects/resources/rock_rubble.tres",
			"res://game/tiles/effects/resources/fortify.tres"]:
		_place_effect(path)
	await _show(panel, _unit(&"nature"))
	panel._reflow_card()
	await get_tree().process_frame

	var scroll: ScrollContainer = panel._effects_scroll
	var container: Control = panel._effects_container
	gut.p("scroll      : %s  content min=%s"
		% [scroll.size, container.get_combined_minimum_size()])
	assert_eq(container.get_child_count(), 4, "every effect on the cell got a chip")
	assert_true(container.get_combined_minimum_size().y > scroll.size.y,
		"four chips do not fit, which is the case the scroll exists for")
	assert_true(panel._card.size.y <= TerrainInfoPanel.MAX_HEIGHT + 0.5,
		"and the card holds its cap instead of growing to fit them")


# --- The name row still behaves ------------------------------------------------


func test_a_long_terrain_name_can_never_widen_the_card() -> void:
	var panel: TerrainInfoPanel = await _mount()
	_place_effect(FIRE_TILE)
	await _show(panel, null)
	var name_label: Label = panel.find_child("TerrainNameLabel", true, false) as Label
	name_label.text = "An Extremely Long Authored Terrain Name That Would Wrap"
	panel._reflow_card()
	await get_tree().process_frame

	assert_true(name_label.clip_text,
		"the name clips rather than wrapping, now that it shares its row with the badge")
	assert_true(panel._card.size.x <= TerrainInfoPanel.PANEL_WIDTH + 0.5,
		"so no name can push the card wider than its 260px frame")
	assert_true(_badge(panel).visible, "and the badge is not squeezed off the row")
