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
func _is_hostile(actor, other, board) -> bool:
	if other == actor:
		return false
	if board.has_method("are_enemies"):
		return board.are_enemies(actor, other)
	return false


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
			var tcell: Vector2i = board.cell_of(target)
			if not move.can_aim_at(origin, tcell):
				continue
			var estimate := _estimate_damage(move, actor, target)
			if estimate <= 0:
				continue
			var thp := _unit_hp(target)
			candidates.append({
				"action": ActionType.MOVE,
				"move": move,
				"target": target,
				"aim_cell": tcell,
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
