extends GutTest

## Invariants for the Forgotten Forest boss encounter (T62). Light + robust: it
## guards that the authored map stays structurally playable (tiles resolve, a boss
## is present, both sides are populated) without pinning exact spawn positions the
## author may tweak in the Map Creator.

const MAP_PATH := "res://game/maps/resources/forgotten_forest.tres"

var _map: MapResource


func before_all() -> void:
	_map = load(MAP_PATH) as MapResource


func test_map_loads_as_the_forgotten_forest() -> void:
	# NOTE: status (Active/Inactive) is deliberately NOT asserted -- it is an
	# author-editable field the user flips in the Map Creator (draft while building,
	# Active once published), so pinning it here would fail the moment they publish.
	assert_not_null(_map, "Forgotten Forest map resource should load")
	assert_eq(_map.map_name, "Forgotten Forest")
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
	# type-only tiles): a healing sacred grove, the author's trees, and plain ground.
	assert_gt(int(composition.get("sacred_meadow", 0)), 0, "has a sacred grove")
	assert_gt(int(composition.get("tree", 0)), 0, "has the author's trees")
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


func test_map_is_offered_in_the_single_player_picker() -> void:
	# The solo map picker (MapSelection) lists get_available_maps(true), which includes
	# drafts -- so the map is selectable whether it is still a draft or published. (We
	# don't assert the draft-only "hidden from the shared list" behaviour here because
	# the map's status is author-editable; that filtering is covered by spawn-point
	# tests on a fixed-status resource.)
	var with_drafts: Array = MapLoader.get_available_maps(true)
	assert_true(MAP_PATH in with_drafts, "the map is offered in the single-player picker")


func test_win_condition_is_defeat_the_boss() -> void:
	# The whole point of the encounter: it ends when Eldroot dies, not when every
	# spawn is cleared (the Hard+ parasites would make elimination the wrong goal).
	assert_true("Defeat Boss" in _map.victory_conditions,
		"victory_conditions should be Defeat Boss, got %s" % str(_map.victory_conditions))
