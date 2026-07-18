extends RefCounted
class_name MovementResolver

## Computes the set of cells a unit can reach given a [MovementProfile].
##
## Stepping shapes ([constant MovementProfile.Shape.ORTHOGONAL] /
## [constant MovementProfile.Shape.DIAGONAL] / [constant MovementProfile.Shape.ALL8])
## use a uniform-cost (Dijkstra) flood by accumulated move cost.
## [constant MovementProfile.Shape.KNIGHT] does a breadth-first search over fixed
## L-jumps (range = number of jumps, intervening cells ignored).
## [constant MovementProfile.Shape.TELEPORT] takes every cell within the direct
## (Manhattan) range regardless of obstacles.
##
## [b]Board interface (all duck-typed; missing methods degrade gracefully):[/b]
## [codeblock]
## board.in_bounds(cell: Vector2i) -> bool       # default: true
## board.move_cost(cell: Vector2i) -> int        # default: 1 (clamped >= 1)
## board.is_blocked(cell: Vector2i) -> bool       # walls / impassable; default: false
## board.is_occupied(cell: Vector2i) -> bool      # a unit stands here; default: false
## board.tile_id_at(cell: Vector2i) -> StringName # for terrain_cost_overrides; optional
## board.tile_tag_at(cell: Vector2i) -> StringName# for terrain_cost_overrides; optional
## [/codeblock]
##
## [b]Per-kind rules[/b] ([enum CombatTypes.MovementKind]):
## [ul]
## GROUND  — cannot path through or end on blocked (walls) or occupied cells.
## FLYING  — ignores walls (`is_blocked`) entirely; blocked by units in its path
##           and may not end on an occupied cell.
## PHASING — ignores walls and units while pathing; may not end on an occupied cell.
## [/ul]
## TELEPORT reachability ignores everything for pathing but still may not land on
## an occupied cell (respecting the profile's kind for the destination).

const ORTHOGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const DIAGONAL_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const ALL8_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const KNIGHT_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(2, 1), Vector2i(2, -1), Vector2i(1, -2),
	Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(-2, 1), Vector2i(-1, 2),
]


## Returns the sorted, de-duplicated set of cells reachable from [param origin]
## within the profile's budget. The origin itself is never included.
func reachable_cells(origin: Vector2i, profile: MovementProfile, board) -> Array[Vector2i]:
	var raw: Array = []
	match profile.shape:
		MovementProfile.Shape.ORTHOGONAL:
			raw = _flood(origin, profile, board, ORTHOGONAL_OFFSETS)
		MovementProfile.Shape.DIAGONAL:
			raw = _flood(origin, profile, board, DIAGONAL_OFFSETS)
		MovementProfile.Shape.ALL8:
			raw = _flood(origin, profile, board, ALL8_OFFSETS)
		MovementProfile.Shape.KNIGHT:
			raw = _knight(origin, profile, board)
		MovementProfile.Shape.TELEPORT:
			raw = _teleport(origin, profile, board)

	var seen := {}
	var out: Array[Vector2i] = []
	for c in raw:
		var cell: Vector2i = c
		if cell == origin or seen.has(cell):
			continue
		seen[cell] = true
		out.append(cell)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.y < b.y)
	return out


## True if [param target] can be reached from [param origin] under [param profile].
## The origin is trivially reachable (distance 0).
func can_reach(origin: Vector2i, target: Vector2i, profile: MovementProfile, board) -> bool:
	if target == origin:
		return true
	return reachable_cells(origin, profile, board).has(target)


# --- Shape strategies ------------------------------------------------------

## Uniform-cost flood for stepping shapes. Expands only through traversable
## cells, accumulates entry cost, and keeps cells whose total cost is within
## range and on which the kind is allowed to stop.
func _flood(origin: Vector2i, profile: MovementProfile, board, offsets: Array[Vector2i]) -> Array:
	var best := { origin: 0 }
	var open: Array[Vector2i] = [origin]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if best[open[i]] < best[open[bi]]:
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		var cur_cost: int = best[cur]
		for off in offsets:
			var n: Vector2i = cur + off
			if not _in_bounds(board, n):
				continue
			if not _can_traverse(n, profile.kind, board):
				continue
			var nc: int = cur_cost + _enter_cost(n, profile, board)
			if nc > profile.range:
				continue
			if best.has(n) and best[n] <= nc:
				continue
			best[n] = nc
			if not open.has(n):
				open.append(n)

	var out: Array = []
	for c in best.keys():
		if c == origin:
			continue
		if _can_stop(c, profile.kind, board):
			out.append(c)
	return out


