extends GutTest

## Pins the BY-NAME contract between TouchInputAdapter and the scripts it drives.
##
## The adapter deliberately owns no command path of its own: it calls existing methods on
## CameraController and on the board cursor through Object.call(), so touch and mouse can
## never diverge. The cost of that choice is that a rename on either side fails SILENTLY --
## the has_method() guard simply stops matching and the gesture quietly does nothing. These
## assertions are what turns that into a red test instead of a bug report from a phone.
##
## Reads script method lists only; nothing is instantiated, so there are no orphans and no
## scene tree involved.

const CAMERA_SCRIPT := preload("res://game/visuals/CameraController.gd")
const CURSOR_SCRIPT := preload("res://board/cursor/cursor.gd")
const ADAPTER_SCRIPT := preload("res://game/input/TouchInputAdapter.gd")


func _method_names(script: GDScript) -> PackedStringArray:
	var names := PackedStringArray()
	for m in script.get_script_method_list():
		names.append(String(m["name"]))
	return names


func test_camera_exposes_the_pan_intent_target() -> void:
	assert_true(_method_names(CAMERA_SCRIPT).has("pan_by_screen_delta"),
		"one-finger drag calls CameraController.pan_by_screen_delta by name")


func test_camera_exposes_the_zoom_intent_target() -> void:
	assert_true(_method_names(CAMERA_SCRIPT).has("zoom_by"),
		"pinch calls CameraController.zoom_by by name")


func test_cursor_exposes_the_tap_and_inspect_targets() -> void:
	var names := _method_names(CURSOR_SCRIPT)
	assert_true(names.has("_handle_mouse_click"),
		"the tap intent routes to the cursor's existing click handler")
	assert_true(names.has("_handle_mouse_movement"),
		"the long-press inspect routes to the cursor's existing hover handler, which is "
		+ "what emits GameEvents.cursor_moved for the terrain/unit info panels")


func test_adapter_still_routes_every_classified_intent() -> void:
	var names := _method_names(ADAPTER_SCRIPT)
	for handler in ["_on_tapped", "_on_long_pressed", "_on_panned", "_on_pinched"]:
		assert_true(names.has(handler),
			"every GestureClassifier signal keeps a handler on the adapter (%s)" % handler)
