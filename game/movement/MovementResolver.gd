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
## board.can_fit(unit, anchor: Vector2i) -> bool  # whole-footprint placement; optional
## board.units_at(cell: Vector2i) -> Array        # for self-excluding occupancy; optional
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
## GROUND  — cannot path through walls, nor through an ENEMY-occupied cell; may not
##           end on a blocked or occupied cell.
## FLYING  — ignores walls (`is_blocked`) entirely; blocked by ENEMY units in its
##           path and may not end on an occupied cell.
## PHASING — ignores walls and units while pathing; may not end on an occupied cell.
## [/ul]
## TELEPORT reachability ignores everything for pathing but still may not land on
## an occupied cell (respecting the profile's kind for the destination).
##
## [b]ALLY PASS-THROUGH (the Fire Emblem rule).[/b] A cell held only by the mover's own
## ALLIES is PASSABLE — a unit boxed in by its own side can always walk out between them —
## but it is never a legal place to STOP. Enemies still block pathing outright. The rule
## needs the board to positively confirm friendship (`units_at` + `are_allies`); a board
## that cannot answer either question falls back to the old "any occupant blocks" behaviour,
## so mock boards and non-allegiance-aware callers are unchanged.
##
## [b]THE BUDGET IS THE MOVER'S MOVEMENT STAT.[/b] How FAR a unit goes is
## [code]unit.get_stat("movement")[/code] — the very number the card's MOV chip prints —
## and NOT [member MovementProfile.range]. There is one source of truth for that number and
## it is the unit's stat block: base movement, plus every live modifier (a Slowed status, a
## haste, Void Surge's canto debuff), plus anything a mode grants (Siege's march bonus).
## Nothing has to be folded in by hand, because the stat has already folded it.
##
## The profile keeps its real jobs — the movement KIND, the stepping SHAPE, and the
## per-terrain cost overrides — and its [member MovementProfile.range] survives only as the
## FALLBACK for a call with no mover (a tool, a mock, a range preview for a profile that has
## no unit attached yet). That split is why the roster can share one `ground_standard.tres`
## and still have eleven different strides.
##
## WHY IT MATTERS. This used to flood with `profile.range` and fold in only the DELTA of the
## live modifiers (`current - base`), which is 0 for a clean unit. Every roster entry shares
## a range-3 profile, so a character with a printed MOV of 5 actually reached 3 — the card
## and the board disagreed for the whole roster. Reading the stat directly makes the printed
## number the true one.
## → pinned by `tests/integration/test_duskmaw_movement_sweep.gd`

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


## Returns the sorted, de-duplicated set of cells reachable from [param origin] within
## the mover's budget. The origin itself is never included. [param unit] is the moving
## unit: it supplies the BUDGET ([code]get_stat("movement")[/code]) and honours a
## multi-cell footprint. Omit it and the flood falls back to
## [member MovementProfile.range] with the original single-cell rules.
## [param excluded] is an optional SET (a Dictionary used as `cell -> anything`) of cells
## the flood may neither cross nor stop on, over and above the board's own rules. It exists
## for callers that want to route AROUND something the board still considers perfectly
## walkable -- the AI steering clear of an armed trap is the only shipped user. Empty (the
## default) is byte-for-byte the original behaviour and costs one `is_empty()` per call.
func reachable_cells(origin: Vector2i, profile: MovementProfile, board, unit = null, excluded: Dictionary = {}) -> Array[Vector2i]:
	# HOW FAR comes from the MOVER, not from the profile (see the class note): the unit's
	# effective movement stat already carries its base stride, every live buff/debuff and
	# any mode grant. The profile still says HOW it moves -- kind, shape, terrain costs.
	var budget: int = _budget(profile, unit)
	var raw: Array = []
	match profile.shape:
		MovementProfile.Shape.ORTHOGONAL:
			raw = _flood(origin, profile, budget, board, ORTHOGONAL_OFFSETS, unit, excluded)
		MovementProfile.Shape.DIAGONAL:
			raw = _flood(origin, profile, budget, board, DIAGONAL_OFFSETS, unit, excluded)
		MovementProfile.Shape.ALL8:
			raw = _flood(origin, profile, budget, board, ALL8_OFFSETS, unit, excluded)
		MovementProfile.Shape.KNIGHT:
			raw = _knight(origin, budget, profile, board, unit, excluded)
		MovementProfile.Shape.TELEPORT:
			raw = _teleport(origin, budget, profile, board, unit, excluded)

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
func can_reach(origin: Vector2i, target: Vector2i, profile: MovementProfile, board, unit = null) -> bool:
	if target == origin:
		return true
	return reachable_cells(origin, profile, board, unit).has(target)


# --- Shape strategies ------------------------------------------------------

