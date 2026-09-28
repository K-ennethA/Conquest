extends Node

# GameSettings Singleton
# Stores game configuration and settings across scenes

## Emitted whenever a presentation setting (animations / battle speed / camera
## auto-focus / audio volumes) changes, so live systems (UnitAnimator,
## CameraController, AudioManager, the settings UI) can react without polling.
## Only the presentation block below emits this -- match-setup fields (map,
## players) are read at load time.
signal settings_changed

## Emitted after a keyboard binding is changed / reset (Settings > Controls), so
## button hints and the controls list can refresh.
signal controls_changed

## Emitted when the held FAST-FORWARD modifier (action `fast_forward`, Shift / R3)
## starts or stops. Runtime only, never persisted. See [method set_fast_forward].
signal fast_forward_changed(active: bool)

enum GameMode {
	SINGLE_PLAYER,
	VERSUS,
	MULTIPLAYER  # Network versus (a NetSession match); set/cleared by GameModeManager
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

# --- Audio volumes ----------------------------------------------------------
# UNIT: LINEAR amplitude in the range 0.0 .. 1.0 (0 = silent, 1 = unattenuated),
# NOT decibels. That is what a 0..100% slider maps onto directly, and it keeps
# "off" representable as an exact 0 rather than a magic -80 dB sentinel.
# AudioManager converts to dB at the point of use with its own
# `AudioManager.volume_to_db()` (linear_to_db, with 0 -> SILENT_DB); nothing
# else should do that conversion itself.
#
# These three multiply: master scales everything, music and ui scale their own
# category on top of it. They persist alongside the presentation block and emit
# `settings_changed`, which is how AudioManager applies them live.

## Overall output level (0..1 linear). Scales music AND every SFX/UI cue.
var master_volume: float = 1.0

## Music level (0..1 linear), on top of [member master_volume]. Defaults below
## 1.0 so the menu/battle bed sits under the gameplay SFX.
var music_volume: float = 0.6

## UI cue level (0..1 linear) for hover/confirm/back clicks, on top of
## [member master_volume].
var ui_volume: float = 0.8

## Default on-disk location of the persisted presentation block. Tests must
## redirect this with [method set_settings_path] rather than writing the
## player's real file -- see tests/README.md ("Temp paths").
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"

## Weather VISUALS only (particles / screen overlay) -- gameplay is never affected.
enum WeatherEffects { FULL, REDUCED, OFF }
var weather_effects: int = WeatherEffects.FULL
## Optional board grid overlay drawn by the tile shaders (the terrain itself is
## seamless). 0 = Off (default), 1 = Subtle. Drives the `grid_lines` global shader
## uniform (see docs/WORLD_ART.md).
enum GridLines { OFF, SUBTLE }
var grid_lines: int = GridLines.OFF

## FAST-FORWARD (Fire Emblem's hold-to-speed-up): while the `fast_forward` action is
## held, every scaled animation runs [constant FAST_FORWARD_MULTIPLIER]x faster and
## the AI's between-action beats shrink by the same factor. Runtime only -- polled
## each frame in _process, not saved.
const FAST_FORWARD_MULTIPLIER := 4.0
var fast_forward_active: bool = false

## Legacy alias (cloud branch name) for [constant DEFAULT_SETTINGS_PATH].
const _SETTINGS_PATH := DEFAULT_SETTINGS_PATH
const BATTLE_SPEED_MIN := 0.5
const BATTLE_SPEED_MAX := 3.0

## Volume bounds. Both ends are meaningful: 0.0 is true silence, 1.0 is the
## unattenuated signal (there is no boost above unity -- headroom above the
## authored mix does not exist).
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0

## Where the presentation block is actually read from / written to. Swappable
## for tests via [method set_settings_path].
var _settings_path: String = DEFAULT_SETTINGS_PATH

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
	_apply_grid_lines()
	load_key_bindings()

func _process(_delta: float) -> void:
	# Hold-to-fast-forward. Polled (not event-driven) so a release is never missed
	# when focus changes mid-hold.
	if InputMap.has_action(&"fast_forward"):
		set_fast_forward(Input.is_action_pressed(&"fast_forward"))

## Turn fast-forward on/off (normally driven by the held `fast_forward` action).
func set_fast_forward(active: bool) -> void:
	if fast_forward_active == active:
		return
	fast_forward_active = active
	fast_forward_changed.emit(active)

## Extra speed-up from the fast-forward modifier: FAST_FORWARD_MULTIPLIER while
## held, else 1.0. Pacing code (AI beats, the turn wipe) divides its waits by this.
func fast_forward_factor() -> float:
	return FAST_FORWARD_MULTIPLIER if fast_forward_active else 1.0

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
	return 1.0 / (clampf(battle_speed, BATTLE_SPEED_MIN, BATTLE_SPEED_MAX) * fast_forward_factor())

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

## Set the overall output level (0..1 linear). See the audio-volume block above for
## the unit choice; AudioManager converts to dB.
func set_master_volume(value: float) -> void:
	var clamped: float = clampf(value, VOLUME_MIN, VOLUME_MAX)
	if is_equal_approx(master_volume, clamped):
		return
	master_volume = clamped
	_save_presentation_settings()
	settings_changed.emit()


## Set the music level (0..1 linear), applied on top of [member master_volume].
func set_music_volume(value: float) -> void:
	var clamped: float = clampf(value, VOLUME_MIN, VOLUME_MAX)
	if is_equal_approx(music_volume, clamped):
		return
	music_volume = clamped
	_save_presentation_settings()
	settings_changed.emit()


## Set the UI-cue level (0..1 linear), applied on top of [member master_volume].
func set_ui_volume(value: float) -> void:
	var clamped: float = clampf(value, VOLUME_MIN, VOLUME_MAX)
	if is_equal_approx(ui_volume, clamped):
		return
	ui_volume = clamped
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
func set_weather_effects(mode: int) -> void:
	var clamped := clampi(mode, 0, WeatherEffects.keys().size() - 1)
	if weather_effects == clamped:
		return
	weather_effects = clamped
	_save_presentation_settings()
	settings_changed.emit()

func set_grid_lines(mode: int) -> void:
	var clamped := clampi(mode, 0, GridLines.keys().size() - 1)
	if grid_lines == clamped:
		return
	grid_lines = clamped
	_apply_grid_lines()
	_save_presentation_settings()
	settings_changed.emit()

func _apply_grid_lines() -> void:
	RenderingServer.global_shader_parameter_set(&"grid_lines", 1.0 if grid_lines == GridLines.SUBTLE else 0.0)

# --- Persistence ------------------------------------------------------------

## Redirect the persisted settings file. FOR TESTS ONLY -- a suite that exercises
## the setters (which all write on change) must point this at a `user://test_*`
## path in `before_all` and restore [constant DEFAULT_SETTINGS_PATH] in
## `after_all`, or it edits the player's real settings. See tests/README.md
## ("Temp paths, or a path-injection API").
func set_settings_path(path: String) -> void:
	_settings_path = path if not path.is_empty() else DEFAULT_SETTINGS_PATH

func get_settings_path() -> String:
	return _settings_path

## Re-read the presentation block from disk, discarding whatever is in memory.
## The public face of [method _load_presentation_settings] -- boot calls the
## private one from `_ready`; a persistence test calls this to prove a value
## survived the round trip.
func reload_presentation_settings() -> void:
	_load_presentation_settings()

func _load_presentation_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_settings_path) != OK:
		return  # No saved file yet -- keep the defaults above.
	animations_enabled = bool(cfg.get_value("presentation", "animations_enabled", animations_enabled))
	battle_speed = clampf(float(cfg.get_value("presentation", "battle_speed", battle_speed)), BATTLE_SPEED_MIN, BATTLE_SPEED_MAX)
	camera_auto_focus = clampi(int(cfg.get_value("presentation", "camera_auto_focus", camera_auto_focus)), 0, AutoFocus.keys().size() - 1)
	speed_turn_timer_seconds = _snap_speed_timer(int(cfg.get_value("presentation", "speed_turn_timer_seconds", speed_turn_timer_seconds)))
	master_volume = clampf(float(cfg.get_value("presentation", "master_volume", master_volume)), VOLUME_MIN, VOLUME_MAX)
	music_volume = clampf(float(cfg.get_value("presentation", "music_volume", music_volume)), VOLUME_MIN, VOLUME_MAX)
	ui_volume = clampf(float(cfg.get_value("presentation", "ui_volume", ui_volume)), VOLUME_MIN, VOLUME_MAX)
	weather_effects = clampi(int(cfg.get_value("presentation", "weather_effects", weather_effects)), 0, WeatherEffects.keys().size() - 1)
	grid_lines = clampi(int(cfg.get_value("presentation", "grid_lines", grid_lines)), 0, GridLines.keys().size() - 1)

