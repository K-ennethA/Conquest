extends AugmentEffect
class_name GrantAbilityEffect

## Grants a TRIGGERED PASSIVE to a squad unit -- the composable augment form of "on kill,
## heal 20%" or "at turn start, gain a shield". It does NOT invent a parallel mechanism:
## it attaches a real [AbilityResource] onto the unit's [AbilitySystem], the exact same
## component and attach path a character's OWN abilities use (see Unit._setup_components,
## which creates an "AbilitySystem" child and calls add_ability for each authored ability).
## Once attached, the ability fires on its own trigger during combat -- ON_KILL, ON_TURN_
## START, ... -- driven by the AbilitySystem's event wiring, with zero augment-specific
## runtime code.
##
## Abilities are referenced the way the rest of the codebase references them: a DIRECT
## [AbilityResource] ref (mirroring [member CharacterResource.abilities], which is an
## Array[AbilityResource] of direct refs, and how deathbloom.tres / natures_blessing.tres
## are loaded). [member ability_id] is an optional convenience that resolves one of the
## in-code [AbilityLibrary] sample abilities by name when no direct ref is authored.

## The ability to grant, as a direct resource ref (preferred). Point this at an authored
## .tres (e.g. res://game/arena/abilities/lifesteal_on_kill.tres).
@export var ability: AbilityResource

## Optional fallback: resolve one of the [AbilityLibrary] sample abilities by id when
## [member ability] is left unset. Unknown ids resolve to null (the effect then no-ops).
@export var ability_id: StringName = &""


## Attach the resolved ability to [param unit]'s AbilitySystem so its trigger fires in
## combat. Null-safe end to end: a missing ability, a unit that cannot host a component,
## or an ability already present are all skipped rather than raised.
func apply_to_unit(unit, _run) -> void:
	if unit == null:
		return
	var resolved: AbilityResource = _resolve_ability()
	if resolved == null:
		return
	var system = _ensure_ability_system(unit)
	if system == null:
		return
	if _already_has(system, resolved):
		return
	system.add_ability(resolved)


## The unit's live AbilitySystem, creating and attaching one the SAME way
## Unit._setup_components does when the character declares no abilities of its own: a child
## node named "AbilitySystem" whose owner_unit is the unit, so its trigger routing and
## _unit() resolution work identically. Returns null when the unit cannot host a child.
func _ensure_ability_system(unit):
	if unit.has_method("get_ability_system"):
		var existing = unit.get_ability_system()
		if existing != null:
			return existing
	if not unit.has_method("add_child"):
		return null
	var system := AbilitySystem.new()
	system.name = "AbilitySystem"
	system.owner_unit = unit
	unit.add_child(system)
	return system


## True when [param system] already carries [param resolved] (same instance, or an ability
## sharing its non-blank id) -- guards against a run-wide and a per-unit augment granting
## the same passive twice on one rebuild.
func _already_has(system, resolved: AbilityResource) -> bool:
	if system == null or not ("abilities" in system):
		return false
	var existing_list: Array = system.abilities
	for a in existing_list:
		if a == resolved:
			return true
		if a is AbilityResource and resolved.id != &"" and a.id == resolved.id:
			return true
	return false


## The ability to grant: the direct ref when set, else the named [AbilityLibrary] sample,
## else null.
func _resolve_ability() -> AbilityResource:
	if ability != null:
		return ability
	if ability_id != &"":
		return _library_ability(ability_id)
	return null


## Best-effort resolution of an [AbilityLibrary] sample factory by id (the library exposes
## no generic id->resource map, so this matches its known factories). Null for anything
## else -- authored abilities should use the direct [member ability] ref instead.
func _library_ability(id: StringName) -> AbilityResource:
	match id:
		&"vampiric":
			return AbilityLibrary.vampiric()
		&"blitz":
			return AbilityLibrary.blitz()
		&"amphibious":
			return AbilityLibrary.amphibious()
		&"last_stand":
			return AbilityLibrary.last_stand()
	return null


## One-line description for the draft card / creator preview, pulled from the granted
## ability's own name + description, with sensible fallbacks.
func describe() -> String:
	var resolved: AbilityResource = _resolve_ability()
	if resolved != null:
		var nm: String = resolved.display_name
		var desc: String = resolved.description
		if nm != "" and desc != "":
			return "Grants %s -- %s" % [nm, desc]
		if nm != "":
			return "Grants %s" % nm
	if ability_id != &"":
		return "Grants ability %s" % String(ability_id)
	return "Grants a passive ability"
