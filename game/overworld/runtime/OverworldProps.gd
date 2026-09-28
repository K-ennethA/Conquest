class_name OverworldProps
extends RefCounted

## PROCEDURAL placeholder art for the overworld's people and props (docs/design/OVERWORLD.md
## §8 "Human world art": procedural first). Blocky, flat-shaded, vertex-coloured meshes built
## with [ProcMesh] and its painterly props shader -- no textures, the same look as the stairs and
## bridges on the battle board. Real models slot in per entity via visual_character (a roster
## model) or, for the hero, [HeroResource].
##
## Every builder returns a Node3D whose origin is the cell's floor centre (feet at y = 0), facing
## +Z (south) -- the model convention (CONQUEST.md "Unit facing").

const SKIN := Color(0.86, 0.68, 0.52)
const HAIR_DARK := Color(0.24, 0.17, 0.12)
const HAIR_GREY := Color(0.78, 0.76, 0.72)
const WOOD := Color(0.47, 0.32, 0.19)
const WOOD_DARK := Color(0.33, 0.22, 0.13)
const STONE := Color(0.62, 0.62, 0.58)
const IRON := Color(0.5, 0.52, 0.56)
const GOLD := Color(0.86, 0.68, 0.28)


static func _node(pm: ProcMesh, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = pm.commit()
	mi.material_override = ProcMesh.material()
	return mi


## A person: legs, a robe / tunic in [param cloak], arms, a head with hair. [param kind] adds the
## role's silhouette: "elder" (long robe, grey hair, staff), "guard" (helm, spear, shield),
## "officer" (pauldrons, cape, sword -- no helm), "trainer" (short cape, satchel), "raider"
## (hood, face wrap, long cloak, curved blade), "scholar" (long robe, satchel, a glowing shard
## pendant), "noble" (gold-trimmed robe, circlet), "child" (a small villager), "villager" (apron).
static func figure(cloak: Color, kind: String = "villager") -> Node3D:
	var root := Node3D.new()
	root.name = "Figure"
	var pm := ProcMesh.new()
	var trousers: Color = cloak.darkened(0.45)
	var long_robe: bool = kind == "elder" or kind == "scholar" or kind == "noble"
	var robe_len: float = 0.05 if long_robe else 0.45
	# Legs / boots.
	if not long_robe:
		pm.box(Vector3(-0.2, 0.0, -0.1), Vector3(-0.04, robe_len, 0.1), trousers)
		pm.box(Vector3(0.04, 0.0, -0.1), Vector3(0.2, robe_len, 0.1), trousers)
		pm.box(Vector3(-0.22, 0.0, -0.12), Vector3(-0.02, 0.1, 0.14), WOOD_DARK)
		pm.box(Vector3(0.02, 0.0, -0.12), Vector3(0.22, 0.1, 0.14), WOOD_DARK)
	# Body (robe / tunic), a belt, shoulders.
	pm.box(Vector3(-0.28, robe_len, -0.17), Vector3(0.28, 1.05, 0.17), cloak)
	pm.box(Vector3(-0.29, 0.62, -0.18), Vector3(0.29, 0.69, 0.18), WOOD_DARK)
	pm.box(Vector3(-0.32, 0.95, -0.19), Vector3(0.32, 1.1, 0.19), cloak.lightened(0.08))
	# Arms.
	pm.box(Vector3(-0.42, 0.55, -0.1), Vector3(-0.29, 1.05, 0.1), cloak.darkened(0.08))
	pm.box(Vector3(0.29, 0.55, -0.1), Vector3(0.42, 1.05, 0.1), cloak.darkened(0.08))
	pm.box(Vector3(-0.41, 0.46, -0.08), Vector3(-0.3, 0.56, 0.08), SKIN)
	pm.box(Vector3(0.3, 0.46, -0.08), Vector3(0.41, 0.56, 0.08), SKIN)
	# Head + hair.
	pm.box(Vector3(-0.07, 1.1, -0.07), Vector3(0.07, 1.16, 0.07), SKIN)
	pm.box(Vector3(-0.17, 1.16, -0.16), Vector3(0.17, 1.48, 0.16), SKIN)
	var hair: Color = HAIR_GREY if kind == "elder" else HAIR_DARK
	pm.box(Vector3(-0.18, 1.4, -0.18), Vector3(0.18, 1.52, 0.17), hair)
	pm.box(Vector3(-0.18, 1.2, -0.18), Vector3(0.18, 1.45, -0.1), hair)
	# Eyes (a dark band on the +Z face).
	pm.box(Vector3(-0.11, 1.3, 0.155), Vector3(-0.05, 1.34, 0.165), Color(0.1, 0.08, 0.08))
	pm.box(Vector3(0.05, 1.3, 0.155), Vector3(0.11, 1.34, 0.165), Color(0.1, 0.08, 0.08))
	match kind:
		"elder":
			pm.box(Vector3(-0.3, 0.0, -0.19), Vector3(0.3, 0.2, 0.19), cloak.darkened(0.15))
			pm.box(Vector3(-0.19, 1.05, 0.14), Vector3(0.19, 1.2, 0.2), HAIR_GREY)  # beard
			pm.box(Vector3(0.44, 0.0, -0.04), Vector3(0.52, 1.7, 0.04), WOOD)       # staff
			pm.box(Vector3(0.4, 1.62, -0.08), Vector3(0.56, 1.76, 0.08), Color(0.55, 0.85, 0.5))
		"guard":
			pm.box(Vector3(-0.2, 1.38, -0.19), Vector3(0.2, 1.58, 0.19), IRON)      # helm
			pm.box(Vector3(-0.3, 0.7, 0.17), Vector3(0.3, 1.0, 0.2), IRON.darkened(0.1))
			pm.box(Vector3(0.45, 0.0, -0.03), Vector3(0.51, 2.0, 0.03), WOOD)       # spear
			pm.box(Vector3(0.43, 2.0, -0.05), Vector3(0.53, 2.25, 0.05), IRON.lightened(0.2))
			pm.box(Vector3(-0.56, 0.45, -0.18), Vector3(-0.44, 1.0, 0.18), cloak.lightened(0.2))
		"trainer":
			pm.box(Vector3(-0.32, 0.4, -0.24), Vector3(0.32, 1.1, -0.17), cloak.darkened(0.25))  # cape
			pm.box(Vector3(0.18, 0.55, 0.16), Vector3(0.34, 0.75, 0.24), WOOD)                   # satchel
			pm.box(Vector3(-0.2, 1.46, -0.2), Vector3(0.2, 1.54, 0.2), cloak.darkened(0.3))      # headband
		"officer":
			pm.box(Vector3(-0.36, 0.95, -0.2), Vector3(-0.2, 1.14, 0.2), IRON)                   # pauldrons
			pm.box(Vector3(0.2, 0.95, -0.2), Vector3(0.36, 1.14, 0.2), IRON)
			pm.box(Vector3(-0.2, 0.62, 0.17), Vector3(0.2, 1.0, 0.2), GOLD.darkened(0.25))       # tabard crest
			pm.box(Vector3(-0.34, 0.3, -0.26), Vector3(0.34, 1.12, -0.18), cloak.darkened(0.35)) # cape
			pm.box(Vector3(-0.47, 0.2, -0.04), Vector3(-0.41, 0.7, 0.04), IRON.lightened(0.25))  # sword
			pm.box(Vector3(-0.5, 0.66, -0.07), Vector3(-0.38, 0.7, 0.07), GOLD)
		"raider":
			var hood: Color = Color(0.13, 0.11, 0.11)
			pm.box(Vector3(-0.2, 1.36, -0.2), Vector3(0.2, 1.58, 0.19), hood)                    # hood
			pm.box(Vector3(-0.2, 1.16, -0.2), Vector3(-0.15, 1.4, 0.19), hood)
			pm.box(Vector3(0.15, 1.16, -0.2), Vector3(0.2, 1.4, 0.19), hood)
			pm.box(Vector3(-0.18, 1.16, 0.15), Vector3(0.18, 1.27, 0.19), hood)                  # face wrap
			pm.box(Vector3(-0.34, 0.12, -0.26), Vector3(0.34, 1.12, -0.18), hood.lightened(0.05)) # long cloak
			pm.box(Vector3(-0.3, 0.72, 0.17), Vector3(0.3, 0.8, 0.2), cloak.lightened(0.2))      # sash
			pm.box(Vector3(0.44, 0.35, -0.03), Vector3(0.5, 1.05, 0.03), IRON.lightened(0.1))    # blade
			pm.box(Vector3(0.5, 0.85, -0.03), Vector3(0.58, 1.05, 0.03), IRON.lightened(0.1))
		"scholar":
			pm.box(Vector3(-0.3, 0.0, -0.19), Vector3(0.3, 0.16, 0.19), cloak.darkened(0.15))
			pm.box(Vector3(-0.3, 0.95, 0.16), Vector3(0.3, 1.04, 0.2), cloak.lightened(0.3))     # collar
			pm.box(Vector3(-0.35, 0.5, -0.12), Vector3(-0.27, 1.02, 0.12), WOOD)                 # satchel strap
			pm.box(Vector3(-0.46, 0.4, -0.1), Vector3(-0.3, 0.62, 0.14), WOOD)                   # satchel
			var shard := Color(0.55, 0.95, 1.0)
			pm.box(Vector3(-0.05, 0.78, 0.18), Vector3(0.05, 0.92, 0.22), shard)                 # shard pendant
			pm.box(Vector3(-0.19, 1.2, -0.19), Vector3(0.19, 1.35, -0.12), HAIR_DARK.lightened(0.25))
		"noble":
			pm.box(Vector3(-0.3, 0.0, -0.19), Vector3(0.3, 0.16, 0.19), GOLD.darkened(0.2))
			pm.box(Vector3(-0.06, 0.16, 0.17), Vector3(0.06, 1.0, 0.2), GOLD)                    # trim
			pm.box(Vector3(-0.18, 1.5, -0.18), Vector3(0.18, 1.58, 0.18), GOLD)                  # circlet
		_:
			pm.box(Vector3(-0.22, 0.3, 0.16), Vector3(0.22, 0.95, 0.2), Color(0.9, 0.86, 0.76))  # apron
	var mi := _node(pm, "Body")
	# Low-poly people read a touch small next to the roster creatures; keep them human-sized.
	mi.scale = Vector3.ONE * (0.8 if kind == "child" else 1.12)
	root.add_child(mi)
	return root


# =====================================================================================
#  Village / castle-town kit (PropEntity kinds)
# =====================================================================================

const PLASTER := Color(0.88, 0.83, 0.72)
const CHAR := Color(0.12, 0.1, 0.09)
const STRAW := Color(0.86, 0.72, 0.38)
const LEAF := Color(0.34, 0.55, 0.25)


## The builder for a [PropEntity] kind over [param footprint] (origin = the top-left cell's
## centre), tinted [param tint]; [param seed] varies flames / clutter deterministically.
static func prop(kind: String, footprint: Vector2i, tint: Color, seed: int = 0) -> Node3D:
	var fp := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	match kind:
		"ruin":
			return ruin(fp, tint, seed)
		"keep":
			return keep(fp, tint)
		"tower":
			return tower(fp, tint)
		"gate":
			return gatehouse(fp, tint)
		"windmill":
			return windmill(fp, tint)
		"stall":
			return stall(fp, tint)
		"well":
			return well(tint)
		"fence":
			return fence(fp, tint)
		"haystack":
			return haystack()
		"barrels":
			return barrels(seed)
		"cart":
			return cart(tint)
		"crops":
			return crops(fp, tint)
		"banner":
			return banner(tint)
		"dummy":
			return dummy()
		"crystal":
			return crystal(tint)
		"fire":
			return fire(seed)
		"rubble":
			return rubble(seed)
		"arena":
			return arena(fp, tint)
	return house(fp, tint)


## THE TOURNAMENT ARENA (DECISIONS.md #33): an elliptical stone drum filling the footprint -- an
## arcaded outer wall, a crenellated rim with pennants in [param tint], a lower seating tier
## inside around a raked sand floor, and a gatehouse arch on the south face (the entrance, toward
## the camera).
static func arena(footprint: Vector2i, tint: Color = Color(0.2, 0.26, 0.42)) -> Node3D:
	var e: Array = _extent(footprint, 0.1)
	var x0: float = e[0]
	var z0: float = e[1]
	var x1: float = e[2]
	var z1: float = e[3]
	var c := Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	var rx: float = (x1 - x0) * 0.5
	var rz: float = (z1 - z0) * 0.5
	var stone := Color(0.76, 0.72, 0.63)
	var sand := Color(0.87, 0.77, 0.54)
	var seat := Color(0.62, 0.58, 0.52)
	var wall_h: float = 2.5
	var tier_h: float = 1.1
	var thick: float = 0.55
	var n: int = 24
	var pt := func(i: int, sx: float, sz: float, y: float) -> Vector3:
		var a: float = TAU * float(i) / float(n)
		return Vector3(c.x + cos(a) * sx, y, c.z + sin(a) * sz)
	var pm := ProcMesh.new()
	var ix: float = rx - thick
	var iz: float = rz - thick
	var sx: float = maxf(0.5, ix - 0.75)
	var sz: float = maxf(0.4, iz - 0.75)
	for i in n:
		var j: int = (i + 1) % n
		var o0: Vector3 = pt.call(i, rx, rz, 0.0)
		var o1: Vector3 = pt.call(j, rx, rz, 0.0)
		var out_n: Vector3 = ((o0 + o1) * 0.5 - c)
		out_n.y = 0.0
		out_n = out_n.normalized()
		var up := Vector3(0, wall_h, 0)
		var shade: Color = stone.darkened(0.05 * float(i % 2))
		# The outer wall and its arcade (a dark arch opening on each bay).
		pm.quad(o0, o1, o1 + up, o0 + up, out_n, shade)
		var m0: Vector3 = o0.lerp(o1, 0.28) + out_n * 0.03
		var m1: Vector3 = o0.lerp(o1, 0.72) + out_n * 0.03
		pm.quad(m0 + Vector3(0, 0.25, 0), m1 + Vector3(0, 0.25, 0), m1 + Vector3(0, 1.45, 0), m0 + Vector3(0, 1.45, 0), out_n, Color(0.22, 0.2, 0.2))
		# The inner face and the rim.
		var i0: Vector3 = pt.call(i, ix, iz, 0.0)
		var i1: Vector3 = pt.call(j, ix, iz, 0.0)
		pm.quad(i1, i0, i0 + up, i1 + up, -out_n, stone.darkened(0.18))
		pm.quad(o0 + up, o1 + up, i1 + up, i0 + up, Vector3.UP, stone.lightened(0.06))
		# Merlons on every other bay.
		if i % 2 == 0:
			var mid: Vector3 = (o0 + o1) * 0.5 * 0.85 + (i0 + i1) * 0.5 * 0.15
			pm.box(Vector3(mid.x - 0.18, wall_h, mid.z - 0.18), Vector3(mid.x + 0.18, wall_h + 0.35, mid.z + 0.18), stone)
		# The seating tier: a lower ring stepping down to the floor.
		var t0: Vector3 = pt.call(i, sx, sz, 0.0)
		var t1: Vector3 = pt.call(j, sx, sz, 0.0)
		var tu := Vector3(0, tier_h, 0)
		pm.quad(i0 + tu, i1 + tu, t1 + tu, t0 + tu, Vector3.UP, seat.darkened(0.04 * float(i % 3)))
		pm.quad(t1, t0, t0 + tu, t1 + tu, -out_n, seat.darkened(0.2))
		# The sand floor (a fan).
		var f0: Vector3 = pt.call(i, sx, sz, 0.06)
		var f1: Vector3 = pt.call(j, sx, sz, 0.06)
		var fc := Vector3(c.x, 0.06, c.z)
		pm.quad(fc, f1, f0, f0, Vector3.UP, sand.darkened(0.03 * float(i % 2)))
	# The gatehouse on the south face.
	var gz: float = c.z + rz
	pm.box(Vector3(c.x - 1.0, 0.0, gz - 0.9), Vector3(c.x + 1.0, wall_h + 0.9, gz + 0.15), stone.darkened(0.08), stone.lightened(0.04))
	_battlements(pm, c.x - 1.0, gz - 0.9, c.x + 1.0, gz + 0.15, wall_h + 0.9, stone.darkened(0.08), 0.5)
	pm.box(Vector3(c.x - 0.55, 0.0, gz + 0.15), Vector3(c.x + 0.55, 1.9, gz + 0.19), Color(0.16, 0.14, 0.14))
	pm.box(Vector3(c.x - 0.7, 1.9, gz + 0.15), Vector3(c.x + 0.7, 2.25, gz + 0.2), tint)
	var root := _wrap(pm, "Arena")
	# Pennants around the rim, and two banners flanking the gate.
	for k in 6:
		var a: float = TAU * (float(k) + 0.5) / 6.0
		var b := banner(tint, 1.6, true)
		b.position = Vector3(c.x + cos(a) * (rx - thick * 0.5), wall_h, c.z + sin(a) * (rz - thick * 0.5))
		b.scale = Vector3.ONE * 0.8
		root.add_child(b)
	for bx in [c.x - 1.35, c.x + 1.35]:
		var g := banner(tint, 0.0, false)
		g.position = Vector3(bx, 0.9, gz + 0.1)
		root.add_child(g)
	return root


## The footprint's inner rect in local space: [x0, z0, x1, z1] inset by [param inset].
static func _extent(fp: Vector2i, inset: float) -> Array:
	var cs: float = Cells.CELL_SIZE
	return [-cs * 0.5 + inset, -cs * 0.5 + inset, fp.x * cs - cs * 0.5 - inset, fp.y * cs - cs * 0.5 - inset]


static func _wrap(pm: ProcMesh, node_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.add_child(_node(pm, "Body"))
	return root


## A four-sided pyramid roof over [lo, hi] (x/z) from [param base_y] to [param apex_y].
static func _pyramid(pm: ProcMesh, x0: float, z0: float, x1: float, z1: float, base_y: float,
		apex_y: float, col: Color) -> void:
	var apex := Vector3((x0 + x1) * 0.5, apex_y, (z0 + z1) * 0.5)
	var a := Vector3(x0, base_y, z1)
	var b := Vector3(x1, base_y, z1)
	var c := Vector3(x1, base_y, z0)
	var d := Vector3(x0, base_y, z0)
	pm.quad(a, b, apex, apex, Vector3(0, 0.6, 1).normalized(), col)
	pm.quad(b, c, apex, apex, Vector3(1, 0.6, 0).normalized(), col.darkened(0.1))
	pm.quad(c, d, apex, apex, Vector3(0, 0.6, -1).normalized(), col.darkened(0.2))
	pm.quad(d, a, apex, apex, Vector3(-1, 0.6, 0).normalized(), col.darkened(0.1))


## Crenellations (merlons) along the top edge of a block at height [param y].
static func _battlements(pm: ProcMesh, x0: float, z0: float, x1: float, z1: float, y: float,
		col: Color, step: float = 0.7) -> void:
	var m: float = step * 0.5
	var x: float = x0
	while x < x1 - 0.05:
		var xe: float = minf(x + m, x1)
		pm.box(Vector3(x, y, z1 - 0.25), Vector3(xe, y + 0.4, z1), col)
		pm.box(Vector3(x, y, z0), Vector3(xe, y + 0.4, z0 + 0.25), col)
		x += step
	var z: float = z0
	while z < z1 - 0.05:
		var ze: float = minf(z + m, z1)
		pm.box(Vector3(x0, y, z), Vector3(x0 + 0.25, y + 0.4, ze), col)
		pm.box(Vector3(x1 - 0.25, y, z), Vector3(x1, y + 0.4, ze), col)
		z += step


## An octagonal prism (barrels, a well shaft, round towers) centred on [param c].
static func _octagon(pm: ProcMesh, c: Vector3, r: float, h: float, col: Color, top: Color = Color(0, 0, 0, 0)) -> void:
	var tc: Color = col if top.a <= 0.0 else top
	var pts: Array[Vector3] = []
	for i in 8:
		var a: float = TAU * (float(i) + 0.5) / 8.0
		pts.append(Vector3(c.x + cos(a) * r, c.y, c.z + sin(a) * r))
	var up := Vector3(0, h, 0)
	for i in 8:
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % 8]
		var mid: Vector3 = ((p0 + p1) * 0.5 - c)
		mid.y = 0.0
		pm.quad(p0, p1, p1 + up, p0 + up, mid.normalized(), col.darkened(0.06 * float(i % 3)))
	var ct := c + up
	for i in 8:
		pm.quad(pts[i] + up, pts[(i + 1) % 8] + up, ct, ct, Vector3.UP, tc)


## A house burned out: charred stumps of wall, fallen roof beams, a fire or two and rubble.
static func ruin(footprint: Vector2i, _tint: Color = CHAR, seed: int = 0) -> Node3D:
	var e: Array = _extent(footprint, 0.08)
	var x0: float = e[0]
	var z0: float = e[1]
	var x1: float = e[2]
	var z1: float = e[3]
	var burnt := PLASTER.darkened(0.62)
	var pm := ProcMesh.new()
	# Wall stumps along each side, broken to uneven heights.
	var seg: float = 0.9
	var i: int = 0
	var x: float = x0
	while x < x1 - 0.05:
		var xe: float = minf(x + seg, x1)
		var hs: float = 0.25 + ProcMesh.hash01(seed, i, 1) * 1.3
		var hn: float = 0.4 + ProcMesh.hash01(seed, i, 2) * 1.5
		pm.box(Vector3(x, 0.0, z1 - 0.2), Vector3(xe, hs, z1), burnt)
		pm.box(Vector3(x, 0.0, z0), Vector3(xe, hn, z0 + 0.2), burnt.darkened(0.1))
		x += seg
		i += 1
	var z: float = z0
	while z < z1 - 0.05:
		var ze: float = minf(z + seg, z1)
		pm.box(Vector3(x0, 0.0, z), Vector3(x0 + 0.2, 0.3 + ProcMesh.hash01(seed, i, 3) * 1.4, ze), burnt)
		pm.box(Vector3(x1 - 0.2, 0.0, z), Vector3(x1, 0.3 + ProcMesh.hash01(seed, i, 4) * 1.4, ze), burnt)
		z += seg
		i += 1
	# Blackened corner posts, one still standing tall.
	pm.box(Vector3(x0, 0.0, z1 - 0.18), Vector3(x0 + 0.18, 1.9, z1), CHAR)
	pm.box(Vector3(x1 - 0.18, 0.0, z0), Vector3(x1, 1.5, z0 + 0.18), CHAR)
	# Fallen beams across the (smouldering) floor.
	pm.box_oriented(Vector3((x0 + x1) * 0.5, 0.06, (z0 + z1) * 0.5), Vector3(0.8, 0, 0.6).normalized(),
		Vector3(-0.6, 0, 0.8).normalized(), Vector3(-(x1 - x0) * 0.45, 0.0, -0.1), Vector3((x1 - x0) * 0.45, 0.18, 0.1), CHAR)
	pm.box_oriented(Vector3((x0 + x1) * 0.5, 0.06, (z0 + z1) * 0.5 + 0.4), Vector3(0.9, 0, -0.44).normalized(),
		Vector3(0.44, 0, 0.9).normalized(), Vector3(-(x1 - x0) * 0.35, 0.0, -0.09), Vector3((x1 - x0) * 0.35, 0.16, 0.09), CHAR.lightened(0.05))
	var root := _wrap(pm, "Ruin")
	root.add_child(_rubble_node(seed + 7, Vector3(x0 + 0.8, 0.06, z1 - 0.8)))
	var fx := fire(seed)
	fx.position = Vector3(lerpf(x0, x1, 0.3 + ProcMesh.hash01(seed, 9, 9) * 0.4), 0.06, (z0 + z1) * 0.5)
	root.add_child(fx)
	return root


## A castle keep over a wall block: a tall stone hall, four corner towers with cone roofs in
## [param tint], battlements, a great door and banners on the south face.
static func keep(footprint: Vector2i, tint: Color = Color(0.2, 0.26, 0.42)) -> Node3D:
	var e: Array = _extent(footprint, 0.05)
	var x0: float = e[0]
	var z0: float = e[1]
	var x1: float = e[2]
	var z1: float = e[3]
	var stone := Color(0.7, 0.68, 0.62)
	var pm := ProcMesh.new()
	var hall_h: float = 4.6
	pm.box(Vector3(x0 + 0.6, 0.0, z0 + 0.6), Vector3(x1 - 0.6, hall_h, z1 - 0.3), stone, stone.darkened(0.15))
	_battlements(pm, x0 + 0.6, z0 + 0.6, x1 - 0.6, z1 - 0.3, hall_h, stone)
	# The donjon: a taller block at the back centre.
	var mx: float = (x0 + x1) * 0.5
	var dz0: float = z0 + 0.8
	var dz1: float = z0 + (z1 - z0) * 0.55
	pm.box(Vector3(mx - 2.2, hall_h, dz0), Vector3(mx + 2.2, hall_h + 2.6, dz1), stone.lightened(0.04))
	_battlements(pm, mx - 2.2, dz0, mx + 2.2, dz1, hall_h + 2.6, stone.lightened(0.04))
	_pyramid(pm, mx - 1.4, dz0 + 0.5, mx + 1.4, dz1 - 0.5, hall_h + 3.0, hall_h + 5.4, tint)
	# Corner towers.
	var tw: float = 1.7
	for tx in [x0, x1 - tw]:
		for tz in [z0, z1 - tw]:
			var th: float = hall_h + 1.8
			pm.box(Vector3(tx, 0.0, tz), Vector3(tx + tw, th, tz + tw), stone.darkened(0.04))
			_battlements(pm, tx, tz, tx + tw, tz + tw, th, stone.darkened(0.04), 0.55)
			_pyramid(pm, tx + 0.15, tz + 0.15, tx + tw - 0.15, tz + tw - 0.15, th + 0.4, th + 2.6, tint)
			# Arrow slits.
			pm.box(Vector3(tx + tw * 0.5 - 0.07, th - 1.6, tz + tw), Vector3(tx + tw * 0.5 + 0.07, th - 0.9, tz + tw + 0.03), CHAR)
	# The great door (an arch of darker stone around dark oak) on the south face.
	pm.box(Vector3(mx - 1.0, 0.0, z1 - 0.3), Vector3(mx + 1.0, 2.6, z1 - 0.12), stone.darkened(0.25))
	pm.box(Vector3(mx - 0.75, 0.0, z1 - 0.12), Vector3(mx + 0.75, 2.2, z1 - 0.08), WOOD_DARK)
	pm.box(Vector3(mx - 0.05, 0.0, z1 - 0.08), Vector3(mx + 0.05, 2.2, z1 - 0.06), IRON)
	# Windows.
	for wx in [mx - 3.4, mx - 2.2, mx + 2.2, mx + 3.4]:
		pm.box(Vector3(wx - 0.18, 2.6, z1 - 0.3), Vector3(wx + 0.18, 3.5, z1 - 0.27), Color(0.16, 0.18, 0.24))
	var root := _wrap(pm, "Keep")
	# Banners in the kingdom's colours either side of the door.
	for bx in [mx - 1.7, mx + 1.7]:
		var b := banner(tint, 0.0, false)
		b.position = Vector3(bx, 1.2, z1 - 0.28)
		root.add_child(b)
	return root


## A squat wall tower with battlements and a cone roof.
static func tower(footprint: Vector2i = Vector2i.ONE, tint: Color = Color(0.2, 0.26, 0.42)) -> Node3D:
	var e: Array = _extent(footprint, -0.12)
	var stone := Color(0.66, 0.64, 0.58)
	var pm := ProcMesh.new()
	var h: float = 4.0
	pm.box(Vector3(e[0], 0.0, e[1]), Vector3(e[2], h, e[3]), stone)
	_battlements(pm, e[0], e[1], e[2], e[3], h, stone, 0.6)
	_pyramid(pm, e[0] + 0.2, e[1] + 0.2, e[2] - 0.2, e[3] - 0.2, h + 0.4, h + 2.4, tint)
	pm.box(Vector3(-0.08, h - 1.5, e[3]), Vector3(0.08, h - 0.8, e[3] + 0.03), CHAR)
	return _wrap(pm, "Tower")


## A gatehouse along the footprint's long axis: towers on the end cells, an arch over the rest.
static func gatehouse(footprint: Vector2i, tint: Color = Color(0.2, 0.26, 0.42)) -> Node3D:
	var cs: float = Cells.CELL_SIZE
	var stone := Color(0.66, 0.64, 0.58)
	var pm := ProcMesh.new()
	var vertical: bool = footprint.y >= footprint.x
	var n: int = footprint.y if vertical else footprint.x
	var h: float = 4.4
	for k in [0, n - 1]:
		var cx: float = 0.0 if vertical else float(k) * cs
		var cz: float = float(k) * cs if vertical else 0.0
		pm.box(Vector3(cx - 1.05, 0.0, cz - 1.05), Vector3(cx + 1.05, h, cz + 1.05), stone)
		_battlements(pm, cx - 1.05, cz - 1.05, cx + 1.05, cz + 1.05, h, stone, 0.6)
		_pyramid(pm, cx - 0.85, cz - 0.85, cx + 0.85, cz + 0.85, h + 0.4, h + 2.2, tint)
	# The arch: a lintel high over the passage cells (walkers pass beneath it).
	var a0: float = cs * 0.5
	var a1: float = float(n - 1) * cs - cs * 0.5
	if vertical:
		pm.box(Vector3(-0.9, 3.0, a0), Vector3(0.9, h - 0.2, a1), stone.darkened(0.08))
		_battlements(pm, -0.9, a0, 0.9, a1, h - 0.2, stone.darkened(0.08), 0.6)
	else:
		pm.box(Vector3(a0, 3.0, -0.9), Vector3(a1, h - 0.2, 0.9), stone.darkened(0.08))
		_battlements(pm, a0, -0.9, a1, 0.9, h - 0.2, stone.darkened(0.08), 0.6)
	return _wrap(pm, "Gatehouse")


## A mill tower with a cap and four sails on its south face.
static func windmill(footprint: Vector2i, tint: Color = Color(0.5, 0.3, 0.2)) -> Node3D:
	var e: Array = _extent(footprint, 0.25)
	var cx: float = (e[0] + e[2]) * 0.5
	var cz: float = (e[1] + e[3]) * 0.5
	var pm := ProcMesh.new()
	var levels := [[1.5, 0.0, 1.6], [1.3, 1.6, 3.0], [1.1, 3.0, 4.2]]
	for l in levels:
		var hw: float = l[0]
		pm.box(Vector3(cx - hw, l[1], cz - hw), Vector3(cx + hw, l[2], cz + hw), PLASTER.darkened(0.04 * float(levels.find(l))))
	pm.box(Vector3(cx - 0.35, 0.0, cz + 1.5), Vector3(cx + 0.35, 1.2, cz + 1.53), WOOD)
	_pyramid(pm, cx - 1.3, cz - 1.3, cx + 1.3, cz + 1.3, 4.2, 5.6, tint)
	# Sails: four blades in an X on the south face.
	var hub := Vector3(cx, 4.0, cz + 1.25)
	pm.box(hub - Vector3(0.18, 0.18, 0.0), hub + Vector3(0.18, 0.18, 0.2), WOOD_DARK)
	for k in 4:
		var a: float = PI * 0.25 + float(k) * PI * 0.5
		var dir := Vector3(cos(a), sin(a), 0.0)
		var side := Vector3(-sin(a), cos(a), 0.0)
		var p0: Vector3 = hub + Vector3(0, 0, 0.22) + dir * 0.3
		var p1: Vector3 = hub + Vector3(0, 0, 0.22) + dir * 3.0
		pm.quad(p0 - side * 0.06, p1 - side * 0.06, p1 + side * 0.06, p0 + side * 0.06, Vector3.BACK, WOOD_DARK)
		pm.quad(p0 + side * 0.06 + Vector3(0, 0, 0.01), p1 + side * 0.06 + Vector3(0, 0, 0.01),
			p1 + side * 0.55 + Vector3(0, 0, 0.01), p0 + side * 0.4 + Vector3(0, 0, 0.01), Vector3.BACK, PLASTER)
	return _wrap(pm, "Windmill")


## A market stall: a counter with wares, four posts and a striped awning in [param tint].
static func stall(footprint: Vector2i, tint: Color = Color(0.7, 0.25, 0.2)) -> Node3D:
	var e: Array = _extent(footprint, 0.25)
	var x0: float = e[0]
	var z0: float = e[1]
	var x1: float = e[2]
	var z1: float = e[3]
	var pm := ProcMesh.new()
	pm.box(Vector3(x0, 0.0, z0 + 0.3), Vector3(x1, 0.85, z1 - 0.2), WOOD, WOOD.lightened(0.1))
	for px in [x0, x1 - 0.12]:
		for pz in [z0, z1 - 0.12]:
			pm.box(Vector3(px, 0.0, pz), Vector3(px + 0.12, 2.1, pz + 0.12), WOOD_DARK)
	# Wares: small crates / produce along the counter.
	var wares := [Color(0.85, 0.3, 0.2), Color(0.95, 0.75, 0.25), Color(0.4, 0.65, 0.3), Color(0.6, 0.45, 0.7)]
	var n: int = maxi(2, int((x1 - x0) / 0.55))
	for k in n:
		var wx: float = lerpf(x0 + 0.2, x1 - 0.5, float(k) / float(maxi(1, n - 1)))
		pm.box(Vector3(wx, 0.85, z1 - 0.7), Vector3(wx + 0.32, 1.1, z1 - 0.35), wares[k % wares.size()])
	# Striped awning, sloping down toward the front.
	var stripes: int = maxi(3, int((x1 - x0) / 0.4))
	var sw: float = (x1 - x0 + 0.3) / float(stripes)
	for k in stripes:
		var sx0: float = x0 - 0.15 + float(k) * sw
		var col: Color = tint if k % 2 == 0 else Color(0.93, 0.9, 0.82)
		pm.quad(Vector3(sx0, 2.3, z0 - 0.1), Vector3(sx0 + sw, 2.3, z0 - 0.1),
			Vector3(sx0 + sw, 1.85, z1 + 0.25), Vector3(sx0, 1.85, z1 + 0.25), Vector3(0, 1, 0.6).normalized(), col)
	return _wrap(pm, "Stall")


## A stone well with a little roof in [param tint].
static func well(tint: Color = Color(0.5, 0.3, 0.2)) -> Node3D:
	var pm := ProcMesh.new()
	_octagon(pm, Vector3.ZERO, 0.62, 0.7, STONE, STONE.lightened(0.1))
	_octagon(pm, Vector3(0, 0.01, 0), 0.45, 0.72, Color(0.12, 0.2, 0.26))
	for px in [-0.62, 0.52]:
		pm.box(Vector3(px, 0.0, -0.05), Vector3(px + 0.1, 1.8, 0.05), WOOD_DARK)
	pm.box(Vector3(-0.6, 1.45, -0.03), Vector3(0.6, 1.53, 0.03), WOOD)
	pm.quad(Vector3(-0.85, 1.7, 0.6), Vector3(0.85, 1.7, 0.6), Vector3(0.85, 2.25, 0.0), Vector3(-0.85, 2.25, 0.0), Vector3(0, 1, 1).normalized(), tint)
	pm.quad(Vector3(0.85, 1.7, -0.6), Vector3(-0.85, 1.7, -0.6), Vector3(-0.85, 2.25, 0.0), Vector3(0.85, 2.25, 0.0), Vector3(0, 1, -1).normalized(), tint.darkened(0.2))
	pm.box(Vector3(0.05, 0.9, -0.1), Vector3(0.25, 1.15, 0.1), WOOD)
	return _wrap(pm, "Well")


## A split-rail fence along the footprint's long axis.
static func fence(footprint: Vector2i, tint: Color = WOOD) -> Node3D:
	var cs: float = Cells.CELL_SIZE
	var pm := ProcMesh.new()
	var along_x: bool = footprint.x >= footprint.y
	var length: float = float(footprint.x if along_x else footprint.y) * cs
	var start: float = -cs * 0.5 + 0.1
	var end_: float = start + length - 0.2
	var p: float = start
	while p <= end_ + 0.01:
		if along_x:
			pm.box(Vector3(p - 0.06, 0.0, -0.06), Vector3(p + 0.06, 0.9, 0.06), tint.darkened(0.15))
		else:
			pm.box(Vector3(-0.06, 0.0, p - 0.06), Vector3(0.06, 0.9, p + 0.06), tint.darkened(0.15))
		p += 1.0
	for ry in [0.35, 0.7]:
		if along_x:
			pm.box(Vector3(start, ry, -0.04), Vector3(end_, ry + 0.08, 0.04), tint)
		else:
			pm.box(Vector3(-0.04, ry, start), Vector3(0.04, ry + 0.08, end_), tint)
	return _wrap(pm, "Fence")


static func haystack() -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.7, 0.0, -0.6), Vector3(0.7, 0.6, 0.6), STRAW)
	pm.box(Vector3(-0.55, 0.6, -0.45), Vector3(0.55, 1.0, 0.45), STRAW.lightened(0.06))
	pm.box(Vector3(-0.35, 1.0, -0.3), Vector3(0.35, 1.25, 0.3), STRAW.lightened(0.12))
	return _wrap(pm, "Haystack")


