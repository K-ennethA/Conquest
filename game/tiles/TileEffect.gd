extends Resource

class_name TileEffect

# Comprehensive tile effect system for tactical combat

@export var effect_name: String = ""
@export var effect_type: EffectType = EffectType.NONE
@export var duration: int = -1  # -1 = permanent, 0 = instant, >0 = turns remaining
@export var strength: int = 1
@export var stacks: bool = false  # Can multiple instances stack?
@export var affects_movement: bool = false
@export var affects_combat: bool = false
@export var affects_healing: bool = false

# Visual properties
@export var particle_effect: PackedScene
@export var material_override: Material
@export var animation_name: String = ""
@export var sound_effect: AudioStream

# Effect triggers
@export var triggers_on_enter: bool = true
@export var triggers_on_exit: bool = false
@export var triggers_on_turn_start: bool = false
@export var triggers_on_turn_end: bool = false

enum EffectType {
	NONE,
	# Damage Effects
	FIRE_DAMAGE,
	ICE_DAMAGE,
	POISON_DAMAGE,
	LIGHTNING_DAMAGE,
	# Healing Effects
	HEALING_SPRING,
	REGENERATION_FIELD,
	SANCTUARY,
	# Buff Effects
	SPEED_BOOST,
	ATTACK_BOOST,
	DEFENSE_BOOST,
	MAGIC_BOOST,
	# Debuff Effects
	SLOW,
	WEAKNESS,
	VULNERABILITY,
	SILENCE,
	# Terrain Effects
	DIFFICULT_TERRAIN,
	IMPASSABLE,
	TELEPORTER,
	TRAP,
	# Special Effects
	MANA_DRAIN,
	EXPERIENCE_BOOST,
	GOLD_BONUS,
	VISION_ENHANCEMENT
}

func _init():
	resource_name = "TileEffect"

func apply_effect(unit: Unit, tile: Tile) -> Dictionary:
	"""Apply this effect to a unit on a tile"""
	var result = {
		"success": false,
		"message": "",
		"damage": 0,
		"healing": 0,
		"stat_changes": {},
		"status_effects": []
	}
	
	if not unit or not tile:
		result.message = "Invalid unit or tile"
		return result
	
	match effect_type:
		EffectType.FIRE_DAMAGE:
			result = _apply_fire_damage(unit, tile)
		EffectType.ICE_DAMAGE:
			result = _apply_ice_damage(unit, tile)
		EffectType.POISON_DAMAGE:
			result = _apply_poison_damage(unit, tile)
		EffectType.LIGHTNING_DAMAGE:
			result = _apply_lightning_damage(unit, tile)
		EffectType.HEALING_SPRING:
			result = _apply_healing_spring(unit, tile)
		EffectType.REGENERATION_FIELD:
			result = _apply_regeneration_field(unit, tile)
		EffectType.SANCTUARY:
			result = _apply_sanctuary(unit, tile)
		EffectType.SPEED_BOOST:
			result = _apply_speed_boost(unit, tile)
		EffectType.ATTACK_BOOST:
			result = _apply_attack_boost(unit, tile)
		EffectType.DEFENSE_BOOST:
			result = _apply_defense_boost(unit, tile)
		EffectType.MAGIC_BOOST:
			result = _apply_magic_boost(unit, tile)
		EffectType.SLOW:
			result = _apply_slow(unit, tile)
		EffectType.WEAKNESS:
			result = _apply_weakness(unit, tile)
		EffectType.VULNERABILITY:
			result = _apply_vulnerability(unit, tile)
		EffectType.SILENCE:
			result = _apply_silence(unit, tile)
		EffectType.DIFFICULT_TERRAIN:
			result = _apply_difficult_terrain(unit, tile)
		EffectType.IMPASSABLE:
			result = _apply_impassable(unit, tile)
		EffectType.TELEPORTER:
			result = _apply_teleporter(unit, tile)
		EffectType.TRAP:
			result = _apply_trap(unit, tile)
		EffectType.MANA_DRAIN:
			result = _apply_mana_drain(unit, tile)
		EffectType.EXPERIENCE_BOOST:
			result = _apply_experience_boost(unit, tile)
		EffectType.GOLD_BONUS:
			result = _apply_gold_bonus(unit, tile)
		EffectType.VISION_ENHANCEMENT:
			result = _apply_vision_enhancement(unit, tile)
		_:
			result.message = "Unknown effect type"
	
	# Reduce duration if not permanent
	if duration > 0:
		duration -= 1
	
	result.success = true
	return result

# Damage Effects
func _apply_fire_damage(unit: Unit, tile: Tile) -> Dictionary:
	var damage = strength * 5  # Base fire damage
	return {
		"success": true,
		"message": unit.unit_name + " takes " + str(damage) + " fire damage!",
		"damage": damage,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["burning"]
	}

func _apply_ice_damage(unit: Unit, tile: Tile) -> Dictionary:
	var damage = strength * 3  # Lower damage but slows
	return {
		"success": true,
		"message": unit.unit_name + " takes " + str(damage) + " ice damage and is slowed!",
		"damage": damage,
		"healing": 0,
		"stat_changes": {"speed": -2},
		"status_effects": ["frozen"]
	}

func _apply_poison_damage(unit: Unit, tile: Tile) -> Dictionary:
	var damage = strength * 2  # Damage over time
	return {
		"success": true,
		"message": unit.unit_name + " is poisoned!",
		"damage": damage,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["poisoned"]
	}

func _apply_lightning_damage(unit: Unit, tile: Tile) -> Dictionary:
	var damage = strength * 7  # High burst damage
	return {
		"success": true,
		"message": unit.unit_name + " is struck by lightning for " + str(damage) + " damage!",
		"damage": damage,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["stunned"]
	}

# Healing Effects
func _apply_healing_spring(unit: Unit, tile: Tile) -> Dictionary:
	var healing = strength * 8
	return {
		"success": true,
		"message": unit.unit_name + " is healed for " + str(healing) + " HP!",
		"damage": 0,
		"healing": healing,
		"stat_changes": {},
		"status_effects": []
	}

func _apply_regeneration_field(unit: Unit, tile: Tile) -> Dictionary:
	var healing = strength * 3  # Healing over time
	return {
		"success": true,
		"message": unit.unit_name + " regenerates " + str(healing) + " HP!",
		"damage": 0,
		"healing": healing,
		"stat_changes": {},
		"status_effects": ["regenerating"]
	}

func _apply_sanctuary(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " is protected by sanctuary!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"defense": strength * 3},
		"status_effects": ["blessed"]
	}

# Buff Effects
func _apply_speed_boost(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " feels energized!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"speed": strength * 2},
		"status_effects": ["hasted"]
	}

func _apply_attack_boost(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " feels empowered!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"attack": strength * 3},
		"status_effects": ["empowered"]
	}

func _apply_defense_boost(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " feels fortified!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"defense": strength * 3},
		"status_effects": ["fortified"]
	}

func _apply_magic_boost(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " feels magically enhanced!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"magic": strength * 3},
		"status_effects": ["enchanted"]
	}

# Debuff Effects
func _apply_slow(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " is slowed!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"speed": -strength * 2},
		"status_effects": ["slowed"]
	}

func _apply_weakness(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " feels weakened!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"attack": -strength * 2},
		"status_effects": ["weakened"]
	}

func _apply_vulnerability(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " becomes vulnerable!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"defense": -strength * 2},
		"status_effects": ["vulnerable"]
	}

func _apply_silence(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " is silenced!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"magic": -strength * 3},
		"status_effects": ["silenced"]
	}

# Terrain Effects
func _apply_difficult_terrain(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " struggles through difficult terrain!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"movement": -1},
		"status_effects": []
	}

func _apply_impassable(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": false,
		"message": "Cannot move through impassable terrain!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {},
		"status_effects": []
	}

