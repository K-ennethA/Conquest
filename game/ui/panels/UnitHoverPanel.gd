extends Control

class_name UnitHoverPanel

# Fire-Emblem-style UNIT INSPECTION card: a compact, non-modal floating overlay
# showing the unit under the board cursor -- its name, HP, and active status
# conditions -- WITHOUT requiring selection, so a player can size up an enemy by
# just moving the cursor over it.
#
# Deliberately built as a sibling of [TerrainInfoPanel]: same code-built (no
# .tscn) structure, same top_level + _fit_to_viewport treatment, same
# GameEvents.cursor_moved subscription, same navy + gold ConquestTheme look, and the
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

const PANEL_WIDTH := HudSafeArea.CORNER_CARD_WIDTH
const MARGIN := ConquestTheme.MARGIN

## Status chips shown before the row collapses into a "+N" overflow marker.
const MAX_CHIPS := 4

## Widest the element badge on the HP row may claim -- see the arithmetic in _create_ui.
const ELEMENT_BADGE_MAX_WIDTH := 72.0

## Terrain-bonus chips shown before the row collapses into a "+N" marker. Same cap the
## world-space badge row and the battle card use -- [constant TerrainVisuals.MAX_CHIPS].
const MAX_TERRAIN_CHIPS := TerrainVisuals.MAX_CHIPS

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
## Header pieces (cloud grove card): the crest portrait (element field, team rim) and
## the side / element subtitle under the name.
var _portrait: PanelContainer
var _sub_label: Label
## Stat name -> value Label in the ATK / DEF / SPD / MOV strip.
var _stat_values: Dictionary = {}


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
		# A unit that MOVES changes the ground under it, and nothing else on this card would
		# notice: the cursor need not have moved, no HP changed, no status landed. This is
		# the beat that makes the terrain chip appear the instant the shown unit steps into
		# grass. Deliberately GameEvents.unit_moved and not a PlayerManager signal, which
		# does not fire on an AI turn (CONQUEST.md rule 2).
		if not GameEvents.unit_moved.is_connected(_on_unit_moved):
			GameEvents.unit_moved.connect(_on_unit_moved)


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
	root_vb.add_theme_constant_override("separation", 8)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	# Header: portrait emblem | name + side / element.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(header)
	_portrait = ConquestTheme.portrait("?", ConquestTheme.GOLD, ConquestTheme.BORDER, 46.0)
	header.add_child(_portrait)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(names)

	_name_label = Label.new()
	_name_label.name = "UnitNameLabel"
	_name_label.text = "Unit"
	_name_label.theme_type_variation = &"SubheadingLabel"
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(_name_label)

	_sub_label = Label.new()
	_sub_label.name = "SideLabel"
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_child(_sub_label)

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
	_hp_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
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

	# The shared HUD HP bar (navy track, tier-coloured fill -- see ConquestTheme.hp_bar).
	_hp_bar = ConquestTheme.hp_bar(10.0)
	_hp_bar.name = "HPBar"
	# CONTINUOUS, not stepped. A Range's default step is 0.01, so this 0..1 bar SNAPPED
	# every fill to the nearest percent -- 25/40 drew as 0.63 rather than 0.625. That was
	# invisible while the bar was the only thing on the track; with the shield tail anchored
	# at the exact fraction it becomes a visible seam between the green and the silver.
	_hp_bar.step = 0.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_hp_bar)

	# Key stats strip: gold caption over a cream value (ATK / DEF / SPD / MOV).
	var stats := HBoxContainer.new()
	stats.name = "Stats"
	stats.add_theme_constant_override("separation", 6)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(stats)
	for pair in [["ATK", "attack"], ["DEF", "defense"], ["SPD", "speed"], ["MOV", "movement"]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", -2)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := Label.new()
		cap.text = pair[0]
		cap.theme_type_variation = &"SectionLabel"
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(cap)
		var val := Label.new()
		val.text = "-"
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(val)
		_stat_values[pair[1]] = val
		stats.add_child(cell)

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
	_effects_container.add_theme_constant_override("h_separation", 4)
	_effects_container.add_theme_constant_override("v_separation", 4)
	_effects_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_container)

	# HUD look, applied first; the deliberate colours / sizes go on after it.
	ConquestTheme.apply_to(self)
	_sub_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	# Cinzel runs wide: a touch smaller so long names ("Eldroot, the Hollow Crown")
	# wrap to two lines at most in the corner card.
	_name_label.add_theme_font_size_override("font_size", 19)
	# apply_to strips baked label colours: re-assert the HP line's cream.
	_hp_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	for v in _stat_values.values():
		(v as Label).add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
		(v as Label).add_theme_color_override("font_color", ConquestTheme.CREAM)


# --- Layout: stay clear of the command menu ------------------------------------

