extends Control

class_name PlayerTurnPanel

# UI panel for player-wide turn actions (End Turn, etc.)
# Always visible during gameplay to show current player and allow ending turn

@onready var player_name_label: Label = $MarginContainer/VBoxContainer/PlayerNameLabel
@onready var turn_info_label: Label = $MarginContainer/VBoxContainer/TurnInfoLabel
@onready var end_turn_button: Button = $MarginContainer/VBoxContainer/EndTurnButton

var current_player: Player = null

# Safety-net watcher state (see _process): guarantees this panel tracks the active
# turn system even if the one-shot turn_system_activated signal is missed due to
# activation timing (which otherwise froze the display on its fallback text).
var _watched_system: TurnSystemBase = null
var _last_seen_player: Player = null

func _ready() -> void:
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
	else:
		push_error("End Turn button not found!")
	
	# Match the amber HUD look (this panel lives outside GameUILayout, so it
	# themes itself).
	ConquestTheme.apply_to(self)

	# Wire to an already-active turn system so we don't miss the one-shot
	# activation signal (which would freeze the display on the first player).
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

	# Initial update
	_update_display()

func _process(_delta: float) -> void:
	"""Reconcile with the active turn system each frame, acting only on a real change.
	Backstops the turn_system_activated / turn_started signals so the panel reliably
	shows and updates the current player even when activation timing hides those
	one-shot signals."""
	if not TurnSystemManager:
		return

	var sys: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	if sys != _watched_system:
		_watched_system = sys
		if sys:
			_on_turn_system_activated(sys)
		return

	if sys == null:
		return

	var active: Player = sys.get_current_active_player()
	if active != _last_seen_player:
		_last_seen_player = active
		_update_display()

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	# Connect to turn system specific events
	if turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.disconnect(_on_turn_started)
	if turn_system.turn_ended.is_connected(_on_turn_ended):
		turn_system.turn_ended.disconnect(_on_turn_ended)
	
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)

	# Keep the watcher baseline in sync so it only fires on genuine future changes.
	_watched_system = turn_system
	_last_seen_player = turn_system.get_current_active_player()

	_update_display()

func _on_turn_started(player: Player) -> void:
	"""Handle turn start"""
	current_player = player
	_last_seen_player = player
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

func _turn_title(player: Player) -> String:
	"""Ally/enemy framing for the panel -- reads better than "Player 1/2" in
	single-player. Keyed off Player.is_ai."""
	if player != null and player.is_ai:
		return "Enemy Turn"
	return "Your Turn"

func _update_display() -> void:
	"""Update the display with current player and turn information"""
	if not player_name_label or not turn_info_label or not end_turn_button:
		return
	
	# Get current player - prioritize TurnSystemManager over PlayerManager
	var active_player = null
	if TurnSystemManager.has_active_turn_system():
		active_player = TurnSystemManager.get_current_active_player()
	
	# Fallback to PlayerManager only if TurnSystemManager doesn't have an active player
	if not active_player and PlayerManager:
		active_player = PlayerManager.get_current_player()
	
	if active_player:
		current_player = active_player

		# Update player name -- ally/enemy framing reads better than "Player 1/2"
		# in single-player (keyed off Player.is_ai).
		player_name_label.text = _turn_title(active_player)
		
		# Update turn info based on turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			
			if turn_system is TraditionalTurnSystem:
				var trad_system = turn_system as TraditionalTurnSystem
				var progress = trad_system.get_current_turn_progress()
				if progress.has("units_can_act"):
					turn_info_label.text = "Round " + str(turn_system.current_turn) + " - " + str(progress.units_can_act) + " units remaining"
				else:
					turn_info_label.text = "Round " + str(turn_system.current_turn)
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
			end_turn_button.text = ("End Enemy Turn" if active_player.is_ai else "End Your Turn")
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
	var turn_ended = false

	# Use turn system if available
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()

		if turn_system is TraditionalTurnSystem:
			turn_ended = (turn_system as TraditionalTurnSystem).end_turn_manually()
		elif turn_system is SpeedFirstTurnSystem:
			turn_ended = (turn_system as SpeedFirstTurnSystem).end_turn_manually()
		else:
			TurnSystemManager.advance_turn()
			turn_ended = true
	elif PlayerManager:
		# Fallback to PlayerManager
		PlayerManager.end_current_player_turn()
		turn_ended = true

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
					_on_end_turn_pressed()