## Uniform-cost flood for stepping shapes. Expands only through traversable
## cells, accumulates entry cost, and keeps cells whose total cost is within
## [param budget] (the mover's movement stat) and on which the kind is allowed to stop.
func _flood(origin: Vector2i, profile: MovementProfile, budget: int, board, offsets: Array[Vector2i], unit = null, excluded: Dictionary = {}) -> Array:
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
			if excluded.has(n):
				continue
			if not _can_enter(unit, n, profile.kind, board):
				continue
			var nc: int = cur_cost + _enter_cost(n, profile, board, unit)
			if nc > budget:
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
		if _can_finish(unit, c, profile.kind, board):
			out.append(c)
	return out


# --- Path derivation --------------------------------------------------------

## The cells [param unit] actually WALKS OVER going from [param origin] to [param dest],
## in step order, EXCLUDING the origin and INCLUDING the destination. Empty when the
## destination is the origin or cannot be reached under [param profile].
##
## WHY THIS EXISTS, and why it is here. Movement in this game is stored as a DESTINATION
## (the MOVE_UNIT command carries one cell, not a route), so "what did the unit step on"
## had no answer until traps needed one. Deriving it HERE -- from the same profile, the
## same board queries and the same per-cell [method _enter_cost] the reachability flood
## uses -- is what makes the answer agree with the reach the player was shown, on every
## lockstep peer and in every replay, without a second pathfinder to drift from the first.
##
## DETERMINISTIC BY CONSTRUCTION. The frontier settles in (cost, x, y) order and the FIRST
## predecessor to reach a cell at its final cost keeps it, so the route depends only on the
## board state and the profile -- never on dictionary iteration, scene order or wall clock.
## Two peers applying the same command to the same board derive the same cells.
##
## KNIGHT and TELEPORT have no traversed cells at all -- both deliberately ignore whatever
## lies between (see the class note) -- so they return just [code][dest][/code]: the unit
## arrives without stepping on anything, and nothing between origin and destination can
## spring on it.
func path_cells(origin: Vector2i, dest: Vector2i, profile: MovementProfile, board, unit = null) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if profile == null or dest == origin:
		return out
	# The SAME budget the reachable flood used (the mover's movement stat), so the route
	# and the reach the player was shown can never disagree.
	var budget: int = _budget(profile, unit)
	var offsets: Array[Vector2i] = _step_offsets(profile.shape)
	if offsets.is_empty():
		out.append(dest)
		return out

	var best := { origin: 0 }
	var prev := {}
	var open: Array[Vector2i] = [origin]
	while not open.is_empty():
		var bi: int = 0
		for i in range(1, open.size()):
			if _settles_first(open[i], open[bi], best):
				bi = i
		var cur: Vector2i = open[bi]
		open.remove_at(bi)
		var cur_cost: int = best[cur]
		for off in offsets:
			var n: Vector2i = cur + off
			if not _in_bounds(board, n):
				continue
			if not _can_enter(unit, n, profile.kind, board):
				continue
			var nc: int = cur_cost + _enter_cost(n, profile, board, unit)
			if nc > budget:
				continue
			if best.has(n) and best[n] <= nc:
				continue
			best[n] = nc
			prev[n] = cur
			if not open.has(n):
				open.append(n)

	if not prev.has(dest):
		return out
	var walk: Array[Vector2i] = []
	var cell: Vector2i = dest
	# The predecessor chain is acyclic by construction (every link strictly lowers the
	# accumulated cost), but bound the unwind anyway: a corrupted chain must return an
	# empty path -- "no route known" -- rather than hang the move.
	var guard: int = best.size() + 1
	while cell != origin:
		walk.append(cell)
		if not prev.has(cell):
			return out
		cell = prev[cell]
		guard -= 1
		if guard < 0:
			return out
	walk.reverse()
	return walk


## The per-step offsets for a stepping [param shape], or EMPTY for the shapes that do not
## step at all (KNIGHT jumps, TELEPORT blinks).
static func _step_offsets(shape: MovementProfile.Shape) -> Array[Vector2i]:
	match shape:
		MovementProfile.Shape.ORTHOGONAL:
			return ORTHOGONAL_OFFSETS
		MovementProfile.Shape.DIAGONAL:
			return DIAGONAL_OFFSETS
		MovementProfile.Shape.ALL8:
			return ALL8_OFFSETS
	return [] as Array[Vector2i]


## Frontier ordering for [method path_cells]: cheaper first, ties broken by column then
## row. A TOTAL order over cells, which is what makes the derived route reproducible.
static func _settles_first(a: Vector2i, b: Vector2i, best: Dictionary) -> bool:
	var ca: int = int(best[a])
	var cb: int = int(best[b])
	if ca != cb:
		return ca < cb
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


