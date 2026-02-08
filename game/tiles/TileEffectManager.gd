extends Node

class_name TileEffectManager

# Manages tile effects across the game board

signal effect_applied(unit: Unit, tile: Tile, effect: TileEffect, result: Dictionary)
signal effect_expired(tile: Tile, effect: TileEffect)
signal tile_visual_changed(tile: Tile, effect: TileEffect)

# Active effects tracking
var active_effects: Dictionary = {}  # tile_position -> Array[TileEffect]
var effect_timers: Dictionary = {}   # effect_id -> remaining_turns

# Visual effect resources
var particle_effects: Dictionary = {}
var material_overrides: Dictionary = {}

func _ready():
	_load_effect_resources()

func _load_effect_resources():
	"""Load visual resources for tile effects"""
	# This would load particle effects, materials, etc.
	# For now, we'll create them procedurally
	_create_default_materials()

func _create_default_materials():
	"""Create default materials for different effect types"""
	for effect_type in TileEffect.EffectType.values():
		var material = StandardMaterial3D.new()
		
		match effect_type:
			TileEffect.EffectType.FIRE_DAMAGE:
				material.albedo_color = Color(1.0, 0.3, 0.1, 0.8)
				material.emission_enabled = true
				material.emission = Color(1.0, 0.5, 0.1)
			TileEffect.EffectType.ICE_DAMAGE:
				material.albedo_color = Color(0.7, 0.9, 1.0, 0.8)
				material.metallic = 0.8
				material.roughness = 0.1
			TileEffect.EffectType.POISON_DAMAGE:
				material.albedo_color = Color(0.5, 0.8, 0.2, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.3, 0.6, 0.1)
			TileEffect.EffectType.LIGHTNING_DAMAGE:
				material.albedo_color = Color(0.9, 0.9, 1.0, 0.9)
				material.emission_enabled = true
				material.emission = Color(0.8, 0.8, 1.0)
			TileEffect.EffectType.HEALING_SPRING:
				material.albedo_color = Color(0.2, 1.0, 0.4, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.1, 0.8, 0.2)
			TileEffect.EffectType.REGENERATION_FIELD:
				material.albedo_color = Color(0.4, 0.9, 0.6, 0.7)
				material.emission_enabled = true
				material.emission = Color(0.2, 0.7, 0.3)
			TileEffect.EffectType.SANCTUARY:
				material.albedo_color = Color(1.0, 1.0, 0.8, 0.9)
				material.emission_enabled = true
				material.emission = Color(0.9, 0.9, 0.7)
			TileEffect.EffectType.SPEED_BOOST:
				material.albedo_color = Color(0.9, 0.9, 0.2, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.8, 0.8, 0.1)
			TileEffect.EffectType.ATTACK_BOOST:
				material.albedo_color = Color(1.0, 0.5, 0.5, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.9, 0.3, 0.3)
			TileEffect.EffectType.DEFENSE_BOOST:
				material.albedo_color = Color(0.5, 0.5, 1.0, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.3, 0.3, 0.9)
			TileEffect.EffectType.MAGIC_BOOST:
				material.albedo_color = Color(0.9, 0.2, 0.9, 0.8)
				material.emission_enabled = true
				material.emission = Color(0.7, 0.1, 0.7)
			_:
				material.albedo_color = Color(0.8, 0.8, 0.8, 0.5)
		
		material_overrides[effect_type] = material

func add_tile_effect(tile: Tile, effect: TileEffect) -> bool:
	"""Add an effect to a tile"""
	if not tile or not effect:
		return false
	
	var tile_pos = tile.global_position
	var pos_key = _position_to_key(tile_pos)
	
	# Initialize effects array for this tile if needed
	if not active_effects.has(pos_key):
		active_effects[pos_key] = []
	
	# Check if effect can stack
	if not effect.stacks:
		# Remove existing effects of the same type
		var existing_effects = active_effects[pos_key] as Array[TileEffect]
		for i in range(existing_effects.size() - 1, -1, -1):
			if existing_effects[i].effect_type == effect.effect_type:
				existing_effects.remove_at(i)
	
	# Add the new effect
	active_effects[pos_key].append(effect)
	
	# Set up timer if effect has duration
	if effect.duration > 0:
		var effect_id = _generate_effect_id(tile_pos, effect)
		effect_timers[effect_id] = effect.duration
	
	# Update tile visuals
	_update_tile_visuals(tile)
	
	print("Added effect " + effect.effect_name + " to tile at " + str(tile_pos))
	return true

