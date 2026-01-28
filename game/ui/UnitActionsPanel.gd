extends Control

class_name UnitActionsPanel

# UI panel for unit actions (Move, End Turn, etc.)
# Only appears when a unit is selected (not hovered)

@onready var margin_container: MarginContainer = $MarginContainer
@onready var content_container: VBoxContainer = $MarginContainer/ContentContainer
@onready var unit_header_container: HBoxContainer = $MarginContainer/ContentContainer/UnitHeaderContainer
@onready var unit_header_background: Panel = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitHeaderBackground
@onready var unit_icon: TextureRect = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitIcon
@onready var unit_info_container: VBoxContainer = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer
@onready var unit_name_label: Label = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer/UnitNameLabel
@onready var unit_type_label: Label = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer/UnitTypeLabel
@onready var move_button: Button = $MarginContainer/ContentContainer/ActionsContainer/MoveButton
@onready var end_unit_turn_button: Button = $MarginContainer/ContentContainer/ActionsContainer/EndUnitTurnButton
@onready var unit_summary_button: Button = $MarginContainer/ContentContainer/UnitSummaryButton
@onready var stats_container: VBoxContainer = $MarginContainer/ContentContainer/StatsContainer
@onready var health_label: Label = $MarginContainer/ContentContainer/StatsContainer/HealthLabel
@onready var attack_label: Label = $MarginContainer/ContentContainer/StatsContainer/AttackLabel
@onready var defense_label: Label = $MarginContainer/ContentContainer/StatsContainer/DefenseLabel
@onready var speed_label: Label = $MarginContainer/ContentContainer/StatsContainer/SpeedLabel
@onready var movement_label: Label = $MarginContainer/ContentContainer/StatsContainer/MovementLabel
@onready var range_label: Label = $MarginContainer/ContentContainer/StatsContainer/RangeLabel
@onready var end_player_turn_button: Button = $MarginContainer/ContentContainer/EndPlayerTurnButton
@onready var cancel_button: Button = $MarginContainer/ContentContainer/CancelButton

var selected_unit: Unit = null
var stats_expanded: bool = false

func _ready() -> void:
	print("=== UnitActionsPanel _ready() called ===")
	
	# Log initial container size
	print("Initial panel size: ", size)
	print("Initial panel position: ", position)
	
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP  # Make sure panel stops mouse events
	
	# Connect to game events
	print("Connecting to GameEvents...")
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		print("GameEvents connections established")
	else:
		print("ERROR: GameEvents not found!")
	
	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
		print("PlayerManager connections established")
	else:
		print("ERROR: PlayerManager not found!")
	
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
	
	if unit_summary_button:
		unit_summary_button.mouse_filter = Control.MOUSE_FILTER_STOP
		unit_summary_button.pressed.connect(_on_unit_summary_pressed)
		print("Unit Summary button connected")
	else:
		print("ERROR: Unit Summary button not found!")
	
	if end_player_turn_button:
		end_player_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_player_turn_button.pressed.connect(_on_end_player_turn_pressed)
		print("End Player Turn button connected")
	else:
		print("ERROR: End Player Turn button not found!")
		
	if cancel_button:
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
		cancel_button.pressed.connect(_on_cancel_pressed)
		print("Cancel button connected")
	else:
		print("ERROR: Cancel button not found!")
	
	# Hide panel initially
	_hide_panel()
	
	# Style the unit header background
	_setup_unit_header_styling()
	
	print("UnitActionsPanel initialized and hidden")

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			print("=== UnitActionsPanel RESIZED ===")
			print("New size: ", size)
			print("New position: ", position)
			print("Content container size: ", content_container.size if content_container else "null")
			print("Margin container size: ", margin_container.size if margin_container else "null")
		NOTIFICATION_VISIBILITY_CHANGED:
			print("=== UnitActionsPanel VISIBILITY CHANGED ===")
			print("Visible: ", visible)
			print("Current size: ", size)

