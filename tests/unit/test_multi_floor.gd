extends GutTest

## Multi-floor maps (docs/MULTI_FLOOR.md): data model, movement, targeting / LOS,
## height advantage and AI. Most tests run on the tiny fixture map
## res://game/maps/resources/test_bridge_map.tres (built by
## game/maps/build_test_bridge_map.gd), loaded straight into a headless
## BoardAdapter via configure_from_map -- no scene required.
##
## Fixture (9 x 7): river down column 4 (deep water), wall at (4,5,0);
##   floor 1 INTACT bridge row 1, x 2..6 (stairs: (1,1,0)->(2,1,1), (7,1,0)->(6,1,1));
##   floor 1 BROKEN bridge row 3, x 2,3 | 5,6 (gap at x 4; ladders cost 2 at both ends).

const MAP_PATH := "res://game/maps/resources/test_bridge_map.tres"
const BuildBridge := preload("res://game/maps/build_test_bridge_map.gd")


class MockUnit extends RefCounted:
	## The movement budget is the unit's "movement" stat (merged rule); tests set it via _profile().
	static var default_movement: int = 0
	var position: Vector3 = Vector3.ZERO
	var owner_player = null
	var hp: int = 100
	var stats: Dictionary = {}
	func get_stat(n: String) -> int:
		if n == "movement" and not stats.has(n):
			return default_movement
		return int(stats.get(n, 0))
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func is_alive() -> bool:
		return hp > 0


class MockOwner extends RefCounted:
	var id: int = 0


var grid: Grid
var p0: MockOwner
var p1: MockOwner


func before_each() -> void:
	grid = Grid.new()
	grid.size = Vector3(9, 0, 7)
	p0 = MockOwner.new()
	p0.id = 0
	p1 = MockOwner.new()
	p1.id = 1


# --- Helpers ------------------------------------------------------------------

func _map() -> MapResource:
	return load(MAP_PATH) as MapResource


func _board(units: Array) -> BoardAdapter:
	return BoardAdapter.new(grid, units).configure_from_map(_map())


func _unit(board_or_null, cell: Vector3i, owner, stats: Dictionary = {}) -> MockUnit:
	var u := MockUnit.new()
	var tmp := BoardAdapter.new(grid, [])
	u.position = tmp.cell_to_world(cell) + Vector3(0, 0.1, 0)  # tile-top, like MapLoader
	u.owner_player = owner
	u.stats = stats
	return u


func _profile(kind: CombatTypes.MovementKind, r: int) -> MovementProfile:
	MockUnit.default_movement = r
	return MovementProfile.create(&"t", "t", kind, r, MovementProfile.Shape.ORTHOGONAL)


func _ranged(min_r: int, max_r: int, power: int = 20) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_shot"
	m.accuracy = 0.9
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = min_r
	p.max_range = max_r
	m.targeting = p
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.category = CombatTypes.DamageCategory.TRUE
	m.effects = [d]
	return m


# --- Map data -------------------------------------------------------------------

func test_fixture_file_matches_builder() -> void:
	var file := _map()
	var built: MapResource = BuildBridge.build()
	assert_not_null(file, "fixture map exists")
	assert_eq(file.tile_layout.size(), built.tile_layout.size(), "saved fixture is up to date with its builder")
	assert_eq(file.get_links().size(), built.get_links().size())
	assert_true(file.validate_map().valid, "fixture validates: %s" % str(file.validate_map().issues))


func test_map_floor_queries() -> void:
	var m := _map()
	assert_eq(m.get_floor_count(), 2)
	assert_eq(m.get_floors_at(Vector2i(3, 1)), [0, 1] as Array[int], "bridge column has ground + deck")
	assert_eq(m.get_floors_at(Vector2i(4, 3)), [0] as Array[int], "broken-bridge gap has only the river")
	assert_true(m.has_tile_at(Vector2i(4, 1), 1))
	assert_false(m.has_tile_at(Vector2i(4, 3), 1), "the gap is air")
	assert_true(m.get_tile_at_position(Vector2i(4, 3), 1).is_empty(), "no entry above the gap")
	assert_eq(m.get_tiles_on_floor(1).size(), 9, "5 intact + 4 broken deck tiles")


