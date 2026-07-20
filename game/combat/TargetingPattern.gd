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
