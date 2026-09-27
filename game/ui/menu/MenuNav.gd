class_name MenuNav
extends RefCounted

## Navigation helpers shared by every out-of-battle screen:
##   * [method change_scene] -- quick fade-out / fade-in scene change.
##   * [method is_back_event] -- the one definition of "go back" (the named
##     [code]cancel[/code] action: Esc / Backspace / gamepad B, plus ui_cancel).
##   * [method hover_focus] / [method focus_deferred] -- mouse and keyboard/pad
##     share ONE highlight: hovering a control focuses it, so there is never a
##     "hovered" item and a different "focused" item on screen at once.
##
## The fade lives on a CanvasLayer parented to the tree ROOT (not the screen), so it
## survives the scene swap. It is robust by construction: a second request while a
## fade is running is ignored, and with no SceneTree it simply does nothing.

const FADE_OUT := 0.12
const FADE_IN := 0.18
const LAYER_NAME := "MenuFade"


## Fade to [param path]. Falls back to an instant change if the fade layer cannot
## be created (e.g. no root viewport).
static func change_scene(from: Node, path: String) -> void:
	if from == null or not from.is_inside_tree():
		return
	var tree := from.get_tree()
	var root: Window = tree.root
	if root == null:
		tree.change_scene_to_file(path)
		return
	var existing := root.get_node_or_null(LAYER_NAME)
	if existing != null:
		return  # a transition is already in flight

	var layer := CanvasLayer.new()
	layer.name = LAYER_NAME
	layer.layer = 120
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var rect := ColorRect.new()
	rect.color = MenuTheme.BG_DEEP
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP  # swallow clicks mid-fade
	rect.modulate.a = 0.0
	layer.add_child(rect)
	root.add_child(layer)

	var tw := layer.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(rect, "modulate:a", 1.0, FADE_OUT)
	tw.tween_callback(func() -> void: tree.change_scene_to_file(path))
	tw.tween_interval(0.04)
	tw.tween_callback(func() -> void: rect.mouse_filter = Control.MOUSE_FILTER_IGNORE)
	tw.tween_property(rect, "modulate:a", 0.0, FADE_IN)
	tw.tween_callback(layer.queue_free)


## True for a fresh (non-echo) press of the back / cancel input.
static func is_back_event(event: InputEvent) -> bool:
	if event == null or not event.is_pressed() or event.is_echo():
		return false
	if InputMap.has_action(&"cancel") and event.is_action_pressed(&"cancel"):
		return true
	return event.is_action_pressed(&"ui_cancel")


## True for a fresh press of the "next tab / page" shoulder input (RB, Tab, R).
static func is_next_event(event: InputEvent) -> bool:
	return event != null and not event.is_echo() and InputMap.has_action(&"cycle_next") \
		and event.is_action_pressed(&"cycle_next")


static func is_prev_event(event: InputEvent) -> bool:
	return event != null and not event.is_echo() and InputMap.has_action(&"cycle_prev") \
		and event.is_action_pressed(&"cycle_prev")


## Hovering [param control] with the mouse gives it keyboard focus.
static func hover_focus(control: Control) -> void:
	if control == null:
		return
	control.mouse_entered.connect(func() -> void:
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE \
				and not (control is BaseButton and (control as BaseButton).disabled):
			control.grab_focus())


## Grab focus on the next frame (after layout / after the scene is in the tree).
static func focus_deferred(control: Control) -> void:
	if control != null:
		control.call_deferred(&"grab_focus")


## True when a gamepad is connected -- hint glyphs then read A / B instead of keys.
static func using_gamepad() -> bool:
	return not Input.get_connected_joypads().is_empty()
