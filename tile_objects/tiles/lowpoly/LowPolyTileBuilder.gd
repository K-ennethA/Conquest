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

## APPEND new styles at the end: scenes store the enum by index.
enum Style { GRASS, TALL_GRASS, DIRT, MEADOW, TREE, WATER, LAVA, SACRED, WALL }
@export var style: Style = Style.GRASS

const HALF: float = 1.0
const CAP_TOP: float = 0.10        # walkable surface == UNIT_GROUND_Y
const CAP_LIP: float = -0.05       # cap skirt bottom (slight overhang lip)
const WATER_TOP: float = 0.03      # water / lava surface: a little below the grass banks
const WALL_TOP: float = 0.75       # dry-stone wall height (kept low so units behind stay readable)
const DIRT_TOP: float = 0.02
const DIRT_BOTTOM: float = -0.7
const DIRT_HALF: float = 0.94      # inset so the green cap overhangs the dirt

# Layered soil sides: a dark humus band under the grass lip, warm earth in the
# middle, a cooler clay base. Two shades per band alternate by face so the block
# still reads as faceted under flat lighting.
const DIRT_COLOR: Color = Color(0.46, 0.31, 0.2, 1.0)   # warm earth (mid band)
const DIRT_DARK: Color = Color(0.38, 0.25, 0.16, 1.0)
const HUMUS_COLOR: Color = Color(0.26, 0.18, 0.12, 1.0)  # dark top band
const HUMUS_DARK: Color = Color(0.24, 0.17, 0.11, 1.0)
const CLAY_COLOR: Color = Color(0.42, 0.33, 0.26, 1.0)   # cooler bottom band
const CLAY_DARK: Color = Color(0.34, 0.27, 0.21, 1.0)
const HUMUS_BOTTOM: float = -0.16
const CLAY_TOP: float = -0.48
const ROCK_COLOR: Color = Color(0.56, 0.55, 0.51, 1.0)   # weathered stone
const ROCK_DARK: Color = Color(0.43, 0.42, 0.39, 1.0)

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
# Sacred meadow blooms: pale, luminous whites / golds / sky blue.
const SACRED_FLOWER_COLORS: Array[Color] = [
	Color(1.0, 0.99, 0.94, 1.0),
	Color(1.0, 0.9, 0.55, 1.0),
	Color(0.72, 0.86, 1.0, 1.0),
]
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
static var _grass_mat: ShaderMaterial = null
static var _mote_mat: ShaderMaterial = null

const DECOR_SHADER := "res://tile_objects/tiles/shaders/stylized_decor.gdshader"
const TALL_GRASS_SHADER := "res://tile_objects/tiles/shaders/stylized_tall_grass.gdshader"
const MOTE_SHADER := "res://tile_objects/tiles/shaders/stylized_motes.gdshader"
const TALL_TIP_DRY: Color = Color(0.78, 0.74, 0.36, 0.62)


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

	# Sacred tiles float soft golden motes (one static billboard mesh, animated
	# entirely in the shader).
	var motes := get_node_or_null("Motes") as MeshInstance3D
	if style == Style.MEADOW or style == Style.SACRED:
		if motes == null:
			motes = MeshInstance3D.new()
			motes.name = "Motes"
			add_child(motes)
		motes.mesh = _build_motes(7 if style == Style.MEADOW else 10)
		motes.material_override = _get_mote_mat()
		motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		motes.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 1.8, 2.4))
	elif motes != null:
		motes.queue_free()

	# Stone walls: a chunky dry-stone block (painterly props shader).
	var wall := get_node_or_null("Wall") as MeshInstance3D
	if style == Style.WALL:
		if wall == null:
			wall = MeshInstance3D.new()
			wall.name = "Wall"
			add_child(wall)
		wall.mesh = _build_wall()
		wall.material_override = ProcMesh.material()
	elif wall != null:
		wall.queue_free()


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
			var y: float = _cap_top()
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
	# Water / lava sit below their banks: no skirt (the soil block shows at edges).
	if style == Style.WATER or style == Style.LAVA:
		return _mesh(v, n, null)
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


