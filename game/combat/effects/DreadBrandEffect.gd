extends MoveEffect
class_name DreadBrandEffect

## Plants a [BrandStatus] on every gathered target -- the payload of Monster's ON_ATTACK
## passive, Dread Brand.
##
## Almost an [ApplyStatusEffect], and deliberately NOT one: a brand has to know the
## EVENT BUS this cast is announcing on so it can hear the next damage instance and spend
## itself. [ApplyStatusEffect] hands the condition to the target's controller and never
## sees it again, so there is no seam to pass a bus through. This is that one extra line
## -- the same shape [SpawnHazardEffect] uses when it carries `ctx.event_bus` onto a vine.
##
## Everything else is the ordinary status road: the condition is DUPLICATED before it is
## handed over (CONQUEST.md rule 7 -- the shared authoring .tres is never stamped) and the
## caster is recorded as the applier, so anything the brand goes on to enable is credited
## to it. Re-branding an already-branded victim resolves through
## [method StatusController.add_status]'s REFRESH rule, which returns the EXISTING
## instance -- so [method BrandStatus.bind] re-arms that one brand instead of opening a
## second, and two brands can never compound (CONQUEST.md rule 6).

## The brand to plant (`branded.tres`). Its x1.3 amplification and REFRESH stacking are
## authored data; this script only owns WHO gets it and WHICH bus it listens on.
@export var brand: StatusCondition


func apply(ctx: MoveContext) -> void:
	if ctx == null or brand == null:
		return
	for target in ctx.gather_targets():
		var applied := _brand(target, ctx)
		ctx.log_event({
			"effect": "brand",
			"target": target,
			"status": brand.id,
			"applied": applied,
		})


## Plant (or refresh) the brand on [param target]. Returns true when it landed.
func _brand(target, ctx: MoveContext) -> bool:
	if target == null:
		return false
	var controller = _controller_of(target)
	if controller == null or not controller.has_method("add_status"):
		return false
	var stamped: StatusCondition = brand.duplicate(true)
	stamped.set_source(ctx.caster)
	var live = controller.add_status(stamped)
	if live == null:
		return false
	# The live instance is the fresh copy, or the already-active one on a refresh. Either
	# way it is the instance that must be listening, and bind() is idempotent.
	if live.has_method("bind"):
		live.bind(target, ctx.event_bus)
	return true


func describe() -> String:
	if description_override != "":
		return description_override
	return "Brand the target: the next damage it takes is amplified"


## [param target]'s [StatusController], or null when it exposes none. Duck-typed so the
## effect no-ops harmlessly against a bare mock rather than erroring.
func _controller_of(target):
	if target != null and target.has_method("get_status_controller"):
		return target.get_status_controller()
	return null
