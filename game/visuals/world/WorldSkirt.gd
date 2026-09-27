extends Node3D
class_name WorldSkirt

## The non-playable LANDSCAPE around the board, so a map never floats in a void.
##
## Built once per map load (MapLoader) from the map data alone, deterministic:
##   * Ground  -- ONE heightfield mesh (2-unit grid aligned to cells) spreading
##                [constant EXTENT] units past every edge. Flush with the board
##                at the border, rolling into gentle hills outward and rising into
##                a horizon ridge far away. It uses the SAME painterly grass / dirt
##                paint as the board (world_skirt.gdshader), dimmed a touch right
##                outside the border and fading into haze_color in the distance.
##   * Water / lava -- edge water / lava cells continue straight out (rivers, moats,
##                lava flows) as flat quads with the board's own water / lava
##                materials (world-space => seamless with the board), valleys carved
##                into the hills around them. Dirt roads continue a few cells.
##   * Props   -- trees, bushes and rocks scattered with deterministic noise-driven
##                density (a clean ring right next to the board stays clear so edge
##                units read), drawn with MultiMesh (a few draw calls total).
##
## NON-INTERACTIVE by construction: no collision shapes, not a "Tile_*" / "Floor_*"
## node, never registered with CombatServices -- picking, pathing, AI, camera bounds
## and floors ignore it. Skipped entirely on the headless (test) renderer.

const EXTENT := 110.0          # world units of landscape beyond each board edge
const STEP := 2.0              # heightfield spacing == one cell
const SKIRT_Y := -0.16         # skirt sits a little BELOW the board (cap 0.10): a readable rim
const BANK_Y := 0.08           # ...except along rivers / lava, flush with the board banks
const WATER_Y := 0.03          # == LowPolyTileBuilder.WATER_TOP
const BED_Y := -0.45
const CLEAR_RING := 2.5        # no trees this close to the board
const GROUND_SHADER := "res://tile_objects/tiles/shaders/world_skirt.gdshader"
const WATER_MAT := "res://tile_objects/tiles/materials/stylized_water_material.tres"
const LAVA_MAT := "res://tile_objects/tiles/materials/stylized_burn_material.tres"

var _w: int = 0
var _h: int = 0
var _noise: FastNoiseLite
var _hill: FastNoiseLite
var _water_dist: Dictionary = {}   # Vector2i cell -> cells to nearest water/lava (capped)
var _heights := PackedFloat32Array()
var _hi0: int = 0
var _hj0: int = 0
var _hcols: int = 0
var _hrows: int = 0
static var _ground_mat: ShaderMaterial = null


## Build a skirt for [param map] (TerrainMask must be published first). Returns null
## on the headless renderer (nothing to see; keeps tests fast).
static func build_for(map: MapResource) -> WorldSkirt:
	if map == null or DisplayServer.get_name() == "headless":
		return null
	var s := WorldSkirt.new()
	s.name = "WorldSkirt"
	s._build(map)
	return s


func _build(map: MapResource) -> void:
	_w = maxi(1, int(map.width))
	_h = maxi(1, int(map.height))
	_noise = FastNoiseLite.new()
	_noise.seed = 1337
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_hill = FastNoiseLite.new()
	_hill.seed = 4242
	_hill.frequency = 0.012
	_compute_water_distance()
	_build_ground()
	_build_liquids()
	_build_props()


# --- Terrain queries -------------------------------------------------------------

func _cls(cx: int, cz: int) -> Color:
	return TerrainMask.class_at(cx, cz)


func _outside(x: float, z: float) -> float:
	var dx := maxf(maxf(-x, x - _w * STEP), 0.0)
	var dz := maxf(maxf(-z, z - _h * STEP), 0.0)
	return Vector2(dx, dz).length()


