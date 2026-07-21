extends Node

class_name MovementVisualizer

# Handles visual feedback for unit movement using overlay mesh approach
# Creates floating highlight planes above ONLY the reachable tiles (the movement range),
# rather than covering the whole map. Meshes are pooled and reused between selections.
# Grid lines are now handled by MapGridVisualizer.

@export var grid: Resource = preload("res://board/Grid.tres")

# Set true to print a single one-line summary per range update (off by default).
var debug_summary: bool = false

# Visual state
var highlighted_tiles: Array[Vector3] = []
var overlay_meshes: Dictionary = {}          # cell Vector3 -> MeshInstance3D (currently shown)
var _mesh_pool: Array[MeshInstance3D] = []    # hidden, reusable overlay meshes

# Shared plane mesh reused by every overlay instance (cheap, no per-tile allocation)
var _shared_plane_mesh: PlaneMesh

# Materials for different movement states
var movement_range_material: StandardMaterial3D
var invalid_move_material: StandardMaterial3D
var path_preview_material: StandardMaterial3D

# Overlay mesh settings
var overlay_height: float = 1.0  # Height above tiles
var overlay_size: float = 2.0    # Size to match tile size (2x2 units)

func _ready() -> void:
	_setup_materials()
	_setup_shared_mesh()
	_connect_events()

func _setup_materials() -> void:
	"""Create materials for movement visualization (transparent glowy panes)"""
	# Movement range material (transparent glowy blue - the model shows through)
	movement_range_material = StandardMaterial3D.new()
	movement_range_material.albedo_color = Color(0.3, 0.7, 1.0, 0.35)  # Transparent bright blue
	movement_range_material.flags_transparent = true
	movement_range_material.flags_unshaded = true
	movement_range_material.emission_enabled = true
	movement_range_material.emission = Color(0.5, 0.8, 1.0, 0.35)  # Soft blue glow
	movement_range_material.no_depth_test = false  # Let taller unit models occlude the flat quads
	movement_range_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	movement_range_material.flags_do_not_receive_shadows = true
	movement_range_material.flags_disable_ambient_light = true

	# Invalid move material (transparent glowy red)
	invalid_move_material = StandardMaterial3D.new()
	invalid_move_material.albedo_color = Color(1.0, 0.3, 0.3, 0.35)
	invalid_move_material.flags_transparent = true
	invalid_move_material.flags_unshaded = true
	invalid_move_material.emission_enabled = true
	invalid_move_material.emission = Color(1.0, 0.5, 0.5, 0.35)
	invalid_move_material.no_depth_test = false
	invalid_move_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	invalid_move_material.flags_do_not_receive_shadows = true
	invalid_move_material.flags_disable_ambient_light = true

	# Path preview material (transparent glowy green)
	path_preview_material = StandardMaterial3D.new()
	path_preview_material.albedo_color = Color(0.3, 1.0, 0.3, 0.35)
	path_preview_material.flags_transparent = true
	path_preview_material.flags_unshaded = true
	path_preview_material.emission_enabled = true
	path_preview_material.emission = Color(0.5, 1.0, 0.5, 0.35)
	path_preview_material.no_depth_test = false
	path_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	path_preview_material.flags_do_not_receive_shadows = true
	path_preview_material.flags_disable_ambient_light = true

func _setup_shared_mesh() -> void:
	"""One shared plane mesh reused by every overlay instance"""
	_shared_plane_mesh = PlaneMesh.new()
	_shared_plane_mesh.size = Vector2(overlay_size, overlay_size)
	_shared_plane_mesh.orientation = PlaneMesh.FACE_Y  # Face upward

func _connect_events() -> void:
	"""Connect to GameEvents for movement visualization"""
	if GameEvents:
		GameEvents.movement_range_calculated.connect(_on_movement_range_calculated)
		GameEvents.movement_range_cleared.connect(_on_movement_range_cleared)
		GameEvents.cursor_moved.connect(_on_cursor_moved)

func _on_movement_range_calculated(positions: Array[Vector3]) -> void:
	"""Highlight ONLY the reachable tiles (the actual movement range)"""
	# Retire any currently shown overlays into the pool.
	_clear_all_highlights()

	# Store movement positions for reference
	highlighted_tiles = positions.duplicate()

	# Draw a cheap glowy quad for each reachable cell only.
	for cell in positions:
		_show_overlay_at_cell(cell, movement_range_material)

	if debug_summary:
		print("MovementVisualizer: highlighted ", overlay_meshes.size(), " reachable tiles")

func _on_movement_range_cleared() -> void:
	"""Clear movement range visualization"""
	_clear_all_highlights()

func _on_cursor_moved(position: Vector3) -> void:
	"""Handle cursor movement for path preview (if in movement mode)"""
	# This could be enhanced to show path preview from unit to cursor
	pass

func _show_overlay_at_cell(cell: Vector3, material: StandardMaterial3D) -> void:
	"""Show a floating overlay quad at the given grid cell, reusing a pooled mesh if available"""
	var world_pos: Vector3 = grid.calculate_map_position(cell)
	world_pos.y += overlay_height  # Float above the tile

	var mesh_instance: MeshInstance3D = _acquire_mesh()
	mesh_instance.material_override = material
	mesh_instance.position = world_pos
	mesh_instance.visible = true

	overlay_meshes[cell] = mesh_instance

func _acquire_mesh() -> MeshInstance3D:
	"""Reuse a hidden mesh from the pool, or instance a new one if the pool is empty"""
	if not _mesh_pool.is_empty():
		return _mesh_pool.pop_back()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MovementOverlay"
	mesh_instance.mesh = _shared_plane_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var scene_root: Node = get_tree().current_scene
	scene_root.add_child(mesh_instance)
	return mesh_instance

func _clear_all_highlights() -> void:
	"""Hide all shown overlays and return them to the pool for reuse (no queue_free churn)"""
	for cell in overlay_meshes.keys():
		var mesh_instance = overlay_meshes[cell]
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.visible = false
			_mesh_pool.append(mesh_instance)

	overlay_meshes.clear()
	highlighted_tiles.clear()

# Public interface
func is_highlighting_movement_range() -> bool:
	"""Check if currently showing movement range"""
	return highlighted_tiles.size() > 0

func get_highlighted_tiles() -> Array[Vector3]:
	"""Get currently highlighted tile positions"""
	return highlighted_tiles.duplicate()
