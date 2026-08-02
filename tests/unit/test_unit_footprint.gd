extends GutTest

# Unit tests for multi-cell unit footprints (units that occupy more than one tile).
#
# A unit's ANCHOR cell is still whatever BoardAdapter.cell_of() derives from its
# world position; its footprint span extends from that anchor toward +col/+row.
# The high-leverage property is that units_at() matches ANY covered cell, so a
# 2x2 boss blocks -- and is attackable from -- every tile it stands on.
#
# Uses lightweight duck-typed mocks (position + owner_player + get_footprint) in
# the style of test_board_adapter.gd, so no full Unit/scene setup is required.

# --- Test doubles ----------------------------------------------------------

class MockUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp = null  # null means "alive" per BoardAdapter's duck-typed check
	var footprint: Vector2i = Vector2i.ONE
	func get_footprint() -> Vector2i:
		return footprint

# A mock with NO get_footprint at all -- must still read as a normal 1x1 unit.
class LegacyMockUnit extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp = null

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


func _make_unit(cell: Vector2i, owner, footprint: Vector2i = Vector2i.ONE) -> MockUnit:
	# Placed at the true world center of the cell so cell_of round-trips.
	var adapter := BoardAdapter.new(grid, [])
	var u := MockUnit.new()
	u.position = adapter.cell_to_world(cell)
	u.owner_player = owner
	u.footprint = footprint
	return u


func _wall() -> TileResource:
	var res := TileResource.new()
	res.is_passable = false
	return res


# --- cells_of ---------------------------------------------------------------

func test_default_unit_covers_only_its_anchor():
	var unit := _make_unit(Vector2i(2, 3), owner_a)
	var adapter := BoardAdapter.new(grid, [unit])

	assert_eq(adapter.cells_of(unit), [Vector2i(2, 3)] as Array[Vector2i],
		"A 1x1 unit should cover exactly its anchor cell")


func test_unit_without_get_footprint_is_one_by_one():
	var adapter := BoardAdapter.new(grid, [])
	var legacy := LegacyMockUnit.new()
	legacy.position = adapter.cell_to_world(Vector2i(1, 1))
	var with_unit := BoardAdapter.new(grid, [legacy])

	assert_eq(with_unit.cells_of(legacy), [Vector2i(1, 1)] as Array[Vector2i],
		"A unit with no get_footprint() should be treated as 1x1")


func test_two_by_two_unit_covers_four_cells():
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	var cells := adapter.cells_of(boss)
	assert_eq(cells.size(), 4, "A 2x2 unit should cover four cells")
	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		assert_true(c in cells, "2x2 unit anchored at (1,1) should cover %s" % c)


func test_cells_of_null_unit_is_safe():
	var adapter := BoardAdapter.new(grid, [])
	assert_eq(adapter.cells_of(null).size(), 0, "cells_of(null) should return an empty list")


# --- units_at / is_occupied -------------------------------------------------

func test_units_at_finds_large_unit_from_every_covered_cell():
	# The "attack the boss from any side" property.
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		assert_true(boss in adapter.units_at(c),
			"The 2x2 boss should be found from covered cell %s" % c)

	assert_eq(adapter.units_at(Vector2i(0, 1)).size(), 0,
		"A cell outside the footprint should hold no units")
	assert_eq(adapter.units_at(Vector2i(3, 3)).size(), 0,
		"A cell past the footprint should hold no units")


func test_is_occupied_true_for_every_covered_cell():
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	for c in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		assert_true(adapter.is_occupied(c), "Covered cell %s should read as occupied" % c)

	assert_false(adapter.is_occupied(Vector2i(0, 0)), "An uncovered cell should be free")


func test_dead_large_unit_occupies_nothing():
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	boss.hp = 0
	var adapter := BoardAdapter.new(grid, [boss])

	assert_false(adapter.is_occupied(Vector2i(2, 2)),
		"A dead multi-cell unit should not occupy its cells")


# --- can_fit ----------------------------------------------------------------

func test_can_fit_on_clear_ground():
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	assert_true(adapter.can_fit(boss, Vector2i(2, 2)),
		"A 2x2 unit should fit on clear ground with room to spare")


# --- Non-square footprints -----------------------------------------------------
# A square footprint hides an axis swap: with 2x2, mixing up width/height or
# col/row looks identical. These rectangle cases are what actually prove the
# span is oriented correctly.

func test_two_wide_unit_spans_columns_not_rows():
	var wide := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 1))  # 2 wide, 1 deep
	var adapter := BoardAdapter.new(grid, [wide])
	var cells := adapter.cells_of(wide)
	assert_eq(cells.size(), 2)
	assert_has(cells, Vector2i(1, 1), "anchor")
	assert_has(cells, Vector2i(2, 1), "extends along +col")
	assert_does_not_have(cells, Vector2i(1, 2), "must NOT extend along +row")


