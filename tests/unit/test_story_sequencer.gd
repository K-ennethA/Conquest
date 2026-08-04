extends GutTest

## PURE beat-sequencing logic for the story system: [StorySequencer] walking a [StoryScene]
## of [StoryBeat]s. No scene tree, no overlay, no wall clock -- time enters only through
## [method StorySequencer.tick], which is the whole point of splitting this state machine
## out of [StoryDialogue] (tests/README.md rule 7: no wall-clock waiting).
##
## Everything here is a [Resource] or a [RefCounted], so nothing can orphan.

const CPS: float = 40.0

var _seq: StorySequencer = null


func before_each() -> void:
	_seq = StorySequencer.new()
	_seq.chars_per_second = CPS


func after_each() -> void:
	_seq = null


# --- Fixtures ---------------------------------------------------------------

func _beat(text: String, speaker: StringName = &"vineweave",
		side: StringName = StoryBeat.SIDE_LEFT) -> StoryBeat:
	var beat := StoryBeat.new()
	beat.speaker_id = speaker
	beat.side = side
	beat.text = text
	return beat


func _scene(beats: Array) -> StoryScene:
	var scene := StoryScene.new()
	scene.scene_id = &"test_scene"
	var typed: Array[Resource] = []
	for b in beats:
		typed.append(b)
	scene.beats = typed
	return scene


# --- Starting ---------------------------------------------------------------

func test_start_refuses_a_null_scene() -> void:
	assert_false(_seq.start(null), "there is nothing to play, so start reports failure")
	assert_true(_seq.is_finished(), "and the sequencer stays in its finished/idle state")
	assert_eq(_seq.index(), -1, "with no beat selected")


func test_start_refuses_a_scene_whose_beats_are_all_null() -> void:
	var scene := _scene([null, null])
	assert_true(scene.is_empty(), "a scene of null holes counts as empty")
	assert_false(_seq.start(scene), "so it is refused rather than mounted blank")


func test_start_skips_null_holes_and_plays_the_real_beats() -> void:
	var scene := _scene([null, _beat("one"), null, _beat("two")])
	assert_true(_seq.start(scene), "a scene with real beats plays")
	assert_eq(_seq.beat_count(), 2, "the two null holes are dropped, not counted")
	assert_eq(_seq.current_beat().text, "one", "and the first REAL beat opens")


func test_the_first_beat_opens_revealing_with_no_text_shown_yet() -> void:
	_seq.start(_scene([_beat("hello")]))
	assert_eq(_seq.index(), 0, "playback opens on beat 0")
	assert_true(_seq.is_revealing(), "the typewriter is running")
	assert_false(_seq.is_holding(), "so the line is not yet waiting for a tap")
	assert_eq(_seq.visible_text(), "", "and no character has typed out at t=0")


# --- The typewriter clock ----------------------------------------------------

func test_ticking_reveals_exactly_rate_times_delta_characters() -> void:
	_seq.start(_scene([_beat("abcdefghij")]))
	_seq.tick(0.1)   # 0.1s * 40 chars/s = 4 characters
	assert_eq(_seq.visible_text(), "abcd", "a tenth of a second types four characters at 40/s")
	_seq.tick(0.05)  # +2
	assert_eq(_seq.visible_text(), "abcdef", "and the reveal accumulates across ticks")


func test_a_sub_character_tick_is_not_lost_to_truncation() -> void:
	_seq.start(_scene([_beat("abcdefghij")]))
	for i in range(4):
		_seq.tick(0.00625)   # 0.25 characters each -- four of them make exactly one
	assert_eq(_seq.visible_text(), "a", "four quarter-character ticks add up to one character")


