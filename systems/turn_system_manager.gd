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
	
	print("TurnSystemManager initialized")

# Turn system registration
func register_turn_system(system: TurnSystemBase) -> void:
	"""Register a turn system for use"""
	if not system:
		print("Cannot register null turn system")
		return
	
	var system_key = TurnSystemBase.TurnSystemType.keys()[system.system_type]
	available_turn_systems[system_key] = system
	
	# Connect to turn system signals
	system.turn_started.connect(_on_turn_started)
	system.turn_ended.connect(_on_turn_ended)
	system.unit_action_completed.connect(_on_unit_action_completed)
	system.all_units_acted.connect(_on_all_units_acted)
	
	print("Registered turn system: " + system.system_name)

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
	print("Unregistered turn system: " + system.system_name)

# Turn system activation
func activate_turn_system(system_type: TurnSystemBase.TurnSystemType) -> bool:
	"""Activate a specific turn system"""
	var system_key = TurnSystemBase.TurnSystemType.keys()[system_type]
	
	if not available_turn_systems.has(system_key):
		print("Turn system not available: " + system_key)
		return false
	
	var new_system = available_turn_systems[system_key]
	return switch_to_turn_system(new_system)

func switch_to_turn_system(new_system: TurnSystemBase) -> bool:
	"""Switch to a different turn system"""
	if not new_system:
		print("Cannot switch to null turn system")
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
			print("TurnSystemManager: Registered player " + player.get_display_name() + " with " + str(player.owned_units.size()) + " units")
	
	# Also register any units that might not be owned by players yet
	_register_all_scene_units()
	
	# Start the turn system
	active_turn_system.start_turn_system()
	
	# Emit signals
	turn_system_activated.emit(active_turn_system)
	if old_system:
		turn_system_switched.emit(old_system, active_turn_system)
	
	print("Activated turn system: " + active_turn_system.system_name)
	print("Total registered units: " + str(active_turn_system.registered_units.size()))
	return true

func _register_all_scene_units() -> void:
	"""Register all units found in the current scene with the active turn system"""
	if not active_turn_system:
		print("TurnSystemManager: No active turn system for unit registration")
		return
	
	var scene_root = get_tree().current_scene
	var units_found = 0
	
	print("TurnSystemManager: Searching for units in scene...")
	
	# Look for units in Player1 and Player2 nodes
	var player_paths = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_paths:
		var player_node = scene_root.get_node_or_null(player_path)
		print("  Checking path: " + player_path + " -> " + ("Found" if player_node else "Not found"))
		
		if player_node:
			print("    Children: " + str(player_node.get_child_count()))
			for child in player_node.get_children():
				print("      Child: " + child.name + " (Type: " + child.get_class() + ")")
				if child is Unit:
					if child not in active_turn_system.registered_units:
						active_turn_system.register_unit(child)
						units_found += 1
						print("        -> Registered as Unit")
					else:
						print("        -> Already registered")
				else:
					print("        -> Not a Unit")
	
	print("TurnSystemManager: Registered " + str(units_found) + " additional units from scene")
	print("TurnSystemManager: Total registered units: " + str(active_turn_system.registered_units.size()))

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
	print("Deactivated turn system: " + old_system.system_name)

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
				print("TurnSystemManager: Activating turn system: " + TurnSystemBase.TurnSystemType.keys()[selected_type])
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
	print("Turn System: " + player.get_display_name() + "'s turn started")
	
	# Update PlayerManager to sync with turn system
	if PlayerManager:
		# Find the player index in PlayerManager
		var player_index = -1
		for i in range(PlayerManager.players.size()):
			if PlayerManager.players[i] == player:
				player_index = i
				break
		
		if player_index >= 0:
			print("TurnSystemManager: Syncing PlayerManager to player index " + str(player_index))
			PlayerManager.current_player_index = player_index
			
			# Set player states - only the current player should be ACTIVE
			for i in range(PlayerManager.players.size()):
				var p = PlayerManager.players[i]
				if i == player_index:
					p.set_state(Player.PlayerState.ACTIVE)
				else:
					if p.current_state != Player.PlayerState.ELIMINATED:
						p.set_state(Player.PlayerState.WAITING)
		else:
			print("TurnSystemManager: Warning - could not find player in PlayerManager")

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end from active turn system"""
	print("Turn System: " + player.get_display_name() + "'s turn ended")
	
	# Set player to waiting state
	if player and player.current_state == Player.PlayerState.ACTIVE:
		player.set_state(Player.PlayerState.WAITING)

func _on_unit_action_completed(unit: Unit, action_type: String) -> void:
	"""Handle unit action completion"""
	print("Turn System: Unit " + unit.get_display_name() + " completed " + action_type)

func _on_all_units_acted() -> void:
	"""Handle all units having acted"""
	print("Turn System: All units have acted")

# Turn system reset (for testing)
func reset_turn_system() -> void:
	"""Reset the active turn system to initial state (for testing purposes)"""
	if active_turn_system and active_turn_system.has_method("reset_turn_system"):
		active_turn_system.reset_turn_system()
		print("TurnSystemManager: Turn system reset completed")
	else:
		print("TurnSystemManager: No active turn system to reset or reset not supported")

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
	print("=== Turn System Status ===")
	var info = get_turn_system_info()
	print("Has Active System: " + str(info.has_active_system))
	print("Available Systems: " + str(info.available_systems))
	
	if info.active_system:
		print("Active System: " + str(info.active_system))
	else:
		print("No active turn system")