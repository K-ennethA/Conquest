extends StatusCondition
class_name RegenStatus

## A [StatusCondition] that HEALS its unit a flat amount at every tick, for as long as it is
## active. The regeneration channel behind items like the Sagebloom Poultice.
##
## Modelled on [StatModifierStatus]: a tiny subclass that carries one exported number and
## overrides one hook, so the whole thing rides the existing status machinery -- ticked by
## [method StatusController.tick_all], which the ACTIVE turn system calls once per unit turn
## from [method TurnSystemBase._tick_unit_turn_start]. That matters: PlayerManager's turn
## signals do not fire on AI turns, so anything per-turn must ride the turn system's, and
## this class inherits that for free by living on the unit's StatusController.
##
## WHY IT OVERRIDES [method tick] INSTEAD OF USING tick_effects: the base implementation
## routes tick effects through a [MoveContext], which needs a live board -- so a regen
## authored as a [HealEffect] would silently do nothing wherever the board is absent (mock
## units in tests, a unit ticked before the board rebuild lands). Healing needs none of that
## context: it is a single call on the unit. Overriding keeps it board-independent and
## trivially testable, exactly as StatModifierStatus's on_apply/on_expire are.
##
## RE-APPLICATION REFRESHES, IT NEVER STACKS. [member StatusCondition.stacking] defaults to
## REFRESH here, so [method StatusController.add_status] resets the timer on the live instance
## and never adds a second one -- two sources of regen can therefore never silently double the
## heal. [ItemSystem] leans on that: it SUMS every equipped item's regen and applies ONE
## instance carrying the total, rather than one instance per item.

## HP restored to the unit at each tick. Non-positive is inert (the status still occupies its
## slot and shows in the HUD, it just heals nothing).
@export var heal_per_turn: int = 5


func _init() -> void:
	# Battle-long by default: an item's regen lasts as long as the unit does. -1 is the
	# engine's "permanent" duration, so tick_all keeps ticking it and never expires it.
	if duration_turns == 1:
		duration_turns = -1
	stacking = Stacking.REFRESH


## Heal the unit once. [param board] is accepted for signature compatibility with the base
## tick contract and deliberately unused -- see the class docs. Returns a one-entry event log
## in the same shape the effect pipeline produces, so a caller aggregating tick events sees a
## regen exactly like any other tick result. Null-safe for a target that cannot be healed.
func tick(target, _board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target == null or heal_per_turn <= 0:
		return events
	if not target.has_method("heal"):
		return events

	var before: int = _health_of(target)
	target.heal(heal_per_turn)
	var after: int = _health_of(target)
	var healed: int = maxi(0, after - before)

	# Announce on the shared bus so the floating-number / battle-log surfaces pick it up the
	# same way they do a heal move. Guarded so a headless test without autoloads is fine.
	if healed > 0 and typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"unit_healed"):
		GameEvents.unit_healed.emit(target, healed)

	events.append({
		"type": "heal",
		"source": id,
		"target": target,
		"amount": healed,
	})
	return events


## Current HP through whichever accessor the target exposes; 0 when it has neither (a mock
## that only implements heal() still works, it just reports 0 healed).
func _health_of(target) -> int:
	if target.has_method("get_stat"):
		return int(target.get_stat("health"))
	if "current_health" in target:
		return int(target.current_health)
	return 0