func test_two_long_unit_spans_rows_not_columns():
	var long_unit := _make_unit(Vector2i(1, 1), owner_a, Vector2i(1, 2))  # 1 wide, 2 deep
	var adapter := BoardAdapter.new(grid, [long_unit])
	var cells := adapter.cells_of(long_unit)
	assert_eq(cells.size(), 2)
	assert_has(cells, Vector2i(1, 1), "anchor")
	assert_has(cells, Vector2i(1, 2), "extends along +row")
	assert_does_not_have(cells, Vector2i(2, 1), "must NOT extend along +col")


func test_units_at_finds_a_rectangular_unit_from_each_covered_cell():
	var wide := _make_unit(Vector2i(0, 0), owner_a, Vector2i(3, 1))
	var adapter := BoardAdapter.new(grid, [wide])
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		assert_has(adapter.units_at(cell), wide, "found from %s" % str(cell))
	assert_eq(adapter.units_at(Vector2i(0, 1)).size(), 0, "the row below is free")


func test_rectangular_fit_is_blocked_on_the_correct_axis():
	var wide := _make_unit(Vector2i(0, 0), owner_a, Vector2i(2, 1))
	var adapter := BoardAdapter.new(grid, [wide])
	# Wall sits to the RIGHT of anchor (1,1): blocks a 2-wide span, not a 2-deep one.
	adapter.set_tile_registry({ Vector2i(2, 1): _wall() })
	assert_false(adapter.can_fit(wide, Vector2i(1, 1)), "2-wide span hits the wall at +col")

	var long_unit := _make_unit(Vector2i(0, 0), owner_b, Vector2i(1, 2))
	var adapter2 := BoardAdapter.new(grid, [long_unit])
	adapter2.set_tile_registry({ Vector2i(2, 1): _wall() })
	assert_true(adapter2.can_fit(long_unit, Vector2i(1, 1)), "2-deep span misses that wall")


func _unit_with_footprint(fp: Vector2i) -> Unit:
	# Drive the REAL Unit.get_footprint()/get_footprint_offset() through a character
	# resource, rather than re-deriving the offset with the same formula.
	var character := CharacterResource.new()
	character.footprint = fp
	# autofree: Unit is a Node3D -- an untracked one is a GUT orphan.
	var u: Unit = autofree(Unit.new())
	u.character_resource = character
	return u


func test_rectangular_visual_offset_is_asymmetric():
	# The model must slide along the axis it actually spans, or a 2-wide unit would
	# sit centred over the wrong pair of cells.
	var wide := _unit_with_footprint(Vector2i(2, 1))
	assert_eq(wide.get_footprint(), Vector2i(2, 1))
	assert_eq(wide.get_footprint_offset(), Vector3(1.0, 0.0, 0.0), "2-wide shifts along X only")
	wide.free()

	var long_unit := _unit_with_footprint(Vector2i(1, 2))
	assert_eq(long_unit.get_footprint_offset(), Vector3(0.0, 0.0, 1.0), "2-deep shifts along Z only")
	long_unit.free()

	var square := _unit_with_footprint(Vector2i(2, 2))
	assert_eq(square.get_footprint_offset(), Vector3(1.0, 0.0, 1.0), "2x2 shifts on both axes")
	square.free()

	var normal := _unit_with_footprint(Vector2i.ONE)
	assert_eq(normal.get_footprint_offset(), Vector3.ZERO, "a 1x1 unit is never offset")
	normal.free()


func test_can_fit_false_when_a_covered_cell_is_blocked():
	var boss := _make_unit(Vector2i(0, 0), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])
	# Only the far corner of the span is a wall; the anchor itself is clear.
	adapter.set_tile_registry({ Vector2i(3, 3): _wall() })

	assert_false(adapter.can_fit(boss, Vector2i(2, 2)),
		"A single blocked cell anywhere in the span should reject the placement")
	assert_true(adapter.can_fit(boss, Vector2i(0, 0)),
		"A span clear of the wall should still fit")


func test_can_fit_false_when_a_covered_cell_holds_another_unit():
	var boss := _make_unit(Vector2i(0, 0), owner_a, Vector2i(2, 2))
	var blocker := _make_unit(Vector2i(3, 3), owner_b)
	var adapter := BoardAdapter.new(grid, [boss, blocker])

	assert_false(adapter.can_fit(boss, Vector2i(2, 2)),
		"Another living unit inside the span should reject the placement")
	assert_true(adapter.can_fit(boss, Vector2i(0, 0)),
		"A span clear of the other unit should still fit")