func _cap_top() -> float:
	if style == Style.WATER or style == Style.LAVA:
		return WATER_TOP
	return CAP_TOP


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
	if style == Style.WATER or style == Style.LAVA:
		# Full-width bed under the surface so the board edge shows a soil bank.
		d = HALF * 0.995
		top = WATER_TOP - 0.005
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
	if style == Style.WATER or style == Style.LAVA or style == Style.WALL:
		pass
	elif style == Style.SACRED:
		_add_shrine_stones(v, n, c)
	elif style != Style.TALL_GRASS:
		var tuft_count: int = 8
		var flower_chance: float = 0.45
		match style:
			Style.MEADOW:
				tuft_count = 9
				flower_chance = 1.0
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
		if style == Style.MEADOW:
			flowers = 5 + int(_rand() * 3.0)
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
	var pal: Array[Color] = SACRED_FLOWER_COLORS if style == Style.MEADOW else FLOWER_COLORS
	var col: Color = pal[int(_rand() * float(pal.size())) % pal.size()]
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


## A bushy clump of tall, CURVED grass blades fanning out from [param base] to
## roughly [param s] tall -- the tall-grass evasion terrain. Each blade is a
## tapered two-segment ribbon (wide root -> bent mid -> point) arching outward on
## its own yaw, dark shadowed root -> leaf green -> sunlit tip (a few tips sun-dried
## gold), with a taller upright core so the clump peaks in the middle. The material
## (stylized_tall_grass) is double-sided + softly translucent and sways, so a unit
## standing in the clump still shows through it.
func _add_grass_clump(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, base: Vector3, s: float) -> void:
	var blades: int = 12 + int(_rand() * 5.0)
	for i in range(blades):
		var ang: float = TAU * float(i) / float(blades) + _rand_range(-0.35, 0.35)
		var core: bool = i % 4 == 0
		var lean: float = _rand_range(0.08, 0.2) if core else _rand_range(0.2, 0.45)
		var bh: float = s * (_rand_range(1.0, 1.3) if core else _rand_range(0.6, 1.05))
		var tip_col: Color = GRASS_BLADE_TIP if _rand() < 0.75 else TALL_TIP_DRY
		_add_curved_blade(v, n, c, base + Vector3(_rand_range(-0.05, 0.05), 0.0, _rand_range(-0.05, 0.05)),
			ang, bh, lean, _rand_range(0.045, 0.065), tip_col)


func _add_curved_blade(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, root: Vector3, ang: float, h: float, lean: float, w: float, tip_col: Color) -> void:
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	var perp := Vector3(-dir.z, 0.0, dir.x)
	# Quadratic arch: rises mostly straight, then bends outward near the top.
	var mid: Vector3 = root + dir * lean * 0.25 + Vector3(0.0, h * 0.55, 0.0)
	var tip: Vector3 = root + dir * lean + Vector3(0.0, h, 0.0) - Vector3(0.0, lean * 0.25, 0.0)
	var r0: Vector3 = root - perp * w
	var r1: Vector3 = root + perp * w
	var m0: Vector3 = mid - perp * w * 0.6
	var m1: Vector3 = mid + perp * w * 0.6
	var face: Vector3 = (dir + Vector3.UP * 0.6).normalized()
	_tri_grad(v, n, c, r0, r1, m1, face, GRASS_BLADE_BASE, GRASS_BLADE_BASE, GRASS_BLADE_MID)
	_tri_grad(v, n, c, r0, m1, m0, face, GRASS_BLADE_BASE, GRASS_BLADE_MID, GRASS_BLADE_MID)
	_tri_grad(v, n, c, m0, m1, tip, face, GRASS_BLADE_MID, GRASS_BLADE_MID, tip_col)


