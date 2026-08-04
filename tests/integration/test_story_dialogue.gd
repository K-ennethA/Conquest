extends GutTest

## THE REAL [StoryDialogue] OVERLAY, mounted in a real tree, asserted on its RENDERED nodes.
##
## Per the project rule recorded after two incidents: screen UI is only proven by mounting
## the actual node and reading back what it laid out -- sizes, texts, visibility, counts --
## never by calling a static helper and trusting the layout followed. So every assertion
## here goes through the overlay's own node accessors after a real layout pass.
##
## THE CLOCK IS INJECTED: [member StoryDialogue.auto_tick] is off in every test and time is
## fed in with [method StoryDialogue.advance_clock], so the typewriter is driven to exact
## positions with no wall-clock waiting (tests/README.md rule 7).
##
## ANIMATIONS are forced OFF through the guard for the layout tests, so a portrait's asserted
## position is its resting position rather than wherever a 0.25s tween happened to be. One
## test deliberately turns them back ON to prove the slide-in starts off-stage.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

const CPS: float = StorySequencer.DEFAULT_CHARS_PER_SECOND

## Untyped on purpose -- see tests/README.md rule 3.
var _guard

var _overlay: StoryDialogue = null


func before_each() -> void:
	_guard = Guard.new()
	# Deterministic layout: no slide tween, panels sit at their resting positions.
	_guard.set_setting("animations_enabled", false)

	_overlay = StoryDialogue.new()
	add_child_autofree(_overlay)
	_overlay.auto_tick = false


func after_each() -> void:
	_overlay = null
	# get_portrait() lazily creates a PortraitCache node under the current scene; without
	# this it leaks into the next suite (see PortraitCache.reset's own doc).
	PortraitCache.reset()
	_guard.restore()


# --- Fixtures ---------------------------------------------------------------

func _beat(text: String, speaker: StringName, side: StringName,
		name_override: String = "") -> StoryBeat:
	var beat := StoryBeat.new()
	beat.speaker_id = speaker
	beat.side = side
	beat.text = text
	beat.speaker_name = name_override
	return beat


func _scene(beats: Array) -> StoryScene:
	var scene := StoryScene.new()
	scene.scene_id = &"test_overlay_scene"
	var typed: Array[Resource] = []
	for b in beats:
		typed.append(b)
	scene.beats = typed
	return scene


## The three-beat conversation every test below drives: a left speaker, a right answer,
## then an unattributed narrator line that must wipe the stage.
func _two_hander() -> StoryScene:
	return _scene([
		_beat("The rot has reached the treeline.", &"vineweave", StoryBeat.SIDE_LEFT),
		_beat("Something coughs under the ferns.", &"blightcap", StoryBeat.SIDE_RIGHT,
			"Something in the Ferns"),
		_beat("Far to the east, something very old does not hurry.", StoryBeat.NARRATOR,
			StoryBeat.SIDE_LEFT),
	])


## Run the injected clock far enough to finish the CURRENT beat's typewriter.
func _finish_reveal() -> void:
	var beat: StoryBeat = _overlay.sequencer().current_beat()
	if beat == null:
		return
	_overlay.advance_clock(beat.reveal_duration(CPS) + 0.01)


# --- Mounting ----------------------------------------------------------------

func test_the_overlay_mounts_on_its_own_layer_hidden_until_played() -> void:
	await get_tree().process_frame
	assert_eq(_overlay.layer, 135, "the overlay sits above the battle HUD and below SceneFade")
	assert_eq(_overlay.process_mode, Node.PROCESS_MODE_ALWAYS,
		"so it keeps running while the game-over screen has the tree paused")
	assert_false(_overlay.root_control().visible,
		"nothing is on screen before a scene is played")


func test_playing_an_empty_scene_shows_nothing_and_reports_it() -> void:
	assert_false(_overlay.play(_scene([])), "an empty scene is refused")
	assert_false(_overlay.play(null), "and so is a null one")
	await get_tree().process_frame
	assert_false(_overlay.root_control().visible, "so the input blocker never goes up")


