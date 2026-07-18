extends RefCounted
class_name TileEffectLibrary

## Convenience factory that seeds a few example [TileEffectResource]s in code.
## These are starting content / test fixtures — the shipping game should author
## tile effects as .tres files, which this system fully supports. Every effect
## here is expressible purely as data (a trigger + condition + effect list),
## demonstrating the format. Flavour is deliberately neutral.

## Scorched terrain: burns whatever stands on it at the start of each turn.
static func fire() -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"fire"
	te.display_name = "Fire"
	te.trigger = TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING
	te.affected_factions = TileEffectResource.AffectedFactions.ALL
	var dmg := DamageEffect.new()
	dmg.power = 15
	dmg.scaling_stat = ""  # environmental: flat, unrelated to any attacker stat
	dmg.category = CombatTypes.DamageCategory.TRUE  # unmitigated burn
	var fx: Array[MoveEffect] = [dmg]
	te.effects = fx
	return te


## Deep water: a standing state that empowers only aquatic-tagged occupants.
static func empowering_water() -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"empowering_water"
	te.display_name = "Empowering Water"
	te.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
	te.affected_factions = TileEffectResource.AffectedFactions.ALL
	te.required_unit_tag = &"aquatic"
	var buff := StatModifierEffect.new()
	buff.stat_name = "attack"
	buff.amount = 4
	buff.duration = 1  # short: the integration re-applies it while occupying
	var fx: Array[MoveEffect] = [buff]
	te.effects = fx
	return te


## Fortified ground: raises the fortified flag and boosts defense while occupied.
static func fortify() -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"fortify"
	te.display_name = "Fortify"
	te.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
	te.affected_factions = TileEffectResource.AffectedFactions.ALL
	te.rule_flags = { "fortified": true }
	var buff := StatModifierEffect.new()
	buff.stat_name = "defense"
	buff.amount = 3
	buff.duration = 1
	var fx: Array[MoveEffect] = [buff]
	te.effects = fx
	return te


## Concealing terrain: a pure rule-flag state — the occupant is untargetable.
static func stealth() -> TileEffectResource:
	var te := TileEffectResource.new()
	te.id = &"stealth"
	te.display_name = "Stealth"
	te.trigger = TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING
	te.affected_factions = TileEffectResource.AffectedFactions.ALL
	te.rule_flags = { "untargetable": true }
	return te
