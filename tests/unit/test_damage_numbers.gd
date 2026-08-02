extends GutTest

## Floating combat numbers ([DamageNumbers]).
##
## This layer is driven entirely by signal handlers that fire during combat -- including
## the frame a unit is being torn down on -- so almost everything worth pinning here is a
## GUARD rather than a feature:
##
##  * it must spawn NOTHING and log NOTHING when it has no scene to spawn into (a Tween
##    cannot be created on a detached node, so an unguarded path would raise);
##  * it must spawn NOTHING when the player has animations switched off;
##  * it must never register in [UnitAnimator]'s busy registry, because that registry is
##    what the AI driver waits on and a cosmetic number must never stall the enemy turn.
##
## The handlers are called DIRECTLY rather than through the GameEvents autoload on purpose:
## `damage_dealt` is a TYPED signal (`Unit, Unit, int`), so a plain Node3D mock cannot be
## emitted through it -- which is exactly why DamageEffect guards its own announce.

const DAMAGE_NUMBERS := preload("res://game/visuals/DamageNumbers.gd")
const ANIMATOR := preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

var _numbers: Node3D
var _victim: Node3D


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never through the setter: set_animations_enabled()
	# writes the player's real user://settings.cfg.
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	ANIMATOR._clear_anim_registry()
	_victim = add_child_autofree(Node3D.new())
	_victim.position = Vector3(4.0, 0.0, 6.0)


func after_each() -> void:
	if _numbers != null and is_instance_valid(_numbers):
		_numbers.clear_popups()
	_numbers = null
	ANIMATOR._clear_anim_registry()
	_guard.restore()


## In the tree: the normal, mounted-in-a-battle case.
func _mounted() -> Node3D:
	_numbers = add_child_autofree(DAMAGE_NUMBERS.new())
	return _numbers


## Detached: what a signal arriving mid-teardown looks like.
func _detached() -> Node3D:
	_numbers = autofree(DAMAGE_NUMBERS.new())
	return _numbers


# --- No scene: spawn nothing, log nothing -------------------------------------

func test_damage_without_a_scene_spawns_nothing() -> void:
	var numbers := _detached()
	numbers._on_damage_dealt(null, _victim, 12)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a hit arriving while the layer is detached must produce no popup and no error")


func test_heal_without_a_scene_spawns_nothing() -> void:
	var numbers := _detached()
	numbers._on_unit_healed(_victim, 7)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a heal arriving while the layer is detached must produce no popup and no error")


func test_fully_null_payloads_are_survivable() -> void:
	var numbers := _mounted()
	numbers._on_damage_dealt(null, null, null)
	numbers._on_unit_healed(null, null)
	numbers._on_move_performed(null, null)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a payload with no unit in it is dropped, not guessed at")


func test_non_positive_amounts_are_ignored() -> void:
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 0)
	numbers._on_unit_healed(_victim, 0)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a zero-damage / zero-heal event has nothing to show")


# --- Animations toggle --------------------------------------------------------

func test_animations_off_spawns_nothing() -> void:
	_guard.set_setting("animations_enabled", false)
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 12)
	numbers._on_unit_healed(_victim, 12)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"animations off means no floating numbers at all")
	assert_true(numbers._pending.is_empty(),
		"and nothing is even buffered, so turning animations back on cannot flush a backlog")


# --- The happy path -----------------------------------------------------------

func test_a_hit_spawns_one_popup_carrying_the_amount() -> void:
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 12)
	# The hit is buffered and flushed DEFERRED so the cast behind it is known by then.
	assert_eq(numbers.get_child_count(), 0, "the hit is buffered, not spawned inline")
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 1, "the deferred flush spawns exactly one popup")
	var label := numbers.get_child(0) as Label3D
	assert_not_null(label, "the popup is a billboarded Label3D")
	assert_eq(label.text, "12", "the popup shows the damage that was dealt")
	# Channel-wise, not whole-Color: the alpha is being tweened to 0 as we look at it.
	assert_almost_eq(label.modulate.r, numbers.damage_color.r, 0.01,
		"an ordinary hit is plain white, not the crit gold or the heal green")
	assert_eq(label.font_size, numbers.font_size, "and it is drawn at the base size")


func test_a_heal_spawns_a_signed_green_popup() -> void:
	var numbers := _mounted()
	numbers._on_unit_healed(_victim, 8)
	var label := numbers.get_child(0) as Label3D
	assert_not_null(label, "a heal spawns immediately -- heals cannot crit, so nothing to wait for")
	assert_eq(label.text, "+8", "restored HP reads as a signed gain, not a bare number")
	assert_almost_eq(label.modulate.r, numbers.heal_color.r, 0.01,
		"and it is green, the opposite of damage")


func test_the_popup_spawns_above_the_victim_it_was_captured_from() -> void:
	var numbers := _mounted()
	numbers._on_unit_healed(_victim, 3)
	var label := numbers.get_child(0) as Label3D
	assert_almost_eq(label.global_position.y, _victim.global_position.y + numbers.spawn_height,
		0.001, "the number floats a fixed height above the unit, clear of its health bar")
	# Only the horizontal placement is jittered, and only within the authored band.
	assert_almost_eq(label.global_position.x, _victim.global_position.x,
		numbers.spawn_jitter + 0.001, "horizontal jitter stays inside its authored band")


func test_a_burst_of_hits_shares_one_deferred_flush() -> void:
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 4)
	numbers._on_damage_dealt(null, _victim, 5)
	numbers._on_damage_dealt(null, _victim, 6)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 3, "every target of an AoE gets its own number")


func test_live_popups_are_capped() -> void:
	var numbers := _mounted()
	numbers.max_live_popups = 2
	for i in range(6):
		numbers._on_damage_dealt(null, _victim, i + 1)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 2,
		"a board-clearing AoE cannot flood the scene with labels")


# --- The load-bearing invariant: numbers never stall the AI --------------------

func test_popups_never_register_as_a_playing_animation() -> void:
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 12)
	numbers._on_unit_healed(_victim, 12)
	await get_tree().process_frame
	assert_gt(numbers.get_child_count(), 0, "popups really are in flight for this assertion")
	assert_false(ANIMATOR.is_any_animation_playing(),
		"floating numbers are cosmetic: the AI must never wait on one")


# --- Teardown -----------------------------------------------------------------

func test_clear_popups_empties_the_layer_immediately() -> void:
	var numbers := _mounted()
	numbers._on_unit_healed(_victim, 5)
	assert_eq(numbers.get_child_count(), 1)
	numbers.clear_popups()
	assert_eq(numbers.get_child_count(), 0,
		"a scene reset drops every in-flight popup in the same frame, not next frame")