func test_links_include_explicit_and_stairs() -> void:
	var links := _map().get_links()
	assert_eq(links.size(), 4)
	var found_stairs := false
	var found_ladder := false
	for l in links:
		if l["from"] == Vector3i(1, 1, 0) and l["to"] == Vector3i(2, 1, 1):
			found_stairs = l["kind"] == "stairs"
		if l["from"] == Vector3i(1, 3, 0) and l["to"] == Vector3i(2, 3, 1):
			found_ladder = l["kind"] == "ladder" and l["cost"] == 2
	assert_true(found_stairs, "the east-facing stair tile generates a link up onto the deck")
	assert_true(found_ladder, "explicit ladder link keeps its kind and cost")


func test_floor_key_only_written_above_ground() -> void:
	var m := MapResource.new()
	m.width = 4
	m.height = 4
	m.set_tile_at_position(Vector2i(1, 1), "NORMAL", "", &"grass_plains")
	m.set_tile_at_position(Vector2i(1, 1), "NORMAL", "", &"forest_dirt", 1)
	assert_eq(m.tile_layout.size(), 2, "(position, floor) is the key -- both entries coexist")
	assert_false(m.get_tile_at_position(Vector2i(1, 1)).has("floor"), "ground entries keep the legacy schema")
	assert_eq(int(m.get_tile_at_position(Vector2i(1, 1), 1)["floor"]), 1)
	m.remove_tile_at_position(Vector2i(1, 1), 1)
	assert_false(m.has_tile_at(Vector2i(1, 1), 1))
	assert_true(m.has_tile_at(Vector2i(1, 1), 0))


func test_json_round_trip_keeps_floors_links_and_spawns() -> void:
	var src := _map()
	var json := src.export_to_json()
	var back := MapResource.import_from_json(json)
	assert_not_null(back)
	assert_eq(back.tile_layout.size(), src.tile_layout.size())
	assert_eq(back.get_floor_count(), 2)
	assert_eq(back.get_floors_at(Vector2i(3, 1)), [0, 1] as Array[int])
	assert_eq(back.get_links().size(), 4, "explicit links and stair flags both survive")
	assert_true(back.get_tile_at_position(Vector2i(2, 1), 0).get("position") is Vector2i, "positions come back as Vector2i")
	var archer := back.get_unit_spawn_at_position(Vector2i(5, 1), 1)
	assert_false(archer.is_empty(), "the floor-1 spawn survives")
	assert_eq(String(archer.get("character_id", "")), "petalfang")
	assert_true(back.validate_map().valid, str(back.validate_map().issues))


func test_json_import_reads_legacy_stringified_positions() -> void:
	var legacy := '{"map_info": {"name": "Legacy"}, "dimensions": {"width": 5, "height": 5}, "layout": {"tiles": [{"position": "(1, 2)", "tile_type": "NORMAL"}], "unit_spawns": [{"position": "(0, 0)", "player_id": 0}, {"position": "(4, 4)", "player_id": 1}]}}'
	var m := MapResource.import_from_json(legacy)
	assert_eq(MapResource.entry_position(m.tile_layout[0]), Vector2i(1, 2))
	assert_eq(m.get_floor_count(), 1)
	assert_eq(m.get_links().size(), 0)


func test_legacy_map_loads_as_single_floor() -> void:
	var m := load("res://game/maps/resources/skirmish_arena.tres") as MapResource
	assert_not_null(m)
	assert_eq(m.get_floor_count(), 1, "pre-multi-floor maps are all floor 0")
	assert_eq(m.get_links().size(), 0)
	var g := Grid.new()
	g.size = Vector3(m.width, 0, m.height)
	var b := BoardAdapter.new(g, []).configure_from_map(m)
	assert_eq(b.floor_count(), 1)
	assert_true(b.has_tile(Vector3i(0, 0, 0)))
	assert_false(b.in_bounds(Vector3i(0, 0, 1)), "there is no floor 1 on a legacy map")


