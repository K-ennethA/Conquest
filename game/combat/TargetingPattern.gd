extends Resource
class_name TargetingPattern

## Describes how a move selects the cells it affects. Pure data + pure math, so
## it's fully unit-testable and reusable across many moves.
##
## A move is aimed at a single [param aim] cell (chosen within range of the
## caster); the [member area_shape] then expands that into the full set of
## affected cells.

@export var target_kind: CombatTypes.TargetKind = CombatTypes.TargetKind.ENEMY

## How far the aim cell may be from the caster, measured by [method Cells.distance]
## (horizontal Manhattan distance + floor difference; plain Manhattan on one floor).
## A pattern with max_range <= 1 is MELEE (see [method is_melee]).
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

## OPTIONAL PER-MOVE AIM RULE -- a resource exposing
## [code]allows_aim(origin, aim, caster, board) -> bool[/code], consulted LAST in
## [method is_aim_allowed]. Like the two flags above it can only ever NARROW what may be
## aimed at, never widen it: the range test has already run by the time it is asked.
##
## This is the escape hatch for a move whose legality is not expressible as a flag -- one
## whose valid cells depend on RUNTIME BOARD STATE rather than on geometry. Duskmaw's
## Voidstep is the case it exists for: within 4 it may plant an anchor on free ground,
## and at any distance up to its reach it may step to an anchor IT ALREADY PLANTED, so
## "which cells are legal" is a question only the move's own effect can answer.
##
## AUTHORED AS THE MOVE'S OWN EFFECT, normally. Pointing this at the same sub-resource the
## move already lists under [member MoveResource.effects] is what keeps the rule and the
## resolution the same object: the highlight, [MoveExecutor]'s validation and the effect
## itself then read ONE function, and they cannot drift.
##
## Typed as plain [Resource] and read duck-typed, exactly as [member MoveResource.fx] is:
## a `.tres` referencing a brand-new global class only resolves once the engine has
## rescanned. Left null (the default, and every pattern authored before this existed) it
## contributes nothing.
@export var aim_rule: Resource = null

## --- Multi-floor (see docs/MULTI_FLOOR.md) --------------------------------------

## When line of sight ([LineOfSight]) is checked for this pattern's aim.
enum LosMode {
	AUTO,    ## Only for CROSS-FLOOR aims (ceilings + walls). Same-floor aims ignore
	         ## LOS entirely -- exactly the pre-multi-floor behaviour. The default.
	ALWAYS,  ## Every aim, same floor too (walls / trees block shots).
	NEVER,   ## Never (lobbed / magical moves that ignore cover).
}
@export var line_of_sight: LosMode = LosMode.AUTO

## The four orthogonal neighbours -- the sides a leap may land on. Diagonals are
## excluded to match the game's orthogonal movement.
const ORTHOGONAL_STEPS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
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
##
## MULTI-FLOOR: distance is [method Cells.distance]; a RANGED pattern aimed downward
## gains [constant Elevation.HIGH_GROUND_RANGE_BONUS]; a MELEE pattern never reaches
## another floor here (only across a link, which needs the board -- see [method in_reach]).
func in_range(origin: Vector3i, aim: Vector3i, range_bonus: int = 0) -> bool:
	if is_melee() and origin.z != aim.z:
		return false
	var d := Cells.distance(origin, aim)
	var reach := effective_max_range(range_bonus) + Elevation.range_bonus(origin, aim, max_range)
	return d >= min_range and d <= reach


## True for a MELEE pattern (authored max_range <= 1). Melee only hits its own floor,
## or the far end of a link (top/bottom of a stair) -- never a unit directly above.
func is_melee() -> bool:
	return max_range <= 1


## [method in_range], plus the one board-dependent reach rule: a MELEE pattern may
## aim at a cell on another floor when the board links it directly to [param origin]
## (the unit at the other end of a stair). [param board] may be null.
func in_reach(origin: Vector3i, aim: Vector3i, board = null, range_bonus: int = 0) -> bool:
	if reach_is_unbounded(board) or in_range(origin, aim, range_bonus):
		return true
	return _melee_link_ok(origin, aim, board)


## A board may declare that DISTANCE IS ABSTRACT (the duel's two-station board): every aim
## is then in reach and only the range test is skipped -- the narrowing constraints
## (requires_*, aim_rule, line of sight) still apply in [method is_aim_allowed]. The
## authored [member min_range] / [member max_range] are never rewritten, so rules that read
## them (Weather.is_ranged, Elevation.range_bonus) keep their meaning. [BoardAdapter] never
## declares the method, so tactical play is byte-identical.
static func reach_is_unbounded(board) -> bool:
	return board != null and board.has_method("reach_is_unbounded") and bool(board.reach_is_unbounded())


func _melee_link_ok(origin: Vector3i, aim: Vector3i, board) -> bool:
	if not is_melee() or origin.z == aim.z or board == null or not board.has_method("are_linked"):
		return false
	return bool(board.are_linked(origin, aim))


## Whether an aim from [param origin] at [param aim] must pass a line-of-sight test.
func needs_line_of_sight(origin: Vector3i, aim: Vector3i) -> bool:
	if origin == aim:
		return false
	match line_of_sight:
		LosMode.NEVER:
			return false
		LosMode.ALWAYS:
			return true
	return origin.z != aim.z


