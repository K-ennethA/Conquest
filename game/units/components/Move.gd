extends Resource

class_name Move

# Move system for tactical combat
# Each move has a name, description, effect function, and cooldown

@export var name: String = ""
@export var description: String = ""
@export var cooldown_turns: int = 0
@export var range: int = 1  # How far the move can reach (0 = self only, 1 = adjacent, etc.)
@export var area_of_effect: int = 0  # 0 = single target, 1 = 3x3 area, etc.
@export var move_type: MoveType = MoveType.DAMAGE
@export var icon_path: String = ""

enum MoveType {
	DAMAGE,
	HEAL,
	SHIELD,
	BUFF,
	DEBUFF,
	UTILITY,
	TILE_EFFECT
}

# Move effect data - can be customized per move
@export var base_power: int = 0
@export var accuracy: float = 1.0  # 0.0 to 1.0
@export var critical_chance: float = 0.1  # 0.0 to 1.0
@export var effect_duration: int = 0  # For buffs/debuffs (0 = instant)

# Tile effect properties (for TILE_EFFECT moves)
@export var tile_effect_type: TileEffect.EffectType = TileEffect.EffectType.NONE
@export var tile_effect_strength: int = 1
@export var tile_effect_duration: int = 3
@export var affects_multiple_tiles: bool = false
@export var tile_pattern: TilePattern = TilePattern.SINGLE

enum TilePattern {
	SINGLE,      # Single tile
	CROSS,       # + pattern
	SQUARE,      # 3x3 square
	LINE,        # Straight line
	CIRCLE,      # Circular area
	CUSTOM       # Custom pattern
}

# Custom effect function - this is where the magic happens
var effect_function: Callable

func _init(move_name: String = "", move_description: String = "", move_cooldown: int = 0):
	name = move_name
	description = move_description
	cooldown_turns = move_cooldown

func set_effect(effect_func: Callable) -> Move:
	"""Set the custom effect function for this move"""
	effect_function = effect_func
	return self

func execute(caster: Node, target: Node, target_position: Vector3 = Vector3.ZERO) -> Dictionary:
	"""Execute the move effect"""
	var result = {
		"success": false,
		"damage_dealt": 0,
		"healing_done": 0,
		"shield_applied": 0,
		"effects_applied": [],
		"tiles_affected": [],
		"tile_effects_created": [],
		"message": ""
	}
	
	# Check accuracy
	if randf() > accuracy:
		result.message = "%s missed!" % name
		return result
	
	# Execute custom effect if available
	if effect_function.is_valid():
		var custom_result = effect_function.call(caster, target, target_position, self)
		if custom_result is Dictionary:
			# Merge custom result with base result
			for key in custom_result:
				result[key] = custom_result[key]
		result.success = true
	else:
		# Default behavior based on move type
		result = _execute_default_effect(caster, target, target_position, result)
	
	return result

func _execute_default_effect(caster: Node, target: Node, target_position: Vector3, result: Dictionary) -> Dictionary:
	"""Default move effects based on move type"""
	match move_type:
		MoveType.DAMAGE:
			result = _apply_damage(caster, target, result)
		MoveType.HEAL:
			result = _apply_healing(caster, target, result)
		MoveType.SHIELD:
			result = _apply_shield(caster, target, result)
		MoveType.BUFF:
			result = _apply_buff(caster, target, result)
		MoveType.DEBUFF:
			result = _apply_debuff(caster, target, result)
		MoveType.UTILITY:
			result.message = "%s used %s" % [caster.name, name]
			result.success = true
		MoveType.TILE_EFFECT:
			result = _apply_tile_effect(caster, target_position, result)
	
	return result

