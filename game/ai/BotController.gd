extends RefCounted
class_name BotController

## Turn-planner for an AI-controlled unit. Given an acting unit, its moveset, and
## a board-query adapter, it returns a structured [i]decision[/i] describing what
## the unit should do this turn. It never touches the scene tree, so it is fully
## testable with mock units and a mock board.
##
## Strategy: pick the damaging move + target that removes the most enemy HP; if
## nothing damaging can reach an enemy, step one cell toward the nearest enemy;
## if there are no enemies at all, wait.
##
## Expected board-query interface (a superset of [MoveContext]'s board):
##   cell_of(unit) -> Vector2i
##   units_at(cell: Vector2i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   all_units() -> Array          ## every unit in play (used to find targets)
## Units are duck-typed like the combat system's: get_stat(name), take_damage(n),
## and (for planning) a readable `hp` / get_hp(). A boss unit may expose `is_boss`.

## The kind of action a decision represents.
enum ActionType {
	MOVE,  ## use `move` aimed at `aim_cell` against `target`
	STEP,  ## walk toward `step_to`
	WAIT,  ## do nothing this turn
}

## How sharply the AI plays. Higher tiers target better, secure kills, and never
## hesitate; EASY deliberately dithers and misplays so it is beatable.
enum Difficulty {
	EASY,    ## dithers: often skips its attack, mis-targets, hesitates to advance
	NORMAL,  ## greedy best-damage (the baseline strategy)
	HARD,    ## NORMAL + secures guaranteed kills when reachable
	BRUTAL,  ## HARD + focus-fires the weakest enemy and never hesitates
}

## Which tier this planner plays at. Set by the driver from the game settings.
var difficulty: int = Difficulty.NORMAL

## RNG used only by EASY's dithering/mis-targeting. Injectable so tests stay
## deterministic; created (and randomized) lazily on first EASY use, so NORMAL /
## HARD / BRUTAL never touch it and remain fully deterministic.
var rng: RandomNumberGenerator = null

## When set, allegiance is INVERTED: the actor's own ALLIES are treated as its
## hostiles, so the ordinary planner turns it on its own side. This is how a hijacked
## (mind-controlled) unit is force-driven -- the caller sets it before plan()/decide().
## It is ALSO inverted whenever the actor itself reports is_controlled() (so a live
## controlled unit inverts with no external flag), but the explicit field lets the turn
## system drive the inversion by the latched control state even after the 1-turn
## Enthralled status has already ticked away. Off (the default) is byte-for-byte the
## historical behaviour.
var force_control: bool = false


## Human-readable name for a [enum Difficulty] value (UI / logs).
static func difficulty_name(d: int) -> String:
	match d:
		Difficulty.EASY: return "Easy"
		Difficulty.HARD: return "Hard"
		Difficulty.BRUTAL: return "Brutal"
		_: return "Normal"


## Plan this unit's turn. [param moveset] is an Array of [MoveResource].
## Returns a decision dictionary with keys: "action" ([enum ActionType]), "move",
## "target", "aim_cell", "estimated_damage", "step_to", "reason".
func decide(actor, moveset: Array, board) -> Dictionary:
	if actor == null or board == null or not board.has_method("cell_of"):
		return _wait("no_actor_or_board")

	var origin: Vector2i = board.cell_of(actor)
	var hostiles := _list_hostiles(actor, board)
	if hostiles.is_empty():
		return _wait("no_hostiles")

	# All reachable damaging plays this turn, best-first (index 0 == the greedy
	# pick NORMAL has always made). Difficulty decides which of them we take.
	var ranked := _ranked_attacks(actor, origin, moveset, hostiles, board)
	var choice := _choose_attack(ranked)
	if not choice.is_empty():
		return choice

	# No attack taken (none in range, or EASY chose to hold). Advance -- unless
	# EASY hesitates this turn, in which case do nothing.
	if difficulty == Difficulty.EASY and _get_rng().randf() < 0.30:
		return _wait("hesitate")
	return _step_toward_nearest(origin, hostiles, board)


