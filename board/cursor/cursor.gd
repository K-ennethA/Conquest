extends Node3D

# Enhanced cursor with unit selection and visual feedback
# Handles input, selection, and UI integration

@export var grid: Resource = preload("res://board/Grid.tres")
@export var move_speed: float = 10.0

# --- Fire-Emblem style corner-bracket tile selector geometry ---
# The tile is 2x2 world units (see Grid.tres cell_size), so half a tile = 1.0.
# Brackets sit inset from the tile edge; the dark outline is drawn slightly
# larger/thicker than the gold bracket so it reads as a crisp edge on any
# terrain (light sand/stone as well as dark lava/water).
const CORNER_GOLD := 0.86        # gold bracket corner distance from tile center
const CORNER_OUTLINE := 0.90     # outline corner sits further out, framing the gold
const ARM_LENGTH_GOLD := 0.5
const ARM_LENGTH_OUTLINE := 0.54
const ARM_WIDTH_GOLD := 0.11
const ARM_WIDTH_OUTLINE := 0.17

const COLOR_GOLD_IDLE := Color(1.0, 0.78, 0.25, 0.95)
const EMISSION_GOLD_IDLE := Color(1.0, 0.65, 0.15)
const COLOR_GOLD_SELECTED := Color(1.0, 0.92, 0.55, 1.0)
const EMISSION_GOLD_SELECTED := Color(1.2, 0.85, 0.25)

const COLOR_OUTLINE_IDLE := Color(0.12, 0.07, 0.02, 0.9)
const EMISSION_OUTLINE_IDLE := Color(0.08, 0.04, 0.0)
const COLOR_OUTLINE_SELECTED := Color(0.35, 0.18, 0.05, 0.95)
const EMISSION_OUTLINE_SELECTED := Color(0.3, 0.15, 0.02)

# Idle "breathing" animation applied to the gold brackets only, so the dark
# outline stays put as a stable frame around the tile.
const PULSE_SPEED := 2.2
const PULSE_AMPLITUDE := 0.06

var tile_position := Vector3.ZERO:
	set(value):
		var new_position = grid.grid_clamp(value)
		if new_position.is_equal_approx(tile_position):
			return
		
		var old_position = tile_position
		tile_position = new_position
		position = grid.calculate_map_position(tile_position)
		# (Multi-floor: tile_position.y is the FLOOR; the bracket sits on that floor.)
		# Sit the bracket just above the tile top so it reads as ON the tile. Under a
		# tilted orthographic view any vertical offset shifts the cursor's SCREEN
		# position off the ground cell (~offset*sin(tilt)); a large lift (the old 3.0)
		# floated it well above the tile under the mouse. The bracket material uses
		# no_depth_test, so this small lift only prevents z-fighting with the tile top
		# and never causes occlusion.
		position.y = Cells.floor_y(int(tile_position.y)) + 0.15
		
		# Emit movement event
		GameEvents.cursor_moved.emit(tile_position)
		
		# Check for unit at new position
		_check_unit_at_cursor()
		# Multi-floor: the auto cutaway depends on where the cursor stands.
		_update_view_state()

var selected_unit: Unit = null
var hovered_unit: Unit = null

# --- Multi-floor view state (see FloorNav / docs/MULTI_FLOOR.md) -------------------
## The VIEW FLOOR: the highest floor the player is looking at. Keyboard steps land
## on the top-most tile at or below it, mouse picking ignores floors above it, and
## FloorCutaway fades every floor above the CUT floor. Defaults to the top floor
## (everything visible) whenever a board loads.
var view_floor: int = 0
## Floor actually cut to: view_floor, lowered to the cursor's / selected unit's floor
## while either stands UNDER a deck (auto cutaway).
var cut_floor: int = 0
var _floor_count: int = 1
var _last_emitted_view: int = -1
## Last unit each player selected (player_id -> Unit), for turn-start cursor memory.
var _last_selected_by_player: Dictionary = {}

# Visual components
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var base_mesh: MeshInstance3D = $BaseMesh
var base_material: StandardMaterial3D
var selection_material: StandardMaterial3D
var base_ring_material: StandardMaterial3D
var selection_ring_material: StandardMaterial3D

# Idle pulse animation state (cheap _process oscillation, no per-frame allocations)
var _pulse_time: float = 0.0
var _bracket_base_scale: Vector3 = Vector3.ONE

# Mouse support
var camera: Camera3D
var is_mouse_enabled: bool = true

