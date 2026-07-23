extends Node

class_name UnitVisualManager

# Manages visual appearance of units including materials, health bars, and type indicators

@export var player_materials: PlayerMaterials

var _health_bar_scene: PackedScene
var _unit_health_bars: Dictionary = {}  # Unit -> HealthBar

# Shared "spent turn" GREYSCALE wash (Fire Emblem style drained-of-colour). One
# material is reused across every unit and every frame -- never allocate per unit --
# and it is applied non-destructively via each MeshInstance3D's `material_overlay`,
# which composites OVER the model's own materials without replacing them, so clearing
# it (`material_overlay = null`) restores the original look exactly. It is a STRONG
# neutral-grey wash (albedo ~0.5,0.5,0.5 at ~0.6 alpha, unshaded, MIX blend): pulling
# every hue toward the same mid-grey is what reads as "desaturated / spent" rather
# than a faint darkening. It is paired with a slight per-mesh `transparency` fade
# (~0.15) so the spent unit also recedes a touch -- grey wash + slight fade together.
var _dim_material: StandardMaterial3D = null

# How much a spent unit fades via GeometryInstance3D.transparency (0 = opaque,
# 1 = invisible). Small on purpose: the greyscale wash carries the "spent" read;
# this just adds a subtle recede. Cleared back to 0.0 when the unit can act again.
const _DIM_TRANSPARENCY: float = 0.15

func _ready():
	if not player_materials:
		player_materials = PlayerMaterials.new()

	_ensure_dim_material()

	# Load health bar scene
	_health_bar_scene = preload("res://game/visuals/HealthBar.tscn")
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		# CRITICAL: this manager is created LAZILY by the first unit that spawns
		# (see unit.gd _find_visual_manager), which routinely happens AFTER the game
		# has already reached IN_PROGRESS and TurnSystemManager fired its one-shot
		# `turn_system_activated`. In that (normal) case we missed the signal, so
		# `_on_turn_system_activated` never runs and we NEVER connect to the live
		# system's turn_started / turn_ended / unit_action_completed -- meaning the
		# per-action "spent unit greys out" sweep is never triggered during play.
		# Wire up the already-active system right now to close that gap.
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

	# Connect to game events (null-safe: guard the signal exists and isn't already
	# wired so a minimal/headless scene never crashes on a missing bus).
	if GameEvents and GameEvents.has_signal("unit_action_completed") \
			and not GameEvents.unit_action_completed.is_connected(_on_unit_action_completed):
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
		var type_data = unit.unit_stats.stats_resource.unit_type
		if type_data is String:
			# Handle string type - convert to enum
			var type_string = type_data.to_upper()
			match type_string:
				"WARRIOR":
					unit_type = UnitType.Type.WARRIOR
				"ARCHER":
					unit_type = UnitType.Type.ARCHER
				"MAGE":
					unit_type = UnitType.Type.MAGE
				_:
					unit_type = UnitType.Type.WARRIOR
		elif typeof(type_data) == TYPE_OBJECT and type_data != null and type_data.has_method("get_type"):
			unit_type = type_data.get_type()
		else:
			# Handle string type - convert to enum
			var type_string = str(type_data).to_upper()
			match type_string:
				"WARRIOR":
					unit_type = UnitType.Type.WARRIOR
				"ARCHER":
					unit_type = UnitType.Type.ARCHER
				"MAGE":
					unit_type = UnitType.Type.MAGE
				_:
					unit_type = UnitType.Type.WARRIOR
	
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

	# A multi-cell unit (e.g. a 2x2 boss) then fills and centers over its whole
	# footprint. No-op for normal 1x1 units, so the per-type scales above stand.
	if unit and unit.has_method("apply_footprint_visual"):
		unit.apply_footprint_visual()

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
	
	# Position health bar higher to avoid clipping with taller units (Archers are 1.2x height).
	# A multi-cell unit is scaled up by its footprint, so lift the bar to clear the
	# bigger model and slide it over the center of the covered block. Both offsets
	# are zero for a normal 1x1 unit, leaving the classic (0, 1.8, 0) placement.
	var bar_offset: Vector3 = Vector3.ZERO
	var bar_height: float = 1.8
	if unit and unit.has_method("get_footprint_offset"):
		bar_offset = unit.get_footprint_offset()
	if unit and unit.has_method("get_footprint"):
		var fp: Vector2i = unit.get_footprint()
		bar_height += 1.2 * float(maxi(fp.x, fp.y) - 1)
	health_bar.position = Vector3(bar_offset.x, bar_height, bar_offset.z)
	
	# Normal scale for good readability
	health_bar.scale = Vector3(1.0, 1.0, 1.0)
	
	# Store reference
	_unit_health_bars[unit] = health_bar

	# Initialize health bar
	_update_health_bar(unit)

	# Bind the bar directly to the unit's HP signal so it self-refreshes on every
	# damage/heal -- not just on the action-completed sweep. This is the reliable
	# path; the older visual_manager indirection could silently miss updates.
	if health_bar.has_method("bind_unit"):
		health_bar.bind_unit(unit)

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

