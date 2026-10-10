extends Resource
class_name CharacterResource

## A single, unique custom character — the replacement for fixed unit "classes".
##
## Everything that makes a character distinct (identity, art, base stats, and its
## four moves) lives here as data. Authoring a new character is creating a new
## .tres; no new script or class is required. This is the canonical stat block
## the live [Unit] reads from.

const MAX_MOVES: int = 4

## WHAT a character is (docs/design/DECISIONS.md #5): a CREATURE (a species -- caught, evolves,
## fights with its four authored moves) or a HUMAN (a unique named individual -- recruited, never
## wild; promotes by class; fights with a WEAPON ATTACK, plus special moves when ENHANCED).
## docs/design/HUMANS.md is the as-built spec.
enum Kind { CREATURE, HUMAN }

@export_group("Identity")
@export var character_id: StringName = &""
## CREATURE (the default -- every roster entry that predates kinds) or HUMAN. The Compendium and
## the squad / party screens badge it; acquisition and progression key off it.
@export var kind: Kind = Kind.CREATURE
@export var display_name: String = "New Character"
@export_multiline var description: String = ""
@export var portrait: Texture2D
@export var model_scene: PackedScene

@export_group("Base Stats")
@export var base_health: int = 100
@export var base_attack: int = 20
@export var base_defense: int = 15
@export var base_magic: int = 10
@export var base_magic_defense: int = 10
@export var base_speed: int = 12
@export var base_movement: int = 3
@export var attack_range: int = 1

## SIGHT RADIUS (Chebyshev cells) under FOG OF WAR -- how far this character lights the board
## for its own side. 0 means "no opinion", and the unit then sees
## [constant VisionSystem.DEFAULT_SIGHT_RANGE], which is what every character that predates
## this field says and why adding it changed nothing about the roster.
##
## Deliberately NOT one of the stats [method get_stat] serves and NOT touched by buffs: sight
## is a property of who a character IS (a scout sees further, a burrower barely at all), and
## making it modifiable would put a per-turn recompute of the whole lit set behind every stat
## change. Retune it here, in data.
##
## Inert on a map with [member MapResource.fog_of_war] off -- there is nothing to see through.
@export var sight_range: int = 0

@export_group("Profile")
## Elemental TYPE for matchup effectiveness (Fire-Emblem / Pokemon style). Damage a
## unit deals/takes is scaled by [ElementChart] against a move's element and the tile
## it stands on. Empty = NEUTRAL: no matchup either way (the safe, unchanged default).
## Use one vocabulary shared with move elements and tile elements: &"fire", &"water",
## &"nature", &"wind", &"earth", &"holy", &"dark".
@export var element: StringName = &""
## Free-form trait tags read by conditions ([UnitElementCondition]), e.g.
## &"sand_proof" (immune to Desert Storm chip damage). Empty by default.
@export var tags: Array[StringName] = []
@export var movement_kind: CombatTypes.MovementKind = CombatTypes.MovementKind.GROUND
## Optional authored movement profile. When unset, [method get_movement_profile]
## synthesizes one from [member movement_kind] + [member base_movement] so
## callers always have a valid profile to consume.
@export var movement_profile: MovementProfile
## Marks bosses / map bosses so modes and AI can treat them specially.
@export var is_boss: bool = false
## Minimum AI difficulty at which this character is allowed to spawn, matching
## [code]GameSettings.ai_difficulty[/code] (0 = Easy, 1 = Normal, 2 = Hard,
## 3 = Brutal). 0 = always available. A harder-only enemy (e.g. a parasite that
## only infests you on Hard+) sets this to 2, and the spawner skips it on lower
## difficulties. Applies to every spawn path -- initial placement and runtime waves.
@export_enum("Easy", "Normal", "Hard", "Brutal") var min_difficulty: int = 0
## How many board cells this character spans — [code]Vector2i(1, 1)[/code] for a
## normal unit, [code]Vector2i(2, 2)[/code] for a large boss such as a Great Tree.
## The character's anchor cell (what [code]BoardAdapter.cell_of()[/code] reports)
## is the MINIMUM corner of the span, which extends toward +col / +row from there.
@export var footprint: Vector2i = Vector2i.ONE

