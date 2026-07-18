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

var _sfx_players: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _music_player: AudioStreamPlayer

func _ready() -> void:
	name = "AudioManager"

	# Fall back to a fresh empty library if none was assigned, so the API never
	# dereferences null.
	if library == null:
		library = AudioLibrary.new()

	_build_players()
	_connect_events()

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

# --- Public API ------------------------------------------------------------

## Play the SFX mapped to [param event_name] (e.g. &"sfx_attack").
## No-op when the library slot is empty or the event is unknown -- safe to call
## for events that have no sound assigned yet.
func play_sfx(event_name: StringName) -> void:
	if library == null:
		return
	var stream := library.get_stream(event_name)
	if stream == null:
		return
	_play_stream_on_free_voice(stream)

## Play an explicit AudioStream through the SFX pool (bypasses the library map).
func play_stream(stream: AudioStream) -> void:
	if stream == null:
		return
	_play_stream_on_free_voice(stream)

## Start (or restart) music. Pass an AudioStream, or omit to use
## library.music_battle. No-op when the resolved stream is null.
func play_music(stream: AudioStream = null) -> void:
	if _music_player == null:
		return
	var to_play := stream
	if to_play == null and library != null:
		to_play = library.music_battle
	if to_play == null:
		return
	_music_player.stream = to_play
	if library != null:
		_music_player.volume_db = library.music_volume_db
	_music_player.play()

## Stop music playback.
func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()

# --- Internal --------------------------------------------------------------

func _play_stream_on_free_voice(stream: AudioStream) -> void:
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
	player.volume_db = library.sfx_volume_db if library != null else 0.0
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
	play_sfx(&"sfx_ui_click")

func _on_cursor_selected(_position = null) -> void:
	play_sfx(&"sfx_ui_click")

func _on_combat_initiated(_attacker = null, _defender = null) -> void:
	play_sfx(&"sfx_attack")

func _on_damage_dealt(_attacker = null, _defender = null, _damage = null) -> void:
	play_sfx(&"sfx_hit")

func _on_unit_eliminated(_unit = null, _eliminator = null) -> void:
	play_sfx(&"sfx_death")

func _on_game_started() -> void:
	# Kick off battle music if one is assigned.
	play_music()

func _on_game_ended(_winner = null) -> void:
	stop_music()
