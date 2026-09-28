extends RefCounted
class_name EffectFX

## Painterly, readable ground FX for TILE EFFECTS and hazards, in the same visual
## language as the world (see docs/WORLD_ART.md). Everything is shader-animated
## static geometry with SHARED materials (one per effect kind) -- no particles, no
## per-frame CPU -- so a board full of burning cells stays cheap:
##   fire     charred scorch decal with glowing cracks + stylized flame tongues +
##            rising embers
##   poison   bubbling toxic puddle + drifting green motes
##   ice      frost bloom with crystalline cracks + sparkle
##   heal     warm radiant rune ring + golden motes (sacred / healing / regen)
##   water    rippling puddle
##   fortify  golden rune circle
##   rubble   a few painted stones
##   other    soft ring tinted with the effect's TileEffectVisuals colour
## Variation (flame / mote placement) is deterministic per cell.

const DECAL_SHADER := "res://tile_objects/tiles/shaders/stylized_effect_decal.gdshader"
const FLAME_SHADER := "res://tile_objects/tiles/shaders/stylized_flame.gdshader"
const MOTE_SHADER := "res://tile_objects/tiles/shaders/stylized_motes.gdshader"

enum Kind { GENERIC, FIRE, POISON, ICE, HEAL, WATER, TELEGRAPH, FORTIFY }

static var _decal_mats: Dictionary = {}
static var _mote_mats: Dictionary = {}
static var _flame_mat: ShaderMaterial = null
static var _decal_mesh: PlaneMesh = null


## Effect id -> visual kind, or -1 for effects that need no ground FX (the terrain
## itself already shows them, e.g. tall grass; vine traps have their own visual).
static func kind_for(effect_id: StringName) -> int:
	var id := String(effect_id).to_lower()
	if id == "tall_grass" or id == "vine_trap":
		return -1
	if id.contains("fire") or id.contains("burn") or id.contains("scorch") or id.contains("lava") or id.contains("vent"):
		return Kind.FIRE
	if id.contains("poison") or id.contains("toxic") or id.contains("corrupt") or id.contains("venom"):
		return Kind.POISON
	if id.contains("ice") or id.contains("frost") or id.contains("freeze") or id.contains("snow"):
		return Kind.ICE
	if id.contains("heal") or id.contains("sacred") or id.contains("regen") or id.contains("sanct") or id.contains("bless"):
		return Kind.HEAL
	if id.contains("water") or id.contains("puddle") or id.contains("rain"):
		return Kind.WATER
	if id.contains("fortif") or id.contains("ward") or id.contains("shield"):
		return Kind.FORTIFY
	if id.contains("rubble") or id.contains("rock"):
		return 100
	return Kind.GENERIC


## Ground FX node for [param effect_id] at a cell (local origin = tile top centre),
## or null when the effect needs none. [param tint] is the effect's UI colour.
static func make(effect_id: StringName, tint: Color, seed: int) -> Node3D:
	var k := kind_for(effect_id)
	if k < 0:
		return null
	var root := Node3D.new()
	root.name = "GroundFX_" + String(effect_id)
	if k == 100:
		_add_rubble(root, seed)
		root.add_child(decal(Kind.GENERIC, Color(0.45, 0.42, 0.38), 0.5))
		return root
	var strength := 1.0
	root.add_child(decal(k, tint, strength))
	match k:
		Kind.FIRE:
			root.add_child(_flames(seed))
			root.add_child(_motes(seed, 6, Color(1.0, 0.55, 0.15), 0.9))
		Kind.POISON:
			root.add_child(_motes(seed, 7, Color(0.55, 0.95, 0.3), 0.45))
		Kind.HEAL:
			root.add_child(_motes(seed, 8, Color(1.0, 0.9, 0.5), 0.8))
		Kind.ICE:
			root.add_child(_motes(seed, 4, Color(0.75, 0.92, 1.0), 0.3))
	return root


## A flat decal quad of [param k] (see stylized_effect_decal.gdshader).
static func decal(k: int, tint: Color, strength: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Decal"
	if _decal_mesh == null:
		_decal_mesh = PlaneMesh.new()
		_decal_mesh.size = Vector2(1.94, 1.94)
	mi.mesh = _decal_mesh
	mi.material_override = decal_material(k, tint, strength)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, 0.018, 0.0)
	return mi


static func decal_material(k: int, tint: Color, strength: float = 1.0) -> ShaderMaterial:
	var key := "%d_%s_%.2f" % [k, tint.to_html(false), strength]
	if not _decal_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = load(DECAL_SHADER)
		m.set_shader_parameter("kind", k)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("strength", strength)
		m.render_priority = 1
		_decal_mats[key] = m
	return _decal_mats[key]


static func _flames(seed: int) -> MeshInstance3D:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	var count := 7
	for i in count:
		var a := TAU * float(i) / float(count) + ProcMesh.hash01(seed, i, 1) * 0.8
		var rr := 0.15 + ProcMesh.hash01(seed, i, 2) * 0.55
		var p := Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		var size := 1.0 - rr * 0.9 + ProcMesh.hash01(seed, i, 3) * 0.3
		var ph := ProcMesh.hash01(seed, i, 4)
		for k in corners:
			v.append(p)
			uv.append(Vector2(k.x, k.y))
			c.append(Color(clampf(size, 0.0, 1.0), 0, 0, ph))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Flames"
	mi.mesh = m
	if _flame_mat == null:
		_flame_mat = ShaderMaterial.new()
		_flame_mat.shader = load(FLAME_SHADER)
		_flame_mat.render_priority = 2
	mi.material_override = _flame_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1.2, -0.1, -1.2), Vector3(2.4, 1.5, 2.4))
	return mi


static func _motes(seed: int, count: int, col: Color, rise: float) -> MeshInstance3D:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var corners := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]
	for i in count:
		var p := Vector3(ProcMesh.hash01(seed, i, 11) * 1.4 - 0.7, 0.05 + ProcMesh.hash01(seed, i, 12) * 0.3,
			ProcMesh.hash01(seed, i, 13) * 1.4 - 0.7)
		var ph := ProcMesh.hash01(seed, i, 14)
		for k in corners:
			v.append(p)
			uv.append(k)
			c.append(Color(1, 1, 1, ph))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Motes"
	mi.mesh = m
	var key := "%s_%.2f" % [col.to_html(false), rise]
	if not _mote_mats.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = load(MOTE_SHADER)
		mat.set_shader_parameter("mote_color", col)
		mat.set_shader_parameter("rise", rise)
		mat.set_shader_parameter("mote_size", 0.06)
		mat.render_priority = 2
		_mote_mats[key] = mat
	mi.material_override = _mote_mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1.2, -0.2, -1.2), Vector3(2.4, 2.0, 2.4))
	return mi


static func _add_rubble(root: Node3D, seed: int) -> void:
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Rubble%d" % i
		mi.mesh = WorldSkirt._rock_mesh()
		mi.material_override = ProcMesh.material()
		var a := TAU * ProcMesh.hash01(seed, i, 21)
		var r := 0.2 + ProcMesh.hash01(seed, i, 22) * 0.5
		var s := 0.35 + ProcMesh.hash01(seed, i, 23) * 0.3
		mi.position = Vector3(cos(a) * r, -0.02, sin(a) * r)
		mi.rotation.y = a * 3.0
		mi.scale = Vector3(s, s * 0.8, s)
		root.add_child(mi)
