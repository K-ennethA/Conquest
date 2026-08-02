extends Node3D

class_name ImpactFX

## Code-built impact particles: a small spark where a hit lands, and a bigger, darker
## ember burst where a unit dies. No art assets -- every mesh, material and process
## curve here is constructed in code, so this ships with the logic rather than with a
## content pipeline.
##
## MOUNTING: a per-battle [Node3D] added to the 3D scene root by
## [code]GameWorldManager._setup_impact_fx[/code], beside [DamageNumbers] and
## [TileEffectOverlay]. Freed and recreated on the next map load.
##
## Same three rules as [DamageNumbers], and for the same reasons:
##  1. NOTHING here registers with [UnitAnimator]'s busy registry. A cosmetic 0.4s spark
##     must never be able to stall the AI's next action.
##  2. The victim's position is captured IMMEDIATELY. `unit_eliminated` is emitted while
##     the unit is being torn down, so reading its transform a frame later is a crash.
##  3. Each burst owns a tween that frees it, so the layer drains itself.
##
## The spark is tinted by the ATTACKER's element via [method ConquestTheme.element_color]
## (the single source of truth every element chip in the UI already uses), because
## [signal GameEvents.damage_dealt] carries no element of its own. An unelemented or
## unresolvable attacker gets a warm white, which reads as a neutral physical hit.

# --- Hit spark ---------------------------------------------------------------
@export_group("Hit Spark")
## Authored seconds a hit spark lives. Scaled by battle speed, then floored.
@export_range(0.05, 2.0, 0.01) var spark_time: float = 0.4
## Particles in one spark.
@export_range(1, 128, 1) var spark_amount: int = 14
## Height above the victim's origin the spark bursts at (chest height on a 1-cell unit).
@export_range(0.0, 4.0, 0.05) var spark_height: float = 0.9
## Outward speed range of the spark.
@export_range(0.1, 20.0, 0.1) var spark_speed_min: float = 1.6
@export_range(0.1, 20.0, 0.1) var spark_speed_max: float = 3.4
## World size of one spark particle.
@export_range(0.01, 1.0, 0.01) var spark_particle_size: float = 0.11
## Fallback tint when the attacker has no element (a plain physical hit). Warm white.
@export var neutral_spark_color: Color = Color(1.0, 0.94, 0.82)

# --- Death burst --------------------------------------------------------------
@export_group("Death Burst")
## Authored seconds a death burst lives. Longer than a spark -- it is the bigger beat.
@export_range(0.05, 4.0, 0.01) var death_time: float = 0.9
@export_range(1, 256, 1) var death_amount: int = 30
@export_range(0.0, 4.0, 0.05) var death_height: float = 0.7
@export_range(0.1, 20.0, 0.1) var death_speed_min: float = 2.0
@export_range(0.1, 20.0, 0.1) var death_speed_max: float = 4.5
@export_range(0.01, 1.0, 0.01) var death_particle_size: float = 0.16
## Dark ember. Deliberately NOT the bright hit colour: a death should read as smoke and
## cinders coming off the body, not as another hit.
@export var death_ember_color: Color = Color(0.22, 0.13, 0.10)

## Hard cap on simultaneous bursts, so a wipe-the-board AoE cannot spawn 40 emitters.
@export_range(1, 64, 1) var max_live_bursts: int = 16

## Floor / ceiling on a burst's scaled lifetime.
const _LIFETIME_MIN: float = 0.15
const _LIFETIME_MAX: float = 3.0
## Extra seconds the emitter node is kept alive past its particle lifetime, so the last
## particles finish drawing before the node is freed.
const _FREE_MARGIN: float = 0.25

## Cached only on a HIT, so a late-registered autoload is still picked up.
var _game_settings_cached: Node = null


func _ready() -> void:
	name = "ImpactFX"
	var bus := get_node_or_null("/root/GameEvents")
	if bus == null:
		return
	_safe_connect(bus, &"damage_dealt", _on_damage_dealt)
	_safe_connect(bus, &"unit_eliminated", _on_unit_eliminated)


func _safe_connect(obj: Object, signal_name: StringName, callable: Callable) -> void:
	if obj != null and obj.has_signal(signal_name) and not obj.is_connected(signal_name, callable):
		obj.connect(signal_name, callable)


# --- Signal handlers ---------------------------------------------------------

func _on_damage_dealt(attacker = null, defender = null, _damage = null) -> void:
	if not _fx_enabled():
		return
	var pos = _anchor_of(defender, spark_height)
	if pos == null:
		return
	_spawn_burst(pos, _element_color_of(attacker), spark_amount, spark_time,
		spark_speed_min, spark_speed_max, spark_particle_size, true)


