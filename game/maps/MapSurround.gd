extends Node3D

class_name MapSurround

## PURELY COSMETIC scenery that surrounds a loaded battle map so the board reads as a
## carved diorama block sitting in a wider world, instead of a bare tile slab floating
## in the void.
##
## Three layers, all built under ONE node ("MapSurround", a sibling of "Tiles" under the
## map root) so they tear down with the map in a single free:
##
##   1. RING   -- 2..4 rings of decor CELLS beyond the playable bounds: a faceted
##                grass-on-dirt apron with scattered rocks, tufts and low-poly TREES
##                whose density RISES toward the outer edge ("the forest closes in").
##                Muted (darkened + desaturated) with distance so the playable edge
##                stays the brightest thing on screen.
##   2. SKIRT  -- one dirt-coloured box under the COMBINED bounds, dropping several
##                units below tile level so the whole slab reads as carved earth.
##   3. BACKDROP -- a large dim ground plane far below everything, so the void reads as
##                depth. Paired with the height fog on GameWorld.tscn's WorldEnvironment.
##
## THE HARD RULE: this adds ZERO board cells. Nothing here is registered with
## [CombatServices], nothing carries a [Tile] script, and nothing has a
## [CollisionObject3D] — so pathing, cursor picking (a ground-plane hit filtered by
## [method Grid.is_within_bounds]), spawns, AI, lockstep and replays cannot see it.
## Camera framing is likewise untouched: [CameraController] fits to "Map/Tiles" only,
## and this node lives OUTSIDE that container (it only publishes a "peek_margin" meta
## the camera adds to its PAN clamp, never to its fit rect).
##
## DETERMINISM: the scatter is drawn from a LOCAL [RandomNumberGenerator] seeded by an
## FNV-1a hash of the map's identity (resource path, else name, plus dimensions). It
## never touches the process-wide RNG and never draws from the match stream
## ([MatchRng]) — a decoration that consumed match draws would desync every peer and
## every replay. Same map id => byte-identical layout, every load, on every machine.


# --- Layout ------------------------------------------------------------------

## Node name this builder always mounts under, and what tests / the camera look for.
const NODE_NAME := "MapSurround"

## One board cell is 2x2 world units (see MapLoader._create_tile_at_position).
const CELL: float = 2.0
const HALF: float = 1.0

## Walkable surface height, matching LowPolyTileBuilder.CAP_TOP so the apron is flush
## with the playable tiles rather than stepping up or down at the border.
const CAP_TOP: float = 0.10
## Bottom of the apron's outer lip (a short overhang so the ring has a visible edge).
const CAP_LIP: float = -0.14

## Rings of decor beyond the playable rect. Trimmed toward MIN_RING_DEPTH on huge maps
## so the instance budget below is respected (see [method ring_depth_for]).
const MAX_RING_DEPTH: int = 4
const MIN_RING_DEPTH: int = 2

## PERF CAPS. The apron is ONE merged mesh regardless of cell count, so the cell cap is
## about triangles (~12 tris/cell) rather than draw calls; the tree cap is about NODES,
## which is the number that actually matters. A 40x40 map (the authored maximum) at
## depth 4 plans 704 ring cells and lands well under both.
const MAX_RING_CELLS: int = 900
const MAX_TREES: int = 160

## Dirt skirt: a box under the combined bounds. Its top sits just BELOW the grass cap
## (never coplanar with it) and it drops SKIRT_DEPTH units.
const SKIRT_TOP: float = 0.05
const SKIRT_DEPTH: float = 6.0

## Backdrop plane: far below, wide enough to fill the frame at any fit distance.
const BACKDROP_Y: float = -16.0
const BACKDROP_SIZE: float = 900.0

## The tree prop is LIFTED WHOLESALE from the real forest tree tile, so the surround is
## made of the same art the board is. Only its "TreeVisual" subtree is used; the tile
## body (mesh, collider, Tile script) is instantiated-and-discarded WITHOUT ever
## entering the tree, so none of its _ready side effects (GPUParticles3D, effect
## overlay, material setup) ever run.
const TREE_SCENE: PackedScene = preload("res://tile_objects/tiles/scenes/forest/tree_tile.tscn")