static func barrels(seed: int = 0) -> Node3D:
	var pm := ProcMesh.new()
	var spots := [Vector3(-0.35, 0, -0.2), Vector3(0.35, 0, -0.15), Vector3(0.0, 0, 0.4)]
	for k in spots.size():
		var r: float = 0.28 + ProcMesh.hash01(seed, k, 5) * 0.06
		_octagon(pm, spots[k], r, 0.75, WOOD, WOOD.lightened(0.1))
		_octagon(pm, spots[k] + Vector3(0, 0.18, 0), r + 0.02, 0.06, IRON.darkened(0.2))
		_octagon(pm, spots[k] + Vector3(0, 0.56, 0), r + 0.02, 0.06, IRON.darkened(0.2))
	return _wrap(pm, "Barrels")


## A two-wheeled hand cart with a load in [param tint].
static func cart(tint: Color = STRAW) -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.8, 0.45, -0.45), Vector3(0.8, 0.6, 0.45), WOOD)
	pm.box(Vector3(-0.8, 0.6, 0.38), Vector3(0.8, 0.9, 0.45), WOOD_DARK)
	pm.box(Vector3(-0.8, 0.6, -0.45), Vector3(0.8, 0.9, -0.38), WOOD_DARK)
	pm.box(Vector3(-0.65, 0.6, -0.35), Vector3(0.6, 0.95, 0.35), tint)
	pm.box(Vector3(0.8, 0.5, -0.3), Vector3(1.5, 0.56, -0.24), WOOD_DARK)
	pm.box(Vector3(0.8, 0.5, 0.24), Vector3(1.5, 0.56, 0.3), WOOD_DARK)
	for wz in [0.47, -0.55]:
		pm.box(Vector3(-0.42, 0.0, wz), Vector3(0.42, 0.84, wz + 0.08), WOOD_DARK)
		pm.box(Vector3(-0.3, 0.12, wz - 0.01), Vector3(0.3, 0.72, wz + 0.09), WOOD.darkened(0.3))
	return _wrap(pm, "Cart")


