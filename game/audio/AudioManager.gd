extends Node

## Autoload that plays game audio from a swappable [AudioLibrary] resource.
##
## Designers change WHAT plays by editing the `.tres` assigned to [member library]
## (default: res://game/audio/default_audio_library.tres) -- no code required.
## This node handles HOW/WHEN: it owns a small pool of AudioStreamPlayers for
## overlapping SFX plus one dedicated music player, and it wires itself to the
## existing GameEvents signal bus so gameplay automatically triggers sounds.
##
## Robustness contract: every slot may be null and every signal may be missing;
## nothing here errors when audio assets or emitters are absent. This lets the
## project run today with zero audio files and grow coverage later.
##
## Menu polish (hover/confirm/back SFX + menu music) additionally wires itself
## to EVERY BaseButton project-wide via [signal SceneTree.node_added], so no
## individual menu scene needs to be edited. It shares the exact
## `"ui_sfx_wired"` meta key that [script UIFeedback] (game/ui/UIFeedback.gd)
## already uses to mark buttons it has wired, so whichever of the two runs
## first on a given button wins and the other is a no-op -- never a double
## connection. See `_wire_ui_button()` below.
##
## MIX MODEL (where a played sound's final volume_db comes from). Four terms,
## summed in dB, in this order:
##   1. the LIBRARY's per-category base (`library.sfx_volume_db` /
##      `library.music_volume_db`) -- the authored mix, edited in the .tres;
##   2. this node's @export trims (`master_volume_db` / `music_volume_db` /
##      `ui_volume_db`) -- the DEVELOPER's static offsets, e.g. music_volume_db
##      sits at -10 so the music bed never competes with gameplay SFX;
##   3. the PLAYER's settings (GameSettings.master_volume / music_volume /
##      ui_volume), stored as LINEAR 0..1 and converted here by
##      [method volume_to_db];
##   4. the per-cue offset the caller passes (the cursor tick's -14, etc).
## Only (3) changes at runtime: GameSettings emits `settings_changed`, this node
## re-reads the three linear values and re-levels the music player in place, so a
## settings slider is audible while it is being dragged.

## The swappable audio bank. Assign a different AudioLibrary .tres in the
## inspector (this node is an autoload -> Project Settings > Globals, or edit
## the scene if promoted to one) to re-skin all game audio at once.
@export var library: AudioLibrary = preload("res://game/audio/default_audio_library.tres")

## Number of pooled SFX players. More = more sounds can overlap before the
## oldest is recycled. Inspector-editable.
@export_range(1, 16, 1) var sfx_voice_count: int = 8

## Audio bus name for SFX players (must exist in the project's Audio bus layout;
## "Master" is always present).
@export var sfx_bus: StringName = &"Master"
## Audio bus name for the music player.
@export var music_bus: StringName = &"Master"

## The cursor-move blip fires on every tile the cursor crosses, so it plays MUCH
## quieter than a deliberate action sound (negative dB = quieter). Tune to taste;
## 0.0 would match full SFX volume (too loud/disruptive for a constant tick).
@export_range(-40.0, 0.0, 0.5) var cursor_move_volume_offset_db: float = -14.0
## Minimum seconds between cursor-move blips, so sliding the cursor fast doesn't
## machine-gun the sound across every voice. 0 disables throttling.
@export_range(0.0, 0.5, 0.01) var cursor_move_min_interval: float = 0.05

# --- Menu / UI polish (hover, confirm, back, menu music) --------------------

## Master switch for the project-wide button hover/confirm/back wiring below.
## Flipping this off silences future UI cues immediately (checked at play
## time, not wire time) without needing to disconnect anything.
@export var ui_sounds_enabled: bool = true