## Breadth-first search over L-jumps. Each jump ignores intervening cells but
## must land on a cell the kind may stop on; [param budget] caps the number of jumps.
func _knight(origin: Vector2i, budget: int, profile: MovementProfile, board, unit = null, excluded: Dictionary = {}) -> Array:
	var out: Array = []
	var visited := { origin: true }
	var frontier: Array[Vector2i] = [origin]
	var jumps: int = maxi(0, budget)
	for _step in range(jumps):
		var nxt: Array[Vector2i] = []
		for cell in frontier:
			for off in KNIGHT_OFFSETS:
				var n: Vector2i = cell + off
				if visited.has(n):
					continue
				if not _in_bounds(board, n):
					continue
				if excluded.has(n):
					continue
				if not _can_finish(unit, n, profile.kind, board):
					continue
				visited[n] = true
				out.append(n)
				nxt.append(n)
		frontier = nxt
	return out


## Every cell within direct (Manhattan) [param budget], obstacles ignored for pathing.
func _teleport(origin: Vector2i, budget: int, profile: MovementProfile, board, unit = null, excluded: Dictionary = {}) -> Array:
	var out: Array = []
	var r: int = maxi(0, budget)
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			if absi(dx) + absi(dy) > r:
				continue
			var n := Vector2i(origin.x + dx, origin.y + dy)
			if not _in_bounds(board, n):
				continue
			if excluded.has(n):
				continue
			if not _can_finish(unit, n, profile.kind, board):
				continue
			out.append(n)
	return out


# --- Traversal / stopping rules -------------------------------------------

## Whether the pathfinder may move [i]through[/i] (or into) a cell for a kind.
##
## [param mover] is the unit doing the walking; it is what makes ally pass-through
## possible (a cell holding only friends does not block). Null keeps the historical
## "any occupant blocks" reading.
static func _can_traverse(mover, cell: Vector2i, kind: CombatTypes.MovementKind, board) -> bool:
	match kind:
		CombatTypes.MovementKind.GROUND:
			return not _is_blocked(board, cell) and not _blocks_traversal(board, mover, cell)
		CombatTypes.MovementKind.FLYING:
			return not _blocks_traversal(board, mover, cell)
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


# --- Footprint-aware wrappers ----------------------------------------------

## Traversal check that also honours a multi-cell mover. A 1x1 (or unknown) unit
## falls straight through to [method _can_traverse], so single-cell behaviour is
## byte-for-byte the pre-footprint logic.
static func _can_enter(unit, cell: Vector2i, kind: CombatTypes.MovementKind, board) -> bool:
	var fp := _footprint_of(unit)
	if fp == Vector2i.ONE:
		return _can_traverse(unit, cell, kind, board)
	return _span_allows(unit, cell, fp, kind, board, false)


## Stopping check that also honours a multi-cell mover (see [method _can_enter]).
## For GROUND this is exactly the board's own [code]can_fit[/code] when it exposes
## one; the other kinds are span-checked here because they ignore walls.
static func _can_finish(unit, cell: Vector2i, kind: CombatTypes.MovementKind, board) -> bool:
	var fp := _footprint_of(unit)
	if fp == Vector2i.ONE:
		return _can_stop(cell, kind, board)
	if kind == CombatTypes.MovementKind.GROUND and board != null and board.has_method("can_fit"):
		return bool(board.can_fit(unit, cell))
	return _span_allows(unit, cell, fp, kind, board, true)


## Per-kind legality across every cell a footprint covers from [param anchor].
## Occupancy excludes the mover itself, so a large unit's own body never blocks the
## step it is trying to take. [param stopping] applies the end-of-move rule (no kind
## may finish on a cell another living unit holds); while merely PASSING THROUGH, the
## mover's own allies are transparent exactly as they are for a 1x1 unit.
static func _span_allows(unit, anchor: Vector2i, fp: Vector2i, kind: CombatTypes.MovementKind, board, stopping: bool) -> bool:
	for dx in range(fp.x):
		for dy in range(fp.y):
			var c := Vector2i(anchor.x + dx, anchor.y + dy)
			if not _in_bounds(board, c):
				return false
			# Landing: ANY other living unit blocks. Passing: only a non-ally does.
			var unit_in_the_way: bool = _occupied_by_other(board, unit, c) if stopping \
				else _blocks_traversal(board, unit, c)
			match kind:
				CombatTypes.MovementKind.GROUND:
					if _is_blocked(board, c) or unit_in_the_way:
						return false
				CombatTypes.MovementKind.FLYING:
					if unit_in_the_way:
						return false
				CombatTypes.MovementKind.PHASING:
					# Phases through everything while pathing; still cannot land on a unit.
					if stopping and unit_in_the_way:
						return false
	return true


