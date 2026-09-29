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
##
## COST MODEL (story area travel, docs/STORY_MODE.md): computing a skirt is ~350 ms of GDScript
## (a 20 k-vertex heightfield, a chamfer distance field and ~18 k prop candidates), so it is split
## in two:
##   * [method compute] -- PURE DATA (surface arrays + MultiMesh transform buffers) from the
##     board size and the terrain-class mask. Thread-safe, so [method prewarm] runs it on the
##     WorkerThreadPool for a neighbouring area while the player is still walking this one.
##   * [method _apply] -- turns that data into a handful of nodes on the main thread. The
##     meshes / MultiMeshes it makes are kept with the data, so a map built before (a revisited
##     area, a replayed battle board) mounts its skirt from shared resources in well under 1 ms.
## Both caches are keyed by [method TerrainMask.content_key] (board size + tile layout), so an
## edited map never reuses a stale skirt.

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
## How many built skirts are kept (a few MB each incl. GPU buffers).
const DATA_CACHE_SIZE := 6

static var _ground_mat: ShaderMaterial = null
## content key -> skirt data ([method compute] + the "res" parts [method _apply] made), LRU.
static var _data_cache: Dictionary = {}
## content key -> {"id": WorkerThreadPool task id, "out": Dictionary the task fills}.
static var _tasks: Dictionary = {}


## Build a skirt for [param map] (TerrainMask must be published first). Returns null
## on the headless renderer (nothing to see; keeps tests fast).
static func build_for(map: MapResource) -> WorldSkirt:
	if map == null or DisplayServer.get_name() == "headless":
		return null
	var s := WorldSkirt.new()
	s.name = "WorldSkirt"
	s._apply(data_for(map))
	return s


## The skirt data of [param map]: cached, else collected from its in-flight [method prewarm]
## task (waiting for it to finish), else computed right now.
static func data_for(map: MapResource) -> Dictionary:
	var key := TerrainMask.content_key(map)
	if _data_cache.has(key):
		var hit: Dictionary = _data_cache[key]
		_data_cache.erase(key)   # re-insert: most recently used last
		_data_cache[key] = hit
		return hit
	if _tasks.has(key):
		_harvest(key)
		if _data_cache.has(key):
			return _data_cache[key]
	var d := compute(int(map.width), int(map.height), TerrainMask.mask_for(map))
	_store(key, d)
	return d


## Start computing [param map]'s skirt on the WorkerThreadPool (a neighbouring area, while the
## player walks this one). No-op headless, when already cached / queued, or for a null map.
## True when a task was started. Collected by [method poll] or by [method data_for].
static func prewarm(map: MapResource) -> bool:
	if map == null or DisplayServer.get_name() == "headless":
		return false
	var key := TerrainMask.content_key(map)
	if _data_cache.has(key) or _tasks.has(key):
		return false
	# Resolve the tile catalog on the main thread first (the task then only reads it).
	TileCatalog.find_by_id(&"grass_plains")
	var out: Dictionary = {}
	var id: int = WorkerThreadPool.add_task(_prewarm_task.bind(map, out), false, "WorldSkirt.prewarm")
	_tasks[key] = {"id": id, "out": out}
	return true


static func _prewarm_task(map: MapResource, out: Dictionary) -> void:
	var mask := TerrainMask.build_image(map)
	out["mask"] = mask
	out["data"] = compute(int(map.width), int(map.height), mask)


## Collect every finished prewarm task (main thread, once per frame). True while any runs.
static func poll() -> bool:
	for key in _tasks.keys():
		if WorkerThreadPool.is_task_completed(int(_tasks[key]["id"])):
			_harvest(key)
	return not _tasks.is_empty()


## Block until every prewarm task is done and collected (shutdown, tests).
static func finish_pending() -> void:
	for key in _tasks.keys():
		_harvest(key)


static func _harvest(key: int) -> void:
	var t: Dictionary = _tasks[key]
	_tasks.erase(key)
	WorkerThreadPool.wait_for_task_completion(int(t["id"]))
	var out: Dictionary = t["out"]
	if out.has("mask"):
		TerrainMask.store_mask(key, out["mask"])
	if out.has("data"):
		_store(key, out["data"])


