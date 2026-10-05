class_name EncounterZone
extends Resource

## Where wild creatures live (docs/design/OVERWORLD.md §4.2 / §4.5). A zone is a cell rect AND/OR a
## set of tile ids -- [code][&"tall_grass"][/code] makes the grass itself the zone, no double
## authoring.
##
## TWO MODES ([member mode]):
## - [constant Mode.VISIBLE] (the DEFAULT, Let's Go / Mystery Dungeon "symbol" encounters):
##   [member max_active] creatures from [member table] stand on the zone's cells, step one cell per
##   player step by their species' [member EncounterEntry.behaviour], and a battle starts on
##   CONTACT. Run by [WildSpawner]; beaten ones come back by [member respawn].
## - [constant Mode.HIDDEN] (opt-in, the classic tall-grass roll): every step onto a zone cell rolls
##   [member rate]; [member grace_steps] steps after a battle or area entry never roll
##   ([EncounterRoller]). Keep it for places where surprise is the point (caves, night swamps).
##
## Both are deterministic (journey seed + area + counters, never randf()).

enum Mode {
	VISIBLE,  ## visible, grid-locked wild creatures (the default)
	HIDDEN,   ## hidden per-step rolls (the classic tall grass)
}

## When beaten / befriended VISIBLE creatures come back. Mirrors [enum ShopResource.Restock].
enum Respawn {
	ON_REST,        ## after a rest (Wayshrine / healer / whiteout): [member StoryState.rests]
	ON_REENTER,     ## every time the player enters the area from another one (a fresh roster)
	EVERY_N_STEPS,  ## every [member respawn_steps] steps walked: [member StoryState.steps]
}

## Stable key for this zone's saved spawn state ("" = its index in the area's zone list, "z0").
## Set it once a zone ships if zones may be reordered later.
@export var zone_id: StringName = &""
@export var mode: Mode = Mode.VISIBLE
## Empty rect (size 0) = the whole area.
@export var area_rect: Rect2i = Rect2i()
@export var tile_ids: Array[StringName] = [&"tall_grass"]
@export var table: Array[Resource] = []
## Steps after a battle or area entry with no wild battle: HIDDEN zones never roll, VISIBLE
## creatures never walk INTO you (you may still walk into them).
@export_range(0, 20) var grace_steps: int = 3
## The STORY LEVELS its creatures roll in (min, max; docs/design/PROGRESSION.md §3). Unset
## (0, 0) = the area's [member OverworldAreaResource.level_band].
@export var level_band: Vector2i = Vector2i.ZERO

@export_group("Hidden (grass rolls)")
## HIDDEN: the per-step encounter chance.
@export_range(0.0, 1.0) var rate: float = 0.08

@export_group("Visible (wild creatures)")
## VISIBLE: creatures standing in the zone at once (3-6 reads well on a ~32x32 area).
@export_range(1, 8) var max_active: int = 4
@export var respawn: Respawn = Respawn.ON_REENTER
## Steps per respawn for [constant Respawn.EVERY_N_STEPS].
@export_range(1, 10000) var respawn_steps: int = 150
## No creature is placed within this many cells (Manhattan) of the player when a roster is rolled.
@export_range(0, 8) var spawn_clearance: int = 3


func is_visible_mode() -> bool:
	return mode == Mode.VISIBLE


func is_hidden_mode() -> bool:
	return mode == Mode.HIDDEN


## The save key of this zone, given its [param index] in the area's list.
func key(index: int) -> String:
	return String(zone_id) if not String(zone_id).is_empty() else "z%d" % index


## The level band this zone's creatures roll in: its own [member level_band], else
## [param area]'s; Vector2i.ZERO when neither is set (no levels).
func band_in(area: OverworldAreaResource) -> Vector2i:
	var own: Vector2i = Progression.normalize_band(level_band)
	if own != Vector2i.ZERO:
		return own
	return Progression.normalize_band(area.level_band) if area != null else Vector2i.ZERO


## Is [param cell] (whose tile is [param tile_id]) part of this zone?
func contains(cell: Vector3i, tile_id: StringName) -> bool:
	if area_rect.size != Vector2i.ZERO and not area_rect.has_point(Vector2i(cell.x, cell.y)):
		return false
	if not tile_ids.is_empty() and not tile_ids.has(tile_id):
		return false
	return true


func entries() -> Array[EncounterEntry]:
	var out: Array[EncounterEntry] = []
	for e in table:
		var entry := e as EncounterEntry
		if entry != null:
			out.append(entry)
	return out


## The first entry for [param character_id] (a saved creature's row), or null.
func entry_for(character_id: String) -> EncounterEntry:
	for e in entries():
		if String(e.character_id) == character_id:
			return e
	return null


static func respawn_name(r: int) -> String:
	match r:
		Respawn.ON_REST:
			return "on rest"
		Respawn.EVERY_N_STEPS:
			return "every N steps"
	return "on re-enter"


func validate(issues: Array[String], where: String) -> void:
	if entries().is_empty():
		issues.append("%s: encounter zone has an empty table" % where)
	for e in entries():
		if CharacterLibrary.get_character(e.character_id) == null:
			issues.append("%s: encounter character '%s' does not exist" % [where, e.character_id])
		StoryCommand.check_condition(e.condition, issues, "%s encounter condition" % where)
		if e.kind == EncounterEntry.Kind.TACTICAL:
			if e.battle == null:
				issues.append("%s: tactical encounter '%s' has no battle" % [where, e.character_id])
			else:
				e.battle.validate(issues)
		if is_visible_mode() and e.behaviour == EncounterEntry.Behaviour.PATROL and e.patrol.size() < 2:
			issues.append("%s: patrolling '%s' needs at least two waypoints" % [where, e.character_id])


func _to_string() -> String:
	if is_hidden_mode():
		return "EncounterZone(hidden %.0f%%, %d entries)" % [rate * 100.0, entries().size()]
	return "EncounterZone(visible x%d, respawn %s, %d entries)" % [max_active, respawn_name(respawn), entries().size()]
