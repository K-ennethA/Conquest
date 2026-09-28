class_name EncounterZone
extends Resource

## Where wild encounters roll (docs/design/OVERWORLD.md §4.2). A zone is a cell rect AND/OR a
## set of tile ids -- [code][&"tall_grass"][/code] makes the grass itself the zone, no double
## authoring. [member rate] is the per-step chance; [member grace_steps] steps after a battle or
## area entry never roll. Rolls are deterministic ([EncounterRoller]).

## Empty rect (size 0) = the whole area.
@export var area_rect: Rect2i = Rect2i()
@export var tile_ids: Array[StringName] = [&"tall_grass"]
@export_range(0.0, 1.0) var rate: float = 0.08
@export_range(0, 20) var grace_steps: int = 3
@export var table: Array[Resource] = []


## Does a step onto [param cell] (whose tile is [param tile_id]) roll in this zone?
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
