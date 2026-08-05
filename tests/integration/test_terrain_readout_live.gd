extends GutTest

## THE TERRAIN CHIP, ON THE THREE SURFACES A UNIT IS DRAWN ON -- all of them mounted, live,
## and measured rather than described.
##
## THE REPORT: "when standing on a tile with an effect such as tall grass maybe there should
## be a visual indicator that shows their evasive." Terrain bonuses are computed at combat
## time and stored nowhere (see [TerrainStats]), so every readout of them lived on the TILE
## card -- the unit itself wore nothing, on the map or in the panels.
##
## Every assertion below is taken off a REAL board (a live [CombatServices] adapter with a
## real [Unit] standing on a real `tall_grass.tres`), through the beat the game actually
## uses ([signal GameEvents.unit_moved]), and read off RENDERED nodes:
##
##   * the world-space badge row on [HealthBar] -- the plate is measured against the width
##     the string it carries actually draws at, because a chip narrower than its own text is
##     the "small coloured dot" this project has already shipped twice;
##   * the compact battle card ([UnitInfoPanel]) booted from the real GameUILayout.tscn;
##   * the hover card ([UnitHoverPanel]).
##
## And the number is the ELEMENT-BOOSTED one throughout: the fixture unit is NATURE standing
## in NATURE tall grass, so every surface must say +19, which is the avoid an attacker's
## forecast has to beat -- not the authored +15 (CONQUEST.md rule 9).

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const HEALTH_BAR := preload("res://game/visuals/HealthBar.tscn")
const HOVER_PANEL := preload("res://game/ui/panels/UnitHoverPanel.gd")

const GRASS_TILE := "res://game/tiles/effects/resources/tall_grass.tres"

const DESIGN := Vector2i(1280, 720)

## Cells on the 5x5 board in `board/Grid.tres`. GRASS_CELL carries the tall grass;
## BARE_CELL is plain ground, so stepping between them is the whole test.
const GRASS_CELL := Vector2i(2, 2)
const BARE_CELL := Vector2i(0, 0)

## 15 authored x 1.25 (nature unit in nature grass) = 18.75 -> 19. Pinned as a constant so a
## content retune fails LOUDLY here rather than quietly weakening every assertion.
const BOOSTED_AVOID := 19

var _prev_window_size: Vector2i
var _map_root: Node3D = null


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func before_each() -> void:
	# CombatServices is an AUTOLOAD (tests/README.md rule 3): cleared in BOTH hooks so
	# neither a previous suite's board nor this suite's tile effects leak either way.
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	ElementChart.reset_chart()
	_map_root = null
	# The chip rows detach their children with queue_free, which is deferred; GUT counts
	# orphans before the frame ends.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Fixtures ------------------------------------------------------------------

## World centre of [param cell] on the shared grid, so a unit placed there round-trips
## through [method BoardAdapter.cell_of] (and through CombatServices' own startup assertion,
## which would otherwise push a warning and fail the test).
func _world_of(cell: Vector2i) -> Vector3:
	return CombatServices.GRID.calculate_map_position(Vector3(cell.x, 0, cell.y))


func _character(element: StringName) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald"
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = 3
	c.element = element
	return c


## A LIVE board: a "Map" root holding one real [Unit] of [param element] standing on
## [param cell], with tall grass applied to GRASS_CELL through the same
## [method CombatServices.add_tile_effect] a move that transformed terrain would use.
## Returns the unit.
func _board_with_unit(element: StringName, cell: Vector2i) -> Unit:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var unit := Unit.new()
	unit.character_resource = _character(element)
	_map_root.add_child(unit)   # freed with the map root -- one autofree covers both
	unit.position = _world_of(cell)

	CombatServices.rebuild(_map_root)
	CombatServices.add_tile_effect(GRASS_CELL, load(GRASS_TILE))
	return unit


## Walk [param unit] to [param cell] the way the game does: reposition it on the board, then
## announce it on [signal GameEvents.unit_moved] -- the beat every terrain readout rides.
func _walk(unit: Unit, cell: Vector2i) -> void:
	var from: Vector3 = unit.position
	unit.position = _world_of(cell)
	GameEvents.unit_moved.emit(unit, from, unit.position)
	for i in range(4):
		await get_tree().process_frame


