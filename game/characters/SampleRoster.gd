extends RefCounted
class_name SampleRoster

## In-code factory that builds a small, varied pool of sample moves and a starter
## roster of custom [CharacterResource]s for playtesting and move authoring.
##
## Everything here is expressible purely as data (a [MoveResource] is a
## [TargetingPattern] plus an ordered list of [MoveEffect]s; a character is
## identity + base stats + up to four moves). This mirrors [MoveLibrary]'s style
## but adds full characters with placeholder 3D models so the game has something
## concrete to spawn. The shipping game can also author this same content as
## .tres files — see build_sample_content.gd, which serializes what is built here.
##
## All names/flavor are original and franchise-neutral.

## Placeholder base models, one per archetype. Referenced so each saved character
## points at a spawnable scene out of the box.
const MODEL_BRUISER: PackedScene = preload("res://game/characters/models/bruiser_model.tscn")
const MODEL_TANK: PackedScene = preload("res://game/characters/models/tank_model.tscn")
const MODEL_ARCHER: PackedScene = preload("res://game/characters/models/archer_model.tscn")
const MODEL_MAGE: PackedScene = preload("res://game/characters/models/mage_model.tscn")
const MODEL_SCOUT: PackedScene = preload("res://game/characters/models/scout_model.tscn")
const MODEL_SUPPORT: PackedScene = preload("res://game/characters/models/support_model.tscn")
const MODEL_BOSS: PackedScene = preload("res://game/characters/models/boss_model.tscn")


# --- Move pool -------------------------------------------------------------
# Eight varied moves that together exercise every corner of the system:
# single-target melee, ranged single, an AoE that also scorches terrain, a heal,
# an ally buff, an enemy defense debuff, a knockback, and a boss signature that
# stacks area damage + knockback + terrain change.

## Plain adjacent melee hit, scales with attack.
static func move_cleave() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"cleave"
	m.display_name = "Cleave"
	m.element = &"steel"
	m.description = "A heavy adjacent swing. Deal physical damage to one enemy."
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 1, CombatTypes.AreaShape.SINGLE, 0)
	m.effects = [_damage(22, "attack", 1.0, CombatTypes.DamageCategory.PHYSICAL)]
	return m


## Long single-target shot, scales with attack.
static func move_piercing_shot() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"piercing_shot"
	m.display_name = "Piercing Shot"
	m.element = &"steel"
	m.description = "A precise ranged bolt that strikes a distant enemy."
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.energy_cost = 1
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 2, 4, CombatTypes.AreaShape.SINGLE, 0)
	m.effects = [_damage(20, "attack", 1.0, CombatTypes.DamageCategory.PHYSICAL)]
	return m


## Ranged diamond blast: damages every enemy in the area AND scorches the terrain.
static func move_ember_storm() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"ember_storm"
	m.display_name = "Ember Storm"
	m.element = &"ember"
	m.description = "Rain embers over an area, burning nearby enemies and scorching the ground."
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 3
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 3, CombatTypes.AreaShape.DIAMOND, 1)
	var burn := TileTransformEffect.new()
	burn.tile_id = &"scorched"
	m.effects = [_damage(26, "magic", 1.0, CombatTypes.DamageCategory.MAGICAL), burn]
	return m


## Restore health to a nearby ally, scaling with magic.
static func move_soothing_light() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"soothing_light"
	m.display_name = "Soothing Light"
	m.element = &"holy"
	m.description = "Mend a wounded ally, restoring health scaled by magic."
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 2
	m.targeting = _pattern(CombatTypes.TargetKind.ALLY, 1, 2, CombatTypes.AreaShape.SINGLE, 0)
	var h := HealEffect.new()
	h.amount = 24
	h.scaling_stat = "magic"
	h.scale = 1.0
	m.effects = [h]
	return m


## Buff the attack of allies clustered around the aim point.
static func move_rallying_hymn() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"rallying_hymn"
	m.display_name = "Rallying Hymn"
	m.element = &"holy"
	m.description = "Embolden allies near the target cell, raising their attack for a few turns."
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 2
	m.targeting = _pattern(CombatTypes.TargetKind.ALLY, 1, 2, CombatTypes.AreaShape.DIAMOND, 1)
	var buff := StatModifierEffect.new()
	buff.stat_name = "attack"
	buff.amount = 6
	buff.duration = 3
	m.effects = [buff]
	return m


