# Example of how to integrate multiplayer with existing game systems
# This shows how to modify UnitActionsPanel to work with multiplayer

extends Node

# This is an example of how you would modify the existing UnitActionsPanel.gd
# to work with the new multiplayer system

"""
Example modifications to UnitActionsPanel.gd:

1. Add multiplayer checks to action methods:

func _on_move_pressed() -> void:
	if not selected_unit:
		return
	
	# NEW: Check if multiplayer is active and if it's our turn
	if Multiplayer.is_active() and not Multiplayer.is_my_turn():
		print("Cannot move: not your turn")
		return
	
	# Existing validation code...
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system.validate_turn_action(selected_unit, "move"):
			# NEW: Submit action to multiplayer system
			if Multiplayer.is_active():
				var action_data = {
					"unit_id": selected_unit.get_id(),
					"player_id": PlayerManager.get_current_player().player_id
				}
				Multiplayer.submit_action("unit_move_start", action_data)
			else:
				_enter_movement_mode()

2. Modify movement execution:

func _execute_movement_to_destination(destination: Vector3) -> void:
	if not selected_unit:
		return
	
	# Get movement data
	var old_world_pos = selected_unit.global_position
	var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)
	
	# NEW: Submit to multiplayer if active
	if Multiplayer.is_active():
		var action_data = {
			"unit_id": selected_unit.get_id(),
			"from_position": old_grid_pos,
			"to_position": destination,
			"player_id": PlayerManager.get_current_player().player_id
		}
		
		# Submit action and let multiplayer system handle synchronization
		if Multiplayer.submit_action("unit_move", action_data):
			print("Movement submitted to multiplayer system")
		else:
			print("Failed to submit movement to multiplayer")
		return
	
	# Existing single-player movement code...
	var new_world_pos = grid.calculate_map_position(destination)
	new_world_pos.y = selected_unit.global_position.y
	
	_clear_movement_range()
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)
	_complete_movement_action()
	_update_actions()

3. Add multiplayer event handlers:

func _ready() -> void:
	# Existing code...
	
	# NEW: Connect to multiplayer events
	if Multiplayer:
		Multiplayer.turn_started.connect(_on_multiplayer_turn_started)
		Multiplayer.turn_ended.connect(_on_multiplayer_turn_ended)
		Multiplayer.game_started.connect(_on_multiplayer_game_started)

func _on_multiplayer_turn_started(player_id: int) -> void:
	# Update UI based on whose turn it is
	_update_actions()
	
	var local_player_id = Multiplayer.get_status().get("local_player_id", -1)
	if player_id == local_player_id:
		print("Your turn started!")
	else:
		print("Player %d's turn started" % player_id)

func _on_multiplayer_turn_ended(player_id: int) -> void:
	# Update UI when turn ends
	_update_actions()

func _on_multiplayer_game_started(players: Array) -> void:
	print("Multiplayer game started with %d players" % players.size())
	_update_actions()

4. Modify action availability checks:

func _update_actions() -> void:
	if not selected_unit or not PlayerManager:
		return
	
	var current_player = PlayerManager.get_current_player()
	var game_active = PlayerManager.current_game_state == PlayerManager.GameState.IN_PROGRESS
	var can_control = current_player and current_player.can_control_unit(selected_unit)
	
	# NEW: Add multiplayer checks
	var multiplayer_allows_action = true
	if Multiplayer.is_active():
		multiplayer_allows_action = Multiplayer.is_my_turn()
	
	# Existing turn system checks...
	var can_perform_unit_actions = false
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		can_perform_unit_actions = turn_system.can_unit_act(selected_unit)
	
	# Combine all checks
	var final_can_act = can_control and can_perform_unit_actions and multiplayer_allows_action
	
	# Update buttons
	if move_button:
		move_button.disabled = not final_can_act
		if not multiplayer_allows_action:
			move_button.text = "Move (M)\n[Not Your Turn]"
		elif final_can_act:
			move_button.text = "Move (M)"
		else:
			move_button.text = "Move (M)\n[N/A]"
"""

