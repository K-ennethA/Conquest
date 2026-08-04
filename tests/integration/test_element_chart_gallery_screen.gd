extends GutTest

## The ELEMENTS section as it is actually DRAWN, booted from the real
## [code]menus/Compendium.tscn[/code].
##
## WHY THIS SUITE IS SHAPED LIKE THIS. This project has twice shipped a screen that
## passed a suite reading strings out of a node tree while the visible page was broken
## -- a chip laid out 11px wide with its text trimmed off, a detail page allotted zero
## height. So nothing here builds a widget by hand: it mounts the shipped Compendium
## scene, opens the section through the shell, and asserts on the RENDERED tree --
## how many rows the grid really has, what colour a cell is really painted, whether a
## label is really drawn as wide as the text it must draw, and whether the whole page
## is really inside a 1280x720 window.
##
## It follows `integration/test_battle_element_readout.gd`, which is the pattern.
##
## AND IT PROVES THE PAGE IS LIVE. The last test swaps in a chart the shipped .tres
## has never seen BEFORE the screen is mounted, and asserts the drawn grid and the
## drawn cards changed shape. That is the content-phase promise: edit the .tres, the
## Compendium follows, no code edit.

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
	# The chart is a static cache -- global state, restored here rather than at the end
	# of a test body so a failing assertion cannot leak into a later suite.
	ElementChart.reset_chart()
	await get_tree().process_frame
	await get_tree().process_frame


# --- Mounting ------------------------------------------------------------------

## Boot the real Compendium with the Elements section open.
##
## The section index is pointed BEFORE _ready. That is not a shortcut around the nav:
## the shell hosts its sections lazily and builds whichever one opens first, so this
## is the shell's own code path -- and it means this suite does not spin up the three
## 3D gallery SubViewports it has no business exercising. The nav BUTTON is driven for
## real in `test_the_nav_button_switches_to_the_section`.
func _open_compendium() -> Compendium:
	var screen: Compendium = COMPENDIUM.instantiate()
	screen._current_section = Compendium.SECTION_ELEMENTS
	add_child_autofree(screen)
	for i in range(8):
		await get_tree().process_frame
	return screen


func _gallery_in(screen: Compendium) -> ElementChartGallery:
	var host := screen.find_child("Elements", true, false) as Control
	if host == null or host.get_child_count() == 0:
		return null
	return host.get_child(0) as ElementChartGallery


func _grid_in(gallery: ElementChartGallery) -> GridContainer:
	return gallery.find_child(ElementChartGallery.GRID_NAME, true, false) as GridContainer


func _cards_in(gallery: ElementChartGallery) -> VBoxContainer:
	return gallery.find_child(ElementChartGallery.CARDS_NAME, true, false) as VBoxContainer


# --- Rendering helpers ---------------------------------------------------------

## The width [param label]'s own text needs at the size it is actually drawn.
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## Assert [param label] is drawn at least as wide as the glyphs it has to paint. THE
## assertion this suite exists for: a label narrower than its own text is the failure
## mode that shipped twice, and it is invisible to a text-only check.
func _assert_reads(label: Label, where: String) -> void:
	assert_not_null(label, "%s is on the page" % where)
	if label == null:
		return
	assert_true(label.visible, "%s is visible" % where)
	var needed: float = _text_width(label)
	assert_true(needed > 0.0, "%s has real text to draw ('%s')" % [where, label.text])
	gut.p("%-26s drawn %6.1fpx   text needs %6.1fpx   '%s'"
			% [where, label.size.x, needed, label.text])
	assert_true(label.size.x >= needed - 1.0,
			"%s is drawn at least as wide as its own text (%.1f >= %.1f)"
			% [where, label.size.x, needed])


## Children of [param parent] whose name starts with [param prefix]. Counted rather
## than pattern-matched so a stray extra child is caught rather than skipped.
func _count_prefixed(parent: Node, prefix: String) -> int:
	var total: int = 0
	for child in parent.get_children():
		if String(child.name).begins_with(prefix):
			total += 1
	return total


# ==============================================================================
# 1. Sidebar registration
# ==============================================================================

