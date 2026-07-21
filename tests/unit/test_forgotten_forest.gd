extends GutTest

## Invariants for the Forgotten Forest boss encounter (T62). Light + robust: it
## guards that the authored map stays structurally playable (tiles resolve, a boss
## is present, both sides are populated) without pinning exact spawn positions the
## author may tweak in the Map Creator.

const MAP_PATH := "res://game/maps/resources/forgotten_forest.tres"

var _map: MapResource


func before_all() -> void:
	_map = load(MAP_PATH) as MapResource


func test_map_loads_as_the_forgotten_forest_draft() -> void:
	assert_not_null(_map, "Forgotten Forest map resource should load")
	assert_eq(_map.map_name, "Forgotten Forest")
	assert_eq(_map.status, "Inactive", "it is authored as a draft")
	assert_eq(_map.width, 20)
	assert_eq(_map.height, 20)


func test_every_tile_is_populated_and_resolves() -> void:
	assert_eq(_map.tile_layout.size(), _map.width * _map.height, "every cell painted")
	var composition := {}
	for tile in _map.tile_layout:
		var tid: String = str(tile.get("tile_id", ""))
		composition[tid] = int(composition.get(tid, 0)) + 1
		assert_not_null(TileCatalog.find_by_id(StringName(tid)),
			"tile_id '%s' must resolve via TileCatalog" % tid)
	# The forest terrain the encounter needs is present (upgraded from the old
	# type-only tiles): a healing sacred grove, evasion cover, and plain ground.
	assert_gt(int(composition.get("sacred_meadow", 0)), 0, "has a sacred grove")
	assert_gt(int(composition.get("tall_grass", 0)), 0, "has tall-grass cover")
	assert_gt(int(composition.get("grass_plains", 0)), 0, "has plain ground")


func test_a_boss_screens_the_grove_and_both_sides_are_populated() -> void:
	var players := {}
	var boss_found := false
	for spawn_data in _map.unit_spawns:
		var cid: String = str(spawn_data.get("character_id", ""))
		if cid.is_empty():
			continue
		var pid: int = int(spawn_data.get("player_id", -1))
		players[pid] = int(players.get(pid, 0)) + 1
		var character := CharacterLibrary.get_character(cid)
		assert_not_null(character, "spawn character '%s' must resolve" % cid)
		if character != null and character.is_boss:
			boss_found = true
	assert_true(boss_found, "the encounter must field a boss (Eldroot)")
	assert_true(players.has(0) and int(players[0]) >= 1, "player side has units")
	assert_true(players.has(1) and int(players[1]) >= 1, "enemy side has units")


func test_map_passes_its_own_validator() -> void:
	var report: Dictionary = _map.validate_map()
	assert_true(bool(report.get("valid", false)),
		"validate_map issues: %s" % str(report.get("issues", [])))


func test_draft_is_offered_in_single_player_but_hidden_from_shared_lists() -> void:
	# The solo map picker (MapSelection) includes drafts so you can play-test a map
	# you just built; the default/shared list (used by network setup) hides them.
	var with_drafts: Array = MapLoader.get_available_maps(true)
	var without_drafts: Array = MapLoader.get_available_maps(false)
	assert_true(MAP_PATH in with_drafts, "the draft is offered when drafts are included (single-player picker)")
	assert_false(MAP_PATH in without_drafts, "the draft stays out of the draft-free shared list")


func test_win_condition_is_defeat_the_boss() -> void:
	# The whole point of the encounter: it ends when Eldroot dies, not when every
	# spawn is cleared (the Hard+ parasites would make elimination the wrong goal).
	assert_true("Defeat Boss" in _map.victory_conditions,
		"victory_conditions should be Defeat Boss, got %s" % str(_map.victory_conditions))
