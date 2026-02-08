extends Resource

class_name UnitStatsResource

# Resource for storing unit statistics and information
# Used by the Unit Creator tool and unit system

# Stat bounds constants
const MAX_HEALTH = 999
const MIN_ATTACK = 1
const MAX_ATTACK = 99
const MIN_DEFENSE = 1
const MAX_DEFENSE = 99
const MIN_SPEED = 1
const MAX_SPEED = 99
const MIN_MOVEMENT = 1
const MAX_MOVEMENT = 10
const MIN_ACTIONS = 1
const MAX_ACTIONS = 5
const MIN_RANGE = 1
const MAX_RANGE = 10

@export var unit_name: String = ""
@export var unit_type: String = ""
@export var description: String = ""

# Core Stats
@export var max_health: int = 100
@export var base_attack: int = 20
@export var base_defense: int = 15
@export var base_magic: int = 10
@export var base_speed: int = 12

# Movement and Range
@export var movement_range: int = 3
@export var attack_range: int = 1

# Visual Assets
@export var model_scene_path: String = ""
@export var profile_image_path: String = ""
@export var icon_texture: Texture2D

# Gameplay Properties
@export var unit_class: String = ""
@export var rarity: String = "Common"  # Common, Uncommon, Rare, Epic, Legendary
@export var cost: int = 100  # For unit recruitment systems

# Growth Stats (for leveling systems)
@export var health_growth: float = 1.0
@export var attack_growth: float = 1.0
@export var defense_growth: float = 1.0
@export var magic_growth: float = 1.0
@export var speed_growth: float = 1.0

# Special Abilities
@export var special_abilities: Array[String] = []
@export var resistances: Array[String] = []
@export var weaknesses: Array[String] = []

# AI Behavior
@export var ai_behavior: String = "Aggressive"  # Aggressive, Defensive, Support, Custom
@export var ai_priority_targets: Array[String] = []

func _init():
	resource_name = "UnitStatsResource"

func get_stat(stat_name: String) -> int:
	"""Get a specific stat value by name"""
	match stat_name.to_lower():
		"health", "hp":
			return max_health
		"attack", "atk":
			return base_attack
		"defense", "def":
			return base_defense
		"magic", "mag":
			return base_magic
		"speed", "spd":
			return base_speed
		"movement", "move":
			return movement_range
		"range":
			return attack_range
		_:
			push_warning("Unknown stat requested: " + stat_name)
			return 0

func get_all_stats() -> Dictionary:
	"""Get all stats as a dictionary"""
	return {
		"health": max_health,
		"attack": base_attack,
		"defense": base_defense,
		"magic": base_magic,
		"speed": base_speed,
		"movement": movement_range,
		"range": attack_range
	}

func get_display_name() -> String:
	"""Get the display name for this unit (for backward compatibility)"""
	return unit_name if not unit_name.is_empty() else "Unnamed Unit"

func get_stat_total() -> int:
	"""Get total stat points for balance checking"""
	return max_health + base_attack + base_defense + base_magic + base_speed

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	return {
		"name": unit_name,
		"type": unit_type,
		"description": description,
		"health": max_health,
		"attack": base_attack,
		"defense": base_defense,
		"magic": base_magic,
		"speed": base_speed,
		"movement": movement_range,
		"range": attack_range,
		"total_stats": get_stat_total(),
		"rarity": rarity,
		"cost": cost
	}

func validate_stats() -> Dictionary:
	"""Validate unit stats for balance"""
	var issues: Array[String] = []
	var warnings: Array[String] = []
	
	# Check for reasonable stat ranges
	if max_health < 30 or max_health > 300:
		warnings.append("Health seems unusual: " + str(max_health))
	
	if base_attack < 5 or base_attack > 50:
		warnings.append("Attack seems unusual: " + str(base_attack))
	
	if base_defense < 5 or base_defense > 50:
		warnings.append("Defense seems unusual: " + str(base_defense))
	
	if movement_range < 1 or movement_range > 8:
		issues.append("Movement range should be 1-8: " + str(movement_range))
	
	if attack_range < 1 or attack_range > 10:
		issues.append("Attack range should be 1-10: " + str(attack_range))
	
	# Check for required fields
	if unit_name.is_empty():
		issues.append("Unit name is required")
	
	if unit_type.is_empty():
		issues.append("Unit type is required")
	
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}

func create_unit_stats_component() -> UnitStats:
	"""Create a UnitStats component with this resource's data"""
	var unit_stats = UnitStats.new()
	unit_stats.stats_resource = self
	return unit_stats

func export_to_json() -> String:
	"""Export unit data to JSON format"""
	var data = {
		"unit_name": unit_name,
		"unit_type": unit_type,
		"description": description,
		"stats": {
			"max_health": max_health,
			"base_attack": base_attack,
			"base_defense": base_defense,
			"base_magic": base_magic,
			"base_speed": base_speed,
			"movement_range": movement_range,
			"attack_range": attack_range
		},
		"visual": {
			"model_scene_path": model_scene_path,
			"profile_image_path": profile_image_path
		},
		"gameplay": {
			"unit_class": unit_class,
			"rarity": rarity,
			"cost": cost,
			"ai_behavior": ai_behavior
		},
		"growth": {
			"health_growth": health_growth,
			"attack_growth": attack_growth,
			"defense_growth": defense_growth,
			"magic_growth": magic_growth,
			"speed_growth": speed_growth
		},
		"special": {
			"abilities": special_abilities,
			"resistances": resistances,
			"weaknesses": weaknesses
		}
	}
	
	return JSON.stringify(data, "\t")

static func import_from_json(json_string: String) -> UnitStatsResource:
	"""Import unit data from JSON format"""
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse JSON: " + json.get_error_message())
		return null
	
	var data = json.data
	var resource = UnitStatsResource.new()
	
	# Basic info
	resource.unit_name = data.get("unit_name", "")
	resource.unit_type = data.get("unit_type", "")
	resource.description = data.get("description", "")
	
	# Stats
	var stats = data.get("stats", {})
	resource.max_health = stats.get("max_health", 100)
	resource.base_attack = stats.get("base_attack", 20)
	resource.base_defense = stats.get("base_defense", 15)
	resource.base_magic = stats.get("base_magic", 10)
	resource.base_speed = stats.get("base_speed", 12)
	resource.movement_range = stats.get("movement_range", 3)
	resource.attack_range = stats.get("attack_range", 1)
	
	# Visual
	var visual = data.get("visual", {})
	resource.model_scene_path = visual.get("model_scene_path", "")
	resource.profile_image_path = visual.get("profile_image_path", "")
	
	# Gameplay
	var gameplay = data.get("gameplay", {})
	resource.unit_class = gameplay.get("unit_class", "")
	resource.rarity = gameplay.get("rarity", "Common")
	resource.cost = gameplay.get("cost", 100)
	resource.ai_behavior = gameplay.get("ai_behavior", "Aggressive")
	
	# Growth
	var growth = data.get("growth", {})
	resource.health_growth = growth.get("health_growth", 1.0)
	resource.attack_growth = growth.get("attack_growth", 1.0)
	resource.defense_growth = growth.get("defense_growth", 1.0)
	resource.magic_growth = growth.get("magic_growth", 1.0)
	resource.speed_growth = growth.get("speed_growth", 1.0)
	
	# Special
	var special = data.get("special", {})
	resource.special_abilities = special.get("abilities", [])
	resource.resistances = special.get("resistances", [])
	resource.weaknesses = special.get("weaknesses", [])
	
	return resource
