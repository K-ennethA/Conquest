extends RefCounted
class_name DuelBrain

## The duel opponent AI (docs/design/DUEL_BATTLE.md §5). Pure: it reads the board and the
## units and returns a decision; the caller turns it into a USE_MOVE / WAIT command (so a
## replay re-applies the COMMAND and never re-runs the brain).
##
## It scores every READY move against the foe with the SHARED forecast
## ([method MoveExecutor.preview_vs] -> [method DamageMath.preview]) -- it never estimates
## damage itself (CONQUEST.md rule 9), so type matchups, abilities, weather, guards and
## invulnerability are all already in the number. Every weight is on the [DuelRuleset].
##
## Difficulty (BotController vocabulary): EASY = softmax over the scores, drawn from the
## injected seeded RNG; NORMAL = greedy. HARD / BRUTAL (1-ply lookahead) play as NORMAL until
## then. Only EASY draws RNG.
##
## PARTY DUELS: NORMAL and up also SWITCH on a bad matchup ([method consider_switch]) and pick
## the best-matched KO replacement ([method pick_replacement]); EASY never switches by choice and
## sends its bench in team order. Both are deterministic (no RNG).

const EASY := 0
const NORMAL := 1
const HARD := 2
const BRUTAL := 3

## Slot value for "nothing to do" (the caller spends the turn with a WAIT).
const NO_SLOT := -1


## Choose [param actor]'s action against [param foe] on [param board].
## Returns { slot, aim_cell, reason, score, scores: {slot: score} }.
static func decide(actor, foe, board, ruleset: DuelRuleset, difficulty: int = NORMAL,
		rng: RandomNumberGenerator = null) -> Dictionary:
	if ruleset == null:
		ruleset = DuelRuleset.load_default()
	var candidates: Array = []  # [{slot, score, reason}]
	for slot in ready_slots(actor):
		var s := score_move(actor, foe, board, slot, ruleset)
		candidates.append({"slot": slot, "score": float(s["score"]), "reason": String(s["reason"])})
	if candidates.is_empty():
		var struggle := struggle_slot(actor)
		if struggle != NO_SLOT:
			candidates.append({"slot": struggle, "score": 0.0, "reason": "struggle"})
	if candidates.is_empty():
		return {"slot": NO_SLOT, "aim_cell": _cell(board, actor), "reason": "no_move", "score": 0.0, "scores": {}}

	var scores: Dictionary = {}
	for c in candidates:
		scores[int(c["slot"])] = float(c["score"])
	var pick: Dictionary = candidates[0]
	if difficulty == EASY and rng != null and candidates.size() > 1:
		pick = _softmax_pick(candidates, ruleset.ai_easy_temperature, rng)
	else:
		for c in candidates:
			if float(c["score"]) > float(pick["score"]):
				pick = c
	var slot: int = int(pick["slot"])
	return {
		"slot": slot,
		"aim_cell": aim_for(actor, foe, board, slot),
		"reason": String(pick["reason"]),
		"score": float(pick["score"]),
		"scores": scores,
	}


# --- Party duels: switching and KO replacement --------------------------------------------
#
# A unit's MATCHUP against the foe (higher = better): its best expected hit as a fraction of the
# foe's HP, minus the foe's best expected hit on it as a fraction of its own HP. Both halves come
# off the shared forecast ([method MoveExecutor.preview_vs]), so elements, abilities, weather and
# guards are already in them -- rule 9, no damage maths here. A benched unit is parked on its
# side's station (hidden), so its forecast reads the same stage as the fielded one's.

## Matchup of [param unit] against [param foe] (see above). 0 when either is missing.
static func matchup(unit, foe, board) -> float:
	if unit == null or foe == null or not is_instance_valid(unit) or not is_instance_valid(foe):
		return 0.0
	var foe_hp: float = maxf(1.0, float(foe.get_hp()))
	var my_hp: float = maxf(1.0, float(unit.get_hp()))
	return best_expected_hit(unit, foe, board) / foe_hp - foe_threat(unit, foe, board) / my_hp


