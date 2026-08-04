extends Control

class_name UnitInfoPanel

## The COMPACT BATTLE CARD for the selected (or hovered) unit -- the left column's
## persistent "what is true about this unit right now" readout.
##
## WHAT IT IS, AND WHAT IT DELIBERATELY IS NOT.
##
## This card used to be a whole unit sheet: portrait, six stat rows, a scrolling ability
## list and a scrolling status list, all inside a 260px column. Three things were wrong
## with that at once, and all three were reported:
##
##   1. the Abilities section was ALWAYS cut off -- it was the flexible region, and the
##      column never had room for it;
##   2. the same stats were duplicated in the right sidebar's "Unit Summary" dropdown, so
##      the player had two disagreeing places to read the same numbers; and
##   3. it showed far too much at a glance for something that is on screen the entire time
##      the player is aiming at the map.
##
## So the card was cut down to exactly the BATTLE-RELEVANT facts -- the ones you need
## while looking at the board -- and everything general moved to [UnitDetailPage], a
## dedicated full-screen page opened from the DETAILS chip (or the D key).
##
## THE CARD IS, IN ORDER, AND NOTHING ELSE:
##   * a small portrait thumb, the unit's name and its class line;
##   * an HP bar with the numbers on it;
##   * ONE row of four stat chips -- ATK / DEF / SPD / MOV -- showing EFFECTIVE values,
##     tinted and arrowed when they are off base (see [method _build_stat_chip]);
##   * the status strip: one compact chip per active condition, wrapping to at most two
##     rows, with a "+N" overflow marker. Each chip NAMES its status, its severity and its
##     remaining turns, and ELABORATES on hover (see [method chip_tooltip]) -- a coloured
##     pip the player has to guess at is not a readout.
##
## There is NO ability list, NO move list, NO lore, and no damage maths -- the forecast
## panel already owns that.
##
## THE HEIGHT IS PINNED, NOT FITTED. [constant CARD_HEIGHT] is the card's whole vertical
## claim, and the status strip is a FIXED-height clipping frame rather than a growing
## list, so no amount of content can push the card past it. That is what makes the left
## column's budget arithmetic (see [UILayoutManager]) exact instead of hopeful, and it is
## why nothing on this card can ever be "cut off" again: content that does not fit is
## COUNTED ("+2"), not clipped away silently.

# --- Nodes (see UnitInfoPanel.tscn) ------------------------------------------
@onready var unit_name_label: Label = $MarginContainer/VBoxContainer/PortraitContainer/BasicInfoContainer/UnitNameLabel
@onready var unit_type_label: Label = $MarginContainer/VBoxContainer/PortraitContainer/BasicInfoContainer/UnitTypeLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/HealthRow/HealthLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthBar
## Element-coloured monogram plate: a rounded panel filled with the unit's element colour,
## holding its initial, with the real captured portrait stacked over it when there is one.
@onready var unit_portrait: PanelContainer = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait
@onready var portrait_monogram: Label = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait/Monogram

var current_unit: Unit = null

# --- Geometry ----------------------------------------------------------------

## The card's WHOLE vertical claim, pinned rather than measured. Everything on the card
## has a fixed height, so this is the sum of them (see the arithmetic in
## [method fixed_content_height]) and the left column can budget against it exactly.
const CARD_HEIGHT: float = 228.0

## The MarginContainer's 10px top + 10px bottom margins.
const CHROME_HEIGHT: float = 20.0

## Widest any row inside the card may DEMAND: the 260px left column
## (UILayoutManager.LEFT_COLUMN_WIDTH) minus the MarginContainer's 10px each side.
const CONTENT_WIDTH: float = 240.0

## Floor width an autowrapping label is measured at, so its reported minimum HEIGHT is a
## stable line count rather than whatever narrow width it last saw. Leaves room for the
## 48px portrait plate + the 8px row separation inside CONTENT_WIDTH.
const WRAP_MIN_WIDTH: float = 160.0

