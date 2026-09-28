extends Control

class_name TerrainInfoPanel

# Fire-Emblem-style TERRAIN / TILE INSPECTION window: a compact, non-modal
# floating overlay that shows the terrain under the board cursor -- its name,
# its ELEMENT, movement cost, how the tile matches up against the unit you have
# selected, and any active tile effects (fire, empowering water, fortify, ...).
# Updates live as the cursor moves and as the selection changes.
#
# THE TWO ELEMENT ROWS, and why they cost the card almost nothing:
#   * the element BADGE rides the name row (a ~17px caption pill beside a ~24px
#     18pt name), so it adds no height at all;
#   * the MATCHUP line is a single 13px row that is HIDDEN whenever the matchup
#     is neutral or nothing is selected -- which is the common case. When it does
#     show, the fixed rows grow by ~22px and _reflow_card() hands the difference
#     to the chip list's existing scroll rather than growing the card past
#     MAX_HEIGHT. It reports HARM ("Fire: x1.25 vs you (19 dmg)", red) and BOOST
#     ("Nature: heals x1.25 for you (13 HP)", green) on the same row -- a tile
#     that favours your unit is news too, and burying it under a chip would make
#     the element system look like a pure tax.
# Both numbers come from the combat code itself (ElementChart /
# TileEffectResource.damage_preview_for), never from arithmetic written here --
# CONQUEST.md rule 9.
#
# Code-built (no .tscn) exactly like MoveSelectionPanel / CombatForecastPanel:
# it is top_level, anchors itself over the battlefield, and calls
# ConquestTheme.apply_to(self) for the navy + gold HUD look. Like CombatForecastPanel
# it is non-modal: mouse_filter = IGNORE everywhere, so it never blocks clicks
# on the board or sibling panels.
#
# Anchored to the BOTTOM-LEFT of the viewport (with a margin) so it never
# overlaps UnitActionsPanel (right sidebar), the turn banner (top-center), or
# CombatForecastPanel (also top-center).
#
# Self-contained: this panel builds its own UI and wires its own
# GameEvents.cursor_moved handler in _ready(). Callers (see
# GameWorldManager._setup_terrain_info_panel) only need to instantiate it and
# add it to the "UI" CanvasLayer -- nothing else to wire up.

const PANEL_WIDTH := HudSafeArea.CORNER_CARD_WIDTH
const MARGIN := ConquestTheme.MARGIN

## Hard cap on the card's height. The HUD's whole left column is budgeted against this:
## UnitInfoPanel.BOTTOM_RESERVE (176) = MARGIN (16) + MAX_HEIGHT (152) + an 8px gap, and
## the unit card is never allowed to grow into that band. A tile carrying more effect
## chips than fit therefore SCROLLS the chip list instead of growing the card upward into
## the unit card (and, before the explicit offsets below, off the bottom of the screen).
const MAX_HEIGHT := 152.0

## Width the card's rows are measured at: PANEL_WIDTH minus the grove card's 18px content
## margins each side (ConquestTheme.panel_box), minus a couple of px of frame.
const CONTENT_WIDTH := PANEL_WIDTH - 40.0

## Gap between the terrain card and the floor badge beside it.
const FLOOR_BADGE_GAP := 8.0

var _card: PanelContainer
var _name_label: Label
var _move_label: Label
var _effects_header: Label
var _effects_container: VBoxContainer
## Scrolls the chip list once the card would exceed MAX_HEIGHT. The name / rule /
## move-cost / "Effects:" rows above it are fixed; this is the one elastic region.
var _effects_scroll: ScrollContainer

## The tile's ELEMENT, as the shared [ElementVisuals] pill — the same widget (and the
## same palette) a unit's own element badge is drawn with, riding on the name row so it
## costs the card no height. Hidden for terrain nobody has elemented.
var _element_badge: PanelContainer

## One compact line reading the tile's matchup against the SELECTED unit
## ("Fire: ×1.25 vs you (19 dmg)"), tinted with the HUD's buff/nerf pair. HIDDEN unless
## there is a selection AND the matchup is non-neutral — the overwhelmingly common case
## is neutral, and a row that always shows spends a line of a 152px budget saying nothing.
var _matchup_label: Label

## "Trap - springs when stepped on", shown only for a cell carrying a pass-through trap.
## TRAPS SPRING WHERE YOU STEP and glowing tiles hurt where you STAND (CONQUEST.md rule 10) —
## the chip below already names the effect, but the chip cannot say WHICH of those two things
## it is, and that is the whole difference between "walk around it" and "do not stop there".
## The wording is [constant TileEffectResource.TRAP_DESCRIPTOR], read off the resource so the
## compendium's tile gallery quotes the same sentence this card does.
var _trap_label: Label

