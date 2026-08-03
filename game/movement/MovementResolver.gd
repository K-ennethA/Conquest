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
## within the profile's budget. The origin itself is never included. [param unit] is
## the moving unit, used only to honour a multi-cell footprint; omit it (or pass a
## 1x1 unit) for the original single-cell behaviour.
func reachable_cells(origin: Vector2i, profile: MovementProfile, board, unit = null) -> Array[Vector2i]:
	# LIVE MOVEMENT DEBUFFS/BUFFS shrink or grow the flood budget. The authored profile
	# carries a STATIC range (base movement); a temporary movement-stat modifier -- e.g.
	# the "Slowed" status a rubble field applies -- lowers the unit's live movement but
	# never touched the profile, so it used to do nothing to reachability. Fold the delta
	# (current - base movement) into an effective range here so a slow visibly shrinks the
	# reachable set the same turn (and a haste grows it).
	profile = _effective_profile(profile, unit)
	var raw: Array = []
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
## range and on which the kind is allowed to stop.
func _flood(origin: Vector2i, profile: MovementProfile, board, offsets: Array[Vector2i], unit = null) -> Array:
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
			if not _can_enter(unit, n, profile.kind, board):
				continue
			var nc: int = cur_cost + _enter_cost(n, profile, board, unit)
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
		if _can_finish(unit, c, profile.kind, board):
			out.append(c)
	return out


## Breadth-first search over L-jumps. Each jump ignores intervening cells but
## must land on a cell the kind may stop on; range caps the number of jumps.
func _knight(origin: Vector2i, profile: MovementProfile, board, unit = null) -> Array:
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
				if not _can_finish(unit, n, profile.kind, board):
					continue
				visited[n] = true
				out.append(n)
				nxt.append(n)
		frontier = nxt
	return out


## Every cell within direct (Manhattan) range, obstacles ignored for pathing.
func _teleport(origin: Vector2i, profile: MovementProfile, board, unit = null) -> Array:
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


# --- Effective range (live movement stat delta) ----------------------------

## The profile to actually flood with, once the unit's LIVE movement modifiers are
## folded in. When the unit exposes both a current and a base movement stat and they
## differ (a temporary buff/debuff is active), return a DUPLICATE whose range is
## [code]maxi(0, profile.range + (current - base))[/code] -- a -2 movement debuff shrinks
## the reachable set by 2, a +1 haste grows it by 1. The shared authoring resource is
## never mutated (a fresh duplicate is returned only when the delta is nonzero).
##
## Fully null-safe for mocks: a null profile/unit, or a unit that cannot report both
## stats (the RefCounted units tests pass), yields the ORIGINAL profile untouched, so
## every existing caller and test is byte-for-byte unchanged.
static func _effective_profile(profile: MovementProfile, unit) -> MovementProfile:
	if profile == null or unit == null:
		return profile
	if not (unit.has_method("get_stat") and unit.has_method("get_base_stat")):
		return profile
	var current: int = int(unit.get_stat("movement"))
	var base: int = int(unit.get_base_stat("movement"))
	var delta: int = current - base
	if delta == 0:
		return profile
	var adjusted: MovementProfile = profile.duplicate()
	adjusted.range = maxi(0, profile.range + delta)
	return adjusted


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