# --- Rendered structure -------------------------------------------------------

func test_the_first_beat_stages_its_speaker_on_the_LEFT_only() -> void:
	assert_true(_overlay.play(_two_hander()), "the scene plays")
	await get_tree().process_frame

	assert_true(_overlay.root_control().visible, "the full-rect input blocker is up")
	assert_true(_overlay.is_side_visible(StoryBeat.SIDE_LEFT),
		"the left portrait panel is on stage")
	assert_false(_overlay.is_side_visible(StoryBeat.SIDE_RIGHT),
		"and the right side is still empty -- nobody has answered yet")
	assert_true(_overlay.is_side_active(StoryBeat.SIDE_LEFT),
		"the left speaker is the ACTIVE one")
	assert_true(_overlay.portrait_content_visible(StoryBeat.SIDE_LEFT),
		"the panel shows a portrait, or the monogram badge that stands in for one headless")


func test_the_portrait_panels_lay_out_at_their_authored_size_on_opposite_edges() -> void:
	_overlay.play(_two_hander())
	_overlay.advance_clock(10.0)   # complete beat 0
	_overlay.advance()             # -> beat 1, the right-hand speaker
	await get_tree().process_frame

	var left: PanelContainer = _overlay.portrait_panel(StoryBeat.SIDE_LEFT)
	var right: PanelContainer = _overlay.portrait_panel(StoryBeat.SIDE_RIGHT)
	assert_eq(left.size, Vector2(StoryDialogue.PORTRAIT_WIDTH, StoryDialogue.PORTRAIT_HEIGHT),
		"the left panel keeps its authored 720p size")
	assert_eq(right.size, Vector2(StoryDialogue.PORTRAIT_WIDTH, StoryDialogue.PORTRAIT_HEIGHT),
		"and so does the right one")

	var root_width: float = _overlay.root_control().size.x
	assert_almost_eq(left.position.x, StoryDialogue.EDGE_MARGIN, 0.5,
		"the left panel rests against the left edge")
	assert_almost_eq(right.position.x,
		root_width - StoryDialogue.EDGE_MARGIN - StoryDialogue.PORTRAIT_WIDTH, 0.5,
		"and the right panel mirrors it against the right edge")
	assert_gt(right.position.x, left.position.x + StoryDialogue.PORTRAIT_WIDTH,
		"the two panels never overlap")


func test_the_text_box_spans_the_bottom_at_a_fixed_height() -> void:
	_overlay.play(_two_hander())
	await get_tree().process_frame

	var root: Control = _overlay.root_control()
	var box: PanelContainer = _overlay.text_box()
	assert_almost_eq(box.size.x, root.size.x - 2.0 * StoryDialogue.EDGE_MARGIN, 0.5,
		"the box spans the viewport width inside its margins")
	assert_almost_eq(box.size.y, StoryDialogue.TEXTBOX_HEIGHT, 0.5,
		"at the fixed height that stops the stage jumping between a short and a long line")
	assert_gt(_overlay.text_label().size.x, 100.0,
		"and the wrapping body label really occupies that width -- it did not collapse to a minimum")


# --- Active / dim ------------------------------------------------------------