## Keep the card out from under the unit command menu (right column): when the
## menu is tall enough to reach the card (e.g. with Info expanded, or on a 720p
## window), slide the card left of it. Also dims while a modal overlay (map menu,
## settings) is up so it reads as "behind" it.
func _process(_delta: float) -> void:
	if not visible or _card == null:
		return
	modulate = Color(0.5, 0.5, 0.55) if InputActions.gameplay_input_blocked(get_tree()) else Color.WHITE
	var want := -MARGIN
	var panel := get_tree().get_first_node_in_group("unit_actions_panel") as Control
	var duplicate := is_duplicate_of_hud(panel, _current_unit)
	if panel != null and panel.is_visible_in_tree() and not duplicate:
		var pr := panel.get_global_rect()
		var card_h := _card.size.y
		var card_top := size.y - MARGIN - card_h
		if pr.end.y + 8.0 > card_top:
			want = -(size.x - pr.position.x + 12.0)
	if not is_equal_approx(_card.offset_right, want):
		_card.offset_right = want
	_card.visible = not duplicate


## True when [param unit] is already on screen in another HUD card, so the hover card
## would just repeat it: the command menu's header (the selected unit, while that
## menu is up) or either side of the combat forecast. Hover for any OTHER unit is
## unaffected.
static func is_duplicate_of_hud(panel: Node, unit) -> bool:
	if unit == null or not is_instance_valid(unit) or panel == null:
		return false
	var panel_up := panel is CanvasItem and (panel as CanvasItem).is_visible_in_tree()
	if panel_up and "selected_unit" in panel and panel.selected_unit != null \
			and panel.selected_unit == unit:
		return true
	var fc = panel.get("combat_forecast_panel")
	if fc != null and is_instance_valid(fc) and fc is CanvasItem and (fc as CanvasItem).is_visible_in_tree() \
			and fc.has_method("shows_unit") and fc.shows_unit(unit):
		return true
	return false


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
	var display := _display_name_of(unit)
	_name_label.text = display
	ElementVisuals.update_badge(
			_element_badge, ElementVisuals.of_unit(unit), ELEMENT_BADGE_MAX_WIDTH)
	var owner = ConquestTheme.owner_of(unit)
	var parts: PackedStringArray = [ConquestTheme.side_label(owner)]
	if unit.has_method("is_boss") and unit.is_boss():
		parts.append("Boss")
	_sub_label.text = "  ·  ".join(parts)
	_sub_label.add_theme_color_override("font_color", ConquestTheme.team_text_color(owner))
	var cols := ConquestTheme.unit_portrait_colors(unit)
	ConquestTheme.set_portrait(_portrait, display, cols[0], cols[1])
	# Team-coloured edge stripe (the element lives in the crest and the badge).
	_card.add_theme_stylebox_override("panel", ConquestTheme.unit_card_box(unit, 0.95))

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
		# Tier colour off the plain HP fraction (the same thresholds as the map bar).
		ConquestTheme.tint_hp_bar(_hp_bar, clampf(float(current) / float(maximum), 0.0, 1.0))
		_hp_bar.visible = true
		_update_shield_readout(shield, fractions)
	else:
		_hp_label.text = "HP --/--"
		_hp_bar.value = 0.0
		_hp_bar.visible = false
		_update_shield_readout(0, {})

	for stat_name in _stat_values.keys():
		var lbl: Label = _stat_values[stat_name]
		lbl.text = str(int(unit.get_stat(stat_name))) if unit.has_method("get_stat") else "-"

	# Reveal BEFORE populating statuses: the name/HP rows are already valid, so
	# even if status population ever failed we still surface the unit rather than
	# leaving a wired-but-hidden panel (TerrainInfoPanel records the same lesson).
	show()
	var panel := get_tree().get_first_node_in_group("unit_actions_panel") if is_inside_tree() else null
	_card.visible = not is_duplicate_of_hud(panel, unit)
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


