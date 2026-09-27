extends RefCounted
class_name FloorDecor

## Procedural, DATA-DRIVEN dressing for multi-floor maps, built by MapLoader from the
## MapResource alone (so an edited map is dressed correctly with no hand work):
##
##  * Upper-floor tiles get a structure under them: a MASONRY WALL when the tile
##    below is impassable (castle walls under a rampart walk), otherwise a deck beam
##    (bridge / gatehouse walkway) plus a PIER when it spans water.
##  * Every open edge of an upper floor gets a PARAPET (stone, crenellated on castle
##    walls) or a timber RAIL; edges that a stair / ladder arrives at stay open, and
##    edges facing a GAP in the same floor (a broken bridge) get a jagged BROKEN EDGE
##    with rubble on the ground below.
##  * Every link gets a readable visual: STAIRS (a stepped stone flight in the lower
##    cell rising to the upper cell's edge), a LADDER (kind "ladder"), a vertical
##    ladder for same-column links, or a plank RAMP for anything else.
##
## All geometry is vertex-coloured boxes merged into ONE mesh per floor (plus one
## small mesh per link), so the cost is a handful of draw calls per map.
## Scene layout: Tiles/Decor/Floor_<f>/Decor (MeshInstance3D) and
## Tiles/Links/Link_* (one Node3D per link, meta "cutaway_floor" = its upper floor),
## so FloorCutaway can ghost them together with their floor.

const STONE := Color(0.47, 0.45, 0.41)
const STONE_DARK := Color(0.34, 0.32, 0.3)
const STONE_TOP := Color(0.58, 0.55, 0.5)
const WOOD := Color(0.5, 0.34, 0.2)
const WOOD_DARK := Color(0.36, 0.24, 0.14)
const RUBBLE := Color(0.52, 0.5, 0.46)

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]
const META_FLOOR := &"cutaway_floor"


## Build the per-floor decor meshes under [param tiles_root] (the "Tiles" node).
static func build_floor_decor(map: MapResource, tiles_root: Node3D) -> void:
	if map == null or tiles_root == null or map.get_floor_count() <= 1:
		return
	var decor_root := Node3D.new()
	decor_root.name = "Decor"
	tiles_root.add_child(decor_root)
	var links: Array = map.get_links()
	var by_floor: Dictionary = {}  # floor -> ProcMesh
	for entry in map.tile_layout:
		var f := MapResource.entry_floor(entry)
		if f <= 0:
			continue
		if not by_floor.has(f):
			by_floor[f] = ProcMesh.new()
		if not by_floor.has(f - 1):
			by_floor[f - 1] = ProcMesh.new()
		_tile_decor(by_floor[f], by_floor[f - 1], map, entry, links)
	for f in by_floor:
		var pm: ProcMesh = by_floor[f]
		if pm.is_empty():
			continue
		var holder := Node3D.new()
		holder.name = "Floor_%d" % f
		holder.set_meta(META_FLOOR, f)
		decor_root.add_child(holder)
		var mi := MeshInstance3D.new()
		mi.name = "Decor"
		mi.mesh = pm.commit()
		mi.material_override = ProcMesh.material()
		holder.add_child(mi)


## True for wood-styled decks (planks, dirt, ...); stone otherwise.
static func _is_wood(entry: Dictionary) -> bool:
	var id := String(entry.get("tile_id", "")).to_lower()
	return id.contains("plank") or id.contains("wood") or id.contains("dirt") or id.contains("timber")


static func _res(entry: Dictionary) -> TileResource:
	if entry.is_empty():
		return null
	return MapLoader.resolve_tile_resource_for_entry(entry)


## World-space top of a tile's walkable surface for the resource (default box tiles
## are 1 unit tall, authored slabs 0.2).
static func _tile_top(res: TileResource) -> float:
	if res != null and not res.model_path.is_empty():
		return 0.1
	return 0.5


static func _is_water(res: TileResource) -> bool:
	return res != null and (res.tile_type == Tile.TileType.WATER or String(res.id).contains("water"))


## Is there a link between (pos, f) and ANY floor of column [param other]?
static func _edge_has_link(links: Array, cell: Vector3i, other: Vector2i) -> bool:
	for l in links:
		var a: Vector3i = l["from"]
		var b: Vector3i = l["to"]
		if (a == cell and Cells.flat(b) == other) or (b == cell and Cells.flat(a) == other):
			return true
	return false


