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
