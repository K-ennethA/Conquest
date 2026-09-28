extends GutTest

# MapResource export_to_json -> import_from_json round trip. JSON has no Vector2i
# or int, so positions used to come back as "(x, y)" strings and ids as floats,
# and the untyped arrays could not even be assigned to the typed properties.

func _make_map() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Round Trip"
	m.width = 6
	m.height = 4
	m.turn_limit = 9
	m.victory_conditions = ["Survive 5 Turns", "Seize Throne"]
	m.special_rules = ["objective:THRONE:-1:3:2"]
	m.tags = ["test", "json"]
	m.set_tile_at_position(Vector2i(1, 2), "WATER", "res://x.tres", "deep_water")
	m.set_tile_at_position(Vector2i(5, 3), "NORMAL")
	m.set_character_spawn_at_position(Vector2i(0, 0), 0, "vineweave")
	m.set_spawn_point_at_position(Vector2i(4, 1), 1, MapResource.SPAWN_KIND_RESPAWN,
		{ "character_id": "mycothrall", "respawn_interval": 3, "max_spawns": 2 })
	return m


func test_round_trip_restores_typed_positions_and_ints():
	var src := _make_map()
	var json := src.export_to_json()
	var dst := MapResource.import_from_json(json)
	assert_not_null(dst, "import succeeds")

	assert_eq(dst.width, 6)
	assert_eq(dst.height, 4)
	assert_eq(dst.turn_limit, 9)
	assert_eq(dst.victory_conditions, src.victory_conditions)
	assert_eq(dst.special_rules, src.special_rules)
	assert_eq(dst.tags, src.tags)

	assert_eq(dst.tile_layout.size(), src.tile_layout.size())
	for i in src.tile_layout.size():
		var pos = dst.tile_layout[i]["position"]
		assert_true(pos is Vector2i, "tile position is a Vector2i again")
		assert_eq(pos, src.tile_layout[i]["position"])
	assert_eq(dst.get_tile_at_position(Vector2i(1, 2)).get("tile_id"), "deep_water")

	assert_eq(dst.unit_spawns.size(), src.unit_spawns.size())
	for i in src.unit_spawns.size():
		var s: Dictionary = dst.unit_spawns[i]
		assert_true(s["position"] is Vector2i, "spawn position is a Vector2i again")
		assert_eq(s["position"], src.unit_spawns[i]["position"])
		assert_eq(typeof(s["player_id"]), TYPE_INT, "player_id is an int again")
	var respawn := dst.get_unit_spawn_at_position(Vector2i(4, 1))
	assert_eq(respawn.get("character_id"), "mycothrall")
	assert_eq(respawn.get("respawn_interval"), 3)
	assert_eq(typeof(respawn.get("max_spawns")), TYPE_INT)
	assert_eq(dst.get_player_spawn_positions(0), [Vector2i(0, 0)] as Array[Vector2i])


func test_json_to_vector_accepts_common_encodings():
	assert_eq(MapResource.json_to_vector("(3, 4)"), Vector2i(3, 4))
	assert_eq(MapResource.json_to_vector([5, 6]), Vector2i(5, 6))
	assert_eq(MapResource.json_to_vector({ "x": 1.0, "y": 2.0 }), Vector2i(1, 2))
	assert_eq(MapResource.json_to_vector("(1, 2, 3)"), Vector3i(1, 2, 3))
	assert_eq(MapResource.json_to_vector(Vector2i(7, 8)), Vector2i(7, 8))
	assert_eq(MapResource.json_to_vector("garbage"), Vector2i(-1, -1))
