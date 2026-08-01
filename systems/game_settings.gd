extends Node

# GameSettings Singleton
# Stores game configuration and settings across scenes

## Emitted whenever a presentation setting (animations / battle speed / camera
## auto-focus) changes, so live systems (UnitAnimator, CameraController, the
## settings UI) can react without polling. Only the presentation block below
## emits this -- match-setup fields (map, players) are read at load time.
signal settings_changed

enum GameMode {
	SINGLE_PLAYER,
	VERSUS,
	MULTIPLAYER  # For future expansion
}

## How aggressively the camera chases live events (spawns, moves, attacks).
##   OFF       -- never auto-moves; the player drives the camera entirely.
##   QUICK     -- a fast snap-glide to the action, minimal dwell (default).
##   CINEMATIC -- a slower, framed glide with a brief hold on each beat.
enum AutoFocus {
	OFF,
	QUICK,
	CINEMATIC,
}

# --- Presentation settings (persisted to user://settings.cfg) ---------------
# These control feel/pacing and are the ones the in-game Settings panel exposes.
# Fire-Emblem / Pokemon let players speed up or switch off battle animation; this
# is that. Read them through the helpers (animations_on / anim_duration_scale)
# so callers never have to special-case the "off" state.

## Master switch for all procedural/authored unit animation (shake, glide, hit
## flash, death). Off = everything snaps instantly (fastest, most readable).
var animations_enabled: bool = true

## Playback-speed multiplier for animations. 1.0 = authored speed; 2.0 = twice as
## fast (durations halved); 0.5 = half speed. Clamped to a sane band.
var battle_speed: float = 1.0

## Camera auto-focus mode (see [enum AutoFocus]).
var camera_auto_focus: int = AutoFocus.QUICK

## Per-unit move clock (seconds) for a HUMAN player's unit in Speed First mode: how
## long the player has to command that one unit before its turn is auto-ended (exactly
## like pressing End Turn -- no staged move is committed). This is what makes Speed mode
## SPEEDY. Allowed values only: 0 = OFF (no clock, classic behaviour), or 15 / 20 / 30
## seconds. AI units are never clocked (BotTurnDriver already acts fast). Snapped to the
## nearest allowed value by [method set_speed_turn_timer_seconds].
var speed_turn_timer_seconds: int = 30

const _SETTINGS_PATH := "user://settings.cfg"
const BATTLE_SPEED_MIN := 0.5
const BATTLE_SPEED_MAX := 3.0

## The only accepted Speed First move-clock durations (0 = off). Any other value passed
## to the setter/loader is snapped to the nearest of these.
const SPEED_TIMER_ALLOWED: Array[int] = [0, 15, 20, 30]
const SPEED_TIMER_DEFAULT: int = 30

# Game configuration
var game_mode: GameMode = GameMode.VERSUS
var selected_turn_system: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL
var selected_map_path: String = "res://game/maps/resources/default_skirmish.tres"  # Default map

## The squad the local player chose on the Character Select screen (an ordered list of
## character_ids). Empty = field the map's OWN authored player-0 roster (so maps launched
## without a squad pick -- the mirror testbed, older flows -- are unchanged). When set,
## MapLoader fills player 0's spawn slots with these ids in order (Arena reads it via
## ArenaController.start_run instead). Cleared back to empty when starting a fresh pick.
var selected_squad: Array = []

## The HOST's chosen squad (character_ids for player slot 0), replicated to clients in the
## lobby's MatchSettings so every peer fields the SAME slot-0 roster. Distinct from
## [member selected_squad], which is THIS peer's own pick for its own slot; the client keeps
## its own selected_squad and reads host_squad for slot 0. Empty = use the map's authored
## player-0 roster (legacy / no-pick flows unchanged).
var host_squad: Array = []

## A validated custom-map JSON payload broadcast by the host so a client that lacks the .tres
## can rebuild the identical board. Empty = a builtin map path ([member selected_map_path])
## is used. Set from the host's MatchSettings on the client; the host reads it back when it
## builds the broadcast.
var custom_map_json: String = ""

# Player configuration
var player_count: int = 2
var player_names: Array[String] = ["Player 1", "Player 2"]

# Game settings
var auto_end_turn: bool = true  # Whether to automatically end turns when all units have acted
var show_turn_indicators: bool = true
var enable_undo: bool = false  # For future expansion

# AI difficulty for bot-controlled enemies. Int mirrors BotController.Difficulty
# (EASY=0, NORMAL=1, HARD=2, BRUTAL=3); the driver reads this when it builds a
# controller. Kept as a plain int so this settings singleton need not depend on
# BotController's load order.
var ai_difficulty: int = 1  # NORMAL

