extends RefCounted
class_name ThreatResolver

## THREAT RANGES -- "where could this unit hit next turn?" (Fire Emblem's danger zone,
## the red attack fringe around a selected unit's blue move range).
##
## For a unit: every cell it could STAND on this turn (its [MovementResolver]
## reachable set PLUS its own cell), and from each of those every cell one of its
## OFFENSIVE moves could legally be aimed at (its effective max range, height bonus
## and melee-over-a-stair included -- [method TargetingPattern.in_reach] -- and line
## of sight where the pattern needs it). Area moves also count the cells their
## footprint would cover from that aim.
##
## Every entry point wraps a live board in a [BoardSnapshot] (occupancy indexed once),
## so a whole army's reach costs milliseconds rather than seconds.
##
## Pure (reads the board, mutates nothing) and board-agnostic: any board that
## satisfies [MovementResolver]'s duck-typed interface works, so the whole thing is
## unit-testable against a mock. Cells are [Vector3i](col, row, floor) -- see [Cells].
##
## Deliberately NOT modelled (a danger zone is a planning aid, not a proof): the
## pattern's situational constraints ([member TargetingPattern.requires_empty_cell] /
## [member TargetingPattern.requires_adjacent_enemy]) and whether a target would
## actually be standing there -- only reach is shown.

## Offensive moves [param unit] could use on its NEXT turn: moves whose (mode-aware)
## effects include a [DamageEffect], aimed at enemies / any unit / tiles (not SELF or
## ALLY), that still have charges and are off cooldown by then (remaining <= 1).
static func offensive_moves(unit) -> Array[MoveResource]:
	var out: Array[MoveResource] = []
	if unit == null or not unit.has_method("get_moveset"):
		return out
	var controller = unit.get_moveset_controller() if unit.has_method("get_moveset_controller") else null
	for move in unit.get_moveset():
		if move == null:
			continue
		var pattern: TargetingPattern = move.targeting_for(unit)
		if pattern == null:
			continue
		if pattern.target_kind == CombatTypes.TargetKind.SELF or pattern.target_kind == CombatTypes.TargetKind.ALLY:
			continue
		var deals_damage := false
		for e in move.effects_for(unit):
			if e is DamageEffect:
				deals_damage = true
				break
		if not deals_damage:
			continue
		if controller != null:
			if controller.has_method("uses_left") and int(controller.uses_left(move)) == 0:
				continue
			if controller.has_method("remaining") and int(controller.remaining(move)) > 1:
				continue
		out.append(move)
	return out


## Cells [param unit] can stand on: its reachable set plus its own cell (first).
## [param respect_turn_state] = true uses only its current cell once it has already
## moved this turn (can_move() false) -- right for a friendly unit's live fringe.
## false (the danger-zone default) assumes a fresh turn: full movement.
static func stand_cells(unit, board, respect_turn_state: bool = false) -> Array[Vector3i]:
	board = BoardSnapshot.of(board)
	var out: Array[Vector3i] = []
	if unit == null or board == null:
		return out
	var origin: Vector3i = board.cell_of(unit)
	out.append(origin)
	if respect_turn_state and unit.has_method("can_move") and not unit.can_move():
		return out
	var profile = unit.get_movement_profile() if unit.has_method("get_movement_profile") else null
	if profile == null:
		return out
	for c in MovementResolver.new().reachable_cells(origin, profile, board, unit):
		out.append(c)
	return out


## Every cell [param move] could affect when [param unit] stands on [param stand]:
## the legal aim cells plus, for an area pattern, each aim's footprint. Aims into
## the air on an upper floor, or off the board, are skipped.
## [param skip_floor] (>= 0) leaves out aims on that floor (already stamped by the
## caller's same-floor fast path).
static func move_threat_from(stand: Vector3i, move: MoveResource, unit, board, into: Dictionary = {}, skip_floor: int = -1) -> Dictionary:
	var pattern: TargetingPattern = move.targeting_for(unit)
	if pattern == null:
		return into
	var bonus := MoveResource.range_bonus_of(unit)
	var reach: int = pattern.effective_max_range(bonus) + Elevation.HIGH_GROUND_RANGE_BONUS
	var floors := _floor_count(board)
	var area := pattern.area_shape != CombatTypes.AreaShape.SINGLE
	for f in range(floors):
		if f == skip_floor:
			continue
		var r: int = reach - absi(f - stand.z)
		if r < 0:
			continue
		for aim in _candidates(stand, f, r, pattern, board):
			if not area and into.has(aim):
				continue  # already threatened -- skip the (costlier) legality test
			if not _aimable(board, aim):
				continue
			if not pattern.in_reach(stand, aim, board, bonus):
				continue
			if pattern.needs_line_of_sight(stand, aim) and not _linked_melee(pattern, stand, aim, board) \
					and not LineOfSight.has_line_of_sight(board, stand, aim, true):
				continue
			if area:
				for c in pattern.resolve_cells(stand, aim):
					if _aimable(board, c):
						into[c] = true
			else:
				into[aim] = true
	return into


