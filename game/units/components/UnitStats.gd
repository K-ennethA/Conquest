extends Node

class_name UnitStats

# Component for managing unit statistics and stat modifications
# Integrates UnitStatsResource with the Unit system

@export var stats_resource: UnitStatsResource:
	set(value):
		stats_resource = value
		if stats_resource and is_inside_tree():
			_initialize_current_stats()
@export var allow_runtime_modifications: bool = true

# Current stats (can be modified during gameplay)
var current_health: int
var current_attack: int
var current_defense: int
var current_speed: int
var current_movement: int
var current_actions: int
var current_range: int

# Temporary stat modifiers (buffs/debuffs)
var _stat_modifiers: Dictionary = {}
var _modifier_id_counter: int = 0

# Signals for stat changes
signal stat_changed(stat_name: String, old_value: int, new_value: int)
signal health_changed(old_health: int, new_health: int)
signal stat_modifier_added(modifier_id: int, stat_name: String, amount: int)
signal stat_modifier_removed(modifier_id: int, stat_name: String)
signal stats_reset_to_base()

func _ready() -> void:
	if not stats_resource:
		push_error("UnitStats component requires a UnitStatsResource!")
		return
	
	_initialize_current_stats()
	
	# Connect to GameEvents for global stat tracking
	if GameEvents:
		stat_changed.connect(_on_stat_changed_global)

func _initialize_current_stats() -> void:
	"""Initialize current stats from the base resource"""
	current_health = stats_resource.base_health
	current_attack = stats_resource.base_attack
	current_defense = stats_resource.base_defense
	current_speed = stats_resource.base_speed
	current_movement = stats_resource.base_movement
	current_actions = stats_resource.base_actions
	current_range = stats_resource.attack_range

# Stat getter methods
func get_stat(stat_name: String) -> int:
	"""Get current value of a stat including all modifiers"""
	match stat_name.to_lower():
		"health", "hp":
			return current_health
		"attack", "atk":
			return current_attack
		"defense", "def":
			return current_defense
		"speed", "spd":
			return current_speed
		"movement", "move":
			return current_movement
		"actions", "act":
			return current_actions
		"range":
			return current_range
		_:
			push_warning("Unknown stat requested: " + stat_name)
			return 0

func get_base_stat(stat_name: String) -> int:
	"""Get base stat value from resource (ignoring modifiers)"""
	if not stats_resource:
		return 0
	return stats_resource.get_stat(stat_name)

func get_all_stats() -> Dictionary:
	"""Get all current stats as a dictionary"""
	return {
		"health": current_health,
		"attack": current_attack,
		"defense": current_defense,
		"speed": current_speed,
		"movement": current_movement,
		"actions": current_actions,
		"range": current_range
	}

func get_all_base_stats() -> Dictionary:
	"""Get all base stats from resource"""
	if not stats_resource:
		return {}
	return stats_resource.get_all_stats()

# Stat modification methods
func modify_stat(stat_name: String, amount: int, is_permanent: bool = false) -> void:
	"""Modify a stat by a specific amount"""
	if not allow_runtime_modifications and not is_permanent:
		push_warning("Runtime stat modifications are disabled for this unit")
		return
	
	var old_value = get_stat(stat_name)
	var new_value = old_value + amount
	
	# Apply bounds checking
	new_value = _clamp_stat_to_bounds(stat_name, new_value)
	
	if new_value == old_value:
		return  # No change needed
	
	_set_current_stat(stat_name, new_value)
	
	if is_permanent:
		_modify_base_stat(stat_name, amount)
	
	stat_changed.emit(stat_name, old_value, new_value)
	
	# Special handling for health changes
	if stat_name.to_lower() in ["health", "hp"]:
		health_changed.emit(old_value, new_value)

func set_stat(stat_name: String, value: int, is_permanent: bool = false) -> void:
	"""Set a stat to a specific value"""
	var old_value = get_stat(stat_name)
	var new_value = _clamp_stat_to_bounds(stat_name, value)
	
	if new_value == old_value:
		return
	
	_set_current_stat(stat_name, new_value)
	
	if is_permanent:
		_set_base_stat(stat_name, new_value)
	
	stat_changed.emit(stat_name, old_value, new_value)
	
	if stat_name.to_lower() in ["health", "hp"]:
		health_changed.emit(old_value, new_value)