func remove_tile_effect(tile: Tile, effect: TileEffect) -> bool:
	"""Remove a specific effect from a tile"""
	if not tile or not effect:
		return false
	
	var tile_pos = tile.global_position
	var pos_key = _position_to_key(tile_pos)
	
	if not active_effects.has(pos_key):
		return false
	
	var effects = active_effects[pos_key] as Array[TileEffect]
	var removed = false
	
	for i in range(effects.size() - 1, -1, -1):
		if effects[i] == effect:
			effects.remove_at(i)
			removed = true
			break
	
	if removed:
		# Clean up timer
		var effect_id = _generate_effect_id(tile_pos, effect)
		if effect_timers.has(effect_id):
			effect_timers.erase(effect_id)
		
		# Update visuals
		_update_tile_visuals(tile)
		
		effect_expired.emit(tile, effect)
		print("Removed effect " + effect.effect_name + " from tile at " + str(tile_pos))
	
	return removed

func get_tile_effects(tile: Tile) -> Array[TileEffect]:
	"""Get all effects on a tile"""
	if not tile:
		return []
	
	var pos_key = _position_to_key(tile.global_position)
	if active_effects.has(pos_key):
		return active_effects[pos_key]
	return []

func apply_tile_effects_to_unit(unit: Unit, tile: Tile, trigger_type: String = "enter") -> Array[Dictionary]:
	"""Apply all relevant tile effects to a unit"""
	var results: Array[Dictionary] = []
	var effects = get_tile_effects(tile)
	
	for effect in effects:
		var should_trigger = false
		
		match trigger_type:
			"enter":
				should_trigger = effect.triggers_on_enter
			"exit":
				should_trigger = effect.triggers_on_exit
			"turn_start":
				should_trigger = effect.triggers_on_turn_start
			"turn_end":
				should_trigger = effect.triggers_on_turn_end
		
		if should_trigger:
			var result = effect.apply_effect(unit, tile)
			results.append(result)
			
			# Apply the effect results to the unit
			if result.success:
				_apply_effect_result_to_unit(unit, result)
				effect_applied.emit(unit, tile, effect, result)
	
	return results

func _apply_effect_result_to_unit(unit: Unit, result: Dictionary):
	"""Apply effect results to a unit's stats"""
	if not unit or not unit.unit_stats:
		return
	
	# Apply damage
	if result.damage > 0:
		unit.unit_stats.take_damage(result.damage)
	
	# Apply healing
	if result.healing > 0:
		unit.unit_stats.heal(result.healing)
	
	# Apply stat changes (temporary)
	if result.has("stat_changes") and not result.stat_changes.is_empty():
		for stat_name in result.stat_changes:
			var change = result.stat_changes[stat_name]
			unit.unit_stats.apply_temporary_stat_change(stat_name, change)
	
	# Apply status effects (would need status effect system)
	if result.has("status_effects") and not result.status_effects.is_empty():
		for status in result.status_effects:
			print("Applied status effect: " + status + " to " + unit.unit_name)

func get_movement_cost_for_tile(tile: Tile) -> int:
	"""Get total movement cost for a tile including effects"""
	var base_cost = tile.get_movement_cost()
	var effects = get_tile_effects(tile)
	
	for effect in effects:
		base_cost += effect.get_movement_cost_modifier()
	
	return max(1, base_cost)  # Minimum cost of 1

func is_tile_passable(tile: Tile) -> bool:
	"""Check if a tile is passable considering all effects"""
	if not tile.is_passable():
		return false
	
	var effects = get_tile_effects(tile)
	for effect in effects:
		if not effect.is_passable():
			return false
	
	return true

func process_turn_effects(turn_type: String = "start"):
	"""Process all turn-based effects"""
	var tiles_to_update: Array[Tile] = []
	
	# Process effect timers
	for effect_id in effect_timers.keys():
		effect_timers[effect_id] -= 1
		
		if effect_timers[effect_id] <= 0:
			# Effect expired
			var parts = effect_id.split("_")
			if parts.size() >= 3:
				var pos_key = parts[0] + "_" + parts[1] + "_" + parts[2]
				if active_effects.has(pos_key):
					var effects = active_effects[pos_key] as Array[TileEffect]
					for i in range(effects.size() - 1, -1, -1):
						if effects[i].duration == 0:
							var expired_effect = effects[i]
							effects.remove_at(i)
							# Find the tile and update visuals
							var tile = _find_tile_by_position_key(pos_key)
							if tile:
								_update_tile_visuals(tile)
								effect_expired.emit(tile, expired_effect)
			
			effect_timers.erase(effect_id)