func _save_presentation_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_settings_path)  # Preserve any other sections; ignore load failure.
	cfg.set_value("presentation", "animations_enabled", animations_enabled)
	cfg.set_value("presentation", "battle_speed", battle_speed)
	cfg.set_value("presentation", "camera_auto_focus", camera_auto_focus)
	cfg.set_value("presentation", "speed_turn_timer_seconds", speed_turn_timer_seconds)
	cfg.set_value("presentation", "master_volume", master_volume)
	cfg.set_value("presentation", "music_volume", music_volume)
	cfg.set_value("presentation", "ui_volume", ui_volume)
	cfg.set_value("presentation", "weather_effects", weather_effects)
	cfg.set_value("presentation", "grid_lines", grid_lines)
	cfg.save(_settings_path)

# --- Controls (keyboard rebinding) -----------------------------------------------
# Player keyboard overrides for the named actions in InputActions.REBINDABLE,
# stored in the [controls] section of the same ConfigFile as the presentation
# settings: action name -> Array of keycode-with-modifiers ints. Only the KEYBOARD
# side of an action is overridden; gamepad bindings always keep their defaults.
# Actions without an entry use the project.godot defaults.

const CONTROLS_SECTION := "controls"

## action (String) -> Array[int] keycodes-with-modifiers. See the block comment above.
var key_binding_overrides: Dictionary = {}

