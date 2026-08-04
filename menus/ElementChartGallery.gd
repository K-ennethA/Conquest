extends Control

class_name ElementChartGallery

# Element Chart Gallery - the Compendium's ELEMENTS section.
#
# EVERY NUMBER AND EVERY ELEMENT ON THIS PAGE IS READ LIVE FROM [ElementChart].
# Nothing here hardcodes "there are seven elements", and nothing here hardcodes 1.25
# or 0.75. The vocabulary comes from the resource, the multipliers come from the
# resource, and the strong/weak lists are DERIVED from the matrix in both directions.
# Retuning a matchup -- or authoring an eighth element -- is a content edit to
# res://game/combat/resources/element_chart.tres and this page changes with it, with
# zero code edits. That is the same contract CONQUEST.md rule 9 puts on the damage
# pipeline; the reference screen must not be the one place that drifts.
#
# THE THREE THINGS ON THE PAGE
#   1. TYPE CHART -- attacker rows x defender columns, one cell per pairing. A cell
#      shows its multiplier ONLY when the pairing is not neutral (see cell_text): a
#      matrix is mostly 1.0, so printing "x1" in 40 of 49 cells buries the 9 that
#      matter. Blank IS the neutral reading, and the exceptions pop.
#   2. PER-ELEMENT CARDS -- one card per element: does it resist itself, what is it
#      strong against (its ROW), what is it weak to (its COLUMN). An element with
#      neither says "No matchups yet". IT NEVER INVENTS A PAIR -- wind ships with no
#      opposite on purpose (see the chart resource's own notes) and this page says so
#      rather than filling the gap.
#   3. LEGEND -- one line naming the colour rule.
#
# THE COLOURS ARE NOT INVENTED HERE. Element hues come from [ElementVisuals] (which
# forwards to [ConquestTheme.element_color], the one element palette), and the
# strong/resisted tint is [ElementVisuals.effectiveness_color], i.e. the SAME
# MoveStatVisuals BUFF/NERF pair the battle forecast tints its effectiveness line
# with. Green means "better for the attacker" on this grid exactly as it means
# "better for me" on the HUD.
#
# WIDTH BUDGET (measured at the 1280x720 design size, which is the floor).
#   viewport 1280 - Compendium nav rail 216            = 1064 content host
#   1064 - 24 left margin - 24 right margin            = 1016 usable
#   1016 - 16 column separation                        = 1000 to split
#   chart column: HEADER_COL_W + n * (CELL_W + GRID_SEP)
#                 = 112 + 7 * 62                       =  546  (<= CHART_WIDTH_BUDGET)
#   cards column: 1000 - 546                           =  454
# The chart column claims its natural width up to CHART_WIDTH_BUDGET and no further,
# so an authored 8th element (608px natural) starts scrolling the grid horizontally
# instead of squeezing the cards. Height: (n + 1) * CELL_H + n * GRID_SEP = 268 for
# seven, against ~570 of body height -- the grid does not scroll vertically today.
# Both scroll regions are real ScrollContainers, so neither budget is a cliff.

const MUTED := Color(0.72, 0.70, 0.78)

# --- Grid geometry ----------------------------------------------------------

## Width of the leftmost (attacker badge) column. Wide enough for a full element
## name at FONT_CAPTION, unlike the compact column headers.
const HEADER_COL_W: float = 112.0

## One matchup cell. 58px carries "x1.25" at FONT_CAPTION (~30px) with room to spare
## and keeps an 8x8 grid inside the width budget above.
const CELL_W: float = 58.0
const CELL_H: float = 30.0
const GRID_SEP: int = 4

## The most horizontal space the chart column may claim before it starts scrolling
## rather than eating the cards column.
const CHART_WIDTH_BUDGET: float = 560.0

## Column-header badges are capped to the cell width so a long authored element id
## cannot widen every column; the ROW headers get the roomy cap and stay readable.
const COL_BADGE_CAP: float = CELL_W - 8.0
const ROW_BADGE_CAP: float = HEADER_COL_W - 16.0