## The unit the player currently has selected, tracked off GameEvents so the matchup line
## knows who "you" is. Never dereferenced without an is_instance_valid check: a selected
## unit can die (or the map can be torn down) while this panel still holds it.
var _selected_unit = null

# Sentinel so the very first _on_cursor_moved always does a fresh lookup.
var _current_cell: Vector3i = Vector3i(-999999, -999999, 0)

# --- Multi-floor readout -------------------------------------------------------
var _floor_label: Label
var _floor_badge: PanelContainer
var _floor_badge_label: Label
var _floor_hint_label: Label
var _floor_pips: FloorPips
var _view_floor: int = 0
var _cut_floor: int = 0
var _floor_count: int = 1


## Tiny vertical stack of floor pips for the floor badge: one bar per floor
## (bottom = ground), the view floor filled, cut-away floors hollow.
class FloorPips extends Control:
	var count: int = 1
	var view: int = 0
	var cut: int = 0
	var cursor_floor: int = 0

	func set_state(c: int, v: int, k: int, cf: int) -> void:
		count = maxi(1, c)
		view = v
		cut = k
		cursor_floor = cf
		custom_minimum_size = Vector2(18, maxf(22.0, count * 9.0))
		queue_redraw()

	func _draw() -> void:
		var h := size.y
		var bar_h := minf(7.0, (h - 2.0) / count - 2.0)
		for f in count:
			var y := h - (f + 1) * (bar_h + 2.0)
			var r := Rect2(Vector2(1, y), Vector2(size.x - 2, bar_h))
			if f == cursor_floor:
				draw_rect(r, ConquestTheme.GOLD)
				draw_rect(r, ConquestTheme.GOLD_LITE, false, 1.5)
			elif f == view:
				draw_rect(r, ConquestTheme.TEXT_DIM)
			elif f <= cut:
				draw_rect(r, ConquestTheme.BORDER)
			else:
				draw_rect(r, ConquestTheme.BORDER, false, 1.0)


func _ready() -> void:
	name = "TerrainInfoPanel"

	# Detach from whatever Container we're added under (see the long note in
	# MoveSelectionPanel._ready): top_level makes our anchors viewport-relative
	# so we float freely instead of being force-fit into a parent layout cell.
	top_level = true
	# A top_level Control IGNORES anchors, so PRESET_FULL_RECT left our size at
	# (0,0) -- the bottom-anchored card then resolved against height 0 and floated
	# to a NEGATIVE y, off-screen (the "hover shows nothing" bug). So we do NOT use
	# an anchor preset here (which would also warn about being overridden); instead
	# we size our rect to the viewport explicitly and keep it in sync on resize.
	# The card inside is a normal (non-top_level) child, so ITS bottom anchor
	# resolves correctly against this rect.
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)

	# Passive readout only -- never eat mouse input. The whole subtree is set
	# IGNORE below too, so this panel can never block a click reaching the
	# board/cursor or another panel underneath.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Draw above the base HUD layout but below modal popups (MoveSelectionPanel
	# uses z_index 100); CombatForecastPanel (top-center) uses 90 -- matching it
	# is harmless since the two never overlap on screen.
	z_as_relative = false
	z_index = 90

	_create_ui()
	visible = false

	if GameEvents and not GameEvents.cursor_moved.is_connected(_on_cursor_moved):
		GameEvents.cursor_moved.connect(_on_cursor_moved)
	# WHO "you" IS. The matchup line and the Move Cost row are both relative to the
	# selected unit (its element; its movement profile), so this panel tracks the
	# selection itself rather than reaching into UnitActionsPanel -- the two are siblings
	# on the HUD and neither should own the other's state.
	if GameEvents:
		if not GameEvents.unit_selected.is_connected(_on_unit_selected):
			GameEvents.unit_selected.connect(_on_unit_selected)
		if not GameEvents.unit_deselected.is_connected(_on_unit_deselected):
			GameEvents.unit_deselected.connect(_on_unit_deselected)
		if GameEvents.has_signal("view_floor_changed") \
				and not GameEvents.view_floor_changed.is_connected(_on_view_floor_changed):
			GameEvents.view_floor_changed.connect(_on_view_floor_changed)


## Pin our rect to the whole viewport so the bottom-left-anchored card lands on
## screen. A top_level Control ignores its parent, so it will not size itself.
func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size
	# The card's offsets are relative to THIS rect's bottom edge, so re-pin on resize.
	_reflow_card()


