extends Node

class_name TurnSystemBase

# Abstract base class for all turn systems
# Defines common interface and signals for turn management

# Turn system signals
signal turn_started(player: Player)
signal turn_ended(player: Player)
signal turn_system_changed(old_system: TurnSystemBase, new_system: TurnSystemBase)
signal unit_action_completed(unit: Unit, action_type: String)
signal all_units_acted()

# Turn system types
enum TurnSystemType {
	TRADITIONAL,    # Player-based turns (all units per player)
	INITIATIVE,     # Unit-based turns (speed/initiative order)
	SIMULTANEOUS,   # All players act simultaneously
	REAL_TIME       # Real-time with action points
}

# Abstract properties
var system_type: TurnSystemType
var system_name: String = "Base Turn System"
var is_active: bool = false

# Registered units and players
var registered_units: Array[Unit] = []
var registered_players: Array[Player] = []

# Current turn state
var current_turn: int = 0
var is_turn_in_progress: bool = false

func _init() -> void:
	name = "TurnSystemBase"

# Abstract methods - must be implemented by derived classes
func start_turn_system() -> void:
	"""Initialize and start the turn system"""
	push_error("start_turn_system() must be implemented by derived class")

func end_turn_system() -> void:
	"""Clean up and end the turn system"""
	push_error("end_turn_system() must be implemented by derived class")

func advance_turn() -> void:
	"""Advance to the next turn"""
	push_error("advance_turn() must be implemented by derived class")

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	push_error("can_unit_act() must be implemented by derived class")
	return false

func get_current_active_player() -> Player:
	"""Get the currently active player"""
	push_error("get_current_active_player() must be implemented by derived class")
	return null

func get_turn_order() -> Array:
	"""Get the current turn order (units or players)"""
	push_error("get_turn_order() must be implemented by derived class")
	return []

# Virtual methods - can be overridden by derived classes
func reset_turn_system() -> void:
	"""Reset the turn system to initial state (for testing purposes)"""
	# Default implementation - derived classes should override
	current_turn = 1
	is_turn_in_progress = false
	print("TurnSystemBase: Basic reset completed")

# Common implementation methods
func register_unit(unit: Unit) -> void:
	"""Register a unit with the turn system"""
	if unit not in registered_units:
		registered_units.append(unit)
		
		# Connect to unit signals
		if unit.has_signal("unit_action_completed"):
			unit.unit_action_completed.connect(_on_unit_action_completed)
		
		print("Turn System: Registered unit " + unit.get_display_name())

func unregister_unit(unit: Unit) -> void:
	"""Unregister a unit from the turn system"""
	if unit in registered_units:
		registered_units.erase(unit)
		
		# Disconnect from unit signals
		if unit.has_signal("unit_action_completed") and unit.unit_action_completed.is_connected(_on_unit_action_completed):
			unit.unit_action_completed.disconnect(_on_unit_action_completed)
		
		print("Turn System: Unregistered unit " + unit.get_display_name())

func register_player(player: Player) -> void:
	"""Register a player with the turn system"""
	if player not in registered_players:
		registered_players.append(player)
		
		# Register all player's units
		for unit in player.owned_units:
			register_unit(unit)
		
		print("Turn System: Registered player " + player.get_display_name())

func unregister_player(player: Player) -> void:
	"""Unregister a player from the turn system"""
	if player in registered_players:
		registered_players.erase(player)
		
		# Unregister all player's units
		for unit in player.owned_units:
			unregister_unit(unit)
		
		print("Turn System: Unregistered player " + player.get_display_name())

func validate_turn_action(unit: Unit, action_type: String) -> bool:
	"""Validate if a unit can perform an action"""
	if not unit or not is_active:
		return false
	
	if unit not in registered_units:
		return false
	
	return can_unit_act(unit)

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	unit_action_completed.emit(unit, action_type)
	
	# Check if turn should advance
	_check_turn_completion()

func _check_turn_completion() -> void:
	"""Check if the current turn should end (override in derived classes)"""
	pass

# Utility methods
func get_units_for_player(player: Player) -> Array[Unit]:
	"""Get all registered units for a specific player"""
	var player_units: Array[Unit] = []
	for unit in registered_units:
		if unit.get_owner_player() == player:
			player_units.append(unit)
	return player_units

func get_active_units() -> Array[Unit]:
	"""Get all units that can currently act"""
	var active_units: Array[Unit] = []
	for unit in registered_units:
		if can_unit_act(unit):
			active_units.append(unit)
	return active_units

func reset_all_unit_actions() -> void:
	"""Reset action states for all units"""
	for unit in registered_units:
		if unit.has_method("reset_turn_actions"):
			unit.reset_turn_actions()

# Debug and info methods
func get_turn_system_info() -> Dictionary:
	"""Get information about the current turn system state"""
	return {
		"system_type": TurnSystemType.keys()[system_type],
		"system_name": system_name,
		"is_active": is_active,
		"current_turn": current_turn,
		"is_turn_in_progress": is_turn_in_progress,
		"registered_units": registered_units.size(),
		"registered_players": registered_players.size(),
		"active_units": get_active_units().size()
	}

func _to_string() -> String:
	"""String representation for debugging"""
	return system_name + " (Turn " + str(current_turn) + ")"
