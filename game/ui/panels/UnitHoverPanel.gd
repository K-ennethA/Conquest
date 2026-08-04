extends Control

class_name UnitHoverPanel

# Fire-Emblem-style UNIT INSPECTION card: a compact, non-modal floating overlay
# showing the unit under the board cursor -- its name, HP, and active status
# conditions -- WITHOUT requiring selection, so a player can size up an enemy by
# just moving the cursor over it.
#
# Deliberately built as a sibling of [TerrainInfoPanel]: same code-built (no
# .tscn) structure, same top_level + _fit_to_viewport treatment, same
# GameEvents.cursor_moved subscription, same ConquestTheme amber look, and the
# same mouse_filter = IGNORE everywhere so it can never eat a board click.
# Statuses are coloured through [StatusVisuals], the shared vocabulary the
# world-space HealthBar pips and the UnitInfoPanel chips also use.
#
# POSITION -- anchored BOTTOM-RIGHT. Every other corner is already claimed in the
# battle HUD: TerrainInfoPanel and TurnSystemIndicator sit bottom-LEFT,
# UnitInfoPanel occupies top-left (20,20)-(320,360), TurnIndicator and
# UnitActionsPanel share the top-right / right sidebar, and the turn banner plus
# CombatForecastPanel own top-center. Bottom-right is the one region nothing else
# uses, so the card can never collide. It was chosen over "follow the cursor with
# an offset" because a fixed corner needs no camera unprojection (cursor_moved
# carries GRID coordinates, not screen ones), keeps the card in a stable place the
# eye learns, and cannot drift under the pointer while the player is aiming.
#
# Self-contained: builds its own UI and wires its own cursor handler in _ready().
# See GameWorldManager._setup_unit_hover_panel(), which only instantiates it.

const PANEL_WIDTH := 240.0
const MARGIN := 16.0

## Status chips shown before the row collapses into a "+N" overflow marker.
const MAX_CHIPS := 4

## Widest the element badge on the HP row may claim -- see the arithmetic in _create_ui.
const ELEMENT_BADGE_MAX_WIDTH := 72.0

## Green used for the terrain-bonus chip (== ConquestTheme.EL_NATURE). Terrain
## avoid is a passive of WHERE the unit stands (tall grass -> +evasion), so it
## reads as "nature" green rather than a status colour to set it apart from the
## StatusVisuals-coloured condition chips.
const TERRAIN_AVOID_COLOR := Color("5fb84e")

var _card: PanelContainer
var _name_label: Label
var _hp_label: Label
var _hp_bar: ProgressBar
## The unit's elemental TYPE, right-aligned on the HP row. Hidden for a unit with no
## element, so the row is exactly what it was before for two thirds of the roster.
var _element_badge: PanelContainer
var _effects_container: HFlowContainer
## "◊15" on the HP row and the silver tail on the HP bar -- the damage-soak shield, drawn
## by the same rule as on the battle card and the world bar (see [ShieldVisuals]). Both
## hidden at zero shield, so an unshielded unit's card is unchanged. The label is 12px, one
## point under the HP label, so it draws inside the row's existing height and cannot grow
## the card (the same measurement that put the element badge on this row).
var _shield_label: Label
var _shield_tail: ColorRect

# The unit currently shown, or null. Lets _on_cursor_moved own a local "stays sticky
# until the reported unit genuinely changes" guarantee -- see the TOUCH-READY
# STICKINESS note there -- instead of depending on cursor_moved's own emission
# semantics.
var _current_unit = null

## The unit currently SELECTED (via GameEvents.unit_selected/deselected). The hover
## card suppresses itself for this unit -- its readout already lives on the compact
## battle card, and duplicating HP bottom-right is what the unit-info split removed.
var _selected_unit = null


