extends MoveEffect
class_name StackConsumeDamageEffect

## Deals damage that SCALES with how many stacks of [member stack_status_id] the
## CASTER currently holds, then CLEARS that status (spends the charge). The release
## half of a "guard, then reprisal" move: the Gem Knight's Prism Bulwark accumulates
## a `reprisal_charge` stack every time it is hit, and this pays them all back at once.
##
## Reuses DamageEffect's shared, static resolution helpers (mitigation, the defender's
## damage-reduction, the element chart, invulnerability) so a stack-scaled hit obeys the
## exact same defender-side rules as a normal DamageEffect -- only the raw number differs.
## Null-safe: a caster with no status controller simply resolves at [member base_power].

## Flat damage before any stacks are counted.
@export var base_power: int = 8
## Extra raw damage added per stack of [member stack_status_id] the caster holds.
@export var power_per_stack: int = 6
## The stacking StatusCondition whose count drives (and is consumed by) this hit.
@export var stack_status_id: StringName = &"reprisal_charge"
## Caster stat blended into the raw damage (like DamageEffect.scaling_stat).
@export var scaling_stat: String = "attack"
@export var scale: float = 0.5
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL


func apply(ctx: MoveContext) -> void:
	var stacks: int = _caster_stacks(ctx)
	var bonus: int = 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var raw: int = base_power + power_per_stack * maxi(0, stacks) + bonus

	for target in ctx.gather_targets():
		var outcome: Dictionary = ctx.resolve_hit(target)
		if not outcome.get("hit", true):
			ctx.log_event({"effect": "damage", "target": target, "amount": 0, "category": category, "missed": true})
			continue
		if DamageEffect.is_invulnerable(target):
			ctx.log_event({"effect": "damage", "target": target, "amount": 0, "category": category, "negated": true})
			continue
		var dealt: int = DamageEffect._mitigate_for(raw, target, category)
		var taken: float = DamageEffect.damage_taken_scale_for(target, ctx.board)
		if not is_equal_approx(taken, 1.0):
			dealt = maxi(1, int(round(float(dealt) * taken)))
		var elem: float = ElementChart.damage_scale_for(ctx.move, target, ctx.board)
		if not is_equal_approx(elem, 1.0):
			dealt = maxi(1, int(round(float(dealt) * elem)))
		if outcome.get("crit", false):
			dealt = maxi(1, int(round(float(dealt) * CombatTypes.CRIT_MULTIPLIER)))
		# Announce BEFORE applying, for the same reason DamageEffect does: a lethal hit
		# resolves the death synchronously, and the killer must already be known (via the
		# damage_dealt signal) or ON_KILL abilities never fire.
		DamageEffect._announce(ctx, target, dealt)
		if target.has_method("take_damage"):
			target.take_damage(dealt)
		ctx.log_event({"effect": "damage", "target": target, "amount": dealt, "category": category, "crit": outcome.get("crit", false)})

	# Spend the accumulated charge whether or not there was a target, so the counter
	# never carries stale stacks into the next stance.
	_clear_caster_stacks(ctx)


## Current stack count of [member stack_status_id] on the caster (0 when none / no controller).
func _caster_stacks(ctx: MoveContext) -> int:
	var controller = _caster_controller(ctx)
	if controller == null or not controller.has_method("stack_count"):
		return 0
	return int(controller.stack_count(stack_status_id))


func _clear_caster_stacks(ctx: MoveContext) -> void:
	var controller = _caster_controller(ctx)
	if controller != null and controller.has_method("remove_status"):
		controller.remove_status(stack_status_id, ctx.board)


func _caster_controller(ctx: MoveContext):
	if ctx == null or ctx.caster == null:
		return null
	if ctx.caster.has_method("get_status_controller"):
		return ctx.caster.get_status_controller()
	return null


func describe() -> String:
	if description_override != "":
		return description_override
	return "Deal %d damage +%d per charge, then spend all charges" % [base_power, power_per_stack]