func _ready() -> void:
	_setup_cursor_visuals()
	position = grid.calculate_map_position(tile_position)
	position.y = Cells.floor_y(int(tile_position.y)) + 0.15  # Sit on the tile (see the tile_position setter for why)
	GameEvents.cursor_moved.emit(tile_position)
	_check_unit_at_cursor()
	
	# Find camera for mouse support
	camera = get_viewport().get_camera_3d()
	
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	
	# Connect to turn system events for cursor positioning
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)

	# (Re)read the floor structure whenever a board is (re)built.
	if CombatServices and not CombatServices.board_ready.is_connected(_on_board_ready):
		CombatServices.board_ready.connect(_on_board_ready)
	if CombatServices and CombatServices.board() != null:
		_on_board_ready()

func _setup_cursor_visuals() -> void:
	"""Build the Fire-Emblem style corner-bracket tile selector: four warm
	gold corner brackets (mesh_instance) framed by a darker bracket outline
	(base_mesh) so the selector reads clearly against any terrain. Everything
	is mesh/material-generated here in _ready; _process only tweaks scale."""
	if mesh_instance:
		mesh_instance.mesh = _build_corner_bracket_mesh(CORNER_GOLD, ARM_LENGTH_GOLD, ARM_WIDTH_GOLD)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		# Idle gold brackets
		base_material = _make_bracket_material(COLOR_GOLD_IDLE, EMISSION_GOLD_IDLE)
		base_material.render_priority = 1

		# Selected gold brackets (hotter, brighter gold - stays in the warm palette)
		selection_material = _make_bracket_material(COLOR_GOLD_SELECTED, EMISSION_GOLD_SELECTED)
		selection_material.render_priority = 1

		mesh_instance.material_override = base_material
		_bracket_base_scale = mesh_instance.scale

	if base_mesh:
		# Outline brackets are slightly larger/thicker than the gold ones so a
		# thin dark edge frames the gold on every side - this is what keeps the
		# cursor legible on light terrain (sand/stone) as well as dark (lava/water).
		base_mesh.mesh = _build_corner_bracket_mesh(CORNER_OUTLINE, ARM_LENGTH_OUTLINE, ARM_WIDTH_OUTLINE)
		base_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		base_ring_material = _make_bracket_material(COLOR_OUTLINE_IDLE, EMISSION_OUTLINE_IDLE)
		base_ring_material.render_priority = 0

		selection_ring_material = _make_bracket_material(COLOR_OUTLINE_SELECTED, EMISSION_OUTLINE_SELECTED)
		selection_ring_material.render_priority = 0

		base_mesh.material_override = base_ring_material


func _make_bracket_material(albedo: Color, emission: Color) -> StandardMaterial3D:
	"""Shared material recipe for the cursor brackets: unshaded, always-on-top,
	double-sided flat decal with a warm emissive glow and a soft rim."""
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.flags_transparent = true
	mat.flags_unshaded = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = emission
	mat.no_depth_test = true  # Always visible above terrain and units
	mat.rim_enabled = true
	mat.rim = 0.35
	mat.rim_tint = 0.6
	return mat


func _build_corner_bracket_mesh(corner: float, arm_length: float, arm_width: float) -> ArrayMesh:
	"""Procedurally build four L-shaped corner brackets (flat quads on the XZ
	plane) framing a 2x2-unit tile, classic Fire-Emblem cursor style. `corner`
	is each bracket's distance from the tile center (tile half-size is 1.0)."""
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var signs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for s in signs:
		var sx: float = s.x
		var sz: float = s.y
		var ex := sx * corner
		var ez := sz * corner

		# Arm running along the X edge (thin in Z)
		_add_flat_quad(st, ex, ex - sx * arm_length, ez, ez - sz * arm_width)
		# Arm running along the Z edge (thin in X)
		_add_flat_quad(st, ex, ex - sx * arm_width, ez, ez - sz * arm_length)

	return st.commit()


func _add_flat_quad(st: SurfaceTool, x0: float, x1: float, z0: float, z1: float) -> void:
	"""Add a two-triangle quad lying flat on the XZ plane (Y = 0, local space)."""
	var p00 := Vector3(x0, 0.0, z0)
	var p10 := Vector3(x1, 0.0, z0)
	var p11 := Vector3(x1, 0.0, z1)
	var p01 := Vector3(x0, 0.0, z1)

	st.set_normal(Vector3.UP)
	st.add_vertex(p00)
	st.set_normal(Vector3.UP)
	st.add_vertex(p10)
	st.set_normal(Vector3.UP)
	st.add_vertex(p11)

	st.set_normal(Vector3.UP)
	st.add_vertex(p00)
	st.set_normal(Vector3.UP)
	st.add_vertex(p11)
	st.set_normal(Vector3.UP)
	st.add_vertex(p01)


