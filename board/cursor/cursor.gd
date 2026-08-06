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
		# Sit the bracket just above the tile top so it reads as ON the tile. Under a
		# tilted orthographic view any vertical offset shifts the cursor's SCREEN
		# position off the ground cell (~offset*sin(tilt)); a large lift (the old 3.0)
		# floated it well above the tile under the mouse. The bracket material uses
		# no_depth_test, so this small lift only prevents z-fighting with the tile top
		# and never causes occlusion.
		position.y = 0.15
		
		# Emit movement event
		GameEvents.cursor_moved.emit(tile_position)
		
		# Check for unit at new position
		_check_unit_at_cursor()

var selected_unit: Unit = null
var hovered_unit: Unit = null

# Visual components
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var base_mesh: MeshInstance3D = $BaseMesh
var base_material: StandardMaterial3D
var selection_material: StandardMaterial3D
var base_ring_material: StandardMaterial3D
var selection_ring_material: StandardMaterial3D
## Lazily built the first time flash_invalid() runs (invalid-click feedback).
var _invalid_flash_material: StandardMaterial3D

# Idle pulse animation state (cheap _process oscillation, no per-frame allocations)
var _pulse_time: float = 0.0
var _bracket_base_scale: Vector3 = Vector3.ONE

# Mouse support
var camera: Camera3D
var is_mouse_enabled: bool = true

func _ready() -> void:
	# Group so the UnitActionsPanel (and anything else) can find the cursor regardless of
	# its scene path (Map/Cursor vs World/Board/Cursor).
	add_to_group("board_cursor")

	_setup_cursor_visuals()
	position = grid.calculate_map_position(tile_position)
	position.y = 0.15  # Sit on the tile (see the tile_position setter for why)
	GameEvents.cursor_moved.emit(tile_position)
	_check_unit_at_cursor()
	
	# Find camera for mouse support. get_viewport() is null when this runs outside a live
	# window (headless harnesses, mid-teardown), and calling get_camera_3d() on null is an
	# engine error -- the mouse paths below already treat a null camera as "no mouse".
	var vp := get_viewport()
	camera = vp.get_camera_3d() if vp != null else null
	
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	
	# Connect to turn system events for cursor positioning
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)

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

func _unhandled_input(event: InputEvent) -> void:
	# Handle keyboard input first (always works)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			_test_unit_selection_signal()
			return
		elif event.is_action_pressed("ui_accept"):
			_handle_selection()
			return
		elif event.is_action_pressed("ui_cancel"):
			_handle_deselection()
			return
		
		# Handle movement input
		var input_vector = Vector3.ZERO
		
		if event.is_action_pressed("ui_right"):
			input_vector.x += 1
		elif event.is_action_pressed("ui_left"):
			input_vector.x -= 1
		elif event.is_action_pressed("ui_down"):
			input_vector.z += 1
		elif event.is_action_pressed("ui_up"):
			input_vector.z -= 1
		
		if input_vector != Vector3.ZERO:
			var new_position = tile_position + input_vector
			if grid.is_within_bounds(new_position):
				self.tile_position = new_position
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
	return grid.calculate_grid_coordinates(point)


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
	var world_pos = grid.calculate_map_position(tile_position)
	GameEvents.unit_selected.emit(unit, world_pos)

	# Update cursor visuals
	if mesh_instance:
		mesh_instance.material_override = selection_material
	if base_mesh:
		base_mesh.material_override = selection_ring_material

func _deselect_unit() -> void:
	"""Deselect current unit"""
	# is_instance_valid, not truthiness: when the selected unit DIES nothing clears this
	# reference, so a later click would broadcast unit_deselected with a freed instance to
	# every HUD listener. Dropping it silently is the correct deselect for a dead unit.
	if not is_instance_valid(selected_unit):
		selected_unit = null
	elif selected_unit:
		var unit = selected_unit
		selected_unit = null
		GameEvents.unit_deselected.emit(unit)

	# Update cursor visuals
	if mesh_instance:
		mesh_instance.material_override = base_material
	if base_mesh:
		base_mesh.material_override = base_ring_material

# --- Public helpers for the UnitActionsPanel command loop --------------------

func select_unit_external(unit: Unit) -> void:
	"""Select [param unit] as if the player had clicked it: move the cursor onto its tile
	and route through the normal _select_unit path (so GameEvents.unit_selected fires and
	the cursor's own selection state stays in sync). Used by unit cycling (Tab) and the
	Speed First auto-select-next-actor chain. No-op if it is already selected."""
	if unit == null:
		return
	var unit_grid_pos: Vector3 = grid.calculate_grid_coordinates(unit.global_position)
	if grid.is_within_bounds(unit_grid_pos):
		self.tile_position = unit_grid_pos
	if selected_unit == unit:
		return
	_select_unit(unit)

func deselect_current() -> void:
	"""Public deselect: clears BOTH the cursor's selection state and the panel's (via the
	emitted unit_deselected), so a Wait / resolved action fully ends the selection."""
	_deselect_unit()