## Developer trim (dB) applied on top of everything else. This is term (2) of the
## MIX MODEL above -- the PLAYER's master slider is GameSettings.master_volume,
## not this; leave this at 0 unless the whole game's authored mix is off.
@export_range(-60.0, 12.0, 0.1) var master_volume_db: float = 0.0
## Developer trim (dB) applied to UI hover/confirm/back cues only (on top of
## master_volume_db).
@export_range(-60.0, 12.0, 0.1) var ui_volume_db: float = 0.0
## Developer trim (dB) applied to music playback only (on top of master_volume_db
## and library.music_volume_db). Negative by default and deliberately so: music is
## a BED, and at 0 the menu loop sat on top of the SFX (the "too loud" report).
## With the shipped defaults the menu bed lands ~20 dB under an SFX cue -- see
## [method _resolve_music_volume_db].
@export_range(-60.0, 12.0, 0.1) var music_volume_db: float = -10.0

## Semantic pitch/volume map for the auto-wired UI cues. All three reuse the
## existing &"sfx_ui_click" stream (no new audio files) and differ only by
## pitch_scale + volume, so a click, a hover tick, and a "back" tick feel
## distinct without any new assets:
##   confirm (press)       -> pitch 1.0,  -6 dB  (matches UIFeedback's HUD click)
##   hover   (mouse_enter) -> pitch 1.4, -14 dB  (quiet, easy-to-ignore tick)
##   back/cancel (press)   -> pitch 0.8,  -6 dB  (lower = "stepping back")
const UI_CONFIRM_PITCH := 1.0
const UI_CONFIRM_VOLUME_DB := -6.0
const UI_HOVER_PITCH := 1.4
const UI_HOVER_VOLUME_DB := -14.0
const UI_BACK_PITCH := 0.8
const UI_BACK_VOLUME_DB := -6.0

## Button text/name substrings (case-insensitive) that mark a button as
## "back-like" for the auto-wired press cue. Checked at press time (not wire
## time) so relabelled/localized text is always picked up correctly.
const _BACK_KEYWORDS: PackedStringArray = ["back", "cancel", "quit", "exit", "return", "close"]

## Must match UIFeedback._WIRED_META exactly (see game/ui/UIFeedback.gd) --
## this is the shared idempotency flag that prevents AudioManager and
## UIFeedback from ever both wiring the same button.
const _UI_SFX_WIRED_META := "ui_sfx_wired"

## Crossfade duration (seconds) for menu <-> menu music transitions.
const MUSIC_FADE_TIME := 0.5

## The dB value that stands for "off". Godot treats anything at or below roughly
## -80 dB as inaudible, and `linear_to_db(0.0)` is -INF, which poisons any sum it
## lands in -- so a 0.0 slider resolves to this finite floor instead.
const SILENT_DB := -80.0
## Linear volumes at or below this count as off (a slider dragged to its minimum
## never lands on an exact 0.0 after float rounding).
const SILENT_THRESHOLD := 0.0005

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _music_player: AudioStreamPlayer
## Dedicated single voice for the hover tick so rapid hovers retrigger-cancel
## instead of stacking into a wall of noise.
var _ui_hover_player: AudioStreamPlayer
## Timestamp (ms) of the last cursor-move blip, for throttling.
var _last_cursor_sfx_ms: int = 0

## True from game_started to game_ended. While true, the menu-music
## scene-change watcher backs off entirely and leaves music to
## play_music()/stop_music() (battle's existing, unchanged behaviour).
var _in_battle: bool = false
## Runtime override for the menu-music stream (see set_menu_music()). Takes
## priority over library.music_menu when set.
var _menu_music_override: AudioStream
var _music_tween: Tween

## Term (3) of the MIX MODEL: the PLAYER's volumes, already converted from
## GameSettings' linear 0..1 to dB. Cached rather than read per sound so the
## conversion happens once per settings change, not once per cursor tick. The
## defaults here mirror GameSettings' own so this node is correctly levelled even
## when that autoload is absent (an isolated tool/test scene).
var _settings_master_db: float = 0.0
var _settings_music_db: float = -4.44
var _settings_ui_db: float = -1.94

