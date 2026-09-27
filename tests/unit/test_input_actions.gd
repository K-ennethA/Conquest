extends GutTest

# Named input actions (project.godot [input]), the InputActions helpers, and the
# GameSettings keyboard-rebinding persistence. Uses a throwaway settings file so the
# player's real user://settings.cfg is never touched.

const TEST_CFG := "user://test_controls_settings.cfg"


func after_each():
	# Leave the live InputMap / GameSettings exactly as the project defines them.
	GameSettings.key_binding_overrides.clear()
	InputActions.restore_all_defaults()
	if FileAccess.file_exists(TEST_CFG):
		DirAccess.remove_absolute(TEST_CFG)


func _has_joy(action: StringName) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false


# --- Definitions ---------------------------------------------------------------

func test_every_action_is_defined():
	for a in InputActions.ALL:
		assert_true(InputMap.has_action(a), "action '%s' defined in project.godot" % a)

func test_core_actions_have_keyboard_and_gamepad():
	for a in [InputActions.CURSOR_UP, InputActions.CURSOR_DOWN, InputActions.CURSOR_LEFT,
			InputActions.CURSOR_RIGHT, InputActions.CONFIRM, InputActions.CANCEL,
			InputActions.WAIT, InputActions.UNIT_INFO, InputActions.END_TURN]:
		assert_false(InputActions.keyboard_events(a).is_empty(), "%s has a key" % a)
		assert_true(_has_joy(a), "%s has a gamepad binding" % a)

func test_default_keyboard_bindings_do_not_collide():
	var seen := {}
	for entry in InputActions.REBINDABLE:
		for code in InputActions.key_codes(entry["action"]):
			assert_false(seen.has(code), "%s shared by %s and %s" % [OS.get_keycode_string(code), seen.get(code), entry["action"]])
			seen[code] = entry["action"]

func test_arrows_step_cursor_but_do_not_pan_camera():
	var up := InputActions.make_key_event(KEY_UP)
	up.pressed = true
	assert_true(up.is_action_pressed(InputActions.CURSOR_UP))
	for a in [InputActions.CAMERA_PAN_UP, InputActions.CAMERA_PAN_DOWN,
			InputActions.CAMERA_PAN_LEFT, InputActions.CAMERA_PAN_RIGHT]:
		assert_false(KEY_UP in InputActions.key_codes(a), "%s must not use arrows" % a)

func test_unit_info_is_not_on_camera_pan_s():
	assert_false(KEY_S in InputActions.key_codes(InputActions.UNIT_INFO))
	assert_true(KEY_S in InputActions.key_codes(InputActions.CAMERA_PAN_DOWN))

func test_held_key_echo_counts_for_cursor():
	var e := InputActions.make_key_event(KEY_RIGHT)
	e.pressed = true
	e.echo = true
	assert_true(e.is_action_pressed(InputActions.CURSOR_RIGHT, true), "echo repeats the cursor step")


# --- Descriptions --------------------------------------------------------------

func test_describe_keyboard_and_gamepad():
	assert_eq(InputActions.describe(InputActions.WAIT), "E")
	assert_eq(InputActions.describe(InputActions.CONFIRM, true), "A")
	assert_eq(InputActions.describe(InputActions.CURSOR_UP, true), "D-Pad Up")
	assert_eq(InputActions.with_hint("Move", InputActions.UNIT_MOVE), "Move [M]")
	assert_true(InputActions.describe_keys(InputActions.CANCEL).begins_with("Escape"))

func test_event_label_for_modifier_and_axis():
	assert_eq(InputActions.event_label(InputActions.make_key_event(KEY_TAB | KEY_MASK_SHIFT)), "Shift+Tab")
	var m := InputEventJoypadMotion.new()
	m.axis = JOY_AXIS_TRIGGER_RIGHT
	m.axis_value = 1.0
	assert_eq(InputActions.event_label(m), "RT")

func test_make_key_event_round_trips_modifiers():
	var code: int = KEY_K | KEY_MASK_CTRL | KEY_MASK_SHIFT
	var e := InputActions.make_key_event(code)
	assert_eq(e.keycode, KEY_K)
	assert_true(e.ctrl_pressed and e.shift_pressed)
	assert_eq(e.get_keycode_with_modifiers(), code)


# --- Debug gating -------------------------------------------------------------

func test_debug_hotkey_requires_ctrl_shift():
	var plain := InputActions.make_key_event(KEY_M)
	plain.pressed = true
	assert_false(InputActions.is_debug_hotkey(plain), "a plain key is never a debug hotkey")
	var combo := InputActions.make_key_event(KEY_F1 | KEY_MASK_CTRL | KEY_MASK_SHIFT)
	combo.pressed = true
	assert_eq(InputActions.is_debug_hotkey(combo, KEY_F1), OS.is_debug_build())
	assert_false(InputActions.is_debug_hotkey(combo, KEY_F2), "keycode must match")


# --- Rebinding + persistence ---------------------------------------------------

func test_set_keyboard_bindings_keeps_gamepad_and_restore_defaults():
	InputActions.set_keyboard_bindings(InputActions.WAIT, [KEY_K])
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_K] as Array[int])
	assert_true(_has_joy(InputActions.WAIT), "gamepad binding untouched")
	InputActions.restore_defaults(InputActions.WAIT)
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_E] as Array[int])

func test_game_settings_persists_and_reloads_binding():
	GameSettings.set_key_binding(InputActions.WAIT, KEY_K, TEST_CFG)
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_K] as Array[int], "applied live")

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEST_CFG), OK)
	assert_eq(cfg.get_value(GameSettings.CONTROLS_SECTION, "wait"), [KEY_K])

	# Simulate a fresh boot: defaults in the InputMap, then load the file.
	GameSettings.key_binding_overrides.clear()
	InputActions.restore_all_defaults()
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_E] as Array[int])
	GameSettings.load_key_bindings(TEST_CFG)
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_K] as Array[int], "reapplied at startup")

func test_rebinding_to_a_used_key_swaps():
	GameSettings.set_key_binding(InputActions.WAIT, KEY_M, TEST_CFG)
	assert_eq(InputActions.key_codes(InputActions.WAIT), [KEY_M] as Array[int])
	assert_eq(InputActions.key_codes(InputActions.UNIT_MOVE), [KEY_E] as Array[int], "Move takes Wait's old key")

func test_reset_restores_defaults_and_clears_file_section():
	GameSettings.set_key_binding(InputActions.END_TURN, KEY_O, TEST_CFG)
	GameSettings.reset_key_bindings(TEST_CFG)
	assert_eq(InputActions.key_codes(InputActions.END_TURN), [KEY_P] as Array[int])
	var cfg := ConfigFile.new()
	cfg.load(TEST_CFG)
	assert_false(cfg.has_section(GameSettings.CONTROLS_SECTION), "no overrides left on disk")