# --- Rendering helpers ----------------------------------------------------------

## The width [param label]'s own text needs at the size it is actually drawn.
func _text_width(label: Label) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x


## The same measurement for a [Label3D], in WORLD units: a Label3D maps
## `font_size * pixel_size` onto world space, and with no font of its own it draws with
## [code]ThemeDB.fallback_font[/code] -- which is exactly the font with no fallback chain
## that made this project's original ◆▲●▼■ glyphs render as tofu boxes over every unit.
func _label3d_font(label: Label3D) -> Font:
	return label.font if label.font != null else ThemeDB.fallback_font


func _label3d_world_width(label: Label3D) -> float:
	var font: Font = _label3d_font(label)
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.font_size).x * label.pixel_size


func _bar_terrain_plates(bar: Node3D) -> Array:
	return bar._status_root.find_children("TerrainChip*", "MeshInstance3D", true, false)


func _bar_terrain_labels(bar: Node3D) -> Array:
	return bar._status_root.find_children("TerrainChipLabel*", "Label3D", true, false)


func _panel_terrain_chips(container: Node) -> Array:
	return container.find_children("TerrainChip*", "PanelContainer", true, false)


func _mount_bar(unit: Unit) -> Node3D:
	var bar: Node3D = HEALTH_BAR.instantiate()
	add_child_autofree(bar)           # entering the tree runs _ready
	bar.bind_unit(unit)
	await get_tree().process_frame
	return bar


func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


func _select(unit: Unit) -> void:
	GameEvents.unit_selected.emit(unit, Vector3.ZERO)
	for i in range(6):
		await get_tree().process_frame


func _mount_hover() -> Control:
	var panel := Control.new()
	panel.set_script(HOVER_PANEL)
	add_child_autofree(panel)
	for i in range(4):
		await get_tree().process_frame
	return panel


# ==============================================================================
# 0. The fixture really is a live board with real terrain on it
# ==============================================================================

func test_the_fixture_grants_the_element_boosted_avoid_through_the_live_board() -> void:
	# If this fails, every assertion below proves nothing: there would be no bonus to draw.
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var board = CombatServices.board()
	assert_not_null(board, "the suite is running against a real BoardAdapter")
	assert_eq(board.cell_of(unit), GRASS_CELL, "with the unit really standing on the grass")
	assert_eq(TerrainStats.bonus_for(unit, "evasion", board), BOOSTED_AVOID,
		"a nature unit in nature tall grass: +15 x 1.25 = +19 avoid")


func test_the_forecast_already_prices_the_boosted_terrain_avoid() -> void:
	# CONQUEST.md rule 9, on the live board: MoveExecutor.preview_vs adds
	# TerrainStats.bonus_for(target, "evasion") -- with NO board argument, so it resolves the
	# same live CombatServices the chip reads. Nothing had to be added for this; the point of
	# the assertion is that the number the chip advertises is the number the card quotes.
	var target := _board_with_unit(&"nature", GRASS_CELL)
	var attacker := Unit.new()
	attacker.character_resource = _character(&"fire")
	_map_root.add_child(attacker)
	attacker.position = _world_of(BARE_CELL)
	CombatServices.rebuild(_map_root)

	var move := MoveResource.new()
	move.move_id = &"probe"
	move.accuracy = 1.0
	var preview: Dictionary = MoveExecutor.preview_vs(move, attacker, target,
		CombatServices.board())
	gut.p("forecast    : hit %.1f%% vs a unit wearing %s"
		% [float(preview.get("hit_pct", 0.0)),
		TerrainVisuals.chip_text(TerrainVisuals.bonuses_for(target, CombatServices.board())[0])])
	assert_eq(float(preview.get("hit_pct", 0.0)), 100.0 - float(BOOSTED_AVOID),
		"the forecast a player reads already subtracts the BOOSTED terrain avoid, so the "
		+ "chip and the hit chance can never disagree")


# ==============================================================================
# 1. The world-space badge row
# ==============================================================================

