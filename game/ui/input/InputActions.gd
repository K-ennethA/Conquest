extends RefCounted
class_name InputActions

## Named gameplay input actions + small helpers (binding descriptions for UI hints,
## keyboard rebinding, debug-hotkey gating).
##
## The DEFAULT bindings live in project.godot's [input] section (the InputMap source
## of truth); this file only names them, so gameplay code never matches raw KEY_*
## codes and every action works on keyboard AND gamepad and can be rebound from the
## in-game Settings > Controls tab (persisted by GameSettings in user://settings.cfg).
##
## Default bindings
## ------------------------------------------------------------------------------
##  action            keyboard                      gamepad
##  cursor_up/down/   Arrow keys                    D-pad, left stick
##    left/right                                    (held direction repeats)
##  confirm           Enter, Keypad Enter, Space    A / Cross
##  cancel            Esc, Backspace, X, C          B / Circle
##  unit_move         M                             -- (Confirm on the unit)
##  wait              E  (end the unit's action)    Y / Triangle
##  unit_info         I  (Unit Summary)             X / Square
##  end_turn          P                             Back / Select
##  map_menu          Esc (only when nothing is     Start       [reserved]
##                    selected / nothing to cancel)
##  cycle_next        Tab, R                        RB / R1     [reserved]
##  cycle_prev        Shift+Tab, Q                  LB / L1     [reserved]
##  danger_zone       Z                             L3          [reserved]
##  fast_forward      Shift (hold)                  R3 (hold)   [reserved]
##  camera_pan_*      W / A / S / D                 right stick
##  floor_up/down     Page Up / Page Down           RT / LT     [reserved: multi-floor]
##
## Arrow keys move ONLY the board cursor (the camera no longer pans on them); the
## camera pans on WASD, the right stick, the screen edge and mouse drag. Unit
## Summary moved from S to I so S is free for camera pan.
##
## Debug hotkeys (GameWorldManager / UnitActionsPanel / cursor / visualizer dev
## helpers) only fire in debug builds AND with Ctrl+Shift held -- see
## [method is_debug_hotkey]. No plain key ever quits to the main menu.

# --- Action names -------------------------------------------------------------
const CURSOR_UP := &"cursor_up"
const CURSOR_DOWN := &"cursor_down"
const CURSOR_LEFT := &"cursor_left"
const CURSOR_RIGHT := &"cursor_right"
const CONFIRM := &"confirm"
const CANCEL := &"cancel"
const UNIT_MOVE := &"unit_move"
const WAIT := &"wait"
const UNIT_INFO := &"unit_info"
const END_TURN := &"end_turn"
const MAP_MENU := &"map_menu"
const CYCLE_NEXT := &"cycle_next"
const CYCLE_PREV := &"cycle_prev"
const DANGER_ZONE := &"danger_zone"
const FAST_FORWARD := &"fast_forward"
const CAMERA_PAN_UP := &"camera_pan_up"
const CAMERA_PAN_DOWN := &"camera_pan_down"
const CAMERA_PAN_LEFT := &"camera_pan_left"
const CAMERA_PAN_RIGHT := &"camera_pan_right"
const FLOOR_UP := &"floor_up"
const FLOOR_DOWN := &"floor_down"

## Every action this file defines (all present in project.godot).
const ALL: Array[StringName] = [
	CURSOR_UP, CURSOR_DOWN, CURSOR_LEFT, CURSOR_RIGHT, CONFIRM, CANCEL, UNIT_MOVE,
	WAIT, UNIT_INFO, END_TURN, MAP_MENU, CYCLE_NEXT, CYCLE_PREV, DANGER_ZONE,
	FAST_FORWARD, CAMERA_PAN_UP, CAMERA_PAN_DOWN, CAMERA_PAN_LEFT, CAMERA_PAN_RIGHT,
	FLOOR_UP, FLOOR_DOWN,
]

## Board-cursor step (grid x / z) for each cursor direction action.
const CURSOR_STEPS := {
	CURSOR_UP: Vector3(0, 0, -1),
	CURSOR_DOWN: Vector3(0, 0, 1),
	CURSOR_LEFT: Vector3(-1, 0, 0),
	CURSOR_RIGHT: Vector3(1, 0, 0),
}

