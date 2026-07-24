extends MoveEffect
class_name ShieldEffect

## Grants a temporary damage-soaking SHIELD to every gathered target. The shield is a
## flat HP buffer that [method Unit.take_damage] burns through before any damage
## reaches real health -- see Unit.grant_shield / Unit.shield_hp.
##
## Self-buff moves and abilities (SELF targeting, or a triggering-unit anchor) gather
## exactly the caster, so this is how Crystalline Ward hands the Gem Knight its 15-HP
## ward. The shield REFRESHES to the strongest value rather than stacking, so re-granting
## it never compounds -- the same rule the damage-reduction statuses follow.

## Shield points granted.
@export var amount: int = 15


func apply(ctx: MoveContext) -> void:
	var targets: Array = ctx.gather_targets()
	# A pure self-buff whose pattern gathered nothing (mock/edge case) still shields the caster.
	if targets.is_empty() and ctx.caster != null:
		targets = [ctx.caster]
	for target in targets:
		if target != null and target.has_method("grant_shield"):
			target.grant_shield(amount)
			ctx.log_event({
				"effect": "shield",
				"target": target,
				"amount": amount,
			})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Gain a %d HP shield" % amount