func _apply_damage(caster: Node, target: Node, result: Dictionary) -> Dictionary:
	"""Apply damage to target"""
	var damage = base_power
	
	# Add caster's attack stat if available
	var caster_stats = caster.get_node_or_null("UnitStats")
	if caster_stats and caster_stats.has_method("get_attack"):
		damage += caster_stats.get_attack()
	
	# Apply critical hit
	var is_critical = randf() < critical_chance
	if is_critical:
		damage = int(damage * 1.5)
		result.message = "Critical hit! "
	
	# Apply damage to target
	var target_stats = target.get_node_or_null("UnitStats")
	if target_stats and target_stats.has_method("take_damage"):
		var actual_damage = target_stats.take_damage(damage)
		result.damage_dealt = actual_damage
		result.message += "%s dealt %d damage to %s" % [caster.name, actual_damage, target.name]
		result.success = true
	
	return result

func _apply_healing(caster: Node, target: Node, result: Dictionary) -> Dictionary:
	"""Apply healing to target"""
	var healing = base_power
	
	# Add caster's magic stat if available
	var caster_stats = caster.get_node_or_null("UnitStats")
	if caster_stats and caster_stats.has_method("get_magic"):
		healing += caster_stats.get_magic()
	
	# Apply healing to target
	var target_stats = target.get_node_or_null("UnitStats")
	if target_stats and target_stats.has_method("heal"):
		var actual_healing = target_stats.heal(healing)
		result.healing_done = actual_healing
		result.message = "%s healed %s for %d HP" % [caster.name, target.name, actual_healing]
		result.success = true
	
	return result

func _apply_shield(caster: Node, target: Node, result: Dictionary) -> Dictionary:
	"""Apply shield to target"""
	var shield_amount = base_power
	
	# Apply shield through battle effects manager
	if BattleEffectsManager:
		BattleEffectsManager.apply_shield(target, shield_amount, effect_duration)
		result.shield_applied = shield_amount
		result.message = "%s shielded %s for %d points" % [caster.name, target.name, shield_amount]
		result.success = true
	
	return result

func _apply_buff(caster: Node, target: Node, result: Dictionary) -> Dictionary:
	"""Apply buff to target"""
	if BattleEffectsManager:
		var buff_data = {
			"type": "buff",
			"name": name,
			"duration": effect_duration,
			"power": base_power
		}
		BattleEffectsManager.apply_effect(target, buff_data)
		result.effects_applied.append("buff")
		result.message = "%s buffed %s with %s" % [caster.name, target.name, name]
		result.success = true
	
	return result

func _apply_debuff(caster: Node, target: Node, result: Dictionary) -> Dictionary:
	"""Apply debuff to target"""
	if BattleEffectsManager:
		var debuff_data = {
			"type": "debuff",
			"name": name,
			"duration": effect_duration,
			"power": base_power
		}
		BattleEffectsManager.apply_effect(target, debuff_data)
		result.effects_applied.append("debuff")
		result.message = "%s debuffed %s with %s" % [caster.name, target.name, name]
		result.success = true
	
	return result

func _apply_tile_effect(caster: Node, target_position: Vector3, result: Dictionary) -> Dictionary:
	"""Apply tile effects to the battlefield"""
	var affected_positions = get_tile_pattern_positions(target_position)
	var tiles_affected = 0
	var effects_created: Array[TileEffect] = []
	
	# Create the tile effect
	var tile_effect = TileEffect.new()
	tile_effect.effect_name = name
	tile_effect.effect_type = tile_effect_type
	tile_effect.strength = tile_effect_strength
	tile_effect.duration = tile_effect_duration
	
	# Set trigger conditions based on effect type
	match tile_effect_type:
		TileEffect.EffectType.FIRE_DAMAGE, TileEffect.EffectType.ICE_DAMAGE, TileEffect.EffectType.POISON_DAMAGE, TileEffect.EffectType.LIGHTNING_DAMAGE:
			tile_effect.triggers_on_enter = true
			tile_effect.triggers_on_turn_start = true
		TileEffect.EffectType.HEALING_SPRING, TileEffect.EffectType.REGENERATION_FIELD:
			tile_effect.triggers_on_enter = true
			tile_effect.triggers_on_turn_start = true
		TileEffect.EffectType.SPEED_BOOST, TileEffect.EffectType.ATTACK_BOOST, TileEffect.EffectType.DEFENSE_BOOST, TileEffect.EffectType.MAGIC_BOOST:
			tile_effect.triggers_on_enter = true
		TileEffect.EffectType.TRAP:
			tile_effect.triggers_on_enter = true
		_:
			tile_effect.triggers_on_enter = true
	
	# Apply effect to all affected positions
	for pos in affected_positions:
		var tile = _find_tile_at_position(pos)
		if tile:
			tile.add_effect(tile_effect.duplicate())
			tiles_affected += 1
			effects_created.append(tile_effect)
	
	result.tiles_affected = affected_positions
	result.tile_effects_created = effects_created
	result.message = "%s created %s affecting %d tiles" % [caster.name, name, tiles_affected]
	result.success = tiles_affected > 0
	
	return result

