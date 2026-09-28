extends GutTest

## THE OVERWORLD WALK, driven by REAL input events (Input.parse_input_event: arrow keys, WASD,
## Shift, the d-pad, the left stick) through the booted OverworldScene -- the regression for
## "clicking the arrow keys teleports you far across the land". With animations OFF (a player
## setting) the hero's step snaps, and the held-key path used to step again the very next
## frame: a held arrow crossed the town in a few frames, a short tap moved several cells. Every
## step now costs its walk / run seconds whatever the visual, so the hero moves exactly one
## cell per step. Sampled every frame: no frame ever moves the hero more than one cell, and
## consecutive steps are never closer together than the step time.
##
## Uses wall-clock holds (the step pace IS wall-clock), well under a second each.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_overworld_key_walk/"
## Oakvale's start: open flagstones for several cells west along row 11.
const START := Vector3i(10, 11, 0)
## Scheduling slack on a step interval (headless frames are a few ms apart).
const SLACK_MS := 25

var _guard
var _world: Node = null
var _prev_scene: Node = null
## [ms since the sample began, cell] per cell change, and the largest per-frame moves seen.
var _changes: Array = []
var _max_cell_jump: int = 0
var _max_world_jump: float = 0.0


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false
	_changes.clear()
	_max_cell_jump = 0
	_max_world_jump = 0.0


func after_each() -> void:
	_release_everything()
	_teardown()
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(facing: String) -> OverworldController:
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.grace_steps = 9999
	s.set_location("oakvale", START, facing)
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


# --- real input -------------------------------------------------------------------------

func _key(code: Key, pressed: bool, shift: bool = false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	e.shift_pressed = shift
	Input.parse_input_event(e)


func _dpad(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _stick_x(value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = JOY_AXIS_LEFT_X
	e.axis_value = value
	Input.parse_input_event(e)


func _release_everything() -> void:
	for code in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_SHIFT]:
		_key(code, false)
	_dpad(JOY_BUTTON_DPAD_LEFT, false)
	_stick_x(0.0)
	for a in InputActions.ALL:
		if InputMap.has_action(a):
			Input.action_release(a)


## Run frames for [param ms] of wall clock, recording every cell change and the biggest
## per-frame jump (in cells, and in world units of the hero's position).
func _sample(ow: OverworldController, ms: int) -> void:
	var t0: int = Time.get_ticks_msec()
	var last_cell: Vector3i = ow.player.cell
	var last_pos: Vector3 = ow.player.global_position
	while Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
		var c: Vector3i = ow.player.cell
		var p: Vector3 = ow.player.global_position
		_max_cell_jump = maxi(_max_cell_jump, Cells.manhattan_2d(c, last_cell))
		_max_world_jump = maxf(_max_world_jump, p.distance_to(last_pos))
		if c != last_cell:
			_changes.append([Time.get_ticks_msec() - t0, c])
		last_cell = c
		last_pos = p


func _min_interval_ms() -> int:
	var out: int = 1 << 30
	for i in range(1, _changes.size()):
		out = mini(out, int(_changes[i][0]) - int(_changes[i - 1][0]))
	return out


func _ms(seconds: float) -> int:
	return int(seconds * 1000.0)


# --- tests --------------------------------------------------------------------------------

func test_a_tap_on_a_new_direction_only_turns() -> void:
	var ow := await _boot("south")
	_key(KEY_LEFT, true)
	await _sample(ow, 40)
	_key(KEY_LEFT, false)
	await _sample(ow, 300)
	assert_eq(ow.player.cell, START, "a short tap on a new direction does not move the hero")
	assert_eq(ow.player.facing, Vector2i(-1, 0), "it turns him to face it")


func test_a_tap_the_way_he_faces_steps_exactly_one_cell() -> void:
	var ow := await _boot("west")
	# A tap long enough for several frames (the old bug stepped once per frame held).
	_key(KEY_LEFT, true)
	await _sample(ow, 80)
	_key(KEY_LEFT, false)
	await _sample(ow, 400)
	assert_eq(ow.player.cell, START + Vector3i(-1, 0, 0), "one tap = one cell, never a slide")
	assert_eq(_changes.size(), 1, "exactly one step happened")


func test_holding_an_arrow_walks_one_cell_per_step_with_animations_off() -> void:
	var ow := await _boot("west")
	var step_ms: int = _ms(StoryController.ruleset().walk_step_seconds)
	_key(KEY_LEFT, true)
	await _sample(ow, 600)
	_key(KEY_LEFT, false)
	await _sample(ow, 100)
	assert_gte(_changes.size(), 2, "holding keeps walking")
	assert_lte(_changes.size(), 600 / step_ms + 1, "but only as fast as the walk pace allows")
	assert_eq(_max_cell_jump, 1, "no frame ever moves the hero more than one cell")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "each step takes the walk time")
	var end_x: int = START.x - _changes.size()
	assert_eq(ow.player.cell, Vector3i(end_x, START.y, 0), "walked straight west, cell by cell")


func test_holding_an_arrow_glides_one_cell_per_step_with_animations_on() -> void:
	_guard.set_setting("animations_enabled", true)
	var ow := await _boot("west")
	var step_ms: int = _ms(StoryController.ruleset().walk_step_seconds)
	_key(KEY_LEFT, true)
	await _sample(ow, 600)
	_key(KEY_LEFT, false)
	await _sample(ow, 300)
	assert_gte(_changes.size(), 2, "holding keeps walking")
	assert_lte(_changes.size(), 600 / step_ms + 2, "at the walk pace")
	assert_eq(_max_cell_jump, 1, "one cell per step")
	assert_lt(_max_world_jump, Cells.CELL_SIZE, "the hero glides; his position never jumps a cell in a frame")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "one step per walk tween")