func test_the_listening_speaker_stays_on_stage_dimmed_and_settled() -> void:
	_overlay.play(_two_hander())
	_overlay.advance_clock(10.0)
	_overlay.advance()             # -> beat 1, right-hand speaker answers
	await get_tree().process_frame

	var left: PanelContainer = _overlay.portrait_panel(StoryBeat.SIDE_LEFT)
	var right: PanelContainer = _overlay.portrait_panel(StoryBeat.SIDE_RIGHT)

	assert_true(left.visible, "the first speaker stays on stage -- this is a conversation")
	assert_false(_overlay.is_side_active(StoryBeat.SIDE_LEFT), "but is no longer the speaker")
	assert_true(_overlay.is_side_active(StoryBeat.SIDE_RIGHT), "the right side has the line")

	assert_eq(right.modulate, StoryDialogue.PORTRAIT_ACTIVE_MODULATE,
		"the active speaker is full-bright")
	assert_eq(left.modulate, StoryDialogue.PORTRAIT_DIM_MODULATE,
		"and the listener is dimmed back")
	assert_almost_eq(right.position.y, left.position.y - StoryDialogue.ACTIVE_LIFT_PX, 0.5,
		"the active speaker also sits slightly forward of the listener")


func test_a_beats_tint_multiplies_over_the_active_speaker() -> void:
	var beat := _beat("A sickly green cast.", &"blightcap", StoryBeat.SIDE_RIGHT)
	beat.tint = Color(0.5, 1.0, 0.5, 1.0)
	_overlay.play(_scene([beat]))
	await get_tree().process_frame

	assert_eq(_overlay.portrait_panel(StoryBeat.SIDE_RIGHT).modulate,
		StoryDialogue.PORTRAIT_ACTIVE_MODULATE * beat.tint,
		"the authored tint is applied on top of the full-bright active modulate")


func test_a_narrator_beat_clears_both_portraits_and_the_name_plate() -> void:
	_overlay.play(_two_hander())
	for i in range(2):
		_overlay.advance_clock(10.0)   # complete the current line
		_overlay.advance()             # ...and move on: beat 0 -> 1 -> 2 (the narrator line)
	await get_tree().process_frame

	assert_eq(_overlay.sequencer().index(), 2, "we are on the narrator beat")
	assert_false(_overlay.is_side_visible(StoryBeat.SIDE_LEFT), "the left portrait is gone")
	assert_false(_overlay.is_side_visible(StoryBeat.SIDE_RIGHT), "and so is the right one")
	assert_eq(_overlay.name_label().text, "",
		"an unattributed line carries no name, so the plate has nothing to print")


# --- The typewriter, on the injected clock ------------------------------------

func test_the_text_box_fills_in_only_as_the_injected_clock_runs() -> void:
	var scene := _two_hander()
	_overlay.play(scene)
	await get_tree().process_frame

	assert_eq(_overlay.text_label().text, "",
		"no character has typed out before the clock is advanced")

	_overlay.advance_clock(0.1)   # 4 characters at 40/s
	assert_eq(_overlay.text_label().text, "The ",
		"the rendered label shows exactly the revealed prefix")

	_finish_reveal()
	await get_tree().process_frame
	assert_eq(_overlay.text_label().text, scene.beat_at(0).text,
		"and the whole beat text is rendered once the typewriter completes")
	assert_true(_overlay.sequencer().is_holding(), "the line is now waiting for a tap")


func test_the_first_tap_completes_the_line_and_the_second_moves_on() -> void:
	var scene := _two_hander()
	_overlay.play(scene)
	_overlay.advance_clock(0.05)
	await get_tree().process_frame

	_overlay.advance()
	await get_tree().process_frame
	assert_eq(_overlay.text_label().text, scene.beat_at(0).text,
		"the first tap snaps the typewriter to the whole line")
	assert_eq(_overlay.sequencer().index(), 0, "without leaving the beat")

	_overlay.advance()
	await get_tree().process_frame
	assert_eq(_overlay.sequencer().index(), 1, "the second tap advances")
	assert_eq(_overlay.name_label().text, "Something in the Ferns",
		"and the name plate re-renders with the new speaker's authored name")
	assert_eq(_overlay.text_label().text, "", "with its typewriter starting over")


# --- Finishing / skipping ------------------------------------------------------