# --- Node names (every test looks the page up by these) ---------------------

const GRID_NAME := "TypeChartGrid"
const GRID_SCROLL_NAME := "TypeChartScroll"
const CORNER_NAME := "TypeChartCorner"
const CARDS_NAME := "ElementCards"
const CARDS_SCROLL_NAME := "ElementCardsScroll"
const LEGEND_NAME := "ElementLegend"
const EMPTY_NAME := "EmptyChartNotice"

## Node-name prefixes. Ids are suffixed onto every one of these because sibling names
## must be unique -- seven badges all called "ElementBadge" in one row get silently
## renamed by the engine and become unfindable.
const CELL_PREFIX := "Cell_"
const ROW_HEADER_PREFIX := "RowHeader_"
const COL_HEADER_PREFIX := "ColHeader_"
const CARD_PREFIX := "ElementCard_"
const BADGE_PREFIX := "ElementBadge_"

## Names of the lines inside one element card.
const CARD_SELF_RESIST := "SelfResist"
const CARD_STRONG_ROW := "StrongRow"
const CARD_WEAK_ROW := "WeakRow"
const CARD_NO_MATCHUPS := "NoMatchups"

## The exact sentence an element with no authored pairing shows. Pinned as a constant
## because it is the "do not invent a matchup" promise, and a test asserts it.
const NO_MATCHUPS_TEXT := "No matchups yet"

# --- UI handles -------------------------------------------------------------

var back_button: Button
var chart_grid: GridContainer
var cards_box: VBoxContainer


# ===========================================================================
# Pure derivations -- no tree, no nodes. Everything the page DISPLAYS is
# computed here, so the rules can be tested against a crafted chart resource
# without mounting a screen.
# ===========================================================================

## Every element this page draws a row, a column and a card for, in authored order.
##
## The vocabulary comes first (that is what an author curates), then any element the
## MATRIX mentions that the vocabulary forgot -- a pairing authored against an
## unlisted element still resolves in combat, so hiding it here would make the
## reference lie. Never a hardcoded list.
static func elements() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in ElementChart.vocabulary():
		_append_key(out, entry)
	var matrix: Dictionary = ElementChart.chart().matrix
	for attacker in matrix:
		_append_key(out, attacker)
		var row: Variant = matrix[attacker]
		if row is Dictionary:
			for defender in (row as Dictionary):
				_append_key(out, defender)
	return out


static func _append_key(out: Array[StringName], value) -> void:
	var key: StringName = ElementChartResource.key_of(value)
	if key != &"" and not out.has(key):
		out.append(key)


## What one cell of the grid says. EMPTY for a neutral pairing -- see the class note:
## blank is the neutral reading, and it is what makes the authored exceptions visible.
static func cell_text(mult: float) -> String:
	if ElementVisuals.label_for_multiplier(mult) == ElementVisuals.NEUTRAL:
		return ""
	return "×%s" % ElementVisuals.format_multiplier(mult)


## Green for a pairing in the attacker's favour, red against, dim for neutral -- the
## MoveStatVisuals BUFF/NERF pair, reached through the theme layer's forwarder so this
## screen cannot introduce a second effectiveness palette.
static func cell_color(mult: float) -> Color:
	return ElementVisuals.effectiveness_color(
			ElementVisuals.label_for_multiplier(mult), MenuTheme.CREAM_DIM)


## Tooltip for one cell: the pairing spelled out, including the neutral case that the
## cell itself deliberately renders as nothing.
static func cell_tooltip(attacker, defender, mult: float) -> String:
	var verdict: String = ElementVisuals.effectiveness_word(
			ElementVisuals.label_for_multiplier(mult))
	if verdict == "":
		verdict = "Neutral"
	return "%s → %s:  ×%s  (%s)" % [
		ElementVisuals.label_for(attacker),
		ElementVisuals.label_for(defender),
		ElementVisuals.format_multiplier(mult),
		verdict,
	]