# --- Board structure --------------------------------------------------------------

func test_board_floor_structure() -> void:
	var b := _board([])
	assert_eq(b.floor_count(), 2)
	assert_true(b.has_tile(Vector3i(3, 1, 1)), "bridge deck")
	assert_true(b.has_tile(Vector3i(3, 1, 0)), "ground under the bridge")
	assert_false(b.has_tile(Vector3i(4, 3, 1)), "broken-bridge gap is air")
	assert_eq(b.floors_at(Vector2i(3, 1)), [0, 1] as Array[int])
	assert_eq(b.top_floor_at(Vector2i(4, 3)), 0)
	assert_eq(b.top_floor_at(Vector2i(4, 1)), 1)
	assert_eq(b.cells_on_floor(1).size(), 9)
	assert_true(b.are_linked(Vector3i(1, 1, 0), Vector3i(2, 1, 1)))
	assert_true(b.are_linked(Vector3i(2, 1, 1), Vector3i(1, 1, 0)), "links are bidirectional by default")
	assert_almost_eq(b.cell_to_world(Vector3i(3, 1, 1)).y, Cells.FLOOR_HEIGHT, 0.001)


func test_units_under_and_on_bridge_coexist() -> void:
	var under := _unit(null, Vector3i(3, 1, 0), p0)
	var over := _unit(null, Vector3i(3, 1, 1), p1)
	var b := _board([under, over])
	assert_eq(b.cell_of(under), Vector3i(3, 1, 0))
	assert_eq(b.cell_of(over), Vector3i(3, 1, 1))
	assert_eq(b.units_at(Vector3i(3, 1, 0)), [under], "occupancy is per floor")
	assert_eq(b.units_at(Vector3i(3, 1, 1)), [over])
	assert_eq(b.units_on_floor(1), [over])


func test_move_unit_changes_floor_height() -> void:
	var u := _unit(null, Vector3i(1, 1, 0), p0)
	var b := _board([u])
	b.move_unit(u, Vector3i(2, 1, 1))
	assert_eq(b.cell_of(u), Vector3i(2, 1, 1))
	assert_almost_eq(u.position.y, Cells.FLOOR_HEIGHT + 0.1, 0.001, "lifted a whole floor, tile-top offset kept")


# --- Movement ---------------------------------------------------------------------

func test_ground_unit_passes_under_the_bridge() -> void:
	var walker := _unit(null, Vector3i(3, 0, 0), p0)
	var blocker_on_deck := _unit(null, Vector3i(3, 1, 1), p1)  # standing right above the path
	var b := _board([walker, blocker_on_deck])
	var r := MovementResolver.new()
	var cells := r.reachable_cells(Vector3i(3, 0, 0), _profile(CombatTypes.MovementKind.GROUND, 2), b, walker)
	assert_true(cells.has(Vector3i(3, 2, 0)), "walks under the bridge (the unit ON it is a floor above)")
	assert_eq(r.path_to(Vector3i(3, 2, 0)), [Vector3i(3, 0, 0), Vector3i(3, 1, 0), Vector3i(3, 2, 0)] as Array[Vector3i])
	assert_false(cells.has(Vector3i(3, 1, 1)), "cannot jump up onto the deck without stairs")


func test_broken_bridge_gap_blocks_ground_units() -> void:
	var u := _unit(null, Vector3i(3, 3, 1), p0)
	var b := _board([u])
	var cells := MovementResolver.new().reachable_cells(Vector3i(3, 3, 1), _profile(CombatTypes.MovementKind.GROUND, 5), b, u)
	assert_false(cells.has(Vector3i(4, 3, 1)), "never stops in the gap")
	assert_false(cells.has(Vector3i(5, 3, 1)), "cannot cross the gap")
	assert_true(cells.has(Vector3i(2, 3, 1)), "can walk along its half of the deck")
	assert_false(cells.has(Vector3i(3, 2, 1)), "cannot walk off the side of the deck into the air")
	assert_true(cells.has(Vector3i(1, 3, 0)), "can climb down the ladder")


