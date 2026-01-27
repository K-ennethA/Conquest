extends Node

# Battle Effects Manager Singleton
# Manages temporary stat modifications and battle-scoped effects
# Works with ANY turn system (Traditional, Speed-First, etc.)

signal speed_modifier_added(unit: Unit, modifier_name: String, speed_change: int)
signal speed_modifier_removed(unit: Unit, modifier_name: String)
signal unit_turn_refreshed(unit: Unit)

# Battle effect tracking
var speed_modifiers: Dictionary = {}  # Unit -> Array of speed modifiers
var turn_refresh_flags: Dictionary = {} # Unit -> bool (for turn refresh tracking)

# Battle effect structure
class BattleEffect:
	var name: String
	var effect_type: String  # "speed", "health", "damage", etc.
	var value_change: int
	var duration_rounds: int  # -1 for "permanent" (battle-scoped), >0 for temporary
	var source: String  # What caused this effect
	var round_applied: int  # When this effect was applied
	
	func _init(effect_name: String, type: String, change: int, rounds: int = -1, effect_source: String = "", applied_round: int = 1):
		name = effect_name
		effect_type = type
		value_change = change
		duration_rounds = rounds
		source = effect_source
		round_applied = applied_round

func _ready() -> void:
	name = "BattleEffectsManager"
	print("BattleEffectsManager initialized")

