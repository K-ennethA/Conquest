extends Control

class_name UnitActionsPanel

# UI panel for unit actions (Move, End Turn, etc.)
# Only appears when a unit is selected (not hovered)

@onready var move_button: Button = $MarginContainer/VBoxContainer/ActionsContainer/MoveButton
@onready var end_turn_button: Button = $MarginContainer/VBoxContainer/ActionsContainer/EndTurnButton
@onready var cancel_button: Button = $MarginContainer/VBoxContainer/CancelButton

var selected_unit: Unit = null

func _ready() -> void:
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	
	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	
	# Connect button signals
	if move_button:
		move_button.pressed.connect(_on_move_pressed)
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if cancel_button:
		cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Hide panel initially
	_hide_panel()

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - show actions for selected unit"""
	# Only show if this is the current player's unit
	if not PlayerManager.can_current_player_select_unit(unit):
		return
	
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
	
	# Update Move button
	if move_button:
		var can_move = can_control and selected_unit.can_act()
		move_button.disabled = not can_move
		
		if can_move:
			move_button.text = "Move (" + str(selected_unit.get_stat("movement")) + " tiles)"
		else:
			move_button.text = "Move (unavailable)"
	
	# Update End Turn button
	if end_turn_button:
		var can_end_turn = current_player and current_player.can_end_turn() and game_active
		end_turn_button.disabled = not can_end_turn
		
		if current_player:
			end_turn_button.text = "End " + current_player.get_display_name() + "'s Turn"
		else:
			end_turn_button.text = "End Turn"
	
	# Cancel button is always available when unit is selected
	if cancel_button:
		cancel_button.disabled = false

func _on_move_pressed() -> void:
	"""Handle Move button press"""
	if not selected_unit:
		return
	
	print("Move action for unit: " + selected_unit.get_display_name())
	
	# TODO: Implement movement system
	# For now, just mark the unit as having acted
	if selected_unit.owner_player:
		selected_unit.owner_player.mark_unit_acted(selected_unit)
		selected_unit.mark_action_completed("move")
	
	# Update actions to reflect the unit has acted
	_update_actions()
	
	print("Unit has moved and used their action for this turn")

func _on_end_turn_pressed() -> void:
	"""Handle End Turn button press"""
	if PlayerManager:
		PlayerManager.end_current_player_turn()

func _on_cancel_pressed() -> void:
	"""Handle Cancel button press - deselect unit"""
	if selected_unit:
		GameEvents.unit_deselected.emit(selected_unit)

func _show_panel() -> void:
	"""Show the actions panel"""
	visible = true
	modulate.a = 1.0

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