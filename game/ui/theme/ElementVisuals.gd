extends RefCounted
class_name ElementVisuals

## Single source of truth for how an ELEMENT reads in the UI: its colour, its display
## name, the badge chip that carries both, and the words a TYPE MATCHUP is announced in.
##
## Deliberately shaped like [StatusVisuals] and [MoveStatVisuals] -- all statics, no
## state, every entry point null-safe and duck-typed -- so the three vocabularies behave
## identically and the surfaces that use them cannot drift apart.
##
## THE COLOUR IS NOT DEFINED HERE. [method color_for] forwards to
## [method ConquestTheme.element_color], which the move rows already colour their element
## stripes with ([MoveSelectionPanel], [UnitActionMenu]), the forecast card paints its
## accent stripe with, and the portrait plates on [UnitInfoPanel] / [UnitDetailPage] fill
## themselves with. There is exactly ONE element palette in this project and this file
## does not add a second one -- it only adds the WIDGET that carries it, so a unit's type
## badge and its moves' stripes are the same hue by construction rather than by review.
##
## THE MATCHUP WORDS. A forecast reads its multiplier out of the preview dictionary
## ([code]element_mult[/code] / [code]element_label[/code]); this file turns that pair into
## the line the player sees. NEUTRAL RENDERS AS NOTHING -- [method effectiveness_text]
## returns "" for a 1.0 matchup, so the common case costs no line on a 720p card and the
## presence of the row is itself the signal.

# --- The matchup vocabulary ----------------------------------------------------
# Matches the labels ElementChart.label_for() is contracted to return, so a preview that
# carries `element_label` and one that does not (we derive it) produce the same words.

const STRONG: StringName = &"strong"
const RESISTED: StringName = &"resisted"
const NEUTRAL: StringName = &"neutral"

## A matchup within this much of 1.0 is neutral. Multipliers are products of floats
## (effectiveness x tile amplifier x own-tile benefit), so an exact == 1.0 test would
## print "Strong x1" on rounding noise.
const NEUTRAL_EPSILON: float = 0.005

## Widest an element badge's LABEL may claim by default. One element name at
## [constant ConquestTheme.FONT_CAPTION] ("Nature", "Arcane") measures ~40px; the cap is
## headroom for a long authored id, not the expected width.
const BADGE_MAX_WIDTH: float = 72.0

## The badge's node names. Stated as constants because every caller (and every test)
## looks the badge up by name on a rendered tree.
const BADGE_NAME := "ElementBadge"
const BADGE_LABEL_NAME := "ElementBadgeLabel"


# --- Reading an element --------------------------------------------------------

## Duck-typed element of [param unit]: a live [Unit] answers [code]get_element()[/code]
## (which reads its backing [CharacterResource]); a mock may expose a plain
## [code]element[/code] property; anything else is &"" (no element, therefore no badge).
##
## Mirrors [method ElementChart.element_of] on purpose -- the UI must ask the same
## question combat does -- but is implemented here so a UI test needs no combat fixture.
static func of_unit(unit) -> StringName:
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		return &""
	if unit.has_method("get_element"):
		return StringName(unit.get_element())
	var e = unit.get("element")
	return StringName(e) if e != null else &""


## The element a MOVE carries ([member MoveResource.element]), or &"".
static func of_move(move) -> StringName:
	if move == null or typeof(move) != TYPE_OBJECT:
		return &""
	var e = move.get("element")
	return StringName(e) if e != null else &""


## The palette colour for [param element]. Forwards to [ConquestTheme] -- see the class
## note: this file never defines an element hue of its own.
static func color_for(element) -> Color:
	return ConquestTheme.element_color(String(element))


## "Nature" / "Deep Water" / "" -- the element's display name. EMPTY for an unelemented
## subject, which is how every caller decides not to draw a badge at all: a chip reading
## "Neutral" on two thirds of the roster is furniture, not information.
static func label_for(element) -> String:
	var raw: String = String(element).strip_edges()
	if raw == "":
		return ""
	return raw.capitalize()


# --- The matchup line ----------------------------------------------------------

