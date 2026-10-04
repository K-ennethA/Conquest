class_name OverworldCamera
extends Camera3D

## The overworld camera (docs/design/OVERWORLD.md §3.3): south-facing and never rotating (the
## canopy dither and a future cutaway assume that), following the hero, clamped to the area.
## Its pitch / FOV / distance and follow behaviour come from the active overworld feel preset
## ([OverworldFeel], [method apply_feel]); the constants below are the "current" feel -- the
## battle camera's pitch and FOV (GameWorld.tscn: 50 deg down, fov 50), a little closer, an
## eased lerp follow.
##
## Duck-types TouchInputAdapter's camera contract -- [method zoom_by] (pinch / wheel, clamped
## band) and [method pan_by_screen_delta] (a temporary look-ahead that springs back) -- so touch
## works with no adapter change.

const PITCH_DEG: float = 50.0
const FOV_DEG: float = 50.0
const DEFAULT_DISTANCE: float = 14.0
const MIN_DISTANCE: float = 10.0
const MAX_DISTANCE: float = 28.0
## A building interior is a small room: a little closer than outdoors, the whole room in view.
const INTERIOR_DISTANCE: float = 13.5
## Follow smoothing (per second, exponential).
const FOLLOW_RATE: float = 7.0
const LOOK_RETURN_RATE: float = 3.0
const FOLLOW_LERP := &"lerp"
const FOLLOW_SMOOTH := &"smooth"

var distance: float = DEFAULT_DISTANCE
var target: Node3D = null
## World-space clamp for the look-at point (the area rect).
var bounds: Rect2 = Rect2()
## Feel knobs (defaults = the "current" feel). follow_mode "lerp": the legacy
## clamp(delta x rate) lerp; "smooth": frame-rate-independent 1 - exp(-rate x delta) lag toward
## the hero plus a look-ahead of lookahead_seconds of his glide velocity (capped at
## lookahead_max metres, eased in at lookahead_rate per second), clamped to [member bounds].
var pitch_deg: float = PITCH_DEG
var fov_deg: float = FOV_DEG
var follow_mode: StringName = FOLLOW_LERP
var follow_rate: float = FOLLOW_RATE
var lookahead_seconds: float = 0.0
var lookahead_max: float = 0.0
var lookahead_rate: float = 0.0
var _focus: Vector3 = Vector3.ZERO
var _look_offset: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO


func _ready() -> void:
	_apply_lens()
	current = true


## Take the camera knobs of a resolved feel preset ([method OverworldFeel.resolve]); an
## [param interior] takes the preset's whole-room framing.
func apply_feel(feel: Dictionary, interior: bool) -> void:
	if interior:
		pitch_deg = float(feel.get("interior_pitch_deg", PITCH_DEG))
		fov_deg = float(feel.get("interior_fov_deg", FOV_DEG))
		distance = float(feel.get("interior_distance", INTERIOR_DISTANCE))
	else:
		pitch_deg = float(feel.get("cam_pitch_deg", PITCH_DEG))
		fov_deg = float(feel.get("cam_fov_deg", FOV_DEG))
		distance = float(feel.get("cam_distance", DEFAULT_DISTANCE))
	follow_mode = StringName(feel.get("cam_follow", FOLLOW_LERP))
	follow_rate = float(feel.get("cam_follow_rate", FOLLOW_RATE))
	lookahead_seconds = float(feel.get("cam_lookahead_s", 0.0))
	lookahead_max = float(feel.get("cam_lookahead_max", 0.0))
	lookahead_rate = float(feel.get("cam_lookahead_rate", 0.0))
	_lead = Vector3.ZERO
	if is_inside_tree():
		_apply_lens()


func _apply_lens() -> void:
	fov = fov_deg
	rotation_degrees = Vector3(-pitch_deg, 0.0, 0.0)


## Jump straight to the target (area load, warps).
func snap() -> void:
	_lead = Vector3.ZERO
	if target != null and is_instance_valid(target):
		_focus = _clamped(target.global_position)
	_apply()


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		if follow_mode == FOLLOW_SMOOTH:
			var vel: Vector3 = (target as OverworldActor).glide_velocity if target is OverworldActor else Vector3.ZERO
			var lead_want: Vector3 = (vel * lookahead_seconds).limit_length(lookahead_max)
			_lead = _lead.lerp(lead_want, 1.0 - exp(-lookahead_rate * delta))
			var want_s: Vector3 = _clamped(target.global_position + _lead)
			_focus = _focus.lerp(want_s, 1.0 - exp(-follow_rate * delta))
		else:
			var want: Vector3 = _clamped(target.global_position)
			_focus = _focus.lerp(want, clampf(delta * follow_rate, 0.0, 1.0))
	_look_offset = _look_offset.lerp(Vector3.ZERO, clampf(delta * LOOK_RETURN_RATE, 0.0, 1.0))
	_apply()


func _apply() -> void:
	var p: float = deg_to_rad(pitch_deg)
	var look: Vector3 = _focus + _look_offset
	global_position = look + Vector3(0.0, sin(p) * distance, cos(p) * distance)


## The ground point the camera looks at (tests / the feel gate).
func focus_point() -> Vector3:
	return _focus + _look_offset


func _clamped(p: Vector3) -> Vector3:
	if bounds.size == Vector2.ZERO:
		return p
	return Vector3(clampf(p.x, bounds.position.x, bounds.end.x), p.y,
		clampf(p.z, bounds.position.y, bounds.end.y))


## Pinch / wheel zoom (factor > 1 zooms in).
func zoom_by(factor: float, _screen_pos: Vector2 = Vector2.ZERO) -> void:
	if factor <= 0.0:
		return
	distance = clampf(distance / factor, MIN_DISTANCE, MAX_DISTANCE)


## A drag peeks ahead; it springs back once released.
func pan_by_screen_delta(delta: Vector2) -> void:
	var k: float = distance / 900.0
	_look_offset += Vector3(-delta.x * k, 0.0, -delta.y * k)
	_look_offset = _look_offset.limit_length(6.0)


## Project the ground plane (y = [param plane_y]) under screen point [param screen_pos].
func ground_point(screen_pos: Vector2, plane_y: float = 0.0) -> Variant:
	var origin: Vector3 = project_ray_origin(screen_pos)
	var dir: Vector3 = project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4:
		return null
	var t: float = (plane_y - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t
