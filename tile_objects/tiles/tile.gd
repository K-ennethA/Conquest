extends TileObject

class_name Tile

# Enhanced tile system with comprehensive effect support

@export var tile_type: TileType = TileType.NORMAL
@export var base_movement_cost: int = 1
@export var is_passable_base: bool = true

# Visual components
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var base_material: StandardMaterial3D
var current_material: StandardMaterial3D
var highlight_material: StandardMaterial3D

# Effect system integration
var effect_manager: TileEffectManager
var active_effects: Array[TileEffect] = []
var effect_particles: GPUParticles3D
var effect_overlay: MeshInstance3D

# Tile coordinates
var grid_position: Vector2i
var world_position: Vector3

enum TileType {
	NORMAL,
	DIFFICULT_TERRAIN,
	WATER,
	WALL,
	SPECIAL,
	LAVA,
	ICE,
	SWAMP,
	SACRED_GROUND,
	CORRUPTED
}

enum HighlightType {
	NONE,
	MOVEMENT,
	ATTACK,
	SELECTED,
	EFFECT_PREVIEW
}

func _ready() -> void:
	world_position = global_position
	_setup_base_materials()
	_setup_effect_system()
	_connect_to_effect_manager()

func _setup_base_materials() -> void:
	"""Initialize base materials for different tile types"""
	if not mesh_instance:
		return
	
	# Create base material based on tile type
	base_material = StandardMaterial3D.new()
	
	match tile_type:
		TileType.NORMAL:
			base_material.albedo_color = Color(0.8, 0.8, 0.8, 1.0)  # Light gray
		TileType.DIFFICULT_TERRAIN:
			base_material.albedo_color = Color(0.6, 0.4, 0.2, 1.0)  # Brown
		TileType.WATER:
			base_material.albedo_color = Color(0.2, 0.4, 0.8, 1.0)  # Blue
			base_material.metallic = 0.8
			base_material.roughness = 0.1
		TileType.WALL:
			base_material.albedo_color = Color(0.3, 0.3, 0.3, 1.0)  # Dark gray
		TileType.SPECIAL:
			base_material.albedo_color = Color(0.8, 0.8, 0.2, 1.0)  # Yellow
		TileType.LAVA:
			base_material.albedo_color = Color(1.0, 0.2, 0.0, 1.0)  # Red
			base_material.emission_enabled = true
			base_material.emission = Color(1.0, 0.3, 0.0)
		TileType.ICE:
			base_material.albedo_color = Color(0.8, 0.9, 1.0, 0.9)  # Light blue
			base_material.metallic = 0.9
			base_material.roughness = 0.0
		TileType.SWAMP:
			base_material.albedo_color = Color(0.3, 0.5, 0.2, 1.0)  # Dark green
		TileType.SACRED_GROUND:
			base_material.albedo_color = Color(1.0, 1.0, 0.9, 1.0)  # Light gold
			base_material.emission_enabled = true
			base_material.emission = Color(0.9, 0.9, 0.7)
		TileType.CORRUPTED:
			base_material.albedo_color = Color(0.4, 0.2, 0.4, 1.0)  # Dark purple
			base_material.emission_enabled = true
			base_material.emission = Color(0.3, 0.1, 0.3)
	
	# Create highlight material (for selection/movement preview)
	highlight_material = StandardMaterial3D.new()
	highlight_material.albedo_color = Color(0.2, 0.8, 0.2, 0.7)  # Semi-transparent green
	highlight_material.flags_transparent = true
	highlight_material.flags_unshaded = true
	
	# Apply base material
	current_material = base_material
	mesh_instance.material_override = current_material

func _setup_effect_system() -> void:
	"""Set up particle system and effect overlay for tile effects"""
	# Create particle system node
	effect_particles = GPUParticles3D.new()
	effect_particles.name = "EffectParticles"
	effect_particles.position = Vector3(0, 0.6, 0)  # Above tile surface
	effect_particles.emitting = false
	add_child(effect_particles)
	
	# Create effect overlay mesh for additional visual effects
	effect_overlay = MeshInstance3D.new()
	effect_overlay.name = "EffectOverlay"
	effect_overlay.position = Vector3(0, 0.1, 0)  # Slightly above tile
	var overlay_mesh = PlaneMesh.new()
	overlay_mesh.size = Vector2(0.9, 0.9)  # Slightly smaller than tile
	effect_overlay.mesh = overlay_mesh
	effect_overlay.visible = false
	add_child(effect_overlay)

func _connect_to_effect_manager():
	"""Connect to the global tile effect manager"""
	# This would be connected to a global effect manager
	# For now, we'll create a local reference
	pass

