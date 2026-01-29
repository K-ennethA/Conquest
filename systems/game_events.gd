extends Node

# Centralized event bus for game-wide communication
# This singleton manages all game events to reduce coupling between systems

signal unit_selected(unit: Unit, position: Vector3)
signal unit_deselected(unit: Unit)
signal unit_hover_started(unit: Unit)
signal unit_hover_ended(unit: Unit)
signal unit_moved(unit: Unit, from_position: Vector3, to_position: Vector3)
signal tile_highlighted(position: Vector3)
signal tile_unhighlighted(position: Vector3)
signal turn_started(unit: Unit)
signal turn_ended(unit: Unit)
signal cursor_moved(position: Vector3)
signal cursor_selected(position: Vector3)

# Movement and validation events
signal movement_range_calculated(positions: Array[Vector3])
signal movement_range_cleared()
signal movement_validated(from_position: Vector3, to_position: Vector3, is_valid: bool)

# UI events
signal ui_unit_info_requested(unit: Unit)
signal ui_action_menu_requested(unit: Unit, actions: Array)

# Combat events
signal combat_initiated(attacker: Unit, defender: Unit)
signal damage_dealt(attacker: Unit, defender: Unit, damage: int)
signal unit_eliminated(unit: Unit, eliminator: Unit)

# Player management events
signal player_turn_started(player: Player)
signal player_turn_ended(player: Player)
signal player_eliminated(player: Player)
signal game_started()
signal game_ended(winner: Player)
signal unit_action_completed(unit: Unit, action_type: String)

func _ready() -> void:
	# Make this a singleton
	name = "GameEvents"