func _setup_unit_header_styling() -> void:
	"""Setup styling for the unit header background"""
	if unit_header_background:
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
		style_box.border_width_left = 1
		style_box.border_width_top = 1
		style_box.border_width_right = 1
		style_box.border_width_bottom = 1
		style_box.corner_radius_top_left = 4
		style_box.corner_radius_top_right = 4
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 4
		unit_header_background.add_theme_stylebox_override("panel", style_box)

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - show actions for selected unit"""
	print("=== UnitActionsPanel: Unit selection received ===")
	print("Unit: " + unit.name)
	print("Position: " + str(position))
	
	# Only show if this is the current player's unit
	if not PlayerManager.can_current_player_select_unit(unit):
		print("Selection rejected by PlayerManager")
		return
	
	# For Speed First mode, allow selection of any unit but actions will be restricted in _update_actions
	# For Traditional mode, still check turn system constraints
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		
		# Only block selection in Traditional mode if unit can't act
		if turn_system is TraditionalTurnSystem and not turn_system.can_unit_act(unit):
			print("Selection rejected by Traditional turn system: " + turn_system.system_name)
			return
		
		# In Speed First mode, allow selection but _update_actions will handle restrictions
		if turn_system is SpeedFirstTurnSystem:
			print("Speed First mode: Allowing selection, actions will be restricted as needed")
	
	print("Unit selection accepted: " + unit.name)
	selected_unit = unit
	_update_unit_header()
	_update_actions()
	_update_unit_stats()
	_show_panel()
	print("=== UnitActionsPanel: Unit selection processing complete ===")

func _update_unit_header() -> void:
	"""Update the unit header with name, type, and icon"""
	if not selected_unit:
		return
	
	# Update unit name with player info
	if unit_name_label:
		var player = selected_unit.get_owner_player()
		var player_info = ""
		if player:
			player_info = " (" + player.get_display_name() + ")"
		unit_name_label.text = selected_unit.get_display_name() + player_info
	
	# Update unit type
	if unit_type_label:
		var unit_type = selected_unit.get_unit_type()
		if unit_type:
			unit_type_label.text = unit_type.display_name
		else:
			unit_type_label.text = "Unknown Type"
	
	# Update unit icon
	if unit_icon:
		_update_unit_icon()
	
	# Update header background color based on player
	if unit_header_background:
		_update_header_background_color()

func _update_unit_icon() -> void:
	"""Update the unit icon based on unit type and player"""
	if not selected_unit or not unit_icon:
		return
	
	# For now, create a simple colored rectangle as the unit icon
	# This can be replaced with actual unit sprites later
	var unit_type = selected_unit.get_unit_type()
	var player = selected_unit.get_owner_player()
	
	# Create a simple colored texture based on unit type and player
	var image = Image.create(36, 36, false, Image.FORMAT_RGBA8)
	
	# Base color based on unit type
	var base_color: Color
	if unit_type and unit_type.display_name == "Warrior":
		base_color = Color(0.8, 0.6, 0.2, 1.0)  # Golden for warriors
	elif unit_type and unit_type.display_name == "Archer":
		base_color = Color(0.2, 0.8, 0.2, 1.0)  # Green for archers
	else:
		base_color = Color(0.6, 0.6, 0.6, 1.0)  # Gray for unknown
	
	# Tint based on player
	if player:
		if player.player_id == 0:
			# Player 1 - add blue tint
			base_color = base_color.lerp(Color(0.2, 0.4, 0.8, 1.0), 0.3)
		elif player.player_id == 1:
			# Player 2 - add red tint
			base_color = base_color.lerp(Color(0.8, 0.2, 0.2, 1.0), 0.3)
	
	# Fill the image with the color
	image.fill(base_color)
	
	# Add a simple border
	var border_color = Color(1.0, 1.0, 1.0, 0.8)
	# Top and bottom borders
	for x in range(36):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, 35, border_color)
	# Left and right borders
	for y in range(36):
		image.set_pixel(0, y, border_color)
		image.set_pixel(35, y, border_color)
	
	# Create texture from image
	var texture = ImageTexture.new()
	texture.set_image(image)
	unit_icon.texture = texture

func _update_header_background_color() -> void:
	"""Update header background color based on player"""
	if not selected_unit or not unit_header_background:
		return
	
	var player = selected_unit.get_owner_player()
	var style_box = StyleBoxFlat.new()
	
	# Base styling
	style_box.border_width_left = 1
	style_box.border_width_top = 1
	style_box.border_width_right = 1
	style_box.border_width_bottom = 1
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	
	# Color based on player
	if player:
		if player.player_id == 0:
			# Player 1 - blue theme
			style_box.bg_color = Color(0.1, 0.2, 0.4, 0.8)
			style_box.border_color = Color(0.2, 0.4, 0.8, 0.8)
		elif player.player_id == 1:
			# Player 2 - red theme
			style_box.bg_color = Color(0.4, 0.1, 0.1, 0.8)
			style_box.border_color = Color(0.8, 0.2, 0.2, 0.8)
		else:
			# Neutral - gray theme
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
	else:
		# No player - default gray
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
	
	unit_header_background.add_theme_stylebox_override("panel", style_box)

func _update_unit_stats() -> void:
	"""Update the unit stats display"""
	if not selected_unit:
		return
	
	# Update all stat labels
	if health_label:
		health_label.text = "Health: " + str(selected_unit.current_health) + "/" + str(selected_unit.max_health)
	
	if attack_label:
		var attack = selected_unit.get_stat("attack") if selected_unit.has_method("get_stat") else 0
		attack_label.text = "Attack: " + str(attack)
	
	if defense_label:
		var defense = selected_unit.get_stat("defense") if selected_unit.has_method("get_stat") else 0
		defense_label.text = "Defense: " + str(defense)
	
	if speed_label:
		var speed = selected_unit.get_stat("speed") if selected_unit.has_method("get_stat") else 0
		# Show current speed if different from base (due to battle effects)
		var current_speed = speed
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system is SpeedFirstTurnSystem:
				current_speed = (turn_system as SpeedFirstTurnSystem).get_unit_current_speed(selected_unit)
		
		if current_speed != speed:
			speed_label.text = "Speed: " + str(current_speed) + " (base: " + str(speed) + ")"
		else:
			speed_label.text = "Speed: " + str(speed)
	
	if movement_label:
		var movement = selected_unit.get_stat("movement") if selected_unit.has_method("get_stat") else 0
		movement_label.text = "Movement: " + str(movement)
	
	if range_label:
		var range_val = selected_unit.get_stat("range") if selected_unit.has_method("get_stat") else 0
		range_label.text = "Range: " + str(range_val)

func _on_unit_summary_pressed() -> void:
	"""Handle Unit Summary button press - toggle stats display"""
	stats_expanded = not stats_expanded
	
	if stats_container:
		stats_container.visible = stats_expanded
	
	if unit_summary_button:
		if stats_expanded:
			unit_summary_button.text = "Unit Summary ▲"
		else:
			unit_summary_button.text = "Unit Summary ▼"
	
	print("Unit stats " + ("expanded" if stats_expanded else "collapsed"))

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection - hide actions"""
	if selected_unit == unit:
		selected_unit = null
		stats_expanded = false
		if stats_container:
			stats_container.visible = false
		if unit_summary_button:
			unit_summary_button.text = "Unit Summary ▼"
		_clear_unit_header()
		_hide_panel()

