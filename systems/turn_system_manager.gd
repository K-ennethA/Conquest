extends Node

# TurnSystemManager Singleton
# Manages active turn system and coordinates with PlayerManager

signal turn_system_activated(turn_system: TurnSystemBase)
signal turn_system_deactivated(turn_system: TurnSystemBase)
signal turn_system_switched(old_system: TurnSystemBase, new_system: TurnSystemBase)

var active_turn_system: TurnSystemBase = null
var available_turn_systems: Dictionary = {}

func _ready() -> void:
	name = "TurnSystemManager"

	# Connect to PlayerManager events
	if PlayerManager:
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
		PlayerManager.player_registered.connect(_on_player_registered)

# Turn system registration
func register_turn_system(system: TurnSystemBase) -> void:
	"""Register a turn system for use"""
	if not system:
		return

	var system_key = TurnSystemBase.TurnSystemType.keys()[system.system_type]

	# Registering over an occupied slot drops the manager's only reference to the old
	# instance, so it must also be freed (see _free_owned_system) or it leaks as a
	# parentless orphan Node.
	var previous = available_turn_systems.get(system_key)
	if previous != null and previous != system:
		unregister_turn_system(previous)
		_free_owned_system(previous)

	available_turn_systems[system_key] = system

	# Connect to turn system signals (guarded so registering the same instance twice
	# never double-fires these handlers -- mirrors the is_connected guards in
	# unregister_turn_system and TurnSystemBase.register_unit).
	if not system.turn_started.is_connected(_on_turn_started):
		system.turn_started.connect(_on_turn_started)
	if not system.turn_ended.is_connected(_on_turn_ended):
		system.turn_ended.connect(_on_turn_ended)
	if not system.unit_action_completed.is_connected(_on_unit_action_completed):
		system.unit_action_completed.connect(_on_unit_action_completed)
	if not system.all_units_acted.is_connected(_on_all_units_acted):
		system.all_units_acted.connect(_on_all_units_acted)

func unregister_turn_system(system: TurnSystemBase) -> void:
	"""Unregister a turn system"""
	if not system:
		return

	var system_key = TurnSystemBase.TurnSystemType.keys()[system.system_type]

	if system == active_turn_system:
		deactivate_turn_system()

	# Disconnect signals
	if system.turn_started.is_connected(_on_turn_started):
		system.turn_started.disconnect(_on_turn_started)
	if system.turn_ended.is_connected(_on_turn_ended):
		system.turn_ended.disconnect(_on_turn_ended)
	if system.unit_action_completed.is_connected(_on_unit_action_completed):
		system.unit_action_completed.disconnect(_on_unit_action_completed)
	if system.all_units_acted.is_connected(_on_all_units_acted):
		system.all_units_acted.disconnect(_on_all_units_acted)

	available_turn_systems.erase(system_key)

# Turn system activation
func activate_turn_system(system_type: TurnSystemBase.TurnSystemType) -> bool:
	"""Activate a specific turn system"""
	var system_key = TurnSystemBase.TurnSystemType.keys()[system_type]

	if not available_turn_systems.has(system_key):
		return false

	var new_system = available_turn_systems[system_key]
	return switch_to_turn_system(new_system)

func switch_to_turn_system(new_system: TurnSystemBase) -> bool:
	"""Switch to a different turn system"""
	if not new_system:
		return false

	var old_system = active_turn_system

	# Deactivate current system
	if active_turn_system:
		deactivate_turn_system()

	# Activate new system
	active_turn_system = new_system
	active_turn_system.is_active = true

	# Register all current players with the new system
	if PlayerManager:
		for player in PlayerManager.players:
			active_turn_system.register_player(player)

	# Also register any units that might not be owned by players yet
	_register_all_scene_units()

	# Start the turn system
	active_turn_system.start_turn_system()

	# Emit signals
	turn_system_activated.emit(active_turn_system)
	if old_system:
		turn_system_switched.emit(old_system, active_turn_system)

	return true

func _register_all_scene_units() -> void:
	"""Register all units found in the current scene with the active turn system"""
	if not active_turn_system:
		return

	var scene_root = get_tree().current_scene
	var units_found = 0

	# Look for units in Player1 and Player2 nodes
	var player_paths = ["Map/Player1", "Map/Player2"]

	for player_path in player_paths:
		var player_node = scene_root.get_node_or_null(player_path)

		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					if child not in active_turn_system.registered_units:
						active_turn_system.register_unit(child)
						units_found += 1

func deactivate_turn_system() -> void:
	"""Deactivate the current turn system"""
	if not active_turn_system:
		return

	var old_system = active_turn_system

	# End the turn system
	old_system.end_turn_system()
	old_system.is_active = false

	active_turn_system = null

	turn_system_deactivated.emit(old_system)

# Turn system queries
func get_active_turn_system() -> TurnSystemBase:
	"""Get the currently active turn system"""
	return active_turn_system

func has_active_turn_system() -> bool:
	"""Check if there is an active turn system"""
	return active_turn_system != null

func get_available_turn_systems() -> Array[String]:
	"""Get list of available turn system names"""
	var keys: Array[String] = []
	for key in available_turn_systems.keys():
		keys.append(key)
	return keys