# Temporary modifier system
func add_stat_modifier(stat_name: String, amount: int, duration: int = -1) -> int:
	"""Add a temporary stat modifier. Returns modifier ID for removal"""
	var modifier_id = _modifier_id_counter
	_modifier_id_counter += 1
	
	var modifier = {
		"stat": stat_name.to_lower(),
		"amount": amount,
		"duration": duration,
		"turns_remaining": duration
	}
	
	_stat_modifiers[modifier_id] = modifier
	
	# Apply the modifier immediately
	var old_value = get_stat(stat_name)
	var new_value = _clamp_stat_to_bounds(stat_name, old_value + amount)
	_set_current_stat(stat_name, new_value)
	
	stat_modifier_added.emit(modifier_id, stat_name, amount)
	stat_changed.emit(stat_name, old_value, new_value)
	
	return modifier_id

func remove_stat_modifier(modifier_id: int) -> bool:
	"""Remove a specific stat modifier by ID"""
	if not _stat_modifiers.has(modifier_id):
		return false
	
	var modifier = _stat_modifiers[modifier_id]
	var stat_name = modifier.stat
	var amount = modifier.amount
	
	_stat_modifiers.erase(modifier_id)
	
	# Recalculate stat without this modifier
	_recalculate_stat(stat_name)
	
	stat_modifier_removed.emit(modifier_id, stat_name)
	
	return true

func process_modifier_durations() -> void:
	"""Process modifier durations (call each turn)"""
	var expired_modifiers = []
	
	for modifier_id in _stat_modifiers:
		var modifier = _stat_modifiers[modifier_id]
		if modifier.duration > 0:
			modifier.turns_remaining -= 1
			if modifier.turns_remaining <= 0:
				expired_modifiers.append(modifier_id)
	
	# Remove expired modifiers
	for modifier_id in expired_modifiers:
		remove_stat_modifier(modifier_id)

func clear_all_modifiers() -> void:
	"""Remove all temporary stat modifiers"""
	var modifier_ids = _stat_modifiers.keys()
	for modifier_id in modifier_ids:
		remove_stat_modifier(modifier_id)

# Utility methods
func reset_to_base_stats() -> void:
	"""Reset all current stats to base values and clear modifiers"""
	clear_all_modifiers()
	_initialize_current_stats()
	stats_reset_to_base.emit()

func is_stat_modified(stat_name: String) -> bool:
	"""Check if a stat has any active modifiers"""
	var stat_lower = stat_name.to_lower()
	for modifier in _stat_modifiers.values():
		if modifier.stat == stat_lower:
			return true
	return false

func get_stat_modifiers(stat_name: String) -> Array:
	"""Get all active modifiers for a specific stat"""
	var stat_lower = stat_name.to_lower()
	var modifiers = []
	for modifier_id in _stat_modifiers:
		var modifier = _stat_modifiers[modifier_id]
		if modifier.stat == stat_lower:
			modifiers.append({
				"id": modifier_id,
				"amount": modifier.amount,
				"duration": modifier.duration,
				"turns_remaining": modifier.turns_remaining
			})
	return modifiers

func validate_stats() -> bool:
	"""Validate that all current stats are within acceptable bounds"""
	if not stats_resource:
		return false
	
	var stats = get_all_stats()
	for stat_name in stats:
		var value = stats[stat_name]
		if not _is_stat_value_valid(stat_name, value):
			return false
	
	return true

# Private helper methods
func _set_current_stat(stat_name: String, value: int) -> void:
	"""Set current stat value directly"""
	match stat_name.to_lower():
		"health", "hp":
			current_health = value
		"attack", "atk":
			current_attack = value
		"defense", "def":
			current_defense = value
		"speed", "spd":
			current_speed = value
		"movement", "move":
			current_movement = value
		"actions", "act":
			current_actions = value
		"range":
			current_range = value

