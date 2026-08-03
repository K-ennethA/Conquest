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

# --- Units-left-to-act counter -----------------------------------------------
#
# WHAT THE OLD NUMBER WAS. The banner read
# `TraditionalTurnSystem.get_current_turn_progress().units_can_act`, and it was only ever
# recomputed on turn_started / turn_ended. So it was a SNAPSHOT taken the instant the side
# became active -- every unit that then moved, attacked, was stunned, died or spawned left
# the number untouched for the rest of the turn. On an enemy phase the banner therefore
# sat on "41 units remaining" while the AI worked through the roster. It also said
# "remaining", which reads as "units left alive", not "units left to act".
#
# WHAT IT SAYS NOW. "N of M units left to act" for the ACTIVE side only, recomputed from
# the live roster on the active turn system's turn_started / turn_ended /
# unit_action_completed / all_units_acted, plus GameEvents unit_eliminated / unit_spawned.
# Never PlayerManager.player_turn_started -- that does not fire on AI turns, which is the
# exact case this counter exists for (CONQUEST.md convention 2).

## How many of [param units] have still to act this turn, and how many there are.
##
## Pure and duck-typed so a test can hand it a crafted roster. The rules, in order:
##   * a null / freed entry is not a unit at all -- skipped entirely;
##   * a DEAD unit is skipped entirely: neither "left" nor part of the total, so a side
##     that loses a unit mid-turn reports a smaller M rather than a stuck one;
##   * a unit that has acted -- via the turn system's [param acted] side list OR its own
##     has_acted_this_turn flag, which can disagree (see
##     TraditionalTurnSystem.can_unit_act) -- counts toward the total, not toward "left";
##   * a unit in [param blocked] (stunned or hijacked THIS turn) also counts toward the
##     total but can never act, so it is not "left" either;
##   * a unit SPAWNED mid-turn is simply a live unacted unit and lands in both counts on
##     the next refresh -- which is why this is recomputed from the live roster instead of
##     decremented from a turn-start snapshot.
static func count_act_progress(units: Array, acted: Array = [], blocked: Array = []) -> Dictionary:
	var total: int = 0
	var left: int = 0
	var acted_count: int = 0
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if not _counts_as_alive(unit):
			continue
		total += 1
		if unit in acted or ("has_acted_this_turn" in unit and bool(unit.has_acted_this_turn)):
			acted_count += 1
			continue
		if unit in blocked:
			continue
		left += 1
	return {"left": left, "total": total, "acted": acted_count}


## Liveness, duck-typed: a real [Unit] answers is_alive(), a bare double may only carry
## current_health, and something with neither is assumed alive (it cannot be proven dead).
static func _counts_as_alive(unit) -> bool:
	if unit.has_method("is_alive"):
		return bool(unit.is_alive())
	if "current_health" in unit:
		return int(unit.current_health) > 0
	return true


## The banner's second line for [param round_number] and a [method count_act_progress]
## result. Static so the wording is pinned by a test alongside the arithmetic.
static func progress_text(round_number: int, progress: Dictionary) -> String:
	if progress.is_empty() or int(progress.get("total", 0)) <= 0:
		return "Round %d" % round_number
	return "Round %d - %d of %d units left to act" % [
		round_number, int(progress.get("left", 0)), int(progress.get("total", 0))]


func _ready() -> void:
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)

	# Roster changes do not go through the turn system's own signals, but they DO change
	# the denominator, so the banner listens for them directly.
	if GameEvents:
		if not GameEvents.unit_eliminated.is_connected(_on_roster_changed):
			GameEvents.unit_eliminated.connect(_on_roster_changed)
		if not GameEvents.unit_spawned.is_connected(_on_roster_changed):
			GameEvents.unit_spawned.connect(_on_roster_changed)

	# Delay initial update to ensure turn system is fully initialized
	await get_tree().process_frame
	# Backing out of the battle during that frame frees this node; everything below
	# touches `self`.
	if not is_inside_tree():
		return

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

	# Both lines just changed; keep the amber frame around them.
	_fit_chip_width()

func _turn_title(player: Player) -> String:
	"""Ally/enemy framing for the chip -- reads better than "Player 1/2" in
	single-player. Keyed off Player.is_ai; the player-colour tint (see
	_update_background_color) still conveys which side subtly."""
	if player != null and player.is_ai:
		return "Enemy Turn"
	return "Your Turn"

