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
## WARM GRADE fields (research godot-world-feel.md item 3). The defaults are the pre-grade
## look exactly: black non-sky ambient, 85% sky ambient, ground hemisphere derived from
## haze, Filmic white 6, no LUT. Grades ([constant GRADES]) set them per time of day.
## Non-sky part of the ambient fill (the (1 - ambient_sky_contribution) share).
@export var ambient_light_color: Color = Color(0.0, 0.0, 0.0):
	set(v):
		ambient_light_color = v
		_apply()
@export var ambient_sky_contribution: float = 0.85:
	set(v):
		ambient_sky_contribution = v
		_apply()
## Lower sky hemisphere (the bounce side faces and units pick up). Alpha 0 = derive from
## haze_color (horizon = haze, bottom = haze darkened 25%), the pre-grade behaviour.
@export var ground_bottom_color: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(v):
		ground_bottom_color = v
		_apply()
@export var ground_horizon_color: Color = Color(0.0, 0.0, 0.0, 0.0):
	set(v):
		ground_horizon_color = v
		_apply()
@export var tonemap_white: float = 6.0:
	set(v):
		tonemap_white = v
		_apply()
## 3D colour-correction LUT (sRGB in -> sRGB out, sampled after the tonemap + adjustments).
@export var color_correction: Texture = null:
	set(v):
		color_correction = v
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
	# WARM GRADE (research item 3): "new" + GRADES["warm"] -- warm/coloured shadow fill,
	# key:fill 3:1, Filmic white 3 (light trim baked into the energies), warm 3D LUT.
	# Glow values are "new"'s on purpose: the light trim lowers the lit board, never the
	# emissives, so the threshold/ramp derivations above still hold (see GRADES).
	"warm": {
		"glow_intensity": 0.3, "glow_bloom": 0.0, "glow_hdr_threshold": 1.2,
		"glow_hdr_scale": GLOW_HDR_CEILING_MOBILE - 1.2, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": -1, "debanding": true,
		"shadow_profile": &"", "ssao_enabled": true,
		"grade": "warm", "lut": true,
	},
	# The research's T3 A/B axis: identical light, fill and tonemap, but a NEUTRAL
	# (identity = none) LUT -- so warm vs this isolates what the LUT alone adds.
	"warm-neutralLUT": {
		"glow_intensity": 0.3, "glow_bloom": 0.0, "glow_hdr_threshold": 1.2,
		"glow_hdr_scale": GLOW_HDR_CEILING_MOBILE - 1.2, "glow_blend_mode": Environment.GLOW_BLEND_MODE_SCREEN,
		"glow_levels": [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0],
		"msaa": -1, "debanding": true,
		"shadow_profile": &"", "ssao_enabled": true,
		"grade": "warm", "lut": false,
	},
}
const LOOK_PRESET_ORDER: Array[String] = ["current", "new", "new thr1.0", "new mobile-profile", "warm", "warm-neutralLUT"]

## Map lighting presets (time of day; [method apply_preset]). Values are the pre-grade
## ones verbatim ("Day" = the property defaults above; "Dusk" shares "Dawn").
const TIME_OF_DAY := {
	"Day": {
		"sun_color": Color(1.0, 0.93, 0.8), "sun_energy": 1.55, "ambient_energy": 0.62,
		"sky_top": Color(0.42, 0.6, 0.78), "sky_horizon": Color(0.74, 0.82, 0.86), "haze": Color(0.66, 0.75, 0.8),
	},
	"Dawn": {
		"sun_color": Color(1.0, 0.76, 0.58), "sun_energy": 1.1, "ambient_energy": 0.42,
		"sky_top": Color(0.46, 0.5, 0.68), "sky_horizon": Color(0.92, 0.72, 0.58), "haze": Color(0.78, 0.66, 0.6),
	},
	"Night": {
		"sun_color": Color(0.62, 0.7, 0.95), "sun_energy": 0.55, "ambient_energy": 0.28,
		"sky_top": Color(0.08, 0.1, 0.2), "sky_horizon": Color(0.2, 0.24, 0.34), "haze": Color(0.16, 0.2, 0.28),
	},
}

