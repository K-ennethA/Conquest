extends Control

class_name TurnIndicator

# Prominent UI element showing whose turn it is and turn transitions

@onready var player_name_label: Label = $CenterContainer/VBoxContainer/PlayerNameLabel
@onready var turn_info_label: Label = $CenterContainer/VBoxContainer/TurnInfoLabel
@onready var transition_label: Label = $CenterContainer/VBoxContainer/TransitionLabel
@onready var background_panel: Panel = $BackgroundPanel

var current_player: Player = null
var is_transitioning: bool = false

# Player colors for background
var player_colors = {
	0: Color(0.2, 0.4, 0.8, 0.8),  # Blue - Player 1
	1: Color(0.8, 0.2, 0.2, 0.8),  # Red - Player 2
	2: Color(0.2, 0.8, 0.2, 0.8),  # Green - Player 3
	3: Color(0.8, 0.8, 0.2, 0.8),  # Yellow - Player 4
}

func _ready() -> void:
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		print("TurnIndicator: Connected to TurnSystemManager")
	
	# Initial update
	_update_display()
	print("TurnIndicator: Initialized")

func _update_display() -> void:
	"""Update the turn indicator display"""
	if not player_name_label or not turn_info_label:
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
					turn_info_label.text = "Turn " + str(turn_system.current_turn) + " - calculating..."
			elif turn_system is SpeedFirstTurnSystem:
				var speed_system = turn_system as SpeedFirstTurnSystem
				var acting_unit = speed_system.get_current_acting_unit()
				if acting_unit:
					turn_info_label.text = "Round " + str(turn_system.current_turn) + " - " + acting_unit.get_display_name() + " acting"
				else:
					turn_info_label.text = "Round " + str(turn_system.current_turn)
			else:
				turn_info_label.text = "Turn " + str(turn_system.current_turn)
		else:
			turn_info_label.text = "Turn in progress"
		
		# Update background color
		_update_background_color(active_player)
		
		# Show the indicator
		visible = true
	else:
		# No active player
		player_name_label.text = "Game Setup"
		turn_info_label.text = "Waiting for players..."
		_update_background_color(null)
		visible = true

func _update_background_color(player: Player) -> void:
	"""Update background color based on current player"""
	if not background_panel:
		return
	
	var style_box = StyleBoxFlat.new()
	
	if player and player.player_id in player_colors:
		style_box.bg_color = player_colors[player.player_id]
	else:
		style_box.bg_color = Color(0.3, 0.3, 0.3, 0.8)  # Default gray
	
	style_box.corner_radius_top_left = 12
	style_box.corner_radius_top_right = 12
	style_box.corner_radius_bottom_left = 12
	style_box.corner_radius_bottom_right = 12
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	style_box.border_color = Color.WHITE
	
	background_panel.add_theme_stylebox_override("panel", style_box)

func show_turn_transition(from_player: Player, to_player: Player) -> void:
	"""Show turn transition animation"""
	if not transition_label:
		return
	
	is_transitioning = true
	
	# Show transition message
	if from_player and to_player:
		transition_label.text = from_player.get_display_name() + " → " + to_player.get_display_name()
	elif to_player:
		transition_label.text = "Starting " + to_player.get_display_name() + "'s Turn"
	else:
		transition_label.text = "Turn Transition"
	
	transition_label.visible = true
	
	# Animate the transition
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Fade in transition
	transition_label.modulate.a = 0.0
	tween.tween_property(transition_label, "modulate:a", 1.0, 0.3)
	
	# Scale effect
	transition_label.scale = Vector2(0.8, 0.8)
	tween.tween_property(transition_label, "scale", Vector2(1.0, 1.0), 0.3)
	
	# Wait and fade out
	await tween.finished
	await get_tree().create_timer(1.5).timeout
	
	var fade_tween = create_tween()
	fade_tween.tween_property(transition_label, "modulate:a", 0.0, 0.5)
	await fade_tween.finished
	
	transition_label.visible = false
	is_transitioning = false
	
	# Update display for new player
	_update_display()

# Event handlers
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	print("TurnIndicator: Turn system activated - " + turn_system.system_name)
	
	# Disconnect from previous turn system if any
	if turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.disconnect(_on_turn_started)
	if turn_system.turn_ended.is_connected(_on_turn_ended):
		turn_system.turn_ended.disconnect(_on_turn_ended)
	
	# Connect to new turn system events
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)
	
	print("TurnIndicator: Connected to turn system events")
	_update_display()

func _on_turn_started(player: Player) -> void:
	"""Handle turn start"""
	print("TurnIndicator: Turn started for " + player.get_display_name())
	
	if current_player != player:
		print("TurnIndicator: Showing transition from " + (current_player.get_display_name() if current_player else "None") + " to " + player.get_display_name())
		show_turn_transition(current_player, player)
	else:
		print("TurnIndicator: Same player, just updating display")
		_update_display()

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end"""
	print("TurnIndicator: Turn ended for " + player.get_display_name())
	_update_display()

func _on_player_turn_started(player: Player) -> void:
	"""Handle player turn start from PlayerManager"""
	_on_turn_started(player)

func _on_player_turn_ended(player: Player) -> void:
	"""Handle player turn end from PlayerManager"""
	_on_turn_ended(player)

func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	_update_display()

# Public interface
func get_current_player() -> Player:
	"""Get the currently displayed player"""
	return current_player

func is_showing_transition() -> bool:
	"""Check if transition animation is playing"""
	return is_transitioning