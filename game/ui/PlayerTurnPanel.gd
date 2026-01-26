extends Control

class_name PlayerTurnPanel

# UI panel for player-wide turn actions (End Turn, etc.)
# Always visible during gameplay to show current player and allow ending turn

@onready var player_name_label: Label = $MarginContainer/VBoxContainer/PlayerNameLabel
@onready var turn_info_label: Label = $MarginContainer/VBoxContainer/TurnInfoLabel
@onready var end_turn_button: Button = $MarginContainer/VBoxContainer/EndTurnButton

var current_player: Player = null

func _ready() -> void:
	print("PlayerTurnPanel _ready() called")
	
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	
	# Connect button signal
	if end_turn_button:
		end_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_turn_button.pressed.connect(_on_end_turn_pressed)
		print("End Turn button connected")
	else:
		print("ERROR: End Turn button not found!")
	
	# Initial update
	_update_display()
	print("PlayerTurnPanel initialized")

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	# Connect to turn system specific events
	if turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.disconnect(_on_turn_started)
	if turn_system.turn_ended.is_connected(_on_turn_ended):
		turn_system.turn_ended.disconnect(_on_turn_ended)
	
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)
	
	_update_display()

func _on_turn_started(player: Player) -> void:
	"""Handle turn start"""
	current_player = player
	_update_display()

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end"""
	_update_display()

func _on_player_turn_changed(player: Player) -> void:
	"""Handle player turn changes"""
	current_player = player
	_update_display()

func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	_update_display()

func _update_display() -> void:
	"""Update the display with current player and turn information"""
	if not player_name_label or not turn_info_label or not end_turn_button:
		return
	
	# Get current player
	var active_player = null
	if TurnSystemManager.has_active_turn_system():
		active_player = TurnSystemManager.get_current_active_player()
	elif PlayerManager:
		active_player = PlayerManager.get_current_player()
	
	if active_player:
		current_player = active_player
		
		# Update player name
		player_name_label.text = active_player.get_display_name() + "'s Turn"
		
		# Update turn info based on turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			
			if turn_system is TraditionalTurnSystem:
				var trad_system = turn_system as TraditionalTurnSystem
				var progress = trad_system.get_current_turn_progress()
				if progress.has("units_can_act"):
					turn_info_label.text = "Turn " + str(turn_system.current_turn) + " - " + str(progress.units_can_act) + " units remaining"
				else:
					turn_info_label.text = "Turn " + str(turn_system.current_turn)
			else:
				turn_info_label.text = "Turn " + str(turn_system.current_turn)
		else:
			turn_info_label.text = "Turn in progress"
		
		# Update End Turn button
		var can_end_turn = false
		
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system is TraditionalTurnSystem:
				can_end_turn = (turn_system as TraditionalTurnSystem).can_end_turn_manually()
			elif turn_system is SpeedFirstTurnSystem:
				can_end_turn = (turn_system as SpeedFirstTurnSystem).can_end_turn_manually()
		else:
			can_end_turn = active_player and active_player.can_end_turn()
		
		end_turn_button.disabled = not can_end_turn
		
		if can_end_turn:
			end_turn_button.text = "End " + active_player.get_display_name() + "'s Turn"
		else:
			end_turn_button.text = "Cannot End Turn"
		
		# Show the panel
		visible = true
	else:
		# No active player
		player_name_label.text = "Game Setup"
		turn_info_label.text = "Waiting for players..."
		end_turn_button.text = "No Active Player"
		end_turn_button.disabled = true
		visible = true

func _on_end_turn_pressed() -> void:
	"""Handle End Turn button press - ends the entire player's turn"""
	print("=== PLAYER END TURN BUTTON PRESSED ===")
	print("Ending entire turn for player: " + (current_player.get_display_name() if current_player else "None"))
	
	var turn_ended = false
	
	# Use turn system if available
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Using turn system: " + turn_system.system_name)
		
		if turn_system is TraditionalTurnSystem:
			print("Ending turn manually (Traditional)")
			turn_ended = (turn_system as TraditionalTurnSystem).end_turn_manually()
		elif turn_system is SpeedFirstTurnSystem:
			print("Ending turn manually (Speed First)")
			turn_ended = (turn_system as SpeedFirstTurnSystem).end_turn_manually()
		else:
			print("Advancing turn (Generic)")
			TurnSystemManager.advance_turn()
			turn_ended = true
	elif PlayerManager:
		print("Using PlayerManager fallback")
		# Fallback to PlayerManager
		PlayerManager.end_current_player_turn()
		turn_ended = true
	else:
		print("No turn system or PlayerManager available")
	
	if turn_ended:
		print("Player turn ended successfully")
	else:
		print("Failed to end player turn")
	
	print("=== PLAYER END TURN PROCESSING COMPLETE ===")

# Public interface
func get_current_player() -> Player:
	"""Get the currently displayed player"""
	return current_player

# Debug method for testing
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_P:
				if current_player:
					print("P key pressed - triggering Player End Turn action")
					_on_end_turn_pressed()