func _process(delta: float) -> void:
	"""Cheap idle "breathing" animation: the gold brackets gently pulse in
	scale while the dark outline stays fixed as a stable frame on the tile."""
	if not mesh_instance:
		return
	_pulse_time += delta
	var pulse := 1.0 + sin(_pulse_time * PULSE_SPEED) * PULSE_AMPLITUDE
	mesh_instance.scale = _bracket_base_scale * pulse
	_update_joy_repeat(delta)

# --- Gamepad held-direction repeat -----------------------------------------------
# Keyboard repeat comes from OS echo events; a gamepad d-pad/stick has none, so a
# held gamepad direction is re-stepped here: first repeat after JOY_REPEAT_DELAY,
# then every JOY_REPEAT_INTERVAL while the action stays pressed.
const JOY_REPEAT_DELAY := 0.3
const JOY_REPEAT_INTERVAL := 0.08
var _joy_held_action: StringName = &""
var _joy_repeat_timer: float = 0.0

func _update_joy_repeat(delta: float) -> void:
	if _joy_held_action == &"":
		return
	if not Input.is_action_pressed(_joy_held_action) or InputActions.gameplay_input_blocked(get_tree()):
		_joy_held_action = &""
		return
	_joy_repeat_timer -= delta
	if _joy_repeat_timer <= 0.0:
		_joy_repeat_timer = JOY_REPEAT_INTERVAL
		_step_cursor(InputActions.CURSOR_STEPS[_joy_held_action])

func _step_cursor(step: Vector3) -> void:
	var new_position = tile_position + step
	if not grid.is_within_bounds(new_position):
		return
	# Multi-floor: land on the top-most tile at or below the view floor (walks over
	# bridges at the default view, drops off a bridge end onto the ground).
	var board = _board()
	if board != null and _floor_count > 1:
		var cell := FloorNav.step(board, Cells.from_grid(tile_position),
			Vector2i(int(step.x), int(step.z)), view_floor)
		if cell == Cells.INVALID:
			return
		new_position = Cells.to_grid(cell)
	self.tile_position = new_position
	_camera_follow()


# --- Multi-floor: view floor, floor cycling, cutaway state ------------------------

func _board():
	return CombatServices.board() if CombatServices else null


func _on_board_ready() -> void:
	var board = _board()
	_floor_count = 1
	if board != null and board.has_method("floor_count"):
		_floor_count = maxi(1, int(board.floor_count()))
	view_floor = _floor_count - 1
	cut_floor = view_floor
	# Re-seat the cursor on a real tile of the new board.
	if board != null:
		var cell := Cells.from_grid(tile_position)
		var f := FloorNav.snap_floor(board, cell, view_floor)
		if f >= 0 and f != cell.z:
			self.tile_position = Cells.to_grid(Vector3i(cell.x, cell.y, f))
	_update_view_state(true)


## Number of floors on the current board (1 on a classic flat map).
func get_floor_count() -> int:
	return _floor_count


## Set the view floor (clamped to the board's floors).
func set_view_floor(f: int) -> void:
	view_floor = clampi(f, 0, _floor_count - 1)
	_update_view_state()


## floor_up (+1) / floor_down (-1): cycle the floors of the cursor's column, moving
## the view floor along (see FloorNav.cycle_floor).
func cycle_floor(dir: int) -> void:
	var board = _board()
	if board == null or _floor_count <= 1:
		return
	var r := FloorNav.cycle_floor(board, Cells.from_grid(tile_position), view_floor, dir)
	view_floor = int(r["view"])
	var cell: Vector3i = r["cell"]
	if Cells.to_grid(cell) != tile_position:
		self.tile_position = Cells.to_grid(cell)  # the setter refreshes the view state
	else:
		_update_view_state()
	_camera_follow()


## Recompute the cut floor and broadcast the view state when it changed.
func _update_view_state(force: bool = false) -> void:
	var board = _board()
	var cut := view_floor
	if board != null and _floor_count > 1:
		var here := Cells.from_grid(tile_position)
		if FloorNav.is_covered(board, here):
			cut = mini(cut, here.z)
		if selected_unit != null and is_instance_valid(selected_unit):
			var ucell := _unit_cell(selected_unit)
			if FloorNav.is_covered(board, ucell):
				cut = mini(cut, ucell.z)
	if not force and cut == cut_floor and _last_emitted_view == view_floor:
		return
	cut_floor = cut
	_last_emitted_view = view_floor
	if GameEvents and GameEvents.has_signal("view_floor_changed"):
		GameEvents.view_floor_changed.emit(view_floor, cut_floor, _floor_count)


