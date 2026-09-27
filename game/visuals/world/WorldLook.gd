extends Node
class_name WorldLook

## ONE place that owns the battle scene's look: key light, sky / ambient, fog,
## tonemap + glow + colour grade, the haze the far landscape fades into, soft unit
## contact shadows and the cursor "see-through" focus point for tree canopies.
##
## Every knob is a plain property with a setter that applies immediately, so the
## WEATHER system (or a cutscene) can simply tween them:
##     create_tween().tween_property(look, "sun_energy", 0.6, 2.0)
## Material-level weather goes through the global shader uniforms documented in
## docs/WORLD_ART.md (weather_wetness, weather_dust, weather_bloom, weather_sun,
## wind_strength_global) -- see [method set_weather].
##
## Created by GameWorldManager._setup_lighting (node "WorldLook" under the scene
## root); find it with [method find]. Safe with no environment / no camera.

@export var sun_color: Color = Color(1.0, 0.93, 0.8):
	set(v):
		sun_color = v
		_apply()
@export var sun_energy: float = 1.55:
	set(v):
		sun_energy = v
		_apply()
## Sun orientation (degrees, like Node3D.rotation_degrees).
@export var sun_rotation_degrees: Vector3 = Vector3(-50.0, -36.0, 0.0):
	set(v):
		sun_rotation_degrees = v
		_apply()
@export var shadow_softness: float = 1.6:
	set(v):
		shadow_softness = v
		_apply()
@export var ambient_energy: float = 0.62:
	set(v):
		ambient_energy = v
		_apply()
## Sky gradient (also what the ambient light is sampled from).
@export var sky_top_color: Color = Color(0.42, 0.6, 0.78):
	set(v):
		sky_top_color = v
		_apply()
@export var sky_horizon_color: Color = Color(0.74, 0.82, 0.86):
	set(v):
		sky_horizon_color = v
		_apply()
## Colour the distant landscape fades into (global `haze_color`).
@export var haze_color: Color = Color(0.66, 0.75, 0.8):
	set(v):
		haze_color = v
		_apply()
@export var fog_density: float = 0.35:
	set(v):
		fog_density = v
		_apply()
@export var exposure: float = 1.0:
	set(v):
		exposure = v
		_apply()
@export var glow_intensity: float = 0.55:
	set(v):
		glow_intensity = v
		_apply()
@export var glow_bloom: float = 0.04:
	set(v):
		glow_bloom = v
		_apply()
@export var saturation: float = 1.0:
	set(v):
		saturation = v
		_apply()
@export var contrast: float = 1.03:
	set(v):
		contrast = v
		_apply()
@export var contact_shadows: bool = true

var sun: DirectionalLight3D = null
var environment: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _ready_to_apply := false
## Weather bridge (see [method apply_weather_look]): the un-weathered look, captured
## the first time weather is applied so every weather is RELATIVE to the map preset.
var _weather_base: Dictionary = {}
## Where depth fog starts; weather pulls it in (rain / sand close the view down).
var _fog_begin: float = 70.0

# Unit contact-shadow pool (blob quads following units; no unit files touched).
var _blob_pool: Array[MeshInstance3D] = []
var _units: Array = []
var _unit_refresh := 0.0


static func find(tree: SceneTree) -> WorldLook:
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("WorldLook") as WorldLook


## Attach to [param scene_root]: reuse/create the sun, adopt the WorldEnvironment.
func setup(scene_root: Node) -> void:
	sun = scene_root.get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		scene_root.add_child(sun)
	var we := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null:
		if we.environment == null:
			we.environment = Environment.new()
		environment = we.environment
	_weather_base = {}
	_fog_begin = 70.0
	_ready_to_apply = true
	add_to_group(&"world_look")
	_apply()


