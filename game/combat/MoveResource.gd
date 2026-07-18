extends Resource
class_name MoveResource

## A single move (ability). Standardized as: identity + a [TargetingPattern] +
## an ordered list of [MoveEffect]s. Any combination of effects is legal, so one
## data format expresses everything from a plain melee hit to an area spell that
## damages several enemies, buffs allies, and scorches the terrain at once.
##
## Author these as .tres files (fully inspector-editable) to add content without
## writing code.

@export var move_id: StringName = &""
@export var display_name: String = "New Move"
@export_multiline var description: String = ""
@export var icon: Texture2D

@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL
## Resource spent to use the move (energy/mana). 0 = free.
@export var energy_cost: int = 0
## Limited charges per battle. -1 = unlimited.
@export var max_uses: int = -1
## Turns that must pass after use before the move is available again.
## 0 = no cooldown (usable every turn, subject to [member max_uses]).
@export var cooldown: int = 0
## Hit chance 0..1 before the target's evasion is subtracted (resolved by the
## executor / RNG layer). 1.0 = always lands against a 0-evasion target.
@export var accuracy: float = 1.0
## Base critical-hit chance 0..1, added to the caster's "crit" stat. A crit deals
## [constant CombatTypes.CRIT_MULTIPLIER]x damage.
@export var crit_chance: float = 0.0

@export var targeting: TargetingPattern
@export var effects: Array[MoveEffect] = []


func is_valid() -> bool:
	return targeting != null and not effects.is_empty()


## True if a caster on [param origin] may legally aim this move at [param aim].
func can_aim_at(origin: Vector2i, aim: Vector2i) -> bool:
	return targeting != null and targeting.in_range(origin, aim)


## Build a full description from the effect list (for tooltips).
func full_description() -> String:
	if description != "":
		return description
	var parts: Array[String] = []
	for e in effects:
		if e:
			parts.append(e.describe())
	var body := ", ".join(parts)
	if targeting:
		body += " (%s)" % targeting.describe_range()
	return body
