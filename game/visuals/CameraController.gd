extends Camera3D

## RTS / Fire-Emblem style camera controller for the tactical board.
##
## Attached to the single PERSPECTIVE [Camera3D] in GameWorld.tscn. It NEVER changes
## the camera's tilt (basis) or field of view -- it only translates the camera
## across the ground (XZ) plane (pan) and DOLLIES it along its view axis (zoom, by
## changing the distance from the camera to the ground point it looks at). The
## camera therefore keeps its authored ~50-degree angle at all times; only where it
## looks and how close it is change.
##
## Controls:
##   * PAN   -- WASD/arrows (smooth, in [method _process]), middle-mouse grab-drag,
##              and optional screen-edge scroll.
##   * ZOOM  -- mouse wheel (dollies toward the cursor), clamped to a distance range.
##   * FIT   -- on [signal CombatServices.board_ready] the camera centers on the
##              board and pulls back to a distance that frames it.
##
## Input hygiene: mouse handling is in [method _unhandled_input] so UI wins first,
## and consults the HUD's is_mouse_over_ui(). Keyboard pan is suppressed while a text
## field has focus. It only reads input and never marks it handled, so the cursor and
## unit selection keep working.

# --- Tunables ---------------------------------------------------------------

## Ground units / second for keyboard pan (scaled by zoom so it feels consistent).
@export var keyboard_pan_speed: float = 18.0
## Grab-drag multiplier. 1.0 = 1:1 ground-follows-cursor at the view center.
@export var drag_speed: float = 1.0
## Mouse-wheel zoom: fraction of the current distance added/removed per notch.
@export var zoom_step: float = 0.1

## Zoom is the camera's DISTANCE to its ground focus (perspective dolly). Smaller =
## closer. The upper bound may be raised at fit time so a large map still frames.
@export var dist_min: float = 10.0
@export var dist_max: float = 90.0

## Extra headroom around the board when fitting (1.0 = exact). A bit generous so the
## whole board frames without the edges hugging the screen.
@export var fit_margin: float = 1.12

## How far past the board edge the focus may pan before being clamped back.
@export var pan_edge_margin: float = 6.0

## Screen-edge scroll (RTS style). Off by default.
@export var edge_scroll_enabled: bool = false
@export var edge_scroll_margin_px: float = 24.0
@export var edge_scroll_speed: float = 16.0

# --- Internal state ---------------------------------------------------------

## Ground-plane (XZ) basis derived once from the authored camera angle: the screen
## "right" and "forward" directions flattened onto the board, so pan tracks the
## visible axes without rotating.
var _ground_right: Vector3 = Vector3.RIGHT
var _ground_forward: Vector3 = Vector3.FORWARD

## Board bounds on the XZ plane and their center, set by the fit.
var _board_min: Vector2 = Vector2.ZERO
var _board_max: Vector2 = Vector2.ZERO
var _board_center: Vector3 = Vector3.ZERO
var _has_bounds: bool = false

## Effective upper distance clamp (>= dist_max; grows to frame oversized maps).
var _dist_max_runtime: float = 90.0

## Reference distance captured at fit, used to scale pan speed by zoom.
var _base_distance: float = 30.0

## Middle-mouse drag state.
var _dragging: bool = false


func _ready() -> void:
	_dist_max_runtime = dist_max
	_capture_ground_basis()
	_base_distance = maxf(_current_distance(), 1.0)

	if CombatServices and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)
	if CombatServices and CombatServices.board() != null:
		call_deferred("fit_to_map")


## Flatten the authored camera axes onto the ground plane. Called once; the basis
## never changes because pan only translates and zoom only dollies along -Z.
func _capture_ground_basis() -> void:
	var b := global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	if right.length() > 0.0001:
		_ground_right = right.normalized()
	var fwd := -b.z  # camera looks down -Z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length() > 0.0001:
		_ground_forward = fwd_flat.normalized()


# --- Distance (perspective zoom) --------------------------------------------

## Distance from the camera to the ground point its center ray hits.
func _current_distance() -> float:
	return global_position.distance_to(_camera_focus_ground())