## Rows of leafy crops over the footprint ([param tint] = the crop colour).
static func crops(footprint: Vector2i, tint: Color = LEAF) -> Node3D:
	var e: Array = _extent(footprint, 0.2)
	var pm := ProcMesh.new()
	var z: float = e[1]
	var row: int = 0
	while z < e[3] - 0.1:
		pm.box(Vector3(e[0], 0.0, z), Vector3(e[2], 0.12, z + 0.3), Color(0.36, 0.25, 0.16))
		var x: float = e[0] + 0.1
		var k: int = 0
		while x < e[2] - 0.2:
			var h: float = 0.3 + ProcMesh.hash01(row, k, 3) * 0.25
			var col: Color = tint if (k + row) % 5 != 0 else tint.lerp(STRAW, 0.6)
			pm.box(Vector3(x, 0.12, z + 0.02), Vector3(x + 0.26, 0.12 + h, z + 0.28), col)
			x += 0.42
			k += 1
		z += 0.6
		row += 1
	return _wrap(pm, "Crops")


## A pole with a hanging banner in [param tint] and a gold stripe. [param pole_h] 0 = the cloth
## alone (hung on a wall).
static func banner(tint: Color = Color(0.2, 0.26, 0.42), pole_h: float = 3.0, with_pole: bool = true) -> Node3D:
	var pm := ProcMesh.new()
	var top: float = pole_h if with_pole else 2.0
	if with_pole:
		pm.box(Vector3(-0.06, 0.0, -0.06), Vector3(0.06, pole_h + 0.2, 0.06), WOOD_DARK)
		pm.box(Vector3(-0.45, top - 0.06, -0.04), Vector3(0.45, top + 0.02, 0.04), WOOD_DARK)
	pm.quad(Vector3(-0.4, top, 0.06), Vector3(0.4, top, 0.06), Vector3(0.4, top - 1.3, 0.06), Vector3(-0.4, top - 1.3, 0.06), Vector3.BACK, tint)
	pm.quad(Vector3(-0.4, top - 1.3, 0.06), Vector3(0.4, top - 1.3, 0.06), Vector3(0.0, top - 1.6, 0.06), Vector3(0.0, top - 1.6, 0.06), Vector3.BACK, tint)
	pm.quad(Vector3(-0.08, top - 0.15, 0.07), Vector3(0.08, top - 0.15, 0.07), Vector3(0.08, top - 1.2, 0.07), Vector3(-0.08, top - 1.2, 0.07), Vector3.BACK, GOLD)
	return _wrap(pm, "Banner")


