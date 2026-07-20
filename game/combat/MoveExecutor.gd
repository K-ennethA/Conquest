extends RefCounted
class_name MoveExecutor

## Resolves a move end-to-end: validate range, expand the area, then run every
## effect in order. Returns a structured result the UI / turn system / network
## layer can consume (it does not touch visuals directly).
##
## Deterministic given the same inputs (RNG for accuracy/crit is injected, not
## called internally) so it is safe to run identically on every networked peer.

## Result dictionary keys: "success" (bool), "reason" (String, on failure),
## "events" (Array[Dictionary] from the effects), "cells" (Array[Vector2i]).
static func execute(move: MoveResource, caster, board, aim_cell: Vector2i, rng: RandomNumberGenerator = null) -> Dictionary:
	if move == null or not move.is_valid():
		return _fail("invalid_move")
	if caster == null or board == null:
		return _fail("missing_caster_or_board")
	if not board.has_method("cell_of"):
		return _fail("board_missing_cell_of")

	var origin: Vector2i = board.cell_of(caster)
	# Through can_aim_at (not targeting.in_range directly) so the caster's own
	# range bonus is honoured -- the same helper the UI and the AI validate with.
	if not move.can_aim_at(origin, aim_cell, caster):
		return _fail("out_of_range")

	var cells := move.targeting.resolve_cells(origin, aim_cell)
	var ctx := MoveContext.new(caster, board, move, aim_cell, cells)
	ctx.rng = rng  # null -> MoveContext lazily makes a randomized one

	for effect in move.effects:
		if effect:
			effect.apply(ctx)

	return {
		"success": true,
		"events": ctx.results,
		"cells": cells,
	}


## Non-mutating combat forecast of [param move] from [param caster] against
## [param target] -- what the FE-style forecast panel shows. Never rolls RNG.
## Returns { hit_pct, crit_pct, damage, crit_damage, target_hp, remaining, lethal }.
static func preview_vs(move: MoveResource, caster, target) -> Dictionary:
	var hit_pct := 100.0
	var crit_pct := 0.0
	var dmg := 0
	if move != null:
		# Include terrain avoid so the forecast matches what resolve_hit will roll.
		var evasion := float(_stat(target, "evasion")) + float(TerrainStats.bonus_for(target, "evasion"))
		hit_pct = clampf(move.accuracy * 100.0 - evasion, 0.0, 100.0)
		crit_pct = clampf(move.crit_chance * 100.0 + float(_stat(caster, "crit")), 0.0, 100.0)
		for effect in move.effects:
			if effect is DamageEffect:
				dmg += _preview_damage(effect, caster, target)
	var hp := _hp(target)
	return {
		"hit_pct": hit_pct,
		"crit_pct": crit_pct,
		"damage": dmg,
		"crit_damage": maxi(dmg, int(round(dmg * CombatTypes.CRIT_MULTIPLIER))),
		"target_hp": hp,
		"remaining": maxi(0, hp - dmg),
		"lethal": hp > 0 and dmg >= hp,
	}


static func _preview_damage(effect: DamageEffect, caster, target) -> int:
	var bonus := 0
	if effect.scaling_stat != "":
		bonus = int(round(_stat(caster, effect.scaling_stat) * effect.scale))
	var raw: int = effect.power + bonus
	match effect.category:
		CombatTypes.DamageCategory.TRUE:
			return maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			var res := _stat_or(target, "magic_defense", _stat_or(target, "defense", 0))
			return maxi(1, raw - res)
		_:
			return maxi(1, raw - _stat_or(target, "defense", 0))


static func _stat(unit, stat_name: String) -> int:
	if unit and unit.has_method("get_stat"):
		return unit.get_stat(stat_name)
	return 0


static func _stat_or(unit, stat_name: String, fallback: int) -> int:
	if unit and unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback


static func _hp(unit) -> int:
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


static func _fail(reason: String) -> Dictionary:
	return { "success": false, "reason": reason, "events": [], "cells": [] }