## [param unit]'s best expected hit on [param foe] with the moves it could use now (the
## struggle when nothing is ready).
static func best_expected_hit(unit, foe, board) -> float:
	var best := 0.0
	var slots := ready_slots(unit)
	if slots.is_empty():
		var s := struggle_slot(unit)
		if s != NO_SLOT:
			slots.append(s)
	for slot in slots:
		var move: MoveResource = unit.get_move(slot)
		if move == null or move.targeting_for(unit) == null:
			continue
		if move.targeting_for(unit).target_kind == CombatTypes.TargetKind.SELF or not deals_damage(move, unit):
			continue
		best = maxf(best, expected_damage(MoveExecutor.preview_vs(move, unit, foe, board)))
	return best


## Should [param actor] switch out instead of acting? Returns the bench index to bring in, or -1.
## EASY never switches voluntarily. NORMAL and up switch when the best benched matchup beats the
## fielded one by [member DuelRuleset.ai_switch_margin], the fielded unit has already had
## [member DuelRuleset.ai_switch_min_turns] turns on the field (no ping-pong), and the planned
## move ([param decision], [method decide]) is not a forecast KO. [param bench] = [{index, unit}]
## (healthy benched members); [param turns_on_field] counts the current turn. Pure and
## deterministic (no RNG).
static func consider_switch(actor, foe, board, ruleset: DuelRuleset, difficulty: int, bench: Array,
		decision: Dictionary = {}, turns_on_field: int = 99) -> int:
	if ruleset == null or difficulty == EASY or bench.is_empty() or actor == null or foe == null:
		return -1
	if String(decision.get("reason", "")) == "lethal":
		return -1
	if turns_on_field <= ruleset.ai_switch_min_turns:
		return -1
	var mine := matchup(actor, foe, board)
	var best_idx := -1
	var best := -INF
	for row in bench:
		var u = row.get("unit")
		if u == null or not is_instance_valid(u):
			continue
		var m := matchup(u, foe, board)
		if m > best:
			best = m
			best_idx = int(row.get("index", -1))
	if best_idx >= 0 and best - mine >= ruleset.ai_switch_margin:
		return best_idx
	return -1


## Who replaces a fainted combatant: EASY sends the next healthy member in team order; NORMAL
## and up the best matchup against [param foe] (ties -> team order). -1 when [param bench] is
## empty. Pure, no RNG.
static func pick_replacement(foe, board, ruleset: DuelRuleset, difficulty: int, bench: Array) -> int:
	if bench.is_empty():
		return -1
	if difficulty == EASY or foe == null or not is_instance_valid(foe):
		return int(bench[0].get("index", -1))
	var best_idx := int(bench[0].get("index", -1))
	var best := -INF
	for row in bench:
		var u = row.get("unit")
		if u == null or not is_instance_valid(u):
			continue
		var m := matchup(u, foe, board)
		if m > best:
			best = m
			best_idx = int(row.get("index", -1))
	return best_idx


## The moveset slots [param actor] may use right now (ready per its MovesetController).
static func ready_slots(actor) -> Array[int]:
	var out: Array[int] = []
	if actor == null or not actor.has_method("get_move"):
		return out
	var count: int = actor.character_resource.move_count() if "character_resource" in actor and actor.character_resource != null else 0
	var mc = actor.get_moveset_controller() if actor.has_method("get_moveset_controller") else null
	for slot in range(count):
		var move: MoveResource = actor.get_move(slot)
		if move == null or move.targeting_for(actor) == null:
			continue
		if mc != null and mc.has_method("can_use") and not mc.can_use(move):
			continue
		out.append(slot)
	return out


## The struggle slot when [param actor] carries one ([DuelCharacter]), else NO_SLOT.
static func struggle_slot(actor) -> int:
	if actor == null or not ("character_resource" in actor):
		return NO_SLOT
	var ch = actor.character_resource
	if ch is DuelCharacter and (ch as DuelCharacter).struggle_move != null:
		return DuelCharacter.STRUGGLE_SLOT
	return NO_SLOT