## Bind [param action]'s keyboard side to the single key [param code]
## (keycode-with-modifiers). If another rebindable action already uses that key it
## is SWAPPED onto this action's previous primary key, so no two actions share a key.
## Persists to [param path] and applies immediately.
func set_key_binding(action: StringName, code: int, path: String = "") -> void:
	path = _controls_path(path)
	if not InputMap.has_action(action):
		return
	var previous: Array[int] = InputActions.key_codes(action)
	var conflict := InputActions.find_conflict(code, action)
	if conflict != &"":
		var theirs: Array[int] = InputActions.key_codes(conflict)
		theirs.erase(code)
		if theirs.is_empty() and not previous.is_empty() and previous[0] != code:
			theirs.append(previous[0])
		key_binding_overrides[String(conflict)] = theirs
	key_binding_overrides[String(action)] = [code]
	apply_key_bindings()
	save_key_bindings(path)
	controls_changed.emit()

## Drop every keyboard override (back to project.godot defaults), persist, apply.
func reset_key_bindings(path: String = "") -> void:
	path = _controls_path(path)
	key_binding_overrides.clear()
	InputActions.restore_all_defaults()
	save_key_bindings(path)
	controls_changed.emit()

## Push [member key_binding_overrides] into the live InputMap.
func apply_key_bindings() -> void:
	for action in key_binding_overrides.keys():
		var codes = key_binding_overrides[action]
		if codes is Array and InputMap.has_action(StringName(action)):
			InputActions.set_keyboard_bindings(StringName(action), codes)

## Read the [controls] section from [param path] and apply it (defaults when absent).
func load_key_bindings(path: String = "") -> void:
	path = _controls_path(path)
	key_binding_overrides.clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK and cfg.has_section(CONTROLS_SECTION):
		for action in cfg.get_section_keys(CONTROLS_SECTION):
			var codes = cfg.get_value(CONTROLS_SECTION, action, [])
			if codes is Array and InputMap.has_action(StringName(action)):
				var ints: Array[int] = []
				for c in codes:
					ints.append(int(c))
				key_binding_overrides[action] = ints
	apply_key_bindings()

## Write [member key_binding_overrides] to the [controls] section of [param path],
## preserving every other section of the file.
func save_key_bindings(path: String = "") -> void:
	path = _controls_path(path)
	var cfg := ConfigFile.new()
	cfg.load(path)  # Preserve other sections; ignore load failure.
	if cfg.has_section(CONTROLS_SECTION):
		cfg.erase_section(CONTROLS_SECTION)
	for action in key_binding_overrides.keys():
		cfg.set_value(CONTROLS_SECTION, action, key_binding_overrides[action])
	cfg.save(path)

## The file the [controls] section lives in: [param path] when given, else the same
## (test-redirectable) file as the presentation block -- [method set_settings_path].
func _controls_path(path: String) -> String:
	return path if not path.is_empty() else _settings_path

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
		# Ownership: the instance is handed over parentless, and the manager FREES it on
		# reset_for_new_game() or when a later registration replaces it (see
		# TurnSystemManager._free_owned_system) -- do not keep references past that.
		match selected_turn_system:
			TurnSystemBase.TurnSystemType.TRADITIONAL:
				var traditional_system = TraditionalTurnSystem.new()
				TurnSystemManager.register_turn_system(traditional_system)
			
			TurnSystemBase.TurnSystemType.INITIATIVE:
				var speed_first_system = SpeedFirstTurnSystem.new()
				TurnSystemManager.register_turn_system(speed_first_system)
			
			# TODO: Add other turn systems when implemented
			_:
				# An unimplemented type has a WORKING fallback right below, so this is a
				# handled branch, not a fault -- it reported to the debugger on every match
				# start that selected one. print keeps it discoverable without that.
				print("[GameSettings] turn system not implemented (%s); using Traditional."
					% get_turn_system_string())
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
	master_volume = 1.0
	music_volume = 0.6
	ui_volume = 0.8

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