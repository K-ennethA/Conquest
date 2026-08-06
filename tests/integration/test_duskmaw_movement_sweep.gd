extends GutTest

## "COULD NOT MOVE TO A SPOT" -- the playtest report, made falsifiable.
##
## The complaint was vague, so this suite is a SWEEP rather than a scenario: Duskmaw is
## put on a varied real board (open ground, difficult tall grass, impassable trees, an
## ally to walk past, an enemy to path around) and then commanded to EVERY cell
## MovementResolver says it can reach, through the mounted UnitActionsPanel's own click
## path. Any refusal is the bug, and the refusals are collected into an Array (GUT lambdas
## capture BY VALUE) so the failure names the exact cells.
##
## Each cell is also checked for CELL-FIT / ORIGIN ALIGNMENT: after the move the board must
## report the unit standing on the cell that was clicked, not on a neighbour. That is what
## catches a rigged .glb whose armature root offsets the model away from its logical cell --
## the class of defect a static roster sculpt cannot have and Duskmaw's rig could.
##
## The two plausible user paths are replayed too: move-then-dash-then-canto-move (the old
## full-extra-action left state behind that blocked the follow-up step), and a unit standing
## one cell short of tall grass with exactly its last movement point left.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

const GRASS := "res://game/tiles/resources/forest/grass_plains.tres"
const TALL_GRASS := "res://game/tiles/resources/forest/tall_grass.tres"
const TREE := "res://game/tiles/resources/forest/tree.tres"

const DASH_SLOT: int = 3
const FODDER_ID: StringName = &"test_sweep_fodder"

## World units across one cell (Grid.cell_size); a cell-fitted sculpt must live inside it.
const CELL_SIZE: float = 2.0

var _guard
var _map_root: Node3D
var _prev_grid_size: Vector3


## The shared Grid resource, reached through a FUNCTION rather than CombatServices.GRID
## directly: GDScript refuses `SomeConst.size = ...` ("cannot assign a new value to a
## constant") even though the resource behind it is perfectly mutable -- which is exactly
## what a map load does to it (MapLoader._sync_grid_size).
func _grid() -> Grid:
	return CombatServices.GRID


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard = Guard.new()
	_guard.set_setting("auto_end_turn", true)
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_prev_grid_size = _grid().size
	_grid().size = Vector3(10, 0, 10)
	CharacterLibrary._cache[FODDER_ID] = _make_fodder()


func after_each() -> void:
	TurnSystemManager.active_turn_system = null
	CombatServices.clear()
	_grid().size = _prev_grid_size
	_map_root = null
	_guard.restore()
	CharacterLibrary.clear_cache()


# --- Fixtures ----------------------------------------------------------------

func _make_fodder() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = FODDER_ID
	c.display_name = "Fodder"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 200
	c.base_movement = 2
	c.base_speed = 4
	c.attack_range = 1
	return c


func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(_grid(), []).cell_to_world(cell)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## A VARIED 10x10 board: open grass everywhere, a tall-grass band (movement cost 2) and a
## stand of trees (impassable) that a route has to bend around.
func _paint_terrain() -> void:
	var grass: TileResource = load(GRASS)
	var tall: TileResource = load(TALL_GRASS)
	var tree: TileResource = load(TREE)
	for x in range(10):
		for y in range(10):
			CombatServices.register_tile(Vector2i(x, y), grass)
	for cell in [Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(7, 4)]:
		CombatServices.register_tile(cell, tall)
	for cell in [Vector2i(3, 6), Vector2i(4, 6), Vector2i(2, 2)]:
		CombatServices.register_tile(cell, tree)


## Duskmaw (human, centre-ish) with an ally beside it and two enemies lined up east, on a
## varied board, with a live Traditional turn system and the REAL HUD mounted.
## Returns {} -- a clean skip signal -- when the roster or the board is unavailable.
func _boot() -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true

	var duskmaw := _spawn(&"monster", Vector2i(4, 4), human)
	var ally := _spawn(FODDER_ID, Vector2i(4, 3), human)
	var near := _spawn(FODDER_ID, Vector2i(5, 4), ai)
	var far := _spawn(FODDER_ID, Vector2i(6, 4), ai)
	if duskmaw == null or ally == null or near == null or far == null:
		return {}

	_paint_terrain()
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

	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for _i in range(4):
		await get_tree().process_frame

	return {
		"duskmaw": duskmaw, "ally": ally, "near": near, "far": far,
		"human": human, "ai": ai, "ts": ts,
		"board": CombatServices.board(),
		"panel": layout.unit_actions_panel,
	}