func test_the_world_bar_wears_a_terrain_chip_with_the_real_number() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var bar: Node3D = await _mount_bar(unit)

	var labels: Array = _bar_terrain_labels(bar)
	assert_eq(labels.size(), 1, "one stat is moving, so the row carries one terrain chip")
	if labels.is_empty():
		return
	var label := labels[0] as Label3D
	gut.p("world chip  : '%s'" % label.text)
	assert_eq(label.text, "±AVO+%d" % BOOSTED_AVOID,
		"and it names the mark, the stat and the boosted number: %s" % label.text)
	assert_eq(label.modulate, TerrainVisuals.GAIN_COLOR,
		"tinted with the terrain green, because this is a gain")


func test_the_world_chip_plate_is_wider_than_the_text_it_draws() -> void:
	# THE recurring failure on this project's chips, stated as geometry. A plate narrower
	# than its own string is a coloured smudge over the unit's head, and a string assertion
	# cannot see it.
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var bar: Node3D = await _mount_bar(unit)

	var plates: Array = _bar_terrain_plates(bar)
	var labels: Array = _bar_terrain_labels(bar)
	assert_eq(plates.size(), 1, "the chip has a plate behind its text")
	assert_eq(labels.size(), 1, "and text on the plate")
	if plates.is_empty() or labels.is_empty():
		return

	var label := labels[0] as Label3D
	var mesh := (plates[0] as MeshInstance3D).mesh as QuadMesh
	var needed: float = _label3d_world_width(label)
	gut.p("world plate : %.3f wide, '%s' needs %.3f" % [mesh.size.x, label.text, needed])
	assert_true(needed > 0.0, "the chip has real text to draw")
	assert_true(mesh.size.x >= needed,
		"the plate (%.3f) is at least as wide as its string (%.3f) -- anything narrower is "
		% [mesh.size.x, needed] + "the coloured dot this project has already shipped twice")


func test_the_font_the_world_chip_is_drawn_with_can_draw_the_terrain_mark() -> void:
	# THE TOFU PIN. A Label3D over the battlefield has NO font fallback at all, so a mark
	# the theme font lacks is a literal box over every unit standing on terrain. This is why
	# TerrainVisuals.MARK is a MEASURED choice and not a taste one.
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var bar: Node3D = await _mount_bar(unit)

	var labels: Array = _bar_terrain_labels(bar)
	assert_false(labels.is_empty(), "there is a rendered chip to inspect")
	if labels.is_empty():
		return
	var label := labels[0] as Label3D
	var font: Font = _label3d_font(label)
	assert_not_null(font, "the mounted chip resolves a real font")
	if font == null:
		return

	var code: int = TerrainVisuals.MARK.unicode_at(0)
	gut.p("mark        : '%s' U+%04X" % [TerrainVisuals.MARK, code])
	assert_true(label.text.begins_with(TerrainVisuals.MARK),
		"the rendered chip leads with the terrain mark: %s" % label.text)
	assert_true(font.has_char(code),
		"and the font it is drawn with can draw '%s' (U+%04X)" % [TerrainVisuals.MARK, code])
	assert_true(font.get_string_size(TerrainVisuals.MARK, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.font_size).x > 0.0, "occupying real width at the chip's own font size")


func test_walking_off_the_grass_takes_the_world_chip_away() -> void:
	# The beat, end to end: GameEvents.unit_moved is what makes the chip appear the instant
	# a unit steps into grass and vanish when it steps out.
	var unit := _board_with_unit(&"nature", BARE_CELL)
	var bar: Node3D = await _mount_bar(unit)
	assert_true(_bar_terrain_labels(bar).is_empty(),
		"a unit on bare earth wears nothing -- the row is exactly what it always was")

	await _walk(unit, GRASS_CELL)
	assert_eq(_bar_terrain_labels(bar).size(), 1,
		"stepping into the grass puts the chip on the bar, with no turn or HP change")

	await _walk(unit, BARE_CELL)
	assert_true(_bar_terrain_labels(bar).is_empty(), "and stepping out takes it away again")