func _ready() -> void:
	name = "AudioManager"

	# Fall back to a fresh empty library if none was assigned, so the API never
	# dereferences null.
	if library == null:
		library = AudioLibrary.new()

	_build_players()
	_connect_events()
	_connect_settings()

	# Global menu-button audio wiring (zero per-menu edits): watch every node
	# entering the tree for BaseButtons (hover/confirm/back cues) and for
	# scene-root swaps (menu music). NOTE: this canNOT catch the BOOT scene -
	# at startup every autoload AND the main scene enter the tree before any
	# autoload's _ready runs (verified live while fixing the stuck-black
	# SceneFade bug), so the initial menu-music kick is done explicitly below.
	get_tree().node_added.connect(_on_scene_tree_node_added)
	# Boot-scene kick: start menu music for the very first scene (deferred so
	# the whole boot cascade - including the battle-state signals that would
	# set _in_battle - lands first). Runtime scene swaps ride the signal above.
	call_deferred("_kick_boot_menu_music")

func _build_players() -> void:
	for i in sfx_voice_count:
		var p := AudioStreamPlayer.new()
		p.bus = sfx_bus
		p.name = "SFXVoice%d" % i
		add_child(p)
		_sfx_players.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = music_bus
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	_ui_hover_player = AudioStreamPlayer.new()
	_ui_hover_player.bus = sfx_bus
	_ui_hover_player.name = "UIHoverVoice"
	add_child(_ui_hover_player)

# --- Public API ------------------------------------------------------------

## Play the SFX mapped to [param event_name] (e.g. &"sfx_attack").
## No-op when the library slot is empty or the event is unknown -- safe to call
## for events that have no sound assigned yet.
func play_sfx(event_name: StringName, volume_offset_db: float = 0.0) -> void:
	if library == null:
		return
	var stream := library.get_stream(event_name)
	if stream == null:
		return
	_play_stream_on_free_voice(stream, volume_offset_db)

## Play an explicit AudioStream through the SFX pool (bypasses the library map).
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	_play_stream_on_free_voice(stream)

## Start (or restart) music instantly (no fade -- this is battle's existing,
## unchanged entry point, driven by GameEvents.game_started). Pass an
## AudioStream, or omit to use library.music_battle. No-op when the resolved
## stream is null.
func play_music(stream: AudioStream = null) -> void:
	if _music_player == null:
		return
	var to_play := stream
	if to_play == null and library != null:
		to_play = library.music_battle
	if to_play == null:
		return
	_kill_music_tween()
	_music_player.stream = to_play
	_music_player.volume_db = _resolve_music_volume_db()
	_music_player.play()

## Stop music playback instantly (no fade -- battle's existing, unchanged
## entry point, driven by GameEvents.game_ended).
func stop_music() -> void:
	_kill_music_tween()
	if _music_player != null:
		_music_player.stop()

## Runtime override for the menu-music slot, so a future generation pass (or
## any calling code) can supply a stream without editing default_audio_library.tres.
## Pass null to clear the override and fall back to library.music_menu (also
## likely null today -- see the class doc TODO). If a non-battle scene is
## currently active, this re-evaluates immediately.
## Boot-scene menu-music kick - see the note at the node_added connection in _ready.
func _kick_boot_menu_music() -> void:
	if not _in_battle:
		_crossfade_menu_music(_resolve_menu_music())


func set_menu_music(stream: AudioStream) -> void:
	_menu_music_override = stream
	if not _in_battle:
		_crossfade_menu_music(_resolve_menu_music())

## Semantic UI cue: a deliberate confirm/select press. Reuses &"sfx_ui_click"
## at pitch 1.0. No-op when ui_sounds_enabled is false or the slot is empty.
func play_ui_confirm() -> void:
	_play_ui_click_variant(UI_CONFIRM_VOLUME_DB, UI_CONFIRM_PITCH)

## Semantic UI cue: back/cancel press. Reuses &"sfx_ui_click" pitched down so
## it reads as distinct from confirm. No-op when disabled/empty (see above).
func play_ui_back() -> void:
	_play_ui_click_variant(UI_BACK_VOLUME_DB, UI_BACK_PITCH)

