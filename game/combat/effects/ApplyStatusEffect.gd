extends MoveEffect
class_name ApplyStatusEffect

## Inflicts a [StatusCondition] on every valid target in the area.
##
## This is the bridge that lets any move — and, via the shared pipeline, any tile
## or ability — cause a multi-turn effect (burn, poison, regen, timed buff). Each
## target receives an independent duplicate of [member condition] through its
## status controller, so per-unit durations never alias one another.

## The condition to inflict. Compose it from existing effects (e.g. a burn =
## a condition whose tick_effects = [DamageEffect]).
@export var condition: StatusCondition


func apply(ctx: MoveContext) -> void:
	if condition == null:
		return
	for target in ctx.gather_targets():
		var applied := false
		if target.has_method("add_status"):
			target.add_status(condition.duplicate(true))
			applied = true
		elif target.has_method("get_status_controller"):
			var controller = target.get_status_controller()
			if controller != null and controller.has_method("add_status"):
				controller.add_status(condition.duplicate(true))
				applied = true
		ctx.log_event({
			"effect": "apply_status",
			"target": target,
			"status": condition.id,
			"applied": applied,
		})


func describe() -> String:
	if description_override != "":
		return description_override
	var label := condition.display_name if condition != null and condition.display_name != "" else "a condition"
	return "Inflict %s" % label
