extends Control

class_name TurnIndicator

# The persistent PHASE BANNER at the top-centre of the battle HUD (Fire Emblem's
# "PLAYER PHASE / ENEMY PHASE"): a swallow-tailed heraldic ribbon edged in the acting
# side's team colour with a gold crest, the phase title in Cinzel, and ONE compact
# info row underneath -- "Round N · X units ready" followed by the map objective
# (the ObjectiveChip, mounted inline via [method attach_objective]) and the "Danger
# zone" tag. Keeping the objective INSIDE the banner keeps the whole top HUD to a
# single ~64px strip (see HudSafeArea), so it never covers the back row of the board.
# In a network match it reads YOUR TURN / OPPONENT'S TURN, in local versus PLAYER N
# PHASE (see ConquestTheme.phase_title). The cinematic wipe lives in TurnTransition.

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

## Swallow-tail depth of the banner ends (base px).
const BANNER_NOTCH := 20.0
## Horizontal / vertical padding of the banner content.
const BANNER_PAD := Vector2(BANNER_NOTCH + 26.0, 5.0)

## Row under the title: round / ready count, then the inline objective.
var _info_row: HBoxContainer = null


func _ready() -> void:
	custom_minimum_size = Vector2(340, 62)
	if player_name_label:
		player_name_label.add_theme_font_override("font", MenuTheme.display_font(3))
		player_name_label.add_theme_font_size_override("font_size", ConquestTheme.FS_PHASE)
		player_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
		player_name_label.add_theme_constant_override("shadow_offset_y", 2)
	if turn_info_label:
		turn_info_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
		# One compact info row: the round label, then (attach_objective) the objective.
		var vb := turn_info_label.get_parent()
		_info_row = HBoxContainer.new()
		_info_row.name = "InfoRow"
		_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
		_info_row.add_theme_constant_override("separation", 10)
		_info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(_info_row)
		vb.move_child(_info_row, turn_info_label.get_index())
		turn_info_label.reparent(_info_row)
		ConquestTheme.keep_style(_info_row)
	var vbox := get_node_or_null("CenterContainer/VBoxContainer") as Control
	if vbox:
		vbox.minimum_size_changed.connect(_refit)
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)

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
	
	# Fallback to PlayerManager only if TurnSystemManager doesn't have an active player
	if not active_player and PlayerManager:
		active_player = PlayerManager.get_current_player()
	
	if active_player:
		current_player = active_player
		
		# Update display based on turn system type
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()

			if turn_system is TraditionalTurnSystem:
				_update_traditional_display(turn_system, active_player)
			elif turn_system is SpeedFirstTurnSystem:
				_update_speed_first_display(turn_system, active_player)
			else:
				_update_generic_display(turn_system, active_player)
		else:
			_update_fallback_display(active_player)
		
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

func _turn_title(player: Player) -> String:
	"""FE phase framing: PLAYER PHASE / ENEMY PHASE (single player), YOUR TURN /
	OPPONENT'S TURN (network), PLAYER N PHASE (local versus)."""
	return ConquestTheme.phase_title(player)

func _update_traditional_display(turn_system: TraditionalTurnSystem, active_player: Player) -> void:
	"""Update display for Traditional Turn System"""
	player_name_label.text = _turn_title(active_player)
	
	var progress = turn_system.get_current_turn_progress()
	if progress.has("units_can_act"):
		var n := int(progress.units_can_act)
		turn_info_label.text = "Round %d  ·  %d unit%s ready" % [turn_system.current_turn, n, "" if n == 1 else "s"]
	else:
		turn_info_label.text = "Round %d" % turn_system.current_turn

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
		
		turn_info_label.text = "Round " + str(progress.get("round_number", 1)) + speed_info + remaining_info.replace(" - ", "  ·  ")
		
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
	player_name_label.text = _turn_title(active_player)
	turn_info_label.text = "Round " + str(turn_system.current_turn)

func _update_fallback_display(active_player: Player) -> void:
	"""Update display when no turn system is active"""
	player_name_label.text = _turn_title(active_player)
	turn_info_label.text = "Turn in progress"

func _chip_box(team: Color) -> StyleBox:
	"""The phase banner: a swallow-tailed navy ribbon edged in the acting side's team
	colour, gold filigree inside and a gold crest on top, so whose phase it is reads
	at a glance."""
	var sb := MenuTheme.ribbon_box(ConquestTheme.PANEL, team, BANNER_NOTCH)
	sb.bg_color = Color(ConquestTheme.PANEL.lightened(0.08), 0.96)
	sb.bg_color_end = Color(ConquestTheme.PANEL.darkened(0.35), 0.96)
	sb.border_width = 2.0
	sb.inner_line_color = Color(ConquestTheme.GOLD, 0.42)
	sb.crest = true
	sb.ornament_color = ConquestTheme.GOLD
	sb.ornament_size = 3.2
	sb.accent_color = Color(team, 0.85)
	sb.accent_side = SIDE_BOTTOM
	sb.accent_width = 3.0
	return sb


## Mount the objective chip inline in the info row (see UILayoutManager).
func attach_objective(chip: Control) -> void:
	if _info_row == null or chip == null:
		return
	if chip.get_parent() != null:
		chip.reparent(_info_row)
	else:
		_info_row.add_child(chip)


## The banner is a plain Control (its min size does not follow its children), so size
## it to the content: title / info row plus the ribbon's tails and padding.
func _refit() -> void:
	var vbox := get_node_or_null("CenterContainer/VBoxContainer") as Control
	if vbox == null:
		return
	var need := vbox.get_combined_minimum_size() + BANNER_PAD * 2.0
	var want := Vector2(maxf(340.0, ceilf(need.x)), maxf(58.0, ceilf(need.y)))
	if not custom_minimum_size.is_equal_approx(want):
		custom_minimum_size = want


func _update_background_color(player: Player) -> void:
	"""Team-coloured frame + phase title in the team's (lightened, legible) colour."""
	var team: Color = ConquestTheme.team_color(player) if player else ConquestTheme.BORDER
	if background_panel:
		background_panel.add_theme_stylebox_override("panel", _chip_box(team))
	if player_name_label:
		if player:
			player_name_label.add_theme_color_override("font_color", ConquestTheme.team_text_color(player))
		else:
			player_name_label.add_theme_color_override("font_color", ConquestTheme.CREAM)
	if turn_info_label:
		turn_info_label.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)

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
	# Hide TurnIndicator when Speed First is active (TurnQueue handles it)
	if turn_system is SpeedFirstTurnSystem:
		visible = false
		return
	else:
		visible = true
	
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

	_update_display()

func _on_turn_started(player: Player) -> void:
	"""Handle turn start"""
	# Record what we've now observed so the _process watcher and the signal path
	# converge on the same state and never double-fire the transition.
	_last_seen_player = player
	if not player:
		_update_display()
		return

	# The cinematic turn announcement is now owned by the full-screen TurnTransition
	# overlay; this persistent chip just refreshes quietly so the two don't compete.
	_update_display()

func _on_turn_ended(player: Player) -> void:
	"""Handle turn end"""
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