## Dolly the camera to [param d] units from its current ground focus, along the view
## axis, so the focus stays put and only closeness changes. Clamped.
func _set_distance(d: float) -> void:
	var focus := _camera_focus_ground()
	var fwd := (-global_transform.basis.z).normalized()
	var clamped := clampf(d, dist_min, _dist_max_runtime)
	global_position = focus - fwd * clamped


# --- Fit to map -------------------------------------------------------------

func _on_board_ready() -> void:
	call_deferred("fit_to_map")


## Center on the board and pull back to a distance that frames the whole thing.
func fit_to_map() -> void:
	if not _compute_board_bounds():
		return

	var world_w: float = _board_max.x - _board_min.x
	var world_d: float = _board_max.y - _board_min.y

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = 1.777
	if vp.y > 0.0:
		aspect = vp.x / vp.y

	# The board's depth foreshortens by the camera tilt (|forward.y| = sin(pitch)),
	# so it needs less screen-vertical at a shallower angle. Convert the larger of the
	# (foreshortened depth) / (width scaled to aspect) into the vertical WORLD span the
	# frame must cover, then solve the perspective distance for that span at this fov.
	var tilt: float = clampf(absf((-global_transform.basis.z).y), 0.4, 1.0)
	var need_vertical: float = world_d * tilt
	var need_horizontal: float = world_w / maxf(aspect, 0.001)
	var span: float = maxf(need_vertical, need_horizontal) * fit_margin
	var half_fov: float = deg_to_rad(fov) * 0.5
	var dist: float = (span * 0.5) / maxf(tan(half_fov), 0.01)

	_dist_max_runtime = maxf(dist_max, dist)
	_move_focus_to(Vector3(_board_center.x, 0.0, _board_center.z))
	_set_distance(clampf(dist, dist_min, _dist_max_runtime))
	_base_distance = maxf(_current_distance(), 1.0)


## Derive the board's XZ bounds from the live tiles under "Map/Tiles" (each tile a
## 2x2 cell at (col*2, 0, row*2)); expand by the cell footprint. Falls back to Grid.
func _compute_board_bounds() -> bool:
	var tiles := _find_tiles_container()
	var min_x := INF
	var min_z := INF
	var max_x := -INF
	var max_z := -INF
	var count := 0

	if tiles:
		for child in tiles.get_children():
			if child is Node3D:
				var p: Vector3 = child.position
				min_x = minf(min_x, p.x)
				min_z = minf(min_z, p.z)
				max_x = maxf(max_x, p.x)
				max_z = maxf(max_z, p.z)
				count += 1

	if count > 0:
		_board_min = Vector2(min_x, min_z)
		_board_max = Vector2(max_x + 2.0, max_z + 2.0)
		_board_center = Vector3((_board_min.x + _board_max.x) * 0.5, 0.0,
			(_board_min.y + _board_max.y) * 0.5)
		_has_bounds = true
		return true

	if CombatServices and CombatServices.GRID:
		var g = CombatServices.GRID
		var w: float = g.size.x * g.cell_size.x
		var d: float = g.size.z * g.cell_size.z
		_board_min = Vector2(0.0, 0.0)
		_board_max = Vector2(w, d)
		_board_center = Vector3(w * 0.5, 0.0, d * 0.5)
		_has_bounds = true
		return true

	return false


func _find_tiles_container() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.get_node_or_null("Map/Tiles")


# --- Per-frame keyboard + edge pan ------------------------------------------

func _process(delta: float) -> void:
	var dir := Vector3.ZERO

	if not _text_field_has_focus():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir -= _ground_right
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir += _ground_right
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir += _ground_forward
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir -= _ground_forward

	if edge_scroll_enabled:
		dir += _edge_scroll_dir()

	if dir != Vector3.ZERO:
		# Scale by zoom so a keypress covers a consistent fraction of the view.
		var zoom_scale: float = _current_distance() / maxf(_base_distance, 0.001)
		global_position += dir.normalized() * keyboard_pan_speed * zoom_scale * delta
		_clamp_to_board()


