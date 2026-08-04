extends GutTest

# WHAT THE PLAYER IS TOLD BEFORE THEY CONFIRM A MOVE ACROSS A TRAP.
#
# Traps spring where you STEP (CONQUEST.md rule 10), which means a route can cost a move the
# player never aimed for: the destination tile is clean, but a trap two cells back catches
# the unit on the way. Traps are VISIBLE tiles, so nothing here reveals a secret -- it just
# refuses to let the confirm be a surprise. Two guarantees, both measured on the REAL
# mounted GameUILayout rather than on a helper:
#
#   * the WARNING LINE renders, inside the sidebar, in a glyph the theme font can draw;
#   * the GHOST -- which in this game's Fire-Emblem loop is the unit itself at its pending
#     position -- stands on the cell the move will ACTUALLY end on, not the one clicked.
#
# A helper-static version of these assertions passed while the live screen was wrong before
# (see tests/README and the project's UI-test rule), so every assertion below reads a node
# that the booted layout actually laid out.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const CHARACTER_UNIT_SCENE := preload("res://game/characters/CharacterUnit.tscn")
const GRID: Grid = preload("res://board/Grid.tres")

const MOVER_ID := &"vineweave"
const DESIGN := Vector2i(1280, 720)

const START := Vector2i(0, 0)
const TRAP_CELL := Vector2i(1, 0)

## Where the fixture aims the move: the far end of the corridor within the mover's OWN
## movement budget, read off its profile rather than hard-coded, so retuning the roster
## character's movement stat cannot silently turn these tests into no-ops (an unreachable
## destination derives no route, which would pass every "no trap" assertion vacuously).
var _aimed: Vector2i = Vector2i(3, 0)

var _prev_window_size: Vector2i
var _map_root: Node3D = null


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	_map_root = null


# --- Fixtures ----------------------------------------------------------------

func _cell_to_world(cell: Vector2i) -> Vector3:
	return GRID.calculate_map_position(Vector3(cell.x, 0, cell.y))


## A live one-unit board with an armed Vine Trap at TRAP_CELL, laid by the OTHER side so it
## really is hostile to the mover. Returns {} when the roster character cannot load, which
## callers turn into a pending() rather than a false pass (tests/README rule 8).
func _build_board() -> Dictionary:
	var character := CharacterLibrary.get_character(MOVER_ID)
	if character == null:
		return {}

	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var human := Player.new(0, "Human")
	var foe := Player.new(1, "Foe")

	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character
	unit.position = _cell_to_world(START)
	_map_root.add_child(unit)
	human.add_unit(unit)

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	var board = CombatServices.board()
	if board == null:
		return {}

	var profile: MovementProfile = unit.get_movement_profile()
	if profile == null:
		return {}
	_aimed = Vector2i(clampi(profile.range, 2, 4), 0)
	gut.p("mover: movement profile range=%d, aiming at %s over a trap at %s"
		% [profile.range, _aimed, TRAP_CELL])
	# A destination the unit cannot actually walk to would make every assertion below
	# vacuous, so prove the corridor is real before anything is measured against it.
	var route: Array[Vector2i] = MovementResolver.new().path_cells(START, _aimed, profile, board, unit)
	if route.is_empty() or not route.has(TRAP_CELL):
		return {}

	var trap: TileEffectResource = (load("res://game/tiles/effects/resources/vine_trap.tres") as TileEffectResource).duplicate()
	trap.owner_player = foe
	CombatServices.add_tile_effect(TRAP_CELL, trap)

	return { "unit": unit, "board": board, "trap": trap, "player": human }


## The booted HUD, with every deferred re-budget / re-fit settled.
func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for _i in range(8):
		await get_tree().process_frame
	return layout


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)


# --- The warning line --------------------------------------------------------

