@tool
extends Node3D
class_name LowPolyTileBuilder

## Chunky low-poly forest tile. A helper node under a tile scene that, at load,
## builds faceted geometry for the grass-on-dirt block look:
##   * CAP  -> replaces the sibling "MeshInstance3D" box mesh with a faceted grass
##            cap. That MeshInstance3D is the surface tile.gd drives with the tile's
##            material (the green stylized_grass shader), so the cap renders GREEN
##            and stays highlightable -- we only swap its GEOMETRY, never its material.
##   * DIRT base + ROCKS + grass TUFTS -> one vertex-coloured, flat-shaded ArrayMesh
##            on a child node, so the sides read as a chunky diorama block at edges.
##
## Flat/faceted: each triangle carries its own face normal (verts are not shared
## across faces). Variation is DETERMINISTIC (an LCG seeded from the tile's world
## XZ) -- no Math.random / Time, so the board never flickers.

enum Style { GRASS, TALL_GRASS, DIRT, MEADOW, TREE }
@export var style: Style = Style.GRASS

const HALF: float = 1.0
const CAP_TOP: float = 0.10        # walkable surface == UNIT_GROUND_Y
const CAP_LIP: float = -0.05       # cap skirt bottom (slight overhang lip)
const DIRT_TOP: float = 0.02
const DIRT_BOTTOM: float = -0.7
const DIRT_HALF: float = 0.94      # inset so the green cap overhangs the dirt

const DIRT_COLOR: Color = Color(0.82, 0.55, 0.35, 1.0)   # warm tan (like the ref)
const DIRT_DARK: Color = Color(0.66, 0.42, 0.26, 1.0)
const ROCK_COLOR: Color = Color(0.86, 0.86, 0.83, 1.0)   # light stone
const TUFT_COLOR: Color = Color(0.42, 0.78, 0.30, 1.0)

var _rng: int = 1
static var _decor_mat: StandardMaterial3D = null


func _ready() -> void:
	_rng = (_seed() | 1) & 0x7fffffff

	var cap := get_node_or_null("../MeshInstance3D") as MeshInstance3D
	if cap != null:
		cap.mesh = _build_cap()
		cap.rotation = Vector3(0.0, deg_to_rad(90.0 * float(_seed() % 4)), 0.0)

	var decor := get_node_or_null("Decor") as MeshInstance3D
	if decor == null:
		decor = MeshInstance3D.new()
		decor.name = "Decor"
		add_child(decor)
	decor.mesh = _build_decor()
	decor.material_override = _get_decor_mat()


# --- Deterministic RNG ------------------------------------------------------

func _seed() -> int:
	var ix: int = int(round(global_position.x))
	var iz: int = int(round(global_position.z))
	var h: int = (ix * 73856093) ^ (iz * 19349663)
	return absi(h) % 1000000 + 1

func _rand() -> float:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return float(_rng) / float(0x7fffffff)

func _rand_range(lo: float, hi: float) -> float:
	return lo + (hi - lo) * _rand()


# --- Cap (faceted grass top; coloured GREEN by the sibling's shader material) --

