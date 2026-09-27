extends RefCounted
class_name MovementResolver

## Computes the set of cells a unit can reach given a [MovementProfile].
##
## Cells are [Vector3i](col, row, floor) -- see [Cells].
##
## Stepping shapes ([constant MovementProfile.Shape.ORTHOGONAL] /
## [constant MovementProfile.Shape.DIAGONAL] / [constant MovementProfile.Shape.ALL8])
## use a uniform-cost (Dijkstra) flood by accumulated move cost.
## [constant MovementProfile.Shape.KNIGHT] does a breadth-first search over fixed
## L-jumps (range = number of jumps, intervening cells ignored, same floor only).
## [constant MovementProfile.Shape.TELEPORT] takes every cell within the direct
## range ([method Cells.distance]: Manhattan + floor difference) regardless of obstacles.
##
## [b]Floors[/b] (see docs/MULTI_FLOOR.md). Stepping shapes move within the unit's
## floor, plus across [b]links[/b] (stairs/ladders) reported by the board. A step
## over a link costs the link's own cost instead of the destination's terrain cost.
## A cell with no tile (board [code]has_tile[/code] false -- e.g. the gap in a broken
## bridge) is AIR: GROUND and PHASING units can never enter it. FLYING units may fly
## THROUGH air on upper floors (but never stop in it) and may also change floor
## vertically at any column (cost = the destination's enter cost, 1 for air) -- so a
## flier crosses a broken bridge directly and hops onto a rampart without stairs.
##
## [b]Paths:[/b] every stepping/knight search records predecessors, so after
## [method reachable_cells] (or [method can_reach]) [method path_to] returns the
## exact route to any reached cell and [method cost_to] its accumulated cost.
##
## [b]Board interface (all duck-typed; missing methods degrade gracefully):[/b]
## [codeblock]
## board.in_bounds(cell: Vector3i) -> bool       # default: true
## board.move_cost(cell: Vector3i) -> int        # default: 1 (clamped >= 1)
## board.is_blocked(cell: Vector3i) -> bool       # walls / impassable; default: false
## board.is_occupied(cell: Vector3i) -> bool      # a unit stands here; default: false
## board.has_tile(cell: Vector3i) -> bool         # floor exists (not air); default: true
## board.links_from(cell: Vector3i) -> Array      # [{to, cost, kind}]; default: none
## board.floor_count() -> int                     # floors (fliers/teleport); default: 1
## board.tile_id_at(cell: Vector3i) -> StringName # for terrain_cost_overrides; optional
## board.tile_tag_at(cell: Vector3i) -> StringName# for terrain_cost_overrides; optional
## board.can_fit(unit, anchor: Vector3i) -> bool  # whole-footprint placement; optional
## board.units_at(cell: Vector3i) -> Array        # for self-excluding occupancy; optional
## [/codeblock]
##
## [b]Multi-cell units:[/b] pass the moving unit as the optional [code]unit[/code]
## argument and a unit spanning more than one cell (its ``get_footprint()``) may
## only enter or stop where its WHOLE span is legal. With no unit, a 1x1 unit, or a
## unit whose footprint is unknown, every footprint check short-circuits to the
## original single-cell rules -- so normal units are entirely unaffected.
##
## [b]Per-kind rules[/b] ([enum CombatTypes.MovementKind]):
## [ul]
## GROUND  — cannot path through or end on blocked (walls) or air cells, nor end on
##           an occupied cell. May path THROUGH a cell held only by ALLIES of the
##           mover (Fire Emblem style) but never through an enemy.
## FLYING  — ignores walls (`is_blocked`) entirely; may pass allies like GROUND but
##           is blocked by enemy units in its path and may not end on an occupied or
##           air cell.
## PHASING — ignores walls and units while pathing (never air); may not end on an
##           occupied cell.
## [/ul]
## TELEPORT reachability ignores everything for pathing but still may not land on
## an occupied cell (respecting the profile's kind for the destination).
##
## [b]Allies:[/b] "ally" is answered by the board's [code]are_allies(mover, other)[/code]
## (plus [code]units_at[/code]); with no mover, or a board lacking either query, every
## occupant blocks exactly as before. A pass-through cell is recorded in the search
## (so [method path_to] routes through it) but is never returned as a destination.