## Defenders [param element] hits for MORE than neutral -- its matrix ROW.
static func strong_against(element) -> Array[StringName]:
	var key: StringName = ElementChartResource.key_of(element)
	var out: Array[StringName] = []
	if key == &"":
		return out
	for defender in elements():
		if ElementVisuals.label_for_multiplier(ElementChart.multiplier(key, defender)) \
				== ElementVisuals.STRONG:
			out.append(defender)
	return out


## Attackers that hit [param element] for MORE than neutral -- its matrix COLUMN.
##
## Read separately from [method strong_against] and never inferred from it: the chart
## authors both directions explicitly and has no implied symmetry, so an asymmetric
## pairing (a hits b hard, b does nothing back) must read correctly on both cards.
static func weak_to(element) -> Array[StringName]:
	var key: StringName = ElementChartResource.key_of(element)
	var out: Array[StringName] = []
	if key == &"":
		return out
	for attacker in elements():
		if ElementVisuals.label_for_multiplier(ElementChart.multiplier(attacker, key)) \
				== ElementVisuals.STRONG:
			out.append(attacker)
	return out


## "Resists itself ×0.75", or "" when this element does not resist itself in this
## chart. The number is read, never assumed -- self-resist is a seeded convention,
## not a law, and an author may drop or retune it.
static func self_resist_text(element) -> String:
	var key: StringName = ElementChartResource.key_of(element)
	if key == &"":
		return ""
	var mult: float = ElementChart.multiplier(key, key)
	if ElementVisuals.label_for_multiplier(mult) != ElementVisuals.RESISTED:
		return ""
	return "Resists itself ×%s" % ElementVisuals.format_multiplier(mult)


## True when nothing in the chart makes this element strong against anything, and
## nothing is strong against it. Self-resistance does NOT count as a matchup: wind
## resists itself and still has no opposite, which is exactly the state the chart
## records and this page must report rather than paper over.
static func has_no_matchups(element) -> bool:
	return strong_against(element).is_empty() and weak_to(element).is_empty()


# ===========================================================================
# Construction
# ===========================================================================

func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look (matches the sibling galleries)
	_build_ui()


## Tear the page down and rebuild it from the CURRENT chart. Called from _ready; also
## the seam a test uses after swapping the chart on an already-mounted page.
func refresh() -> void:
	_build_ui()


func _build_ui() -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuTheme.apply_backdrop(self)  # standalone; harmless over the Compendium's own

	var outer := MarginContainer.new()
	outer.name = "Outer"
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	add_child(outer)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", 10)
	outer.add_child(page)

	page.add_child(_build_header())
	page.add_child(_build_legend())

	var element_list: Array[StringName] = elements()

	if element_list.is_empty():
		# A chart with no vocabulary and no matrix is a legal (if empty) resource --
		# say so instead of drawing an empty grid frame.
		var notice := Label.new()
		notice.name = EMPTY_NAME
		notice.text = "No elements are authored in the element chart yet."
		notice.modulate = MUTED
		notice.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.add_child(notice)
		return

	var body := HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	body.add_child(_build_chart_column(element_list))
	body.add_child(_build_cards_column(element_list))


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.name = "Header"
	row.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.name = "Title"
	title.text = "ELEMENTS"
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	# The gallery-contract BACK button. The Compendium shell hides it (it supplies the
	# single back control); it exists so this scene is also usable on its own, exactly
	# like the Unit / Tile / Map galleries it is hosted beside.
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	back_button.pressed.connect(_on_back_pressed)
	row.add_child(back_button)

	return row


