extends Node

class_name UnitVisualManager

# Manages visual appearance of units including materials, health bars, and type indicators

@export var player_materials: PlayerMaterials

var _health_bar_scene: PackedScene
var _unit_health_bars: Dictionary = {}  # Unit -> HealthBar

func _ready():
	if not player_materials:
		player_materials = PlayerMaterials.new()
	
	# Load health bar scene
	_health_bar_scene = preload("res://game/visuals/HealthBar.tscn")
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	
	# Connect to game events
	GameEvents.unit_action_completed.connect(_on_unit_action_completed)

func setup_unit_visuals(unit: Unit, player_assignment: PlayerMaterials.PlayerTeam) -> void:
	"""Set up all visual elements for a unit"""
	_apply_player_material(unit, player_assignment)
	_setup_unit_type_indicator(unit)
	_create_health_bar(unit)

func setup_unit_visuals_for_player(unit: Unit, player: Player) -> void:
	"""Set up all visual elements for a unit using new Player class"""
	var player_assignment = _convert_player_to_assignment(player)
	setup_unit_visuals(unit, player_assignment)

func _convert_player_to_assignment(player: Player) -> PlayerMaterials.PlayerTeam:
	"""Convert new Player class to PlayerMaterials.PlayerTeam enum"""
	if not player:
		return PlayerMaterials.PlayerTeam.NEUTRAL
	
	match player.player_id:
		0:
			return PlayerMaterials.PlayerTeam.PLAYER_1
		1:
			return PlayerMaterials.PlayerTeam.PLAYER_2
		_:
			return PlayerMaterials.PlayerTeam.NEUTRAL

func _apply_player_material(unit: Unit, player: PlayerMaterials.PlayerTeam) -> void:
	"""Apply player-specific material to unit"""
	var mesh_instance = unit.get_node("MeshInstance3D")
	if not mesh_instance:
		push_warning("Unit has no MeshInstance3D node: " + str(unit))
		return
	
	var unit_type = UnitType.Type.WARRIOR
	if unit.unit_stats and unit.unit_stats.stats_resource and unit.unit_stats.stats_resource.unit_type:
		unit_type = unit.unit_stats.stats_resource.unit_type.type
	
	var material = player_materials.get_player_material(player, unit_type)
	mesh_instance.material_override = material
	
	# Add scale differences to make unit types more distinct
	match unit_type:
		UnitType.Type.WARRIOR:
			mesh_instance.scale = Vector3(1.0, 1.0, 1.0)  # Normal size
		UnitType.Type.ARCHER:
			mesh_instance.scale = Vector3(0.8, 1.2, 0.8)  # Taller and thinner
		UnitType.Type.SCOUT:
			mesh_instance.scale = Vector3(1.2, 0.8, 1.2)  # Shorter and wider
		UnitType.Type.TANK:
			mesh_instance.scale = Vector3(1.3, 1.1, 1.3)  # Bigger overall

func _setup_unit_type_indicator(unit: Unit) -> void:
	"""Add visual indicators for unit type"""
	if not unit.unit_stats or not unit.unit_stats.stats_resource:
		return
	
	var unit_type = unit.unit_stats.stats_resource.unit_type
	if not unit_type:
		return
	
	# For now, we'll use material variations instead of mesh modifications
	# This avoids property compatibility issues
	# TODO: Add mesh shape variations once we determine correct property names
	
	# The material differences are already handled in _apply_player_material()
	# so unit types will be distinguished by material properties (metallic, roughness, etc.)

func _create_health_bar(unit: Unit) -> void:
	"""Create and attach health bar to unit"""
	if not _health_bar_scene:
		push_warning("Health bar scene not loaded")
		return
	
	var health_bar = _health_bar_scene.instantiate()
	unit.add_child(health_bar)
	
	# Position health bar higher to avoid clipping with taller units (Archers are 1.2x height)
	health_bar.position = Vector3(0, 1.8, 0)  # Higher to clear all unit types
	
	# Normal scale for good readability
	health_bar.scale = Vector3(1.0, 1.0, 1.0)
	
	# Store reference
	_unit_health_bars[unit] = health_bar
	
	# Initialize health bar
	_update_health_bar(unit)

func _update_health_bar(unit: Unit) -> void:
	"""Update health bar display"""
	if not _unit_health_bars.has(unit):
		return
	
	var health_bar = _unit_health_bars[unit]
	if not health_bar:
		return
	
	var current_health = unit.current_health
	var max_health = unit.max_health
	
	if max_health > 0:
		var health_percentage = float(current_health) / float(max_health)
		health_bar.update_health(health_percentage, current_health, max_health)

func _on_unit_health_changed(unit: Unit, old_health: int, new_health: int) -> void:
	"""Handle unit health changes"""
	_update_health_bar(unit)