func _on_unit_eliminated(unit = null, _eliminator = null) -> void:
	if not _fx_enabled():
		return
	# Captured NOW: the emitter of this signal frees the unit, sometimes on this frame.
	var pos = _anchor_of(unit, death_height)
	if pos == null:
		return
	_spawn_burst(pos, death_ember_color, death_amount, death_time,
		death_speed_min, death_speed_max, death_particle_size, false)


# --- Burst construction ------------------------------------------------------

## Build and fire one one-shot [GPUParticles3D] at [param world_pos]. [param glowing]
## adds emission (the hit spark pops); a death ember stays dark and smoky.
## Self-freeing: a tween on the emitter frees it once its particles have finished.
func _spawn_burst(world_pos: Vector3, color: Color, amount: int, base_time: float,
		speed_min: float, speed_max: float, particle_size: float, glowing: bool) -> void:
	# A Tween cannot be created on a detached node, and these signals arrive during
	# teardown as readily as during play.
	if not is_inside_tree():
		return
	if get_child_count() >= max_live_bursts:
		return

	var life: float = clampf(_scaled(base_time), _LIFETIME_MIN, _LIFETIME_MAX)

	var particles := GPUParticles3D.new()
	particles.amount = maxi(1, amount)
	particles.lifetime = life
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.local_coords = false
	particles.draw_pass_1 = _make_particle_mesh(color, particle_size, glowing)
	particles.process_material = _make_process_material(color, speed_min, speed_max)
	add_child(particles)
	particles.global_position = world_pos
	particles.emitting = true

	# NOTE: deliberately NOT registered with UnitAnimator's busy registry. See the class doc.
	var tween := particles.create_tween()
	tween.tween_interval(life + _FREE_MARGIN)
	tween.tween_callback(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())


## The quad each particle is drawn as: unshaded, billboarded, additive-ish when glowing.
func _make_particle_mesh(color: Color, particle_size: float, glowing: bool) -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(particle_size, particle_size)

	var material := StandardMaterial3D.new()
	# WHITE, not the tint: the tint arrives per-particle as vertex colour from the process
	# material below, and multiplying it in twice would darken every burst.
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Particles write their colour (and the ramp's alpha fade) through vertex colour;
	# without this the tint and the fade-out would never reach the surface.
	material.vertex_color_use_as_albedo = true
	material.render_priority = 2
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 2.0
	mesh.material = material
	return mesh


## Outward spray with gravity, fading to transparent over the particle's life.
func _make_process_material(color: Color, speed_min: float, speed_max: float) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.18
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 65.0
	process.initial_velocity_min = speed_min
	process.initial_velocity_max = speed_max
	process.gravity = Vector3(0.0, -5.0, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.0
	process.color = color

	# Fade the particles out over their life so a burst dissolves rather than blinking off.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	process.color_ramp = ramp_texture
	return process


# --- Helpers -----------------------------------------------------------------

## The world point a burst for [param unit] belongs at, or null when the unit is not a
## live [Node3D]. Read ONCE, at signal time.
func _anchor_of(unit, height: float):
	if unit == null or not is_instance_valid(unit) or not (unit is Node3D):
		return null
	return (unit as Node3D).global_position + Vector3(0.0, height, 0.0)


## Tint for a hit spark: the attacker's element through the shared theme lookup, or the
## neutral warm white when the attacker has no element (or is not a unit at all).
func _element_color_of(attacker) -> Color:
	if attacker == null or not is_instance_valid(attacker):
		return neutral_spark_color
	if not attacker.has_method("get_element"):
		return neutral_spark_color
	var element: String = String(attacker.get_element())
	if element.is_empty():
		return neutral_spark_color
	return ConquestTheme.element_color(element)


# --- GameSettings bridge -----------------------------------------------------
#
# Mirrors UnitAnimator / DamageNumbers: optional autoload, absent one behaves as
# "animations ON at scale 1.0".

func _game_settings() -> Node:
	if _game_settings_cached != null and is_instance_valid(_game_settings_cached):
		return _game_settings_cached
	# An absolute lookup on an OFF-TREE node logs an engine error even though it
	# returns null (headless tests drive handlers on a bare instance) - guard first.
	if not is_inside_tree():
		return null
	_game_settings_cached = get_node_or_null("/root/GameSettings")
	return _game_settings_cached


## False when the player has turned animations off -- then NOTHING is spawned.
func _fx_enabled() -> bool:
	var settings := _game_settings()
	if settings == null or not settings.has_method("animations_on"):
		return true
	return bool(settings.animations_on())


func _scaled(base_seconds: float) -> float:
	var settings := _game_settings()
	if settings == null or not settings.has_method("scaled_time"):
		return base_seconds
	return float(settings.scaled_time(base_seconds))
