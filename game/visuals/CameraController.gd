extends Camera3D

## RTS / Fire-Emblem style camera controller for the tactical board.
##
## Attached directly to the single [Camera3D] in GameWorld.tscn. It NEVER changes
## the camera's tilt (basis) or projection type -- it only translates the camera
## across the ground (XZ) plane (pan) and adjusts [member Camera3D.size] (zoom, the
## camera is ORTHOGONAL). The camera therefore keeps its authored look/angle at all
## times; only where it looks and how much it shows changes.
##
## Controls:
##   * PAN   -- WASD and arrow keys (smooth, polled in [method _process]),
##              middle-mouse drag (grab-drag), and optional screen-edge scroll.
##   * ZOOM  -- mouse wheel (zooms toward the cursor), clamped to a sane range.
##   * FIT   -- on [signal CombatServices.board_ready] (fires when a map finishes
##              loading) the camera auto-centers on the board and zooms so the
##              whole board is visible.
##
## Input hygiene: mouse handling lives in [method _unhandled_input] so any UI that
## consumes the event wins first, and it additionally consults the HUD's
## [code]is_mouse_over_ui()[/code] so wheel/drag never fire over a panel. Keyboard
## pan is suppressed while a text field has focus. The controller only reads input;
## it never calls [code]set_input_as_handled()[/code], so the existing cursor
## (board/cursor/cursor.gd) and unit selection keep working unchanged.

# --- Tunables ---------------------------------------------------------------

## Ground units / second for keyboard pan (scaled by current zoom so it feels
## consistent whether zoomed in or out).
@export var keyboard_pan_speed: float = 18.0

## World units the view shifts per pixel of middle-mouse drag is derived from the
## zoom; this multiplier lets it be tuned. 1.0 = 1:1 grab feel at screen center.
@export var drag_speed: float = 1.0

## Mouse-wheel zoom: fraction of the current size added/removed per notch.
@export var zoom_step: float = 0.12

## Zoom clamp for the orthographic [member Camera3D.size]. The upper bound may be
## raised at fit time for very large maps so the whole board stays visible.
@export var zoom_min: float = 6.0
@export var zoom_max: float = 40.0

## Extra headroom around the board when fitting (1.0 = exact, 1.15 = 15% margin).
## Kept small so the steeper, more top-down camera fills the frame (less sky). The
## vertical fit need is computed from the un-foreshortened board depth (see
## fit_to_map), which is already a conservative over-estimate, so a slim margin
## still guarantees the whole board stays visible.
@export var fit_margin: float = 1.08

## How far (world units) past the board edge the view may be panned before it is
## clamped back, so the player can nudge the edge into view but not fly into the void.
@export var pan_edge_margin: float = 6.0

## Screen-edge scroll (RTS style). Off by default: it can feel intrusive and moves
## the camera whenever the pointer nears a window edge. Flip on to enable.
@export var edge_scroll_enabled: bool = false
@export var edge_scroll_margin_px: float = 24.0
@export var edge_scroll_speed: float = 16.0

# --- Internal state ---------------------------------------------------------

## Ground-plane (XZ) basis derived once from the authored camera angle: the screen
## "right" and screen "forward/up" directions flattened onto the board. Panning is
## expressed in these so movement always tracks the visible axes without rotating.
var _ground_right: Vector3 = Vector3.RIGHT
var _ground_forward: Vector3 = Vector3.FORWARD

## Board bounds on the XZ plane (world units) and their center, set by the fit.
var _board_min: Vector2 = Vector2.ZERO
var _board_max: Vector2 = Vector2.ZERO
var _board_center: Vector3 = Vector3.ZERO
var _has_bounds: bool = false

## Effective upper zoom clamp (>= zoom_max; grows to fit oversized maps).
var _zoom_max_runtime: float = 40.0

## Reference size captured at fit, used to scale keyboard/edge pan by zoom.
var _base_size: float = 20.0

## Middle-mouse drag state.
var _dragging: bool = false


func _ready() -> void:
	_zoom_max_runtime = zoom_max
	_base_size = size
	_capture_ground_basis()

	# Fit whenever a map finishes loading and the live board is (re)built.
	if CombatServices and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)

	# If a board already exists (e.g. this node initialized after the first load),
	# fit once on the next frame so tiles are settled in the tree.
	if CombatServices and CombatServices.board() != null:
		call_deferred("fit_to_map")


## Flatten the authored camera axes onto the ground plane. Called once; the basis
## never changes afterward because pan only translates the camera.
func _capture_ground_basis() -> void:
	var b := global_transform.basis
	var right := Vector3(b.x.x, 0.0, b.x.z)
	if right.length() > 0.0001:
		_ground_right = right.normalized()
	var fwd := -b.z  # camera looks down -Z
	var fwd_flat := Vector3(fwd.x, 0.0, fwd.z)
	if fwd_flat.length() > 0.0001:
		_ground_forward = fwd_flat.normalized()


# --- Fit to map -------------------------------------------------------------