func test_the_route_warning_renders_in_the_real_sidebar() -> void:
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return
	var layout: Control = await _build_hud()
	var panel = layout.unit_actions_panel

	var label: Label = panel.trap_warning_label
	assert_not_null(label, "the sidebar owns a trap warning line")
	assert_false(label.visible, "which says nothing until a route actually crosses a trap")

	# Sweep the cursor onto a destination whose route crosses the trap, with the sidebar up
	# exactly as selecting a unit puts it up -- the line has to be readable on the real
	# screen, not merely flagged visible inside a hidden panel.
	panel.selected_unit = scene["unit"]
	panel.movement_mode = true
	panel.movement_range_tiles = [Vector3(_aimed.x, 0, _aimed.y)] as Array[Vector3]
	panel._show_panel()
	panel._refresh_trap_warning(Vector3(_aimed.x, 0, _aimed.y))
	for _i in range(6):
		await get_tree().process_frame

	assert_true(label.visible, "the warning appears BEFORE the move is confirmed")
	assert_true(label.text.contains("Vine Trap"),
		"and names the trap the route springs (got: '%s')" % label.text)
	assert_true(label.text.begins_with(UnitActionsPanel.TRAP_WARNING_MARK),
		"led by the caution mark")
	gut.p("warning line: '%s'" % label.text)

	# Rendered, not merely flagged visible: a real rect, inside the real sidebar.
	assert_true(label.is_visible_in_tree(), "the line is visible through the whole booted HUD")
	assert_gt(label.size.x, 100.0, "it occupies the sidebar's content width, so the line is readable")
	assert_gt(label.size.y, 0.0, "and real height")
	var panel_rect: Rect2 = _rect_of(panel)
	var label_rect: Rect2 = _rect_of(label)
	gut.p("sidebar %s / warning %s" % [panel_rect, label_rect])
	assert_true(panel_rect.encloses(label_rect),
		"and sits inside the sidebar rather than spilling out of it")