## Same, for labels inside a chip: CONTENT_WIDTH minus the chip's content margins.
const CHIP_WRAP_WIDTH: float = 200.0

## Vertical space reserved at the BOTTOM of the window that this (top-anchored) card must
## never grow into. The bottom-left corner is owned by the floating [TerrainInfoPanel]: a
## 16px margin + a terrain card capped at TerrainInfoPanel.MAX_HEIGHT (152px) + an 8px
## breathing gap.
const BOTTOM_RESERVE: float = 176.0

## The four stat chips' row height, and the height of one status-chip row.
const STAT_ROW_HEIGHT: float = 22.0
const STATUS_ROW_HEIGHT: float = 20.0

## The status strip is exactly TWO rows tall, always -- reserved whether or not the unit
## has any statuses, so the card does not resize under the player as conditions land and
## expire (a card that grows mid-turn moves the battle log above it).
const STATUS_STRIP_HEIGHT: float = STATUS_ROW_HEIGHT * 2.0 + 4.0

## The DETAILS chip's height. Under the project's 44px touch floor on purpose: this is a
## secondary affordance on a compact HUD card, and the same page is reachable from the
## right sidebar's full-size DETAILS button and from the D key.
const DETAILS_BUTTON_HEIGHT: float = 30.0

## How many status chips the strip shows before the last slot becomes a "+N" overflow
## marker. Matches [constant StatusVisuals.MAX_PIPS] so the card, the hover panel and the
## world-space health bar all overflow at the same point.
const MAX_STATUS_CHIPS: int = 4

## Widest one status chip's LABEL may claim.
##
## Two chips plus their pill padding and the flow's separation have to fit one row of the
## strip: 2 * (104 + 5 + 5) + 4 == 232, inside [constant CONTENT_WIDTH] (240). That is what
## makes [constant MAX_STATUS_CHIPS] chips land in exactly the two rows the strip reserves,
## so a full strip is never silently clipped. A status whose label is longer than this is
## ellipsised at the cap -- and its tooltip still spells the whole thing out.
const CHIP_MAX_WIDTH: float = 104.0

# --- Code-built rows ----------------------------------------------------------
# Built in _ready and appended to the scene's VBox (the .tscn owns only the static rows).
# Every one of them is null in a stripped harness, and every path below no-ops on null.

## The ATK / DEF / SPD / MOV row.
var _stat_row: HBoxContainer = null
## Fixed-height clipping frame + the wrapping flow inside it. The frame is a plain
## Control: its minimum is its own custom_minimum_size, so however many chips the flow
## holds, the STRIP's claim on the card is constant.
var _status_strip: Control = null
var _status_flow: HFlowContainer = null
## The DETAILS affordance. Opens [UnitDetailPage] for the card's current unit.
var _details_button: Button = null

## The real captured portrait (game/ui/PortraitCache.gd), stacked over portrait_monogram
## inside the same PanelContainer.
var _portrait_texture_rect: TextureRect = null


func _ready() -> void:
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	GameEvents.unit_hover_started.connect(_on_unit_hover_started)
	GameEvents.unit_hover_ended.connect(_on_unit_hover_ended)
	# Death is the OTHER way the card's subject can go away; without this, current_unit
	# outlives the unit it points at (see _on_unit_eliminated).
	GameEvents.unit_eliminated.connect(_on_unit_eliminated)

	# Append the code-built rows BEFORE theming, so they pick up the amber cascade along
	# with the scene-authored ones.
	_build_stat_row()
	_build_status_strip()
	_build_details_button()
	_build_portrait_texture_rect()
	_apply_width_discipline()

	ConquestTheme.apply_to(self)

	# The card's height never changes, so claim it once here rather than re-fitting.
	custom_minimum_size.y = CARD_HEIGHT

	_hide_panel()


# --- Width discipline ---------------------------------------------------------