func test_the_clock_completes_the_line_and_stops_there() -> void:
	var scene := _scene([_beat("abcde")])
	_seq.start(scene)
	var completed: Array = []
	_seq.reveal_completed.connect(func(index: int) -> void: completed.append(index))

	_seq.tick(10.0)   # far past the 0.125s this line needs
	assert_false(_seq.is_revealing(), "the line is fully typed")
	assert_true(_seq.is_holding(), "so it is now waiting for a tap")
	assert_eq(_seq.visible_text(), "abcde", "and the whole line is shown, never overrun")
	assert_eq(completed.size(), 1, "reveal_completed fired exactly once")

	_seq.tick(10.0)
	assert_eq(completed.size(), 1, "ticking a finished reveal fires nothing further")


func test_a_zero_length_line_opens_already_held() -> void:
	_seq.start(_scene([_beat(""), _beat("second")]))
	assert_false(_seq.is_revealing(), "an empty line has nothing to type")
	assert_true(_seq.is_holding(), "so the first tap advances instead of completing nothing")
	assert_eq(_seq.advance(), StorySequencer.Action.ADVANCED, "and that tap does advance")


func test_a_non_positive_rate_means_no_typewriter_at_all() -> void:
	_seq.chars_per_second = 0.0
	_seq.start(_scene([_beat("instant")]))
	_seq.tick(0.001)
	assert_eq(_seq.visible_text(), "instant", "rate 0 shows the whole line on the first tick")


# --- The tap: complete, then advance -----------------------------------------

func test_the_first_tap_completes_the_typewriter_and_the_second_advances() -> void:
	_seq.start(_scene([_beat("a long first line"), _beat("second line")]))
	_seq.tick(0.05)   # two characters in

	assert_eq(_seq.advance(), StorySequencer.Action.COMPLETED_REVEAL,
		"tapping mid-reveal completes the typewriter")
	assert_eq(_seq.visible_text(), "a long first line", "the whole line is shown at once")
	assert_eq(_seq.index(), 0, "and we are still on the SAME beat")

	assert_eq(_seq.advance(), StorySequencer.Action.ADVANCED,
		"the next tap moves on")
	assert_eq(_seq.index(), 1, "to beat 1")
	assert_eq(_seq.visible_text(), "", "whose typewriter starts over from nothing")


func test_completing_the_reveal_by_tap_announces_it_once() -> void:
	_seq.start(_scene([_beat("abcde")]))
	var completed: Array = []
	_seq.reveal_completed.connect(func(index: int) -> void: completed.append(index))
	_seq.advance()
	assert_eq(completed, [0], "a tap-completed reveal announces itself exactly like a clocked one")


func test_advancing_past_the_last_beat_finishes_unskipped() -> void:
	_seq.start(_scene([_beat("only")]))
	var finishes: Array = []
	_seq.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_seq.advance()   # completes the reveal
	assert_eq(_seq.advance(), StorySequencer.Action.FINISHED, "dismissing the last beat ends it")
	assert_eq(finishes, [false], "finished fired once, reporting a read-through not a skip")
	assert_true(_seq.is_finished(), "and the sequencer is idle")
	assert_eq(_seq.visible_text(), "", "with nothing left on screen")


func test_beat_changed_fires_for_every_beat_including_the_first() -> void:
	_seq.start(_scene([_beat("one"), _beat("two"), _beat("three")]))
	var seen: Array = []
	_seq.beat_changed.connect(func(index: int) -> void: seen.append(index))
	# Beat 0 already opened inside start(), before this connection -- so drive the rest.
	_seq.advance(); _seq.advance()
	_seq.advance(); _seq.advance()
	assert_eq(seen, [1, 2], "each advance opens exactly one new beat, in order")


func test_tapping_a_finished_sequencer_does_nothing() -> void:
	_seq.start(_scene([_beat("only")]))
	_seq.skip()
	assert_eq(_seq.advance(), StorySequencer.Action.NONE, "a finished script ignores input")


# --- Skip --------------------------------------------------------------------

