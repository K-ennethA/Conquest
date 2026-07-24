extends MoveEffect
class_name InfestEffect

## Infection that ripens into MIND CONTROL. Applies one [member infested] stack to
## every gathered target; the instant a target reaches [member control_threshold]
## stacks, the counter is CLEARED and [member enthralled] (the "controlled" rule flag)
## is applied instead -- so two attacks on the same enemy hand it over.
##
## This is the project's bespoke-effect pattern (like Blightcap's on-death burst): the
## "apply a stack, then PROMOTE once a threshold is crossed" shape has no generic hook,
## so it is one small [MoveEffect] subclass rather than new plumbing. It is authored on
## an ON_ATTACK ability with [member AbilityResource.targets_triggering_unit] set, so it
## runs against the unit the caster just hit with no extra wiring.
##
## Both statuses are authored data ([member infested] / [member enthralled]); this
## script only owns the promotion RULE, so the numbers stay in the .tres files.

## The stacking counter status applied on every hit (Infested). Its own
## [member StatusCondition.max_stacks] caps the counter; this effect promotes the
## instant the count reaches [member control_threshold].
@export var infested: StatusCondition
## The control status granted when the threshold is crossed (Enthralled -- carries the
## "controlled" rule flag). Cleared automatically after one turn by the status tick.
@export var enthralled: StatusCondition
## Stacks required to flip infection into control. 2 = two attacks on the same target.
@export var control_threshold: int = 2


func apply(ctx: MoveContext) -> void:
	if infested == null:
		return
	for target in ctx.gather_targets():
		var controller = _controller_of(target)
		if controller == null:
			continue
		# Add one stack (add_status duplicates the resource, so per-unit durations never
		# alias the shared authoring copy).
		controller.add_status(infested)
		var stacks: int = int(controller.stack_count(infested.id))
		var promoted := false
		if stacks >= control_threshold and enthralled != null:
			# Spend the counter and hand the unit over. remove_status fires each
			# instance's on_expire; add_status seeds a fresh 1-turn Enthralled.
			controller.remove_status(infested.id)
			controller.add_status(enthralled)
			promoted = true
			_announce_control(ctx, target)
		ctx.log_event({
			"effect": "infest",
			"target": target,
			"stacks": stacks,
			"controlled": promoted,
		})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Infest the target; a second infestation seizes control of it"


## The target's [StatusController], or null when it exposes none (a bare mock, or a
## non-character unit). Duck-typed so the effect no-ops harmlessly rather than erroring.
func _controller_of(target):
	if target != null and target.has_method("get_status_controller"):
		return target.get_status_controller()
	return null


## Fire [signal GameEvents.unit_controlled] so the UI/combat log can explain the
## betrayal. Guarded end to end: no autoload (headless), no such signal, all no-op.
func _announce_control(ctx: MoveContext, target) -> void:
	var bus = ctx.event_bus if ctx != null and ctx.event_bus != null else GameEvents
	if bus == null or not bus.has_signal(&"unit_controlled"):
		return
	var source = ctx.caster if ctx != null else null
	bus.emit_signal(&"unit_controlled", target, source)
