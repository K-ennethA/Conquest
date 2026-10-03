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
## GLOW (retuned 2026-10-03, research godot-world-feel.md item 2; the pre-change values
## live verbatim in LOOK_PRESETS["current"]). Godot 4.6 (PR #110671) blends glow BEFORE
## the tonemap for every mode except soft light, and made Screen + intensity 0.3 + levels
## {0, .8, .4, .1, 0, 0, 0} the defaults. We now use exactly those, so the glow is the
## engine's own 4.6 look rather than the soft-light mode that "removes the glow effect
## when blending against dark backgrounds" (the PR's words).
@export var glow_intensity: float = 0.3:
	set(v):
		glow_intensity = v
		_apply()
## Bloom = the glow-feedback FLOOR for pixels below the threshold (4.6 copy.glsl:
## feedback = max(smoothstep(thr, thr + hdr_scale, lum), bloom)), i.e. it makes ALL lit
## surfaces glow. 0 = only emissives bloom (the research's intent). The old base 0.04
## under soft light added 0.0037 linear on a typical lit pixel (c = 0.8 -> 0.598 after
## Filmic; 0.6%), below visibility, so dropping it loses nothing that was seen.
@export var glow_bloom: float = 0.0:
	set(v):
		glow_bloom = v
		_apply()
## Pre-tonemap luminance where glow starts. A lit board pixel is albedo x (sun 1.55 x
## sin 50 deg + sky ambient ~0.42) = albedo x ~1.6, so 1.2 keeps albedo <= 0.75 (grass,
## dirt, stone) out of the glow and lets emissives (fire, magic, unit _GLOW) in.
@export var glow_hdr_threshold: float = 1.2:
	set(v):
		glow_hdr_threshold = v
		_apply()
## Width of the threshold ramp. Derived, not tuned: GLOW_HDR_CEILING_MOBILE - threshold,
## so the ramp completes exactly at 2.0 -- an emissive at the forge palette cap (peak
## <= 2.0, godot-import-notes.md) gets FULL glow feedback on both renderers. With the
## engine default 2.0 it would get smoothstep(1.2, 3.2, 2.0) = 0.35 on desktop and could
## never get more on a phone (Mobile RGB10A2 clips at 2.0).
@export var glow_hdr_scale: float = GLOW_HDR_CEILING_MOBILE - 1.2:
	set(v):
		glow_hdr_scale = v
		_apply()
@export var glow_blend_mode: Environment.GlowBlendMode = Environment.GLOW_BLEND_MODE_SCREEN:
	set(v):
		glow_blend_mode = v
		_apply()
## Glow mip weights, levels 1..7 (4.6 defaults).
@export var glow_levels: PackedFloat32Array = PackedFloat32Array([0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0]):
	set(v):
		glow_levels = v
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
## Screen-space AO. Forward+ only (the Mobile renderer ignores it); the A/B harness turns
## it off in the "mobile profile" preset so desktop previews what a phone renders.
@export var ssao_enabled: bool = true:
	set(v):
		ssao_enabled = v
		_apply()
## Sun shadow profile: SHADOW_PROFILE_DESKTOP / SHADOW_PROFILE_MOBILE, or &"" = auto
## ([method detect_shadow_profile]: the Mobile renderer or a mobile platform -> mobile).
@export var shadow_profile: StringName = &"":
	set(v):
		shadow_profile = v
		_apply()

