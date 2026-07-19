extends GutTest

# Terrain avoid: a tile's passive +evasion (e.g. tall grass) lowers the attacker's
# hit chance, computed at combat time (the FE model). Also verifies that MULTIPLE
# effects on one cell coexist -- a tall-grass (+evasion) tile that is also on fire
# still contributes its evasion layer -- which is the user's "long grass that
# catches fire = two effects" scenario.

class MockUnit:
	var team: int
	var stats: Dictionary
	func _init(t: int, s: Dictionary) -> void:
		team = t
		stats = s
	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_hp() -> int:
		return stats.get("health", 100)
	func take_damage(_n: int) -> void:
		pass

# Board where cell (1,0) is tall grass (+15 evasion). extra_burn adds a second,
# non-evasion effect on that same cell to prove effects stack.
class GrassBoard:
	var grass_cell := Vector2i(1, 0)
	var placements := {}
	var extra_burn := false
	func place(u, c: Vector2i) -> void:
		placements[u] = c
	func cell_of(u) -> Vector2i:
		return placements.get(u, Vector2i(-999, -999))
	func tile_effects_at(c: Vector2i) -> Array:
		if c != grass_cell:
			return []
		var out: Array = [_tall_grass()]
		if extra_burn:
			out.append(_burn())  # a second effect on the same cell (no evasion)
		return out
	func _tall_grass() -> TileEffectResource:
		var te := TileEffectResource.new()
		te.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
		var buff := StatModifierEffect.new()
		buff.stat_name = "evasion"
		buff.amount = 15
		te.effects = [buff]
		return te
	func _burn() -> TileEffectResource:
		var te := TileEffectResource.new()
		te.trigger = TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING
		var dmg := StatModifierEffect.new()
		dmg.stat_name = "health"
		dmg.amount = -5
		te.effects = [dmg]
		return te


func _move(acc: float) -> MoveResource:
	var m := MoveResource.new()
	m.accuracy = acc
	return m


func test_terrain_evasion_lowers_hit_chance() -> void:
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "evasion": 0 })
	var board := GrassBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, board.grass_cell)
	var ctx := MoveContext.new(caster, board, _move(1.0), Vector2i.ZERO, [] as Array[Vector2i])
	assert_eq(ctx.hit_chance(target), 85.0, "100% accuracy - 15 terrain evasion = 85%")


func test_no_terrain_means_no_avoid() -> void:
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "evasion": 0 })
	var board := GrassBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(5, 5))  # bare ground, no tile effect
	var ctx := MoveContext.new(caster, board, _move(1.0), Vector2i.ZERO, [] as Array[Vector2i])
	assert_eq(ctx.hit_chance(target), 100.0, "no terrain => full accuracy")


func test_multiple_effects_on_one_cell_still_grant_evasion() -> void:
	# Tall grass AND a burn share the cell; TerrainStats reads only the evasion
	# layer, so avoid is unchanged and the two effects coexist.
	var caster := MockUnit.new(0, {})
	var target := MockUnit.new(1, { "evasion": 0 })
	var board := GrassBoard.new()
	board.extra_burn = true
	board.place(caster, Vector2i(0, 0))
	board.place(target, board.grass_cell)
	assert_eq(board.tile_effects_at(board.grass_cell).size(), 2, "cell holds two effects")
	var ctx := MoveContext.new(caster, board, _move(1.0), Vector2i.ZERO, [] as Array[Vector2i])
	assert_eq(ctx.hit_chance(target), 85.0, "evasion layer still applies through the burn")


func test_terrain_stats_helper_sums_matching_stat() -> void:
	var target := MockUnit.new(1, {})
	var board := GrassBoard.new()
	board.place(target, board.grass_cell)
	assert_eq(TerrainStats.bonus_for(target, "evasion", board), 15)
	assert_eq(TerrainStats.bonus_for(target, "crit", board), 0, "unrelated stat => 0")