func is_turn_system_available(system_type: TurnSystemBase.TurnSystemType) -> bool:
	"""Check if a turn system type is available"""
	var system_key = TurnSystemBase.TurnSystemType.keys()[system_type]
	return available_turn_systems.has(system_key)

# Turn management delegation
func advance_turn() -> void:
	"""Advance the current turn"""
	if active_turn_system:
		active_turn_system.advance_turn()

func can_unit_act(unit: Unit) -> bool:
	"""Check if a unit can act in the current turn"""
	if not active_turn_system:
		return false
	return active_turn_system.can_unit_act(unit)

func get_current_active_player() -> Player:
	"""Get the currently active player"""
	if not active_turn_system:
		return null
	return active_turn_system.get_current_active_player()

func get_turn_order() -> Array:
	"""Get the current turn order"""
	if not active_turn_system:
		return []
	return active_turn_system.get_turn_order()

func validate_turn_action(unit: Unit, action_type: String) -> bool:
	"""Validate if a unit can perform an action"""
	if not active_turn_system:
		return false
	return active_turn_system.validate_turn_action(unit, action_type)

# Event handlers
func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	match new_state:
		PlayerManager.GameState.IN_PROGRESS:
			# Game started - ensure turn system is active
			if not active_turn_system:
				# Activate the turn system selected in GameSettings
				var selected_type = GameSettings.selected_turn_system if GameSettings else TurnSystemBase.TurnSystemType.TRADITIONAL
				activate_turn_system(selected_type)

		PlayerManager.GameState.FINISHED:
			# Game ended - deactivate turn system
			if active_turn_system:
				deactivate_turn_system()

func _on_player_registered(player: Player) -> void:
	"""Handle new player registration"""
	if active_turn_system:
		active_turn_system.register_player(player)

func _on_turn_started(player: Player) -> void:
	"""Handle turn start from active turn system"""
	# Update PlayerManager to sync with turn system
	if PlayerManager:
		# Find the player index in PlayerManager
		var player_index = -1
		for i in range(PlayerManager.players.size()):
			if PlayerManager.players[i] == player:
				player_index = i
				break

		if player_index >= 0:
			PlayerManager.current_player_index = player_index

			# Set player states - only the current player should be ACTIVE
			for i in range(PlayerManager.players.size()):
				var p = PlayerManager.players[i]
				if i == player_index:
					p.set_state(Player.PlayerState.ACTIVE)
				else:
					if p.current_state != Player.PlayerState.ELIMINATED:
						p.set_state(Player.PlayerState.WAITING)

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end from active turn system"""
	# Set player to waiting state
	if player and player.current_state == Player.PlayerState.ACTIVE:
		player.set_state(Player.PlayerState.WAITING)

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	pass

func _on_all_units_acted() -> void:
	"""Handle all units having acted"""
	pass

# Per-session reset (for starting a fresh game in the same app run)
func reset_for_new_game() -> void:
	"""Tear down all turn-system state so a fresh game can be set up in the same app
	run. Autoloads survive scene changes, so without this the previous session's
	active_turn_system (with freed registered_units) persists and advancing a turn
	script-errors or silently wraps. apply_settings_to_game() registers a fresh
	turn-system instance on each load, so clearing the dict here is safe."""
	var was_active = active_turn_system
	if active_turn_system:
		deactivate_turn_system()

	# Unregister every available system (disconnects signals), then FREE the ones the
	# manager owns: these instances are built with .new() and never parented (see
	# GameSettings.apply_settings_to_game), so dropping the dictionary reference alone
	# leaked one parentless Node per battle boot.
	for system in available_turn_systems.values().duplicate():
		unregister_turn_system(system)
		_free_owned_system(system)
	available_turn_systems.clear()

	# An active system that was never registered (switch_to_turn_system accepts raw
	# instances) is owned here too; one that was in the dict is already freed and the
	# is_instance_valid guard skips it.
	_free_owned_system(was_active)

## Free a turn system the manager owns. Registered systems are constructed with .new() and
## deliberately NEVER parented -- SpeedFirstTurnSystem's move clock relies on being outside
## the tree (the in-tree TurnTimer HUD drives the countdown) -- so when the manager drops
## its reference it must also free the Node or every battle boot leaks an orphan. A system
## somebody parented is theirs to free and is left alone. The parameter is untyped on
## purpose: callers may hand it an already-freed reference, which a typed parameter would
## reject with "cannot convert freed Object" before the guard could run.
func _free_owned_system(system) -> void:
	if system != null and is_instance_valid(system) and system.get_parent() == null:
		system.free()

# Turn system reset (for testing)
func reset_turn_system() -> void:
	"""Reset the active turn system to initial state (for testing purposes)"""
	if active_turn_system and active_turn_system.has_method("reset_turn_system"):
		active_turn_system.reset_turn_system()

# Debug and utility
func get_turn_system_info() -> Dictionary:
	"""Get information about the turn system manager"""
	var info = {
		"has_active_system": has_active_turn_system(),
		"available_systems": get_available_turn_systems(),
		"active_system": null
	}

	if active_turn_system:
		info.active_system = active_turn_system.get_turn_system_info()

	return info

func print_turn_system_status() -> void:
	"""Print current turn system status for debugging"""
	var info = get_turn_system_info()
