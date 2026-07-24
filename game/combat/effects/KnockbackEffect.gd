extends MoveEffect
class_name KnockbackEffect

## Pushes valid targets away from the caster by up to [member distance] cells.
## Useful for control moves (shove an enemy off the throne, into a hazard, etc.).

@export var distance: int = 1


func apply(ctx: MoveContext) -> void:
	if not ctx.board.has_method("cell_of") or not ctx.board.has_method("move_unit"):
		return
	var origin: Vector2i = ctx.board.cell_of(ctx.caster)
	for target in ctx.gather_targets():
		var from: Vector2i = ctx.board.cell_of(target)
		var dir := _push_dir(origin, from)
		var dest := _clamped_dest(ctx.board, target, from, dir)
		if dest == from:
			continue  # blocked/edge right behind the target -- nowhere to shove it
		ctx.board.move_unit(target, dest)
		ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": dest })


## Walk up to [member distance] cells along [param dir], returning the last cell the
## unit can actually stand on. [BoardAdapter.move_unit] snaps unconditionally, so all
## bounds/wall/occupancy validation must happen HERE -- otherwise a knock near an edge or
## wall shoves the unit off-grid or onto another unit (stacking two on one cell). Stops at
## the first cell the unit can't fit, so a knock never passes THROUGH a wall either.
func _clamped_dest(board, unit, from: Vector2i, dir: Vector2i) -> Vector2i:
	var last_ok := from
	for step in range(1, distance + 1):
		var c := from + dir * step
		if board.has_method("can_fit"):
			if not board.can_fit(unit, c):
				break
		else:
			if board.has_method("in_bounds") and not board.in_bounds(c):
				break
			if board.has_method("is_blocked") and board.is_blocked(c):
				break
			if board.has_method("is_occupied") and board.is_occupied(c):
				break
		last_ok = c
	return last_ok


func describe() -> String:
	if description_override != "":
		return description_override
	return "Knock target back %d" % distance


static func _push_dir(origin: Vector2i, target_cell: Vector2i) -> Vector2i:
	var delta := target_cell - origin
	if delta == Vector2i.ZERO:
		return Vector2i(1, 0)
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))
