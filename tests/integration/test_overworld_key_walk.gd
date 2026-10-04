extends GutTest

## THE OVERWORLD WALK, driven by REAL input events (Input.parse_input_event: arrow keys, WASD,
## Shift, the d-pad, the left stick) through the booted OverworldScene -- the regression for
## "clicking the arrow keys teleports you far across the land". With animations OFF (a player
## setting) the hero's step snaps, and the held-key path used to step again the very next
## frame: a held arrow crossed the town in a few frames, a short tap moved several cells. Every
## step now costs its walk / run seconds whatever the visual, so the hero moves exactly one
## cell per step. Sampled every frame: no frame ever moves the hero more than one cell, and
## consecutive steps are never closer together than the step time. Those GRID tests pin the
## debug "grid" feel ([OverworldFeel]).
##
## The shipped "free" feel (Sun/Moon free movement, [HeroMover]) has its own tests at the end:
## a held key walks CONTINUOUSLY whatever the Animations setting (the 2026-10-04 report: "the
## character pauses and moves in place then abruptly moves spots") -- the hero's position
## advances every frame at the walk / run speed, never stalls at a cell centre, never jumps.
##
## Uses wall-clock holds (the step pace IS wall-clock), sized from the controller's active feel
## pace (OverworldFeel: ~1.7 s per walk cell in the "grid" feel, so a few seconds each).

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
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
	OverworldFeel.set_active(OverworldFeel.PRESET_DEFAULT)
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(facing: String, preset: String = OverworldFeel.PRESET_DEFAULT) -> OverworldController:
	OverworldFeel.set_active(preset)
	StoryController.new_journey(1)
	var s: StoryState = StoryController.state()
	s.grace_steps = 9999
	# Past the send-off: the opening's first scene would otherwise hold input on this boot.
	StoryFixture.sent_off(s)
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


## A hold that spans at least two walk steps (three cell changes) at the active feel's pace --
## the step time comes from the controller (OverworldFeel), never a fixed 0.22 s.
func _hold_ms(step_ms: int) -> int:
	return 2 * step_ms + 150


# --- tests --------------------------------------------------------------------------------

func test_a_tap_on_a_new_direction_only_turns() -> void:
	var ow := await _boot("south", OverworldFeel.PRESET_GRID)
	_key(KEY_LEFT, true)
	await _sample(ow, 40)
	_key(KEY_LEFT, false)
	await _sample(ow, 300)
	assert_eq(ow.player.cell, START, "a short tap on a new direction does not move the hero")
	assert_eq(ow.player.facing, Vector2i(-1, 0), "it turns him to face it")


func test_a_tap_the_way_he_faces_steps_exactly_one_cell() -> void:
	var ow := await _boot("west", OverworldFeel.PRESET_GRID)
	# A tap long enough for several frames (the old bug stepped once per frame held).
	_key(KEY_LEFT, true)
	await _sample(ow, 80)
	_key(KEY_LEFT, false)
	await _sample(ow, 400)
	assert_eq(ow.player.cell, START + Vector3i(-1, 0, 0), "one tap = one cell, never a slide")
	assert_eq(_changes.size(), 1, "exactly one step happened")


func test_holding_an_arrow_walks_one_cell_per_step_with_animations_off() -> void:
	var ow := await _boot("west", OverworldFeel.PRESET_GRID)
	var step_ms: int = _ms(ow.walk_step_seconds())
	var hold_ms: int = _hold_ms(step_ms)
	_key(KEY_LEFT, true)
	await _sample(ow, hold_ms)
	_key(KEY_LEFT, false)
	await _sample(ow, 100)
	assert_gte(_changes.size(), 2, "holding keeps walking")
	assert_lte(_changes.size(), hold_ms / step_ms + 1, "but only as fast as the walk pace allows")
	assert_eq(_max_cell_jump, 1, "no frame ever moves the hero more than one cell")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "each step takes the walk time")
	var end_x: int = START.x - _changes.size()
	assert_eq(ow.player.cell, Vector3i(end_x, START.y, 0), "walked straight west, cell by cell")


func test_holding_an_arrow_glides_one_cell_per_step_with_animations_on() -> void:
	_guard.set_setting("animations_enabled", true)
	var ow := await _boot("west", OverworldFeel.PRESET_GRID)
	var step_ms: int = _ms(ow.walk_step_seconds())
	var hold_ms: int = _hold_ms(step_ms)
	_key(KEY_LEFT, true)
	await _sample(ow, hold_ms)
	_key(KEY_LEFT, false)
	await _sample(ow, 300)
	assert_gte(_changes.size(), 2, "holding keeps walking")
	assert_lte(_changes.size(), hold_ms / step_ms + 2, "at the walk pace")
	assert_eq(_max_cell_jump, 1, "one cell per step")
	assert_lt(_max_world_jump, Cells.CELL_SIZE, "the hero glides; his position never jumps a cell in a frame")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "one step per walk tween")


