extends TileObject

class_name Tile

# Enhanced tile system with visual effect support

@export var tile_type: TileType = TileType.NORMAL
@export var has_effect: bool = false
@export var effect_type: EffectType = EffectType.NONE

# Visual components
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var base_material: StandardMaterial3D
var effect_material: StandardMaterial3D
var highlight_material: StandardMaterial3D

# Effect system (preparation for Phase 4)
var active_effects: Array[TileEffect] = []
var effect_particles: GPUParticles3D

enum TileType {
	NORMAL,
	DIFFICULT_TERRAIN,
	WATER,
	WALL,
	SPECIAL
}

enum EffectType {
	NONE,
	FIRE,
	ICE,
	POISON,
	HEALING,
	SPEED_BOOST,
	DAMAGE_BOOST
}

func _ready() -> void:
	_setup_base_materials()
	_setup_effect_system()

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
		TileType.WALL:
			base_material.albedo_color = Color(0.3, 0.3, 0.3, 1.0)  # Dark gray
		TileType.SPECIAL:
			base_material.albedo_color = Color(0.8, 0.8, 0.2, 1.0)  # Yellow
	
	# Create highlight material (for selection/movement preview)
	highlight_material = StandardMaterial3D.new()
	highlight_material.albedo_color = Color(0.2, 0.8, 0.2, 0.7)  # Semi-transparent green
	highlight_material.flags_transparent = true
	highlight_material.flags_unshaded = true
	
	# Apply base material
	mesh_instance.material_override = base_material

func _setup_effect_system() -> void:
	"""Prepare particle system for tile effects (Phase 4)"""
	# Create particle system node (but don't activate yet)
	effect_particles = GPUParticles3D.new()
	effect_particles.name = "EffectParticles"
	effect_particles.position = Vector3(0, 0.6, 0)  # Above tile surface
	effect_particles.emitting = false
	add_child(effect_particles)
	
	# Apply initial effect if specified
	if has_effect and effect_type != EffectType.NONE:
		_setup_effect_material()

func _setup_effect_material() -> void:
	"""Create effect-specific material overlay"""
	effect_material = base_material.duplicate()
	
	match effect_type:
		EffectType.FIRE:
			effect_material.albedo_color = Color(1.0, 0.3, 0.1, 0.8)  # Red-orange
			effect_material.emission_enabled = true
			effect_material.emission = Color(1.0, 0.5, 0.1)
		EffectType.ICE:
			effect_material.albedo_color = Color(0.7, 0.9, 1.0, 0.8)  # Light blue
			effect_material.metallic = 0.8
			effect_material.roughness = 0.1
		EffectType.POISON:
			effect_material.albedo_color = Color(0.5, 0.8, 0.2, 0.8)  # Sickly green
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.3, 0.6, 0.1)
		EffectType.HEALING:
			effect_material.albedo_color = Color(0.2, 1.0, 0.4, 0.8)  # Bright green
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.1, 0.8, 0.2)
		EffectType.SPEED_BOOST:
			effect_material.albedo_color = Color(0.9, 0.9, 0.2, 0.8)  # Yellow
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.8, 0.8, 0.1)
		EffectType.DAMAGE_BOOST:
			effect_material.albedo_color = Color(0.9, 0.2, 0.9, 0.8)  # Purple
			effect_material.emission_enabled = true
			effect_material.emission = Color(0.7, 0.1, 0.7)

# Highlighting system for movement/selection preview
func set_highlight(highlight_type: HighlightType) -> void:
	"""Set tile highlighting for UI feedback"""
	if not mesh_instance:
		return
	
	match highlight_type:
		HighlightType.NONE:
			mesh_instance.material_override = base_material
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

enum HighlightType {
	NONE,
	MOVEMENT,
	ATTACK,
	SELECTED
}

# Effect management (preparation for Phase 4)
func add_effect(effect: TileEffect) -> void:
	"""Add a tile effect (Phase 4 feature)"""
	active_effects.append(effect)
	_update_effect_visuals()

func remove_effect(effect: TileEffect) -> void:
	"""Remove a tile effect (Phase 4 feature)"""
	active_effects.erase(effect)
	_update_effect_visuals()

func _update_effect_visuals() -> void:
	"""Update visual effects based on active effects"""
	if active_effects.is_empty():
		if effect_particles:
			effect_particles.emitting = false
		mesh_instance.material_override = base_material
	else:
		# Use the most recent effect for visuals
		var latest_effect = active_effects[-1]
		# This will be expanded in Phase 4
		if effect_particles:
			effect_particles.emitting = true

# Utility methods
func get_world_position() -> Vector3:
	"""Get the world position of this tile"""
	return global_position

func is_passable() -> bool:
	"""Check if units can move through this tile"""
	return tile_type != TileType.WALL

func get_movement_cost() -> int:
	"""Get movement cost for this tile type"""
	match tile_type:
		TileType.NORMAL:
			return 1
		TileType.DIFFICULT_TERRAIN:
			return 2
		TileType.WATER:
			return 3
		TileType.WALL:
			return 999  # Impassable
		TileType.SPECIAL:
			return 1
		_:
			return 1

# Placeholder for Phase 4 tile effects
class TileEffect:
	var effect_type: EffectType
	var duration: int
	var strength: int
	
	func _init(type: EffectType, dur: int = -1, str: int = 1):
		effect_type = type
		duration = dur
		strength = str