func _create_ui() -> void:
	# The floating card, anchored to the BOTTOM-LEFT corner of the viewport with
	# a fixed margin. grow_horizontal END / grow_vertical BEGIN means it expands
	# right-and-up from that pinned corner as content is added, mirroring the
	# top-center anchoring CombatForecastPanel uses for its own card.
	_card = PanelContainer.new()
	_card.name = "TerrainCard"
	_card.anchor_left = 0.0
	_card.anchor_right = 0.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_END
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = MARGIN
	_card.offset_right = MARGIN + PANEL_WIDTH
	# BOTH vertical offsets are written explicitly by _reflow_card() after every content
	# change. Leaving offset_top at its default 0 against a 1.0 top anchor made the card's
	# rect NEGATIVE-height and left it to the grow direction to rescue -- which is what put
	# the card's bottom edge off the bottom of the screen. An explicit
	# [-(MARGIN + height), -MARGIN] band cannot be cut off.
	_card.offset_top = -(MARGIN + MAX_HEIGHT)
	_card.offset_bottom = -MARGIN
	_card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 4)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	# NAME + ELEMENT on ONE row. The badge is a ~17px caption pill beside a ~24px 18pt
	# name, so it rides along for FREE -- exactly the arrangement UnitInfoPanel's portrait
	# row uses for a unit's own element, and the reason the card's 152px cap still holds
	# with an element badge added to it.
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(name_row)

	_name_label = Label.new()
	_name_label.name = "TerrainNameLabel"
	_name_label.text = "Terrain"
	_name_label.theme_type_variation = &"SubheadingLabel"
	# NOT autowrapped, now that it shares a row. discipline_label gives an AUTOWRAP label
	# a minimum WIDTH of the full content width -- which, next to a badge, would demand
	# more than the card can give and overflow its frame. Clipped instead: a long terrain
	# name ellipsizes rather than widening or wrapping the card.
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_name_label)

	_element_badge = ElementVisuals.make_badge()
	# The whole card is click-through (see the class note), so the badge -- which defaults
	# to PASS so it can raise a tooltip -- is overridden here like every other row.
	_element_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_element_badge)

	# Multi-floor: which floor the cell is on + where its stairs/ladders lead.
	# Hidden on single-floor maps (so it costs single-floor maps -- every local map --
	# nothing). Wraps at the pinned content width; on a multi-floor map the extra line
	# is absorbed by the chip list's scroll like the matchup / trap rows.
	_floor_label = Label.new()
	_floor_label.name = "FloorLabel"
	_floor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_floor_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_floor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_label.visible = false
	root_vb.add_child(_floor_label)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(sep)

	_move_label = Label.new()
	_move_label.name = "MoveCostLabel"
	_move_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_label.text = "Move Cost: --"
	_move_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_move_label)

	_matchup_label = Label.new()
	_matchup_label.name = "ElementMatchupLabel"
	_matchup_label.text = ""
	_matchup_label.add_theme_font_size_override("font_size", 13)
	_matchup_label.clip_text = true
	_matchup_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_matchup_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_matchup_label.visible = false
	root_vb.add_child(_matchup_label)

	# THE TRAP LINE. One 13px row, HIDDEN for every ordinary tile -- the same "spend a line
	# only when there is news" budget the matchup row above follows, which is what keeps the
	# card inside MAX_HEIGHT. When it does show, _reflow_card hands the extra height to the
	# chip list's existing scroll rather than growing the card.
	_trap_label = Label.new()
	_trap_label.name = "TrapLabel"
	_trap_label.text = ""
	_trap_label.add_theme_font_size_override("font_size", 13)
	_trap_label.add_theme_color_override("font_color", MoveStatVisuals.NERF_COLOR)
	_trap_label.clip_text = true
	_trap_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_trap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trap_label.visible = false
	root_vb.add_child(_trap_label)

	_effects_header = Label.new()
	_effects_header.name = "EffectsHeader"
	_effects_header.text = "TERRAIN EFFECTS"
	_effects_header.theme_type_variation = &"SectionLabel"
	_effects_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_header)

	_effects_scroll = ScrollContainer.new()
	_effects_scroll.name = "EffectsScroll"
	_effects_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_effects_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_scroll)

	_effects_container = VBoxContainer.new()
	_effects_container.name = "EffectsContainer"
	_effects_container.add_theme_constant_override("separation", 4)
	_effects_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_effects_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effects_scroll.add_child(_effects_container)

	# Floor badge: a small separate card beside the terrain card, bottom-aligned with it
	# (multi-floor maps only) -- see _layout_floor_badge / FloorLabels. Beside, not above:
	# the band above the terrain card is the left column's unit card (UnitInfoPanel's
	# BOTTOM_RESERVE is exactly this card's MARGIN + MAX_HEIGHT + gap).
	_floor_badge = PanelContainer.new()
	_floor_badge.name = "FloorBadge"
	_floor_badge.anchor_left = 0.0
	_floor_badge.anchor_right = 0.0
	_floor_badge.anchor_top = 1.0
	_floor_badge.anchor_bottom = 1.0
	_floor_badge.grow_horizontal = Control.GROW_DIRECTION_END
	_floor_badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_floor_badge.offset_left = MARGIN + PANEL_WIDTH + FLOOR_BADGE_GAP
	_floor_badge.offset_bottom = -MARGIN
	_floor_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_badge.visible = false
	add_child(_floor_badge)
	var badge_hb := HBoxContainer.new()
	badge_hb.add_theme_constant_override("separation", 12)
	badge_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_badge.add_child(badge_hb)
	_floor_pips = FloorPips.new()
	_floor_pips.custom_minimum_size = Vector2(18, 30)
	_floor_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_hb.add_child(_floor_pips)
	var badge_vb := VBoxContainer.new()
	badge_vb.add_theme_constant_override("separation", 0)
	badge_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_hb.add_child(badge_vb)
	_floor_badge_label = Label.new()
	_floor_badge_label.name = "FloorBadgeLabel"
	_floor_badge_label.add_theme_font_override("font", MenuTheme.bold_font(0.4))
	_floor_badge_label.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_floor_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_vb.add_child(_floor_badge_label)
	_floor_hint_label = Label.new()
	_floor_hint_label.name = "FloorHintLabel"
	_floor_hint_label.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	_floor_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_vb.add_child(_floor_hint_label)
	_card.resized.connect(_layout_floor_badge)
	_card.visibility_changed.connect(_layout_floor_badge)

	# HUD look first, then the deliberate local colours on top.
	ConquestTheme.apply_to(self)
	# The grove HUD card with tighter vertical padding: this corner is height-capped at
	# MAX_HEIGHT (the HUD reserves exactly that band), and the default 14px top / bottom
	# would spend the room the chip list needs before a single chip is drawn.
	var card_sb := ConquestTheme.panel_box(0.94)
	card_sb.content_margin_top = 9
	card_sb.content_margin_bottom = 9
	_card.add_theme_stylebox_override("panel", card_sb)
	_floor_label.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_floor_hint_label.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_floor_badge_label.add_theme_color_override("font_color", ConquestTheme.GOLD_LITE)
	var badge_sb := ConquestTheme.chip_box(ConquestTheme.GOLD_DK, 0.94)
	badge_sb.content_margin_top = 8
	badge_sb.content_margin_bottom = 8
	_floor_badge.add_theme_stylebox_override("panel", badge_sb)

	# Bound every row's contribution to the card's minimum size. An autowrap Label (the
	# move-cost and floor rows) reports its minimum HEIGHT for whatever width it was last
	# laid out at -- measured, this card's VBox was demanding 287px for four short rows,
	# which blew the 152px the HUD reserves for this corner. Pinning a floor width pins the
	# line count with it. See UnitInfoPanel.discipline_label for the full note. Only the
	# CARD's subtree: the floor badge is not height-budgeted and sizes to its own text.
	UnitInfoPanel.discipline_subtree(_card, CONTENT_WIDTH)


