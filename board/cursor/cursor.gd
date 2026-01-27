extends Node3D

# Enhanced cursor with unit selection and visual feedback
# Handles input, selection, and UI integration

@export var grid: Resource = preload("res://board/Grid.tres")
@export var move_speed: float = 10.0

var tile_position := Vector3.ZERO:
	set(value):
		var new_position = grid.grid_clamp(value)
		if new_position.is_equal_approx(tile_position):
			return
		
		var old_position = tile_position
		tile_position = new_position
		position = grid.calculate_map_position(tile_position)
		position.y = 3.0  # Keep cursor above units and tiles
		
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

# Mouse support
var camera: Camera3D
var is_mouse_enabled: bool = true

func _ready() -> void:
	_setup_cursor_visuals()
	position = grid.calculate_map_position(tile_position)
	position.y = 3.0  # Keep cursor above everything
	GameEvents.cursor_moved.emit(tile_position)
	_check_unit_at_cursor()
	
	# Find camera for mouse support
	camera = get_viewport().get_camera_3d()
	
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	
	# Connect to turn system events for auto-positioning
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)

func _setup_cursor_visuals() -> void:
	"""Setup cursor visual materials"""
	if mesh_instance:
		# Create base cursor material (bright yellow diamond with rim lighting)
		base_material = StandardMaterial3D.new()
		base_material.albedo_color = Color(1.0, 1.0, 0.2, 0.8)
		base_material.flags_transparent = true
		base_material.flags_unshaded = true
		base_material.emission_enabled = true
		base_material.emission = Color(1.0, 1.0, 0.3)
		base_material.no_depth_test = true  # Always visible
		base_material.rim_enabled = true
		base_material.rim = 0.5
		base_material.rim_tint = 0.8
		
		# Create selection material (bright green diamond with rim lighting)
		selection_material = StandardMaterial3D.new()
		selection_material.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
		selection_material.flags_transparent = true
		selection_material.flags_unshaded = true
		selection_material.emission_enabled = true
		selection_material.emission = Color(0.3, 1.0, 0.3)
		selection_material.no_depth_test = true  # Always visible
		selection_material.rim_enabled = true
		selection_material.rim = 0.6
		selection_material.rim_tint = 0.9
		
		mesh_instance.material_override = base_material
	
	if base_mesh:
		# Create base ring material (subtle yellow with rim)
		base_ring_material = StandardMaterial3D.new()
		base_ring_material.albedo_color = Color(1.0, 1.0, 0.2, 0.2)
		base_ring_material.flags_transparent = true
		base_ring_material.flags_unshaded = true
		base_ring_material.emission_enabled = true
		base_ring_material.emission = Color(1.0, 1.0, 0.3, 0.3)
		base_ring_material.no_depth_test = true
		base_ring_material.rim_enabled = true
		base_ring_material.rim = 0.3
		base_ring_material.rim_tint = 0.5
		
		# Create selection ring material (subtle green with rim)
		selection_ring_material = StandardMaterial3D.new()
		selection_ring_material.albedo_color = Color(0.2, 1.0, 0.2, 0.3)
		selection_ring_material.flags_transparent = true
		selection_ring_material.flags_unshaded = true
		selection_ring_material.emission_enabled = true
		selection_ring_material.emission = Color(0.3, 1.0, 0.3, 0.4)
		selection_ring_material.no_depth_test = true
		selection_ring_material.rim_enabled = true
		selection_ring_material.rim = 0.4
		selection_ring_material.rim_tint = 0.7
		
		base_mesh.material_override = base_ring_material

func _unhandled_input(event: InputEvent) -> void:
	# Handle keyboard input first (always works)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			print("F5 pressed - testing GameEvents.unit_selected signal")
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

