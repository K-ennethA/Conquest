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
##   "damage_vs_restricted" (float) fractional bonus damage this unit deals to a
##                          movement-restricted target (0.5 = +50%); read by
##                          [DamageEffect] — see its _is_movement_restricted for
##                          exactly what counts as restricted
## Integer keys sum across active abilities; bool keys OR together
## (see [method AbilitySystem.passive_modifiers]).
##
## Author these as .tres files (fully inspector-editable) to add content without
## writing code — see [AbilityLibrary] for the in-code factory equivalents.

@export var id: StringName = &""
@export var display_name: String = "New Ability"
@export_multiline var description: String = ""

## Optional inspector art for ability lists / tooltips. Purely cosmetic.
@export var icon: Texture2D

## The ONE moment this ability fires on. An ability that has to land on two different
## moments -- or on the same moment under two different conditions -- is authored as TWO
## resources listed side by side on the character, not as a multi-trigger schema: the
## [member condition] is per-ability, so a second trigger sharing it could not be gated
## differently. Geode's ward is the worked example: `crystalline_ward_initial.tres`
## (ON_BATTLE_START, ungated) plus `crystalline_ward.tres` (ON_TURN_START, gated on three
## untouched turns), both granting the same 15 through [ShieldEffect] -- which refreshes
## rather than stacks, so the pair can never compound.
@export var trigger: AbilityTrigger.Trigger = AbilityTrigger.Trigger.PASSIVE
## Optional gate; null means unconditional (always met). Compose several with
## [AllCondition] / [AnyCondition] / [NotCondition].
@export var condition: AbilityCondition
## Pipeline effects fired when the ability runs (see [method run_effects]).
@export var effects: Array[MoveEffect] = []
## Action-economy tweaks read by the turn system (see class docs for the keys).
@export var rule_modifiers: Dictionary = {}

## Optional area the effects cover, exactly as a [MoveResource] uses one.
## Null (the default) keeps the legacy self-targeted behaviour; set it to reach
## allies in a radius, adjacent enemies, and so on (see [method run_effects]).
@export var targeting: TargetingPattern

## When true the effects are anchored on the unit that CAUSED the trigger — the
## attacker for ON_DAMAGED, the victim for ON_ATTACK / ON_KILL — instead of on
## this ability's own unit. No-ops when no triggering unit was supplied.
@export var targets_triggering_unit: bool = false

## Turns that must pass between activations (0 = every time it triggers).
## Tracked per unit by [AbilitySystem], counted down by its
## [method AbilitySystem.tick_cooldowns] — never stored on this shared resource.
@export var cooldown: int = 0
## Total activations allowed per battle (-1 = unlimited, 1 = once per battle).
## Also tracked per unit by [AbilitySystem].
@export var max_activations: int = -1


## True when this ability's condition currently holds for [param unit]. A null
## condition is treated as always met.
func is_condition_met(unit, board) -> bool:
	if condition == null:
		return true
	return condition.is_met(unit, board)


## Apply every effect once, resolved through the shared effect pipeline — the
## same resolution path a move or a [StatusCondition] tick uses, so effects like
## [HealEffect] / [DamageEffect] / [StatModifierEffect] need no ability-specific
## code. [param other] is the unit that caused the trigger (the attacker for
## ON_DAMAGED, the victim for ON_ATTACK / ON_KILL), or null.
##
## The acting unit is ALWAYS the caster, so ALLY / ENEMY targeting stays relative
## to it. What changes is the area:
##   - no [member targeting] — exactly the anchor's own cell, as it has always
##     been. With [member targets_triggering_unit] off this is the legacy
##     self-buff behaviour, byte for byte.
##   - a [member targeting] pattern — the pattern resolved from the acting unit's
##     cell (the origin) toward the anchor cell (the aim), so an ability can heal
##     allies in a radius, strike adjacent enemies, and so on.
## The anchor is the acting unit itself, or [param other] when
## [member targets_triggering_unit] is set (and nothing happens if there is none).
##
## Returns the accumulated event log. Does not check [member condition]; callers
## gate first via [method is_condition_met] (as [AbilitySystem] does).
func run_effects(unit, board, other = null) -> Array:
	if unit == null or board == null or effects.is_empty():
		return []
	var anchor = unit
	if targets_triggering_unit:
		if other == null:
			return []  # nothing caused this trigger — nothing to affect
		anchor = other
	var origin := _cell_of(board, unit)
	var aim: Vector2i = origin if anchor == unit else _cell_of(board, anchor)
	var cells: Array[Vector2i] = [aim] as Array[Vector2i]
	if targeting != null:
		cells = targeting.resolve_cells(origin, aim)
	var ctx := MoveContext.new(unit, board, _synthetic_move(), aim, cells)
	for effect in effects:
		if effect:
			effect.apply(ctx)
	return ctx.results


## Synthetic move used to route ability effects through a [MoveContext] — it
## carries the targeting pattern that decides WHICH units in the resolved cells
## are gathered.
##
## Three cases, in order: an authored [member targeting] is used verbatim; else a
## triggering-unit ability gets ANY_UNIT (the attacker/victim is gathered whatever
## side it is on); else the historical SELF pattern, where SELF + affects_caster_tile
## makes [method MoveContext.gather_targets] return exactly the acting unit.
func _synthetic_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"ability"
	m.display_name = display_name
	if targeting != null:
		m.targeting = targeting
		return m
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ANY_UNIT if targets_triggering_unit else CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m


## The board cell [param who] stands on, or [code]Vector2i.ZERO[/code] when the
## board cannot report one (mock boards in tests may omit the accessor).
func _cell_of(board, who) -> Vector2i:
	if board.has_method("cell_of"):
		return board.cell_of(who)
	return Vector2i.ZERO