## Keep every row inside the card's 260px column.
##
## MEASURED FAILURE (kept as a warning): the card sat in a 260px column while its
## MarginContainer reported a 293px minimum, and a full-rect anchored child with the
## default GROW_DIRECTION_BOTH resolves an over-wide minimum by growing HALF THE EXCESS
## OFF EACH SIDE -- so the stat labels ran off the left edge of the screen and the HP bar
## ran past the card's right edge. Two rules fix it for good:
##
##   * nothing may declare a minimum wider than the column (see [method discipline_label]), and
##   * the MarginContainer grows RIGHT only, so it can never reach off-screen even if some
##     future row does demand more.
func _apply_width_discipline() -> void:
	var margin := get_node_or_null("MarginContainer") as MarginContainer
	if margin != null:
		margin.grow_horizontal = Control.GROW_DIRECTION_END

	discipline_subtree(self, WRAP_MIN_WIDTH)

	if health_bar != null and is_instance_valid(health_bar):
		health_bar.custom_minimum_size.x = 0.0
		health_bar.size_flags_horizontal = Control.SIZE_FILL


## Bound one label's contribution to its row's minimum size.
##
## A NON-wrapping Label reports its whole text width as a minimum, so a long name or a
## four-digit stat widens the row past the card. Clipping with an ellipsis drops that
## minimum to 1 and trims on screen instead.
##
## An AUTOWRAPPING Label is the opposite and much nastier: Godot reports its minimum WIDTH
## as 1 and its minimum HEIGHT for whatever width it was last laid out at. A label that was
## ever ~20px wide therefore reports a THIRTEEN-line minimum height from then on. Pinning a
## floor width pins the line count with it.
##
## Still static, and still used by [TerrainInfoPanel] -- the two left-column cards share
## one width contract.
static func discipline_label(label: Label, wrap_width: float) -> void:
	if label == null or not is_instance_valid(label):
		return
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.custom_minimum_size.x = 0.0
	else:
		var w: float = minf(wrap_width, CONTENT_WIDTH)
		label.custom_minimum_size.x = w
		label.size.x = maxf(label.size.x, w)
		# Force a re-shape AT that width. A Label shapes its lines lazily and only when
		# something marks them dirty; a CODE-BUILT label is first shaped at width 0, where
		# it wraps to one character per line, and setting custom_minimum_size afterwards
		# invalidates the Control's cached minimum but NOT the Label's line cache.
		# Round-tripping the text is what marks the lines dirty.
		var text: String = label.text
		if text != "":
			label.text = ""
			label.text = text


## Give [param label] a minimum WIDTH equal to the text it actually has to draw, capped at
## [param cap]. Returns the width claimed.
##
## MEASURED FAILURE, and the only reason this exists. [method discipline_label] clips a
## non-wrapping label so a long name cannot widen the card -- and a clipped Label (or ANY
## Label whose `text_overrun_behavior` is not NO_TRIMMING) reports a minimum WIDTH of 1px.
## That is Godot's documented contract, not a bug, and inside a BoxContainer it is exactly
## what we want: the row has a width already and the label just trims into it.
##
## Inside an [HFlowContainer] it is a disaster: a flow lays every child out at ITS OWN
## minimum, so each status chip was drawn 11px wide with its label trimmed away to nothing.
## On screen that is a small coloured DOT per status -- which is precisely what was
## reported ("a small green dot for poison, but it doesn't elaborate"). The old suites read
## `ChipLabel.text`, i.e. the string the chip was HANDED, so none of them ever saw it.
##
## So a chip label states its width explicitly. `custom_minimum_size` wins over the
## reported minimum, which keeps the ellipsis available for the over-long case while still
## reserving room for the ordinary one.
static func fit_chip_label(label: Label, cap: float = CHIP_MAX_WIDTH) -> float:
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


## Apply [method discipline_label] to every Label under [param node]. Static so the chip
## builders can call it on a freshly built chip, which is the only way rows created at
## runtime get the same treatment as the scene-authored ones.
static func discipline_subtree(node: Node, wrap_width: float) -> void:
	for child in node.get_children():
		if child is Label:
			discipline_label(child, wrap_width)
		discipline_subtree(child, wrap_width)