# --- Public API --------------------------------------------------------------

## Populate and show the panel for a specific board cell. Hides itself (and
## returns) when the cell has no registered terrain -- e.g. off the loaded
## map, or no map/board loaded yet.
func show_for_cell(cell: Vector3i) -> void:
	# NOTE: a null tile here means the cursor is on an IN-BOUNDS cell whose terrain
	# isn't registered (a registry miss), NOT off-board -- _on_cursor_moved already
	# rejected off-board cells. Blanking the whole panel in that case was the
	# "hovering shows no UI" symptom, so instead show the cell as Unknown Terrain
	# and still surface any tile effects. The panel appears whenever the cursor is
	# over the board.
	var tile: TileResource = CombatServices.tile_at(cell)

	_current_cell = cell

	var unit_cost := _unit_move_cost_text(cell)
	if tile != null:
		_name_label.text = tile.tile_name if tile.tile_name != "" else "Unknown Terrain"
		if not unit_cost.is_empty():
			_move_label.text = unit_cost
		elif tile.is_tile_passable():
			_move_label.text = "Move cost  %d" % maxi(1, tile.base_movement_cost)
		else:
			_move_label.text = "Impassable"
	else:
		_name_label.text = "Unknown Terrain"
		_move_label.text = unit_cost if not unit_cost.is_empty() else "Move cost  1"

	_refresh_floor_info(cell)

	# Reveal BEFORE populating effects: the name/move rows are already valid, so
	# even if effect population ever failed we still surface the terrain instead of
	# leaving a wired-but-hidden panel (the reported "never appears" symptom).
	show()
	_refresh_element_rows(cell)
	_refresh_trap_row(cell)
	_populate_effects(cell)


