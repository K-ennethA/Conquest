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
	# Heals ride the SAME deferred buffer hits do -- not because a heal can crit (it
	# cannot), but because a regen tick has to be recolourable by the status announce
	# that arrives after it. One path for both is what stops the two drifting.
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	assert_not_null(label, "the deferred flush spawns the heal popup")
	assert_eq(label.text, "+8", "restored HP reads as a signed gain, not a bare number")
	assert_almost_eq(label.modulate.r, numbers.heal_color.r, 0.01,
		"and it is green, the opposite of damage")


func test_the_popup_spawns_above_the_victim_it_was_captured_from() -> void:
	var numbers := _mounted()
	numbers._on_unit_healed(_victim, 3)
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	# A RANGE, not an exact height: the popup spawns at spawn_height and immediately
	# begins drifting up by float_height, and the deferred flush means a frame of that
	# drift has already elapsed by the time a test can look at it. What the placement
	# rule actually promises is "starts clear of the health bar, ends no higher than one
	# float_height above that" -- so that is what is asserted.
	assert_between(label.global_position.y,
		_victim.global_position.y + numbers.spawn_height - 0.001,
		_victim.global_position.y + numbers.spawn_height + numbers.float_height,
		"the number floats above the unit, clear of its health bar, and drifts up from there")
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


# --- Status feedback ----------------------------------------------------------
#
# Signal -> presentation wiring, driven with a stub emitter (the handlers are called
# directly, exactly as the damage/heal ones above are). The report behind these: a player
# could not tell whether poison was doing anything, because a poison tick drew the SAME
# plain white number a sword hit does, from no visible source.


## A live poison instance -- a Resource, so it never orphans.
func _poison() -> StatusCondition:
	var condition := StatusCondition.new()
	condition.id = &"poisoned"
	condition.display_name = "Poisoned"
	condition.duration_turns = 3
	condition.turns_left = 2
	return condition


func test_a_status_tick_is_recoloured_and_marked() -> void:
	var numbers := _mounted()
	var poison := _poison()
	# Exactly the live order: the tick's damage is announced first, then the status
	# announce that attributes it.
	numbers._on_damage_dealt(_victim, _victim, 4)
	numbers._on_status_ticked(_victim, poison, [])
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	assert_not_null(label, "a poison tick still produces a floating number")
	assert_eq(label.text, StatusVisuals.tick_text(poison, 4, false),
		"but it carries the status' glyph, so the player can see WHERE the damage came from")
	assert_almost_eq(label.modulate.g, Color(StatusVisuals.info_for(poison)["color"]).g, 0.01,
		"and it is drawn in the status' own colour, not the plain damage white")


func test_an_ordinary_hit_in_the_same_frame_is_untouched() -> void:
	var numbers := _mounted()
	# A sword hit buffered BEFORE any tick ran must not be claimed by the tick: the
	# attribution rule is "untagged entries at the moment the tick announces", which is
	# only exact because tick_all announces per condition, immediately.
	numbers._on_damage_dealt(null, _victim, 9)
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	assert_eq(label.text, "9", "an unattributed hit is still a bare number")
	assert_almost_eq(label.modulate.r, numbers.damage_color.r, 0.01, "and still plain white")


func test_a_regen_tick_stays_signed_and_takes_the_status_colour() -> void:
	var numbers := _mounted()
	var regen := StatusCondition.new()
	regen.id = &"regen"
	regen.display_name = "Regeneration"
	regen.turns_left = 2
	numbers._on_unit_healed(_victim, 5)
	numbers._on_status_ticked(_victim, regen, [])
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	assert_eq(label.text, StatusVisuals.tick_text(regen, 5, true),
		"a regen tick reads as a signed heal WITH its status marker")


func test_a_tick_on_another_unit_does_not_claim_this_units_number() -> void:
	var other: Node3D = add_child_autofree(Node3D.new())
	other.position = Vector3(1.0, 0.0, 1.0)
	var numbers := _mounted()
	numbers._on_damage_dealt(null, _victim, 7)
	numbers._on_status_ticked(other, _poison(), [])
	await get_tree().process_frame
	var label := numbers.get_child(0) as Label3D
	assert_eq(label.text, "7",
		"a condition only ticks its OWN unit, so it can never colour another unit's number")


func test_a_landing_status_shouts_its_name_above_the_numbers() -> void:
	var numbers := _mounted()
	var poison := _poison()
	numbers._on_status_applied(_victim, poison)
	var label := numbers.get_child(0) as Label3D
	assert_not_null(label, "an applied status spawns inline -- there is nothing to correlate")
	assert_eq(label.text, "POISONED", "the shout names the status the unit just picked up")
	assert_gt(label.global_position.y, _victim.global_position.y + numbers.spawn_height,
		"and sits ABOVE the tick number, so the two are legible at once")
	assert_lt(label.font_size, numbers.font_size,
		"a word must never out-shout the damage it is explaining")


func test_an_expiring_status_reports_quietly() -> void:
	var numbers := _mounted()
	var poison := _poison()
	numbers._on_status_expired(_victim, poison)
	var label := numbers.get_child(0) as Label3D
	assert_eq(label.text, "Poisoned faded", "an expiry is good news, reported in sentence case")
	var vivid: Color = StatusVisuals.info_for(poison)["color"]
	assert_lt(label.modulate.g, vivid.g,
		"and is faded toward grey -- the quietest thing this layer draws")


func test_status_labels_obey_every_existing_guard() -> void:
	# Detached layer (a signal arriving mid-teardown).
	var detached := _detached()
	detached._on_status_applied(_victim, _poison())
	assert_eq(detached.get_child_count(), 0, "no scene to spawn into -> nothing, and no error")

	# Animations off.
	_guard.set_setting("animations_enabled", false)
	var numbers := _mounted()
	numbers._on_status_applied(_victim, _poison())
	numbers._on_status_expired(_victim, _poison())
	assert_eq(numbers.get_child_count(), 0, "animations off means no floating status words either")


func test_null_status_payloads_are_survivable() -> void:
	var numbers := _mounted()
	numbers._on_status_applied(null, null)
	numbers._on_status_expired(_victim, null)
	numbers._on_status_ticked(null, null, null)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a payload with no condition in it is dropped, not guessed at")


# --- Teardown -----------------------------------------------------------------

func test_clear_popups_empties_the_layer_immediately() -> void:
	var numbers := _mounted()
	numbers._on_unit_healed(_victim, 5)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 1)
	numbers.clear_popups()
	assert_eq(numbers.get_child_count(), 0,
		"a scene reset drops every in-flight popup in the same frame, not next frame")