func test_a_terrain_chip_and_a_status_badge_are_told_apart_by_more_than_colour() -> void:
	# They share one row, so if they shared a recipe the player would read "standing in
	# grass" and "poisoned" as the same kind of fact. Terrain is a WIDE dark plate with
	# coloured ink; a status is a SQUARE coloured chip with dark ink.
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var poison := StatusCondition.new()
	poison.id = &"poisoned"
	poison.display_name = "Poisoned"
	poison.duration_turns = 2
	unit.get_status_controller().add_status(poison)
	var bar: Node3D = await _mount_bar(unit)

	var plates: Array = _bar_terrain_plates(bar)
	assert_eq(plates.size(), 1, "the terrain chip is on the row")
	var all_quads: Array = bar._status_root.find_children("*", "MeshInstance3D", true, false)
	assert_eq(all_quads.size(), 2, "beside exactly one status badge")
	if plates.is_empty() or all_quads.size() < 2:
		return

	var terrain_plate := plates[0] as MeshInstance3D
	var status_pip: MeshInstance3D = null
	for quad in all_quads:
		if quad != terrain_plate:
			status_pip = quad as MeshInstance3D
	gut.p("terrain     : %s   status: %s"
		% [(terrain_plate.mesh as QuadMesh).size, (status_pip.mesh as QuadMesh).size])
	assert_true((terrain_plate.mesh as QuadMesh).size.x > (status_pip.mesh as QuadMesh).size.x,
		"the terrain chip is the wider of the two, so shape alone separates them")
	assert_true(terrain_plate.material_override.albedo_color.get_luminance()
			< status_pip.material_override.albedo_color.get_luminance(),
		"and it is a DARK plate against the status badge's bright chip -- figure/ground, "
		+ "which survives colour blindness and map distance")


# ==============================================================================
# 2. The compact battle card, booted from the real HUD
# ==============================================================================

func test_the_live_card_shows_a_terrain_chip_the_moment_the_unit_walks_into_grass() -> void:
	var unit := _board_with_unit(&"nature", BARE_CELL)
	var layout: Control = await _build_hud()
	await _select(unit)

	var card = layout.unit_info_panel
	assert_true(card.visible, "the card is on screen for the selected unit")
	assert_true(_panel_terrain_chips(card).is_empty(),
		"and shows no terrain chip while the unit stands on bare earth")

	await _walk(unit, GRASS_CELL)
	var chips: Array = _panel_terrain_chips(card)
	assert_eq(chips.size(), 1, "walking into the grass puts one terrain chip on the card")
	if chips.is_empty():
		return
	var label := (chips[0] as Control).get_node("TerrainChipLabel") as Label
	gut.p("card chip   : '%s'  tooltip: '%s'" % [label.text, (chips[0] as Control).tooltip_text])
	assert_eq(label.text, "±AVO+%d" % BOOSTED_AVOID,
		"carrying the boosted number, not the authored +15: %s" % label.text)

	await _walk(unit, BARE_CELL)
	assert_true(_panel_terrain_chips(card).is_empty(),
		"and walking back out takes it off again")


func test_the_cards_terrain_chip_is_drawn_wide_enough_to_read() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var layout: Control = await _build_hud()
	await _select(unit)

	var chips: Array = _panel_terrain_chips(layout.unit_info_panel)
	assert_eq(chips.size(), 1, "there is a rendered chip to measure")
	if chips.is_empty():
		return
	var chip := chips[0] as Control
	var label := chip.get_node("TerrainChipLabel") as Label
	var needed: float = _text_width(label)
	gut.p("card chip   : chip=%s label=%.1f needs=%.1f for '%s'"
		% [chip.size, label.size.x, needed, label.text])
	assert_true(needed > 0.0, "the chip's label has real text to draw")
	assert_true(label.size.x >= needed - 1.0,
		"the label is laid out at least as wide as its own text (%.1f >= %.1f)"
		% [label.size.x, needed])
	assert_true(chip.size.x >= needed, "and the pill around it is wider still")


func test_the_cards_terrain_chip_elaborates_on_hover() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var layout: Control = await _build_hud()
	await _select(unit)

	var chips: Array = _panel_terrain_chips(layout.unit_info_panel)
	assert_false(chips.is_empty(), "there is a chip to hover")
	if chips.is_empty():
		return
	var chip := chips[0] as Control
	var tip: String = chip.tooltip_text
	assert_true(tip.contains("Tall Grass"), "the tooltip names the terrain: %s" % tip)
	assert_true(tip.contains("+%d" % BOOSTED_AVOID),
		"quotes the number the unit actually has: %s" % tip)
	assert_true(tip.contains("evasion"), "names the stat: %s" % tip)
	assert_true(tip.contains("while standing here"),
		"and says it lasts only while the unit stands there: %s" % tip)
	assert_ne(chip.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"and the chip accepts the hover, or the tooltip can never be shown")


