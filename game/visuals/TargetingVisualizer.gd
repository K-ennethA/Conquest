extends Node3D

class_name TargetingVisualizer

# Handles visual feedback for attack targeting: attack-range highlights and
# AoE preview highlights, driven entirely by GameEvents signals.
# Mirrors the overlay mesh approach used by MovementVisualizer/MapGridVisualizer:
# simple flat quads floating just above the tiles, rather than modifying tile
# materials directly.

@export var grid: Resource = preload("res://board/Grid.tres")

# Overlay mesh settings
var overlay_size: float = 2.0            # Matches tile size (2x2 units)
var attack_range_height: float = 1.0     # Height above tiles for attack-range markers
var aoe_preview_height: float = 1.05     # Slightly higher so AoE markers render on top

# Visual state
var attack_range_meshes: Dictionary = {}  # Vector3 cell -> MeshInstance3D
var aoe_preview_meshes: Dictionary = {}   # Vector3 cell -> MeshInstance3D

# Materials
var attack_range_material: StandardMaterial3D
var aoe_preview_material: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	_connect_events()


func _setup_materials() -> void:
	"""Create materials for attack-range and AoE preview visualization"""
	# Attack range material (transparent glowy red - enemies show through)
	attack_range_material = StandardMaterial3D.new()
	attack_range_material.albedo_color = Color(1.0, 0.25, 0.25, 0.35)
	attack_range_material.flags_transparent = true
	attack_range_material.flags_unshaded = true
	attack_range_material.emission_enabled = true
	attack_range_material.emission = Color(1.0, 0.35, 0.35, 0.35)
	attack_range_material.no_depth_test = false  # Let unit models occlude the flat ground quads
	attack_range_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	attack_range_material.flags_do_not_receive_shadows = true
	attack_range_material.flags_disable_ambient_light = true

	# AoE preview material (transparent glowy orange, a touch stronger than attack range)
	aoe_preview_material = StandardMaterial3D.new()
	aoe_preview_material.albedo_color = Color(1.0, 0.55, 0.05, 0.45)
	aoe_preview_material.flags_transparent = true
	aoe_preview_material.flags_unshaded = true
	aoe_preview_material.emission_enabled = true
	aoe_preview_material.emission = Color(1.0, 0.65, 0.1, 0.45)
	aoe_preview_material.no_depth_test = false  # Let unit models occlude the flat ground quads
	aoe_preview_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	aoe_preview_material.flags_do_not_receive_shadows = true
	aoe_preview_material.flags_disable_ambient_light = true


func _connect_events() -> void:
	"""Connect to GameEvents for targeting visualization; null-safe if unavailable"""
	if not GameEvents:
		push_warning("TargetingVisualizer: GameEvents not found, targeting visuals disabled")
		return

	GameEvents.attack_range_calculated.connect(_on_attack_range_calculated)
	GameEvents.aoe_preview_calculated.connect(_on_aoe_preview_calculated)
	GameEvents.targeting_cleared.connect(_on_targeting_cleared)


func _on_attack_range_calculated(cells: Array) -> void:
	"""Draw range-highlight markers at each attack-range cell"""
	_clear_attack_range_markers()

	for cell in cells:
		if cell is Vector3:
			_create_overlay_at_cell(cell, attack_range_material, attack_range_height, attack_range_meshes, "AttackRange")


func _on_aoe_preview_calculated(cells: Array) -> void:
	"""Draw a second, brighter highlight set for the AoE preview"""
	_clear_aoe_preview_markers()

	for cell in cells:
		if cell is Vector3:
			_create_overlay_at_cell(cell, aoe_preview_material, aoe_preview_height, aoe_preview_meshes, "AoEPreview")


func _on_targeting_cleared() -> void:
	"""Remove all targeting markers (attack range and AoE preview)"""
	_clear_attack_range_markers()
	_clear_aoe_preview_markers()


func _create_overlay_at_cell(cell: Vector3, material: StandardMaterial3D, height: float, storage: Dictionary, name_prefix: String) -> void:
	"""Create a floating overlay mesh at the specified grid cell"""
	if not grid:
		return

	var world_pos: Vector3 = grid.calculate_map_position(cell)
	world_pos.y += height

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "%s_%s_%s" % [name_prefix, str(cell.x), str(cell.z)]

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(overlay_size, overlay_size)
	plane_mesh.orientation = PlaneMesh.FACE_Y

	mesh_instance.mesh = plane_mesh
	mesh_instance.material_override = material
	mesh_instance.position = world_pos
	mesh_instance.visible = true
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(mesh_instance)
	storage[cell] = mesh_instance


func _clear_attack_range_markers() -> void:
	"""Remove all attack-range overlay meshes"""
	for cell in attack_range_meshes.keys():
		var mesh_instance = attack_range_meshes[cell]
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	attack_range_meshes.clear()


func _clear_aoe_preview_markers() -> void:
	"""Remove all AoE preview overlay meshes"""
	for cell in aoe_preview_meshes.keys():
		var mesh_instance = aoe_preview_meshes[cell]
		if mesh_instance and is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	aoe_preview_meshes.clear()


# Public interface
func is_showing_attack_range() -> bool:
	"""Check if attack-range markers are currently displayed"""
	return attack_range_meshes.size() > 0


func is_showing_aoe_preview() -> bool:
	"""Check if AoE preview markers are currently displayed"""
	return aoe_preview_meshes.size() > 0
