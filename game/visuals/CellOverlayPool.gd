extends RefCounted
class_name CellOverlayPool

## A pooled set of flat, translucent cell highlights (one quad per grid cell), used
## by the board overlays (blue move range, red attack fringe, purple danger zone).
##
## Cells are grid coords [code]Vector3(col, floor, row)[/code] (see [Cells]); each
## quad floats [member height] above its cell's FLOOR, so an overlay on a bridge deck
## sits on the deck and one under it on the road. Quads are hidden and reused rather
## than freed, and [method show_cells] only touches cells whose state changed, so
## recomputing a large overlay every move is cheap.

const DEFAULT_SIZE := 2.0

var grid: Grid = preload("res://board/Grid.tres")
var height: float = 1.0
var material: Material

var _parent: Node
var _mesh: PlaneMesh
var _shown: Dictionary = {}   ## Vector3 grid cell -> MeshInstance3D
var _free: Array[MeshInstance3D] = []
var _name: String


func _init(parent: Node, p_material: Material, p_height: float = 1.0, node_name: String = "CellOverlay", size: float = DEFAULT_SIZE) -> void:
	_parent = parent
	material = p_material
	height = p_height
	_name = node_name
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(size * 0.96, size * 0.96)  # hairline gap keeps adjacent cells readable
	_mesh.orientation = PlaneMesh.FACE_Y


## Translucent, unshaded, glowing material for a cell layer.
static func make_material(color: Color, emission_strength: float = 0.35, priority: int = 0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(color.r, color.g, color.b) * emission_strength
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.disable_ambient_light = true
	m.render_priority = priority
	return m


## Show exactly [param cells] (grid coords); everything else is hidden.
func show_cells(cells: Array) -> void:
	var want := {}
	for c in cells:
		if c is Vector3:
			want[c] = true
		elif c is Vector3i:
			want[Cells.to_grid(c)] = true
	for c in _shown.keys():
		if not want.has(c):
			_release(c)
	for c in want.keys():
		if not _shown.has(c):
			_acquire(c)


func clear() -> void:
	for c in _shown.keys():
		_release(c)


func count() -> int:
	return _shown.size()


func has_cell(cell: Vector3) -> bool:
	return _shown.has(cell)


func cells() -> Array:
	return _shown.keys()


## Show or hide every quad without forgetting which cells are set.
func set_visible(on: bool) -> void:
	for mi in _shown.values():
		if is_instance_valid(mi):
			mi.visible = on


func _acquire(cell: Vector3) -> void:
	var mi: MeshInstance3D = null
	while not _free.is_empty() and mi == null:
		var cand: MeshInstance3D = _free.pop_back()
		if is_instance_valid(cand):
			mi = cand
	if mi == null:
		if _parent == null or not is_instance_valid(_parent):
			return
		mi = MeshInstance3D.new()
		mi.name = _name
		mi.mesh = _mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_parent.add_child(mi)
	mi.material_override = material
	var world: Vector3 = grid.calculate_map_position(cell)
	world.y += height
	mi.position = world
	mi.visible = true
	_shown[cell] = mi


func _release(cell: Vector3) -> void:
	var mi = _shown.get(cell)
	_shown.erase(cell)
	if mi != null and is_instance_valid(mi):
		mi.visible = false
		_free.append(mi)