# --- The budget contract ------------------------------------------------------

## The height this card claims from the left column. FIXED, by construction: every row on
## the card has a pinned height, so the column can budget against a constant instead of
## re-measuring a card whose content changes every time a status lands.
##
##   10  MarginContainer top margin
##   48  portrait row (48px plate; name + class line sit beside it)
##    6  separation
##   18  HP numbers row
##    6  separation
##   10  HP bar
##    6  separation
##   22  the four stat chips
##    6  separation
##   44  status strip (two 20px rows + 4px between them)
##    6  separation
##   31  DETAILS chip (30px claim, 31px once the theme's button padding is applied)
##   10  MarginContainer bottom margin
##  ---
##  223 measured (integration/test_battle_hud_layout.gd prints it), pinned at
##  CARD_HEIGHT (228) so there is font-metric slack on other platforms.
##
## The `maxf` is a backstop, not the normal path: if a platform's font metrics ever made
## the real content taller than the pin, the card reports the truth rather than lying to
## the column and overlapping the terrain card.
func fixed_content_height() -> float:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return CARD_HEIGHT
	return maxf(CARD_HEIGHT, vb.get_combined_minimum_size().y + CHROME_HEIGHT)


## Tallest this top-anchored card may be, given a window [param viewport_height], a top
## edge at [param top_y], and the card's own irreducible [param floor_h].
##
## Pure arithmetic so the 720p budget can be pinned by a test. Never returns less than
## [param floor_h]: a budget that cannot hold the card's fixed rows is not a budget, it is
## a squeeze -- and a BoxContainer handed less than its minimum distributes NEGATIVE space,
## which is what once stacked the portrait plate on top of the stat rows.
static func height_budget(viewport_height: float, top_y: float, floor_h: float) -> float:
	return maxf(floor_h, viewport_height - top_y - BOTTOM_RESERVE)


## Re-assert the card's pinned height. Called by [UILayoutManager] when the battle log
## above this card changes row height. The card no longer FITS to its content -- there is
## nothing elastic left on it -- so this is idempotent by construction.
func refit() -> void:
	custom_minimum_size.y = fixed_content_height()
	size.y = custom_minimum_size.y


# --- Selection / hover --------------------------------------------------------

func _on_unit_selected(unit: Unit, _position: Vector3) -> void:
	current_unit = unit
	_update_unit_info(unit)
	_show_panel()


func _on_unit_deselected(unit: Unit) -> void:
	if current_unit == unit:
		current_unit = null
		_hide_panel()


func _on_unit_eliminated(unit: Unit, _eliminator: Unit) -> void:
	"""A unit died: drop it as the card's subject.

	current_unit was only ever cleared on an explicit deselect, so killing the selected
	unit left this holding a reference that is freed a frame later -- and because
	_on_unit_hover_started gates on `if not current_unit` (true for a freed instance),
	that also permanently suppressed hover info for the rest of the match."""
	if unit != null and unit == current_unit:
		current_unit = null
		_hide_panel()


func _on_unit_hover_started(unit: Unit) -> void:
	# is_instance_valid, not truthiness: a freed current_unit is still "truthy".
	if not is_instance_valid(current_unit):
		current_unit = null
	if not current_unit:  # hover only fills the card when nothing is selected
		_update_unit_info(unit)
		_show_panel()


func _on_unit_hover_ended(_unit: Unit) -> void:
	if not current_unit:
		_hide_panel()


# --- Population ---------------------------------------------------------------

