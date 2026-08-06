extends GutTest

## Scree Trap's rubble must actually SLOW a unit crossing it -- via extra movement cost
## (MovementResolver reads it while flooding), so the penalty bites the same turn a foe
## tries to cross, not just if it stops on the tile next turn.

class MockBoard:
	var effects: Dictionary = {}  # cell -> Array[TileEffectResource]
	func in_bounds(_c: Vector2i) -> bool:
		return true
	func is_occupied(_c: Vector2i) -> bool:
		return false
	func is_blocked(_c: Vector2i) -> bool:
		return false
	func move_cost(_c: Vector2i) -> int:
		return 1
	func tile_effects_at(cell: Vector2i) -> Array:
		return effects.get(cell, [])


func _profile(r: int) -> MovementProfile:
	var p := MovementProfile.new()
	p.shape = MovementProfile.Shape.ORTHOGONAL
	p.kind = CombatTypes.MovementKind.GROUND
	p.range = r
	return p


func _rubble(bonus: int) -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"rock_rubble"
	te.affected_factions = TileEffectResource.AffectedFactions.ALL  # applies to anyone (no perspective needed)
	te.move_cost_bonus = bonus
	return te


func test_rubble_costs_extra_to_cross():
	var board := MockBoard.new()
	# applies_to only needs non-null + faction/tag; ALL passes both. Carrying no stats, it
	# is budgeted by the profile's fallback range -- which is all this case is about.
	var unit := RefCounted.new()
	var res := MovementResolver.new()

	# Clear ground: with a budget of 2, the cell two steps straight ahead is reachable.
	var clear := res.reachable_cells(Vector2i(0, 0), _profile(2), board, unit)
	assert_true(clear.has(Vector2i(0, 2)), "on open ground a 2-move unit reaches two cells out")

	# Drop rubble (cost +2) on the cell in between: entering it now costs 3 > range 2, so
	# neither the rubble cell nor the cell beyond it is reachable this turn.
	board.effects[Vector2i(0, 1)] = [_rubble(2)]
	var slowed := res.reachable_cells(Vector2i(0, 0), _profile(2), board, unit)
	assert_false(slowed.has(Vector2i(0, 1)), "the rubble cell is too costly to enter this turn")
	assert_false(slowed.has(Vector2i(0, 2)), "and the unit can no longer cross the rubble to the cell beyond")


func test_zero_bonus_rubble_does_not_slow():
	var board := MockBoard.new()
	board.effects[Vector2i(0, 1)] = [_rubble(0)]  # a tile effect with no move cost
	var res := MovementResolver.new()
	var cells := res.reachable_cells(Vector2i(0, 0), _profile(2), board, RefCounted.new())
	assert_true(cells.has(Vector2i(0, 2)), "a tile effect with move_cost_bonus 0 never changes reach")


## A unit exposing a LIVE movement stat that differs from its base -- the shape a "Slowed"
## status produces via a stat modifier. THE FLOOD BUDGET IS THAT LIVE STAT: the resolver
## reads `get_stat("movement")` directly, so a debuff shrinks the reachable set and a haste
## grows it with no arithmetic on the profile at all. `base` is carried purely so these
## cases still describe a modifier rather than a bare number.
class MoverStub:
	var cur: int
	var base: int
	func _init(p_cur: int, p_base: int) -> void:
		cur = p_cur
		base = p_base
	func get_stat(name: String) -> int:
		return cur if name == "movement" else 0
	func get_base_stat(name: String) -> int:
		return base if name == "movement" else 0


## The cells reachable straight down the open column, derived rather than listed, so each
## case below asserts a DISTANCE against the stat instead of hard-coded coordinates.
func _reach_down_column(unit, profile_range: int) -> int:
	var cells := MovementResolver.new().reachable_cells(
		Vector2i(0, 0), _profile(profile_range), MockBoard.new(), unit)
	var farthest: int = 0
	for c in cells:
		if c.x == 0 and c.y > 0:
			farthest = maxi(farthest, c.y)
	return farthest


func test_movement_debuff_shrinks_reachable_set():
	# Base movement 3 with a -2 debuff: the LIVE stat is 1, so exactly one cell out.
	var unit := MoverStub.new(1, 3)
	assert_eq(_reach_down_column(unit, 3), unit.cur,
		"a slowed unit reaches exactly its LIVE movement stat (%d), not its base %d"
			% [unit.cur, unit.base])


func test_no_movement_delta_leaves_reach_unchanged():
	# No modifier: live == base, and the reach is that number.
	var unit := MoverStub.new(3, 3)
	assert_eq(_reach_down_column(unit, 3), unit.cur,
		"an unmodified unit reaches its own movement stat")


func test_movement_buff_grows_reachable_set():
	# A haste EXTENDS reach past the base, and past the profile's fallback range (2).
	var unit := MoverStub.new(3, 2)
	assert_eq(_reach_down_column(unit, 2), unit.cur,
		"a hasted unit reaches its raised stat (%d), one farther than its base %d"
			% [unit.cur, unit.base])


func test_the_profile_range_is_only_the_fallback_for_a_mover_with_no_stats():
	# THE SPLIT, stated once: a unit that can report a movement stat is budgeted by it and
	# the profile's own `range` is ignored entirely; a mover that cannot (a bare RefCounted,
	# a tool, a mock) falls back to the profile. Same profile, two different budgets.
	assert_eq(_reach_down_column(MoverStub.new(4, 4), 2), 4,
		"a stat-bearing mover ignores the profile's range-2 and uses its own 4")
	assert_eq(_reach_down_column(RefCounted.new(), 2), 2,
		"a mover with no stats falls back to the profile's authored range")
	assert_eq(_reach_down_column(null, 2), 2,
		"and so does a call with no mover at all")