func _cell_inside(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < _w and cz < _h


## Chamfer distance (in cells) from every skirt cell to the nearest liquid cell.
func _compute_water_distance() -> void:
	var n := int(EXTENT / STEP) + 2
	var x0 := -n
	var z0 := -n
	var x1 := _w + n
	var z1 := _h + n
	var cap := 8.0
	var d: Dictionary = {}
	for cz in range(z0, z1):
		for cx in range(x0, x1):
			var c := _cls(cx, cz)
			d[Vector2i(cx, cz)] = 0.0 if (c.r > 0.5 or c.b > 0.5) else cap
	for pass_i in 2:
		var zr := range(z0, z1) if pass_i == 0 else range(z1 - 1, z0 - 1, -1)
		var xr := range(x0, x1) if pass_i == 0 else range(x1 - 1, x0 - 1, -1)
		var s := 1 if pass_i == 0 else -1
		for cz in zr:
			for cx in xr:
				var k := Vector2i(cx, cz)
				var best: float = d[k]
				for o in [Vector2i(-s, 0), Vector2i(0, -s), Vector2i(-s, -s), Vector2i(s, -s)]:
					var nk: Vector2i = k + o
					if d.has(nk):
						var step := 1.0 if (o.x == 0 or o.y == 0) else 1.41
						best = minf(best, float(d[nk]) + step)
				d[k] = best
	_water_dist = d


## Liquid weight at a heightfield vertex (grid corner): mean of its 4 cells.
func _liquid_at_vertex(i: int, j: int) -> float:
	var s := 0.0
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var c := _cls(i + o.x, j + o.y)
		s += maxf(c.r, c.b)
	return s * 0.25


func _water_dist_at_vertex(i: int, j: int) -> float:
	var best := 8.0
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		best = minf(best, float(_water_dist.get(Vector2i(i + o.x, j + o.y), 8.0)))
	return best


func height_at_vertex(i: int, j: int) -> float:
	var x := i * STEP
	var z := j * STEP
	var o := _outside(x, z)
	var h := SKIRT_Y
	var rolling := (_noise.get_noise_2d(x, z) * 0.5 + 0.5)
	h += rolling * 2.6 * smoothstep(3.0, 24.0, o)
	var ridge := smoothstep(38.0, EXTENT, o)
	h += ridge * ridge * (9.0 + 7.0 * (_hill.get_noise_2d(x, z) * 0.5 + 0.5))
	# Valleys toward rivers / lava so they never cut through a hill.
	var wd := _water_dist_at_vertex(i, j)
	h = lerpf(BANK_Y, h, smoothstep(1.5, 5.0, wd))
	var liquid := _liquid_at_vertex(i, j)
	if liquid > 0.0:
		# A straight shoreline vertex (half liquid) sits just under the surface so the
		# bank rises out of the water within a fraction of a cell; open water is deep.
		if liquid < 0.99:
			h = lerpf(BANK_Y, WATER_Y - 0.012, smoothstep(0.2, 0.5, liquid))
		else:
			h = BED_Y
	return h


# --- Ground heightfield -----------------------------------------------------------

func _build_ground() -> void:
	var n := int(EXTENT / STEP)
	var i0 := -n
	var j0 := -n
	var i1 := _w + n
	var j1 := _h + n
	var cols := i1 - i0 + 1
	var rows := j1 - j0 + 1
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			heights[(j - j0) * cols + (i - i0)] = height_at_vertex(i, j)
	_heights = heights
	_hi0 = i0
	_hj0 = j0
	_hcols = cols
	_hrows = rows
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize(cols * rows)
	norms.resize(cols * rows)
	for j in range(rows):
		for i in range(cols):
			var hh := heights[j * cols + i]
			verts[j * cols + i] = Vector3((i + i0) * STEP, hh, (j + j0) * STEP)
			var hl := heights[j * cols + maxi(i - 1, 0)]
			var hr := heights[j * cols + mini(i + 1, cols - 1)]
			var hd := heights[maxi(j - 1, 0) * cols + i]
			var hu := heights[mini(j + 1, rows - 1) * cols + i]
			norms[j * cols + i] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
	var idx := PackedInt32Array()
	for j in range(rows - 1):
		for i in range(cols - 1):
			var cx := i + i0
			var cz := j + j0
			if _cell_inside(cx, cz):
				continue  # the board itself
			var a := j * cols + i
			var b := a + 1
			var c := a + cols
			var d := c + 1
			# Clockwise front faces seen from above.
			idx.append_array([a, b, d, a, d, c])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = ground_material()
	add_child(mi)


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = load(GROUND_SHADER)
	return _ground_mat


# --- Rivers / moats / lava ---------------------------------------------------------

func _build_liquids() -> void:
	var n := int(EXTENT / STEP)
	var water := PackedVector3Array()
	var lava := PackedVector3Array()
	for cz in range(-n, _h + n):
		for cx in range(-n, _w + n):
			if _cell_inside(cx, cz):
				continue
			# Any liquid in the 3x3 neighbourhood: cover the bank too so the slope
			# below the waterline is always under a surface.
			var wv := 0.0
			var lv := 0.0
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var c := _cls(cx + ox, cz + oz)
					wv = maxf(wv, c.r)
					lv = maxf(lv, c.b)
			if wv < 0.5 and lv < 0.5:
				continue
			var x0 := cx * STEP
			var z0 := cz * STEP
			var quad := [Vector3(x0, WATER_Y, z0), Vector3(x0 + STEP, WATER_Y, z0),
				Vector3(x0 + STEP, WATER_Y, z0 + STEP), Vector3(x0, WATER_Y, z0 + STEP)]
			var target := water if wv >= lv else lava
			target.append_array([quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]])
	_add_flat(water, "Water", WATER_MAT)
	_add_flat(lava, "Lava", LAVA_MAT)