func _on_board_ready() -> void:
	# Defer one frame: board_ready can fire in the same frame the tiles are added.
	call_deferred("fit_to_map")


## Center on the board and choose a zoom that shows the whole thing. Only the
## camera's XZ position and orthographic size change; the tilt is preserved.
func fit_to_map() -> void:
	if not _compute_board_bounds():
		return

	var world_w: float = _board_max.x - _board_min.x
	var world_d: float = _board_max.y - _board_min.y

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = 1.777
	if vp.y > 0.0:
		aspect = vp.x / vp.y

	# Orthographic size (KEEP_HEIGHT) = vertical world span. The tilted board maps
	# its X extent to ~screen-horizontal and its Z (depth) to ~screen-vertical.
	# Cover both: vertically we need the depth; horizontally we need width/aspect.
	# Foreshortening only reveals MORE depth, so ignoring it is conservative (safe).
	var need_vertical: float = world_d
	var need_horizontal: float = world_w / maxf(aspect, 0.001)
	var target: float = maxf(need_vertical, need_horizontal) * fit_margin

	# Allow the fit to exceed the normal wheel ceiling for large maps so the whole
	# board is always visible; the raised ceiling then applies to wheel zoom too.
	_zoom_max_runtime = maxf(zoom_max, target)
	size = clampf(target, zoom_min, _zoom_max_runtime)
	_base_size = size

	# Recenter so the camera's center ray meets the ground at the board center.
	_move_focus_to(Vector3(_board_center.x, 0.0, _board_center.z))


## Derive the board's XZ bounds from the live tiles under "Map/Tiles". Each tile is
## a 2x2 world-unit cell whose origin sits at (col*2, 0, row*2); we take the AABB of
## the tile origins and expand by one unit on each side to include the cell footprint.
## Falls back to the Grid resource if no tiles are present.
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
		# Tile origins are the cell's near corner; each cell spans 2 units, so the
		# far edge is +2 and the whole board runs from the first origin to last+2.
		_board_min = Vector2(min_x, min_z)
		_board_max = Vector2(max_x + 2.0, max_z + 2.0)
		_board_center = Vector3((_board_min.x + _board_max.x) * 0.5, 0.0,
			(_board_min.y + _board_max.y) * 0.5)
		_has_bounds = true
		return true

	# Fallback: use the shared Grid (col=X, row=Z; cell 2x2). May be stale but keeps
	# the fit sane if the tiles could not be read.
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
		var zoom_scale: float = size / maxf(_base_size, 0.001)
		global_position += dir.normalized() * keyboard_pan_speed * zoom_scale * delta
		_clamp_to_board()


## Screen-edge scroll direction (zero unless the pointer is near a window edge, the
## window is focused, and the pointer is not over the HUD).
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
# In _unhandled_input so UI that consumes the event takes priority.

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
		# World units per screen pixel at the view center (orthographic, KEEP_HEIGHT).
		var wpp: float = (size / vp_h) * drag_speed
		# Grab-drag: the ground follows the cursor, so the camera moves opposite to
		# the mouse in world space. (Signs are easily flipped if the feel is inverted.)
		var move := _ground_right * (-mm.relative.x) + _ground_forward * (mm.relative.y)
		global_position += move * wpp
		_clamp_to_board()


## Zoom by [param factor] (<1 zooms in, >1 out) while keeping the ground point under
## [param screen_pos] fixed on screen (cursor-anchored zoom).
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before = _ground_point_at(screen_pos)  # Vector3 or null (untyped)
	size = clampf(size * factor, zoom_min, _zoom_max_runtime)
	var after = _ground_point_at(screen_pos)
	if before != null and after != null:
		var delta: Vector3 = before - after
		global_position += Vector3(delta.x, 0.0, delta.z)
	_clamp_to_board()


# --- Ground-plane helpers ---------------------------------------------------

## World point where the ray through [param screen_pos] meets the y=0 plane, or null.
func _ground_point_at(screen_pos: Vector2):
	var origin := project_ray_origin(screen_pos)
	var normal := project_ray_normal(screen_pos)
	if absf(normal.y) < 0.00001:
		return null
	var t: float = -origin.y / normal.y
	if t < 0.0:
		return null
	return origin + normal * t


## World point where the camera's CENTER ray meets the y=0 plane (the focus point).
func _camera_focus_ground() -> Vector3:
	var o := global_position
	var d := -global_transform.basis.z
	if absf(d.y) < 0.00001:
		return Vector3(o.x, 0.0, o.z)
	var t: float = -o.y / d.y
	return o + d * t


## Translate the camera so its focus lands on [param target] (XZ only; y unchanged).
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

## True when the pointer is over the HUD, consulting the layout manager's helper.
func _is_mouse_over_ui(pos: Vector2) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var ui_layout := scene.get_node_or_null("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		return bool(ui_layout.is_mouse_over_ui(pos))
	return false


## True when a text-entry control has focus, so keyboard pan doesn't eat typing.
func _text_field_has_focus() -> bool:
	var vp := get_viewport()
	if vp == null:
		return false
	var focused := vp.gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit
