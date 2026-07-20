extends Resource
class_name TargetingPattern

## Describes how a move selects the cells it affects. Pure data + pure math, so
## it's fully unit-testable and reusable across many moves.
##
## A move is aimed at a single [param aim] cell (chosen within range of the
## caster); the [member area_shape] then expands that into the full set of
## affected cells.

@export var target_kind: CombatTypes.TargetKind = CombatTypes.TargetKind.ENEMY

## How far (Manhattan distance) the aim cell may be from the caster.
@export var min_range: int = 1
@export var max_range: int = 1

@export var area_shape: CombatTypes.AreaShape = CombatTypes.AreaShape.SINGLE
## Radius (SQUARE/DIAMOND/CROSS) or length (LINE). Ignored for SINGLE.
@export var area_size: int = 0

## If true, self-targeting / area moves may also include the caster's own cell.
@export var affects_caster_tile: bool = false

## --- Board-aware aim constraints --------------------------------------------
##
## [member min_range] / [member max_range] are pure geometry and need no world to
## answer. These two need the BOARD, so they are checked separately in
## [method is_aim_allowed] (which [MoveExecutor] and the targeting UI validate
## with) rather than in [method in_range]. Both default to false, so a pattern
## authored before they existed resolves through range alone exactly as it always
## has -- they only ever NARROW what may be aimed at, never widen it.

## The aim cell must be somewhere the CASTER could actually stand: in bounds,
## passable, and free of other living units. Independent of [member target_kind]
## on purpose -- a move can require an empty LANDING cell while its target kind
## still says which units the effects then hit.
@export var requires_empty_cell: bool = false

## The aim cell must be orthogonally adjacent to at least one enemy of the caster.
##
## Together with [member requires_empty_cell] this expresses "a free tile beside
## an enemy", which is how a dash/leap gets its landing choice for free: the
## player aims at the DESTINATION, so the ordinary targeting UI *is* the choice of
## which side to land on, and "there is no room beside the target" needs no
## special case at all -- no cell passes, so nothing can be aimed at and the move
## simply cannot be used. Adjacency is measured from the aim cell to each enemy's
## anchor cell.
@export var requires_adjacent_enemy: bool = false

## The four orthogonal neighbours -- the sides a leap may land on. Diagonals are
## excluded to match the game's orthogonal movement.
const ORTHOGONAL_STEPS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


## This pattern's reach once a caster's per-unit range bonus is folded in.
##
## [member max_range] is authored per MOVE and the resource is SHARED by every
## unit that knows the move, so a per-unit bonus must never be written back into
## it — it is added here, at resolution time, instead. Negative bonuses are
## clamped away so a debuff can never shrink a move below its authored reach
## (that would need its own, separately-tuned rule).
func effective_max_range(range_bonus: int = 0) -> int:
	return max_range + maxi(0, range_bonus)


## True if [param aim] is a legal aim point for a caster standing on [param origin].
## [param range_bonus] is the caster's extra reach (0 = the authored pattern,
## byte-identical to the behaviour before per-unit range bonuses existed).
## [member min_range] is deliberately NOT shifted: a bonus extends how FAR a move
## reaches, it does not open up the dead zone a long-range move has up close.
func in_range(origin: Vector2i, aim: Vector2i, range_bonus: int = 0) -> bool:
	var d := _manhattan(origin, aim)
	return d >= min_range and d <= effective_max_range(range_bonus)


## The FULL legality test for aiming at [param aim]: [method in_range] plus every
## board-aware constraint this pattern declares (see [member requires_empty_cell] /
## [member requires_adjacent_enemy]).
##
## [param board] is optional and may be null (previews, mock harnesses, anything
## with no world to ask); a null board falls back to the range answer alone, which
## is what every caller got before these constraints existed. A pattern that
## declares neither constraint resolves identically to [method in_range] whatever
## the board says, so this is safe to call everywhere in place of it.
func is_aim_allowed(origin: Vector2i, aim: Vector2i, caster = null, board = null, range_bonus: int = 0) -> bool:
	if not in_range(origin, aim, range_bonus):
		return false
	if board == null:
		return true
	if requires_empty_cell and not _is_free_cell(aim, caster, board):
		return false
	if requires_adjacent_enemy and not _has_adjacent_enemy(aim, caster, board):
		return false
	return true