# --- Per-unit move cost ----------------------------------------------------------
# MovementResolver prices a step with the MOVER's profile (per-terrain overrides,
# and flying/phasing kinds ignore blocking terrain), so the tile's base cost can be
# wrong for the unit the player cares about. When a unit is selected -- or, with
# nothing selected, a unit stands on the hovered cell -- show the cost for THAT
# unit's profile via the resolver's own (read-only) cost/blocking helpers.
# (The selection itself is tracked in the element-rows section below:
# selected_unit / set_selected_unit / _on_unit_selected / _on_unit_deselected.)

func _refresh_current_cell() -> void:
	if visible and _current_cell != Vector3i(-999999, -999999, 0):
		show_for_cell(_current_cell)

## The unit whose profile prices the hovered cell: the selected unit, else the unit
## standing on [param cell]; null when neither exists. FOG: a unit this screen cannot
## see is never used -- "Move cost 2 (Duskmaw)" on a fogged cell would name exactly the
## unit fog of war is hiding.
func _cost_unit_for(cell: Vector3i, board):
	var sel = selected_unit()
	if sel != null:
		return sel
	if board != null and board.has_method("units_at"):
		for u in board.units_at(cell):
			if u != null and is_instance_valid(u) and not FogOfWarOverlay.unit_hidden(u):
				return u
	return null

## "Move Cost: N (Unit)" for the cost-unit's movement profile, or "" when there is no
## unit / profile to price with (the caller then shows the tile's base cost).
func _unit_move_cost_text(cell: Vector3i) -> String:
	var board = CombatServices.board()
	if board == null:
		return ""
	var unit = _cost_unit_for(cell, board)
	if unit == null or not unit.has_method("get_movement_profile"):
		return ""
	var profile = unit.get_movement_profile()
	if not (profile is MovementProfile):
		return ""
	var who: String = unit.get_display_name() if unit.has_method("get_display_name") else ""
	var suffix := "  (%s)" % who if not who.is_empty() else ""
	# Only GROUND movers are stopped by blocking terrain (see MovementResolver._can_traverse).
	if profile.kind == CombatTypes.MovementKind.GROUND and MovementResolver._is_blocked(board, cell):
		return "Impassable" + suffix
	return "Move cost  %d" % MovementResolver._enter_cost(cell, profile, board, unit) + suffix


# --- Multi-floor readout ---------------------------------------------------------

func _on_view_floor_changed(view_floor: int, cut_floor: int, floor_count: int) -> void:
	_view_floor = view_floor
	_cut_floor = cut_floor
	_floor_count = maxi(1, floor_count)
	if _current_cell != Vector3i(-999999, -999999, 0):
		_refresh_floor_info(_current_cell)
	else:
		_refresh_floor_badge(0)


## Floor line ("Upper floor · Stairs ▼ Ground") in the terrain card, and the floor
## badge beside it. Both hidden on single-floor maps.
func _refresh_floor_info(cell: Vector3i) -> void:
	if _floor_label == null:
		return
	var board = CombatServices.board() if CombatServices else null
	if board != null and board.has_method("floor_count"):
		_floor_count = maxi(_floor_count, int(board.floor_count()))
	if _floor_count <= 1:
		_floor_label.visible = false
		_refresh_floor_badge(cell.z)
		return
	var parts := PackedStringArray(["%s floor" % FloorNav.floor_name(cell.z, _floor_count)])
	parts.append_array(FloorNav.describe_links(board, cell))
	if FloorNav.is_covered(board, cell):
		parts.append("Under cover")
	# One wrapped line rather than a line per part: the card is height-capped (MAX_HEIGHT).
	_floor_label.text = "  ·  ".join(parts)
	_floor_label.visible = true
	_refresh_floor_badge(cell.z)
	call_deferred("_reflow_card")


func _refresh_floor_badge(cursor_floor: int) -> void:
	if _floor_badge == null:
		return
	if _floor_count <= 1:
		_floor_badge.visible = false
		return
	_floor_badge_label.text = "Floor %d / %d  ·  %s" % [
		_view_floor + 1, _floor_count, FloorNav.floor_name(_view_floor, _floor_count)]
	var up := ConquestTheme.action_glyph(InputActions.FLOOR_UP)
	var down := ConquestTheme.action_glyph(InputActions.FLOOR_DOWN)
	var hint := "%s / %s  change floor" % [up, down]
	if _cut_floor < _view_floor:
		hint = "Cutaway to %s  ·  %s" % [FloorNav.floor_name(_cut_floor, _floor_count), hint]
	_floor_hint_label.text = hint
	_floor_pips.set_state(_floor_count, _view_floor, _cut_floor, cursor_floor)
	_floor_badge.visible = true
	_layout_floor_badge()


