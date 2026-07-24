extends RefCounted
class_name MoveLibrary

## Convenience factory that seeds a few example moves in code. These are meant as
## starting content / test fixtures — the shipping game should author moves as
## .tres files, which this system fully supports. Every move here is expressible
## purely as data (a TargetingPattern + effects), demonstrating the format.

## Plain adjacent hit, scales with attack.
static func basic_strike() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"basic_strike"
	m.display_name = "Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 1, CombatTypes.AreaShape.SINGLE, 0)
	m.effects = [_damage(24, "attack", 1.0, CombatTypes.DamageCategory.PHYSICAL)]
	return m


## Ranged area blast that hits every enemy in a diamond — "various enemies".
static func flame_burst() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"flame_burst"
	m.display_name = "Flame Burst"
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 3
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 3, CombatTypes.AreaShape.DIAMOND, 1)
	var burn := TileTransformEffect.new()
	burn.tile_id = &"fire"
	m.effects = [_damage(30, "magic", 1.0, CombatTypes.DamageCategory.MAGICAL), burn]
	return m


## Heal a nearby ally, scaling with magic.
static func mend() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"mend"
	m.display_name = "Mend"
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 2
	m.targeting = _pattern(CombatTypes.TargetKind.ALLY, 1, 2, CombatTypes.AreaShape.SINGLE, 0)
	var h := HealEffect.new()
	h.amount = 28
	h.scaling_stat = "magic"
	h.scale = 1.0
	m.effects = [h]
	return m


## Debuff an enemy's defense so allies hit harder.
static func expose() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"expose"
	m.display_name = "Expose"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 2, CombatTypes.AreaShape.SINGLE, 0)
	var d := StatModifierEffect.new()
	d.stat_name = "defense"
	d.amount = -6
	d.duration = 2
	m.effects = [d]
	return m


static func _pattern(kind, minr, maxr, shape, size) -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = kind
	p.min_range = minr
	p.max_range = maxr
	p.area_shape = shape
	p.area_size = size
	return p


static func _damage(power, stat, scale, cat) -> DamageEffect:
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = stat
	d.scale = scale
	d.category = cat
	return d
