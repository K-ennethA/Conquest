extends MoveEffect
class_name StatModifierEffect

## Applies a temporary buff or debuff to valid targets (e.g. +attack for 3 turns,
## or -defense on an enemy). Positive [member amount] buffs, negative debuffs.

@export var stat_name: String = "attack"
@export var amount: int = 5
## Turns the modifier lasts. -1 = permanent.
@export var duration: int = 3


## A TIMED modifier forced on a unit from outside -- by a hostile caster or by the ground
## ([member MoveContext.environmental]) -- runs on the AFFLICTION clock, exactly like a
## status would (CONQUEST.md rule 6a, one shared rule in
## [method StatusCondition.is_affliction_from]): Sunder Guard's "-8 defense for 2 turns"
## holds through the victim's next 2 turns instead of lapsing as the first one opens. A
## self / ally buff, and the modifier a status TICK grants (its context's caster is the
## afflicted unit itself -- Entangled's slow), keep the protective turn-start clock.
func apply(ctx: MoveContext) -> void:
	for target in ctx.gather_targets():
		if target.has_method("add_stat_modifier"):
			var modifier_id = target.add_stat_modifier(stat_name, amount, duration)
			var afflicts: bool = duration > 0 \
					and StatusCondition.is_affliction_from(ctx.caster, target, ctx.environmental)
			if afflicts and target.has_method("set_stat_modifier_clock"):
				target.set_stat_modifier_clock(int(modifier_id), true)
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