## Could [param caster] stand at [param cell]?
##
## Asks the board's [code]can_fit[/code] when it has one, because that is the
## primitive that already knows about bounds, blocking terrain, other living units
## AND multi-cell footprints -- a 2x2 unit must not leap into a 1-cell gap.
## Boards without it (lightweight mocks) fall back to whichever of the individual
## queries they do expose, defaulting to "free" for the ones they don't.
func _is_free_cell(cell: Vector2i, caster, board) -> bool:
	if board.has_method("can_fit"):
		return bool(board.can_fit(caster, cell))
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if board.has_method("is_blocked") and bool(board.is_blocked(cell)):
		return false
	if board.has_method("is_occupied"):
		return not bool(board.is_occupied(cell))
	if board.has_method("units_at"):
		return board.units_at(cell).is_empty()
	return true


## True when any of [param cell]'s four orthogonal neighbours holds a unit the
## board calls an enemy of [param caster]. False without a caster or without the
## allegiance query, so this can never invent hostility a board cannot confirm.
func _has_adjacent_enemy(cell: Vector2i, caster, board) -> bool:
	if caster == null or not board.has_method("units_at") or not board.has_method("are_enemies"):
		return false
	for step in ORTHOGONAL_STEPS:
		for unit in board.units_at(cell + step):
			if unit != null and unit != caster and board.are_enemies(caster, unit):
				return true
	return false


## Expand the aim point into every cell the move touches.
func resolve_cells(origin: Vector2i, aim: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	match area_shape:
		CombatTypes.AreaShape.SINGLE:
			cells.append(aim)
		CombatTypes.AreaShape.SQUARE:
			for dx in range(-area_size, area_size + 1):
				for dy in range(-area_size, area_size + 1):
					cells.append(aim + Vector2i(dx, dy))
		CombatTypes.AreaShape.DIAMOND:
			for dx in range(-area_size, area_size + 1):
				for dy in range(-area_size, area_size + 1):
					if absi(dx) + absi(dy) <= area_size:
						cells.append(aim + Vector2i(dx, dy))
		CombatTypes.AreaShape.CROSS:
			cells.append(aim)
			for step in range(1, area_size + 1):
				cells.append(aim + Vector2i(step, 0))
				cells.append(aim + Vector2i(-step, 0))
				cells.append(aim + Vector2i(0, step))
				cells.append(aim + Vector2i(0, -step))
		CombatTypes.AreaShape.LINE:
			var dir := _cardinal_dir(origin, aim)
			for step in range(0, maxi(area_size, 1)):
				cells.append(aim + dir * step)
		CombatTypes.AreaShape.ARC:
			# A 3-cell sweep across the face of the caster it is aimed at: the aimed
			# cell plus its two neighbours PERPENDICULAR to the caster->aim heading.
			# Aim north and it covers the three cells along the north face; aim east
			# and it covers the three down the east face.
			#
			# WHY AIM-DERIVED: units in this game have no facing, so there is nothing
			# else to ask which way "in front" points. Deriving it from the aim gives
			# a directional attack with no facing system to build, own, sync over the
			# network, or explain -- and the player already chooses the aim, so the
			# ordinary targeting UI IS the choice of which face to sweep.
			#
			# DIAGONAL AIMS: _cardinal_dir collapses the heading to its DOMINANT axis
			# (ties favour X), exactly as LINE already does, so a diagonal aim sweeps
			# the nearer clean face rather than producing a staircase of cells. Sharing
			# LINE's rule matters more than any bespoke diagonal handling: two
			# direction-derived shapes that disagreed about what a diagonal means would
			# be indefensible to a player and a standing bug source. Note this is the
			# heading only -- the arc is still centred on the cell actually aimed at.
			var facing := _cardinal_dir(origin, aim)
			var flank := Vector2i(-facing.y, facing.x)  # 90-degree rotation
			cells.append(aim)
			cells.append(aim + flank)
			cells.append(aim - flank)
	if not affects_caster_tile:
		cells.erase(origin)
	return cells


func describe_range() -> String:
	if min_range == max_range:
		return "range %d" % max_range
	return "range %d-%d" % [min_range, max_range]


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Nearest cardinal direction from [param origin] toward [param aim]
## (dominant axis wins; defaults to +X if origin == aim).
static func _cardinal_dir(origin: Vector2i, aim: Vector2i) -> Vector2i:
	var delta := aim - origin
	if delta == Vector2i.ZERO:
		return Vector2i(1, 0)
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(signi(delta.x), 0)
	return Vector2i(0, signi(delta.y))
