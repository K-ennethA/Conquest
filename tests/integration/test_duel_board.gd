extends GutTest

## DuelBoard on the live stack (docs/design/DUEL_BATTLE.md §3.3): two stations, installed
## as THE CombatServices board, stations never change, only the ACTIVE combatants exist for
## it, and the station tile drives terrain rules (tall-grass evasion) for both sides.

const UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _battle(tile: StringName = &"", stage: String = "meadow") -> DuelBattle:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.seed = 77
	req.foe_is_ai = false
	req.stage_id = stage
	req.station_tile_id = tile
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), "setup: %s" % str(ok.get("reason", "")))
	return battle


func test_board_is_installed_with_two_stations() -> void:
	var b := _battle()
	var board := b.board
	assert_eq(CombatServices.board(), board, "the duel board is THE live board")
	assert_true(board.reach_is_unbounded())
	assert_eq(board.station(0), Vector3i(0, 0, 0))
	assert_eq(board.station(1), Vector3i(DuelRuleset.load_default().station_gap, 0, 0))
	assert_eq(board.cell_of(b.unit_of(0)), board.station(0), "the challenger stands on station A")
	assert_eq(board.cell_of(b.unit_of(1)), board.station(1), "the foe on station B")
	assert_eq(board.side_of(b.unit_of(1)), 1)
	assert_eq(NetUnitIds.id_of(b.unit_of(0)), "0:0", "stable command ids")
	assert_eq(NetUnitIds.id_of(b.unit_of(1)), "1:0")
	assert_eq(b.unit_of(0).get_facing(), Vector2i(1, 0), "face to face")
	assert_eq(b.unit_of(1).get_facing(), Vector2i(-1, 0))


func test_stations_never_change() -> void:
	var b := _battle()
	var u = b.unit_of(0)
	b.board.move_unit(u, Vector3i(2, 0, 0))
	assert_eq(b.board.cell_of(u), b.board.station(0), "move_unit is a no-op")
	assert_true(b.board.can_fit(u, b.board.station(0)))
	assert_false(b.board.can_fit(u, Vector3i(2, 0, 0)), "nobody lands anywhere else")
	assert_false(b.board.can_fit(u, b.board.station(1)))


func test_only_active_combatants_exist_for_the_board() -> void:
	var b := _battle()
	# A benched party member: a real unit parked under the map, not fielded.
	var bench: Unit = UNIT_SCENE.instantiate()
	bench.character_resource = CharacterLibrary.get_character(&"petalfang")
	bench.position = b.board.station_world(0)
	b.map_root.get_node("Player1").add_child(bench)
	b.players[0].add_unit(bench)
	var at_a: Array = b.board.units_at(b.board.station(0))
	assert_eq(at_a.size(), 1, "the bench is invisible to the board")
	assert_eq(at_a[0], b.unit_of(0))
	assert_eq(b.board.all_units().size(), 2)


func test_station_tile_drives_terrain_rules_for_both_sides() -> void:
	var meadow := _battle(&"grass_plains")
	var plain_eva: int = TerrainStats.bonus_for(meadow.unit_of(1), "evasion", meadow.board)
	meadow.teardown()
	var grass := _battle(&"tall_grass", "tall_grass")
	var a_eva: int = TerrainStats.bonus_for(grass.unit_of(0), "evasion", grass.board)
	var b_eva: int = TerrainStats.bonus_for(grass.unit_of(1), "evasion", grass.board)
	assert_eq(plain_eva, 0, "plain grass gives nothing")
	assert_gt(a_eva, 0, "tall grass grants the challenger evasion")
	assert_gt(b_eva, 0, "and the foe")
	assert_eq(CombatServices.tile_at(grass.board.station(1)).id, &"tall_grass")
