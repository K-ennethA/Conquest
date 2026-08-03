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
##
## THE THRALL STATE MACHINE (one host, one parasite):
##
##   clean --bite--> infested x1 --bite--> ENTHRALLED (counter spent, control seized)
##     ^                                        |
##     |                                     bites during control are JUST DAMAGE
##     +------------- control lapses after 1 turn, residual stacks CLEARED
##
## Two rules make the loop honest, and both are DELIBERATE EXCEPTIONS to the project's
## "a re-application refreshes" convention (CONQUEST.md rule 6):
##
##  1. A BITE ON AN ALREADY-CONTROLLED HOST PLANTS NOTHING. Not a refresh, not a stack --
##     nothing at all. Infesting a puppet you already own would bank progress toward the
##     NEXT takeover for free, so control would renew itself off attacks that cost the
##     parasite nothing extra.
##  2. WHEN CONTROL LAPSES, LEFTOVER INFESTATION IS CLEARED (see [EnthralledStatus]).
##
## Together: re-taking a host always costs TWO FRESH BITES, exactly like the first time.
## The infestation counter is a run-up to a takeover, never a permanent debuff.
##
## A LETHAL SECOND BITE DOES NOT KILL. The promotion happens on the attacker's ON_ATTACK,
## which resolves BEFORE the blow's HP is applied, so a bite that both completes the
## takeover and would kill raises the thrall instead: [method DamageEffect.apply] sees
## the target became controlled during its announce and clamps the blow to leave 1 HP.
## The host is alive to be puppeted -- and effectively dead anyway.

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
		# ALREADY OURS: a bite on a host under our control plants nothing (rule 1 in the
		# class docs). Logged rather than skipped silently, so the combat log can still
		# show the hit happened and simply carried no infestation.
		if _is_controlled(controller):
			ctx.log_event({
				"effect": "infest",
				"target": target,
				"stacks": int(controller.stack_count(infested.id)),
				"controlled": false,
				"suppressed": true,
			})
			continue
		# Add one stack, stamped with the parasite so anything the status does is credited
		# to it. Duplicated here rather than handing over the shared authoring resource:
		# stamping the .tres itself would re-point every other unit's copy.
		controller.add_status(_stamped(infested, ctx.caster))
		var stacks: int = int(controller.stack_count(infested.id))
		var promoted := false
		if stacks >= control_threshold and enthralled != null:
			# Spend the counter and hand the unit over. remove_status fires each
			# instance's on_expire; add_status seeds a fresh 1-turn Enthralled.
			controller.remove_status(infested.id)
			controller.add_status(_stamped(enthralled, ctx.caster))
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


## True while [param controller]'s unit is already under mind control -- read from the
## "controlled" rule flag [member enthralled] declares, so the suppression is keyed on
## the STATUS rather than on Mycothrall. Duck-typed: a controller without the query
## simply never suppresses.
func _is_controlled(controller) -> bool:
	if controller == null or not controller.has_method("has_rule_flag"):
		return false
	return bool(controller.has_rule_flag(&"controlled"))


## A fresh duplicate of [param condition] credited to [param source]. The shared
## authoring .tres is never touched (CONQUEST.md rule 7).
func _stamped(condition: StatusCondition, source) -> StatusCondition:
	var instance: StatusCondition = condition.duplicate(true)
	instance.set_source(source)
	return instance


## Fire [signal GameEvents.unit_controlled] so the UI/combat log can explain the
## betrayal. Guarded end to end: no autoload (headless), no such signal, all no-op.
func _announce_control(ctx: MoveContext, target) -> void:
	var bus = ctx.event_bus if ctx != null and ctx.event_bus != null else GameEvents
	if bus == null or not bus.has_signal(&"unit_controlled"):
		return
	var source = ctx.caster if ctx != null else null
	bus.emit_signal(&"unit_controlled", target, source)