## Seat the floor badge beside the terrain card, bottom edges aligned (the band above the
## card belongs to the left column's unit card -- see the note in _create_ui).
func _layout_floor_badge() -> void:
	if _floor_badge == null or _card == null:
		return
	_floor_badge.offset_left = MARGIN + maxf(_card.size.x, PANEL_WIDTH) + FLOOR_BADGE_GAP
	_floor_badge.offset_bottom = -MARGIN


## Dim while a modal overlay (map menu, settings) is open so it reads as behind it.
func _process(_delta: float) -> void:
	if visible:
		modulate = Color(0.5, 0.5, 0.55) if InputActions.gameplay_input_blocked(get_tree()) else Color.WHITE


## Hide the panel and reset its tracked cell so the next show_for_cell always
## repopulates fresh.
func hide_panel() -> void:
	_current_cell = Vector3i(-999999, -999999, 0)
	hide()


# --- The element rows ----------------------------------------------------------


## The unit the matchup line is measured against, or null. Kept as an accessor so a test
## (and a future caller) can read the panel's notion of "you" without touching the field.
func selected_unit():
	return _selected_unit if _selected_unit != null and is_instance_valid(_selected_unit) else null


## Point the panel at [param unit] as the selection, repainting the matchup line AND the
## per-unit Move Cost row in place. Public so a test can set the selection without a live
## cursor or turn system; the live game reaches it through GameEvents.
func set_selected_unit(unit) -> void:
	_selected_unit = unit
	_refresh_current_cell()


func _on_unit_selected(unit, _position = null) -> void:
	set_selected_unit(unit)


func _on_unit_deselected(unit) -> void:
	if _selected_unit == unit:
		set_selected_unit(null)


## Repaint the element badge and the matchup line for [param cell].
##
## THE SAME NUMBERS THE BOARD USES, on both sides of the line. The multiplier is
## [method ElementChart.environment_scale_for] -- the one function a tile's damage tick
## resolves through; the damage in parentheses is
## [method TileEffectResource.damage_preview_for]; the boosted heal / bonus is
## [method TileEffectResource.home_summary_for], which scales through the SAME
## [method ElementChart.home_effect_amount] the effect's own run does. Nothing on this row
## is re-derived here (CONQUEST.md rule 9).
func _refresh_element_rows(cell: Vector3i) -> void:
	if _element_badge == null or not is_instance_valid(_element_badge):
		return
	var effects: Array = CombatServices.tile_effects_at(cell)
	var elements: Array = ElementChart.tile_elements_of(effects)

	# THE tile's element: the first one its effects contribute, in the cell's own effect
	# order (base terrain before anything a move applied on top). Deterministic, and one
	# badge rather than a row of them -- a cell carrying two different elements at once is
	# the rare case, and the chips below already name every effect on it.
	ElementVisuals.update_badge(_element_badge, elements[0] if not elements.is_empty() else &"")

	_matchup_label.visible = false
	_matchup_label.text = ""
	var unit = selected_unit()
	if unit == null:
		call_deferred("_reflow_card")
		return

	for te in effects:
		if te == null:
			continue
		var line: Dictionary = _matchup_line(te, unit)
		if line.is_empty():
			continue
		_matchup_label.text = String(line["text"])
		_matchup_label.add_theme_color_override("font_color", line["color"] as Color)
		_matchup_label.visible = true
		break

	call_deferred("_reflow_card")