# --- Palettes ----------------------------------------------------------------
##
## Keyed by [member MapResource.environment_preset] (lowercased). A volcanic or desert
## map gets ash / sand and NO trees but more rocks, so the surround never contradicts
## the biome the author picked. Anything unrecognised falls back to "default".

const PALETTES: Dictionary = {
	"default": {
		"grass": Color(0.36, 0.62, 0.30, 1.0),
		"tuft": Color(0.30, 0.55, 0.24, 1.0),
		"rock": Color(0.68, 0.68, 0.66, 1.0),
		"dirt": Color(0.55, 0.38, 0.24, 1.0),
		"dirt_dark": Color(0.42, 0.28, 0.18, 1.0),
		"backdrop": Color(0.10, 0.13, 0.11, 1.0),
		"trees": true,
		"rock_near": 0.10,
		"rock_far": 0.22,
	},
	"forest": {
		"grass": Color(0.32, 0.58, 0.27, 1.0),
		"tuft": Color(0.26, 0.50, 0.22, 1.0),
		"rock": Color(0.64, 0.65, 0.62, 1.0),
		"dirt": Color(0.50, 0.35, 0.22, 1.0),
		"dirt_dark": Color(0.38, 0.26, 0.16, 1.0),
		"backdrop": Color(0.08, 0.12, 0.10, 1.0),
		"trees": true,
		"rock_near": 0.08,
		"rock_far": 0.18,
	},
	"snow": {
		"grass": Color(0.78, 0.84, 0.90, 1.0),
		"tuft": Color(0.66, 0.74, 0.82, 1.0),
		"rock": Color(0.60, 0.64, 0.70, 1.0),
		"dirt": Color(0.46, 0.44, 0.46, 1.0),
		"dirt_dark": Color(0.34, 0.33, 0.36, 1.0),
		"backdrop": Color(0.12, 0.15, 0.19, 1.0),
		"trees": true,
		"rock_near": 0.12,
		"rock_far": 0.24,
	},
	"volcanic": {
		"grass": Color(0.26, 0.23, 0.22, 1.0),
		"tuft": Color(0.34, 0.20, 0.14, 1.0),
		"rock": Color(0.20, 0.18, 0.18, 1.0),
		"dirt": Color(0.32, 0.22, 0.18, 1.0),
		"dirt_dark": Color(0.22, 0.15, 0.13, 1.0),
		"backdrop": Color(0.11, 0.07, 0.06, 1.0),
		"trees": false,
		"rock_near": 0.22,
		"rock_far": 0.46,
	},
	"desert": {
		"grass": Color(0.76, 0.65, 0.42, 1.0),
		"tuft": Color(0.62, 0.56, 0.34, 1.0),
		"rock": Color(0.66, 0.60, 0.50, 1.0),
		"dirt": Color(0.58, 0.44, 0.28, 1.0),
		"dirt_dark": Color(0.44, 0.33, 0.20, 1.0),
		"backdrop": Color(0.16, 0.13, 0.10, 1.0),
		"trees": false,
		"rock_near": 0.20,
		"rock_far": 0.42,
	},
}

## FNV-1a 64-bit constants (same fold [MatchRng] uses; deterministic across peers).
const _FNV_OFFSET: int = 1469598103934665603
const _FNV_PRIME: int = 1099511628211


# --- Instance state ----------------------------------------------------------

## The layout this instance was built from — see [method plan]. Read by tests and by
## anything that wants the instance counts without walking the node tree.
var layout: Dictionary = {}


# =============================================================================
# PLANNING (pure, static, no scene tree, no engine RNG)
# =============================================================================

## The stable seed for [param map]'s surround. Identity is the resource path when the
## map came off disk (the durable reference), else its authored name; dimensions are
## folded in so two different-sized maps sharing a name still differ.
static func seed_for(map: MapResource) -> int:
	if map == null:
		return _fnv("<null>")
	var identity: String = String(map.resource_path)
	if identity.is_empty():
		identity = String(map.map_name)
	identity += "|%dx%d" % [int(map.width), int(map.height)]
	return _fnv(identity)


## FNV-1a fold of [param text]'s UTF-8 bytes. Our OWN hash rather than String.hash()
## so the layout cannot shift under us if the engine's hashing ever changes.
static func _fnv(text: String) -> int:
	var h: int = _FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = (h ^ int(b)) * _FNV_PRIME
	return h


