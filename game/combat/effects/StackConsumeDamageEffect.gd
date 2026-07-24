extends DamageEffect
class_name StackConsumeDamageEffect

## A hit whose power GROWS with how many stacks of [member stack_status_id] the CASTER
## holds, and which SPENDS those stacks when it lands. The release half of a
## "guard, then reprisal" move: Geode's Prism Bulwark stores a charge every time it is
## struck, and this pays them all back at once.
##
## Extends [DamageEffect] rather than reimplementing it. That is the whole point: every
## consumer that reasons about damage generically -- the combat FORECAST, and the AI's
## "is this move worth using / how much will it hurt" ranking -- tests for DamageEffect.
## A parallel damage class was invisible to both, so the AI would never fire the release
## and the forecast showed nothing. Inheriting means mitigation, the element chart, crit,
## lifesteal, the damage_dealt announce and the preview all come along for free; only the
## RAW POWER and the spend-the-charges step are new.

## Extra raw damage per stored stack (on top of the inherited [member power] base).
@export var power_per_stack: int = 6
## The stacking StatusCondition whose count drives -- and is consumed by -- this hit.
@export var stack_status_id: StringName = &"reprisal_charge"


## The stored charges, expressed as bonus power. Read by DamageEffect for BOTH the
## resolved hit and the forecast, so what the player is shown is what lands.
func bonus_power_for(caster) -> int:
	return power_per_stack * maxi(0, _stacks_of(caster))


func apply(ctx: MoveContext) -> void:
	# Resolve the hit exactly as any DamageEffect does (bonus_power_for folds the charges
	# into the raw number), then SPEND the charges -- whether or not anything was hit, so
	# stale stacks never carry into the next stance.
	super.apply(ctx)
	_clear_stacks(ctx.caster if ctx != null else null, ctx.board if ctx != null else null)


func _stacks_of(caster) -> int:
	var controller = _status_controller(caster)
	if controller == null or not controller.has_method("stack_count"):
		return 0
	return int(controller.stack_count(stack_status_id))


func _clear_stacks(caster, board) -> void:
	var controller = _status_controller(caster)
	if controller != null and controller.has_method("remove_status"):
		controller.remove_status(stack_status_id, board)


func _status_controller(caster):
	if caster == null:
		return null
	if caster.has_method("get_status_controller"):
		return caster.get_status_controller()
	return null


func describe() -> String:
	if description_override != "":
		return description_override
	return "Deals %d damage +%d per stored charge, spending them all" % [power, power_per_stack]
