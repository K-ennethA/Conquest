extends Node3D
class_name WeatherFX

## Renders the battle weather: particle rigs that follow the camera's focus, a
## screen-space overlay (sun rays, rain vignette, sand haze, bloom glow) and the
## light / fog / colour mood through [WeatherEnvAdapter]. Spawned by
## [GameWorldManager] per battle scene; purely cosmetic -- it READS the gameplay
## weather ([signal CombatServices.weather_changed] / [method Weather.current]) and
## never writes it.
##
## Weather changes CROSS-FADE over [constant FADE_TIME] seconds: every rig carries a
## weight 0..1 that scales its particle alpha and its overlay term, and the light
## params blend from the old look to the new one.
##
## Quality ([member GameSettings.weather_effects]): FULL, REDUCED (~40% particles),
## OFF (no particles / overlay; the light & fog mood still follows the weather,
## which costs nothing). Gameplay is never affected.

const FADE_TIME := 1.5
const OVERLAY_LAYER := 0
const OVERLAY_SHADER := preload("res://game/visuals/weather/weather_overlay.gdshader")
const REDUCED_FACTOR := 0.4

## Rig kinds and the overlay uniform each drives.
const KINDS := {
	&"rain": "rain_amt",
	&"sun": "sun_amt",
	&"sand": "sand_amt",
	&"bloom": "bloom_amt",
}

var _env := WeatherEnvAdapter.new()
var _rigs: Dictionary = {}        # kind -> Node3D rig
var _weights: Dictionary = {}     # kind -> current weight 0..1
var _target_kind: StringName = &"clear"
var _from_params: Dictionary = {}
var _to_params: Dictionary = {}
var _blend_t: float = 1.0
var _quality: int = 0
var _overlay_layer: CanvasLayer = null
var _overlay: ColorRect = null
var _overlay_mat: ShaderMaterial = null
var _last_view: float = -1.0
var _ripple_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	add_to_group("weather_fx")
	_env.bind(get_tree().current_scene if get_tree() != null else get_parent())
	for kind in KINDS:
		_weights[kind] = 0.0
	_quality = _read_quality()
	_build_overlay()
	var services := get_node_or_null("/root/CombatServices")
	if services != null and services.has_signal("weather_changed"):
		services.weather_changed.connect(_on_weather_changed)
		if services.has_signal("board_ready"):
			services.board_ready.connect(_collect_ripple_points)
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_signal("settings_changed"):
		gs.settings_changed.connect(_on_settings_changed)
	_collect_ripple_points()
	show_weather(Weather.current(), true)


func _exit_tree() -> void:
	_env.restore()


## Re-read the scene's base lighting (after a map load re-lit it) and snap to the
## current weather.
func rebase() -> void:
	_env.capture_base()
	_collect_ripple_points()
	show_weather(Weather.current(), true)


## Show [param w] (a [WeatherResource]), cross-fading unless [param instant].
func show_weather(w, instant: bool = false) -> void:
	var kind: StringName = w.fx_kind if w != null else &"clear"
	_target_kind = kind
	_from_params = _current_params()
	_to_params = WeatherEnvAdapter.params_for(w)
	_blend_t = 1.0 if instant else 0.0
	if kind in KINDS and not _rigs.has(kind):
		_build_rig(kind)
	if instant:
		for k in KINDS:
			_weights[k] = 1.0 if k == kind else 0.0
		_apply_weights()
		_env.apply(_to_params)
		_from_params = _to_params.duplicate()


## Active quality (0 FULL, 1 REDUCED, 2 OFF).
func quality() -> int:
	return _quality


## Current cross-fade weight of [param kind] (tests / debug).
func weight_of(kind: StringName) -> float:
	return float(_weights.get(kind, 0.0))


func _on_weather_changed(now, _previous) -> void:
	show_weather(now, false)


func _on_settings_changed() -> void:
	var q := _read_quality()
	if q == _quality:
		return
	_quality = q
	for kind in _rigs.keys():
		_apply_amounts(_rigs[kind])
	_apply_weights()


func _process(delta: float) -> void:
	# Cross-fade.
	var step := delta / FADE_TIME
	var changed := false
	for kind in KINDS:
		var target := 1.0 if kind == _target_kind else 0.0
		var w: float = _weights[kind]
		if not is_equal_approx(w, target):
			_weights[kind] = move_toward(w, target, step)
			changed = true
	if changed:
		_apply_weights()
	if _blend_t < 1.0:
		_blend_t = minf(1.0, _blend_t + step)
		_env.apply(WeatherEnvAdapter.blend(_from_params, _to_params, _smooth(_blend_t)))
	_follow_camera()
	if _overlay_mat != null:
		var vp := get_viewport().get_visible_rect().size
		_overlay_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))


static func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _current_params() -> Dictionary:
	if _to_params.is_empty():
		return WeatherEnvAdapter.params_for(null)
	if _blend_t >= 1.0:
		return _to_params.duplicate()
	return WeatherEnvAdapter.blend(_from_params, _to_params, _smooth(_blend_t))


# --- Rigs --------------------------------------------------------------------