func test_the_terrain_chip_never_pushes_the_card_past_its_pinned_height() -> void:
	# The card's height is PINNED (UnitInfoPanel.CARD_HEIGHT); the strip is two rows and
	# terrain chips spend from the same slot budget statuses do. Worst realistic case:
	# terrain plus a full complement of conditions.
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var controller = unit.get_status_controller()
	for spec in [[&"poisoned", "Poisoned"], [&"burn", "Burn"],
			[&"hastened", "Hastened"], [&"fortified", "Fortified"]]:
		var c := StatusCondition.new()
		c.id = spec[0]
		c.display_name = String(spec[1])
		c.duration_turns = 2
		controller.add_status(c)
	var layout: Control = await _build_hud()
	await _select(unit)

	var card = layout.unit_info_panel
	var flow: Control = card._status_flow
	gut.p("crowded strip: %d chips, card claims %.1f of %.1f"
		% [flow.get_child_count(), card.fixed_content_height(), UnitInfoPanel.CARD_HEIGHT])
	assert_eq(_panel_terrain_chips(card).size(), 1, "the terrain chip is not the one dropped")
	assert_true(flow.get_child_count() <= UnitInfoPanel.MAX_STATUS_CHIPS,
		"the strip never draws more slots than its two rows hold (%d)" % flow.get_child_count())
	assert_true(card.fixed_content_height() <= UnitInfoPanel.CARD_HEIGHT,
		"and the card still fits its pinned budget")

	for chip in flow.get_children():
		var labels: Array = chip.find_children("*ChipLabel*", "Label", true, false)
		if labels.is_empty():
			continue
		var label := labels[0] as Label
		assert_true(label.size.x >= _text_width(label) - 1.0,
			"'%s' is still drawn wide enough to read" % label.text)


func test_a_unit_with_only_terrain_is_never_told_it_has_no_effects() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var layout: Control = await _build_hud()
	await _select(unit)

	var flow: Control = layout.unit_info_panel._status_flow
	assert_null(flow.get_node_or_null("NoStatuses"),
		"a terrain chip standing on its own IS an active effect -- contradicting it one "
		+ "chip later would be nonsense")
	assert_eq(_panel_terrain_chips(layout.unit_info_panel).size(), 1, "and it is on the strip")


# ==============================================================================
# 3. The hover card
# ==============================================================================

func test_the_hover_card_carries_the_same_chip_and_names_the_terrain() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var panel: Control = await _mount_hover()
	panel.show_for_unit(unit)
	for i in range(4):
		await get_tree().process_frame

	var chips: Array = _panel_terrain_chips(panel)
	assert_eq(chips.size(), 1, "the hover card wears the terrain chip too")
	if chips.is_empty():
		return
	var label := (chips[0] as Control).get_node("TerrainChipLabel") as Label
	gut.p("hover chip  : '%s'" % label.text)
	assert_true(label.text.begins_with("±AVO+%d" % BOOSTED_AVOID),
		"with the same mark and the same boosted number as every other surface: %s"
		% label.text)
	assert_true(label.text.contains("Tall Grass"),
		"and, since this card's subtree is click-through and can never show a tooltip, it "
		+ "names the terrain in the label itself: %s" % label.text)
	assert_true(label.size.x >= _text_width(label) - 1.0,
		"drawn wide enough to read (%.1f vs %.1f)" % [label.size.x, _text_width(label)])


func test_the_hover_card_drops_the_chip_when_the_unit_walks_out_of_the_grass() -> void:
	var unit := _board_with_unit(&"nature", GRASS_CELL)
	var panel: Control = await _mount_hover()
	panel.show_for_unit(unit)
	for i in range(4):
		await get_tree().process_frame
	assert_eq(_panel_terrain_chips(panel).size(), 1, "on the grass, the chip is up")

	await _walk(unit, BARE_CELL)
	assert_true(_panel_terrain_chips(panel).is_empty(),
		"the shown unit moving repaints the card without the cursor having to move")
	assert_true(panel.visible, "and the card is still up, just without the terrain chip")