## Plan a FULL-movement turn using the set of cells the unit can actually reach
## this turn ([param reachable], computed by [MovementResolver] against the live
## board). Where [method decide] only ever considers the unit's current cell and
## takes a single step, this walks the unit up to an enemy and strikes the SAME
## turn -- Fire-Emblem-style enemy behaviour:
##
##   1. MOVE-THEN-ATTACK -- over every candidate stand cell (the origin plus each
##      reachable cell) find the (dest_cell, move, target) that does the most good;
##      the move must legally hit the target FROM that stand cell
##      ([method MoveResource.can_aim_at]). The difficulty tiers pick among the
##      ranked options exactly as [method decide] does (so HARD still secures kills,
##      BRUTAL still focus-fires, EASY still dithers, NORMAL stays deterministic).
##   2. FULL ADVANCE -- if no attack is reachable from ANY cell, move to the
##      reachable cell that minimizes distance to the nearest enemy, closing the
##      unit's whole move range rather than a single cell.
##   3. WAIT -- only when there are no hostiles, or nothing gets the unit closer.
##
## The returned dictionary is [method decide]'s shape plus a "dest_cell" key (the
## cell to stand on before acting):
##   action MOVE -> walk to dest_cell (may equal the origin), then use `move` at
##                  `aim_cell`.
##   action STEP -> walk to dest_cell (a full advance; no attack this turn).
##   action WAIT -> do nothing.
## [param reachable] is an Array of [Vector2i] (empty is valid -- planning then only
## considers the origin cell, matching a unit with no movement profile).
func plan(actor, moveset: Array, board, reachable: Array) -> Dictionary:
	if actor == null or board == null or not board.has_method("cell_of"):
		return _wait("no_actor_or_board")

	var origin: Vector2i = board.cell_of(actor)
	var hostiles := _list_hostiles(actor, board)
	if hostiles.is_empty():
		return _wait("no_hostiles")

	# STANCE + LEASH. Every unit's effective home is its authored guard post if it
	# has one, otherwise the cell it currently stands on (units spawned outside the
	# map loader -- e.g. tests -- have no home). An untethered aggressive unit reads
	# home == origin, an infinite leash, and an aggressive stance, so every branch
	# below collapses to the historical attack-then-advance-full behaviour.
	var home: Vector2i = _effective_home(actor, origin)

	# LEASH FILTER on movement destinations: an anchored unit may only stop on cells
	# within its leash radius of home. Untethered -> the reachable set is returned
	# untouched. `origin` is always a legal stop (a unit already home is never
	# stranded, even if a shrunk leash would exclude its own cell on an edge case).
	var leashed_reachable: Array = _leash_filter(actor, home, reachable)

	# Candidate stand cells: the origin (attack without moving) plus every leashed
	# cell the unit can reach this turn. Reachable cells are already legal stops.
	var stand_cells: Array = [origin]
	stand_cells.append_array(leashed_reachable)

	# ATTACK BRANCH (runs for EVERY stance): all reachable damaging plays, best-first
	# (one per move+target, standing on the cheapest leashed cell that can hit it).
	# A defensive turret still strikes anything reachable from a leashed stand cell.
	# Difficulty decides which we take -- identical selection logic to decide()'s.
	var ranked := _ranked_attacks_from_cells(actor, origin, stand_cells, moveset, hostiles, board, home)
	var choice := _choose_attack(ranked)

	# SUPPORT BRANCH (damage-first). A unit's non-damage kit -- self-buffs, heals,
	# pure debuffs -- is invisible to the attack ranking above (every such move
	# estimates 0 damage), so without this branch Eldroot would never pop Heartwood
	# Guard and a healer would never heal. Here we classify each USABLE support move
	# and, ONLY when no lethal / clearly-strong attack is on the table this turn (see
	# _support_beats_attack), take the best-triggered one instead.
	#
	# Skipped entirely for a force-driven / mind-controlled actor: it must keep
	# attacking its own side (never "support" itself). The cast is resolved IN PLACE
	# (dest_cell == origin), so a self / ally cast is unaffected by the leash. A unit
	# whose kit is purely damaging produces no support candidate, so this branch is a
	# no-op and the historical attack-then-advance behaviour is byte-for-byte intact.
	if not _actor_is_controlled(actor):
		var support := _best_support_play(actor, origin, moveset, hostiles, board)
		if not support.is_empty() and _support_beats_attack(support, ranked, actor):
			return support

	if not choice.is_empty():
		return choice

	# No attack (none reachable, or EASY declined). EASY may still hesitate.
	if difficulty == Difficulty.EASY and _get_rng().randf() < 0.30:
		return _wait("hesitate")

	# ADVANCE BRANCH. A DEFENSIVE unit only wakes (advances) when a hostile has come
	# within its aggro range of home; otherwise it holds. aggro_range 0 therefore
	# never chases -- such a unit only ever acts through the attack branch above.
	if _is_defensive(actor) and not _hostile_within_aggro(actor, home, hostiles, board):
		return _wait("holding")

	# Advance the full distance toward the nearest hostile, but only onto leashed
	# cells (unchanged from the historical advance when the unit is untethered).
	return _advance_full(origin, hostiles, board, leashed_reachable)


## Lazily-created RNG for EASY's stochastic behaviour.
func _get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng


## Pick which of the ranked attacks (best-first) to actually take, per difficulty.
## Returns {} to decline attacking (advance/hesitate instead).
func _choose_attack(ranked: Array) -> Dictionary:
	if ranked.is_empty():
		return {}
	match difficulty:
		Difficulty.EASY:
			# Dither: sometimes skip a clear attack, sometimes hit the wrong target.
			var roll := _get_rng().randf()
			if roll < 0.35:
				return {}  # squanders the opening
			if roll < 0.65 and ranked.size() > 1:
				return ranked[_get_rng().randi_range(0, ranked.size() - 1)]
			return ranked[0]
		Difficulty.HARD:
			return _first_kill_or_best(ranked)
		Difficulty.BRUTAL:
			# Secure a kill if possible; otherwise focus-fire the weakest enemy to
			# set one up next turn (rather than chipping the highest-HP target).
			var kill := _first_kill_or_best(ranked, true)
			if not kill.is_empty() and bool(kill.get("_is_kill", false)):
				return kill
			return _focus_weakest(ranked)
		_:  # NORMAL
			return ranked[0]