static func dummy() -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.06, 0.0, -0.06), Vector3(0.06, 1.7, 0.06), WOOD_DARK)
	pm.box(Vector3(-0.55, 1.15, -0.05), Vector3(0.55, 1.25, 0.05), WOOD_DARK)
	pm.box(Vector3(-0.25, 0.6, -0.18), Vector3(0.25, 1.35, 0.18), STRAW)
	pm.box(Vector3(-0.16, 1.35, -0.15), Vector3(0.16, 1.7, 0.15), Color(0.8, 0.7, 0.52))
	pm.box(Vector3(-0.26, 0.9, 0.18), Vector3(0.26, 1.0, 0.2), Color(0.6, 0.2, 0.16))
	return _wrap(pm, "Dummy")


## The Researcher's shard pylon: a carved plinth with a floating, glowing starstone crystal.
static func crystal(tint: Color = Color(0.5, 0.92, 1.0)) -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.5, 0.0, -0.5), Vector3(0.5, 0.3, 0.5), STONE.darkened(0.1))
	pm.box(Vector3(-0.32, 0.3, -0.32), Vector3(0.32, 1.0, 0.32), STONE)
	pm.box(Vector3(-0.4, 1.0, -0.4), Vector3(0.4, 1.12, 0.4), STONE.lightened(0.1))
	var root := _wrap(pm, "Crystal")
	var cm := ProcMesh.new()
	var top := Vector3(0, 2.25, 0)
	var bot := Vector3(0, 1.25, 0)
	var ring: Array[Vector3] = []
	for k in 6:
		var a: float = TAU * float(k) / 6.0
		ring.append(Vector3(cos(a) * 0.24, 1.75, sin(a) * 0.24))
	for k in 6:
		var p0: Vector3 = ring[k]
		var p1: Vector3 = ring[(k + 1) % 6]
		var out: Vector3 = ((p0 + p1) * 0.5 - Vector3(0, 1.75, 0)).normalized()
		cm.quad(p0, p1, top, top, (out + Vector3.UP * 0.5).normalized(), tint)
		cm.quad(p1, p0, bot, bot, (out - Vector3.UP * 0.5).normalized(), tint.darkened(0.2))
	var mi := MeshInstance3D.new()
	mi.name = "Shard"
	mi.mesh = cm.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.6
	mi.material_override = mat
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = tint
	light.light_energy = 1.0
	light.omni_range = 4.5
	light.position = Vector3(0, 1.8, 0)
	root.add_child(light)
	return root


