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

	var best := _best_attack(actor, origin, moveset, hostiles, board)
	if not best.is_empty():
		return best

	# No damaging option in range: close on the nearest enemy.
	return _step_toward_nearest(origin, hostiles, board)


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


## Best damaging move+target, or an empty dict if none can reach a hostile.
func _best_attack(actor, origin: Vector2i, moveset: Array, hostiles: Array, board) -> Dictionary:
	var best := {}
	var best_reduction := 0
	var best_estimate := 0
	var best_hp := 0
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
			var reduction := mini(estimate, maxi(0, thp))
			# Prefer the biggest HP removed; tie-break by raw damage, then by
			# hitting the weaker (lower-HP) target to secure a kill.
			if best.is_empty() \
					or reduction > best_reduction \
					or (reduction == best_reduction and estimate > best_estimate) \
					or (reduction == best_reduction and estimate == best_estimate and thp < best_hp):
				best_reduction = reduction
				best_estimate = estimate
				best_hp = thp
				best = {
					"action": ActionType.MOVE,
					"move": move,
					"target": target,
					"aim_cell": tcell,
					"estimated_damage": estimate,
					"step_to": origin,
					"reason": "attack_best_target",
				}
	return best


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