func test_shift_runs_faster_but_still_cell_by_cell() -> void:
	var ow := await _boot("west", OverworldFeel.PRESET_GRID)
	var run_ms: int = _ms(ow.run_step_seconds())
	var walk_ms: int = _ms(ow.walk_step_seconds())
	# Long enough for three run steps at any feel's pace (the old fixed 450 ms assumed 0.12 s).
	var hold_ms: int = 2 * run_ms + 150
	_key(KEY_SHIFT, true, true)
	_key(KEY_LEFT, true, true)
	await _sample(ow, hold_ms)
	_key(KEY_LEFT, false, true)
	_key(KEY_SHIFT, false)
	await _sample(ow, 100)
	assert_gte(_changes.size(), 3, "running keeps stepping")
	assert_lte(_changes.size(), hold_ms / run_ms + 1, "at the run pace, not once per frame")
	assert_eq(_max_cell_jump, 1, "one cell per step")
	assert_gte(_min_interval_ms(), run_ms - SLACK_MS, "each run step takes the run time")
	assert_lt(_min_interval_ms(), walk_ms, "and that is quicker than walking")


func test_wasd_dpad_and_stick_share_the_one_cell_pace() -> void:
	var inputs: Array[String] = ["wasd", "dpad", "stick"]
	for which in inputs:
		_changes.clear()
		_max_cell_jump = 0
		var ow := await _boot("west", OverworldFeel.PRESET_GRID)
		var step_ms: int = _ms(ow.walk_step_seconds())
		# Two steps' worth: the first at the press, the second one walk time later.
		var hold_ms: int = step_ms + 300
		match which:
			"wasd":
				_key(KEY_A, true)
			"dpad":
				_dpad(JOY_BUTTON_DPAD_LEFT, true)
			"stick":
				_stick_x(-1.0)
		await _sample(ow, hold_ms)
		_release_everything()
		await _sample(ow, 100)
		assert_gte(_changes.size(), 2, "%s: holding walks" % which)
		assert_lte(_changes.size(), hold_ms / step_ms + 1, "%s: at the walk pace" % which)
		assert_eq(_max_cell_jump, 1, "%s: one cell per step" % which)
		_teardown()
		StoryController.end_session()


func test_tap_to_walk_paces_the_path_one_cell_per_step() -> void:
	var ow := await _boot("south", OverworldFeel.PRESET_GRID)
	var step_ms: int = _ms(ow.walk_step_seconds())
	ow.tap_cell(START + Vector3i(-3, 0, 0))
	await _sample(ow, 3 * step_ms + 250)
	assert_eq(ow.player.cell, START + Vector3i(-3, 0, 0), "the tap walks there")
	assert_eq(_changes.size(), 3, "three steps")
	assert_eq(_max_cell_jump, 1, "cell by cell")
	assert_gte(_min_interval_ms(), step_ms - SLACK_MS, "at the walk pace, not one cell a frame")


# --- the shipped "free" feel: Sun/Moon free movement ----------------------------------------

## Run frames for [param ms] of wall clock; returns [[usec, world position], ...] per frame (and
## records cell changes / jumps like [method _sample]).
func _trail(ow: OverworldController, ms: int) -> Array:
	var out: Array = []
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
		out.append([Time.get_ticks_usec(), p])
	return out


## Ground speed (m/s) over trail entries [param from_i] .. the end.
func _avg_speed(trail: Array, from_i: int) -> float:
	var a: Array = trail[from_i]
	var b: Array = trail[trail.size() - 1]
	var dt: float = float(int(b[0]) - int(a[0])) / 1e6
	return (b[1] as Vector3).distance_to(a[1] as Vector3) / dt if dt > 0.0 else 0.0


## Index of the first trail entry at least [param ms] after the trail began.
func _index_after(trail: Array, ms: int) -> int:
	var t0: int = int(trail[0][0])
	for i in range(trail.size()):
		if int(trail[i][0]) - t0 >= ms * 1000:
			return i
	return trail.size() - 1


func test_free_is_the_shipped_feel() -> void:
	var ow := await _boot("west")
	assert_true(OverworldFeel.is_free(ow.feel), "the shipped overworld walks freely (Sun/Moon), not tile by tile")