func _update_unit_info(unit: Unit) -> void:
	"""Repaint every row of the card for [param unit]."""
	# is_instance_valid, not truthiness: reached from selection / hover with a unit that
	# may already be freed, and every line below dereferences it.
	if not is_instance_valid(unit):
		return

	if unit_name_label:
		unit_name_label.text = unit.get_display_name()

	if unit_type_label:
		# The CLASS line: the humanized character id, plus the owning player -- who a unit
		# belongs to is battle-relevant (this card also shows inspected ENEMIES), and it
		# used to be crammed into the name label where a long name clipped it away.
		var parts: PackedStringArray = []
		var unit_type: String = unit.get_unit_type()
		parts.append(UnitPageContent.humanize_id(unit_type) if unit_type != "" else "Unknown")
		var owner_player = unit.get_owner_player()
		if owner_player != null:
			parts.append(String(owner_player.get_display_name()))
		unit_type_label.text = " · ".join(parts)

	if health_label:
		health_label.text = "%d/%d" % [unit.current_health, unit.max_health]
	if health_bar:
		health_bar.max_value = maxf(1.0, float(unit.max_health))
		health_bar.value = clampf(float(unit.current_health), 0.0, health_bar.max_value)

	_update_stat_chips(unit)
	_update_status_strip(unit)
	_update_portrait(unit)


# --- The four stat chips -------------------------------------------------------

func _build_stat_row() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return
	_stat_row = HBoxContainer.new()
	_stat_row.name = "StatChips"
	_stat_row.add_theme_constant_override("separation", 4)
	_stat_row.custom_minimum_size.y = STAT_ROW_HEIGHT
	_stat_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_stat_row)


## The four chips a player actually reads mid-battle. Damage maths lives in the combat
## forecast; the full nine-stat table lives on [UnitDetailPage]. These four are the ones
## that change what you can DO this turn.
const STAT_CHIPS: Array = [
	["ATK", "attack"],
	["DEF", "defense"],
	["SPD", "speed"],
	["MOV", "movement"],
]


func _update_stat_chips(unit) -> void:
	if _stat_row == null or not is_instance_valid(_stat_row):
		return
	for child in _stat_row.get_children():
		_stat_row.remove_child(child)
		child.queue_free()
	for spec in STAT_CHIPS:
		_stat_row.add_child(_build_stat_chip(unit, String(spec[0]), String(spec[1])))


## One stat chip, showing the EFFECTIVE value.
##
## The value and the "is it modified" verdict both come from
## [method MoveStatVisuals.stat_info] -- i.e. the unit's own `get_stat` / `get_base_stat`
## pair, the same one gameplay reads. That is the whole point: the card must never
## re-derive "what the bonus probably is", because a panel that guesses is a panel that
## advertises a number the player then cannot use. Decoration follows the shared
## vocabulary too: green ▲ up, red ▼ down, undecorated when the value is at base.
func _build_stat_chip(unit, label: String, stat_name: String) -> PanelContainer:
	var info: Dictionary = MoveStatVisuals.stat_info(unit, stat_name, label)
	var base: int = int(info.get("base", 0))
	var effective: int = int(info.get("effective", 0))
	var modified: bool = bool(info.get("modified", false))
	var color: Color = MoveStatVisuals.delta_color(base, effective, ConquestTheme.CREAM)

	var chip := PanelContainer.new()
	chip.name = "StatChip" + label
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = MoveStatVisuals.stat_text(label, base, effective)

	var sb := StyleBoxFlat.new()
	# A modified chip is FILLED with its delta colour (dimmed); an unmodified one keeps the
	# neutral plate, so "something changed here" reads before any glyph is legible.
	sb.bg_color = color.darkened(0.62) if modified else ConquestTheme.PLATE_BG
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = color if modified else ConquestTheme.BROWN
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)

	var text := Label.new()
	text.name = "Value"
	var arrow: String = ""
	if modified:
		arrow = MoveStatVisuals.UP_ARROW if effective > base else MoveStatVisuals.DOWN_ARROW
	text.text = "%s %d%s" % [label, effective, arrow]
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	text.add_theme_color_override("font_color", color)
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	chip.add_child(text)

	return chip


# --- The status strip ----------------------------------------------------------