static func _store(key: int, d: Dictionary) -> void:
	_data_cache[key] = d
	while _data_cache.size() > DATA_CACHE_SIZE:
		_data_cache.erase(_data_cache.keys()[0])


## True when [param map]'s skirt is already built or being built (tests / perf tools).
static func is_prepared(map: MapResource) -> bool:
	var key := TerrainMask.content_key(map)
	return _data_cache.has(key) or _tasks.has(key)


## Drop every cached skirt (tests / tools).
static func clear_cache() -> void:
	finish_pending()
	_data_cache.clear()


## Mount the nodes for skirt [param data], creating (once) and then sharing its meshes.
func _apply(data: Dictionary) -> void:
	if not data.has("res"):
		data["res"] = _make_resources(data)
		# The meshes / MultiMeshes own copies of the arrays now: keep only what is mounted.
		for k in ["ground", "water", "lava", "buckets", "shadows", "rocks"]:
			data.erase(k)
	for part in data["res"]:
		var p: Dictionary = part
		if p.has("multimesh"):
			var mmi := MultiMeshInstance3D.new()
			mmi.name = p["name"]
			mmi.multimesh = p["multimesh"]
			mmi.material_override = p["material"]
			mmi.cast_shadow = p["shadow"]
			add_child(mmi)
		else:
			var mi := MeshInstance3D.new()
			mi.name = p["name"]
			mi.mesh = p["mesh"]
			mi.material_override = p["material"]
			mi.cast_shadow = p["shadow"]
			add_child(mi)
	print_verbose("[WorldSkirt] %d trees/bushes, %d rocks" % [int(data["tree_count"]), int(data["rock_count"])])
	set_meta(&"tree_count", int(data["tree_count"]))