func test_the_sidebar_registers_an_elements_section() -> void:
	var screen: Compendium = await _open_compendium()

	var nav := screen.find_child("Nav_Elements", true, false) as Button
	assert_not_null(nav, "the nav rail carries an Elements entry, like every other section")
	if nav == null:
		return
	assert_eq(nav.text, "Elements", "named for what it browses")
	assert_true(nav.size.y >= 44.0,
			"and keeps the rail's >=44px touch target (%.0f)" % nav.size.y)

	var badge := nav.get_node_or_null("Badge") as Label
	assert_not_null(badge, "with a count badge, like the other entries")
	if badge != null:
		assert_eq(badge.text, str(ElementChartGallery.elements().size()),
				"counting the elements the CHART authors -- not a number typed into the shell")


func test_the_section_mounts_the_real_gallery_scene() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	assert_not_null(gallery,
			"the Elements host holds the shipped ElementChartGallery scene, hosted exactly "
			+ "the way the Unit / Tile / Map galleries are")
	if gallery == null:
		return
	assert_true(gallery.visible, "and it is the section on screen")
	assert_not_null(gallery.back_button, "it honours the hosted-gallery back_button contract")
	if gallery.back_button != null:
		assert_false(gallery.back_button.visible,
				"which the shell hides, because the rail supplies the one back control")


