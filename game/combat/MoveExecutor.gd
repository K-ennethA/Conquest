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
	# Then the pattern's BOARD-aware constraints (an empty landing cell for a leap,
	# adjacency to an enemy, ...). Reported separately from range so the UI/AI can
	# tell "too far" apart from "you cannot land there"; a pattern that declares
	# none of them passes this unconditionally.
	if not move.can_target(origin, aim_cell, caster, board):
		return _fail("invalid_target_cell")

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
##
## [param board] is optional and trailing, so every existing call site is
## unaffected: omitted, it resolves to the live board exactly as before. It exists
## because a passive that changes damage may be gated on a CONDITION that needs a
## board to answer -- Eldroot's Grovebound only reduces damage while it stands on
## forest. Without a board those conditions fail closed, and the forecast would
## quietly under-report the boss's toughness while resolution applied it. Callers
## holding a board (and tests using a mock one) should pass it.
static func preview_vs(move: MoveResource, caster, target, board = null) -> Dictionary:
	if board == null:
		board = _live_board()
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
				dmg += _preview_damage(effect, move, caster, target, board)
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


static func _preview_damage(effect: DamageEffect, move, caster, target, board = null) -> int:
	# An invulnerable defender takes nothing, so the forecast must SAY nothing --
	# short-circuited here exactly as DamageEffect.apply() short-circuits, ahead of
	# mitigation and every scaling step. Showing a mitigated number against a target
	# that will take 0 is the forecast telling a straight lie.
	if DamageEffect.is_invulnerable(target):
		return 0
	var bonus := 0
	if effect.scaling_stat != "":
		bonus = int(round(_stat(caster, effect.scaling_stat) * effect.scale))
	var raw: int = effect.power + bonus
	var mitigated: int = 0
	match effect.category:
		CombatTypes.DamageCategory.TRUE:
			mitigated = maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			var res := _stat_or(target, "magic_defense", _stat_or(target, "defense", 0))
			mitigated = maxi(1, raw - res)
		_:
			mitigated = maxi(1, raw - _stat_or(target, "defense", 0))

	# Predation bonus (e.g. Petalfang's Thornlust vs a snared target). Shown in the
	# forecast because it is DETERMINISTIC: it depends only on the target's current
	# state, so revealing it gives the player information, not an exploit. Crit is
	# deliberately NOT resolved here -- the forecast reports it as a probability and
	# never rolls, so re-aiming or cancelling can never fish for a favourable roll.
	#
	# Routed through DamageEffect's own helper (rather than reimplemented) so the
	# preview and the actual resolution cannot drift apart. Applied after mitigation
	# and before crit, matching DamageEffect.apply() exactly.
	var scale: float = DamageEffect.restricted_scale_for(caster, target, board)
	if scale > 1.0:
		mitigated = maxi(1, roundi(float(mitigated) * scale))

	# The attacker's ELEMENT-HUNTER bonus (Vineweave's Grass Cutter vs nature),
	# routed through DamageEffect's shared helper and applied in the same position
	# (after the predation bonus, before the defender's reduction) so preview == hit.
	var elem_bonus: float = DamageEffect.element_bonus_scale_for(caster, target, board)
	if elem_bonus > 1.0:
		mitigated = maxi(1, roundi(float(mitigated) * elem_bonus))

	# The DEFENDER's own reduction (e.g. Eldroot's Grovebound while it stands in the
	# grove). Applied after the attacker's bonus and before crit, matching the order
	# in DamageEffect.apply() step for step, and routed through the same shared
	# helper so the two cannot drift.
	var taken: float = DamageEffect.damage_taken_scale_for(target, board)
	if not is_equal_approx(taken, 1.0):
		mitigated = maxi(1, roundi(float(mitigated) * taken))

	# TYPE MATCHUP (move-element vs target-type + tile amplifier + own-element tile
	# benefit), routed through the SAME ElementChart helper DamageEffect.apply() uses,
	# applied in the same position (after the defender's reduction, before crit) so the
	# forecast's damage matches the resolved hit exactly. Deterministic, so previewing
	# it is honest; a flat 1.0 for unelemented moves/units leaves the number untouched.
	var element_scale: float = ElementChart.damage_scale_for(move, target, board)
	if not is_equal_approx(element_scale, 1.0):
		mitigated = maxi(1, roundi(float(mitigated) * element_scale))
	return mitigated


## The live board, when there is one. Only needed so a passive's CONDITION can be
## evaluated during a preview; null is fine and simply fails those conditions shut.
static func _live_board():
	var services = Engine.get_main_loop().root.get_node_or_null("CombatServices") if Engine.get_main_loop() is SceneTree else null
	if services != null and services.has_method("board"):
		return services.board()
	return null


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