## The board cell a unit stands on (Vector3i(col, row, floor)).
func _unit_cell(unit: Node3D) -> Vector3i:
	return Cells.from_grid(grid.calculate_grid_coordinates(unit.global_position))


## Move the cursor onto [param cell], adjusting the view floor so the cell is
## visible: a covered cell (under a bridge) cuts the view down to it, a cell above
## the view floor raises it. Used by unit cycling and turn-start positioning.
## [param follow] = false (an AI turn) leaves both the camera and the view alone.
func focus_cell(cell: Vector3i, follow: bool = true) -> void:
	var board = _board()
	if follow and board != null and _floor_count > 1:
		if cell.z > view_floor or FloorNav.is_covered(board, cell):
			view_floor = cell.z
	var g := Cells.to_grid(cell)
	if not g.is_equal_approx(tile_position):
		self.tile_position = g
	else:
		_update_view_state()
	if follow:
		_camera_follow()


## Ask the camera to keep the cursor on screen (edge-margin follow). Only used for
## keyboard / gamepad / cycling moves -- never for mouse hover, which would chase
## the mouse off the edge of the screen.
func _camera_follow() -> void:
	if not camera and get_viewport():
		camera = get_viewport().get_camera_3d()
	if camera and camera.has_method("follow_world_point"):
		camera.follow_world_point(grid.calculate_map_position(tile_position))


# --- Unit cycling (FE L/R) -------------------------------------------------------

## The current HUMAN player's units that can still act, in stable reading order
## (row, column, floor). Empty on an AI turn.
func get_ready_units() -> Array:
	var out: Array = []
	if not PlayerManager:
		return out
	var player = PlayerManager.get_current_player()
	if player == null or bool(player.is_ai):
		return out
	var candidates: Array = []
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		var ts = TurnSystemManager.get_active_turn_system()
		if ts is SpeedFirstTurnSystem:
			var acting = (ts as SpeedFirstTurnSystem).get_current_acting_unit()
			if acting != null:
				candidates.append(acting)
		elif ts.has_method("get_units_that_can_act"):
			candidates = ts.get_units_that_can_act()
	else:
		candidates = player.get_units_that_can_act()
	for u in candidates:
		if u == null or not is_instance_valid(u) or not (u is Node3D):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		out.append(u)
	out.sort_custom(func(a, b): return FloorNav.cell_order_less(_unit_cell(a), _unit_cell(b)))
	return out


## Jump the cursor (and camera) to the next (+1) / previous (-1) ready unit. With a
## unit selected (but no move staged) the selection follows; while a move is being
## aimed or a tentative move is staged, cycling is ignored.
func cycle_ready_unit(dir: int) -> Unit:
	var panel := _get_unit_actions_panel()
	if panel:
		if panel.has_method("is_targeting_move") and panel.is_targeting_move():
			return null
		if "_tentative_active" in panel and bool(panel.get("_tentative_active")):
			return null
	var units := get_ready_units()
	if units.is_empty():
		return null
	var cells: Array = []
	for u in units:
		cells.append(_unit_cell(u))
	var here := Cells.from_grid(tile_position)
	if selected_unit != null and is_instance_valid(selected_unit) and units.has(selected_unit):
		here = _unit_cell(selected_unit)
	var idx := FloorNav.cycle_index(cells, here, dir)
	if idx < 0:
		return null
	var target: Unit = units[idx]
	focus_cell(cells[idx])
	if selected_unit != null and selected_unit != target:
		_select_unit(target)
	return target