@export_group("Model")
## Extra yaw (Y rotation, degrees) applied to the authored model so that it faces
## +Z (south, toward the battle camera) -- the model-forward convention the unit
## facing system builds on (UnitFacing / CONQUEST.md "Unit facing"). The Blender
## pipeline exports facing +Z, so 0 is normal; use 180 for a sculpt that faces
## away. Verify with dev_scripts/render_unit_facing.gd.
@export var model_yaw_deg: float = 0.0
## Uniform scale multiplier on the model (1.0 = the size the .glb imports at). Scales
## about the feet-at-origin, so the unit stays grounded. This is what puts a unit at
## its TRUE design height (CONQUEST.md "Size"): design height / imported height, e.g.
## a 2 ft Blightcap < 1, an 8 ft Barkling > 1. A model wider than its cell overhangs
## it and stays one tile -- never shrink a unit to fit; only giants get a [member footprint].
@export var model_scale: float = 1.0

@export_group("AI Behavior")
## Default combat stance for a unit of this character. "aggressive" units close on
## the nearest enemy every turn (the classic behaviour); "defensive" units hold
## their ground and only engage once a hostile enters [member default_aggro_range]
## of their home cell. A spawn point may override this per placement (see
## MapResource's unit_spawns schema and [method Unit.configure_ai_behavior]).
## Empty "" = no per-character preference: the spawn KIND decides (pre-placed hold,
## waves charge). Set it to "aggressive" to make a character always charge (e.g.
## blightcap, a fast fungus) or "defensive" for a camper, even when pre-placed.
## (Plain String, not @export_enum, because the enum annotation rejects an empty
## default; the resolver only accepts "aggressive"/"defensive" and ignores anything else.)
@export var default_ai_stance: String = ""
## How close (Manhattan cells) a hostile must come to a DEFENSIVE unit's home cell
## before it wakes and engages. 0 means it acts only when it can already strike a
## target from a reachable cell — a stationary turret / guardian. Ignored while the
## unit is aggressive.
@export var default_aggro_range: int = 0
## Max distance (Manhattan cells) a unit of this character will ever move from its
## home cell, capping pursuit so an anchored boss can never be dragged off its
## ground. -1 = untethered (roam freely). A small positive value (e.g. 2) keeps a
## guardian on its post while still letting it face an adjacent attacker.
@export var default_leash_radius: int = -1

@export_group("Moveset")
## Up to [constant MAX_MOVES] moves. Extra entries are ignored by [method get_move].
## A HUMAN's list is its SPECIAL moves (possibly none), fielded after the weapon attack
## ([method get_moveset] builds the kit). Read moves through [method get_moveset] /
## [method get_move], never this field, so a human's kit is the one every system sees.
@export var moveset: Array[MoveResource] = []

@export_group("Human")
## HUMANS ONLY (ignored for a creature). The equipped weapon: its WEAPON ATTACK
## ([method WeaponResource.attack_move]) is slot 0 of the kit. Null = [method WeaponLibrary.unarmed].
@export var weapon: WeaponResource
## Weapon TYPES this human can wield ([WeaponRules] type ids). More than one = the human can SWAP
## weapons (DECISIONS.md #63); empty = only its own [member weapon]'s type.
@export var weapon_proficiencies: Array[StringName] = []
## The weapon type this human naturally leans toward (#63's "tendency"); "" = none. Data only for
## now -- shown on the party page; no bonus is attached yet.
@export var weapon_tendency: StringName = &""
## ("ENHANCED" humans -- #54 / #64 -- are design flavour, not a mechanic: an enhanced character is
## simply one whose [member moveset] lists special moves. Chiefs are authored that way; the hero
## gains them by PROMOTION -- the promoted form's moveset lists them.)

@export_group("Abilities")
## Always-on / triggered passives the character owns for free. Distinct from
## [member moveset]: the player never selects one of these — the unit's
## [AbilitySystem] fires each on its own [member AbilityResource.trigger]
## (turn start, kill, …) or reads it as a standing rule modifier. Unbounded.
@export var abilities: Array[AbilityResource] = []

