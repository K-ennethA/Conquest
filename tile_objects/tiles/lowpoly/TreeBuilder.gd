@tool
extends Node3D
class_name TreeBuilder

## Stylized, painterly tree for a tile (and the world skirt). A helper node under a
## tile scene: at load it picks a DETERMINISTIC variant from its world XZ -- species
## (round broadleaf / tiered oak / conifer / bush), size, yaw -- and shows it with
## SHARED meshes + materials (a handful of cached variant meshes for the whole map,
## so 90 trees cost 90 cheap instances, not 90 unique meshes / materials):
##   * Trunk  -- tapered, 6-sided, with a flared root skirt and branch stubs,
##               bark gradient in vertex colour (stylized_decor material).
##   * Canopy -- clustered blobs / pine tiers with "spherized" normals so the
##               stylized_foliage shader paints a soft lit-top / cool-underside
##               ramp, leaf-cluster dabs, a warm rim, per-tree hue (lush / olive /
##               autumn, hashed from the node origin in the shader), gentle sway
##               and cursor see-through.
##   * Shadow -- a soft multiply contact-shadow blob grounding the tree.
## Trees stay within the old footprint (<= ~1.3 wide, <= ~2.0 tall) so units
## behind them remain readable.

enum Species { AUTO, BROADLEAF, OAK, CONIFER, BUSH, SNOW_PINE }
@export var species: Species = Species.AUTO

const FOLIAGE_MAT := "res://tile_objects/tiles/materials/stylized_foliage_material.tres"
const FOLIAGE_SNOW_MAT := "res://tile_objects/tiles/materials/stylized_foliage_snow_material.tres"
const DECOR_SHADER := "res://tile_objects/tiles/shaders/stylized_decor.gdshader"
const VARIANTS := 3

const BARK_DARK := Color(0.20, 0.13, 0.09, 0.12)
const BARK_MID := Color(0.36, 0.24, 0.15, 0.12)
const BARK_LIGHT := Color(0.50, 0.36, 0.23, 0.12)


static var _canopy_cache: Dictionary = {}
static var _trunk_cache: Dictionary = {}
static var _decor_mat: ShaderMaterial = null
static var _shadow_mat: ShaderMaterial = null
static var _shadow_mesh: QuadMesh = null


func _ready() -> void:
	var p := global_position
	var pick := pick_variant(p.x, p.z, species)
	_clear()
	var holder := Node3D.new()
	holder.name = "Tree"
	holder.rotation.y = pick["yaw"]
	holder.scale = Vector3.ONE * float(pick["scale"])
	add_child(holder)
	var sp: int = pick["species"]
	var v: int = pick["variant"]
	var trunk_mesh := trunk_mesh_for(sp, v)
	if trunk_mesh != null:
		var trunk := MeshInstance3D.new()
		trunk.name = "Trunk"
		trunk.mesh = trunk_mesh
		trunk.material_override = decor_material()
		holder.add_child(trunk)
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	canopy.mesh = canopy_mesh_for(sp, v)
	canopy.material_override = foliage_material(sp == Species.SNOW_PINE)
	holder.add_child(canopy)
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = shadow_mesh()
	shadow.material_override = shadow_material()
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.position = Vector3(0.0, 0.006, 0.0)
	shadow.rotation.x = -PI * 0.5
	var ss: float = 1.0 if sp != Species.BUSH else 0.75
	shadow.scale = Vector3(ss, ss, ss)
	add_child(shadow)


func _clear() -> void:
	for c in get_children():
		c.queue_free()


# --- Deterministic variant pick ------------------------------------------------

static func _h(x: float, z: float, salt: int) -> float:
	return ProcMesh.hash01(int(round(x * 3.0)), int(round(z * 3.0)), salt)