## First candidate that outright kills its target (estimate >= target HP), or the
## best-damage candidate if none can. When [param tag] is true the returned dict
## carries "_is_kill" so BRUTAL can tell a secured kill from a fallback.
func _first_kill_or_best(ranked: Array, tag: bool = false) -> Dictionary:
	for c in ranked:
		if int(c.get("estimated_damage", 0)) >= int(c.get("target_hp", 1 << 30)):
			if tag:
				c = c.duplicate()
				c["_is_kill"] = true
			return c
	return ranked[0]


## Candidate hitting the lowest-current-HP target (tie-break: more damage).
func _focus_weakest(ranked: Array) -> Dictionary:
	var best: Dictionary = ranked[0]
	for c in ranked:
		var chp := int(c.get("target_hp", 1 << 30))
		var bhp := int(best.get("target_hp", 1 << 30))
		if chp < bhp or (chp == bhp and int(c.get("estimated_damage", 0)) > int(best.get("estimated_damage", 0))):
			best = c
	return best


# --- Target selection ------------------------------------------------------

## Every unit currently considered hostile to [param actor].
func _list_hostiles(actor, board) -> Array:
	var out: Array = []
	for u in _all_units(board):
		if u != actor and _is_hostile(actor, u, board):
			out.append(u)
	return out


## Hostility test. Base rule: whatever the board reports as an enemy.
## Overridden by [BossController] for faction-agnostic aggression.
##
## INVERTED while the actor is mind-controlled ([method _actor_is_controlled]): its own
## ALLIES become its targets, so the unchanged planner drives it to attack its own side.
## A non-controlled actor takes the historical enemy branch, byte for byte.
func _is_hostile(actor, other, board) -> bool:
	if other == actor:
		return false
	if _actor_is_controlled(actor):
		if board.has_method("are_allies"):
			return board.are_allies(actor, other)
		return false
	if board.has_method("are_enemies"):
		return board.are_enemies(actor, other)
	return false


## True while [param actor] should target its own side: either the caller set
## [member force_control], or the actor itself reports [method Unit.is_controlled].
## Duck-typed and null-safe, so a bare mock without is_controlled() is never controlled.
func _actor_is_controlled(actor) -> bool:
	if force_control:
		return true
	return actor != null and actor.has_method("is_controlled") and bool(actor.is_controlled())


## Every reachable damaging move+target this turn, sorted best-first. Element 0 is
## the greedy pick NORMAL has always made; higher difficulties may choose others.
## Ranking (matches the historical tie-break): most HP removed, then most raw
## damage, then the lower-HP target (so a kill is secured on ties).
func _ranked_attacks(actor, origin: Vector2i, moveset: Array, hostiles: Array, board) -> Array:
	var candidates: Array = []
	for move in moveset:
		if move == null or move.targeting == null or not _move_has_damage(move):
			continue
		for target in hostiles:
			# The AIM cell for this move against the target. An ordinary move aims at
			# the target's OWN cell (historical); a POSITIONAL move (a leap) aims at
			# an empty LANDING cell beside it instead -- see _resolve_aim. The actor
			# casts from its current cell here (decide() takes no movement), and this
			# path has no leash model, so home == origin.
			var aim_res := _resolve_aim(move, actor, origin, target, board, origin)
			if not bool(aim_res["found"]):
				continue
			var aim_cell: Vector2i = aim_res["aim"]
			var estimate := _estimate_damage(move, actor, target)
			if estimate <= 0:
				continue
			var thp := _unit_hp(target)
			candidates.append({
				"action": ActionType.MOVE,
				"move": move,
				"target": target,
				"aim_cell": aim_cell,
				"estimated_damage": estimate,
				"target_hp": thp,
				"reduction": mini(estimate, maxi(0, thp)),
				"step_to": origin,
				"reason": "attack_best_target",
			})
	candidates.sort_custom(_attack_is_better)
	return candidates


## Strict "a ranks before b" comparator for [method _ranked_attacks].
func _attack_is_better(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a["reduction"]); var rb := int(b["reduction"])
	if ra != rb:
		return ra > rb
	var ea := int(a["estimated_damage"]); var eb := int(b["estimated_damage"])
	if ea != eb:
		return ea > eb
	return int(a["target_hp"]) < int(b["target_hp"])