func _edge_scroll_dir() -> Vector3:
	if not get_window().has_focus():
		return Vector3.ZERO
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if mp.x < 0.0 or mp.y < 0.0 or mp.x > vp.x or mp.y > vp.y:
		return Vector3.ZERO
	if _is_mouse_over_ui(mp):
		return Vector3.ZERO

	var d := Vector3.ZERO
	var m := edge_scroll_margin_px
	var s := edge_scroll_speed / maxf(keyboard_pan_speed, 0.001)
	if mp.x < m:
		d -= _ground_right * s
	elif mp.x > vp.x - m:
		d += _ground_right * s
	if mp.y < m:
		d += _ground_forward * s
	elif mp.y > vp.y - m:
		d -= _ground_forward * s
	return d


# --- Mouse: wheel zoom + middle-drag pan ------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and not _is_mouse_over_ui(mb.position):
					_zoom_at(mb.position, 1.0 - zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and not _is_mouse_over_ui(mb.position):
					_zoom_at(mb.position, 1.0 + zoom_step)
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed and not _is_mouse_over_ui(mb.position):
					_dragging = true
				else:
					_dragging = false
		return

	if event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var vp_h: float = get_viewport().get_visible_rect().size.y
		if vp_h <= 0.0:
			return
		# World units per screen pixel at the focus depth (perspective): the visible
		# vertical world span at distance d is 2*d*tan(fov/2).
		var d: float = _current_distance()
		var wpp: float = (2.0 * d * tan(deg_to_rad(fov) * 0.5) / vp_h) * drag_speed
		var move := _ground_right * (-mm.relative.x) + _ground_forward * (mm.relative.y)
		global_position += move * wpp
		_clamp_to_board()


## Dolly by [param factor] (<1 closer, >1 farther) while keeping the ground point
## under [param screen_pos] fixed on screen (cursor-anchored zoom).
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before = _ground_point_at(screen_pos)  # Vector3 or null
	_set_distance(_current_distance() * factor)
	var after = _ground_point_at(screen_pos)
	if before != null and after != null:
		var delta: Vector3 = before - after
		global_position += Vector3(delta.x, 0.0, delta.z)
	_clamp_to_board()


# --- Ground-plane helpers ---------------------------------------------------

## World point where the ray through [param screen_pos] meets y=0, or null.
func _ground_point_at(screen_pos: Vector2):
	var origin := project_ray_origin(screen_pos)
	var normal := project_ray_normal(screen_pos)
	if absf(normal.y) < 0.00001:
		return null
	var t: float = -origin.y / normal.y
	if t < 0.0:
		return null
	return origin + normal * t


## World point where the camera's CENTER ray meets y=0 (the focus point).
func _camera_focus_ground() -> Vector3:
	var o := global_position
	var d := -global_transform.basis.z
	if absf(d.y) < 0.00001:
		return Vector3(o.x, 0.0, o.z)
	var t: float = -o.y / d.y
	return o + d * t


## Translate the camera so its focus lands on [param target] (XZ only).
func _move_focus_to(target: Vector3) -> void:
	var focus := _camera_focus_ground()
	global_position += Vector3(target.x - focus.x, 0.0, target.z - focus.z)


## Keep the focus point within the board bounds (plus [member pan_edge_margin]).
func _clamp_to_board() -> void:
	if not _has_bounds:
		return
	var focus := _camera_focus_ground()
	var min_x: float = _board_min.x - pan_edge_margin
	var max_x: float = _board_max.x + pan_edge_margin
	var min_z: float = _board_min.y - pan_edge_margin
	var max_z: float = _board_max.y + pan_edge_margin
	var cx: float = clampf(focus.x, min_x, max_x)
	var cz: float = clampf(focus.z, min_z, max_z)
	global_position += Vector3(cx - focus.x, 0.0, cz - focus.z)


# --- Input hygiene ----------------------------------------------------------

func _is_mouse_over_ui(pos: Vector2) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var ui_layout := scene.get_node_or_null("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		return bool(ui_layout.is_mouse_over_ui(pos))
	return false


func _text_field_has_focus() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var focused := vp.gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
