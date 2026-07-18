extends Node
class_name AbilitySystem

## Per-unit component that owns the unit's [AbilityResource]s and evaluates them.
##
## Attach one to a unit (or hold one on a mock in tests) and populate
## [member abilities]. The turn / action system drives it two ways:
##   - [method trigger] — on a gameplay event (turn start, kill, …), run the
##     pipeline effects of every ability whose trigger matches and whose condition
##     holds. Deterministic (insertion order), so networked peers resolve alike.
##   - [method passive_modifiers] — ask, on demand, for the merged action-economy
##     tweaks of all currently-in-force PASSIVE abilities, e.g. "how many extra
##     actions / movement does this unit have on its current tile right now?".
##
## Ability effects and rule-modifier vocabulary live on [AbilityResource].

## The unit these abilities belong to; passed as the acting unit when an explicit
## one isn't supplied. Defaults to the parent node if left unset.
var owner_unit

var abilities: Array[AbilityResource] = []


func _ready() -> void:
	if owner_unit == null:
		owner_unit = get_parent()


## Convenience: register an ability. Returns it for chaining in setup code.
func add_ability(ability: AbilityResource) -> AbilityResource:
	if ability != null:
		abilities.append(ability)
	return ability


## Fire every ability whose [member AbilityResource.trigger] equals [param event]
## and whose condition currently holds, applying each one's pipeline effects to
## [param unit] (defaults to [member owner_unit]). Returns the combined event log.
func trigger(event: AbilityTrigger.Trigger, unit = null, board = null) -> Array:
	var acting = unit if unit != null else _unit()
	var events: Array = []
	for ability in abilities:
		if ability == null or ability.trigger != event:
			continue
		if not ability.is_condition_met(acting, board):
			continue
		for e in ability.run_effects(acting, board):
			events.append(e)
	return events


## Merged [member AbilityResource.rule_modifiers] of every PASSIVE ability whose
## condition currently holds for [param unit]. Integer values sum across abilities;
## bool values OR together; any other value type is last-write-wins. Callers read
## the result to adjust the action economy (extra actions, movement, terrain-cost
## rules, …). Abilities whose condition is unmet contribute nothing.
func passive_modifiers(unit = null, board = null) -> Dictionary:
	var acting = unit if unit != null else _unit()
	var merged: Dictionary = {}
	for ability in abilities:
		if ability == null or ability.trigger != AbilityTrigger.Trigger.PASSIVE:
			continue
		if ability.rule_modifiers.is_empty():
			continue
		if not ability.is_condition_met(acting, board):
			continue
		_merge_modifiers(merged, ability.rule_modifiers)
	return merged


## Extra actions granted this turn by in-force passives ("act/move twice").
func extra_actions(unit = null, board = null) -> int:
	return int(passive_modifiers(unit, board).get("extra_actions", 0))


## Extra movement range granted this turn by in-force passives.
func extra_movement(unit = null, board = null) -> int:
	return int(passive_modifiers(unit, board).get("extra_movement", 0))


## True if any in-force passive sets the named boolean rule flag
## (e.g. "ignore_terrain_cost").
func has_flag(flag_name: String, unit = null, board = null) -> bool:
	return bool(passive_modifiers(unit, board).get(flag_name, false))


func _merge_modifiers(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		var val = from[key]
		if val is bool:
			into[key] = bool(into.get(key, false)) or val
		elif val is int or val is float:
			var current = into.get(key, 0)
			if current is bool:
				current = 1 if current else 0
			into[key] = current + val  # int + int stays int; float propagates
		else:
			into[key] = val  # non-numeric, non-bool: last write wins


func _unit():
	return owner_unit if owner_unit != null else get_parent()
