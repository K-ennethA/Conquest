extends GutTest

# Tests for the sample content (SampleRoster): the built move pool and character
# roster, plus one end-to-end move resolution through MoveExecutor against a
# lightweight mock board. Mocks mirror the style in test_move_system.gd so no
# scene tree / live board is required.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var modifiers: Array = []
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = stats.get("health", 100)
	func get_stat(name: String) -> int:
		return stats.get(name, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp += n
	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()

class MockBoard:
	var placements: Array = []  # { unit, cell }
	var tiles: Dictionary = {}
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func set_tile(cell: Vector2i, tile_id) -> void:
		tiles[cell] = tile_id
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell

# --- Roster shape ----------------------------------------------------------

func test_every_character_has_exactly_four_valid_moves():
	for c in SampleRoster.build_roster():
		assert_eq(c.move_count(), 4,
			"%s carries exactly 4 moves" % c.display_name)
		assert_eq(c.moveset.size(), 4,
			"%s moveset holds 4 entries (no overflow/underflow)" % c.display_name)
		for slot in range(4):
			assert_not_null(c.get_move(slot),
				"%s slot %d is populated" % [c.display_name, slot])
		var v := c.validate()
		assert_true(v.valid,
			"%s passes CharacterResource.validate(): %s" % [c.display_name, v.issues])

func test_character_ids_are_unique():
	var seen: Array = []
	for c in SampleRoster.build_roster():
		assert_false(String(c.character_id).is_empty(),
			"%s has a non-empty character_id" % c.display_name)
		assert_false(c.character_id in seen,
			"character_id '%s' is unique" % c.character_id)
		seen.append(c.character_id)

func test_exactly_one_boss_and_it_is_stronger():
	var roster := SampleRoster.build_roster()
	var bosses: Array = []
	var non_bosses: Array = []
	for c in roster:
		if c.is_boss:
			bosses.append(c)
		else:
			non_bosses.append(c)
	assert_eq(bosses.size(), 1, "exactly one character is flagged as a boss")
	var boss = bosses[0]
	var strongest_non_boss := 0
	for c in non_bosses:
		strongest_non_boss = maxi(strongest_non_boss, c.power_budget())
	assert_gt(boss.power_budget(), strongest_non_boss,
		"the boss has a larger power budget than every other character")

func test_boss_has_area_knockback_signature_move():
	var boss: CharacterResource = null
	for c in SampleRoster.build_roster():
		if c.is_boss:
			boss = c
			break
	assert_not_null(boss, "a boss exists")
	var has_area_knockback := false
	for move in boss.moveset:
		var is_area := move.targeting != null \
			and move.targeting.area_shape != CombatTypes.AreaShape.SINGLE
		var has_knockback := false
		for e in move.effects:
			if e is KnockbackEffect:
				has_knockback = true
		if is_area and has_knockback:
			has_area_knockback = true
	assert_true(has_area_knockback,
		"boss owns an area move that also applies knockback")

# --- Move pool -------------------------------------------------------------

func test_move_pool_ids_are_unique_and_valid():
	var pool := SampleRoster.build_move_pool()
	assert_eq(pool.size(), 8, "the sample pool contains 8 moves")
	var seen: Array = []
	for m in pool:
		assert_true(m.is_valid(),
			"move '%s' has targeting and at least one effect" % m.move_id)
		assert_false(m.move_id in seen, "move_id '%s' is unique" % m.move_id)
		seen.append(m.move_id)

func test_pool_showcases_terrain_transform():
	var found_terrain := false
	for m in SampleRoster.build_move_pool():
		for e in m.effects:
			if e is TileTransformEffect:
				found_terrain = true
	assert_true(found_terrain, "at least one move scorches / transforms terrain")

# --- End-to-end execution --------------------------------------------------

func test_ember_storm_hits_multiple_enemies_and_spares_ally():
	var caster := MockUnit.new(0, { "magic": 10 })
	var enemy_a := MockUnit.new(1, { "health": 100 })   # aim cell
	var enemy_b := MockUnit.new(1, { "health": 100 })   # splash within diamond radius 1
	var ally := MockUnit.new(0, { "health": 100 })      # inside the area but friendly
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy_a, Vector2i(3, 0))
	board.place(enemy_b, Vector2i(3, 1))
	board.place(ally, Vector2i(2, 0))

	var result := MoveExecutor.execute(
		SampleRoster.move_ember_storm(), caster, board, Vector2i(3, 0))

	assert_true(result.success, "ember storm resolves")
	assert_lt(enemy_a.hp, 100, "enemy A (aim) is damaged")
	assert_lt(enemy_b.hp, 100, "enemy B (splash) is damaged")
	assert_eq(enemy_a.hp, enemy_b.hp, "both enemies take equal area damage")
	assert_eq(ally.hp, 100, "the ally inside the area is spared by an ENEMY-targeted move")
	assert_eq(board.tiles.get(Vector2i(3, 0)), &"scorched", "aim tile is scorched")

func test_boss_crushing_quake_damages_and_knocks_back():
	var caster := MockUnit.new(1, { "magic": 30 })       # boss on team 1
	var hero := MockUnit.new(0, { "health": 200 })
	var board := MockBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(hero, Vector2i(2, 0))                     # within diamond radius 2

	var result := MoveExecutor.execute(
		SampleRoster.move_crushing_quake(), caster, board, Vector2i(2, 0))

	assert_true(result.success, "crushing quake resolves")
	assert_lt(hero.hp, 200, "hero caught in the quake takes damage")
	assert_ne(board.cell_of(hero), Vector2i(2, 0), "hero is knocked back off the impact cell")
	assert_eq(board.tiles.get(Vector2i(2, 0)), &"rubble", "impact tile is cracked to rubble")
