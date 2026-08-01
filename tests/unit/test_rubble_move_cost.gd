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
	var unit := RefCounted.new()  # applies_to only needs non-null + faction/tag; ALL passes both
	var res := MovementResolver.new()

	# Clear ground: with movement 2, the cell two steps straight ahead is reachable.
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


## A unit exposing a LIVE movement stat below its base -- the shape a "Slowed" status
## produces via a stat modifier. MovementResolver must fold the (current - base) delta
## into its flood budget so the reachable set shrinks by the debuff.
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


func test_movement_debuff_shrinks_reachable_set():
	# Base movement 3, but a -2 debuff drops live movement to 1: only one cell out is
	# reachable, the cells two and three out are cut off (profile.range 3 + (1 - 3) = 1).
	var board := MockBoard.new()
	var res := MovementResolver.new()
	var unit := MoverStub.new(1, 3)
	var cells := res.reachable_cells(Vector2i(0, 0), _profile(3), board, unit)
	assert_true(cells.has(Vector2i(0, 1)), "one step out is still reachable while slowed")
	assert_false(cells.has(Vector2i(0, 2)), "two steps out is cut off by the -2 movement debuff")
	assert_false(cells.has(Vector2i(0, 3)), "three steps out is cut off too")


func test_no_movement_delta_leaves_reach_unchanged():
	# current == base -> zero delta -> the full authored range-3 reach stands (byte-for-byte).
	var board := MockBoard.new()
	var res := MovementResolver.new()
	var unit := MoverStub.new(3, 3)
	var cells := res.reachable_cells(Vector2i(0, 0), _profile(3), board, unit)
	assert_true(cells.has(Vector2i(0, 3)), "with no movement delta the unit reaches the full range")


func test_movement_buff_grows_reachable_set():
	# A positive delta (a haste) EXTENDS reach: base 2, live 3 -> range 2 + (3 - 2) = 3.
	var board := MockBoard.new()
	var res := MovementResolver.new()
	var unit := MoverStub.new(3, 2)
	var cells := res.reachable_cells(Vector2i(0, 0), _profile(2), board, unit)
	assert_true(cells.has(Vector2i(0, 3)), "a +1 movement buff lets the unit reach one cell farther")