## Debuff an enemy's defense so the team hits harder.
static func move_sunder_guard() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"sunder_guard"
	m.display_name = "Sunder Guard"
	m.element = &"steel"
	m.description = "Batter an enemy's armor, lowering its defense for a short time."
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 2, CombatTypes.AreaShape.SINGLE, 0)
	var debuff := StatModifierEffect.new()
	debuff.stat_name = "defense"
	debuff.amount = -8
	debuff.duration = 2
	m.effects = [debuff]
	return m


## Small hit that shoves an adjacent enemy away.
static func move_gale_shove() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"gale_shove"
	m.display_name = "Gale Shove"
	m.element = &"nature"
	m.description = "A concussive push: light damage that knocks an enemy back two cells."
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 1, CombatTypes.AreaShape.SINGLE, 0)
	var push := KnockbackEffect.new()
	push.distance = 2
	m.effects = [_damage(10, "attack", 0.5, CombatTypes.DamageCategory.PHYSICAL), push]
	return m


## Boss signature: a wide quake that damages, knocks back, and cracks the ground.
static func move_crushing_quake() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"crushing_quake"
	m.display_name = "Crushing Quake"
	m.element = &"nature"
	m.description = "Slam the earth: heavy area damage that knocks enemies back and leaves rubble."
	m.category = CombatTypes.DamageCategory.MAGICAL
	m.energy_cost = 4
	m.max_uses = 2
	m.targeting = _pattern(CombatTypes.TargetKind.ENEMY, 1, 2, CombatTypes.AreaShape.DIAMOND, 2)
	var push := KnockbackEffect.new()
	push.distance = 1
	var crack := TileTransformEffect.new()
	crack.tile_id = &"rubble"
	m.effects = [
		_damage(30, "magic", 1.0, CombatTypes.DamageCategory.MAGICAL),
		push,
		crack,
	]
	return m


## The full pool of sample moves (fresh instances).
static func build_move_pool() -> Array[MoveResource]:
	var pool: Array[MoveResource] = [
		move_cleave(),
		move_piercing_shot(),
		move_ember_storm(),
		move_soothing_light(),
		move_rallying_hymn(),
		move_sunder_guard(),
		move_gale_shove(),
		move_crushing_quake(),
	]
	return pool


# --- Characters ------------------------------------------------------------
# Six archetypes plus one boss. Each carries EXACTLY four moves drawn from the
# pool above (built as fresh instances so every character owns its moveset).

## Bruiser: front-line damage dealer, high attack, sturdy but no magic.
static func character_bruiser() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"torvald_ironhide"
	c.display_name = "Torvald Ironhide"
	c.description = "A relentless front-line bruiser who trades finesse for raw force."
	c.model_scene = MODEL_BRUISER
	c.movement_kind = CombatTypes.MovementKind.GROUND
	c.base_health = 130
	c.base_attack = 34
	c.base_defense = 16
	c.base_magic = 4
	c.base_magic_defense = 8
	c.base_speed = 11
	c.base_movement = 3
	c.attack_range = 1
	var ms: Array[MoveResource] = [
		move_cleave(), move_sunder_guard(), move_gale_shove(), move_rallying_hymn(),
	]
	c.moveset = ms
	return c


## Tank: massive health and defense, slow, protects the line.
static func character_tank() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"mabel_bulwark"
	c.display_name = "Mabel Bulwark"
	c.description = "An immovable guardian built to soak hits and hold ground."
	c.model_scene = MODEL_TANK
	c.movement_kind = CombatTypes.MovementKind.GROUND
	c.base_health = 180
	c.base_attack = 18
	c.base_defense = 30
	c.base_magic = 6
	c.base_magic_defense = 20
	c.base_speed = 7
	c.base_movement = 2
	c.attack_range = 1
	var ms: Array[MoveResource] = [
		move_cleave(), move_gale_shove(), move_rallying_hymn(), move_soothing_light(),
	]
	c.moveset = ms
	return c