func _ready() -> void:
	name = "UnitHoverPanel"

	# Detach from any parent Container so our anchors are viewport-relative.
	top_level = true
	# A top_level Control IGNORES anchors, so an anchor preset would leave our size
	# at (0,0) and the bottom-anchored card would resolve against height 0 and land
	# off-screen -- the exact bug recorded in TerrainInfoPanel._ready. So size the
	# rect to the viewport explicitly and keep it in sync on resize; the card inside
	# is a normal (non-top_level) child, so ITS anchors resolve correctly.
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)

	# Passive readout only -- never eat mouse input anywhere in the subtree.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Same layer as TerrainInfoPanel: above the base HUD, below modal popups.
	z_as_relative = false
	z_index = 90

	_create_ui()
	visible = false

	if GameEvents and not GameEvents.cursor_moved.is_connected(_on_cursor_moved):
		GameEvents.cursor_moved.connect(_on_cursor_moved)
	# Track the SELECTED unit so the card can suppress itself for it: the selected
	# unit already owns the compact battle card on the left, and showing the same
	# HP a second time bottom-right is exactly the duplication the unit-info split
	# removed. Hover stays for peeking at every OTHER unit.
	if GameEvents:
		if not GameEvents.unit_selected.is_connected(_on_unit_selected):
			GameEvents.unit_selected.connect(_on_unit_selected)
		if not GameEvents.unit_deselected.is_connected(_on_unit_deselected):
			GameEvents.unit_deselected.connect(_on_unit_deselected)


## Pin our rect to the whole viewport so the bottom-right-anchored card lands on
## screen. A top_level Control ignores its parent, so it will not size itself.
func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size

	# Cap the card to the viewport so it never clips off a narrow window. _card is
	# built in _create_ui, which runs AFTER the first _fit_to_viewport call in
	# _ready, so guard it here (and it stays valid on every later resize signal).
	if _card != null and is_instance_valid(_card):
		var w := minf(PANEL_WIDTH, size.x - MARGIN * 2.0)
		_card.custom_minimum_size.x = maxf(0.0, w)


