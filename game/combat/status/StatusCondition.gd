extends Resource
class_name StatusCondition

## A multi-turn condition on a unit (burn, poison, regen, timed buff, …).
##
## Built on the shared effect pipeline: a condition simply owns a list of
## [MoveEffect]s ([member tick_effects]) that fire once per turn while it is
## active. So a burn is a [StatusCondition] whose tick_effects = [DamageEffect];
## a regen is one whose tick_effects = [HealEffect]; a timed buff is one whose
## tick_effects = [] plus an [member on_apply] / [member on_expire] pair (or a
## StatModifierEffect applied by the inflicting move).
##
## Ticking is deterministic: [method tick] builds a minimal [MoveContext] with
## the affected unit as its own caster over a single cell, then applies each
## effect in order — the exact same resolution path a move uses.

## How a freshly applied copy interacts with an identical condition already on
## the unit (matched by [member id]).
enum Stacking {
	REFRESH,  ## reset the existing condition's remaining duration; no new instance
	STACK,    ## add an independent second instance (both tick)
	IGNORE,   ## keep the existing condition unchanged; drop the new one
}

@export var id: StringName = &""
@export var display_name: String = ""
## Turns the condition lasts. Must be > 0, or -1 for permanent (never expires).
@export var duration_turns: int = 1
## Effects applied to the affected unit once per [method tick].
@export var tick_effects: Array[MoveEffect] = []
@export var stacking: Stacking = Stacking.REFRESH

## Ceiling on how many independent instances of this condition may be live on one
## unit at once — its SEVERITY cap. Only [constant Stacking.STACK] can ever reach
## it (REFRESH and IGNORE never add a second instance), and once it is reached a
## further application refreshes the OLDEST live instance instead of deepening the
## severity: re-applying a maxed poison keeps it on the target but cannot make it
## worse. Enforced by [method StatusController.add_status].
##
## -1 (the default) means UNBOUNDED, which is precisely how STACK behaved before
## this field existed — so every status authored until now is unchanged. It is the
## default rather than 1 for that reason: 1 would have silently demoted every
## existing STACK condition to REFRESH.
@export var max_stacks: int = -1

## Standing rules the condition imposes while it is active, queried rather than
## applied — the status-side mirror of [member TileEffectResource.rule_flags].
## A tick effect MUTATES the unit; a rule flag simply says the unit's rules are
## different right now, e.g. [code]{ "immobilized": true }[/code] (cannot move).
## Merged across every active condition by
## [method StatusController.has_rule_flag]; empty (the default) is inert, so a
## condition authored before this existed behaves exactly as it always did.
@export var rule_flags: Dictionary = {}

## Remaining turns for a live instance. Seeded from [member duration_turns] when
## the condition is added to a [StatusController]; -1 means permanent.
var turns_left: int = 0


## True while this live instance still has time on it (or is permanent).
func is_active() -> bool:
	return turns_left != 0


## True if this condition never expires on its own.
func is_permanent() -> bool:
	return duration_turns == -1


## Apply every tick effect to [param target] once, resolved through the shared
## effect pipeline. [param board] must expose the standard board interface
## (see [MoveContext]). Returns the accumulated event log for this tick.
func tick(target, board) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target == null or board == null:
		return events
	var cell: Vector2i = Vector2i.ZERO
	if board.has_method("cell_of"):
		cell = board.cell_of(target)
	var ctx := MoveContext.new(target, board, _tick_move(), cell, [cell] as Array[Vector2i])
	for effect in tick_effects:
		if effect:
			effect.apply(ctx)
	for e in ctx.results:
		events.append(e)
	return events


## Hook fired when the condition is first added to a unit. Empty by default;
## override via subclass or extend later (e.g. an initial stat modifier).
func on_apply(_target, _board) -> void:
	pass


## Hook fired when the condition expires or is cleared. Empty by default.
func on_expire(_target, _board) -> void:
	pass


## Synthetic self-targeted move used to route tick effects through a
## [MoveContext]. SELF targeting makes [method MoveContext.gather_targets]
## return exactly the affected unit.
func _tick_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"status_tick"
	m.display_name = display_name
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m
