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
var movement_mode: bool = false
var movement_range_tiles: Array[Vector3] = []

# Move system variables
var move_selection_panel: MoveSelectionPanel
var moves_button: Button
var move_mode: bool = false
var selected_move_index: int = -1

func _ready() -> void:
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP  # Make sure panel stops mouse events
	
	# Connect to game events
	print("Connecting to GameEvents...")
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		GameEvents.cursor_selected.connect(_on_cursor_selected)
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
	
	# Initialize move system
	_setup_move_system()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			# Resize notification - no logging to prevent spam
			pass
		NOTIFICATION_VISIBILITY_CHANGED:
			# Visibility notification - no logging to prevent spam
			pass

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
	print("Current selected_unit before: " + (selected_unit.name if selected_unit else "None"))
	
	# Check if we're in multiplayer mode and validate ownership
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		print("Multiplayer mode detected - validating unit ownership")
		
		# Get local player ID and unit owner
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(unit)
		
		print("Local player ID: " + str(local_player_id))
		print("Unit owner: " + (unit_owner.player_name if unit_owner else "None"))
		print("Unit owner ID: " + str(unit_owner.player_id if unit_owner else -1))
		
		if not unit_owner:
			print("Selection rejected: Unit has no owner")
			return
		
		# Ensure player_id is int for comparison and arithmetic
		var owner_player_id = int(unit_owner.player_id) if unit_owner.player_id is String else unit_owner.player_id
		
		if owner_player_id != local_player_id:
			print("Selection rejected: Unit belongs to Player " + str(owner_player_id + 1) + ", you are Player " + str(local_player_id + 1))
			# Could show a message to the player here
			return
		
		print("Unit ownership validated - selection allowed")
	else:
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
	print("Selected unit set to: " + selected_unit.name)
	
	_update_unit_header()
	_update_actions()
	_update_unit_stats()
	
	# Show movement range immediately when unit is selected (Fire Emblem style)
	print("About to call _show_movement_range_on_selection()...")
	_show_movement_range_on_selection()
	
	_show_panel()
	print("=== UnitActionsPanel: Unit selection processing complete ===")

func _show_movement_range_on_selection() -> void:
	"""Show movement range immediately when unit is selected (Fire Emblem style)"""
	if not selected_unit:
		return
	
	# Calculate and show movement range
	_calculate_and_show_movement_range()

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
		
		# Clear movement range when unit is deselected
		_clear_movement_range()
		
		_clear_unit_header()
		_hide_panel()

func _clear_movement_range() -> void:
	"""Clear movement range visualization"""
	movement_range_tiles.clear()
	GameEvents.movement_range_cleared.emit()

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
	
	# Update Moves button availability
	_update_moves_button_availability()

func _on_move_pressed() -> void:
	"""Handle Move button press - enter movement mode"""
	if not selected_unit:
		print("Move pressed but no unit selected")
		return
	
	print("Move action for unit: " + selected_unit.get_display_name())
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit and our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if not unit_owner or owner_player_id != local_player_id:
			print("Move action rejected: not your unit")
			return
		
		if not GameModeManager.is_my_turn():
			print("Move action rejected: not your turn in multiplayer")
			return
		
		# Submit move action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("unit_move_start", action_data):
			print("Move action submitted to multiplayer system")
			_enter_movement_mode()
		else:
			print("Move action rejected by multiplayer system")
		return
	
	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Validating move with turn system: " + turn_system.system_name)
		
		if turn_system.validate_turn_action(selected_unit, "move"):
			print("Move validated by turn system - entering movement mode")
			_enter_movement_mode()
		else:
			print("Move action not allowed by turn system")
	else:
		print("No active turn system - entering movement mode anyway")
		_enter_movement_mode()

