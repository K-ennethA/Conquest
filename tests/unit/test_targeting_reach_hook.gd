extends GutTest

## The duel's one targeting seam (docs/design/DUEL_BATTLE.md §3.2): a board may declare
## reach_is_unbounded(), which skips ONLY the range test. Tactical boards never declare it,
## the narrowing constraints still narrow, and the authored ranges are never rewritten.


## A board that says distance is abstract, with the queries the constraints ask.
class UnboundedBoard:
	extends RefCounted
	var fit: bool = true
	func reach_is_unbounded() -> bool:
		return true
	func cell_of(_u) -> Vector3i:
		return Vector3i.ZERO
	func can_fit(_u, _c) -> bool:
		return fit
	func units_at(_c) -> Array:
		return []
	func are_enemies(_a, _b) -> bool:
		return false


## An aim rule that refuses every cell.
class RefuseAll:
	extends Resource
	func allows_aim(_o, _a, _c, _b) -> bool:
		return false


func _pattern(min_r: int, max_r: int) -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = min_r
	p.max_range = max_r
	return p


func test_board_adapter_never_declares_unbounded_reach() -> void:
	var tactical := BoardAdapter.new(null, [])
	assert_false(tactical.has_method("reach_is_unbounded"), "tactical boards never declare the hook")
	assert_false(TargetingPattern.reach_is_unbounded(tactical))
	assert_false(TargetingPattern.reach_is_unbounded(null), "no board = bounded")
	var p := _pattern(1, 1)
	assert_false(p.in_reach(Vector3i.ZERO, Vector3i(4, 0, 0), tactical), "a melee move still cannot reach 4 cells")
	assert_false(p.is_aim_allowed(Vector3i.ZERO, Vector3i(4, 0, 0), null, tactical))


func test_unbounded_board_admits_any_aim_including_dead_zones() -> void:
	var board := UnboundedBoard.new()
	var melee := _pattern(1, 1)
	var lob := _pattern(2, 3)  # Strangling Roots' dead zone up close
	for aim in [Vector3i(4, 0, 0), Vector3i(12, 0, 0), Vector3i(1, 0, 0), Vector3i.ZERO]:
		assert_true(melee.in_reach(Vector3i.ZERO, aim, board), "melee reaches %s" % str(aim))
		assert_true(melee.is_aim_allowed(Vector3i.ZERO, aim, null, board))
	assert_true(lob.is_aim_allowed(Vector3i.ZERO, Vector3i(1, 0, 0), null, board),
		"the min-range dead zone is part of the skipped range test")


func test_narrowing_constraints_still_apply_on_an_unbounded_board() -> void:
	var board := UnboundedBoard.new()
	var leap := _pattern(1, 1)
	leap.requires_empty_cell = true
	board.fit = false
	assert_false(leap.is_aim_allowed(Vector3i.ZERO, Vector3i(4, 0, 0), null, board),
		"requires_empty_cell still refuses a cell nobody can land on")
	board.fit = true
	assert_true(leap.is_aim_allowed(Vector3i.ZERO, Vector3i(4, 0, 0), null, board))

	var adjacent := _pattern(1, 1)
	adjacent.requires_adjacent_enemy = true
	assert_false(adjacent.is_aim_allowed(Vector3i.ZERO, Vector3i(4, 0, 0), null, board),
		"requires_adjacent_enemy still narrows")

	var ruled := _pattern(1, 9)
	ruled.aim_rule = RefuseAll.new()
	assert_false(ruled.is_aim_allowed(Vector3i.ZERO, Vector3i(4, 0, 0), null, board),
		"an aim_rule still has the last word")


func test_authored_ranges_are_untouched_so_weather_still_reads_ranged() -> void:
	var storm: WeatherResource = Weather.get_weather(&"desert_storm")
	assert_not_null(storm, "Desert Storm ships")
	var lance: MoveResource = load("res://game/combat/moves/refraction_lance.tres")
	var long_shot := lance.duplicate(false) as MoveResource
	long_shot.targeting = _pattern(1, maxi(4, storm.ranged_min_range))
	var compiled: MoveResource = DuelMoveCompiler.compile_move(long_shot)["move"]
	assert_eq(compiled.targeting.max_range, long_shot.targeting.max_range,
		"the compiler never rewrites max_range")
	assert_true(Weather.is_ranged(compiled, storm),
		"a max-range-%d move is still ranged on a duel board" % compiled.targeting.max_range)
	var board := UnboundedBoard.new()
	assert_true(compiled.can_aim_at(Vector3i.ZERO, Vector3i(4, 0, 0), null, board))
