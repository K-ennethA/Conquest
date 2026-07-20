extends GutTest

# Forgotten Forest terrain. The subtle requirement: a tile's effects come from the
# TILE, not its TileType. Trees and Tall Grass are both DIFFICULT_TERRAIN, and
# Sacred Meadow shares SACRED_GROUND with the fortify terrain -- so resolving
# effects by type alone would give trees evasion and the meadow a defence buff
# instead of healing.

const TILE_DIR := "res://game/tiles/resources/forest/%s.tres"


func after_each() -> void:
	# tile_effects_at reads a process-wide registry; don't leak cells between tests.
	CombatServices.clear()


func _register(name: String, cell: Vector2i) -> void:
	CombatServices.register_tile(cell, load(TILE_DIR % name))


func _effect_ids(cell: Vector2i) -> Array:
	var ids: Array = []
	for te in CombatServices.tile_effects_at(cell):
		ids.append(String(te.id))
	return ids


func test_sacred_meadow_heals_rather_than_fortifies() -> void:
	_register("sacred_meadow", Vector2i(0, 0))
	var ids := _effect_ids(Vector2i(0, 0))
	assert_has(ids, "sacred_meadow", "meadow must use its OWN healing effect")
	assert_does_not_have(ids, "fortify", "must not inherit the SACRED_GROUND type effect")


func test_tall_grass_grants_its_evasion_effect() -> void:
	_register("tall_grass", Vector2i(1, 0))
	assert_has(_effect_ids(Vector2i(1, 0)), "tall_grass")


func test_trees_have_no_effect_despite_sharing_grass_type() -> void:
	_register("tree", Vector2i(2, 0))
	assert_eq(_effect_ids(Vector2i(2, 0)), [], "trees are cover/LOS only, no tile effect")


func test_trees_and_tall_grass_share_a_type_but_not_effects() -> void:
	var tree: TileResource = load(TILE_DIR % "tree")
	var grass: TileResource = load(TILE_DIR % "tall_grass")
	assert_eq(tree.tile_type, grass.tile_type, "both are DIFFICULT_TERRAIN")
	_register("tree", Vector2i(0, 1))
	_register("tall_grass", Vector2i(1, 1))
	assert_eq(_effect_ids(Vector2i(0, 1)).size(), 0)
	assert_eq(_effect_ids(Vector2i(1, 1)).size(), 1)


func test_plain_terrain_has_no_effects() -> void:
	_register("grass_plains", Vector2i(3, 0))
	_register("forest_dirt", Vector2i(4, 0))
	assert_eq(_effect_ids(Vector2i(3, 0)), [], "standard grass is neutral")
	assert_eq(_effect_ids(Vector2i(4, 0)), [], "standard dirt is neutral")


func test_forest_movement_costs() -> void:
	assert_eq((load(TILE_DIR % "tall_grass") as TileResource).base_movement_cost, 2, "grass slows you")
	assert_eq((load(TILE_DIR % "tree") as TileResource).base_movement_cost, 2, "trees slow you")
	assert_eq((load(TILE_DIR % "forest_dirt") as TileResource).base_movement_cost, 1, "dirt is open")
	assert_eq((load(TILE_DIR % "sacred_meadow") as TileResource).base_movement_cost, 1)


func test_trees_are_impassable_and_block_pathing() -> void:
	# Trees function as walls: you must path around them.
	var tree: TileResource = load(TILE_DIR % "tree")
	assert_false(tree.is_tile_passable(), "a tree cannot be walked through")
	assert_true(tree.blocks_line_of_sight, "and it blocks sight")
	# The board's blocking check is what MovementResolver consults.
	_register("tree", Vector2i(7, 7))
	var board = CombatServices.board()
	if board != null:
		assert_true(board.is_blocked(Vector2i(7, 7)), "board reports the tree cell blocked")


func test_walkable_forest_tiles_stay_passable() -> void:
	for name in ["tall_grass", "grass_plains", "forest_dirt", "sacred_meadow"]:
		var t: TileResource = load(TILE_DIR % name)
		assert_true(t.is_tile_passable(), "%s must stay walkable" % name)


func test_runtime_effects_still_stack_on_forest_tiles() -> void:
	# A move can ignite tall grass: the evasion stays AND the fire layers on top.
	_register("tall_grass", Vector2i(5, 5))
	CombatServices.add_tile_effect(Vector2i(5, 5), load("res://game/tiles/effects/resources/fire.tres"))
	var ids := _effect_ids(Vector2i(5, 5))
	assert_has(ids, "tall_grass", "base evasion survives")
	assert_has(ids, "fire", "runtime fire layers on top")