## Semantic UI cue: mouse-hover tick. Plays on a single dedicated voice so
## rapid hovers retrigger-cancel instead of stacking/overlapping loudly.
## No-op when ui_sounds_enabled is false or the slot is empty.
func play_ui_hover() -> void:
	if not ui_sounds_enabled or library == null or _ui_hover_player == null:
		return
	var stream := library.get_stream(&"sfx_ui_click")
	if stream == null:
		return
	_ui_hover_player.stop()
	_ui_hover_player.stream = stream
	_ui_hover_player.volume_db = (_resolve_sfx_volume_db() + ui_volume_db + _settings_ui_db
		+ UI_HOVER_VOLUME_DB)
	_ui_hover_player.pitch_scale = UI_HOVER_PITCH
	_ui_hover_player.play()

# --- Internal --------------------------------------------------------------

func _play_ui_click_variant(volume_offset_db: float, pitch: float) -> void:
	if not ui_sounds_enabled or library == null:
		return
	var stream := library.get_stream(&"sfx_ui_click")
	if stream == null:
		return
	_play_stream_on_free_voice(stream, volume_offset_db + ui_volume_db + _settings_ui_db, pitch)

## Convert one of GameSettings' LINEAR 0..1 volumes to dB. Pure and static so the
## mapping can be tested without an audio device, a tree or this autoload's state
## (`tests/unit/test_audio_volume_mapping.gd`). 0 (and anything within
## [constant SILENT_THRESHOLD] of it) maps to the finite [constant SILENT_DB]
## floor rather than `linear_to_db`'s -INF, which would make every sum it takes
## part in NaN/-INF.
static func volume_to_db(linear: float) -> float:
	var v: float = clampf(linear, 0.0, 1.0)
	if v <= SILENT_THRESHOLD:
		return SILENT_DB
	return maxf(linear_to_db(v), SILENT_DB)


## Subscribe to GameSettings and take its current volumes. Looked up by node path
## (not the bare autoload identifier) so this node is equally safe in a stripped
## scene where GameSettings is not registered.
func _connect_settings() -> void:
	var settings := _settings_node()
	if settings == null:
		return
	if settings.has_signal(&"settings_changed") and not settings.is_connected(&"settings_changed", _on_settings_changed):
		settings.connect(&"settings_changed", _on_settings_changed)
	_pull_settings_volumes()


func _settings_node() -> Node:
	return get_node_or_null("/root/GameSettings")


## Re-read the three linear volumes and cache them as dB. Leaves the cached
## defaults in place when the autoload is absent, or when a field is missing (an
## older/stripped GameSettings) -- see [method _settings_volume_db].
func _pull_settings_volumes() -> void:
	var settings := _settings_node()
	if settings == null:
		return
	_settings_master_db = _settings_volume_db(settings, "master_volume", _settings_master_db)
	_settings_music_db = _settings_volume_db(settings, "music_volume", _settings_music_db)
	_settings_ui_db = _settings_volume_db(settings, "ui_volume", _settings_ui_db)


## One linear volume off [param settings], converted to dB. `Object.get()` on an
## unknown property returns null, and `float(null)` is a hard cast error -- so the
## type is checked and [param fallback_db] returned instead of crashing boot.
func _settings_volume_db(settings: Node, property: String, fallback_db: float) -> float:
	var value: Variant = settings.get(property)
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return fallback_db
	return volume_to_db(float(value))


## GameSettings changed (a slider moved, or another system wrote a setting).
## SFX pick the new level up on their next play by themselves -- they are levelled
## at play time -- but the music player is already playing, so it is re-levelled
## in place here. Skipped while a crossfade tween owns volume_db, otherwise this
## would fight the tween and the fade would jump.
func _on_settings_changed() -> void:
	_pull_settings_volumes()
	if _music_player == null or not _music_player.playing:
		return
	if _music_tween != null and _music_tween.is_valid() and _music_tween.is_running():
		return
	_music_player.volume_db = _resolve_music_volume_db()