static func _tile_decor(pm: ProcMesh, pm_below: ProcMesh, map: MapResource, entry: Dictionary, links: Array) -> void:
	var pos := MapResource.entry_position(entry)
	var f := MapResource.entry_floor(entry)
	var cell := Cells.lift(pos, f)
	var c := Vector3(pos.x * 2 + 1, 0, pos.y * 2 + 1)
	var fy := Cells.floor_y(f)
	var wood := _is_wood(entry)
	var below: Dictionary = map.get_tile_at_position(pos, f - 1)
	var below_res := _res(below)
	var castle := false

	# --- Structure under the deck ----------------------------------------------
	var deck_bottom := fy - 0.55
	if not below.is_empty() and below_res != null and not below_res.is_passable:
		# Solid masonry from the wall tile below up to the deck: a castle wall.
		castle = true
		var y0 := Cells.floor_y(f - 1) + _tile_top(below_res) - 0.05
		_masonry(pm, c, y0, fy - 0.02, pos, f)
	elif not below.is_empty():
		# A span (bridge / walkway): a beam under the slab...
		var col := WOOD_DARK if wood else STONE_DARK
		pm.box(c + Vector3(-1.0, deck_bottom, -1.0), c + Vector3(1.0, fy - 0.05, 1.0), col)
		# ...and a pier where it crosses water.
		if _is_water(below_res):
			var wy := Cells.floor_y(f - 1) + 0.2
			if wood:
				for s in [-0.55, 0.55]:
					pm.box(c + Vector3(s - 0.13, wy, -0.13), c + Vector3(s + 0.13, deck_bottom, 0.13), WOOD_DARK)
			else:
				pm.box(c + Vector3(-0.42, wy, -0.42), c + Vector3(0.42, deck_bottom, 0.42), STONE_DARK, STONE)
				pm.box(c + Vector3(-0.55, wy, -0.55), c + Vector3(0.55, wy + 0.35, 0.55), STONE_DARK)

	# --- Edges (not for impassable blocks such as a tower's wall course) ----------
	var self_res := _res(entry)
	if self_res != null and not self_res.is_passable:
		return
	for d in DIRS:
		var npos: Vector2i = pos + d
		if map.has_tile_at(npos, f):
			continue
		if _edge_has_link(links, cell, npos):
			continue  # a stair / ladder arrives here: keep it open
		var dir3 := Vector3(d.x, 0, d.y)
		var right := Vector3(-d.y, 0, d.x)
		if map.has_tile_at(pos + d * 2, f):  # a one-cell GAP in this floor: broken
			_broken_edge(pm, pm_below, c, fy, dir3, right, wood, pos, f, map)
		elif wood:
			_rail(pm, c, fy, dir3, right)
		else:
			# Crenellate castle walls, but not on the side facing a paved courtyard.
			var ground_id := String(map.get_tile_at_position(npos, 0).get("tile_id", ""))
			_parapet(pm, c, fy, dir3, right, castle and ground_id != "flagstones")


## Coursed masonry block filling one cell column between [param y0] and [param y1].
static func _masonry(pm: ProcMesh, c: Vector3, y0: float, y1: float, pos: Vector2i, f: int) -> void:
	pm.box(c + Vector3(-0.98, y0, -0.98), c + Vector3(0.98, y1, 0.98), STONE_DARK)
	# Proud stone courses on the four faces so the wall reads as masonry.
	var course := 0.42
	var k := 0
	var y := y0 + 0.04
	while y + course * 0.5 < y1:
		var yt := minf(y1 - 0.02, y + course - 0.05)
		var off := 0.0 if k % 2 == 0 else 0.5
		for side in 4:
			var i := 0
			var t := -1.0 + off * 0.5
			while t < 1.0:
				var t1 := minf(1.0, t + 0.62)
				var t0 := maxf(-1.0, t)
				if t1 - t0 > 0.12:
					var h := ProcMesh.hash01(pos.x * 5 + side, pos.y * 3 + k, f * 17 + i)
					var col := STONE.lerp(STONE_DARK, h * 0.6)
					var a0 := t0 + 0.03
					var a1 := t1 - 0.03
					match side:
						0: pm.box(c + Vector3(a0, y, 0.98), c + Vector3(a1, yt, 1.0), col)
						1: pm.box(c + Vector3(a0, y, -1.0), c + Vector3(a1, yt, -0.98), col)
						2: pm.box(c + Vector3(0.98, y, a0), c + Vector3(1.0, yt, a1), col)
						3: pm.box(c + Vector3(-1.0, y, a0), c + Vector3(-0.98, yt, a1), col)
				t = t1
				i += 1
		y += course
		k += 1


