extends SceneTree

## Headless builder for the multi-floor showcase map "Castle Siege".
##
## Run with:
##   godot --headless --path . -s res://game/maps/build_castle_siege.gd
##
## Writes [constant OUTPUT_PATH]; [method build] returns the same map in code.
## 15 x 13, mirror-symmetric north/south (y -> 12 - y). Player 0 ATTACKS from the
## western fields, player 1 DEFENDS the castle.
##
##   floor 0 : a moat (west col 6, north row 1, south row 11) with a timber
##             drawbridge at (6,6); a dirt road to it; the castle's curtain wall
##             ring (x 7-13, y 2-10) of stone_wall with a GATE PASSAGE at (7,6)
##             that runs UNDER the gatehouse walkway; a paved courtyard inside
##             with a sacred well at its centre.
##   floor 1 : the rampart walk on top of the whole ring (incl. above the gate);
##             the four corner cells are stone TOWER bases (impassable).
##   floor 2 : the four tower tops, each reached by stairs from both adjoining
##             rampart walks.
##   links   : stairs from the courtyard up to the west / east walls and to the
##             middle of the north / south walls; stairs from the walks to the
##             towers.
##   spawns  : 6 attackers in the west; 5 defenders -- archers on the west
##             ramparts and a tower, melee holding the gate and courtyard.

const OUTPUT_PATH := "res://game/maps/resources/castle_siege.tres"
const WIDTH := 15
const HEIGHT := 13
const X0 := 7
const X1 := 13
const Y0 := 2
const Y1 := 10
const GATE := Vector2i(7, 6)
const MOAT_X := 6
const TOWERS := [Vector2i(X0, Y0), Vector2i(X0, Y1), Vector2i(X1, Y0), Vector2i(X1, Y1)]

## North-half field features (mirrored to the south).
const TREES := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(3, 0), Vector2i(0, 2), Vector2i(4, 2), Vector2i(14, 0)]
const TALL_GRASS := [Vector2i(2, 1), Vector2i(3, 3), Vector2i(4, 4), Vector2i(1, 3), Vector2i(5, 3)]


static func mirror(p: Vector2i) -> Vector2i:
	return Vector2i(p.x, HEIGHT - 1 - p.y)


static func is_ring(p: Vector2i) -> bool:
	var inside := p.x >= X0 and p.x <= X1 and p.y >= Y0 and p.y <= Y1
	return inside and (p.x == X0 or p.x == X1 or p.y == Y0 or p.y == Y1)