## Ring cells a [param w] x [param h] map would generate at depth [param d].
static func ring_cell_count(w: int, h: int, d: int) -> int:
	return (w + 2 * d) * (h + 2 * d) - w * h


## Rings to build for a [param w] x [param h] map: MAX_RING_DEPTH, trimmed (never below
## MIN_RING_DEPTH) until the cell budget is respected.
static func ring_depth_for(w: int, h: int) -> int:
	var d: int = MAX_RING_DEPTH
	while d > MIN_RING_DEPTH and ring_cell_count(w, h, d) > MAX_RING_CELLS:
		d -= 1
	return d


## How far OUTSIDE the playable rect cell ([param cx], [param cz]) sits, in cells:
## 0 means it IS a playable cell (never decorated), 1..depth is its ring index.
## Chebyshev, so the rings are square shells and the corners fill in.
static func ring_index(cx: int, cz: int, w: int, h: int) -> int:
	var dx: int = 0
	if cx < 0:
		dx = -cx
	elif cx >= w:
		dx = cx - w + 1
	var dz: int = 0
	if cz < 0:
		dz = -cz
	elif cz >= h:
		dz = cz - h + 1
	return maxi(dx, dz)


## The palette key for [param map]'s authored environment_preset.
static func preset_key(map: MapResource) -> String:
	if map == null:
		return "default"
	var key: String = String(map.environment_preset).strip_edges().to_lower()
	return key if PALETTES.has(key) else "default"


## The complete, DETERMINISTIC layout for [param map]'s surround — everything
## [method generate] needs, decided before a single node exists.
##
## Returns:
##   seed        int              the RNG seed used (see [method seed_for])
##   depth       int              rings built
##   width/height int             the playable rect this surrounds
##   preset      String           palette key
##   cells       Array[Dictionary] one entry per DECOR cell, in a fixed scan order:
##                                { cell: Vector2i, ring: int, kind: String
##                                  ("grass"/"rock"/"tree"), yaw: float,
##                                  offset: Vector2, scale: float, tufts: int }
##   tree_count / rock_count / cell_count  int  instance accounting
##
## PURE apart from its own local RNG: it reads only [param map]'s authored fields, so
## calling it twice (or on another machine) yields identical data, and it consumes no
## draw from the match RNG or the process-wide RNG.
static func plan(map: MapResource) -> Dictionary:
	var w: int = maxi(1, int(map.width)) if map != null else 1
	var h: int = maxi(1, int(map.height)) if map != null else 1
	var depth: int = ring_depth_for(w, h)
	var preset: String = preset_key(map)
	var pal: Dictionary = PALETTES[preset]
	var allow_trees: bool = bool(pal["trees"])
	var rock_near: float = float(pal["rock_near"])
	var rock_far: float = float(pal["rock_far"])

	# LOCAL rng. Never MatchRng, never randi()/randf() — see the class doc.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(map)

	var cells: Array[Dictionary] = []
	var trees: int = 0
	var rocks: int = 0

	for cz in range(-depth, h + depth):
		for cx in range(-depth, w + depth):
			var ring: int = ring_index(cx, cz, w, h)
			if ring <= 0:
				continue
			# 0 at the innermost ring, 1 at the outermost: density rises outward so the
			# treeline visibly closes in and the playable edge stays open.
			var t: float = float(ring - 1) / float(maxi(depth - 1, 1))
			var tree_chance: float = lerpf(0.07, 0.55, t) if allow_trees else 0.0
			var rock_chance: float = lerpf(rock_near, rock_far, t)

			# EVERY draw below is unconditional and in a fixed order, so the stream
			# never depends on a branch — that is what makes the layout reproducible.
			var roll: float = rng.randf()
			var yaw: float = rng.randf() * TAU
			var off := Vector2(rng.randf_range(-0.42, 0.42), rng.randf_range(-0.42, 0.42))
			var scale: float = rng.randf_range(0.74, 1.20)
			var tufts: int = int(rng.randf() * 3.0)

			var kind: String = "grass"
			if roll < tree_chance and trees < MAX_TREES:
				kind = "tree"
				trees += 1
			elif roll < tree_chance + rock_chance:
				kind = "rock"
				rocks += 1

			cells.append({
				"cell": Vector2i(cx, cz),
				"ring": ring,
				"kind": kind,
				"yaw": yaw,
				"offset": off,
				"scale": scale,
				"tufts": tufts,
			})

	return {
		"seed": rng.seed,
		"depth": depth,
		"width": w,
		"height": h,
		"preset": preset,
		"cells": cells,
		"cell_count": cells.size(),
		"tree_count": trees,
		"rock_count": rocks,
	}


