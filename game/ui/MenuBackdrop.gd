class_name MenuBackdrop
extends Control

## Ambient motion behind a dark menu screen: a slow drifting ember/spore particle
## field plus an ultra-slow "breathing" vignette. Purely decorative -- self-contained,
## full-rect, click-through, and cheap (two GPUParticles2D layers, one looping Tween).
##
## Usage: instantiate and insert directly above the screen's opaque "Background"
## ColorRect (see [method MenuTheme.apply_backdrop]) and below the content layout, e.g.
## [codeblock]
## var backdrop := MenuBackdrop.new()
## add_child(backdrop)
## move_child(backdrop, background_index + 1)
## [/codeblock]

const EMBER_COLOR := Color(0.9, 0.65, 0.29)          # warm gold -- matches MenuTheme.GOLD
const SPORE_COLOR := Color(0.35, 0.65, 0.55)         # cool green-teal, forest register

const EMBER_COUNT := 32
const SPORE_COUNT := 8                               # "a few" cooler particles mixed in

const PARTICLE_TEXTURE_SIZE := 16
const PARTICLE_LIFETIME := 20.0
const PARTICLE_LIFETIME_RANDOMNESS := 0.4            # actual range ~= [12s, 20s]

const VIGNETTE_ALPHA_MIN := 0.05
const VIGNETTE_ALPHA_MAX := 0.12
const VIGNETTE_STATIC_ALPHA := 0.08                  # used when animations are off
const VIGNETTE_LEG_SECONDS := 4.5                    # one breath (min->max or max->min)

var _ember_particles: GPUParticles2D
var _spore_particles: GPUParticles2D
var _vignette: TextureRect
var _vignette_tween: Tween


func _ready() -> void:
	name = "MenuBackdrop"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_vignette = _build_vignette()
	add_child(_vignette)

	_ember_particles = _build_particle_layer(EMBER_COLOR, EMBER_COUNT, 0.3)
	add_child(_ember_particles)

	_spore_particles = _build_particle_layer(SPORE_COLOR, SPORE_COUNT, 0.22)
	add_child(_spore_particles)

	resized.connect(_on_resized)
	call_deferred("_on_resized")  # ensure size is settled after the first layout pass

	_apply_animation_state()


func _on_resized() -> void:
	var half := size * 0.5
	_fit_particle_layer(_ember_particles, half)
	_fit_particle_layer(_spore_particles, half)


func _fit_particle_layer(particles: GPUParticles2D, half: Vector2) -> void:
	if particles == null:
		return
	particles.position = half
	var pm := particles.process_material as ParticleProcessMaterial
	if pm != null:
		pm.emission_box_extents = Vector3(maxf(half.x, 1.0), maxf(half.y, 1.0), 0.0)


## Null-safe read of GameSettings.animations_on(). Fails OPEN (treats animations as
## on) when the autoload is missing -- a stripped test scene or editor preview should
## still show the intended motion rather than look broken.
func _animations_enabled() -> bool:
	var settings: Node = get_node_or_null("/root/GameSettings")
	if settings == null or not settings.has_method("animations_on"):
		return true
	return settings.animations_on()


func _apply_animation_state() -> void:
	var on := _animations_enabled()
	if _ember_particles != null:
		_ember_particles.emitting = on
	if _spore_particles != null:
		_spore_particles.emitting = on
	if on:
		_start_vignette_breathing()
	else:
		_stop_vignette_breathing()
		if _vignette != null:
			_vignette.modulate.a = VIGNETTE_STATIC_ALPHA


func _start_vignette_breathing() -> void:
	if _vignette == null:
		return
	_stop_vignette_breathing()
	_vignette.modulate.a = VIGNETTE_ALPHA_MIN
	_vignette_tween = create_tween()
	_vignette_tween.set_loops()
	_vignette_tween.tween_property(_vignette, "modulate:a", VIGNETTE_ALPHA_MAX, VIGNETTE_LEG_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_vignette_tween.tween_property(_vignette, "modulate:a", VIGNETTE_ALPHA_MIN, VIGNETTE_LEG_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_vignette_breathing() -> void:
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = null


## Large radial-gradient TextureRect: transparent centre, dark at the rim. Its overall
## strength is modulated (not baked) by the breathing tween so the tween only touches a
## single float per frame.
func _build_vignette() -> TextureRect:
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.texture = _make_vignette_texture()
	rect.modulate = Color(1.0, 1.0, 1.0, VIGNETTE_ALPHA_MIN)
	return rect


func _make_vignette_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 1.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## One drifting layer: a GPUParticles2D emitting soft round motes upward out of a
## full-screen box, with gentle turbulence for horizontal sway. [param base_alpha] is
## the layer's peak opacity (kept within the 0.15-0.35 "very subtle" band).
func _build_particle_layer(color: Color, count: int, base_alpha: float) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = count
	particles.lifetime = PARTICLE_LIFETIME
	particles.preprocess = PARTICLE_LIFETIME  # pre-fill so the screen isn't empty on load
	particles.explosiveness = 0.0
	particles.randomness = 0.4
	particles.texture = _make_particle_texture(color)
	var mat: ParticleProcessMaterial = _make_particle_material(color, base_alpha)
	# lifetime_randomness lives on the PROCESS MATERIAL for GPU particles, not the
	# node (assigning it on GPUParticles2D is a runtime script error - gate-caught).
	mat.lifetime_randomness = PARTICLE_LIFETIME_RANDOMNESS
	particles.process_material = mat
	return particles


func _make_particle_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(color.r, color.g, color.b, 1.0), Color(color.r, color.g, color.b, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = PARTICLE_TEXTURE_SIZE
	tex.height = PARTICLE_TEXTURE_SIZE
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _make_particle_material(color: Color, base_alpha: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()

	# Emission: full-screen box, refit on resize via _fit_particle_layer.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(1.0, 1.0, 0.0)  # placeholder, sized by _on_resized

	# Slow upward drift with a narrow spread cone, easing further upward over life.
	pm.direction = Vector3(0.0, -1.0, 0.0)
	pm.spread = 20.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(0.0, -2.0, 0.0)

	# Gentle horizontal sway via turbulence rather than a hard sideways velocity.
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.4
	pm.turbulence_noise_scale = 1.5
	pm.turbulence_noise_speed = Vector3(0.06, 0.03, 0.0)

	# Slow lazy tumble, purely cosmetic.
	pm.angular_velocity_min = -8.0
	pm.angular_velocity_max = 8.0

	# 4-7px on screen from a 16px base texture.
	pm.scale_min = 0.25
	pm.scale_max = 0.45

	# Flat tint at the target peak alpha; the ramp below supplies the fade in/out envelope.
	pm.color = Color(color.r, color.g, color.b, base_alpha)

	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex

	return pm