## {species, variant, scale, yaw} for a tree rooted at world (x, z).
static func pick_variant(x: float, z: float, want: int = Species.AUTO) -> Dictionary:
	var sp := want
	if sp == Species.AUTO:
		var r := _h(x, z, 3)
		if r < 0.42:
			sp = Species.BROADLEAF
		elif r < 0.64:
			sp = Species.OAK
		elif r < 0.9:
			sp = Species.CONIFER
		else:
			sp = Species.BUSH
	var variant := int(_h(x, z, 7) * VARIANTS) % VARIANTS
	var s := lerpf(0.8, 0.98, _h(x, z, 11))
	return {"species": sp, "variant": variant, "scale": s, "yaw": _h(x, z, 13) * TAU}


# --- Shared materials ------------------------------------------------------------

static func foliage_material(snow: bool = false) -> Material:
	var path := FOLIAGE_SNOW_MAT if snow else FOLIAGE_MAT
	return load(path) as Material


static func decor_material() -> ShaderMaterial:
	if _decor_mat == null:
		_decor_mat = ShaderMaterial.new()
		_decor_mat.shader = load(DECOR_SHADER)
	return _decor_mat


static func shadow_material() -> ShaderMaterial:
	if _shadow_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
uniform float strength = 0.42;
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(0.1, 1.0, d);
	ALBEDO = vec3(0.02, 0.05, 0.06);
	ALPHA = a * a * strength;
}
"""
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = sh
		_shadow_mat.render_priority = -1
	return _shadow_mat


static func shadow_mesh() -> QuadMesh:
	if _shadow_mesh == null:
		_shadow_mesh = QuadMesh.new()
		_shadow_mesh.size = Vector2(1.7, 1.7)
	return _shadow_mesh


# --- Cached variant meshes -------------------------------------------------------

## [param lod] 1 = low-poly variant (un-subdivided blobs, fewer pine points) for
## distant world-skirt forests: ~4x fewer triangles, same silhouette at range.
static func canopy_mesh_for(sp: int, v: int, lod: int = 0) -> ArrayMesh:
	var key := sp * 16 + v + lod * 1000
	if not _canopy_cache.has(key):
		_build_lod = lod
		_canopy_cache[key] = _build_canopy(sp, v)
		_build_lod = 0
	return _canopy_cache[key]


static var _build_lod: int = 0


static func trunk_mesh_for(sp: int, v: int) -> ArrayMesh:
	var key := sp * 16 + v
	if not _trunk_cache.has(key):
		_trunk_cache[key] = _build_trunk(sp, v)
	return _trunk_cache[key]


static func _r(v: int, salt: int) -> float:
	return ProcMesh.hash01(v * 31 + 7, salt, 91)


static func _build_canopy(sp: int, v: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var conifer_flag := 0.0
	match sp:
		Species.BROADLEAF:
			# Round crown: a big core + a ring of lobes + a top lobe.
			var c := Vector3(0.0, 1.12, 0.0)
			_blob(st, c, 0.47, c, v * 10 + 1, 0.0)
			var lobes := 5
			for i in lobes:
				var a := TAU * float(i) / float(lobes) + _r(v, i) * 0.6
				var rr := 0.34 + _r(v, i + 20) * 0.08
				var lp := c + Vector3(cos(a) * 0.36, -0.12 + _r(v, i + 40) * 0.2, sin(a) * 0.36)
				_blob(st, lp, rr, c, v * 10 + i + 2, 0.0)
			_blob(st, c + Vector3(0.05, 0.32, -0.04), 0.28, c, v * 10 + 9, 0.0)
		Species.OAK:
			# Two tiers of clusters: a broad lower skirt and a smaller crown.
			var c2 := Vector3(0.0, 1.15, 0.0)
			for i in 4:
				var a := TAU * float(i) / 4.0 + 0.4 + _r(v, i) * 0.5
				_blob(st, c2 + Vector3(cos(a) * 0.4, -0.1, sin(a) * 0.4), 0.33, c2, v * 10 + i, 0.0)
			_blob(st, c2 + Vector3(0.0, 0.05, 0.0), 0.42, c2, v * 10 + 5, 0.0)
			for i in 3:
				var a := TAU * float(i) / 3.0 + _r(v, i + 7) * 0.8
				_blob(st, c2 + Vector3(cos(a) * 0.18, 0.42, sin(a) * 0.18), 0.27, c2 + Vector3(0, 0.3, 0), v * 10 + i + 6, 0.0)
		Species.CONIFER, Species.SNOW_PINE:
			conifer_flag = 1.0
			var tiers := 4
			var base_y := 0.45
			var top_y := 1.95 - _r(v, 3) * 0.2
			for t in tiers:
				var f := float(t) / float(tiers)
				var y0 := lerpf(base_y, top_y - 0.55, f)
				var rad := lerpf(0.66, 0.26, f) * (0.95 + _r(v, t) * 0.1)
				var h := lerpf(0.62, 0.5, f)
				_cone_tier(st, Vector3(0.0, y0, 0.0), rad, h, v * 7 + t)
			_cone_tier(st, Vector3(0.0, top_y - 0.5, 0.0), 0.2, 0.55, v * 7 + 9)
		Species.BUSH:
			var c3 := Vector3(0.0, 0.34, 0.0)
			_blob(st, c3, 0.38, c3, v * 5 + 1, 0.0)
			for i in 3:
				var a := TAU * float(i) / 3.0 + _r(v, i) * 0.9
				_blob(st, c3 + Vector3(cos(a) * 0.32, -0.08, sin(a) * 0.32), 0.27, c3, v * 5 + i + 2, 0.0)
	var m := st.commit()
	_set_conifer_colour(m, conifer_flag)
	return m


## Write COLOR.r = conifer flag on every vertex (foliage shader palette switch).
static func _set_conifer_colour(m: ArrayMesh, flag: float) -> void:
	if m.get_surface_count() == 0:
		return
	var arrays := m.surface_get_arrays(0)
	var n: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var cols := PackedColorArray()
	cols.resize(n)
	cols.fill(Color(flag, 0.0, 0.0, 1.0))
	arrays[Mesh.ARRAY_COLOR] = cols
	m.clear_surfaces()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## A lumpy icosphere blob (1 subdivision). Normals are "spherized" toward the whole
## crown's centre [param crown] so clusters shade as one soft painted mass.
static func _blob(st: SurfaceTool, centre: Vector3, radius: float, crown: Vector3, salt: int, _unused: float) -> void:
	var tris := _icosphere_tris(_build_lod)
	for tri in tris:
		var pts: Array = []
		var nrms: Array = []
		for dir in tri:
			var d: Vector3 = dir
			var bump := 0.86 + 0.28 * ProcMesh.hash01(int(d.x * 97.0) + salt, int(d.y * 89.0), int(d.z * 83.0))
			var p := centre + d * radius * bump
			# Flatten the underside a little (crowns sit on their lower lobes).
			if d.y < -0.3:
				p.y = lerpf(p.y, centre.y - radius * 0.45, 0.5)
			pts.append(p)
			var sph := (p - crown).normalized()
			nrms.append((d * 0.45 + sph * 0.55).normalized())
		for k in 3:
			st.set_normal(nrms[k])
			st.add_vertex(pts[k])


static var _ico: Array = []
static var _ico_low: Array = []

static func _icosphere_tris(lod: int = 0) -> Array:
	if lod > 0 and not _ico_low.is_empty():
		return _ico_low
	if lod == 0 and not _ico.is_empty():
		return _ico
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts := [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in verts.size():
		verts[i] = (verts[i] as Vector3).normalized()
	var faces := [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for f in faces:
		var a: Vector3 = verts[f[0]]
		var b: Vector3 = verts[f[1]]
		var c: Vector3 = verts[f[2]]
		var ab := ((a + b) * 0.5).normalized()
		var bc := ((b + c) * 0.5).normalized()
		var ca := ((c + a) * 0.5).normalized()
		var subtris := [[a, b, c]] if lod > 0 else [[a, ab, ca], [b, bc, ab], [c, ca, bc], [ab, bc, ca]]
		# Wind so the outward face is front-facing (Godot: clockwise).
		for tri in subtris:
			var p0: Vector3 = tri[0]
			var p1: Vector3 = tri[1]
			var p2: Vector3 = tri[2]
			var nrm := (p1 - p0).cross(p2 - p0)
			var out_list: Array = _ico_low if lod > 0 else _ico
			if nrm.dot(p0 + p1 + p2) > 0.0:
				out_list.append([p0, p2, p1])
			else:
				out_list.append([p0, p1, p2])
	return _ico_low if lod > 0 else _ico


## One drooping pine tier: a cone whose rim alternates long / short points.
static func _cone_tier(st: SurfaceTool, base: Vector3, radius: float, height: float, salt: int) -> void:
	var n := 10 if _build_lod == 0 else 6
	var apex := base + Vector3(0.0, height, 0.0)
	var rim: Array = []
	for i in n:
		var a := TAU * float(i) / float(n) + ProcMesh.hash01(salt, i, 5) * 0.2
		var long := (i % 2 == 0)
		var rr := radius * (1.0 if long else 0.72)
		var dy := -0.08 if long else 0.04
		rim.append(base + Vector3(cos(a) * rr, dy, sin(a) * rr))
	var under := base + Vector3(0.0, height * 0.18, 0.0)
	for i in n:
		var p0: Vector3 = rim[i]
		var p1: Vector3 = rim[(i + 1) % n]
		# Outer face.
		_tri_sph(st, apex, p0, p1, base + Vector3(0, height * 0.4, 0), true)
		# Underside (shadowed).
		_tri_sph(st, under, p1, p0, base + Vector3(0, height * 0.9, 0), false)


static func _tri_sph(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Vector3, outward: bool) -> void:
	var face := (b - a).cross(c - a).normalized()
	var mid := (a + b + c) / 3.0
	var want := (mid - centre).normalized()
	if not outward:
		want = Vector3.DOWN
	var p1 := b
	var p2 := c
	if face.dot(want) > 0.0:
		p1 = c
		p2 = b
	for p in [a, p1, p2]:
		var pv: Vector3 = p
		var sph := (pv - centre).normalized()
		var nrm := (sph * 0.6 + want * 0.4).normalized() if outward else (Vector3.DOWN * 0.7 + sph * 0.3).normalized()
		st.set_normal(nrm)
		st.add_vertex(pv)


static func _build_trunk(sp: int, v: int) -> ArrayMesh:
	var pm := _TrunkMesh.new()
	match sp:
		Species.BUSH:
			pm.trunk(0.0, 0.18, 0.09, 0.05, v, 0)
		Species.CONIFER, Species.SNOW_PINE:
			pm.trunk(0.0, 1.2, 0.13, 0.05, v, 4)
		Species.OAK:
			pm.trunk(0.0, 1.0, 0.16, 0.09, v, 5)
			pm.branch(Vector3(0, 0.72, 0), Vector3(0.36, 1.05, 0.1), 0.06)
			pm.branch(Vector3(0, 0.8, 0), Vector3(-0.3, 1.1, -0.18), 0.05)
		_:
			pm.trunk(0.0, 1.0, 0.14, 0.07, v, 5)
			pm.branch(Vector3(0, 0.78, 0), Vector3(0.26, 1.08, -0.12), 0.05)
	return pm.commit()


## Tiny helper for the tapered trunk + root flare, vertex-coloured bark.
class _TrunkMesh:
	var st := SurfaceTool.new()

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Quad a-b-c-d facing [param out] (winding fixed up like ProcMesh._tri).
	func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, out: Vector3 = Vector3.ZERO) -> void:
		if out == Vector3.ZERO:
			var centre := (a + b + c + d) * 0.25
			out = Vector3(centre.x, 0.0, centre.z).normalized()
			if out == Vector3.ZERO:
				out = Vector3.UP
		_tri(a, b, c, out, ca, cb, cc)
		_tri(a, c, d, out, ca, cc, cd)

	func _tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		if n.dot(out) < 0.0:
			var t := b; b = c; c = t
			var tc := cb; cb = cc; cc = tc
		var nrm := out.normalized()
		# Godot front faces are clockwise: emit reversed.
		_v(a, nrm, ca); _v(c, nrm, cc); _v(b, nrm, cb)

	func _v(p: Vector3, n: Vector3, c: Color) -> void:
		st.set_color(c)
		st.set_normal(n)
		st.add_vertex(p)

	func trunk(y0: float, y1: float, r0: float, r1: float, v: int, roots: int) -> void:
		var sides := 6
		var rings := 3
		for k in rings:
			var fa := float(k) / float(rings)
			var fb := float(k + 1) / float(rings)
			var ya := lerpf(y0, y1, fa)
			var yb := lerpf(y0, y1, fb)
			var ra := lerpf(r0, r1, fa)
			var rb := lerpf(r0, r1, fb)
			var bend_a := Vector3(sin(fa * 2.0 + v) * 0.03, 0, cos(fa * 1.7 + v) * 0.03)
			var bend_b := Vector3(sin(fb * 2.0 + v) * 0.03, 0, cos(fb * 1.7 + v) * 0.03)
			var col_a := TreeBuilder.BARK_DARK.lerp(TreeBuilder.BARK_MID, fa)
			var col_b := TreeBuilder.BARK_DARK.lerp(TreeBuilder.BARK_MID, fb)
			for i in sides:
				var a0 := TAU * float(i) / float(sides)
				var a1 := TAU * float(i + 1) / float(sides)
				var lit := TreeBuilder.BARK_LIGHT if i % 2 == 0 else TreeBuilder.BARK_MID
				var p00 := Vector3(cos(a0) * ra, ya, sin(a0) * ra) + bend_a
				var p10 := Vector3(cos(a1) * ra, ya, sin(a1) * ra) + bend_a
				var p11 := Vector3(cos(a1) * rb, yb, sin(a1) * rb) + bend_b
				var p01 := Vector3(cos(a0) * rb, yb, sin(a0) * rb) + bend_b
				_quad(p00, p10, p11, p01, col_a, col_a, col_b.lerp(lit, 0.4), col_b.lerp(lit, 0.4))
		# Root flare: low wedges spreading from the base.
		for i in roots:
			var a := TAU * float(i) / float(roots) + ProcMesh.hash01(v, i, 3) * 0.5
			var dir := Vector3(cos(a), 0.0, sin(a))
			var side := Vector3(-dir.z, 0.0, dir.x)
			var foot := dir * (r0 + 0.16 + ProcMesh.hash01(v, i, 9) * 0.08)
			var top := dir * r0 * 0.7 + Vector3(0, 0.2, 0)
			var bl := dir * r0 * 0.8 - side * 0.06
			var br := dir * r0 * 0.8 + side * 0.06
			var f := foot + Vector3(0, 0.0, 0)
			_tri(bl, f, top, -side + dir * 0.5 + Vector3.UP * 0.3, TreeBuilder.BARK_DARK, TreeBuilder.BARK_DARK, TreeBuilder.BARK_MID)
			_tri(f, br, top, side + dir * 0.5 + Vector3.UP * 0.3, TreeBuilder.BARK_DARK, TreeBuilder.BARK_DARK, TreeBuilder.BARK_MID)

	func branch(a: Vector3, b: Vector3, r: float) -> void:
		var dir := (b - a).normalized()
		var side := dir.cross(Vector3.UP).normalized() * r
		var up := side.cross(dir).normalized() * r
		var ring := [side, up, -side, -up]
		for i in 4:
			var s0: Vector3 = ring[i]
			var s1: Vector3 = ring[(i + 1) % 4]
			_quad(a + s0, a + s1, b + s1 * 0.4, b + s0 * 0.4, TreeBuilder.BARK_MID, TreeBuilder.BARK_MID, TreeBuilder.BARK_LIGHT, TreeBuilder.BARK_LIGHT, (s0 + s1).normalized())

	func commit() -> ArrayMesh:
		return st.commit()
