extends RefCounted
class_name WeatherEnvAdapter

## Adapter between [WeatherFX] and the battle scene's lighting: the key light
## ("Sun" DirectionalLight3D), the WorldEnvironment (ambient, fog, glow, colour
## adjustments, procedural sky) and the world-art global shader uniforms.
##
## It captures the scene's BASE look once per map load ([method capture_base]) and
## then applies a weather "look" as RELATIVE changes on top of it (energy scales,
## colour tints, added fog), so a Night or Dusk map stays night/dusk in the rain.
##
## FUTURE WorldLook API: when the world-art pass lands a lighting script, it can
## join the group [constant WORLD_LOOK_GROUP] and implement
## [code]apply_weather_look(params: Dictionary) -> void[/code]; this adapter then
## hands it the params and stops touching the environment itself -- a one-line
## switch, no WeatherFX changes. Params keys are listed in [method params_for].

const WORLD_LOOK_GROUP := &"world_look"
const DEFAULT_SUN := Color(1.0, 0.96, 0.88)
## Global shader uniforms shared with the world-art pass (declared in project.godot
## [shader_globals]). Each is only written if it is declared, so a build without
## them simply skips.
const SHADER_GLOBALS := {
	"weather_wetness": "wetness",
	"weather_dust": "dust",
	"weather_bloom": "bloom",
	"weather_sun": "sun",
	"wind_strength_global": "wind",
}

var _scene: Node = null
var _sun: DirectionalLight3D = null
var _env: Environment = null
var _sky: ProceduralSkyMaterial = null
var _base: Dictionary = {}


## Bind to [param scene_root] and capture its current look as the base.
func bind(scene_root: Node) -> void:
	_scene = scene_root
	capture_base()


## (Re)read the untouched look (call after the map's own lighting was set up).
func capture_base() -> void:
	_base = {}
	if _scene == null or not is_instance_valid(_scene):
		return
	_sun = _scene.get_node_or_null("Sun") as DirectionalLight3D
	var we := _scene.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_env = we.environment if we != null else null
	_sky = null
	if _env != null and _env.sky != null and _env.sky.sky_material is ProceduralSkyMaterial:
		_sky = _env.sky.sky_material as ProceduralSkyMaterial
	if _sun != null:
		_base["sun_color"] = _sun.light_color
		_base["sun_energy"] = _sun.light_energy
	if _env != null:
		_base["ambient_energy"] = _env.ambient_light_energy
		_base["ambient_color"] = _env.ambient_light_color
		_base["fog_enabled"] = _env.fog_enabled
		_base["fog_density"] = _env.fog_density
		_base["fog_color"] = _env.fog_light_color
		_base["glow_enabled"] = _env.glow_enabled
		_base["glow_intensity"] = _env.glow_intensity
		_base["glow_bloom"] = _env.glow_bloom
		_base["adj_enabled"] = _env.adjustment_enabled
		_base["brightness"] = _env.adjustment_brightness
		_base["contrast"] = _env.adjustment_contrast
		_base["saturation"] = _env.adjustment_saturation
	if _sky != null:
		_base["sky_top"] = _sky.sky_top_color
		_base["sky_horizon"] = _sky.sky_horizon_color
		_base["ground_horizon"] = _sky.ground_horizon_color
		_base["ground_bottom"] = _sky.ground_bottom_color


## The look parameters of [param w] (a [WeatherResource]; null = neutral).
static func params_for(w) -> Dictionary:
	if w == null:
		return {
			"sun_color": DEFAULT_SUN, "sun_energy_scale": 1.0, "ambient_scale": 1.0,
			"ambient_tint": Color(1, 1, 1), "fog_color": Color(0.7, 0.75, 0.8), "fog_density": 0.0,
			"glow_scale": 1.0, "glow_bloom": 0.0, "saturation": 1.0, "brightness": 1.0,
			"contrast": 1.0, "sky_tint": Color(1, 1, 1),
			"wetness": 0.0, "dust": 0.0, "bloom": 0.0, "sun": 0.0, "wind": 1.0,
		}
	return {
		"sun_color": w.sun_color, "sun_energy_scale": w.sun_energy_scale,
		"ambient_scale": w.ambient_scale, "ambient_tint": w.ambient_tint,
		"fog_color": w.fog_color, "fog_density": w.fog_density,
		"glow_scale": w.glow_scale, "glow_bloom": w.glow_bloom,
		"saturation": w.saturation, "brightness": w.brightness, "contrast": w.contrast,
		"sky_tint": w.sky_tint,
		"wetness": w.shader_wetness, "dust": w.shader_dust, "bloom": w.shader_bloom,
		"sun": w.shader_sun, "wind": w.wind_strength,
	}