# --- Incoming-damage preview (overworld AoE) --------------------------------

func preview_damage(previews: Dictionary) -> void:
	"""Light up each affected unit's world-space bar with the HP a pending move
	would remove, so an AoE that hits several units shows the damage on ALL of
	their bars at once (not just the single enemy the forecast card covers).
	[param previews] maps Unit -> predicted damage (int). Bars not in the map are
	cleared, so moving the aim off a unit drops its band. Fully null-safe."""
	for unit in _unit_health_bars:
		var bar = _unit_health_bars[unit]
		if bar == null or not is_instance_valid(bar):
			continue
		if previews.has(unit):
			if bar.has_method("show_damage_preview"):
				bar.show_damage_preview(int(previews[unit]))
		elif bar.has_method("clear_damage_preview"):
			bar.clear_damage_preview()

func clear_damage_previews() -> void:
	"""Drop every bar's incoming-damage band (targeting ended / aim left a cell)."""
	for unit in _unit_health_bars:
		var bar = _unit_health_bars[unit]
		if bar != null and is_instance_valid(bar) and bar.has_method("clear_damage_preview"):
			bar.clear_damage_preview()

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
	
	# Apply appropriate visual state. Restore the base player material first (clears
	# any selection-glow material_override), then re-apply the dim overlay on top for
	# a spent unit -- the two use independent channels (override vs overlay).
	var player = _determine_unit_player(unit)
	_apply_player_material(unit, player)
	apply_acted_visual(unit, has_acted)

func apply_acted_visual(unit: Unit, has_acted: bool) -> void:
	"""Grey out a unit that has spent its turn (or clear it when it can act again).

	Non-destructive: we set a SHARED semi-transparent neutral-grey `material_overlay`
	on every MeshInstance3D under the unit's visible model, which composites over the
	model's own materials and washes their colour toward mid-grey, plus a slight
	per-mesh `transparency` fade. Clearing both (`material_overlay = null`,
	`transparency = 0.0`) restores the original look exactly -- no material is
	duplicated, copied, or overwritten, so this never fights UnitAnimator's transient
	hit/heal `material_override` flashes (a different channel) or the selection glow.
	Resolves the model the same way UnitAnimator does (CharacterModel glb root, else
	a placeholder MeshInstance3D, else the first mesh found)."""
	if not is_instance_valid(unit):
		return

	var model_root: Node = _get_model_root(unit)
	if model_root == null:
		return

	# Only living, spent units are greyed; dead units are being removed, and a unit
	# that can act again must read as fully active / full-colour.
	var should_dim: bool = has_acted and unit.is_alive()
	var overlay: Material = _ensure_dim_material() if should_dim else null
	var fade: float = _DIM_TRANSPARENCY if should_dim else 0.0

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model_root, meshes)
	for mesh in meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay
			mesh.transparency = fade

## Build (once) and return the shared greyscale wash material. Lazily created so it
## is always available even if apply_acted_visual runs before _ready.
func _ensure_dim_material() -> StandardMaterial3D:
	if _dim_material == null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		# Unshaded so the wash is a consistent flat grey regardless of scene
		# lighting -- every hue underneath gets pulled toward the same mid-grey,
		# reading as "desaturated / drained of colour / spent" everywhere.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		# Strong, slightly-dark neutral grey at ~0.72 alpha: heavy enough that the
		# model's own colours are unmistakably washed toward a drained mid-grey and
		# clearly read as "spent" at a glance, not merely tinted or faintly darkened.
		mat.albedo_color = Color(0.42, 0.42, 0.44, 0.72)
		_dim_material = mat
	return _dim_material

