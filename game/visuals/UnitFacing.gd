extends RefCounted
class_name UnitFacing

## Unit ORIENTATION math (Fire Emblem-style map facing). All static and pure, so the
## rules are unit-testable headlessly (tests/unit/test_unit_facing.gd). The live
## wiring is [FacingController] (rest facing / attack facing off GameEvents) and
## [UnitAnimator] (per-step facing while walking); [method Unit.set_facing] applies a
## direction to the visible model. See CONQUEST.md "Unit facing".
##
## A FACING is a [code]Vector2i(dcol, drow)[/code] with components in -1..1:
## [code](0, 1)[/code] = +row = "south" (toward the camera), [code](1, 0)[/code] = +col
## = east (screen right), [code](0, -1)[/code] north, [code](-1, 0)[/code] west.
## [code]Vector2i.ZERO[/code] means "no opinion -- keep the current facing".
##
## PURELY VISUAL: nothing in combat / AI / net reads facing today (and the net state
## digest never includes it). A future facing rule (flanking, back attacks) should
## read [method Unit.get_facing].
##
## MODEL CONVENTION: after its CharacterResource.model_yaw_deg, a character model
## faces +Z (south, toward the default camera) -- the pose every unit had before
## facing existed. Facing [param dir] then adds [method yaw_for] (dir) on top.

## Restrict every facing to the 4 grid directions (the clean FE / grid look). Set to
## true to allow 8-way (diagonal) facings everywhere.
const ALLOW_DIAGONAL := false

## Facing of a unit nobody has oriented yet (toward the camera).
const DEFAULT_FACING := Vector2i(0, 1)

## Seconds for a turn (before battle-speed / fast-forward scaling).
const TURN_TIME := 0.1

const _EPS := 0.001


## The 4-way (or 8-way with [param diagonal]) facing closest to [param delta]
## (x = +col, y = +row). ZERO when the delta is (near) zero. On an exact diagonal
## tie in 4-way mode the first of [param prefer] that is one of the two candidate
## directions wins, else the row axis (north/south) -- it reads best from the
## camera, which looks along the rows.
static func cardinal(delta: Vector2, prefer: Array = [], diagonal: bool = ALLOW_DIAGONAL) -> Vector2i:
	var ax := absf(delta.x)
	var ay := absf(delta.y)
	if ax < _EPS and ay < _EPS:
		return Vector2i.ZERO
	var sx := 1 if delta.x > 0.0 else -1
	var sy := 1 if delta.y > 0.0 else -1
	if diagonal:
		# Nearest octant: within 22.5 deg of an axis snaps to it, else diagonal.
		var t := tan(deg_to_rad(22.5))
		if ay <= ax * t:
			return Vector2i(sx, 0)
		if ax <= ay * t:
			return Vector2i(0, sy)
		return Vector2i(sx, sy)
	if ax > ay + _EPS:
		return Vector2i(sx, 0)
	if ay > ax + _EPS:
		return Vector2i(0, sy)
	var a := Vector2i(sx, 0)
	var b := Vector2i(0, sy)
	for p in prefer:
		if p is Vector2i and (p == a or p == b):
			return p
	return b


## Center of a unit's footprint in CELL units: x = col, y = row, z = floor. A 2x2
## anchored at (3,4) is centred at (3.5, 4.5).
static func center_of(anchor: Vector3i, footprint: Vector2i = Vector2i.ONE) -> Vector3:
	var fp := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	return Vector3(anchor.x + (fp.x - 1) * 0.5, anchor.y + (fp.y - 1) * 0.5, anchor.z)


## Center of a cell (a 1x1 footprint).
static func cell_center(cell: Vector3i) -> Vector3:
	return Vector3(cell.x, cell.y, cell.z)


## [param unit]'s footprint center on [param board] (duck-typed: cell_of +
## optional get_footprint).
static func unit_center(unit, board) -> Vector3:
	var fp := Vector2i.ONE
	if unit != null and unit.has_method("get_footprint"):
		var f = unit.get_footprint()
		if f is Vector2i:
			fp = f
	return center_of(board.cell_of(unit), fp)


## Facing from [param from_center] toward [param to_center] (vertical ignored). A
## target directly above / below (same column) gives ZERO: keep the current facing.
static func toward(from_center: Vector3, to_center: Vector3, prefer: Array = []) -> Vector2i:
	return cardinal(Vector2(to_center.x - from_center.x, to_center.y - from_center.y), prefer)


## Cell-distance between two centers: manhattan + |floor difference| (Cells.distance
## generalised to footprint centers).
static func distance(a: Vector3, b: Vector3) -> float:
	return absf(a.x - b.x) + absf(a.y - b.y) + absf(a.z - b.z)


## REST facing: toward the NEAREST enemy ([method distance] between footprint
## centers). Several equally-near enemies face their combined direction; an exact
## diagonal tie breaks toward the enemies' side (their centroid), then the
## [param current] facing (no churn), then the row axis. No enemies -> [param
## fallback] (the team's forward); nothing usable -> [param current].
static func rest_facing(me: Vector3, enemies: Array, current: Vector2i = DEFAULT_FACING, fallback: Vector2i = Vector2i.ZERO) -> Vector2i:
	if enemies.is_empty():
		return fallback if fallback != Vector2i.ZERO else current
	var best := INF
	for e in enemies:
		best = minf(best, distance(me, e))
	var near_sum := Vector2.ZERO
	var all_sum := Vector2.ZERO
	for e in enemies:
		var d := Vector2(e.x - me.x, e.y - me.y)
		all_sum += d
		if distance(me, e) <= best + _EPS:
			near_sum += d
	var side := cardinal(all_sum, [current])
	var dir := cardinal(near_sum, [side, current])
	if dir == Vector2i.ZERO:
		dir = side
	return dir if dir != Vector2i.ZERO else current


## A team's default FORWARD when it has no enemy to look at: from the team's
## centroid toward the board center (cell units, x = col, y = row). ZERO when the
## team already sits on the center.
static func team_forward(team_centroid: Vector2, board_center: Vector2) -> Vector2i:
	return cardinal(board_center - team_centroid)


## Yaw (radians, around +Y) that turns a +Z-facing model to [param dir].
static func yaw_for(dir: Vector2i) -> float:
	if dir == Vector2i.ZERO:
		return 0.0
	return atan2(float(dir.x), float(dir.y))


## Full model yaw: the character's authored correction plus the facing.
static func model_yaw(model_yaw_deg: float, dir: Vector2i) -> float:
	return deg_to_rad(model_yaw_deg) + yaw_for(dir)


## Clamp any Vector2i to a facing (components -1..1; 4-way unless ALLOW_DIAGONAL).
static func normalized(dir: Vector2i) -> Vector2i:
	return cardinal(Vector2(dir), [], ALLOW_DIAGONAL)
