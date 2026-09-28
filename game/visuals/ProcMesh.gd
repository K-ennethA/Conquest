extends RefCounted
class_name ProcMesh

## Tiny flat-shaded, vertex-coloured mesh builder for procedural props (stairs,
## ladders, parapets, deck skirts, paving). Accumulate boxes / quads, then
## [method commit] one ArrayMesh; render it with [method material] (one shared
## vertex-colour material), so a whole floor of decor is one draw call.

var v := PackedVector3Array()
var n := PackedVector3Array()
var c := PackedColorArray()

static var _mat: Material = null

const PROPS_SHADER := "res://tile_objects/tiles/shaders/stylized_props.gdshader"


## Shared opaque vertex-colour material: the painterly props shader (vertex colour
## = base paint, plus world-space dabs / wood grain / moss / weather -- see
## stylized_props.gdshader). Falls back to a flat vertex-colour material if the
## shader is missing.
static func material() -> Material:
	if _mat == null:
		var sh = load(PROPS_SHADER) if ResourceLoader.exists(PROPS_SHADER) else null
		if sh is Shader:
			var sm := ShaderMaterial.new()
			sm.shader = sh
			_mat = sm
		else:
			var m := StandardMaterial3D.new()
			m.vertex_color_use_as_albedo = true
			# Colours below are authored in sRGB (like every Color literal in the project).
			m.vertex_color_is_srgb = true
			m.roughness = 0.95
			m.metallic = 0.0
			_mat = m
	return _mat


func is_empty() -> bool:
	return v.is_empty()


func commit() -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.is_empty():
		return m
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A quad a-b-d-e (counter-clockwise seen from the side [param normal] points to).
func quad(a: Vector3, b: Vector3, d: Vector3, e: Vector3, normal: Vector3, col: Color) -> void:
	_tri(a, b, d, normal, col)
	_tri(a, d, e, normal, col)


func _tri(a: Vector3, b: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	var nrm := (b - a).cross(d - a)
	if nrm.length_squared() < 1e-12:
		return
	nrm = nrm.normalized()
	if nrm.dot(want) < 0.0:
		# Flip winding so the face points where it should (front faces are CW in
		# Godot's convention for the default cull mode).
		var t := b
		b = d
		d = t
		nrm = -nrm
	# Godot treats clockwise triangles as front-facing: emit reversed.
	v.append(a); v.append(d); v.append(b)
	n.append(nrm); n.append(nrm); n.append(nrm)
	c.append(col); c.append(col); c.append(col)


## Axis-aligned box from [param lo] to [param hi]. [param top] colours the top face
## (defaults to [param col]); side faces are shaded slightly darker for form.
## [param skip_bottom] drops the (usually hidden) bottom face.
func box(lo: Vector3, hi: Vector3, col: Color, top: Color = Color(0, 0, 0, 0), skip_bottom: bool = true) -> void:
	var tc := col if top.a <= 0.0 else top
	var side := col.darkened(0.12)
	var x0 := lo.x; var y0 := lo.y; var z0 := lo.z
	var x1 := hi.x; var y1 := hi.y; var z1 := hi.z
	quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, tc)
	if not skip_bottom:
		quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3.DOWN, col.darkened(0.3))
	quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, side)
	quad(Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3.FORWARD, side.darkened(0.1))
	quad(Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3.RIGHT, side.darkened(0.05))
	quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, side.darkened(0.05))


## Box given by [param center] + [param size] in a local frame where +X is
## [param right] and +Z is [param fwd] (both unit, horizontal) around [param origin].
## Lets stairs / ladders be written once for any compass direction.
func box_oriented(origin: Vector3, right: Vector3, fwd: Vector3, lo: Vector3, hi: Vector3, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
	var tc := col if top.a <= 0.0 else top
	var side := col.darkened(0.12)
	var p := func(x: float, y: float, z: float) -> Vector3:
		return origin + right * x + Vector3.UP * y + fwd * z
	var a: Vector3 = p.call(lo.x, hi.y, lo.z)
	var b: Vector3 = p.call(hi.x, hi.y, lo.z)
	var d: Vector3 = p.call(hi.x, hi.y, hi.z)
	var e: Vector3 = p.call(lo.x, hi.y, hi.z)
	quad(a, b, d, e, Vector3.UP, tc)
	# sides: +fwd, -fwd, +right, -right
	quad(p.call(lo.x, lo.y, hi.z), p.call(hi.x, lo.y, hi.z), p.call(hi.x, hi.y, hi.z), p.call(lo.x, hi.y, hi.z), fwd, side)
	quad(p.call(lo.x, lo.y, lo.z), p.call(hi.x, lo.y, lo.z), p.call(hi.x, hi.y, lo.z), p.call(lo.x, hi.y, lo.z), -fwd, side.darkened(0.08))
	quad(p.call(hi.x, lo.y, lo.z), p.call(hi.x, lo.y, hi.z), p.call(hi.x, hi.y, hi.z), p.call(hi.x, hi.y, lo.z), right, side.darkened(0.04))
	quad(p.call(lo.x, lo.y, lo.z), p.call(lo.x, lo.y, hi.z), p.call(lo.x, hi.y, hi.z), p.call(lo.x, hi.y, lo.z), -right, side.darkened(0.04))


## Cheap deterministic hash in [0, 1) for jitter keyed on integers.
static func hash01(a: int, b: int = 0, c2: int = 0) -> float:
	var h: int = (a * 73856093) ^ (b * 19349663) ^ (c2 * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h) % 10007) / 10007.0
