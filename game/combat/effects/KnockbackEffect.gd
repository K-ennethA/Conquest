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
		var dest := from + dir * distance
		# Multi-floor: never shove a unit into the AIR (off a bridge edge / into a
		# broken bridge's gap) -- it braces at the edge instead.
		if ctx.board.has_method("has_tile") and not bool(ctx.board.has_tile(dest)):
			ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": from })
			continue
		ctx.board.move_unit(target, dest)
		ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": dest })


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
