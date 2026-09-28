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
## "trainer" (short cape, satchel), "villager" (apron).
static func figure(cloak: Color, kind: String = "villager") -> Node3D:
	var root := Node3D.new()
	root.name = "Figure"
	var pm := ProcMesh.new()
	var trousers: Color = cloak.darkened(0.45)
	var robe_len: float = 0.05 if kind == "elder" else 0.45
	# Legs / boots.
	if kind != "elder":
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
		_:
			pm.box(Vector3(-0.22, 0.3, 0.16), Vector3(0.22, 0.95, 0.2), Color(0.9, 0.86, 0.76))  # apron
	var mi := _node(pm, "Body")
	# Low-poly people read a touch small next to the roster creatures; keep them human-sized.
	mi.scale = Vector3.ONE * 1.12
	root.add_child(mi)
	return root


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