func test_reading_to_the_end_tears_the_stage_down_and_reports_a_read_through() -> void:
	var finishes: Array = []
	_overlay.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_overlay.play(_two_hander())
	for i in range(3):
		_overlay.advance_clock(10.0)
		_overlay.advance()   # completes the (already complete) reveal / advances
	await get_tree().process_frame

	assert_eq(finishes, [false], "finished fired once, reporting a read-through")
	assert_false(_overlay.root_control().visible, "the overlay stopped blocking the screen")
	assert_eq(_overlay.text_label().text, "", "the text box is cleared")


func test_skipping_tears_the_stage_down_immediately() -> void:
	var finishes: Array = []
	_overlay.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_overlay.play(_two_hander())
	_overlay.advance_clock(0.05)
	await get_tree().process_frame
	assert_true(_overlay.root_control().visible, "the scene is up")

	_overlay.skip()
	await get_tree().process_frame

	assert_eq(finishes, [true], "finished fired once, flagged as a skip")
	assert_false(_overlay.root_control().visible, "the root -- and its input block -- is down")
	assert_false(_overlay.is_side_visible(StoryBeat.SIDE_LEFT), "the left portrait is released")
	assert_false(_overlay.is_side_visible(StoryBeat.SIDE_RIGHT), "and the right one too")
	assert_eq(_overlay.name_label().text, "", "and the name plate is blank")


func test_the_skip_button_is_rendered_and_skips_the_whole_scene() -> void:
	var finishes: Array = []
	_overlay.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_overlay.play(_two_hander())
	await get_tree().process_frame

	var button: Button = _overlay.skip_button()
	assert_eq(button.text, "SKIP", "the skip affordance is labelled")
	assert_gt(button.size.x, 0.0, "and really occupies space on screen")

	button.pressed.emit()
	await get_tree().process_frame
	assert_eq(finishes, [true], "pressing it abandons the scene, no confirmation")


func test_holding_cancel_for_the_authored_duration_skips_on_the_injected_clock() -> void:
	var finishes: Array = []
	_overlay.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_overlay.play(_two_hander())
	_overlay.set_cancel_held(true)

	_overlay.advance_clock(StoryDialogue.SKIP_HOLD_SECONDS * 0.5)
	assert_eq(finishes.size(), 0, "half the hold is not a skip -- a tap on ESC must not bail")

	_overlay.advance_clock(StoryDialogue.SKIP_HOLD_SECONDS)
	assert_eq(finishes, [true], "holding past the threshold abandons the scene")


func test_releasing_cancel_resets_the_hold() -> void:
	var finishes: Array = []
	_overlay.finished.connect(func(skipped: bool) -> void: finishes.append(skipped))

	_overlay.play(_two_hander())
	_overlay.set_cancel_held(true)
	_overlay.advance_clock(StoryDialogue.SKIP_HOLD_SECONDS * 0.9)
	_overlay.set_cancel_held(false)
	_overlay.advance_clock(StoryDialogue.SKIP_HOLD_SECONDS * 0.9)

	assert_eq(finishes.size(), 0,
		"two near-threshold holds with a release between them never add up to a skip")


# --- Reduced motion -----------------------------------------------------------

func test_animations_off_places_the_portrait_at_rest_with_no_tween() -> void:
	# animations_enabled is already false (set in before_each).
	_overlay.play(_two_hander())
	await get_tree().process_frame
	assert_almost_eq(_overlay.portrait_panel(StoryBeat.SIDE_LEFT).position.x,
		StoryDialogue.EDGE_MARGIN, 0.5,
		"with animations off the panel is snapped to its resting position, never mid-slide")


func test_animations_on_starts_the_portrait_off_stage_so_it_can_slide_in() -> void:
	_guard.set_setting("animations_enabled", true)
	_overlay.play(_two_hander())
	# Read BEFORE any frame processes, so the tween has not stepped yet.
	assert_lt(_overlay.portrait_panel(StoryBeat.SIDE_LEFT).position.x, 0.0,
		"the left panel starts fully outside the left edge, so it slides in from its own side")
	await get_tree().process_frame