## Base dB for any SFX voice: the library's authored SFX level plus both master
## terms. The per-cue offset is added by the caller.
func _resolve_sfx_volume_db() -> float:
	var base_db: float = library.sfx_volume_db if library != null else 0.0
	return base_db + master_volume_db + _settings_master_db


func _resolve_music_volume_db() -> float:
	var base_db: float = library.music_volume_db if library != null else -6.0
	return base_db + master_volume_db + music_volume_db + _settings_master_db + _settings_music_db

func _resolve_menu_music() -> AudioStream:
	if _menu_music_override != null:
		return _menu_music_override
	return library.music_menu if library != null else null

func _kill_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null

## Crossfade the music player to [param new_stream] over MUSIC_FADE_TIME on
## each side. A null stream (no menu-music asset yet -- see class doc TODO)
## just fades whatever is playing out to silence, so this is always safe to
## call speculatively. No-ops if already playing the requested stream.
func _crossfade_menu_music(new_stream: AudioStream) -> void:
	if _music_player == null:
		return
	if _music_player.stream == new_stream and (new_stream == null or _music_player.playing):
		return
	_kill_music_tween()
	if _music_player.playing:
		# Only build the fade-out tween when there is something to fade: a Tween
		# created and never given a tweener logs an engine error on its first step.
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", -80.0, MUSIC_FADE_TIME)
		_music_tween.tween_callback(_start_music_stream.bind(new_stream))
	else:
		_start_music_stream(new_stream)

func _start_music_stream(stream: AudioStream) -> void:
	if _music_player == null:
		return
	if stream == null:
		_music_player.stop()
		return
	var target_db := _resolve_music_volume_db()
	_music_player.stream = stream
	_music_player.volume_db = -80.0
	_music_player.play()
	_music_tween = create_tween()
	_music_tween.tween_property(_music_player, "volume_db", target_db, MUSIC_FADE_TIME)

func _play_stream_on_free_voice(stream: AudioStream, volume_offset_db: float = 0.0, pitch_override: float = -1.0) -> void:
	if _sfx_players.is_empty():
		return
	# Prefer an idle player; otherwise round-robin (recycle the oldest).
	var player: AudioStreamPlayer = null
	for candidate in _sfx_players:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		player = _sfx_players[_next_voice]
		_next_voice = (_next_voice + 1) % _sfx_players.size()

	player.stream = stream
	player.volume_db = _resolve_sfx_volume_db() + volume_offset_db
	if pitch_override > 0.0:
		player.pitch_scale = pitch_override
	else:
		var variance := library.sfx_pitch_variance if library != null else 0.0
		player.pitch_scale = 1.0 + randf_range(-variance, variance) if variance > 0.0 else 1.0
	player.play()

# --- Signal wiring ---------------------------------------------------------

## Connect to the game's existing GameEvents signals and map each to an SFX.
## Every connection is guarded so a renamed/removed signal never crashes boot.
func _connect_events() -> void:
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		# GameEvents autoload not present (e.g. isolated tool scene) -- skip.
		return

	_safe_connect(bus, &"unit_selected", _on_unit_selected)
	_safe_connect(bus, &"unit_moved", _on_unit_moved)
	_safe_connect(bus, &"turn_started", _on_turn_started)
	_safe_connect(bus, &"cursor_moved", _on_cursor_moved)
	_safe_connect(bus, &"cursor_selected", _on_cursor_selected)
	_safe_connect(bus, &"combat_initiated", _on_combat_initiated)
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_healed", _on_unit_healed)
	_safe_connect(bus, &"unit_eliminated", _on_unit_eliminated)
	_safe_connect(bus, &"game_started", _on_game_started)
	_safe_connect(bus, &"game_ended", _on_game_ended)

func _safe_connect(obj: Object, signal_name: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, callable):
		obj.connect(signal_name, callable)