func _build_rig(kind: StringName) -> void:
	var rig := WeatherRigs.build(kind)
	if rig == null:
		return
	add_child(rig)
	_rigs[kind] = rig
	_apply_amounts(rig)
	if kind == &"rain":
		_apply_ripple_points(rig)
	_last_view = -1.0


func _apply_amounts(rig: Node3D) -> void:
	var factor := 1.0 if _quality == 0 else REDUCED_FACTOR
	for layer in rig.get_meta("layers"):
		var p: CPUParticles3D = layer["node"]
		var n := maxi(1, int(round(float(layer["amount"]) * factor)))
		if p.amount != n:
			p.amount = n


func _apply_weights() -> void:
	var on := _quality != 2
	for kind in KINDS:
		var w: float = _weights[kind] if on else 0.0
		if _overlay_mat != null:
			_overlay_mat.set_shader_parameter(KINDS[kind], w)
		if not _rigs.has(kind):
			continue
		var rig: Node3D = _rigs[kind]
		rig.visible = w > 0.001
		for layer in rig.get_meta("layers"):
			var p: CPUParticles3D = layer["node"]
			var mat: StandardMaterial3D = layer["mat"]
			var c := mat.albedo_color
			c.a = float(layer["alpha"]) * w
			mat.albedo_color = c
			var should_emit := w > 0.001
			if p.emitting != should_emit:
				p.emitting = should_emit
	if _overlay != null:
		_overlay.visible = on


# --- Camera follow -----------------------------------------------------------

## Keep every rig centred on the point the camera looks at, sized to the view, so
## coverage is right at any zoom.
func _follow_camera() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var o := cam.global_position
	var d := -cam.global_transform.basis.z
	var focus := o + d * 30.0
	if absf(d.y) > 0.01:
		var t := (WeatherRigs.GROUND_Y - o.y) / d.y
		if t > 0.0:
			focus = o + d * t
	var dist := o.distance_to(focus)
	# View footprint grows with distance (fov ~50 deg -> ~0.95 * distance across).
	var view := clampf(dist * 1.1, 12.0, 160.0)
	for kind in _rigs:
		var rig: Node3D = _rigs[kind]
		if not rig.visible:
			continue
		rig.global_position = Vector3(focus.x, 0.0, focus.z)
		# Pull the rig a little toward the camera so the near edge is covered too.
		var toward := Vector3(o.x - focus.x, 0.0, o.z - focus.z)
		if toward.length() > 0.001:
			rig.global_position += toward.normalized() * minf(dist * 0.15, 10.0)
	if absf(view - _last_view) > _last_view * 0.08:
		_last_view = view
		for kind in _rigs:
			for layer in _rigs[kind].get_meta("layers"):
				if layer.get("pinned", false):
					continue
				var p: CPUParticles3D = layer["node"]
				var box: Vector3 = layer["box"]
				p.emission_box_extents = Vector3(view * box.x, box.y, view * box.z)


# --- Ripples on water --------------------------------------------------------

## Collect world-space water surface points so rain ripples land on water.
func _collect_ripple_points() -> void:
	_ripple_points = PackedVector3Array()
	var services := get_node_or_null("/root/CombatServices")
	if services == null or not ("_tile_registry" in services):
		return
	var registry: Dictionary = services._tile_registry
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # cosmetic only -- never the combat RNG
	var cells: Array = registry.keys()
	cells.sort_custom(func(a, b): return Cells.less(a, b))
	for cell in cells:
		if not _is_water(registry[cell]):
			continue
		var c: Vector3 = Cells.cell_to_world(cell)
		for i in 5:
			_ripple_points.append(Vector3(c.x + rng.randf_range(-0.8, 0.8), c.y + 0.02, c.z + rng.randf_range(-0.8, 0.8)))
	if _rigs.has(&"rain"):
		_apply_ripple_points(_rigs[&"rain"])


static func _is_water(res) -> bool:
	if res == null:
		return false
	var id := String(res.get("id")) if res.get("id") != null else ""
	if id.contains("water") or id.contains("river") or id.contains("pond"):
		return true
	return int(res.get("tile_type")) == int(Tile.TileType.WATER) if "tile_type" in res else false


func _apply_ripple_points(rig: Node3D) -> void:
	for layer in rig.get_meta("layers"):
		var p: CPUParticles3D = layer["node"]
		if p.name != "Ripples":
			continue
		if _ripple_points.is_empty():
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			layer["pinned"] = false
			p.top_level = false
		else:
			# Pinned in world space: points are world positions.
			layer["pinned"] = true
			p.top_level = true
			p.global_transform = Transform3D.IDENTITY
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
			p.emission_points = _ripple_points
			layer["amount"] = clampi(_ripple_points.size() / 2, 40, 320)
	_apply_amounts(rig)


# --- Overlay -----------------------------------------------------------------

func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "WeatherOverlay"
	_overlay_layer.layer = OVERLAY_LAYER
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = OVERLAY_SHADER
	_overlay.material = _overlay_mat
	_overlay_layer.add_child(_overlay)


func _read_quality() -> int:
	var gs := get_node_or_null("/root/GameSettings")
	if gs != null and "weather_effects" in gs:
		return clampi(int(gs.weather_effects), 0, 2)
	return 0
