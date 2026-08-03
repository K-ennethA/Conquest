extends GutTest

# The Fire Emblem movement rule, pinned: YOUR OWN LINE IS NOT A WALL.
#
#   * a path may run THROUGH allied units (a unit boxed in by its own side walks out
#     between them),
#   * no unit may END its move on an occupied cell -- ally or enemy,
#   * ENEMY units block pathing outright,
#   * per-tile movement cost, walls and multi-cell footprints are all unchanged.
#
# The rule needs the board to positively confirm friendship (units_at + are_allies).
# A board that cannot answer must FAIL CLOSED and keep the old "any occupant blocks"
# reading, so lightweight mocks and allegiance-blind callers cannot accidentally gain
# pass-through -- that is asserted here too, because it is the half that keeps every
# other suite (and the AI) honest.
#
# Pure resolver tests: no scene tree, no autoloads. Cells are Vector2i(col, row).

# --- Doubles ----------------------------------------------------------------
#
# Local on purpose (tests/README rule 5): the shared board doubles deliberately do NOT
# combine footprint-aware units_at with an allegiance model, and teaching one of them to
# would silently reroute every suite that uses it through the pass-through branch.

## A unit with a side, a footprint and a liveness flag -- the three things the resolver
## asks about while deciding who blocks whom.
class Fighter:
	var team: int
	var footprint: Vector2i
	var alive: bool = true
	func _init(p_team: int, p_footprint: Vector2i = Vector2i.ONE) -> void:
		team = p_team
		footprint = p_footprint
	func get_footprint() -> Vector2i:
		return footprint
	func is_alive() -> bool:
		return alive


## A board that knows WHO stands where and WHOSE side they are on.
class AllegianceBoard:
	var w: int
	var h: int
	var walls := {}            # Vector2i -> true
	var costs := {}            # Vector2i -> int (default 1)
	var placements: Array = [] # { unit, cell }

	func _init(p_w: int = 9, p_h: int = 9) -> void:
		w = p_w
		h = p_h

	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })

	func wall(cell: Vector2i) -> void:
		walls[cell] = true

	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h

	func move_cost(cell: Vector2i) -> int:
		return int(costs.get(cell, 1))

	func is_blocked(cell: Vector2i) -> bool:
		return walls.has(cell)

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			var anchor: Vector2i = p.cell
			var fp: Vector2i = p.unit.get_footprint()
			if cell.x >= anchor.x and cell.x < anchor.x + fp.x \
				and cell.y >= anchor.y and cell.y < anchor.y + fp.y:
				out.append(p.unit)
		return out

	func is_occupied(cell: Vector2i) -> bool:
		for u in units_at(cell):
			if u.is_alive():
				return true
		return false

	func are_allies(a, b) -> bool:
		return a != null and b != null and a.team == b.team

	func are_enemies(a, b) -> bool:
		return a != null and b != null and a.team != b.team

	func can_fit(unit, anchor: Vector2i) -> bool:
		var fp: Vector2i = unit.get_footprint()
		for dx in range(fp.x):
			for dy in range(fp.y):
				var c := Vector2i(anchor.x + dx, anchor.y + dy)
				if not in_bounds(c) or is_blocked(c):
					return false
				for other in units_at(c):
					if other != unit and other.is_alive():
						return false
		return true


## The allegiance-blind board: occupancy only, exactly the shape every
## pre-existing mock in the suite has.
class OccupancyOnlyBoard:
	var w: int
	var h: int
	var units := {}
	func _init(p_w: int = 9, p_h: int = 9) -> void:
		w = p_w
		h = p_h
	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.x < w and cell.y >= 0 and cell.y < h
	func move_cost(_cell: Vector2i) -> int:
		return 1
	func is_blocked(_cell: Vector2i) -> bool:
		return false
	func is_occupied(cell: Vector2i) -> bool:
		return units.has(cell)
	func occupy(cell: Vector2i) -> void:
		units[cell] = true


# --- Helpers ----------------------------------------------------------------

func _resolver() -> MovementResolver:
	return MovementResolver.new()


func _profile(range_value: int, kind := CombatTypes.MovementKind.GROUND) -> MovementProfile:
	return MovementProfile.create(
		&"test_pass_through", "Test", kind, range_value,
		MovementProfile.Shape.ORTHOGONAL)


const ORTHO_NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


# --- The headline case: boxed in by your own side ---------------------------

func test_a_unit_surrounded_by_allies_can_still_path_out() -> void:
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	var origin := Vector2i(3, 3)
	board.place(mover, origin)
	for step in ORTHO_NEIGHBOURS:
		board.place(Fighter.new(0), origin + step)

	var cells := _resolver().reachable_cells(origin, _profile(2), board, mover)

	assert_gt(cells.size(), 0,
		"a unit ringed by its own side is not stuck -- allies are passable")
	assert_true(cells.has(Vector2i(1, 3)),
		"it can step over the ally to its west and stop on the free cell beyond")
	assert_true(cells.has(Vector2i(3, 1)),
		"and over the ally to its north")


