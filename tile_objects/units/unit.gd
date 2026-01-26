extends TileObject

class_name Unit

# Unit stats component integration
@export var stats_resource: UnitStatsResource
@onready var unit_stats: UnitStats = $UnitStats

@export var has_turn: bool = false

# Player ownership
var owner_player: Player = null
var has_acted_this_turn: bool = false

# Signals
signal unit_died(unit: Unit)
signal unit_action_completed(unit: Unit, action_type: String)
signal owner_changed(unit: Unit, old_owner: Player, new_owner: Player)

# Inspector testing properties (for runtime testing)
@export_group("Runtime Testing")
@export var test_damage_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			take_damage(value)
			test_damage_amount = 0  # Reset after use

@export var test_heal_amount: int = 10:
	set(value):
		if value > 0 and is_inside_tree():
			heal(value)
			test_heal_amount = 0  # Reset after use

@export var current_health_display: int:
	get:
		return current_health
	set(value):
		if unit_stats and value >= 0:
			unit_stats.set_stat("health", min(value, max_health))

# Visual management
var visual_manager: UnitVisualManager
var player_assignment: PlayerMaterials.PlayerTeam = PlayerMaterials.PlayerTeam.NEUTRAL

# Health management
var current_health: int:
	get:
		if unit_stats:
			return unit_stats.get_stat("health")
		return 0

var max_health: int:
	get:
		if unit_stats:
			return unit_stats.get_base_stat("health")
		return 0

# Visual feedback
var _mesh_instance: MeshInstance3D
var _original_material: Material

func _ready() -> void:
	_setup_stats_component()
	_setup_visuals()
	_connect_events()
	_setup_visual_management()

func _setup_visual_management() -> void:
	"""Set up visual management for this unit"""
	# Find or create visual manager
	visual_manager = _find_visual_manager()
	if not visual_manager:
		push_warning("No UnitVisualManager found in scene")
		return
	
	# Check if we have an owner player (new system)
	if owner_player:
		visual_manager.setup_unit_visuals_for_player(self, owner_player)
	else:
		# Fallback to old system - determine player assignment from scene tree
		player_assignment = _determine_player_from_scene_tree()
		visual_manager.setup_unit_visuals(self, player_assignment)

func _find_visual_manager() -> UnitVisualManager:
	"""Find UnitVisualManager in the scene tree"""
	# Look for it in the scene root or map
	var scene_root = get_tree().current_scene
	if scene_root:
		var manager = scene_root.find_child("UnitVisualManager", true, false)
		if manager:
			return manager
	
	# If not found, create one
	var manager = UnitVisualManager.new()
	manager.name = "UnitVisualManager"
	scene_root.add_child(manager)
	return manager

func _determine_player_from_scene_tree() -> PlayerMaterials.PlayerTeam:
	"""Determine player assignment based on parent node names"""
	var parent = get_parent()
	while parent:
		if parent.name.to_lower().contains("player1"):
			return PlayerMaterials.PlayerTeam.PLAYER_1
		elif parent.name.to_lower().contains("player2"):
			return PlayerMaterials.PlayerTeam.PLAYER_2
		parent = parent.get_parent()
	
	return PlayerMaterials.PlayerTeam.NEUTRAL

func _setup_stats_component() -> void:
	"""Initialize the UnitStats component"""
	# Create UnitStats component if it doesn't exist
	if not unit_stats:
		unit_stats = UnitStats.new()
		unit_stats.name = "UnitStats"
		
		# Set up stats resource BEFORE adding to tree
		if stats_resource:
			unit_stats.stats_resource = stats_resource
		else:
			push_error("Unit requires a UnitStatsResource! Please assign one in the inspector.")
			return
		
		# Now add to tree, _ready() will work properly
		add_child(unit_stats)
	
	# Connect to stats events
	if unit_stats:
		unit_stats.health_changed.connect(_on_health_changed)
		unit_stats.stat_changed.connect(_on_stat_changed)

func _setup_visuals() -> void:
	"""Initialize visual components"""
	# Only set up visuals if MeshInstance3D exists (for testing compatibility)
	if has_node("MeshInstance3D"):
		_mesh_instance = get_node("MeshInstance3D")
		if _mesh_instance and _mesh_instance.mesh and _mesh_instance.mesh.material:
			_original_material = _mesh_instance.mesh.material

func _connect_events() -> void:
	"""Connect to game events"""
	# Only connect if GameEvents exists (for testing compatibility)
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)

# Stat access methods (preferred interface)
func get_stat(stat_name: String) -> int:
	"""Get current stat value"""
	if unit_stats:
		return unit_stats.get_stat(stat_name)
	return 0

func get_base_stat(stat_name: String) -> int:
	"""Get base stat value (without modifiers)"""
	if unit_stats:
		return unit_stats.get_base_stat(stat_name)
	return 0

func modify_stat(stat_name: String, amount: int, is_permanent: bool = false) -> void:
	"""Modify a stat by amount"""
	if unit_stats:
		unit_stats.modify_stat(stat_name, amount, is_permanent)

func set_stat(stat_name: String, value: int, is_permanent: bool = false) -> void:
	"""Set a stat to specific value"""
	if unit_stats:
		unit_stats.set_stat(stat_name, value, is_permanent)

func add_stat_modifier(stat_name: String, amount: int, duration: int = -1) -> int:
	"""Add temporary stat modifier"""
	if unit_stats:
		return unit_stats.add_stat_modifier(stat_name, amount, duration)
	return -1

