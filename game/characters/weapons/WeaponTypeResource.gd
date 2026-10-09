extends Resource
class_name WeaponTypeResource

## ONE WEAPON TYPE (Fire Emblem style: sword, lance, axe, bow, staff, tome ...) as DATA
## (docs/design/HUMANS.md, DECISIONS.md #54 / #63). A type says what KIND of strike a weapon of
## it makes -- physical or magical, which caster stat it scales with -- and its default reach.
## The list lives on [WeaponRules] (game/characters/weapons/weapon_rules.tres); adding a type is
## a data edit there plus a [WeaponResource] that names it.

## Stable id a [WeaponResource] names ([member WeaponResource.weapon_type]): &"sword", &"lance" ...
@export var type_id: StringName = &""
@export var display_name: String = ""
## PHYSICAL (mitigated by defense) or MAGICAL (by magic defense) -- the strike's damage category.
@export var category: CombatTypes.DamageCategory = CombatTypes.DamageCategory.PHYSICAL
## The caster stat the strike adds to the weapon's might: "attack" or "magic".
@export var scaling_stat: String = "attack"
## The reach a weapon of this type gets when it authors none (min_range / max_range 0).
@export var default_min_range: int = 1
@export var default_max_range: int = 1
## The verb a strike of this type is named with when the weapon has no attack_name ("Slash").
@export var verb: String = "Strike"


func is_magical() -> bool:
	return category == CombatTypes.DamageCategory.MAGICAL
