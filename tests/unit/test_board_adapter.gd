extends GutTest

# Unit tests for BoardAdapter (game/combat/BoardAdapter.gd)
#
# Covers the combat-model <-> live-game bridge: Vector2i(col,row) <-> the game's
# Vector3 grid coordinate mapping, cell/units queries, allegiance checks via
# owner_player, tile overrides, and moving units. Uses lightweight duck-typed
# mock units (position + owner_player) so no full Unit/scene setup is required.

# --- Test doubles ----------------------------------------------------------

class MockUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp = null  # left unset (null) means "alive" per BoardAdapter's duck-typed check

# Opaque owner tokens (compared by identity inside the adapter).
class MockOwner extends RefCounted:
	var id: int = 0

var grid: Grid
var owner_a: MockOwner
var owner_b: MockOwner


func before_each():
	grid = Grid.new()  # default cell_size (2,0,2), size (5,0,5)
	owner_a = MockOwner.new()
	owner_a.id = 1
	owner_b = MockOwner.new()
	owner_b.id = 2


func _make_unit(cell: Vector2i, owner) -> MockUnit:
	# Placed at the true world center of the cell so cell_of round-trips.
	var adapter := BoardAdapter.new(grid, [])
	var u := MockUnit.new()
	u.position = adapter.cell_to_world(cell)
	u.owner_player = owner
	return u


func test_cell_to_world_round_trips():
	var adapter := BoardAdapter.new(grid, [])
	for cell in [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 3), Vector2i(4, 0)]:
		var world := adapter.cell_to_world(cell)
		assert_eq(adapter.world_to_cell(world), cell,
			"Cell %s should survive world round-trip" % cell)


func test_cell_of_reads_unit_position():
	var unit := _make_unit(Vector2i(2, 3), owner_a)
	var adapter := BoardAdapter.new(grid, [unit])
	assert_eq(adapter.cell_of(unit), Vector2i(2, 3), "cell_of should map world position back to grid cell")


func test_cell_of_null_unit_is_safe():
	var adapter := BoardAdapter.new(grid, [])
	assert_eq(adapter.cell_of(null), Vector2i.ZERO, "cell_of(null) should return a safe default")


func test_units_at_finds_units_on_cell():
	var here_1 := _make_unit(Vector2i(1, 1), owner_a)
	var here_2 := _make_unit(Vector2i(1, 1), owner_b)
	var elsewhere := _make_unit(Vector2i(3, 2), owner_a)
	var adapter := BoardAdapter.new(grid, [here_1, here_2, elsewhere])

	var found := adapter.units_at(Vector2i(1, 1))
	assert_eq(found.size(), 2, "Two units occupy cell (1,1)")
	assert_true(here_1 in found and here_2 in found, "Both co-located units should be returned")
	assert_false(elsewhere in found, "A unit on another cell should not be returned")

	assert_eq(adapter.units_at(Vector2i(0, 0)).size(), 0, "Empty cell should return no units")


func test_are_enemies_and_allies():
	var a := _make_unit(Vector2i(0, 0), owner_a)
	var b := _make_unit(Vector2i(1, 0), owner_b)
	var c := _make_unit(Vector2i(2, 0), owner_a)
	var adapter := BoardAdapter.new(grid, [a, b, c])

	assert_true(adapter.are_enemies(a, b), "Different owners should be enemies")
	assert_false(adapter.are_allies(a, b), "Different owners should not be allies")

	assert_true(adapter.are_allies(a, c), "Same owner should be allies")
	assert_false(adapter.are_enemies(a, c), "Same owner should not be enemies")


func test_unowned_units_are_neither():
	var a := _make_unit(Vector2i(0, 0), null)
	var b := _make_unit(Vector2i(1, 0), owner_b)
	var adapter := BoardAdapter.new(grid, [a, b])

	assert_false(adapter.are_enemies(a, b), "A null-owner unit is not an enemy")
	assert_false(adapter.are_allies(a, b), "A null-owner unit is not an ally")


func test_move_unit_changes_cell():
	var unit := _make_unit(Vector2i(1, 1), owner_a)
	var adapter := BoardAdapter.new(grid, [unit])

	adapter.move_unit(unit, Vector2i(3, 2))

	assert_eq(adapter.cell_of(unit), Vector2i(3, 2), "Unit should report its new cell")
	assert_eq(adapter.units_at(Vector2i(1, 1)).size(), 0, "Old cell should be empty after move")
	assert_true(unit in adapter.units_at(Vector2i(3, 2)), "New cell should contain the moved unit")


func test_move_unit_preserves_height():
	var unit := _make_unit(Vector2i(1, 1), owner_a)
	unit.position.y = 1.5
	var adapter := BoardAdapter.new(grid, [unit])

	adapter.move_unit(unit, Vector2i(2, 2))
	assert_eq(unit.position.y, 1.5, "move_unit should preserve the unit's height")


