extends MoveEffect
class_name DelayedBurstEffect

## Marks the aimed area and arms a [DelayedBurstHazard] on it -- a DELAYED area strike
## that telegraphs for a turn and then erupts (Monster's Abyssal Maw).
##
## The counterpart of [SpawnHazardEffect]: that one throws a hazard that MOVES, this one
## plants a hazard that WAITS. Both snapshot their damage from the caster's stats at cast
## time (so a later buff cannot retune something already on the board), both carry the
## cast's element and event bus onto the hazard, and both leave the actual damage to the
## shared environmental chain.
##
## THE AREA IS THE MOVE'S OWN. [member MoveContext.affected_cells] is whatever the move's
## [TargetingPattern] already resolved, so retuning the maw from a 3x3 to a diamond is a
## .tres edit with no code change -- and the cells the player was shown in the targeting
## preview are, by construction, the cells that erupt.
##
## THE FUSE IS A STATUS ON THE CASTER ([DelayedBurstStatus]), not a tick on
## [HazardManager], because "the start of the CASTER's next turn" is a per-unit beat and
## the manager ticks on every side's turn. See that class for the whole argument.
##
## TELEGRAPH. On cast this emits the ordinary [code]hazard_advanced[/code] with an EMPTY
## current band and the marked patch as the NEXT band -- which is exactly the shape the
## crawling vine emits for "the lane sweeps here next turn", so the existing hazard
## overlay renders the maw's warning glow with no new visual code. The eruption then
## emits the mirror (the patch as the current band, nothing next) followed by
## [code]hazard_expired[/code], from [DelayedBurstStatus].

## Raw damage per occupant before the caster stat is folded in.
@export var power: int = 24
## Caster stat added to power (e.g. "magic"). Empty = flat power.
@export var scaling_stat: String = "magic"
## Fraction of the scaling stat added to power.
@export var scale: float = 1.0
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.MAGICAL

## Who the eruption damages, relative to the CASTER. ENEMY (the default) makes the maw
## bite only foes; ANY_UNIT would make it indiscriminate. Evaluated through the same
## [enum CombatTypes.TargetKind] instant moves and vines use.
@export var affiliation: CombatTypes.TargetKind = CombatTypes.TargetKind.ENEMY

## The fuse planted on the caster (`void_maw_fuse.tres`, a [DelayedBurstStatus]). Its
## 1-turn duration is authored there, so "erupts next turn" is data.
@export var fuse: StatusCondition


func apply(ctx: MoveContext) -> void:
	if ctx == null or ctx.caster == null or fuse == null:
		return

	# Snapshot the damage from the caster's CURRENT stats. Everything about the maw is
	# frozen here: a buff that lands while the fuse burns cannot deepen it.
	var bonus: int = 0
	if scaling_stat != "":
		bonus = int(round(float(ctx.get_caster_stat(scaling_stat)) * scale))
	var raw: int = power + bonus

	var blast: Array[Vector2i] = ctx.affected_cells.duplicate()
	var hazard := DelayedBurstHazard.new(blast, raw, category, affiliation, ctx.caster)
	hazard.event_bus = ctx.event_bus
	# The cast's ELEMENT, snapshotted like the damage -- a maw is an environmental
	# extension of the move that opened it, so every bite is matched against the victim's
	# element through the same chart a direct hit would use.
	hazard.element = ElementChart.move_element(ctx.move)

	var armed := _arm_fuse(ctx, hazard)
	if armed:
		_telegraph(ctx, hazard)
	ctx.log_event({
		"effect": "delayed_burst",
		"target": ctx.caster,
		"cells": blast,
		"power": raw,
		"category": category,
		"armed": armed,
	})


## Plant the fuse on the caster and hand it the maw. Returns false when the caster has no
## status controller to carry it -- in which case nothing is armed at all, so a maw can
## never be left on the board with nothing to set it off.
func _arm_fuse(ctx: MoveContext, hazard) -> bool:
	var controller = _controller_of(ctx.caster)
	if controller == null or not controller.has_method("add_status"):
		return false
	var stamped: StatusCondition = fuse.duplicate(true)
	stamped.set_source(ctx.caster)
	var live = controller.add_status(stamped)
	if live == null or not live.has_method("arm"):
		return false
	# The live instance is the fresh copy, or the already-armed one on a refresh -- either
	# way it is the single fuse this caster carries (CONQUEST.md rule 6).
	live.arm(hazard)
	return true


## Emit the warning: no current band, the marked patch as the band that erupts NEXT. The
## same signal shape a crawling vine telegraphs with, so the existing overlay reads it.
func _telegraph(ctx: MoveContext, hazard) -> void:
	var bus = ctx.event_bus
	if bus == null:
		if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
			return
		bus = GameEvents
	if bus == null or not is_instance_valid(bus) or not bus.has_signal(&"hazard_advanced"):
		return
	bus.emit_signal(&"hazard_advanced", hazard,
		[] as Array[Vector2i], hazard.telegraph_cells(), 0)


func describe() -> String:
	if description_override != "":
		return description_override
	return "Mark the ground; it erupts on your next turn for %d %s damage" % [
		power, CombatTypes.DamageCategory.keys()[category].to_lower()]


## [param unit]'s [StatusController], or null when it exposes none.
func _controller_of(unit):
	if unit != null and unit.has_method("get_status_controller"):
		return unit.get_status_controller()
	return null