# --- Render profile constants (research godot-world-feel.md item 1) -------------------
## ANTI-ALIASING lives in project.godot [rendering] (it is a viewport setting, not an
## Environment one):
##   anti_aliasing/quality/msaa_3d=2          4x MSAA on desktop (Forward+)
##   anti_aliasing/quality/msaa_3d.mobile=1   2x MSAA on phones (feature tag "mobile";
##                                            Android/iOS run the Mobile renderer, since
##                                            rendering_method.mobile defaults to "mobile")
##   anti_aliasing/quality/use_debanding=true both renderers (Mobile's RGB10A2 buffer
##                                            bands on fog/sky gradients)
## Mobile choice: the Godot 4.6 Mobile renderer supports MSAA 3D, FXAA and SMAA 1x (3D
## antialiasing docs: FXAA/SMAA are "only available in the Forward+ and Mobile
## renderers"; TAA is Forward+ only). 2x MSAA is picked over SMAA because our aliasing is
## GEOMETRIC (flat-shaded low-poly edges, toon light steps), which MSAA samples and a
## post filter only guesses at, and because tile-based phone GPUs resolve MSAA in tile
## memory while SMAA adds three full-screen passes of framebuffer bandwidth. The docs:
## "2x MSAA may be usable ... higher MSAA levels are unlikely to run smoothly on mobile
## GPUs". If 2x measures too slow on the target phone, screen_space_aa.mobile=2 (SMAA)
## is the supported fallback.
const SHADOW_PROFILE_DESKTOP := &"desktop"
const SHADOW_PROFILE_MOBILE := &"mobile"
## Mobile RGB10A2 framebuffer range: no pixel brighter than Color(2, 2, 2) on phones.
const GLOW_HDR_CEILING_MOBILE := 2.0
## Desktop shadows: the pre-change values, unchanged (engine-default split ratios).
const DESKTOP_SHADOW_MAX_DISTANCE := 140.0
const DESKTOP_SHADOW_SPLITS := Vector3(0.1, 0.2, 0.5)
## Camera rig facts the mobile shadow fit is derived from (read from the code, not eyed):
## both cameras pitch 50 deg down with a 50 deg vertical FOV (GameWorld.tscn Camera3D,
## OverworldCamera.FOV_DEG); the battle camera's authored zoom-out clamp is
## CameraController.dist_max = 90 (the overworld's MAX_DISTANCE 28 is smaller), and its
## typical fit distance is ~20 (13x11 board, CameraController's dist_max comment).
## Boards past the authored budget raise the clamp at runtime (board_zoom_limit); there
## the far edge falls outside the mobile shadow range and fades out (fade_start 0.8).
const CAMERA_PITCH_DEG := 50.0
const CAMERA_FOV_DEG := 50.0
const CAMERA_DIST_MAX := 90.0
const CAMERA_FIT_DISTANCE := 20.0

## LOOK PRESETS for the artist's A/B harness ([WorldLookPresetCycler], debug builds,
## F7). "current" = the pre-2026-10-03 values captured verbatim (glow levels and
## hdr_scale were never set, so they were the 4.6 engine defaults; AA was off).
## "msaa" = a Viewport.MSAA_* value, or -1 = whatever project.godot sets for this
## platform; "mobile" in "msaa" reads the project's .mobile override.
const LOOK_PRESET_DEFAULT := "new"
const LOOK_PRESETS := {
	"current": {
		"glow_intensity": 0.55, "glow_bloom": 0.04, "glow_hdr_threshold": 0.95,
		"glow_hdr_scale": 2.0, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SOFTLIGHT,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": Viewport.MSAA_DISABLED, "debanding": false,
		"shadow_profile": &"desktop", "ssao_enabled": true,
	},
	"new": {
		"glow_intensity": 0.3, "glow_bloom": 0.0, "glow_hdr_threshold": 1.2,
		"glow_hdr_scale": GLOW_HDR_CEILING_MOBILE - 1.2, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": -1, "debanding": true,
		"shadow_profile": &"", "ssao_enabled": true,
	},
	# Research T2 range low end: albedo above ~0.62 in full sun starts to glow too.
	"new thr1.0": {
		"glow_intensity": 0.3, "glow_bloom": 0.0, "glow_hdr_threshold": 1.0,
		"glow_hdr_scale": GLOW_HDR_CEILING_MOBILE - 1.0, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": -1, "debanding": true,
		"shadow_profile": &"", "ssao_enabled": true,
	},
	# What a phone renders, previewed on desktop: 2x MSAA, 2-split fitted shadows, no
	# SSAO. (Not emulated: the 2.0 HDR clip and Hard shadow filtering.)
	"new mobile-profile": {
		"glow_intensity": 0.3, "glow_bloom": 0.0, "glow_hdr_threshold": 1.2,
		"glow_hdr_scale": GLOW_HDR_CEILING_MOBILE - 1.2, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": "mobile", "debanding": true,
		"shadow_profile": &"mobile", "ssao_enabled": false,
	},
}
const LOOK_PRESET_ORDER: Array[String] = ["current", "new", "new thr1.0", "new mobile-profile"]