func test_shift_runs_faster_but_still_cell_by_cell() -> void:
	var ow := await _boot("west")
	var run_ms: int = _ms(StoryController.ruleset().run_step_seconds)
	var walk_ms: int = _ms(StoryController.ruleset().walk_step_seconds)
	_key(KEY_SHIFT, true, true)
	_key(KEY_LEFT, true, true)
	await _sample(ow, 450)
	_key(KEY_LEFT, false, true)
	_key(KEY_SHIFT, false)
	await _sample(ow, 100)
	assert_gte(_changes.size(), 3, "running keeps stepping")
	assert_lte(_changes.size(), 450 / run_ms + 1, "at the run pace, not once per frame")
	assert_eq(_max_cell_jump, 1, "one cell per step")
	assert_gte(_min_interval_ms(), run_ms - SLACK_MS, "each run step takes the run time")
	assert_lt(_min_interval_ms(), walk_ms, "and that is quicker than walking")


func test_wasd_dpad_and_stick_share_the_one_cell_pace() -> void:
	var step_ms: int = _ms(StoryController.ruleset().walk_step_seconds)
	var inputs: Array[String] = ["wasd", "dpad", "stick"]
	for which in inputs:
		_changes.clear()
		_max_cell_jump = 0
		var ow := await _boot("west")
		match which:
			"wasd":
				_key(KEY_A, true)
			"dpad":
				_dpad(JOY_BUTTON_DPAD_LEFT, true)
			"stick":
				_stick_x(-1.0)
		await _sample(ow, 500)
		_release_everything()
		await _sample(ow, 100)
		assert_gte(_changes.size(), 2, "%s: holding walks" % which)
		assert_lte(_changes.size(), 500 / step_ms + 1, "%s: at the walk pace" % which)
		assert_eq(_max_cell_jump, 1, "%s: one cell per step" % which)
		_teardown()
		StoryController.end_session()


func test_tap_to_walk_paces_the_path_one_cell_per_step() -> void:
	var ow := await _boot("south")
	var step_ms: int = _ms(StoryController.ruleset().walk_step_seconds)
	ow.tap_cell(START + Vector3i(-3, 0, 0))
	await _sample(ow, 3 * step_ms + 250)
	assert_eq(ow.player.cell, START + Vector3i(-3, 0, 0), "the tap walks there")
	assert_eq(_changes.size(), 3, "three steps")
	assert_eq(_max_cell_jump, 1, "cell by cell")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "at the walk pace, not one cell a frame")