func _add_flat(v: PackedVector3Array, node_name: String, mat_path: String) -> void:
	if v.is_empty():
		return
	var norms := PackedVector3Array()
	norms.resize(v.size())
	norms.fill(Vector3.UP)
	var uvs := PackedVector2Array()
	uvs.resize(v.size())
	for k in v.size():
		uvs[k] = Vector2(v[k].x, v[k].z) * 0.5
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = load(mat_path)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- Props (MultiMesh) --------------------------------------------------------------

func _ground_h(x: float, z: float) -> float:
	# Bilinear on the vertex heights.
	var fi := x / STEP
	var fj := z / STEP
	var i := int(floor(fi))
	var j := int(floor(fj))
	var tx := fi - i
	var tz := fj - j
	var h00 := _hv(i, j)
	var h10 := _hv(i + 1, j)
	var h01 := _hv(i, j + 1)
	var h11 := _hv(i + 1, j + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _hv(i: int, j: int) -> float:
	var a := clampi(i - _hi0, 0, _hcols - 1)
	var b := clampi(j - _hj0, 0, _hrows - 1)
	return _heights[b * _hcols + a]


func _build_props() -> void:
	var buckets: Dictionary = {}   # "sp_v" -> Array[Transform3D]
	var shadows: Array = []
	var rocks: Array = []
	var spacing := 2.0
	var reach := EXTENT - 8.0
	var x := -reach
	var ix := 0
	while x < _w * STEP + reach:
		var z := -reach
		var iz := 0
		while z < _h * STEP + reach:
			var jx := x + (ProcMesh.hash01(ix, iz, 1) - 0.5) * spacing * 0.9
			var jz := z + (ProcMesh.hash01(ix, iz, 2) - 0.5) * spacing * 0.9
			z += spacing
			iz += 1
			var o := _outside(jx, jz)
			if o <= 0.6:
				continue
			var cx := int(floor(jx / STEP))
			var cz := int(floor(jz / STEP))
			var c := _cls(cx, cz)
			if c.r > 0.1 or c.b > 0.1 or c.g > 0.3:
				continue
			if float(_water_dist.get(Vector2i(cx, cz), 8.0)) < 1.0:
				continue
			var r := ProcMesh.hash01(ix, iz, 3)
			# Forest clumps: noise field thresholded, denser a little way out.
			var forest := _noise.get_noise_2d(jx * 1.7 + 50.0, jz * 1.7) * 0.5 + 0.5
			var density := smoothstep(0.45, 0.62, forest) * smoothstep(CLEAR_RING, 7.0, o)
			density *= 1.0 - smoothstep(40.0, 85.0, o) * 0.7
			var y := _ground_h(jx, jz)
			if r < density:
				var pick := TreeBuilder.pick_variant(jx, jz)
				var key := "%d_%d_%d" % [pick["species"], pick["variant"], 0 if o < 30.0 else 1]
				var s: float = float(pick["scale"]) * lerpf(1.0, 1.5, smoothstep(10.0, 60.0, o))
				var t := Transform3D(Basis(Vector3.UP, pick["yaw"]).scaled(Vector3.ONE * s), Vector3(jx, y, jz))
				if not buckets.has(key):
					buckets[key] = []
				buckets[key].append(t)
				if o < 45.0:
					shadows.append(Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * s), Vector3(jx, y + 0.02, jz)))
			elif r > 0.985 - smoothstep(1.0, 6.0, o) * 0.02:
				var rs := lerpf(0.25, 0.7, ProcMesh.hash01(ix, iz, 5))
				rocks.append(Transform3D(Basis(Vector3.UP, r * 40.0).scaled(Vector3(rs, rs * 0.7, rs)), Vector3(jx, y - 0.05, jz)))
			elif o < 8.0 and r > 0.9:
				# A few bushes near the border for close-up richness (low, no occlusion).
				var key2 := "%d_%d_0" % [TreeBuilder.Species.BUSH, int(r * 100.0) % TreeBuilder.VARIANTS]
				if not buckets.has(key2):
					buckets[key2] = []
				buckets[key2].append(Transform3D(Basis(Vector3.UP, r * 30.0).scaled(Vector3.ONE * 0.8), Vector3(jx, y, jz)))
		x += spacing
		ix += 1
	for key in buckets.keys():
		var parts := String(key).split("_")
		var sp := int(parts[0])
		var v := int(parts[1])
		var near := int(parts[2]) == 0
		var list: Array = buckets[key]
		_add_multimesh("Canopy_" + key, TreeBuilder.canopy_mesh_for(sp, v), TreeBuilder.foliage_material(false), list, near)
		_add_multimesh("Trunk_" + key, TreeBuilder.trunk_mesh_for(sp, v), TreeBuilder.decor_material(), list, near)
	_add_multimesh("TreeShadows", TreeBuilder.shadow_mesh(), TreeBuilder.shadow_material(), shadows, false)
	_add_multimesh("Rocks", _rock_mesh(), ProcMesh.material(), rocks, true)