## One compact line naming the colour rule. Three labels rather than one string,
## because the labels are DRAWN in the colours they describe -- the legend is a
## sample of the grid, not a sentence about it.
func _build_legend() -> Control:
	var row := HBoxContainer.new()
	row.name = LEGEND_NAME
	row.add_theme_constant_override("separation", 14)

	row.add_child(_legend_part("LegendStrong", "▲ Strong  (above ×1)",
			ElementVisuals.effectiveness_color(ElementVisuals.STRONG)))
	row.add_child(_legend_part("LegendResisted", "▼ Resisted  (below ×1)",
			ElementVisuals.effectiveness_color(ElementVisuals.RESISTED)))
	row.add_child(_legend_part("LegendNeutral", "blank  Neutral  (×1)", MenuTheme.CREAM_DIM))

	return row


func _legend_part(part_name: String, text: String, color: Color) -> Label:
	var label := Label.new()
	label.name = part_name
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	label.add_theme_color_override("font_color", color)
	return label


# --- The type chart ---------------------------------------------------------

func _build_chart_column(element_list: Array[StringName]) -> Control:
	var col := VBoxContainer.new()
	col.name = "ChartColumn"
	col.add_theme_constant_override("separation", 6)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	col.add_child(_section_header("Type chart"))

	var caption := Label.new()
	caption.name = "ChartCaption"
	caption.text = "Rows attack, columns defend."
	caption.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	caption.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(caption)

	var scroll := ScrollContainer.new()
	scroll.name = GRID_SCROLL_NAME
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# A ScrollContainer's own minimum size is ZERO in both axes, so inside a flexible
	# column it will happily be laid out at nothing. Claim the grid's natural size,
	# clamped to the width budget -- past that the grid scrolls sideways rather than
	# stealing the cards column.
	var natural_w: float = HEADER_COL_W + element_list.size() * (CELL_W + GRID_SEP)
	scroll.custom_minimum_size = Vector2(minf(natural_w, CHART_WIDTH_BUDGET), 200)
	col.add_child(scroll)

	chart_grid = GridContainer.new()
	chart_grid.name = GRID_NAME
	chart_grid.columns = element_list.size() + 1  # +1 for the attacker-name column
	chart_grid.add_theme_constant_override("h_separation", GRID_SEP)
	chart_grid.add_theme_constant_override("v_separation", GRID_SEP)
	scroll.add_child(chart_grid)

	_populate_grid(element_list)
	return col


func _populate_grid(element_list: Array[StringName]) -> void:
	# Row 0: the corner caption, then one compact badge per DEFENDER.
	var corner := Label.new()
	corner.name = CORNER_NAME
	corner.text = "ATK \\ DEF"
	corner.custom_minimum_size = Vector2(HEADER_COL_W, CELL_H)
	corner.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	corner.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	corner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chart_grid.add_child(corner)

	for defender in element_list:
		var head := ElementVisuals.make_badge(defender, MenuTheme.FONT_CAPTION, COL_BADGE_CAP)
		head.name = COL_HEADER_PREFIX + String(defender)
		head.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		chart_grid.add_child(head)

	# One row per ATTACKER: its badge, then its multiplier against every defender.
	for attacker in element_list:
		var row_head := ElementVisuals.make_badge(attacker, MenuTheme.FONT_CAPTION, ROW_BADGE_CAP)
		row_head.name = ROW_HEADER_PREFIX + String(attacker)
		# SHRINK_END, and no minimum of its own: the corner label already claims
		# HEADER_COL_W for column 0, so the pill hugs its text against the cells.
		row_head.size_flags_horizontal = Control.SIZE_SHRINK_END
		chart_grid.add_child(row_head)

		for defender in element_list:
			chart_grid.add_child(_build_cell(attacker, defender))


