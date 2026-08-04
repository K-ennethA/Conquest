extends GutTest

## The TILES section of the Compendium as it is actually DRAWN, booted from the real
## `menus/Compendium.tscn`.
##
## The derivation rules (which tile is elemented, and by what) are pure statics pinned in
## `unit/test_tile_gallery_elements.gd`. None of that proves a player can SEE the element,
## and this project has twice shipped a screen whose string-reading suite was green while
## the page was broken -- a chip laid out 11px wide with its text trimmed off being the
## exact failure mode an element badge is prone to (the badge's label is CLIPPED, so it
## reports a 1px minimum and an unfitted badge draws as a coloured dot).
##
## So everything here mounts the shipped shell, opens the section through it, selects a
## tile through the gallery's own selection handler, and measures the RENDERED tree:
##
##   * an elemented tile shows a badge, and the badge is drawn at least as wide as the
##     text it must draw;
##   * its effects carry the badge too -- including terrain whose effect is a legacy
##     TileEffect with no id of its own, which inherits the tile's element;
##   * an ELEMENTLESS tile shows no badge anywhere. Absence is the authored answer.

const COMPENDIUM := preload("res://menus/Compendium.tscn")

const DESIGN := Vector2i(1280, 720)

var _prev_window_size: Vector2i


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func after_each() -> void:
	# The chart is a static cache -- global state, restored from the hook so a failing
	# assertion cannot leak into a later suite.
	ElementChart.reset_chart()
	await get_tree().process_frame


# =====================================================================================
#  Mounting
# =====================================================================================

## Boot the real Compendium with the TILES section open.
##
## The section index is pointed BEFORE _ready for the same reason
## `integration/test_element_chart_gallery_screen.gd` does it: the shell hosts its sections
## lazily and builds whichever one opens first, so this is the shell's own code path and it
## keeps the suite from spinning up the galleries it has no business exercising.
func _open_tiles() -> TileGallery:
	var screen: Compendium = COMPENDIUM.instantiate()
	screen._current_section = Compendium.SECTION_TILES
	add_child_autofree(screen)
	for i in range(10):
		await get_tree().process_frame
	var host := screen.find_child("Tiles", true, false) as Control
	if host == null or host.get_child_count() == 0:
		return null
	return host.get_child(0) as TileGallery


## Select the shipped tile with [param id] through the gallery's OWN selection handler --
## the one its list emits into -- so the page is built exactly as a click builds it.
## Fails the test itself when the tile is not in the shipped catalogue -- a renamed tile
## must show up as a broken fixture, not as a silently skipped assertion.
func _select(gallery: TileGallery, id: StringName) -> void:
	for i in range(gallery.filtered_tiles.size()):
		if gallery.filtered_tiles[i] != null and gallery.filtered_tiles[i].get_id() == id:
			gallery._on_tile_selected(i)
			for j in range(4):
				await get_tree().process_frame
			return
	fail_test("'%s' is not in the shipped tile catalogue" % id)


func _badge_label(badge: Control) -> Label:
	return badge.get_node_or_null(ElementVisuals.BADGE_LABEL_NAME) as Label


## Width the badge's own text needs at the badge's own font size.
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x


func _effect_badges(gallery: TileGallery) -> Array[Node]:
	return gallery.effects_container.find_children(
			TileGallery.EFFECT_BADGE_NAME, "", true, false)


# =====================================================================================
#  An elemented tile
# =====================================================================================

func test_an_elemented_tile_shows_a_badge_wide_enough_to_read() -> void:
	var gallery: TileGallery = await _open_tiles()
	assert_not_null(gallery, "the shell built the tiles section")
	if gallery == null:
		return
	await _select(gallery, &"tall_grass")

	var row: Control = gallery.tile_element_row
	var badge: Control = gallery.tile_element_badge
	var label: Label = _badge_label(badge)

	gut.p("row     : visible=%s rect=%s" % [row.is_visible_in_tree(),
			Rect2(row.global_position, row.size)])
	gut.p("badge   : \"%s\" rect=%s  text needs %.1f"
			% [label.text, Rect2(badge.global_position, badge.size), _text_width(label)])

	assert_true(row.is_visible_in_tree(), "the element row is on screen for an elemented tile")
	assert_true(badge.is_visible_in_tree(), "and so is the badge itself")
	assert_eq(label.text, ElementVisuals.label_for(&"nature"),
			"tall grass is nature, read off the chart")
	assert_gt(label.size.x, 0.0, "the badge label was granted real width")
	assert_true(label.size.x + 1.0 >= _text_width(label),
			"the badge is drawn at least as wide as its own text, so nothing is trimmed "
			+ "to an 11px coloured dot")