func test_it_may_pass_through_an_ally_but_never_stop_on_one() -> void:
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	var origin := Vector2i(3, 3)
	board.place(mover, origin)
	for step in ORTHO_NEIGHBOURS:
		board.place(Fighter.new(0), origin + step)

	var cells := _resolver().reachable_cells(origin, _profile(2), board, mover)

	for step in ORTHO_NEIGHBOURS:
		assert_false(cells.has(origin + step),
			"the ally's own cell at %s is passable but is never a landing" % [origin + step])


func test_the_origin_is_still_excluded_from_the_reachable_set() -> void:
	# The mover is transparent to itself now; that must not make its own cell a "move".
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(3, 3))
	var cells := _resolver().reachable_cells(Vector2i(3, 3), _profile(3), board, mover)
	assert_false(cells.has(Vector2i(3, 3)), "standing still is not a destination")


# --- Enemies are still a wall ----------------------------------------------

func test_a_unit_surrounded_by_enemies_is_genuinely_stuck() -> void:
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	var origin := Vector2i(3, 3)
	board.place(mover, origin)
	for step in ORTHO_NEIGHBOURS:
		board.place(Fighter.new(1), origin + step)

	var cells := _resolver().reachable_cells(origin, _profile(3), board, mover)
	assert_eq(cells.size(), 0,
		"an enemy ring is a wall -- pass-through is for allies only")


func test_an_enemy_blocks_the_lane_an_ally_would_have_opened() -> void:
	# Same geometry, one side swapped: the cell two steps west is reachable through a
	# friend and unreachable through a foe. Nothing else differs.
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	var origin := Vector2i(3, 3)
	board.place(mover, origin)
	board.place(Fighter.new(0), Vector2i(2, 3))   # ally, west
	board.place(Fighter.new(1), Vector2i(4, 3))   # enemy, east
	# Wall off the detours so each destination has exactly ONE two-step approach.
	for y in [2, 4]:
		for x in [2, 3, 4, 5, 1]:
			board.wall(Vector2i(x, y))

	var cells := _resolver().reachable_cells(origin, _profile(2), board, mover)
	assert_true(cells.has(Vector2i(1, 3)), "through the ally: reachable")
	assert_false(cells.has(Vector2i(5, 3)), "through the enemy: not reachable")


# --- Everything the rule must NOT change ------------------------------------

func test_movement_cost_is_still_paid_for_the_cell_the_ally_stands_on() -> void:
	# Passing through a friend is free of PERMISSION, not free of COST: the tile under
	# it charges its own move cost exactly as an empty tile would.
	var board := AllegianceBoard.new()
	board.costs[Vector2i(1, 0)] = 2   # the ally is standing in mud
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(0, 0))
	board.place(Fighter.new(0), Vector2i(1, 0))
	# Wall the detours so (2,0) can only be reached straight through the ally.
	board.wall(Vector2i(0, 1))
	board.wall(Vector2i(1, 1))
	board.wall(Vector2i(2, 1))

	var tight := _resolver().reachable_cells(Vector2i(0, 0), _profile(2), board, mover)
	assert_false(tight.has(Vector2i(2, 0)),
		"2 movement cannot cross a cost-2 ally tile AND step beyond it")

	var roomy := _resolver().reachable_cells(Vector2i(0, 0), _profile(3), board, mover)
	assert_true(roomy.has(Vector2i(2, 0)),
		"3 movement can -- the cost was charged, not waived")


func test_a_wall_is_still_a_wall_even_with_an_ally_on_the_far_side() -> void:
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(0, 0))
	for y in range(9):
		board.wall(Vector2i(1, y))
	board.place(Fighter.new(0), Vector2i(2, 0))

	var cells := _resolver().reachable_cells(Vector2i(0, 0), _profile(4), board, mover)
	assert_false(cells.has(Vector2i(2, 0)), "an ally does not tunnel through terrain")
	assert_false(cells.has(Vector2i(3, 0)), "nor does anything past it become reachable")


func test_a_multi_cell_unit_crosses_allies_but_lands_only_where_it_wholly_fits() -> void:
	var board := AllegianceBoard.new(12, 12)
	var big := Fighter.new(0, Vector2i(2, 2))
	board.place(big, Vector2i(1, 1))            # covers (1,1)(2,1)(1,2)(2,2)
	board.place(Fighter.new(0), Vector2i(3, 1)) # a friend directly in its path

	var cells := _resolver().reachable_cells(Vector2i(1, 1), _profile(3), board, big)

	assert_false(cells.has(Vector2i(2, 1)),
		"an anchor whose span would cover the ally is not a landing")
	assert_false(cells.has(Vector2i(3, 1)),
		"nor is one that would stand on top of it")
	assert_true(cells.has(Vector2i(4, 1)),
		"but the 2x2 walked THROUGH its own line and stopped where its whole span fits")