# Handlers accept untyped args so they never fail on argument-type differences
# (some turn systems emit a Player where a Unit is declared, etc.).
func _on_unit_selected(_unit = null, _position = null) -> void:
	play_sfx(&"sfx_select")

func _on_unit_moved(_unit = null, _from = null, _to = null) -> void:
	play_sfx(&"sfx_move")

func _on_turn_started(_who = null) -> void:
	play_sfx(&"sfx_turn_start")

func _on_cursor_moved(_position = null) -> void:
	# The cursor tick fires constantly as it crosses tiles, so it plays quietly and
	# is rate-limited -- otherwise it dominates the mix and machine-guns the voices.
	if cursor_move_min_interval > 0.0:
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_cursor_sfx_ms < int(cursor_move_min_interval * 1000.0):
			return
		_last_cursor_sfx_ms = now_ms
	play_sfx(&"sfx_ui_click", cursor_move_volume_offset_db)

func _on_cursor_selected(_position = null) -> void:
	play_sfx(&"sfx_ui_click")

func _on_combat_initiated(_attacker = null, _defender = null) -> void:
	play_sfx(&"sfx_attack")

func _on_damage_dealt(_attacker = null, _defender = null, _damage = null) -> void:
	play_sfx(&"sfx_hit")

func _on_unit_healed(_unit = null, _amount = null) -> void:
	# The AudioLibrary defines a dedicated sfx_heal slot; play_sfx no-ops until an
	# asset is assigned, so this is silent-but-safe rather than a fallback to another cue.
	play_sfx(&"sfx_heal")

func _on_unit_eliminated(_unit = null, _eliminator = null) -> void:
	play_sfx(&"sfx_death")

func _on_game_started() -> void:
	# Kick off battle music if one is assigned. Also flips the flag that makes
	# the menu-music scene watcher below back off for the duration of the battle.
	_in_battle = true
	play_music()

func _on_game_ended(_winner = null) -> void:
	_in_battle = false
	stop_music()

# --- Menu polish: global button wiring + menu-music scene watcher ----------

## Fires for every node added anywhere in the tree. Cheap: two type/parent
## checks, no allocation on the common-case miss.
func _on_scene_tree_node_added(node: Node) -> void:
	if node is BaseButton:
		_wire_ui_button(node as BaseButton)
	# A node added directly under the tree root is (in this project) always a
	# scene swap via change_scene_to_file/change_scene_to_packed -- every menu
	# and the battle scene (game/world/GameWorld.tscn) are added there. This
	# avoids hardcoding scene paths: we don't need to know a scene IS the
	# battle scene, only that GameEvents.game_started/game_ended (handled
	# above) already tracks _in_battle for us.
	elif node.get_parent() == get_tree().root:
		if not _in_battle:
			_crossfade_menu_music(_resolve_menu_music())

## Wires [param button]'s hover + press to the semantic UI cues. Idempotent
## and shared with UIFeedback via the _UI_SFX_WIRED_META meta key: whichever
## of the two wires a given button first sets the flag, so the other backs off.
func _wire_ui_button(button: BaseButton) -> void:
	if bool(button.get_meta(_UI_SFX_WIRED_META, false)):
		return
	button.set_meta(_UI_SFX_WIRED_META, true)
	button.mouse_entered.connect(play_ui_hover)
	button.pressed.connect(_on_wired_button_pressed.bind(button))

func _on_wired_button_pressed(button: BaseButton) -> void:
	if _is_back_like(button):
		play_ui_back()
	else:
		play_ui_confirm()

## Heuristic: a button "reads" as back/cancel if its visible text or node name
## contains one of _BACK_KEYWORDS. Evaluated at press time (not wire time) so
## relabelled/localized buttons are always classified correctly.
func _is_back_like(button: BaseButton) -> bool:
	var label := String(button.name)
	if button is Button:
		label += " " + (button as Button).text
	label = label.to_lower()
	for keyword in _BACK_KEYWORDS:
		if label.contains(keyword):
			return true
	return false