func test_flier_crosses_the_gap() -> void:
	var u := _unit(null, Vector3i(3, 3, 1), p0)
	var b := _board([u])
	var r := MovementResolver.new()
	var cells := r.reachable_cells(Vector3i(3, 3, 1), _profile(CombatTypes.MovementKind.FLYING, 2), b, u)
	assert_true(cells.has(Vector3i(5, 3, 1)), "flies straight across the gap")
	assert_false(cells.has(Vector3i(4, 3, 1)), "but never stops in mid-air")
	assert_eq(r.path_to(Vector3i(5, 3, 1)), [Vector3i(3, 3, 1), Vector3i(4, 3, 1), Vector3i(5, 3, 1)] as Array[Vector3i])
	assert_true(cells.has(Vector3i(3, 3, 0)), "fliers can drop straight down a floor")


func test_stairs_link_movement_and_cost() -> void:
	var u := _unit(null, Vector3i(0, 1, 0), p0)
	var b := _board([u])
	var r := MovementResolver.new()
	var cells := r.reachable_cells(Vector3i(0, 1, 0), _profile(CombatTypes.MovementKind.GROUND, 2), b, u)
	assert_true(cells.has(Vector3i(2, 1, 1)), "one step to the stair foot, one step up the stairs")
	assert_eq(r.cost_to(Vector3i(2, 1, 1)), 2)
	assert_eq(r.path_to(Vector3i(2, 1, 1)), [Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(2, 1, 1)] as Array[Vector3i])
	var short := MovementResolver.new().reachable_cells(Vector3i(0, 1, 0), _profile(CombatTypes.MovementKind.GROUND, 1), b, u)
	assert_false(short.has(Vector3i(2, 1, 1)), "out of budget")


func test_ladder_link_uses_its_own_cost() -> void:
	var u := _unit(null, Vector3i(0, 3, 0), p0)
	var b := _board([u])
	var r := MovementResolver.new()
	var cells := r.reachable_cells(Vector3i(0, 3, 0), _profile(CombatTypes.MovementKind.GROUND, 3), b, u)
	assert_true(cells.has(Vector3i(2, 3, 1)))
	assert_eq(r.cost_to(Vector3i(2, 3, 1)), 3, "1 to the ladder foot + ladder cost 2")
	var r2 := MovementResolver.new()
	assert_false(r2.reachable_cells(Vector3i(0, 3, 0), _profile(CombatTypes.MovementKind.GROUND, 2), b, u).has(Vector3i(2, 3, 1)))


func test_occupied_stair_top_blocks_the_climb() -> void:
	var u := _unit(null, Vector3i(0, 1, 0), p0)
	var guard := _unit(null, Vector3i(2, 1, 1), p1)
	var b := _board([u, guard])
	var cells := MovementResolver.new().reachable_cells(Vector3i(0, 1, 0), _profile(CombatTypes.MovementKind.GROUND, 4), b, u)
	assert_false(cells.has(Vector3i(3, 1, 1)), "the guard on the stair top holds the bridge")


# --- Targeting / LOS ----------------------------------------------------------------

func test_melee_cannot_hit_directly_above() -> void:
	var a := _unit(null, Vector3i(3, 1, 0), p0, { "attack": 10 })
	var t := _unit(null, Vector3i(3, 1, 1), p1)
	var b := _board([a, t])
	var strike := MoveLibrary.basic_strike()
	assert_false(strike.can_target(Vector3i(3, 1, 0), Vector3i(3, 1, 1), a, b))
	var res := MoveExecutor.execute(strike, a, b, Vector3i(3, 1, 1))
	assert_false(res.success, "the executor rejects it too")
	assert_eq(t.hp, 100)


