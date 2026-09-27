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

# Layered soil sides: a dark humus band under the grass lip, warm earth in the
# middle, a cooler clay base. Two shades per band alternate by face so the block
# still reads as faceted under flat lighting.
const DIRT_COLOR: Color = Color(0.55, 0.37, 0.23, 1.0)   # warm earth (mid band)
const DIRT_DARK: Color = Color(0.45, 0.29, 0.18, 1.0)
const HUMUS_COLOR: Color = Color(0.30, 0.21, 0.14, 1.0)  # dark top band
const HUMUS_DARK: Color = Color(0.24, 0.17, 0.11, 1.0)
const CLAY_COLOR: Color = Color(0.47, 0.36, 0.27, 1.0)   # cooler bottom band
const CLAY_DARK: Color = Color(0.39, 0.29, 0.22, 1.0)
const HUMUS_BOTTOM: float = -0.16
const CLAY_TOP: float = -0.48
const ROCK_COLOR: Color = Color(0.74, 0.73, 0.68, 1.0)   # weathered stone
const ROCK_DARK: Color = Color(0.58, 0.57, 0.53, 1.0)

# Short-grass tuft gradient (opaque): shadowed base -> leaf green -> sunlit tip.
# Each tuft picks a lush or a sun-dried variant so the field isn't uniform.
const TUFT_BASE: Color = Color(0.10, 0.27, 0.12, 1.0)
const TUFT_MID: Color = Color(0.25, 0.50, 0.21, 1.0)
const TUFT_TIP: Color = Color(0.55, 0.74, 0.32, 1.0)
const TUFT_TIP_DRY: Color = Color(0.72, 0.74, 0.38, 1.0)
const FLOWER_COLORS: Array[Color] = [
	Color(0.97, 0.96, 0.90, 1.0),   # daisy white
	Color(0.99, 0.83, 0.30, 1.0),   # buttercup yellow
	Color(0.80, 0.68, 0.97, 1.0),   # lilac
]
const FLOWER_CENTRE: Color = Color(0.96, 0.66, 0.16, 1.0)
const STEM_COLOR: Color = Color(0.20, 0.42, 0.18, 1.0)

# Tall-grass blade gradient: a dark green base rising to a bright, faintly
# yellow-green tip -- the stylized "clump of pointed blades" look. Applied per
# vertex (base verts dark, tip vert bright) so each blade reads as lit-from-above
# even under flat shading, matching the reference tuft art.
# Alpha < 1 so a unit standing in the tall grass shows THROUGH the blades instead of
# being hidden behind them -- denser (more opaque) at the shadowed base, airier at the
# lit tips. Only the tall-grass blade mesh uses these; dirt/rocks stay fully opaque.
const GRASS_BLADE_BASE: Color = Color(0.06, 0.30, 0.11, 0.92)  # deep shadowed green
const GRASS_BLADE_MID: Color = Color(0.18, 0.55, 0.20, 0.82)   # mid leaf green
const GRASS_BLADE_TIP: Color = Color(0.44, 0.82, 0.32, 0.68)   # bright (but still green) lit tip