## Every reachable damaging play this turn, best-first, for the movement-aware
## [method plan]. For each move+target that can be hit from at least one candidate
## stand cell, keeps ONLY the single cheapest such cell (least movement, then lowest
## cell coord) and records it as "dest_cell". Collapsing to one entry per move+target
## keeps the ranked list -- and therefore [method _choose_attack] / HARD / BRUTAL --
## behaving exactly as they do for the origin-only [method _ranked_attacks].
func _ranked_attacks_from_cells(actor, origin: Vector2i, stand_cells: Array, moveset: Array, hostiles: Array, board, home: Vector2i) -> Array:
	var best_by_key := {}  # "move_id:target_id" -> best candidate for that pairing
	for move in moveset:
		if move == null or move.targeting == null or not _move_has_damage(move):
			continue
		var positional: bool = _is_positional_move(move)
		for target in hostiles:
			var tcell: Vector2i = board.cell_of(target)
			# Cheapest stand cell (least movement) that can legally hit this target,
			# plus the AIM cell to use from there.
			var dest_cell := origin
			var dest_cost := 1 << 30
			var aim_cell := tcell
			var found := false
			if positional:
				# A leap is cast from the actor's CURRENT cell (it does not walk
				# first), so the stand cell is fixed at the origin and the aim is a
				# valid empty LANDING cell beside the target, chosen by _resolve_aim
				# and already leash-checked against home. dest_cell == origin makes the
				# executor relocate NOTHING before the leap (no double-move): the
				# LeapEffect itself moves the caster onto the aimed landing cell.
				var aim_res := _resolve_aim(move, actor, origin, target, board, home)
				if bool(aim_res["found"]):
					dest_cell = origin
					dest_cost = 0
					aim_cell = aim_res["aim"]
					found = true
			else:
				for c in stand_cells:
					# Board-aware, exactly as in _ranked_attacks above.
					if not move.can_target(c, tcell, actor, board):
						continue
					var cost := _manhattan(origin, c)
					if not found or cost < dest_cost or (cost == dest_cost and _cell_less(c, dest_cell)):
						dest_cost = cost
						dest_cell = c
						found = true
			if not found:
				continue
			var estimate := _estimate_damage(move, actor, target)
			if estimate <= 0:
				continue
			var thp := _unit_hp(target)
			var key := "%d:%d" % [move.get_instance_id(), target.get_instance_id()]
			best_by_key[key] = {
				"action": ActionType.MOVE,
				"move": move,
				"target": target,
				"aim_cell": aim_cell,
				"dest_cell": dest_cell,
				"estimated_damage": estimate,
				"target_hp": thp,
				"reduction": mini(estimate, maxi(0, thp)),
				"move_cost": dest_cost,
				"step_to": dest_cell,
				"reason": "move_then_attack",
			}
	var candidates: Array = best_by_key.values()
	candidates.sort_custom(_attack_from_cells_is_better)
	return candidates


## Strict "a ranks before b" comparator for [method _ranked_attacks_from_cells].
## Same primary ordering as [method _attack_is_better] (most HP removed, then most
## raw damage, then lower-HP target) with deterministic tie-breaks (least movement,
## then cell order) so NORMAL's pick is stable regardless of dictionary iteration.
func _attack_from_cells_is_better(a: Dictionary, b: Dictionary) -> bool:
	var ra := int(a["reduction"]); var rb := int(b["reduction"])
	if ra != rb:
		return ra > rb
	var ea := int(a["estimated_damage"]); var eb := int(b["estimated_damage"])
	if ea != eb:
		return ea > eb
	var ta := int(a["target_hp"]); var tb := int(b["target_hp"])
	if ta != tb:
		return ta < tb
	var ca := int(a["move_cost"]); var cb := int(b["move_cost"])
	if ca != cb:
		return ca < cb
	return _cell_less(a["dest_cell"], b["dest_cell"])


## Advance as far as possible toward the nearest hostile: choose the reachable cell
## that minimizes distance to that enemy (closing the unit's whole move range, not a
## single cell). Returns WAIT only when no reachable cell gets the unit closer.
func _advance_full(origin: Vector2i, hostiles: Array, board, reachable: Array) -> Dictionary:
	var nearest = null
	var best_dist := 1 << 30
	for target in hostiles:
		var d := _manhattan(origin, board.cell_of(target))
		if d < best_dist:
			best_dist = d
			nearest = target
	if nearest == null:
		return _wait("no_hostiles")

	var goal: Vector2i = board.cell_of(nearest)
	var dest := origin
	var dest_dist := _manhattan(origin, goal)
	for c in reachable:
		var d := _manhattan(c, goal)
		if d < dest_dist:
			dest_dist = d
			dest = c
		elif d == dest_dist and dest != origin and _cell_less(c, dest):
			dest = c
	if dest == origin:
		# Nothing reachable gets us closer (blocked in, or an empty reachable set).
		return _wait("no_progress")
	return {
		"action": ActionType.STEP,
		"move": null,
		"target": nearest,
		"aim_cell": origin,
		"dest_cell": dest,
		"estimated_damage": 0,
		"target_hp": _unit_hp(nearest),
		"step_to": dest,
		"reason": "advance_full",
	}