func _create_ui() -> void:
	# Pinned to the BOTTOM-RIGHT corner: grow_horizontal BEGIN / grow_vertical
	# BEGIN means the card expands left-and-up from that corner as content is
	# added, mirroring how TerrainInfoPanel grows from the bottom-left.
	_card = PanelContainer.new()
	_card.name = "UnitHoverCard"
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -MARGIN
	_card.offset_bottom = -MARGIN
	_card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 4)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	_name_label = Label.new()
	_name_label.name = "UnitNameLabel"
	_name_label.text = "Unit"
	_name_label.add_theme_font_size_override("font_size", 17)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_name_label)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(sep)

	# The HP row carries the element badge on its right, and that placement is the whole
	# reason there IS a badge here. The card has no fixed height -- it grows up-and-left
	# from the bottom-right corner -- so any NEW row would grow the panel, and the brief
	# was to add the chip only where an existing row has room. This row has room by
	# measurement, not by hope: "HP 40/40" at 13px is ~58px, the badge is capped at
	# ELEMENT_BADGE_MAX_WIDTH (72), and 58 + 6 separation + 72 == 136 inside the ~224px
	# the 240px card leaves after its panel padding.
	#
	# VERTICALLY it is free only because the pill gives up its padding. The HP label at
	# 13px draws 18px; a 12px badge label draws 17px, and at the badge's DEFAULT 1px
	# top/bottom content margin that is 19px -- one pixel taller than the row, which grows
	# the card. Measured, and caught by test_the_hover_chip_does_not_grow_the_card. Passing
	# v_padding = 0 puts the pill at 17px, inside the 18px the row already claimed, so the
	# row's height (and therefore the card's) is genuinely unchanged.
	#
	# The NAME row was the obvious alternative and was rejected: _name_label autowraps,
	# so taking ~72px off it makes a multi-word boss name ("Eldroot the Hollow Crown")
	# wrap to a second line -- i.e. it grows the panel for exactly the units a player is
	# most likely to be inspecting.
	var hp_row := HBoxContainer.new()
	hp_row.name = "HPRow"
	hp_row.add_theme_constant_override("separation", 6)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(hp_row)

	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.text = "HP --/--"
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(_hp_label)

	_shield_label = Label.new()
	_shield_label.name = "ShieldLabel"
	_shield_label.text = ""
	_shield_label.add_theme_font_size_override("font_size", 12)
	_shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_label.visible = false
	hp_row.add_child(_shield_label)

	_element_badge = ElementVisuals.make_badge(&"", 12, ELEMENT_BADGE_MAX_WIDTH, 0)
	# This whole subtree is click-through by design (see _ready), so the badge gives up
	# the tooltip its PASS default would earn it.
	_element_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(_element_badge)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.custom_minimum_size = Vector2(0, 10)
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	# CONTINUOUS, not stepped. A Range's default step is 0.01, so this 0..1 bar SNAPPED
	# every fill to the nearest percent -- 25/40 drew as 0.63 rather than 0.625. That was
	# invisible while the bar was the only thing on the track; with the shield tail anchored
	# at the exact fraction it becomes a visible seam between the green and the silver.
	_hp_bar.step = 0.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_hp_bar)

	# The shield tail: a child of the bar, so it draws over the fill and claims no layout
	# slot. Anchored per forecast in _update_shield_readout.
	_shield_tail = ColorRect.new()
	_shield_tail.name = "ShieldTail"
	_shield_tail.color = ShieldVisuals.SILVER
	_shield_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_tail.anchor_top = 0.0
	_shield_tail.anchor_bottom = 1.0
	_shield_tail.offset_left = 0.0
	_shield_tail.offset_right = 0.0
	_shield_tail.offset_top = 0.0
	_shield_tail.offset_bottom = 0.0
	_shield_tail.visible = false
	_hp_bar.add_child(_shield_tail)

	# HFlow so a unit with several statuses wraps onto a second line instead of
	# stretching the card past PANEL_WIDTH.
	_effects_container = HFlowContainer.new()
	_effects_container.name = "EffectsContainer"
	_effects_container.add_theme_constant_override("h_separation", 3)
	_effects_container.add_theme_constant_override("v_separation", 3)
	_effects_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_container)

	# Amber HUD look, applied last so local overrides above are not stripped.
	ConquestTheme.apply_to(self)


# --- Public API --------------------------------------------------------------

## Populate and show the card for [param unit]. Hides itself for a null or freed
## unit, so callers never need to branch.
func show_for_unit(unit) -> void:
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		hide_panel()
		return
	# The selected unit's readout lives on the compact battle card -- never
	# duplicate it here (see _ready's selection subscription).
	if unit == _selected_unit:
		hide_panel()
		return

	_current_unit = unit
	_name_label.text = _display_name_of(unit)
	ElementVisuals.update_badge(
			_element_badge, ElementVisuals.of_unit(unit), ELEMENT_BADGE_MAX_WIDTH)

	# HP is read through `in` guards: a legacy/mock unit with no stats component
	# simply shows a dashed readout instead of erroring.
	var current: int = 0
	var maximum: int = 0
	if "current_health" in unit:
		current = int(unit.current_health)
	if "max_health" in unit:
		maximum = int(unit.max_health)

	# The shield is part of the HP readout, not a separate fact: "HP 58/108 ◊15", with the
	# bar's silver tail saying the same thing in geometry.
	var shield: int = ShieldVisuals.shield_of(unit)
	if maximum > 0:
		_hp_label.text = "HP %d/%d" % [current, maximum]
		var fractions: Dictionary = ShieldVisuals.bar_fractions(current, maximum, shield)
		_hp_bar.value = clampf(float(fractions.get("hp", 0.0)), 0.0, 1.0)
		_hp_bar.visible = true
		_update_shield_readout(shield, fractions)
	else:
		_hp_label.text = "HP --/--"
		_hp_bar.value = 0.0
		_hp_bar.visible = false
		_update_shield_readout(0, {})

	# Reveal BEFORE populating statuses: the name/HP rows are already valid, so
	# even if status population ever failed we still surface the unit rather than
	# leaving a wired-but-hidden panel (TerrainInfoPanel records the same lesson).
	show()
	_populate_effects(unit)