## Weather glow_bloom conversion (see [method _weather_bloom_factor]). The weather
## resources' additive glow_bloom values were authored against soft light at base
## intensity 0.55. Both blends are linear in a small glow g, so the multiplicative
## glow_scale keeps its meaning unchanged; an ADDITIVE bloom needs re-scaling by the
## ratio of the two blends' slopes. 4.6 tonemap.glsl: soft light adds
## Tf(g) * (D(t) - t) after the tonemap (t = Tf(c), D = the soft-light curve); Screen
## adds g * (1 - c / white) before it. At a typical lit board pixel c = 0.8 (Filmic,
## white 6): soft slope 0.1339, Screen slope 0.3165 -> 0.423. (The ratio runs 0.23 at
## c = 0.3 to 0.68 at c = 1.5; 0.8 is the board's mid-lit value from the threshold
## comment above.)
const SOFTLIGHT_TO_SCREEN_BLOOM_SLOPE := 0.423
const WEATHER_AUTHORED_GLOW_INTENSITY := 0.55

var sun: DirectionalLight3D = null
var environment: Environment = null
var _sky_mat: ProceduralSkyMaterial = null
var _ready_to_apply := false
## Weather bridge (see [method apply_weather_look]): the un-weathered look, captured
## the first time weather is applied so every weather is RELATIVE to the map preset.
var _weather_base: Dictionary = {}
## Where depth fog starts; weather pulls it in (rain / sand close the view down).
var _fog_begin: float = 70.0
## Last weather params handed to [method apply_weather_look], so a look-preset switch
## can re-apply the active weather on top of the new base.
var _last_weather: Dictionary = {}
## Name of the last look preset applied ([method apply_look_preset]); the defaults above
## ARE the "new" preset.
var look_preset: String = LOOK_PRESET_DEFAULT

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
	WorldLookPresetCycler.attach(self)


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
	_last_weather = p
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
	glow_bloom = float(b["bloom"]) + float(p.get("glow_bloom", 0.0)) * _weather_bloom_factor(float(b["glow"]))
	saturation = float(b["saturation"]) * float(p.get("saturation", 1.0))
	contrast = float(b["contrast"]) * float(p.get("contrast", 1.0))
	exposure = float(b["exposure"]) * float(p.get("brightness", 1.0))
	_ready_to_apply = was_ready
	_apply()
	set_weather(float(p.get("wetness", 0.0)), float(p.get("dust", 0.0)), float(p.get("bloom", 0.0)),
		float(p.get("sun", 0.0)), float(p.get("wind", 1.0)))


## Multiplier for a weather's additive glow_bloom under the current blend mode: 1 under
## soft light (what the weather was authored for); otherwise the slope ratio times the
## base-intensity ratio, so the bloom's on-screen lift on a typical lit pixel matches the
## authored one (constants derived at SOFTLIGHT_TO_SCREEN_BLOOM_SLOPE). New base 0.3 ->
## 0.423 x 0.55 / 0.3 = 0.776 (bright_sun's +0.12 -> +0.093).
func _weather_bloom_factor(base_glow: float) -> float:
	if glow_blend_mode == Environment.GLOW_BLEND_MODE_SOFTLIGHT or base_glow <= 0.0:
		return 1.0
	return SOFTLIGHT_TO_SCREEN_BLOOM_SLOPE * WEATHER_AUTHORED_GLOW_INTENSITY / base_glow


## Resolved shadow profile (auto -> renderer/platform).
func active_shadow_profile() -> StringName:
	return shadow_profile if shadow_profile != &"" else detect_shadow_profile()


static func detect_shadow_profile() -> StringName:
	if OS.has_feature("mobile") or RenderingServer.get_current_rendering_method() == "mobile":
		return SHADOW_PROFILE_MOBILE
	return SHADOW_PROFILE_DESKTOP


## View-space depth of the farthest ground point on screen (the top frame edge) for a
## camera [param dist] from its ground focus at CAMERA_PITCH_DEG / CAMERA_FOV_DEG:
## height h = dist * sin(pitch); per unit of view depth the top-edge ray drops
## sin(pitch) - tan(fov/2) * cos(pitch). Directional shadow distance is view depth.
static func far_ground_depth(dist: float) -> float:
	var p := deg_to_rad(CAMERA_PITCH_DEG)
	var hf := deg_to_rad(CAMERA_FOV_DEG * 0.5)
	return dist * sin(p) / maxf(sin(p) - tan(hf) * cos(p), 0.01)


## Mobile shadows: 2 splits (the split count is the pass-count cost driver), max
## distance = the far ground edge at max zoom-out (90 -> 147.9), and the split placed so
## the near split holds the whole board at the typical fit distance (20 -> 32.9 m,
## split_1 = 0.222) instead of the engine default 0.1 (14.8 m, mid-board).
static func mobile_shadow_max_distance() -> float:
	return far_ground_depth(CAMERA_DIST_MAX)