# =============================================================================
# BUILDING
# =============================================================================

## Build (or REBUILD) the surround for [param map] under [param map_root], returning the
## mounted node. Any stray node already named [constant NODE_NAME] is freed first, so a
## second load can never leave two aprons stacked on one board.
static func build(map: MapResource, map_root: Node3D) -> MapSurround:
	if map == null or map_root == null:
		return null
	var stale := map_root.get_node_or_null(NODE_NAME)
	if stale != null:
		map_root.remove_child(stale)
		stale.free()

	var node := MapSurround.new()
	node.name = NODE_NAME
	map_root.add_child(node)
	node.generate(map)
	return node


## Populate this node with the ring / skirt / backdrop geometry for [param map].
## Idempotent: existing children are cleared first.
func generate(map: MapResource) -> void:
	for child in get_children():
		remove_child(child)
		child.free()

	layout = plan(map)
	var pal: Dictionary = PALETTES[String(layout["preset"])]
	var depth: int = int(layout["depth"])
	var w: int = int(layout["width"])
	var h: int = int(layout["height"])

	# One vertex-coloured material for every merged surface. Built FRESH here (never a
	# shared .tres mutated in place — see CONQUEST.md convention 7), so tinting the
	# surround can never recolour the board's own tiles.
	var vc_mat := StandardMaterial3D.new()
	vc_mat.vertex_color_use_as_albedo = true
	vc_mat.roughness = 1.0
	vc_mat.metallic = 0.0

	var ground := MeshInstance3D.new()
	ground.name = "Apron"
	ground.mesh = _build_apron_mesh(layout, pal)
	ground.material_override = vc_mat
	add_child(ground)

	var skirt := MeshInstance3D.new()
	skirt.name = "DirtSkirt"
	skirt.mesh = _build_skirt_mesh(w, h, depth, pal)
	skirt.material_override = vc_mat
	add_child(skirt)

	add_child(_build_backdrop(w, h, pal))

	if int(layout["tree_count"]) > 0:
		_build_trees(layout, pal)

	# How far past the board edge the camera may PAN (never how far it fits — see the
	# class doc). Roughly the middle of the ring: enough to peek at the treeline,
	# not enough to fly off into the void.
	set_meta("peek_margin", float(depth) * CELL * 0.55)


# --- Apron (rings of grass-on-dirt cells, rocks and tufts, ONE merged mesh) ---

func _build_apron_mesh(plan_data: Dictionary, pal: Dictionary) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	var depth: int = int(plan_data["depth"])
	var grass: Color = pal["grass"]
	var tuft: Color = pal["tuft"]
	var rock: Color = pal["rock"]

	for entry in (plan_data["cells"] as Array):
		var cell: Vector2i = entry["cell"]
		var ring: int = int(entry["ring"])
		var mute: float = float(ring) / float(maxi(depth, 1))
		var center := Vector3(float(cell.x) * CELL + HALF, 0.0, float(cell.y) * CELL + HALF)
		_add_cap(v, n, c, center, cell, _muted(grass, mute))

		var off: Vector2 = entry["offset"]
		var scale: float = float(entry["scale"])
		if String(entry["kind"]) == "rock":
			_add_rock(v, n, c, center + Vector3(off.x, CAP_TOP, off.y),
				0.26 * scale, _muted(rock, mute))
		var tufts: int = int(entry["tufts"])
		for i in range(tufts):
			# Deterministic fan around the cell centre — no extra RNG draws needed.
			var ang: float = float(i) * 2.399963 + float(entry["yaw"])
			var r: float = 0.30 + 0.22 * float(i)
			var base := center + Vector3(cos(ang) * r, CAP_TOP, sin(ang) * r)
			_add_tuft(v, n, c, base, 0.16 + 0.05 * scale, _muted(tuft, mute))

	# Outer lip: a short skirt around the WHOLE apron so its edge reads as a cut block
	# rather than an infinitely thin sheet. Drawn once, not per cell.
	var w: int = int(plan_data["width"])
	var h: int = int(plan_data["height"])
	var x0: float = float(-depth) * CELL
	var x1: float = float(w + depth) * CELL
	var z0: float = float(-depth) * CELL
	var z1: float = float(h + depth) * CELL
	_add_outward_walls(v, n, c, x0, x1, z0, z1, CAP_TOP, CAP_LIP,
		_muted(pal["dirt"], 1.0), _muted(pal["dirt_dark"], 1.0))

	return _mesh(v, n, c)