## Resolve a unit's visible model root, mirroring UnitAnimator._get_anim_root:
## prefer the "CharacterModel" glb root, else the placeholder "MeshInstance3D",
## else the first MeshInstance3D found anywhere below the unit. Null-safe.
func _get_model_root(unit: Unit) -> Node:
	if not is_instance_valid(unit):
		return null
	var model: Node = unit.get_node_or_null("CharacterModel")
	if model is Node3D:
		return model
	var direct: Node = unit.get_node_or_null("MeshInstance3D")
	if direct is Node3D:
		return direct
	return _find_first_mesh(unit)

## Gather every MeshInstance3D at or below [param node] into [param out].
func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, out)

## First MeshInstance3D anywhere below [param node], or null.
func _find_first_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var found: MeshInstance3D = _find_first_mesh(child)
		if found != null:
			return found
	return null

func _get_unit_type(unit: Unit) -> UnitType.Type:
	"""Get the unit type for a unit"""
	if unit.unit_stats and unit.unit_stats.stats_resource and unit.unit_stats.stats_resource.unit_type:
		var type_data = unit.unit_stats.stats_resource.unit_type
		if type_data is String:
			# Handle string type - convert to enum
			var type_string = type_data.to_upper()
			match type_string:
				"WARRIOR":
					return UnitType.Type.WARRIOR
				"ARCHER":
					return UnitType.Type.ARCHER
				"MAGE":
					return UnitType.Type.MAGE
				_:
					return UnitType.Type.WARRIOR
		elif typeof(type_data) == TYPE_OBJECT and type_data != null and type_data.has_method("get_type"):
			return type_data.get_type()
		else:
			# Handle string type - convert to enum
			var type_string = str(type_data).to_upper()
			match type_string:
				"WARRIOR":
					return UnitType.Type.WARRIOR
				"ARCHER":
					return UnitType.Type.ARCHER
				"MAGE":
					return UnitType.Type.MAGE
				_:
					return UnitType.Type.WARRIOR
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
	"""Refresh the acted/spent dim for every unit from its own turn state.

	Driven by the unit's authoritative `has_acted_this_turn` flag rather than a
	turn-system side list, so a unit un-dims automatically the moment its actions
	reset (reset_turn_actions() clears the flag, and this runs on turn start)."""
	# Find all units in the scene
	var all_units: Array[Unit] = _find_all_units()

	for unit in all_units:
		if not is_instance_valid(unit):
			continue
		var has_acted: bool = bool(unit.has_acted_this_turn)
		apply_acted_visual(unit, has_acted)

func _find_all_units() -> Array[Unit]:
	"""Find all units in the current scene"""
	var units: Array[Unit] = []
	# Null-safe with PLAIN ifs (not a ternary): during scene teardown / a mid-frame
	# turn-system deactivation the node can be detached (get_tree() == null) and the scene
	# can be null. A `tree.current_scene if tree != null else null` guard does NOT work --
	# GDScript evaluates `tree.current_scene` eagerly there and crashes on null. Guard each
	# step with its own if/return.
	if not is_inside_tree():
		return units
	var tree = get_tree()
	if tree == null:
		return units
	var scene_root = tree.current_scene
	if scene_root == null:
		return units

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
	"""Clean up visual elements when unit is removed (e.g. on death)."""
	if _unit_health_bars.has(unit):
		var health_bar = _unit_health_bars[unit]
		# The bar is a child of the unit, so freeing the unit frees it too; guard
		# so we don't queue_free a node that is already gone / already queued.
		if health_bar and is_instance_valid(health_bar) and not health_bar.is_queued_for_deletion():
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

func _on_turn_started(player: Player) -> void:
	"""Handle turn start - refresh unit visuals"""
	update_all_unit_visuals()

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end - refresh unit visuals"""
	update_all_unit_visuals()

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion from GameEvents"""
	# Dim the acting unit immediately for instant feedback; the unit has already
	# set has_acted_this_turn in mark_action_completed by the time this fires.
	if is_instance_valid(unit):
		apply_acted_visual(unit, bool(unit.has_acted_this_turn))
	# Then sweep all units after a short delay so any turn-system side effects settle.
	await get_tree().create_timer(0.1).timeout
	update_all_unit_visuals()

func _on_turn_system_unit_action(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion from turn system"""
	update_all_unit_visuals()

# Public interface for manual updates
func refresh_unit_visuals() -> void:
	"""Manually refresh all unit visuals - useful for testing"""
	update_all_unit_visuals()
