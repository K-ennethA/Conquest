extends Resource
class_name AbilityResource

## A unique passive or triggered unit power, authored as data.
##
## An ability is standardized as: identity + a [member trigger] + an optional
## [member condition] + two composable payloads that reuse the shared pipeline:
##   - [member effects] — an ordered list of [MoveEffect]s, resolved against the
##     unit itself through a [MoveContext] (exactly how [StatusCondition] ticks).
##     This is how "heal after a kill" or "buff defense when wounded" are authored
##     with zero new code.
##   - [member rule_modifiers] — named integer/bool tweaks to the action economy
##     (see the vocabulary below), read by the turn/action system. This is how
##     "move twice" or "empowered movement on water" work without new effect code.
##
## Recognized [member rule_modifiers] keys (extend freely — unknown keys are just
## ignored by callers that don't understand them):
##   "extra_actions"       (int)  additional actions per turn ("act/move twice")
##   "extra_movement"      (int)  additional movement range this turn
##   "ignore_terrain_cost" (bool) movement ignores per-tile move cost
## Integer keys sum across active abilities; bool keys OR together
## (see [method AbilitySystem.passive_modifiers]).
##
## Author these as .tres files (fully inspector-editable) to add content without
## writing code — see [AbilityLibrary] for the in-code factory equivalents.

@export var id: StringName = &""
@export var display_name: String = "New Ability"
@export_multiline var description: String = ""

@export var trigger: AbilityTrigger.Trigger = AbilityTrigger.Trigger.PASSIVE
## Optional gate; null means unconditional (always met).
@export var condition: AbilityCondition
## Pipeline effects fired when the ability runs (see [method run_effects]).
@export var effects: Array[MoveEffect] = []
## Action-economy tweaks read by the turn system (see class docs for the keys).
@export var rule_modifiers: Dictionary = {}


## True when this ability's condition currently holds for [param unit]. A null
## condition is treated as always met.
func is_condition_met(unit, board) -> bool:
	if condition == null:
		return true
	return condition.is_met(unit, board)


## Apply every effect to [param unit] once, resolved through the shared effect
## pipeline. Builds a minimal self-targeted [MoveContext] over the unit's own cell
## — the same resolution path a move or a [StatusCondition] tick uses — so effects
## like [HealEffect] / [StatModifierEffect] land on the unit itself. Returns the
## accumulated event log. Does not check [member condition]; callers gate first
## via [method is_condition_met] (as [AbilitySystem] does).
func run_effects(unit, board) -> Array:
	if unit == null or board == null or effects.is_empty():
		return []
	var cell := Vector2i.ZERO
	if board.has_method("cell_of"):
		cell = board.cell_of(unit)
	var ctx := MoveContext.new(unit, board, _self_move(), cell, [cell] as Array[Vector2i])
	for effect in effects:
		if effect:
			effect.apply(ctx)
	return ctx.results


## Synthetic self-targeted move used to route ability effects through a
## [MoveContext]. SELF targeting + affects_caster_tile makes
## [method MoveContext.gather_targets] return exactly the acting unit.
func _self_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"ability"
	m.display_name = display_name
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m