func _clear_unit_header() -> void:
	"""Clear the unit header information"""
	if unit_name_label:
		unit_name_label.text = "No Unit Selected"
	if unit_type_label:
		unit_type_label.text = ""
	if unit_icon:
		unit_icon.texture = null

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
	
	# Determine action availability based on turn system
	var can_perform_unit_actions = false
	var action_restriction_reason = ""
	
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		
		if turn_system is TraditionalTurnSystem:
			# Traditional mode: use existing logic
			can_perform_unit_actions = turn_system.can_unit_act(selected_unit)
			
			if not can_perform_unit_actions:
				var trad_system = turn_system as TraditionalTurnSystem
				if selected_unit in trad_system.get_units_that_acted():
					action_restriction_reason = "already acted this turn"
				elif not current_player.owns_unit(selected_unit):
					action_restriction_reason = "not your unit"
				else:
					action_restriction_reason = "cannot act"
		
		elif turn_system is SpeedFirstTurnSystem:
			# Speed First mode: only current acting unit can perform actions
			var speed_system = turn_system as SpeedFirstTurnSystem
			var current_acting_unit = speed_system.get_current_acting_unit()
			
			if selected_unit == current_acting_unit:
				can_perform_unit_actions = speed_system.can_unit_act(selected_unit)
				if not can_perform_unit_actions:
					if selected_unit in speed_system.get_units_that_acted_this_round():
						action_restriction_reason = "already acted this round"
					else:
						action_restriction_reason = "cannot act"
			else:
				can_perform_unit_actions = false
				if selected_unit in speed_system.get_units_that_acted_this_round():
					action_restriction_reason = "already acted this round"
				else:
					action_restriction_reason = "not this unit's turn"
		else:
			can_perform_unit_actions = turn_system.can_unit_act(selected_unit)
			if not can_perform_unit_actions:
				action_restriction_reason = "not your turn"
	else:
		# No turn system active
		can_perform_unit_actions = can_control
		if not can_perform_unit_actions:
			action_restriction_reason = "no turn system active"
	
	# Update Move button - only available if unit can perform actions
	if move_button:
		var can_move = can_control and can_perform_unit_actions and selected_unit.can_act()
		move_button.disabled = not can_move
		
		if can_move:
			move_button.text = "Move (M)"
		elif not can_control:
			move_button.text = "Move (M)\n[Not Yours]"
		elif action_restriction_reason == "not this unit's turn":
			move_button.text = "Move (M)\n[Not Turn]"
		elif action_restriction_reason == "already acted this round":
			move_button.text = "Move (M)\n[Used]"
		elif action_restriction_reason == "already acted this turn":
			move_button.text = "Move (M)\n[Used]"
		else:
			move_button.text = "Move (M)\n[N/A]"
	
	# Update End Unit Turn button - only available if unit can perform actions
	if end_unit_turn_button:
		var can_end_unit_turn = can_control and can_perform_unit_actions and selected_unit.can_act()
		end_unit_turn_button.disabled = not can_end_unit_turn
		
		if can_end_unit_turn:
			end_unit_turn_button.text = "End Turn (E)"
		elif not can_control:
			end_unit_turn_button.text = "End Turn (E)\n[Not Yours]"
		elif action_restriction_reason == "not this unit's turn":
			end_unit_turn_button.text = "End Turn (E)\n[Not Turn]"
		elif action_restriction_reason == "already acted this round":
			end_unit_turn_button.text = "End Turn (E)\n[Used]"
		elif action_restriction_reason == "already acted this turn":
			end_unit_turn_button.text = "End Turn (E)\n[Used]"
		else:
			end_unit_turn_button.text = "End Turn (E)\n[N/A]"
	
	# Update End Player Turn button - always available if you can control and game is active
	if end_player_turn_button:
		var can_end_player_turn = can_control and game_active
		end_player_turn_button.disabled = not can_end_player_turn
		
		if can_end_player_turn:
			end_player_turn_button.text = "End Player Turn (P)"
		elif not can_control:
			end_player_turn_button.text = "End Player Turn (P)\n[Not Yours]"
		else:
			end_player_turn_button.text = "End Player Turn (P)\n[N/A]"
	
	# Unit Summary button is always available when unit is selected (handled in _on_unit_summary_pressed)
	if unit_summary_button:
		unit_summary_button.disabled = false
		if stats_expanded:
			unit_summary_button.text = "Unit Summary ▲"
		else:
			unit_summary_button.text = "Unit Summary ▼"
	
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