## Actions offered in Settings > Controls, in display order, with their labels.
## (map_menu is contextual on Esc and fast_forward is a hold-modifier, so neither
## is listed.)
const REBINDABLE: Array[Dictionary] = [
	{ "action": CURSOR_UP, "label": "Cursor Up" },
	{ "action": CURSOR_DOWN, "label": "Cursor Down" },
	{ "action": CURSOR_LEFT, "label": "Cursor Left" },
	{ "action": CURSOR_RIGHT, "label": "Cursor Right" },
	{ "action": CONFIRM, "label": "Confirm / Select" },
	{ "action": CANCEL, "label": "Cancel / Back" },
	{ "action": UNIT_MOVE, "label": "Move" },
	{ "action": WAIT, "label": "Wait" },
	{ "action": UNIT_INFO, "label": "Unit Info" },
	{ "action": END_TURN, "label": "End Turn" },
	{ "action": CYCLE_NEXT, "label": "Next Unit" },
	{ "action": CYCLE_PREV, "label": "Previous Unit" },
	{ "action": DANGER_ZONE, "label": "Danger Zone" },
	{ "action": CAMERA_PAN_UP, "label": "Camera Up" },
	{ "action": CAMERA_PAN_DOWN, "label": "Camera Down" },
	{ "action": CAMERA_PAN_LEFT, "label": "Camera Left" },
	{ "action": CAMERA_PAN_RIGHT, "label": "Camera Right" },
	{ "action": FLOOR_UP, "label": "Floor Up" },
	{ "action": FLOOR_DOWN, "label": "Floor Down" },
]

## Group joined by full-screen overlays (Settings, future map menu) that should
## swallow gameplay input while visible. See [method gameplay_input_blocked].
const OVERLAY_GROUP := &"input_blocking_overlay"

const _JOY_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}


# --- Descriptions (UI hints) ------------------------------------------------------

## Human-readable name of one bound [param event] ("Esc", "Shift+Tab", "A",
## "Left Stick Up", "RT"). Empty for unsupported event types.
static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code: int = k.get_keycode_with_modifiers()
		if k.keycode == KEY_NONE and k.physical_keycode != KEY_NONE:
			code = k.get_physical_keycode_with_modifiers()
		return OS.get_keycode_string(code)
	if event is InputEventJoypadButton:
		var b := (event as InputEventJoypadButton).button_index
		return _JOY_BUTTON_NAMES.get(b, "Button %d" % b)
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var neg := m.axis_value < 0.0
		match m.axis:
			JOY_AXIS_LEFT_X:
				return "Left Stick " + ("Left" if neg else "Right")
			JOY_AXIS_LEFT_Y:
				return "Left Stick " + ("Up" if neg else "Down")
			JOY_AXIS_RIGHT_X:
				return "Right Stick " + ("Left" if neg else "Right")
			JOY_AXIS_RIGHT_Y:
				return "Right Stick " + ("Up" if neg else "Down")
			JOY_AXIS_TRIGGER_LEFT:
				return "LT"
			JOY_AXIS_TRIGGER_RIGHT:
				return "RT"
		return "Axis %d" % m.axis
	if event is InputEventMouseButton:
		return "Mouse %d" % (event as InputEventMouseButton).button_index
	return ""