## COLOUR GRADES layered on a time of day by a look preset's "grade" key (none = the
## TIME_OF_DAY values with the pre-grade fill/tonemap defaults).
##
## "warm" (research item 3, FE warm-amber direction). How the numbers were derived:
## * Fill = Godot 4.6 sky ambient: energy x mix(ambient_light_color, sky radiance,
##   ambient_sky_contribution); 4.6's ProceduralSkyMaterial is sky = mix(top, horizon,
##   (1 - y)^4), ground = mix(bottom, ground_horizon, (1 + y)^30). An up-facing tile in
##   sun shadow sees the cosine-weighted upper hemisphere ([method estimate_key_fill]).
##   Key on that tile = sun_energy x lum(sun_color) x sin(50 deg pitch). (Ignored: the
##   sun halo in the sky, ~2% of the fill; toon diffuse raising N.L on world tiles.)
## * Pre-grade Day measures key 1.024 + fill 0.169 -> 7.05:1, and the fill hue is
##   (0.30, 0.59, 1.00) -- grey-blue. Target: 3:1 at the SAME lit total (1.20), so the
##   board's mid-tones keep their brightness and only shadows lift (fill 0.40, key 0.80).
##   Key: sun a touch more golden, energy = 0.80 / (lum 0.810 x sin 50) = 1.29.
##   Fill colour: saturated sky blue at 50% share + warm ambient_light_color at 50% gives
##   an up-face shadow hue (0.98, 0.85, 1.00) (soft rose, coloured not grey); the ground
##   hemisphere becomes a sunlit grass/sand bounce, so side faces + units read warm
##   (1.00, 0.81, 0.69). ambient_energy then solved for exactly 3.00:1 -> 0.772.
##   Dawn/Dusk and Night: same 3:1 at their own lit totals (0.61, 0.21); Night's fill
##   stays moonlit blue-violet (warmth is a daylight read) but is no longer black
##   (pre-grade night measures 61:1).
## * Tonemap: Filmic white 6 -> 3. 4.6 Filmic (tonemap.glsl constants, exposure bias 2)
##   puts albedo 1.0 fully lit at f(1)/f(6) = 0.66 (the milky shoulder); white 3 gives
##   0.73. To keep a lit mid-albedo pixel (0.5 x 1.2) at the same display value, every
##   light energy is trimmed by light_trim = 0.8561 (solved: f(0.6 t)/f(3) = f(0.6)/f(6)).
##   The trim is in the LIGHTS, not tonemap_exposure, because the glow threshold is
##   compared AFTER exposure (4.6 copy.glsl) -- an exposure trim would also dim the
##   emissives and break the "ramp ends at 2.0" glow derivation; trimming lights leaves
##   emissives untouched, so they now sit relatively brighter (2.0 -> 0.92 display vs 0.83).
## * LUT: see WARM_LUT_* below. Night uses none (the warm LUT targets daylight).
const GRADES := {
	"warm": {
		"tonemap_white": 3.0,
		"light_trim": 0.8561,
		"lut": {"Day": true, "Dawn": true, "Night": false},
		"Day": {
			"sun_color": Color(1.0, 0.9, 0.72), "sun_energy": 1.29, "ambient_energy": 0.772,
			"ambient_color": Color(1.0, 0.84, 0.68), "ambient_sky_contribution": 0.5,
			"sky_top": Color(0.36, 0.58, 0.88), "sky_horizon": Color(0.78, 0.84, 0.86),
			"ground_bottom": Color(0.56, 0.56, 0.42), "ground_horizon": Color(0.7, 0.7, 0.6),
		},
		"Dawn": {
			"sun_color": Color(1.0, 0.76, 0.58), "sun_energy": 0.86, "ambient_energy": 0.497,
			"ambient_color": Color(1.0, 0.74, 0.62), "ambient_sky_contribution": 0.5,
			"sky_top": Color(0.44, 0.46, 0.74), "sky_horizon": Color(0.94, 0.7, 0.54),
			"ground_bottom": Color(0.56, 0.46, 0.4), "ground_horizon": Color(0.78, 0.62, 0.54),
		},
		"Night": {
			"sun_color": Color(0.62, 0.7, 0.95), "sun_energy": 0.4, "ambient_energy": 0.497,
			"ambient_color": Color(0.5, 0.52, 0.85), "ambient_sky_contribution": 0.5,
			"sky_top": Color(0.1, 0.12, 0.3), "sky_horizon": Color(0.24, 0.26, 0.42),
			"ground_bottom": Color(0.16, 0.16, 0.24), "ground_horizon": Color(0.22, 0.24, 0.32),
		},
	},
}