func _on_end_player_turn_pressed() -> void:
	"""Handle End Player Turn button press - ends the entire player's turn"""
	print("=== END PLAYER TURN BUTTON PRESSED ===")
	
	if not PlayerManager:
		print("PlayerManager not available")
		return
	
	var current_player = PlayerManager.get_current_player()
	if not current_player:
		print("No current player")
		return
	
	print("Ending turn for player: " + current_player.player_name)
	
	# Use the turn system to end the player's turn
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Using turn system to end player turn: " + turn_system.system_name)
		
		# End the player's turn through the turn system
		if turn_system.has_method("end_player_turn"):
			turn_system.end_player_turn()
		else:
			# Fallback: use PlayerManager directly
			print("Turn system doesn't have end_player_turn method, using PlayerManager")
			PlayerManager.end_current_player_turn()
	else:
		# Fallback: use PlayerManager directly
		print("No active turn system, using PlayerManager")
		PlayerManager.end_current_player_turn()
	
	print("=== END PLAYER TURN PROCESSING COMPLETE ===")

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
	print("=== Showing UnitActionsPanel ===")
	print("Panel size before show: ", size)
	visible = true
	modulate.a = 1.0
	
	# Force a layout update and log the results
	await get_tree().process_frame
	print("Panel size after show: ", size)
	print("Content container size: ", content_container.size if content_container else "null")
	print("Margin container size: ", margin_container.size if margin_container else "null")
	
	# Try to resize to fit content
	_try_resize_to_content()

