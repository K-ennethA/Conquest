class_name TouchInputAdapter
extends Node

## Scene-facing half of the touch gesture layer: subscribes to Godot's touch events, runs
## them through the pure [GestureClassifier], and calls the game's EXISTING camera and
## cursor APIs. It adds no new command path -- every intent lands on the same method a
## mouse already drives.
##
## Mounted once, as a child of the [code]MobileDisplay[/code] autoload, so it is alive for
## every scene and self-gates: with no [Camera3D] exposing [method
## CameraController.pan_by_screen_delta] (menus, galleries, headless) the camera intents
## are silently dropped.
##
## [b]Desktop mouse behaviour is untouched.[/b] This node reads ONLY
## [InputEventScreenTouch], [InputEventScreenDrag] and [InputEventMagnifyGesture]. A mouse
## generates none of those, so on a mouse-driven desktop this node never runs a line of
## routing code. The one thing it does add on desktop is trackpad pinch-to-zoom, which is
## a magnify gesture, not a mouse event.
##
## [b]Intent -> existing API map[/b]
## [codeblock]
##   tap          -> cursor._handle_mouse_click(pos)     (select / confirm; see below)
##   one-finger   -> CameraController.pan_by_screen_delta(delta)
##   pinch        -> CameraController.zoom_by(1.0 / factor, center)
##   long-press   -> cursor._handle_mouse_movement(pos)  (moves the board cursor, which
##                   emits GameEvents.cursor_moved -- the exact signal TerrainInfoPanel /
##                   UnitHoverPanel already use for mouse hover info)
## [/codeblock]
##
## [b]THE emulate_mouse_from_touch DECISION[/b]
##
## Godot's [code]input_devices/pointing/emulate_mouse_from_touch[/code] defaults to
## [code]true[/code], and this project deliberately LEAVES IT AT THE DEFAULT -- the setting
## is not written to [code]project.godot[/code] at all. Reasoning:
##
## [i]Why not turn it off[/i] (which would make this adapter the single owner of touch):
## Godot's [BaseButton] only handles [InputEventMouseButton] in [method Control._gui_input];
## it does not handle [InputEventScreenTouch]. Disabling emulation would therefore stop
## every HUD and menu button in the game from responding to a tap. That is a much bigger
## regression than the one it fixes, and it cannot be validated without a device.
##
## [i]What that costs, and how it is handled[/i]: with emulation on, a tap ALREADY reaches
## [code]cursor.gd[/code] as a synthetic left click -- this is the "Tap == click" row that
## [code]docs/MOBILE_PLAN.md[/code] records as already working. If this adapter ALSO routed
## its tap intent to the cursor, every tap would select twice. So tap routing is
## [b]auto-detected[/b] in [method _ready]: [member _route_taps] is true only when mouse
## emulation is off. The classifier still classifies taps either way (it is pure and fully
## tested); the adapter simply declines to double-fire them.
##
## [i]Residual known issue[/i]: because emulation raises its synthetic mouse-DOWN at touch
## down, starting a camera pan from a board tile also selects that tile before the drag is
## classified. The selection is harmless (the next tap replaces it) and undoing it would
## mean teaching [code]cursor.gd[/code] to ignore
## [code]InputEvent.DEVICE_ID_EMULATION[/code] events -- a change to the shared click path
## that should be made and verified on a real device, not blind. Logged rather than guessed.
##
## [code]emulate_touch_from_mouse[/code] is likewise NOT enabled. It would let these
## gestures be driven with a desktop mouse for testing, but it does exactly what this
## adapter is forbidden from doing: it changes what a mouse drag means (a left-drag on the
## board would start panning the camera). Gesture behaviour is covered by the classifier's
## unit tests instead.

## Pixels of finger travel before a touch stops being a tap and becomes a camera pan.
@export var slop_px: float = 16.0
## Seconds a finger must be held still before it reads as inspect.
@export var long_press_sec: float = 0.5

var _classifier: GestureClassifier = null
## See the emulate_mouse_from_touch section of the class doc. Resolved once in _ready.
var _route_taps: bool = false
## Touch indices whose press landed on HUD chrome -- their whole sequence is ignored so a
## drag that starts on a panel can never pan the board underneath it.
var _blocked: Dictionary = {}