## &"strong" / &"resisted" / &"neutral" for [param mult].
##
## The same mapping [method ElementChart.label_for] is contracted to make. Derived here
## rather than delegated so this file can format a preview that carries only the NUMBER,
## and so a UI test needs no combat class at all. When a preview supplies its own
## `element_label`, callers prefer that -- this is the fallback, not a second opinion.
static func label_for_multiplier(mult: float) -> StringName:
	if mult > 1.0 + NEUTRAL_EPSILON:
		return STRONG
	if mult < 1.0 - NEUTRAL_EPSILON:
		return RESISTED
	return NEUTRAL


## "Strong" / "Resisted" / "" -- the word a matchup label is announced with.
static func effectiveness_word(label) -> String:
	match StringName(label):
		STRONG:
			return "Strong"
		RESISTED:
			return "Resisted"
		_:
			return ""


## "1.25" / "0.75" / "1.5" -- the multiplier with no trailing-zero noise. Two decimals is
## the authored precision (RESISTED is 0.75), and a x1.50 that prints as "1.5" reads as a
## number rather than as a currency amount.
static func format_multiplier(mult: float) -> String:
	var s: String = "%.2f" % mult
	if s.contains("."):
		while s.ends_with("0"):
			s = s.substr(0, s.length() - 1)
		if s.ends_with("."):
			s = s.substr(0, s.length() - 1)
	return s


## "Strong x1.25" / "Resisted x0.75" / "" -- the forecast's effectiveness line.
##
## EMPTY ON NEUTRAL, which is the whole design of this row: the overwhelmingly common
## matchup is 1.0, and a card that prints "Neutral x1" on every aim has spent a line of a
## 720p budget saying nothing. The row is hidden instead, so its APPEARANCE is the signal.
##
## [param label] wins over the number when it is one of the two decided labels, so a
## preview that has already made the call (including a chart rule we do not know about)
## is rendered as it decided; an unknown/absent label falls back to the arithmetic.
static func effectiveness_text(mult: float, label = null) -> String:
	var verdict: StringName = StringName(label) if label != null else label_for_multiplier(mult)
	if verdict != STRONG and verdict != RESISTED:
		verdict = label_for_multiplier(mult)
	var word: String = effectiveness_word(verdict)
	if word == "":
		return ""
	return "%s ×%s" % [word, format_multiplier(mult)]


## Green for a matchup in the player's favour, red against -- the SAME buff/debuff pair
## [MoveStatVisuals] tints a boosted stat with, so "green means better for me" is one
## rule across the HUD and neither colour can be mistaken for an element hue.
static func effectiveness_color(label, neutral: Color = ConquestTheme.CREAM) -> Color:
	match StringName(label):
		STRONG:
			return MoveStatVisuals.BUFF_COLOR
		RESISTED:
			return MoveStatVisuals.NERF_COLOR
		_:
			return neutral


# --- The ability line ----------------------------------------------------------

## "+30% (Grass Cutter)" / "-20% (Grovebound)" / "" -- the forecast's ability line.
##
## The percentage is what an ability is doing to THIS hit, and [param notes] name the
## reason(s). EMPTY at 0%, for the same reason the neutral matchup renders as nothing:
## most hits have no ability riding on them, and a row that always shows is furniture.
## Notes are joined rather than one-per-line -- the card has a width budget, not a height
## one, and two abilities on one hit is already the rare case.
static func ability_bonus_text(percent: int, notes = null) -> String:
	if percent == 0:
		return ""
	var head: String = "%+d%%" % percent
	var reason: String = _join_notes(notes)
	if reason == "":
		return head
	return "%s (%s)" % [head, reason]


## Green when an ability is ADDING damage for the player, red when one is taking it away.
static func ability_bonus_color(percent: int, neutral: Color = ConquestTheme.CREAM) -> Color:
	if percent > 0:
		return MoveStatVisuals.BUFF_COLOR
	if percent < 0:
		return MoveStatVisuals.NERF_COLOR
	return neutral


## Flatten `ability_notes` (an Array[String] in the contract, but tolerant of a bare
## String, a null, and blank entries) into one comma-joined phrase.
static func _join_notes(notes) -> String:
	if notes == null:
		return ""
	if notes is String or notes is StringName:
		return String(notes).strip_edges()
	if not (notes is Array):
		return ""
	var parts: PackedStringArray = []
	for n in (notes as Array):
		var s: String = String(n).strip_edges()
		if s != "":
			parts.append(s)
	return ", ".join(parts)


# --- The badge widget ----------------------------------------------------------