func _unhandled_input(event: InputEvent) -> void:
	# A full-screen overlay (Settings, ...) owns input while it is open.
	if InputActions.gameplay_input_blocked(get_tree()):
		return

	# Dev helper: Ctrl+Shift+F5 (debug builds only) fires a synthetic unit_selected.
	if InputActions.is_debug_hotkey(event, KEY_F5):
		_test_unit_selection_signal()
		return

	# Named actions (keyboard + gamepad, rebindable -- see InputActions).
	if event.is_action_pressed(InputActions.FLOOR_UP):
		cycle_floor(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.FLOOR_DOWN):
		cycle_floor(-1)
		get_viewport().set_input_as_handled()
		return
	# Exact matching so Shift+Tab (cycle_prev) is not also read as Tab (cycle_next).
	if event.is_action_pressed(InputActions.CYCLE_PREV, false, true):
		cycle_ready_unit(-1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.CYCLE_NEXT, false, true):
		cycle_ready_unit(1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.CONFIRM):
		_handle_selection()
		return
	if event.is_action_pressed(InputActions.CANCEL):
		_handle_deselection()
		return

	# Cursor movement. Keys step on press AND on OS key-repeat (echo), so holding a
	# direction glides the cursor. Gamepad d-pad / stick send no echo, so a held
	# gamepad direction repeats via _process (see _update_joy_repeat).
	for action in InputActions.CURSOR_STEPS:
		if not event.is_action(action):
			continue
		var is_joy := event is InputEventJoypadButton or event is InputEventJoypadMotion
		if is_joy:
			if event.is_action_pressed(action) and _joy_held_action != action:
				_joy_held_action = action
				_joy_repeat_timer = JOY_REPEAT_DELAY
				_step_cursor(InputActions.CURSOR_STEPS[action])
			elif not event.is_action_pressed(action) and _joy_held_action == action \
					and not Input.is_action_pressed(action):
				_joy_held_action = &""
			return
		if event.is_action_pressed(action, true):
			_step_cursor(InputActions.CURSOR_STEPS[action])
			return

	# Handle mouse input (only if not handled by UI)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Check if mouse is over UI elements using UILayoutManager
			var ui_layout = null
			var tree = get_tree()
			if tree != null and tree.current_scene != null:
				ui_layout = tree.current_scene.get_node_or_null("UI/GameUILayout")
			if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
				if ui_layout.is_mouse_over_ui(event.position):
					return
			else:
				# Fallback: Check if mouse is over UI elements using screen position
				var screen_size = get_viewport().get_visible_rect().size
				var mouse_pos = event.position

				# More lenient UI detection - only block if in right sidebar area
				if mouse_pos.x > screen_size.x * 0.8:  # Changed from 0.75 to 0.8
					return

			_handle_mouse_click(event.position)
		return
	
	# Handle mouse movement for cursor positioning (only if mouse enabled)
	if event is InputEventMouseMotion and is_mouse_enabled:
		var ui_layout = null
		var tree = get_tree()
		if tree != null and tree.current_scene != null:
			ui_layout = tree.current_scene.get_node_or_null("UI/GameUILayout")
		if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
			if ui_layout.is_mouse_over_ui(event.position):
				return  # Don't move cursor when over UI
		else:
			# Fallback detection
			var screen_size = get_viewport().get_visible_rect().size
			var mouse_pos = event.position
			
			# Only move cursor with mouse if not over UI area
			if mouse_pos.x > screen_size.x * 0.8:  # Changed from 0.75 to 0.8
				return
		
		_handle_mouse_movement(event.position)
		return

func _input(event: InputEvent) -> void:
	"""Handle high-priority input - currently unused to let UI have priority"""
	# Debug: Print all input events to see what we're receiving
	if event is InputEventMouseButton:
		# RIGHT CLICK = CANCEL (Fire-Emblem style back-out). While a unit interaction
		# is staged (aiming a move, a tentative move, movement mode, or just a
		# selection), route the click to UnitActionsPanel.request_cancel() so it backs
		# out one level (drop targeting -> revert tentative move -> deselect). When
		# nothing is staged this is a harmless no-op.
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var panel := _get_unit_actions_panel()
			if panel and panel.has_method("request_cancel"):
				panel.request_cancel()
				get_viewport().set_input_as_handled()
			return
			

	# Don't handle mouse events here - let UI have priority
	# Mouse events will be handled in _unhandled_input() if UI doesn't consume them