## The full threat picture for one unit:
##   "move"   : Array[Vector3i] -- cells it can stand on (its own cell first)
##   "attack" : Array[Vector3i] -- every cell it could hit from any of those
##   "fringe" : Array[Vector3i] -- attack cells it cannot stand on (the red border)
## All sorted with [method Cells.less]. See [method stand_cells] for
## [param respect_turn_state].
static func unit_threat(unit, board, respect_turn_state: bool = false) -> Dictionary:
	board = BoardSnapshot.of(board)
	var stands := stand_cells(unit, board, respect_turn_state)
	var hit := attack_set_from(stands, unit, board)
	var stand_set := {}
	for s in stands:
		stand_set[s] = true
	var attack: Array[Vector3i] = []
	var fringe: Array[Vector3i] = []
	for c in hit.keys():
		attack.append(c)
		if not stand_set.has(c):
			fringe.append(c)
	attack.sort_custom(Cells.less)
	fringe.sort_custom(Cells.less)
	return { "move": stands, "attack": attack, "fringe": fringe }


## Set (cell -> true) of every cell [param unit]'s offensive moves could hit from
## any of [param stands]. For callers that already ran the movement flood.
static func attack_set_from(stands: Array, unit, board) -> Dictionary:
	board = BoardSnapshot.of(board)
	var hit := {}
	var floors := _floor_count(board)
	var bonus := MoveResource.range_bonus_of(unit)
	# FAST PATH (same floor). Unless a pattern demands same-floor LOS, what it can hit
	# on its own floor is pure geometry relative to where the unit stands: one set U
	# of (dx, dy) offsets (reach ring + area footprints, all moves merged) that every
	# stand simply stamps. Cross-floor aims and LosMode.ALWAYS patterns take the
	# general per-aim path below.
	var offsets := {}  # Vector2i -> true (U)
	var general: Array = []
	for m in offensive_moves(unit):
		var pattern: TargetingPattern = m.targeting_for(unit)
		if pattern.line_of_sight == TargetingPattern.LosMode.ALWAYS:
			general.append([m, -1])
			continue
		for o in _pattern_offsets(pattern, bonus):
			offsets[o] = true
		if floors > 1:
			general.append([m, 0])  # other floors only
	var full: Array = offsets.keys()
	# B: offsets NOT reachable as (a strictly shorter offset in U) + one step. An
	# INTERIOR stand (all 4 neighbours are stands) only needs to stamp B: any other
	# cell it reaches is reached from a neighbour with a shorter offset (induction).
	var back: Array = []
	for o in full:
		var covered := false
		var norm: int = absi(o.x) + absi(o.y)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var p: Vector2i = o - d
			if offsets.has(p) and absi(p.x) + absi(p.y) < norm:
				covered = true
				break
		if not covered:
			back.append(o)
	var stand_set := {}
	for s in stands:
		stand_set[s] = true
	# Inline bounds for a single-floor board with a known grid (the common case).
	var cols: int = board.cols if board is BoardSnapshot else -1
	var rows: int = board.rows if board is BoardSnapshot else -1
	var fast_bounds: bool = cols > 0 and rows > 0 and floors <= 1
	for s in stands:
		var interior := stand_set.has(s + Vector3i(1, 0, 0)) and stand_set.has(s + Vector3i(-1, 0, 0)) \
				and stand_set.has(s + Vector3i(0, 1, 0)) and stand_set.has(s + Vector3i(0, -1, 0))
		for o in (back if interior else full):
			var aim := Vector3i(s.x + o.x, s.y + o.y, s.z)
			if hit.has(aim):
				continue
			if fast_bounds:
				if aim.x < 0 or aim.y < 0 or aim.x >= cols or aim.y >= rows:
					continue
			elif not _aimable(board, aim):
				continue
			hit[aim] = true
	for s in stands:
		for entry in general:
			move_threat_from(s, entry[0], unit, board, hit, s.z if entry[1] == 0 else -1)
	return hit


## Same-floor offsets (dx, dy) [param pattern] can affect from its caster's cell:
## every aim in its reach ring plus (area patterns) that aim's footprint. Cached per
## pattern + range bonus (patterns are shared, immutable move data).
static var _offset_cache: Dictionary = {}