## WARM LUT (artist knobs). Built at runtime ([method warm_lut]) from [method warm_grade_srgb],
## so it is reproducible from these constants with no texture asset. Godot 4.6 samples the
## 3D LUT with the display-encoded (sRGB) colour after tonemap + contrast + saturation
## (tonemap.glsl), so the grade is written in sRGB. L = Rec.709 luma of the sRGB value.
##   1. shadow lift:  c += LIFT x TINT x (1 - smoothstep(0, 0.5, L))^2   (soft, coloured blacks)
##   2. warm highlights: c *= mix(1, HIGHLIGHT_GAIN, smoothstep(0.55, 1, L))
##   3. mid saturation: chroma x (1 + MID_SAT x 4L(1 - L))               (peaks at L = 0.5)
## Kept subtle: largest channel shift is white's blue, 1.0 -> 0.93; black lifts to 0.027.
const WARM_LUT_SIZE := 32
const WARM_LUT_SHADOW_LIFT := 0.03
const WARM_LUT_SHADOW_TINT := Color(0.9, 0.62, 0.48)
const WARM_LUT_HIGHLIGHT_GAIN := Color(1.03, 1.0, 0.93)
const WARM_LUT_MID_SAT := 0.12
static var _warm_lut: ImageTexture3D = null

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
## Since the warm grade the Screen slope is COMPUTED ([method screen_glow_slope]) for the
## active tonemap_white at the active grade's mid-lit pixel (0.8 x light_trim), against
## the fixed authored soft-light slope; at white 6 / trim 1 that reproduces 0.423 (the
## preset gate checks it). Warm (white 3, c = 0.685): slope 0.3669 -> ratio 0.365.
const SOFTLIGHT_TO_SCREEN_BLOOM_SLOPE := 0.423
const SOFTLIGHT_AUTHORED_SLOPE := 0.1339
const WEATHER_REFERENCE_LIT := 0.8
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
## Map time of day last given to [method apply_preset] (TIME_OF_DAY key), and the grade
## the active look preset layers on it ("" = none). A preset switch re-derives the
## lighting from both, so F7 never loses a Night map's night.
var lighting_preset: String = "Day"
var grade: String = ""
var _light_trim: float = 1.0
## The look preset's "lut" switch (false = the grade's neutral-LUT A/B variant).
var _grade_lut_enabled: bool = true

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
## Values come from TIME_OF_DAY, with the active look preset's grade layered on top.
func apply_preset(preset: String) -> void:
	_weather_base = {}  # the preset is the new un-weathered base
	lighting_preset = time_of_day_key(preset)
	var was_ready := _ready_to_apply
	_ready_to_apply = false
	_write_lighting()
	_ready_to_apply = was_ready
	_apply()


## TIME_OF_DAY key for a map lighting preset name ("Dusk" -> "Dawn", unknown -> "Day").
static func time_of_day_key(preset: String) -> String:
	match preset:
		"Night":
			return "Night"
		"Dawn", "Dusk":
			return "Dawn"
	return "Day"