## Best-of / round count for a Versus match. Set host-side on the lobby's embedded
## MatchConfigPanel and applied locally when the match starts (1 = single game / Bo1,
## 3 = Bo3, 5 = Bo5). Kept as a plain int, clamped to a sane 1..9 band by its setter.
var versus_rounds: int = 1

func _ready() -> void:
	name = "GameSettings"
	_load_presentation_settings()

# --- Presentation helpers ---------------------------------------------------

## True when unit animations should play at all. Systems that animate should
## no-op (snap to final state) when this is false.
func animations_on() -> bool:
	return animations_enabled

## Multiplier to apply to an animation's authored DURATION. Faster battle_speed =
## shorter durations, so this is 1.0 / battle_speed. Returns 0.0 when animations
## are disabled, letting callers uniformly treat "0 duration" as "snap instantly".
func anim_duration_scale() -> float:
	if not animations_enabled:
		return 0.0
	return 1.0 / clampf(battle_speed, BATTLE_SPEED_MIN, BATTLE_SPEED_MAX)

## Scale an authored duration by the current speed/enabled state. Convenience for
## animation code: `var t := GameSettings.scaled_time(base_time)`.
func scaled_time(base_seconds: float) -> float:
	return base_seconds * anim_duration_scale()

func set_animations_enabled(enabled: bool) -> void:
	if animations_enabled == enabled:
		return
	animations_enabled = enabled
	_save_presentation_settings()
	settings_changed.emit()

func set_battle_speed(speed: float) -> void:
	var clamped := clampf(speed, BATTLE_SPEED_MIN, BATTLE_SPEED_MAX)
	if is_equal_approx(battle_speed, clamped):
		return
	battle_speed = clamped
	_save_presentation_settings()
	settings_changed.emit()

func set_camera_auto_focus(mode: int) -> void:
	var clamped := clampi(mode, 0, AutoFocus.keys().size() - 1)
	if camera_auto_focus == clamped:
		return
	camera_auto_focus = clamped
	_save_presentation_settings()
	settings_changed.emit()

## Set the Speed First per-unit move clock (seconds). Input is SNAPPED to the nearest
## allowed value (0 = off, 15, 20, 30) so the UI can pass a slider/stepper value safely.
func set_speed_turn_timer_seconds(seconds: int) -> void:
	var snapped: int = _snap_speed_timer(seconds)
	if speed_turn_timer_seconds == snapped:
		return
	speed_turn_timer_seconds = snapped
	_save_presentation_settings()
	settings_changed.emit()

## Snap an arbitrary second count to the nearest [constant SPEED_TIMER_ALLOWED] value.
func _snap_speed_timer(seconds: int) -> int:
	var best: int = SPEED_TIMER_ALLOWED[0]
	var best_d: int = absi(seconds - best)
	for v in SPEED_TIMER_ALLOWED:
		var d: int = absi(seconds - v)
		if d < best_d:
			best_d = d
			best = v
	return best

# --- Persistence ------------------------------------------------------------

func _load_presentation_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return  # No saved file yet -- keep the defaults above.
	animations_enabled = bool(cfg.get_value("presentation", "animations_enabled", animations_enabled))
	battle_speed = clampf(float(cfg.get_value("presentation", "battle_speed", battle_speed)), BATTLE_SPEED_MIN, BATTLE_SPEED_MAX)
	camera_auto_focus = clampi(int(cfg.get_value("presentation", "camera_auto_focus", camera_auto_focus)), 0, AutoFocus.keys().size() - 1)
	speed_turn_timer_seconds = _snap_speed_timer(int(cfg.get_value("presentation", "speed_turn_timer_seconds", speed_turn_timer_seconds)))

func _save_presentation_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)  # Preserve any other sections; ignore load failure.
	cfg.set_value("presentation", "animations_enabled", animations_enabled)
	cfg.set_value("presentation", "battle_speed", battle_speed)
	cfg.set_value("presentation", "camera_auto_focus", camera_auto_focus)
	cfg.set_value("presentation", "speed_turn_timer_seconds", speed_turn_timer_seconds)
	cfg.save(_SETTINGS_PATH)

# Configuration methods
func set_game_mode(mode: GameMode) -> void:
	"""Set the game mode"""
	game_mode = mode

func set_turn_system(turn_system: TurnSystemBase.TurnSystemType) -> void:
	"""Set the selected turn system"""
	selected_turn_system = turn_system

func set_player_count(count: int) -> void:
	"""Set the number of players"""
	player_count = clamp(count, 2, 4)  # Support 2-4 players
	
	# Adjust player names array
	while player_names.size() < player_count:
		player_names.append("Player " + str(player_names.size() + 1))

func set_player_name(player_index: int, name: String) -> void:
	"""Set a specific player's name"""
	if player_index >= 0 and player_index < player_names.size():
		player_names[player_index] = name