func remove_stat_modifier(modifier_id: int) -> bool:
	"""Remove specific stat modifier"""
	if unit_stats:
		return unit_stats.remove_stat_modifier(modifier_id)
	return false

# Health management
func take_damage(amount: int) -> void:
	"""Apply damage to the unit"""
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var new_hp = max(0, current_hp - amount)
		unit_stats.set_stat("health", new_hp)
		
		if new_hp <= 0:
			_on_unit_died()

func heal(amount: int) -> void:
	"""Heal the unit"""
	if unit_stats:
		var current_hp = unit_stats.get_stat("health")
		var max_hp = unit_stats.get_base_stat("health")
		var new_hp = min(max_hp, current_hp + amount)
		unit_stats.set_stat("health", new_hp)

func is_alive() -> bool:
	"""Check if unit is alive"""
	return current_health > 0

func is_at_full_health() -> bool:
	"""Check if unit is at full health"""
	return current_health >= max_health

# Unit type and properties
func get_unit_type() -> UnitType:
	"""Get the unit's type"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.unit_type
	return null

func get_display_name() -> String:
	"""Get the unit's display name"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.get_display_name()
	return "Unknown Unit"

func is_ranged_unit() -> bool:
	"""Check if this is a ranged unit"""
	if unit_stats and unit_stats.stats_resource:
		return unit_stats.stats_resource.is_ranged_unit()
	return false

# Player ownership methods
func set_owner_player(player: Player) -> void:
	"""Set the player who owns this unit"""
	var old_owner = owner_player
	owner_player = player
	
	# Update visual identification
	if player:
		player_assignment = _get_player_assignment_from_player(player)
		# Update visuals immediately if visual manager exists
		if visual_manager:
			visual_manager.setup_unit_visuals_for_player(self, player)
	else:
		player_assignment = PlayerMaterials.PlayerTeam.NEUTRAL
		# Update visuals to neutral
		if visual_manager:
			visual_manager.setup_unit_visuals(self, player_assignment)
	
	owner_changed.emit(self, old_owner, player)

func get_owner_player() -> Player:
	"""Get the player who owns this unit"""
	return owner_player

func _get_player_assignment_from_player(player: Player) -> PlayerMaterials.PlayerTeam:
	"""Convert Player to PlayerMaterials.PlayerTeam enum"""
	if not player:
		return PlayerMaterials.PlayerTeam.NEUTRAL
	
	match player.player_id:
		0:
			return PlayerMaterials.PlayerTeam.PLAYER_1
		1:
			return PlayerMaterials.PlayerTeam.PLAYER_2
		_:
			return PlayerMaterials.PlayerTeam.NEUTRAL

# Turn action management
func reset_turn_actions() -> void:
	"""Reset unit's actions for a new turn"""
	has_acted_this_turn = false

func mark_action_completed(action_type: String) -> void:
	"""Mark that this unit has completed an action"""
	has_acted_this_turn = true
	unit_action_completed.emit(self, action_type)

func can_act() -> bool:
	"""Check if unit can still act this turn"""
	return not has_acted_this_turn and is_alive()

# Validation methods
func can_be_selected_by_player(player: Player) -> bool:
	"""Check if a specific player can select this unit"""
	return owner_player == player

func can_be_controlled_by_player(player: Player) -> bool:
	"""Check if a specific player can control this unit"""
	return owner_player == player and can_act()

# Movement methods
func get_movement_range() -> int:
	"""Get unit's movement range"""
	return get_stat("movement")

func can_move_to(position: Vector3) -> bool:
	"""Check if unit can move to position (override in derived classes)"""
	return true

# Turn management
func process_turn_start() -> void:
	"""Called when unit's turn starts"""
	if unit_stats:
		unit_stats.process_modifier_durations()

func process_turn_end() -> void:
	"""Called when unit's turn ends"""
	# Reset action points or other per-turn resources
	pass
func _on_health_changed(old_health: int, new_health: int) -> void:
	"""Handle health changes"""
	# Notify visual manager directly
	if visual_manager:
		visual_manager._on_unit_health_changed(self, old_health, new_health)
	
	# Update health bar UI, check for death, etc.
	if new_health <= 0 and old_health > 0:
		_on_unit_died()

func _on_stat_changed(stat_name: String, old_value: int, new_value: int) -> void:
	"""Handle stat changes"""
	# Update UI, trigger effects, etc.
	pass

func _on_unit_died() -> void:
	"""Handle unit death"""
	unit_died.emit(self)
	GameEvents.unit_eliminated.emit(self, null)  # null = no killer specified

# Visual feedback (updated to use visual manager)
func _on_unit_selected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, true)

func _on_unit_deselected(unit: Unit) -> void:
	if unit == self and visual_manager:
		visual_manager.apply_selection_visual(self, false)

func _apply_selection_visual(selected: bool) -> void:
	"""Legacy method - now delegates to visual manager"""
	if visual_manager:
		visual_manager.apply_selection_visual(self, selected)

# Debug helpers
func _to_string() -> String:
	if unit_stats:
		return str(unit_stats)
	return "Unit: No stats component"

func get_debug_info() -> Dictionary:
	"""Get debug information about the unit"""
	var info = {
		"name": get_display_name(),
		"alive": is_alive(),
		"has_turn": has_turn,
		"position": position,
		"stats_component": unit_stats != null
	}
	
	if unit_stats:
		info.merge(unit_stats.get_debug_info())
	
	return info
