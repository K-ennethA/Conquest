extends GutTest

## VOIDSTEP ON THE REAL SCREEN -- what the booted [GameUILayout] actually lights up.
##
## WHY MOUNTED. A dual-resolution move is only usable if the player can SEE which cells do
## which thing, and that highlight is drawn by a chain nothing helper-level exercises: the
## panel sweeps [method UnitActionsPanel._compute_in_range_aim_cells], publishes the cells on
## [signal GameEvents.attack_range_calculated], and [TargetingVisualizer] turns them into
## meshes. A helper-static assertion would have passed while the screen showed nothing (the
## standing lesson of `test_battle_hud_live_unit_info.gd`), so this suite reads the
## VISUALIZER'S RENDERED MARKERS.
##
## THE RULE UNDER TEST. Aiming Voidstep lights up two things at once:
##   * every free cell within 4 of Duskmaw -- somewhere an anchor may be PLANTED;
##   * every cell holding one of Duskmaw's OWN anchors, out to the move's reach -- somewhere
##     it may STEP;
## and nothing else. A cell somebody is standing on is lit for neither.
##
## THE DOCUMENTED LIMIT: the teleport reaches the move's authored max_range (12), not the
## whole map. [method TargetingPattern.in_range] is pure geometry that both [MoveExecutor]
## and the highlight sweep bound themselves by, and widening a pattern from board state
## would invert an invariant the whole targeting layer rests on ("a constraint may only ever
## NARROW"). 12 covers the width of every shipped map from any cell an anchor can be planted
## from, so the fallback is the behaviour, not a gap.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Voidstep's slot in Duskmaw's authored moveset.
const VOIDSTEP_SLOT: int = 3
const FODDER_ID: StringName = &"test_voidstep_fodder"

## Untyped on purpose (tests/README rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.set_setting().
var _guard

var _map_root: Node3D
var _prev_grid_size: Vector3


func _grid() -> Grid:
	return CombatServices.GRID


func before_each() -> void:
	CombatServices.clear()
	ModeTuning.clear()
	_map_root = null
	_guard = Guard.new()
	_guard.set_setting("auto_end_turn", true)
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	# The shared Grid is 5x5 by default (a map load resizes it); Voidstep needs room to
	# plant an anchor and then walk away from it.
	_prev_grid_size = _grid().size
	_grid().size = Vector3(12, 0, 12)
	CharacterLibrary._cache[FODDER_ID] = _make_fodder()


func after_each() -> void:
	TurnSystemManager.active_turn_system = null
	ModeTuning.clear()
	CombatServices.clear()
	_grid().size = _prev_grid_size
	_map_root = null
	_guard.restore()
	CharacterLibrary.clear_cache()
	await get_tree().process_frame


# --- Fixtures ----------------------------------------------------------------


func _make_fodder() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = FODDER_ID
	c.display_name = "Fodder"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 200
	c.base_attack = 5
	c.base_defense = 8
	c.base_speed = 1
	c.base_movement = 1
	c.attack_range = 1
	return c


func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(_grid(), []).cell_to_world(cell)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # before add_child, so _ready() builds stats from it
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## Board + turn system + the REAL HUD + a real [TargetingVisualizer]. Duskmaw opens at
## (2,2) with one enemy parked well out of the way. Returns {} -- a clean skip signal --
## when the roster or the board is unavailable.
func _boot() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true

	var duskmaw := _spawn(&"monster", Vector2i(2, 2), human)
	var fodder := _spawn(FODDER_ID, Vector2i(10, 10), ai)
	if duskmaw == null or fodder == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	if CombatServices.board() == null:
		return {}

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	ts.register_player(human)
	ts.register_player(ai)
	ts.start_turn_system()
	TurnSystemManager.active_turn_system = ts

	var viz := TargetingVisualizer.new()
	viz.name = "TargetingVisualizer"
	_map_root.add_child(viz)

	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for _i in range(4):
		await get_tree().process_frame

	return {
		"duskmaw": duskmaw,
		"fodder": fodder,
		"human": human,
		"ai": ai,
		"ts": ts,
		"board": CombatServices.board(),
		"panel": layout.unit_actions_panel,
		"viz": viz,
	}


