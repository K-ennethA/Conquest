extends GutTest

# Tiles are referenced by a STABLE LOGICAL ID, not by file path.
#
# The point: maps are authored by players and SHARED, so a map's tile references
# have to survive the tile assets being reorganised on someone else's install.
# Reorganising tiles into biome folders already broke path-addressed maps once.
# TileResource.id never changes when a file moves or is renamed, so it is what
# maps, the map creator, BoardAdapter and MapLoader now address tiles by.
#
# The regression that matters most is test_all_shipped_tile_ids_are_unique: a
# duplicate id silently redirects every map that names it to the wrong terrain.


func before_each() -> void:
	# The catalog caches its scan process-wide; start from a known index.
	TileCatalog.rescan()


func test_find_by_id_resolves_tiles_across_biome_folders() -> void:
	# Ids are flat; the folder a tile lives in is an implementation detail.
	var expected := {
		&"grass_plains": "Grass Plains",
		&"tree": "Tree",
		&"molten_lava": "Molten Lava",
		&"deep_water": "Deep Water",
		&"snow_field": "Snow Field",
		&"stone_wall": "Stone Wall",
	}
	for tile_id in expected:
		var tile := TileCatalog.find_by_id(tile_id)
		assert_not_null(tile, "id '%s' must resolve to a tile" % String(tile_id))
		if tile != null:
			assert_eq(tile.get_id(), tile_id, "resolved tile must report the id asked for")
			assert_eq(tile.tile_name, String(expected[tile_id]), "id '%s' resolved to the wrong tile" % String(tile_id))


func test_find_by_id_ignores_which_folder_the_asset_lives_in() -> void:
	# Same id, four different biome folders on disk.
	var forest := TileCatalog.find_by_id(&"sacred_meadow")
	var volcano := TileCatalog.find_by_id(&"obsidian")
	var ice := TileCatalog.find_by_id(&"ice_sheet")
	var common := TileCatalog.find_by_id(&"sacred_ground")
	assert_not_null(forest, "forest/ tile resolves by id")
	assert_not_null(volcano, "volcano/ tile resolves by id")
	assert_not_null(ice, "ice/ tile resolves by id")
	assert_not_null(common, "common/ tile resolves by id")


func test_find_by_id_returns_null_for_unknown_and_empty_ids() -> void:
	assert_null(TileCatalog.find_by_id(&"no_such_tile_anywhere"), "unknown id must not guess")
	assert_null(TileCatalog.find_by_id(&""), "empty id resolves to nothing")


func test_every_shipped_tile_declares_an_id() -> void:
	var paths := TileCatalog.all_paths()
	assert_gt(paths.size(), 0, "the catalog must actually find the shipped tiles")
	for path in paths:
		var tile: TileResource = load(path) as TileResource
		assert_not_null(tile, "%s must load as a TileResource" % path)
		if tile != null:
			assert_false(String(tile.get_id()).is_empty(), "%s has no usable id" % path)


func test_all_shipped_tile_ids_are_unique() -> void:
	# THE regression guard. Two tiles sharing an id means every map naming it gets
	# whichever one the catalog happened to index first - a silent content bug.
	var seen: Dictionary = {}
	var duplicates: Array[String] = []
	for path in TileCatalog.all_paths():
		var tile: TileResource = load(path) as TileResource
		if tile == null:
			continue
		var tile_id: StringName = tile.get_id()
		if seen.has(tile_id):
			duplicates.append("'%s' claimed by both %s and %s" % [
				String(tile_id), String(seen[tile_id]), path])
			continue
		seen[tile_id] = path
	assert_eq(duplicates.size(), 0, "tile ids must be unique -- " + ", ".join(duplicates))


func test_every_shipped_tile_is_reachable_by_its_own_id() -> void:
	# Declaring an id is not enough - the catalog must actually index it, so a
	# round trip through find_by_id has to land back on the same file.
	for path in TileCatalog.all_paths():
		var tile: TileResource = load(path) as TileResource
		if tile == null:
			continue
		var round_trip := TileCatalog.find_by_id(tile.get_id())
		assert_not_null(round_trip, "%s is not reachable by its own id" % path)
		if round_trip != null:
			assert_eq(round_trip.resource_path, path, "id round trip landed on a different file")


func test_get_id_falls_back_to_the_file_name_stem() -> void:
	# An un-migrated or player-created tile that never set `id` still gets a usable
	# identity from its file name, rather than an empty key.
	var tile := TileResource.new()
	tile.tile_name = "Unmigrated"
	assert_eq(tile.get_id(), &"", "no id and no file on disk means no identity")

	tile.take_over_path("res://game/tiles/resources/forest/some_new_tile.tres")
	assert_eq(tile.get_id(), &"some_new_tile", "falls back to the file name stem")


func test_explicit_id_wins_over_the_file_name() -> void:
	var tile := TileResource.new()
	tile.take_over_path("res://game/tiles/resources/forest/renamed_on_disk.tres")
	tile.id = &"original_identity"
	assert_eq(tile.get_id(), &"original_identity", "an explicit id is never overridden by the path")