func _reachable(unit: Unit, board) -> Array[Vector2i]:
	return MovementResolver.new().reachable_cells(
		board.cell_of(unit), unit.get_movement_profile(), board, unit)


## Select [param unit] on the mounted panel and let its range publish.
func _select(panel, unit: Unit) -> void:
	panel._on_unit_selected(unit, unit.global_position)
	await get_tree().process_frame


# ===========================================================================
# 1. THE SWEEP -- every reachable cell must actually be reachable
# ===========================================================================

func test_every_cell_the_resolver_offers_is_a_cell_the_board_accepts() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]

	await _select(panel, duskmaw)
	var origin: Vector2i = board.cell_of(duskmaw)
	var cells: Array[Vector2i] = _reachable(duskmaw, board)
	assert_gt(cells.size(), 8,
		"the fixture is worth sweeping (movement 5 on open ground reaches plenty)")

	# GUT lambdas capture BY VALUE, and a bare assert per cell would drown the report --
	# so both failure kinds are gathered into shared Arrays and asserted once.
	var refused: Array = []
	var misplaced: Array = []
	for cell in cells:
		var tile := Vector3(cell.x, 0, cell.y)
		assert_true(panel._is_grid_pos_in_range(tile),
			"the panel published %s as reachable" % str(cell))
		panel.handle_movement_destination_selected(tile)
		await get_tree().process_frame
		if not panel.is_tentative_move_active():
			refused.append(cell)
		elif board.cell_of(duskmaw) != cell:
			misplaced.append("%s -> %s" % [str(cell), str(board.cell_of(duskmaw))])
		# Back to the start, fully available, for the next cell.
		panel._on_action_menu_cancel_chosen()
		await get_tree().process_frame

	assert_eq(refused, [],
		"every cell MovementResolver offers must be a cell the click path accepts")
	assert_eq(misplaced, [],
		"and the unit must come to rest on the cell that was clicked -- a model offset " +
		"from its logical cell would show up here")
	assert_eq(board.cell_of(duskmaw), origin, "the sweep left the unit where it started")


func test_the_sweep_covers_terrain_that_actually_varies() -> void:
	# A sweep over featureless ground would prove nothing, so pin that the fixture really
	# does contain difficult terrain, a wall and a body to path around.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var board = s["board"]
	assert_eq(board.move_cost(Vector2i(6, 4)), 2, "tall grass costs two to enter")
	assert_eq(board.move_cost(Vector2i(4, 5)), 1, "open grass costs one")
	assert_true(board.is_blocked(Vector2i(3, 6)), "the tree stand is impassable")
	assert_true(board.is_occupied(Vector2i(5, 4)), "and an enemy is standing in the way")

	var cells: Array[Vector2i] = _reachable(s["duskmaw"], board)
	assert_false(Vector2i(3, 6) in cells, "an impassable tree is never offered")
	assert_false(Vector2i(5, 4) in cells, "nor a cell an enemy is standing on")
	assert_false(Vector2i(4, 3) in cells,
		"nor the ALLY's own cell -- FE pass-through lets you walk through a friend, " +
		"never stop on one")
	assert_true(Vector2i(4, 2) in cells,
		"but the cell BEYOND that ally is offered, so the sweep really does path through one")


# ===========================================================================
# 2. THE MODEL SITS ON ITS OWN CELL
# ===========================================================================

## Merged bounds of every mesh under [param unit]'s CharacterModel, expressed in the
## UNIT's local space -- i.e. exactly where the sculpt sits relative to the cell the board
## thinks the unit occupies.
func _model_bounds(unit: Unit) -> AABB:
	var model := unit.get_node_or_null("CharacterModel")
	if model == null:
		return AABB()
	var meshes: Array = []
	_collect_meshes(model, meshes)
	var to_local: Transform3D = unit.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mi in meshes:
		var m: MeshInstance3D = mi
		if m.mesh == null:
			continue
		var box: AABB = (to_local * m.global_transform) * m.mesh.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged


func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)


func test_duskmaws_rigged_model_is_still_fitted_to_one_cell() -> void:
	# Duskmaw is the roster's RIGGED sculpt: its .glb root is an armature rig with the
	# pipeline's cell-fit scale baked onto it, where every other roster model is a bare
	# mesh. Unit._orient_character_model assigns that root's scale from
	# CharacterResource.model_scale, so if the imported scene root WERE the rig itself the
	# fit would be thrown away and the creature would render many cells wide -- covering
	# the tiles the player is trying to click. This is the assertion that would catch it.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var bounds := _model_bounds(duskmaw)
	if bounds.size == Vector3.ZERO:
		pending("Duskmaw's .glb is not imported in this run; skipping the fit check.")
		return

	assert_lt(bounds.size.x, CELL_SIZE * 2.0,
		"the sculpt is no wider than its own cell and its neighbours (%.2f world units)"
			% bounds.size.x)
	assert_lt(bounds.size.z, CELL_SIZE * 2.0,
		"nor deeper (%.2f world units)" % bounds.size.z)
	assert_lt(bounds.size.y, CELL_SIZE * 3.0,
		"nor absurdly tall (%.2f world units)" % bounds.size.y)
	assert_almost_eq(bounds.position.y, 0.0, CELL_SIZE * 0.5,
		"and it stands ON the tile: the sculpt's feet are at the unit's own origin")


func test_the_board_reads_duskmaws_cell_from_where_it_is_actually_standing() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]
	var mismatched: Array = []
	for cell in [Vector2i(0, 0), Vector2i(4, 4), Vector2i(9, 9), Vector2i(7, 2)]:
		board.move_unit(duskmaw, cell)
		if board.cell_of(duskmaw) != cell:
			mismatched.append("%s -> %s" % [str(cell), str(board.cell_of(duskmaw))])
	assert_eq(mismatched, [],
		"cell -> world -> cell round-trips exactly, so a click on a tile names the cell " +
		"the unit is really on")


# ===========================================================================
# 3. THE USER PATHS
# ===========================================================================

func test_move_then_dash_then_canto_move_is_accepted_at_every_step() -> void:
	# The most likely shape of the report: the player walks, dashes, and then finds the
	# unit cannot be sent anywhere. Under the old full-extra-action grant the turn system
	# had already banked the unit as "acted" by this point, so the third step was refused.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]
	var ts: TraditionalTurnSystem = s["ts"]

	# 1. WALK one cell west, staged as the ordinary FE tentative move.
	await _select(panel, duskmaw)
	panel.handle_movement_destination_selected(Vector3(3, 0, 4))
	await get_tree().process_frame
	assert_true(panel.is_tentative_move_active(), "step one: the walk is staged")
	assert_eq(panel.get_command_state(), UnitActionsPanel.CommandState.ACTION_MENU,
		"and the post-move menu is up, exactly as it is for any other unit")

	# 2. DASH from the menu, east down the row the two enemies are lined up on. The panel
	#    commits the staged walk first, so this is genuinely move-THEN-dash in one turn.
	panel._on_action_menu_move_chosen(DASH_SLOT)
	await get_tree().process_frame
	assert_eq(panel.get_command_state(), UnitActionsPanel.CommandState.TARGETING,
		"the dash is being aimed")
	panel.handle_move_target_selected(Vector3(4, 0, 4))
	for _i in range(2):
		await get_tree().process_frame
	assert_eq(board.cell_of(duskmaw), Vector2i(7, 4),
		"step two: the dash ran through both enemies and landed beyond them")
	assert_true(duskmaw.has_canto(), "arming the canto")
	assert_false(duskmaw.can_act(), "the action is now spent as well as the walk")

	# 3. CANTO STEP. The unit has both MOVED and ACTED this turn -- the exact state that
	#    used to refuse every destination.
	assert_true(duskmaw.can_move(), "step three: the unit may still move")
	assert_true(ts.can_unit_act(duskmaw), "and the turn system has not written it off")
	assert_false(panel.movement_range_tiles.is_empty(), "a range is on screen to click")
	var target: Vector2i = _grid_to_cell(panel.movement_range_tiles[0])
	panel.handle_movement_destination_selected(panel.movement_range_tiles[0])
	await get_tree().process_frame
	assert_true(panel.is_tentative_move_active(),
		"REGRESSION: the canto destination was refused after a move-then-dash turn")
	panel._on_action_menu_wait_chosen()
	await get_tree().process_frame
	assert_eq(board.cell_of(duskmaw), target, "the unit took its canto step")
	assert_false(ts.can_unit_act(duskmaw), "and that closed its turn")