func _build_status_strip() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return

	# A plain Control, so its minimum is exactly custom_minimum_size and the wrapping flow
	# inside cannot grow the card. clip_contents is the belt to that braces: even a freak
	# third row is trimmed at the strip's edge rather than pushing the DETAILS chip off.
	_status_strip = Control.new()
	_status_strip.name = "StatusStrip"
	_status_strip.custom_minimum_size = Vector2(0, STATUS_STRIP_HEIGHT)
	_status_strip.clip_contents = true
	_status_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# IGNORE on the frame and the flow, PASS on the chips: a Control with IGNORE is skipped
	# as a hit-test CANDIDATE but its children are still traversed, so the chips underneath
	# these two are reachable for their tooltips while neither of the wrappers can swallow
	# a click meant for the card.
	_status_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_status_strip)

	_status_flow = HFlowContainer.new()
	_status_flow.name = "StatusFlow"
	_status_flow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_status_flow.add_theme_constant_override("h_separation", 4)
	_status_flow.add_theme_constant_override("v_separation", 4)
	_status_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_strip.add_child(_status_flow)


func _update_status_strip(unit) -> void:
	if _status_flow == null or not is_instance_valid(_status_flow):
		return

	# remove_child BEFORE queue_free: a queued-but-still-parented chip would keep
	# contributing to the flow's layout for the rest of the frame.
	for child in _status_flow.get_children():
		_status_flow.remove_child(child)
		child.queue_free()

	# Grouped by id, exactly like the world-space health-bar pips and the hover card:
	# three live Poisoned instances are ONE status at severity 3, not three chips that eat
	# the whole strip and hide everything else behind the overflow marker.
	var groups: Array = StatusVisuals.group_by_id(StatusVisuals.active_conditions(unit))
	var total: int = groups.size()

	if total == 0:
		var none_label := Label.new()
		none_label.name = "NoStatuses"
		none_label.text = "No active effects"
		none_label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
		none_label.clip_text = true
		none_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		# NOT discipline_label: this label is inside the flow, where a 1px minimum means it
		# is drawn as nothing at all (see fit_chip_label).
		fit_chip_label(none_label, CHIP_WRAP_WIDTH)
		_status_flow.add_child(none_label)
		return

	var shown: int = StatusVisuals.shown_count(total, MAX_STATUS_CHIPS)
	var hidden: int = StatusVisuals.hidden_count(total, MAX_STATUS_CHIPS)

	for i in range(shown):
		var group: Dictionary = groups[i]
		var condition = group.get("condition", null)
		if condition == null:
			continue
		var info: Dictionary = StatusVisuals.info_for(condition)
		var count: int = int(group.get("count", 1))
		var turns: int = int(group.get("turns_left", StatusVisuals.TURNS_FROM_CONDITION))
		_status_flow.add_child(_build_status_chip(
				compact_status_text(condition, count, turns),
				info.get("color", ConquestTheme.AMBER),
				chip_tooltip(condition, count, turns)))

	if hidden > 0:
		_status_flow.add_child(_build_status_chip(
				StatusVisuals.overflow_label(hidden), StatusVisuals.OVERFLOW_COLOR,
				overflow_tooltip(groups, shown)))


## "2t" / "1t" / "∞" -- the compact turn count this card uses.
##
## The card has ~240px for up to four chips, so [method StatusVisuals.turns_label]'s
## "2 turns" does not fit; this is the same NUMBER in the smallest honest form. The
## permanent sentinel (< 0) becomes the infinity glyph rather than a negative count.
static func compact_turns(turns_left: int) -> String:
	if turns_left < 0:
		return "∞"
	return "%dt" % turns_left