# --- Dirt skirt (the carved-block under-extrusion) ---------------------------

func _build_skirt_mesh(w: int, h: int, depth: int, pal: Dictionary) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()

	var x0: float = float(-depth) * CELL
	var x1: float = float(w + depth) * CELL
	var z0: float = float(-depth) * CELL
	var z1: float = float(h + depth) * CELL
	var top: float = SKIRT_TOP
	var bot: float = SKIRT_TOP - SKIRT_DEPTH

	_add_outward_walls(v, n, c, x0, x1, z0, z1, top, bot,
		pal["dirt"], pal["dirt_dark"])

	# Bottom cap, so the block is solid when the camera catches it from a low angle.
	var b0 := Vector3(x0, bot, z0)
	var b1 := Vector3(x1, bot, z0)
	var b2 := Vector3(x1, bot, z1)
	var b3 := Vector3(x0, bot, z1)
	_tri(v, n, c, b0, b1, b2, Vector3.DOWN, pal["dirt_dark"])
	_tri(v, n, c, b0, b2, b3, Vector3.DOWN, pal["dirt_dark"])

	return _mesh(v, n, c)


# --- Backdrop (the "there is a world down there" plane) ----------------------

func _build_backdrop(w: int, h: int, pal: Dictionary) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(BACKDROP_SIZE, BACKDROP_SIZE)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = pal["backdrop"]
	mat.roughness = 1.0
	mat.metallic = 0.0

	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = plane
	mi.material_override = mat
	# A 900x900 plane casting shadows buys nothing and costs a shadow-map pass.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(float(w) * CELL * 0.5, BACKDROP_Y, float(h) * CELL * 0.5)
	return mi


# --- Trees (the real forest tree prop, muted and scattered) ------------------

