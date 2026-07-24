extends MoveEffect
class_name LeapEffect

## Relocates the CASTER to the move's aimed cell.
##
## Every other movement effect in the pipeline moves a TARGET ([KnockbackEffect]
## pushes what you hit); this is the mirror — the caster closes the distance
## itself. Placed FIRST in a move's effect list, everything after it resolves with
## the caster already standing on the landing cell, which is what makes a
## "dash in, then strike" read correctly.
##
## WHERE the caster may land is deliberately not decided here. The move's own
## [TargetingPattern] restricts the aim (see
## [member TargetingPattern.requires_empty_cell] /
## [member TargetingPattern.requires_adjacent_enemy]), so the player picks the
## landing cell — and therefore which side of the target to land on — with the
## ordinary targeting UI, and no bespoke sub-selection step is needed. This effect
## only refuses a destination that is physically impossible, and does so silently:
## an invalid landing is a logged no-op, never an error, so a stale aim or a mock
## board can never break a move mid-resolution.

func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null or ctx.board == null:
		return
	if not ctx.board.has_method("cell_of") or not ctx.board.has_method("move_unit"):
		return

	var from: Vector2i = ctx.board.cell_of(ctx.caster)
	var to: Vector2i = ctx.aim_cell
	if not _can_land(ctx, to):
		ctx.log_event({
			"effect": "leap",
			"unit": ctx.caster,
			"from": from,
			"to": from,
			"moved": false,
		})
		return

	ctx.board.move_unit(ctx.caster, to)
	ctx.log_event({
		"effect": "leap",
		"unit": ctx.caster,
		"from": from,
		"to": to,
		"moved": true,
	})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Leap to the targeted cell"


## Can the caster physically occupy [param cell]?
##
## Prefers the board's [code]can_fit[/code], which answers bounds + blocking
## terrain + other living units + the caster's own FOOTPRINT in one call, so a
## multi-cell unit is never squeezed into a gap it does not fit. Boards without it
## fall back to the individual queries they do expose; anything a board cannot
## answer is treated as permissive, exactly as the rest of the pipeline does.
static func _can_land(ctx: MoveContext, cell: Vector2i) -> bool:
	var board = ctx.board
	if board.has_method("can_fit"):
		return bool(board.can_fit(ctx.caster, cell))
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if board.has_method("is_blocked") and bool(board.is_blocked(cell)):
		return false
	for unit in board.units_at(cell):
		if unit != null and unit != ctx.caster:
			return false
	return true