## A burning patch: the tile FX fire (scorch decal, flame tongues, embers) plus a warm light.
static func fire(seed: int = 0, with_light: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Fire"
	var fx: Node3D = EffectFX.make(&"fire", Color(1.0, 0.45, 0.12), seed)
	if fx != null:
		root.add_child(fx)
	if with_light:
		var light := OmniLight3D.new()
		light.name = "FireLight"
		light.light_color = Color(1.0, 0.55, 0.2)
		light.light_energy = 1.3
		light.omni_range = 4.0
		light.position = Vector3(0, 1.0, 0)
		root.add_child(light)
	return root


static func rubble(seed: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Rubble"
	root.add_child(_rubble_node(seed, Vector3.ZERO))
	return root


static func _rubble_node(seed: int, at: Vector3) -> Node3D:
	var fx: Node3D = EffectFX.make(&"rubble", Color(0.3, 0.28, 0.26), seed)
	if fx == null:
		fx = Node3D.new()
	fx.position = at
	return fx


## A carved standing stone (a memorial cairn, a waymarker) with a rune in [param tint] and a
## few flowers at its foot.
static func standing_stone(tint: Color = Color(0.55, 0.9, 0.6)) -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.55, 0.0, -0.4), Vector3(0.55, 0.25, 0.4), STONE.darkened(0.15))
	pm.box(Vector3(-0.38, 0.25, -0.22), Vector3(0.38, 1.25, 0.22), STONE)
	pm.box(Vector3(-0.3, 1.25, -0.18), Vector3(0.3, 1.5, 0.18), STONE.lightened(0.08))
	pm.box(Vector3(-0.07, 0.55, 0.22), Vector3(0.07, 1.15, 0.24), tint)
	pm.box(Vector3(-0.2, 0.8, 0.22), Vector3(0.2, 0.88, 0.24), tint)
	var flowers := [Color(0.95, 0.9, 0.55), Color(0.85, 0.5, 0.65), Color(0.95, 0.95, 0.95)]
	for k in 5:
		var fx: float = -0.5 + float(k) * 0.25
		pm.box(Vector3(fx, 0.25, 0.42), Vector3(fx + 0.1, 0.36, 0.52), flowers[k % flowers.size()])
	return _wrap(pm, "Stone")


