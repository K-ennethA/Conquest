extends Control

class_name TurnSystemIndicator

# UI indicator showing current turn system and turn information

@onready var turn_system_label: Label = $VBoxContainer/TurnSystemLabel
@onready var current_turn_label: Label = $VBoxContainer/CurrentTurnLabel
@onready var current_player_label: Label = $VBoxContainer/CurrentPlayerLabel

func _ready() -> void:
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		TurnSystemManager.turn_system_deactivated.connect(_on_turn_system_deactivated)
	
	# Connect to player events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_started)
		PlayerManager.player_turn_ended.connect(_on_player_turn_ended)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	
	# Initial update
	_update_display()

func _update_display() -> void:
	"""Update the display with current turn system and turn information"""
	# Update turn system info
	if turn_system_label:
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			turn_system_label.text = "Turn System: " + turn_system.system_name
		else:
			turn_system_label.text = "Turn System: None"
	
	# Update current turn info
	if current_turn_label:
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system is SpeedFirstTurnSystem:
				current_turn_label.text = "Round: " + str(turn_system.current_turn)
			else:
				current_turn_label.text = "Turn: " + str(turn_system.current_turn)
		else:
			current_turn_label.text = "Turn: -"
	
	# Update current player/unit info
	if current_player_label:
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			
			if turn_system is SpeedFirstTurnSystem:
				var speed_system = turn_system as SpeedFirstTurnSystem
				var current_unit = speed_system.get_current_acting_unit()
				if current_unit:
					var owner = speed_system.get_current_active_player()
					var owner_name = owner.get_display_name() if owner else "Unknown"
					current_player_label.text = "Acting: " + current_unit.get_display_name() + " (" + owner_name + ")"
				else:
					current_player_label.text = "Acting: None"
			else:
				var current_player = turn_system.get_current_active_player()
				if current_player:
					current_player_label.text = "Current Player: " + current_player.get_display_name()
				else:
					current_player_label.text = "Current Player: None"
		else:
			var current_player = PlayerManager.get_current_player() if PlayerManager else null
			if current_player:
				current_player_label.text = "Current Player: " + current_player.get_display_name()
			else:
				current_player_label.text = "Current Player: None"

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	_update_display()

func _on_turn_system_deactivated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system deactivation"""
	_update_display()

func _on_player_turn_started(player: Player) -> void:
	"""Handle player turn start"""
	_update_display()

func _on_player_turn_ended(player: Player) -> void:
	"""Handle player turn end"""
	_update_display()

func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	_update_display()