func test_melee_reaches_across_a_stair_link_only() -> void:
	var a := _unit(null, Vector3i(1, 1, 0), p0, { "attack": 10 })
	var t := _unit(null, Vector3i(2, 1, 1), p1)
	var b := _board([a, t])
	var strike := MoveLibrary.basic_strike()
	assert_true(strike.can_target(Vector3i(1, 1, 0), Vector3i(2, 1, 1), a, b), "stair foot -> stair top")
	assert_true(strike.can_target(Vector3i(2, 1, 1), Vector3i(1, 1, 0), t, b), "and back down")
	assert_false(strike.can_target(Vector3i(2, 2, 0), Vector3i(2, 1, 1), a, b), "adjacent-but-below without a link is out of reach")
	# Seeded: the lower attacker has a hit penalty, so an unseeded roll made this
	# test flaky (an occasional miss left hp at 100).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var res := MoveExecutor.execute(strike, a, b, Vector3i(2, 1, 1), rng)
	assert_true(res.success)
	assert_lt(t.hp, 100)


func test_ranged_across_floors_with_clear_los() -> void:
	var archer := _unit(null, Vector3i(6, 1, 1), p0)
	var t := _unit(null, Vector3i(8, 1, 0), p1)
	var b := _board([archer, t])
	var shot := _ranged(1, 4)
	assert_true(shot.can_target(Vector3i(6, 1, 1), Vector3i(8, 1, 0), archer, b), "open ground beside the bridge end")
	assert_true(LineOfSight.has_line_of_sight(b, Vector3i(8, 1, 0), Vector3i(6, 1, 1)), "and from below, up at the edge")


func test_los_blocked_by_ceiling() -> void:
	var b := _board([])
	# The unit under the deck is covered from the deck, both ways.
	assert_false(LineOfSight.has_line_of_sight(b, Vector3i(6, 1, 1), Vector3i(5, 1, 0)))
	assert_false(LineOfSight.has_line_of_sight(b, Vector3i(5, 1, 0), Vector3i(6, 1, 1)))
	# Directly above/below through the deck.
	assert_false(LineOfSight.has_line_of_sight(b, Vector3i(3, 1, 0), Vector3i(3, 1, 1)))
	# Shooting down from deep inside the deck passes through the deck itself.
	assert_false(LineOfSight.has_line_of_sight(b, Vector3i(3, 1, 1), Vector3i(3, 3, 0)),
		"the target is covered by the broken bridge's deck at (3,3,1)")
	# Units on the ground shoot freely UNDER the bridge.
	assert_true(LineOfSight.has_line_of_sight(b, Vector3i(3, 0, 0), Vector3i(3, 2, 0)))
	var archer := _unit(null, Vector3i(6, 1, 1), p0)
	var hidden := _unit(null, Vector3i(5, 1, 0), p1)
	var b2 := _board([archer, hidden])
	assert_false(_ranged(1, 4).can_target(Vector3i(6, 1, 1), Vector3i(5, 1, 0), archer, b2), "is_aim_allowed honours LOS")


func test_los_blocked_by_wall() -> void:
	# Same-floor: walls only matter for LosMode.ALWAYS (AUTO keeps legacy behaviour).
	var b := _board([])
	assert_false(LineOfSight.has_line_of_sight(b, Vector3i(2, 5, 0), Vector3i(6, 5, 0), true), "the wall at (4,5,0)")
	var shot := _ranged(1, 4)
	assert_true(shot.can_target(Vector3i(2, 5, 0), Vector3i(6, 5, 0), null, b), "AUTO ignores same-floor LOS")
	shot.targeting.line_of_sight = TargetingPattern.LosMode.ALWAYS
	assert_false(shot.can_target(Vector3i(2, 5, 0), Vector3i(6, 5, 0), null, b), "ALWAYS respects the wall")
	# Cross-floor: a tower top shooting down past a wall on the ground.
	var g := Grid.new()
	g.size = Vector3(6, 0, 1)
	var wall := load("res://game/tiles/resources/common/stone_wall.tres")
	var tower := BoardAdapter.new(g, [])
	tower.set_tile_registry({ Vector3i(2, 0, 0): wall })
	tower.set_present_cells({ Vector3i(0, 0, 1): true })
	assert_false(LineOfSight.has_line_of_sight(tower, Vector3i(0, 0, 1), Vector3i(4, 0, 0)), "wall in between at shot height")
	tower.set_tile_registry({})
	assert_true(LineOfSight.has_line_of_sight(tower, Vector3i(0, 0, 1), Vector3i(4, 0, 0)), "clear without the wall")
	shot.targeting.line_of_sight = TargetingPattern.LosMode.NEVER
	tower.set_tile_registry({ Vector3i(2, 0, 0): wall })
	assert_true(shot.can_target(Vector3i(0, 0, 1), Vector3i(4, 0, 0), null, tower), "NEVER skips LOS entirely")


