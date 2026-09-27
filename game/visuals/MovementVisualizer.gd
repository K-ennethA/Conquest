extends Node

class_name MovementVisualizer

# Handles visual feedback for unit movement using overlay mesh approach
# Creates floating highlight planes above ONLY the reachable tiles (the movement range),
# rather than covering the whole map. Meshes are pooled and reused between selections.
# Grid lines are now handled by MapGridVisualizer.
#
# Fire-Emblem layers on top of the blue range (all driven by GameEvents):
#   * RED attack fringe  -- attack_fringe_calculated: cells the unit could hit but not
#     reach, drawn around the blue range (cleared with the range).
#   * PATH ARROW          -- path_preview_updated: the route to the hovered cell.
# Every overlay sits on its cell's FLOOR (grid coords carry the floor in y).

@export var grid: Resource = preload("res://board/Grid.tres")

# Set true to print a single one-line summary per range update (off by default).
var debug_summary: bool = false

# Visual state
var highlighted_tiles: Array[Vector3] = []
var fringe_tiles: Array[Vector3] = []

# Materials for different movement states
var movement_range_material: StandardMaterial3D
var invalid_move_material: StandardMaterial3D   # the red attack fringe
var path_preview_material: StandardMaterial3D

# Overlay mesh settings
## Height above the cell's floor origin: just over the 0.2-thick tile slab (a larger
## lift visibly shifts the quads off their cells under the tilted camera).
var overlay_height: float = 0.16
var overlay_size: float = 2.0    # Size to match tile size (2x2 units)

var _move_pool: CellOverlayPool
var _fringe_pool: CellOverlayPool
var _arrow: PathArrow

func _ready() -> void:
	_setup_materials()
	_move_pool = CellOverlayPool.new(self, movement_range_material, overlay_height, "MovementOverlay", overlay_size)
	_move_pool.grid = grid
	_fringe_pool = CellOverlayPool.new(self, invalid_move_material, overlay_height, "AttackFringeOverlay", overlay_size)
	_fringe_pool.grid = grid
	_arrow = PathArrow.new()
	_arrow.grid = grid
	_arrow.height = overlay_height + 0.1
	add_child(_arrow)
	_connect_events()

func _setup_materials() -> void:
	"""Create materials for movement visualization (transparent glowy panes)"""
	# Blue move range (the model shows through).
	movement_range_material = CellOverlayPool.make_material(Color(0.22, 0.55, 1.0, 0.5), 0.45)
	# Red attack fringe (FE: where it could strike without moving there).
	invalid_move_material = CellOverlayPool.make_material(Color(1.0, 0.1, 0.12, 0.58), 0.45)
	# Path preview (kept for API compatibility; the arrow draws the path).
	path_preview_material = CellOverlayPool.make_material(Color(0.3, 1.0, 0.3, 0.35), 0.35)

func _connect_events() -> void:
	"""Connect to GameEvents for movement visualization"""
	if GameEvents:
		GameEvents.movement_range_calculated.connect(_on_movement_range_calculated)
		GameEvents.movement_range_cleared.connect(_on_movement_range_cleared)
		GameEvents.attack_fringe_calculated.connect(_on_attack_fringe_calculated)
		GameEvents.path_preview_updated.connect(_on_path_preview_updated)

func _on_movement_range_calculated(positions: Array[Vector3]) -> void:
	"""Highlight ONLY the reachable tiles (the actual movement range). A new range
	drops the previous fringe and arrow; the caller re-sends a fringe if it has one."""
	highlighted_tiles = positions.duplicate()
	_move_pool.show_cells(positions)
	_set_fringe([])
	_arrow.clear()

	if debug_summary:
		print("MovementVisualizer: highlighted ", _move_pool.count(), " reachable tiles")

func _on_movement_range_cleared() -> void:
	"""Clear movement range visualization (range, fringe and path arrow)."""
	_clear_all_highlights()

func _on_attack_fringe_calculated(cells: Array) -> void:
	_set_fringe(cells)

func _on_path_preview_updated(cells: Array) -> void:
	if cells.size() < 2:
		_arrow.clear()
	else:
		_arrow.show_path(cells)

func _set_fringe(cells: Array) -> void:
	fringe_tiles.clear()
	for c in cells:
		if c is Vector3:
			fringe_tiles.append(c)
	_fringe_pool.show_cells(fringe_tiles)

func _clear_all_highlights() -> void:
	"""Hide all shown overlays and return them to the pool for reuse (no queue_free churn)"""
	_move_pool.clear()
	_fringe_pool.clear()
	_arrow.clear()
	highlighted_tiles.clear()
	fringe_tiles.clear()

# Public interface
func is_highlighting_movement_range() -> bool:
	"""Check if currently showing movement range"""
	return highlighted_tiles.size() > 0

func get_highlighted_tiles() -> Array[Vector3]:
	"""Get currently highlighted tile positions"""
	return highlighted_tiles.duplicate()

func get_fringe_tiles() -> Array[Vector3]:
	return fringe_tiles.duplicate()

func get_path_arrow() -> PathArrow:
	return _arrow
