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

	# Mode-aware: a two-mode move resolves the pattern AND the effect list that its
	# caster's current state puts in force (single-mode moves return their only pair).
	var pattern := move.targeting_for(caster)
	if pattern == null:
		return _fail("no_targeting")
	var cells := pattern.resolve_cells(origin, aim_cell)
	var ctx := MoveContext.new(caster, board, move, aim_cell, cells)
	ctx.rng = rng  # null -> MoveContext lazily makes a randomized one

	for effect in move.effects_for(caster):
		if effect:
			effect.apply(ctx)

	return {
		"success": true,
		"events": ctx.results,
		"cells": cells,
	}


## Non-mutating combat FORECAST of [param move] from [param caster] against
## [param target] -- what the FE-style forecast panel shows. Never rolls RNG, never
## mutates anything.
##
## Returns { hit_pct, crit_pct, damage, crit_damage, target_hp, remaining, lethal }
## PLUS the element/ability breakdown [DamageMath.preview] produces:
## { total, base, element_mult, element_label, ability_bonus_percent, ability_notes }.
## "damage" and "total" are the same number by construction -- "damage" is the historical
## key the panel already reads, "total" is the pinned name.
##
## THE DAMAGE NUMBER IS NOT COMPUTED HERE. It comes from [method DamageMath.preview],
## which is the identical function [method DamageEffect.apply] resolves the real hit
## through, so the forecast cannot drift from reality: there is no second copy of the
## arithmetic to fall out of step.
##
## [param board] is optional and trailing, so every existing call site is unaffected:
## omitted, it resolves to the live board exactly as before. It exists because a passive
## that changes damage may be gated on a CONDITION that needs a board to answer --
## Eldroot's Grovebound only reduces damage while it stands on forest. Without a board
## those conditions fail closed, and the forecast would quietly under-report the boss's
## toughness while resolution applied it. Callers holding a board (and tests using a mock
## one) should pass it.
static func preview_vs(move: MoveResource, caster, target, board = null) -> Dictionary:
	if board == null:
		board = _live_board()
	var hit_pct := 100.0
	var crit_pct := 0.0
	if move != null:
		# Include terrain avoid so the forecast matches what resolve_hit will roll.
		var evasion := float(_stat(target, "evasion")) + float(TerrainStats.bonus_for(target, "evasion"))
		hit_pct = clampf(move.accuracy * 100.0 - evasion, 0.0, 100.0)
		crit_pct = clampf(move.crit_chance * 100.0 + float(_stat(caster, "crit")), 0.0, 100.0)
	# Mode-aware (DamageMath reads move.effects_for(caster)), invulnerability-aware, and
	# element-aware -- all of it the shared implementation, none of it restated here.
	var preview: Dictionary = DamageMath.preview(caster, target, move, board)
	var dmg: int = int(preview.get("total", 0))
	var hp := _hp(target)
	var out := {
		"hit_pct": hit_pct,
		"crit_pct": crit_pct,
		"damage": dmg,
		"crit_damage": maxi(dmg, int(round(dmg * CombatTypes.CRIT_MULTIPLIER))),
		"target_hp": hp,
		"remaining": maxi(0, hp - dmg),
		"lethal": hp > 0 and dmg >= hp,
	}
	out.merge(preview)
	return out


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
