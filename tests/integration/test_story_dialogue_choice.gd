extends GutTest

## StoryDialogue.play_choice -- the one StoryDialogue extension story mode needed, proven on the
## REAL overlay with the injected clock (auto_tick off): options appear only once the prompt is
## revealed, a press never advances past them, number keys / buttons / confirm pick, cancel picks
## the cancel option, and the pick emits choice_made then finished(false).

const Guard := preload("res://tests/helpers/global_state_guard.gd")

var _guard
var _overlay: StoryDialogue = null
var _picked: int = -99
var _finished: int = 0
var _skipped: bool = false


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	_overlay = StoryDialogue.new()
	add_child_autofree(_overlay)
	_overlay.auto_tick = false
	_picked = -99
	_finished = 0
	_overlay.choice_made.connect(func(i: int) -> void: _picked = i)
	_overlay.finished.connect(func(s: bool) -> void:
		_finished += 1
		_skipped = s)


func after_each() -> void:
	_overlay = null
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _prompt(text: String = "Will you walk the Mossway for us?") -> StoryBeat:
	var b := StoryBeat.new()
	b.speaker_id = &"npc_elder"
	b.speaker_name = "Elder Wynn"
	b.side = StoryBeat.SIDE_RIGHT
	b.text = text
	return b


func _reveal() -> void:
	_overlay.advance_clock(100.0)


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_options_appear_only_after_the_prompt_is_revealed() -> void:
	assert_true(_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "Not yet"]), 1), "a choice plays")
	await get_tree().process_frame
	assert_true(_overlay.is_choosing(), "choosing")
	assert_false(_overlay.choices_visible(), "no options while the prompt types")
	_reveal()
	await get_tree().process_frame
	assert_true(_overlay.choices_visible(), "the options appear once the line is whole")
	assert_eq(_overlay.choice_buttons().size(), 2, "one row per option")
	assert_true(_overlay.choice_buttons()[0].text.contains("Yes"), "labelled")
	assert_true(_overlay.choice_buttons()[0].is_visible_in_tree(), "and actually drawn")


func test_a_press_never_advances_past_the_options() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "No"]))
	_overlay.advance()
	assert_true(_overlay.choices_visible(), "the first press completes the typewriter and shows the options")
	_overlay.advance()
	_overlay.advance()
	assert_eq(_finished, 0, "further presses do not finish the prompt")
	assert_true(_overlay.choices_visible(), "the options stay up")


func test_number_key_picks() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "No", "Maybe"]))
	_reveal()
	await get_tree().process_frame
	_overlay._unhandled_input(_key(KEY_3))
	assert_eq(_picked, 2, "3 picks the third option")
	assert_eq(_finished, 1, "and the prompt finishes")
	assert_false(_skipped, "not as a skip")
	assert_false(_overlay.root_control().visible, "the overlay comes down")
	assert_eq(_overlay.choice_buttons().size(), 0, "the rows are cleared")


func test_button_press_picks() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "No"]))
	_reveal()
	await get_tree().process_frame
	_overlay.choice_buttons()[1].pressed.emit()
	assert_eq(_picked, 1, "tapping a row picks it")


func test_cancel_picks_the_cancel_option_and_skip_does_too() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "Not yet"]), 1)
	_reveal()
	await get_tree().process_frame
	var cancel := InputEventAction.new()
	cancel.action = InputActions.CANCEL
	cancel.pressed = true
	_overlay._unhandled_input(cancel)
	assert_eq(_picked, 1, "Cancel picks the cancel option")
	_picked = -99
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "Not yet"]), 1)
	_overlay.skip()
	assert_eq(_picked, 1, "SKIP on a question completes it and picks the cancel option")


func test_without_a_cancel_option_cancel_does_nothing() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "No"]), -1)
	_reveal()
	await get_tree().process_frame
	var cancel := InputEventAction.new()
	cancel.action = InputActions.CANCEL
	cancel.pressed = true
	_overlay._unhandled_input(cancel)
	assert_eq(_picked, -99, "no cancel option -> the question waits for a pick")
	assert_true(_overlay.choices_visible(), "still up")


func test_plain_scenes_are_unchanged_after_a_choice() -> void:
	_overlay.play_choice(_prompt(), PackedStringArray(["Yes", "No"]))
	_reveal()
	_overlay.choose(0)
	var scene := StoryScene.new()
	var b := StoryBeat.new()
	b.text = "A plain line."
	scene.beats = [b] as Array[Resource]
	assert_true(_overlay.play(scene), "a normal scene plays after a choice")
	_reveal()
	_overlay.advance()
	assert_eq(_finished, 2, "and finishes on the next press as always")
	assert_false(_skipped, "read through, not skipped")