## The whole treeline in a HANDFUL OF DRAW CALLS.
##
## The naive version — one duplicated TreeVisual per tree — is 4 MeshInstance3D nodes
## each (trunk + three leaf blobs), i.e. ~500 nodes and ~500 draw calls on a 20x20 map,
## which is far more than the board itself costs. Instead the prototype's parts are
## GROUPED BY MESH and drawn as one [MultiMesh] per distinct mesh: the trunk cylinder is
## one, the leaf sphere (shared by all three blobs) is the other. Total: 2 draw calls
## and 2 nodes for every tree on the map, at any ring depth.
func _build_trees(plan_data: Dictionary, pal: Dictionary) -> void:
	var parts := _tree_prototype()
	if parts.is_empty():
		return

	# One root transform per planted tree, in plan order (so this stays deterministic).
	var depth: int = int(plan_data["depth"])
	var roots: Array[Transform3D] = []
	for entry in (plan_data["cells"] as Array):
		if String(entry["kind"]) != "tree":
			continue
		var cell: Vector2i = entry["cell"]
		var off: Vector2 = entry["offset"]
		# Outer trees stand a touch taller, which is what makes the ring read as a
		# treeline rising BEHIND the board rather than a flat field of shrubs.
		var ring_boost: float = 1.0 + 0.18 * (float(entry["ring"]) / float(maxi(depth, 1)))
		var basis := Basis(Vector3.UP, float(entry["yaw"])).scaled(
			Vector3.ONE * float(entry["scale"]) * ring_boost)
		roots.append(Transform3D(basis, Vector3(
			float(cell.x) * CELL + HALF + off.x,
			CAP_TOP,
			float(cell.y) * CELL + HALF + off.y)))
	if roots.is_empty():
		return

	# mesh -> { material, local transforms of every part using that mesh }.
	# Dictionaries keep insertion order, so the grouping is stable run to run.
	var groups: Dictionary = {}
	for part in parts:
		var mesh: Mesh = part["mesh"]
		if not groups.has(mesh):
			groups[mesh] = { "material": part["material"], "locals": [] }
		(groups[mesh]["locals"] as Array).append(part["xform"])

	var trees := Node3D.new()
	trees.name = "Trees"
	add_child(trees)

	var group_index: int = 0
	for mesh in groups:
		var locals: Array = groups[mesh]["locals"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = roots.size() * locals.size()
		var i: int = 0
		for root in roots:
			for local in locals:
				mm.set_instance_transform(i, root * (local as Transform3D))
				i += 1
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "TreeParts%d" % group_index
		mmi.multimesh = mm
		mmi.material_override = groups[mesh]["material"]
		trees.add_child(mmi)
		group_index += 1


## The forest tree prop, taken apart into { mesh, material, xform } pieces the MultiMesh
## builder above can batch — so the surround is made of the same art the board is,
## without inheriting its node count.
##
## The donor scene is instantiated but NEVER enters the tree, so Tile._ready (a
## GPUParticles3D and an overlay per tile) and LowPolyTileBuilder._ready never run for
## it: the whole treeline costs ONE scene instantiation. Materials are DUPLICATED before
## being muted (CONQUEST.md convention 7) — the board's own trees must not darken
## because the surround wanted a darker one.
func _tree_prototype() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	var donor := TREE_SCENE.instantiate()
	if donor == null:
		return parts
	var visual := donor.get_node_or_null("TreeVisual") as Node3D
	if visual == null:
		donor.free()
		return parts

	# One muted duplicate per distinct shared material, reused across every part.
	var muted: Dictionary = {}
	for child in visual.get_children():
		var mi := child as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var source: Material = mi.material_override
		var material: Material = null
		if source != null:
			if not muted.has(source):
				var dup: Material = source.duplicate()
				_mute_material(dup, 0.72)
				muted[source] = dup
			material = muted[source]
		parts.append({
			"mesh": mi.mesh,
			"material": material,
			"xform": mi.transform,
		})

	donor.free()
	return parts


## Darken (and slightly desaturate) [param mat] IN PLACE. Only ever called on a
## duplicate. Handles both material kinds the tree prop uses: the stylized foliage
## ShaderMaterial (three authored leaf colours) and the bark StandardMaterial3D.
static func _mute_material(mat: Material, factor: float) -> void:
	if mat is ShaderMaterial:
		var sm := mat as ShaderMaterial
		for param in ["leaf_dark", "leaf_mid", "leaf_bright",
				"grass_dark", "grass_mid", "grass_bright"]:
			var value = sm.get_shader_parameter(param)
			if value is Color:
				sm.set_shader_parameter(param, _dim(value, factor, 0.22))
	elif mat is StandardMaterial3D:
		var std := mat as StandardMaterial3D
		std.albedo_color = _dim(std.albedo_color, factor, 0.22)


# --- Colour helpers ----------------------------------------------------------

## The ring colour for [param base] at normalised distance [param t] (0 = innermost
## ring, 1 = outermost): progressively darker AND greyer, so the surround always reads
## as background and the playable edge stays the most saturated thing on screen.
static func _muted(base: Color, t: float) -> Color:
	var k: float = clampf(t, 0.0, 1.0)
	return _dim(base, lerpf(0.86, 0.58, k), lerpf(0.10, 0.38, k))


## [param base] scaled by [param mult] and pulled [param desat] of the way toward its
## own grey. Alpha is preserved.
static func _dim(base: Color, mult: float, desat: float) -> Color:
	var grey: float = (base.r + base.g + base.b) / 3.0
	return Color(
		lerpf(base.r, grey, desat) * mult,
		lerpf(base.g, grey, desat) * mult,
		lerpf(base.b, grey, desat) * mult,
		base.a)


# --- Geometry helpers (flat-shaded, vertex-coloured; mirrors LowPolyTileBuilder) ---

## A 2x2 subdivided grass cap for one cell, perimeter pinned flat at [constant CAP_TOP]
## so neighbouring cells tile seamlessly and only the interior is jittered.
func _add_cap(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		center: Vector3, cell: Vector2i, col: Color) -> void:
	var pts: Array = []
	for iz in range(3):
		var row: Array = []
		for ix in range(3):
			var fx: float = -HALF + HALF * float(ix)
			var fz: float = -HALF + HALF * float(iz)
			var y: float = CAP_TOP
			if ix == 1 and iz == 1:
				y = CAP_TOP + _cell_jitter(cell)
			row.append(center + Vector3(fx, y, fz))
		pts.append(row)

	for iz in range(2):
		for ix in range(2):
			var p00: Vector3 = pts[iz][ix]
			var p10: Vector3 = pts[iz][ix + 1]
			var p11: Vector3 = pts[iz + 1][ix + 1]
			var p01: Vector3 = pts[iz + 1][ix]
			_tri(v, n, c, p00, p11, p10, Vector3.UP, col)
			_tri(v, n, c, p00, p01, p11, Vector3.UP, col)


## A tiny deterministic height wobble per cell, from the cell coordinates alone (no RNG
## draw), so the apron is faceted rather than a mirror-flat sheet.
static func _cell_jitter(cell: Vector2i) -> float:
	var hsh: int = (cell.x * 911) ^ (cell.y * 677)
	hsh = (hsh ^ (hsh >> 5)) * 2654435761
	return -0.02 + float(absi(hsh) % 1000) / 1000.0 * 0.055


func _add_rock(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		center: Vector3, s: float, col: Color) -> void:
	var top := center + Vector3(0.0, s, 0.0)
	var bot := center + Vector3(0.0, -s * 0.6, 0.0)
	var ring := [
		center + Vector3(s, 0.0, 0.0), center + Vector3(0.0, 0.0, s),
		center + Vector3(-s, 0.0, 0.0), center + Vector3(0.0, 0.0, -s)]
	for i in range(4):
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_tri(v, n, c, top, a, b, ((top + a + b) / 3.0) - center, col)
		_tri(v, n, c, bot, b, a, ((bot + a + b) / 3.0) - center, col)


func _add_tuft(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		base: Vector3, h: float, col: Color) -> void:
	var wdt: float = 0.05
	var tip := base + Vector3(0.0, h, 0.0)
	var b0 := base + Vector3(-wdt, 0.0, -wdt * 0.5)
	var b1 := base + Vector3(wdt, 0.0, -wdt * 0.5)
	var b2 := base + Vector3(0.0, 0.0, wdt)
	_tri(v, n, c, b0, b1, tip, Vector3(0, 0, -1), col)
	_tri(v, n, c, b1, b2, tip, Vector3(1, 0, 1).normalized(), col)
	_tri(v, n, c, b2, b0, tip, Vector3(-1, 0, 1).normalized(), col)


## Four outward-facing walls around the rectangle [param x0]..[param x1] /
## [param z0]..[param z1], from [param top] down to [param bot]. Alternating shades so
## the block reads faceted under flat shading.
func _add_outward_walls(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		x0: float, x1: float, z0: float, z1: float, top: float, bot: float,
		light: Color, dark: Color) -> void:
	var corners := [
		Vector3(x0, top, z0), Vector3(x1, top, z0),
		Vector3(x1, top, z1), Vector3(x0, top, z1)]
	var cx: float = (x0 + x1) * 0.5
	var cz: float = (z0 + z1) * 0.5
	for i in range(4):
		var t0: Vector3 = corners[i]
		var t1: Vector3 = corners[(i + 1) % 4]
		var b0 := Vector3(t0.x, bot, t0.z)
		var b1 := Vector3(t1.x, bot, t1.z)
		var mid: Vector3 = (t0 + t1) * 0.5
		var outward := Vector3(mid.x - cx, 0.0, mid.z - cz).normalized()
		var shade: Color = light if (i % 2 == 0) else dark
		_tri(v, n, c, t0, t1, b1, outward, shade)
		_tri(v, n, c, t0, b1, b0, outward, shade)


## Append one FLAT triangle whose face normal points toward [param want] (each triangle
## owns its verts, so nothing is smoothed across faces).
func _tri(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray,
		a: Vector3, b: Vector3, d: Vector3, want: Vector3, col: Color) -> void:
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
		bb = d
		dd = b
	v.append(a); v.append(bb); v.append(dd)
	n.append(nrm); n.append(nrm); n.append(nrm)
	c.append(col); c.append(col); c.append(col)


func _mesh(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray) -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.size() == 0:
		return m
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
