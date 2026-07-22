extends AugmentEffect
class_name StatEffect

## Flat delta to one of the unit's stats -- the first-class, composable form of the old
## stat_bonuses dictionary. Delegates to ArenaAugmentApplier.apply_stat so it uses the
## exact same engine path (modify_stat for engine-writable stats; a direct current_<stat>
## write for evasion/crit/magic, which UnitStats has no setter branch for).

## Author-facing stat key: max_health/hp, attack/atk, defense/def, speed/spd, movement/move,
## range, evasion, crit, magic, magic_defense/resistance, actions. Aliases canonicalize.
@export var stat: String = "attack"
@export var amount: int = 1


func apply_to_unit(unit, _run) -> void:
	if unit == null or amount == 0:
		return
	ArenaAugmentApplier.apply_stat(unit, stat, amount)


func describe() -> String:
	var sign_str: String = "+" if amount >= 0 else ""
	return "%s%d %s" % [sign_str, amount, _pretty_stat(stat)]


func _pretty_stat(key: String) -> String:
	match key.strip_edges().to_lower():
		"health", "hp", "max_health", "maxhp": return "Max HP"
		"attack", "atk": return "Attack"
		"defense", "def": return "Defense"
		"speed", "spd": return "Speed"
		"movement", "move": return "Move"
		"range": return "Range"
		"evasion", "eva", "evade": return "Evasion"
		"crit": return "Crit"
		"magic", "mag": return "Magic"
		"magic_defense", "mdef", "resistance", "res": return "Resistance"
		"actions", "act": return "Actions"
	return key.capitalize()
