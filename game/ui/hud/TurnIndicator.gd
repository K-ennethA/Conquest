extends Control

class_name TurnIndicator

# Prominent UI element showing whose turn it is and turn transitions

@onready var player_name_label: Label = $CenterContainer/VBoxContainer/PlayerNameLabel
@onready var turn_info_label: Label = $CenterContainer/VBoxContainer/TurnInfoLabel
@onready var transition_label: Label = $CenterContainer/VBoxContainer/TransitionLabel
@onready var background_panel: Panel = $BackgroundPanel

var current_player: Player = null
var is_transitioning: bool = false

# Safety-net watcher state (see _process): the turn system may activate on a frame
# the panel never observes, so the one-shot turn_system_activated signal can be
# missed and the banner freezes on its fallback text. We poll the manager and
# reconcile on any actual change, so the banner reliably tracks the current player.
var _watched_system: TurnSystemBase = null
var _last_seen_player: Player = null

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

	# Delay initial update to ensure turn system is fully initialized
	await get_tree().process_frame

	# If a turn system is ALREADY active (it usually is by the time the HUD
	# loads), wire up to it now -- otherwise we'd miss the one-shot
	# turn_system_activated signal and never hear turn_started, leaving the
	# banner frozen on the first player.
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		_on_turn_system_activated(TurnSystemManager.get_active_turn_system())
	else:
		_update_display()
	print("TurnIndicator: Initialized")

func _process(_delta: float) -> void:
	"""Reconcile the banner with the active turn system every frame, but only ACT on
	a real change. This guarantees the banner shows and updates the current player
	even when the turn_system_activated / turn_started signals are missed due to
	activation timing (the original freeze-on-'Turn in progress' bug)."""
	if not TurnSystemManager:
		return

	var sys: TurnSystemBase = TurnSystemManager.get_active_turn_system()

	# The active system changed (activated, switched, or deactivated) since we last
	# looked -- (re)wire to it and refresh once.
	if sys != _watched_system:
		_watched_system = sys
		if sys:
			_on_turn_system_activated(sys)
		return

	# Speed First is owned by the TurnQueue; this banner stays hidden for it.
	if sys == null or sys is SpeedFirstTurnSystem:
		return

	# Same system, but the current player advanced -- run the normal turn-start path.
	var active: Player = sys.get_current_active_player()
	if active != _last_seen_player:
		_on_turn_started(active)

func _update_display() -> void:
	"""Update the turn indicator display"""
	if not player_name_label or not turn_info_label:
		return
	
	# Get current player - prioritize TurnSystemManager over PlayerManager
	var active_player = null
	if TurnSystemManager.has_active_turn_system():
		active_player = TurnSystemManager.get_current_active_player()
		print("TurnIndicator: Got active player from TurnSystemManager: " + (active_player.get_display_name() if active_player else "None"))
	
	# Fallback to PlayerManager only if TurnSystemManager doesn't have an active player
	if not active_player and PlayerManager:
		active_player = PlayerManager.get_current_player()
		print("TurnIndicator: Fallback to PlayerManager current player: " + (active_player.get_display_name() if active_player else "None"))
	
	if active_player:
		current_player = active_player
		
		# Update display based on turn system type
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			print("TurnIndicator: Updating display for " + active_player.get_display_name() + " with turn system " + turn_system.system_name)
			
			if turn_system is TraditionalTurnSystem:
				_update_traditional_display(turn_system, active_player)
			elif turn_system is SpeedFirstTurnSystem:
				_update_speed_first_display(turn_system, active_player)
			else:
				_update_generic_display(turn_system, active_player)
		else:
			print("TurnIndicator: No active turn system, using fallback display")
			_update_fallback_display(active_player)
		
		# Update background color
		_update_background_color(active_player)
		
		# Show the indicator
		visible = true
	else:
		# No active player
		print("TurnIndicator: No active player found")
		player_name_label.text = "Game Setup"
		turn_info_label.text = "Waiting for players..."
		_update_background_color(null)
		visible = true

func _update_traditional_display(turn_system: TraditionalTurnSystem, active_player: Player) -> void:
	"""Update display for Traditional Turn System"""
	player_name_label.text = active_player.get_display_name() + "'s Turn"
	
	var progress = turn_system.get_current_turn_progress()
	if progress.has("units_can_act"):
		turn_info_label.text = "Round " + str(turn_system.current_turn) + " - " + str(progress.units_can_act) + " units remaining"
	else:
		turn_info_label.text = "Round " + str(turn_system.current_turn) + " - calculating..."