## Map lighting preset ("Day" default, "Dawn", "Dusk", "Night").
func apply_preset(preset: String) -> void:
	_weather_base = {}  # the preset is the new un-weathered base
	match preset:
		"Night":
			sun_color = Color(0.62, 0.7, 0.95)
			sun_energy = 0.55
			ambient_energy = 0.28
			sky_top_color = Color(0.08, 0.1, 0.2)
			sky_horizon_color = Color(0.2, 0.24, 0.34)
			haze_color = Color(0.16, 0.2, 0.28)
		"Dawn", "Dusk":
			sun_color = Color(1.0, 0.76, 0.58)
			sun_energy = 1.1
			ambient_energy = 0.42
			sky_top_color = Color(0.46, 0.5, 0.68)
			sky_horizon_color = Color(0.92, 0.72, 0.58)
			haze_color = Color(0.78, 0.66, 0.6)
		_:
			pass


## Convenience for the weather system: write the global material hooks at once.
static func set_weather(wetness: float, dust: float, bloom: float, sun_amt: float, wind: float = 1.0) -> void:
	RenderingServer.global_shader_parameter_set(&"weather_wetness", wetness)
	RenderingServer.global_shader_parameter_set(&"weather_dust", dust)
	RenderingServer.global_shader_parameter_set(&"weather_bloom", bloom)
	RenderingServer.global_shader_parameter_set(&"weather_sun", sun_amt)
	RenderingServer.global_shader_parameter_set(&"wind_strength_global", wind)


## Weather bridge: WeatherEnvAdapter hands every (cross-faded) weather look here
## when a node in group "world_look" exists. [param p] is
## WeatherEnvAdapter.params_for(): tints/scales relative to a neutral look, plus
## an EXPONENTIAL fog density (~0.0006 light .. 0.02 heavy) that is mapped onto this
## node's depth fog + haze. All properties are written in one batch, then applied once.
func apply_weather_look(p: Dictionary) -> void:
	if _weather_base.is_empty():
		_weather_base = {
			"sun_color": sun_color, "sun_energy": sun_energy, "ambient_energy": ambient_energy,
			"sky_top": sky_top_color, "sky_horizon": sky_horizon_color, "haze": haze_color,
			"fog": fog_density, "glow": glow_intensity, "bloom": glow_bloom,
			"saturation": saturation, "contrast": contrast, "exposure": exposure,
		}
	var b := _weather_base
	var was_ready := _ready_to_apply
	_ready_to_apply = false  # batch: setters below skip their own _apply()
	var neutral_sun := Color(1.0, 0.96, 0.88)
	var st: Color = p.get("sun_color", neutral_sun)
	var bs: Color = b["sun_color"]
	sun_color = Color(bs.r * st.r / neutral_sun.r, bs.g * st.g / neutral_sun.g, bs.b * st.b / neutral_sun.b, 1.0)
	sun_energy = float(b["sun_energy"]) * float(p.get("sun_energy_scale", 1.0))
	ambient_energy = float(b["ambient_energy"]) * float(p.get("ambient_scale", 1.0))
	var sky_tint: Color = p.get("sky_tint", Color(1, 1, 1))
	sky_top_color = (b["sky_top"] as Color) * sky_tint
	sky_horizon_color = (b["sky_horizon"] as Color) * sky_tint
	var fog_amt := clampf(float(p.get("fog_density", 0.0)) * 50.0, 0.0, 1.0)
	haze_color = (b["haze"] as Color).lerp(p.get("fog_color", b["haze"]), clampf(fog_amt * 1.2, 0.0, 0.85))
	fog_density = clampf(float(b["fog"]) + fog_amt * 0.45, 0.0, 1.0)
	_fog_begin = lerpf(70.0, 18.0, fog_amt)
	glow_intensity = float(b["glow"]) * float(p.get("glow_scale", 1.0))
	glow_bloom = float(b["bloom"]) + float(p.get("glow_bloom", 0.0))
	saturation = float(b["saturation"]) * float(p.get("saturation", 1.0))
	contrast = float(b["contrast"]) * float(p.get("contrast", 1.0))
	exposure = float(b["exposure"]) * float(p.get("brightness", 1.0))
	_ready_to_apply = was_ready
	_apply()
	set_weather(float(p.get("wetness", 0.0)), float(p.get("dust", 0.0)), float(p.get("bloom", 0.0)),
		float(p.get("sun", 0.0)), float(p.get("wind", 1.0)))


