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

## Probability (0..1) that the condition actually lands, rolled INDEPENDENTLY per
## target through [method MoveContext.roll] — i.e. against the executor's injected,
## seedable RNG, so a "30% chance to poison" replays identically on every peer and
## a test can pin it with a seeded generator.
##
## 1.0 (the default) always applies and consumes no roll at all, so every move
## authored before this field existed behaves exactly as it did. Deliberately a
## field here rather than a bespoke roll inside one move: any move, tile or ability
## that inflicts a status gets a chance for free by authoring a number.
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0


func apply(ctx: MoveContext) -> void:
	if condition == null:
		return
	for target in ctx.gather_targets():
		if not ctx.roll(chance):
			ctx.log_event({
				"effect": "apply_status",
				"target": target,
				"status": condition.id,
				"applied": false,
				"chance": chance,
			})
			continue
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
	if chance < 1.0:
		return "%d%% chance to inflict %s" % [roundi(chance * 100.0), label]
	return "Inflict %s" % label