## Main thread: the meshes / MultiMeshes of skirt [param data], in mount order.
static func _make_resources(data: Dictionary) -> Array:
	var res: Array = []
	var ground := ArrayMesh.new()
	ground.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data["ground"])
	res.append({"name": "Ground", "mesh": ground, "material": ground_material(),
		"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON})
	for liquid in [["water", "Water", WATER_MAT], ["lava", "Lava", LAVA_MAT]]:
		var arrays: Array = data[liquid[0]]
		if arrays.is_empty():
			continue
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		res.append({"name": liquid[1], "mesh": m, "material": load(liquid[2]),
			"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})
	var buckets: Dictionary = data["buckets"]
	for key in buckets.keys():
		var parts := String(key).split("_")
		var sp := int(parts[0])
		var v := int(parts[1])
		var near := int(parts[2]) == 0
		var buf: PackedFloat32Array = buckets[key]
		_add_multimesh(res, "Canopy_" + key, TreeBuilder.canopy_mesh_for(sp, v, 0 if near else 1), TreeBuilder.foliage_material(false), buf, near)
		_add_multimesh(res, "Trunk_" + key, TreeBuilder.trunk_mesh_for(sp, v), TreeBuilder.decor_material(), buf, near)
	_add_multimesh(res, "TreeShadows", TreeBuilder.shadow_mesh(), TreeBuilder.shadow_material(), data["shadows"], false)
	_add_multimesh(res, "Rocks", _rock_mesh(), ProcMesh.material(), data["rocks"], true)
	return res


## 12 floats per instance: the MultiMesh TRANSFORM_3D buffer layout (basis rows + origin).
const FLOATS_PER_XFORM := 12


static func _add_multimesh(res: Array, node_name: String, mesh: Mesh, mat: Material, buf: PackedFloat32Array, shadows_on: bool) -> void:
	if buf.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = buf.size() / FLOATS_PER_XFORM
	mm.buffer = buf
	res.append({"name": node_name, "multimesh": mm, "material": mat,
		"shadow": GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows_on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF})


## Append [param t] to a MultiMesh TRANSFORM_3D buffer (the layout set_instance_transform
## writes: basis row 0, origin.x, basis row 1, origin.y, basis row 2, origin.z).
static func pack_xform(buf: PackedFloat32Array, t: Transform3D) -> void:
	var b := t.basis
	var o := t.origin
	buf.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])


static func ground_material() -> ShaderMaterial:
	if _ground_mat == null:
		_ground_mat = ShaderMaterial.new()
		_ground_mat.shader = load(GROUND_SHADER)
	return _ground_mat


## PURE skirt data for a [param w] x [param h] board whose terrain classes are [param mask]
## ([method TerrainMask.mask_for] / [method TerrainMask.build_image]). Touches no node, no
## resource cache and no static state, so it is safe on a worker thread.
static func compute(w: int, h: int, mask: Image) -> Dictionary:
	var b := _Builder.new(w, h, mask)
	return b.run()


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


## The computation proper (formerly the node's own _build): per-build state in one object so it
## can run anywhere.
class _Builder extends RefCounted:
	var _w: int = 0
	var _h: int = 0
	var _mask: Image = null
	var _noise: FastNoiseLite
	var _hill: FastNoiseLite
	var _water_dist: Dictionary = {}   # Vector2i cell -> cells to nearest water/lava (capped)
	var _heights := PackedFloat32Array()
	var _hi0: int = 0
	var _hj0: int = 0
	var _hcols: int = 0
	var _hrows: int = 0

	func _init(w: int, h: int, mask: Image) -> void:
		_w = maxi(1, w)
		_h = maxi(1, h)
		_mask = mask

	func run() -> Dictionary:
		_noise = FastNoiseLite.new()
		_noise.seed = 1337
		_noise.frequency = 0.035
		_noise.fractal_octaves = 3
		_hill = FastNoiseLite.new()
		_hill.seed = 4242
		_hill.frequency = 0.012
		_compute_water_distance()
		var out: Dictionary = {}
		out["ground"] = _build_ground()
		_build_liquids(out)
		_build_props(out)
		return out

	# --- Terrain queries ---------------------------------------------------------

	func _cls(cx: int, cz: int) -> Color:
		return TerrainMask.class_in(_mask, cx, cz)

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

	# --- Ground heightfield ---------------------------------------------------------

	func _build_ground() -> Array:
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
		return arrays

	# --- Rivers / moats / lava -------------------------------------------------------

	func _build_liquids(out: Dictionary) -> void:
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
		out["water"] = _flat_arrays(water)
		out["lava"] = _flat_arrays(lava)

	func _flat_arrays(v: PackedVector3Array) -> Array:
		if v.is_empty():
			return []
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
		return arrays

	# --- Props (MultiMesh transforms) -------------------------------------------------

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

	func _build_props(out: Dictionary) -> void:
		var buckets: Dictionary = {}   # "sp_v_lod" -> PackedFloat32Array transform buffer
		var shadows := PackedFloat32Array()
		var rocks := PackedFloat32Array()
		var total := 0
		var rock_count := 0
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
						buckets[key] = PackedFloat32Array()
					WorldSkirt.pack_xform(buckets[key], t)
					total += 1
					if o < 45.0:
						WorldSkirt.pack_xform(shadows, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * s), Vector3(jx, y + 0.02, jz)))
				elif r > 0.985 - smoothstep(1.0, 6.0, o) * 0.02:
					var rs := lerpf(0.25, 0.7, ProcMesh.hash01(ix, iz, 5))
					WorldSkirt.pack_xform(rocks, Transform3D(Basis(Vector3.UP, r * 40.0).scaled(Vector3(rs, rs * 0.7, rs)), Vector3(jx, y - 0.05, jz)))
					rock_count += 1
				elif o < 8.0 and r > 0.9:
					# A few bushes near the border for close-up richness (low, no occlusion).
					var key2 := "%d_%d_0" % [TreeBuilder.Species.BUSH, int(r * 100.0) % TreeBuilder.VARIANTS]
					if not buckets.has(key2):
						buckets[key2] = PackedFloat32Array()
					WorldSkirt.pack_xform(buckets[key2], Transform3D(Basis(Vector3.UP, r * 30.0).scaled(Vector3.ONE * 0.8), Vector3(jx, y, jz)))
					total += 1
			x += spacing
			ix += 1
		out["buckets"] = buckets
		out["shadows"] = shadows
		out["rocks"] = rocks
		out["tree_count"] = total
		out["rock_count"] = rock_count