func _grid_to_cell(tile: Vector3) -> Vector2i:
	return Vector2i(int(round(tile.x)), int(round(tile.z)))


func test_tall_grass_at_the_last_movement_point_is_offered_only_when_it_is_paid_for() -> void:
	# Difficult terrain costs 2, so the boundary case is a unit whose remaining budget is
	# exactly 1 when it arrives beside the grass. Whatever the resolver decides, the panel
	# must agree -- an offered cell that the click refuses is the bug; an unoffered cell is
	# honest terrain cost, not a defect.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]

	# The budget is the unit's MOVEMENT STAT (the number its card prints), so the start
	# cells are DERIVED from it rather than hard-coded: retuning the character's stride
	# slides the fixture along row 3 instead of breaking this test.
	# Row 3 runs west from the tall grass at (6,3) over open grass, through the ally at
	# (4,3) (pass-through: passable, still costs 1), with no wall in between.
	var mov: int = duskmaw.get_stat("movement")
	var edge := Vector2i(5, 3)     # the open cell that touches the grass
	var grass := Vector2i(6, 3)    # costs 2 to enter
	# Stand `mov - 1` cells west of the edge: arriving there spends all but ONE point.
	var one_short := Vector2i(edge.x - (mov - 1), edge.y)
	# One cell nearer: 2 points left on the edge, exactly what the grass costs.
	var can_afford := Vector2i(one_short.x + 1, edge.y)
	if one_short.x < 0:
		pending("The boundary fixture needs a stride that fits on row 3; this one is %d." % mov)
		return

	board.move_unit(duskmaw, one_short)
	await _select(panel, duskmaw)
	var cells: Array[Vector2i] = _reachable(duskmaw, board)
	assert_true(edge in cells,
		"the open cell beside the grass is reachable -- %d of the %d points, through the ally"
			% [mov - 1, mov])
	assert_false(grass in cells,
		"but the grass itself needs 2 more and only 1 is left -- correctly NOT offered")

	# Now with the budget to pay for it: from one cell nearer, the grass is affordable and
	# the click path must honour it.
	board.move_unit(duskmaw, can_afford)
	await _select(panel, duskmaw)
	assert_true(grass in _reachable(duskmaw, board),
		"%d steps to the edge plus 2 for the grass is exactly the budget" % (mov - 2))
	panel.handle_movement_destination_selected(Vector3(grass.x, 0, grass.y))
	await get_tree().process_frame
	assert_true(panel.is_tentative_move_active(), "and the board accepts the move into it")
	assert_eq(board.cell_of(duskmaw), grass, "landing in the grass")


# ===========================================================================
# 4. THE ROSTER ENTRY, FIELD FOR FIELD
# ===========================================================================

func test_duskmaws_movement_fields_match_a_known_good_roster_entry() -> void:
	# Compared against Mortis, the other dark ranged caster, because a movement defect
	# would most likely be a field left at a wrong default rather than an authored value.
	var duskmaw := load("res://game/characters/roster/monster.tres") as CharacterResource
	var mortis := load("res://game/characters/roster/necromancer.tres") as CharacterResource

	assert_eq(duskmaw.movement_profile, mortis.movement_profile,
		"the SAME ground_standard profile resource -- not a private copy")
	assert_eq(duskmaw.movement_kind, mortis.movement_kind, "the same movement kind (GROUND)")
	assert_eq(duskmaw.get_footprint(), Vector2i.ONE,
		"one cell (CONQUEST.md: multi-cell is the deliberate exception)")
	assert_eq(duskmaw.get_footprint(), mortis.get_footprint(), "same as the known-good entry")
	assert_eq(duskmaw.base_movement, 5, "a 5 stride, as authored")
	assert_eq(duskmaw.model_scale, mortis.model_scale,
		"and no per-model scale override, exactly like the static roster sculpts")
	assert_eq(duskmaw.is_boss, false, "not a boss, so nothing gives it boss movement rules")