## Hide the card. Safe to call repeatedly.
func hide_panel() -> void:
	_current_unit = null
	hide()


func _on_unit_selected(unit, _selected_position := Vector3.ZERO) -> void:
	_selected_unit = unit
	# If the card is already showing the unit that just became selected, drop it
	# now rather than waiting for the next cursor move.
	if _current_unit == unit:
		hide_panel()


func _on_unit_deselected(_unit) -> void:
	_selected_unit = null


# --- Internals ---------------------------------------------------------------

func _display_name_of(unit) -> String:
	if unit.has_method("get_display_name"):
		var disp: String = String(unit.get_display_name())
		if disp.strip_edges() != "":
			return disp
	if unit is Node:
		return String((unit as Node).name)
	return "Unit"


func _populate_effects(unit) -> void:
	# remove_child before queue_free so a stale chip never lingers for a frame in
	# the flow layout while the new row is being built.
	for child in _effects_container.get_children():
		_effects_container.remove_child(child)
		child.queue_free()

	# Terrain-derived avoid: a passive of the unit's TILE (tall grass -> +evasion),
	# computed on the fly by TerrainStats, never stored as a status -- so it is
	# surfaced here as its own green chip, first in the row, clearly labeled as
	# terrain. Shown only when non-zero.
	var terrain_avoid: int = _terrain_evasion_bonus(unit)
	if terrain_avoid > 0:
		_effects_container.add_child(
			_build_chip("Avoid +%d (terrain)" % terrain_avoid, TERRAIN_AVOID_COLOR))

	# Empty for a unit with no StatusController, no statuses, or a freed unit.
	var conditions: Array = StatusVisuals.active_conditions(unit)
	if conditions.is_empty():
		# Only claim "no effects" when there is ALSO no terrain bonus to show;
		# otherwise the green terrain chip stands on its own.
		if terrain_avoid <= 0:
			var none_label := Label.new()
			none_label.text = "No active effects"
			none_label.add_theme_font_size_override("font_size", 12)
			none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
			none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_effects_container.add_child(none_label)
		return

	# Grouped by id, exactly like the world-space health-bar badges: three live Poisoned
	# instances are ONE status at severity 3, and the hover card is where that severity
	# has to be legible ("† Poisoned x3 · 2 turns"). Ungrouped, they filled the chip
	# budget with identical rows and hid every other condition behind the overflow marker
	# -- so the one surface that could answer "how bad is the poison, and how long" never
	# actually answered it.
	var groups: Array = StatusVisuals.group_by_id(conditions)
	var total: int = groups.size()
	var shown: int = StatusVisuals.shown_count(total, MAX_CHIPS)
	var hidden: int = StatusVisuals.hidden_count(total, MAX_CHIPS)

	for i in range(shown):
		var group: Dictionary = groups[i]
		var condition = group.get("condition", null)
		if condition == null:
			continue
		var info: Dictionary = StatusVisuals.info_for(condition)
		var color: Color = info.get("color", ConquestTheme.AMBER)
		var text: String = StatusVisuals.chip_text(
			condition,
			int(group.get("count", 1)),
			int(group.get("turns_left", StatusVisuals.TURNS_FROM_CONDITION)))
		_effects_container.add_child(_build_chip(text, color))

	if hidden > 0:
		_effects_container.add_child(
			_build_chip(StatusVisuals.overflow_label(hidden), StatusVisuals.OVERFLOW_COLOR))