func test_skip_abandons_the_whole_scene_from_the_middle() -> void:
	_seq.start(_scene([_beat("one"), _beat("two"), _beat("three")]))
	var finishes: Array = []
	_seq.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_seq.skip()
	assert_eq(finishes, [true], "finished fired once, flagged as a skip")
	assert_true(_seq.was_skipped(), "and the sequencer reports the playthrough was skipped")
	assert_true(_seq.is_finished(), "the remaining beats are dropped, not queued")
	assert_null(_seq.current_beat(), "with no beat left on screen")


func test_skip_is_idempotent() -> void:
	_seq.start(_scene([_beat("one")]))
	var finishes: Array = []
	_seq.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))
	_seq.skip()
	_seq.skip()
	assert_eq(finishes.size(), 1, "a second skip fires nothing -- the script is already over")


func test_restarting_resets_every_counter() -> void:
	_seq.start(_scene([_beat("one"), _beat("two")]))
	_seq.advance(); _seq.advance()
	assert_eq(_seq.index(), 1, "we walked to the second beat")

	_seq.start(_scene([_beat("fresh")]))
	assert_eq(_seq.index(), 0, "a restart opens beat 0 again")
	assert_eq(_seq.beat_count(), 1, "on the NEW scene's beats")
	assert_false(_seq.was_skipped(), "and the previous run's skip flag is cleared")


# --- Progress ----------------------------------------------------------------

func test_reveal_progress_reports_the_fraction_typed() -> void:
	_seq.start(_scene([_beat("abcdefghij")]))   # 10 chars
	_seq.tick(0.125)                            # 5 chars
	assert_almost_eq(_seq.reveal_progress(), 0.5, 0.001, "half the line is typed")
	_seq.advance()
	assert_eq(_seq.reveal_progress(), 1.0, "completing the reveal reads as fully typed")


func test_reveal_progress_of_an_empty_line_is_complete_not_a_division_by_zero() -> void:
	_seq.start(_scene([_beat("")]))
	assert_eq(_seq.reveal_progress(), 1.0, "an empty line is trivially fully revealed")


# --- Beat schema helpers ------------------------------------------------------

func test_a_narrator_beat_hides_portraits_and_has_no_name_plate() -> void:
	var beat := _beat("The forest goes quiet.", StoryBeat.NARRATOR)
	assert_true(beat.is_narrator(), "the reserved narrator id marks the line unattributed")
	assert_true(beat.hides_portraits(), "so no portrait is staged for it")
	assert_eq(beat.resolved_speaker_name(), "", "and there is no name to plate")


func test_clear_portraits_wipes_the_stage_for_an_attributed_line() -> void:
	var beat := _beat("A voice from the roots.")
	beat.clear_portraits = true
	assert_false(beat.is_narrator(), "the line still has a speaker")
	assert_true(beat.hides_portraits(), "but the author asked for an empty stage anyway")


func test_an_authored_name_override_beats_the_roster_lookup() -> void:
	var beat := _beat("...", &"blightcap")
	beat.speaker_name = "Something in the Ferns"
	assert_eq(beat.resolved_speaker_name(), "Something in the Ferns",
		"an override is how a character is introduced before the player knows its name")


func test_side_normalises_to_one_of_the_two_slots() -> void:
	assert_eq(_beat("x", &"a", StoryBeat.SIDE_RIGHT).resolved_side(), StoryBeat.SIDE_RIGHT,
		"an explicit right stays right")
	assert_eq(_beat("x", &"a", &"nonsense").resolved_side(), StoryBeat.SIDE_LEFT,
		"anything unrecognised falls back to left, so no beat is left off-stage")


func test_reveal_duration_is_the_no_input_runtime_of_a_scene() -> void:
	var scene := _scene([_beat("abcd"), _beat("efghijkl")])   # 4 + 8 = 12 chars
	assert_almost_eq(scene.total_reveal_duration(CPS), 0.3, 0.001,
		"twelve characters at 40/s is 0.3 seconds of typing")
