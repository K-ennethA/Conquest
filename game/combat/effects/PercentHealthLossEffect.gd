extends MoveEffect
class_name PercentHealthLossEffect

## Environmental attrition: every valid target loses [member fraction] of its OWN
## max health (at least [member min_amount]). No accuracy roll, no crit, ignores
## defense -- it is weather / terrain wear, not an attack (Desert Storm's sand chip
## is 1/16 max HP, min 1). A shield soaks it like any damage (it goes through
## take_damage), and an invulnerable unit ([method DamageEffect.is_invulnerable])
## takes nothing.
##
## Deliberately does NOT announce damage_dealt: there is no attacker, so ON_ATTACK /
## ON_DAMAGED retaliation abilities and kill credit are not triggered by the weather.

@export_range(0.0, 1.0, 0.0001) var fraction: float = 0.0625
@export var min_amount: int = 1


func apply(ctx: MoveContext) -> void:
	for target in ctx.gather_targets():
		var amount := amount_for(target)
		if amount <= 0:
			continue
		if target.has_method("take_damage"):
			target.take_damage(amount)
		ctx.log_event({
			"effect": "damage",
			"target": target,
			"amount": amount,
			"category": CombatTypes.DamageCategory.TRUE,
			"environmental": true,
		})


## HP [param target] would lose (0 when invulnerable or max health is unknown).
func amount_for(target) -> int:
	if target == null or DamageEffect.is_invulnerable(target):
		return 0
	var max_hp := 0
	if "max_health" in target:
		max_hp = int(target.max_health)
	elif target.has_method("get_base_stat"):
		max_hp = int(target.get_base_stat("health"))
	if max_hp <= 0:
		return 0
	return maxi(min_amount, int(floor(float(max_hp) * fraction)))


func describe() -> String:
	if description_override != "":
		return description_override
	return "Lose %d%% of max health" % roundi(fraction * 100.0)
