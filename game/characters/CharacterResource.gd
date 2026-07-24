extends Resource
class_name CharacterResource

## A single, unique custom character — the replacement for fixed unit "classes".
##
## Everything that makes a character distinct (identity, art, base stats, and its
## four moves) lives here as data. Authoring a new character is creating a new
## .tres; no new script or class is required. This is the canonical stat block
## the live [Unit] reads from.

const MAX_MOVES: int = 4

@export_group("Identity")
@export var character_id: StringName = &""
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

@export_group("Profile")
## Elemental TYPE for matchup effectiveness (Fire-Emblem / Pokemon style). Damage a
## unit deals/takes is scaled by [ElementChart] against a move's element and the tile
## it stands on. Empty = NEUTRAL: no matchup either way (the safe, unchanged default).
## Use one vocabulary shared with move elements and tile elements: &"fire", &"water",
## &"nature", &"wind", &"earth", &"holy", &"dark".
@export var element: StringName = &""
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
## Extra yaw (Y rotation, degrees) applied to the authored model when it enters the
## board -- use 180 for a sculpt that faces the wrong way. 0 = as authored.
@export var model_yaw_deg: float = 0.0
## Uniform scale multiplier on the model (1.0 = the pipeline-fit size). Scales about
## the feet-at-origin, so the unit stays grounded. Use < 1 for a small creature
## (e.g. a mushroom) that should read smaller than the others.
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
@export var moveset: Array[MoveResource] = []

@export_group("Abilities")
## Always-on / triggered passives the character owns for free. Distinct from
## [member moveset]: the player never selects one of these — the unit's
## [AbilitySystem] fires each on its own [member AbilityResource.trigger]
## (turn start, kill, …) or reads it as a standing rule modifier. Unbounded.
@export var abilities: Array[AbilityResource] = []


func move_count() -> int:
	return mini(moveset.size(), MAX_MOVES)


func ability_count() -> int:
	return abilities.size()


## Move in [param slot] (0..3), or null if empty/out of range.
func get_move(slot: int) -> MoveResource:
	if slot < 0 or slot >= move_count():
		return null
	return moveset[slot]


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
		"range": return attack_range
		_: return 0


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
	for i in range(move_count()):
		if moveset[i] == null:
			issues.append("move slot %d is empty" % i)
	for i in range(abilities.size()):
		if abilities[i] == null:
			issues.append("ability slot %d is empty" % i)
	return { "valid": issues.is_empty(), "issues": issues }