## The FULL legality test for aiming at [param aim]: [method in_range] plus every
## board-aware constraint this pattern declares (see [member requires_empty_cell] /
## [member requires_adjacent_enemy]).
##
## [param board] is optional and may be null (previews, mock harnesses, anything
## with no world to ask); a null board falls back to the range answer alone, which
## is what every caller got before these constraints existed. A pattern that
## declares neither constraint resolves identically to [method in_range] whatever
## the board says, so this is safe to call everywhere in place of it.
##
## MULTI-FLOOR: also admits a melee aim across a link ([method in_reach]) and, with a
## board, requires [LineOfSight] per [member line_of_sight] (skipped for linked
## melee -- the stair itself is the path).
func is_aim_allowed(origin: Vector3i, aim: Vector3i, caster = null, board = null, range_bonus: int = 0) -> bool:
	var linked_melee := false
	if not reach_is_unbounded(board) and not in_range(origin, aim, range_bonus):
		if not _melee_link_ok(origin, aim, board):
			return false
		linked_melee = true
	if board == null:
		return true
	if not linked_melee and needs_line_of_sight(origin, aim):
		if not LineOfSight.has_line_of_sight(board, origin, aim, true):
			return false
	if requires_empty_cell and not _is_free_cell(aim, caster, board):
		return false
	if requires_adjacent_enemy and not _has_adjacent_enemy(aim, caster, board):
		return false
	# LAST, and narrowing only: everything above has already had its say, so a rule can
	# refuse a cell but never rescue one the pattern itself rejected.
	if aim_rule != null and aim_rule.has_method("allows_aim") \
			and not bool(aim_rule.allows_aim(origin, aim, caster, board)):
		return false
	return true


## Could [param caster] stand at [param cell]?
##
## Asks the board's [code]can_fit[/code] when it has one, because that is the
## primitive that already knows about bounds, blocking terrain, other living units
## AND multi-cell footprints -- a 2x2 unit must not leap into a 1-cell gap.
## Boards without it (lightweight mocks) fall back to whichever of the individual
## queries they do expose, defaulting to "free" for the ones they don't.
func _is_free_cell(cell: Vector3i, caster, board) -> bool:
	if board.has_method("can_fit"):
		return bool(board.can_fit(caster, cell))
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if board.has_method("is_blocked") and bool(board.is_blocked(cell)):
		return false
	if board.has_method("has_tile") and not bool(board.has_tile(cell)):
		return false
	if board.has_method("is_occupied"):
		return not bool(board.is_occupied(cell))
	if board.has_method("units_at"):
		return board.units_at(cell).is_empty()
	return true


## True when any of [param cell]'s four orthogonal neighbours holds a unit the
## board calls an enemy of [param caster]. False without a caster or without the
## allegiance query, so this can never invent hostility a board cannot confirm.
func _has_adjacent_enemy(cell: Vector3i, caster, board) -> bool:
	if caster == null or not board.has_method("units_at") or not board.has_method("are_enemies"):
		return false
	for step in ORTHOGONAL_STEPS:
		for unit in board.units_at(cell + step):
			if unit != null and unit != caster and board.are_enemies(caster, unit):
				return true
	return false


## Expand the aim point into every cell the move touches.
##
## MULTI-FLOOR: every shape is laid out on the AIM's floor only (offsets never change
## the floor), so a fireball on a bridge does not scorch the road below it.
func resolve_cells(origin: Vector3i, aim: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	match area_shape:
		CombatTypes.AreaShape.SINGLE:
			cells.append(aim)
		CombatTypes.AreaShape.SQUARE:
			for dx in range(-area_size, area_size + 1):
				for dy in range(-area_size, area_size + 1):
					cells.append(aim + Vector3i(dx, dy, 0))
		CombatTypes.AreaShape.DIAMOND:
			for dx in range(-area_size, area_size + 1):
				for dy in range(-area_size, area_size + 1):
					if absi(dx) + absi(dy) <= area_size:
						cells.append(aim + Vector3i(dx, dy, 0))
		CombatTypes.AreaShape.CROSS:
			cells.append(aim)
			for step in range(1, area_size + 1):
				cells.append(aim + Vector3i(step, 0, 0))
				cells.append(aim + Vector3i(-step, 0, 0))
				cells.append(aim + Vector3i(0, step, 0))
				cells.append(aim + Vector3i(0, -step, 0))
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
			var flank := Vector3i(-facing.y, facing.x, 0)  # 90-degree rotation
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


## Horizontal Manhattan distance (floors ignored). Range checks use
## [method Cells.distance] instead.
static func _manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Nearest cardinal direction (on the horizontal plane, z = 0) from [param origin]
## toward [param aim] (dominant axis wins; defaults to +X if the columns coincide).
static func _cardinal_dir(origin: Vector3i, aim: Vector3i) -> Vector3i:
	var dx := aim.x - origin.x
	var dy := aim.y - origin.y
	if dx == 0 and dy == 0:
		return Vector3i(1, 0, 0)
	if absi(dx) >= absi(dy):
		return Vector3i(signi(dx), 0, 0)
	return Vector3i(0, signi(dy), 0)