## Non-mutating estimate of the damage [param move] would deal to [param target].
## Mirrors [DamageEffect]'s scaling + mitigation so planning matches execution.
func _estimate_damage(move: MoveResource, actor, target) -> int:
	var total := 0
	for effect in move.effects:
		if effect is DamageEffect:
			var bonus := 0
			if effect.scaling_stat != "":
				bonus = int(round(_actor_stat(actor, effect.scaling_stat) * effect.scale))
			var raw: int = effect.power + bonus
			total += _mitigate(raw, target, effect.category)
	return total


func _move_has_damage(move: MoveResource) -> bool:
	for effect in move.effects:
		if effect is DamageEffect:
			return true
	return false


# --- Aim resolution (ordinary target-cell vs positional landing-cell) -------

## True when [param move] is a POSITIONAL move -- one whose targeting requires an
## empty LANDING cell (a leap / dash), so its aim is a free tile the caster relocates
## to, NOT the target's own occupied cell. Detected purely by the targeting data
## (never by move id), so any move authored with requires_empty_cell is handled.
func _is_positional_move(move: MoveResource) -> bool:
	return move.targeting != null and move.targeting.requires_empty_cell


## The AIM cell [param move] should use against [param target] when cast from
## [param cast_cell], plus whether any legal aim exists: { "found": bool, "aim": Vector2i }.
##
## ORDINARY move -> aims at the target's OWN cell, gated by [method MoveResource.can_target]
## exactly as before (byte-for-byte: same call, same aim). A pattern with no board
## constraints resolves here identically to the historical behaviour.
##
## POSITIONAL move (a leap) -> aims at an empty LANDING cell beside the target. The
## candidates are the four cells orthogonally adjacent to the target; each is validated
## through the SAME [method MoveResource.can_target] (range from cast_cell + the
## pattern's requires_empty_cell / requires_adjacent_enemy board constraints), so the
## AI reuses TargetingPattern's own legality rules rather than reimplementing them. A
## leashed actor additionally rejects any landing beyond its leash of [param home].
## Among the legal landings the best is the closest to the caster (fewest leap steps),
## tie-broken by deterministic cell order.
func _resolve_aim(move: MoveResource, actor, cast_cell: Vector2i, target, board, home: Vector2i) -> Dictionary:
	var tcell: Vector2i = board.cell_of(target)
	if not _is_positional_move(move):
		if move.can_target(cast_cell, tcell, actor, board):
			return { "found": true, "aim": tcell }
		return { "found": false, "aim": tcell }
	var best := Vector2i.ZERO
	var best_cost := 1 << 30
	var found := false
	for step in TargetingPattern.ORTHOGONAL_STEPS:
		var landing: Vector2i = tcell + step
		if not move.can_target(cast_cell, landing, actor, board):
			continue
		if not _within_leash(actor, home, landing):
			continue
		var cost := _manhattan(cast_cell, landing)
		if not found or cost < best_cost or (cost == best_cost and _cell_less(landing, best)):
			best = landing
			best_cost = cost
			found = true
	return { "found": found, "aim": best }


## True when [param cell] is a legal stopping point for [param actor] under its leash:
## untethered actors accept every cell (so the untethered leap path is unconstrained),
## a leashed actor only a cell within its leash radius of [param home]. Mirrors
## [method _leash_filter]'s rule for a single cell so a leap's landing obeys the same
## tether as an ordinary advance.
func _within_leash(actor, home: Vector2i, cell: Vector2i) -> bool:
	if not _has_leash(actor):
		return true
	return _manhattan(cell, home) <= _leash_radius(actor)


# --- Stance + leash (movement-aware planning only) -------------------------
# All duck-typed and guarded: an actor that predates the AI-behaviour contract
# (a bare mock, or a legacy unit) reports aggressive + untethered, so plan()'s
# stance/leash branches are no-ops and its behaviour is byte-for-byte the old
# attack-then-advance-full path.

## This actor's effective guard-post cell: its authored home if it has one, else
## the cell it currently stands on ([param origin]).
func _effective_home(actor, origin: Vector2i) -> Vector2i:
	if actor != null and actor.has_method("has_home_cell") and actor.has_home_cell() \
			and actor.has_method("get_home_cell"):
		return actor.get_home_cell()
	return origin


## True only when the actor explicitly reports a defensive stance.
func _is_defensive(actor) -> bool:
	return actor != null and actor.has_method("is_defensive") and actor.is_defensive()


## True only when the actor reports a finite leash (an anchored / guarding unit).
func _has_leash(actor) -> bool:
	return actor != null and actor.has_method("has_leash") and actor.has_leash()


## The actor's leash radius (Manhattan cells from home). Meaningful only when
## [method _has_leash] is true.
func _leash_radius(actor) -> int:
	if actor != null and actor.has_method("get_leash_radius"):
		return int(actor.get_leash_radius())
	return -1


## The actor's defensive wake distance (Manhattan cells from home). 0 for a pure
## turret that never chases.
func _aggro_range(actor) -> int:
	if actor != null and actor.has_method("get_aggro_range"):
		return int(actor.get_aggro_range())
	return 0