func _build_cap() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var subdiv: int = 4

	# Top grid: perimeter pinned flat at CAP_TOP (seamless tiling), interior jittered.
	var pts: Array = []
	for iz in range(subdiv + 1):
		var row: Array = []
		for ix in range(subdiv + 1):
			var fx: float = -HALF + 2.0 * HALF * float(ix) / float(subdiv)
			var fz: float = -HALF + 2.0 * HALF * float(iz) / float(subdiv)
			var y: float = CAP_TOP
			if ix != 0 and ix != subdiv and iz != 0 and iz != subdiv:
				y = CAP_TOP + _cap_jitter(ix, iz)
			row.append(Vector3(fx, y, fz))
		pts.append(row)

	for iz in range(subdiv):
		for ix in range(subdiv):
			var p00: Vector3 = pts[iz][ix]
			var p10: Vector3 = pts[iz][ix + 1]
			var p11: Vector3 = pts[iz + 1][ix + 1]
			var p01: Vector3 = pts[iz + 1][ix]
			_tri(v, n, null, p00, p11, p10, Vector3.UP, Color.WHITE)   # top faces UP
			_tri(v, n, null, p00, p01, p11, Vector3.UP, Color.WHITE)

	# Skirt: from the flat perimeter (CAP_TOP) down to CAP_LIP, facing outward.
	var corners := [
		Vector3(-HALF, CAP_TOP, -HALF), Vector3(HALF, CAP_TOP, -HALF),
		Vector3(HALF, CAP_TOP, HALF), Vector3(-HALF, CAP_TOP, HALF)
	]
	for i in range(4):
		var t0: Vector3 = corners[i]
		var t1: Vector3 = corners[(i + 1) % 4]
		var b0 := Vector3(t0.x, CAP_LIP, t0.z)
		var b1 := Vector3(t1.x, CAP_LIP, t1.z)
		var outward := ((t0 + t1) * 0.5).normalized()
		outward.y = 0.0
		_tri(v, n, null, t0, t1, b1, outward, Color.WHITE)
		_tri(v, n, null, t0, b1, b0, outward, Color.WHITE)

	return _mesh(v, n, null)


func _cap_jitter(ix: int, iz: int) -> float:
	var h: int = (ix * 911) ^ (iz * 677)
	h = (h ^ (h >> 5)) * 2654435761
	var f: float = float(absi(h) % 1000) / 1000.0
	return -0.015 + f * 0.045


# --- Decoration (dirt base + rocks + tufts), vertex-coloured ----------------

func _build_decor() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	# Dirt base: a faceted box from DIRT_TOP down to DIRT_BOTTOM, inset under the cap.
	var d := DIRT_HALF
	var top := DIRT_TOP
	var bot := DIRT_BOTTOM
	var corners_top := [
		Vector3(-d, top, -d), Vector3(d, top, -d), Vector3(d, top, d), Vector3(-d, top, d)]
	var corners_bot := [
		Vector3(-d, bot, -d), Vector3(d, bot, -d), Vector3(d, bot, d), Vector3(-d, bot, d)]
	for i in range(4):
		var t0: Vector3 = corners_top[i]
		var t1: Vector3 = corners_top[(i + 1) % 4]
		var b0: Vector3 = corners_bot[i]
		var b1: Vector3 = corners_bot[(i + 1) % 4]
		var outward := ((t0 + t1) * 0.5)
		outward.y = 0.0
		outward = outward.normalized()
		var shade: Color = DIRT_COLOR if (i % 2 == 0) else DIRT_DARK
		_tri(v, n, c, t0, t1, b1, outward, shade)
		_tri(v, n, c, t0, b1, b0, outward, shade)
	# Dirt bottom cap (so it's solid from below at edges).
	_tri(v, n, c, corners_bot[0], corners_bot[1], corners_bot[2], Vector3.DOWN, DIRT_DARK)
	_tri(v, n, c, corners_bot[0], corners_bot[2], corners_bot[3], Vector3.DOWN, DIRT_DARK)

	# Rocks on the dirt sides. DIRT reads as a stony path, so give it one extra.
	var rock_count: int = 3
	if style == Style.DIRT:
		rock_count = 4
	for r in range(rock_count):
		var side: int = int(_rand() * 4.0) % 4
		var along: float = _rand_range(-0.6, 0.6)
		var yy: float = _rand_range(-0.45, -0.1)
		var pos := Vector3.ZERO
		match side:
			0: pos = Vector3(along, yy, -d)
			1: pos = Vector3(d, yy, along)
			2: pos = Vector3(along, yy, d)
			_: pos = Vector3(-d, yy, along)
		_add_rock(v, n, c, pos, _rand_range(0.12, 0.2))

	# Grass tufts poking up above the cap. Per-style density so each tile reads right:
	#   TALL_GRASS -> dense & tall,  MEADOW -> slightly denser,
	#   TREE       -> a few (tree prop owns the centre),
	#   DIRT       -> 0-2 sparse blades (it's a dirt patch, not grassy).
	var tuft_count: int = 5
	match style:
		Style.TALL_GRASS:
			tuft_count = 9
		Style.MEADOW:
			tuft_count = 7
		Style.TREE:
			tuft_count = 4
		Style.DIRT:
			tuft_count = int(_rand() * 3.0)
	for t in range(tuft_count):
		var bx := _rand_range(-0.7, 0.7)
		var bz := _rand_range(-0.7, 0.7)
		var th := _rand_range(0.14, 0.24)
		if style == Style.TALL_GRASS:
			th = _rand_range(0.4, 0.6)
		_add_tuft(v, n, c, Vector3(bx, CAP_TOP, bz), th)

	return _mesh(v, n, c)