func _try_resize_to_content() -> void:
	"""Attempt to resize the panel to fit its content"""
	if not content_container:
		print("No content container found for resizing")
		return
	
	print("=== Attempting to resize panel to content ===")
	
	# Get the minimum size needed for content
	var content_min_size = content_container.get_combined_minimum_size()
	print("Content minimum size: ", content_min_size)
	
	# Add margin container padding
	if margin_container:
		var margin_left = margin_container.get_theme_constant("margin_left")
		var margin_right = margin_container.get_theme_constant("margin_right") 
		var margin_top = margin_container.get_theme_constant("margin_top")
		var margin_bottom = margin_container.get_theme_constant("margin_bottom")
		
		print("Margins - Left: ", margin_left, " Right: ", margin_right, " Top: ", margin_top, " Bottom: ", margin_bottom)
		
		var needed_size = Vector2(
			content_min_size.x + margin_left + margin_right,
			content_min_size.y + margin_top + margin_bottom
		)
		
		print("Calculated needed size: ", needed_size)
		print("Current panel size: ", size)
		
		# Try to set the size
		custom_minimum_size = needed_size
		size = needed_size
		
		print("Set custom_minimum_size to: ", custom_minimum_size)
		print("Set size to: ", size)
		
		# Force layout update
		await get_tree().process_frame
		print("Final panel size after resize: ", size)

func _hide_panel() -> void:
	"""Hide the actions panel"""
	print("=== Hiding UnitActionsPanel ===")
	print("Panel size before hide: ", size)
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
			KEY_F4:
				print("F4 pressed - testing manual unit selection")
				_test_manual_unit_selection()
			
			# Keyboard shortcuts for actions (only when panel is visible and unit selected)
			KEY_M:
				if visible and selected_unit:
					print("M key pressed - triggering Move action")
					_on_move_pressed()
			KEY_E:
				if visible and selected_unit:
					print("E key pressed - triggering End Unit Turn action")
					_on_end_unit_turn_pressed()
			KEY_P:
				if visible and selected_unit:
					print("P key pressed - triggering End Player Turn action")
					_on_end_player_turn_pressed()
			KEY_S:
				if visible and selected_unit:
					print("S key pressed - triggering Unit Summary toggle")
					_on_unit_summary_pressed()
			KEY_C, KEY_ESCAPE:
				if visible and selected_unit:
					print("C/ESC key pressed - triggering Cancel action")
					_on_cancel_pressed()

func _test_manual_unit_selection() -> void:
	"""Test manual unit selection for debugging"""
	print("=== Testing manual unit selection ===")
	
	# Find a unit to test with
	var scene_root = get_tree().current_scene
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				print("Found test unit: " + child.name)
				var world_pos = child.global_position
				print("Manually triggering unit selection...")
				_on_unit_selected(child, world_pos)
				return
	
	print("No units found for testing")