static func build() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Castle Siege"
	# Battle weather (docs/WEATHER.md).
	m.set_weather_settings({"mode": "schedule", "weather": "clear", "schedule": [{"weather": "clear", "rounds": 3}, {"weather": "rain", "rounds": 3}]})
	m.description = "Storm the keep. Archers man the ramparts and towers, the gate passage runs beneath the gatehouse walk, and stairs climb from the courtyard to the walls. Multi-floor: Page Up / Page Down to see inside the walls."
	m.author = "System"
	m.width = WIDTH
	m.height = HEIGHT
	m.max_players = 2
	m.recommended_players = 2
	m.difficulty = "Hard"
	m.map_type = "Skirmish"
	m.status = "Active"
	m.tags = ["multi-floor", "castle", "siege"] as Array[String]

	# --- Floor 0 ------------------------------------------------------------------
	for x in range(WIDTH):
		for y in range(HEIGHT):
			var p := Vector2i(x, y)
			var id := &"grass_plains"
			var type := "NORMAL"
			if is_ring(p):
				id = &"stone_wall"
				type = "WALL"
			elif x > X0 and x < X1 and y > Y0 and y < Y1:
				id = &"flagstones"
			elif (x == MOAT_X and y >= 1 and y <= HEIGHT - 2) or ((y == 1 or y == HEIGHT - 2) and x >= MOAT_X):
				id = &"deep_water"
				type = "WATER"
			m.set_tile_at_position(p, type, "", id)
	for p in TREES:
		for q in [p, mirror(p)]:
			m.set_tile_at_position(q, "NORMAL", "", &"tree")
	for p in TALL_GRASS:
		for q in [p, mirror(p)]:
			m.set_tile_at_position(q, "NORMAL", "", &"tall_grass")
	for x in range(0, MOAT_X):
		m.set_tile_at_position(Vector2i(x, GATE.y), "NORMAL", "", &"forest_dirt")
	m.set_tile_at_position(Vector2i(MOAT_X, GATE.y), "NORMAL", "", &"wooden_planks")  # drawbridge
	m.set_tile_at_position(GATE, "NORMAL", "", &"flagstones")  # the gate passage
	m.set_tile_at_position(Vector2i(10, 6), "SACRED_GROUND", "", &"sacred_ground")  # courtyard well

	# --- Floor 1: rampart walk + tower bases --------------------------------------------
	for x in range(X0, X1 + 1):
		for y in range(Y0, Y1 + 1):
			var p := Vector2i(x, y)
			if not is_ring(p):
				continue
			if p in TOWERS:
				m.set_tile_at_position(p, "WALL", "", &"stone_wall", 1)
			else:
				m.set_tile_at_position(p, "NORMAL", "", &"flagstones", 1)

	# --- Floor 2: tower tops ------------------------------------------------------------
	for t in TOWERS:
		m.set_tile_at_position(t, "NORMAL", "", &"flagstones", 2)

	# --- Stairs ---------------------------------------------------------------------------
	# Courtyard -> walls.
	for y in [4, 8]:
		m.set_stairs_at_position(Vector2i(X0 + 1, y), "west", 0)
		m.set_stairs_at_position(Vector2i(X1 - 1, y), "east", 0)
	m.set_stairs_at_position(Vector2i(10, Y0 + 1), "north", 0)
	m.set_stairs_at_position(Vector2i(10, Y1 - 1), "south", 0)
	# Walks -> towers (both adjoining walks of every tower).
	for t in TOWERS:
		var along_x := Vector2i(t.x + (1 if t.x == X0 else -1), t.y)
		var along_y := Vector2i(t.x, t.y + (1 if t.y == Y0 else -1))
		m.set_stairs_at_position(along_x, "west" if t.x == X0 else "east", 1)
		m.set_stairs_at_position(along_y, "north" if t.y == Y0 else "south", 1)

	# --- Spawns ------------------------------------------------------------------------------
	for s in [
		[Vector2i(1, 5), "vineweave"], [Vector2i(1, 7), "tree_grunt"], [Vector2i(2, 6), "gem_knight"],
		[Vector2i(0, 4), "petalfang"], [Vector2i(0, 8), "blightcap"], [Vector2i(0, 6), "mycothrall"],
	]:
		m.set_spawn_point_at_position(s[0], 0, MapResource.SPAWN_KIND_START, { "character_id": s[1] })
	var hold := { "ai_stance": "defensive", "aggro_range": 6 }
	var perch := { "ai_stance": "defensive", "aggro_range": 7, "leash_radius": 3 }
	_defender(m, Vector2i(X0, 4), 1, "petalfang", perch)
	_defender(m, Vector2i(X0, 8), 1, "petalfang", perch)
	_defender(m, Vector2i(X0, Y0), 2, "blightcap", perch)
	_defender(m, Vector2i(X0 + 1, 6), 0, "gem_knight", hold)
	_defender(m, Vector2i(11, 6), 0, "necromancer", hold)
	return m


static func _defender(m: MapResource, pos: Vector2i, floor_index: int, character: String, opts: Dictionary) -> void:
	var o := opts.duplicate()
	o["character_id"] = character
	if floor_index > 0:
		o["floor"] = floor_index
	m.set_spawn_point_at_position(pos, 1, MapResource.SPAWN_KIND_START, o)


func _init() -> void:
	var m := build()
	var check := m.validate_map()
	if not check.valid:
		push_error("[build_castle_siege] invalid: %s" % str(check.issues))
		quit(1)
		return
	var err := ResourceSaver.save(m, OUTPUT_PATH)
	print("[build_castle_siege] saved %s -> %s (floors=%d, links=%d, spawns=%d)" % [
		OUTPUT_PATH, error_string(err), m.get_floor_count(), m.get_links().size(), m.unit_spawns.size()])
	quit(0 if err == OK else 1)