## Select [param unit] and arm Voidstep, then hand back the cells the visualizer is
## RENDERING a marker on (Vector2i(col, row), row-major).
func _lit_cells(panel, viz, unit: Unit) -> Array:
	# Drop any aim left armed by a previous read, so the visualizer is repopulated from
	# scratch rather than asserted against a stale set.
	panel._cancel_move_targeting()
	await get_tree().process_frame
	panel._on_unit_selected(unit, unit.global_position)
	await get_tree().process_frame
	panel._on_move_selected(VOIDSTEP_SLOT)
	await get_tree().process_frame
	var cells: Array = []
	for key in viz.attack_range_meshes.keys():
		var mesh = viz.attack_range_meshes[key]
		if mesh == null or not is_instance_valid(mesh):
			continue
		cells.append(Vector2i(int(round(key.x)), int(round(key.z))))
	cells.sort()
	return cells


## Plant an anchor at [param cell] by resolving the unit's OWN authored Voidstep effect
## against the LIVE board -- the same object the move lists and the same board the panel
## validates with, just without spending the unit's turn. Used by the highlight tests, which
## are about what is DRAWN once anchors exist rather than about the cast that made them (the
## panel-driven cast has its own test below).
func _plant(unit: Unit, cell: Vector2i) -> void:
	var move: MoveResource = unit.get_move(VOIDSTEP_SLOT)
	if move == null or move.effects.is_empty():
		return
	var ctx := MoveContext.new(
		unit, CombatServices.board(), move, cell, [cell] as Array[Vector2i])
	move.effects[0].apply(ctx)


## Plant an anchor at [param cell] through the panel's own command path -- pick the move,
## click the cell -- which is exactly what the player does.
func _cast_at(panel, unit: Unit, cell: Vector2i) -> void:
	panel._on_unit_selected(unit, unit.global_position)
	await get_tree().process_frame
	panel._on_move_selected(VOIDSTEP_SLOT)
	panel.handle_move_target_selected(Vector3(cell.x, 0, cell.y))
	for _i in range(2):
		await get_tree().process_frame


# ===========================================================================
# The lit range
# ===========================================================================


func test_with_no_anchors_down_the_lit_range_is_the_planting_reach_alone() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("roster/board unavailable in this environment")
		return
	var lit: Array = await _lit_cells(s["panel"], s["viz"], s["duskmaw"])

	assert_gt(lit.size(), 0, "the screen lights SOMETHING -- the move is aimable")
	assert_true(lit.has(Vector2i(6, 2)),
		"free ground 4 cells east is lit: that is where an anchor may be planted")
	assert_false(lit.has(Vector2i(7, 2)),
		"and 5 cells east is dark -- planting is bounded at 4")
	assert_false(lit.has(Vector2i(2, 2)),
		"the caster's own cell is never a legal aim")
	for cell in lit:
		assert_lte(absi(cell.x - 2) + absi(cell.y - 2), 4,
			"with nothing at all lit past the planting reach while no anchor exists: %s" % str(cell))


func test_an_own_anchor_stays_lit_after_the_caster_walks_out_of_planting_reach() -> void:
	# THE WHOLE POINT OF THE MOVE, as the screen has to show it: the anchor is still a legal
	# aim from somewhere no placement could ever reach, so the player can see the way home.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("roster/board unavailable in this environment")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]

	var anchor := Vector2i(2, 6)
	_plant(duskmaw, anchor)
	assert_eq(CombatServices.applied_tile_effects_at(anchor).size(), 1,
		"an anchor stands 4 cells south of where Duskmaw started")

	# Walk away, far past the 4-cell planting reach.
	board.move_unit(duskmaw, Vector2i(9, 2))

	var lit: Array = await _lit_cells(panel, s["viz"], duskmaw)

	assert_true(lit.has(anchor),
		"the caster's own anchor is LIT from 11 cells away -- the long half of the move")
	assert_false(lit.has(Vector2i(2, 7)),
		"while the bare ground beside it is dark: only the anchor reaches that far")
	assert_true(lit.has(Vector2i(9, 6)),
		"and the planting reach is still lit around the caster's new cell")


