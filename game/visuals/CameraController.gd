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

## Auto-focus (see the AUTO_FOCUS section below): the comfortable close distance the
## CINEMATIC mode dollies IN to when currently zoomed far out. Clamped to [dist_min,
## runtime max], so it never punches through the near clamp on tiny boards.
@export var cinematic_close_distance: float = 24.0
## Auto-focus HIT PUNCH: the close distance a hit (damage_dealt) dollies IN to for
## emphasis, in BOTH QUICK and CINEMATIC (never OFF). Clamped to [dist_min, runtime max]
## and never pushed past the resting distance, so it reads as a shove-in, not a lurch.
@export var action_zoom_distance: float = 18.0
## Seconds for the fast push-IN on a hit (the punch). Kept short so it snaps.
@export var action_zoom_in_dur: float = 0.25
## Seconds the camera holds at the close framing before easing back out.
@export var action_zoom_hold_dur: float = 0.12
## Seconds for the ease back OUT to the resting distance, so hits don't creep ever-closer.
@export var action_zoom_out_dur: float = 0.5
## Skip an auto-focus request whose destination is already this near the current focus
## (world units) -- no point gliding a hair, and it stops jitter during AI bursts.
@export var auto_focus_min_move: float = 1.5
## CRIT KICK (see [method impulse_shake]): authored seconds one impulse takes to decay
## back to zero. Short -- it is a jolt, not a rumble.
@export var impulse_shake_time: float = 0.18
## How many oscillations the impulse packs into that decay. More = buzzier.
@export_range(0.5, 8.0, 0.5) var impulse_shake_cycles: float = 2.5
## Minimum seconds between event-driven auto-focuses. Bursty events (a flurry of hits
## as the AI resolves a turn) can't snap the camera rapidly -- only the first within a
## window moves it. Spawns bypass this (they're rare and worth framing every time).
## Kept short so the camera actually KEEPS UP with the AI turn (each enemy attack gets
## a watchable dwell in BotTurnDriver) instead of lagging a beat behind the action.
@export var auto_focus_cooldown: float = 0.25

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

## Cached autoloads for auto-focus (either may be absent in headless/minimal scenes).
var _game_settings: Node = null
var _game_events: Node = null
## The live focus glide, if any -- killed/replaced rather than stacked.
var _focus_tween: Tween = null
## Hit-punch burst state: true while a hit-zoom (in->hold->out) is in flight. Used so a
## flurry of hits captures the RESTING distance only once (the first punch) and returns
## there, instead of each hit stacking its zoom-in atop the previous close framing.
var _action_zoom_active: bool = false
## The distance to ease back OUT to after a hit punch -- captured before the first hit of
## a burst so repeated hits never treat an already-zoomed-in frame as "resting".
var _action_resting_distance: float = 0.0
## Time.get_ticks_msec() of the last event-driven auto-focus, for the cooldown gate.
var _last_auto_focus_ms: int = 0

## --- Impulse shake (crit kick) ----------------------------------------------
## True while a kick is decaying. This is the RE-ENTRANCY GUARD: a second crit in the
## same burst is ignored rather than restarting (or stacking) the jolt, which is what
## keeps a multi-target crit from turning into a seizure.
var _shake_active: bool = false
## The live kick tween, killed on teardown so it can never resume on a freed camera.
var _shake_tween: Tween = null
## The offset THIS kick currently has applied to global_position. The kick is applied as
## a DELTA against this value rather than by capturing-and-restoring an absolute position,
## so a focus glide (or a pan, or the hit punch) running at the same time composes with it
## instead of fighting it -- and zeroing it removes exactly what was added, no more.
var _shake_offset: Vector3 = Vector3.ZERO
## Peak displacement (world units) and the two screen-aligned axes of the current kick,
## resolved once when it starts.
var _shake_amplitude: float = 0.0
var _shake_axis_a: Vector3 = Vector3.RIGHT
var _shake_axis_b: Vector3 = Vector3.UP

