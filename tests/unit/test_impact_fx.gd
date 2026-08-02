extends GutTest

## Code-built impact particles ([ImpactFX]).
##
## Like [DamageNumbers], this rides signals that fire during teardown as readily as during
## play -- `unit_eliminated` in particular is emitted while the unit is being freed -- so
## the guards are the behaviour worth pinning: no scene means no burst and no engine error,
## and animations off means no burst at all.
##
## The handlers are called DIRECTLY rather than emitted through the GameEvents autoload:
## `damage_dealt` is typed (`Unit, Unit, int`), so a Node3D mock cannot travel through it.
##
## The POSITIVE spawn path builds a real [GPUParticles3D]. That is skipped under the
## headless display server rather than asserted vacuously -- see tests/README.md, rule 8.

const IMPACT_FX := preload("res://game/visuals/ImpactFX.gd")
const ANIMATOR := preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

var _fx: Node3D
var _victim: Node3D


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never the setter (which persists to user://settings.cfg).
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	ANIMATOR._clear_anim_registry()
	_victim = add_child_autofree(Node3D.new())
	_victim.position = Vector3(2.0, 0.0, 2.0)


func after_each() -> void:
	ANIMATOR._clear_anim_registry()
	_guard.restore()


func _mounted() -> Node3D:
	_fx = add_child_autofree(IMPACT_FX.new())
	return _fx


func _detached() -> Node3D:
	_fx = autofree(IMPACT_FX.new())
	return _fx


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- No scene: spawn nothing, log nothing -------------------------------------

func test_a_hit_without_a_scene_spawns_nothing() -> void:
	var fx := _detached()
	fx._on_damage_dealt(null, _victim, 9)
	assert_eq(fx.get_child_count(), 0,
		"a hit arriving while the layer is detached must produce no burst and no error")


func test_a_death_without_a_scene_spawns_nothing() -> void:
	var fx := _detached()
	fx._on_unit_eliminated(_victim, null)
	assert_eq(fx.get_child_count(), 0,
		"a death arriving while the layer is detached must produce no burst and no error")


func test_null_payloads_are_survivable() -> void:
	var fx := _mounted()
	fx._on_damage_dealt(null, null, null)
	fx._on_unit_eliminated(null, null)
	assert_eq(fx.get_child_count(), 0,
		"a payload with no unit in it is dropped, not guessed at")


# --- Animations toggle --------------------------------------------------------

func test_animations_off_spawns_nothing() -> void:
	_guard.set_setting("animations_enabled", false)
	var fx := _mounted()
	fx._on_damage_dealt(null, _victim, 9)
	fx._on_unit_eliminated(_victim, null)
	assert_eq(fx.get_child_count(), 0,
		"animations off means no particles at all")


# --- Element tint -------------------------------------------------------------
#
# damage_dealt carries no element, so the spark is tinted from the ATTACKER's own
# get_element() through the shared theme lookup. These need no scene and no particles.

class _ElementalAttacker extends Node3D:
	var element: StringName = &""
	func get_element() -> StringName:
		return element


func test_an_unelemented_attacker_gives_a_neutral_spark() -> void:
	var fx := _mounted()
	assert_eq(fx._element_color_of(null), fx.neutral_spark_color,
		"no attacker at all falls back to the warm neutral, never to a wrong element")
	var attacker: Node3D = add_child_autofree(_ElementalAttacker.new())
	assert_eq(fx._element_color_of(attacker), fx.neutral_spark_color,
		"a physical hit reads as warm white rather than borrowing a colour")


func test_an_elemental_attacker_tints_the_spark_from_the_shared_theme() -> void:
	var fx := _mounted()
	var attacker := _ElementalAttacker.new()
	attacker.element = &"ember"
	add_child_autofree(attacker)
	assert_eq(fx._element_color_of(attacker), ConquestTheme.element_color("ember"),
		"the spark uses the SAME element lookup every element chip in the UI uses")


func test_a_non_unit_attacker_does_not_break_the_tint() -> void:
	var fx := _mounted()
	var not_a_unit: Node3D = add_child_autofree(Node3D.new())
	assert_eq(fx._element_color_of(not_a_unit), fx.neutral_spark_color,
		"a hazard or a mock with no get_element() resolves to neutral, not an error")


# --- The positive path (needs a real display server) ---------------------------

func test_a_hit_spawns_one_self_freeing_burst() -> void:
	if _headless():
		pending("GPUParticles3D needs a real rendering device; skipped under --headless")
		return
	var fx := _mounted()
	fx._on_damage_dealt(null, _victim, 9)
	assert_eq(fx.get_child_count(), 1, "a landed hit sparks exactly once")
	var burst := fx.get_child(0) as GPUParticles3D
	assert_not_null(burst, "the burst is a code-built GPUParticles3D")
	assert_true(burst.one_shot, "it fires once and stops -- never a standing emitter")
	assert_almost_eq(burst.global_position.y, _victim.global_position.y + fx.spark_height,
		0.001, "it bursts at chest height on the unit that was struck")
	assert_false(ANIMATOR.is_any_animation_playing(),
		"particles are cosmetic: the AI must never wait on one")
	burst.free()
