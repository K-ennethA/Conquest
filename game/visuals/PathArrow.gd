extends Node3D
class_name PathArrow

## Fire-Emblem style movement arrow: a thick gold ribbon with a dark outline running
## cell-centre to cell-centre along a path, rounded joints at the turns and an
## arrowhead on the destination. Paths come as grid coords
## [code]Vector3(col, floor, row)[/code] (see [Cells]); each point is raised to its
## own floor, so a step over a stair link draws as a slope.
##
## Pieces are pooled MeshInstance3Ds (hidden + reused), so re-drawing on every cursor
## step allocates nothing after warm-up. Materials ignore depth so the arrow always
## reads over unit models and terrain props.

const RIBBON_WIDTH := 0.42
const OUTLINE_PAD := 0.14
const THICKNESS := 0.04
const HEAD_LENGTH := 0.9
const HEAD_WIDTH := 1.05
## The head's centre sits this far past the destination centre; the last ribbon
## segment stops the same distance short of it, tucking under the head's base.
const HEAD_OFFSET := 0.2

const GOLD := Color(1.0, 0.86, 0.36, 0.95)
const OUTLINE := Color(0.10, 0.06, 0.02, 0.85)

var grid: Grid = preload("res://board/Grid.tres")
## Height above the cell's floor the ribbon floats at (just over the move overlay).
var height: float = 0.26

var _gold_mat: StandardMaterial3D
var _outline_mat: StandardMaterial3D
var _box: BoxMesh
var _box_outline: BoxMesh
var _disc: CylinderMesh
var _disc_outline: CylinderMesh
var _head: ArrayMesh
var _head_outline: ArrayMesh
var _pool: Array[MeshInstance3D] = []
var _used: int = 0
var _cells: Array = []


func _ready() -> void:
	name = "PathArrow"
	_gold_mat = _material(GOLD, 2)
	_outline_mat = _material(OUTLINE, 1)
	_box = BoxMesh.new()
	_box.size = Vector3(RIBBON_WIDTH, THICKNESS, 1.0)
	_box_outline = BoxMesh.new()
	_box_outline.size = Vector3(RIBBON_WIDTH + OUTLINE_PAD, THICKNESS * 0.5, 1.0)
	_disc = _make_disc(RIBBON_WIDTH * 0.5)
	_disc_outline = _make_disc((RIBBON_WIDTH + OUTLINE_PAD) * 0.5)
	_head = _make_head(HEAD_WIDTH, HEAD_LENGTH)
	_head_outline = _make_head(HEAD_WIDTH + OUTLINE_PAD * 1.6, HEAD_LENGTH + OUTLINE_PAD * 1.4)


## Draw the arrow along [param cells] (grid coords, origin first). Fewer than two
## cells hides it.
func show_path(cells: Array) -> void:
	_cells = cells.duplicate()
	_begin()
	if cells.size() >= 2:
		var pts: Array[Vector3] = []
		for c in cells:
			var gc: Vector3 = c if c is Vector3 else Cells.to_grid(c)
			var w: Vector3 = grid.calculate_map_position(gc)
			w.y += height
			pts.append(w)
		var n := pts.size()
		# Start nub + joints.
		for i in range(n - 1):
			_place(_disc_outline, _outline_mat, pts[i], Basis(), -0.005)
			_place(_disc, _gold_mat, pts[i], Basis(), 0.0)
		for i in range(n - 1):
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			if i == n - 2:
				# Stop the last segment where the arrowhead's base begins.
				var d := b - a
				var flat_len := d.length()
				if flat_len > 0.001:
					b = a + d * maxf(0.0, (flat_len - HEAD_OFFSET) / flat_len)
			_segment(a, b)
		var last_dir: Vector3 = pts[n - 1] - pts[n - 2]
		var head_basis := _basis_along(last_dir)
		var tip: Vector3 = pts[n - 1] + last_dir.normalized() * HEAD_OFFSET
		_place(_head_outline, _outline_mat, tip + head_basis.z * (OUTLINE_PAD * 0.7), head_basis, -0.005)
		_place(_head, _gold_mat, tip, head_basis, 0.0)
	_end()


func clear() -> void:
	_cells = []
	_begin()
	_end()


## The grid cells currently drawn (for tests / callers).
func current_path() -> Array:
	return _cells.duplicate()


func is_showing() -> bool:
	return _cells.size() >= 2


# --- construction ---------------------------------------------------------------

func _segment(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var basis := _basis_along(d)
	var mid := (a + b) * 0.5
	_place(_box_outline, _outline_mat, mid, basis.scaled_local(Vector3(1, 1, length + OUTLINE_PAD * 0.5)), -0.005)
	_place(_box, _gold_mat, mid, basis.scaled_local(Vector3(1, 1, length)), 0.0)


## Basis whose -Z points along [param dir] (Node3D.look_at convention).
func _basis_along(dir: Vector3) -> Basis:
	if dir.length() < 0.0001:
		return Basis()
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.98:
		up = Vector3.FORWARD
	return Basis.looking_at(dir, up)


func _place(mesh: Mesh, mat: Material, pos: Vector3, basis: Basis, dy: float) -> void:
	var mi: MeshInstance3D
	if _used < _pool.size():
		mi = _pool[_used]
	else:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_pool.append(mi)
	_used += 1
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos + Vector3(0, dy, 0))
	mi.visible = true


func _begin() -> void:
	_used = 0


func _end() -> void:
	for i in range(_used, _pool.size()):
		_pool[i].visible = false


static func _material(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.render_priority = priority
	return m


static func _make_disc(radius: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = THICKNESS
	c.radial_segments = 16
	c.rings = 1
	return c


## Flat triangle in the XZ plane, tip at -Z (the look_at forward), base centred on +Z.
static func _make_head(width: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(0, 0, -length * 0.5))
	st.add_vertex(Vector3(width * 0.5, 0, length * 0.5))
	st.add_vertex(Vector3(-width * 0.5, 0, length * 0.5))
	return st.commit()