## Where [param slot] is aimed: the caster's own station for a SELF pattern (in the mode in
## force right now), the foe's station for everything else. The HUD never asks for a cell.
static func aim_for(actor, foe, board, slot: int) -> Vector3i:
	var move: MoveResource = actor.get_move(slot) if actor != null and actor.has_method("get_move") else null
	var pattern: TargetingPattern = move.targeting_for(actor) if move != null else null
	if pattern != null and pattern.target_kind == CombatTypes.TargetKind.SELF:
		return _cell(board, actor)
	return _cell(board, foe)


## Score one move. Returns { score, reason, forecast }.
static func score_move(actor, foe, board, slot: int, ruleset: DuelRuleset) -> Dictionary:
	var move: MoveResource = actor.get_move(slot)
	var pattern := move.targeting_for(actor)
	var self_cast: bool = pattern.target_kind == CombatTypes.TargetKind.SELF
	var score := 0.0
	var reason := "neutral"
	var forecast: Dictionary = {}

	if not self_cast and deals_damage(move, actor):
		forecast = MoveExecutor.preview_vs(move, actor, foe, board)
		var ev := expected_damage(forecast)
		score += ev
		reason = "damage"
		if bool(forecast.get("lethal", false)) and float(forecast.get("hit_pct", 0.0)) >= ruleset.ai_lethal_min_hit:
			score += ruleset.ai_lethal_bonus + float(forecast.get("hit_pct", 0.0)) * 0.1
			reason = "lethal"
	var hit: float = float(forecast.get("hit_pct", move.accuracy * 100.0)) / 100.0

	for effect in move.effects_for(actor):
		if effect is ApplyStatusEffect:
			var cond: StatusCondition = effect.condition
			if cond == null:
				continue
			if bool(effect.to_caster) or self_cast:
				score += _guard_value(actor, foe, board, cond, ruleset)
			else:
				var v := _status_value(foe, cond, ruleset) * float(effect.chance) * hit
				if v > 0.0 and reason == "neutral":
					reason = "status"
				score += v
		elif effect is StatModifierEffect:
			if self_cast:
				if int(effect.amount) > 0:
					score += _threat_scaled(actor, foe, board, ruleset) * 0.5
			elif int(effect.amount) < 0:
				score += float(ruleset.ai_status_values.get("debuff", 0.0)) * hit
		elif effect is ShieldEffect and self_cast:
			score += _threat_scaled(actor, foe, board, ruleset)
		elif effect is HealEffect and self_cast:
			score += _heal_value(actor, ruleset)

	# Cooldown economy: a long-cooldown move spent for little is a small loss.
	score -= float(move.cooldown) * ruleset.ai_cooldown_penalty
	# Hold the ultimate while the foe is guarded or untouchable.
	if MoveResource.is_ultimate_move(move, slot) and not self_cast:
		if DamageMath.is_invulnerable(foe) or DamageMath.damage_taken_scale_for(foe, board) < 1.0:
			score *= 0.25
			reason = "held_ultimate"
	return {"score": score, "reason": reason, "forecast": forecast}


## Expected damage of a forecast: hit% x (damage + crit% x (crit damage - damage)).
static func expected_damage(f: Dictionary) -> float:
	var hit := float(f.get("hit_pct", 0.0)) / 100.0
	var crit := float(f.get("crit_pct", 0.0)) / 100.0
	var dmg := float(f.get("damage", 0))
	var crit_dmg := float(f.get("crit_damage", 0))
	return hit * (dmg + crit * (crit_dmg - dmg))


