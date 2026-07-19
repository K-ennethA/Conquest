extends RefCounted
class_name TerrainStats

## Passive stat bonuses the terrain under a unit grants it, summed at combat time
## (the Fire-Emblem "terrain avoid" model: a forest gives +avoid, computed when the
## attack is forecast/resolved, not stored as a standing buff on the unit).
##
## Tile effects author these as PASSIVE_WHILE_OCCUPYING [StatModifierEffect]s.
## [TileEffectSystem] only reads PASSIVE effects for their rule_flags, so those
## stat bonuses would otherwise never reach combat -- this helper is what makes
## them count. Because [method CombatServices.tile_effects_at] merges a cell's
## BASE + runtime effects, a tile that is both tall grass (+evasion) and on fire
## contributes each layer's bonus here.


## Sum the [param stat_name] bonus from every passive tile effect under [param unit].
## [param board] is optional; when it exposes tile_effects_at/cell_of that source is
## used (keeps unit tests mockable), otherwise the live CombatServices board is queried.
static func bonus_for(unit, stat_name: String, board = null) -> int:
	if unit == null:
		return 0
	var cell := _cell_of(unit, board)
	var total := 0
	for te in _effects_at(cell, board):
		if te == null or te.trigger != TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING:
			continue
		for e in te.effects:
			if e is StatModifierEffect and e.stat_name == stat_name:
				total += e.amount
	return total


static func _cell_of(unit, board) -> Vector2i:
	if board != null and board.has_method("cell_of"):
		return board.cell_of(unit)
	var svc = _services()
	if svc != null and svc.board() != null and svc.board().has_method("cell_of"):
		return svc.board().cell_of(unit)
	return Vector2i(-9999, -9999)  # off-board sentinel => no tile => no bonus


static func _effects_at(cell: Vector2i, board) -> Array:
	if board != null and board.has_method("tile_effects_at"):
		var arr = board.tile_effects_at(cell)
		if arr is Array and not arr.is_empty():
			return arr
	var svc = _services()
	if svc != null and svc.has_method("tile_effects_at"):
		return svc.tile_effects_at(cell)
	return []


## Resolve the CombatServices autoload without a hard compile-time dependency, so
## isolated unit tests that run without it (or with a mock board) don't crash.
static func _services():
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("CombatServices")
	return null