## The events currently bound to [param action] (empty if the action is unknown).
static func events_for(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if not InputMap.has_action(action):
		return out
	out.append_array(InputMap.action_get_events(action))
	return out


## Keyboard-only events bound to [param action].
static func keyboard_events(action: StringName) -> Array[InputEventKey]:
	var out: Array[InputEventKey] = []
	for e in events_for(action):
		if e is InputEventKey:
			out.append(e)
	return out


## Short hint for [param action]: the first keyboard binding (or, with
## [param prefer_joypad], the first gamepad binding). "" when unbound.
## Example: describe(InputActions.WAIT) -> "E".
static func describe(action: StringName, prefer_joypad: bool = false) -> String:
	var fallback := ""
	for e in events_for(action):
		var is_joy := e is InputEventJoypadButton or e is InputEventJoypadMotion
		var label := event_label(e)
		if label.is_empty():
			continue
		if is_joy == prefer_joypad:
			return label
		if fallback.is_empty():
			fallback = label
	return fallback


## Every keyboard binding of [param action], joined ("Esc / Backspace / X / C").
static func describe_keys(action: StringName, separator: String = " / ") -> String:
	var parts: PackedStringArray = []
	for e in keyboard_events(action):
		parts.append(event_label(e))
	return separator.join(parts)


## Button-label helper: "Move [M]". Returns [param text] unchanged when unbound.
static func with_hint(text: String, action: StringName) -> String:
	var key := describe(action)
	return text if key.is_empty() else "%s [%s]" % [text, key]


# --- Rebinding --------------------------------------------------------------------

## A key event for a combined keycode-with-modifiers value (as returned by
## InputEventKey.get_keycode_with_modifiers()).
static func make_key_event(code_with_modifiers: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1
	e.keycode = code_with_modifiers & KEY_CODE_MASK
	e.shift_pressed = (code_with_modifiers & KEY_MASK_SHIFT) != 0
	e.ctrl_pressed = (code_with_modifiers & KEY_MASK_CTRL) != 0
	e.alt_pressed = (code_with_modifiers & KEY_MASK_ALT) != 0
	e.meta_pressed = (code_with_modifiers & KEY_MASK_META) != 0
	return e


## Combined keycode-with-modifiers of every keyboard binding of [param action].
static func key_codes(action: StringName) -> Array[int]:
	var out: Array[int] = []
	for e in keyboard_events(action):
		out.append(e.get_keycode_with_modifiers())
	return out


## Replace [param action]'s KEYBOARD bindings with [param codes] (combined
## keycode-with-modifiers ints). Gamepad / mouse bindings are kept.
static func set_keyboard_bindings(action: StringName, codes: Array) -> void:
	if not InputMap.has_action(action):
		return
	for e in keyboard_events(action):
		InputMap.action_erase_event(action, e)
	for c in codes:
		InputMap.action_add_event(action, make_key_event(int(c)))


## The project.godot default events for [param action] (fresh copies).
static func default_events(action: StringName) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var setting = ProjectSettings.get_setting("input/" + String(action))
	if setting is Dictionary:
		for e in setting.get("events", []):
			if e is InputEvent:
				out.append((e as InputEvent).duplicate())
	return out


## Restore [param action] to its project.godot default bindings.
static func restore_defaults(action: StringName) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	for e in default_events(action):
		InputMap.action_add_event(action, e)


## Restore every rebindable action to its default bindings.
static func restore_all_defaults() -> void:
	for entry in REBINDABLE:
		restore_defaults(entry["action"])


## Rebindable action (other than [param except_action]) currently bound to key
## [param code], or &"" when none.
static func find_conflict(code: int, except_action: StringName = &"") -> StringName:
	for entry in REBINDABLE:
		var a: StringName = entry["action"]
		if a == except_action:
			continue
		if code in key_codes(a):
			return a
	return &""


## Display label of a rebindable [param action] (falls back to the action name).
static func label_for(action: StringName) -> String:
	for entry in REBINDABLE:
		if entry["action"] == action:
			return entry["label"]
	return String(action)


# --- Gating -----------------------------------------------------------------------

## True for a developer hotkey press: debug builds only, AND Ctrl+Shift held, so no
## debug helper can ever fire from a plain gameplay key. Pass [param keycode] to
## match a specific key as well.
static func is_debug_hotkey(event: InputEvent, keycode: Key = KEY_NONE) -> bool:
	if not OS.is_debug_build():
		return false
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	if not (k.ctrl_pressed and k.shift_pressed):
		return false
	return keycode == KEY_NONE or k.keycode == keycode


## True while a full-screen overlay (Settings, ...) is open, so board/HUD handlers
## should ignore gameplay input underneath it.
static func gameplay_input_blocked(tree: SceneTree) -> bool:
	if tree == null:
		return false
	for n in tree.get_nodes_in_group(OVERLAY_GROUP):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree():
			return true
	return false