static func mobile_shadow_split_1() -> float:
	return far_ground_depth(CAMERA_FIT_DISTANCE) / far_ground_depth(CAMERA_DIST_MAX)


static func look_preset_names() -> Array[String]:
	return LOOK_PRESET_ORDER.duplicate()


## Apply a named look preset (LOOK_PRESETS): glow, shadow profile, SSAO, and the
## viewport's MSAA / debanding. Debug A/B harness entry point ([WorldLookPresetCycler]);
## an active weather is re-applied on top of the new base. Unknown names are ignored.
func apply_look_preset(preset_name: String) -> bool:
	if not LOOK_PRESETS.has(preset_name):
		return false
	var d: Dictionary = LOOK_PRESETS[preset_name]
	look_preset = preset_name
	var was_ready := _ready_to_apply
	_ready_to_apply = false
	glow_intensity = float(d["glow_intensity"])
	glow_bloom = float(d["glow_bloom"])
	glow_hdr_threshold = float(d["glow_hdr_threshold"])
	glow_hdr_scale = float(d["glow_hdr_scale"])
	glow_blend_mode = int(d["glow_blend_mode"]) as Environment.GlowBlendMode
	glow_levels = PackedFloat32Array(d["glow_levels"])
	shadow_profile = d["shadow_profile"]
	ssao_enabled = bool(d["ssao_enabled"])
	_ready_to_apply = was_ready
	_apply_viewport_aa(_resolve_msaa(d["msaa"]), bool(d["debanding"]))
	if not _weather_base.is_empty() and not _last_weather.is_empty():
		_weather_base["glow"] = glow_intensity
		_weather_base["bloom"] = glow_bloom
		apply_weather_look(_last_weather)
	else:
		_apply()
	return true


static func _resolve_msaa(v) -> int:
	if v is String and v == "mobile":
		return int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d.mobile", Viewport.MSAA_2X))
	if int(v) < 0:
		return int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d", Viewport.MSAA_DISABLED))
	return int(v)


func _apply_viewport_aa(msaa: int, debanding: bool) -> void:
	if not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	vp.msaa_3d = msaa as Viewport.MSAA
	vp.use_debanding = debanding


## The values the look actually rendered with (Environment + sun + viewport), for the
## A/B harness label and the headless preset gate.
func dump_state() -> Dictionary:
	var out := {"preset": look_preset, "shadow_profile": String(active_shadow_profile())}
	if environment != null:
		var e := environment
		out["glow_enabled"] = e.glow_enabled
		out["glow_intensity"] = e.glow_intensity
		out["glow_bloom"] = e.glow_bloom
		out["glow_hdr_threshold"] = e.glow_hdr_threshold
		out["glow_hdr_scale"] = e.glow_hdr_scale
		out["glow_blend_mode"] = e.glow_blend_mode
		var lv: Array = []
		for i in 7:
			lv.append(snappedf(e.get_glow_level(i), 0.001))
		out["glow_levels"] = lv
		out["ssao_enabled"] = e.ssao_enabled
	if sun != null:
		out["shadow_mode"] = sun.directional_shadow_mode
		out["shadow_max_distance"] = snappedf(sun.directional_shadow_max_distance, 0.01)
		out["shadow_split_1"] = snappedf(sun.directional_shadow_split_1, 0.001)
	if is_inside_tree() and get_viewport() != null:
		out["msaa_3d"] = get_viewport().msaa_3d
		out["use_debanding"] = get_viewport().use_debanding
	return out


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
		if active_shadow_profile() == SHADOW_PROFILE_MOBILE:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = mobile_shadow_max_distance()
			sun.directional_shadow_split_1 = mobile_shadow_split_1()
		else:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = DESKTOP_SHADOW_MAX_DISTANCE
			sun.directional_shadow_split_1 = DESKTOP_SHADOW_SPLITS.x
			sun.directional_shadow_split_2 = DESKTOP_SHADOW_SPLITS.y
			sun.directional_shadow_split_3 = DESKTOP_SHADOW_SPLITS.z
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
	env.glow_hdr_threshold = glow_hdr_threshold
	env.glow_hdr_scale = glow_hdr_scale
	env.glow_blend_mode = glow_blend_mode
	for i in mini(glow_levels.size(), 7):
		env.set_glow_level(i, glow_levels[i])
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
	env.ssao_enabled = ssao_enabled
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
