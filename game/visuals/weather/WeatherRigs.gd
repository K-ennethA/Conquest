extends RefCounted
class_name WeatherRigs

## Builders for the per-weather particle rigs [WeatherFX] follows the camera with.
##
## Everything is [CPUParticles3D] + unshaded [StandardMaterial3D] + generated
## gradient textures, so it renders identically in the Compatibility (OpenGL 3) and
## Forward+ renderers, needs no imported assets, and costs a few thousand quads at
## most. Particles use world coordinates (local_coords = false) so drops already in
## flight stay put while the rig slides with the camera.
##
## A rig is a Node3D with meta:
##   "layers": Array of { node: CPUParticles3D, mat: StandardMaterial3D, alpha: float,
##                        amount: int, box: Vector3 (extents as a fraction of view
##                        size, y absolute), y: float (height above focus) }
## [WeatherFX] scales each layer's material alpha by the rig's weight (cross-fade)
## and its amount by the quality setting, and re-sizes the emission boxes to the
## camera's view.

const GROUND_Y := 0.1


static func build(kind: StringName) -> Node3D:
	match kind:
		&"rain":
			return _rain()
		&"sun":
			return _sun()
		&"sand":
			return _sand()
		&"bloom":
			return _bloom()
	return null


# --- Rain --------------------------------------------------------------------

static func _rain() -> Node3D:
	var rig := _rig("RainRig")
	# Falling streaks: tall thin camera-facing quads, slanted by the wind.
	var drops := _layer(rig, "Drops", 3000, Vector2(0.05, 1.5), soft_streak_texture(), Color(0.82, 0.9, 1.0), 0.75, false)
	drops.lifetime = 0.85
	drops.direction = Vector3(0.18, -1.0, 0.08)
	drops.spread = 3.0
	drops.initial_velocity_min = 30.0
	drops.initial_velocity_max = 36.0
	drops.gravity = Vector3(0, -6, 0)
	drops.angle_min = -9.0
	drops.angle_max = -7.0
	_set_box(rig, drops, Vector3(0.75, 3.0, 0.75), 17.0)
	# Splash droplets kicked up where drops land.
	var splash := _layer(rig, "Splash", 900, Vector2(0.14, 0.14), soft_dot_texture(0.3), Color(0.9, 0.95, 1.0), 0.85, false)
	splash.lifetime = 0.32
	splash.direction = Vector3(0, 1, 0)
	splash.spread = 55.0
	splash.initial_velocity_min = 1.6
	splash.initial_velocity_max = 3.2
	splash.gravity = Vector3(0, -14, 0)
	_set_box(rig, splash, Vector3(0.55, 0.02, 0.55), GROUND_Y + 0.08)
	# Ripple rings: flat expanding rings on the ground / water (see set_ripple_points).
	var rings := _layer(rig, "Ripples", 260, Vector2(1.2, 1.2), ring_texture(), Color(0.9, 0.95, 1.0), 0.9, true, true)
	rings.lifetime = 0.9
	rings.direction = Vector3(0, 1, 0)
	rings.initial_velocity_min = 0.0
	rings.initial_velocity_max = 0.0
	rings.gravity = Vector3.ZERO
	rings.scale_amount_min = 0.35
	rings.scale_amount_max = 0.8
	rings.scale_amount_curve = _curve([Vector2(0, 0.25), Vector2(1, 1.4)])
	rings.color_ramp = _fade_ramp(Color(1, 1, 1, 1), 0.0)
	_set_box(rig, rings, Vector3(0.5, 0.0, 0.5), GROUND_Y + 0.04)
	return rig


# --- Bright sun --------------------------------------------------------------

static func _sun() -> Node3D:
	var rig := _rig("SunRig")
	# Golden dust motes hanging in the light shafts.
	var motes := _layer(rig, "Motes", 320, Vector2(0.09, 0.09), soft_dot_texture(), Color(1.0, 0.86, 0.5), 0.9, true)
	motes.lifetime = 6.0
	motes.direction = Vector3(0.3, 0.4, 0.1)
	motes.spread = 180.0
	motes.initial_velocity_min = 0.15
	motes.initial_velocity_max = 0.5
	motes.gravity = Vector3(0, 0.03, 0)
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.6
	motes.color_ramp = _pulse_ramp(Color(1, 1, 1, 1))
	_set_box(rig, motes, Vector3(0.6, 3.5, 0.6), 4.0)
	# Heat shimmer sparkles just above the ground.
	var glints := _layer(rig, "Glints", 160, Vector2(0.14, 0.14), star_texture(), Color(1.0, 0.95, 0.75), 0.8, true)
	glints.lifetime = 1.6
	glints.initial_velocity_min = 0.0
	glints.initial_velocity_max = 0.2
	glints.gravity = Vector3(0, 0.2, 0)
	glints.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.5, 1), Vector2(1, 0)])
	_set_box(rig, glints, Vector3(0.55, 0.2, 0.55), GROUND_Y + 0.35)
	return rig