@export_group("Progression (story)")
## STORY levels only (docs/design/PROGRESSION.md, [Progression]); open modes never read these.
## Per-stat GROWTH per level: stat(L) = round(base * (1 + growth * (L - 1))). A negative value
## (the default) = [member ProgressionRules.default_growth]. Speed's growth is further scaled by
## [member ProgressionRules.speed_growth_mult]; movement never scales.
@export var health_growth: float = -1.0
@export var attack_growth: float = -1.0
@export var defense_growth: float = -1.0
@export var magic_growth: float = -1.0
@export var magic_defense_growth: float = -1.0
@export var speed_growth: float = -1.0
## Base XP this species yields when defeated. 0 (the default) = derived from its
## [method power_budget] ([method Progression.xp_yield_of]): stronger species give more.
@export var xp_yield: int = 0
## How easy this species is to bond with / catch, 0..1 (DECISIONS.md #78): it MULTIPLIES the
## befriend chance. Negative (the default) = derived from its power budget
## ([method Progression.catch_rate_of]): strong species are hard.
@export var catch_rate: float = -1.0


func move_count() -> int:
	return mini(get_moveset().size(), MAX_MOVES)


func ability_count() -> int:
	return abilities.size()


## Move in [param slot] (0..3), or null if empty/out of range.
func get_move(slot: int) -> MoveResource:
	if slot < 0 or slot >= move_count():
		return null
	return get_moveset()[slot]


## THE moves this character fields, in slot order -- what the board, the AI, the duel compiler
## and every screen read. A CREATURE: its authored [member moveset], exactly as before. A HUMAN:
## its WEAPON ATTACK in slot 0, then whatever special moves its [member moveset] lists (an
## "enhanced" human is just one that lists some), up to [constant MAX_MOVES] in all.
func get_moveset() -> Array[MoveResource]:
	if not is_human():
		return moveset
	var out: Array[MoveResource] = [equipped_weapon().attack_move()]
	for m in moveset:
		if out.size() >= MAX_MOVES:
			break
		out.append(m)
	return out


# --- Humans (docs/design/HUMANS.md) --------------------------------------------------------

func is_human() -> bool:
	return kind == Kind.HUMAN


func is_creature() -> bool:
	return kind == Kind.CREATURE


## "Human" / "Creature" -- the badge text.
func kind_label() -> String:
	return "Human" if is_human() else "Creature"


## The weapon this human strikes with ([member weapon], else the unarmed fallback). Null for a
## creature.
func equipped_weapon() -> WeaponResource:
	if not is_human():
		return null
	return weapon if weapon != null else WeaponLibrary.unarmed()


## The equipped weapon's type ("" for a creature / an unarmed human).
func weapon_type() -> StringName:
	var w: WeaponResource = equipped_weapon()
	return w.weapon_type if w != null else &""


## The weapon types this human may wield: [member weapon_proficiencies], else its own weapon's.
func wieldable_types() -> Array[StringName]:
	var out: Array[StringName] = []
	if not is_human():
		return out
	for t in weapon_proficiencies:
		if not out.has(t):
			out.append(t)
	if out.is_empty() and weapon != null and weapon.weapon_type != &"":
		out.append(weapon.weapon_type)
	return out


## True when this human may equip [param w] (its type is one it wields).
func can_wield(w: WeaponResource) -> bool:
	return is_human() and w != null and wieldable_types().has(w.weapon_type)


## Can this human SWAP weapons at all (#63)? More than one wieldable type.
func can_swap_weapons() -> bool:
	return wieldable_types().size() > 1


## A PRIVATE COPY of this character wielding [param w] (rule 7: the roster entry is shared).
## Returns self unchanged for a creature, a null weapon or the weapon it already holds.
func with_weapon(w: WeaponResource) -> CharacterResource:
	if not is_human() or w == null or w == weapon:
		return self
	var copy := duplicate(false) as CharacterResource
	copy.weapon = w
	return copy


