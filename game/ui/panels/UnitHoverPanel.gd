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

const PANEL_WIDTH := 300.0
const MARGIN := ConquestTheme.MARGIN

## Status chips shown before the row collapses into a "+N" overflow marker.
const MAX_CHIPS := 4

## Green used for the terrain-bonus chip (== ConquestTheme.EL_NATURE). Terrain
## avoid is a passive of WHERE the unit stands (tall grass -> +evasion), so it
## reads as "nature" green rather than a status colour to set it apart from the
## StatusVisuals-coloured condition chips.
const TERRAIN_AVOID_COLOR := Color("5fb84e")

var _card: PanelContainer
var _name_label: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _effects_container: HFlowContainer
var _portrait: PanelContainer
var _sub_label: Label
var _hp_value: Label
## Stat name -> value Label in the ATK / DEF / SPD / MOV strip.
var _stat_values: Dictionary = {}
## The unit the card currently describes (see _process: hidden when it duplicates
## the command menu's own header).
var _shown_unit = null


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

	# HP: caption, bar, numbers.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(hp_row)
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.text = "HP"
	_hp_label.theme_type_variation = &"SectionLabel"
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(_hp_label)
	_hp_bar = ConquestTheme.hp_bar(10.0)
	_hp_bar.name = "HPBar"
	_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_hp_value = Label.new()
	_hp_value.name = "HPValue"
	_hp_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(_hp_value)

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
	_hp_value.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_hp_value.add_theme_color_override("font_color", ConquestTheme.CREAM)
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
	var duplicate := false
	var panel := get_tree().get_first_node_in_group("unit_actions_panel") as Control
	if panel != null and panel.is_visible_in_tree():
		var pr := panel.get_global_rect()
		var card_h := _card.size.y
		var card_top := size.y - MARGIN - card_h
		if pr.end.y + 8.0 > card_top:
			want = -(size.x - pr.position.x + 12.0)
			# The command menu already shows this very unit: don't repeat it
			# mid-screen, just step aside.
			duplicate = "selected_unit" in panel and panel.selected_unit != null \
				and panel.selected_unit == _shown_unit
	if not is_equal_approx(_card.offset_right, want):
		_card.offset_right = want
	_card.visible = not duplicate


# --- Public API --------------------------------------------------------------

## Populate and show the card for [param unit]. Hides itself for a null or freed
## unit, so callers never need to branch.
func show_for_unit(unit) -> void:
	if unit == null or typeof(unit) != TYPE_OBJECT or not is_instance_valid(unit):
		hide_panel()
		return

	_shown_unit = unit
	var display := _display_name_of(unit)
	_name_label.text = display
	var owner = ConquestTheme.owner_of(unit)
	var parts: PackedStringArray = [ConquestTheme.side_label(owner)]
	var el := String(unit.get_element()) if unit.has_method("get_element") else ""
	if el != "":
		parts.append(el.capitalize())
	if unit.has_method("is_boss") and unit.is_boss():
		parts.append("Boss")
	_sub_label.text = "  ·  ".join(parts)
	_sub_label.add_theme_color_override("font_color", ConquestTheme.team_text_color(owner))
	var cols := ConquestTheme.unit_portrait_colors(unit)
	ConquestTheme.set_portrait(_portrait, display, cols[0], cols[1])

	# HP is read through `in` guards: a legacy/mock unit with no stats component
	# simply shows a dashed readout instead of erroring.
	var current: int = 0
	var maximum: int = 0
	if "current_health" in unit:
		current = int(unit.current_health)
	if "max_health" in unit:
		maximum = int(unit.max_health)

	if maximum > 0:
		var frac := clampf(float(current) / float(maximum), 0.0, 1.0)
		_hp_value.text = "%d/%d" % [current, maximum]
		_hp_bar.value = frac
		ConquestTheme.tint_hp_bar(_hp_bar, frac)
		_hp_bar.visible = true
	else:
		_hp_value.text = "--/--"
		_hp_bar.value = 0.0
		_hp_bar.visible = false

	for stat_name in _stat_values.keys():
		var lbl: Label = _stat_values[stat_name]
		lbl.text = str(int(unit.get_stat(stat_name))) if unit.has_method("get_stat") else "-"

	# Reveal BEFORE populating statuses: the name/HP rows are already valid, so
	# even if status population ever failed we still surface the unit rather than
	# leaving a wired-but-hidden panel (TerrainInfoPanel records the same lesson).
	show()
	_populate_effects(unit)


## Hide the card. Safe to call repeatedly.
func hide_panel() -> void:
	hide()


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
			_build_chip("✦ Avoid +%d" % terrain_avoid, TERRAIN_AVOID_COLOR,
				"Terrain bonus: +%d evasion while standing on this tile." % terrain_avoid))

	# Empty for a unit with no StatusController, no statuses, or a freed unit.
	var conditions: Array = StatusVisuals.active_conditions(unit)
	if conditions.is_empty():
		# Only claim "no effects" when there is ALSO no terrain bonus to show;
		# otherwise the green terrain chip stands on its own.
		if terrain_avoid <= 0:
			var none_label := Label.new()
			none_label.text = "No status effects"
			none_label.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
			none_label.add_theme_color_override("font_color", ConquestTheme.TEXT_MUTED)
			none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_effects_container.add_child(none_label)
		return

	var total: int = conditions.size()
	var shown: int = StatusVisuals.shown_count(total, MAX_CHIPS)
	var hidden: int = StatusVisuals.hidden_count(total, MAX_CHIPS)

	for i in range(shown):
		var condition = conditions[i]
		if condition == null:
			continue
		var info: Dictionary = StatusVisuals.info_for(condition)
		var color: Color = info.get("color", ConquestTheme.AMBER)
		var kind := String(info.get("kind", "neutral"))
		var glyph := "▲" if kind == "buff" else ("▼" if kind == "debuff" else "●")
		var text: String = "%s %s · %s" % [
			glyph,
			String(info.get("name", "Status")),
			StatusVisuals.turns_label(StatusVisuals.turns_left_of(condition)),
		]
		var desc := StatusVisuals.describe_condition(condition)
		var tip := String(info.get("name", "Status")) + (": " + desc if desc != "" else "")
		tip += " (%s)" % StatusVisuals.turns_label(StatusVisuals.turns_left_of(condition))
		_effects_container.add_child(_build_chip(text, color, tip))

	if hidden > 0:
		_effects_container.add_child(
			_build_chip(StatusVisuals.overflow_label(hidden), StatusVisuals.OVERFLOW_COLOR))


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
	if unit == null:
		hide_panel()
		return

	show_for_unit(unit)