func test_id_for_path_maps_legacy_data_onto_ids() -> void:
	# The migration helper: given an old path-addressed entry, what id is it?
	assert_eq(
		TileCatalog.id_for_path("res://game/tiles/resources/volcano/molten_lava.tres"),
		&"molten_lava")
	assert_eq(TileCatalog.id_for_path("res://game/tiles/resources/nope.tres"), &"")
	assert_eq(TileCatalog.id_for_path(""), &"")


# --- MapLoader resolution order ------------------------------------------------
#
# The whole reason the id exists: a map entry must resolve by id even when the
# path stored beside it is stale, AND a legacy path-only entry must keep working.

func _resolve(tile_data: Dictionary) -> TileResource:
	var loader := MapLoader.new()
	autofree(loader)
	return loader._resolve_tile_resource(
		str(tile_data.get("tile_resource_path", "")),
		str(tile_data.get("tile_type", "NORMAL")),
		str(tile_data.get("tile_id", "")))


func test_tile_id_resolves_even_when_the_stored_path_is_stale() -> void:
	# This is the change in one test: the path is nonsense (the asset "moved"),
	# the id still lands on the right terrain.
	var resolved := _resolve({
		"tile_id": "molten_lava",
		"tile_resource_path": "res://game/tiles/resources/old_layout/does_not_exist.tres",
		"tile_type": "NORMAL",
	})
	assert_not_null(resolved, "a stale path must not stop the id from resolving")
	if resolved != null:
		assert_eq(resolved.get_id(), &"molten_lava")


func test_tile_id_wins_over_a_valid_but_different_path() -> void:
	# The id is the authority, not the path that happens to sit beside it.
	var resolved := _resolve({
		"tile_id": "deep_water",
		"tile_resource_path": "res://game/tiles/resources/forest/grass_plains.tres",
		"tile_type": "NORMAL",
	})
	assert_not_null(resolved)
	if resolved != null:
		assert_eq(resolved.get_id(), &"deep_water", "tile_id must take priority over tile_resource_path")


func test_legacy_path_only_entry_still_resolves() -> void:
	# BACK-COMPAT: every existing map on disk stores only a path.
	var resolved := _resolve({
		"tile_resource_path": "res://game/tiles/resources/forest/grass_plains.tres",
		"tile_type": "NORMAL",
	})
	assert_not_null(resolved, "maps authored before tile_id must keep loading")
	if resolved != null:
		assert_eq(resolved.get_id(), &"grass_plains")


func test_legacy_stale_path_still_falls_back_to_the_basename() -> void:
	# The pre-existing band-aid stays in place for maps that carry neither an id
	# nor a currently-valid path.
	var resolved := _resolve({
		"tile_resource_path": "res://game/tiles/resources/grass_plains.tres",
		"tile_type": "NORMAL",
	})
	assert_not_null(resolved, "a pre-reorg path must still find the moved asset")
	if resolved != null:
		assert_eq(resolved.get_id(), &"grass_plains")


func test_tile_type_family_is_the_last_resort() -> void:
	# No id, no path - the coarse type still yields terrain, now via the catalog.
	var resolved := _resolve({"tile_type": "LAVA"})
	assert_not_null(resolved)
	if resolved != null:
		assert_eq(resolved.get_id(), &"molten_lava")


func test_unresolvable_entry_returns_null() -> void:
	assert_null(_resolve({"tile_id": "nope", "tile_resource_path": "", "tile_type": "NOT_A_TYPE"}),
		"nothing resolvable must return null so the caller can fall back")


# --- MapResource authoring ------------------------------------------------------

func test_set_tile_at_position_stores_the_tile_id() -> void:
	var map := MapResource.new()
	map.set_tile_at_position(Vector2i(1, 2), "LAVA",
		"res://game/tiles/resources/volcano/molten_lava.tres", "molten_lava")
	var entry := map.get_tile_at_position(Vector2i(1, 2))
	assert_eq(str(entry.get("tile_id", "")), "molten_lava")
	assert_eq(str(entry.get("tile_resource_path", "")), "res://game/tiles/resources/volcano/molten_lava.tres",
		"the legacy path is still written for tools that read it")


func test_set_tile_at_position_keeps_its_old_signature() -> void:
	# Every pre-existing caller passes two or three arguments.
	var map := MapResource.new()
	map.set_tile_at_position(Vector2i(0, 0), "NORMAL")
	map.set_tile_at_position(Vector2i(0, 1), "WATER", "res://game/tiles/resources/common/deep_water.tres")
	assert_eq(str(map.get_tile_at_position(Vector2i(0, 0)).get("tile_id", "")), "")
	assert_eq(str(map.get_tile_at_position(Vector2i(0, 1)).get("tile_id", "")), "")
	assert_eq(map.tile_layout.size(), 2)