## Low stone parapet along one edge; crenellated (merlons) on castle walls.
static func _parapet(pm: ProcMesh, c: Vector3, fy: float, d: Vector3, right: Vector3, castle: bool) -> void:
	var o := c + Vector3(0, fy, 0)
	pm.box_oriented(o, right, d, Vector3(-1.0, 0.05, 0.8), Vector3(1.0, 0.32, 1.0), STONE, STONE_TOP)
	if castle:
		for x in [-0.7, 0.0, 0.7]:
			pm.box_oriented(o, right, d, Vector3(x - 0.2, 0.32, 0.8), Vector3(x + 0.2, 0.62, 1.0), STONE, STONE_TOP)


## Timber rail: posts at the ends + a top rail.
static func _rail(pm: ProcMesh, c: Vector3, fy: float, d: Vector3, right: Vector3) -> void:
	var o := c + Vector3(0, fy, 0)
	for x in [-0.9, 0.0, 0.9]:
		pm.box_oriented(o, right, d, Vector3(x - 0.07, 0.05, 0.84), Vector3(x + 0.07, 0.55, 0.98), WOOD_DARK)
	pm.box_oriented(o, right, d, Vector3(-1.0, 0.45, 0.86), Vector3(1.0, 0.55, 0.97), WOOD, WOOD)


## Jagged broken end of a deck facing a gap, plus rubble on the ground below the gap.
static func _broken_edge(pm: ProcMesh, pm_below: ProcMesh, c: Vector3, fy: float, d: Vector3, right: Vector3, wood: bool, pos: Vector2i, f: int, map: MapResource) -> void:
	var o := c + Vector3(0, fy, 0)
	var col := WOOD if wood else STONE
	var dark := WOOD_DARK if wood else STONE_DARK
	# Teeth: irregular chunks sticking out past the edge, each lower than the deck.
	for i in 6:
		var x0 := -1.0 + i * 0.34
		var h := ProcMesh.hash01(pos.x * 11 + i, pos.y * 13, f)
		var reach := 0.95 + h * 0.4
		var drop := -0.1 - h * 0.5
		pm.box_oriented(o, right, d, Vector3(x0, drop - 0.25, 0.7), Vector3(x0 + 0.3, 0.02 + h * 0.06 - 0.06, reach), dark, col)
	# Splintered stubs of the parapet / rail on each side of the break.
	for s in [-1.0, 1.0]:
		pm.box_oriented(o, right, d, Vector3(s * 0.84 - 0.08, 0.05, 0.55), Vector3(s * 0.84 + 0.08, 0.28, 1.05), dark, col)
	# Rubble fallen onto the ground under the gap.
	var gap: Vector2i = pos + Vector2i(int(d.x), int(d.z))
	var ground_f := f - 1
	var below: Dictionary = map.get_tile_at_position(gap, ground_f)
	if below.is_empty():
		return
	var gy := Cells.floor_y(ground_f) + _tile_top(_res(below))
	var gc := Vector3(gap.x * 2 + 1, gy, gap.y * 2 + 1)
	for i in 5:
		var h1 := ProcMesh.hash01(gap.x * 7 + i, gap.y * 5, f)
		var h2 := ProcMesh.hash01(gap.y * 3 + i, gap.x * 9, f + 1)
		var p := gc - d * (0.45 + h2 * 0.4) + right * ((h1 - 0.5) * 1.4)
		var s := 0.12 + h1 * 0.14
		pm_below.box(p + Vector3(-s, -0.08, -s), p + Vector3(s, s * 0.9, s), RUBBLE.darkened(h2 * 0.25))


# --- Links -------------------------------------------------------------------------