func test_a_body_parked_on_an_anchor_puts_its_light_out() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("roster/board unavailable in this environment")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]

	var anchor := Vector2i(2, 6)
	_plant(duskmaw, anchor)
	var lit_free: Array = await _lit_cells(panel, s["viz"], duskmaw)
	assert_true(lit_free.has(anchor), "an empty anchor is lit")

	board.move_unit(s["fodder"], anchor)
	var lit_blocked: Array = await _lit_cells(panel, s["viz"], duskmaw)

	assert_false(lit_blocked.has(anchor),
		"an anchor with somebody standing on it is dark -- there is nowhere to arrive")
	assert_true(CombatServices.applied_tile_effects_at(anchor).size() == 1,
		"but the anchor itself is untouched: a body PARKED on it never broke it, it was only "
		+ "ever closed while occupied")

	# NOTE: the fodder here is an ENEMY, and an enemy that ENTERS an anchor's cell destroys
	# it (the stomp). It was placed straight onto the cell rather than walking there, so no
	# tile entry ever happened -- which is exactly what isolates "occupied" from "stomped".
	# The stomp itself is pinned at its own seam in tests/integration/test_voidstep.gd.


func test_the_planted_anchor_gets_its_own_visible_marker_on_the_board() -> void:
	# The overlay is what makes an anchor findable at all. It reads TileEffectVisuals, so a
	# void spot with no table entry would render in the fallback colour and be
	# indistinguishable from every other placed effect.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("roster/board unavailable in this environment")
		return
	var overlay := TileEffectOverlay.new()
	_map_root.add_child(overlay)
	await get_tree().process_frame

	var anchor := Vector2i(2, 6)
	await _cast_at(s["panel"], s["duskmaw"], anchor)
	await get_tree().process_frame

	assert_true(overlay._markers.has(anchor),
		"the overlay stacked a pip row over the anchored cell")

	# AND IT GOES WHEN THE ANCHOR DOES. Every way an anchor leaves the board runs through
	# CombatServices.remove_tile_effect, which raises tile_effects_changed -- so the overlay
	# pulls the pip reactively, whether the anchor was stepped through, stomped, evicted or
	# expired. Spending it by teleporting is the cheapest of the four to drive here.
	var duskmaw: Unit = s["duskmaw"]
	var move: MoveResource = duskmaw.get_move(VOIDSTEP_SLOT)
	var ctx := MoveContext.new(
		duskmaw, CombatServices.board(), move, anchor, [anchor] as Array[Vector2i])
	move.effects[0].apply(ctx)
	await get_tree().process_frame

	assert_eq(CombatServices.board().cell_of(duskmaw), anchor, "the step arrived")
	assert_eq(CombatServices.applied_tile_effects_at(anchor).size(), 0,
		"and spent the anchor")
	assert_false(overlay._markers.has(anchor),
		"so the pip came off the cell -- a spent anchor leaves no marker behind")

	var info: Dictionary = TileEffectVisuals.info_for_id(&"void_spot")
	assert_eq(String(info.get("name", "")), "Void Spot", "and the table names it")
	assert_ne(info.get("color", Color.WHITE), TileEffectVisuals._FALLBACK["color"],
		"in its own dark tint rather than the generic fallback colour")
	assert_eq(String(info.get("kind", "")), "neutral",
		"as a NEUTRAL mark -- it neither harms nor helps whoever stands on it, so it must "
		+ "not pulse like a hazard")