# --- Height advantage ------------------------------------------------------------------

func test_height_advantage_range() -> void:
	var p := _ranged(1, 3).targeting
	assert_true(p.in_range(Vector3i(0, 0, 1), Vector3i(3, 0, 0)), "3 across + 1 down = 4 <= 3 + high-ground bonus")
	assert_false(p.in_range(Vector3i(3, 0, 0), Vector3i(0, 0, 1)), "shooting UP gets no bonus: 4 > 3")
	assert_true(p.in_range(Vector3i(0, 0, 0), Vector3i(3, 0, 0)), "same floor unchanged")
	assert_false(p.in_range(Vector3i(0, 0, 0), Vector3i(4, 0, 0)), "same floor unchanged")
	var melee := MoveLibrary.basic_strike().targeting
	assert_false(melee.in_range(Vector3i(0, 0, 1), Vector3i(1, 0, 0)), "melee gets no height reach")


func test_height_advantage_damage_and_hit() -> void:
	var hi := _unit(null, Vector3i(6, 1, 1), p0)
	var lo := _unit(null, Vector3i(8, 1, 0), p1)
	var b := _board([hi, lo])
	var shot := _ranged(1, 4, 20)
	var down := MoveExecutor.preview_vs(shot, hi, lo, b)
	var up := MoveExecutor.preview_vs(shot, lo, hi, b)
	assert_eq(int(down["damage"]), roundi(20 * Elevation.HIGH_GROUND_DAMAGE_SCALE))
	assert_eq(int(up["damage"]), roundi(20 * Elevation.LOW_GROUND_DAMAGE_SCALE))
	assert_almost_eq(float(down["hit_pct"]), 90.0 + Elevation.HIGH_GROUND_HIT_BONUS, 0.01)
	assert_almost_eq(float(up["hit_pct"]), 90.0 - Elevation.LOW_GROUND_HIT_PENALTY, 0.01)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var res := MoveExecutor.execute(shot, hi, b, Vector3i(8, 1, 0), rng)
	assert_true(res.success)
	assert_eq(lo.hp, 100 - roundi(20 * Elevation.HIGH_GROUND_DAMAGE_SCALE), "resolution matches the forecast")


func test_same_floor_has_no_height_modifiers() -> void:
	var a := _unit(null, Vector3i(0, 0, 0), p0)
	var t := _unit(null, Vector3i(2, 0, 0), p1)
	var b := _board([a, t])
	assert_eq(Elevation.damage_scale_for(a, t, b), 1.0)
	assert_eq(Elevation.hit_modifier_for(a, t, b), 0.0)


func test_aoe_stays_on_the_aim_floor() -> void:
	var p := TargetingPattern.new()
	p.area_shape = CombatTypes.AreaShape.DIAMOND
	p.area_size = 1
	for c in p.resolve_cells(Vector3i(0, 1, 0), Vector3i(3, 1, 1)):
		assert_eq(c.z, 1, "AOE cells never spill onto another floor")


# --- AI ------------------------------------------------------------------------------

## 8 x 3 board: floor-1 platform x 4..7 (all rows) + a walkway x 1..3 on row 0, and a
## single staircase (0,0,0) <-> (1,0,1). The target stands on the platform; the only
## way up is back at the stairs, so hugging the platform's base is a dead end.
func _platform_board(units: Array) -> BoardAdapter:
	var g := Grid.new()
	g.size = Vector3(8, 0, 3)
	var b := BoardAdapter.new(g, units)
	var present := {}
	for x in range(4, 8):
		for y in range(3):
			present[Vector3i(x, y, 1)] = true
	for x in range(1, 4):
		present[Vector3i(x, 0, 1)] = true
	b.set_present_cells(present)
	b.set_links([{ "from": Vector3i(0, 0, 0), "to": Vector3i(1, 0, 1) }])
	return b


