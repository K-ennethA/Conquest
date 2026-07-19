extends GutTest

# Spawn POINTS: position + owning player slot + what kind of spawning it does.
# The critical property is BACKWARD COMPATIBILITY -- maps authored before these
# keys existed carry only position/player_id/unit_type, and must keep behaving
# exactly like a one-shot "Start" point.

func _map() -> MapResource:
	return MapResource.new()


# --- backward compatibility ---------------------------------------------------

func test_legacy_entry_defaults_to_a_start_point() -> void:
	var m := _map()
	# Exactly the shape the four shipped maps use: no spawn_kind, no max_spawns.
	var legacy := { "position": Vector2i(1, 1), "player_id": 0, "unit_type": "WARRIOR" }
	assert_eq(m.get_spawn_kind(legacy), MapResource.SPAWN_KIND_START, "no kind => Start")
	assert_true(m.is_initial_spawn(legacy), "a legacy spawn still places its unit at load")
	assert_true(m.spawn_has_unit_reference(legacy), "unit_type counts as a reference")


func test_unrecognised_kind_falls_back_to_start() -> void:
	var m := _map()
	var weird := { "position": Vector2i(0, 0), "player_id": 0, "spawn_kind": "Nonsense" }
	assert_eq(m.get_spawn_kind(weird), MapResource.SPAWN_KIND_START)


func test_normalize_fills_every_optional_key() -> void:
	var m := _map()
	var n := m.normalize_spawn({ "position": Vector2i(2, 3), "player_id": 1 })
	assert_eq(n["spawn_kind"], MapResource.SPAWN_KIND_START)
	assert_eq(n["max_spawns"], 1, "a Start point produces one unit")
	assert_eq(n["respawn_interval"], 1)
	assert_eq(n["spawn_turn"], 1)
	assert_eq(n["character_id"], "")


# --- spawn kinds --------------------------------------------------------------

func test_endless_defaults_to_unlimited_spawns() -> void:
	var m := _map()
	assert_eq(m.get_default_max_spawns(MapResource.SPAWN_KIND_ENDLESS), -1, "-1 = unlimited")
	assert_eq(m.get_default_max_spawns(MapResource.SPAWN_KIND_START), 1)


func test_reinforcement_on_a_later_turn_is_not_an_initial_spawn() -> void:
	var m := _map()
	var late := {
		"position": Vector2i(0, 0), "player_id": 1, "unit_type": "ARCHER",
		"spawn_kind": MapResource.SPAWN_KIND_REINFORCEMENT, "spawn_turn": 5,
	}
	assert_false(m.is_initial_spawn(late), "must NOT drop a unit at map load")


func test_respawn_and_endless_seed_at_load() -> void:
	var m := _map()
	for kind in [MapResource.SPAWN_KIND_RESPAWN, MapResource.SPAWN_KIND_ENDLESS]:
		var s := { "position": Vector2i(0, 0), "player_id": 0, "unit_type": "MAGE", "spawn_kind": kind }
		assert_true(m.is_initial_spawn(s), "%s places its first unit at load" % kind)


func test_start_point_may_be_an_empty_slot() -> void:
	var m := _map()
	var slot := { "position": Vector2i(4, 4), "player_id": 0 }
	assert_false(m.spawn_has_unit_reference(slot), "no unit => filled at match setup")


# --- writing + validation -----------------------------------------------------

func test_set_spawn_point_records_kind_and_options() -> void:
	var m := _map()
	m.set_spawn_point_at_position(
		Vector2i(3, 3), 1, MapResource.SPAWN_KIND_ENDLESS,
		{ "unit_type": "ARCHER", "respawn_interval": 3 }
	)
	var n := m.normalize_spawn(m.get_unit_spawn_at_position(Vector2i(3, 3)))
	assert_eq(n["spawn_kind"], MapResource.SPAWN_KIND_ENDLESS)
	assert_eq(n["respawn_interval"], 3)
	assert_eq(n["player_id"], 1)


func test_legacy_writer_still_makes_a_start_point() -> void:
	var m := _map()
	m.set_unit_spawn_at_position(Vector2i(1, 2), 0, "WARRIOR")
	var n := m.normalize_spawn(m.get_unit_spawn_at_position(Vector2i(1, 2)))
	assert_eq(n["spawn_kind"], MapResource.SPAWN_KIND_START, "old callers keep working")


func test_spawner_without_a_unit_is_a_validation_issue() -> void:
	var m := _map()
	m.map_name = "T"
	m.width = 5
	m.height = 5
	# Two players so the "needs 2 players" rule isn't what trips.
	m.set_spawn_point_at_position(Vector2i(0, 0), 0, MapResource.SPAWN_KIND_START, { "unit_type": "WARRIOR" })
	m.set_spawn_point_at_position(Vector2i(4, 4), 1, MapResource.SPAWN_KIND_ENDLESS, {})
	var issues: Array = m.validate_map().issues
	var found := false
	for issue in issues:
		if String(issue).to_lower().contains("spawn"):
			found = true
	assert_true(found, "a respawning point with nothing to spawn must be flagged: %s" % str(issues))


func test_size_guardrails_exist_for_shared_maps() -> void:
	assert_eq(MapResource.MIN_MAP_SIZE, 3)
	assert_eq(MapResource.MAX_MAP_SIZE, 20)
