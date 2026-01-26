extends Resource

class_name Player

# Player representation for tactical combat game
# Manages player identity, team assignment, and unit ownership

@export var player_id: int = 0
@export var player_name: String = "Player"
@export var team_color: Color = Color.WHITE
@export var is_active: bool = false

# Player state tracking
enum PlayerState {
	WAITING,      # Waiting for turn
	ACTIVE,       # Currently taking turn
	ELIMINATED,   # No units remaining
	DISCONNECTED  # Player disconnected (future multiplayer)
}

var current_state: PlayerState = PlayerState.WAITING
var owned_units: Array[Unit] = []
var units_acted_this_turn: Array[Unit] = []

# Team materials for visual identification
var team_material: StandardMaterial3D
var selection_material: StandardMaterial3D

# Player statistics
var units_lost: int = 0
var damage_dealt: int = 0
var damage_taken: int = 0
var turns_played: int = 0

signal player_state_changed(player: Player, old_state: PlayerState, new_state: PlayerState)
signal unit_added(player: Player, unit: Unit)
signal unit_removed(player: Player, unit: Unit)
signal turn_completed(player: Player)

func _init(id: int = 0, name: String = "Player") -> void:
	player_id = id
	player_name = name
	_setup_team_materials()

func _setup_team_materials() -> void:
	"""Create team-specific materials for visual identification"""
	# Base team material
	team_material = StandardMaterial3D.new()
	team_material.albedo_color = team_color
	team_material.metallic = 0.3
	team_material.roughness = 0.7
	
	# Selection material (brighter version)
	selection_material = StandardMaterial3D.new()
	selection_material.albedo_color = team_color.lightened(0.3)
	selection_material.metallic = 0.2
	selection_material.roughness = 0.5
	selection_material.emission_enabled = true
	selection_material.emission = team_color * 0.2

# Player state management
func set_state(new_state: PlayerState) -> void:
	"""Change player state and emit signal"""
	if current_state == new_state:
		return
	
	var old_state = current_state
	current_state = new_state
	is_active = (new_state == PlayerState.ACTIVE)
	
	player_state_changed.emit(self, old_state, new_state)
	
	# Handle state-specific logic
	match new_state:
		PlayerState.ACTIVE:
			_start_turn()
		PlayerState.WAITING:
			_end_turn()
		PlayerState.ELIMINATED:
			_handle_elimination()

func _start_turn() -> void:
	"""Handle turn start logic"""
	turns_played += 1
	units_acted_this_turn.clear()
	
	# Reset unit action states
	for unit in owned_units:
		if unit and unit.has_method("reset_turn_actions"):
			unit.reset_turn_actions()

func _end_turn() -> void:
	"""Handle turn end logic"""
	turn_completed.emit(self)

func _handle_elimination() -> void:
	"""Handle player elimination"""
	print("Player " + player_name + " has been eliminated!")
	# Clear all unit ownership
	for unit in owned_units.duplicate():
		remove_unit(unit)

# Unit management
func add_unit(unit: Unit) -> void:
	"""Add a unit to this player's control"""
	if not unit or unit in owned_units:
		return
	
	owned_units.append(unit)
	unit.set_owner_player(self)
	
	# Don't apply team visuals here - let UnitVisualManager handle it
	# The UnitVisualManager will be notified through the unit_added signal
	
	unit_added.emit(self, unit)
	
	# Connect to unit signals
	if unit.has_signal("unit_died"):
		unit.unit_died.connect(_on_unit_died)

func remove_unit(unit: Unit) -> void:
	"""Remove a unit from this player's control"""
	if not unit or unit not in owned_units:
		return
	
	owned_units.erase(unit)
	units_acted_this_turn.erase(unit)
	
	if unit.has_method("set_owner_player"):
		unit.set_owner_player(null)
	
	unit_removed.emit(self, unit)
	
	# Disconnect from unit signals
	if unit.has_signal("unit_died") and unit.unit_died.is_connected(_on_unit_died):
		unit.unit_died.disconnect(_on_unit_died)
	
	# Check for elimination
	if owned_units.is_empty() and current_state != PlayerState.ELIMINATED:
		set_state(PlayerState.ELIMINATED)

func _apply_team_visuals(unit: Unit) -> void:
	"""Apply team colors and materials to a unit"""
	var mesh_instance = unit.get_node_or_null("MeshInstance3D")
	if mesh_instance:
		mesh_instance.material_override = team_material

func _on_unit_died(unit: Unit) -> void:
	"""Handle unit death"""
	units_lost += 1
	remove_unit(unit)

# Unit action tracking
func mark_unit_acted(unit: Unit) -> void:
	"""Mark a unit as having acted this turn"""
	if unit in owned_units and unit not in units_acted_this_turn:
		units_acted_this_turn.append(unit)

func has_unit_acted(unit: Unit) -> bool:
	"""Check if a unit has acted this turn"""
	return unit in units_acted_this_turn

func get_units_that_can_act() -> Array[Unit]:
	"""Get units that haven't acted this turn"""
	var available_units: Array[Unit] = []
	for unit in owned_units:
		if unit and not has_unit_acted(unit):
			available_units.append(unit)
	return available_units

func can_end_turn() -> bool:
	"""Check if player can end their turn"""
	return current_state == PlayerState.ACTIVE

func has_units_remaining() -> bool:
	"""Check if player has any units left"""
	return not owned_units.is_empty()

# Validation methods
func owns_unit(unit: Unit) -> bool:
	"""Check if this player owns a specific unit"""
	return unit in owned_units

func can_control_unit(unit: Unit) -> bool:
	"""Check if player can currently control a unit"""
	return current_state == PlayerState.ACTIVE and owns_unit(unit)

func can_select_unit(unit: Unit) -> bool:
	"""Check if player can select a unit"""
	return owns_unit(unit) and (current_state == PlayerState.ACTIVE or current_state == PlayerState.WAITING)

# Statistics and info
func get_unit_count() -> int:
	"""Get number of units owned by this player"""
	return owned_units.size()

func get_active_unit_count() -> int:
	"""Get number of units that can still act"""
	return get_units_that_can_act().size()

func get_display_name() -> String:
	"""Get formatted display name"""
	return player_name + " (Player " + str(player_id + 1) + ")"

func get_team_color() -> Color:
	"""Get team color"""
	return team_color

func set_team_color(color: Color) -> void:
	"""Set team color and update materials"""
	team_color = color
	_setup_team_materials()
	
	# Don't update unit visuals here - let UnitVisualManager handle it
	# The visual manager should listen for team color changes if needed

# Debug and utility
func get_debug_info() -> Dictionary:
	"""Get debug information about this player"""
	return {
		"player_id": player_id,
		"player_name": player_name,
		"state": PlayerState.keys()[current_state],
		"units_owned": owned_units.size(),
		"units_acted": units_acted_this_turn.size(),
		"units_lost": units_lost,
		"turns_played": turns_played,
		"team_color": team_color
	}

func _to_string() -> String:
	"""String representation for debugging"""
	return "Player[" + str(player_id) + ":" + player_name + " (" + PlayerState.keys()[current_state] + ")]"