func test_can_fit_false_when_span_leaves_the_board():
	var boss := _make_unit(Vector2i(0, 0), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	# (4,4) is the last cell of the 5x5 grid, so a 2x2 span there runs off the edge.
	assert_false(adapter.can_fit(boss, Vector2i(4, 4)),
		"A span extending past the grid should be rejected")
	assert_true(adapter.can_fit(boss, Vector2i(3, 3)),
		"A span ending exactly on the last cell should fit")


func test_unit_does_not_block_itself():
	var boss := _make_unit(Vector2i(1, 1), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])

	assert_true(adapter.can_fit(boss, Vector2i(1, 1)),
		"A unit's own cells must never block it at its current anchor")
	assert_true(adapter.can_fit(boss, Vector2i(2, 2)),
		"A unit should be able to shuffle into a span overlapping its own body")


func test_can_fit_for_one_by_one_matches_the_single_cell_check():
	# Backward-compat guard: for a normal unit, can_fit is exactly
	# "in bounds and not blocked and not occupied by someone else".
	var mover := _make_unit(Vector2i(0, 0), owner_a)
	var other := _make_unit(Vector2i(1, 0), owner_b)
	var adapter := BoardAdapter.new(grid, [mover, other])
	adapter.set_tile_registry({ Vector2i(0, 1): _wall() })

	assert_true(adapter.can_fit(mover, Vector2i(0, 0)), "Its own cell is free for it")
	assert_true(adapter.can_fit(mover, Vector2i(2, 2)), "Clear ground fits")
	assert_false(adapter.can_fit(mover, Vector2i(1, 0)), "An occupied cell does not fit")
	assert_false(adapter.can_fit(mover, Vector2i(0, 1)), "A blocked cell does not fit")
	assert_false(adapter.can_fit(mover, Vector2i(5, 0)), "An out-of-bounds cell does not fit")


# --- Movement integration ---------------------------------------------------

func test_large_unit_cannot_stop_where_its_span_does_not_fit():
	var boss := _make_unit(Vector2i(0, 0), owner_a, Vector2i(2, 2))
	var adapter := BoardAdapter.new(grid, [boss])
	adapter.set_tile_registry({ Vector2i(3, 0): _wall() })

	var profile := MovementProfile.create(
		&"boss", "Boss", CombatTypes.MovementKind.GROUND, 4, MovementProfile.Shape.ORTHOGONAL)
	var cells := MovementResolver.new().reachable_cells(Vector2i(0, 0), profile, adapter, boss)

	assert_false(Vector2i(2, 0) in cells,
		"Anchoring at (2,0) would put the span on the wall at (3,0)")
	assert_true(Vector2i(0, 1) in cells,
		"A step whose whole 2x2 span is clear should stay reachable")
	assert_false(Vector2i(4, 0) in cells,
		"A span running off the board's edge is never reachable")


func test_one_by_one_movement_is_unchanged_by_footprint_support():
	var mover := _make_unit(Vector2i(0, 0), owner_a)
	var adapter := BoardAdapter.new(grid, [mover])
	adapter.set_tile_registry({ Vector2i(2, 0): _wall() })

	var profile := MovementProfile.create(
		&"walker", "Walker", CombatTypes.MovementKind.GROUND, 3, MovementProfile.Shape.ORTHOGONAL)
	var resolver := MovementResolver.new()
	var with_unit := resolver.reachable_cells(Vector2i(0, 0), profile, adapter, mover)
	var without_unit := resolver.reachable_cells(Vector2i(0, 0), profile, adapter)

	assert_eq(with_unit, without_unit,
		"Passing a 1x1 unit must not change the reachable set at all")
	assert_false(Vector2i(2, 0) in with_unit, "The wall is still unreachable")


# --- Unit accessor / visual math -------------------------------------------

func test_unit_defaults_to_one_by_one_without_a_character():
	# Not added to the tree: get_footprint() must not depend on _ready()/stats setup.
	var unit: Unit = autofree(Unit.new())
	assert_eq(unit.get_footprint(), Vector2i.ONE,
		"A unit with no character resource should report a 1x1 footprint")
	assert_eq(unit.get_footprint_offset(), Vector3.ZERO,
		"A 1x1 unit needs no visual offset")
	unit.apply_footprint_visual()  # no mesh, no character -- must not error


func test_character_footprint_is_read_and_guarded():
	var character := CharacterResource.new()
	character.footprint = Vector2i(2, 2)
	var unit: Unit = autofree(Unit.new())
	unit.character_resource = character
	assert_eq(unit.get_footprint(), Vector2i(2, 2), "The character's footprint should be used")

	# A 2x2 span centers half a cell (cell_size 2.0 -> 1.0) along +X and +Z.
	assert_eq(unit.get_footprint_offset(), Vector3(1.0, 0.0, 1.0),
		"A 2x2 model should be offset to the center of its covered block")

	character.footprint = Vector2i(0, -3)
	assert_eq(unit.get_footprint(), Vector2i.ONE,
		"A zero/negative authored footprint should be guarded back to 1x1")