func _update_speed_first_display(turn_system: SpeedFirstTurnSystem, active_player: Player) -> void:
	"""Update display for Speed First Turn System"""
	var acting_unit = turn_system.get_current_acting_unit()
	var progress = turn_system.get_current_round_progress()
	
	if acting_unit:
		# Show current acting unit
		player_name_label.text = acting_unit.get_display_name() + " Acting"
		
		# Show round info and speed
		var speed_info = ""
		if progress.has("current_unit_speed"):
			speed_info = " (Speed: " + str(progress.current_unit_speed) + ")"
		
		var remaining_info = ""
		if progress.has("units_remaining"):
			remaining_info = " - " + str(progress.units_remaining) + " units left"
		
		turn_info_label.text = "Round " + str(progress.get("round_number", 1)) + speed_info + remaining_info
		
		# Add queue preview info
		var queue_preview = progress.get("turn_queue_preview", [])
		if queue_preview.size() > 1:  # More than just current unit
			var next_unit = queue_preview[1]  # Next unit after current
			turn_info_label.text += "\nNext: " + next_unit.get("name", "Unknown")
	else:
		# Fallback if no acting unit
		player_name_label.text = active_player.get_display_name() + "'s Unit"
		turn_info_label.text = "Round " + str(progress.get("round_number", 1))

func _update_generic_display(turn_system: TurnSystemBase, active_player: Player) -> void:
	"""Update display for generic turn system"""
	player_name_label.text = active_player.get_display_name() + "'s Turn"
	turn_info_label.text = "Round " + str(turn_system.current_turn)

func _update_fallback_display(active_player: Player) -> void:
	"""Update display when no turn system is active"""
	player_name_label.text = active_player.get_display_name() + "'s Turn"
	turn_info_label.text = "Turn in progress"

func _chip_box() -> StyleBoxFlat:
	"""A slimmed-down amber chip derived from ConquestTheme.panel_box(): same palette
	and frame, but tight margins / smaller radius / no drop shadow so the persistent
	indicator reads as a compact strip instead of a big card jutting from the top."""
	var sb := ConquestTheme.panel_box()
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.shadow_size = 0
	return sb


func _update_background_color(player: Player) -> void:
	"""Keep the amber ConquestTheme frame (compact chip variant) so the banner matches
	every other HUD panel. Convey whose turn it is subtly, by tinting just the
	player-name label text with that player's colour."""
	if background_panel:
		# Compact amber chip -- no player-coloured border.
		background_panel.add_theme_stylebox_override("panel", _chip_box())

	# Subtle player cue: tint the name text with the player's colour (lightened a
	# touch so it stays legible on the amber ground). Clear it when no player.
	if player_name_label:
		if player and player.player_id in player_colors:
			var c: Color = player_colors[player.player_id]
			c.a = 1.0
			c = c.lerp(Color.WHITE, 0.25)
			player_name_label.add_theme_color_override("font_color", c)
		else:
			player_name_label.remove_theme_color_override("font_color")

func show_turn_transition(_from_player: Player, _to_player: Player) -> void:
	"""Deprecated: the cinematic turn announcement now lives in the full-screen
	TurnTransition overlay (game/ui/hud/TurnTransition.gd). Kept as a lightweight
	refresh so any external caller still updates the compact chip without replaying
	the old in-place scale/fade effect."""
	is_transitioning = false
	if transition_label:
		transition_label.visible = false
	_update_display()

# Event handlers
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	print("TurnIndicator: Turn system activated - " + turn_system.system_name)
	
	# Hide TurnIndicator when Speed First is active (TurnQueue handles it)
	if turn_system is SpeedFirstTurnSystem:
		visible = false
		print("TurnIndicator: Hidden for Speed First system (TurnQueue handles display)")
		return
	else:
		visible = true
		print("TurnIndicator: Visible for " + turn_system.system_name)
	
	# Disconnect from previous turn system if any
	if turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.disconnect(_on_turn_started)
	if turn_system.turn_ended.is_connected(_on_turn_ended):
		turn_system.turn_ended.disconnect(_on_turn_ended)
	
	# Connect to new turn system events
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)

	# Keep the watcher's baseline in sync so it only fires on genuine future changes.
	_watched_system = turn_system
	_last_seen_player = turn_system.get_current_active_player()

	print("TurnIndicator: Connected to turn system events")
	_update_display()

func _on_turn_started(player: Player) -> void:
	"""Handle turn start"""
	# Record what we've now observed so the _process watcher and the signal path
	# converge on the same state and never double-fire the transition.
	_last_seen_player = player
	if not player:
		_update_display()
		return
	print("TurnIndicator: Turn started for " + player.get_display_name())

	# The cinematic turn announcement is now owned by the full-screen TurnTransition
	# overlay; this persistent chip just refreshes quietly so the two don't compete.
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