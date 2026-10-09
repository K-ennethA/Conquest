extends Resource
class_name WeaponRules

## THE HUMAN WEAPON TUNING SURFACE (CONQUEST.md rule 11: knobs live on a data resource) --
## game/characters/weapons/weapon_rules.tres. docs/design/HUMANS.md is the as-built spec.
##
##   * [member weapon_types] -- the Fire Emblem weapon types as data ([WeaponTypeResource]).
##   * THE WEAPON TRIANGLE -- [member triangle_enabled] (DEFAULT ON) + [member triangle_beats]
##     + [member triangle_damage_bonus]. It is step 7 of [method DamageMath.apply_scales] and
##     applies ONLY when a WEAPON STRIKE ([WeaponStrikeEffect]) hits a HUMAN who wields a weapon
##     of a type the table relates: a creature is never on the triangle, so every creature-vs-
##     creature (and creature-vs-human) number in every mode is unchanged. ON by default because
##     it can only touch human-vs-human weapon strikes, which no open-mode content had before
##     humans became battle units.

const RULES_PATH := "res://game/characters/weapons/weapon_rules.tres"

@export var weapon_types: Array[WeaponTypeResource] = []

@export_group("Weapon triangle")
## Master switch. Off = no weapon type ever beats another (every strike x1.0).
@export var triangle_enabled: bool = true
## ADVANTAGE table: key type BEATS value type ("sword" beats "axe"). Classic Fire Emblem:
## sword > axe > lance > sword. Types not in the table (bow, staff, tome) are neutral.
@export var triangle_beats: Dictionary = {"sword": "axe", "axe": "lance", "lance": "sword"}
## Damage multiplier step: advantage x(1 + bonus), disadvantage x(1 - bonus).
@export_range(0.0, 1.0, 0.01) var triangle_damage_bonus: float = 0.15

static var _current: WeaponRules = null


static func current() -> WeaponRules:
	if _current == null:
		if ResourceLoader.exists(RULES_PATH):
			_current = load(RULES_PATH) as WeaponRules
		if _current == null:
			_current = WeaponRules.new()
	return _current


## Tests swap the rules in (and back out with null).
static func set_current(rules: WeaponRules) -> void:
	_current = rules


## The [WeaponTypeResource] for [param type_id], or null when it is not a known type.
func type_of(type_id: StringName) -> WeaponTypeResource:
	for t in weapon_types:
		if t != null and t.type_id == type_id:
			return t
	return null


func has_type(type_id: StringName) -> bool:
	return type_of(type_id) != null


func type_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t in weapon_types:
		if t != null and not String(t.type_id).is_empty():
			out.append(t.type_id)
	return out


## +1 when [param attacker_type] beats [param defender_type], -1 when it is beaten, 0 otherwise
## (or with the triangle off / either type empty).
func triangle_edge(attacker_type: StringName, defender_type: StringName) -> int:
	if not triangle_enabled or attacker_type == &"" or defender_type == &"" or attacker_type == defender_type:
		return 0
	if String(triangle_beats.get(String(attacker_type), "")) == String(defender_type):
		return 1
	if String(triangle_beats.get(String(defender_type), "")) == String(attacker_type):
		return -1
	return 0


## The damage multiplier for [param attacker_type] striking a wielder of [param defender_type].
func triangle_scale(attacker_type: StringName, defender_type: StringName) -> float:
	var edge: int = triangle_edge(attacker_type, defender_type)
	if edge == 0:
		return 1.0
	return maxf(0.0, 1.0 + float(edge) * triangle_damage_bonus)


## Audit the rules; returns human-readable problems (empty == clean).
func validate() -> Array[String]:
	var issues: Array[String] = []
	var seen: Array[StringName] = []
	for t in weapon_types:
		if t == null:
			issues.append("weapon_types has an empty slot")
			continue
		if String(t.type_id).is_empty():
			issues.append("a weapon type has no type_id")
		elif seen.has(t.type_id):
			issues.append("weapon type '%s' is listed twice" % t.type_id)
		seen.append(t.type_id)
		if t.scaling_stat != "attack" and t.scaling_stat != "magic":
			issues.append("weapon type '%s' scales with '%s' (attack / magic)" % [t.type_id, t.scaling_stat])
	for k in triangle_beats.keys():
		if not seen.has(StringName(String(k))):
			issues.append("triangle names unknown type '%s'" % k)
		if not seen.has(StringName(String(triangle_beats[k]))):
			issues.append("triangle names unknown type '%s'" % triangle_beats[k])
	return issues