## The unit this card is showing just moved: repaint it, so its terrain chips describe the
## cell it is standing on now. Every other unit's move is ignored -- this card only ever
## describes one.
func _on_unit_moved(unit, _from_position = null, _to_position = null) -> void:
	if unit != null and unit == _current_unit and visible:
		show_for_unit(unit)


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

	# WHAT THE GROUND IS GIVING IT, first in the row. A terrain bonus is a passive of the
	# unit's TILE (tall grass -> +evasion, fortify -> +defense, ice -> -evasion), computed
	# on the fly and never stored as a status, so nothing else on this card would show it.
	#
	# UNIFIED, not local: the numbers, the mark, the wording and the colours all come from
	# [TerrainVisuals] -- the same helper the world-space badge row and the battle card read
	# -- so the "+19" over a nature unit in nature grass and the "+19" on this card are one
	# lookup off [method TerrainStats.bonus_for], which is also the number
	# [method MoveContext.hit_chance] rolls against. This card used to compute an
	# evasion-only version of its own; that is exactly the drift the helper removes.
	var terrain: Array = _terrain_bonuses(unit)
	var terrain_shown: int = TerrainVisuals.shown_count(terrain.size(), MAX_TERRAIN_CHIPS)
	var terrain_hidden: int = TerrainVisuals.hidden_count(terrain.size(), MAX_TERRAIN_CHIPS)
	for i in range(terrain_shown):
		var entry: Dictionary = terrain[i]
		# The ROOMY label: this card has 240px and its whole subtree is click-through (see
		# _ready), so it can never show a tooltip -- naming the terrain in the label itself
		# is the only way it can say WHERE the bonus comes from. The tooltip is still set,
		# for the same reason the element badge keeps its own: it costs nothing and becomes
		# correct the moment this card's input policy changes.
		_effects_container.add_child(_build_terrain_chip(entry))
	if terrain_hidden > 0:
		_effects_container.add_child(_build_chip(
			TerrainVisuals.overflow_label(terrain_hidden), StatusVisuals.OVERFLOW_COLOR))

	# Empty for a unit with no StatusController, no statuses, or a freed unit.
	var conditions: Array = StatusVisuals.active_conditions(unit)
	if conditions.is_empty():
		# Only claim "no effects" when there is ALSO no terrain bonus to show;
		# otherwise the terrain chip stands on its own.
		if terrain.is_empty():
			var none_label := Label.new()
			none_label.text = "No status effects"
			none_label.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
			none_label.add_theme_color_override("font_color", ConquestTheme.TEXT_MUTED)
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
		# Hover wording shared with the Compendium's Statuses entry.
		var tip := CompendiumData.status_tooltip(condition, StatusVisuals.turns_left_of(condition))
		_effects_container.add_child(_build_chip(text, color, tip))

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


## Every nonzero stat bonus the unit's current tile grants it, from the shared helper.
## Null-safe: a freed unit, an absent CombatServices, or a null board all resolve to an
## empty array. [TerrainVisuals] reads the PASSIVE_WHILE_OCCUPYING tile effects under the
## unit through [TerrainStats] -- the same source and the same arithmetic combat uses when
## it forecasts the hit chance.
func _terrain_bonuses(unit) -> Array:
	if unit == null or not is_instance_valid(unit):
		return []
	var board = CombatServices.board() if CombatServices else null
	return TerrainVisuals.bonuses_for(unit, board)


## A terrain chip: the shared mark and colours, but a THICKER frame, squarer corners and
## COLOURED text on a deep fill -- the inverse of the status chips beside it (cream text on
## a tinted fill, round corners, hairline frame). "Where I am standing" and "what is on me"
## have to be distinguishable at a glance, or one row of chips reads as one kind of fact.
func _build_terrain_chip(entry: Dictionary) -> PanelContainer:
	var color: Color = TerrainVisuals.color_for(entry)
	var chip := PanelContainer.new()
	chip.name = "TerrainChip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.tooltip_text = TerrainVisuals.tooltip_for(entry)

	# Square-shouldered notched plate, 2px frame: the inverse of a status TAG chip.
	var sb := MenuTheme.plate_box(color.darkened(0.72), color, 3.0, 6, 2, 2.0)
	sb.sheen = 0.0
	chip.add_theme_stylebox_override("panel", sb)

	var label := Label.new()
	label.name = "TerrainChipLabel"
	label.text = TerrainVisuals.full_chip_text(entry)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)

	return chip


## A compact colour-coded pill: dim fill, 1px frame in the status colour, cream
## text. Same recipe as TerrainInfoPanel's tile-effect chips, minus the swatch --
## at this size the fill colour IS the swatch.
func _build_chip(text: String, color: Color, tip: String = "") -> PanelContainer:
	var chip := ConquestTheme.chip(text, color, ConquestTheme.FS_CAPTION)
	if tip != "":
		# PASS (not STOP) so the tooltip shows without eating board clicks.
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = tip
	return chip


## The first living unit covering [param cell], or null. Goes through
## [code]BoardAdapter.units_at[/code], which is FOOTPRINT-aware -- so a 2x2 unit
## is found from any of the four cells it covers, not only its anchor.
func _unit_at(cell: Vector3i):
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
		# FOG: a unit this screen cannot see is not there to be inspected. The board still
		# knows it is standing here -- that is the whole point -- but hovering the cell must
		# read as empty ground, or the card becomes an x-ray that names the unit, its HP and
		# its statuses through the mist. Falls through to `null`, so the panel simply hides.
		if FogOfWarOverlay.unit_hidden(unit):
			continue
		return unit
	return null


## GameEvents.cursor_moved carries the cursor's GRID coordinates as
## Vector3(col, 0, row) -- already grid-clamped by board/cursor/cursor.gd. No
## world->cell math needed; this mirrors TerrainInfoPanel._on_cursor_moved exactly.
func _on_cursor_moved(grid_pos: Vector3) -> void:
	var cell := Cells.from_grid(grid_pos)  # Vector3(col, floor, row) -> cell

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
