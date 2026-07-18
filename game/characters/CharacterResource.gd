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
@export var movement_kind: CombatTypes.MovementKind = CombatTypes.MovementKind.GROUND
## Marks bosses / map bosses so modes and AI can treat them specially.
@export var is_boss: bool = false

@export_group("Moveset")
## Up to [constant MAX_MOVES] moves. Extra entries are ignored by [method get_move].
@export var moveset: Array[MoveResource] = []


func move_count() -> int:
	return mini(moveset.size(), MAX_MOVES)


## Move in [param slot] (0..3), or null if empty/out of range.
func get_move(slot: int) -> MoveResource:
	if slot < 0 or slot >= move_count():
		return null
	return moveset[slot]


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
	return { "valid": issues.is_empty(), "issues": issues }
