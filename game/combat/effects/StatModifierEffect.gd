extends MoveEffect
class_name StatModifierEffect

## Applies a temporary buff or debuff to valid targets (e.g. +attack for 3 turns,
## or -defense on an enemy). Positive [member amount] buffs, negative debuffs.

@export var stat_name: String = "attack"
@export var amount: int = 5
## Turns the modifier lasts. -1 = permanent.
@export var duration: int = 3


func apply(ctx: MoveContext) -> void:
	for target in ctx.gather_targets():
		if target.has_method("add_stat_modifier"):
			target.add_stat_modifier(stat_name, amount, duration)
		ctx.log_event({
			"effect": "stat_modifier",
			"target": target,
			"stat": stat_name,
			"amount": amount,
			"duration": duration,
		})


func describe() -> String:
	if description_override != "":
		return description_override
	var verb := "+%d" % amount if amount >= 0 else str(amount)
	return "%s %s for %d turns" % [verb, stat_name, duration]