func test_the_warning_uses_only_glyphs_the_theme_font_can_draw() -> void:
	# This project has shipped tofu twice (see the probe table in unit/test_status_feedback).
	# A warning the player cannot read is worse than no warning, so the mark is pinned.
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to measure against")
	if font == null:
		return
	for i in range(UnitActionsPanel.TRAP_WARNING_MARK.length()):
		var code: int = UnitActionsPanel.TRAP_WARNING_MARK.unicode_at(i)
		assert_true(font.has_char(code),
			"the theme font can draw the caution mark (U+%04X)" % code)
	assert_gt(font.get_string_size(
			UnitActionsPanel.TRAP_WARNING_MARK, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 0.0,
		"and it occupies real width at the warning's 13px size")


func test_a_clear_route_leaves_the_warning_silent() -> void:
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return
	var layout: Control = await _build_hud()
	var panel = layout.unit_actions_panel

	panel.selected_unit = scene["unit"]
	panel.movement_mode = true
	# Straight down the other column -- never touches TRAP_CELL.
	panel.movement_range_tiles = [Vector3(0, 0, 3)] as Array[Vector3]
	panel._refresh_trap_warning(Vector3(0, 0, 3))
	for _i in range(4):
		await get_tree().process_frame

	assert_false(panel.trap_warning_label.visible,
		"a route that never steps on the trap has nothing to warn about")


# --- The ghost ---------------------------------------------------------------

func test_the_pending_move_stands_on_the_cell_it_will_really_stop_on() -> void:
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return
	var layout: Control = await _build_hud()
	var panel = layout.unit_actions_panel
	var unit: Unit = scene["unit"]
	var board = scene["board"]

	panel.selected_unit = unit
	panel.movement_mode = true
	panel.movement_range_tiles = [Vector3(_aimed.x, 0, _aimed.y)] as Array[Vector3]
	panel._begin_tentative_move(Vector3(_aimed.x, 0, _aimed.y))
	for _i in range(4):
		await get_tree().process_frame

	assert_true(panel.is_tentative_move_active(), "a tentative move is staged")
	assert_eq(board.cell_of(unit), TRAP_CELL,
		"the ghost stands ON the trap -- the cell the move actually ends on, not the one clicked")
	assert_eq(panel._tentative_dest_cell, TRAP_CELL,
		"and the pending destination the confirm will commit is that same cell")
	assert_true(panel.trap_warning_label.visible,
		"with the warning still standing while the player decides")


func test_the_warning_goes_when_the_staged_move_is_cancelled() -> void:
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return
	var layout: Control = await _build_hud()
	var panel = layout.unit_actions_panel

	panel.selected_unit = scene["unit"]
	panel.movement_mode = true
	panel.movement_range_tiles = [Vector3(_aimed.x, 0, _aimed.y)] as Array[Vector3]
	panel._begin_tentative_move(Vector3(_aimed.x, 0, _aimed.y))
	panel._revert_tentative_move()
	for _i in range(4):
		await get_tree().process_frame

	assert_false(panel.trap_warning_label.visible,
		"the warning belonged to the staged move and goes with it")
	assert_eq(scene["board"].cell_of(scene["unit"]), START,
		"and the unit is back where it started -- nothing was committed")


# --- The terrain card --------------------------------------------------------

func test_the_terrain_card_says_a_trapped_tile_is_a_trap() -> void:
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return

	var card: TerrainInfoPanel = TerrainInfoPanel.new()
	add_child_autofree(card)
	for _i in range(4):
		await get_tree().process_frame

	card.show_for_cell(TRAP_CELL)
	for _i in range(4):
		await get_tree().process_frame

	var line: Label = _find_label(card, "TrapLabel")
	assert_not_null(line, "the terrain card carries a trap row")
	if line == null:
		return
	assert_true(line.visible, "which is shown for a tile carrying a trap")
	assert_eq(line.text, TileEffectResource.TRAP_DESCRIPTOR,
		"quoting the resource's own descriptor rather than wording of its own")
	gut.p("terrain trap row: '%s'" % line.text)

	# The card's whole point is that it fits the HUD's bottom-left reserve.
	var panel_card: Control = card.get_child(0)
	assert_true(panel_card.size.y <= TerrainInfoPanel.MAX_HEIGHT + 0.5,
		"and the extra row is absorbed by the effects scroll, not by growing the card (got %.1f)"
			% panel_card.size.y)

	card.show_for_cell(Vector2i(5, 5))
	for _i in range(4):
		await get_tree().process_frame
	assert_false(line.visible, "an ordinary tile prints no trap row at all")


# --- The replay / networked apply path ---------------------------------------

func test_an_applied_move_command_truncates_exactly_like_a_local_one() -> void:
	# THE REPLAY AND LOCKSTEP GUARANTEE. A MOVE_UNIT command carries a DESTINATION and
	# nothing else, so a replay (ReplayDriver -> CommandApplier) and a remote peer both
	# re-derive the route themselves. This walks the real applier and then hands the move it
	# announced to the real seam GameWorldManager hangs off GameEvents.unit_moved -- if those
	# two ever stop agreeing, a replay diverges from the match it recorded.
	var scene: Dictionary = await _build_board()
	if scene.is_empty():
		pending("Could not load the roster character / live board; skipping.")
		return
	var unit: Unit = scene["unit"]
	var board = scene["board"]

	var registry := CommandApplier.UnitRegistry.new()
	registry.register(unit, 1)
	var applier := CommandApplier.new(registry)

	# GUT lambdas capture by VALUE, so the announcement is collected into an Array.
	var announced: Array = []
	var sink := func(moved, from_grid, to_grid) -> void:
		if moved == unit:
			announced.append([from_grid, to_grid])
	GameEvents.unit_moved.connect(sink)

	var result: Dictionary = applier.apply_command(
		NetProtocol.make_move_unit(1, _aimed), board)
	GameEvents.unit_moved.disconnect(sink)

	assert_true(bool(result.get("ok", false)), "the applier accepted the move command")
	assert_eq(announced.size(), 1, "and announced it exactly once, as every peer does")
	if announced.is_empty():
		return

	# What GameWorldManager._on_unit_moved_tile_effects does with that announcement.
	var from_cell := Vector2i(int(round(announced[0][0].x)), int(round(announced[0][0].z)))
	var to_cell := Vector2i(int(round(announced[0][1].x)), int(round(announced[0][1].z)))
	assert_eq(from_cell, START, "the announcement is in GRID space, from the origin cell")
	assert_eq(to_cell, _aimed, "to the destination the command carried")

	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	var landed: Vector2i = system.apply_move(unit, from_cell, to_cell, board)

	assert_eq(landed, TRAP_CELL, "an applied command truncates on the trap, same as a local move")
	assert_eq(board.cell_of(unit), TRAP_CELL, "and the applied board state ends there too")


## Depth-first search for a named Label, so the assertion does not depend on the card's
## internal container path (which is code-built and unnamed at the VBox level).
func _find_label(node: Node, wanted: String) -> Label:
	for child in node.get_children():
		if child is Label and child.name == wanted:
			return child as Label
		var found := _find_label(child, wanted)
		if found != null:
			return found
	return null
