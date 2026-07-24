extends AbilityCondition
class_name OnTerrainCondition

## Met while the unit stands on a tile matching [member terrain_id] — the data
## backbone of "empowered on water", "steady on fortify tiles", and similar
## terrain-keyed powers.
##
## Terrain identity is read duck-typed from the board, preferring a tag accessor
## over a raw id so authors can key on broad tags ("water") rather than specific
## tile ids. Either accessor may return a single value or an [Array] of tags; a
## match is exact-equality against the value, or membership when it is an array.
## If the board exposes neither accessor, the condition degrades to false rather
## than erroring.

## Terrain tag or tile id the unit must be standing on for the ability to apply.
@export var terrain_id: StringName = &""


func is_met(unit, board) -> bool:
	if unit == null or board == null:
		return false
	if not board.has_method("cell_of"):
		return false
	var cell = board.cell_of(unit)
	if board.has_method("tile_tag_at"):
		return _matches(board.tile_tag_at(cell))
	if board.has_method("tile_id_at"):
		return _matches(board.tile_id_at(cell))
	return false  # board can't report terrain — fail closed


func describe() -> String:
	return "on %s" % terrain_id


## True if [param value] (a single tag/id or an Array of them) matches
## [member terrain_id]. StringName/String compare by value in GDScript.
func _matches(value) -> bool:
	if value is Array:
		return terrain_id in value
	return value == terrain_id
