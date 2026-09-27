extends GutTest

## The multi-floor showcase maps (River Crossing, Castle Siege): the saved .tres
## files are up to date with their build scripts, validate, are listed for players,
## and their floor structure plays as designed (walk under the bridge, climb the
## walls, broken bridge impassable on foot).

const BuildRiver := preload("res://game/maps/build_river_crossing.gd")
const BuildCastle := preload("res://game/maps/build_castle_siege.gd")
const RIVER_PATH := "res://game/maps/resources/river_crossing.tres"
const CASTLE_PATH := "res://game/maps/resources/castle_siege.tres"


func _board(map: MapResource) -> BoardAdapter:
	var grid := Grid.new()
	grid.size = Vector3(map.width, 0, map.height)
	return BoardAdapter.new(grid, []).configure_from_map(map)


func _same_layout(a: MapResource, b: MapResource) -> void:
	assert_eq(a.width, b.width)
	assert_eq(a.height, b.height)
	assert_eq(a.tile_layout.size(), b.tile_layout.size(), "tile count")
	assert_eq(a.unit_spawns.size(), b.unit_spawns.size(), "spawn count")
	assert_eq(a.get_links().size(), b.get_links().size(), "link count")
	assert_eq(a.get_floor_count(), b.get_floor_count(), "floor count")


func test_saved_maps_match_their_builders() -> void:
	_same_layout(load(RIVER_PATH), BuildRiver.build())
	_same_layout(load(CASTLE_PATH), BuildCastle.build())


func test_maps_validate_and_are_listed() -> void:
	var listed := MapLoader.get_available_maps()
	for path in [RIVER_PATH, CASTLE_PATH]:
		var m: MapResource = load(path)
		var v := m.validate_map()
		assert_true(v.valid, "%s valid: %s" % [path, str(v.issues)])
		assert_true(m.is_active(), "%s is player-facing" % path)
		assert_true(listed.has(path), "%s appears in map selection" % path)
		assert_gt(m.get_total_units_for_player(0), 3)
		assert_gt(m.get_total_units_for_player(1), 3)


func test_river_crossing_structure() -> void:
	var m: MapResource = BuildRiver.build()
	var b := _board(m)
	assert_eq(b.floor_count(), 2)
	# The towpath runs under the stone bridge.
	assert_true(b.has_tile(Vector3i(5, 4, 0)) and b.has_tile(Vector3i(5, 4, 1)))
	assert_true(FloorNav.is_covered(b, Vector3i(5, 4, 0)))
	# Stairs climb onto both ends; the broken bridge has a gap over the river.
	assert_true(b.are_linked(Vector3i(3, 4, 0), Vector3i(4, 4, 1)))
	assert_true(b.are_linked(Vector3i(11, 5, 0), Vector3i(10, 5, 1)))
	assert_false(b.has_tile(Vector3i(7, 8, 1)), "broken bridge gap")
	assert_true(b.are_linked(Vector3i(3, 8, 0), Vector3i(4, 8, 1)))
	# Units on both levels.
	var floors := {}
	for s in m.unit_spawns:
		floors[MapResource.entry_floor(s)] = true
	assert_true(floors.has(0) and floors.has(1))


func test_castle_siege_structure() -> void:
	var m: MapResource = BuildCastle.build()
	var b := _board(m)
	assert_eq(b.floor_count(), 3)
	assert_true(b.has_tile(Vector3i(7, 6, 0)) and b.has_tile(Vector3i(7, 6, 1)), "gate passage under the walk")
	assert_true(FloorNav.is_covered(b, Vector3i(7, 6, 0)))
	assert_true(b.is_blocked(Vector3i(7, 5, 0)), "curtain wall")
	assert_true(b.are_linked(Vector3i(8, 4, 0), Vector3i(7, 4, 1)), "courtyard stairs to the west wall")
	assert_true(b.are_linked(Vector3i(8, 2, 1), Vector3i(7, 2, 2)), "walk stairs to the NW tower")
	assert_true(b.has_tile(Vector3i(13, 10, 2)), "SE tower top")
	var defenders_up := 0
	for s in m.unit_spawns:
		if int(s.get("player_id", -1)) == 1 and MapResource.entry_floor(s) > 0:
			defenders_up += 1
	assert_gt(defenders_up, 1, "archers man the walls")


func test_floor_decor_builds_for_multi_floor_only() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	FloorDecor.build_floor_decor(BuildRiver.build(), root)
	assert_not_null(root.get_node_or_null("Decor/Floor_1/Decor"), "upper-floor dressing mesh")
	assert_not_null(root.get_node_or_null("Decor/Floor_0/Decor"), "rubble under the broken bridge")
	var flat := Node3D.new()
	add_child_autofree(flat)
	var single := MapResource.new()
	single.width = 5
	single.height = 5
	FloorDecor.build_floor_decor(single, flat)
	assert_eq(flat.get_child_count(), 0, "classic maps get no decor")


func test_link_visuals_for_each_kind() -> void:
	var stairs := FloorDecor.make_link_visual({ "from": Vector3i(1, 1, 0), "to": Vector3i(2, 1, 1), "kind": "stairs" })
	var ladder := FloorDecor.make_link_visual({ "from": Vector3i(1, 3, 0), "to": Vector3i(2, 3, 1), "kind": "ladder" })
	var hatch := FloorDecor.make_link_visual({ "from": Vector3i(1, 3, 0), "to": Vector3i(1, 3, 1), "kind": "ladder" })
	for v in [stairs, ladder, hatch]:
		assert_not_null(v)
		assert_eq(int(v.get_meta(FloorDecor.META_FLOOR)), 1, "ghosts with the upper floor")
		var mi := v.get_node("Mesh") as MeshInstance3D
		assert_gt(mi.mesh.get_surface_count(), 0)
		v.free()
