extends Control

class_name UnitActionsPanel

# UI panel for unit actions (Move, End Turn, etc.)
# Only appears when a unit is selected (not hovered)

@onready var move_button: Button = $MarginContainer/VBoxContainer/ActionsContainer/MoveButton
@onready var end_unit_turn_button: Button = $MarginContainer/VBoxContainer/ActionsContainer/EndUnitTurnButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/CancelButton

var selected_unit: Unit = null

func _ready() -> void:
	print("UnitActionsPanel _ready() called")
	
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP  # Make sure panel stops mouse events
	
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	
	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	
	# Connect button signals and ensure they can receive mouse input
	if move_button:
		move_button.mouse_filter = Control.MOUSE_FILTER_STOP
		move_button.pressed.connect(_on_move_pressed)
		print("Move button connected")
	else:
		print("ERROR: Move button not found!")
		
	if end_unit_turn_button:
		end_unit_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_unit_turn_button.pressed.connect(_on_end_unit_turn_pressed)
		# Add mouse event debugging to the button
		end_unit_turn_button.gui_input.connect(_on_end_unit_turn_button_input)
		print("End Unit Turn button connected")
	else:
		print("ERROR: End Unit Turn button not found!")
		
	if cancel_button:
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
		cancel_button.pressed.connect(_on_cancel_pressed)
		print("Cancel button connected")
	else:
		print("ERROR: Cancel button not found!")
	
	# Hide panel initially
	_hide_panel()
	print("UnitActionsPanel initialized and hidden")

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - show actions for selected unit"""
	print("Unit selection attempted: " + unit.name)
	
	# Only show if this is the current player's unit
	if not PlayerManager.can_current_player_select_unit(unit):
		print("Selection rejected by PlayerManager")
		return
	
	# Check turn system constraints
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if not turn_system.can_unit_act(unit):
			print("Selection rejected by turn system: " + turn_system.system_name)
			return
	
	print("Unit selection accepted: " + unit.name)
	selected_unit = unit
	_update_actions()
	_show_panel()

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection - hide actions"""
	if selected_unit == unit:
		selected_unit = null
		_hide_panel()

func _on_player_turn_changed(player: Player) -> void:
	"""Handle player turn changes"""
	_update_actions()

func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	_update_actions()

func _update_actions() -> void:
	"""Update available actions based on selected unit and game state"""
	if not selected_unit or not PlayerManager:
		return
	
	var current_player = PlayerManager.get_current_player()
	var game_active = PlayerManager.current_game_state == PlayerManager.GameState.IN_PROGRESS
	var can_control = current_player and current_player.can_control_unit(selected_unit)
	
	# Check turn system constraints
	var turn_system_allows = true
	var turn_system_reason = ""
	
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		turn_system_allows = turn_system.can_unit_act(selected_unit)
		
		if not turn_system_allows:
			if turn_system is TraditionalTurnSystem:
				var trad_system = turn_system as TraditionalTurnSystem
				if selected_unit in trad_system.get_units_that_acted():
					turn_system_reason = "already acted this turn"
				elif not current_player.owns_unit(selected_unit):
					turn_system_reason = "not your unit"
				else:
					turn_system_reason = "cannot act"
			else:
				turn_system_reason = "not your turn"
	
	# Update Move button
	if move_button:
		var can_move = can_control and turn_system_allows and selected_unit.can_act()
		move_button.disabled = not can_move
		
		if can_move:
			move_button.text = "Move (M) - " + str(selected_unit.get_stat("movement")) + " tiles"
		elif not turn_system_allows:
			move_button.text = "Move (M) - " + turn_system_reason
		else:
			move_button.text = "Move (M) - unavailable"
	
	# Update End Unit Turn button
	if end_unit_turn_button:
		var can_end_unit_turn = can_control and turn_system_allows and selected_unit.can_act()
		end_unit_turn_button.disabled = not can_end_unit_turn
		
		if can_end_unit_turn:
			end_unit_turn_button.text = "End Unit Turn (E)"
		elif not turn_system_allows:
			end_unit_turn_button.text = "End Unit Turn (E) - " + turn_system_reason
		else:
			end_unit_turn_button.text = "End Unit Turn (E) - unavailable"
	
	# Cancel button is always available when unit is selected
	if cancel_button:
		cancel_button.disabled = false
		cancel_button.text = "Cancel (C/ESC)"