func _modify_base_stat(stat_name: String, amount: int) -> void:
	"""Modify base stat in resource (permanent change)"""
	if not stats_resource:
		return
	
	var current_base = stats_resource.get_stat(stat_name)
	var new_base = _clamp_stat_to_bounds(stat_name, current_base + amount)
	_set_base_stat(stat_name, new_base)

func _set_base_stat(stat_name: String, value: int) -> void:
	"""Set base stat in resource directly"""
	if not stats_resource:
		return
	
	match stat_name.to_lower():
		"health", "hp":
			stats_resource.base_health = value
		"attack", "atk":
			stats_resource.base_attack = value
		"defense", "def":
			stats_resource.base_defense = value
		"speed", "spd":
			stats_resource.base_speed = value
		"movement", "move":
			stats_resource.base_movement = value
		"actions", "act":
			stats_resource.base_actions = value
		"range":
			stats_resource.attack_range = value

func _recalculate_stat(stat_name: String) -> void:
	"""Recalculate a stat from base value plus all active modifiers"""
	var base_value = get_base_stat(stat_name)
	var total_modifier = 0
	
	var stat_lower = stat_name.to_lower()
	for modifier in _stat_modifiers.values():
		if modifier.stat == stat_lower:
			total_modifier += modifier.amount
	
	var old_value = get_stat(stat_name)
	var new_value = _clamp_stat_to_bounds(stat_name, base_value + total_modifier)
	
	_set_current_stat(stat_name, new_value)
	
	if old_value != new_value:
		stat_changed.emit(stat_name, old_value, new_value)

func _clamp_stat_to_bounds(stat_name: String, value: int) -> int:
	"""Clamp stat value to valid bounds"""
	if not stats_resource:
		return value
	
	match stat_name.to_lower():
		"health", "hp":
			return clamp(value, 0, UnitStatsResource.MAX_HEALTH)
		"attack", "atk":
			return clamp(value, UnitStatsResource.MIN_ATTACK, UnitStatsResource.MAX_ATTACK)
		"defense", "def":
			return clamp(value, UnitStatsResource.MIN_DEFENSE, UnitStatsResource.MAX_DEFENSE)
		"speed", "spd":
			return clamp(value, UnitStatsResource.MIN_SPEED, UnitStatsResource.MAX_SPEED)
		"movement", "move":
			return clamp(value, UnitStatsResource.MIN_MOVEMENT, UnitStatsResource.MAX_MOVEMENT)
		"actions", "act":
			return clamp(value, UnitStatsResource.MIN_ACTIONS, UnitStatsResource.MAX_ACTIONS)
		"range":
			return clamp(value, UnitStatsResource.MIN_RANGE, UnitStatsResource.MAX_RANGE)
		_:
			return value

func _is_stat_value_valid(stat_name: String, value: int) -> bool:
	"""Check if a stat value is within valid bounds"""
	return value == _clamp_stat_to_bounds(stat_name, value)

func _on_stat_changed_global(stat_name: String, old_value: int, new_value: int) -> void:
	"""Handle global stat change events"""
	# This can be used for global stat tracking, achievements, etc.
	pass

# Debug and development helpers
func _to_string() -> String:
	if not stats_resource:
		return "UnitStats: No resource loaded"
	
	return "UnitStats[%s]: HP:%d/%d ATK:%d DEF:%d SPD:%d MOV:%d ACT:%d RNG:%d" % [
		stats_resource.get_display_name(),
		current_health, stats_resource.base_health,
		current_attack, current_defense, current_speed,
		current_movement, current_actions, current_range
	]

func get_debug_info() -> Dictionary:
	"""Get detailed debug information about the component"""
	return {
		"resource_loaded": stats_resource != null,
		"resource_name": stats_resource.get_display_name() if stats_resource else "None",
		"current_stats": get_all_stats(),
		"base_stats": get_all_base_stats(),
		"active_modifiers": _stat_modifiers.size(),
		"modifiers_detail": _stat_modifiers,
		"stats_valid": validate_stats()
	}