extends MoveEffect
class_name KnockbackEffect

## Pushes valid targets away from the caster by up to [member distance] cells.
## Useful for control moves (shove an enemy off the throne, into a hazard, etc.).

@export var distance: int = 1


func apply(ctx: MoveContext) -> void:
	if not ctx.board.has_method("cell_of") or not ctx.board.has_method("move_unit"):
		return
	var origin: Vector3i = ctx.board.cell_of(ctx.caster)
	for target in ctx.gather_targets():
		var from: Vector3i = ctx.board.cell_of(target)
		var dir := _push_dir(origin, from)
		var dest := _clamped_dest(ctx.board, target, from, dir)
		if dest == from:
			# Blocked / edge / AIR right behind the target -- nowhere to shove it; it
			# braces where it stands (logged so the combat log can say so).
			ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": from })
			continue
		ctx.board.move_unit(target, dest)
		ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": dest })


## Walk up to [member distance] cells along [param dir], returning the last cell the
## unit can actually stand on. [BoardAdapter.move_unit] snaps unconditionally, so all
## bounds/wall/occupancy validation must happen HERE -- otherwise a knock near an edge or
## wall shoves the unit off-grid or onto another unit (stacking two on one cell). Stops at
## the first cell the unit can't fit, so a knock never passes THROUGH a wall either.
## Multi-floor: never shoves a unit into the AIR (off a bridge edge / into a broken
## bridge's gap) -- it braces at the edge instead. The push stays on the unit's floor.
func _clamped_dest(board, unit, from: Vector3i, dir: Vector3i) -> Vector3i:
	var last_ok := from
	for step in range(1, distance + 1):
		var c := from + dir * step
		if board.has_method("has_tile") and not bool(board.has_tile(c)):
			break
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


## Horizontal push direction (the floor never changes; a target directly above or
## below the caster is pushed +X).
static func _push_dir(origin: Vector3i, target_cell: Vector3i) -> Vector3i:
	var delta := Vector3i(target_cell.x - origin.x, target_cell.y - origin.y, 0)
	if delta == Vector3i.ZERO:
		return Vector3i(1, 0, 0)
	if absi(delta.x) >= absi(delta.y):
		return Vector3i(signi(delta.x), 0, 0)
	return Vector3i(0, signi(delta.y), 0)
