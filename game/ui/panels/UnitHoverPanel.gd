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

var _card: PanelContainer
var _name_label: Label
var _hp_label: Label
var _hp_bar: ProgressBar
var _effects_container: HFlowContainer


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

	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.text = "HP --/--"
	_hp_label.add_theme_font_size_override("font_size", 13)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_hp_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HPBar"
	_hp_bar.custom_minimum_size = Vector2(0, 10)
	_hp_bar.show_percentage = false
	_hp_bar.min_value = 0.0
	_hp_bar.max_value = 1.0
	_hp_bar.value = 1.0
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_hp_bar)

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

	_name_label.text = _display_name_of(unit)

	# HP is read through `in` guards: a legacy/mock unit with no stats component
	# simply shows a dashed readout instead of erroring.
	var current: int = 0
	var maximum: int = 0
	if "current_health" in unit:
		current = int(unit.current_health)
	if "max_health" in unit:
		maximum = int(unit.max_health)

	if maximum > 0:
		_hp_label.text = "HP %d/%d" % [current, maximum]
		_hp_bar.value = clampf(float(current) / float(maximum), 0.0, 1.0)
		_hp_bar.visible = true
	else:
		_hp_label.text = "HP --/--"
		_hp_bar.value = 0.0
		_hp_bar.visible = false

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

	# Empty for a unit with no StatusController, no statuses, or a freed unit.
	var conditions: Array = StatusVisuals.active_conditions(unit)
	if conditions.is_empty():
		var none_label := Label.new()
		none_label.text = "No active effects"
		none_label.add_theme_font_size_override("font_size", 12)
		none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
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
		var text: String = "%s · %s" % [
			String(info.get("name", "Status")),
			StatusVisuals.turns_label(StatusVisuals.turns_left_of(condition)),
		]
		_effects_container.add_child(_build_chip(text, color))

	if hidden > 0:
		_effects_container.add_child(
			_build_chip(StatusVisuals.overflow_label(hidden), StatusVisuals.OVERFLOW_COLOR))


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
	if unit == null:
		hide_panel()
		return

	show_for_unit(unit)