func _add_rock(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, center: Vector3, s: float) -> void:
	# A little faceted octahedron.
	var top := center + Vector3(0, s, 0)
	var bot := center + Vector3(0, -s, 0)
	var ring := [
		center + Vector3(s, 0, 0), center + Vector3(0, 0, s),
		center + Vector3(-s, 0, 0), center + Vector3(0, 0, -s)]
	for i in range(4):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_tri(v, n, c, top, a, b, (((top + a + b) / 3.0) - center), ROCK_COLOR)
		_tri(v, n, c, bot, b, a, (((bot + a + b) / 3.0) - center), ROCK_COLOR)


func _add_tuft(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, base: Vector3, h: float) -> void:
	# A thin tapered 3-sided spike.
	var w: float = 0.05
	var tip := base + Vector3(_rand_range(-0.03, 0.03), h, _rand_range(-0.03, 0.03))
	var b0 := base + Vector3(-w, 0, -w * 0.5)
	var b1 := base + Vector3(w, 0, -w * 0.5)
	var b2 := base + Vector3(0, 0, w)
	_tri(v, n, c, b0, b1, tip, Vector3(0, 0, -1), TUFT_COLOR)
	_tri(v, n, c, b1, b2, tip, Vector3(1, 0, 1).normalized(), TUFT_COLOR)
	_tri(v, n, c, b2, b0, tip, Vector3(-1, 0, 1).normalized(), TUFT_COLOR)


# --- Mesh helpers -----------------------------------------------------------

## Append one flat triangle, winding so its normal points toward [param want].
func _tri(v: PackedVector3Array, n: PackedVector3Array, c, a: Vector3, b: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
	var nrm: Vector3 = (b - a).cross(d - a)
	if nrm.length_squared() < 0.000000001:
		nrm = want
	else:
		nrm = nrm.normalized()
	var bb: Vector3 = b
	var dd: Vector3 = d
	if nrm.dot(want) < 0.0:
		nrm = -nrm
	else:
		# Reverse the winding so the visible (front) face is the side the normal
		# points toward, under Godot's front-face convention. Normal stays = want-ward.
		bb = d
		dd = b
	v.append(a); v.append(bb); v.append(dd)
	n.append(nrm); n.append(nrm); n.append(nrm)
	if c != null:
		c.append(col); c.append(col); c.append(col)


func _mesh(v: PackedVector3Array, n: PackedVector3Array, c) -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.size() == 0:
		return m
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	if c != null:
		arrays[Mesh.ARRAY_COLOR] = c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _get_decor_mat() -> StandardMaterial3D:
	if _decor_mat == null:
		_decor_mat = StandardMaterial3D.new()
		_decor_mat.vertex_color_use_as_albedo = true
		_decor_mat.roughness = 1.0
		_decor_mat.metallic = 0.0
	return _decor_mat