func _input(event: InputEvent) -> void:
	"""Handle mouse input with higher priority"""
	# Debug: Print all input events to see what we're receiving
	if event is InputEventMouseButton:
		print("=== Mouse Button Event Received ===")
		print("Button: " + str(event.button_index))
		print("Pressed: " + str(event.pressed))
		print("Position: " + str(event.position))
	elif event is InputEventMouseMotion:
		# Only print occasionally to avoid spam
		if randf() < 0.01:  # Print ~1% of mouse motion events
			print("Mouse motion: " + str(event.position))
	
	# Handle mouse input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			print("=== Left Mouse Click Detected ===")
			print("Mouse position: " + str(event.position))
			
			# Check if mouse is over UI elements first
			var screen_size = get_viewport().get_visible_rect().size
			var mouse_pos = event.position
			print("Screen size: " + str(screen_size))
			print("UI threshold (80%): " + str(screen_size.x * 0.8))
			
			# More lenient UI detection - only block if in right sidebar area
			if mouse_pos.x > screen_size.x * 0.8:  # Changed from 0.75 to 0.8
				print("Mouse click in UI area - not handling in cursor")
				return
			
			print("Mouse click in game area - handling cursor selection")
			_handle_mouse_click(event.position)
			get_viewport().set_input_as_handled()  # Consume the event
		return
	
	# Handle mouse movement for cursor positioning (only if mouse enabled)
	if event is InputEventMouseMotion and is_mouse_enabled:
		var screen_size = get_viewport().get_visible_rect().size
		var mouse_pos = event.position
		
		# Only move cursor with mouse if not over UI area
		if mouse_pos.x <= screen_size.x * 0.8:  # Changed from 0.75 to 0.8
			_handle_mouse_movement(event.position)
		return

