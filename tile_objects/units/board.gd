extends Node3D

# Board manages the game state and coordinates between systems
# Responds to events rather than directly managing other systems

@export var grid: Resource = preload("res://board/Grid.tres")

# Game state
var units: Dictionary = {} # Vector3 -> Array[TileObject]
var _selected_unit: Unit
var _highlighted_tiles: Array[Vector3] = []
var _turn_system: Node

func _ready() -> void:
	initialize_units()
	_connect_events()
	_setup_turn_system()

func _connect_events() -> void:
	GameEvents.cursor_selected.connect(_on_cursor_selected)
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	GameEvents.turn_started.connect(_on_turn_started)
	GameEvents.turn_ended.connect(_on_turn_ended)

func _setup_turn_system() -> void:
	_turn_system = get_node("../TurnSystem")
	if _turn_system:
		# Collect all units and initialize turn system
		var all_units: Array[Unit] = []
		for tile_objects in units.values():
			for obj in tile_objects:
				if obj is Unit:
					all_units.append(obj)
		
		if not all_units.is_empty():
			_turn_system.initialize_with_units(all_units)

func initialize_units() -> void:
	for child in get_children():
		_scan_node_for_tile_objects(child)

func _scan_node_for_tile_objects(node: Node) -> void:
	if node is TileObject:
		var tile_position = grid.get_tile_position(node.position)
		if not units.has(tile_position):
			units[tile_position] = []
		units[tile_position].append(node)
	
	for child in node.get_children():
		_scan_node_for_tile_objects(child)

func _on_cursor_selected(position: Vector3) -> void:
	if _selected_unit:
		_attempt_move_unit(position)
	else:
		_attempt_select_unit(position)

func _attempt_select_unit(position: Vector3) -> void:
	var unit = _get_unit_at_position(position)
	if unit and _can_select_unit(unit):
		_selected_unit = unit
		GameEvents.unit_selected.emit(unit, position)
		_show_movement_range(unit, position)

func _can_select_unit(unit: Unit) -> bool:
	# Only allow selecting units during their turn
	return _turn_system and _turn_system.is_unit_turn(unit)

func _attempt_move_unit(position: Vector3) -> void:
	if _can_move_to_position(position):
		_move_unit_to_position(_selected_unit, position)
	_clear_selection()

func _get_unit_at_position(position: Vector3) -> Unit:
	var tile_position = grid.get_tile_position(position)
	if not units.has(tile_position):
		return null
	
	for tile_object in units[tile_position]:
		if tile_object is Unit:
			return tile_object
	return null

func _can_move_to_position(position: Vector3) -> bool:
	if not _selected_unit:
		return false
	
	var current_pos = grid.get_tile_position(_selected_unit.position)
	var target_pos = grid.get_tile_position(position)
	var distance = _calculate_distance(current_pos, target_pos)
	
	return distance <= _selected_unit.get_movement_range() and grid.is_within_bounds(target_pos)

func _calculate_distance(from: Vector3, to: Vector3) -> int:
	# Manhattan distance for grid-based movement
	return int(abs(to.x - from.x) + abs(to.z - from.z))

func _move_unit_to_position(unit: Unit, new_position: Vector3) -> void:
	var old_tile_pos = grid.get_tile_position(unit.position)
	var new_tile_pos = grid.get_tile_position(new_position)
	
	# Remove from old position
	if units.has(old_tile_pos):
		units[old_tile_pos].erase(unit)
		if units[old_tile_pos].is_empty():
			units.erase(old_tile_pos)
	
	# Add to new position
	if not units.has(new_tile_pos):
		units[new_tile_pos] = []
	units[new_tile_pos].append(unit)
	
	# Update unit position
	unit.position = grid.calculate_map_position(new_tile_pos)
	
	GameEvents.unit_moved.emit(unit, old_tile_pos, new_tile_pos)

func _show_movement_range(unit: Unit, position: Vector3) -> void:
	var reachable_positions = _calculate_movement_range(position, unit.get_movement_range())
	_highlighted_tiles = reachable_positions
	GameEvents.movement_range_calculated.emit(reachable_positions)
	
	# Highlight tiles
	for pos in reachable_positions:
		_highlight_tile_at_position(pos)

func _calculate_movement_range(start_position: Vector3, max_distance: int) -> Array[Vector3]:
	var reachable: Array[Vector3] = []
	var queue: Array = [start_position]
	var visited: Dictionary = {start_position: 0}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_distance = visited[current]
		
		if current_distance < max_distance:
			for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
				var next_pos = current + direction
				
				if grid.is_within_bounds(next_pos) and not visited.has(next_pos):
					visited[next_pos] = current_distance + 1
					queue.append(next_pos)
					reachable.append(next_pos)
	
	return reachable

func _highlight_tile_at_position(position: Vector3) -> void:
	var tile_position = grid.get_tile_position(position)
	if not units.has(tile_position):
		return
	
	for tile_object in units[tile_position]:
		if tile_object is Tile:
			var mesh_instance = tile_object.get_node("MeshInstance3D")
			if mesh_instance:
				var original_color = Color.WHITE
				if mesh_instance.mesh and mesh_instance.mesh.material:
					original_color = mesh_instance.mesh.material.get("albedo_color")
				
				var material = ResourceManager.get_selection_material(original_color)
				ResourceManager.set_selection_state(material, true)
				mesh_instance.set_surface_override_material(0, material)

func _clear_selection() -> void:
	if _selected_unit:
		GameEvents.unit_deselected.emit(_selected_unit)
		_selected_unit = null
	
	_clear_highlighted_tiles()

func _clear_highlighted_tiles() -> void:
	for position in _highlighted_tiles:
		_unhighlight_tile_at_position(position)
	_highlighted_tiles.clear()

func _unhighlight_tile_at_position(position: Vector3) -> void:
	var tile_position = grid.get_tile_position(position)
	if not units.has(tile_position):
		return
	
	for tile_object in units[tile_position]:
		if tile_object is Tile:
			var mesh_instance = tile_object.get_node("MeshInstance3D")
			if mesh_instance:
				var material = mesh_instance.get_surface_override_material(0)
				if material:
					ResourceManager.set_selection_state(material, false)

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	# Additional logic when a unit is selected
	pass

func _on_unit_deselected(unit: Unit) -> void:
	# Additional logic when a unit is deselected
	pass

func _on_turn_started(unit: Unit) -> void:
	# Visual feedback for whose turn it is
	pass

func _on_turn_ended(unit: Unit) -> void:
	# Clean up after turn ends
	if _selected_unit == unit:
		_clear_selection()