## Write the un-weathered lighting for (lighting_preset, grade): sun, sky, fill, ground
## bounce, haze, tonemap white and LUT. Callers batch (_ready_to_apply false).
func _write_lighting() -> void:
	var tod: Dictionary = TIME_OF_DAY[lighting_preset]
	haze_color = tod["haze"]
	var g: Dictionary = GRADES.get(grade, {})
	if g.is_empty():
		_light_trim = 1.0
		sun_color = tod["sun_color"]
		sun_energy = float(tod["sun_energy"])
		ambient_energy = float(tod["ambient_energy"])
		sky_top_color = tod["sky_top"]
		sky_horizon_color = tod["sky_horizon"]
		ambient_light_color = Color(0.0, 0.0, 0.0)
		ambient_sky_contribution = 0.85
		ground_bottom_color = Color(0.0, 0.0, 0.0, 0.0)
		ground_horizon_color = Color(0.0, 0.0, 0.0, 0.0)
		tonemap_white = 6.0
		color_correction = null
		return
	var gt: Dictionary = g[lighting_preset]
	_light_trim = float(g["light_trim"])
	sun_color = gt["sun_color"]
	sun_energy = float(gt["sun_energy"]) * _light_trim
	ambient_energy = float(gt["ambient_energy"]) * _light_trim
	sky_top_color = gt["sky_top"]
	sky_horizon_color = gt["sky_horizon"]
	ambient_light_color = gt["ambient_color"]
	ambient_sky_contribution = float(gt["ambient_sky_contribution"])
	ground_bottom_color = gt["ground_bottom"]
	ground_horizon_color = gt["ground_horizon"]
	tonemap_white = float(g["tonemap_white"])
	var lut_on: bool = bool((g["lut"] as Dictionary).get(lighting_preset, false)) and _grade_lut_enabled
	color_correction = warm_lut() if lut_on else null


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
			"ambient_color": ambient_light_color,
			"ground_bottom": ground_bottom_color, "ground_horizon": ground_horizon_color,
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
	# Grade-era weather terms (meaning re-derived because the grade made them non-zero):
	# ambient_tint was a no-op while the non-sky ambient was black; it now tints the grade's
	# ambient_light_color (the same rule WeatherEnvAdapter's own fallback path uses). An
	# explicit ground bounce takes the sky_tint like the rest of the fill hemisphere (the
	# adapter's rule too); a haze-derived ground (alpha 0) still follows haze + fog below.
	# sun_energy_scale / ambient_scale / glow_scale stay plain multipliers: the grade moves
	# the key:fill balance, so e.g. rain's 0.62 sun now dims the frame less (lit 1.20 ->
	# 0.88 vs 1.19 -> 0.80 pre-grade) -- an overcast frame being fill-dominated is the
	# intended 3:1 behaviour, not a broken weather.
	var amb_tint: Color = p.get("ambient_tint", Color(1, 1, 1))
	var bac: Color = b["ambient_color"]
	ambient_light_color = Color(bac.r * amb_tint.r, bac.g * amb_tint.g, bac.b * amb_tint.b)
	for key in ["ground_bottom", "ground_horizon"]:
		var gc: Color = b[key]
		var tinted := Color(gc.r * sky_tint.r, gc.g * sky_tint.g, gc.b * sky_tint.b, gc.a)
		if key == "ground_bottom":
			ground_bottom_color = tinted
		else:
			ground_horizon_color = tinted
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
## authored one. New base 0.3 at white 6 -> 0.423 x 0.55 / 0.3 = 0.776 (bright_sun's
## +0.12 -> +0.093); warm (white 3, trim 0.8561) -> 0.365 x 0.55 / 0.3 = 0.669 (+0.080).
func _weather_bloom_factor(base_glow: float) -> float:
	if glow_blend_mode == Environment.GLOW_BLEND_MODE_SOFTLIGHT or base_glow <= 0.0:
		return 1.0
	return softlight_to_screen_ratio(tonemap_white, _light_trim) * WEATHER_AUTHORED_GLOW_INTENSITY / base_glow


## Authored soft-light slope / Screen slope at the grade's mid-lit pixel (see the
## SOFTLIGHT_TO_SCREEN_BLOOM_SLOPE comment). White 6, trim 1 -> 0.423.
static func softlight_to_screen_ratio(white: float, light_trim: float) -> float:
	return SOFTLIGHT_AUTHORED_SLOPE / screen_glow_slope(WEATHER_REFERENCE_LIT * light_trim, white)


## Godot 4.6 Filmic (tonemap.glsl, exposure bias 2 baked into A and B), un-normalized.
static func filmic_curve(x: float) -> float:
	const A := 0.88
	const B := 0.6
	const C := 0.1
	const D := 0.2
	const E := 0.01
	const F := 0.3
	return (x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F) - E / F


## Display (linear) value of scene value [param x] under Filmic with [param white].
static func filmic(x: float, white: float) -> float:
	return filmic_curve(x) / filmic_curve(white)


