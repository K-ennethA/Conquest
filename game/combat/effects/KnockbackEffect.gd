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
		var dest := from + dir * distance
		ctx.board.move_unit(target, dest)
		ctx.log_event({ "effect": "knockback", "target": target, "from": from, "to": dest })


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