func apply_selection_visual(unit: Unit, selected: bool) -> void:
	"""Apply or remove selection visual effects"""
	var mesh_instance = unit.get_node("MeshInstance3D")
	if not mesh_instance:
		return
	
	if selected:
		# Add selection glow with enhanced visibility
		var base_material = mesh_instance.material_override
		if base_material:
			var selection_material = base_material.duplicate()
			selection_material.emission_enabled = true
			selection_material.emission = Color(1.0, 1.0, 0.5, 1.0)  # Bright yellow glow
			selection_material.rim_enabled = true
			selection_material.rim = 0.5  # Float value, not Color
			selection_material.rim_tint = 0.5
			mesh_instance.material_override = selection_material
	else:
		# Restore appropriate material based on unit's current state
		_restore_unit_material(unit)

func apply_current_acting_highlight(unit: Unit, is_current: bool) -> void:
	"""Apply or remove highlighting for the current acting unit in Speed First mode"""
	var mesh_instance = unit.get_node("MeshInstance3D")
	if not mesh_instance:
		return
	
	if is_current:
		# Add bright pulsing highlight for current acting unit
		var base_material = mesh_instance.material_override
		if base_material:
			var highlight_material = base_material.duplicate()
			highlight_material.emission_enabled = true
			highlight_material.emission = Color(0.0, 1.0, 1.0, 1.0)  # Bright cyan glow
			highlight_material.rim_enabled = true
			highlight_material.rim = 0.8  # Float value, not Color
			highlight_material.rim_tint = 0.8
			# Make it more prominent
			highlight_material.metallic = 0.3
			highlight_material.roughness = 0.2
			mesh_instance.material_override = highlight_material
			
			# Add pulsing animation
			_add_pulsing_animation(unit)
	else:
		# Remove pulsing animation
		_remove_pulsing_animation(unit)
		# Restore appropriate material
		_restore_unit_material(unit)

func _add_pulsing_animation(unit: Unit) -> void:
	"""Add pulsing animation to unit"""
	var mesh_instance = unit.get_node("MeshInstance3D")
	if not mesh_instance:
		return
	
	# Remove existing tween if any
	_remove_pulsing_animation(unit)
	
	# Create pulsing tween
	var tween = unit.create_tween()
	tween.set_loops()
	tween.tween_property(mesh_instance, "scale", mesh_instance.scale * 1.1, 0.8)
	tween.tween_property(mesh_instance, "scale", mesh_instance.scale, 0.8)
	
	# Store tween reference for cleanup
	unit.set_meta("_acting_tween", tween)

func _remove_pulsing_animation(unit: Unit) -> void:
	"""Remove pulsing animation from unit"""
	if unit.has_meta("_acting_tween"):
		var tween = unit.get_meta("_acting_tween")
		if tween and tween.is_valid():
			tween.kill()
		unit.remove_meta("_acting_tween")
	
	# Reset scale to original
	var mesh_instance = unit.get_node("MeshInstance3D")
	if mesh_instance:
		# Reset to unit type appropriate scale
		var unit_type = UnitType.Type.WARRIOR
		if unit.unit_stats and unit.unit_stats.stats_resource and unit.unit_stats.stats_resource.unit_type:
			unit_type = unit.unit_stats.stats_resource.unit_type.type
		
		match unit_type:
			UnitType.Type.WARRIOR:
				mesh_instance.scale = Vector3(1.0, 1.0, 1.0)
			UnitType.Type.ARCHER:
				mesh_instance.scale = Vector3(0.8, 1.2, 0.8)
			UnitType.Type.SCOUT:
				mesh_instance.scale = Vector3(1.2, 0.8, 1.2)
			UnitType.Type.TANK:
				mesh_instance.scale = Vector3(1.3, 1.1, 1.3)

func _restore_unit_material(unit: Unit) -> void:
	"""Restore unit material based on current state (acted or not acted)"""
	if not TurnSystemManager.has_active_turn_system():
		# No turn system active, just apply base player material
		var player = _determine_unit_player(unit)
		_apply_player_material(unit, player)
		return
	
	var turn_system = TurnSystemManager.get_active_turn_system()
	var has_acted = false
	
	# Check if unit has acted in current turn
	if turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		var acted_units = trad_system.get_units_that_acted()
		has_acted = unit in acted_units
	elif turn_system is SpeedFirstTurnSystem:
		var speed_system = turn_system as SpeedFirstTurnSystem
		has_acted = unit in speed_system.get_units_that_acted_this_round()
	
	# Apply appropriate visual state
	if has_acted:
		apply_acted_visual(unit, true)
	else:
		var player = _determine_unit_player(unit)
		_apply_player_material(unit, player)