## d(display)/d(glow) for Screen glow at scene value c: Screen adds g (1 - c / white)
## before the tonemap (4.6 apply_glow), so the slope is filmic'(c) x (1 - c / white).
static func screen_glow_slope(c: float, white: float) -> float:
	var h := 1e-4
	return (filmic(c + h, white) - filmic(c - h, white)) / (2.0 * h) * (1.0 - c / white)


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
	var weathered := not _weather_base.is_empty() and not _last_weather.is_empty()
	if weathered:
		# Put the weather-touched, non-lighting fields back to their un-weathered values;
		# the lighting ones are rewritten from (time of day, grade) just below.
		fog_density = float(_weather_base["fog"])
		saturation = float(_weather_base["saturation"])
		contrast = float(_weather_base["contrast"])
		exposure = float(_weather_base["exposure"])
	glow_intensity = float(d["glow_intensity"])
	glow_bloom = float(d["glow_bloom"])
	glow_hdr_threshold = float(d["glow_hdr_threshold"])
	glow_hdr_scale = float(d["glow_hdr_scale"])
	glow_blend_mode = int(d["glow_blend_mode"]) as Environment.GlowBlendMode
	glow_levels = PackedFloat32Array(d["glow_levels"])
	shadow_profile = d["shadow_profile"]
	ssao_enabled = bool(d["ssao_enabled"])
	grade = String(d.get("grade", ""))
	_grade_lut_enabled = bool(d.get("lut", true))
	_write_lighting()
	_ready_to_apply = was_ready
	_apply_viewport_aa(_resolve_msaa(d["msaa"]), bool(d["debanding"]))
	_weather_base = {}
	if weathered:
		apply_weather_look(_last_weather)  # re-captures the new base, then re-weathers it
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
		out["tonemap_white"] = e.tonemap_white
		out["exposure"] = e.tonemap_exposure
		out["ambient_light_energy"] = snappedf(e.ambient_light_energy, 0.001)
		out["ambient_light_color"] = _c3(e.ambient_light_color)
		out["ambient_sky_contribution"] = e.ambient_light_sky_contribution
		out["lut"] = e.adjustment_color_correction != null and e.adjustment_enabled
		if _sky_mat != null:
			out["sky_top"] = _c3(_sky_mat.sky_top_color)
			out["sky_horizon"] = _c3(_sky_mat.sky_horizon_color)
			out["ground_horizon"] = _c3(_sky_mat.ground_horizon_color)
			out["ground_bottom"] = _c3(_sky_mat.ground_bottom_color)
			var kf := estimate_key_fill(sun_color, sun_energy, e.ambient_light_energy, e.ambient_light_color,
				e.ambient_light_sky_contribution, _sky_mat.sky_top_color, _sky_mat.sky_horizon_color)
			out["key_up"] = snappedf(kf["key"], 0.001)
			out["fill_up"] = snappedf(kf["fill"], 0.001)
			out["key_fill_ratio"] = snappedf(kf["ratio"], 0.01)
	out["grade"] = grade
	out["lighting_preset"] = lighting_preset
	if sun != null:
		out["sun_color"] = _c3(sun.light_color)
		out["sun_energy"] = snappedf(sun.light_energy, 0.001)
		out["shadow_mode"] = sun.directional_shadow_mode
		out["shadow_max_distance"] = snappedf(sun.directional_shadow_max_distance, 0.01)
		out["shadow_split_1"] = snappedf(sun.directional_shadow_split_1, 0.001)
	if is_inside_tree() and get_viewport() != null:
		out["msaa_3d"] = get_viewport().msaa_3d
		out["use_debanding"] = get_viewport().use_debanding
	return out


static func _c3(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]


## Analytic key:fill on an up-facing board tile (derivation at GRADES). Colours are the
## sRGB property values; Godot linearizes light, ambient and sky (source_color) colours.
## Fill irradiance of the upper hemisphere, cosine-weighted: E = integral 0..1 of
## L(y) 2y dy, L(y) = mix(top, horizon, (1 - y)^4) (4.6 ProceduralSkyMaterial).
static func estimate_key_fill(p_sun_color: Color, p_sun_energy: float, amb_energy: float, amb_color: Color,
		sky_contrib: float, top: Color, horizon: Color, pitch_deg: float = CAMERA_PITCH_DEG) -> Dictionary:
	var t := top.srgb_to_linear()
	var h := horizon.srgb_to_linear()
	var steps := 400
	var e_sky := Color(0, 0, 0)
	for i in steps:
		var y := (i + 0.5) / steps
		var l := t.lerp(h, pow(1.0 - y, 4.0))
		var w := 2.0 * y / steps
		e_sky = Color(e_sky.r + l.r * w, e_sky.g + l.g * w, e_sky.b + l.b * w)
	var a := amb_color.srgb_to_linear()
	var fill := Color(
		amb_energy * lerpf(a.r, e_sky.r, sky_contrib),
		amb_energy * lerpf(a.g, e_sky.g, sky_contrib),
		amb_energy * lerpf(a.b, e_sky.b, sky_contrib))
	var s := p_sun_color.srgb_to_linear()
	var key := _luma_linear(s) * p_sun_energy * sin(deg_to_rad(pitch_deg))
	var fl := _luma_linear(fill)
	return {"key": key, "fill": fl, "ratio": (key + fl) / maxf(fl, 1e-6), "fill_rgb": fill}