## Blend two params dictionaries (floats and Colors) by [param t] in 0..1.
static func blend(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out: Dictionary = {}
	for k in b:
		var va = a.get(k, b[k])
		var vb = b[k]
		if vb is Color:
			out[k] = (va as Color).lerp(vb, t)
		else:
			out[k] = lerpf(float(va), float(vb), t)
	return out


## Apply a (possibly blended) params dictionary to the scene.
func apply(p: Dictionary) -> void:
	_push_shader_globals(p)
	if _scene != null and is_instance_valid(_scene) and _scene.is_inside_tree():
		var look := _scene.get_tree().get_first_node_in_group(WORLD_LOOK_GROUP)
		if look != null and look.has_method("apply_weather_look"):
			look.apply_weather_look(p)
			return
	if _sun != null and is_instance_valid(_sun) and _base.has("sun_color"):
		var tint: Color = p["sun_color"]
		var bc: Color = _base["sun_color"]
		_sun.light_color = Color(bc.r * tint.r / DEFAULT_SUN.r, bc.g * tint.g / DEFAULT_SUN.g,
			bc.b * tint.b / DEFAULT_SUN.b, 1.0)
		_sun.light_energy = float(_base["sun_energy"]) * float(p["sun_energy_scale"])
	if _env == null or not _base.has("ambient_energy"):
		return
	_env.ambient_light_energy = float(_base["ambient_energy"]) * float(p["ambient_scale"])
	var ac: Color = _base["ambient_color"]
	_env.ambient_light_color = ac * (p["ambient_tint"] as Color)
	var fog_d: float = float(p["fog_density"])
	_env.fog_enabled = bool(_base["fog_enabled"]) or fog_d > 0.0005
	_env.fog_density = maxf(float(_base["fog_density"]) if bool(_base["fog_enabled"]) else 0.0, 0.0) + fog_d
	_env.fog_light_color = p["fog_color"]
	_env.fog_sky_affect = 0.35
	_env.glow_enabled = true
	_env.glow_intensity = float(_base["glow_intensity"]) * float(p["glow_scale"])
	_env.glow_bloom = float(_base["glow_bloom"]) + float(p["glow_bloom"])
	var adj := not (is_equal_approx(float(p["saturation"]), 1.0) and is_equal_approx(float(p["brightness"]), 1.0) \
		and is_equal_approx(float(p["contrast"]), 1.0))
	_env.adjustment_enabled = bool(_base["adj_enabled"]) or adj
	_env.adjustment_brightness = float(_base["brightness"]) * float(p["brightness"])
	_env.adjustment_contrast = float(_base["contrast"]) * float(p["contrast"])
	_env.adjustment_saturation = float(_base["saturation"]) * float(p["saturation"])
	if _sky != null and _base.has("sky_top"):
		var st: Color = p["sky_tint"]
		_sky.sky_top_color = (_base["sky_top"] as Color) * st
		_sky.sky_horizon_color = (_base["sky_horizon"] as Color) * st
		_sky.ground_horizon_color = (_base["ground_horizon"] as Color) * st
		_sky.ground_bottom_color = (_base["ground_bottom"] as Color) * st


## Restore the captured base look (WeatherFX leaving the tree).
func restore() -> void:
	apply(params_for(null))


static func _push_shader_globals(p: Dictionary) -> void:
	for uniform in SHADER_GLOBALS:
		if ProjectSettings.has_setting("shader_globals/" + uniform):
			RenderingServer.global_shader_parameter_set(uniform, float(p.get(SHADER_GLOBALS[uniform], 0.0)))