func set_selected_map(map_path: String) -> void:
	"""Set the selected map path"""
	selected_map_path = map_path

func set_selected_squad(ids: Array) -> void:
	"""The local player's chosen squad (character_ids). Copied so later edits don't alias."""
	selected_squad = ids.duplicate()

func get_selected_squad() -> Array:
	return selected_squad

func clear_selected_squad() -> void:
	selected_squad = []

func set_host_squad(ids: Array) -> void:
	"""The host's slot-0 squad (character_ids), replicated to clients. Copied so later edits
	on the source array don't alias into settings."""
	host_squad = ids.duplicate()

func get_host_squad() -> Array:
	return host_squad

func set_custom_map_json(j: String) -> void:
	"""Store the host's validated custom-map JSON payload (see [member custom_map_json])."""
	custom_map_json = j

func get_custom_map_json() -> String:
	return custom_map_json

func set_ai_difficulty(difficulty: int) -> void:
	"""Set the AI difficulty (BotController.Difficulty: EASY=0..BRUTAL=3)."""
	ai_difficulty = clampi(difficulty, 0, 3)

func set_versus_rounds(rounds: int) -> void:
	"""Set the Versus best-of round count (1 = Bo1, 3 = Bo3, 5 = Bo5). Clamped 1..9."""
	versus_rounds = clampi(rounds, 1, 9)

func get_selected_map() -> String:
	"""Get the selected map path"""
	# Return default map if none selected
	if selected_map_path.is_empty():
		return "res://game/maps/resources/default_skirmish.tres"
	return selected_map_path

# Query methods
func get_game_mode_string() -> String:
	"""Get the current game mode as a string"""
	return GameMode.keys()[game_mode]

func get_turn_system_string() -> String:
	"""Get the current turn system as a string"""
	return TurnSystemBase.TurnSystemType.keys()[selected_turn_system]

func is_single_player() -> bool:
	"""Check if this is a single player game"""
	return game_mode == GameMode.SINGLE_PLAYER

func is_versus() -> bool:
	"""Check if this is a versus game"""
	return game_mode == GameMode.VERSUS

# Game initialization
func apply_settings_to_game() -> void:
	"""Apply current settings to the game systems"""

	# Set up PlayerManager with configured players
	if PlayerManager:
		# Only set up players if they don't exist yet
		if PlayerManager.players.is_empty():
			# Create players based on configuration
			for i in range(player_count):
				var player_name = player_names[i] if i < player_names.size() else "Player " + str(i + 1)
				PlayerManager.register_player(player_name)
	
	# Set up TurnSystemManager with selected turn system
	if TurnSystemManager:
		# Create and register the selected turn system (but don't activate yet)
		# The turn system will be activated when PlayerManager.start_game() is called
		match selected_turn_system:
			TurnSystemBase.TurnSystemType.TRADITIONAL:
				var traditional_system = TraditionalTurnSystem.new()
				TurnSystemManager.register_turn_system(traditional_system)
			
			TurnSystemBase.TurnSystemType.INITIATIVE:
				var speed_first_system = SpeedFirstTurnSystem.new()
				TurnSystemManager.register_turn_system(speed_first_system)
			
			# TODO: Add other turn systems when implemented
			_:
				push_warning("Turn system not implemented: " + get_turn_system_string())
				# Fallback to traditional
				var traditional_system = TraditionalTurnSystem.new()
				TurnSystemManager.register_turn_system(traditional_system)

# Reset and defaults
func reset_to_defaults() -> void:
	"""Reset all settings to default values"""
	game_mode = GameMode.VERSUS
	selected_turn_system = TurnSystemBase.TurnSystemType.TRADITIONAL
	selected_map_path = "res://game/maps/resources/default_skirmish.tres"  # Default map
	player_count = 2
	player_names = ["Player 1", "Player 2"]
	auto_end_turn = true
	show_turn_indicators = true
	enable_undo = false
	ai_difficulty = 1  # NORMAL
	versus_rounds = 1
	host_squad = []
	custom_map_json = ""
	speed_turn_timer_seconds = SPEED_TIMER_DEFAULT

# Debug and info
func get_settings_info() -> Dictionary:
	"""Get all current settings as a dictionary"""
	return {
		"game_mode": get_game_mode_string(),
		"turn_system": get_turn_system_string(),
		"selected_map": selected_map_path,
		"player_count": player_count,
		"player_names": player_names.duplicate(),
		"auto_end_turn": auto_end_turn,
		"show_turn_indicators": show_turn_indicators,
		"enable_undo": enable_undo,
		"ai_difficulty": ai_difficulty
	}

func print_settings() -> void:
	"""Print current settings for debugging"""
	print("=== Game Settings ===")
	var info = get_settings_info()
	for key in info:
		print(key + ": " + str(info[key]))