func flash_invalid() -> void:
	"""Brief red flash of the cursor bracket -- feedback for an invalid click (unreachable
	tile / illegal target). Restores the correct idle/selected material afterwards."""
	if mesh_instance == null:
		return
	if _invalid_flash_material == null:
		_invalid_flash_material = _make_bracket_material(
			Color(1.0, 0.25, 0.2, 1.0), Color(1.4, 0.2, 0.15))
		_invalid_flash_material.render_priority = 2
	mesh_instance.material_override = _invalid_flash_material
	# Restore after a short beat. create_timer is frame-safe and needs no node.
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(0.18).timeout
	# The cursor can be freed during that beat (scene change on game over / Main Menu),
	# which would resume this coroutine on a dead instance.
	if not is_instance_valid(self) or not is_inside_tree():
		return
	_restore_bracket_material()

func _restore_bracket_material() -> void:
	"""Put the gold bracket material back to whichever state the cursor is in now."""
	if mesh_instance == null:
		return
	# is_instance_valid, not `!= null`: selected_unit is never cleared when the selected
	# unit DIES, so it routinely holds a freed reference here.
	if is_instance_valid(selected_unit):
		mesh_instance.material_override = selection_material
	else:
		mesh_instance.material_override = base_material

func _check_unit_at_cursor() -> void:
	"""Check for unit at cursor position and update hover state"""
	var unit_at_cursor = _get_unit_at_position(tile_position)

	# hovered_unit is not cleared when the hovered unit dies, so it can be a freed
	# reference by the time the cursor next moves. Drop it BEFORE the comparison so we
	# never emit unit_hover_ended with a dead unit -- that would hand a freed instance to
	# every listening HUD panel at once.
	if not is_instance_valid(hovered_unit):
		hovered_unit = null

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
		# FOG: a unit this screen cannot see is not standing here as far as the cursor is
		# concerned. Selection IS inspection in this game (see _handle_selection), so
		# answering with a fogged unit would let a click read its whole card -- and clicking
		# its tile would silently refuse to be a move destination for no visible reason.
		# Returning null instead makes the cell behave exactly like empty ground.
		if FogOfWarOverlay.unit_hidden(unit):
			continue
		var unit_world_pos = unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)

		# Check if positions match (with some tolerance)
		if abs(unit_grid_pos.x - grid_pos.x) < 0.1 and abs(unit_grid_pos.z - grid_pos.z) < 0.1:
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

	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
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
			# auto_select = true: when the next actor is a human-commandable unit, SELECT
			# it (not just position on it) so play chains without a re-click. AI units are
			# only positioned-to.
			_position_cursor_on_current_unit(turn_system as SpeedFirstTurnSystem, true)

func _on_traditional_turn_started(player: Player) -> void:
	"""Handle turn start in Traditional system"""
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is TraditionalTurnSystem:
			_position_cursor_on_player_unit(turn_system as TraditionalTurnSystem)

func _position_cursor_on_current_unit(speed_system: SpeedFirstTurnSystem, auto_select: bool = false) -> void:
	"""Position cursor on the current acting unit. When [param auto_select] is true AND
	the actor is a human-commandable unit, also SELECT it so the player commands the next
	unit without a re-click (the Speed First chain). AI actors are never auto-selected."""
	var current_unit = speed_system.get_current_acting_unit()
	if current_unit:
		# Move cursor to unit's position
		var unit_world_pos = current_unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)

		# Set cursor position (this will trigger position update)
		self.tile_position = unit_grid_pos

		# Auto-select ONLY a human-commandable next actor; an AI unit is positioned-to
		# but left unselected so the player is not handed the enemy's controls.
		if auto_select and _unit_is_human_owned(current_unit):
			if selected_unit != current_unit:
				_select_unit(current_unit)

func _unit_is_human_owned(unit: Unit) -> bool:
	"""True when `unit` belongs to a human (non-AI) player -- the gate for auto-selecting
	the next Speed First actor. Multiplayer ownership nuances are handled downstream by
	the panel's own _human_may_command gate, so 'not AI' is sufficient here."""
	if unit == null:
		return false
	var player := unit.get_owner_player()
	if player == null:
		return false
	return not player.is_ai

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
	if available_units.size() > 0:
		# Pick the first unit that can still act
		target_unit = available_units[0]
	elif current_player.owned_units.size() > 0:
		# If no units can act, just pick the first unit for cursor positioning
		target_unit = current_player.owned_units[0]
	
	if target_unit:
		var unit_world_pos = target_unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)

		# Set cursor position
		self.tile_position = unit_grid_pos

func _test_unit_selection_signal() -> void:
	"""Test GameEvents.unit_selected signal emission"""
	# Find a unit to test with
	var units = _find_all_units()
	if units.size() > 0:
		var test_unit = units[0]
		var test_position = test_unit.global_position
		GameEvents.unit_selected.emit(test_unit, test_position)