func _on_move_pressed() -> void:
	"""Handle Move button press"""
	if not selected_unit:
		print("Move pressed but no unit selected")
		return
	
	print("Move action for unit: " + selected_unit.get_display_name())
	
	# Use turn system to validate and process the action
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Validating move with turn system: " + turn_system.system_name)
		
		if turn_system.validate_turn_action(selected_unit, "move"):
			print("Move validated by turn system")
			# TODO: Implement actual movement system
			# For now, just mark the unit as having acted
			if turn_system is TraditionalTurnSystem:
				print("Marking unit acted (Traditional)")
				(turn_system as TraditionalTurnSystem).mark_unit_acted(selected_unit)
			elif turn_system is SpeedFirstTurnSystem:
				print("Marking unit acted (Speed First)")
				(turn_system as SpeedFirstTurnSystem).mark_unit_acted(selected_unit)
			
			# Emit action completed signal
			GameEvents.unit_action_completed.emit(selected_unit, "move")
			
			# Force update unit visuals immediately
			var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
			if visual_manager:
				print("Updating unit visuals via UnitVisualManager")
				visual_manager.update_all_unit_visuals()
			else:
				print("UnitVisualManager not found!")
			
			print("Unit has moved and used their action for this turn")
		else:
			print("Move action not allowed by turn system")
	else:
		print("Using fallback move system")
		# Fallback to old system
		if selected_unit.owner_player:
			selected_unit.owner_player.mark_unit_acted(selected_unit)
			selected_unit.mark_action_completed("move")
		print("Unit has moved (fallback system)")
	
	# Update actions to reflect the unit has acted
	_update_actions()

func _on_end_unit_turn_pressed() -> void:
	"""Handle End Unit Turn button press - only ends this unit's turn"""
	print("=== END UNIT TURN BUTTON PRESSED ===")
	print("Ending turn for unit: " + selected_unit.get_display_name())
	
	if not selected_unit:
		print("No unit selected")
		return
	
	# Mark this unit as having acted (ends their turn)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		
		if turn_system is TraditionalTurnSystem:
			print("Marking unit acted (Traditional)")
			(turn_system as TraditionalTurnSystem).mark_unit_acted(selected_unit)
		elif turn_system is SpeedFirstTurnSystem:
			print("Marking unit acted (Speed First)")
			(turn_system as SpeedFirstTurnSystem).mark_unit_acted(selected_unit)
		
		# Emit action completed signal
		GameEvents.unit_action_completed.emit(selected_unit, "end_turn")
		
		# Force update unit visuals immediately
		var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
		if visual_manager:
			print("Updating unit visuals via UnitVisualManager")
			visual_manager.update_all_unit_visuals()
		
		print("Unit " + selected_unit.get_display_name() + " has ended their turn")
	else:
		print("No active turn system")
	
	# Update actions to reflect the unit has acted
	_update_actions()
	
	print("=== END UNIT TURN PROCESSING COMPLETE ===")

# Add mouse event debugging
func _gui_input(event: InputEvent) -> void:
	print("UnitActionsPanel received GUI input: " + str(event))
	if event is InputEventMouseButton:
		print("Mouse button event in UnitActionsPanel: " + str(event.button_index) + " pressed: " + str(event.pressed))

func _on_end_unit_turn_button_input(event: InputEvent) -> void:
	print("End Unit Turn button received input: " + str(event))
	if event is InputEventMouseButton:
		print("End Unit Turn button mouse event: " + str(event.button_index) + " pressed: " + str(event.pressed))

func _on_cancel_pressed() -> void:
	"""Handle Cancel button press - deselect unit"""
	if selected_unit:
		GameEvents.unit_deselected.emit(selected_unit)

func _show_panel() -> void:
	"""Show the actions panel"""
	print("Showing UnitActionsPanel")
	visible = true
	modulate.a = 1.0

func _hide_panel() -> void:
	"""Hide the actions panel"""
	print("Hiding UnitActionsPanel")
	visible = false

# Public interface
func get_selected_unit() -> Unit:
	"""Get the currently selected unit"""
	return selected_unit

func is_showing_actions_for_unit(unit: Unit) -> bool:
	"""Check if panel is showing actions for specific unit"""
	return selected_unit == unit and visible

# Debug method to test button functionality
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_F1:
				print("F1 pressed - testing End Unit Turn button directly")
				_on_end_unit_turn_pressed()
			KEY_F2:
				print("F2 pressed - showing panel for testing")
				_show_panel()
			KEY_F3:
				print("F3 pressed - hiding panel")
				_hide_panel()
			
			# Keyboard shortcuts for actions (only when panel is visible and unit selected)
			KEY_M:
				if visible and selected_unit:
					print("M key pressed - triggering Move action")
					_on_move_pressed()
			KEY_E:
				if visible and selected_unit:
					print("E key pressed - triggering End Unit Turn action")
					_on_end_unit_turn_pressed()
			KEY_C, KEY_ESCAPE:
				if visible and selected_unit:
					print("C/ESC key pressed - triggering Cancel action")
					_on_cancel_pressed()