func _update_traditional_display(turn_system: TraditionalTurnSystem, active_player: Player) -> void:
	"""Update display for Traditional Turn System"""
	player_name_label.text = _turn_title(active_player)
	turn_info_label.text = progress_text(turn_system.current_turn, _live_progress(turn_system))


## Read the ACTIVE side's roster off [param turn_system] and count it. Everything here is
## a read -- the roster, the turn system's own acted side list, and its per-turn stun /
## forced-control latches (which bar a unit from acting without it having "acted").
func _live_progress(turn_system) -> Dictionary:
	if turn_system == null or not is_instance_valid(turn_system):
		return {}
	if not turn_system.has_method("get_current_active_player") \
			or not turn_system.has_method("get_units_for_player"):
		return {}
	var player = turn_system.get_current_active_player()
	if player == null:
		return {}

	var units: Array = turn_system.get_units_for_player(player)
	var acted: Array = []
	if "units_acted_this_turn" in turn_system:
		acted = turn_system.units_acted_this_turn
	var blocked: Array = []
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if turn_system.has_method("is_turn_skipped") and bool(turn_system.is_turn_skipped(unit)):
			blocked.append(unit)
		elif turn_system.has_method("is_turn_forced_control") \
				and bool(turn_system.is_turn_forced_control(unit)):
			blocked.append(unit)
	return count_act_progress(units, acted, blocked)


## Repaint ONLY the progress line, from the live roster. Cheap enough to run on every
## unit action; leaves the player-name line and the chip tint alone.
func _refresh_progress() -> void:
	if not is_inside_tree() or turn_info_label == null:
		return
	if not TurnSystemManager:
		return
	var sys: TurnSystemBase = TurnSystemManager.get_active_turn_system()
	# Speed First is owned by the TurnQueue; this banner stays hidden for it.
	if sys == null or sys is SpeedFirstTurnSystem:
		return
	turn_info_label.text = progress_text(sys.current_turn, _live_progress(sys))
	_fit_chip_width()


## Widest the chip's amber frame has to be to hold its two lines.
const CHIP_MIN_WIDTH: float = 240.0
## _chip_box(): 12px content margin each side + the 3px frame each side, rounded up.
const CHIP_PADDING: float = 32.0


## Keep the amber frame wide enough for the longest line it currently shows.
##
## This root is a plain Control, so its children contribute NOTHING to its minimum size --
## the 240px authored width was sized for "Round 1 - 3 units remaining" and the longer
## "N of M units left to act" line would simply spill out past the frame.
func _fit_chip_width() -> void:
	if player_name_label == null or turn_info_label == null:
		return
	var widest: float = maxf(
			player_name_label.get_minimum_size().x,
			turn_info_label.get_minimum_size().x)
	custom_minimum_size.x = maxf(CHIP_MIN_WIDTH, widest + CHIP_PADDING)


func _on_unit_acted(_unit = null, _action_type = "") -> void:
	# Deferred: this fires from inside the unit's action signal, before the turn system has
	# finished its own bookkeeping (mark_unit_acted / completion check).
	call_deferred("_refresh_progress")


func _on_all_units_acted() -> void:
	call_deferred("_refresh_progress")


func _on_roster_changed(_a = null, _b = null) -> void:
	# A death unregisters the unit from the turn system inside the same emission, so read
	# the roster after this signal has unwound.
	call_deferred("_refresh_progress")

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
	player_name_label.text = _turn_title(active_player)
	turn_info_label.text = progress_text(turn_system.current_turn, _live_progress(turn_system))

func _update_fallback_display(active_player: Player) -> void:
	"""Update display when no turn system is active"""
	player_name_label.text = _turn_title(active_player)
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
	
	# Connect to new turn system events. unit_action_completed / all_units_acted are what
	# make the "N of M units left to act" line tick DURING a turn -- including an AI turn,
	# which is why these ride the turn system and never PlayerManager (CONQUEST.md rule 2).
	turn_system.turn_started.connect(_on_turn_started)
	turn_system.turn_ended.connect(_on_turn_ended)
	if turn_system.has_signal("unit_action_completed") \
			and not turn_system.unit_action_completed.is_connected(_on_unit_acted):
		turn_system.unit_action_completed.connect(_on_unit_acted)
	if turn_system.has_signal("all_units_acted") \
			and not turn_system.all_units_acted.is_connected(_on_all_units_acted):
		turn_system.all_units_acted.connect(_on_all_units_acted)

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