func _handle_mouse_click(mouse_pos: Vector2) -> void:
	"""Handle mouse click for unit selection"""
	print("=== _handle_mouse_click called ===")
	print("Mouse position: " + str(mouse_pos))
	
	if not camera:
		print("ERROR: No camera found!")
		return
	
	print("Camera found: " + camera.name)
	
	# Check if click is over UI using the layout manager
	var ui_layout = get_tree().current_scene.get_node_or_null("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		if ui_layout.is_mouse_over_ui(mouse_pos):
			print("Mouse click in UI area - not handling in cursor")
			return
	
	print("Mouse click in game area - proceeding with raycast")
	
	# Cast ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	print("Ray from: " + str(from))
	print("Ray to: " + str(to))
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		print("Ray hit something!")
		print("Hit position: " + str(result.position))
		print("Hit collider: " + str(result.collider))
		
		# Convert world position to grid position
		var world_pos = result.position
		var grid_pos = grid.calculate_grid_coordinates(world_pos)
		print("Ray hit at world pos: " + str(world_pos))
		print("Converted to grid pos: " + str(grid_pos))
		
		# Move cursor to clicked position
		if grid.is_within_bounds(grid_pos):
			print("Grid position is within bounds - moving cursor")
			self.tile_position = grid_pos
			_handle_selection()
		else:
			print("Grid position out of bounds: " + str(grid_pos))
	else:
		print("Ray cast did not hit anything - no collision detected")
		print("This might mean:")
		print("1. No collision bodies in the scene")
		print("2. Ray is not hitting the ground/tiles")
		print("3. Collision layers are not set up correctly")

func _handle_mouse_movement(mouse_pos: Vector2) -> void:
	"""Handle mouse movement for cursor positioning"""
	if not camera:
		return
	
	# Check if mouse is over UI using the layout manager
	var ui_layout = get_tree().current_scene.get_node("UI/GameUILayout")
	if ui_layout and ui_layout.has_method("is_mouse_over_ui"):
		if ui_layout.is_mouse_over_ui(mouse_pos):
			return  # Don't move cursor when over UI
	
	# Cast ray from camera through mouse position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	var result = space_state.intersect_ray(query)
	
	if result:
		# Convert world position to grid position
		var world_pos = result.position
		var grid_pos = grid.calculate_grid_coordinates(world_pos)
		
		# Move cursor to mouse position (but don't auto-select)
		if grid.is_within_bounds(grid_pos):
			self.tile_position = grid_pos

func _handle_selection() -> void:
	"""Handle unit selection at cursor position"""
	var unit_at_cursor = _get_unit_at_position(tile_position)
	
	if unit_at_cursor:
		print("Unit found for selection: ", unit_at_cursor.name)
		
		# First check PlayerManager validation
		if not PlayerManager.can_current_player_select_unit(unit_at_cursor):
			print("Cannot select unit: not owned by current player or game not active")
			return
		
		# Then check turn system validation
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			print("Cursor: Active turn system is " + turn_system.system_name)
			
			# Special handling for Speed First turn system
			if turn_system is SpeedFirstTurnSystem:
				var speed_system = turn_system as SpeedFirstTurnSystem
				var current_acting_unit = speed_system.get_current_acting_unit()
				
				print("Cursor: Speed First mode - current acting unit: " + (current_acting_unit.get_display_name() if current_acting_unit else "None"))
				print("Cursor: Attempted selection: " + unit_at_cursor.get_display_name())
				
				# In Speed First mode, only allow selection of the currently acting unit
				if unit_at_cursor != current_acting_unit:
					print("Cursor: BLOCKED - Cannot select unit: not the currently acting unit in Speed First mode")
					return
				else:
					print("Cursor: ALLOWED - Unit is the currently acting unit")
			
			if not turn_system.can_unit_act(unit_at_cursor):
				if turn_system is TraditionalTurnSystem:
					var trad_system = turn_system as TraditionalTurnSystem
					if unit_at_cursor in trad_system.get_units_that_acted():
						print("Cannot select unit: already acted this turn")
					else:
						print("Cannot select unit: turn system constraint")
				else:
					print("Cannot select unit: not allowed by turn system")
				return
		
		if selected_unit == unit_at_cursor:
			# Deselect if clicking same unit
			_deselect_unit()
		else:
			# Select new unit
			_select_unit(unit_at_cursor)
	else:
		# No unit at cursor, deselect current
		_deselect_unit()

func _handle_deselection() -> void:
	"""Handle unit deselection"""
	_deselect_unit()

func _select_unit(unit: Unit) -> void:
	"""Select a unit and update visuals"""
	if selected_unit:
		_deselect_unit()
	
	selected_unit = unit
	var world_pos = grid.calculate_map_position(tile_position)
	print("=== Cursor: Selecting unit ===")
	print("Unit: ", unit.name)
	print("World position: ", world_pos)
	print("Emitting GameEvents.unit_selected signal...")
	GameEvents.unit_selected.emit(unit, world_pos)
	print("GameEvents.unit_selected signal emitted")
	
	# Update cursor visuals
	if mesh_instance:
		mesh_instance.material_override = selection_material
	if base_mesh:
		base_mesh.material_override = selection_ring_material
	print("=== Cursor: Unit selection complete ===")

func _deselect_unit() -> void:
	"""Deselect current unit"""
	if selected_unit:
		var unit = selected_unit
		print("Deselecting unit: ", unit.name)
		selected_unit = null
		GameEvents.unit_deselected.emit(unit)
	
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
		if abs(unit_grid_pos.x - grid_pos.x) < 0.1 and abs(unit_grid_pos.z - grid_pos.z) < 0.1:
			return unit
	
	return null

func _find_all_units() -> Array[Unit]:
	"""Find all units in the scene"""
	var units: Array[Unit] = []
	var scene_root = get_tree().current_scene
	
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

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	if turn_system is SpeedFirstTurnSystem:
		var speed_system = turn_system as SpeedFirstTurnSystem
		
		# Connect to turn events
		if speed_system.turn_started.is_connected(_on_speed_first_turn_started):
			speed_system.turn_started.disconnect(_on_speed_first_turn_started)
		speed_system.turn_started.connect(_on_speed_first_turn_started)
		
		# Auto-position cursor on current acting unit
		_auto_position_on_current_unit(speed_system)

func _on_speed_first_turn_started(unit_or_player) -> void:
	"""Handle turn start in Speed First system"""
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system is SpeedFirstTurnSystem:
			_auto_position_on_current_unit(turn_system as SpeedFirstTurnSystem)

func _auto_position_on_current_unit(speed_system: SpeedFirstTurnSystem) -> void:
	"""Auto-position cursor on the current acting unit"""
	var current_unit = speed_system.get_current_acting_unit()
	if current_unit:
		# Move cursor to unit's position
		var unit_world_pos = current_unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
		
		print("Auto-positioning cursor on current acting unit: " + current_unit.get_display_name())
		print("  Unit world pos: " + str(unit_world_pos))
		print("  Unit grid pos: " + str(unit_grid_pos))
		
		# Set cursor position (this will trigger position update and selection check)
		self.tile_position = unit_grid_pos
		
		# Auto-select the unit
		await get_tree().process_frame  # Wait for position to update
		_select_unit(current_unit)

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
	print("Mouse cursor movement " + ("enabled" if enabled else "disabled"))

func toggle_mouse_mode() -> void:
	"""Toggle between mouse and keyboard-only mode"""
	set_mouse_enabled(not is_mouse_enabled)

func _test_unit_selection_signal() -> void:
	"""Test GameEvents.unit_selected signal emission"""
	print("=== Testing GameEvents.unit_selected signal ===")
	
	# Find a unit to test with
	var units = _find_all_units()
	if units.size() > 0:
		var test_unit = units[0]
		var test_position = test_unit.global_position
		print("Emitting GameEvents.unit_selected for: " + test_unit.name)
		print("Position: " + str(test_position))
		GameEvents.unit_selected.emit(test_unit, test_position)
		print("Signal emitted")
	else:
		print("No units found for testing")