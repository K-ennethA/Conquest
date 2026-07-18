extends Node
class_name TileEffectSystem

## Resolves [TileEffectResource]s for units on the tactical board.
##
## The system does not own the map. It looks up the effects on a cell through a
## duck-typed board method [code]tile_effects_at(cell) -> Array[/code], falling
## back to an injected [member tile_effects] dictionary (cell -> Array). This
## keeps it testable against a mock board and lets the live board/map supply the
## real authoring source later.
##
## A turn/movement system raises the events by calling [method on_enter],
## [method on_exit] and [method on_turn_start]; the targeting system asks
## [method passive_flags] whether an occupant is currently untargetable,
## fortified, and so on. Every method resolves effects in deterministic order
## (the cell's array order, then each effect's own order).

## Optional injected lookup: cell ([Vector2i]) -> [code]Array[TileEffectResource][/code].
## Used only when the board does not supply effects for that cell.
var tile_effects: Dictionary = {}


## Run every [enum TileEffectResource.Trigger].ON_ENTER effect on [param cell]
## that applies to [param unit]. Returns the merged event log.
func on_enter(unit, cell: Vector2i, board) -> Array:
	return _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_ENTER)


## Run every ON_EXIT effect on the cell the unit is leaving.
func on_exit(unit, cell: Vector2i, board) -> Array:
	return _run_trigger(unit, cell, board, TileEffectResource.Trigger.ON_EXIT)


## Run every ON_TURN_START_WHILE_OCCUPYING effect on the unit's current cell.
func on_turn_start(unit, board) -> Array:
	return _run_trigger(unit, _cell_of(unit, board), board, TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING)


## Merge the [member TileEffectResource.rule_flags] of every
## PASSIVE_WHILE_OCCUPYING effect currently affecting [param unit] on its cell.
## Later effects override earlier ones on key collisions. This is what lets the
## targeting system ask "is this unit untargetable?" without mutating anything.
func passive_flags(unit, board) -> Dictionary:
	var flags: Dictionary = {}
	if unit == null:
		return flags
	var cell := _cell_of(unit, board)
	for te in _effects_at(cell, board):
		if te == null or te.trigger != TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING:
			continue
		if not te.applies_to(unit, board):
			continue
		for key in te.rule_flags:
			flags[key] = te.rule_flags[key]
	return flags


func _run_trigger(unit, cell: Vector2i, board, trigger: int) -> Array:
	var events: Array = []
	if unit == null:
		return events
	for te in _effects_at(cell, board):
		if te == null or te.trigger != trigger:
			continue
		if not te.applies_to(unit, board):
			continue
		for e in te.run(unit, board):
			events.append(e)
	return events


## Prefer the board's own authoring source; fall back to the injected dictionary.
func _effects_at(cell: Vector2i, board) -> Array:
	if board and board.has_method("tile_effects_at"):
		var arr = board.tile_effects_at(cell)
		if arr is Array and not arr.is_empty():
			return arr
	if tile_effects.has(cell):
		var injected = tile_effects[cell]
		if injected is Array:
			return injected
	return []


static func _cell_of(unit, board) -> Vector2i:
	if board and board.has_method("cell_of"):
		return board.cell_of(unit)
	return Vector2i.ZERO