func test_set_and_get_tile():
	var adapter := BoardAdapter.new(grid, [])
	assert_null(adapter.get_tile(Vector2i(2, 2)), "Unset tile should return null")

	adapter.set_tile(Vector2i(2, 2), &"lava")
	assert_eq(adapter.get_tile(Vector2i(2, 2)), &"lava", "set_tile override should be readable via get_tile")


func test_dictionary_units_provider():
	# Mirrors board.gd's units dict (position -> Array). units_at recomputes cells
	# from live positions, so the dictionary keys need not be the cells themselves.
	var u := _make_unit(Vector2i(2, 2), owner_a)
	var provider := { Vector3(99, 0, 99): [u] }
	var adapter := BoardAdapter.new(grid, provider)

	assert_true(u in adapter.units_at(Vector2i(2, 2)), "Dictionary-provided units should be found by cell")


func test_callable_units_provider():
	var u := _make_unit(Vector2i(0, 4), owner_a)
	var provider := func(): return [u]
	var adapter := BoardAdapter.new(grid, provider)

	assert_true(u in adapter.units_at(Vector2i(0, 4)), "Callable-provided units should be found by cell")


# --- BotController board interface ------------------------------------------

func test_all_units_returns_placed_units():
	var a := _make_unit(Vector2i(0, 0), owner_a)
	var b := _make_unit(Vector2i(1, 1), owner_b)
	var adapter := BoardAdapter.new(grid, [a, b])

	var all := adapter.all_units()
	assert_eq(all.size(), 2, "all_units should return every placed unit")
	assert_true(a in all and b in all, "all_units should include both placed units")


func test_all_units_excludes_dead_units():
	var alive := _make_unit(Vector2i(0, 0), owner_a)
	var dead := _make_unit(Vector2i(1, 0), owner_a)
	dead.hp = 0
	var adapter := BoardAdapter.new(grid, [alive, dead])

	var all := adapter.all_units()
	assert_true(alive in all, "A living unit should be included in all_units")
	assert_false(dead in all, "A unit with 0 hp should be excluded from all_units")


# --- MovementResolver board interface ---------------------------------------

func test_in_bounds_true_inside_grid():
	var adapter := BoardAdapter.new(grid, [])
	assert_true(adapter.in_bounds(Vector2i(0, 0)), "Origin cell should be in bounds")
	assert_true(adapter.in_bounds(Vector2i(4, 4)), "Last cell of a 5x5 grid should be in bounds")


func test_in_bounds_false_outside_grid():
	var adapter := BoardAdapter.new(grid, [])
	assert_false(adapter.in_bounds(Vector2i(5, 0)), "Cell past the grid's width should be out of bounds")
	assert_false(adapter.in_bounds(Vector2i(0, -1)), "A negative cell should be out of bounds")


func test_in_bounds_defaults_true_without_grid():
	var adapter := BoardAdapter.new(null, [])
	assert_true(adapter.in_bounds(Vector2i(999, 999)), "With no grid attached, bounds are unconstrained")


func test_is_occupied_true_where_unit_stands():
	var unit := _make_unit(Vector2i(2, 2), owner_a)
	var adapter := BoardAdapter.new(grid, [unit])

	assert_true(adapter.is_occupied(Vector2i(2, 2)), "A cell with a unit should be occupied")
	assert_false(adapter.is_occupied(Vector2i(0, 0)), "An empty cell should not be occupied")


func test_is_occupied_ignores_dead_units():
	var dead := _make_unit(Vector2i(3, 3), owner_a)
	dead.hp = 0
	var adapter := BoardAdapter.new(grid, [dead])

	assert_false(adapter.is_occupied(Vector2i(3, 3)), "A cell with only a dead unit should not be occupied")


func test_is_blocked_defaults_to_false():
	var adapter := BoardAdapter.new(grid, [])
	assert_false(adapter.is_blocked(Vector2i(1, 1)), "is_blocked should default to false (terrain blocking is a later task)")


func test_move_cost_defaults_to_one():
	var adapter := BoardAdapter.new(grid, [])
	assert_eq(adapter.move_cost(Vector2i(1, 1)), 1, "move_cost should default to 1")


func test_tile_id_at_defaults_empty_then_reflects_set_tile():
	var adapter := BoardAdapter.new(grid, [])
	assert_eq(adapter.tile_id_at(Vector2i(2, 2)), &"", "Unset tile id should default to an empty StringName")

	adapter.set_tile(Vector2i(2, 2), &"lava")
	assert_eq(adapter.tile_id_at(Vector2i(2, 2)), &"lava", "tile_id_at should reflect a set_tile override")