func test_a_dead_unit_blocks_nothing() -> void:
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	var corpse := Fighter.new(1)
	corpse.alive = false
	board.place(mover, Vector2i(0, 0))
	board.place(corpse, Vector2i(1, 0))

	var cells := _resolver().reachable_cells(Vector2i(0, 0), _profile(1), board, mover)
	assert_true(cells.has(Vector2i(1, 0)),
		"a unit mid-cleanup is not an obstacle, enemy or not")


# --- Per-kind behaviour -----------------------------------------------------

func test_a_flier_passes_allies_and_is_stopped_by_enemies() -> void:
	var flying := CombatTypes.MovementKind.FLYING
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(3, 3))
	board.place(Fighter.new(0), Vector2i(2, 3))  # ally west
	board.place(Fighter.new(1), Vector2i(4, 3))  # enemy east
	for y in [2, 4]:
		for x in [1, 2, 3, 4, 5]:
			board.wall(Vector2i(x, y))            # walls are nothing to a flier

	var cells := _resolver().reachable_cells(Vector2i(3, 3), _profile(2, flying), board, mover)
	assert_true(cells.has(Vector2i(1, 3)), "a flier crosses its own side")
	assert_false(cells.has(Vector2i(5, 3)), "and is still stopped by an enemy body")


func test_a_phaser_is_unchanged() -> void:
	var phasing := CombatTypes.MovementKind.PHASING
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(3, 3))
	board.place(Fighter.new(1), Vector2i(4, 3))

	var cells := _resolver().reachable_cells(Vector2i(3, 3), _profile(2, phasing), board, mover)
	assert_true(cells.has(Vector2i(5, 3)), "phasing already ignored everything on the way")
	assert_false(cells.has(Vector2i(4, 3)), "and still may not land on a body")


# --- Fail-closed: the rule needs an allegiance-aware board ------------------

func test_an_allegiance_blind_board_keeps_the_old_blocking_behaviour() -> void:
	# Every mock in the suite (and any caller with no allegiance model) is this shape.
	# Pass-through must not be invented for it.
	var board := OccupancyOnlyBoard.new()
	board.occupy(Vector2i(1, 0))
	var mover := Fighter.new(0)

	var cells := _resolver().reachable_cells(Vector2i(0, 0), _profile(2), board, mover)
	assert_false(cells.has(Vector2i(2, 0)),
		"a board that cannot say who is friendly blocks on ANY occupant, as it always did")


func test_pathing_with_no_mover_is_unchanged() -> void:
	# reachable_cells' unit argument is optional; callers that omit it (the AI's
	# threat-range preview among them) get the historical occupancy rule.
	var board := AllegianceBoard.new()
	board.place(Fighter.new(0), Vector2i(1, 0))

	var cells := _resolver().reachable_cells(Vector2i(0, 0), _profile(2), board)
	assert_false(cells.has(Vector2i(2, 0)),
		"with nobody moving there is no 'ally' to be friendly to -- occupancy blocks")


func test_enemy_only_pathing_matches_the_allegiance_blind_result_exactly() -> void:
	# The AI soak guarantee: for a board containing only hostiles, the fix cannot have
	# widened anything. The two boards must produce identical reachable sets.
	var aware := AllegianceBoard.new()
	var blind := OccupancyOnlyBoard.new()
	var mover := Fighter.new(0)
	aware.place(mover, Vector2i(4, 4))
	for cell in [Vector2i(5, 4), Vector2i(4, 5), Vector2i(2, 4), Vector2i(4, 2)]:
		aware.place(Fighter.new(1), cell)
		blind.occupy(cell)

	var from_aware := _resolver().reachable_cells(Vector2i(4, 4), _profile(3), aware, mover)
	var from_blind := _resolver().reachable_cells(Vector2i(4, 4), _profile(3), blind, mover)
	assert_eq(from_aware, from_blind,
		"an all-enemy board resolves exactly as it did before ally pass-through existed")


func test_can_reach_agrees_with_the_reachable_set() -> void:
	# can_reach is the single-cell query the executor and the AI validate with; it must
	# not have drifted from the flood it delegates to.
	var board := AllegianceBoard.new()
	var mover := Fighter.new(0)
	board.place(mover, Vector2i(3, 3))
	board.place(Fighter.new(0), Vector2i(2, 3))

	assert_true(_resolver().can_reach(Vector2i(3, 3), Vector2i(1, 3), _profile(2), board, mover),
		"the cell past the ally is reachable")
	assert_false(_resolver().can_reach(Vector2i(3, 3), Vector2i(2, 3), _profile(2), board, mover),
		"the ally's own cell is not")