## The one line [param te] has to say to [param unit], as
## [code]{ text: String, color: Color }[/code] — or EMPTY when it has nothing to say,
## which is every tile the element rule does not touch (no element, no element on the
## unit, an unauthored pairing, an effect with no magnitude to scale).
##
## Two shapes, because a tile can hurt you or help you and the player needs to be told
## either way:
##
##   HARM   "Fire: ×1.25 vs you (19 dmg)"          — the tile DAMAGES, and the matchup
##          moves the number. Tinted from the PLAYER's side, which INVERTS the forecast's
##          reading: on a forecast card "strong" is your move landing hard, so it is
##          green; here the strong party is the GROUND, and ×1.25 into your unit is bad
##          news. Swapping the verdict before asking for the colour keeps the HUD's one
##          rule — green means better for me — true on both cards.
##   BOOST  "Nature: heals ×1.25 for you (13 HP)"  — the tile GIVES, and the unit is at
##          home in it, so what it gives is bigger (or what it takes is smaller). Always
##          the buff colour: every outcome of the at-home rule is in the player's favour.
##
## Harm is checked FIRST. A tile that both damages and buffs would otherwise announce the
## pleasant half of itself while quietly burning the unit down.
func _matchup_line(te, unit) -> Dictionary:
	var element: StringName = ElementChart.tile_element_of(te)
	if element == &"":
		return {}
	var name: String = ElementVisuals.label_for(element)

	var dealt: int = te.damage_preview_for(unit, CombatServices.board())
	if dealt > 0:
		var mult: float = ElementChart.environment_scale_for(element, unit)
		var label: StringName = ElementVisuals.label_for_multiplier(mult)
		if label == ElementVisuals.NEUTRAL:
			return {}  # neutral renders as nothing; the row's presence is the signal
		return {
			"text": "%s: ×%s vs you (%d dmg)"
				% [name, ElementVisuals.format_multiplier(mult), dealt],
			"color": ElementVisuals.effectiveness_color(_inverted(label)),
		}

	var summary: Dictionary = te.home_summary_for(unit)
	var authored: int = int(summary.get("authored", 0))
	var landed: int = int(summary.get("landed", 0))
	if authored == 0 or landed == authored:
		return {}  # the element rule changed nothing here, so there is nothing to report
	var scale: String = ElementVisuals.format_multiplier(
		ElementChart.home_effect_scale(authored))
	var text: String = ""
	if landed < 0:
		text = "%s: softens ×%s for you (%d)" % [name, scale, landed]
	elif StringName(summary.get("kind", &"")) == &"heal":
		text = "%s: heals ×%s for you (%d HP)" % [name, scale, landed]
	else:
		text = "%s: boosts ×%s for you (+%d)" % [name, scale, landed]
	return { "text": text, "color": MoveStatVisuals.BUFF_COLOR }


## Show the trap row when [param cell] carries a pass-through trap, else hide it.
##
## Asked of the RESOURCE, never of a table here: [method TileEffectResource.trap_descriptor]
## returns the line (empty for everything that is not a trap), so the rule and its wording
## live with the data and every surface that describes a tile quotes the same sentence.
## The first trap on the cell wins, in the cell's own effect order -- the same first-in-order
## rule the element badge and the matchup line already use.
##
## Deliberately NOT filtered by the selected unit: a trap is a property of the tile the
## player is inspecting, and hiding it because the currently-selected unit happens to be on
## the side that placed it would make the card lie about the board.
func _refresh_trap_row(cell: Vector3i) -> void:
	if _trap_label == null or not is_instance_valid(_trap_label):
		return
	_trap_label.text = ""
	_trap_label.visible = false
	for te in CombatServices.tile_effects_at(cell):
		if te == null or not te.has_method("trap_descriptor"):
			continue
		var line: String = te.trap_descriptor()
		if line == "":
			continue
		_trap_label.text = line
		_trap_label.visible = true
		break
	call_deferred("_reflow_card")


## Swap STRONG <-> RESISTED. The tile is the ATTACKER in an environmental matchup, so the
## verdict a forecast would print has to be read from the other side before it is coloured.
static func _inverted(label: StringName) -> StringName:
	if label == ElementVisuals.STRONG:
		return ElementVisuals.RESISTED
	if label == ElementVisuals.RESISTED:
		return ElementVisuals.STRONG
	return label


# --- Internals -----------------------------------------------------------------

## Height the card renders at for a content height of [param content_h], capped so the
## HUD's bottom-left reserve holds. Pure so the budget can be pinned by a test:
## MARGIN (16) + card (<= MAX_HEIGHT 152) + an 8px gap == UnitInfoPanel.BOTTOM_RESERVE.
static func card_height(content_h: float) -> float:
	return clampf(content_h, 0.0, MAX_HEIGHT)


## Re-pin the card to the bottom-left corner: cap the elastic chip list so the whole card
## fits in MAX_HEIGHT, then write BOTH vertical offsets from the measured height. Never
## relies on the grow direction to rescue an inverted rect.
func _reflow_card() -> void:
	if _card == null or not is_instance_valid(_card):
		return

	var content_h: float = _card.get_combined_minimum_size().y
	if _effects_scroll != null and is_instance_valid(_effects_scroll):
		# Measure the fixed rows with the list collapsed, then give the list whatever is
		# left under the cap.
		_effects_scroll.custom_minimum_size.y = 0.0
		var fixed: float = _card.get_combined_minimum_size().y
		var room: float = maxf(0.0, MAX_HEIGHT - fixed)
		var used: float = minf(_effects_container.get_combined_minimum_size().y, room)
		_effects_scroll.custom_minimum_size.y = used
		content_h = fixed + used

	var h: float = card_height(content_h)
	_card.offset_top = -(MARGIN + h)
	_card.offset_bottom = -MARGIN