## "◆ Poisoned x3 · 2t" -- the card's chip label.
##
## Deliberately the same GRAMMAR as [method StatusVisuals.chip_text] (glyph, name, stack
## suffix, separator, duration) with only the duration compacted, so a chip on this card
## and the same status on the hover panel or the detail page read as one vocabulary.
static func compact_status_text(condition, count: int = 1,
		turns_left: int = StatusVisuals.TURNS_FROM_CONDITION) -> String:
	var info: Dictionary = StatusVisuals.info_for(condition)
	var turns: int = StatusVisuals.turns_left_of(condition) if turns_left == StatusVisuals.TURNS_FROM_CONDITION else turns_left
	return "%s %s%s · %s" % [
		StatusVisuals.glyph_for(condition),
		String(info.get("name", "Status")),
		StatusVisuals.stack_suffix(count),
		compact_turns(turns),
	]


## What a chip says when the player HOVERS it: the one-line label, then a plain-English
## sentence for what the status is doing to the unit.
##
## This is the "elaborate" half of the chip. The strip has ~104px per chip, which is enough
## to NAME a status and time it and no more -- so the explanation lives here, one hover
## away, and the full page (with the same sentence on a status card) stays one click away
## for everything else.
static func chip_tooltip(condition, count: int = 1,
		turns_left: int = StatusVisuals.TURNS_FROM_CONDITION) -> String:
	var head: String = StatusVisuals.chip_text(condition, count, turns_left)
	var detail: String = StatusVisuals.describe_condition(condition)
	if detail == "":
		return head
	return "%s\n%s" % [head, detail]


## What the "+N" marker says on hover: the statuses it is standing in for, named. The
## overflow marker COUNTS what did not fit; this is how the player finds out what that was
## without opening the page.
static func overflow_tooltip(groups: Array, shown: int) -> String:
	var lines: PackedStringArray = []
	for i in range(shown, groups.size()):
		var group: Dictionary = groups[i]
		var condition = group.get("condition", null)
		if condition == null:
			continue
		lines.append(StatusVisuals.chip_text(
				condition,
				int(group.get("count", 1)),
				int(group.get("turns_left", StatusVisuals.TURNS_FROM_CONDITION))))
	return "\n".join(lines)


## A compact colour-coded pill: dim fill, 1px frame in the status colour, cream text.
## Same recipe as the hover card's chips, so the two surfaces read identically.
##
## [param tooltip] defaults to the chip's own text, so a caller with nothing more to say
## still gets a legible hover.
func _build_status_chip(text: String, color: Color, tooltip: String = "") -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "StatusChip"
	# PASS, not IGNORE: an IGNORE control is skipped by the hit test, and a control the hit
	# test never returns can never show a tooltip. PASS lets the hover land here while the
	# click still travels on to the card underneath.
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = tooltip if tooltip != "" else text

	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.set_corner_radius_all(5)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	chip.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.name = "ChipLabel"
	label.text = text
	label.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	# CREAM reads on the dim chip fill; the theme's default INK is tuned for the light
	# amber panel background instead.
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# ...and therefore a reported minimum width of 1px, which inside the strip's flow means
	# "draw me as a dot". State the width the text needs, capped so the strip still holds
	# MAX_STATUS_CHIPS chips in its two rows. See fit_chip_label.
	fit_chip_label(label)
	chip.add_child(label)

	return chip


# --- The DETAILS affordance -----------------------------------------------------

func _build_details_button() -> void:
	var vb := get_node_or_null("MarginContainer/VBoxContainer") as VBoxContainer
	if vb == null:
		return
	_details_button = Button.new()
	_details_button.name = "DetailsButton"
	_details_button.text = "DETAILS (D)"
	_details_button.tooltip_text = "Full stats, moves, abilities and statuses (D)"
	_details_button.custom_minimum_size.y = DETAILS_BUTTON_HEIGHT
	_details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_button.focus_mode = Control.FOCUS_NONE
	_details_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_details_button.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
	_details_button.set_meta("style_role", "secondary")
	_details_button.pressed.connect(open_details)
	vb.add_child(_details_button)


## Open [UnitDetailPage] on whatever unit the card is showing. Public so the D hotkey (in
## [UnitActionsPanel]) and the right sidebar's DETAILS entry route through ONE opener --
## there is exactly one detail page per battle, and this is how it is asked for.
func open_details() -> void:
	if not is_instance_valid(current_unit):
		return
	UnitDetailPage.open_for(self, current_unit)


