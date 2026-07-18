extends MoveEffect
class_name HealEffect

## Restores health to valid targets in the area (typically ALLY or SELF moves).

@export var amount: int = 20
## Optional caster stat that adds to the heal (e.g. "magic").
@export var scaling_stat: String = ""
@export var scale: float = 1.0


func apply(ctx: MoveContext) -> void:
	var bonus := 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var total := amount + bonus

	for target in ctx.gather_targets():
		if target.has_method("heal"):
			target.heal(total)
		ctx.log_event({ "effect": "heal", "target": target, "amount": total })


func describe() -> String:
	if description_override != "":
		return description_override
	return "Restore %d health" % amount
