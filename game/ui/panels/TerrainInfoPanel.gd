extends Control

class_name TerrainInfoPanel

# Fire-Emblem-style TERRAIN / TILE INSPECTION window: a compact, non-modal
# floating overlay that shows the terrain under the board cursor -- its name,
# movement cost, and any active tile effects (fire, empowering water,
# fortify, ...). Updates live as the cursor moves.
#
# Code-built (no .tscn) exactly like MoveSelectionPanel / CombatForecastPanel:
# it is top_level, anchors itself over the battlefield, and calls
# ConquestTheme.apply_to(self) for the amber HUD look. Like CombatForecastPanel
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

const PANEL_WIDTH := 260.0
const MARGIN := 16.0

var _card: PanelContainer
var _name_label: Label
var _move_label: Label
var _effects_header: Label
var _effects_container: VBoxContainer

# Sentinel so the very first _on_cursor_moved always does a fresh lookup.
var _current_cell: Vector2i = Vector2i(-999999, -999999)


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


## Pin our rect to the whole viewport so the bottom-left-anchored card lands on
## screen. A top_level Control ignores its parent, so it will not size itself.
func _fit_to_viewport() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	position = Vector2.ZERO
	size = vp.get_visible_rect().size


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
	_card.offset_bottom = -MARGIN
	_card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 4)
	root_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(root_vb)

	_name_label = Label.new()
	_name_label.name = "TerrainNameLabel"
	_name_label.text = "Terrain"
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_name_label)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(sep)

	_move_label = Label.new()
	_move_label.name = "MoveCostLabel"
	_move_label.text = "Move Cost: --"
	_move_label.add_theme_font_size_override("font_size", 14)
	_move_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_move_label)

	_effects_header = Label.new()
	_effects_header.name = "EffectsHeader"
	_effects_header.text = "Effects:"
	_effects_header.add_theme_font_size_override("font_size", 13)
	_effects_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_header)

	_effects_container = VBoxContainer.new()
	_effects_container.name = "EffectsContainer"
	_effects_container.add_theme_constant_override("separation", 2)
	_effects_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vb.add_child(_effects_container)

	# Amber HUD look, applied last (see CombatForecastPanel._create_ui) so it
	# doesn't get stripped by any later local overrides.
	ConquestTheme.apply_to(self)


# --- Public API --------------------------------------------------------------

## Populate and show the panel for a specific board cell. Hides itself (and
## returns) when the cell has no registered terrain -- e.g. off the loaded
## map, or no map/board loaded yet.
func show_for_cell(cell: Vector2i) -> void:
	# NOTE: a null tile here means the cursor is on an IN-BOUNDS cell whose terrain
	# isn't registered (a registry miss), NOT off-board -- _on_cursor_moved already
	# rejected off-board cells. Blanking the whole panel in that case was the
	# "hovering shows no UI" symptom, so instead show the cell as Unknown Terrain
	# and still surface any tile effects. The panel appears whenever the cursor is
	# over the board.
	var tile: TileResource = CombatServices.tile_at(cell)

	_current_cell = cell

	if tile != null:
		_name_label.text = tile.tile_name if tile.tile_name != "" else "Unknown Terrain"
		if tile.is_tile_passable():
			_move_label.text = "Move Cost: %d" % maxi(1, tile.base_movement_cost)
		else:
			_move_label.text = "Move Cost: -- (Impassable)"
	else:
		_name_label.text = "Unknown Terrain"
		_move_label.text = "Move Cost: 1"

	# Reveal BEFORE populating effects: the name/move rows are already valid, so
	# even if effect population ever failed we still surface the terrain instead of
	# leaving a wired-but-hidden panel (the reported "never appears" symptom).
	show()
	_populate_effects(cell)


## Hide the panel and reset its tracked cell so the next show_for_cell always
## repopulates fresh.
func hide_panel() -> void:
	_current_cell = Vector2i(-999999, -999999)
	hide()


# --- Internals -----------------------------------------------------------------

func _populate_effects(cell: Vector2i) -> void:
	for child in _effects_container.get_children():
		child.queue_free()

	# ALL effects (base terrain + runtime), plus the runtime-only set so we can flag
	# which chips are temporary. A tile can now hold several at once (e.g. tall
	# grass + a fire ignited on top), and each gets its own colour-coded chip.
	var effects: Array = CombatServices.tile_effects_at(cell)
	var applied: Array = CombatServices.applied_tile_effects_at(cell)

	if effects.is_empty():
		var none_label := Label.new()
		none_label.text = "No special effects"
		none_label.add_theme_font_size_override("font_size", 13)
		# Muted so the "nothing here" state reads as secondary, not a real effect.
		none_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)
		none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_effects_container.add_child(none_label)
		return

	for te in effects:
		if te == null:
			continue
		# Temporary iff this effect is in the runtime (applied-this-battle) set --
		# i.e. NOT an inherent terrain effect.
		_effects_container.add_child(_build_effect_chip(te, te in applied))


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
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Dim fill + effect-colour frame, rounded to match the amber HUD's soft corners.
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.35)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(1)
	sb.border_color = color
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(hb)

	# Tiny colour swatch echoing the effect colour (and the 3D overlay pip).
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(10, 10)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(swatch)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 13)
	# CREAM reads clearly on the dim (darkened) chip fill, unlike the theme's
	# default INK which is tuned for the light amber panel background.
	label.add_theme_color_override("font_color", ConquestTheme.CREAM)
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
	var cell := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

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
