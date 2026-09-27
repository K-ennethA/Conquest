extends SceneTree

## Headless builder for the multi-floor showcase map "River Crossing".
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_river_crossing.gd
##
## Writes [constant OUTPUT_PATH]; [method build] returns the same map in code (the
## tests check the saved file matches it). Mirror-symmetric (x -> 14 - x), 15 x 11:
##
##   floor 0 : a three-wide river (cols 6-8), flagstone towpaths along both banks
##             (cols 5 and 9) that run UNDER the stone bridge, dirt roads to the
##             stairs, woods and tall grass on the flanks for cover.
##   floor 1 : a two-wide STONE BRIDGE (rows 4-5, cols 4-10) -- towpath traffic
##             passes beneath it -- climbed by stone stairs at both ends
##             ((3,4|5,0) -> east, (11,4|5,0) -> west);
##             a BROKEN timber bridge (row 8, cols 4-6 | 8-10, gap over col 7)
##             reached by ladders (cost 2) from (3,8,0) and (11,8,0).
##   spawns  : five units a side on the flanks, plus each side's Petalfang archer
##             perched on its half of the broken bridge (floor 1).

const OUTPUT_PATH := "res://game/maps/resources/river_crossing.tres"
const WIDTH := 15
const HEIGHT := 11
const RIVER := [6, 7, 8]
const TOWPATHS := [5, 9]
const BRIDGE_ROWS := [4, 5]
const BRIDGE_X0 := 4
const BRIDGE_X1 := 10
const BROKEN_ROW := 8
const GAP_X := 7

## West-half features (mirrored to the east).
const TREES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(2, 2), Vector2i(0, 9),
	Vector2i(1, 10), Vector2i(3, 10), Vector2i(4, 0)]
const TALL_GRASS := [Vector2i(3, 1), Vector2i(2, 1), Vector2i(3, 2), Vector2i(1, 8), Vector2i(2, 8),
	Vector2i(2, 9), Vector2i(4, 7), Vector2i(4, 10)]


static func mirror(p: Vector2i) -> Vector2i:
	return Vector2i(WIDTH - 1 - p.x, p.y)


static func build() -> MapResource:
	var m := MapResource.new()
	m.map_name = "River Crossing"
	m.description = "A river splits the field. Hold the stone bridge -- or slip along the towpaths beneath it -- while archers duel from the ruins of the broken bridge downstream. Multi-floor: Page Up / Page Down to look under the bridge."
	m.author = "System"
	m.width = WIDTH
	m.height = HEIGHT
	m.max_players = 2
	m.recommended_players = 2
	m.difficulty = "Normal"
	m.map_type = "Skirmish"
	m.status = "Active"
	m.tags = ["multi-floor", "bridge", "river"] as Array[String]

	# --- Floor 0 ------------------------------------------------------------------
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var pos := Vector2i(x, y)
			if x in RIVER:
				m.set_tile_at_position(pos, "WATER", "", &"deep_water")
			elif x in TOWPATHS:
				m.set_tile_at_position(pos, "NORMAL", "", &"flagstones")
			else:
				m.set_tile_at_position(pos, "NORMAL", "", &"grass_plains")
	for p in TREES:
		for q in [p, mirror(p)]:
			m.set_tile_at_position(q, "NORMAL", "", &"tree")
	for p in TALL_GRASS:
		for q in [p, mirror(p)]:
			m.set_tile_at_position(q, "NORMAL", "", &"tall_grass")
	# Dirt roads from the edges to the bridge stairs, and a track to the ladders.
	for x in range(0, BRIDGE_X0):
		for y in BRIDGE_ROWS:
			for q in [Vector2i(x, y), mirror(Vector2i(x, y))]:
				m.set_tile_at_position(q, "NORMAL", "", &"forest_dirt")
	for q in [Vector2i(3, 7), Vector2i(3, 6), mirror(Vector2i(3, 7)), mirror(Vector2i(3, 6))]:
		m.set_tile_at_position(q, "NORMAL", "", &"forest_dirt")
	for q in [Vector2i(BRIDGE_X0, 4), Vector2i(BRIDGE_X0, 5)]:
		m.set_tile_at_position(q, "NORMAL", "", &"flagstones")
		m.set_tile_at_position(mirror(q), "NORMAL", "", &"flagstones")
	m.set_tile_at_position(Vector2i(3, BROKEN_ROW), "NORMAL", "", &"forest_dirt")
	m.set_tile_at_position(mirror(Vector2i(3, BROKEN_ROW)), "NORMAL", "", &"forest_dirt")

	# --- Floor 1: the stone bridge --------------------------------------------------
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		for y in BRIDGE_ROWS:
			m.set_tile_at_position(Vector2i(x, y), "NORMAL", "", &"flagstones", 1)
	for y in BRIDGE_ROWS:
		m.set_stairs_at_position(Vector2i(BRIDGE_X0 - 1, y), "east", 0)
		m.set_stairs_at_position(Vector2i(BRIDGE_X1 + 1, y), "west", 0)

	# --- Floor 1: the broken timber bridge ------------------------------------------
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		if x != GAP_X:
			m.set_tile_at_position(Vector2i(x, BROKEN_ROW), "NORMAL", "", &"wooden_planks", 1)
	m.add_link(Vector3i(BRIDGE_X0 - 1, BROKEN_ROW, 0), Vector3i(BRIDGE_X0, BROKEN_ROW, 1), 2, "ladder")
	m.add_link(Vector3i(BRIDGE_X1 + 1, BROKEN_ROW, 0), Vector3i(BRIDGE_X1, BROKEN_ROW, 1), 2, "ladder")

	# --- Spawns (mirrored) -------------------------------------------------------------
	var squad := [
		[Vector2i(1, 4), "vineweave", 0],
		[Vector2i(1, 5), "gem_knight", 0],
		[Vector2i(0, 3), "tree_grunt", 0],
		[Vector2i(0, 6), "blightcap", 0],
		[Vector2i(1, 7), "mycothrall", 0],
		[Vector2i(BRIDGE_X0, BROKEN_ROW), "petalfang", 1],
	]
	for s in squad:
		var pos: Vector2i = s[0]
		var opts := { "character_id": String(s[1]) }
		if int(s[2]) > 0:
			opts["floor"] = int(s[2])
		m.set_spawn_point_at_position(pos, 0, MapResource.SPAWN_KIND_START, opts)
		m.set_spawn_point_at_position(mirror(pos), 1, MapResource.SPAWN_KIND_START, opts.duplicate())
	return m


func _init() -> void:
	var m := build()
	var check := m.validate_map()
	if not check.valid:
		push_error("[build_river_crossing] invalid: %s" % str(check.issues))
		quit(1)
		return
	var err := ResourceSaver.save(m, OUTPUT_PATH)
	print("[build_river_crossing] saved %s -> %s (floors=%d, links=%d, spawns=%d)" % [
		OUTPUT_PATH, error_string(err), m.get_floor_count(), m.get_links().size(), m.unit_spawns.size()])
	quit(0 if err == OK else 1)
