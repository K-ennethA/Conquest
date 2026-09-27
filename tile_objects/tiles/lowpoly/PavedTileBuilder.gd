@tool
extends Node3D
class_name PavedTileBuilder

## Procedural paving for built terrain (castle flagstones, bridge planks). Like
## LowPolyTileBuilder it is a helper node under a tile scene: at load it builds a
## vertex-coloured "Paving" mesh on top of the sibling 2 x 0.2 x 2 base slab (the
## slab keeps the TileResource material, so it reads as mortar / the gaps between
## planks and stays highlightable), plus a masonry / timber base block under it.
## Variation is deterministic (hashed from the tile's world XZ) -- no flicker.

enum Style { FLAGSTONE, PLANKS }
@export var style: Style = Style.FLAGSTONE

const TOP := 0.10          # walkable surface == MapLoader.UNIT_GROUND_Y
const STONE := Color(0.42, 0.4, 0.37)
const STONE_ALT := Color(0.34, 0.33, 0.31)
const WOOD := Color(0.56, 0.38, 0.22)
const WOOD_ALT := Color(0.47, 0.31, 0.18)
const BASE_STONE := Color(0.27, 0.25, 0.23)
const BASE_WOOD := Color(0.36, 0.25, 0.15)


func _ready() -> void:
	var paving := get_node_or_null("Paving") as MeshInstance3D
	if paving == null:
		paving = MeshInstance3D.new()
		paving.name = "Paving"
		add_child(paving)
	paving.mesh = build_mesh(style, int(round(global_position.x)), int(round(global_position.z)), int(round(global_position.y)))
	paving.material_override = ProcMesh.material()


static func build_mesh(s: int, kx: int, kz: int, ky: int = 0) -> ArrayMesh:
	var pm := ProcMesh.new()
	if s == Style.PLANKS:
		_planks(pm, kx, kz, ky)
	else:
		_flagstones(pm, kx, kz, ky)
	return pm.commit()


static func _flagstones(pm: ProcMesh, kx: int, kz: int, ky: int) -> void:
	# Base masonry block (only really visible at the board edge / under decks).
	pm.box(Vector3(-0.97, -0.6, -0.97), Vector3(0.97, 0.02, 0.97), BASE_STONE)
	# Three courses of irregular slabs across Z, each split into 2-3 stones.
	var gap := 0.05
	var rows := [-1.0, -0.3, 0.38, 1.0]
	for r in 3:
		var z0: float = rows[r] + gap * 0.5
		var z1: float = rows[r + 1] - gap * 0.5
		var cuts: Array = [-1.0]
		var k := 2 + int(ProcMesh.hash01(kx, kz * 7 + r, ky) * 2.0)
		for i in range(1, k):
			var base := -1.0 + 2.0 * float(i) / float(k)
			cuts.append(base + (ProcMesh.hash01(kx + i, kz, r) - 0.5) * 0.35)
		cuts.append(1.0)
		for i in range(cuts.size() - 1):
			var x0: float = cuts[i] + gap * 0.5
			var x1: float = cuts[i + 1] - gap * 0.5
			var h := ProcMesh.hash01(kx * 3 + i, kz * 5 + r, ky + 11)
			var col := STONE.lerp(STONE_ALT, h)
			var top := TOP + 0.015 + h * 0.02
			pm.box(Vector3(x0, TOP - 0.06, z0), Vector3(x1, top, z1), col.darkened(0.1), col)


static func _planks(pm: ProcMesh, kx: int, kz: int, ky: int) -> void:
	# Timber joists underneath.
	pm.box(Vector3(-0.97, -0.28, -0.75), Vector3(0.97, 0.02, -0.55), BASE_WOOD)
	pm.box(Vector3(-0.97, -0.28, 0.55), Vector3(0.97, 0.02, 0.75), BASE_WOOD)
	# Planks run along Z; widths vary a little.
	var x := -1.0
	var i := 0
	while x < 0.99:
		var w := 0.34 + ProcMesh.hash01(kx + i, kz, ky) * 0.1
		var x1 := minf(1.0, x + w)
		var h := ProcMesh.hash01(kx * 7 + i, kz * 3, ky + 5)
		var col := WOOD.lerp(WOOD_ALT, h)
		var jitter := (ProcMesh.hash01(i, kx, kz) - 0.5) * 0.08
		pm.box(Vector3(x + 0.025, TOP - 0.06, -1.0 + maxf(0.0, jitter)), Vector3(x1 - 0.025, TOP + 0.02 + h * 0.012, 1.0 + minf(0.0, jitter)), col.darkened(0.15), col)
		x = x1
		i += 1