# Example of a multiplayer-aware game action handler
class MultiplayerActionHandler:
	
	static func handle_unit_move_action(action_data: Dictionary) -> void:
		"""Handle a unit move action received from multiplayer system"""
		var unit_id = action_data.get("unit_id", "")
		var from_pos = action_data.get("from_position", Vector3.ZERO)
		var to_pos = action_data.get("to_position", Vector3.ZERO)
		var player_id = action_data.get("player_id", -1)
		
		print("Handling multiplayer unit move: %s from %s to %s (player %d)" % [unit_id, from_pos, to_pos, player_id])
		
		# Find the unit in the scene
		var unit = _find_unit_by_id(unit_id)
		if not unit:
			print("Unit not found: %s" % unit_id)
			return
		
		# Calculate world positions
		var grid = preload("res://board/Grid.tres")
		var new_world_pos = grid.calculate_map_position(to_pos)
		new_world_pos.y = unit.global_position.y
		
		# Animate the movement
		var tween = unit.create_tween()
		tween.tween_property(unit, "global_position", new_world_pos, 0.5)
		
		# Update game state
		GameEvents.unit_moved.emit(unit, from_pos, to_pos)
		
		# Mark unit as acted if it's in a turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system.has_method("mark_unit_acted"):
				turn_system.mark_unit_acted(unit)
	
	static func _find_unit_by_id(unit_id: String) -> Unit:
		"""Find a unit by its ID in the current scene"""
		var scene_root = Engine.get_main_loop().current_scene
		
		# Look in player nodes
		for player_path in ["Map/Player1", "Map/Player2"]:
			var player_node = scene_root.get_node_or_null(player_path)
			if player_node:
				for child in player_node.get_children():
					if child is Unit and child.get_id() == unit_id:
						return child
		
		return null

# Example of how to set up multiplayer action handling
func setup_multiplayer_action_handling() -> void:
	"""Set up handlers for multiplayer actions"""
	
	# Connect to multiplayer game state for action handling
	var multiplayer_game_state = get_node("/root/MultiplayerGameState")
	if multiplayer_game_state:
		multiplayer_game_state.message_received.connect(_on_multiplayer_action_received)

func _on_multiplayer_action_received(sender_id: int, message: Dictionary) -> void:
	"""Handle actions received from other players"""
	if message.get("type") != "game_action":
		return
	
	var action_type = message.get("action_type", "")
	var action_data = message.get("action_data", {})
	
	match action_type:
		"unit_move":
			MultiplayerActionHandler.handle_unit_move_action(action_data)
		"unit_attack":
			_handle_unit_attack_action(action_data)
		"end_turn":
			_handle_end_turn_action(action_data)
		_:
			print("Unknown multiplayer action: %s" % action_type)

func _handle_unit_attack_action(action_data: Dictionary) -> void:
	"""Handle unit attack action from multiplayer"""
	# TODO: Implement attack handling
	print("Handling multiplayer unit attack: %s" % str(action_data))

func _handle_end_turn_action(action_data: Dictionary) -> void:
	"""Handle end turn action from multiplayer"""
	var player_id = action_data.get("player_id", -1)
	print("Player %d ended their turn" % player_id)
	
	# Update turn system
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system.has_method("end_player_turn"):
			turn_system.end_player_turn()

# Example of how to integrate with existing GameEvents
func integrate_with_game_events() -> void:
	"""Show how to integrate multiplayer with existing GameEvents"""
	
	# Connect existing game events to multiplayer system
	if GameEvents:
		GameEvents.unit_moved.connect(_on_unit_moved_locally)
		GameEvents.unit_action_completed.connect(_on_unit_action_completed_locally)

func _on_unit_moved_locally(unit: Unit, from_pos: Vector3, to_pos: Vector3) -> void:
	"""Handle local unit movement and sync to multiplayer"""
	var multiplayer_manager = get_node("/root/MultiplayerManager")
	if not multiplayer_manager or not multiplayer_manager.is_multiplayer_active():
		return
	
	# Only sync if this was a local action (not received from multiplayer)
	if multiplayer_manager.is_local_player_turn():
		var action_data = {
			"unit_id": unit.get_id(),
			"from_position": from_pos,
			"to_position": to_pos,
			"player_id": multiplayer_manager.get_multiplayer_status().get("local_player_id", -1)
		}
		
		multiplayer_manager.submit_game_action("unit_move", action_data)

func _on_unit_action_completed_locally(unit: Unit, action_type: String) -> void:
	"""Handle local unit action completion and sync to multiplayer"""
	var multiplayer_manager = get_node("/root/MultiplayerManager")
	if not multiplayer_manager or not multiplayer_manager.is_multiplayer_active():
		return
	
	if not multiplayer_manager.is_local_player_turn():
		return
	
	var action_data = {
		"unit_id": unit.get_id(),
		"action_type": action_type,
		"player_id": multiplayer_manager.get_multiplayer_status().get("local_player_id", -1)
	}
	
	multiplayer_manager.submit_game_action("unit_action_completed", action_data)