func _on_end_unit_turn_pressed() -> void:
	"""Handle End Unit Turn button press - only ends this unit's turn"""
	print("=== END UNIT TURN BUTTON PRESSED ===")
	print("Ending turn for unit: " + selected_unit.get_display_name())
	
	if not selected_unit:
		print("No unit selected")
		return
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit and our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if not unit_owner or owner_player_id != local_player_id:
			print("End unit turn action rejected: not your unit")
			return
		
		if not GameModeManager.is_my_turn():
			print("End unit turn action rejected: not your turn in multiplayer")
			return
		
		# Submit end unit turn action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("end_unit_turn", action_data):
			print("End unit turn action submitted to multiplayer system")
			# The action will be processed when received back from network
		else:
			print("End unit turn action rejected by multiplayer system")
		return
	
	# Local game logic (existing)
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
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that it's our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		
		# Ensure player_id is int for comparison
		var current_player_id = int(current_player.player_id) if current_player.player_id is String else current_player.player_id
		
		if current_player_id != local_player_id:
			print("End player turn action rejected: not your turn (current: " + str(current_player_id) + ", local: " + str(local_player_id) + ")")
			return
		
		if not GameModeManager.is_my_turn():
			print("End player turn action rejected: not your turn in multiplayer")
			return
		
		# Submit end turn action through multiplayer system
		var action_data = {
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("end_turn", action_data):
			print("End player turn action submitted to multiplayer system")
			# The action will be processed when received back from network
		else:
			print("End player turn action rejected by multiplayer system")
		return
	
	# Local game logic (existing)
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
	# Only log mouse button events, not movement
	if event is InputEventMouseButton:
		print("UnitActionsPanel mouse button: " + str(event.button_index) + " pressed: " + str(event.pressed))

func _on_end_unit_turn_button_input(event: InputEvent) -> void:
	# Only log mouse button events, not movement
	if event is InputEventMouseButton:
		print("End Unit Turn button mouse: " + str(event.button_index) + " pressed: " + str(event.pressed))

func _on_cancel_pressed() -> void:
	"""Handle Cancel button press - deselect unit or exit movement mode"""
	if movement_mode:
		print("Canceling movement mode")
		_exit_movement_mode()
	elif selected_unit:
		GameEvents.unit_deselected.emit(selected_unit)

func _show_panel() -> void:
	"""Show the actions panel"""
	visible = true
	modulate.a = 1.0
	
	# Force a layout update
	await get_tree().process_frame
	
	# Try to resize to fit content
	_try_resize_to_content()

func _try_resize_to_content() -> void:
	"""Attempt to resize the panel to fit its content"""
	if not content_container:
		return
	
	# Get the minimum size needed for content
	var content_min_size = content_container.get_combined_minimum_size()
	
	# Add margin container padding
	if margin_container:
		var margin_left = margin_container.get_theme_constant("margin_left")
		var margin_right = margin_container.get_theme_constant("margin_right") 
		var margin_top = margin_container.get_theme_constant("margin_top")
		var margin_bottom = margin_container.get_theme_constant("margin_bottom")
		
		var needed_size = Vector2(
			content_min_size.x + margin_left + margin_right,
			content_min_size.y + margin_top + margin_bottom
		)
		
		# Try to set the size
		custom_minimum_size = needed_size
		size = needed_size
		
		# Force layout update
		await get_tree().process_frame

func _hide_panel() -> void:
	"""Hide the actions panel"""
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
			KEY_F5:
				print("F5 pressed - testing movement range calculation directly")
				_test_movement_range_calculation_direct()
			
			# Keyboard shortcuts for actions (only when panel is visible and unit selected)
			KEY_M:
				if visible and selected_unit:
					if movement_mode:
						print("M key pressed - canceling movement mode")
						_exit_movement_mode()
					else:
						print("M key pressed - triggering Move action")
						_on_move_pressed()
			KEY_E:
				if visible and selected_unit and not movement_mode:
					print("E key pressed - triggering End Unit Turn action")
					_on_end_unit_turn_pressed()
			KEY_P:
				if visible and selected_unit and not movement_mode:
					print("P key pressed - triggering End Player Turn action")
					_on_end_player_turn_pressed()
			KEY_S:
				if visible and selected_unit and not movement_mode:
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

func _test_movement_range_calculation_direct() -> void:
	"""Test movement range calculation directly"""
	print("=== Testing Movement Range Calculation Directly ===")
	
	# Find a unit to test with
	var scene_root = get_tree().current_scene
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				print("Found test unit: " + child.name)
				
				# Set this as selected unit temporarily
				selected_unit = child
				
				# Test movement range calculation
				print("Testing movement range calculation...")
				_calculate_and_show_movement_range()
				
				# Wait 3 seconds then clear
				await get_tree().create_timer(3.0).timeout
				_clear_movement_range()
				selected_unit = null
				return
	
	print("No units found for testing")

# Movement system implementation
func _enter_movement_mode() -> void:
	"""Enter movement mode - show movement range and wait for destination selection"""
	if not selected_unit:
		return
	
	print("=== Entering Movement Mode ===")
	movement_mode = true
	
	# Calculate and show movement range
	_calculate_and_show_movement_range()
	
	# Update UI to show movement mode
	_update_movement_ui()
	
	print("Movement mode active - select destination tile")

func _exit_movement_mode() -> void:
	"""Exit movement mode and return to normal selection"""
	print("=== Exiting Movement Mode ===")
	movement_mode = false
	movement_range_tiles.clear()
	
	# Clear movement range visualization
	GameEvents.movement_range_cleared.emit()
	
	# Update UI back to normal
	_update_actions()

func _calculate_and_show_movement_range() -> void:
	"""Calculate movement range and show visual indicators"""
	if not selected_unit:
		print("DEBUG: No selected unit for movement range calculation")
		return
	
	print("DEBUG: Calculating movement range for " + selected_unit.get_display_name())
	
	# Get unit's current position
	var grid = preload("res://board/Grid.tres")
	var unit_world_pos = selected_unit.global_position
	var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
	
	print("DEBUG: Unit world pos: " + str(unit_world_pos))
	print("DEBUG: Unit grid pos: " + str(unit_grid_pos))
	
	# Get movement range from unit
	var movement_range = selected_unit.get_movement_range()
	print("DEBUG: Movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("DEBUG: Movement range is 0 or negative, aborting")
		return
	
	# Calculate reachable tiles using BFS (similar to board.gd logic)
	movement_range_tiles = _calculate_reachable_tiles(unit_grid_pos, movement_range, grid)
	
	print("DEBUG: Calculated " + str(movement_range_tiles.size()) + " reachable tiles")
	
	if movement_range_tiles.size() == 0:
		print("DEBUG: No reachable tiles calculated, aborting")
		return
	
	# Show first few tiles for debugging
	for i in range(min(3, movement_range_tiles.size())):
		print("DEBUG: Reachable tile " + str(i) + ": " + str(movement_range_tiles[i]))
	
	# Emit event to show movement range visually
	print("DEBUG: Emitting movement_range_calculated signal with " + str(movement_range_tiles.size()) + " tiles")
	GameEvents.movement_range_calculated.emit(movement_range_tiles)
	print("DEBUG: Signal emitted")

func _calculate_reachable_tiles(start_pos: Vector3, max_distance: int, grid: Grid) -> Array[Vector3]:
	"""Calculate all tiles reachable within movement range using BFS"""
	print("DEBUG: BFS starting from " + str(start_pos) + " with max distance " + str(max_distance))
	
	var reachable: Array[Vector3] = []
	var queue: Array = [{pos = start_pos, distance = 0}]
	var visited: Dictionary = {start_pos: 0}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_pos = current.pos
		var current_distance = current.distance
		
		# Add adjacent tiles if within movement range
		if current_distance < max_distance:
			var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
			
			for direction in directions:
				var next_pos = current_pos + direction
				
				# Check if tile is valid and not visited
				if grid.is_within_bounds(next_pos) and not visited.has(next_pos):
					# Check if tile is passable (not occupied by another unit)
					if _is_tile_passable(next_pos):
						visited[next_pos] = current_distance + 1
						queue.append({pos = next_pos, distance = current_distance + 1})
						reachable.append(next_pos)
	
	print("DEBUG: BFS completed, found " + str(reachable.size()) + " reachable tiles")
	return reachable

func _is_tile_passable(grid_pos: Vector3) -> bool:
	"""Check if a tile is passable (not occupied by another unit)"""
	# Find all units in scene and check if any occupy this position
	var units = _find_all_units_in_scene()
	var grid = preload("res://board/Grid.tres")
	
	for unit in units:
		if unit == selected_unit:
			continue  # Skip the moving unit itself
		
		var unit_world_pos = unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
		
		# Check if positions match (with tolerance)
		if abs(unit_grid_pos.x - grid_pos.x) < 0.1 and abs(unit_grid_pos.z - grid_pos.z) < 0.1:
			return false  # Tile is occupied
	
	return true  # Tile is passable

func _find_all_units_in_scene() -> Array[Unit]:
	"""Find all units in the current scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func _update_movement_ui() -> void:
	"""Update UI to show movement mode state"""
	if move_button:
		move_button.text = "Moving...\n(Select Destination)"
		move_button.disabled = true
	
	if cancel_button:
		cancel_button.text = "Cancel Move (C/ESC)"
	
	# Show movement range info in unit summary if expanded
	if stats_expanded and selected_unit:
		var movement_range = selected_unit.get_movement_range()
		print("Movement mode active - unit can move " + str(movement_range) + " tiles")
		print("Highlighted " + str(movement_range_tiles.size()) + " reachable tiles")

func _on_cursor_selected(position: Vector3) -> void:
	"""Handle cursor selection - used for movement destination"""
	print("=== Cursor Selected ===")
	print("Selected position: " + str(position))
	
	# Check if we're in movement mode or if there's a movement range displayed
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			print("Movement range is showing - checking if position is valid destination")
			# Let the UnitActionsPanel handle the movement
			unit_actions_panel.handle_movement_destination_selected(position)
			return
	
	# If not in movement mode, handle normal selection
	if not movement_mode or not selected_unit:
		return
	
	print("Movement mode active - processing destination selection")
	
	# Check if position is within movement range
	if position in movement_range_tiles:
		print("Valid movement destination - executing move")
		_execute_movement(position)
	else:
		print("Invalid movement destination - not in range")

func _get_unit_actions_panel() -> Node:
	"""Get reference to UnitActionsPanel"""
	var scene_root = get_tree().current_scene
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		return ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	return null

func _execute_movement(destination: Vector3) -> void:
	"""Execute the actual unit movement"""
	if not selected_unit:
		return
	
	print("=== Executing Unit Movement ===")
	print("Moving " + selected_unit.get_display_name() + " to " + str(destination))
	
	# Get grid for position calculations
	var grid = preload("res://board/Grid.tres")
	var old_world_pos = selected_unit.global_position
	var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)
	
	# Calculate new world position
	var new_world_pos = grid.calculate_map_position(destination)
	# Preserve the unit's original Y height (units are at Y=1.5)
	new_world_pos.y = selected_unit.global_position.y
	
	# Animate the unit movement
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)
	
	print("Unit moved from " + str(old_grid_pos) + " to " + str(destination))
	
	# Emit movement event
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)
	
	# Mark unit as having acted
	_complete_movement_action()
	
	# Exit movement mode
	_exit_movement_mode()

func _animate_unit_movement(unit: Unit, from_pos: Vector3, to_pos: Vector3) -> void:
	"""Animate unit movement with a smooth tween"""
	if not unit:
		return
	
	print("Animating movement from " + str(from_pos) + " to " + str(to_pos))
	
	# Create a tween for smooth movement
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUART)
	
	# Animate the movement over 0.5 seconds
	tween.tween_property(unit, "global_position", to_pos, 0.5)
	
	# Optional: Add a small bounce effect
	tween.tween_callback(_on_movement_animation_complete.bind(unit))

func _complete_movement_action() -> void:
	"""Complete the movement action and update turn system"""
	if not selected_unit:
		return
	
	print("=== Completing Movement Action ===")
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if unit_owner and owner_player_id == local_player_id:
			# Submit movement completion action through multiplayer system
			var action_data = {
				"unit_id": selected_unit.get_display_name(),
				"player_id": local_player_id,
				"from_position": selected_unit.global_position,
				"to_position": selected_unit.global_position  # Current position after move
			}
			
			if GameModeManager.submit_action("unit_move_complete", action_data):
				print("Movement completion action submitted to multiplayer system")
			else:
				print("Movement completion action rejected by multiplayer system")
		
		# Still do local processing for immediate feedback
	
	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		
		if turn_system is TraditionalTurnSystem:
			print("Marking unit acted (Traditional)")
			(turn_system as TraditionalTurnSystem).mark_unit_acted(selected_unit)
		elif turn_system is SpeedFirstTurnSystem:
			print("Marking unit acted (Speed First)")
			(turn_system as SpeedFirstTurnSystem).mark_unit_acted(selected_unit)
	
	# Mark unit action completed
	selected_unit.mark_action_completed("move")
	
	# Emit action completed signal
	GameEvents.unit_action_completed.emit(selected_unit, "move")
	
	# Force update unit visuals
	var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		print("Updating unit visuals via UnitVisualManager")
		visual_manager.update_all_unit_visuals()
	
	print("Movement action completed")

func _on_movement_animation_complete(unit: Unit) -> void:
	"""Called when movement animation finishes"""
	print("Movement animation completed for " + unit.get_display_name())

# Fire Emblem style movement handling
func is_showing_movement_range() -> bool:
	"""Check if movement range is currently displayed"""
	var showing = movement_range_tiles.size() > 0
	print("DEBUG: is_showing_movement_range() = " + str(showing) + " (tiles: " + str(movement_range_tiles.size()) + ")")
	return showing

func handle_movement_destination_selected(destination: Vector3) -> void:
	"""Handle selection of a movement destination (Fire Emblem style)"""
	print("DEBUG: handle_movement_destination_selected called with destination: " + str(destination))
	
	if not selected_unit:
		print("DEBUG: No unit selected for movement")
		return
	
	print("DEBUG: Selected unit: " + selected_unit.get_display_name())
	print("DEBUG: Available movement tiles: " + str(movement_range_tiles.size()))
	
	# Check if destination is in movement range
	var is_valid_destination = false
	for tile in movement_range_tiles:
		if abs(tile.x - destination.x) < 0.1 and abs(tile.z - destination.z) < 0.1:
			is_valid_destination = true
			print("DEBUG: Found matching tile: " + str(tile) + " for destination: " + str(destination))
			break
	
	print("DEBUG: Is valid destination: " + str(is_valid_destination))
	
	if is_valid_destination:
		print("DEBUG: Valid destination - executing movement")
		
		# Validate with turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system.validate_turn_action(selected_unit, "move"):
				_execute_movement_to_destination(destination)
			else:
				print("DEBUG: Movement not allowed by turn system")
		else:
			_execute_movement_to_destination(destination)
	else:
		print("DEBUG: Invalid destination - not in movement range")
		# Could play error sound or show message here

func _execute_movement_to_destination(destination: Vector3) -> void:
	"""Execute movement to destination (Fire Emblem style)"""
	if not selected_unit:
		return
	
	print("=== Executing Movement to Destination ===")
	print("Moving " + selected_unit.get_display_name() + " to " + str(destination))
	
	# Get grid for position calculations
	var grid = preload("res://board/Grid.tres")
	var old_world_pos = selected_unit.global_position
	var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)
	
	# Calculate new world position
	var new_world_pos = grid.calculate_map_position(destination)
	# Preserve the unit's original Y height (units are at Y=1.5)
	new_world_pos.y = selected_unit.global_position.y
	
	# Clear movement range first
	_clear_movement_range()
	
	# Animate the unit movement
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)
	
	print("Unit moved from " + str(old_grid_pos) + " to " + str(destination))
	
	# Emit movement event
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)
	
	# Mark unit as having acted
	_complete_movement_action()
	
	# Update UI to reflect unit has moved
	_update_actions()

# Move System Implementation
func _setup_move_system() -> void:
	"""Initialize the move system"""
	# Create move selection panel
	move_selection_panel = MoveSelectionPanel.new()
	add_child(move_selection_panel)
	
	# Connect move selection signals
	move_selection_panel.move_selected.connect(_on_move_selected)
	move_selection_panel.move_cancelled.connect(_on_move_cancelled)
	
	# Create moves button and add it to the actions container
	moves_button = Button.new()
	moves_button.text = "MOVES"
	moves_button.custom_minimum_size = Vector2(120, 40)
	moves_button.pressed.connect(_on_moves_pressed)
	
	# Add moves button to the actions container (after move button)
	var actions_container = get_node_or_null("MarginContainer/ContentContainer/ActionsContainer")
	if actions_container:
		# Insert after move button
		var move_button_index = -1
		for i in range(actions_container.get_child_count()):
			if actions_container.get_child(i) == move_button:
				move_button_index = i
				break
		
		if move_button_index >= 0:
			actions_container.add_child(moves_button)
			actions_container.move_child(moves_button, move_button_index + 1)
		else:
			actions_container.add_child(moves_button)
	
	print("Move system initialized")

func _on_moves_pressed() -> void:
	"""Handle Moves button press"""
	if not selected_unit:
		return
	
	print("Moves button pressed for " + selected_unit.name)
	
	# Check if unit has MoveManager
	var move_manager = selected_unit.get_node_or_null("MoveManager")
	if not move_manager:
		print("Unit has no MoveManager - creating default moves")
		_create_default_moves_for_unit(selected_unit)
		move_manager = selected_unit.get_node_or_null("MoveManager")
	
	if move_manager:
		# Show move selection panel
		move_selection_panel.show_moves_for_unit(selected_unit)
	else:
		print("Failed to create MoveManager for unit")

func _on_move_selected(move_index: int) -> void:
	"""Handle move selection from the move panel"""
	if not selected_unit:
		return
	
	var move_manager = selected_unit.get_node_or_null("MoveManager")
	if not move_manager:
		return
	
	selected_move_index = move_index
	var move = move_manager.moves[move_index]
	
	print("Move selected: " + move.name + " (index: " + str(move_index) + ")")
	
	# Check if move requires a target
	if move.range > 0:
		# Enter move targeting mode
		move_mode = true
		_show_move_targeting(move)
	else:
		# Self-target move, execute immediately
		_execute_move_on_target(selected_unit)

func _on_move_cancelled() -> void:
	"""Handle move selection cancellation"""
	selected_move_index = -1
	move_mode = false
	print("Move selection cancelled")

func _show_move_targeting(move: Move) -> void:
	"""Show targeting interface for a move"""
	print("Showing targeting for move: " + move.name)
	print("Range: " + str(move.range))
	
	# Calculate valid targets based on move range
	var valid_targets = _calculate_move_targets(move)
	
	if valid_targets.is_empty():
		print("No valid targets for move")
		move_mode = false
		selected_move_index = -1
		return
	
	# For now, just show a message - in a full implementation you'd highlight valid targets
	print("Select a target within range " + str(move.range))
	print("Valid targets: " + str(valid_targets.size()))

func _calculate_move_targets(move: Move) -> Array[Node]:
	"""Calculate valid targets for a move"""
	var targets: Array[Node] = []
	
	if not selected_unit:
		return targets
	
	var caster_pos = selected_unit.global_position
	var all_units = _find_all_units_in_scene()
	
	for unit in all_units:
		var target_pos = unit.global_position
		
		# Check if target is within range
		if move.can_target(caster_pos, target_pos):
			# For damage moves, only target enemies
			# For heal/buff moves, only target allies
			# For now, allow all targets
			targets.append(unit)
	
	return targets

func _execute_move_on_target(target: Node) -> void:
	"""Execute the selected move on the target"""
	if not selected_unit or selected_move_index < 0:
		return
	
	var move_manager = selected_unit.get_node_or_null("MoveManager")
	if not move_manager:
		return
	
	print("Executing move on target: " + target.name)
	
	# Execute the move
	var result = move_manager.use_move(selected_move_index, target)
	
	# Show result message
	if result.success:
		print("Move executed successfully: " + result.message)
		
		# Update UI to reflect move usage
		_update_actions()
		
		# Update move selection panel if it's still visible
		if move_selection_panel.visible:
			move_selection_panel.update_move_cooldowns()
	else:
		print("Move failed: " + result.message)
	
	# Exit move mode
	move_mode = false
	selected_move_index = -1

func _create_default_moves_for_unit(unit: Node) -> void:
	"""Create default moves for a unit that doesn't have any"""
	# Add MoveManager component
	var move_manager = MoveManager.new()
	unit.add_child(move_manager)
	
	# Determine unit type and add appropriate moves
	var unit_name = unit.name.to_lower()
	var moves: Array[Move] = []
	
	if "warrior" in unit_name:
		moves = MoveFactory.get_warrior_moves()
	elif "archer" in unit_name:
		moves = MoveFactory.get_archer_moves()
	elif "mage" in unit_name:
		moves = MoveFactory.get_mage_moves()
	else:
		# Default moves for unknown unit types
		moves = [
			MoveFactory.create_basic_attack(),
			MoveFactory.create_heal(),
			MoveFactory.create_shield_wall()
		]
	
	# Add moves to the unit
	for move in moves:
		move_manager.add_move(move)
	
	print("Created default moves for " + unit.name + ": " + str(moves.size()) + " moves")

func _update_moves_button_availability() -> void:
	"""Update the availability of the moves button"""
	if not moves_button or not selected_unit:
		return
	
	var move_manager = selected_unit.get_node_or_null("MoveManager")
	if not move_manager:
		moves_button.disabled = false  # Will create default moves
		moves_button.text = "MOVES"
		return
	
	# Check if any moves are available
	var available_moves = move_manager.get_available_moves()
	moves_button.disabled = available_moves.is_empty()
	
	if available_moves.is_empty():
		moves_button.text = "MOVES (All on cooldown)"
	else:
		moves_button.text = "MOVES (" + str(available_moves.size()) + " available)"
