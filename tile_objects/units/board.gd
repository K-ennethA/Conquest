extends Node3D


const DIRECTIONS = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]

@export var grid: Resource = preload("res://board/Grid.tres")
@onready var cursor := $Cursor
var units := {} # Vector3 to List[Tile, Units]

var _selected_unit: Unit
var selected_tile_objects : Array

func _ready() -> void:
	cursor.selected.connect(_is_selected)
	initialize_units()
	
func _unhandled_input(event: InputEvent) -> void:
	if _selected_unit and event.is_action_pressed("ui_cancel"):
		print("cancelling")
		_selected_unit.is_selected = false
	
func initialize_units() -> void:
	for child in get_children():
		if child.get_children():
			for nested in child.get_children():
				if nested is TileObject:
					var tile_position = grid.get_tile_position(nested.position)
					if units.has(tile_position):
						units[tile_position].append(nested)
					else:
						units[tile_position] = [nested]

func _is_selected(_position: Vector3) -> void:
	if not selected_tile_objects:
		select_tile_objects(_position)
		select_movement_units(get_movement_tiles(_position, 10))
		var unit = get_unit_at_position(_position)
		if unit:
			highlight_unit(unit.get_node("MeshInstance3D"))
	elif selected_tile_objects:
		print("move and deselect")
		unhighlight_units(get_movement_tiles(_position, 1000, true))
		if _selected_unit:
			move_unit(_position)
		selected_tile_objects = []

func select_tile_objects(_position: Vector3) -> void:
	var tile_position = grid.get_tile_position(_position)
	if not units.has(tile_position):
		return
	selected_tile_objects = units[tile_position]
	_select_unit(_position)

func _select_unit(_position: Vector3) -> void:
	var tile_position = grid.get_tile_position(_position)
	var unit : Unit
	if not units.has(tile_position):
		return
	for tile_object in units[tile_position]:
		if tile_object is Unit:
			unit = tile_object
	
	if unit:
		_selected_unit = unit
		_selected_unit.is_selected = true
	
func move_unit(_position: Vector3) -> void:
	var unit_to_move : Unit
	for tile_object in units[grid.get_tile_position(_selected_unit.position)]:
		if tile_object is Unit:
			unit_to_move =  tile_object
			units[grid.get_tile_position(_selected_unit.position)].erase(tile_object)
	if unit_to_move:
		_selected_unit.position = grid.get_translated_position(_selected_unit.position, _position)
		units[grid.get_tile_position(_selected_unit.position)].append(unit_to_move)
		_selected_unit = null


func select_movement_units(units_to_highlight: Array) -> void:
	#highlight_unit() get the current pos unit and select that one
	
	for _tiles_pos in units_to_highlight:
		var tile_objects = units[grid.get_tile_position(_tiles_pos)]
		for tile_object in tile_objects:
			if tile_object is not Unit:
				var mesh_instance = tile_object.get_node("MeshInstance3D")
				highlight_unit(mesh_instance)			

func highlight_unit(mesh: MeshInstance3D) -> void:
	var shader = load("res://selected_shader.gdshader")
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	
	var original_color = mesh.mesh.material.albedo_color
	shader_material.set_shader_parameter("original_color", original_color)
	shader_material.set_shader_parameter("is_selected", true)
	mesh.set_surface_override_material(0, shader_material)

func unhighlight_units(units_to_highlight: Array):
	for _tiles_pos in units_to_highlight:
		var obj = units[grid.get_tile_position(_tiles_pos)]
		for item in obj:
			var mesh_instance = item.get_node("MeshInstance3D")
			var material_override = mesh_instance.get_surface_override_material(0)
			if material_override:
				material_override.set_shader_parameter("is_selected", false)
	
func get_movement_tiles(tile_position: Vector3, max_distance: int, select_all: bool = false) -> Array:
	var array := []
	var stack := [tile_position]
	if not _selected_unit && not select_all:
		return [tile_position]
		
	while not stack.size() == 0:
		var current = stack.pop_back()
		if not grid.is_within_bounds(current):
			continue
		if current in array:
			continue

		array.append(current)
		for direction in DIRECTIONS:
			var coordinates: Vector3 = current + direction
			if is_occupied(coordinates):
				continue
			if coordinates in array:
				continue
			# Minor optimization: If this neighbor is already queued
			#	to be checked, we don't need to queue it again
			if coordinates in stack:
				continue

			stack.append(coordinates)
	return array

func is_occupied(coordinates: Vector3) -> bool:
	return false
	
func get_unit_at_position(_position: Vector3) -> Unit:
	var tile_objects = units[grid.get_tile_position(_position)]
	var unit : Unit
	for tile_object in tile_objects:
		if tile_object is Unit:
			unit = tile_object
	return unit