func test_ai_takes_the_stairs_toward_an_upper_floor_target() -> void:
	var g := Grid.new()
	g.size = Vector3(8, 0, 3)
	var bot := MockUnit.new()
	bot.position = BoardAdapter.new(g, []).cell_to_world(Vector3i(2, 2, 0))
	bot.owner_player = p1
	bot.stats = { "attack": 5 }
	var target := MockUnit.new()
	target.position = BoardAdapter.new(g, []).cell_to_world(Vector3i(6, 1, 1))
	target.owner_player = p0
	var b := _platform_board([bot, target])
	var reach := MovementResolver.new().reachable_cells(Vector3i(2, 2, 0), _profile(CombatTypes.MovementKind.GROUND, 3), b, bot)
	assert_true(reach.has(Vector3i(5, 2, 0)), "the dead-end under the platform IS reachable (and closer by Manhattan)")
	var decision := BotController.new().plan(bot, [MoveLibrary.basic_strike()], b, reach)
	assert_eq(int(decision["action"]), BotController.ActionType.STEP)
	var dest: Vector3i = decision["dest_cell"]
	assert_true(dest.x <= 1, "the bot heads for the stairs, not under the platform (went to %s)" % str(dest))
	assert_lt(BotController._travel_distance(dest, Vector3i(6, 1, 1), b), BotController._travel_distance(Vector3i(2, 2, 0), Vector3i(6, 1, 1), b),
		"and actually gets closer by walking distance")


func test_ai_attacks_across_a_link_from_the_stair_foot() -> void:
	var bot := _unit(null, Vector3i(0, 1, 0), p1, { "attack": 10 })
	var target := _unit(null, Vector3i(2, 1, 1), p0)
	var b := _board([bot, target])
	var reach := MovementResolver.new().reachable_cells(Vector3i(0, 1, 0), _profile(CombatTypes.MovementKind.GROUND, 1), b, bot)
	var decision := BotController.new().plan(bot, [MoveLibrary.basic_strike()], b, reach)
	assert_eq(int(decision["action"]), BotController.ActionType.MOVE, "strikes up the stairs")
	assert_eq(decision["dest_cell"], Vector3i(1, 1, 0))
	assert_eq(decision["aim_cell"], Vector3i(2, 1, 1))


# --- Cells helper -----------------------------------------------------------------

func test_cells_helpers_round_trip() -> void:
	var c := Cells.make(3, 4, 2)
	assert_eq(Cells.floor_of(c), 2)
	assert_eq(Cells.flat(c), Vector2i(3, 4))
	assert_eq(Cells.lift(Vector2i(3, 4), 2), c)
	assert_eq(Cells.from_variant(Cells.to_array(c)), c)
	assert_eq(Cells.from_variant(JSON.parse_string(JSON.stringify(Cells.to_array(c)))), c, "survives JSON (floats)")
	assert_eq(Cells.from_variant("(3, 4, 2)"), c)
	assert_eq(Cells.from_variant(Vector2i(3, 4)), Vector3i(3, 4, 0))
	assert_eq(Cells.from_grid(Cells.to_grid(c)), c)
	assert_eq(Cells.world_to_cell(Cells.cell_to_world(c) + Vector3(0.3, 0.1, -0.4)), c)
	assert_eq(Cells.distance(Vector3i(0, 0, 0), Vector3i(2, 1, 1)), 4)
	assert_eq(Cells.manhattan_2d(Vector3i(0, 0, 0), Vector3i(2, 1, 1)), 3)
	assert_eq(Cells.floor_from_world_y(1.5), 0, "legacy unit height still reads as the ground floor")
	assert_eq(Cells.floor_from_world_y(Cells.FLOOR_HEIGHT - 0.2), 1, "a unit dipping just under its deck is still upstairs")
