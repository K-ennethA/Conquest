class_name OverworldAreaResource
extends Resource

## ONE WALKABLE AREA of story mode (a town, a route, an interior) -- docs/design/OVERWORLD.md
## §4.2. The TERRAIN is an ordinary [MapResource] painted in the Map Maker (it lives beside this
## file under game/overworld/content/areas/<id>/, so MapLoader.get_available_maps -- which only
## scans game/maps/resources/ -- never lists it in a Skirmish / network picker). Everything story
## lives HERE: entities, encounter zones, arrival points, first-visit scripts.
##
## A MapResource is also the community/JSON interchange format; story data (scripts that
## reference .tres) deliberately never goes into it.

enum Kind { TOWN, ROUTE, INTERIOR, DUNGEON }

@export var area_id: StringName = &""
@export var display_name: String = ""
@export var terrain: MapResource
@export var kind: Kind = Kind.TOWN
@export var region_id: StringName = &"forgotten_forest"
@export var world_map_pos: Vector2 = Vector2.ZERO
## Named arrivals: {entry_id: {"cell": [c, r, f] | Vector3i, "facing": "south"}}. Read ONLY
## through [method entry] (coercion helper -- CONQUEST.md rule 3).
@export var entry_points: Dictionary = {}
@export var entities: Array[Resource] = []
@export var encounter_zones: Array[Resource] = []
## Scripts run on area load whose own conditions gate them (first-visit cutscenes).
@export var on_enter: Array[Resource] = []
@export var music_cue: StringName = &""
## "" = the terrain's own lighting preset.
@export var lighting_preset_override: String = ""
## An INTERIOR's town: the area whose building door leads here (docs/STORY_MODE.md "Interiors").
## The world map lists the interior under the town's place, so "You are here" stays the town.
@export var parent_area: StringName = &""
## The area's STORY LEVEL BAND (min, max -- docs/design/PROGRESSION.md §3, DECISIONS.md #76): what
## its wild creatures roll ([member EncounterZone.level_band] may narrow it per zone), what a
## SCALED chief clamps into and what a LEGEND is authored above. (0, 0) = unset (no levels).
@export var level_band: Vector2i = Vector2i.ZERO


func is_interior() -> bool:
	return kind == Kind.INTERIOR


## Where shipped areas live: <AREAS_DIR><area_id>/area.tres (StoryController.area_path).
const AREAS_DIR := "res://game/overworld/content/areas/"


static func path_for(p_area_id: String) -> String:
	return "%s%s/area.tres" % [AREAS_DIR, p_area_id]


## The shipped area [param p_area_id] (trusted content), or null. Menus and evolution
## requirements ([LocationTrigger]) read names / regions / weather through it.
static func load_by_id(p_area_id: String) -> OverworldAreaResource:
	if p_area_id.is_empty():
		return null
	var path: String = path_for(p_area_id)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as OverworldAreaResource


## The weather id this area's terrain shows ("clear" when unset).
func weather_id() -> String:
	if terrain != null and not String(terrain.weather).is_empty():
		return String(terrain.weather)
	return "clear"


func lighting_preset() -> String:
	if not lighting_preset_override.is_empty():
		return lighting_preset_override
	return String(terrain.lighting_preset) if terrain != null else "Day"


func width() -> int:
	return terrain.width if terrain != null else 0


func height() -> int:
	return terrain.height if terrain != null else 0


func in_bounds(c: Vector3i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width() and c.y < height() and c.z == 0


## {cell: Vector3i, facing: String} for [param entry_id], or {} when unknown / malformed.
func entry(entry_id: String) -> Dictionary:
	var raw = entry_points.get(entry_id, entry_points.get(StringName(entry_id), null))
	if not (raw is Dictionary):
		return {}
	var c: Vector3i = Cells.from_variant(raw.get("cell", null))
	if c == Cells.INVALID:
		return {}
	var f: String = String(raw.get("facing", "south"))
	if not StoryState.FACING_NAMES.has(f):
		f = "south"
	return {"cell": c, "facing": f}


func entry_ids() -> Array[String]:
	var out: Array[String] = []
	for k in entry_points:
		out.append(String(k))
	return out


## The typed entity list (null / foreign entries filtered out, like StoryScene.playable_beats).
func entity_list() -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	for e in entities:
		var ent := e as OverworldEntity
		if ent != null:
			out.append(ent)
	return out


func entity(entity_id: String) -> OverworldEntity:
	for e in entity_list():
		if String(e.id) == entity_id:
			return e
	return null


## Entities present under [param state]'s flags (visible_if).
func present_entities(state: StoryState) -> Array[OverworldEntity]:
	var out: Array[OverworldEntity] = []
	for e in entity_list():
		if e.is_present(state):
			out.append(e)
	return out


func zones() -> Array[EncounterZone]:
	var out: Array[EncounterZone] = []
	for z in encounter_zones:
		var zone := z as EncounterZone
		if zone != null:
			out.append(zone)
	return out


## Structural + content validation (the content test runs this on every area). Returns issues.
func validate() -> Array[String]:
	var issues: Array[String] = []
	var aid: String = String(area_id)
	if aid.is_empty():
		issues.append("area has no area_id")
	if terrain == null:
		issues.append("%s: no terrain" % aid)
		return issues
	var tv: Dictionary = terrain.validate_map(true)
	if not bool(tv.get("valid", false)):
		issues.append("%s: terrain fails validation: %s" % [aid, str(tv.get("issues", []))])
	if entry_points.is_empty():
		issues.append("%s: no entry points" % aid)
	for eid in entry_ids():
		var e: Dictionary = entry(eid)
		if e.is_empty():
			issues.append("%s: entry '%s' is malformed" % [aid, eid])
		elif not in_bounds(e["cell"]):
			issues.append("%s: entry '%s' is off the map" % [aid, eid])
	var seen: Dictionary = {}
	for ent in entity_list():
		var key: String = String(ent.id)
		if seen.has(key):
			issues.append("%s: duplicate entity id '%s'" % [aid, key])
		seen[key] = true
		for c in ent.cells():
			if not in_bounds(c):
				issues.append("%s: entity '%s' has a cell off the map (%s)" % [aid, key, str(c)])
				break
		ent.validate(self, issues)
	for i in range(zones().size()):
		zones()[i].validate(issues, "%s/zone%d" % [aid, i])
	StoryCommand.validate_list(on_enter, issues, "%s/on_enter" % aid)
	return issues


func _to_string() -> String:
	return "Area '%s' (%s, %d entities)" % [String(area_id), display_name, entity_list().size()]