## [param unit]'s cell span, read duck-typed; Vector2i.ONE when unknown or invalid.
static func _footprint_of(unit) -> Vector2i:
	if unit != null and unit.has_method("get_footprint"):
		var fp = unit.get_footprint()
		if fp is Vector2i:
			return Vector2i(maxi(1, fp.x), maxi(1, fp.y))
	return Vector2i.ONE


## True when a living unit OTHER than [param mover] stands on [param cell]. Falls
## back to the plain occupancy query on boards without units_at.
static func _occupied_by_other(board, mover, cell: Vector2i) -> bool:
	if board == null:
		return false
	if mover != null and board.has_method("units_at"):
		for u in board.units_at(cell):
			if u != null and u != mover and _unit_alive(u):
				return true
		return false
	return _is_occupied(board, cell)


## True when something standing on [param cell] stops [param mover] PASSING THROUGH it.
##
## THE ALLY PASS-THROUGH RULE lives here, and nowhere else. A living unit blocks the
## path unless the board can confirm it is one of the mover's own — the Fire Emblem
## model, where you may walk between your own line but never through the enemy's. The
## mover itself is transparent (a large unit never blocks its own step) and a corpse
## mid-cleanup is ignored, exactly as [method _occupied_by_other] does.
##
## FAILS CLOSED. Pass-through requires BOTH [code]units_at[/code] (to see who is there)
## and [code]are_allies[/code] (to judge them). A board offering neither -- a lightweight
## mock, a caller with no allegiance model -- falls straight back to the plain occupancy
## query, so nothing that could not previously be walked through becomes walkable, and no
## board ever has hostility invented for it.
static func _blocks_traversal(board, mover, cell: Vector2i) -> bool:
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


# --- The flood budget: the mover's movement STAT ----------------------------

## How far [param unit] may travel this move: its EFFECTIVE movement stat.
##
## ONE SOURCE OF TRUTH. `get_stat("movement")` is base movement with every live modifier
## already applied -- a Slowed status, a haste, Void Surge's canto debuff, a mode's march
## grant -- and it is the exact number the card's MOV chip prints. Reading it here is what
## makes the printed stride and the reachable set the same number, for every character, with
## no arithmetic of our own to drift.
##
## THE FALLBACK. With no mover (a profile-only call: a tool, a preview, a mock board test)
## there is no stat to read, so [member MovementProfile.range] stands in. It is also the
## fallback for a mover that cannot report stats at all -- a bare RefCounted double. Nothing
## clamps a stat of 0 up to the profile: a unit debuffed to 0 movement genuinely goes
## nowhere, and inventing a stride for it would be the same class of bug this replaced.
static func _budget(profile: MovementProfile, unit) -> int:
	if unit != null and unit.has_method("get_stat"):
		return maxi(0, int(unit.get_stat("movement")))
	if profile == null:
		return 0
	return maxi(0, profile.range)


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
static func _enter_cost(cell: Vector2i, profile: MovementProfile, board, unit = null) -> int:
	var base_cost: int = 1
	var overrides: Dictionary = profile.terrain_cost_overrides
	var matched_override: bool = false
	if overrides != null and not overrides.is_empty() and board != null:
		if board.has_method("tile_id_at"):
			var tid = board.tile_id_at(cell)
			if tid != null and overrides.has(tid):
				base_cost = maxi(0, int(overrides[tid]))
				matched_override = true
		if not matched_override and board.has_method("tile_tag_at"):
			var tag = board.tile_tag_at(cell)
			if tag != null and overrides.has(tag):
				base_cost = maxi(0, int(overrides[tag]))
				matched_override = true
	if not matched_override:
		if board != null and board.has_method("move_cost"):
			base_cost = maxi(1, int(board.move_cost(cell)))
		else:
			base_cost = 1
	# A layered tile effect (a scattered-rubble field) adds its move_cost_bonus for any
	# unit it applies to, so an enemies-only slow bites on the turn the foe tries to cross.
	return base_cost + _tile_effect_cost(cell, board, unit)


## Sum of move_cost_bonus from every tile effect on [param cell] that applies to
## [param unit]. 0 when there is no unit, no tile-effect source, or none apply -- so this
## never changes cost for a plain cell, a headless mock board, or the placer's own units.
static func _tile_effect_cost(cell: Vector2i, board, unit) -> int:
	if unit == null or board == null or not board.has_method("tile_effects_at"):
		return 0
	var total: int = 0
	for te in board.tile_effects_at(cell):
		if te == null:
			continue
		var bonus: int = int(te.get("move_cost_bonus")) if "move_cost_bonus" in te else 0
		if bonus <= 0:
			continue
		if te.has_method("applies_to") and te.applies_to(unit, board):
			total += bonus
	return total