func test_the_matchup_hint_is_drawn_next_to_the_badge() -> void:
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"tall_grass")

	var hint: Label = gallery.tile_matchup_label
	gut.p("hint    : \"%s\"" % hint.text)
	assert_false(hint.text.strip_edges().is_empty(),
			"the matchup line says what the element does, not just what it is")
	assert_eq(hint.text, TileGallery.matchup_hint(&"nature"),
			"and it is the LIVE line, read from the matrix rather than authored here")
	assert_true(hint.is_visible_in_tree(), "drawn, not built and hidden")


func test_a_tile_elemented_by_its_own_id_is_badged_too() -> void:
	# deep_water carries no effect resource at all -- it is elemented as a TILE, which is
	# how terrain that grows its own effect is authored.
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"deep_water")

	var label: Label = _badge_label(gallery.tile_element_badge)
	gut.p("badge   : \"%s\"" % label.text)
	assert_true(gallery.tile_element_row.is_visible_in_tree(),
			"terrain with no effect resource is still elemented")
	assert_eq(label.text, ElementVisuals.label_for(&"water"), "deep water is water")


# =====================================================================================
#  The effect cards
# =====================================================================================

func test_an_elemented_effect_card_carries_its_own_badge() -> void:
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"tall_grass")

	var badges: Array[Node] = _effect_badges(gallery)
	gut.p("effect badges: %d" % badges.size())
	assert_gt(badges.size(), 0, "the tile's authored effect is badged on its own card")
	for badge in badges:
		var label: Label = _badge_label(badge as Control)
		assert_true((badge as Control).is_visible_in_tree(), "the effect badge is drawn")
		assert_true(label.size.x + 1.0 >= _text_width(label),
				"and it is wide enough for \"%s\"" % label.text)


func test_a_legacy_effect_inherits_the_tiles_element_on_screen() -> void:
	# molten_lava's burn is a legacy TileEffect with no id to key on: the chart elements
	# the TILE instead, and the card has to pick that up or lava's effect would be the one
	# elementless card on an elemented page.
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"molten_lava")

	assert_eq(_badge_label(gallery.tile_element_badge).text,
			ElementVisuals.label_for(&"fire"), "lava is fire")
	var badges: Array[Node] = _effect_badges(gallery)
	gut.p("effect badges: %d" % badges.size())
	assert_gt(badges.size(), 0, "its burn is badged as fire too, inherited from the tile")


# =====================================================================================
#  An elementless tile
# =====================================================================================

func test_an_elementless_tile_shows_no_badge_at_all() -> void:
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"grass_plains")

	gut.p("row visible  : %s" % gallery.tile_element_row.is_visible_in_tree())
	gut.p("effect badges: %d" % _effect_badges(gallery).size())

	assert_false(gallery.tile_element_row.is_visible_in_tree(),
			"the chart leaves pure-utility terrain neutral, so the whole row is hidden -- a "
			+ "row reading 'Neutral / no matchups' would be furniture, not information")
	assert_eq(_effect_badges(gallery).size(), 0,
			"and nothing on the page invents an element for it")


func test_the_row_comes_back_when_an_elemented_tile_is_selected_again() -> void:
	# The header row is built ONCE and re-pointed per selection (the ElementVisuals
	# contract), so the hide has to be reversible -- a one-way hide would blank the badge
	# for the rest of the session after a single elementless tile.
	var gallery: TileGallery = await _open_tiles()
	if gallery == null:
		return
	await _select(gallery, &"tall_grass")
	assert_true(gallery.tile_element_row.is_visible_in_tree(), "row shown")

	await _select(gallery, &"obsidian")
	assert_false(gallery.tile_element_row.is_visible_in_tree(), "row hidden for obsidian")

	await _select(gallery, &"deep_water")
	assert_true(gallery.tile_element_row.is_visible_in_tree(), "row shown again")
	assert_eq(_badge_label(gallery.tile_element_badge).text,
			ElementVisuals.label_for(&"water"), "re-pointed at the new tile's element")


func test_the_badge_text_is_one_the_font_can_draw() -> void:
	# Same pin the HUD carries: an element NAME is plain ASCII today, and this is what
	# keeps a decorative glyph from being slipped into it later. (See the probe table in
	# unit/test_status_feedback.gd for the measured drawable set.)
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	for element in ElementChartGallery.elements():
		var text: String = ElementVisuals.label_for(element)
		for i in range(text.length()):
			var code: int = text.unicode_at(i)
			if code == 32:
				continue
			assert_true(font.has_char(code),
				"element name \"%s\" is drawable ('%s' U+%04X)" % [text, text[i], code])