## Restrict [param cells] to those within the actor's leash radius of [param home].
## Untethered actors get the SAME array back untouched (so the untethered path is
## unchanged). `origin` is not filtered here -- plan() always keeps it as a legal
## stand cell and as _advance_full's stay-put fallback.
func _leash_filter(actor, home: Vector2i, cells: Array) -> Array:
	if not _has_leash(actor):
		return cells
	var radius: int = _leash_radius(actor)
	var out: Array = []
	for c in cells:
		if _manhattan(c, home) <= radius:
			out.append(c)
	return out


## True when any hostile has come within the actor's aggro range of [param home]
## -- the wake condition for a defensive unit to leave its post and engage.
func _hostile_within_aggro(actor, home: Vector2i, hostiles: Array, board) -> bool:
	var radius: int = _aggro_range(actor)
	for h in hostiles:
		if _manhattan(home, board.cell_of(h)) <= radius:
			return true
	return false


# --- Support moves (self-buff / heal / debuff) -----------------------------
# Non-damage plays the attack ranking cannot see (they estimate 0 damage). All
# duck-typed and null-safe so a bare mock without a moveset controller / status API
# still classifies purely off the MoveResource's effects + targeting data (never a
# hardcoded move id). See plan()'s SUPPORT BRANCH for how these gate against the
# damage-first bias.

## HP fraction (0..1) at or below which a heal target counts as "hurt enough".
const HEAL_THRESHOLD: float = 0.60
## Manhattan cells within which a hostile is treated as an immediate threat -- close
## enough to strike the actor this turn -- the wake condition for a defensive buff.
const THREAT_RANGE: int = 2
## Baseline scores used to rank support candidates against one another (a heal is
## ranked by the raw HP it would restore instead, which is naturally larger).
const SUPPORT_SELF_BUFF_VALUE: int = 8
const SUPPORT_DEBUFF_VALUE: int = 5


## Best non-damage support cast for [param actor] this turn, or {} when none applies.
## Considers only USABLE (off-cooldown / in-charges) non-damage moves, classifies each
## as SELF-BUFF / HEAL / DEBUFF, and returns the highest-value TRIGGERED candidate as a
## MOVE decision cast in place (dest_cell == origin, so the executor walks the unit
## nowhere before it supports).
func _best_support_play(actor, origin: Vector2i, moveset: Array, hostiles: Array, board) -> Dictionary:
	var best: Dictionary = {}
	var best_value: int = -1
	for move in moveset:
		if move == null or move.targeting == null:
			continue
		if _move_has_damage(move):
			continue  # damaging moves are ranked by the attack branch, not here
		if not _move_is_ready(actor, move):
			continue  # cooldown / uses gate -- reuses MovesetController.can_use
		var cand: Dictionary = _classify_support(move, actor, origin, hostiles, board)
		if cand.is_empty() or not bool(cand.get("_triggered", false)):
			continue
		var value: int = int(cand.get("_value", 0))
		if best.is_empty() or value > best_value \
				or (value == best_value and _support_rank_less(cand, best)):
			best = cand
			best_value = value
	return best


## Classify [param move] and, if it applies right now, build its support decision
## (carrying the internal "_triggered" / "_value" / "_category" keys plan() reads).
## HEAL is checked first so a move that both heals and buffs is driven by its heal
## target logic; a move fitting no category returns {}.
func _classify_support(move: MoveResource, actor, origin: Vector2i, hostiles: Array, board) -> Dictionary:
	if _move_is_heal(move):
		return _heal_candidate(move, actor, origin, board)
	if _move_is_self_buff(move):
		return _self_buff_candidate(move, actor, origin, hostiles, board)
	if _move_is_debuff(move):
		return _debuff_candidate(move, actor, origin, hostiles, board)
	return {}


## SELF-BUFF (defensive) candidate -- e.g. Heartwood Guard. Triggered when a hostile
## is within [constant THREAT_RANGE] of the actor (it can be struck this turn). The
## cast aims at the actor's own cell. The damage-first gate in [method
## _support_beats_attack] supplies the "and no strong attack available" half.
func _self_buff_candidate(move: MoveResource, actor, origin: Vector2i, hostiles: Array, board) -> Dictionary:
	var threatened: bool = _is_threatened(origin, hostiles, board)
	return {
		"action": ActionType.MOVE,
		"move": move,
		"target": actor,
		"aim_cell": origin,
		"dest_cell": origin,
		"estimated_damage": 0,
		"target_hp": _unit_hp(actor),
		"step_to": origin,
		"reason": "support_self_buff",
		"_triggered": threatened,
		"_value": SUPPORT_SELF_BUFF_VALUE,
		"_category": 0,
	}


