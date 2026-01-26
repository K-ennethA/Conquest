extends Resource

class_name UnitStatsResource

# Core unit identification
@export var unit_name: String = ""
@export var unit_type: UnitType

# Base combat stats
@export_range(1, 500) var base_health: int = 100
@export_range(1, 100) var base_attack: int = 20
@export_range(0, 50) var base_defense: int = 10
@export_range(1, 30) var base_speed: int = 10

# Movement and action stats
@export_range(1, 10) var base_movement: int = 3
@export_range(1, 5) var base_actions: int = 1

# Special attributes
@export_range(0, 10) var attack_range: int = 1
@export var abilities: Array[Resource] = []

# Stat validation ranges
const MIN_HEALTH = 1
const MAX_HEALTH = 500
const MIN_ATTACK = 1
const MAX_ATTACK = 100
const MIN_DEFENSE = 0
const MAX_DEFENSE = 50
const MIN_SPEED = 1
const MAX_SPEED = 30
const MIN_MOVEMENT = 1
const MAX_MOVEMENT = 10
const MIN_ACTIONS = 1
const MAX_ACTIONS = 5
const MIN_RANGE = 0
const MAX_RANGE = 10

func _init():
	if not unit_type:
		unit_type = UnitType.new()

# Validation methods
func validate_stats() -> bool:
	return (
		_is_stat_valid(base_health, MIN_HEALTH, MAX_HEALTH) and
		_is_stat_valid(base_attack, MIN_ATTACK, MAX_ATTACK) and
		_is_stat_valid(base_defense, MIN_DEFENSE, MAX_DEFENSE) and
		_is_stat_valid(base_speed, MIN_SPEED, MAX_SPEED) and
		_is_stat_valid(base_movement, MIN_MOVEMENT, MAX_MOVEMENT) and
		_is_stat_valid(base_actions, MIN_ACTIONS, MAX_ACTIONS) and
		_is_stat_valid(attack_range, MIN_RANGE, MAX_RANGE)
	)

func _is_stat_valid(value: int, min_val: int, max_val: int) -> bool:
	return value >= min_val and value <= max_val

# Stat getter methods
func get_stat(stat_name: String) -> int:
	match stat_name.to_lower():
		"health", "hp":
			return base_health
		"attack", "atk":
			return base_attack
		"defense", "def":
			return base_defense
		"speed", "spd":
			return base_speed
		"movement", "move":
			return base_movement
		"actions", "act":
			return base_actions
		"range":
			return attack_range
		_:
			push_warning("Unknown stat requested: " + stat_name)
			return 0

# Get all stats as dictionary
func get_all_stats() -> Dictionary:
	return {
		"health": base_health,
		"attack": base_attack,
		"defense": base_defense,
		"speed": base_speed,
		"movement": base_movement,
		"actions": base_actions,
		"range": attack_range
	}

# Utility methods
func get_display_name() -> String:
	if unit_name.is_empty():
		return unit_type.get_type_name() if unit_type else "Unknown Unit"
	return unit_name

func is_ranged_unit() -> bool:
	return attack_range > 1 or (unit_type and unit_type.is_ranged_unit())

func get_total_combat_power() -> int:
	# Simple combat power calculation for balancing
	return base_attack + base_defense + (base_health / 10)

func get_mobility_rating() -> int:
	# Mobility rating based on speed and movement
	return base_speed + (base_movement * 2)

# Create a copy with modified stats (for temporary modifications)
func create_modified_copy(stat_modifiers: Dictionary) -> UnitStatsResource:
	var copy = duplicate()
	
	for stat_name in stat_modifiers:
		var modifier = stat_modifiers[stat_name]
		match stat_name.to_lower():
			"health", "hp":
				copy.base_health = clamp(copy.base_health + modifier, MIN_HEALTH, MAX_HEALTH)
			"attack", "atk":
				copy.base_attack = clamp(copy.base_attack + modifier, MIN_ATTACK, MAX_ATTACK)
			"defense", "def":
				copy.base_defense = clamp(copy.base_defense + modifier, MIN_DEFENSE, MAX_DEFENSE)
			"speed", "spd":
				copy.base_speed = clamp(copy.base_speed + modifier, MIN_SPEED, MAX_SPEED)
			"movement", "move":
				copy.base_movement = clamp(copy.base_movement + modifier, MIN_MOVEMENT, MAX_MOVEMENT)
			"actions", "act":
				copy.base_actions = clamp(copy.base_actions + modifier, MIN_ACTIONS, MAX_ACTIONS)
			"range":
				copy.attack_range = clamp(copy.attack_range + modifier, MIN_RANGE, MAX_RANGE)
	
	return copy

# Debug and development helpers
func _to_string() -> String:
	return "%s (%s): HP:%d ATK:%d DEF:%d SPD:%d MOV:%d ACT:%d RNG:%d" % [
		get_display_name(),
		unit_type.get_type_name() if unit_type else "No Type",
		base_health, base_attack, base_defense, base_speed,
		base_movement, base_actions, attack_range
	]