static func signpost(tint: Color = WOOD) -> Node3D:
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.07, 0.0, -0.07), Vector3(0.07, 1.1, 0.07), WOOD_DARK)
	pm.box(Vector3(-0.55, 0.75, -0.05), Vector3(0.55, 1.3, 0.05), tint)
	pm.box(Vector3(-0.5, 0.8, 0.05), Vector3(0.5, 1.25, 0.07), tint.lightened(0.12))
	var root := Node3D.new()
	root.name = "Sign"
	root.add_child(_node(pm, "Body"))
	return root


## A chest: a base and a separate "Lid" node (rotated open by [method set_chest_open]).
static func chest(tint: Color = WOOD) -> Node3D:
	var root := Node3D.new()
	root.name = "Chest"
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.45, 0.0, -0.3), Vector3(0.45, 0.45, 0.3), tint)
	pm.box(Vector3(-0.47, 0.18, -0.32), Vector3(0.47, 0.24, 0.32), GOLD.darkened(0.2))
	root.add_child(_node(pm, "Base"))
	var hinge := Node3D.new()
	hinge.name = "Lid"
	hinge.position = Vector3(0, 0.45, -0.3)
	var lp := ProcMesh.new()
	lp.box(Vector3(-0.46, 0.0, 0.0), Vector3(0.46, 0.2, 0.62), tint.lightened(0.08))
	lp.box(Vector3(-0.06, -0.08, 0.6), Vector3(0.06, 0.12, 0.66), GOLD)
	hinge.add_child(_node(lp, "LidMesh"))
	root.add_child(hinge)
	return root