func _cell_under_mouse(mouse_pos: Vector2):
	"""GROUND-PLANE mouse pick, shared by the hover and click paths. Casts the camera
	ray through `mouse_pos` and intersects it with the board plane (y = 0):

	    origin = camera.project_ray_origin(mouse_pos)
	    dir    = camera.project_ray_normal(mouse_pos)
	    t      = -origin.y / dir.y      (solve origin.y + dir.y * t = 0)
	    point  = origin + dir * t

	then converts the world hit `point` to a cell via grid.calculate_grid_coordinates.
	Returns the Vector3(col, 0, row) grid coordinate, or null when the ray is parallel
	to the plane (no dir.y) or the plane is behind the camera. This replaces the old
	PhysicsRayQueryParameters3D raycast, which depended on tile colliders/layers and
	could silently "miss" the board -- the plane math always resolves a cell."""
	# Re-fetch the camera lazily: get_camera_3d() can be null at _ready if the
	# Camera3D has not registered as current yet, which would otherwise kill picking.
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		return null

	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = camera.project_ray_normal(mouse_pos)

	# Ray parallel to the ground plane -> no intersection.
	if absf(dir.y) < 0.00001:
		return null

	var t: float = -origin.y / dir.y
	# Intersection behind the camera (looking away from the board).
	if t < 0.0:
		return null

	var point: Vector3 = origin + dir * t
	# MULTI-FLOOR: pick the TOP-MOST existing tile under the ray. March the floors
	# from the top down, intersecting each floor's walking plane; the first floor
	# that has a tile at the hit column wins. Floor 0 (the plane above) is the
	# fallback, so single-floor maps behave exactly as before.
	var board = CombatServices.board() if CombatServices else null
	if board != null and board.has_method("floor_count") and board.floor_count() > 1:
		# Only floors at or below the VIEW floor: floors above it are cut away, so a
		# cell under a bridge is pickable while viewing the ground.
		for f in range(mini(board.floor_count() - 1, view_floor), 0, -1):
			var plane_y: float = Cells.floor_y(f) + 0.1
			var tf: float = (plane_y - origin.y) / dir.y
			if tf < 0.0:
				continue
			var p: Vector3 = origin + dir * tf
			var col := Vector3i(int(floor(p.x / grid.cell_size.x)), int(floor(p.z / grid.cell_size.z)), f)
			if board.has_tile(col):
				return Cells.to_grid(col)
	var ground: Vector3 = grid.calculate_grid_coordinates(point)
	ground.y = 0.0
	return ground


func _handle_mouse_click(mouse_pos: Vector2) -> void:
	"""Handle mouse click for unit selection"""
	# The camera is cached in _ready, but get_camera_3d() can be null there if the
	# Camera3D has not yet registered as current. Re-fetch lazily so mouse picking
	# is never permanently dead when that race loses.
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		return

	# Check if click is over UI using the layout manager
	var ui_layout = null
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		ui_layout = tree.current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		if ui_layout.is_mouse_over_ui(mouse_pos):
			return

	# GROUND-PLANE picking (replaces the old physics raycast). Intersect the camera
	# ray with the board plane (y = 0) so a click can never "miss" the board because
	# of tile colliders/layers -- the plane is infinite and always solvable.
	var grid_pos = _cell_under_mouse(mouse_pos)
	if grid_pos == null:
		return

	# Move cursor to clicked position (same tile_position setter + bounds check the
	# hover path uses, so selection targets exactly the hovered/clicked cell).
	if grid.is_within_bounds(grid_pos):
		self.tile_position = grid_pos
		_handle_selection()

func _handle_mouse_movement(mouse_pos: Vector2) -> void:
	"""Handle mouse movement for cursor positioning"""
	# Re-fetch lazily (see _handle_mouse_click): a null camera cached at _ready would
	# otherwise silently kill mouse-hover cursor tracking -- and with it the
	# GameEvents.cursor_moved emissions that drive TerrainInfoPanel.
	if not camera:
		camera = get_viewport().get_camera_3d()
	if not camera:
		return
	
	# Check if mouse is over UI using the layout manager (get_node_or_null so a
	# missing HUD never throws and silently kills mouse-hover cursor tracking).
	var ui_layout = null
	var tree = get_tree()
	if tree != null and tree.current_scene != null:
		ui_layout = tree.current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		if ui_layout.is_mouse_over_ui(mouse_pos):
			return  # Don't move cursor when over UI
	
	# GROUND-PLANE picking (replaces the old physics raycast). Intersecting the
	# camera ray with the board plane (y = 0) cannot miss the board, so hovering
	# ANY board cell now moves the cursor there and fires GameEvents.cursor_moved
	# (via the tile_position setter) -- which is exactly what drives TerrainInfoPanel.
	var grid_pos = _cell_under_mouse(mouse_pos)
	if grid_pos == null:
		return

	# Move cursor to mouse position (but don't auto-select)
	if grid.is_within_bounds(grid_pos):
		self.tile_position = grid_pos