const ORTHOGONAL_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]
const DIAGONAL_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 1, 0), Vector3i(1, -1, 0), Vector3i(-1, 1, 0), Vector3i(-1, -1, 0),
]
const ALL8_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(1, 1, 0), Vector3i(1, -1, 0), Vector3i(-1, 1, 0), Vector3i(-1, -1, 0),
]
const KNIGHT_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 2, 0), Vector3i(2, 1, 0), Vector3i(2, -1, 0), Vector3i(1, -2, 0),
	Vector3i(-1, -2, 0), Vector3i(-2, -1, 0), Vector3i(-2, 1, 0), Vector3i(-1, 2, 0),
]
const VERTICAL_OFFSETS: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Cost reported by [method cost_to] / [method travel_distances] for "unreachable".
const UNREACHABLE: int = 1 << 30

## Search state of the most recent [method reachable_cells] call (for path_to).
var _last_origin: Vector3i = Cells.INVALID
var _last_cost: Dictionary = {}       ## cell -> accumulated cost (origin = 0)
var _last_came_from: Dictionary = {}  ## cell -> predecessor cell


## Returns the sorted, de-duplicated set of cells reachable from [param origin]
## within the profile's budget. The origin itself is never included. [param unit] is
## the moving unit, used only to honour a multi-cell footprint; omit it (or pass a
## 1x1 unit) for the original single-cell behaviour.
func reachable_cells(origin: Vector3i, profile: MovementProfile, board, unit = null) -> Array[Vector3i]:
	var raw: Array = []
	_last_origin = origin
	_last_cost = { origin: 0 }
	_last_came_from = {}
	match profile.shape:
		MovementProfile.Shape.ORTHOGONAL:
			raw = _flood(origin, profile, board, ORTHOGONAL_OFFSETS, unit)
		MovementProfile.Shape.DIAGONAL:
			raw = _flood(origin, profile, board, DIAGONAL_OFFSETS, unit)
		MovementProfile.Shape.ALL8:
			raw = _flood(origin, profile, board, ALL8_OFFSETS, unit)
		MovementProfile.Shape.KNIGHT:
			raw = _knight(origin, profile, board, unit)
		MovementProfile.Shape.TELEPORT:
			raw = _teleport(origin, profile, board, unit)

	var seen := {}
	var out: Array[Vector3i] = []
	for c in raw:
		var cell: Vector3i = c
		if cell == origin or seen.has(cell):
			continue
		seen[cell] = true
		out.append(cell)
	out.sort_custom(Cells.less)
	return out


## True if [param target] can be reached from [param origin] under [param profile].
## The origin is trivially reachable (distance 0).
func can_reach(origin: Vector3i, target: Vector3i, profile: MovementProfile, board, unit = null) -> bool:
	if target == origin:
		return true
	return reachable_cells(origin, profile, board, unit).has(target)