## HEAL candidate. Chooses the MOST-HURT valid target (self or ally) below
## [constant HEAL_THRESHOLD] that the move can legally reach from the origin, and is
## triggered only when such a target exists. Value scales with the HP it would restore
## so a heal competes with the fixed buff/debuff scores by how badly it is needed.
func _heal_candidate(move: MoveResource, actor, origin: Vector2i, board) -> Dictionary:
	var best_target = null
	var best_ratio: float = 2.0
	var best_missing: int = 0
	for u in _heal_targets(actor, board):
		var tcell: Vector2i = board.cell_of(u)
		if not move.can_target(origin, tcell, actor, board):
			continue
		var maxhp: int = _max_hp(u)
		var cur: int = _unit_hp(u)
		var ratio: float = float(cur) / float(maxhp)
		if ratio >= HEAL_THRESHOLD:
			continue
		if best_target == null or ratio < best_ratio:
			best_target = u
			best_ratio = ratio
			best_missing = maxi(1, maxhp - cur)
	if best_target == null:
		return {}
	return {
		"action": ActionType.MOVE,
		"move": move,
		"target": best_target,
		"aim_cell": board.cell_of(best_target),
		"dest_cell": origin,
		"estimated_damage": 0,
		"target_hp": _unit_hp(best_target),
		"step_to": origin,
		"reason": "support_heal",
		"_triggered": true,
		"_value": best_missing,
		"_category": 1,
	}


## DEBUFF candidate -- an ENEMY-targeted status / stat-down with little or no damage.
## Debuffs the highest-attack hostile the move can reach from the origin, so the turn
## blunts the biggest threat when no strong attack is available.
func _debuff_candidate(move: MoveResource, actor, origin: Vector2i, hostiles: Array, board) -> Dictionary:
	var best_target = null
	var best_threat: int = -1
	for h in hostiles:
		var hcell: Vector2i = board.cell_of(h)
		if not move.can_target(origin, hcell, actor, board):
			continue
		var threat: int = _actor_stat(h, "attack")
		if best_target == null or threat > best_threat:
			best_target = h
			best_threat = threat
	if best_target == null:
		return {}
	return {
		"action": ActionType.MOVE,
		"move": move,
		"target": best_target,
		"aim_cell": board.cell_of(best_target),
		"dest_cell": origin,
		"estimated_damage": 0,
		"target_hp": _unit_hp(best_target),
		"step_to": origin,
		"reason": "support_debuff",
		"_triggered": true,
		"_value": SUPPORT_DEBUFF_VALUE,
		"_category": 2,
	}


## The DAMAGE-FIRST comparison: may [param support] be taken instead of attacking?
## STRICT for buffs/debuffs -- they answer being UNABLE to retaliate: a SELF-BUFF or
## DEBUFF may fire ONLY when no damaging attack is reachable this turn ([param ranked]
## empty). If the actor can hit ANY enemy at all it attacks (so a full-HP unit standing
## next to a foe strikes rather than guards; an anchored boss bough-sweeps the party on
## it rather than shielding). HEAL is the single exception: a healer may save a badly
## hurt target over a NON-lethal attack -- but never over a LETHAL one (never pass up a
## kill). [param actor] is unused for buff/debuff but kept for signature symmetry.
func _support_beats_attack(support: Dictionary, ranked: Array, actor) -> bool:
	if not bool(support.get("_triggered", false)):
		return false
	if _has_lethal_attack(ranked):
		return false  # a kill is always taken, over any support
	if int(support.get("_category", 0)) == 1:  # HEAL
		return true  # already gated above from ever beating a lethal attack
	# SELF-BUFF / DEBUFF: only when there is nothing to hit this turn.
	return ranked.is_empty()


## True if any ranked attack outright kills its target this turn (the same kill test
## HARD / BRUTAL use: estimate >= target HP).
func _has_lethal_attack(ranked: Array) -> bool:
	for c in ranked:
		if int(c.get("estimated_damage", 0)) >= int(c.get("target_hp", 1 << 30)):
			return true
	return false


## A hostile is within [constant THREAT_RANGE] of [param origin] -- close enough that
## the actor is worth shielding this turn.
func _is_threatened(origin: Vector2i, hostiles: Array, board) -> bool:
	for h in hostiles:
		if _manhattan(origin, board.cell_of(h)) <= THREAT_RANGE:
			return true
	return false


## The actor plus every ally on the board -- the pool a heal may target.
func _heal_targets(actor, board) -> Array:
	var out: Array = [actor]
	for u in _all_units(board):
		if u != actor and board.has_method("are_allies") and board.are_allies(actor, u):
			out.append(u)
	return out


## Deterministic tie-break between two equally-valued support candidates: lower
## category first (heal-adjacent ordering is fixed), then lower move instance id.
func _support_rank_less(a: Dictionary, b: Dictionary) -> bool:
	var ca: int = int(a.get("_category", 9))
	var cb: int = int(b.get("_category", 9))
	if ca != cb:
		return ca < cb
	return a["move"].get_instance_id() < b["move"].get_instance_id()


## A unit's max health, floored at 1 so a ratio never divides by zero.
func _max_hp(unit) -> int:
	return maxi(1, _actor_stat(unit, "health"))


# --- Support-move classification (by effects + targeting, never by id) ------

## HEAL: any move carrying a [HealEffect] (targeting self or an ally in practice).
func _move_is_heal(move: MoveResource) -> bool:
	for e in move.effects:
		if e is HealEffect:
			return true
	return false


