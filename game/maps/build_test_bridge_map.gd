extends SceneTree

## Headless builder for the tiny MULTI-FLOOR test map "Bridge Test".
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_test_bridge_map.gd
##
## Writes [constant OUTPUT_PATH]. The same layout is available in code through
## [method build] (tests use both: the saved .tres, and build() to prove the file
## is up to date). Layout (9 x 7, x = column, y = row):
##
##   floor 0  : grass everywhere, a deep-water river down column 4, a stone wall
##              at (4, 5) (a LOS blocker for tests).
##   floor 1  : INTACT bridge on row 1, columns 2..6 (over the river and over the
##              grass either side -- floor-0 units walk UNDER it).
##              BROKEN bridge on row 3: columns 2, 3 and 5, 6 -- column 4 is a GAP.
##   links    : row 1 -- "stairs" tile flags: (1,1,0) climbs east onto (2,1,1),
##              (7,1,0) climbs west onto (6,1,1).
##              row 3 -- explicit ladders (cost 2): (1,3,0)<->(2,3,1), (7,3,0)<->(6,3,1).
##   spawns   : P0 at (0,1) (0,3) (0,5); P1 at (8,1) (8,3) (8,5) and an archer ON the
##              intact bridge at (5,1) floor 1.
##
## Status "Inactive": a draft/test fixture, kept out of the multiplayer lists.

const OUTPUT_PATH := "res://game/maps/resources/test_bridge_map.tres"
const WIDTH := 9
const HEIGHT := 7
const RIVER_X := 4
const INTACT_ROW := 1
const BROKEN_ROW := 3
const WALL_CELL := Vector2i(4, 5)


static func build() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Bridge Test"
	m.description = "Multi-floor test fixture: an intact bridge, a broken bridge and a river."
	m.author = "System"
	m.width = WIDTH
	m.height = HEIGHT
	m.max_players = 2
	m.status = "Inactive"
	m.tags = ["test", "multi-floor"] as Array[String]

	# Floor 0: river + one wall (grass elsewhere is the implicit default tile, but
	# write it explicitly so the preview shows it).
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var pos := Vector2i(x, y)
			if pos == WALL_CELL:
				m.set_tile_at_position(pos, "WALL", "", &"stone_wall")
			elif x == RIVER_X:
				m.set_tile_at_position(pos, "WATER", "", &"deep_water")
			else:
				m.set_tile_at_position(pos, "NORMAL", "", &"grass_plains")

	# Floor 1: intact bridge (row 1) and broken bridge (row 3, gap at the river).
	for x in range(2, 7):
		m.set_tile_at_position(Vector2i(x, INTACT_ROW), "NORMAL", "", &"forest_dirt", 1)
		if x != RIVER_X:
			m.set_tile_at_position(Vector2i(x, BROKEN_ROW), "NORMAL", "", &"forest_dirt", 1)

	# Stairs onto the intact bridge (tile flags -> auto links).
	m.set_stairs_at_position(Vector2i(1, INTACT_ROW), "east", 0)
	m.set_stairs_at_position(Vector2i(7, INTACT_ROW), "west", 0)
	# Ladders onto the broken bridge (explicit links).
	m.add_link(Vector3i(1, BROKEN_ROW, 0), Vector3i(2, BROKEN_ROW, 1), 2, "ladder")
	m.add_link(Vector3i(7, BROKEN_ROW, 0), Vector3i(6, BROKEN_ROW, 1), 2, "ladder")

	for y in [1, 3, 5]:
		m.set_character_spawn_at_position(Vector2i(0, y), 0, "vineweave")
		m.set_character_spawn_at_position(Vector2i(8, y), 1, "vineweave")
	m.set_spawn_point_at_position(Vector2i(5, INTACT_ROW), 1, MapResource.SPAWN_KIND_START,
		{ "character_id": "petalfang", "floor": 1 })
	return m


func _init() -> void:
	var m := build()
	var check := m.validate_map()
	if not check.valid:
		push_error("[build_test_bridge_map] invalid: %s" % str(check.issues))
		quit(1)
		return
	var err := ResourceSaver.save(m, OUTPUT_PATH)
	print("[build_test_bridge_map] saved %s -> %s (floors=%d, links=%d)" % [
		OUTPUT_PATH, error_string(err), m.get_floor_count(), m.get_links().size()])
	quit(0 if err == OK else 1)