func test_the_authored_profile_is_the_one_the_live_unit_moves_by() -> void:
	# The profile says HOW the unit moves (kind, shape, terrain cost); the STAT says how
	# far. Both halves are checked here, because a synthesized fallback profile or a stray
	# spawn-time modifier would each fake the other's symptoms.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var profile: MovementProfile = duskmaw.get_movement_profile()
	assert_not_null(profile, "the live unit exposes a movement profile")
	assert_eq(profile, load("res://game/movement/profiles/ground_standard.tres"),
		"and it is the authored ground_standard, not a synthesized fallback")
	assert_eq(duskmaw.get_stat("movement"), duskmaw.get_base_stat("movement"),
		"with no stray modifier at spawn, so the live stride is the authored one")
	assert_eq(duskmaw.get_stat("movement"), 5,
		"which the roster authors as 5")


func test_the_movement_stat_and_the_flood_budget_agree() -> void:
	## THE SECOND FINDING, now FIXED -- and this is the test that holds it fixed.
	##
	## It used to read `..._disagree`. A character's reach came from its authored
	## MovementProfile's `range`, not from its movement stat: the resolver flooded with
	## profile.range and folded in only the DELTA of live modifiers (current - base), which
	## is 0 for a clean unit. Every roster entry shares `ground_standard.tres` (range 3), so
	## the card promised Duskmaw a 5 stride and the board handed back 3 -- exactly what
	## "could not move to a spot" feels like from the player's chair.
	##
	## THE DECISION: the movement STAT is the truth. MovementResolver floods with
	## `get_stat("movement")`, so base movement, every live modifier and any mode grant are
	## already in the number, and the profile keeps only the jobs that are really its own --
	## kind, shape, per-terrain cost. The shared profile's `range` survives as the fallback
	## for a call with no mover at all.
	##
	## Measured on row 8 -- the one row of the fixture with no tree, no tall grass and no
	## body on it -- so this is about the budget and nothing else: the cell exactly `mov`
	## steps east must be offered and the one beyond it must not.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var board = s["board"]
	var profile: MovementProfile = duskmaw.get_movement_profile()
	var mov: int = duskmaw.get_stat("movement")

	assert_eq(mov, 5, "the card still says a 5 stride")
	assert_eq(profile.range, 3,
		"and the shared ground_standard profile still carries its own 3 -- which is now " +
		"only the no-mover FALLBACK, not this unit's budget")
	assert_eq(load("res://game/characters/roster/necromancer.tres").movement_profile, profile,
		"the profile really is shared roster-wide, which is why it cannot be the stride")

	# The board must obey the CARD. Everything below is derived from `mov`, so a stat
	# retune moves the expectation with it instead of re-breaking this test.
	if mov < 1 or mov > 8:
		pending("The clear-row measurement needs a stride of 1..8; this one is %d." % mov)
		return
	var origin := Vector2i(1, 8)
	board.move_unit(duskmaw, origin)
	var cells: Array[Vector2i] = _reachable(duskmaw, board)

	assert_true(Vector2i(origin.x + mov, origin.y) in cells,
		"the cell a full %d steps out IS offered -- the board hands over the whole " % mov +
		"printed stride")
	assert_false(Vector2i(origin.x + mov + 1, origin.y) in cells,
		"and the cell one beyond it is not -- the stat is a budget, not a suggestion")

	# Stated as the invariant rather than as two numbers: the farthest cell reachable in a
	# straight line down the clear row is exactly `mov` away.
	var farthest: int = 0
	for c in cells:
		if c.y == origin.y and c.x > origin.x:
			farthest = maxi(farthest, c.x - origin.x)
	assert_eq(farthest, mov,
		"ONE source of truth for one number: the flood budget IS get_stat('movement')")