# --- Desert storm ------------------------------------------------------------

static func _sand() -> Node3D:
	var rig := _rig("SandRig")
	# Fast horizontal sand streaks.
	var grit := _layer(rig, "Grit", 1600, Vector2(0.9, 0.055), soft_dot_texture(0.2), Color(1.0, 0.9, 0.72), 0.95, false)
	grit.lifetime = 1.5
	grit.direction = Vector3(1.0, -0.05, 0.25)
	grit.spread = 6.0
	grit.initial_velocity_min = 16.0
	grit.initial_velocity_max = 26.0
	grit.gravity = Vector3(0, -0.5, 0)
	_set_box(rig, grit, Vector3(0.8, 4.0, 0.8), 3.5)
	# Big soft dust sheets rolling across the field.
	var sheets := _layer(rig, "DustSheets", 80, Vector2(12.0, 5.0), soft_dot_texture(), Color(0.74, 0.52, 0.32), 0.42, false)
	sheets.lifetime = 7.0
	sheets.direction = Vector3(1.0, 0.0, 0.2)
	sheets.spread = 8.0
	sheets.initial_velocity_min = 5.0
	sheets.initial_velocity_max = 8.0
	sheets.gravity = Vector3.ZERO
	sheets.scale_amount_min = 0.7
	sheets.scale_amount_max = 1.5
	sheets.color_ramp = _pulse_ramp(Color(1, 1, 1, 1))
	_set_box(rig, sheets, Vector3(0.8, 2.0, 0.8), 2.5)
	# Low ground-hugging drift.
	var drift := _layer(rig, "Drift", 300, Vector2(1.6, 0.35), soft_dot_texture(), Color(0.9, 0.72, 0.48), 0.35, false)
	drift.lifetime = 2.6
	drift.direction = Vector3(1.0, 0.02, 0.2)
	drift.spread = 5.0
	drift.initial_velocity_min = 7.0
	drift.initial_velocity_max = 11.0
	drift.gravity = Vector3.ZERO
	drift.color_ramp = _pulse_ramp(Color(1, 1, 1, 1))
	_set_box(rig, drift, Vector3(0.7, 0.3, 0.7), GROUND_Y + 0.4)
	return rig


# --- Overbloom ---------------------------------------------------------------

static func _bloom() -> Node3D:
	var rig := _rig("BloomRig")
	# Pollen motes drifting up and sideways.
	var pollen := _layer(rig, "Pollen", 420, Vector2(0.14, 0.14), soft_dot_texture(0.2), Color(1.0, 0.9, 0.4), 1.0, true)
	pollen.lifetime = 7.0
	pollen.direction = Vector3(0.4, 0.5, 0.2)
	pollen.spread = 120.0
	pollen.initial_velocity_min = 0.3
	pollen.initial_velocity_max = 0.9
	pollen.gravity = Vector3(0.05, 0.06, 0)
	pollen.scale_amount_min = 0.5
	pollen.scale_amount_max = 1.5
	pollen.color_ramp = _pulse_ramp(Color(1, 1, 1, 1))
	_set_box(rig, pollen, Vector3(0.6, 3.0, 0.6), 3.0)
	# Tumbling petals.
	var petals := _layer(rig, "Petals", 280, Vector2(0.4, 0.24), soft_dot_texture(0.45), Color(1, 1, 1), 1.0, false)
	petals.lifetime = 8.0
	petals.direction = Vector3(0.6, -0.3, 0.2)
	petals.spread = 40.0
	petals.initial_velocity_min = 0.6
	petals.initial_velocity_max = 1.4
	petals.gravity = Vector3(0.1, -0.35, 0)
	petals.angle_min = -180.0
	petals.angle_max = 180.0
	petals.angular_velocity_min = -120.0
	petals.angular_velocity_max = 120.0
	petals.color_initial_ramp = _palette([Color(1.0, 0.62, 0.82), Color(1.0, 0.86, 0.93), Color(0.86, 0.66, 1.0), Color(1.0, 0.74, 0.7)])
	_set_box(rig, petals, Vector3(0.6, 2.5, 0.6), 6.0)
	# Glowing flower specks twinkling on the ground.
	var specks := _layer(rig, "Specks", 300, Vector2(0.26, 0.26), star_texture(), Color(1, 1, 1), 1.0, true)
	specks.lifetime = 2.8
	specks.initial_velocity_min = 0.0
	specks.initial_velocity_max = 0.05
	specks.gravity = Vector3.ZERO
	specks.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.5, 1), Vector2(1, 0)])
	specks.color_initial_ramp = _palette([Color(1.0, 0.55, 0.85), Color(1.0, 0.9, 0.4), Color(0.75, 0.6, 1.0), Color(0.6, 1.0, 0.7)])
	_set_box(rig, specks, Vector3(0.55, 0.05, 0.55), GROUND_Y + 0.25)
	return rig