## A Node3D visual for one normalized link, or null when the ends are identical.
static func make_link_visual(l: Dictionary) -> Node3D:
	var a: Vector3i = l["from"]
	var b: Vector3i = l["to"]
	if a == b:
		return null
	var lower := a if a.z <= b.z else b
	var upper := b if a.z <= b.z else a
	var kind := String(l.get("kind", "stairs")).to_lower()
	var pm := ProcMesh.new()
	var d2 := Cells.flat(upper) - Cells.flat(lower)
	var y0 := Cells.floor_y(lower.z) + 0.1
	var y1 := Cells.floor_y(upper.z) + 0.1
	var lc := Vector3(lower.x * 2 + 1, 0, lower.y * 2 + 1)
	if d2 == Vector2i.ZERO:
		_ladder(pm, lc, Vector3(0, 0, -1), y0, y1, 0.8)
	elif absi(d2.x) + absi(d2.y) == 1:
		var fwd := Vector3(d2.x, 0, d2.y)
		if kind == "ladder" or kind == "rope":
			_ladder(pm, lc, fwd, y0, y1, 0.62)
		else:
			_stairs(pm, lc, fwd, y0, y1)
	else:
		_ramp(pm, Cells.cell_to_world(lower) + Vector3(0, 0.12, 0), Cells.cell_to_world(upper) + Vector3(0, 0.12, 0))
	var node := Node3D.new()
	node.name = "Link_%d_%d_%d__%d_%d_%d" % [a.x, a.y, a.z, b.x, b.y, b.z]
	node.set_meta(META_FLOOR, upper.z)
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = pm.commit()
	mi.material_override = ProcMesh.material()
	node.add_child(mi)
	return node


## A stepped stone flight in the lower cell, rising toward [param fwd] to the upper
## cell's edge.
static func _stairs(pm: ProcMesh, lc: Vector3, fwd: Vector3, y0: float, y1: float) -> void:
	var right := Vector3(-fwd.z, 0, fwd.x)
	var rise := y1 - y0
	var steps := maxi(4, int(round(rise / 0.32)))
	var s0 := -0.2
	var run := 1.0 - s0
	var o := lc + Vector3(0, y0, 0)
	for k in steps:
		var z0 := s0 + run * float(k) / float(steps)
		var top := rise * float(k + 1) / float(steps)
		var tread := STONE_TOP if k % 2 == 0 else STONE_TOP.darkened(0.06)
		pm.box_oriented(o, right, fwd, Vector3(-0.62, -0.05, z0), Vector3(0.62, top, 1.0), STONE, tread)
	# Side walls (stringers) with a sloped look: short stepped caps each side.
	for side in [-1.0, 1.0]:
		for k in steps:
			var z0 := s0 + run * float(k) / float(steps)
			var top := rise * float(k + 1) / float(steps) + 0.14
			pm.box_oriented(o, right, fwd, Vector3(side * 0.62 - 0.09, -0.05, z0), Vector3(side * 0.62 + 0.09, top, 1.0), STONE_DARK, STONE)


## A timber ladder leaning on the far edge of the lower cell.
static func _ladder(pm: ProcMesh, lc: Vector3, fwd: Vector3, y0: float, y1: float, at: float) -> void:
	var right := Vector3(-fwd.z, 0, fwd.x)
	var o := lc + Vector3(0, y0, 0)
	var h := y1 - y0 + 0.35
	var lean := 0.3
	var segs := maxi(3, int(h / 0.36))
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		for side in [-0.38, 0.38]:
			pm.box_oriented(o, right, fwd, Vector3(side - 0.05, h * t0, at + lean * (1.0 - t0) - 0.2), Vector3(side + 0.05, h * t1, at + lean * (1.0 - t0) - 0.1), WOOD_DARK)
		if i > 0:
			pm.box_oriented(o, right, fwd, Vector3(-0.36, h * t0 - 0.03, at + lean * (1.0 - t0) - 0.18), Vector3(0.36, h * t0 + 0.03, at + lean * (1.0 - t0) - 0.12), WOOD, WOOD)


## A plank ramp between two arbitrary cell centres.
static func _ramp(pm: ProcMesh, pa: Vector3, pb: Vector3) -> void:
	var flat := Vector3(pb.x - pa.x, 0, pb.z - pa.z)
	if flat.length() < 0.01:
		return
	var fwd := flat.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var len := flat.length()
	var segs := int(ceil(len / 0.3))
	for i in segs:
		var t := (float(i) + 0.5) / segs
		var y := lerpf(pa.y, pb.y, t)
		pm.box_oriented(pa, right, fwd, Vector3(-0.45, y - pa.y - 0.08, len * float(i) / segs), Vector3(0.45, y - pa.y, len * float(i + 1) / segs - 0.03), WOOD, WOOD)