static func set_chest_open(prop: Node3D, open: bool) -> void:
	if prop == null:
		return
	var lid := prop.get_node_or_null("Lid") as Node3D
	if lid != null:
		lid.rotation_degrees.x = -105.0 if open else 0.0


## A placeholder HOUSE over a [param footprint]-cell block (origin = the top-left cell's centre):
## plastered timber walls, a door on the south face, a gabled roof in [param tint].
static func house(footprint: Vector2i, tint: Color = Color(0.55, 0.3, 0.2)) -> Node3D:
	var root := Node3D.new()
	root.name = "House"
	var cs: float = Cells.CELL_SIZE
	var x0: float = -cs * 0.5 + 0.08
	var z0: float = -cs * 0.5 + 0.08
	var x1: float = footprint.x * cs - cs * 0.5 - 0.08
	var z1: float = footprint.y * cs - cs * 0.5 - 0.08
	var wall_h: float = 1.7
	var ridge_h: float = wall_h + 1.2 + 0.25 * footprint.y
	var plaster := Color(0.88, 0.83, 0.72)
	var pm := ProcMesh.new()
	pm.box(Vector3(x0, 0.0, z0), Vector3(x1, wall_h, z1), plaster, plaster.darkened(0.05))
	# Timber frame posts at the corners and a beam.
	for px in [x0, x1 - 0.14]:
		for pz in [z0, z1 - 0.14]:
			pm.box(Vector3(px - 0.02, 0.0, pz - 0.02), Vector3(px + 0.16, wall_h, pz + 0.16), WOOD_DARK)
	pm.box(Vector3(x0 - 0.02, wall_h - 0.16, z1 - 0.02), Vector3(x1 + 0.02, wall_h, z1 + 0.04), WOOD_DARK)
	# Door + windows on the south face (+Z, toward the camera).
	var mid: float = (x0 + x1) * 0.5
	pm.box(Vector3(mid - 0.32, 0.0, z1), Vector3(mid + 0.32, 1.25, z1 + 0.05), WOOD)
	pm.box(Vector3(x0 + 0.35, 0.8, z1), Vector3(x0 + 0.85, 1.25, z1 + 0.04), Color(0.2, 0.24, 0.3))
	pm.box(Vector3(x1 - 0.85, 0.8, z1), Vector3(x1 - 0.35, 1.25, z1 + 0.04), Color(0.2, 0.24, 0.3))
	# Gabled roof (ridge along X), with a little overhang.
	var o: float = 0.3
	var zm: float = (z0 + z1) * 0.5
	var a := Vector3(x0 - o, wall_h - 0.1, z1 + o)
	var b := Vector3(x1 + o, wall_h - 0.1, z1 + o)
	var r0 := Vector3(x0 - o, ridge_h, zm)
	var r1 := Vector3(x1 + o, ridge_h, zm)
	var c := Vector3(x1 + o, wall_h - 0.1, z0 - o)
	var d := Vector3(x0 - o, wall_h - 0.1, z0 - o)
	pm.quad(a, b, r1, r0, (Vector3(0, 1, 1)).normalized(), tint)
	pm.quad(c, d, r0, r1, (Vector3(0, 1, -1)).normalized(), tint.darkened(0.2))
	# Gable ends (triangles: a quad with a repeated corner).
	pm.quad(Vector3(x0, wall_h, z1), Vector3(x0, wall_h, z0), Vector3(x0, ridge_h - 0.1, zm), Vector3(x0, ridge_h - 0.1, zm), Vector3.LEFT, plaster.darkened(0.1))
	pm.quad(Vector3(x1, wall_h, z0), Vector3(x1, wall_h, z1), Vector3(x1, ridge_h - 0.1, zm), Vector3(x1, ridge_h - 0.1, zm), Vector3.RIGHT, plaster.darkened(0.1))
	# Chimney.
	pm.box(Vector3(x1 - 0.7, ridge_h - 0.6, zm - 0.5), Vector3(x1 - 0.35, ridge_h + 0.35, zm - 0.15), STONE)
	root.add_child(_node(pm, "Body"))
	return root


