extends Resource

## Data-driven audio bank for Conquest.
##
## This Resource is the single "swap point" for all game audio. A designer can
## select the `.tres` instance of this resource in the Godot inspector and drag
## an AudioStream (.wav / .ogg / .mp3) into any slot to change that sound --
## no code changes required. Any slot left empty (null) simply plays nothing,
## so the game runs cleanly with zero audio assets present.
##
## To create additional banks (e.g. a different biome or faction), just make a
## new AudioLibrary .tres and point AudioManager.library at it.

class_name AudioLibrary

# --- SFX slots (one per game event) ---------------------------------------
@export_group("SFX")
## Played when a unit is selected.
@export var sfx_select: AudioStream
## Played when a unit finishes a move.
@export var sfx_move: AudioStream
## Played when an attack begins.
@export var sfx_attack: AudioStream
## Played when a unit takes damage (a hit lands).
@export var sfx_hit: AudioStream
## Played when a unit is healed.
@export var sfx_heal: AudioStream
## Played when a unit is eliminated / dies.
@export var sfx_death: AudioStream
## Played at the start of a unit's / player's turn.
@export var sfx_turn_start: AudioStream
## Played on victory.
@export var sfx_victory: AudioStream
## Played on defeat.
@export var sfx_defeat: AudioStream
## Light click / tick for UI + cursor movement.
@export var sfx_ui_click: AudioStream

# --- Music slots ----------------------------------------------------------
@export_group("Music")
## Looping battle / gameplay music.
@export var music_battle: AudioStream

# --- Mix settings (inspector-editable) ------------------------------------
@export_group("Mix")
## Master SFX volume in decibels (0 = unchanged, negative = quieter).
@export_range(-60.0, 12.0, 0.1) var sfx_volume_db: float = 0.0
## Master music volume in decibels.
@export_range(-60.0, 12.0, 0.1) var music_volume_db: float = -6.0
## Pitch randomization for SFX (0 = none). Adds +/- this fraction to pitch
## so repeated sounds (footsteps, cursor ticks) feel less robotic.
@export_range(0.0, 0.5, 0.01) var sfx_pitch_variance: float = 0.0

## Resolve an event name (StringName) to its AudioStream slot.
## Returns null if the slot is empty or the event is unknown -- callers must
## null-check (AudioManager does). Keeping the lookup here means the event
## vocabulary lives next to the data it maps to.
func get_stream(event_name: StringName) -> AudioStream:
	match event_name:
		&"sfx_select": return sfx_select
		&"sfx_move": return sfx_move
		&"sfx_attack": return sfx_attack
		&"sfx_hit": return sfx_hit
		&"sfx_heal": return sfx_heal
		&"sfx_death": return sfx_death
		&"sfx_turn_start": return sfx_turn_start
		&"sfx_victory": return sfx_victory
		&"sfx_defeat": return sfx_defeat
		&"sfx_ui_click": return sfx_ui_click
		_:
			return null