# --- Rig / layer plumbing ----------------------------------------------------

static func _rig(rig_name: String) -> Node3D:
	var rig := Node3D.new()
	rig.name = rig_name
	rig.set_meta("layers", [])
	return rig


## One particle layer. [param additive] = glow-blend; [param flat] = a horizontal
## plane (ripples) instead of a camera-facing quad.
static func _layer(rig: Node3D, layer_name: String, amount: int, size: Vector2, tex: Texture2D,
		tint: Color, alpha: float, additive: bool, flat: bool = false) -> CPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mesh: Mesh
	if flat:
		var pm := PlaneMesh.new()
		pm.size = size
		mesh = pm
	else:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		var qm := QuadMesh.new()
		qm.size = size
		mesh = qm
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	var p := CPUParticles3D.new()
	p.name = layer_name
	p.mesh = mesh
	p.amount = amount
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.preprocess = 2.0
	p.randomness = 0.6
	p.lifetime_randomness = 0.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.extra_cull_margin = 400.0
	rig.add_child(p)
	(rig.get_meta("layers") as Array).append({
		"node": p, "mat": mat, "alpha": alpha, "amount": amount, "box": Vector3.ONE, "y": 0.0,
	})
	return p


## Record the emission box of [param p]: x/z extents as a FRACTION of the camera's
## view size, y extent absolute, emitted at [param y] above the focus point.
static func _set_box(rig: Node3D, p: CPUParticles3D, box: Vector3, y: float) -> void:
	for layer in rig.get_meta("layers"):
		if layer["node"] == p:
			layer["box"] = box
			layer["y"] = y
	p.emission_box_extents = Vector3(20.0 * box.x, box.y, 20.0 * box.z)
	p.position = Vector3(0, y, 0)


static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	return c


## Colour ramp fading alpha in and out (a gentle life-cycle "pulse").
static func _pulse_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(c.r, c.g, c.b, 0.0), c, c, Color(c.r, c.g, c.b, 0.0)])
	return g


static func _fade_ramp(c: Color, end_alpha: float) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([c, Color(c.r, c.g, c.b, end_alpha)])
	return g


## A stepped palette for color_initial_ramp (each particle picks one colour).
static func _palette(colors: Array) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / float(colors.size()))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	return g


# --- Generated textures (cached) ---------------------------------------------

static var _tex_cache: Dictionary = {}


## Soft round dot (radial white -> transparent). [param core] = solid fraction.
static func soft_dot_texture(core: float = 0.0) -> Texture2D:
	var key := "dot%.2f" % core
	if _tex_cache.has(key):
		return _tex_cache[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, clampf(core, 0.0, 0.9), 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.85 if core > 0.0 else 0.6), Color(1, 1, 1, 0)])
	var t := _radial(g, 64)
	_tex_cache[key] = t
	return t


## Vertical streak: bright core fading to both ends.
static func soft_streak_texture() -> Texture2D:
	if _tex_cache.has("streak"):
		return _tex_cache["streak"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	var t := _radial(g, 32)
	_tex_cache["streak"] = t
	return t


## Thin ring for water ripples.
static func ring_texture() -> Texture2D:
	if _tex_cache.has("ring"):
		return _tex_cache["ring"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.72, 0.84, 0.92, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	var t := _radial(g, 64)
	_tex_cache["ring"] = t
	return t


## Bright core with a soft halo (twinkles / glints).
static func star_texture() -> Texture2D:
	if _tex_cache.has("star"):
		return _tex_cache["star"]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])
	var t := _radial(g, 64)
	_tex_cache["star"] = t
	return t


static func _radial(g: Gradient, px: int) -> GradientTexture2D:
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = px
	t.height = px
	return t