## The route from the last search's origin to [param dest], inclusive of both ends
## ([code][origin, ..., dest][/code]). [code][origin][/code] for the origin itself;
## empty when [param dest] was not reached (or no search has run). Stepping shapes
## give every step (including link hops), KNIGHT every landing, TELEPORT just
## [code][origin, dest][/code]. NOTE: a cell may have been reached only as a
## pass-through (e.g. occupied by an ally); check [method reachable_cells] for
## whether the unit may STOP there.
func path_to(dest: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if _last_origin == Cells.INVALID or not _last_cost.has(dest):
		return out
	var cur := dest
	var guard := 0
	while cur != _last_origin and guard < 100000:
		out.push_front(cur)
		if not _last_came_from.has(cur):
			return [] as Array[Vector3i]
		cur = _last_came_from[cur]
		guard += 1
	out.push_front(_last_origin)
	return out


## Accumulated cost of reaching [param dest] in the last search, or
## [constant UNREACHABLE]. 0 for the origin.
func cost_to(dest: Vector3i) -> int:
	return int(_last_cost.get(dest, UNREACHABLE))


## Every cell the last search touched -> its accumulated cost (a copy).
func last_costs() -> Dictionary:
	return _last_cost.duplicate()


## Path-aware "how many steps apart" field from [param origin], for planning (the
## AI's advance / threat distances). An unlimited 4-directional flood where every
## step (same-floor or over a link) costs 1, UNITS ARE IGNORED, walls block GROUND
## and air blocks everything but FLYING. Stops expanding past [param max_cost].
## Returns cell -> steps. Unlike a raw Manhattan distance it knows a unit below a
## rampart is NOT next to the defender on top of it: it must walk to the stairs.
func travel_distances(origin: Vector3i, board, kind: CombatTypes.MovementKind = CombatTypes.MovementKind.GROUND, max_cost: int = 64) -> Dictionary:
	var dist := { origin: 0 }
	var heap := MinHeap.new()
	heap.push(0, origin)
	while not heap.is_empty():
		var top: Array = heap.pop()
		var d: int = top[0]
		var cur: Vector3i = top[1]
		if d > int(dist.get(cur, UNREACHABLE)):
			continue
		if d >= max_cost:
			continue
		for n in _neighbors(cur, ORTHOGONAL_OFFSETS, kind, board):
			var cell: Vector3i = n[0]
			if not _in_bounds(board, cell):
				continue
			if not _structure_allows(board, cell, kind, false):
				continue
			if kind == CombatTypes.MovementKind.GROUND and _is_blocked(board, cell):
				continue
			var nd := d + 1
			if nd < int(dist.get(cell, UNREACHABLE)):
				dist[cell] = nd
				heap.push(nd, cell)
	return dist


# --- Shape strategies ------------------------------------------------------

## Neighbour candidates of [param cur]: same-floor [param offsets], link edges from
## the board, and (FLYING only) straight up/down. Each entry is
## [code][cell, link_cost][/code] where link_cost is -1 for an ordinary step.
static func _neighbors(cur: Vector3i, offsets: Array[Vector3i], kind: CombatTypes.MovementKind, board) -> Array:
	var out: Array = []
	for off in offsets:
		out.append([cur + off, -1])
	if board != null and board.has_method("links_from"):
		for e in board.links_from(cur):
			out.append([e["to"], int(e.get("cost", 1))])
	if kind == CombatTypes.MovementKind.FLYING and _floor_count(board) > 1:
		for off in VERTICAL_OFFSETS:
			out.append([cur + off, -1])
	return out


## Uniform-cost flood for stepping shapes. Expands only through traversable
## cells, accumulates entry cost, and keeps cells whose total cost is within
## range and on which the kind is allowed to stop.
func _flood(origin: Vector3i, profile: MovementProfile, board, offsets: Array[Vector3i], unit = null) -> Array:
	var best := { origin: 0 }
	var came_from := {}
	var heap := MinHeap.new()
	heap.push(0, origin)
	while not heap.is_empty():
		var top: Array = heap.pop()
		var cur_cost: int = top[0]
		var cur: Vector3i = top[1]
		if cur_cost > int(best[cur]):
			continue  # stale heap entry
		for nb in _neighbors(cur, offsets, profile.kind, board):
			var n: Vector3i = nb[0]
			var link_cost: int = nb[1]
			if not _in_bounds(board, n):
				continue
			if not _can_enter(unit, n, profile.kind, board):
				continue
			var step: int = link_cost if link_cost > 0 else _enter_cost(n, profile, board)
			var nc: int = cur_cost + step
			if nc > profile.range:
				continue
			if best.has(n) and best[n] <= nc:
				continue
			best[n] = nc
			came_from[n] = cur
			heap.push(nc, n)

	_last_cost = best
	_last_came_from = came_from
	var out: Array = []
	for c in best.keys():
		if c == origin:
			continue
		if _can_finish(unit, c, profile.kind, board):
			out.append(c)
	return out


## Breadth-first search over L-jumps. Each jump ignores intervening cells but
## must land on a cell the kind may stop on; range caps the number of jumps.
## Jumps stay on the unit's floor.
func _knight(origin: Vector3i, profile: MovementProfile, board, unit = null) -> Array:
	var out: Array = []
	var visited := { origin: true }
	var frontier: Array[Vector3i] = [origin]
	var jumps: int = maxi(0, profile.range)
	for step in range(jumps):
		var nxt: Array[Vector3i] = []
		for cell in frontier:
			for off in KNIGHT_OFFSETS:
				var n: Vector3i = cell + off
				if visited.has(n):
					continue
				if not _in_bounds(board, n):
					continue
				if not _can_finish(unit, n, profile.kind, board):
					continue
				visited[n] = true
				_last_cost[n] = step + 1
				_last_came_from[n] = cell
				out.append(n)
				nxt.append(n)
		frontier = nxt
	return out


## Every cell within direct range ([method Cells.distance]), obstacles ignored for
## pathing. Considers every floor the board reports.
func _teleport(origin: Vector3i, profile: MovementProfile, board, unit = null) -> Array:
	var out: Array = []
	var r: int = maxi(0, profile.range)
	var floors: int = _floor_count(board)
	for f in range(floors):
		var dz := absi(f - origin.z) if floors > 1 else 0
		var fz := f if floors > 1 else origin.z
		var rr := r - dz
		if rr < 0:
			continue
		for dx in range(-rr, rr + 1):
			for dy in range(-rr, rr + 1):
				if dx == 0 and dy == 0 and fz == origin.z:
					continue
				if absi(dx) + absi(dy) > rr:
					continue
				var n := Vector3i(origin.x + dx, origin.y + dy, fz)
				if not _in_bounds(board, n):
					continue
				if not _can_finish(unit, n, profile.kind, board):
					continue
				_last_cost[n] = Cells.distance(origin, n)
				_last_came_from[n] = origin
				out.append(n)
	return out


# --- Traversal / stopping rules -------------------------------------------

## Floor structure rule: may a unit of [param kind] be in [param cell]? Cells with
## a tile always qualify. AIR (no tile) only for a FLYING unit passing through an
## upper floor -- never to stop.
static func _structure_allows(board, cell: Vector3i, kind: CombatTypes.MovementKind, stopping: bool) -> bool:
	if _has_tile(board, cell):
		return true
	return kind == CombatTypes.MovementKind.FLYING and not stopping and cell.z > 0


## Whether the pathfinder may move [i]through[/i] (or into) a cell for a kind.
## [param mover] (optional) lets the mover pass through cells held only by its allies.
static func _can_traverse(cell: Vector3i, kind: CombatTypes.MovementKind, board, mover = null) -> bool:
	if not _structure_allows(board, cell, kind, false):
		return false
	match kind:
		CombatTypes.MovementKind.GROUND:
			return not _is_blocked(board, cell) and not _blocks_passage(board, mover, cell)
		CombatTypes.MovementKind.FLYING:
			return not _blocks_passage(board, mover, cell)
		CombatTypes.MovementKind.PHASING:
			return true
	return true


## True when [param cell] holds a living unit that [param mover] may NOT walk
## through: anyone who is not the mover itself and not the mover's ally. With no
## mover, or a board that cannot answer allegiance, any occupant blocks (the
## original rule).
static func _blocks_passage(board, mover, cell: Vector3i) -> bool:
	if board == null:
		return false
	if mover == null or not board.has_method("units_at") or not board.has_method("are_allies"):
		return _is_occupied(board, cell)
	for u in board.units_at(cell):
		if u == null or u == mover or not _unit_alive(u):
			continue
		if not bool(board.are_allies(mover, u)):
			return true
	return false


## Whether a unit of the given kind may end its movement on a cell. No kind may
## stop on an occupied cell or in the air.
static func _can_stop(cell: Vector3i, kind: CombatTypes.MovementKind, board) -> bool:
	if not _structure_allows(board, cell, kind, true):
		return false
	match kind:
		CombatTypes.MovementKind.GROUND:
			return not _is_blocked(board, cell) and not _is_occupied(board, cell)
		_:
			return not _is_occupied(board, cell)


# --- Footprint-aware wrappers ----------------------------------------------

## Traversal check that also honours a multi-cell mover. A 1x1 (or unknown) unit
## falls straight through to [method _can_traverse], so single-cell behaviour is
## byte-for-byte the pre-footprint logic.
static func _can_enter(unit, cell: Vector3i, kind: CombatTypes.MovementKind, board) -> bool:
	var fp := _footprint_of(unit)
	if fp == Vector2i.ONE:
		return _can_traverse(cell, kind, board, unit)
	return _span_allows(unit, cell, fp, kind, board, false)


## Stopping check that also honours a multi-cell mover (see [method _can_enter]).
## For GROUND this is exactly the board's own [code]can_fit[/code] when it exposes
## one; the other kinds are span-checked here because they ignore walls.
static func _can_finish(unit, cell: Vector3i, kind: CombatTypes.MovementKind, board) -> bool:
	var fp := _footprint_of(unit)
	if fp == Vector2i.ONE:
		return _can_stop(cell, kind, board)
	if kind == CombatTypes.MovementKind.GROUND and board != null and board.has_method("can_fit"):
		return bool(board.can_fit(unit, cell))
	return _span_allows(unit, cell, fp, kind, board, true)


## Per-kind legality across every cell a footprint covers from [param anchor] (on
## the anchor's floor). Occupancy excludes the mover itself, so a large unit's own
## body never blocks the step it is trying to take. [param stopping] applies the
## end-of-move rule (no kind may finish on a cell another living unit holds).
static func _span_allows(unit, anchor: Vector3i, fp: Vector2i, kind: CombatTypes.MovementKind, board, stopping: bool) -> bool:
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector3i(anchor.x + dx, anchor.y + dy, anchor.z)
			if not _in_bounds(board, c):
				return false
			if not _structure_allows(board, c, kind, stopping):
				return false
			# Stopping needs the cell free of everyone else; passing only of non-allies.
			var occupied: bool = _occupied_by_other(board, unit, c) if stopping else _blocks_passage(board, unit, c)
			match kind:
				CombatTypes.MovementKind.GROUND:
					if _is_blocked(board, c) or occupied:
						return false
				CombatTypes.MovementKind.FLYING:
					if occupied:
						return false
				CombatTypes.MovementKind.PHASING:
					# Phases through everything while pathing; still cannot land on a unit.
					if stopping and _occupied_by_other(board, unit, c):
						return false
	return true


## [param unit]'s cell span (a 2D x/y size on one floor), read duck-typed;
## Vector2i.ONE when unknown or invalid.
static func _footprint_of(unit) -> Vector2i:
	if unit != null and unit.has_method("get_footprint"):
		var fp = unit.get_footprint()
		if fp is Vector2i:
			return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE


## True when a living unit OTHER than [param mover] stands on [param cell]. Falls
## back to the plain occupancy query on boards without units_at.
static func _occupied_by_other(board, mover, cell: Vector3i) -> bool:
	if board == null:
		return false
	if mover != null and board.has_method("units_at"):
		for u in board.units_at(cell):
			if u != null and u != mover and _unit_alive(u):
				return true
		return false
	return _is_occupied(board, cell)


## Duck-typed liveness: prefers is_alive(), then a readable hp, else assumes alive.
static func _unit_alive(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	var hp = unit.get("hp")
	if hp != null:
		return int(hp) > 0
	return true


# --- Duck-typed board accessors -------------------------------------------

static func _in_bounds(board, cell: Vector3i) -> bool:
	if board != null and board.has_method("in_bounds"):
		return bool(board.in_bounds(cell))
	# A board with no notion of bounds still has no floors below ground.
	return cell.z >= 0 and (cell.z == 0 or cell.z < _floor_count(board))


static func _is_blocked(board, cell: Vector3i) -> bool:
	if board != null and board.has_method("is_blocked"):
		return bool(board.is_blocked(cell))
	return false


static func _is_occupied(board, cell: Vector3i) -> bool:
	if board != null and board.has_method("is_occupied"):
		return bool(board.is_occupied(cell))
	return false


## True when [param cell] has a floor to stand on. Boards without the query are
## single-floor and solid everywhere.
static func _has_tile(board, cell: Vector3i) -> bool:
	if board != null and board.has_method("has_tile"):
		return bool(board.has_tile(cell))
	return cell.z == 0 or cell.z < _floor_count(board)


static func _floor_count(board) -> int:
	if board != null and board.has_method("floor_count"):
		return maxi(1, int(board.floor_count()))
	return 1


## Cost to enter [param cell]: a matching terrain override (by tile id then tag)
## wins; otherwise the board's move_cost (clamped to at least 1); default 1.
static func _enter_cost(cell: Vector3i, profile: MovementProfile, board) -> int:
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


## Minimal binary min-heap of [cost, seq, cell] (seq breaks ties FIFO so the search
## is deterministic). Replaces the old O(n^2) open-list scan.
class MinHeap:
	var _a: Array = []
	var _seq: int = 0

	func is_empty() -> bool:
		return _a.is_empty()

	func push(cost: int, cell: Vector3i) -> void:
		_a.append([cost, _seq, cell])
		_seq += 1
		var i := _a.size() - 1
		while i > 0:
			var p := (i - 1) >> 1
			if _lt(_a[i], _a[p]):
				var t = _a[i]; _a[i] = _a[p]; _a[p] = t
				i = p
			else:
				break

	## Returns [cost, cell].
	func pop() -> Array:
		var top: Array = _a[0]
		var last: Array = _a.pop_back()
		if not _a.is_empty():
			_a[0] = last
			var i := 0
			var n := _a.size()
			while true:
				var l := i * 2 + 1
				var r := l + 1
				var m := i
				if l < n and _lt(_a[l], _a[m]):
					m = l
				if r < n and _lt(_a[r], _a[m]):
					m = r
				if m == i:
					break
				var t = _a[i]; _a[i] = _a[m]; _a[m] = t
				i = m
		return [top[0], top[2]]

	static func _lt(x: Array, y: Array) -> bool:
		if x[0] != y[0]:
			return x[0] < y[0]
		return x[1] < y[1]