static func _luma_linear(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## The warm grade in sRGB display space (formula + knobs at WARM_LUT_*).
static func warm_grade_srgb(c: Color) -> Color:
	var l := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var ws := pow(1.0 - smoothstep(0.0, 0.5, l), 2.0)
	var r := c.r + WARM_LUT_SHADOW_LIFT * WARM_LUT_SHADOW_TINT.r * ws
	var g := c.g + WARM_LUT_SHADOW_LIFT * WARM_LUT_SHADOW_TINT.g * ws
	var b := c.b + WARM_LUT_SHADOW_LIFT * WARM_LUT_SHADOW_TINT.b * ws
	var wh := smoothstep(0.55, 1.0, l)
	r *= lerpf(1.0, WARM_LUT_HIGHLIGHT_GAIN.r, wh)
	g *= lerpf(1.0, WARM_LUT_HIGHLIGHT_GAIN.g, wh)
	b *= lerpf(1.0, WARM_LUT_HIGHLIGHT_GAIN.b, wh)
	var l2 := 0.2126 * r + 0.7152 * g + 0.0722 * b
	var sat := 1.0 + WARM_LUT_MID_SAT * 4.0 * l2 * (1.0 - l2)
	return Color(clampf(l2 + (r - l2) * sat, 0.0, 1.0), clampf(l2 + (g - l2) * sat, 0.0, 1.0),
		clampf(l2 + (b - l2) * sat, 0.0, 1.0))


## LUT input value stored at texel i. The shader samples with linear filtering and no
## half-texel remap, so texel i is read exactly at coordinate (i + 0.5) / N: storing the
## grade of THAT input makes the interior exact; the end texels store 0 and 1 so black
## and white (which clamp to them) stay exact too.
static func lut_texel_input(i: int, n: int = WARM_LUT_SIZE) -> float:
	if i <= 0:
		return 0.0
	if i >= n - 1:
		return 1.0
	return (i + 0.5) / n


## Slices (blue = depth, red = x, green = y) of the warm LUT, RGB8.
static func warm_lut_images() -> Array[Image]:
	var n := WARM_LUT_SIZE
	var out: Array[Image] = []
	for bi in n:
		var bytes := PackedByteArray()
		bytes.resize(n * n * 3)
		var k := 0
		for gi in n:
			for ri in n:
				var c := warm_grade_srgb(Color(lut_texel_input(ri), lut_texel_input(gi), lut_texel_input(bi)))
				bytes[k] = int(roundf(c.r * 255.0))
				bytes[k + 1] = int(roundf(c.g * 255.0))
				bytes[k + 2] = int(roundf(c.b * 255.0))
				k += 3
		out.append(Image.create_from_data(n, n, false, Image.FORMAT_RGB8, bytes))
	return out


## The warm LUT texture, built once per run (32^3, ~30k texels).
static func warm_lut() -> ImageTexture3D:
	if _warm_lut == null:
		var tex := ImageTexture3D.new()
		var err := tex.create(Image.FORMAT_RGB8, WARM_LUT_SIZE, WARM_LUT_SIZE, WARM_LUT_SIZE, false, warm_lut_images())
		if err != OK:
			push_warning("WorldLook: warm LUT create failed (%d)" % err)
			return null
		_warm_lut = tex
	return _warm_lut


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
	_sky_mat.ground_horizon_color = ground_horizon_color if ground_horizon_color.a > 0.0 else haze_color
	_sky_mat.ground_bottom_color = ground_bottom_color if ground_bottom_color.a > 0.0 else haze_color.darkened(0.25)
	_sky_mat.sun_angle_max = 20.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(ambient_light_color.r, ambient_light_color.g, ambient_light_color.b, 1.0)
	env.ambient_light_energy = ambient_energy
	env.ambient_light_sky_contribution = ambient_sky_contribution
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.tonemap_white = tonemap_white
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
	env.adjustment_color_correction = color_correction
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
