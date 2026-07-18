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


## Base moveset plus every special move unlocked up to [member current_phase].
func _effective_moveset(base_moveset: Array) -> Array:
	var out: Array = []
	out.append_array(base_moveset)
	for i in range(mini(current_phase + 1, phase_special_moves.size())):
		var extra = phase_special_moves[i]
		if extra is Array:
			out.append_array(extra)
	return out