## Tiny camera-facing mote quads (billboarded + animated in stylized_motes).
## COLOR.a = per-mote phase; UV = quad corner.
func _build_motes(count: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in range(count):
		var p := Vector3(_rand_range(-0.8, 0.8), CAP_TOP + _rand_range(0.1, 0.7), _rand_range(-0.8, 0.8))
		var phase := _rand()
		for k in corners:
			v.append(p)
			uv.append(k)
			c.append(Color(1, 1, 1, phase))
	var m := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Four weathered standing stones and a low ring of pale pavers: the shrine read
## for Sacred Ground (its cap carries the pale SACRED stone material).
func _add_shrine_stones(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray) -> void:
	var stone := Color(0.7, 0.68, 0.6, 1.0)
	var stone_dk := Color(0.54, 0.52, 0.47, 1.0)
	# At most one weathered standing stone per cell, at a hashed spot, so a shrine
	# area reads as scattered menhirs rather than a grid of posts.
	if _rand() > 0.45:
		return
	for i in range(1):
		var a: float = _rand() * TAU
		var p := Vector3(cos(a) * _rand_range(0.2, 0.7), CAP_TOP, sin(a) * _rand_range(0.2, 0.7))
		var hgt: float = _rand_range(0.22, 0.36)
		var wdt: float = 0.09
		var top := p + Vector3(0.0, hgt, 0.0)
		var ring := [p + Vector3(wdt, 0, 0), p + Vector3(0, 0, wdt), p + Vector3(-wdt, 0, 0), p + Vector3(0, 0, -wdt)]
		for k in range(4):
			var q0: Vector3 = ring[k]
			var q1: Vector3 = ring[(k + 1) % 4]
			var t0 := q0 + Vector3(0, hgt * 0.85, 0) + (p - q0) * 0.25
			var t1 := q1 + Vector3(0, hgt * 0.85, 0) + (p - q1) * 0.25
			var out: Vector3 = ((q0 + q1) * 0.5 - p).normalized()
			var col: Color = stone if k % 2 == 0 else stone_dk
			_tri(v, n, c, q0, q1, t1, out, col)
			_tri(v, n, c, q0, t1, t0, out, col)
			_tri(v, n, c, t0, t1, top, (out + Vector3.UP).normalized(), stone)


## A dry-stone wall block filling the cell: irregular coursed stones (props shader
## adds dabs + moss), a mossy capstone course on top.
func _build_wall() -> ArrayMesh:
	var pm := ProcMesh.new()
	var kx: int = int(round(global_position.x))
	var kz: int = int(round(global_position.z))
	var stone := Color(0.47, 0.45, 0.42)
	var stone_dk := Color(0.33, 0.31, 0.29)
	pm.box(Vector3(-0.93, CAP_TOP - 0.02, -0.93), Vector3(0.93, WALL_TOP - 0.05, 0.93), stone_dk)
	var course := 0.22
	var y := CAP_TOP
	var k := 0
	while y < WALL_TOP - 0.1:
		var y1 := minf(WALL_TOP - 0.03, y + course - 0.03)
		for side in 4:
			var t := -0.95 + (0.0 if k % 2 == 0 else 0.22)
			var i := 0
			while t < 0.95:
				var t1 := minf(0.95, t + 0.38 + ProcMesh.hash01(kx + side, kz + k, i) * 0.22)
				var h := ProcMesh.hash01(kx * 3 + side, kz * 5 + k, i + 7)
				var col := stone.lerp(stone_dk, h * 0.7)
				var o := 0.02 + h * 0.03
				var a0 := t + 0.02
				var a1 := t1 - 0.02
				match side:
					0: pm.box(Vector3(a0, y, 0.93), Vector3(a1, y1, 0.93 + o), col)
					1: pm.box(Vector3(a0, y, -0.93 - o), Vector3(a1, y1, -0.93), col)
					2: pm.box(Vector3(0.93, y, a0), Vector3(0.93 + o, y1, a1), col)
					3: pm.box(Vector3(-0.93 - o, y, a0), Vector3(-0.93, y1, a1), col)
				t = t1
				i += 1
		y += course
		k += 1
	# Capstones.
	var x := -0.97
	var j := 0
	while x < 0.97:
		var x1 := minf(0.97, x + 0.45 + ProcMesh.hash01(kx, kz, j + 30) * 0.2)
		var hh := ProcMesh.hash01(kx, kz, j + 40)
		pm.box(Vector3(x + 0.02, WALL_TOP - 0.05, -0.97), Vector3(x1 - 0.02, WALL_TOP + 0.02 + hh * 0.05, 0.97), stone.lerp(stone_dk, hh * 0.5), stone.lightened(0.08))
		x = x1
		j += 1
	return pm.commit()


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


## Shared vertex-coloured material for the dirt base, rocks, tufts and flowers
## (stylized_decor.gdshader: wind sway above the grass surface, weather, haze).
func _get_decor_mat() -> ShaderMaterial:
	if _decor_mat == null:
		_decor_mat = ShaderMaterial.new()
		_decor_mat.shader = load(DECOR_SHADER)
	return _decor_mat


## Material for the tall-grass blade mesh: double-sided, alpha-blended (vertex alpha
## < 1 lets a unit in the grass show through) and swaying (stylized_tall_grass).
## Shared/static like the decor material so every tile reuses one instance.
func _get_grass_mat() -> ShaderMaterial:
	if _grass_mat == null:
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = load(TALL_GRASS_SHADER)
	return _grass_mat


func _get_mote_mat() -> ShaderMaterial:
	if _mote_mat == null:
		_mote_mat = ShaderMaterial.new()
		_mote_mat.shader = load(MOTE_SHADER)
	return _mote_mat