func _ready() -> void:
	_classifier = GestureClassifier.new()
	_classifier.slop_px = slop_px
	_classifier.long_press_sec = long_press_sec
	_classifier.tapped.connect(_on_tapped)
	_classifier.long_pressed.connect(_on_long_pressed)
	_classifier.panned.connect(_on_panned)
	_classifier.pinched.connect(_on_pinched)

	# Only own taps when nothing else does. See the class doc.
	_route_taps = not bool(ProjectSettings.get_setting(
		"input_devices/pointing/emulate_mouse_from_touch", true))


func _process(_delta: float) -> void:
	# Drives the long-press timer. Cheap: the classifier returns immediately unless a
	# finger is actually pending.
	if _classifier != null:
		_classifier.tick(_now())


func _unhandled_input(event: InputEvent) -> void:
	if _classifier == null:
		return

	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			# A press that lands on HUD chrome belongs to the UI, not the board.
			if _is_over_ui(t.position):
				_blocked[t.index] = true
				return
			_classifier.touch_down(t.index, t.position, _now())
		else:
			if _blocked.erase(t.index):
				return
			_classifier.touch_up(t.index, t.position, _now())
		return

	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _blocked.has(d.index):
			return
		_classifier.touch_move(d.index, d.position, _now())
		return

	if event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		if _is_over_ui(g.position):
			return
		_classifier.magnify(g.factor, g.position)


func _notification(what: int) -> void:
	# Losing focus mid-drag would otherwise leave the classifier believing a finger is
	# still down, and the next touch would resume the stale pan.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _classifier != null:
		_classifier.reset()
		_blocked.clear()


# --- Intent handlers --------------------------------------------------------

func _on_tapped(position: Vector2) -> void:
	if not _route_taps:
		return
	_call_cursor("_handle_mouse_click", position)


func _on_long_pressed(position: Vector2) -> void:
	# Inspect == exactly what a mouse hover does: move the board cursor onto the cell,
	# which emits GameEvents.cursor_moved and lights up TerrainInfoPanel / UnitHoverPanel.
	_call_cursor("_handle_mouse_movement", position)


func _on_panned(delta: Vector2) -> void:
	var cam := _camera()
	if cam != null and cam.has_method("pan_by_screen_delta"):
		cam.call("pan_by_screen_delta", delta)


func _on_pinched(factor: float, center: Vector2) -> void:
	var cam := _camera()
	if cam == null or not cam.has_method("zoom_by") or factor <= 0.0:
		return
	# The classifier's factor is a FINGER-DISTANCE ratio (>1 = spreading = zoom in); the
	# camera's is a DISTANCE-to-board multiplier (<1 = closer). They are reciprocals.
	cam.call("zoom_by", 1.0 / factor, center)


# --- Scene lookups (all null-safe; absent nodes mean the intent is dropped) --

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _camera() -> Camera3D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()


## The board cursor registers itself in the "board_cursor" group in its own _ready.
##
## The two methods called here are underscore-prefixed on [code]cursor.gd[/code], which has
## no public "act at this screen position" API. They are invoked through [method
## Object.call] behind a [method Object.has_method] guard rather than adding one, so the
## shared click path -- owned by the battle command loop -- is not modified by the mobile
## work. If a public wrapper is ever added there, swap these two call sites for it.
func _call_cursor(method: String, position: Vector2) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var cursor := tree.get_first_node_in_group("board_cursor")
	if cursor == null or not is_instance_valid(cursor) or not cursor.has_method(method):
		return
	cursor.call(method, position)


## Same HUD test the mouse paths in [code]cursor.gd[/code] and [CameraController] use, so
## touch and mouse agree on exactly which pixels belong to the UI.
func _is_over_ui(position: Vector2) -> bool:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return false
	var ui_layout := tree.current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout != null and ui_layout.has_method("is_mouse_over_ui"):
		return bool(ui_layout.call("is_mouse_over_ui", position))
	return false