## A compact element chip: dim fill in the element's colour, a 1px frame in it, cream
## text naming the element. The SAME recipe [UnitInfoPanel] and [UnitHoverPanel] build
## their status chips with, so a unit's element badge and its condition chips read as one
## family of pills rather than as two unrelated widgets.
##
## Built once and re-pointed with [method update_badge] rather than rebuilt per unit, so
## a caller can put it in a row at construction time and never touch the tree again.
## Starts HIDDEN (an empty element), which is also the resting state for a unit that has
## no element at all.
##
## [param v_padding] is the pill's top/bottom content margin, and it exists because it is
## the difference between "costs a row nothing" and "costs it a pixel". A badge is only
## free on a row whose existing tallest child is at least as tall as the pill, so a host
## whose row is TIGHT (the hover card's 13px HP label draws 18px; a 12px badge at the
## default padding draws 19) drops the padding to 0 and lands at 17 instead. MEASURED, in
## `integration/test_battle_element_readout.gd`, not estimated.
static func make_badge(element = &"", font_size: int = ConquestTheme.FONT_CAPTION,
		cap: float = BADGE_MAX_WIDTH, v_padding: int = 1) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.name = BADGE_NAME
	# Carried on the node so update_badge can rebuild the stylebox on every repaint
	# without every caller having to re-state it.
	badge.set_meta("badge_v_padding", v_padding)
	# PASS, not IGNORE: an IGNORE control is skipped by the hit test, and a control the
	# hit test never returns can never show a tooltip. A caller whose whole subtree must
	# be click-through (the hover card) overrides this to IGNORE itself.
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.name = BADGE_LABEL_NAME
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	badge.add_child(label)

	update_badge(badge, element, cap)
	return badge


## Point [param badge] at [param element]. HIDES the badge entirely for an empty element
## -- "no element" is not a kind of element and must not occupy a slot.
##
## Re-asserts the label's explicit minimum width every time, and that is not optional:
## the label is clipped (so a long id trims instead of widening the row), a clipped Label
## reports a minimum WIDTH of 1px, and a badge with SIZE_SHRINK_END inside an
## [HBoxContainer] is laid out at exactly its minimum. Without this the chip is drawn as
## an ~11px coloured dot -- the same failure the status chips were reported for. It is
## also re-asserted here rather than at build time because
## [method UnitInfoPanel.discipline_subtree] runs over the card AFTER construction and
## resets exactly this field.
static func update_badge(badge: PanelContainer, element, cap: float = BADGE_MAX_WIDTH) -> void:
	if badge == null or not is_instance_valid(badge):
		return
	var label := badge.get_node_or_null(BADGE_LABEL_NAME) as Label
	var text: String = label_for(element)

	if text == "":
		badge.visible = false
		if label != null:
			label.text = ""
		return

	var color: Color = color_for(element)
	badge.visible = true
	badge.tooltip_text = "Element: %s" % text

	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	var v_padding: int = int(badge.get_meta("badge_v_padding", 1))
	sb.content_margin_top = v_padding
	sb.content_margin_bottom = v_padding
	badge.add_theme_stylebox_override("panel", sb)

	if label != null:
		label.text = text
		# CREAM reads on the dim chip fill; a theme cascade's default INK is tuned for the
		# light amber panel background instead and would be near-invisible here.
		label.add_theme_color_override("font_color", ConquestTheme.CREAM)
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		fit_label(label, cap)


## Give [param label] a minimum WIDTH equal to the text it actually has to draw, capped
## at [param cap]. Returns the width claimed.
##
## The shared implementation behind [method UnitInfoPanel.fit_chip_label] -- see the long
## MEASURED FAILURE note there. Lives in this (theme-layer) file so a widget builder can
## reach it without depending on a panel.
static func fit_label(label: Label, cap: float = BADGE_MAX_WIDTH) -> float:
	if label == null or not is_instance_valid(label):
		return 0.0
	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	if font == null:
		# No font to measure with (a stripped harness): claim the cap rather than 1px, so
		# the chip is at worst too wide and never invisible.
		label.custom_minimum_size.x = cap
		return cap
	var font_size: int = label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = ThemeDB.fallback_font_size
	var needed: float = font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var claimed: float = minf(ceilf(needed), cap)
	label.custom_minimum_size.x = claimed
	return claimed