var _rng: int = 1
static var _decor_mat: ShaderMaterial = null
static var _grass_mat: StandardMaterial3D = null


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

	# TALL_GRASS grows its blades on a SEPARATE, slightly translucent double-sided mesh:
	# transparency there lets a unit standing in the grass show through, and keeping it
	# off the Decor mesh means the opaque dirt/rocks never join the transparent pass.
	var grass := get_node_or_null("Grass") as MeshInstance3D
	if style == Style.TALL_GRASS:
		if grass == null:
			grass = MeshInstance3D.new()
			grass.name = "Grass"
			add_child(grass)
		grass.mesh = _build_grass_clumps()
		grass.material_override = _get_grass_mat()
	elif grass != null:
		grass.queue_free()


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
			# Grassy caps stay perfectly flat so neighbouring tiles light identically and
			# the field reads seamless; only bare DIRT keeps its lumpy facets.
			if style == Style.DIRT and ix != 0 and ix != subdiv and iz != 0 and iz != subdiv:
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

	# Dirt base: a faceted box from DIRT_TOP down to DIRT_BOTTOM, inset under the cap,
	# built as three soil bands (humus / earth / clay) for a layered cross-section.
	var d := DIRT_HALF
	var top := DIRT_TOP
	var bot := DIRT_BOTTOM
	var corners_bot := [
		Vector3(-d, bot, -d), Vector3(d, bot, -d), Vector3(d, bot, d), Vector3(-d, bot, d)]
	var bands := [
		[top, HUMUS_BOTTOM, HUMUS_COLOR, HUMUS_DARK],
		[HUMUS_BOTTOM, CLAY_TOP, DIRT_COLOR, DIRT_DARK],
		[CLAY_TOP, bot, CLAY_COLOR, CLAY_DARK],
	]
	var xz := [Vector2(-d, -d), Vector2(d, -d), Vector2(d, d), Vector2(-d, d)]
	for band in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		for i in range(4):
			var p0: Vector2 = xz[i]
			var p1: Vector2 = xz[(i + 1) % 4]
			var t0 := Vector3(p0.x, y0, p0.y)
			var t1 := Vector3(p1.x, y0, p1.y)
			var b0 := Vector3(p0.x, y1, p0.y)
			var b1 := Vector3(p1.x, y1, p1.y)
			var outward := Vector3((p0.x + p1.x) * 0.5, 0.0, (p0.y + p1.y) * 0.5).normalized()
			var shade: Color = band[2] if (i % 2 == 0) else band[3]
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

	# Grass on top. TALL_GRASS builds its lush blade-CLUMPS on a SEPARATE translucent
	# mesh (see _ready / _build_grass_clumps), so here we only add the simple opaque
	# single-spike tufts the other grassy styles use, at per-style density:
	#   MEADOW -> slightly denser,  TREE -> a few (tree prop owns the centre),
	#   DIRT   -> 0-2 sparse blades (it's a dirt patch, not grassy).
	if style != Style.TALL_GRASS:
		var tuft_count: int = 8
		var flower_chance: float = 0.45
		match style:
			Style.MEADOW:
				tuft_count = 10
				flower_chance = 0.9
			Style.TREE:
				tuft_count = 5
				flower_chance = 0.2
			Style.DIRT:
				tuft_count = int(_rand() * 3.0)
				flower_chance = 0.0
		for t in range(tuft_count):
			var bx: float = _rand_range(-0.78, 0.78)
			var bz: float = _rand_range(-0.78, 0.78)
			var th: float = _rand_range(0.13, 0.27)
			_add_blade_tuft(v, n, c, Vector3(bx, CAP_TOP, bz), th)
		# A couple of wildflowers and the odd pebble for visual interest.
		var flowers: int = 0
		if _rand() < flower_chance:
			flowers = 1 + int(_rand() * 2.0)
		for f in range(flowers):
			var fx: float = _rand_range(-0.7, 0.7)
			var fz: float = _rand_range(-0.7, 0.7)
			_add_flower(v, n, c, Vector3(fx, CAP_TOP, fz), _rand_range(0.12, 0.2))
		if style != Style.DIRT and _rand() < 0.35:
			var px: float = _rand_range(-0.7, 0.7)
			var pz: float = _rand_range(-0.7, 0.7)
			_add_pebble(v, n, c, Vector3(px, CAP_TOP, pz), _rand_range(0.04, 0.07))

	return _mesh(v, n, c)


## Build the tall-grass blade layer: taller, bushier clumps spread to fill the tile,
## on their own translucent mesh (see _get_grass_mat). Vertex-coloured with alpha so a
## unit shows through. Only called for Style.TALL_GRASS.
func _build_grass_clumps() -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	# More clumps, spread nearly edge to edge, so the tile reads as a full bushy patch.
	var clump_count: int = 6
	for t in range(clump_count):
		var cx: float = _rand_range(-0.74, 0.74)
		var cz: float = _rand_range(-0.74, 0.74)
		var ch: float = _rand_range(0.66, 0.98)   # taller than before
		_add_grass_clump(v, n, c, Vector3(cx, CAP_TOP, cz), ch)
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
		_tri(v, n, c, bot, b, a, (((bot + a + b) / 3.0) - center), ROCK_DARK)