func _handle_selection() -> void:
	"""Handle unit selection at cursor position"""
	# FIRST: If a move/attack is being targeted, this click selects the target.
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel and unit_actions_panel.has_method("is_targeting_move"):
		if unit_actions_panel.is_targeting_move():
			unit_actions_panel.handle_move_target_selected(tile_position)
			return

	# SECOND: If movement range is showing, this click is a movement destination --
	# UNLESS the clicked cell holds a DIFFERENT unit, in which case switch selection
	# to that unit instead of trying to move onto it.
	if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			var unit_under_click: Unit = _get_unit_at_position(tile_position)
			if unit_under_click and unit_under_click != selected_unit:
				# Clicking another unit switches selection (reverting any staged
				# tentative move via _deselect_unit inside _select_unit).
				_select_unit(unit_under_click)
				return
			unit_actions_panel.handle_movement_destination_selected(tile_position)
			return  # Exit early - don't do normal unit selection

	# SECOND: Handle normal unit selection/deselection
	var unit_at_cursor = _get_unit_at_position(tile_position)
	
	if unit_at_cursor:
		# Selection == inspection: ANY living unit may be selected (including enemies /
		# AI-owned units) so the player can read their info. Commanding a unit is gated
		# separately in UnitActionsPanel (_human_may_command), so relaxing selection here
		# is safe. We no longer reject via PlayerManager.can_current_player_select_unit
		# or the turn system's can_unit_act.
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()

			# Speed First inspection branch (log-only): any unit is selectable; the UI
			# handles action availability for the current acting unit.
			if turn_system is SpeedFirstTurnSystem:
				var speed_system = turn_system as SpeedFirstTurnSystem
				var current_acting_unit = speed_system.get_current_acting_unit()


		if selected_unit == unit_at_cursor:
			# Deselect if clicking same unit
			_deselect_unit()
		else:
			# Select new unit
			_select_unit(unit_at_cursor)
	else:
		# No unit at cursor - only deselect if we're not in movement mode
		if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
			if not unit_actions_panel.is_showing_movement_range():
				_deselect_unit()
		else:
			_deselect_unit()

func _get_unit_actions_panel() -> Node:
	"""Get reference to UnitActionsPanel"""
	var tree = get_tree()
	if tree == null:
		return null
	var scene_root = tree.current_scene
	if scene_root == null:
		return null

	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")

	if ui_layout:
		# The correct path is MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel
		var unit_actions_panel = ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
		return unit_actions_panel
	return null

func _handle_deselection() -> void:
	"""Handle unit deselection"""
	_deselect_unit()

func _select_unit(unit: Unit) -> void:
	"""Select a unit and update visuals"""
	if selected_unit:
		_deselect_unit()
	
	selected_unit = unit
	# Remember it for this player's next turn start (cursor memory).
	if "owner_player" in unit and unit.owner_player != null:
		_last_selected_by_player[int(unit.owner_player.player_id)] = unit
	var world_pos = grid.calculate_map_position(tile_position)
	GameEvents.unit_selected.emit(unit, world_pos)
	_update_view_state()

	# Update cursor visuals
	if mesh_instance:
		mesh_instance.material_override = selection_material
	if base_mesh:
		base_mesh.material_override = selection_ring_material

func _deselect_unit() -> void:
	"""Deselect current unit"""
	if selected_unit:
		var unit = selected_unit
		selected_unit = null
		GameEvents.unit_deselected.emit(unit)
		_update_view_state()
	
	# Update cursor visuals
	if mesh_instance:
		mesh_instance.material_override = base_material
	if base_mesh:
		base_mesh.material_override = base_ring_material

func _check_unit_at_cursor() -> void:
	"""Check for unit at cursor position and update hover state"""
	var unit_at_cursor = _get_unit_at_position(tile_position)
	
	if hovered_unit != unit_at_cursor:
		if hovered_unit:
			GameEvents.unit_hover_ended.emit(hovered_unit)
		
		hovered_unit = unit_at_cursor
		
		if hovered_unit:
			GameEvents.unit_hover_started.emit(hovered_unit)

func _get_unit_at_position(grid_pos: Vector3) -> Unit:
	"""Find unit at specific grid position"""
	# Search for units in the scene
	var units = _find_all_units()
	
	for unit in units:
		var unit_world_pos = unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
		
		# Check if positions match (with some tolerance)
		# (y = floor: a unit on a bridge is not "at" the road cell beneath it)
		if abs(unit_grid_pos.x - grid_pos.x) < 0.1 and abs(unit_grid_pos.z - grid_pos.z) < 0.1 \
				and abs(unit_grid_pos.y - grid_pos.y) < 0.1:
			return unit
	
	return null

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var tree = get_tree()
	if tree == null:
		return units
	var scene_root = tree.current_scene
	if scene_root == null:
		return units

	# Units live under Map/Player<N> containers (any number of players, incl. the
	# neutral / spawned ones), plus anything registered in the "units" group.
	var map_node = scene_root.get_node_or_null("Map")
	if map_node:
		for player_node in map_node.get_children():
			if not String(player_node.name).begins_with("Player"):
				continue
			for child in player_node.get_children():
				if child is Unit and not units.has(child):
					units.append(child)
	for node in tree.get_nodes_in_group("units"):
		if node is Unit and not units.has(node):
			units.append(node)
	
	return units