func clear_all_effects():
	"""Clear all tile effects (for game reset)"""
	active_effects.clear()
	effect_timers.clear()

func _update_tile_visuals(tile: Tile):
	"""Update tile visual effects"""
	if not tile:
		return
	
	var effects = get_tile_effects(tile)
	
	if effects.is_empty():
		# Reset to base material
		tile._setup_base_materials()
	else:
		# Use the most prominent effect for visuals
		var primary_effect = _get_primary_effect(effects)
		if material_overrides.has(primary_effect.effect_type):
			var material = material_overrides[primary_effect.effect_type]
			if tile.mesh_instance:
				tile.mesh_instance.material_override = material
	
	tile_visual_changed.emit(tile, effects[0] if not effects.is_empty() else null)

func _get_primary_effect(effects: Array[TileEffect]) -> TileEffect:
	"""Get the most visually prominent effect"""
	if effects.is_empty():
		return null
	
	# Priority order for visual effects
	var priority_order = [
		TileEffect.EffectType.FIRE_DAMAGE,
		TileEffect.EffectType.LIGHTNING_DAMAGE,
		TileEffect.EffectType.ICE_DAMAGE,
		TileEffect.EffectType.POISON_DAMAGE,
		TileEffect.EffectType.HEALING_SPRING,
		TileEffect.EffectType.SANCTUARY,
		TileEffect.EffectType.ATTACK_BOOST,
		TileEffect.EffectType.DEFENSE_BOOST,
		TileEffect.EffectType.SPEED_BOOST,
		TileEffect.EffectType.MAGIC_BOOST
	]
	
	for priority_type in priority_order:
		for effect in effects:
			if effect.effect_type == priority_type:
				return effect
	
	return effects[0]  # Return first effect if no priority match

func _position_to_key(pos: Vector3) -> String:
	"""Convert position to string key for dictionary"""
	return str(int(pos.x)) + "_" + str(int(pos.y)) + "_" + str(int(pos.z))

func _generate_effect_id(pos: Vector3, effect: TileEffect) -> String:
	"""Generate unique ID for effect tracking"""
	return _position_to_key(pos) + "_" + effect.effect_name + "_" + str(Time.get_ticks_msec())

func _find_tile_by_position_key(pos_key: String) -> Tile:
	"""Find tile by position key (would need reference to game board)"""
	# This would need to be connected to the game board system
	# For now, return null
	return null

# Factory methods for common effects
static func create_fire_tile(strength: int = 1, duration: int = 3) -> TileEffect:
	var effect = TileEffect.new()
	effect.effect_name = "Fire Damage"
	effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
	effect.strength = strength
	effect.duration = duration
	effect.affects_combat = true
	effect.triggers_on_enter = true
	effect.triggers_on_turn_start = true
	return effect

static func create_healing_spring(strength: int = 2, duration: int = -1) -> TileEffect:
	var effect = TileEffect.new()
	effect.effect_name = "Healing Spring"
	effect.effect_type = TileEffect.EffectType.HEALING_SPRING
	effect.strength = strength
	effect.duration = duration
	effect.affects_healing = true
	effect.triggers_on_enter = true
	effect.triggers_on_turn_start = true
	return effect

static func create_speed_boost_tile(strength: int = 1, duration: int = 2) -> TileEffect:
	var effect = TileEffect.new()
	effect.effect_name = "Speed Boost"
	effect.effect_type = TileEffect.EffectType.SPEED_BOOST
	effect.strength = strength
	effect.duration = duration
	effect.affects_movement = true
	effect.triggers_on_enter = true
	return effect

static func create_trap_tile(strength: int = 2) -> TileEffect:
	var effect = TileEffect.new()
	effect.effect_name = "Hidden Trap"
	effect.effect_type = TileEffect.EffectType.TRAP
	effect.strength = strength
	effect.duration = 0  # Instant effect
	effect.affects_combat = true
	effect.triggers_on_enter = true
	return effect

static func create_difficult_terrain(strength: int = 1) -> TileEffect:
	var effect = TileEffect.new()
	effect.effect_name = "Difficult Terrain"
	effect.effect_type = TileEffect.EffectType.DIFFICULT_TERRAIN
	effect.strength = strength
	effect.duration = -1  # Permanent
	effect.affects_movement = true
	return effect