func test_free_holding_an_arrow_walks_continuously_with_animations_off() -> void:
	var ow := await _boot("west")
	var walk_v: float = float(ow.feel["walk_speed_mps"])
	_key(KEY_LEFT, true)
	var held: Array = await _trail(ow, 1300)
	_key(KEY_LEFT, false)
	var after: Array = await _trail(ow, 500)
	assert_gte(_changes.size(), 1, "holding walks into the next cell")
	assert_eq(_max_cell_jump, 1, "never more than a cell's change in a frame")
	assert_lt(_max_world_jump, 0.25, "and never a jump: the position glides every frame")
	# Past the ease-in, every frame moves him west -- no walking in place, no pause at a centre.
	var cruise: int = _index_after(held, 300)
	var stalls: Array = []
	for i in range(cruise + 1, held.size()):
		var dx: float = (held[i][1] as Vector3).x - (held[i - 1][1] as Vector3).x
		if dx >= 0.0:
			stalls.append("frame %d: dx %.4f" % [i, dx])
	assert_eq(stalls, [], "a held key never stalls the hero (the reported walk-in-place-then-jump)")
	assert_almost_eq(_avg_speed(held, cruise), walk_v, walk_v * 0.08, "at the walk speed")
	assert_almost_eq((held[held.size() - 1][1] as Vector3).z, (held[0][1] as Vector3).z, 0.001, "straight west")
	# Released: he stops within a few frames, wherever he is (no snap to a cell centre).
	var stop_i: int = _index_after(after, 250)
	var p_stop: Vector3 = after[stop_i][1]
	var p_end: Vector3 = after[after.size() - 1][1]
	assert_almost_eq(p_end.distance_to(p_stop), 0.0, 0.001, "released: he stands still")


func test_free_shift_runs_faster() -> void:
	var ow := await _boot("west")
	var walk_v: float = float(ow.feel["walk_speed_mps"])
	var run_v: float = float(ow.feel["run_speed_mps"])
	_key(KEY_SHIFT, true, true)
	_key(KEY_LEFT, true, true)
	var held: Array = await _trail(ow, 700)
	_key(KEY_LEFT, false, true)
	_key(KEY_SHIFT, false)
	var v: float = _avg_speed(held, _index_after(held, 350))
	assert_almost_eq(v, run_v, run_v * 0.1, "Shift runs at the run speed")
	assert_gt(v, walk_v * 1.8, "well above walking")
	assert_lt(_max_world_jump, 0.5, "still a glide, never a jump")


func test_free_a_diagonal_turns_him_to_the_angle() -> void:
	var ow := await _boot("south")
	_key(KEY_LEFT, true)
	_key(KEY_UP, true)
	var held: Array = await _trail(ow, 700)
	_key(KEY_LEFT, false)
	_key(KEY_UP, false)
	var want: float = deg_to_rad(ow.player.model_yaw_deg) + atan2(-1.0, -1.0)
	var got: float = ow.player.model().rotation.y
	assert_almost_eq(wrapf(got - want, -PI, PI), 0.0, 0.02, "the model faces the 45-degree input, not a cardinal")
	assert_true(ow.player.facing in [Vector2i(-1, 0), Vector2i(0, -1)], "Confirm reads the nearest cardinal")
	var moved: float = (held[held.size() - 1][1] as Vector3).distance_to(held[0][1] as Vector3)
	assert_gt(moved, 0.5, "and he walks")


func test_free_a_quick_tap_turns_him_fully_with_barely_a_step() -> void:
	var ow := await _boot("south")
	var start: Vector3 = ow.player.global_position
	_key(KEY_LEFT, true)
	await _trail(ow, 40)
	_key(KEY_LEFT, false)
	await _trail(ow, 400)
	assert_eq(ow.player.facing, Vector2i(-1, 0), "a tap turns him to face it")
	var want: float = deg_to_rad(ow.player.model_yaw_deg) + atan2(-1.0, 0.0)
	assert_almost_eq(wrapf(ow.player.model().rotation.y - want, -PI, PI), 0.0, 0.02, "all the way round")
	assert_lt(ow.player.global_position.distance_to(start), 0.3, "with barely a step")
	assert_eq(ow.player.cell, START, "and stays on his cell")


func test_free_wasd_dpad_and_stick_all_walk() -> void:
	var inputs: Array[String] = ["wasd", "dpad", "stick"]
	for which in inputs:
		var ow := await _boot("west")
		var start: Vector3 = ow.player.global_position
		match which:
			"wasd":
				_key(KEY_A, true)
			"dpad":
				_dpad(JOY_BUTTON_DPAD_LEFT, true)
			"stick":
				_stick_x(-1.0)
		await _trail(ow, 700)
		_release_everything()
		await _trail(ow, 100)
		var moved: float = start.x - ow.player.global_position.x
		assert_gt(moved, 0.6, "%s: walks west (%.2f m)" % [which, moved])
		_teardown()
		StoryController.end_session()


func test_free_tap_to_walk_glides_there() -> void:
	var ow := await _boot("south")
	var goal: Vector3i = START + Vector3i(-3, 0, 0)
	ow.tap_cell(goal)
	var budget_ms: int = int(3.0 * ow.walk_step_seconds() * 1000.0) + 1500
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < budget_ms:
		await _trail(ow, 50)
		if ow.player.cell == goal and ow.player.glide_velocity == Vector3.ZERO:
			break
	assert_eq(ow.player.cell, goal, "the tap walks there")
	assert_lt(_max_world_jump, 0.25, "gliding, never jumping")
	var centre: Vector3 = OverworldActor.world_of(goal)
	assert_lt(Vector2(ow.player.global_position.x - centre.x, ow.player.global_position.z - centre.z).length(),
		0.2, "and stops on the cell's centre")
