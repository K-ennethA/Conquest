extends Node3D

signal selected(position)

var tile_objects_selected := [TileObject]
var is_selected := false

@export var grid: Resource = preload("res://board/Grid.tres")

var tile_position := Vector3.ZERO:
	set(value):
		# We first clamp the cell coordinates and ensure that we aren't
		#	trying to move outside the grid boundaries
		var new_cell: Vector3 = grid.grid_clamp(value)
		if new_cell.is_equal_approx(tile_position):
			return

		tile_position = new_cell
		# If we move to a new cell, we update the cursor's position, emit
		#	a signal, and start the cooldown timer that will limit the rate
		#	at which the cursor moves when we keep the direction key held
		#	down
		#position = grid.calculate_map_position(tile_position)
		#emit_signal("moved", cell)
		#_timer.start()
		
func _ready() -> void:
	print("starting", position)

	#position = grid.calculate_map_position(tile_position)
	print("tile pos", tile_position)
	print(position)
		
func _unhandled_input(event: InputEvent) -> void:
	
	#if event is InputEventMouseMotion:
		#cell = grid.calculate_grid_coordinates(event.position)
	# Trying to select something in a cell.
	
	if event.is_action_pressed("ui_cancel"):
		is_selected = false
	if event.is_action_pressed("ui_accept"):
		selected.emit(position)
	
	if event.is_action_released("ui_right") && grid.is_within_bounds(position + Vector3.RIGHT):
		#self.tile_position = grid.calculate_grid_coordinates(position)
		print("pos on vlick", position)
		print("right", Vector3.RIGHT)
		
		position += Vector3.RIGHT
		print("pos after", position)
		
	elif event.is_action("ui_left") && grid.is_within_bounds(position + Vector3.LEFT):
		position += Vector3.LEFT
	elif event.is_action("ui_down") && grid.is_within_bounds(position + Vector3.BACK):
		position += Vector3.BACK
	elif event.is_action("ui_up") && grid.is_within_bounds(position + Vector3.FORWARD):
		position += Vector3.FORWARD