# --- Portrait -------------------------------------------------------------------

func _build_portrait_texture_rect() -> void:
	if unit_portrait == null:
		return
	_portrait_texture_rect = TextureRect.new()
	_portrait_texture_rect.name = "PortraitTexture"
	_portrait_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE, and it must STAY that way. A TextureRect's default
	# EXPAND_KEEP_SIZE reports the TEXTURE's size as its minimum, and PortraitCache
	# captures at 256x256 -- so the moment a real portrait resolved, this 48x48 plate
	# demanded 256x256 and blew the whole left column apart (the MarginContainer
	# overflowed both side edges and the inner VBox was handed less than its minimum, so
	# it stacked the portrait on the stat rows). Never reintroduce the default.
	_portrait_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_texture_rect.visible = false
	unit_portrait.add_child(_portrait_texture_rect)


func _update_portrait(unit: Unit) -> void:
	"""Paint the monogram plate: the unit's initial on its element colour.

	A compact element-coded stand-in for real portrait art, and the fallback shown until
	(or whenever) PortraitCache has no real capture for this unit's character."""
	if not unit_portrait:
		return

	var element: String = String(unit.get_element()) if unit.has_method("get_element") else ""
	var base: Color = ConquestTheme.element_color(element)

	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = base.darkened(0.35)
	unit_portrait.add_theme_stylebox_override("panel", sb)

	if portrait_monogram:
		var display: String = unit.get_display_name().strip_edges()
		portrait_monogram.text = display.substr(0, 1).to_upper() if display != "" else "?"
		var text_color: Color = ConquestTheme.INK if base.get_luminance() > 0.55 else ConquestTheme.CREAM
		portrait_monogram.add_theme_color_override("font_color", text_color)

	_refresh_portrait_texture(unit)


## Show the real captured portrait for [param unit]'s character if PortraitCache already
## has it cached, and either way (re)issue a request so a not-yet-captured character swaps
## the monogram out the moment its portrait resolves. Never blocks.
func _refresh_portrait_texture(unit: Unit) -> void:
	if _portrait_texture_rect == null:
		return

	var character_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
	if character_id.is_empty():
		_clear_portrait_texture()
		return

	var cached: Texture2D = PortraitCache.get_cached(character_id)
	if cached != null:
		_apply_portrait_texture(cached)
		return

	_clear_portrait_texture()
	PortraitCache.get_portrait(character_id, _on_portrait_resolved.bind(unit, character_id))


func _apply_portrait_texture(tex: Texture2D) -> void:
	if _portrait_texture_rect == null:
		return
	_portrait_texture_rect.texture = tex
	_portrait_texture_rect.visible = true
	if portrait_monogram:
		portrait_monogram.visible = false


func _clear_portrait_texture() -> void:
	if _portrait_texture_rect != null:
		_portrait_texture_rect.visible = false
	if portrait_monogram:
		portrait_monogram.visible = true


## PortraitCache resolution callback. [param unit] / [param character_id] are the unit and
## character this request was made FOR, bound at request time -- a slow capture must never
## clobber the card once the player has selected someone else.
func _on_portrait_resolved(tex: Texture2D, unit: Unit, character_id: String) -> void:
	if tex == null:
		return
	if not is_instance_valid(unit) or current_unit != unit:
		return
	var live_id: String = unit.get_unit_type() if unit.has_method("get_unit_type") else ""
	if live_id != character_id:
		return
	_apply_portrait_texture(tex)


# --- Visibility -----------------------------------------------------------------

func _show_panel() -> void:
	visible = true
	modulate.a = 1.0


func _hide_panel() -> void:
	visible = false


# Public interface
func get_current_unit() -> Unit:
	return current_unit


func is_showing_unit(unit: Unit) -> bool:
	return current_unit == unit
