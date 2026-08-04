class_name StorySequencer
extends RefCounted

## The BEAT STATE MACHINE behind [StoryDialogue] -- which line is up, how much of it has
## typed out, and what the next tap does. Pure [RefCounted]: no nodes, no tree, no
## [code]get_ticks_msec[/code]. Time only ever enters through [method tick], so the whole
## interaction model is testable at exact clock positions with no wall-clock waiting (see
## tests/README.md rule 7).
##
## THE THREE STATES, and the one interaction rule that produces them:
## [codeblock]
## REVEALING  the line is typing out   -- tap COMPLETES the typewriter
## HOLDING    the line is fully shown  -- tap ADVANCES to the next beat
## FINISHED   the script is over       -- tap does nothing
## [/codeblock]
## That is the whole "first tap completes, second advances" contract: [method advance] is
## the ONE input entry point and it branches on the state, so a click, a space bar, a tap
## and a controller button all mean the same thing without the caller knowing which state
## it is in.
##
## SKIP is separate ([method skip]): it jumps straight to FINISHED from anywhere, no
## confirmation, and reports itself through [signal finished]'s [code]skipped[/code] flag so
## a caller can tell "the player read it" from "the player bailed".
##
## A beat with EMPTY text has a zero-length reveal, so it opens directly in HOLDING -- the
## first tap advances it rather than completing nothing.

## What [method advance] just did, so a caller can react (play a page-turn cue, etc.)
## without re-deriving the state.
enum Action {
	NONE,               ## nothing was playing
	COMPLETED_REVEAL,   ## the typewriter was snapped to the full line
	ADVANCED,           ## moved on to the next beat
	FINISHED,           ## the last beat was dismissed; the script is over
}

## Default typewriter rate. ~40 chars/s is the Fire-Emblem-ish pace this system is tuned
## for: fast enough to read along with, slow enough that completing it early feels useful.
const DEFAULT_CHARS_PER_SECOND: float = 40.0

## Emitted when a NEW beat opens (including the first). Carries its index into
## [method StoryScene.playable_beats].
signal beat_changed(index: int)
## Emitted the moment the current beat's text is fully revealed -- whether the clock got
## there or [method advance] snapped it.
signal reveal_completed(index: int)
## Emitted exactly once per playthrough. [param skipped] is true only for [method skip].
signal finished(skipped: bool)

## Typewriter rate in characters per second. <= 0 means "no typewriter": every beat opens
## fully revealed. Assignable so a future accessibility setting can drive it.
var chars_per_second: float = DEFAULT_CHARS_PER_SECOND

## The beats being walked (null-holes already stripped -- see [method StoryScene.playable_beats]).
var _beats: Array[StoryBeat] = []
## Index of the beat currently on screen; -1 before [method start] and after finishing.
var _index: int = -1
## Characters revealed so far, as a FLOAT so a sub-character tick is not lost to truncation.
var _revealed: float = 0.0
var _finished: bool = true
var _skipped: bool = false


# --- Lifecycle ---------------------------------------------------------------

## Begin playing [param scene]. Returns false (leaving the sequencer FINISHED, and emitting
## nothing) when there is nothing to play -- a null scene or one with no non-null beats. A
## caller uses that answer to skip mounting an overlay at all.
##
## Restarting is legal: a second call resets every counter, so one sequencer can play a
## chapter's intro and later its outro.
func start(scene: StoryScene) -> bool:
	_beats = []
	_index = -1
	_revealed = 0.0
	_finished = true
	_skipped = false

	if scene == null:
		return false
	var playable: Array[StoryBeat] = scene.playable_beats()
	if playable.is_empty():
		return false

	_beats = playable
	_finished = false
	_open_beat(0)
	return true


## Open beat [param index]: reset the typewriter and announce it. A zero-length line
## reports its reveal as already complete in the same call, which is what puts an empty
## beat straight into HOLDING.
func _open_beat(index: int) -> void:
	_index = index
	_revealed = 0.0
	beat_changed.emit(_index)
	if _reveal_target() <= 0.0:
		_revealed = 0.0
		reveal_completed.emit(_index)


# --- Clock -------------------------------------------------------------------

## Advance the typewriter by [param delta] seconds. THE ONLY way time enters this class.
## No-op once finished, once the current line is fully revealed, or for a non-positive
## delta. Emits [signal reveal_completed] on the tick that finishes the line.
func tick(delta: float) -> void:
	if _finished or delta <= 0.0:
		return
	if not is_revealing():
		return
	if chars_per_second <= 0.0:
		_revealed = _reveal_target()
		reveal_completed.emit(_index)
		return

	_revealed = minf(_revealed + delta * chars_per_second, _reveal_target())
	if not is_revealing():
		reveal_completed.emit(_index)


# --- Input -------------------------------------------------------------------

## THE ONE INPUT ENTRY POINT -- click, tap, space, controller accept all land here.
## Completes the typewriter when the line is still typing; otherwise moves on (finishing
## the script when the last line is dismissed). Returns what it did.
func advance() -> Action:
	if _finished:
		return Action.NONE

	if is_revealing():
		_revealed = _reveal_target()
		reveal_completed.emit(_index)
		return Action.COMPLETED_REVEAL

	if _index + 1 < _beats.size():
		_open_beat(_index + 1)
		return Action.ADVANCED

	_finish(false)
	return Action.FINISHED


## Abandon the whole script immediately (hold-ESC / the SKIP button). No confirmation by
## design -- a skipped story is recoverable, a confirm dialog over a cutscene is not worth
## the friction. Idempotent.
func skip() -> void:
	if _finished:
		return
	_finish(true)


func _finish(skipped: bool) -> void:
	_finished = true
	_skipped = skipped
	_index = -1
	_revealed = 0.0
	finished.emit(skipped)


# --- Queries -----------------------------------------------------------------

## Index of the beat on screen, or -1 when nothing is playing.
func index() -> int:
	return _index


## Total playable beats in the running scene (0 when nothing is playing).
func beat_count() -> int:
	return _beats.size()


## The beat on screen, or null when nothing is playing.
func current_beat() -> StoryBeat:
	if _index < 0 or _index >= _beats.size():
		return null
	return _beats[_index]


## The prefix of the current line the typewriter has exposed so far. "" when nothing is
## playing; the WHOLE line once the reveal is complete.
func visible_text() -> String:
	var beat: StoryBeat = current_beat()
	if beat == null:
		return ""
	if not is_revealing():
		return beat.text
	return beat.text.substr(0, int(_revealed))


## True while the current line is still typing out. False when nothing is playing (there is
## no reveal in progress) and false once the line is whole.
func is_revealing() -> bool:
	if _finished:
		return false
	return _revealed < _reveal_target()


## True when the current line is fully shown and the next tap will move on. The exact
## complement of [method is_revealing] while a scene is playing.
func is_holding() -> bool:
	return not _finished and not is_revealing()


func is_finished() -> bool:
	return _finished


## True when the playthrough ended via [method skip] rather than by reading to the end.
## Meaningless before [signal finished] has fired.
func was_skipped() -> bool:
	return _skipped


## Fraction of the current line revealed, 0..1. 1.0 when nothing is playing or the line is
## empty, so a progress-driven caller never divides by zero.
func reveal_progress() -> float:
	var target: float = _reveal_target()
	if target <= 0.0:
		return 1.0
	return clampf(_revealed / target, 0.0, 1.0)


func _reveal_target() -> float:
	var beat: StoryBeat = current_beat()
	if beat == null:
		return 0.0
	return float(beat.text_length())