# Effect Management
func add_effect(effect: TileEffect) -> bool:
	"""Add an effect to this tile"""
	if not effect:
		return false
	
	# Check if effect can stack
	if not effect.stacks:
		# Remove existing effects of the same type
		for i in range(active_effects.size() - 1, -1, -1):
			if active_effects[i].effect_type == effect.effect_type:
				active_effects.remove_at(i)
	
	active_effects.append(effect)
	_update_effect_visuals()
	
	print("Added effect " + effect.effect_name + " to tile at " + str(grid_position))
	return true

func remove_effect(effect: TileEffect) -> bool:
	"""Remove a specific effect from this tile"""
	var index = active_effects.find(effect)
	if index >= 0:
		active_effects.remove_at(index)
		_update_effect_visuals()
		print("Removed effect " + effect.effect_name + " from tile at " + str(grid_position))
		return true
	return false

func remove_effects_by_type(effect_type: TileEffect.EffectType) -> int:
	"""Remove all effects of a specific type"""
	var removed_count = 0
	for i in range(active_effects.size() - 1, -1, -1):
		if active_effects[i].effect_type == effect_type:
			active_effects.remove_at(i)
			removed_count += 1
	
	if removed_count > 0:
		_update_effect_visuals()
	
	return removed_count

func get_effects() -> Array[TileEffect]:
	"""Get all active effects on this tile"""
	return active_effects.duplicate()

func has_effect_type(effect_type: TileEffect.EffectType) -> bool:
	"""Check if tile has an effect of specific type"""
	for effect in active_effects:
		if effect.effect_type == effect_type:
			return true
	return false

func apply_effects_to_unit(unit: Unit, trigger_type: String = "enter") -> Array[Dictionary]:
	"""Apply all relevant effects to a unit"""
	var results: Array[Dictionary] = []
	
	for effect in active_effects:
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
			var result = effect.apply_effect(unit, self)
			results.append(result)
			print("Applied effect " + effect.effect_name + " to " + unit.unit_name + ": " + result.message)
	
	return results

# Movement and Passability
func get_movement_cost() -> int:
	"""Get total movement cost including base cost and effect modifiers"""
	var total_cost = base_movement_cost
	
	# Add base tile type cost
	match tile_type:
		TileType.NORMAL:
			total_cost = 1
		TileType.DIFFICULT_TERRAIN:
			total_cost = 2
		TileType.WATER:
			total_cost = 3
		TileType.WALL:
			total_cost = 999  # Impassable
		TileType.SPECIAL:
			total_cost = 1
		TileType.LAVA:
			total_cost = 4
		TileType.ICE:
			total_cost = 1
		TileType.SWAMP:
			total_cost = 3
		TileType.SACRED_GROUND:
			total_cost = 1
		TileType.CORRUPTED:
			total_cost = 2
	
	# Add effect modifiers
	for effect in active_effects:
		total_cost += effect.get_movement_cost_modifier()
	
	return max(1, total_cost)  # Minimum cost of 1

func is_passable() -> bool:
	"""Check if units can move through this tile"""
	# Check base passability
	if not is_passable_base or tile_type == TileType.WALL:
		return false
	
	# Check effect restrictions
	for effect in active_effects:
		if not effect.is_passable():
			return false
	
	return true

func can_unit_stand_here(unit: Unit) -> bool:
	"""Check if a specific unit can stand on this tile"""
	if not is_passable():
		return false
	
	# Additional unit-specific checks could go here
	# For example, flying units might ignore certain terrain
	
	return true

# Visual System
func set_highlight(highlight_type: HighlightType) -> void:
	"""Set tile highlighting for UI feedback"""
	if not mesh_instance:
		return
	
	match highlight_type:
		HighlightType.NONE:
			mesh_instance.material_override = current_material
		HighlightType.MOVEMENT:
			var movement_material = highlight_material.duplicate()
			movement_material.albedo_color = Color(0.2, 0.8, 0.2, 0.5)  # Green
			mesh_instance.material_override = movement_material
		HighlightType.ATTACK:
			var attack_material = highlight_material.duplicate()
			attack_material.albedo_color = Color(0.8, 0.2, 0.2, 0.5)  # Red
			mesh_instance.material_override = attack_material
		HighlightType.SELECTED:
			var selected_material = highlight_material.duplicate()
			selected_material.albedo_color = Color(0.8, 0.8, 0.2, 0.6)  # Yellow
			mesh_instance.material_override = selected_material
		HighlightType.EFFECT_PREVIEW:
			var preview_material = highlight_material.duplicate()
			preview_material.albedo_color = Color(0.8, 0.2, 0.8, 0.5)  # Purple
			mesh_instance.material_override = preview_material

func _update_effect_visuals() -> void:
	"""Update visual effects based on active effects"""
	if active_effects.is_empty():
		# Reset to base material
		current_material = base_material
		mesh_instance.material_override = current_material
		effect_overlay.visible = false
		if effect_particles:
			effect_particles.emitting = false
	else:
		# Use the most prominent effect for visuals
		var primary_effect = _get_primary_effect()
		_apply_effect_material(primary_effect)
		_setup_effect_particles(primary_effect)
		effect_overlay.visible = true