func _build_cell(attacker: StringName, defender: StringName) -> Label:
	var mult: float = ElementChart.multiplier(attacker, defender)
	var color: Color = cell_color(mult)

	var cell := Label.new()
	cell.name = "%s%s_%s" % [CELL_PREFIX, attacker, defender]
	cell.text = cell_text(mult)
	# Fixed cell box: the Label is NOT clipped, so its minimum width is its own text --
	# a bare text minimum would let every column be a different width and would draw a
	# blank neutral cell at 0px. The explicit minimum is what makes it a grid.
	cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
	cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	cell.add_theme_color_override("font_color", color)
	cell.tooltip_text = cell_tooltip(attacker, defender, mult)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS  # an IGNORE control shows no tooltip

	if cell.text != "":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(color.r, color.g, color.b, 0.18)
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = Color(color.r, color.g, color.b, 0.55)
		cell.add_theme_stylebox_override("normal", sb)

	return cell


# --- The per-element cards --------------------------------------------------

func _build_cards_column(element_list: Array[StringName]) -> Control:
	var col := VBoxContainer.new()
	col.name = "CardsColumn"
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	col.add_child(_section_header("By element"))

	var caption := Label.new()
	caption.name = "CardsCaption"
	caption.text = "Both directions, read straight off the chart."
	caption.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	caption.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(caption)

	var scroll := ScrollContainer.new()
	scroll.name = CARDS_SCROLL_NAME
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)  # see the note in _build_chart_column
	col.add_child(scroll)

	cards_box = VBoxContainer.new()
	cards_box.name = CARDS_NAME
	cards_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 8)
	scroll.add_child(cards_box)

	for element in element_list:
		cards_box.add_child(_build_element_card(element))

	return col


func _build_element_card(element: StringName) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = CARD_PREFIX + String(element)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The shared left-accented card look, striped in the element's own hue.
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(ElementVisuals.color_for(element)))

	var box := VBoxContainer.new()
	box.name = "Body"
	box.add_theme_constant_override("separation", 5)
	card.add_child(box)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 8)
	box.add_child(title_row)
	title_row.add_child(_badge(element, MenuTheme.FONT_BODY, ElementVisuals.BADGE_MAX_WIDTH * 2.0))

	var self_text: String = self_resist_text(element)
	if self_text != "":
		var self_label := Label.new()
		self_label.name = CARD_SELF_RESIST
		self_label.text = self_text
		self_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		self_label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		box.add_child(self_label)

	var strong: Array[StringName] = strong_against(element)
	if not strong.is_empty():
		box.add_child(_badge_row(CARD_STRONG_ROW, "Strong against:", strong))

	var weak: Array[StringName] = weak_to(element)
	if not weak.is_empty():
		box.add_child(_badge_row(CARD_WEAK_ROW, "Weak to:", weak))

	if has_no_matchups(element):
		var none_label := Label.new()
		none_label.name = CARD_NO_MATCHUPS
		none_label.text = NO_MATCHUPS_TEXT
		none_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		none_label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		none_label.tooltip_text = \
				"The chart authors no pairing for this element yet, in either direction."
		box.add_child(none_label)

	return card


## A caption plus the badges it names, wrapping when the list is long. HFlowContainer
## and not HBoxContainer: an element with six matchups must wrap onto a second line
## rather than push the card past the column.
func _badge_row(row_name: String, caption: String, element_list: Array[StringName]) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = row_name
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 4)

	var label := Label.new()
	label.name = "Caption"
	label.text = caption
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	label.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	for element in element_list:
		row.add_child(_badge(element, MenuTheme.FONT_CAPTION, ElementVisuals.BADGE_MAX_WIDTH))

	return row


## An element badge with a UNIQUE node name. Every badge [ElementVisuals] builds is
## called "ElementBadge"; several in one row are silently renamed by the engine and
## become unfindable, so the element id is suffixed on. SHRINK_BEGIN because a flow
## row packs from the left and the default SHRINK_END fights it.
func _badge(element: StringName, font_size: int, cap: float) -> PanelContainer:
	var badge := ElementVisuals.make_badge(element, font_size, cap)
	badge.name = BADGE_PREFIX + String(element)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return badge


func _section_header(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
	return label


# ===========================================================================
# Navigation
# ===========================================================================

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")
