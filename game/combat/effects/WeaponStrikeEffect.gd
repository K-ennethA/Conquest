extends DamageEffect
class_name WeaponStrikeEffect

## A HUMAN's WEAPON ATTACK (DECISIONS.md #54: the Fire Emblem "attack with a weapon"). Exactly a
## [DamageEffect] -- the same raw power (the weapon's might + the wielder's stat), mitigation,
## shared [DamageMath] chain, crit and log -- that also says WHICH WEAPON TYPE struck, so the
## chain's weapon-triangle step ([method DamageMath.weapon_triangle_scale_for]) can read it.
## Built only by [method WeaponResource.attack_move]; never authored by hand.

## The striking weapon's [member WeaponResource.weapon_type] (&"sword", &"lance" ...).
@export var weapon_type: StringName = &""
## The striking weapon's id (presentation / logs only).
@export var weapon_id: StringName = &""


func describe() -> String:
	if description_override != "":
		return description_override
	return "Weapon strike: %d might + %s" % [power, scaling_stat]
