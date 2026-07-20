extends MoveEffect
class_name HealEffect

## Restores health to valid targets in the area (typically ALLY or SELF moves).

@export var amount: int = 20
## Optional caster stat that adds to the heal (e.g. "magic").
@export var scaling_stat: String = ""
@export var scale: float = 1.0
## Fraction of the TARGET's own max health added to the heal (0.10 = 10%).
## Resolved per target, so one cast restores each target its own share.
## 0.0 (the default) leaves the flat heal untouched.
@export var percent_of_max_health: float = 0.0


func apply(ctx: MoveContext) -> void:
	var bonus := 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var flat := amount + bonus

	for target in ctx.gather_targets():
		# The percent term reads the TARGET's max health, so it is resolved here
		# rather than once up front.
		var total := flat + _percent_bonus(target)
		if target.has_method("heal"):
			target.heal(total)
		ctx.log_event({ "effect": "heal", "target": target, "amount": total })


func describe() -> String:
	if description_override != "":
		return description_override
	if percent_of_max_health <= 0.0:
		return "Restore %d health" % amount
	var pct := roundi(percent_of_max_health * 100.0)
	if amount == 0 and scaling_stat == "":
		return "Restore %d%% of max health" % pct
	return "Restore %d health + %d%% of max health" % [amount, pct]


## [member percent_of_max_health] of [param target]'s max health. Reads the max
## defensively — units expose [code]max_health[/code], some expose
## [code]get_base_stat("health")[/code] — and contributes nothing when the
## percent is off or neither reading is available.
func _percent_bonus(target) -> int:
	if percent_of_max_health <= 0.0 or target == null:
		return 0
	var max_hp := 0
	if "max_health" in target:
		max_hp = int(target.max_health)
	elif target.has_method("get_base_stat"):
		max_hp = int(target.get_base_stat("health"))
	if max_hp <= 0:
		return 0
	return roundi(max_hp * percent_of_max_health)