## Cached TurnSystemManager autoload (absent in headless/minimal scenes) plus the turn
## system we're currently listening to for turn_started. SEPARATE from the GameEvents
## auto-focus wiring above so the two never clash: that path rides GameEvents' spawn/
## hit/heal signals; THIS path rides the active turn system's per-turn turn_started so
## control returning to the human re-frames a player unit. Distinct member name (mirrors
## SpawnManager/TurnIndicator's _watched_ts) keeps the (re)connect bookkeeping isolated.
var _turn_system_manager: Node = null
var _focus_watched_ts: Node = null
## Last acting side the turn-focus re-framed for: -1 unknown, 0 ally, 1 enemy. In Speed
## mode turn_started fires per-unit, so we only re-frame when the SIDE actually flips
## (ally<->enemy) instead of flying the camera to every consecutive same-side unit.
var _last_focus_side: int = -1

# AutoFocus mode ints, mirroring GameSettings.AutoFocus (kept local so we stay
# null-safe when GameSettings is absent).
const _AUTO_OFF: int = 0
const _AUTO_QUICK: int = 1
const _AUTO_CINEMATIC: int = 2

## The enemy-turn FAST-FORWARD latch (see [TurnFastForward]): while it is armed this camera
## stands its auto-focus down, so a ~1-frame-per-action AI turn does not fly the frame around
## the board. Preloaded by PATH rather than by its global class_name, exactly as
## [GameWorldManager] preloads its juice layers -- a global class only resolves once the
## editor/engine has rescanned, and a fresh checkout would otherwise fail to compile this
## script. Every function on it is static, so this const IS the whole API.
const FAST_FORWARD = preload("res://game/ai/TurnFastForward.gd")


func _ready() -> void:
	_dist_max_runtime = dist_max
	_capture_ground_basis()
	_base_distance = maxf(_current_distance(), 1.0)

	if CombatServices and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)
	if CombatServices and CombatServices.board() != null:
		call_deferred("fit_to_map")

	_setup_auto_focus()
	_setup_turn_focus()


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
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
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
		pan_by_screen_delta(mm.relative)


# --- Public pan / zoom API (shared by mouse and touch) ----------------------
##
## The two entry points below are the ONLY way anything outside this script drives the
## camera by hand. They exist so the touch gesture layer ([TouchInputAdapter]) reuses the
## exact grab-drag and wheel-zoom maths the mouse uses, rather than growing a second
## implementation that would drift. Both are additive: the mouse paths above now call
## through them, so there is one implementation of each.

## Pan by a SCREEN-space delta in pixels (grab-drag semantics: the ground follows the
## pointer). Converts pixels to world units at the current focus depth, so a drag covers
## the same fraction of the view whether zoomed in or out, then re-clamps to the board.
func pan_by_screen_delta(screen_delta: Vector2) -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vp_h: float = vp.get_visible_rect().size.y
	if vp_h <= 0.0:
		return
	# World units per screen pixel at the focus depth (perspective): the visible
	# vertical world span at distance d is 2*d*tan(fov/2).
	var d: float = _current_distance()
	var wpp: float = (2.0 * d * tan(deg_to_rad(fov) * 0.5) / vp_h) * drag_speed
	var move := _ground_right * (-screen_delta.x) + _ground_forward * (screen_delta.y)
	global_position += move * wpp
	_clamp_to_board()


## Dolly by [param factor] (<1 closer, >1 farther) while keeping the ground point under
## [param screen_pos] fixed -- the same anchored zoom the mouse wheel performs, exposed so
## a pinch can drive it. Non-positive factors are ignored rather than inverting the camera.
func zoom_by(factor: float, screen_pos: Vector2) -> void:
	if not is_inside_tree() or not is_finite(factor) or factor <= 0.0:
		return
	_zoom_at(screen_pos, factor)


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
	var tree := get_tree()
	if tree == null:
		return false
	var scene := tree.current_scene
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