func apply_acted_visual(unit: Unit, has_acted: bool) -> void:
	"""Apply or remove visual effects for units that have acted"""
	var mesh_instance = unit.get_node("MeshInstance3D")
	if not mesh_instance:
		return
	
	if has_acted:
		# Gray out the unit by reducing saturation and brightness
		var player = _determine_unit_player(unit)
		var base_material = player_materials.get_player_material(player, _get_unit_type(unit))
		
		var acted_material = base_material.duplicate()
		
		# Reduce albedo brightness and saturation
		var original_color = acted_material.albedo_color
		var gray_color = Color(
			original_color.r * 0.5 + 0.3,  # Mix with gray
			original_color.g * 0.5 + 0.3,
			original_color.b * 0.5 + 0.3,
			original_color.a * 0.7  # Make slightly transparent
		)
		acted_material.albedo_color = gray_color
		
		# Reduce emission if present
		if acted_material.emission_enabled:
			acted_material.emission = acted_material.emission * 0.3
		
		# Reduce metallic and increase roughness for duller appearance
		acted_material.metallic = acted_material.metallic * 0.5
		acted_material.roughness = min(acted_material.roughness + 0.3, 1.0)
		
		mesh_instance.material_override = acted_material
	else:
		# Restore original material
		var player = _determine_unit_player(unit)
		_apply_player_material(unit, player)

func _get_unit_type(unit: Unit) -> UnitType.Type:
	"""Get the unit type for a unit"""
	if unit.unit_stats and unit.unit_stats.stats_resource and unit.unit_stats.stats_resource.unit_type:
		return unit.unit_stats.stats_resource.unit_type.type
	return UnitType.Type.WARRIOR  # Default

func _determine_unit_player(unit: Unit) -> PlayerMaterials.PlayerTeam:
	"""Determine which player owns this unit based on scene tree position"""
	var parent = unit.get_parent()
	if parent and parent.name.contains("Player1"):
		return PlayerMaterials.PlayerTeam.PLAYER_1
	elif parent and parent.name.contains("Player2"):
		return PlayerMaterials.PlayerTeam.PLAYER_2
	else:
		return PlayerMaterials.PlayerTeam.NEUTRAL

func update_all_unit_visuals() -> void:
	"""Update visual state of all units based on current turn system"""
	if not TurnSystemManager.has_active_turn_system():
		return
	
	var turn_system = TurnSystemManager.get_active_turn_system()
	
	# Find all units in the scene
	var all_units = _find_all_units()
	
	for unit in all_units:
		var has_acted = false
		
		if turn_system is TraditionalTurnSystem:
			var trad_system = turn_system as TraditionalTurnSystem
			var acted_units = trad_system.get_units_that_acted()
			has_acted = unit in acted_units
		elif turn_system is SpeedFirstTurnSystem:
			var speed_system = turn_system as SpeedFirstTurnSystem
			has_acted = unit in speed_system.get_units_that_acted_this_round()
		
		apply_acted_visual(unit, has_acted)

func _find_all_units() -> Array[Unit]:
	"""Find all units in the current scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func cleanup_unit_visuals(unit: Unit) -> void:
	"""Clean up visual elements when unit is removed"""
	if _unit_health_bars.has(unit):
		var health_bar = _unit_health_bars[unit]
		if health_bar:
			health_bar.queue_free()
		_unit_health_bars.erase(unit)

# Event handlers
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	# Connect to turn system specific events
	if turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.disconnect(_on_turn_started)
	if turn_system.turn_ended.is_connected(_on_turn_ended):
		turn_system.turn_ended.disconnect(_on_turn_ended)
	if turn_system.unit_action_completed.is_connected(_on_turn_system_unit_action):
		turn_system.unit_action_completed.disconnect(_on_turn_system_unit_action)
	
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)
	turn_system.unit_action_completed.connect(_on_turn_system_unit_action)
	
	# Update all unit visuals
	update_all_unit_visuals()
	
	# Special handling for Speed First system
	if turn_system is SpeedFirstTurnSystem:
		_update_speed_first_highlights(turn_system as SpeedFirstTurnSystem)

func _update_speed_first_highlights(speed_system: SpeedFirstTurnSystem) -> void:
	"""Update highlighting for Speed First turn system"""
	var current_acting_unit = speed_system.get_current_acting_unit()
	var all_units = _find_all_units()
	
	# Clear all current acting highlights
	for unit in all_units:
		apply_current_acting_highlight(unit, false)
	
	# Highlight the current acting unit
	if current_acting_unit:
		apply_current_acting_highlight(current_acting_unit, true)
		print("UnitVisualManager: Highlighted current acting unit: " + current_acting_unit.get_display_name())

func _on_turn_started(player: Player) -> void:
	"""Handle turn start - refresh unit visuals"""
	update_all_unit_visuals()
	
	# Special handling for Speed First system
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is SpeedFirstTurnSystem:
			_update_speed_first_highlights(turn_system as SpeedFirstTurnSystem)

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end - refresh unit visuals"""
	update_all_unit_visuals()
	
	# Special handling for Speed First system
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is SpeedFirstTurnSystem:
			_update_speed_first_highlights(turn_system as SpeedFirstTurnSystem)

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion from GameEvents"""
	# Update visuals after a short delay to ensure turn system has processed the action
	await get_tree().create_timer(0.1).timeout
	update_all_unit_visuals()

func _on_turn_system_unit_action(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion from turn system"""
	update_all_unit_visuals()

# Public interface for manual updates
func refresh_unit_visuals() -> void:
	"""Manually refresh all unit visuals - useful for testing"""
	update_all_unit_visuals()
	print("Unit visuals refreshed")