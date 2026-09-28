class_name OverworldCamera
extends Camera3D

## The overworld camera (docs/design/OVERWORLD.md §3.3): the battle camera's pitch and FOV
## (GameWorld.tscn: 50 deg down, fov 50), a little closer, south-facing and never rotating (the
## canopy dither and a future cutaway assume that), following the hero with an eased glide and
## clamped to the area.
##
## Duck-types TouchInputAdapter's camera contract -- [method zoom_by] (pinch / wheel, clamped
## band) and [method pan_by_screen_delta] (a temporary look-ahead that springs back) -- so touch
## works with no adapter change.

const PITCH_DEG: float = 50.0
const FOV_DEG: float = 50.0
const DEFAULT_DISTANCE: float = 14.0
const MIN_DISTANCE: float = 10.0
const MAX_DISTANCE: float = 28.0
## Follow smoothing (per second, exponential).
const FOLLOW_RATE: float = 7.0
const LOOK_RETURN_RATE: float = 3.0

var distance: float = DEFAULT_DISTANCE
var target: Node3D = null
## World-space clamp for the look-at point (the area rect).
var bounds: Rect2 = Rect2()
var _focus: Vector3 = Vector3.ZERO
var _look_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	fov = FOV_DEG
	rotation_degrees = Vector3(-PITCH_DEG, 0.0, 0.0)
	current = true


## Jump straight to the target (area load, warps).
func snap() -> void:
	if target != null and is_instance_valid(target):
		_focus = _clamped(target.global_position)
	_apply()


func _process(delta: float) -> void:
	if target != null and is_instance_valid(target):
		var want: Vector3 = _clamped(target.global_position)
		_focus = _focus.lerp(want, clampf(delta * FOLLOW_RATE, 0.0, 1.0))
	_look_offset = _look_offset.lerp(Vector3.ZERO, clampf(delta * LOOK_RETURN_RATE, 0.0, 1.0))
	_apply()


func _apply() -> void:
	var p: float = deg_to_rad(PITCH_DEG)
	var look: Vector3 = _focus + _look_offset
	global_position = look + Vector3(0.0, sin(p) * distance, cos(p) * distance)


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