# --- Auto-focus on live combat events ---------------------------------------
##
## Glides the camera's ground focus to IMPACTFUL, occasional battle events (runtime
## spawns, hits landed, heals) so the eye follows the action WITHOUT chasing every
## ordinary shuffle -- plain unit_moved is deliberately NOT auto-focused, as constantly
## gliding after each AI step is what made the camera feel dizzying. A cooldown
## (auto_focus_cooldown) further keeps a burst of hits from snapping the camera rapidly.
## Gated by GameSettings.camera_auto_focus:
##   OFF       -- never auto-moves.
##   QUICK     -- a calm pan glide for heals; a HIT still PUNCHES in (fast dolly in, hold,
##                ease back out) so combat reads impactful even in the lighter mode.
##   CINEMATIC -- the same for heals plus the hit punch, and a spawn ALSO dollies IN once
##                toward cinematic_close_distance when currently zoomed far out (the spawn
##                dolly settles closer and stays; the hit punch always returns to resting).
## Everything here only ever translates focus (and, in cinematic, dollies distance
## within [dist_min, runtime max]); it never touches the authored basis or fov.
## Both autoloads are optional: absent GameSettings behaves as OFF, so headless
## tests and minimal scenes are never yanked around.

func _setup_auto_focus() -> void:
	_game_settings = get_node_or_null("/root/GameSettings")
	_game_events = get_node_or_null("/root/GameEvents")

	if _game_settings != null and _game_settings.has_signal("settings_changed"):
		if not _game_settings.settings_changed.is_connected(_on_settings_changed):
			_game_settings.settings_changed.connect(_on_settings_changed)

	if _game_events == null:
		return
	if _game_events.has_signal("unit_spawned") and not _game_events.unit_spawned.is_connected(_on_event_unit_spawned):
		_game_events.unit_spawned.connect(_on_event_unit_spawned)
	if _game_events.has_signal("damage_dealt") and not _game_events.damage_dealt.is_connected(_on_event_damage_dealt):
		_game_events.damage_dealt.connect(_on_event_damage_dealt)
	if _game_events.has_signal("unit_healed") and not _game_events.unit_healed.is_connected(_on_event_unit_healed):
		_game_events.unit_healed.connect(_on_event_unit_healed)


## Current auto-focus mode, or OFF when GameSettings is absent.
func _auto_focus_mode() -> int:
	if _game_settings == null:
		return _AUTO_OFF
	return int(_game_settings.camera_auto_focus)


## Whether an event-driven auto-move is allowed right now: not OFF, not while the player is
## actively driving the camera (mid grab-drag or typing in a text field), and not while the
## enemy turn is being FAST-FORWARDED.
##
## The fast-forward clause is the third leg of the skip button (see [TurnFastForward]): the AI
## still issues every command, so damage_dealt / unit_healed / unit_spawned still fire -- and
## at a ~1-frame beat each, honouring them would fly the camera across the board dozens of
## times a second. Suppressing auto-focus is what turns "the AI does everything, we just don't
## show it" from a promise into a calm screen.
func _should_auto_focus() -> bool:
	if _dragging or _text_field_has_focus():
		return false
	if FAST_FORWARD.is_armed():
		return false
	return _auto_focus_mode() != _AUTO_OFF


## Event handlers funnel through here so the cooldown is enforced in one place. Ignores
## the request if another auto-focus happened within auto_focus_cooldown, UNLESS [param
## bypass_cooldown] is set (spawns are rare enough to always frame). The min-move / drag
## / text-focus guards still apply (via _should_auto_focus and focus_on itself).
func _request_auto_focus(world_pos: Vector3, cinematic: bool, bypass_cooldown: bool,
		hit_zoom: bool = false) -> void:
	if not _should_auto_focus():
		return
	var now: int = Time.get_ticks_msec()
	if not bypass_cooldown:
		var cooldown_ms: int = int(maxf(auto_focus_cooldown, 0.0) * 1000.0)
		if now - _last_auto_focus_ms < cooldown_ms:
			return
	_last_auto_focus_ms = now
	if hit_zoom:
		_focus_hit(world_pos)
	else:
		focus_on(world_pos, cinematic)


func _kill_focus_tween() -> void:
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = null