func _get_primary_effect() -> TileEffect:
	"""Get the most visually prominent effect"""
	if active_effects.is_empty():
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
		for effect in active_effects:
			if effect.effect_type == priority_type:
				return effect
	
	return active_effects[0]  # Return first effect if no priority match

func _apply_effect_material(effect: TileEffect):
	"""Apply visual material for an effect"""
	if not effect:
		return
	
	var effect_material = base_material.duplicate()
	
	match effect.effect_type:
		TileEffect.EffectType.FIRE_DAMAGE:
			effect_material.albedo_color = Color(1.0, 0.3, 0.1, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(1.0, 0.5, 0.1)
		TileEffect.EffectType.ICE_DAMAGE:
			effect_material.albedo_color = Color(0.7, 0.9, 1.0, 0.8)
			effect_material.metallic = 0.8
			effect_material.roughness = 0.1
		TileEffect.EffectType.POISON_DAMAGE:
			effect_material.albedo_color = Color(0.5, 0.8, 0.2, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.3, 0.6, 0.1)
		TileEffect.EffectType.LIGHTNING_DAMAGE:
			effect_material.albedo_color = Color(0.9, 0.9, 1.0, 0.9)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.8, 0.8, 1.0)
		TileEffect.EffectType.HEALING_SPRING:
			effect_material.albedo_color = Color(0.2, 1.0, 0.4, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.1, 0.8, 0.2)
		TileEffect.EffectType.REGENERATION_FIELD:
			effect_material.albedo_color = Color(0.4, 0.9, 0.6, 0.7)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.2, 0.7, 0.3)
		TileEffect.EffectType.SANCTUARY:
			effect_material.albedo_color = Color(1.0, 1.0, 0.8, 0.9)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.9, 0.9, 0.7)
		TileEffect.EffectType.SPEED_BOOST:
			effect_material.albedo_color = Color(0.9, 0.9, 0.2, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.8, 0.8, 0.1)
		TileEffect.EffectType.ATTACK_BOOST:
			effect_material.albedo_color = Color(1.0, 0.5, 0.5, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.9, 0.3, 0.3)
		TileEffect.EffectType.DEFENSE_BOOST:
			effect_material.albedo_color = Color(0.5, 0.5, 1.0, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.3, 0.3, 0.9)
		TileEffect.EffectType.MAGIC_BOOST:
			effect_material.albedo_color = Color(0.9, 0.2, 0.9, 0.8)
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.7, 0.1, 0.7)
	
	current_material = effect_material
	mesh_instance.material_override = current_material
	
	# Also apply to overlay
	if effect_overlay:
		effect_overlay.material_override = effect_material

func _setup_effect_particles(effect: TileEffect):
	"""Set up particle effects for an effect"""
	if not effect_particles or not effect:
		return
	
	# Basic particle setup - would be expanded with proper particle resources
	effect_particles.emitting = true
	
	# This would be expanded with specific particle configurations
	# for different effect types

# Utility Methods
func get_world_position() -> Vector3:
	"""Get the world position of this tile"""
	return world_position

func set_grid_position(pos: Vector2i):
	"""Set the grid position of this tile"""
	grid_position = pos

func get_grid_position() -> Vector2i:
	"""Get the grid position of this tile"""
	return grid_position

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	var info = {
		"position": grid_position,
		"type": TileType.keys()[tile_type],
		"movement_cost": get_movement_cost(),
		"passable": is_passable(),
		"effects": []
	}
	
	for effect in active_effects:
		info.effects.append(effect.get_display_info())
	
	return info

# Turn Processing
func process_turn_effects(turn_type: String = "start"):
	"""Process turn-based effects on this tile"""
	var effects_to_remove: Array[TileEffect] = []
	
	for effect in active_effects:
		# Reduce duration
		if effect.duration > 0:
			effect.duration -= 1
			if effect.duration <= 0:
				effects_to_remove.append(effect)
	
	# Remove expired effects
	for effect in effects_to_remove:
		remove_effect(effect)

# Factory Methods for Common Tile Configurations
static func create_fire_tile() -> Tile:
	var tile = Tile.new()
	tile.tile_type = TileType.LAVA
	var fire_effect = TileEffectManager.create_fire_tile(2, 5)
	tile.add_effect(fire_effect)
	return tile

static func create_healing_tile() -> Tile:
	var tile = Tile.new()
	tile.tile_type = TileType.SACRED_GROUND
	var healing_effect = TileEffectManager.create_healing_spring(3, -1)
	tile.add_effect(healing_effect)
	return tile

static func create_trap_tile() -> Tile:
	var tile = Tile.new()
	tile.tile_type = TileType.NORMAL
	var trap_effect = TileEffectManager.create_trap_tile(3)
	tile.add_effect(trap_effect)
	return tile
