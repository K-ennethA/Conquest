extends RefCounted

## TEST-ONLY FIXTURE AREA for visible wild creatures ([WildSpawner]). Built in memory (no disk
## writes, nothing under game/overworld/content/areas): a 14x10 meadow with a tall-grass field at
## x 3..10, y 2..7, a stone wall at (0..13, 0) and an entry at (1, 5). Integration suites hand it to
## StoryController with adopt_area(AREA_ID, area) and boot the real OverworldScene on it.

const AREA_ID := "wild_test"
const W := 14
const H := 10
const GRASS := Rect2i(3, 2, 8, 6)
const ENTRY := Vector3i(1, 5, 0)


static func terrain() -> MapResource:
	var m := MapResource.new()
	m.map_name = "Wild Test"
	m.width = W
	m.height = H
	for y in range(H):
		for x in range(W):
			var id := "grass_plains"
			if y == 0:
				id = "stone_wall"
			elif GRASS.has_point(Vector2i(x, y)):
				id = "tall_grass"
			m.set_tile_at_position(Vector2i(x, y), "NORMAL", "", id)
	return m


static func entry(cid: String, behaviour: int = EncounterEntry.Behaviour.WANDER, weight: float = 1.0) -> EncounterEntry:
	var e := EncounterEntry.new()
	e.character_id = StringName(cid)
	e.weight = weight
	e.behaviour = behaviour
	e.kind = EncounterEntry.Kind.DUEL
	e.can_befriend = true
	return e


static func zone(entries: Array, max_active: int = 4,
		respawn: int = EncounterZone.Respawn.ON_REENTER) -> EncounterZone:
	var z := EncounterZone.new()
	var ids: Array[StringName] = [&"tall_grass"]
	z.tile_ids = ids
	z.mode = EncounterZone.Mode.VISIBLE
	z.max_active = max_active
	z.respawn = respawn
	z.grace_steps = 0
	var table: Array[Resource] = []
	for e in entries:
		table.append(e)
	z.table = table
	return z


## The fixture area with [param zones] (default: one visible zone of four wandering Petalfang /
## Blightcap).
static func area(zones: Array = []) -> OverworldAreaResource:
	var a := OverworldAreaResource.new()
	a.area_id = StringName(AREA_ID)
	a.display_name = "Wild Test"
	a.kind = OverworldAreaResource.Kind.ROUTE
	a.terrain = terrain()
	a.entry_points = {"west": {"cell": [ENTRY.x, ENTRY.y, 0], "facing": "east"}}
	if zones.is_empty():
		zones = [zone([entry("petalfang"), entry("blightcap")])]
	var typed: Array[Resource] = []
	for z in zones:
		typed.append(z)
	a.encounter_zones = typed
	return a