## SELF-BUFF / defensive: no damage, and it applies a status or positive stat modifier
## to the CASTER -- either a SELF-targeted move (Heartwood Guard) or an effect flagged
## [member ApplyStatusEffect.to_caster] on an otherwise enemy/ally move.
func _move_is_self_buff(move: MoveResource) -> bool:
	if move.targeting == null:
		return false
	var self_targeted: bool = int(move.targeting.target_kind) == CombatTypes.TargetKind.SELF
	# Untyped local so the subclass fields (to_caster / amount) are reachable -- the
	# elements are typed Array[MoveEffect], mirroring test_eldroot's classification.
	for e in move.effects:
		var fx = e
		if fx is ApplyStatusEffect and (self_targeted or fx.to_caster):
			return true
		if fx is StatModifierEffect and self_targeted and fx.amount >= 0:
			return true
	return false


## DEBUFF: an ENEMY-targeted move that applies a status or a negative stat modifier to
## its target (with no direct damage -- damaging moves are handled by the attack branch).
func _move_is_debuff(move: MoveResource) -> bool:
	if move.targeting == null:
		return false
	if int(move.targeting.target_kind) != CombatTypes.TargetKind.ENEMY:
		return false
	# Untyped local, as in _move_is_self_buff, so to_caster / amount are reachable.
	for e in move.effects:
		var fx = e
		if fx is ApplyStatusEffect and not fx.to_caster:
			return true
		if fx is StatModifierEffect and fx.amount < 0:
			return true
	return false


## Cooldown / charge readiness, duck-typed off the actor's MovesetController -- the
## SAME check the execute path ([MovesetController.can_use]) and [BossController]'s
## hazard-lane heuristic use. An actor that predates the moveset system (a bare mock)
## reports ready; support classification then rests on the move's own effect data.
func _move_is_ready(actor, move) -> bool:
	if actor != null and actor.has_method("get_moveset_controller"):
		var mc = actor.get_moveset_controller()
		if mc != null and mc.has_method("can_use"):
			return bool(mc.can_use(move))
	return true


# --- Movement --------------------------------------------------------------

func _step_toward_nearest(origin: Vector2i, hostiles: Array, board) -> Dictionary:
	var nearest = null
	var best_dist := 1 << 30
	for target in hostiles:
		var d := _manhattan(origin, board.cell_of(target))
		if d < best_dist:
			best_dist = d
			nearest = target
	if nearest == null:
		return _wait("no_hostiles")

	var step := origin + _step_dir(origin, board.cell_of(nearest))
	return {
		"action": ActionType.STEP,
		"move": null,
		"target": nearest,
		"aim_cell": origin,
		"estimated_damage": 0,
		"step_to": step,
		"reason": "advance_to_nearest",
	}


# --- Small helpers ---------------------------------------------------------

func _wait(reason: String) -> Dictionary:
	return {
		"action": ActionType.WAIT,
		"move": null,
		"target": null,
		"aim_cell": Vector2i.ZERO,
		"estimated_damage": 0,
		"step_to": Vector2i.ZERO,
		"reason": reason,
	}


func _all_units(board) -> Array:
	if board.has_method("all_units"):
		return board.all_units()
	if board.has_method("units"):
		return board.units()
	return []


static func _actor_stat(actor, stat_name: String) -> int:
	if actor != null and actor.has_method("get_stat"):
		return int(actor.get_stat(stat_name))
	return 0


static func _mitigate(raw: int, target, category) -> int:
	match category:
		CombatTypes.DamageCategory.TRUE:
			return maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			var res := _stat_or(target, "magic_defense", _stat_or(target, "defense", 0))
			return maxi(1, raw - res)
		_:  # PHYSICAL
			return maxi(1, raw - _stat_or(target, "defense", 0))


static func _stat_or(unit, stat_name: String, fallback: int) -> int:
	if unit != null and unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback


static func _unit_hp(unit) -> int:
	if unit == null:
		return 0
	if unit.has_method("get_hp"):
		return int(unit.get_hp())
	var hp = unit.get("hp")
	if hp != null:
		return int(hp)
	if unit.has_method("get_stat"):
		return int(unit.get_stat("health"))
	return 0


static func _unit_is_boss(unit) -> bool:
	if unit == null:
		return false
	if unit.has_method("is_boss"):
		return bool(unit.is_boss())
	var v = unit.get("is_boss")
	return v != null and bool(v)


static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Total order over cells (column, then row) -- a deterministic tie-break so the
## movement-aware planner picks the same cell every run on NORMAL.
static func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


## One-cell step from [param origin] toward [param goal] (dominant axis first).
static func _step_dir(origin: Vector2i, goal: Vector2i) -> Vector2i:
	var delta := goal - origin
	if delta == Vector2i.ZERO:
		return Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y) and delta.x != 0:
		return Vector2i(signi(delta.x), 0)
	if delta.y != 0:
		return Vector2i(0, signi(delta.y))
	return Vector2i(signi(delta.x), 0)