## The foe's best expected hit against [param actor] with the moves it could use next turn.
static func foe_threat(actor, foe, board) -> float:
	var best := 0.0
	if foe == null or not foe.has_method("get_move"):
		return best
	var count: int = foe.character_resource.move_count() if foe.character_resource != null else 0
	var mc = foe.get_moveset_controller() if foe.has_method("get_moveset_controller") else null
	for slot in range(count):
		var move: MoveResource = foe.get_move(slot)
		if move == null or move.targeting_for(foe) == null:
			continue
		# Ready now or next turn (its cooldown ticks at its own turn start).
		if mc != null and mc.has_method("remaining") and int(mc.remaining(move)) > 1:
			continue
		if move.targeting_for(foe).target_kind == CombatTypes.TargetKind.SELF:
			continue
		best = maxf(best, expected_damage(MoveExecutor.preview_vs(move, foe, actor, board)))
	return best


## True when [param move] (in the mode in force for [param actor]) carries a damage effect.
static func deals_damage(move, actor) -> bool:
	if move == null:
		return false
	for effect in move.effects_for(actor):
		if DamageMath.is_damage_effect(effect):
			return true
	return false


# --- internals ---------------------------------------------------------------------

static func _status_value(foe, cond: StatusCondition, ruleset: DuelRuleset) -> float:
	var values: Dictionary = ruleset.ai_status_values
	# Statuses REFRESH rather than stack (rule 6): re-applying one the foe already carries is
	# worth nothing -- except poison, which stacks up to its cap.
	var has_it: bool = _has_status(foe, cond.id)
	if cond.id == &"poisoned":
		if has_it and cond.max_stacks > 0 and _stacks(foe, cond.id) >= cond.max_stacks:
			return 0.0
		return float(values.get("poisoned", 0.0))
	if has_it:
		return 0.0
	for flag in ["stunned", "controlled"]:
		if bool(cond.rule_flags.get(flag, false)) or bool(cond.rule_flags.get(StringName(flag), false)):
			return float(values.get(flag, 0.0))
	return float(values.get("status", 0.0))


## A guard / self-status is worth [member DuelRuleset.ai_guard_value] while the foe
## threatens enough, and nothing when the actor already holds it.
static func _guard_value(actor, foe, board, cond: StatusCondition, ruleset: DuelRuleset) -> float:
	if _has_status(actor, cond.id):
		return 0.0
	return _threat_scaled(actor, foe, board, ruleset)


static func _threat_scaled(actor, foe, board, ruleset: DuelRuleset) -> float:
	var hp: int = int(actor.get_hp()) if actor.has_method("get_hp") else 0
	if hp <= 0:
		return 0.0
	if foe_threat(actor, foe, board) >= ruleset.ai_guard_threshold * float(hp):
		return ruleset.ai_guard_value
	return 0.0


static func _heal_value(actor, ruleset: DuelRuleset) -> float:
	var hp := float(actor.get_hp()) if actor.has_method("get_hp") else 0.0
	var max_hp := float(actor.max_health) if "max_health" in actor else hp
	if max_hp <= 0.0:
		return 0.0
	var frac := hp / max_hp
	if frac >= ruleset.ai_heal_ceiling:
		return 0.0
	return ruleset.ai_heal_value * (1.0 - frac)


static func _softmax_pick(candidates: Array, temperature: float, rng: RandomNumberGenerator) -> Dictionary:
	var t := maxf(0.01, temperature)
	var top := -INF
	for c in candidates:
		top = maxf(top, float(c["score"]))
	var weights: Array[float] = []
	var total := 0.0
	for c in candidates:
		var w := exp((float(c["score"]) - top) / t)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in range(candidates.size()):
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]


static func _has_status(unit, id: StringName) -> bool:
	if unit == null or id == &"":
		return false
	var sc = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	return sc != null and sc.has_method("has_status") and bool(sc.has_status(id))


static func _stacks(unit, id: StringName) -> int:
	var sc = unit.get_status_controller() if unit.has_method("get_status_controller") else null
	return int(sc.stack_count(id)) if sc != null and sc.has_method("stack_count") else 0


static func _cell(board, unit) -> Vector3i:
	if board == null or unit == null or not board.has_method("cell_of"):
		return Vector3i.ZERO
	return board.cell_of(unit)