## Paint the "◊15" and the bar's silver tail for a shield of [param shield], given the
## already-computed [param fractions] from [method ShieldVisuals.bar_fractions]. A zero
## shield hides both and leaves the card exactly as it was before shields were drawn.
func _update_shield_readout(shield: int, fractions: Dictionary) -> void:
	if _shield_label != null and is_instance_valid(_shield_label):
		_shield_label.text = ShieldVisuals.number_text(shield)
		_shield_label.visible = shield > 0
		if shield > 0:
			# Re-asserted per repaint: ConquestTheme.apply_to strips baked font colours.
			_shield_label.add_theme_color_override("font_color", ShieldVisuals.SILVER)

	if _shield_tail == null or not is_instance_valid(_shield_tail):
		return
	var hp: float = float(fractions.get("hp", 0.0))
	var tail: float = float(fractions.get("shield", 0.0))
	if shield <= 0 or tail <= ShieldVisuals.MIN_FRACTION:
		_shield_tail.visible = false
		return
	_shield_tail.anchor_left = clampf(hp, 0.0, 1.0)
	_shield_tail.anchor_right = clampf(hp + tail, 0.0, 1.0)
	_shield_tail.offset_left = 0.0
	_shield_tail.offset_right = 0.0
	_shield_tail.visible = true


## The evasion bonus the unit's current tile grants it (tall grass -> +avoid), or
## 0 when it stands on plain ground. Null-safe: a freed unit, an absent
## CombatServices, or a null board all resolve to 0. TerrainStats reads the
## PASSIVE_WHILE_OCCUPYING tile effects under the unit, the same source combat
## uses when it forecasts the hit chance.
func _terrain_evasion_bonus(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0
	var board = CombatServices.board() if CombatServices else null
	return TerrainStats.bonus_for(unit, "evasion", board)


## A compact colour-coded pill: dim fill, 1px frame in the status colour, cream
## text. Same recipe as TerrainInfoPanel's tile-effect chips, minus the swatch --
## at this size the fill colour IS the swatch.
func _build_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)

	return chip


## The first living unit covering [param cell], or null. Goes through
## [code]BoardAdapter.units_at[/code], which is FOOTPRINT-aware -- so a 2x2 unit
## is found from any of the four cells it covers, not only its anchor.
func _unit_at(cell: Vector2i):
	if CombatServices == null:
		return null
	var board = CombatServices.board()
	if board == null or not board.has_method("units_at"):
		return null
	var units: Array = board.units_at(cell)
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		# Skip corpses awaiting cleanup so the card never describes a dead unit.
		if unit.has_method("is_alive") and not unit.is_alive():
			continue
		return unit
	return null


## GameEvents.cursor_moved carries the cursor's GRID coordinates as
## Vector3(col, 0, row) -- already grid-clamped by board/cursor/cursor.gd. No
## world->cell math needed; this mirrors TerrainInfoPanel._on_cursor_moved exactly.
func _on_cursor_moved(grid_pos: Vector3) -> void:
	var cell := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

	# No live board yet (no map loaded / mid-rebuild) -- nothing to inspect.
	var board = CombatServices.board() if CombatServices else null
	if board == null:
		hide_panel()
		return

	if board.has_method("in_bounds") and not board.in_bounds(cell):
		hide_panel()
		return

	var unit = _unit_at(cell)

	# TOUCH-READY STICKINESS: the cursor still resolves to the SAME unit already
	# shown (its footprint can span several cells) -- nothing to update, and
	# critically nothing to hide. Only a genuinely different unit, or no unit at
	# all, may change what is displayed. Owning this check locally (rather than
	# depending on board/cursor/cursor.gd's tile_position setter only emitting on
	# real cell changes) keeps the guarantee correct regardless of what drives
	# cursor_moved.
	if unit != null and unit == _current_unit and visible:
		return

	if unit == null:
		hide_panel()
		return

	show_for_unit(unit)