## Public entry point: glide the ground focus to [param world_pos] as a calm, eased pan.
## When [param cinematic] is true it uses the slower duration and dollies IN toward a
## comfortable close distance if currently zoomed far out (event handlers only pass this
## for spawns, so the zoom never churns per-hit). Other systems may call this directly;
## the signal handlers call it only after their mode/cooldown checks. Killed/replaced
## rather than stacked, and short no-op hops are ignored.
func focus_on(world_pos: Vector3, cinematic: bool = false) -> void:
	if not is_inside_tree():
		return

	# A plain pan / spawn glide takes over from any hit-punch burst: end it so the next
	# hit re-captures a fresh resting distance instead of returning to a stale one.
	_action_zoom_active = false

	var start: Vector3 = _camera_focus_ground()
	var dest: Vector3 = Vector3(world_pos.x, 0.0, world_pos.z)
	var moved: float = Vector2(dest.x - start.x, dest.z - start.z).length()

	# CINEMATIC pulls in toward a close framing only when currently further out.
	var cur_dist: float = _current_distance()
	var want_dist: float = cur_dist
	if cinematic:
		want_dist = clampf(minf(cur_dist, cinematic_close_distance), dist_min, _dist_max_runtime)
	var dist_delta: float = absf(want_dist - cur_dist)

	# Nothing worth doing (already framed here at the right distance).
	if moved < auto_focus_min_move and dist_delta < 0.5:
		return

	_kill_focus_tween()

	# Animations off => snap instantly (mirrors how the rest of the FX layer treats a
	# zero authored duration).
	var animate: bool = true
	if _game_settings != null and not _game_settings.animations_on():
		animate = false

	if not animate:
		_move_focus_to(dest)
		if cinematic and dist_delta >= 0.5:
			_set_distance(want_dist)
		_clamp_to_board()
		return

	var base_dur: float = 0.5 if cinematic else 0.3
	var dur: float = base_dur
	if _game_settings != null:
		# Let battle-speed also speed the camera, but keep a sane floor/ceiling.
		dur = _game_settings.scaled_time(base_dur)
	# Minimum-duration floor so a fast battle speed can never turn the pan into a
	# jump-cut, but snappy enough to arrive while the enemy's attack is still playing.
	dur = clampf(dur, 0.2, 1.5)

	_focus_tween = create_tween()
	_focus_tween.set_parallel(true)
	# _move_focus_to lands the focus on the given target, so tweening the target from
	# start -> dest produces a smooth glide (XZ only, distance preserved per step).
	# TRANS_CUBIC + EASE_IN_OUT eases both ends, so the pan accelerates and settles
	# gently instead of snapping -- the calm feel the auto-focus is meant to have.
	_focus_tween.tween_method(Callable(self, "_move_focus_to"), start, dest, dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if cinematic and dist_delta >= 0.5:
		_focus_tween.tween_method(Callable(self, "_set_distance"), cur_dist, want_dist, dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# After the glide settles, snap the focus back inside the board bounds.
	_focus_tween.chain().tween_callback(_clamp_to_board)


## HIT PUNCH: pan to the impact point AND shove the camera IN fast for emphasis, hold a
## beat, then ease back OUT to the resting distance. Runs in BOTH QUICK and CINEMATIC (the
## caller gates OFF via _should_auto_focus). Unlike focus_on's spawn dolly, this always
## zooms -- the whole point is a visible punch -- but returns so a turn of hits can't creep
## ever-closer. Killed/replaced rather than stacked; a burst captures the resting distance
## only once so repeated hits don't treat the already-close frame as their return target.
func _focus_hit(world_pos: Vector3) -> void:
	if not is_inside_tree():
		return

	var start: Vector3 = _camera_focus_ground()
	var dest: Vector3 = Vector3(world_pos.x, 0.0, world_pos.z)
	var moved: float = Vector2(dest.x - start.x, dest.z - start.z).length()

	var cur_dist: float = _current_distance()
	# Capture the resting distance ONCE per burst -- the very first hit, before any punch
	# has pulled us in. Subsequent hits mid-burst keep returning to that same frame.
	if not _action_zoom_active:
		_action_resting_distance = cur_dist
	var resting: float = _action_resting_distance
	# Never push past the resting frame: if already closer than action_zoom_distance, hold.
	var close: float = clampf(minf(resting, action_zoom_distance), dist_min, _dist_max_runtime)
	var zoom_delta: float = absf(close - cur_dist)

	# Already framed here at the close distance (e.g. a second hit on the same tile while
	# still punched in) -- nothing worth churning.
	if moved < auto_focus_min_move and zoom_delta < 0.5:
		return

	_kill_focus_tween()

	# Animations off => snap the pan and settle at the resting distance (mirrors the FX
	# layer treating a zero authored duration as an instant cut); no punch to animate.
	var animate: bool = true
	if _game_settings != null and not _game_settings.animations_on():
		animate = false

	if not animate:
		if moved >= auto_focus_min_move:
			_move_focus_to(dest)
		_set_distance(resting)
		_clamp_to_board()
		_action_zoom_active = false
		return

	# Let battle-speed nudge the timings, but floor them so a fast speed can't turn the
	# punch into a single-frame jump-cut.
	var in_dur: float = action_zoom_in_dur
	var hold_dur: float = maxf(action_zoom_hold_dur, 0.0)
	var out_dur: float = action_zoom_out_dur
	if _game_settings != null:
		in_dur = _game_settings.scaled_time(action_zoom_in_dur)
		out_dur = _game_settings.scaled_time(action_zoom_out_dur)
	in_dur = clampf(in_dur, 0.15, 1.0)
	out_dur = clampf(out_dur, 0.3, 1.5)

	_action_zoom_active = true

	_focus_tween = create_tween()
	# In-phase: the pan and the shove-in run together, fast, easing OUT so they snap in
	# and settle (the punch). TRANS_CUBIC + EASE_OUT front-loads the motion.
	_focus_tween.set_parallel(true)
	if moved >= auto_focus_min_move:
		_focus_tween.tween_method(Callable(self, "_move_focus_to"), start, dest, in_dur) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_focus_tween.tween_method(Callable(self, "_set_distance"), cur_dist, close, in_dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Then hold, then ease back OUT to resting -- sequential from here so it always settles.
	_focus_tween.chain()
	_focus_tween.set_parallel(false)
	if hold_dur > 0.0:
		_focus_tween.tween_interval(hold_dur)
	_focus_tween.tween_method(Callable(self, "_set_distance"), close, resting, out_dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_focus_tween.tween_callback(_on_hit_zoom_done)


## End of a hit-punch burst: settle inside the board bounds and clear the burst flag so the
## next hit re-captures a fresh resting distance. Killed tweens (a rapid follow-up hit or a
## spawn/settings change taking over) simply never reach here, which is what we want.
func _on_hit_zoom_done() -> void:
	_action_zoom_active = false
	_clamp_to_board()


func _on_settings_changed() -> void:
	# If the player just switched auto-focus off, drop any glide in flight.
	if _auto_focus_mode() == _AUTO_OFF:
		_kill_focus_tween()
		_action_zoom_active = false
	# Animations switched off mid-kick: end it now and put back exactly what it moved,
	# rather than leaving the camera parked on a half-decayed offset.
	if _shake_active and _game_settings != null and _game_settings.has_method("animations_on") \
			and not _game_settings.animations_on():
		_end_impulse_shake()


## Frame only RUNTIME spawns (reinforcements / endless waves); skip the initial flood
## of pre-placed units at load. Spawns are rare and worth showing every time, so they
## BYPASS the cooldown, and in CINEMATIC mode they are the ONE event that dollies in.
func _on_event_unit_spawned(unit, runtime: bool) -> void:
	if not runtime:
		return
	if not is_instance_valid(unit) or not (unit is Node3D):
		return
	_request_auto_focus((unit as Node3D).global_position,
		_auto_focus_mode() == _AUTO_CINEMATIC, true)


## Frame the point of IMPACT -- the DEFENDER -- on a hit. We hook damage_dealt (per
## target) rather than move_performed (which fires for every move, including non-
## damaging ones and the attacker itself) so a damaging attack focuses exactly once, on
## where it lands. Attacks are framed regardless of owner: a hit on a player unit is
## just as worth showing as a hit the AI lands. This fires a HIT PUNCH (pan + fast dolly
## IN, hold, then ease back OUT) in QUICK and CINEMATIC alike, cooldown-gated so a flurry
## of hits can't rapid-fire the camera. See _focus_hit.
func _on_event_damage_dealt(_attacker, defender, _damage) -> void:
	if not is_instance_valid(defender) or not (defender is Node3D):
		return
	_request_auto_focus((defender as Node3D).global_position, false, false, true)


## Frame a heal on the unit that received it -- an occasional, meaningful beat. Same as
## a hit: pan-only and cooldown-gated. Connected null-safely (the signal is guarded in
## _setup_auto_focus), so absent that signal this is simply never called.
func _on_event_unit_healed(unit, _amount) -> void:
	if not is_instance_valid(unit) or not (unit is Node3D):
		return
	_request_auto_focus((unit as Node3D).global_position, false, false)


# --- Impulse shake (crit kick) ----------------------------------------------
##
## A tiny, fast-decaying positional jolt of the camera, fired by [DamageNumbers] when a
## CRIT lands. Deliberately NOT a basis or fov change: this controller's whole contract is
## that it only translates and dollies (see the class doc), and a rotating shake would
## break the authored camera angle the whole board art is composed for.
##
## Three properties make it safe to fire from a signal handler in the middle of combat:
##  * RE-ENTRANCY GUARDED. A second call while a kick is decaying is a no-op, so a crit
##    that hits four targets shakes ONCE.
##  * ADDITIVE. The jolt is applied as a DELTA against its own accumulated offset rather
##    than by capturing-and-restoring an absolute position, so the hit punch or a focus
##    glide moving global_position at the same time composes with it instead of fighting
##    it -- and zeroing the offset removes exactly what the kick added, no more.
##  * ANIMATIONS-TOGGLE AWARE. With animations off there is no kick at all -- and since
##    nothing was applied, there is nothing to restore.

## Kick the camera by [param strength] world units of peak displacement. Tiny values are
## the intended range (~0.15-0.25); anything larger reads as a bug, so it is clamped.
func impulse_shake(strength: float = 0.2) -> void:
	if _shake_active:
		return
	# create_tween() errors on a detached node, and this is called from a signal handler.
	if not is_inside_tree():
		return
	if _game_settings != null and _game_settings.has_method("animations_on") \
			and not _game_settings.animations_on():
		return

	var amplitude: float = clampf(strength, 0.0, 0.5)
	if amplitude <= 0.0:
		return

	var duration: float = impulse_shake_time
	if _game_settings != null and _game_settings.has_method("scaled_time"):
		duration = float(_game_settings.scaled_time(impulse_shake_time))
	# Floored so a fast battle speed cannot compress the kick into a single-frame pop,
	# and capped so a slow one cannot leave the camera wobbling through the next action.
	duration = clampf(duration, 0.08, 0.4)

	# Shake across the SCREEN plane (camera-local right / up), so the jolt reads the same
	# whichever way the board is being viewed from.
	var cam_basis := global_transform.basis
	_shake_axis_a = cam_basis.x.normalized()
	_shake_axis_b = cam_basis.y.normalized()
	_shake_amplitude = amplitude
	_shake_active = true

	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	# k decays 1 -> 0; _impulse_step turns that into a decaying oscillation.
	_shake_tween.tween_method(Callable(self, "_impulse_step"), 1.0, 0.0, duration) \
		.set_trans(Tween.TRANS_LINEAR)
	_shake_tween.tween_callback(_end_impulse_shake)


## One step of the kick. [param k] runs 1 -> 0 across the decay, so the oscillation both
## cycles and shrinks; the two axes run at different frequencies so it never degenerates
## into a straight-line slide.
func _impulse_step(k: float) -> void:
	var phase: float = (1.0 - k) * TAU * impulse_shake_cycles
	var magnitude: float = _shake_amplitude * k
	_apply_shake_offset(
		_shake_axis_a * (sin(phase) * magnitude)
		+ _shake_axis_b * (cos(phase * 1.7) * magnitude * 0.5))


## Move the camera so the kick's contribution is exactly [param offset]. Delta-based --
## see [member _shake_offset] for why capturing an absolute position would be wrong.
func _apply_shake_offset(offset: Vector3) -> void:
	global_position += offset - _shake_offset
	_shake_offset = offset


## End of the kick (or an early abort): remove the displacement it added and re-arm.
func _end_impulse_shake() -> void:
	if is_inside_tree():
		_apply_shake_offset(Vector3.ZERO)
	_shake_offset = Vector3.ZERO
	_shake_active = false


# --- Turn-start focus (re-frame the player's side when control returns) ------
##
## During the ENEMY phase the camera chases the AI's actions (via the GameEvents
## hit/spawn/heal auto-focus above) and is left wherever the AI finished. When control
## returns to the HUMAN, nothing re-framed the player's side. This ADDITIVE path rides
## the ACTIVE TURN SYSTEM's turn_started -- the reliable per-turn signal that fires for
## AI advances too (PlayerManager's own signals don't), which is why every per-turn
## system in this project (TurnIndicator, SpawnManager) listens here rather than to
## PlayerManager. On a human turn start it glides the focus back to a relevant player
## unit; the AI's turns are ignored (their own actions already drive the camera).
##
## Deliberately reuses the existing auto-focus machinery: it honours _should_auto_focus()
## (OFF mode / mid-drag / typing) and glides via focus_on() (a gentle cinematic pull-in
## when the mode is CINEMATIC), so it inherits the same feel and gating as every other
## auto-focus, and never touches the authored basis or fov.

## Wire to the active turn system's turn_started, (re)connecting when it activates or
## switches. Mirrors SpawnManager.setup / TurnIndicator._ready exactly, but with its OWN
## member (_focus_watched_ts) so it never disturbs the GameEvents auto-focus connections.
func _setup_turn_focus() -> void:
	_turn_system_manager = get_node_or_null("/root/TurnSystemManager")
	if _turn_system_manager == null:
		return
	if _turn_system_manager.has_signal("turn_system_activated") \
			and not _turn_system_manager.turn_system_activated.is_connected(_on_turn_system_activated_focus):
		_turn_system_manager.turn_system_activated.connect(_on_turn_system_activated_focus)
	if _turn_system_manager.has_method("has_active_turn_system") \
			and _turn_system_manager.has_active_turn_system():
		_on_turn_system_activated_focus(_turn_system_manager.get_active_turn_system())


## (Re)wire to the active turn system's turn_started when it activates or switches.
func _on_turn_system_activated_focus(ts) -> void:
	if _focus_watched_ts == ts:
		return
	if _focus_watched_ts != null and is_instance_valid(_focus_watched_ts) \
			and _focus_watched_ts.has_signal("turn_started") \
			and _focus_watched_ts.turn_started.is_connected(_on_turn_focus_started):
		_focus_watched_ts.turn_started.disconnect(_on_turn_focus_started)
	_focus_watched_ts = ts
	# Forget the last-framed side under the old system so a fresh game re-frames turn 1.
	_last_focus_side = -1
	if ts != null and ts.has_signal("turn_started") \
			and not ts.turn_started.is_connected(_on_turn_focus_started):
		ts.turn_started.connect(_on_turn_focus_started)


## A turn began. Re-frame ONLY when it's a human player's turn (the AI's own actions
## already drive the camera) and auto-focus isn't suppressed. Glides to a relevant player
## unit -- the current acting unit (Speed First) or a sensible player unit (Traditional).
func _on_turn_focus_started(player) -> void:
	if player == null:
		return
	# AUTO-DISARM the enemy-turn fast-forward the instant a human player is up. This rides the
	# ACTIVE turn system's turn_started (see _setup_turn_focus), which is the only signal that
	# fires on AI turns too -- and it has to happen BEFORE _should_auto_focus below, or the
	# still-armed latch would swallow the human turn's re-frame. Idempotent and shared with the
	# HUD button, so whichever of the two the turn system connected first does the work.
	FAST_FORWARD.note_turn_started(player)
	# Re-frame only when the controlling SIDE flips (ally<->enemy), never for every
	# consecutive same-side unit. In Speed mode turn_started fires per-unit, so a run of
	# 8 ally units would otherwise fly the camera 8 times ("player1 to player1" waste) --
	# the user wants the turn re-frame only on a real side change (player1 <-> player2).
	# Track the side across ALL turns (incl. AI) so the flip is detected correctly.
	var side: int = 1 if ("is_ai" in player and bool(player.is_ai)) else 0
	var side_changed: bool = side != _last_focus_side
	_last_focus_side = side
	# Human turns only: skip AI advances (we don't re-frame for them) -- but the side was
	# recorded above so the following ally turn is correctly seen as a flip.
	if side == 1:
		return
	# Same ally side as the previous turn: no flip, so don't re-fly the camera.
	if not side_changed:
		return
	# Same gating as the event auto-focus: OFF mode / mid grab-drag / typing.
	if not _should_auto_focus():
		return

	var ts = _focus_watched_ts
	if ts == null or not is_instance_valid(ts):
		if _turn_system_manager != null and _turn_system_manager.has_method("has_active_turn_system") \
				and _turn_system_manager.has_active_turn_system():
			ts = _turn_system_manager.get_active_turn_system()
	if ts == null or not is_instance_valid(ts):
		return

	var unit = _resolve_turn_focus_unit(ts, player)
	if unit == null or not is_instance_valid(unit) or not (unit is Node3D):
		return

	# Gentle glide back to the player's side; CINEMATIC also dollies in toward a close
	# framing. Bypass the cooldown -- a turn start is a rare, deliberate re-frame.
	var cinematic: bool = _auto_focus_mode() == _AUTO_CINEMATIC
	_request_auto_focus((unit as Node3D).global_position, cinematic, true)


## Resolve which of [param player]'s units to focus for the turn that just started.
## Speed First exposes the unit whose turn it is via get_current_acting_unit(); prefer
## that (it IS the next unit to move). Otherwise (Traditional / player-based) pick a
## sensible one: the first of the player's units that can still act, else the first
## living one. Duck-typed and null-safe throughout; returns null when nothing fits.
func _resolve_turn_focus_unit(ts, player):
	# Speed First: the current acting unit is exactly the next unit that will move.
	if ts.has_method("get_current_acting_unit"):
		var acting = ts.get_current_acting_unit()
		if acting != null and is_instance_valid(acting):
			return acting

	# Traditional / player-based: scan this player's registered units.
	var units: Array = []
	if ts.has_method("get_units_for_player"):
		var owned = ts.get_units_for_player(player)
		if owned is Array:
			units = owned

	var first_living = null
	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		# Skip the dead: we want a LIVING unit as the fallback focus.
		if u.has_method("is_alive") and not bool(u.is_alive()):
			continue
		if first_living == null:
			first_living = u
		# Prefer the first unit that can still act this turn.
		if u.has_method("can_act") and bool(u.can_act()):
			return u
	return first_living


func _exit_tree() -> void:
	# Drop any in-flight crit kick. The tween dies with the node, but clearing the state
	# explicitly means a re-added camera never believes a stale kick is still decaying.
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = null
	_shake_offset = Vector3.ZERO
	_shake_active = false
	# Explicitly drop the turn-system subscriptions (freeing auto-disconnects, but being
	# explicit keeps a reused instance from double-subscribing). The GameEvents auto-focus
	# connections are on autoloads and tear down with the node the same way.
	if _turn_system_manager != null and is_instance_valid(_turn_system_manager) \
			and _turn_system_manager.has_signal("turn_system_activated") \
			and _turn_system_manager.turn_system_activated.is_connected(_on_turn_system_activated_focus):
		_turn_system_manager.turn_system_activated.disconnect(_on_turn_system_activated_focus)
	if _focus_watched_ts != null and is_instance_valid(_focus_watched_ts) \
			and _focus_watched_ts.has_signal("turn_started") \
			and _focus_watched_ts.turn_started.is_connected(_on_turn_focus_started):
		_focus_watched_ts.turn_started.disconnect(_on_turn_focus_started)