func get_tile_pattern_positions(center_pos: Vector3) -> Array[Vector3]:
	"""Get positions affected by tile effect pattern"""
	var positions: Array[Vector3] = []
	
	match tile_pattern:
		TilePattern.SINGLE:
			positions.append(center_pos)
		TilePattern.CROSS:
			positions.append(center_pos)
			positions.append(center_pos + Vector3(1, 0, 0))
			positions.append(center_pos + Vector3(-1, 0, 0))
			positions.append(center_pos + Vector3(0, 0, 1))
			positions.append(center_pos + Vector3(0, 0, -1))
		TilePattern.SQUARE:
			for x in range(-1, 2):
				for z in range(-1, 2):
					positions.append(center_pos + Vector3(x, 0, z))
		TilePattern.LINE:
			# Line in the direction of range
			for i in range(range + 1):
				positions.append(center_pos + Vector3(i, 0, 0))
		TilePattern.CIRCLE:
			# Circular pattern based on area_of_effect
			var radius = area_of_effect
			for x in range(-radius, radius + 1):
				for z in range(-radius, radius + 1):
					if Vector2(x, z).length() <= radius:
						positions.append(center_pos + Vector3(x, 0, z))
		TilePattern.CUSTOM:
			# Would be defined by custom effect function
			positions.append(center_pos)
	
	return positions

func _find_tile_at_position(pos: Vector3) -> Tile:
	"""Find tile at specific world position"""
	# This would need to be connected to the game board system
	# For now, we'll use a simple approach
	var space_state = Engine.get_main_loop().current_scene.get_world_3d().direct_space_state
	if space_state:
		var query = PhysicsRayQueryParameters3D.create(pos + Vector3(0, 10, 0), pos + Vector3(0, -10, 0))
		var result = space_state.intersect_ray(query)
		if result and result.collider:
			var tile = result.collider.get_parent()
			if tile is Tile:
				return tile
	return null

func can_target(caster_pos: Vector3, target_pos: Vector3) -> bool:
	"""Check if target is within range"""
	var distance = caster_pos.distance_to(target_pos)
	return distance <= range

func get_affected_positions(center_pos: Vector3) -> Array[Vector3]:
	"""Get all positions affected by this move's area of effect"""
	var positions: Array[Vector3] = []
	
	if area_of_effect == 0:
		# Single target
		positions.append(center_pos)
	else:
		# Area of effect
		for x in range(-area_of_effect, area_of_effect + 1):
			for z in range(-area_of_effect, area_of_effect + 1):
				positions.append(center_pos + Vector3(x, 0, z))
	
	return positions

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	return {
		"name": name,
		"description": description,
		"type": MoveType.keys()[move_type],
		"power": base_power,
		"range": range,
		"cooldown": cooldown_turns,
		"accuracy": int(accuracy * 100),
		"area_effect": area_of_effect > 0
	}