# Event handlers
func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection event"""
	# Visual feedback is handled in _select_unit
	pass

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection event"""
	# Visual feedback is handled in _deselect_unit
	pass

# Public interface
func get_selected_unit() -> Unit:
	"""Get currently selected unit"""
	return selected_unit

func get_hovered_unit() -> Unit:
	"""Get currently hovered unit"""
	return hovered_unit

func get_cursor_position() -> Vector3:
	"""Get current cursor grid position"""
	return tile_position

func set_mouse_enabled(enabled: bool) -> void:
	"""Enable or disable mouse cursor movement"""
	is_mouse_enabled = enabled

func toggle_mouse_mode() -> void:
	"""Toggle between mouse and keyboard-only mode"""
	set_mouse_enabled(not is_mouse_enabled)

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	if turn_system is SpeedFirstTurnSystem:
		var speed_system = turn_system as SpeedFirstTurnSystem
		
		# Connect to turn events for cursor positioning
		if speed_system.turn_started.is_connected(_on_speed_first_turn_started):
			speed_system.turn_started.disconnect(_on_speed_first_turn_started)
		speed_system.turn_started.connect(_on_speed_first_turn_started)
		
		# Position cursor on current acting unit
		_position_cursor_on_current_unit(speed_system)
	elif turn_system is TraditionalTurnSystem:
		var trad_system = turn_system as TraditionalTurnSystem
		
		# Connect to turn events for cursor positioning
		if trad_system.turn_started.is_connected(_on_traditional_turn_started):
			trad_system.turn_started.disconnect(_on_traditional_turn_started)
		trad_system.turn_started.connect(_on_traditional_turn_started)
		
		# Position cursor on a unit owned by current player
		_position_cursor_on_player_unit(trad_system)

func _on_speed_first_turn_started(unit_or_player) -> void:
	"""Handle turn start in Speed First system"""
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is SpeedFirstTurnSystem:
			_position_cursor_on_current_unit(turn_system as SpeedFirstTurnSystem)

func _on_traditional_turn_started(player: Player) -> void:
	"""Handle turn start in Traditional system"""
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is TraditionalTurnSystem:
			_position_cursor_on_player_unit(turn_system as TraditionalTurnSystem)

func _position_cursor_on_current_unit(speed_system: SpeedFirstTurnSystem) -> void:
	"""Position cursor on the current acting unit (no auto-selection)"""
	var current_unit = speed_system.get_current_acting_unit()
	if current_unit:
		# Move cursor to the unit's cell (and floor). The camera follows only for a
		# human-controlled unit -- the AI's own actions drive the camera.
		var owner = current_unit.owner_player if "owner_player" in current_unit else null
		var human: bool = owner == null or not bool(owner.is_ai)
		focus_cell(_unit_cell(current_unit), human)

		# Note: We don't auto-select the unit - player must manually select it

func _position_cursor_on_player_unit(trad_system: TraditionalTurnSystem) -> void:
	"""Position cursor on a unit owned by the current player that can still act"""
	if not PlayerManager:
		return
	
	var current_player = PlayerManager.get_current_player()
	if not current_player:
		return
	
	# Get units that can still act this turn
	var available_units = current_player.get_units_that_can_act()
	
	var target_unit: Unit = null
	# Cursor memory: the unit this player last selected, if it can still act.
	var remembered = _last_selected_by_player.get(int(current_player.player_id), null)
	if remembered != null and is_instance_valid(remembered) and available_units.has(remembered):
		target_unit = remembered
	elif available_units.size() > 0:
		# Otherwise the first unit that can still act, in stable reading order.
		var sorted: Array = available_units.filter(func(u): return u != null and is_instance_valid(u))
		sorted.sort_custom(func(a, b): return FloorNav.cell_order_less(_unit_cell(a), _unit_cell(b)))
		if not sorted.is_empty():
			target_unit = sorted[0]
	elif current_player.owned_units.size() > 0:
		# If no units can act, just pick the first unit for cursor positioning
		target_unit = current_player.owned_units[0]

	if target_unit and is_instance_valid(target_unit):
		focus_cell(_unit_cell(target_unit), not bool(current_player.is_ai))

func _test_unit_selection_signal() -> void:
	"""Test GameEvents.unit_selected signal emission"""
	# Find a unit to test with
	var units = _find_all_units()
	if units.size() > 0:
		var test_unit = units[0]
		var test_position = test_unit.global_position
		GameEvents.unit_selected.emit(test_unit, test_position)