## Breadth-first search over L-jumps. Each jump ignores intervening cells but
## must land on a cell the kind may stop on; range caps the number of jumps.
func _knight(origin: Vector2i, profile: MovementProfile, board) -> Array:
	var out: Array = []
	var visited := { origin: true }
	var frontier: Array[Vector2i] = [origin]
	var jumps: int = maxi(0, profile.range)
	for _step in range(jumps):
		var nxt: Array[Vector2i] = []
		for cell in frontier:
			for off in KNIGHT_OFFSETS:
				var n: Vector2i = cell + off
				if visited.has(n):
					continue
				if not _in_bounds(board, n):
					continue
				if not _can_stop(n, profile.kind, board):
					continue
				visited[n] = true
				out.append(n)
				nxt.append(n)
		frontier = nxt
	return out


## Every cell within direct (Manhattan) range, obstacles ignored for pathing.
func _teleport(origin: Vector2i, profile: MovementProfile, board) -> Array:
	var out: Array = []
	var r: int = maxi(0, profile.range)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > r:
				continue
			var n := Vector2i(origin.x + dx, origin.y + dy)
			if not _in_bounds(board, n):
				continue
			if not _can_stop(n, profile.kind, board):
				continue
			out.append(n)
	return out


# --- Traversal / stopping rules -------------------------------------------

## Whether the pathfinder may move [i]through[/i] (or into) a cell for a kind.
static func _can_traverse(cell: Vector2i, kind: CombatTypes.MovementKind, board) -> bool:
	match kind:
		CombatTypes.MovementKind.GROUND:
			return not _is_blocked(board, cell) and not _is_occupied(board, cell)
		CombatTypes.MovementKind.FLYING:
			return not _is_occupied(board, cell)
		CombatTypes.MovementKind.PHASING:
			return true
	return true


## Whether a unit of the given kind may end its movement on a cell. No kind may
## stop on an occupied cell.
static func _can_stop(cell: Vector2i, kind: CombatTypes.MovementKind, board) -> bool:
	match kind:
		CombatTypes.MovementKind.GROUND:
			return not _is_blocked(board, cell) and not _is_occupied(board, cell)
		_:
			return not _is_occupied(board, cell)


# --- Duck-typed board accessors -------------------------------------------

static func _in_bounds(board, cell: Vector2i) -> bool:
	if board != null and board.has_method("in_bounds"):
		return bool(board.in_bounds(cell))
	return true


static func _is_blocked(board, cell: Vector2i) -> bool:
	if board != null and board.has_method("is_blocked"):
		return bool(board.is_blocked(cell))
	return false


static func _is_occupied(board, cell: Vector2i) -> bool:
	if board != null and board.has_method("is_occupied"):
		return bool(board.is_occupied(cell))
	return false


## Cost to enter [param cell]: a matching terrain override (by tile id then tag)
## wins; otherwise the board's move_cost (clamped to at least 1); default 1.
static func _enter_cost(cell: Vector2i, profile: MovementProfile, board) -> int:
	var overrides: Dictionary = profile.terrain_cost_overrides
	if overrides != null and not overrides.is_empty() and board != null:
		if board.has_method("tile_id_at"):
			var tid = board.tile_id_at(cell)
			if tid != null and overrides.has(tid):
				return maxi(0, int(overrides[tid]))
		if board.has_method("tile_tag_at"):
			var tag = board.tile_tag_at(cell)
			if tag != null and overrides.has(tag):
				return maxi(0, int(overrides[tag]))
	if board != null and board.has_method("move_cost"):
		return maxi(1, int(board.move_cost(cell)))
	return 1