## A short-grass tuft: 3-5 curved, tapered blades fanning out from [param base].
## Each blade is a 3-sided spike in two segments (base ring -> bent mid ring -> tip)
## so it reads as a curved leaf from any angle without double-sided rendering. Tip
## colour is lush or sun-dried per tuft.
func _add_blade_tuft(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, base: Vector3, h: float) -> void:
	var blades: int = 3 + int(_rand() * 3.0)
	var tip_col: Color = TUFT_TIP if _rand() < 0.7 else TUFT_TIP_DRY
	var spin: float = _rand() * TAU
	for i in range(blades):
		var ang: float = spin + TAU * float(i) / float(blades) + _rand_range(-0.4, 0.4)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var bh: float = h * _rand_range(0.7, 1.15)
		var lean: float = bh * _rand_range(0.35, 0.8)
		var w: float = 0.028
		var root: Vector3 = base + dir * 0.02
		var mid: Vector3 = root + dir * (lean * 0.35) + Vector3(0.0, bh * 0.6, 0.0)
		var tip: Vector3 = root + dir * lean + Vector3(0.0, bh, 0.0)
		var ring0 := _ring(root, dir, w)
		var ring1 := _ring(mid, dir, w * 0.55)
		for k in range(3):
			var a0: Vector3 = ring0[k]
			var a1: Vector3 = ring0[(k + 1) % 3]
			var m0: Vector3 = ring1[k]
			var m1: Vector3 = ring1[(k + 1) % 3]
			var out: Vector3 = ((a0 + a1) * 0.5 - root)
			out.y = 0.0
			out = out.normalized() + Vector3(0.0, 0.35, 0.0)
			_tri_grad(v, n, c, a0, a1, m1, out, TUFT_BASE, TUFT_BASE, TUFT_MID)
			_tri_grad(v, n, c, a0, m1, m0, out, TUFT_BASE, TUFT_MID, TUFT_MID)
			_tri_grad(v, n, c, m0, m1, tip, out, TUFT_MID, TUFT_MID, tip_col)


## Three points around [param centre] in the plane across [param dir] (a thin
## triangular cross-section for a blade).
func _ring(centre: Vector3, dir: Vector3, w: float) -> Array:
	var side := Vector3(-dir.z, 0.0, dir.x)
	return [centre + side * w, centre - side * w, centre - dir * w * 0.9]


## A tiny wildflower: a thin stem and a flat five-petal star facing up.
func _add_flower(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, base: Vector3, h: float) -> void:
	var head: Vector3 = base + Vector3(_rand_range(-0.03, 0.03), h, _rand_range(-0.03, 0.03))
	var sw: float = 0.012
	var s0 := base + Vector3(-sw, 0.0, 0.0)
	var s1 := base + Vector3(sw, 0.0, 0.0)
	var s2 := base + Vector3(0.0, 0.0, sw)
	_tri(v, n, c, s0, s1, head, Vector3(0, 0, -1), STEM_COLOR)
	_tri(v, n, c, s1, s2, head, Vector3(1, 0, 1).normalized(), STEM_COLOR)
	_tri(v, n, c, s2, s0, head, Vector3(-1, 0, 1).normalized(), STEM_COLOR)
	var col: Color = FLOWER_COLORS[int(_rand() * float(FLOWER_COLORS.size())) % FLOWER_COLORS.size()]
	var r: float = _rand_range(0.045, 0.065)
	var spin: float = _rand() * TAU
	var centre := head + Vector3(0.0, 0.004, 0.0)
	for i in range(5):
		var a: float = spin + TAU * float(i) / 5.0
		var tip := head + Vector3(cos(a) * r, 0.0, sin(a) * r)
		var l := head + Vector3(cos(a - 0.5) * r * 0.45, 0.0, sin(a - 0.5) * r * 0.45)
		var rr := head + Vector3(cos(a + 0.5) * r * 0.45, 0.0, sin(a + 0.5) * r * 0.45)
		_tri(v, n, c, l, tip, rr, Vector3.UP, col)
		_tri(v, n, c, head, l, rr, Vector3.UP, col)
	var cr: float = r * 0.3
	for i in range(5):
		var a0: float = TAU * float(i) / 5.0
		var a1: float = TAU * float(i + 1) / 5.0
		_tri(v, n, c, centre, centre + Vector3(cos(a0) * cr, 0.0, sin(a0) * cr),
			centre + Vector3(cos(a1) * cr, 0.0, sin(a1) * cr), Vector3.UP, FLOWER_CENTRE)


## A small half-buried pebble on the grass (low faceted dome).
func _add_pebble(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, centre: Vector3, s: float) -> void:
	var top := centre + Vector3(0.0, s * 0.8, 0.0)
	var ring: Array = []
	for i in range(5):
		var a: float = TAU * float(i) / 5.0 + _rand_range(-0.2, 0.2)
		ring.append(centre + Vector3(cos(a) * s * 1.3, 0.0, sin(a) * s))
	for i in range(5):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 5]
		var col: Color = ROCK_COLOR if (i % 2 == 0) else ROCK_DARK
		_tri(v, n, c, top, a, b, ((top + a + b) / 3.0) - centre, col)


