extends GutTest

# Tests for the data-driven combat/move system: targeting math, composable
# effects, the executor, and the character moveset model. Uses the shared
# doubles so no scene tree / live board is required.

# --- Mocks -----------------------------------------------------------------
# CombatUnit + CombatBoard are the canonical pair; see tests/helpers/test_doubles.gd
# for why each double is an exact shape rather than a kitchen sink.
const Doubles := preload("res://tests/helpers/test_doubles.gd")

# --- Targeting -------------------------------------------------------------

func test_single_shape_is_just_aim():
	var p := TargetingPattern.new()
	p.area_shape = CombatTypes.AreaShape.SINGLE
	var cells := p.resolve_cells(Vector2i(0, 0), Vector2i(2, 0))
	assert_eq(cells, [Vector2i(2, 0)] as Array[Vector2i], "SINGLE resolves to the aim cell")

func test_diamond_radius_one_has_five_cells():
	var p := TargetingPattern.new()
	p.area_shape = CombatTypes.AreaShape.DIAMOND
	p.area_size = 1
	p.affects_caster_tile = true
	var cells := p.resolve_cells(Vector2i(0, 0), Vector2i(5, 5))
	assert_eq(cells.size(), 5, "Diamond radius 1 = aim + 4 neighbours")

func test_in_range_uses_manhattan_distance():
	var p := TargetingPattern.new()
	p.min_range = 1
	p.max_range = 3
	assert_true(p.in_range(Vector2i(0, 0), Vector2i(2, 1)), "distance 3 within 1-3")
	assert_false(p.in_range(Vector2i(0, 0), Vector2i(0, 0)), "distance 0 below min")
	assert_false(p.in_range(Vector2i(0, 0), Vector2i(4, 0)), "distance 4 above max")

func test_pattern_excludes_caster_tile_by_default():
	var p := TargetingPattern.new()
	p.area_shape = CombatTypes.AreaShape.SQUARE
	p.area_size = 1
	var cells := p.resolve_cells(Vector2i(1, 1), Vector2i(1, 1))
	assert_false(Vector2i(1, 1) in cells, "caster tile removed when affects_caster_tile is false")

# --- Damage effect ---------------------------------------------------------

func test_damage_hits_enemies_scaled_and_mitigated():
	var caster := Doubles.CombatUnit.new(0, { "attack": 10 })
	var enemy := Doubles.CombatUnit.new(1, { "health": 100, "defense": 4 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))
	var move := MoveLibrary.basic_strike()  # power 24 + attack 10 = 34, - def 4 = 30
	var result := MoveExecutor.execute(move, caster, board, Vector2i(1, 0))
	assert_true(result.success, "strike resolves")
	assert_eq(enemy.hp, 70, "34 raw minus 4 defense = 30 damage")

func test_area_damage_hits_multiple_enemies_not_ally():
	var caster := Doubles.CombatUnit.new(0, { "magic": 10 })
	var enemy_a := Doubles.CombatUnit.new(1, { "health": 100, "defense": 0 })
	var enemy_b := Doubles.CombatUnit.new(1, { "health": 100, "defense": 0 })
	var ally := Doubles.CombatUnit.new(0, { "health": 100, "defense": 0 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy_a, Vector2i(3, 0))       # aim cell
	board.place(enemy_b, Vector2i(3, 1))       # within diamond radius 1
	board.place(ally, Vector2i(2, 0))          # within diamond but friendly
	var move := MoveLibrary.flame_burst()      # 30 + magic 10 = 40 magical
	var result := MoveExecutor.execute(move, caster, board, Vector2i(3, 0))
	assert_true(result.success, "burst resolves")
	assert_eq(enemy_a.hp, 60, "enemy A takes 40")
	assert_eq(enemy_b.hp, 60, "enemy B (splash) takes 40")
	assert_eq(ally.hp, 100, "ally in area is not hit by an ENEMY-targeted move")

func test_flame_burst_transforms_terrain():
	var caster := Doubles.CombatUnit.new(0, { "magic": 10 })
	var enemy := Doubles.CombatUnit.new(1, { "health": 100, "defense": 0 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(3, 0))
	MoveExecutor.execute(MoveLibrary.flame_burst(), caster, board, Vector2i(3, 0))
	assert_eq(board.tiles.get(Vector2i(3, 0)), &"fire", "aim tile scorched to fire")

# --- Heal & debuff ---------------------------------------------------------

func test_heal_targets_ally_only():
	var caster := Doubles.CombatUnit.new(0, { "magic": 12 })
	var ally := Doubles.CombatUnit.new(0, { "health": 100 })
	ally.hp = 50
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(ally, Vector2i(1, 0))
	MoveExecutor.execute(MoveLibrary.mend(), caster, board, Vector2i(1, 0))  # 28 + magic 12 = 40
	assert_eq(ally.hp, 90, "ally healed for 40")

func test_expose_applies_defense_debuff():
	var caster := Doubles.CombatUnit.new(0, {})
	var enemy := Doubles.CombatUnit.new(1, { "health": 100 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))
	MoveExecutor.execute(MoveLibrary.expose(), caster, board, Vector2i(1, 0))
	assert_eq(enemy.modifiers.size(), 1, "one modifier applied")
	assert_eq(enemy.modifiers[0]["amount"], -6, "defense reduced by 6")

# --- Executor guards -------------------------------------------------------

func test_execute_rejects_out_of_range():
	var caster := Doubles.CombatUnit.new(0, { "attack": 10 })
	var enemy := Doubles.CombatUnit.new(1, { "health": 100, "defense": 0 })
	var board := Doubles.CombatBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(enemy, Vector2i(5, 0))
	var result := MoveExecutor.execute(MoveLibrary.basic_strike(), caster, board, Vector2i(5, 0))
	assert_false(result.success, "range 1 move cannot reach distance 5")
	assert_eq(result.reason, "out_of_range", "reason reported")

# --- Character model -------------------------------------------------------

func test_character_moveset_caps_at_four():
	var c := CharacterResource.new()
	c.character_id = &"test_hero"
	c.display_name = "Test Hero"
	c.moveset = [
		MoveLibrary.basic_strike(), MoveLibrary.flame_burst(),
		MoveLibrary.mend(), MoveLibrary.expose(),
		MoveLibrary.basic_strike(),  # 5th, should be ignored by accessors
	]
	assert_eq(c.move_count(), 4, "move_count clamps to MAX_MOVES")
	assert_null(c.get_move(4), "5th slot inaccessible")
	assert_not_null(c.get_move(0), "first slot accessible")
	var v := c.validate()
	assert_false(v.valid, "oversized moveset flagged invalid")

func test_character_stats_and_budget():
	var c := CharacterResource.new()
	c.base_attack = 25
	assert_eq(c.get_stat("atk"), 25, "stat alias resolves")
	assert_gt(c.power_budget(), 0, "power budget computed")