func _add_multimesh(node_name: String, mesh: Mesh, mat: Material, xforms: Array, shadows_on: bool) -> void:
	if xforms.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


static var _rock: ArrayMesh = null

static func _rock_mesh() -> ArrayMesh:
	if _rock != null:
		return _rock
	# Two lumpy, flattened icosphere boulders (a big one + a companion stone).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in [[Vector3.ZERO, Vector3(0.62, 0.42, 0.5), 3], [Vector3(0.55, -0.05, 0.3), Vector3(0.3, 0.22, 0.26), 9]]:
		var c: Vector3 = part[0]
		var sc: Vector3 = part[1]
		for tri in TreeBuilder._icosphere_tris():
			var pts: Array = []
			for dir in tri:
				var d: Vector3 = dir
				var k := 0.82 + 0.3 * ProcMesh.hash01(int(d.x * 71.0) + part[2], int(d.y * 67.0), int(d.z * 61.0))
				pts.append(c + Vector3(d.x * sc.x, maxf(d.y, -0.2) * sc.y, d.z * sc.z) * k + Vector3(0, sc.y * 0.2, 0))
			var n: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0]).normalized() * -1.0
			var shade := 0.5 + 0.12 * ProcMesh.hash01(int(pts[0].x * 50.0), int(pts[0].z * 50.0), 3)
			var col := Color(shade, shade * 0.97, shade * 0.9) if n.y < 0.7 else Color(0.42, 0.5, 0.33)
			for p in pts:
				st.set_color(col)
				st.set_normal(n)
				st.add_vertex(p)
	_rock = st.commit()
	return _rock
