class_name GestureClassifier
extends RefCounted

## PURE touch-gesture state machine: normalised pointer events in, game INTENTS out.
##
## This class has NO scene dependencies -- no [Node], no [Viewport], no [Input], no
## wall clock. Every entry point takes the current time as a parameter, so a test can
## drive a 0.5s long-press in a single synchronous call instead of waiting on a timer
## (see [code]tests/unit/test_gesture_classifier.gd[/code]). The scene-facing half of
## the feature lives in [TouchInputAdapter], which is the only thing that knows what a
## camera or a board cursor is.
##
## Intents emitted (see [TouchInputAdapter] for what each is wired to):
##   [signal tapped]        -- one finger down and up inside the slop radius, released
##                             before [member long_press_sec]. Means "select / confirm".
##   [signal long_pressed]  -- one finger held past [member long_press_sec] without
##                             leaving the slop radius. Means "inspect this cell".
##   [signal pan_started] / [signal panned] / [signal pan_ended]
##                          -- one finger dragged past [member slop_px]. [signal panned]
##                             carries the SCREEN-space delta since the previous event.
##   [signal pinched]       -- two fingers, carrying the distance RATIO since the previous
##                             event (>1 = fingers spreading = zoom in) and the midpoint.
##
## State machine (one gesture per touch sequence -- it never reclassifies mid-stream):
## [codeblock]
##   IDLE --1st finger down--> PENDING --moved > slop--> PAN --lift--> (SPENT/IDLE)
##                               |  |
##                               |  +--held > long_press_sec--> SPENT (long_pressed)
##                               +--lift inside slop--> IDLE   (tapped)
##   PENDING/PAN --2nd finger down--> PINCH --any lift--> SPENT --all lifted--> IDLE
##   3+ fingers, or a lift after a completed gesture --> SPENT (ignored until all up)
## [/codeblock]
##
## SPENT is what stops one physical touch from producing two intents: once a gesture has
## resolved (or been disqualified), nothing more is emitted until every finger is up.

## One-finger drag beyond this many screen pixels stops being a tap and becomes a pan.
## Also the radius a long-press must stay inside.
var slop_px: float = 16.0

## Seconds a finger must be held (inside the slop radius) before it reads as an inspect.
var long_press_sec: float = 0.5

## Pinch guard: two fingers closer together than this are treated as noise rather than a
## zoom, so a near-zero denominator can never produce an absurd ratio.
var min_pinch_distance_px: float = 8.0

signal tapped(position: Vector2)
signal long_pressed(position: Vector2)
signal pan_started(position: Vector2)
signal panned(delta: Vector2)
signal pan_ended()
signal pinched(factor: float, center: Vector2)

enum State {
	IDLE,     ## Nothing down.
	PENDING,  ## One finger down, still inside the slop radius -- tap or long-press or pan.
	PAN,      ## One finger dragging.
	PINCH,    ## Two fingers.
	SPENT,    ## Gesture resolved or disqualified; ignore until every finger lifts.
}

var _state: int = State.IDLE
## index -> latest screen position, for every finger currently down.
var _touches: Dictionary = {}
## The finger that owns a one-finger gesture (-1 when none).
var _primary: int = -1
var _start_pos: Vector2 = Vector2.ZERO
var _last_pos: Vector2 = Vector2.ZERO
var _start_time: float = 0.0
var _pinch_last_dist: float = 0.0


## Current [enum State]. Exposed for tests and for the adapter's "is a gesture in flight"
## checks; nothing outside should need to branch on it.
func get_state() -> int:
	return _state


## True while a one-finger drag is actively panning.
func is_panning() -> bool:
	return _state == State.PAN


## A finger touched down. [param now] is seconds from any monotonic source.
func touch_down(index: int, position: Vector2, now: float) -> void:
	_touches[index] = position

	if _touches.size() == 1 and _state == State.IDLE:
		_primary = index
		_start_pos = position
		_last_pos = position
		_start_time = now
		_state = State.PENDING
		return

	if _touches.size() == 2:
		# A second finger always wins: whatever the first was doing becomes a pinch.
		if _state == State.PAN:
			pan_ended.emit()
		_state = State.PINCH
		_primary = -1
		_pinch_last_dist = _two_finger_distance()
		return

	# Three or more fingers (or a second sequence starting mid-gesture): disqualify.
	if _state == State.PAN:
		pan_ended.emit()
	_state = State.SPENT
	_primary = -1


## A finger moved. Positions are absolute screen space; deltas are derived here so the
## caller never has to reconcile Godot's per-event [code]relative[/code] values.
func touch_move(index: int, position: Vector2, now: float) -> void:
	if not _touches.has(index):
		return
	_touches[index] = position

	match _state:
		State.PENDING:
			if index != _primary:
				return
			if position.distance_to(_start_pos) > slop_px:
				_state = State.PAN
				pan_started.emit(_start_pos)
				panned.emit(position - _last_pos)
			_last_pos = position
		State.PAN:
			if index != _primary:
				return
			panned.emit(position - _last_pos)
			_last_pos = position
		State.PINCH:
			var dist: float = _two_finger_distance()
			if _pinch_last_dist < min_pinch_distance_px or dist < min_pinch_distance_px:
				_pinch_last_dist = dist
				return
			var factor: float = dist / _pinch_last_dist
			_pinch_last_dist = dist
			if is_finite(factor) and factor > 0.0 and not is_equal_approx(factor, 1.0):
				pinched.emit(factor, _two_finger_center())
		_:
			pass


## A finger lifted. Resolves a tap or a long-press when the primary finger comes up from
## [constant State.PENDING], and closes a pan.
func touch_up(index: int, position: Vector2, now: float) -> void:
	var was_tracked: bool = _touches.has(index)
	_touches.erase(index)
	if not was_tracked:
		_settle()
		return

	match _state:
		State.PENDING:
			if index == _primary and position.distance_to(_start_pos) <= slop_px:
				# tick() normally fires the long-press on time; this covers a caller that
				# never ticks, so a long hold can never degrade into a tap.
				if now - _start_time >= long_press_sec:
					long_pressed.emit(_start_pos)
				else:
					tapped.emit(_start_pos)
			_state = State.SPENT
		State.PAN:
			if index == _primary:
				pan_ended.emit()
			_state = State.SPENT
		State.PINCH:
			_state = State.SPENT
		_:
			pass

	_settle()


## Advance the clock without any pointer movement. The adapter calls this every frame; it
## is what turns "still holding" into a long-press at exactly [member long_press_sec].
func tick(now: float) -> void:
	if _state != State.PENDING:
		return
	if now - _start_time < long_press_sec:
		return
	if _last_pos.distance_to(_start_pos) > slop_px:
		return
	long_pressed.emit(_start_pos)
	_state = State.SPENT


## Trackpad / OS-level pinch (Godot's [InputEventMagnifyGesture]) forwarded straight
## through as a zoom intent. It arrives already classified by the platform, so it bypasses
## the state machine entirely and never disturbs a touch gesture in flight.
func magnify(factor: float, center: Vector2) -> void:
	if not is_finite(factor) or factor <= 0.0:
		return
	pinched.emit(factor, center)


## Drop all state (focus loss, scene change, pause). Emits [signal pan_ended] if a pan was
## live so the consumer is never left believing the finger is still down.
func reset() -> void:
	var was_panning: bool = _state == State.PAN
	_touches.clear()
	_primary = -1
	_state = State.IDLE
	_pinch_last_dist = 0.0
	if was_panning:
		pan_ended.emit()


func _settle() -> void:
	if _touches.is_empty():
		_state = State.IDLE
		_primary = -1
		_pinch_last_dist = 0.0


func _two_finger_positions() -> Array:
	var keys: Array = _touches.keys()
	if keys.size() < 2:
		return []
	return [_touches[keys[0]], _touches[keys[1]]]


func _two_finger_distance() -> float:
	var p: Array = _two_finger_positions()
	if p.is_empty():
		return 0.0
	return (p[0] as Vector2).distance_to(p[1] as Vector2)


func _two_finger_center() -> Vector2:
	var p: Array = _two_finger_positions()
	if p.is_empty():
		return Vector2.ZERO
	return ((p[0] as Vector2) + (p[1] as Vector2)) * 0.5