# Speed modification API
func apply_speed_buff(unit: Unit, buff_name: String, speed_increase: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed buff to a unit"""
	_add_speed_modifier(unit, buff_name, speed_increase, duration_rounds, source)

func apply_speed_debuff(unit: Unit, debuff_name: String, speed_decrease: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Apply a speed debuff to a unit"""
	_add_speed_modifier(unit, debuff_name, -speed_decrease, duration_rounds, source)

func remove_speed_effect(unit: Unit, effect_name: String) -> bool:
	"""Remove a specific speed effect from a unit"""
	return _remove_speed_modifier(unit, effect_name)

func get_unit_current_speed(unit: Unit) -> int:
	"""Get unit's current speed including all battle-scoped modifiers
	
	IMPORTANT: This does NOT modify the unit's base stats resource.
	Battle modifiers are temporary and reset when the battle ends.
	"""
	var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
	var total_modifier = 0
	
	if speed_modifiers.has(unit):
		for modifier in speed_modifiers[unit]:
			total_modifier += modifier.value_change
	
	return max(1, base_speed + total_modifier)  # Minimum speed of 1

func get_unit_speed_modifiers(unit: Unit) -> Array:
	"""Get all speed modifiers for a unit"""
	if speed_modifiers.has(unit):
		return speed_modifiers[unit].duplicate()
	return []

func get_unit_speed_info(unit: Unit) -> Dictionary:
	"""Get detailed speed information for a unit"""
	var base_speed = unit.get_stat("speed") if unit.has_method("get_stat") else 0
	var current_speed = get_unit_current_speed(unit)
	var modifiers = get_unit_speed_modifiers(unit)
	
	var modifier_info: Array[Dictionary] = []
	for modifier in modifiers:
		modifier_info.append({
			"name": modifier.name,
			"change": modifier.value_change,
			"duration": modifier.duration_rounds,
			"source": modifier.source
		})
	
	return {
		"base_speed": base_speed,
		"current_speed": current_speed,
		"total_modifier": current_speed - base_speed,
		"modifiers": modifier_info
	}

# Turn refresh API (works with any turn system)
func refresh_unit_turn(unit: Unit) -> bool:
	"""Mark a unit as having their turn refreshed (for special abilities)"""
	if not unit:
		return false
	
	turn_refresh_flags[unit] = true
	unit_turn_refreshed.emit(unit)
	print("Unit " + unit.get_display_name() + " turn refreshed by battle effect")
	
	# Notify active turn system
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system.has_method("handle_unit_turn_refresh"):
			turn_system.handle_unit_turn_refresh(unit)
	
	return true

func is_unit_turn_refreshed(unit: Unit) -> bool:
	"""Check if a unit has had their turn refreshed"""
	return turn_refresh_flags.get(unit, false)

func clear_unit_turn_refresh(unit: Unit) -> void:
	"""Clear the turn refresh flag for a unit"""
	turn_refresh_flags.erase(unit)

# Round progression (called by turn systems)
func advance_round(new_round: int) -> void:
	"""Update all battle effects for a new round"""
	print("BattleEffectsManager: Advancing to round " + str(new_round))
	_update_effect_durations(new_round)
	_clear_turn_refresh_flags()

func _update_effect_durations(current_round: int) -> void:
	"""Update duration-based effects"""
	var units_to_clean: Array[Unit] = []
	
	for unit in speed_modifiers.keys():
		var modifiers = speed_modifiers[unit]
		
		# Update durations and remove expired modifiers
		for i in range(modifiers.size() - 1, -1, -1):
			var modifier = modifiers[i]
			if modifier.duration_rounds > 0:
				modifier.duration_rounds -= 1
				if modifier.duration_rounds <= 0:
					print("Speed modifier expired: " + modifier.name + " on " + unit.get_display_name())
					modifiers.remove_at(i)
					speed_modifier_removed.emit(unit, modifier.name)
		
		# Mark units with no modifiers for cleanup
		if modifiers.is_empty():
			units_to_clean.append(unit)
	
	# Clean up units with no modifiers
	for unit in units_to_clean:
		speed_modifiers.erase(unit)

func _clear_turn_refresh_flags() -> void:
	"""Clear all turn refresh flags at the start of a new round"""
	turn_refresh_flags.clear()

# Battle lifecycle management
func start_battle() -> void:
	"""Initialize battle effects for a new battle"""
	reset_battle_state()
	print("BattleEffectsManager: Battle started - ready for effects")

func end_battle() -> void:
	"""Clean up all battle effects when battle ends"""
	_clear_all_effects()
	print("BattleEffectsManager: Battle ended - all effects cleared")

func reset_battle_state() -> void:
	"""Reset all battle-specific state"""
	_clear_all_effects()
	turn_refresh_flags.clear()
	print("BattleEffectsManager: Battle state reset")

func _clear_all_effects() -> void:
	"""Clear all battle effects"""
	var units_affected = speed_modifiers.keys()
	speed_modifiers.clear()
	
	if units_affected.size() > 0:
		print("Cleared battle effects from " + str(units_affected.size()) + " units:")
		for unit in units_affected:
			print("  - " + unit.get_display_name() + " effects cleared")

# Internal speed modifier management
func _add_speed_modifier(unit: Unit, modifier_name: String, speed_change: int, duration_rounds: int = -1, source: String = "") -> void:
	"""Internal method to add speed modifier"""
	if not speed_modifiers.has(unit):
		speed_modifiers[unit] = []
	
	var current_round = 1
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		current_round = turn_system.current_turn
	
	var modifier = BattleEffect.new(modifier_name, "speed", speed_change, duration_rounds, source, current_round)
	speed_modifiers[unit].append(modifier)
	
	print("Added speed modifier to " + unit.get_display_name() + ": " + modifier_name + " (" + str(speed_change) + " speed)")
	speed_modifier_added.emit(unit, modifier_name, speed_change)

func _remove_speed_modifier(unit: Unit, modifier_name: String) -> bool:
	"""Internal method to remove speed modifier"""
	if not speed_modifiers.has(unit):
		return false
	
	var modifiers = speed_modifiers[unit]
	for i in range(modifiers.size() - 1, -1, -1):
		if modifiers[i].name == modifier_name:
			print("Removed speed modifier from " + unit.get_display_name() + ": " + modifier_name)
			modifiers.remove_at(i)
			speed_modifier_removed.emit(unit, modifier_name)
			
			# Clean up empty arrays
			if modifiers.is_empty():
				speed_modifiers.erase(unit)
			
			return true
	
	return false

# Debug and utility
func get_all_active_effects() -> Dictionary:
	"""Get all active battle effects for debugging"""
	var effects = {}
	
	for unit in speed_modifiers.keys():
		var unit_effects = []
		for modifier in speed_modifiers[unit]:
			unit_effects.append({
				"name": modifier.name,
				"type": modifier.effect_type,
				"change": modifier.value_change,
				"duration": modifier.duration_rounds,
				"source": modifier.source
			})
		effects[unit.get_display_name()] = unit_effects
	
	return effects

func print_active_effects() -> void:
	"""Print all active effects for debugging"""
	print("=== Active Battle Effects ===")
	var effects = get_all_active_effects()
	
	if effects.is_empty():
		print("No active battle effects")
		return
	
	for unit_name in effects.keys():
		print(unit_name + ":")
		for effect in effects[unit_name]:
			var duration_str = str(effect.duration) if effect.duration > 0 else "battle"
			print("  - " + effect.name + ": " + str(effect.change) + " " + effect.type + " (" + duration_str + " rounds)")