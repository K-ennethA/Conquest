class_name StoryScene
extends Resource

## An ordered script of [StoryBeat]s -- one conversation. Authored as a [code].tres[/code]
## under [code]game/campaign/story/[/code] and played by [StoryDialogue] (which walks it
## through [StorySequencer]).
##
## Deliberately CONTEXT-FREE: a scene knows nothing about chapters, battles or menus. The
## campaign wires two of them onto a chapter ([code]intro_scene[/code] /
## [code]outro_scene[/code] in [CampaignData]); a future mid-battle trigger will hand the
## same overlay a scene the same way, with nothing here to change.
##
## TRUST: these are shipped project resources, not player content -- see the note on
## [StoryBeat] for why a plain [Resource] is the right shape and what would have to change
## if story scripts ever became downloadable.

## Stable key for this scene ("ch1_intro"). Used for logging / future "already seen" gating;
## nothing keys off it today.
@export var scene_id: StringName = &""

## Human-readable title, for authoring convenience and debug output.
@export var title: String = ""

## [AudioManager] event fired once as the scene OPENS, before the first beat's own cue.
## Empty means "leave the current bed alone" -- the common case, since a chapter intro plays
## over the menu music that is already running.
@export var music_cue: StringName = &""

## The beats, in play order.
##
## Typed [code]Array[Resource][/code] rather than [code]Array[StoryBeat][/code] ON PURPOSE.
## These scenes are hand-authored [code].tres[/code] files, and a script-class-typed array
## serialises to the engine's verbose [code]Array[Object]("Resource", <path>, <uid>, [...])[/code]
## form, which is miserable to write and breaks the moment the script's UID changes. The
## [Resource]-typed form is the plain, stable [code]Array[Resource]([SubResource(...)])[/code]
## literal. Element type is enforced at READ time instead -- [method playable_beats] keeps
## only real [StoryBeat]s -- so a mistyped entry is skipped rather than crashing playback
## (and see CONQUEST.md #3 for why a plain Array is never assigned to a typed one).
@export var beats: Array[Resource] = []


func beat_count() -> int:
	return beats.size()


## The beat at [param index], or null when out of range / not a [StoryBeat] (so a caller can
## bound-check by null rather than by arithmetic).
func beat_at(index: int) -> StoryBeat:
	if index < 0 or index >= beats.size():
		return null
	return beats[index] as StoryBeat


## True when there is nothing to play. A scene whose beats are all null (or all the wrong
## type) counts as empty too -- an authoring slip must not put an overlay on screen with no
## line in it.
func is_empty() -> bool:
	return playable_beats().is_empty()


## Every real, non-null beat, in order. The sequencer walks THIS rather than [member beats],
## so a hole left by a deleted sub-resource skips rather than crashing the playback.
func playable_beats() -> Array[StoryBeat]:
	var out: Array[StoryBeat] = []
	for entry in beats:
		var beat: StoryBeat = entry as StoryBeat
		if beat != null:
			out.append(beat)
	return out


## Total seconds every line would take to type out at [param chars_per_second] -- the
## no-input runtime of the scene. Used by tests to bound a clock loop; nothing in the
## runtime auto-advances.
func total_reveal_duration(chars_per_second: float) -> float:
	var total: float = 0.0
	for beat in playable_beats():
		total += beat.reveal_duration(chars_per_second)
	return total