## The Wayshrine's standing stone: a carved pillar with a glowing leaf-green orb, set in the
## fountain. The orb brightens once the shrine is lit.
static func wayshrine(tint: Color = Color(0.55, 0.9, 0.6)) -> Node3D:
	var root := Node3D.new()
	root.name = "Wayshrine"
	var pm := ProcMesh.new()
	pm.box(Vector3(-0.42, 0.0, -0.42), Vector3(0.42, 0.25, 0.42), STONE.darkened(0.1))
	pm.box(Vector3(-0.22, 0.25, -0.22), Vector3(0.22, 1.35, 0.22), STONE)
	pm.box(Vector3(-0.3, 1.35, -0.3), Vector3(0.3, 1.5, 0.3), STONE.lightened(0.1))
	pm.box(Vector3(-0.08, 0.6, 0.22), Vector3(0.08, 1.1, 0.24), tint.darkened(0.3))
	root.add_child(_node(pm, "Pillar"))
	var orb := MeshInstance3D.new()
	orb.name = "Orb"
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	sphere.radial_segments = 12
	sphere.rings = 6
	orb.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 1.4
	orb.material_override = mat
	orb.position = Vector3(0, 1.75, 0)
	root.add_child(orb)
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = tint
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position = Vector3(0, 1.8, 0)
	root.add_child(light)
	return root
