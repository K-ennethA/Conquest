extends BotController
class_name BossController

## A boss variant of [BotController] with two extra behaviours:
##
## 1. Faction-agnostic hostility -- a boss treats [b]every[/b] non-boss unit as a
##    target, so a "map boss" attacks whichever player unit it can hurt most,
##    regardless of teams. Overrides [method BotController._is_hostile].
## 2. Phases -- as the boss loses HP it advances through [member phase_thresholds]
##    and unlocks the extra "special" moves in [member phase_special_moves], which
##    are folded into its moveset when planning.
##
## It reuses the base planner for actual target/damage selection.

## HP ratios (0..1, descending) at which the boss advances to the next phase.
## e.g. [0.66, 0.33] -> phase 1 at <=66% HP, phase 2 at <=33% HP.
var phase_thresholds: Array = []
## Extra moves unlocked per phase index: phase_special_moves[i] is an Array of
## [MoveResource] added once the boss has reached phase i (phase 0 = opening kit).
var phase_special_moves: Array = []
## Highest phase reached so far. Monotonic -- a boss never de-phases when healed.
var current_phase: int = 0


func decide(actor, moveset: Array, board) -> Dictionary:
	_advance_phase(actor)
	return super.decide(actor, _effective_moveset(moveset), board)


## Movement-aware planning (see [method BotController.plan]) with the same phase
## advance + expanded moveset a boss uses for [method decide], so a boss also uses
## its FULL move range and unlocked specials when closing on / striking a target.
func plan(actor, moveset: Array, board, reachable: Array) -> Dictionary:
	_advance_phase(actor)
	var full := _effective_moveset(moveset)
	# LANE PRE-EMPTION: an anchored boss's answer to a kiter. Before the generic
	# planner (which values only DamageEffect moves and would score a hazard at 0),
	# fire a ready lane hazard at a hostile already aligned in a cardinal line within
	# range. Only ever pre-empts when such a hostile really exists and the move is
	# ready; otherwise it falls straight through to the normal plan, so no ordinary
	# behaviour regresses.
	#
	# GATE (defensive boss only): a DEFENSIVE guardian holds its vine until a hostile is
	# actually within its aggro range -- it must not snipe distant enemies with a range-6
	# lane the instant one drifts into alignment. Once something is in range it unleashes
	# the vine down the full lane as before. An aggressive boss keeps the always-on
	# anti-kite pre-emption. (A mock that doesn't report a stance is not "defensive", so
	# this gate is a no-op in unit tests.)
	var fire_lane: bool = true
	if _is_defensive(actor):
		var origin: Vector2i = board.cell_of(actor) if (board != null and board.has_method("cell_of")) else Vector2i.ZERO
		var home: Vector2i = _effective_home(actor, origin)
		fire_lane = _hostile_within_aggro(actor, home, _list_hostiles(actor, board), board)
	if fire_lane:
		var lane := _hazard_lane_plan(actor, full, board)
		if not lane.is_empty():
			return lane
	return super.plan(actor, full, board, reachable)


## Bosses are hostile to anything that is not itself and not another boss.
func _is_hostile(actor, other, _board) -> bool:
	return other != actor and not _unit_is_boss(other)


## Recompute [member current_phase] from the boss's current HP ratio (monotonic).
func _advance_phase(actor) -> int:
	var max_hp := maxi(1, _actor_stat(actor, "health"))
	var ratio := float(_unit_hp(actor)) / float(max_hp)
	var reached := 0
	for threshold in phase_thresholds:
		if ratio <= float(threshold):
			reached += 1
	current_phase = maxi(current_phase, reached)
	return current_phase


## A ready lane-hazard cast at an aligned hostile, or {} to fall through to the
## normal planner. GENERAL (not keyed to "forest_barrage"): it fires ANY off-cooldown
## move whose effects include a [SpawnHazardEffect] when a hostile lies in a cardinal
## line from the boss (same row or column) within that move's max range -- so
## [method TargetingPattern._cardinal_dir] aimed at it sweeps a lane straight through
## it. The nearest such hostile is chosen (a kiter the boss cannot otherwise reach is
## exactly who this punishes). Casting doesn't move the boss, so the leash is
## irrelevant; it never moves to line up, only fires when ALREADY aligned.
func _hazard_lane_plan(actor, moveset: Array, board) -> Dictionary:
	if actor == null or board == null or not board.has_method("cell_of"):
		return {}
	var origin: Vector2i = board.cell_of(actor)
	var hostiles := _list_hostiles(actor, board)
	if hostiles.is_empty():
		return {}

	for move in moveset:
		# MODE-AWARE: the pattern/effects in force for THIS boss (single-mode moves
		# resolve to their one pattern/effect list, so nothing else changes).
		if move == null or move.targeting_for(actor) == null or not _move_has_hazard(move, actor):
			continue
		if not _move_is_ready(actor, move):
			continue
		var max_range: int = move.effective_max_range(actor)
		var best_target = null
		var best_dist: int = 1 << 30
		for h in hostiles:
			var hc: Vector2i = board.cell_of(h)
			if not _is_cardinally_aligned(origin, hc):
				continue
			var d := _manhattan(origin, hc)
			# Reserve the lane for a KITER: distance >= 2 (beyond melee reach). An
			# adjacent aligned foe is left to the boss's normal kit (bough_sweep /
			# timberfall) so this pre-emption never displaces its melee identity -- it
			# only fires at the ranged threat the anchored boss otherwise cannot answer.
			# The lane still sweeps its full travel_range, so aiming at the nearest
			# qualifying kiter also carries through anything farther down the same lane.
			if d < 2 or d > max_range:
				continue
			if d < best_dist:
				best_dist = d
				best_target = h
		if best_target == null:
			continue
		var tcell: Vector2i = board.cell_of(best_target)
		return {
			"action": ActionType.MOVE,
			"move": move,
			"target": best_target,
			"aim_cell": tcell,
			"dest_cell": origin,
			"estimated_damage": 0,
			"target_hp": _unit_hp(best_target),
			"step_to": origin,
			"reason": "hazard_lane",
		}
	return {}


## True if [param move]'s effects include a [SpawnHazardEffect] (a lane hazard).
## [param actor] selects the move's active MODE (a single-mode move ignores it).
func _move_has_hazard(move, actor = null) -> bool:
	for e in move.effects_for(actor):
		if e is SpawnHazardEffect:
			return true
	return false


## Cooldown/charge readiness, duck-typed off the actor's MovesetController. An actor
## that predates the moveset system (a bare mock) reports ready -- harmless, because
## _move_has_hazard has already filtered the moveset to hazard moves such an actor
## does not carry in practice.
func _move_is_ready(actor, move) -> bool:
	if actor != null and actor.has_method("get_moveset_controller"):
		var mc = actor.get_moveset_controller()
		if mc != null and mc.has_method("can_use"):
			return bool(mc.can_use(move))
	return true


## Same row or column as [param a], and not the same cell -- the alignment under
## which a cardinal aim sweeps a lane through [param b].
static func _is_cardinally_aligned(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return false
	return a.x == b.x or a.y == b.y


## Base moveset plus every special move unlocked up to [member current_phase].
func _effective_moveset(base_moveset: Array) -> Array:
	var out: Array = []
	out.append_array(base_moveset)
	for i in range(mini(current_phase + 1, phase_special_moves.size())):
		var extra = phase_special_moves[i]
		if extra is Array:
			out.append_array(extra)
	return out