func _apply() -> void:
	if not _ready_to_apply:
		return
	RenderingServer.global_shader_parameter_set(&"haze_color", Vector3(haze_color.r, haze_color.g, haze_color.b))
	if sun != null:
		sun.rotation_degrees = sun_rotation_degrees
		sun.light_color = sun_color
		sun.light_energy = sun_energy
		sun.shadow_enabled = true
		sun.shadow_blur = shadow_softness
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.2
		sun.directional_shadow_max_distance = 140.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	if environment == null:
		return
	var env := environment
	if _sky_mat == null:
		var sky := env.sky
		if sky == null:
			sky = Sky.new()
			env.sky = sky
		_sky_mat = sky.sky_material as ProceduralSkyMaterial
		if _sky_mat == null:
			_sky_mat = ProceduralSkyMaterial.new()
			sky.sky_material = _sky_mat
	env.background_mode = Environment.BG_SKY
	_sky_mat.sky_top_color = sky_top_color
	_sky_mat.sky_horizon_color = sky_horizon_color
	_sky_mat.ground_horizon_color = haze_color
	_sky_mat.ground_bottom_color = haze_color.darkened(0.25)
	_sky_mat.sun_angle_max = 20.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	env.ambient_light_sky_contribution = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.tonemap_white = 6.0
	env.glow_enabled = glow_intensity > 0.0
	env.glow_intensity = glow_intensity
	env.glow_bloom = glow_bloom
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = saturation
	env.adjustment_contrast = contrast
	env.adjustment_brightness = 1.0
	# Aerial perspective for anything far (the world skirt also hazes by distance
	# from the board in its own shaders, so this stays gentle).
	env.fog_enabled = fog_density > 0.0
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = haze_color
	env.fog_density = fog_density
	env.fog_depth_begin = _fog_begin
	env.fog_depth_end = 240.0
	env.fog_depth_curve = 1.6
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0
	# Screen-space AO is Forward+ only; harmless (ignored) elsewhere.
	env.ssao_enabled = true
	env.ssao_radius = 0.8
	env.ssao_intensity = 1.4
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.1


func _process(delta: float) -> void:
	_update_focus()
	if contact_shadows:
		_unit_refresh -= delta
		if _unit_refresh <= 0.0:
			_unit_refresh = 0.25
			_refresh_units()
		_place_blobs()


## Canopies dither away between the camera and the cursor (stylized_foliage).
func _update_focus() -> void:
	var scene := get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return
	var cursor := scene.get_node_or_null("Map/Cursor") as Node3D
	if cursor == null or not cursor.is_visible_in_tree():
		RenderingServer.global_shader_parameter_set(&"focus_world", Vector4(0, 0, 0, 0))
		return
	var p := cursor.global_position
	RenderingServer.global_shader_parameter_set(&"focus_world", Vector4(p.x, p.y, p.z, 1.0))


func _refresh_units() -> void:
	_units.clear()
	# Looked up dynamically (not the autoload identifier) so this script also
	# compiles in tool / -s contexts where autoloads aren't registered yet.
	var cs := get_node_or_null("/root/CombatServices")
	var board = cs.board() if cs != null and cs.has_method("board") else null
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			if u is Node3D and is_instance_valid(u):
				_units.append(u)


func _place_blobs() -> void:
	var used := 0
	for u in _units:
		if not is_instance_valid(u) or not (u as Node3D).is_visible_in_tree():
			continue
		var blob := _blob(used)
		var p: Vector3 = (u as Node3D).global_position
		blob.global_position = Vector3(p.x, p.y + 0.012, p.z)
		blob.visible = true
		used += 1
	for k in range(used, _blob_pool.size()):
		_blob_pool[k].visible = false


func _blob(i: int) -> MeshInstance3D:
	while _blob_pool.size() <= i:
		var mi := MeshInstance3D.new()
		mi.name = "UnitContactShadow%d" % _blob_pool.size()
		mi.mesh = TreeBuilder.shadow_mesh()
		mi.material_override = TreeBuilder.shadow_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation.x = -PI * 0.5
		mi.scale = Vector3(0.62, 0.62, 0.62)
		add_child(mi)
		_blob_pool.append(mi)
	return _blob_pool[i]