## Archer: mobile ranged striker, fragile up close.
static func character_archer() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"sable_quickarrow"
	c.display_name = "Sable Quickarrow"
	c.description = "A sharpshooter who controls the field from a distance."
	c.model_scene = MODEL_ARCHER
	c.movement_kind = CombatTypes.MovementKind.GROUND
	c.base_health = 95
	c.base_attack = 26
	c.base_defense = 10
	c.base_magic = 6
	c.base_magic_defense = 10
	c.base_speed = 15
	c.base_movement = 3
	c.attack_range = 3
	var ms: Array[MoveResource] = [
		move_piercing_shot(), move_gale_shove(), move_sunder_guard(), move_cleave(),
	]
	c.moveset = ms
	return c


## Mage: glass-cannon caster, high magic and area damage, low durability. Flies.
static func character_mage() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"ysolde_emberwynn"
	c.display_name = "Ysolde Emberwynn"
	c.description = "A storm-caller whose spells scorch whole clusters of foes."
	c.model_scene = MODEL_MAGE
	c.movement_kind = CombatTypes.MovementKind.FLYING
	c.base_health = 80
	c.base_attack = 8
	c.base_defense = 8
	c.base_magic = 34
	c.base_magic_defense = 18
	c.base_speed = 13
	c.base_movement = 3
	c.attack_range = 2
	var ms: Array[MoveResource] = [
		move_ember_storm(), move_sunder_guard(), move_soothing_light(), move_rallying_hymn(),
	]
	c.moveset = ms
	return c


## Scout: fastest mover, hit-and-run harasser, low health. Flies.
static func character_scout() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"wren_fleetfoot"
	c.display_name = "Wren Fleetfoot"
	c.description = "A darting skirmisher who strikes and repositions before retaliation."
	c.model_scene = MODEL_SCOUT
	c.movement_kind = CombatTypes.MovementKind.FLYING
	c.base_health = 85
	c.base_attack = 20
	c.base_defense = 9
	c.base_magic = 8
	c.base_magic_defense = 10
	c.base_speed = 20
	c.base_movement = 5
	c.attack_range = 1
	var ms: Array[MoveResource] = [
		move_piercing_shot(), move_cleave(), move_gale_shove(), move_soothing_light(),
	]
	c.moveset = ms
	return c


## Support: healer and buffer, sturdy against magic, modest offense.
static func character_support() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"callan_brightvow"
	c.display_name = "Callan Brightvow"
	c.description = "A steadfast cleric who keeps the roster standing and emboldened."
	c.model_scene = MODEL_SUPPORT
	c.movement_kind = CombatTypes.MovementKind.GROUND
	c.base_health = 100
	c.base_attack = 12
	c.base_defense = 14
	c.base_magic = 24
	c.base_magic_defense = 22
	c.base_speed = 12
	c.base_movement = 3
	c.attack_range = 2
	var ms: Array[MoveResource] = [
		move_soothing_light(), move_rallying_hymn(), move_sunder_guard(), move_cleave(),
	]
	c.moveset = ms
	return c


## Boss: stronger across the board, with an area + knockback signature move.
static func character_boss() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"dread_sovereign_nyx"
	c.display_name = "Dread Sovereign Nyx"
	c.description = "A towering warlord whose quakes scatter entire formations."
	c.model_scene = MODEL_BOSS
	c.movement_kind = CombatTypes.MovementKind.GROUND
	c.is_boss = true
	c.base_health = 320
	c.base_attack = 40
	c.base_defense = 26
	c.base_magic = 30
	c.base_magic_defense = 24
	c.base_speed = 14
	c.base_movement = 4
	c.attack_range = 2
	var ms: Array[MoveResource] = [
		move_crushing_quake(), move_ember_storm(), move_cleave(), move_sunder_guard(),
	]
	c.moveset = ms
	return c


## The full sample roster (fresh instances, each with exactly four moves).
static func build_roster() -> Array[CharacterResource]:
	var roster: Array[CharacterResource] = [
		character_bruiser(),
		character_tank(),
		character_archer(),
		character_mage(),
		character_scout(),
		character_support(),
		character_boss(),
	]
	return roster


# --- Helpers ---------------------------------------------------------------

static func _pattern(kind: CombatTypes.TargetKind, minr: int, maxr: int,
		shape: CombatTypes.AreaShape, size: int) -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = kind
	p.min_range = minr
	p.max_range = maxr
	p.area_shape = shape
	p.area_size = size
	return p


static func _damage(power: int, stat: String, scale: float,
		cat: CombatTypes.DamageCategory) -> DamageEffect:
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = stat
	d.scale = scale
	d.category = cat
	return d