func test_the_nav_button_switches_to_the_section() -> void:
	var screen: Compendium = await _open_compendium()
	var elements_host := screen.find_child("Elements", true, false) as Control
	var statuses_host := screen.find_child("Statuses", true, false) as Control
	assert_not_null(elements_host, "the Elements host exists")
	assert_not_null(statuses_host, "so does a neighbour to switch away to")
	if elements_host == null or statuses_host == null:
		return

	(screen.find_child("Nav_Statuses", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_false(elements_host.visible, "pressing another entry hides the Elements page")

	(screen.find_child("Nav_Elements", true, false) as Button).pressed.emit()
	for i in range(4):
		await get_tree().process_frame
	assert_true(elements_host.visible, "and pressing Elements brings it back")
	assert_false(statuses_host.visible, "with exactly one section on screen")


# ==============================================================================
# 2. The type chart grid
# ==============================================================================

func test_the_grid_is_one_row_and_one_column_per_charted_element() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	assert_not_null(grid, "the page draws a type chart grid")
	if grid == null:
		return

	var count: int = ElementChartGallery.elements().size()
	assert_true(count > 0, "the shipped chart authors elements to draw")
	gut.p("chart elements: %d  ->  grid %dx%d" % [count, count + 1, count + 1])

	assert_eq(grid.columns, count + 1,
			"one column per defender, plus the attacker-name column")
	assert_eq(grid.get_child_count(), (count + 1) * (count + 1),
			"and a full square: the header row, the header column and every pairing")
	assert_eq(_count_prefixed(grid, ElementChartGallery.ROW_HEADER_PREFIX), count,
			"one attacker badge per element down the left")
	assert_eq(_count_prefixed(grid, ElementChartGallery.COL_HEADER_PREFIX), count,
			"one defender badge per element across the top")
	assert_eq(_count_prefixed(grid, ElementChartGallery.CELL_PREFIX), count * count,
			"and one cell per ordered pairing")


func test_the_headers_are_element_badges_drawn_wide_enough_to_read() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	if grid == null:
		assert_not_null(grid, "the page draws a type chart grid")
		return

	# THE ROW header gets the roomy cap and must read in full.
	var row_head := grid.get_node_or_null(
			ElementChartGallery.ROW_HEADER_PREFIX + "nature") as PanelContainer
	assert_not_null(row_head, "the nature ROW is headed by an element badge, not a bare string")
	if row_head != null:
		assert_true(row_head.visible, "and it is on screen")
		_assert_reads(row_head.get_node_or_null(ElementVisuals.BADGE_LABEL_NAME) as Label,
				"the nature row header")
		var box := row_head.get_theme_stylebox("panel") as StyleBoxFlat
		assert_not_null(box, "the badge is painted with its own chip stylebox")
		if box != null:
			assert_eq(box.border_color, ConquestTheme.element_color("nature"),
					"framed in the ONE element palette, same hue a nature move's stripe uses")

	# THE COLUMN header is deliberately capped to the cell width, so that a long
	# authored element id cannot widen all N columns and blow the 720p budget. It must
	# still be drawn at everything it claims -- the failure being guarded against is a
	# chip laid out at 1px, not one that trims a long name on purpose.
	var col_head := grid.get_node_or_null(
			ElementChartGallery.COL_HEADER_PREFIX + "nature") as PanelContainer
	assert_not_null(col_head, "the nature COLUMN is headed by an element badge too")
	if col_head != null:
		var label := col_head.get_node_or_null(ElementVisuals.BADGE_LABEL_NAME) as Label
		assert_not_null(label, "the column badge carries a label")
		if label != null:
			var needed: float = _text_width(label)
			var claimed: float = minf(needed, ElementChartGallery.COL_BADGE_CAP)
			gut.p("col header 'nature'  drawn %.1fpx  needs %.1fpx  cap %.1fpx"
					% [label.size.x, needed, ElementChartGallery.COL_BADGE_CAP])
			assert_true(label.size.x >= claimed - 1.0,
					"drawn at its claimed width (%.1f >= %.1f), never collapsed to a dot"
					% [label.size.x, claimed])
			assert_true(col_head.size.x <= ElementChartGallery.CELL_W,
					"and inside one cell's width (%.1f <= %.0f), which is what keeps an N-column grid inside the budget"
					% [col_head.size.x, ElementChartGallery.CELL_W])


func test_a_strong_cell_shows_its_multiplier_in_the_buff_colour() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	if grid == null:
		assert_not_null(grid, "the page draws a type chart grid")
		return

	var cell := grid.get_node_or_null("%sfire_nature"
			% ElementChartGallery.CELL_PREFIX) as Label
	assert_not_null(cell, "fire attacking nature has its own cell")
	if cell == null:
		return

	assert_eq(cell.text, "×1.25", "which prints the multiplier the chart authors")
	assert_eq(cell.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
			"in the buff green -- the same 'better for me' colour the HUD uses")
	_assert_reads(cell, "the fire->nature cell")

	var box := cell.get_theme_stylebox("normal") as StyleBoxFlat
	assert_not_null(box, "a decided cell is tinted so it pops out of the matrix")
	if box != null:
		assert_almost_eq(box.bg_color.r, MoveStatVisuals.BUFF_COLOR.r, 0.01,
				"tinted with the same green, at card alpha")


func test_a_resisted_cell_shows_its_multiplier_in_the_nerf_colour() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	if grid == null:
		assert_not_null(grid, "the page draws a type chart grid")
		return

	var cell := grid.get_node_or_null("%sfire_fire" % ElementChartGallery.CELL_PREFIX) as Label
	assert_not_null(cell, "fire attacking fire has its own cell")
	if cell == null:
		return
	assert_eq(cell.text, "×0.75", "every element resists itself in the shipped chart")
	assert_eq(cell.get_theme_color("font_color"), MoveStatVisuals.NERF_COLOR,
			"drawn in the nerf red")
	_assert_reads(cell, "the fire->fire cell")


func test_a_neutral_cell_is_drawn_blank() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	if grid == null:
		assert_not_null(grid, "the page draws a type chart grid")
		return

	var cell := grid.get_node_or_null("%sfire_holy" % ElementChartGallery.CELL_PREFIX) as Label
	assert_not_null(cell, "fire against holy is an unauthored pairing, and still has a cell")
	if cell == null:
		return
	assert_eq(cell.text, "",
			"which draws NOTHING -- blank is the neutral reading, and it is what makes the "
			+ "authored exceptions visible")
	assert_true(cell.size.x >= ElementChartGallery.CELL_W - 1.0,
			"but still claims a full cell (%.0f), so the grid stays a grid" % cell.size.x)
	assert_ne(cell.tooltip_text, "",
			"the blank explains itself on hover rather than being ambiguous")


# ==============================================================================
# 3. The per-element cards
# ==============================================================================

func test_every_element_gets_a_card() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var cards: VBoxContainer = _cards_in(gallery)
	assert_not_null(cards, "the page draws a card column")
	if cards == null:
		return
	assert_eq(_count_prefixed(cards, ElementChartGallery.CARD_PREFIX),
			ElementChartGallery.elements().size(),
			"one card per element the chart knows about")


func test_a_paired_element_reads_both_directions() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var cards: VBoxContainer = _cards_in(gallery)
	if cards == null:
		assert_not_null(cards, "the page draws a card column")
		return

	var card := cards.get_node_or_null("%sfire" % ElementChartGallery.CARD_PREFIX)
	assert_not_null(card, "fire has a card")
	if card == null:
		return

	_assert_reads(card.find_child(ElementChartGallery.CARD_SELF_RESIST, true, false) as Label,
			"fire's self-resistance line")

	var strong := card.find_child(ElementChartGallery.CARD_STRONG_ROW, true, false)
	var weak := card.find_child(ElementChartGallery.CARD_WEAK_ROW, true, false)
	assert_not_null(strong, "fire lists what it is strong against")
	assert_not_null(weak, "and what it is weak to -- both directions, read off the matrix")
	if strong == null or weak == null:
		return

	var badge_name: String = ElementChartGallery.BADGE_PREFIX + "nature"
	assert_not_null(strong.get_node_or_null(badge_name),
			"fire burns wood, badged rather than spelled out")
	assert_not_null(weak.get_node_or_null(badge_name),
			"and green chokes out flame")

	var chip := strong.get_node_or_null(badge_name) as PanelContainer
	if chip != null:
		_assert_reads(chip.get_node_or_null(ElementVisuals.BADGE_LABEL_NAME) as Label,
				"the nature badge on fire's card")

	assert_null(card.find_child(ElementChartGallery.CARD_NO_MATCHUPS, true, false),
			"a paired element never shows the no-matchups line")


func test_the_unpaired_element_says_it_has_no_matchups_yet() -> void:
	# Wind ships with NO opposite, deliberately: nothing in the game carries it yet, so
	# pairing it would be inventing balance for content that does not exist. The page
	# has to say that -- filling the gap here is how a reference screen starts lying.
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var cards: VBoxContainer = _cards_in(gallery)
	if cards == null:
		assert_not_null(cards, "the page draws a card column")
		return

	var card := cards.get_node_or_null("%swind" % ElementChartGallery.CARD_PREFIX)
	assert_not_null(card, "wind has a card like every other element")
	if card == null:
		return

	var none_label := card.find_child(ElementChartGallery.CARD_NO_MATCHUPS, true, false) as Label
	_assert_reads(none_label, "wind's no-matchups line")
	if none_label != null:
		assert_eq(none_label.text, ElementChartGallery.NO_MATCHUPS_TEXT,
				"stating the gap in the chart's own terms")

	assert_null(card.find_child(ElementChartGallery.CARD_STRONG_ROW, true, false),
			"with no invented 'strong against' row")
	assert_null(card.find_child(ElementChartGallery.CARD_WEAK_ROW, true, false),
			"and no invented 'weak to' row")

	_assert_reads(card.find_child(ElementChartGallery.CARD_SELF_RESIST, true, false) as Label,
			"wind's self-resistance line")


# ==============================================================================
# 4. The legend, and the 720p budget
# ==============================================================================

func test_the_legend_names_the_colour_rule_in_one_line() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var legend := gallery.find_child(ElementChartGallery.LEGEND_NAME, true, false) as Control
	assert_not_null(legend, "the page carries a legend")
	if legend == null:
		return

	var strong := legend.get_node_or_null("LegendStrong") as Label
	var resisted := legend.get_node_or_null("LegendResisted") as Label
	var neutral := legend.get_node_or_null("LegendNeutral") as Label
	_assert_reads(strong, "the legend's strong sample")
	_assert_reads(resisted, "the legend's resisted sample")
	_assert_reads(neutral, "the legend's neutral sample")

	# The legend is a SAMPLE of the grid, not a sentence about it: each part is drawn
	# in the colour it names, so it cannot describe a palette the cells do not use.
	if strong != null:
		assert_eq(strong.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
				"drawn in the colour it names")
	if resisted != null:
		assert_eq(resisted.get_theme_color("font_color"), MoveStatVisuals.NERF_COLOR,
				"same for the resisted sample")

	var tallest: float = 0.0
	for part in legend.get_children():
		tallest = maxf(tallest, (part as Control).size.y)
	assert_true(legend.size.y <= tallest + 1.0,
			"and the whole legend is ONE line tall (%.0f), not a stacked block" % legend.size.y)


func test_the_page_fits_the_720p_viewport() -> void:
	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	assert_not_null(gallery, "the section is mounted")
	if gallery == null:
		return

	var rect := Rect2(gallery.global_position, gallery.size)
	gut.p("gallery rect %s inside viewport %s" % [rect, DESIGN])
	assert_true(rect.end.x <= float(DESIGN.x) + 1.0,
			"the page's right edge is inside the window (%.0f)" % rect.end.x)
	assert_true(rect.end.y <= float(DESIGN.y) + 1.0,
			"and so is its bottom edge (%.0f)" % rect.end.y)

	var chart_scroll := gallery.find_child(
			ElementChartGallery.GRID_SCROLL_NAME, true, false) as ScrollContainer
	var cards_scroll := gallery.find_child(
			ElementChartGallery.CARDS_SCROLL_NAME, true, false) as ScrollContainer
	assert_not_null(chart_scroll, "the grid sits in a scroll region")
	assert_not_null(cards_scroll, "so does the card column")
	if chart_scroll == null or cards_scroll == null:
		return

	# A ScrollContainer's own minimum size is ZERO. Both of these have been laid out at
	# nothing before on other screens; that is the trap this pair of assertions pins.
	assert_true(chart_scroll.size.y > 100.0,
			"the chart region is allotted real height (%.0f)" % chart_scroll.size.y)
	assert_true(cards_scroll.size.y > 100.0,
			"and so is the card region (%.0f)" % cards_scroll.size.y)

	var grid: GridContainer = _grid_in(gallery)
	if grid != null:
		gut.p("grid %.0fx%.0f in a %.0fx%.0f region"
				% [grid.size.x, grid.size.y, chart_scroll.size.x, chart_scroll.size.y])
		assert_true(grid.size.x <= chart_scroll.size.x + 1.0,
				"and at the shipped element count the whole grid is visible without "
				+ "scrolling sideways (%.0f <= %.0f)" % [grid.size.x, chart_scroll.size.x])

	var cards: VBoxContainer = _cards_in(gallery)
	if cards != null:
		assert_true(cards.size.x <= cards_scroll.size.x + 1.0,
				"the cards fit their column's width rather than overflowing it")


# ==============================================================================
# 5. The content-phase promise
# ==============================================================================

func test_editing_the_chart_redraws_the_page_with_no_code_edit() -> void:
	# The whole point of the section. A chart the shipped .tres has never seen, injected
	# through ElementChart's own test seam BEFORE the screen boots: a different number of
	# elements, different multipliers, a different unpaired element. Every one of those
	# has to come out the other side as drawn nodes.
	var vocab: Array[StringName] = [&"aero", &"bio", &"gale"]
	var crafted := ElementChartResource.new()
	crafted.elements = vocab
	crafted.matrix = {
		&"aero": {&"bio": 1.4},
		&"bio": {&"aero": 1.1, &"bio": 0.6},
		&"gale": {&"gale": 0.6},
	}
	ElementChart.set_chart(crafted)

	var screen: Compendium = await _open_compendium()
	var gallery: ElementChartGallery = _gallery_in(screen)
	var grid: GridContainer = _grid_in(gallery)
	var cards: VBoxContainer = _cards_in(gallery)
	assert_not_null(grid, "the grid is built from the injected chart")
	assert_not_null(cards, "so is the card column")
	if grid == null or cards == null:
		return

	assert_eq(grid.columns, 4, "three elements draw a 4x4 grid, not the shipped 8x8")
	assert_eq(_count_prefixed(grid, ElementChartGallery.CELL_PREFIX), 9,
			"nine ordered pairings, one cell each")

	var strong_cell := grid.get_node_or_null(
			"%saero_bio" % ElementChartGallery.CELL_PREFIX) as Label
	assert_not_null(strong_cell, "the crafted aero->bio pairing has a cell")
	if strong_cell != null:
		assert_eq(strong_cell.text, "×1.4",
				"printing the CRAFTED multiplier -- no number on this page is a constant")
		assert_eq(strong_cell.get_theme_color("font_color"), MoveStatVisuals.BUFF_COLOR,
				"coloured by the rule, not by the shipped chart's values")

	# Asymmetry survives the round trip: bio hits back for 1.1, which is its own entry.
	var back_cell := grid.get_node_or_null(
			"%sbio_aero" % ElementChartGallery.CELL_PREFIX) as Label
	if back_cell != null:
		assert_eq(back_cell.text, "×1.1",
				"and the reverse direction shows its own authored number")

	var gale_card := cards.get_node_or_null("%sgale" % ElementChartGallery.CARD_PREFIX)
	assert_not_null(gale_card, "the crafted unpaired element gets a card")
	if gale_card != null:
		var none_label := gale_card.find_child(
				ElementChartGallery.CARD_NO_MATCHUPS, true, false) as Label
		_assert_reads(none_label, "gale's no-matchups line")

	var aero_card := cards.get_node_or_null("%saero" % ElementChartGallery.CARD_PREFIX)
	if aero_card != null:
		assert_null(aero_card.find_child(ElementChartGallery.CARD_SELF_RESIST, true, false),
				"aero does not resist itself in this chart, so it shows no such line -- "
				+ "0.75 self-resistance is a seeded convention, not a rule of the page")
