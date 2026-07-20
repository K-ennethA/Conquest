extends MoveEffect
class_name DamageEffect

## Deals damage to every valid target in the area, scaled by a caster stat and
## mitigated by the defender's matching defense stat.

@export var power: int = 20
## Caster stat added to power (e.g. "attack" or "magic"). Empty = flat power.
@export var scaling_stat: String = "attack"
## Fraction of the scaling stat added to power.
@export var scale: float = 1.0
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL


func apply(ctx: MoveContext) -> void:
	var bonus := 0
	if scaling_stat != "":
		bonus = int(round(ctx.get_caster_stat(scaling_stat) * scale))
	var raw := power + bonus

	for target in ctx.gather_targets():
		var outcome := ctx.resolve_hit(target)
		if not outcome.get("hit", true):
			ctx.log_event({
				"effect": "damage",
				"target": target,
				"amount": 0,
				"category": category,
				"missed": true,
			})
			continue
		var dealt := _mitigate(raw, target)
		# Predation bonus: a caster whose passives declare "damage_vs_restricted"
		# hits harder into a target that cannot get away. Applied AFTER mitigation
		# and BEFORE crit, so it scales what the defender actually takes and a crit
		# then multiplies the already-boosted number.
		var restricted_scale: float = _restricted_scale(ctx, target)
		if restricted_scale > 1.0:
			dealt = maxi(1, int(round(float(dealt) * restricted_scale)))
		var crit: bool = outcome.get("crit", false)
		if crit:
			dealt = maxi(1, int(round(dealt * CombatTypes.CRIT_MULTIPLIER)))
		if target.has_method("take_damage"):
			target.take_damage(dealt)
		_announce(ctx, target, dealt)
		ctx.log_event({
			"effect": "damage",
			"target": target,
			"amount": dealt,
			"category": category,
			"crit": crit,
		})


func describe() -> String:
	if description_override != "":
		return description_override
	return "Deal %d %s damage" % [power, CombatTypes.DamageCategory.keys()[category].to_lower()]


## Announce one landed hit on the game-wide bus as
## [code]damage_dealt(attacker, defender, damage)[/code].
##
## This is the single emit point for that signal, and it is what finally lights up
## everything already listening for it — the hit flash and the attack/hit clips in
## [UnitAnimator], and the ON_ATTACK / ON_DAMAGED ability triggers routed by
## [AbilitySystem].
##
## Routed through [member MoveContext.event_bus] when a bus is injected, else the
## [code]GameEvents[/code] autoload. Guarded end to end so a headless or mocked
## context never errors: no bus, no such signal, or non-[Unit] participants (the
## autoload's signal is typed, so mocks must not reach it) all simply no-op.
static func _announce(ctx: MoveContext, target, dealt: int) -> void:
	if ctx == null or target == null:
		return
	var bus = ctx.event_bus
	if bus == null:
		if not (ctx.caster is Unit and target is Unit):
			return
		bus = GameEvents
	if bus == null or not bus.has_signal(&"damage_dealt"):
		return
	bus.emit_signal(&"damage_dealt", ctx.caster, target, dealt)


# --- Damage vs movement-restricted targets ----------------------------------
#
# Routed entirely through the EXISTING passive-modifier mechanism rather than a
# bespoke path: a PASSIVE AbilityResource contributes
# `rule_modifiers = { "damage_vs_restricted": 0.5 }` (= +50%), AbilitySystem
# merges it exactly like "extra_actions"/"extra_movement", and this effect reads
# the merged value. Null-safe end to end -- no ability system, no statuses, no
# board, or a mock unit missing any of the accessors all resolve to plain damage.


## Multiplier to apply to one hit: 1.0 normally, or 1.0 + the caster's merged
## "damage_vs_restricted" modifier when the TARGET is movement-restricted.
static func _restricted_scale(ctx: MoveContext, target) -> float:
	if ctx == null or target == null:
		return 1.0
	if not _is_movement_restricted(target):
		return 1.0
	var bonus: float = _caster_restricted_modifier(ctx)
	if bonus <= 0.0:
		return 1.0
	return 1.0 + bonus


## The caster's merged "damage_vs_restricted" rule modifier (0.0 when it has no
## ability system, or no in-force passive that declares one).
static func _caster_restricted_modifier(ctx: MoveContext) -> float:
	var caster = ctx.caster
	if caster == null:
		return 0.0
	# A live Unit exposes its component; a test mock may BE the ability system.
	var system = null
	if caster.has_method("get_ability_system"):
		system = caster.get_ability_system()
	elif caster.has_method("passive_modifiers"):
		system = caster
	if system == null or not system.has_method("passive_modifiers"):
		return 0.0
	var modifiers: Dictionary = system.passive_modifiers(caster, ctx.board)
	return float(modifiers.get("damage_vs_restricted", 0.0))


## Is [param target] movement-restricted right now?
##
## DEFINITION (deliberately narrow, so the bonus is legible to the player):
##   1. an active status sets the "immobilized" rule flag (Ensnared, Ingrained) —
##      the unit cannot move at all; OR
##   2. the unit's CURRENT "movement" stat is below its BASE — i.e. something is
##      actively slowing it (Entangled's negative StatModifierEffect).
##
## A unit that simply has low base movement is NOT restricted — only one that has
## been restricted by something. Both checks are duck-typed and independently
## optional, so a mock exposing neither is never treated as restricted.
static func _is_movement_restricted(target) -> bool:
	if target == null:
		return false
	if target.has_method("is_immobilized") and bool(target.is_immobilized()):
		return true
	if target.has_method("has_status_rule_flag") and bool(target.has_status_rule_flag(&"immobilized")):
		return true
	if target.has_method("get_status_controller"):
		var controller = target.get_status_controller()
		if controller != null and controller.has_method("has_rule_flag") \
			and bool(controller.has_rule_flag(&"immobilized")):
			return true
	if target.has_method("get_stat") and target.has_method("get_base_stat"):
		var base_movement: int = int(target.get_base_stat("movement"))
		# Guard the "no movement stat at all" case: 0 base would make any unit with
		# 0 current movement read as slowed.
		if base_movement > 0 and int(target.get_stat("movement")) < base_movement:
			return true
	return false


func _mitigate(raw: int, target) -> int:
	match category:
		CombatTypes.DamageCategory.TRUE:
			return maxi(1, raw)
		CombatTypes.DamageCategory.MAGICAL:
			var res := _stat_or(target, "magic_defense", _stat_or(target, "defense", 0))
			return maxi(1, raw - res)
		_:  # PHYSICAL
			return maxi(1, raw - _stat_or(target, "defense", 0))


static func _stat_or(unit, stat_name: String, fallback: int) -> int:
	if unit and unit.has_method("get_stat"):
		var v: int = unit.get_stat(stat_name)
		return v if v > 0 else fallback
	return fallback