func _apply_teleporter(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " is teleported!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["teleported"]
	}

func _apply_trap(unit: Unit, tile: Tile) -> Dictionary:
	var damage = strength * 10  # High trap damage
	return {
		"success": true,
		"message": unit.unit_name + " triggers a trap for " + str(damage) + " damage!",
		"damage": damage,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["trapped"]
	}

# Special Effects
func _apply_mana_drain(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + "'s mana is drained!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"magic": -strength},
		"status_effects": ["drained"]
	}

func _apply_experience_boost(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " gains bonus experience!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["learning"]
	}

func _apply_gold_bonus(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + " finds gold!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {},
		"status_effects": ["wealthy"]
	}

func _apply_vision_enhancement(unit: Unit, tile: Tile) -> Dictionary:
	return {
		"success": true,
		"message": unit.unit_name + "'s vision is enhanced!",
		"damage": 0,
		"healing": 0,
		"stat_changes": {"range": strength},
		"status_effects": ["eagle_eyed"]
	}

func get_movement_cost_modifier() -> int:
	"""Get movement cost modifier for this effect"""
	match effect_type:
		EffectType.DIFFICULT_TERRAIN:
			return strength
		EffectType.IMPASSABLE:
			return 999
		_:
			return 0

func is_passable() -> bool:
	"""Check if this effect blocks movement"""
	return effect_type != EffectType.IMPASSABLE

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	return {
		"name": effect_name,
		"type": EffectType.keys()[effect_type],
		"duration": duration,
		"strength": strength,
		"description": _get_effect_description()
	}

func _get_effect_description() -> String:
	"""Get human-readable description of the effect"""
	match effect_type:
		EffectType.FIRE_DAMAGE:
			return "Deals " + str(strength * 5) + " fire damage to units"
		EffectType.ICE_DAMAGE:
			return "Deals " + str(strength * 3) + " ice damage and slows units"
		EffectType.POISON_DAMAGE:
			return "Poisons units for " + str(strength * 2) + " damage per turn"
		EffectType.LIGHTNING_DAMAGE:
			return "Strikes units with lightning for " + str(strength * 7) + " damage"
		EffectType.HEALING_SPRING:
			return "Heals units for " + str(strength * 8) + " HP"
		EffectType.REGENERATION_FIELD:
			return "Regenerates " + str(strength * 3) + " HP per turn"
		EffectType.SANCTUARY:
			return "Increases defense by " + str(strength * 3)
		EffectType.SPEED_BOOST:
			return "Increases speed by " + str(strength * 2)
		EffectType.ATTACK_BOOST:
			return "Increases attack by " + str(strength * 3)
		EffectType.DEFENSE_BOOST:
			return "Increases defense by " + str(strength * 3)
		EffectType.MAGIC_BOOST:
			return "Increases magic by " + str(strength * 3)
		EffectType.SLOW:
			return "Decreases speed by " + str(strength * 2)
		EffectType.WEAKNESS:
			return "Decreases attack by " + str(strength * 2)
		EffectType.VULNERABILITY:
			return "Decreases defense by " + str(strength * 2)
		EffectType.SILENCE:
			return "Prevents magic use"
		EffectType.DIFFICULT_TERRAIN:
			return "Increases movement cost by " + str(strength)
		EffectType.IMPASSABLE:
			return "Blocks all movement"
		EffectType.TELEPORTER:
			return "Teleports units to another location"
		EffectType.TRAP:
			return "Hidden trap dealing " + str(strength * 10) + " damage"
		EffectType.MANA_DRAIN:
			return "Drains " + str(strength) + " magic per turn"
		EffectType.EXPERIENCE_BOOST:
			return "Grants bonus experience"
		EffectType.GOLD_BONUS:
			return "Provides gold bonus"
		EffectType.VISION_ENHANCEMENT:
			return "Increases vision range by " + str(strength)
		_:
			return "Unknown effect"