func _populate_effects(cell: Vector3i) -> void:
	# remove_child BEFORE queue_free: a queued-but-still-parented chip keeps contributing
	# to get_combined_minimum_size(), so _reflow_card() below would size the card against
	# the PREVIOUS tile's chips as well as this one's.
	for child in _effects_container.get_children():
		_effects_container.remove_child(child)
		child.queue_free()

	# ALL effects (base terrain + runtime), plus the runtime-only set so we can flag
	# which chips are temporary. A tile can now hold several at once (e.g. tall
	# grass + a fire ignited on top), and each gets its own colour-coded chip.
	var effects: Array = CombatServices.tile_effects_at(cell)
	var applied: Array = CombatServices.applied_tile_effects_at(cell)

	if effects.is_empty():
		var none_label := Label.new()
		none_label.text = "None"
		none_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
		# Muted so the "nothing here" state reads as secondary, not a real effect.
		none_label.add_theme_color_override("font_color", ConquestTheme.TEXT_MUTED)
		none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UnitInfoPanel.discipline_label(none_label, CONTENT_WIDTH)
		_effects_container.add_child(none_label)
		# Content changed height; re-pin after this layout pass rather than during it.
		call_deferred("_reflow_card")
		return

	for te in effects:
		if te == null:
			continue
		# Temporary iff this effect is in the runtime (applied-this-battle) set --
		# i.e. NOT an inherent terrain effect.
		_effects_container.add_child(_build_effect_chip(te, te in applied))

	call_deferred("_reflow_card")


## Build one colour-coded chip for a tile effect: a rounded PanelContainer whose
## fill is a dim version of the effect colour, framed by a 1px border in the
## effect colour, holding a tiny colour swatch + the effect name (both from
## [TileEffectVisuals], the shared source of truth the 3D overlay pips also use).
##
## Temporary (runtime-applied) effects are marked with a "· temp" suffix on the
## label rather than a different border colour. Chosen over swapping the border to
## TEMPORARY_TINT because a text tag is unambiguous regardless of the effect's own
## hue (an orange TEMPORARY_TINT border could read as just another Fire-ish frame),
## and it keeps every chip's frame consistent with its swatch colour.
func _build_effect_chip(te: TileEffectResource, is_temporary: bool) -> PanelContainer:
	var info: Dictionary = TileEffectVisuals.info_for(te)
	var color: Color = info.get("color", ConquestTheme.AMBER)
	var label_text: String = String(info.get("name", "Effect"))
	if is_temporary:
		label_text += " · temp"

	var chip := PanelContainer.new()
	# PASS (not STOP): the Compendium-worded tooltip shows without eating board clicks.
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = CompendiumData.tile_effect_tooltip(te)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ConquestTheme.keep_style(chip)
	var sb := ConquestTheme.chip_style(color)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(hb)

	# Colour swatch echoing the effect colour (and the 3D overlay pip).
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(swatch)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	label.add_theme_color_override("font_color", color.lightened(0.5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(label)

	return chip


## GameEvents.cursor_moved carries the cursor's grid coordinates directly, as
## Vector3(col, 0, row) -- see board/cursor/cursor.gd (`tile_position` is
## already grid-clamped before the signal fires) and the same conversion used
## by UnitActionsPanel._on_cursor_moved_forecast / _refresh_move_forecast.
## No world->cell math is needed here; this mirrors that exact pattern instead
## of re-deriving it through BoardAdapter.world_to_cell (which expects a raw
## world-space position, not grid coordinates).
func _on_cursor_moved(grid_pos: Vector3) -> void:
	var cell := Cells.from_grid(grid_pos)  # Vector3(col, floor, row) -> cell

	# TOUCH-READY STICKINESS: once shown for a cell, this panel stays up until the
	# cursor genuinely reports a DIFFERENT cell -- never merely because cursor_moved
	# re-fired (or motion paused) while resting on the same one. Owning this check
	# locally (rather than depending on board/cursor/cursor.gd's tile_position setter
	# only emitting on real changes) keeps the guarantee correct regardless of what
	# drives cursor_moved.
	if cell == _current_cell and visible:
		return

	# No live board yet (no map loaded / between rebuilds) -- nothing to show.
	var board := CombatServices.board()
	if board == null:
		hide_panel()
		return

	# Off-board cells never have registered terrain, but check explicitly so we
	# don't even attempt a lookup once the board can tell us definitively.
	if board.has_method("in_bounds") and not board.in_bounds(cell):
		hide_panel()
		return

	show_for_cell(cell)
