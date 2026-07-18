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
	set_anchors_preset(Control.PRESET_FULL_RECT)

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
	var tile: TileResource = CombatServices.tile_at(cell)
	if tile == null:
		hide_panel()
		return

	_current_cell = cell

	_name_label.text = tile.tile_name if tile.tile_name != "" else "Unknown Terrain"

	if tile.is_tile_passable():
		_move_label.text = "Move Cost: %d" % maxi(1, tile.base_movement_cost)
	else:
		_move_label.text = "Move Cost: -- (Impassable)"

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

	var effects: Array = CombatServices.tile_effects_at(cell)

	if effects.is_empty():
		var none_label := Label.new()
		none_label.text = "No effects"
		none_label.add_theme_font_size_override("font_size", 13)
		none_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_effects_container.add_child(none_label)
		return

	for te in effects:
		if te == null:
			continue
		var line := Label.new()
		line.text = "• " + _describe_effect(te)
		line.add_theme_font_size_override("font_size", 13)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_effects_container.add_child(line)


## Short human label for a TileEffectResource, e.g. "Fire: Deal 15 physical
## damage" or "Empowering Water: +4 attack for 1 turns". Falls back to just
## the display_name/id when the effect exposes nothing describable.
func _describe_effect(te: TileEffectResource) -> String:
	var label := te.display_name
	if label == "":
		label = String(te.id) if te.id != &"" else "Effect"

	var detail := ""
	if te.effects != null and not te.effects.is_empty():
		var first: MoveEffect = te.effects[0]
		if first != null and first.has_method("describe"):
			var d: String = first.describe()
			if d != "":
				detail = d

	if detail != "":
		return "%s: %s" % [label, detail]
	return label


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
