extends RefCounted
class_name AbilityLibrary

## Convenience factory that seeds a few example abilities in code. Like
## [MoveLibrary], these are starting content / test fixtures — the shipping game
## should author abilities as .tres files, which this system fully supports. Each
## one is expressible purely as data (a trigger + condition + effects and/or rule
## modifiers), demonstrating the range: a terrain-keyed passive, an action-economy
## passive, a triggered self-heal, and a conditional buff. Neutral flavor only.


## PASSIVE, terrain-keyed: while standing on water, gain +2 movement range.
## Pure rule-modifier — "empowered on water" with no new code.
static func amphibious() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"amphibious"
	a.display_name = "Amphibious"
	a.description = "Surges an extra 2 tiles while standing on water."
	a.trigger = AbilityTrigger.Trigger.PASSIVE
	var cond := OnTerrainCondition.new()
	cond.terrain_id = &"water"
	a.condition = cond
	a.rule_modifiers = { "extra_movement": 2 }
	return a


## PASSIVE, unconditional: +1 action per turn — the data form of "act twice".
static func blitz() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"blitz"
	a.display_name = "Blitz"
	a.description = "Takes one additional action each turn."
	a.trigger = AbilityTrigger.Trigger.PASSIVE
	a.condition = AlwaysCondition.new()
	a.rule_modifiers = { "extra_actions": 1 }
	return a


## ON_KILL: restore health to self after defeating a foe. Reuses [HealEffect]
## through the shared pipeline, targeting the acting unit.
static func vampiric() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"vampiric"
	a.display_name = "Vampiric"
	a.description = "Restores 15 health after defeating an enemy."
	a.trigger = AbilityTrigger.Trigger.ON_KILL
	a.condition = AlwaysCondition.new()
	var heal := HealEffect.new()
	heal.amount = 15
	heal.scaling_stat = ""
	a.effects = [heal]
	return a


## PASSIVE, conditional: while below 30% health, fortify defense. Reuses
## [StatModifierEffect]; the turn system fires PASSIVE effects while the condition
## holds (see [method AbilitySystem.trigger]).
static func last_stand() -> AbilityResource:
	var a := AbilityResource.new()
	a.id = &"last_stand"
	a.display_name = "Last Stand"
	a.description = "Hardens defense by 5 while gravely wounded (under 30% health)."
	a.trigger = AbilityTrigger.Trigger.PASSIVE
	var cond := HealthBelowCondition.new()
	cond.threshold = 0.3
	a.condition = cond
	var buff := StatModifierEffect.new()
	buff.stat_name = "defense"
	buff.amount = 5
	buff.duration = -1  # sustained while the passive holds
	a.effects = [buff]
	return a


## Every sample ability, for quick iteration / test coverage.
static func all() -> Array[AbilityResource]:
	return [amphibious(), blitz(), vampiric(), last_stand()]