static func _pattern_offsets(pattern: TargetingPattern, bonus: int) -> Array:
	var reach: int = pattern.effective_max_range(bonus)
	var key := "%d:%d:%d:%d:%d:%d" % [pattern.get_instance_id(), bonus, pattern.min_range, reach, pattern.area_shape, pattern.area_size]
	if _offset_cache.has(key):
		return _offset_cache[key]
	var set := {}
	for off in _ring_offsets(pattern.min_range, reach):
		if pattern.area_shape == CombatTypes.AreaShape.SINGLE:
			set[off] = true
		else:
			for c in pattern.resolve_cells(Vector3i.ZERO, Vector3i(off.x, off.y, 0)):
				set[Vector2i(c.x, c.y)] = true
	var out: Array = set.keys()
	_offset_cache[key] = out
	return out


## Offsets (dx, dy) with min_r <= |dx| + |dy| <= max_r.
static func _ring_offsets(min_r: int, max_r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-max_r, max_r + 1):
		var span: int = max_r - absi(dx)
		for dy in range(-span, span + 1):
			var d := absi(dx) + absi(dy)
			if d >= min_r and d <= max_r:
				out.append(Vector2i(dx, dy))
	return out


## The red FRINGE for a unit whose stand cells are already known: attackable cells
## that are not in [param stands]. Sorted with [method Cells.less].
static func fringe_from(stands: Array, unit, board) -> Array[Vector3i]:
	var hit := attack_set_from(stands, unit, board)
	for s in stands:
		hit.erase(s)
	var out: Array[Vector3i] = []
	for c in hit.keys():
		out.append(c)
	out.sort_custom(Cells.less)
	return out


## Union of the attack cells of every unit in [param units] (the DANGER ZONE when
## given all hostile units). Sorted with [method Cells.less].
static func combined_threat(units: Array, board) -> Array[Vector3i]:
	board = BoardSnapshot.of(board)  # index occupancy once for the whole army
	var hit := {}
	for u in units:
		if u == null or not _alive(u):
			continue
		for c in unit_threat(u, board)["attack"]:
			hit[c] = true
	var out: Array[Vector3i] = []
	for c in hit.keys():
		out.append(c)
	out.sort_custom(Cells.less)
	return out


## Living units on [param board] for which [param is_hostile](unit) is true. Used to
## pick the danger-zone units (e.g. "not owned by the local human player").
static func hostile_units(board, is_hostile: Callable) -> Array:
	var out: Array = []
	if board == null or not board.has_method("all_units"):
		return out
	for u in board.all_units():
		if u != null and _alive(u) and bool(is_hostile.call(u)):
			out.append(u)
	return out


# --- helpers -------------------------------------------------------------------

## Aim candidates on floor [param f] within [param r] of [param stand]. Cheap
## shortcuts for the multi-floor cases: melee only crosses floors over a link, and a
## sparse upper floor (a bridge) is enumerated from its few present cells rather than
## by sweeping a whole diamond of mostly air.
static func _candidates(stand: Vector3i, f: int, r: int, pattern: TargetingPattern, board) -> Array:
	var out: Array = []
	if f != stand.z and pattern.is_melee():
		if board != null and board.has_method("links_from"):
			for e in board.links_from(stand):
				var to: Vector3i = e["to"]
				if to.z == f:
					out.append(to)
		return out
	if f > 0 and board != null and board.has_method("cells_on_floor"):
		var present: Array = board.cells_on_floor(f)
		if present.size() < (2 * r + 1) * (r + 1):
			for c in present:
				if absi(c.x - stand.x) + absi(c.y - stand.y) <= r:
					out.append(c)
			return out
	for dx in range(-r, r + 1):
		var span: int = r - absi(dx)
		for dy in range(-span, span + 1):
			out.append(Vector3i(stand.x + dx, stand.y + dy, f))
	return out


static func _aimable(board, cell: Vector3i) -> bool:
	if board == null:
		return true
	if board.has_method("in_bounds") and not bool(board.in_bounds(cell)):
		return false
	if cell.z > 0 and board.has_method("has_tile") and not bool(board.has_tile(cell)):
		return false
	return true


static func _linked_melee(pattern: TargetingPattern, stand: Vector3i, aim: Vector3i, board) -> bool:
	return pattern.is_melee() and stand.z != aim.z and board != null \
		and board.has_method("are_linked") and bool(board.are_linked(stand, aim))


static func _floor_count(board) -> int:
	if board != null and board.has_method("floor_count"):
		return maxi(1, int(board.floor_count()))
	return 1


static func _alive(unit) -> bool:
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	var hp = unit.get("hp")
	return hp == null or int(hp) > 0