## Returns [member movement_profile] if authored, else synthesizes a
## reasonable one at runtime from [member movement_kind] + [member base_movement].
## Never returns null — safe for callers to consume unconditionally.
func get_movement_profile() -> MovementProfile:
	if movement_profile != null:
		return movement_profile

	# GROUND (and any future kind) falls through to the ORTHOGONAL default.
	var shape := MovementProfile.Shape.ORTHOGONAL
	match movement_kind:
		CombatTypes.MovementKind.FLYING:
			shape = MovementProfile.Shape.ALL8
		CombatTypes.MovementKind.PHASING:
			shape = MovementProfile.Shape.TELEPORT

	var profile_id: StringName = character_id
	if String(profile_id).is_empty():
		profile_id = &"synthesized"

	return MovementProfile.create(
		profile_id,
		"%s (synthesized)" % display_name,
		movement_kind,
		base_movement,
		shape)


## [member footprint] guarded so each axis is at least 1 — a zero or negative
## value authored in the inspector still reads back as a usable span.
func get_footprint() -> Vector2i:
	return Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))


## This character's authored [member sight_range], or 0 when it declares none. Kept a plain
## reader (the fallback to [constant VisionSystem.DEFAULT_SIGHT_RANGE] lives in
## [method VisionSystem.sight_range_of]) so the default is stated ONCE, on the system that owns
## the rule, rather than in every resource that has no opinion about it.
func get_sight_range() -> int:
	return maxi(0, sight_range)


## Minimum spawn difficulty, clamped to the valid 0..3 range.
func get_min_difficulty() -> int:
	return clampi(min_difficulty, 0, 3)


## Default stance, guaranteed to be one of the two valid values.
func get_default_ai_stance() -> String:
	return "defensive" if default_ai_stance == "defensive" else "aggressive"


## Default aggro range, floored at 0 (a negative authored value reads as 0).
func get_default_aggro_range() -> int:
	return maxi(0, default_aggro_range)


## Default leash radius. Any negative value normalises to -1 (untethered).
func get_default_leash_radius() -> int:
	return default_leash_radius if default_leash_radius >= 0 else -1


func get_stat(stat_name: String) -> int:
	match stat_name.to_lower():
		"health", "hp": return base_health
		"attack", "atk": return base_attack
		"defense", "def": return base_defense
		"magic", "mag": return base_magic
		"magic_defense", "mdef": return base_magic_defense
		"speed", "spd": return base_speed
		"movement", "move": return base_movement
		"range": return effective_attack_range()
		_: return 0


## The basic attack reach: a creature's authored [member attack_range]; a human's weapon reach.
func effective_attack_range() -> int:
	if is_human():
		return equipped_weapon().reach().y
	return attack_range


## A quick balance heuristic (sum of offensive/defensive stats).
func power_budget() -> int:
	return base_health + base_attack + base_defense + base_magic \
		+ base_magic_defense + base_speed + base_movement * 5


## Validation for the character creator / content checks.
func validate() -> Dictionary:
	var issues: Array[String] = []
	if String(character_id).is_empty():
		issues.append("character_id is required")
	if display_name.is_empty():
		issues.append("display_name is required")
	if moveset.size() > MAX_MOVES:
		issues.append("moveset has %d moves; max is %d" % [moveset.size(), MAX_MOVES])
	for i in range(mini(moveset.size(), MAX_MOVES)):
		if moveset[i] == null:
			issues.append("move slot %d is empty" % i)
	for i in range(abilities.size()):
		if abilities[i] == null:
			issues.append("ability slot %d is empty" % i)
	if is_human():
		if weapon == null:
			issues.append("human has no weapon")
		else:
			issues.append_array(weapon.validate())
			if not weapon_proficiencies.is_empty() and not weapon_proficiencies.has(weapon.weapon_type):
				issues.append("human's weapon type '%s' is not one of its proficiencies" % weapon.weapon_type)
		var rules: WeaponRules = WeaponRules.current()
		for t in weapon_proficiencies:
			if not rules.has_type(t):
				issues.append("unknown weapon proficiency '%s'" % t)
		if weapon_tendency != &"" and not wieldable_types().has(weapon_tendency):
			issues.append("weapon tendency '%s' is not a wieldable type" % weapon_tendency)
		if moveset.size() > MAX_MOVES - 1:
			issues.append("human has %d special moves; max is %d (slot 0 is the weapon attack)" % [moveset.size(), MAX_MOVES - 1])
	elif weapon != null:
		issues.append("a creature has a weapon (weapons are for humans)")
	return { "valid": issues.is_empty(), "issues": issues }