## A bushy clump of pointed grass blades fanning out from [param base] to roughly
## [param s] tall -- the tall-grass "tuft" look. Each blade is one flat pointed
## triangle (base wide, tip a point) leaning outward on its own yaw, with a dark
## base -> bright tip vertex gradient, plus one tall upright central blade so the
## clump peaks in the middle like the reference art. The grass material is
## double-sided + translucent (see _get_grass_mat) so the flat blades read from every
## angle and a unit standing in the clump shows through it.
func _add_grass_clump(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, base: Vector3, s: float) -> void:
	var blades: int = 11 + int(_rand() * 4.0)   # 11-14 blades ringing the clump (bushy)
	var wdt: float = 0.06                        # half-width of a blade base
	for i in range(blades):
		var ang: float = TAU * float(i) / float(blades) + _rand_range(-0.35, 0.35)
		var lean: float = _rand_range(0.12, 0.36)          # how far the tip leans out
		var bh: float = s * _rand_range(0.68, 1.16)        # this blade's height
		var dx: float = cos(ang)
		var dz: float = sin(ang)
		var tip: Vector3 = base + Vector3(dx * lean, bh, dz * lean)
		var perp: Vector3 = Vector3(-dz, 0.0, dx) * wdt    # blade width across its lean
		var b0: Vector3 = base - perp
		var b1: Vector3 = base + perp
		_tri_grad(v, n, c, b0, b1, tip, Vector3.UP,
			GRASS_BLADE_BASE, GRASS_BLADE_MID, GRASS_BLADE_TIP)
	# Tall upright central blade so the clump has a peaked, star-shaped silhouette.
	var ctip: Vector3 = base + Vector3(_rand_range(-0.03, 0.03), s * 1.3, _rand_range(-0.03, 0.03))
	var cperp: Vector3 = Vector3(wdt, 0.0, 0.0)
	_tri_grad(v, n, c, base - cperp, base + cperp, ctip, Vector3.UP,
		GRASS_BLADE_BASE, GRASS_BLADE_MID, GRASS_BLADE_TIP)


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


## Like _tri, but carries a per-vertex colour (a base->tip gradient for grass blades).
## Winding is flipped exactly as in _tri so the face is visible toward [param want];
## the b/d colours swap with the verts so the gradient stays pinned to a/b/d.
func _tri_grad(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, a: Vector3, b: Vector3, d: Vector3, want: Vector3, ca: Color, cb: Color, cd: Color) -> void:
	var nrm: Vector3 = (b - a).cross(d - a)
	if nrm.length_squared() < 0.000000001:
		nrm = want
	else:
		nrm = nrm.normalized()
	var bb: Vector3 = b
	var dd: Vector3 = d
	var cbb: Color = cb
	var cdd: Color = cd
	if nrm.dot(want) < 0.0:
		nrm = -nrm
	else:
		bb = d
		dd = b
		cbb = cd
		cdd = cb
	v.append(a); v.append(bb); v.append(dd)
	n.append(nrm); n.append(nrm); n.append(nrm)
	c.append(ca); c.append(cbb); c.append(cdd)


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


## Shared vertex-coloured material for the dirt base, rocks, tufts and flowers.
## Anything above the grass surface (CAP_TOP) sways gently in the wind, more at the
## tips; the soil block below never moves. World-space phase so neighbouring tiles
## ripple together like one field.
func _get_decor_mat() -> ShaderMaterial:
	if _decor_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode cull_back;
uniform float sway_strength = 0.035;
uniform float sway_speed = 1.3;
uniform float ground_y = %f;
void vertex() {
	float above = max(VERTEX.y - ground_y, 0.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ph = TIME * sway_speed + wp.x * 0.7 + wp.z * 0.45;
	float k = above * above * 6.0;
	VERTEX.x += sin(ph) * sway_strength * k;
	VERTEX.z += cos(ph * 0.8) * sway_strength * 0.6 * k;
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
}
""" % CAP_TOP
		_decor_mat = ShaderMaterial.new()
		_decor_mat.shader = sh
	return _decor_mat


## Material for the tall-grass blade mesh: double-sided (flat blades read from every
## angle) and alpha-blended (vertex-colour alpha < 1 lets a unit in the grass show
## through). Shared/static like the decor material so every tile reuses one instance.
func _get_grass_mat() -> StandardMaterial3D:
	if _grass_mat == null:
		_grass_mat = StandardMaterial3D.new()
		_grass_mat.vertex_color_use_as_albedo = true
		_grass_mat.roughness = 1.0
		_grass_mat.metallic = 0.0
		_grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_grass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return _grass_mat
