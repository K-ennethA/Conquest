extends GutTest

## Floating combat numbers -- the GUARDS and status words of [FloatingCombatText].
##
## This suite used to pin the old DamageNumbers layer. That layer was folded into
## [FloatingCombatText] (the ONE floating-number layer: a number for every HP change, paired
## with its context by [CombatTextPairer]), and every guarantee below is the same promise
## the old layer made, re-pinned against the merged layer. The pairing logic, the wording
## ([method FloatingCombatText.texts_for]) and every source's annotation are covered by
## `test_floating_combat_text.gd`; this file keeps the other half:
##
##  * it must survive -- spawn nothing, log nothing -- when it has no scene to draw into or
##    a payload with no unit / no condition in it;
##  * it must never register in [UnitAnimator]'s busy registry, because that registry is
##    what the AI driver waits on and a cosmetic number must never stall the enemy turn;
##  * it must cap its live popups, stack a burst instead of overlapping it, and clear
##    immediately on a scene reset;
##  * a condition LANDING shouts its name, and one EXPIRING is reported quietly.
##
## The handlers are called DIRECTLY ([method FloatingCombatText._on_health_changed] is what
## each unit's [signal UnitStats.health_changed] is bound to), so a plain Node3D stands in
## for a unit. There is no camera in this suite, so popups are never on screen here -- the
## assertions read the popup nodes and labels the layer built, not pixels.
##
## DROPPED ON PURPOSE (the behaviour changed in the merge, not the promise):
##  * "animations off spawns nothing" -- the merged layer still shows the number, briefly
##    ([method FloatingCombatText._speed_factor]); an HP change must never be invisible.
##  * "a status tick is recoloured by the status_ticked announce that follows it" -- the
##    attribution now arrives BEFORE the HP change as a [CombatText] annotation; the same
##    player-facing promise is re-pinned below through that annotation instead.
##  * "crit inferred from the in-flight cast" -- crits now arrive on the annotation too.

const ANIMATOR := preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")


## A vision core that hides EVERY unit from EVERY seat -- so the fog gate answers "hidden"
## whatever [method FogOfWarOverlay.local_perspective] resolves to in a unit-test tree.
## A RefCounted, so it can never orphan.
class BlindVision:
	extends RefCounted

	func fog_enabled() -> bool:
		return true

	func is_unit_visible(_player_id: int, _unit) -> bool:
		return false

	func is_cell_visible(_player_id: int, _cell) -> bool:
		return false


## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

var _numbers: FloatingCombatText
var _victim: Node3D


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never through the setter: set_animations_enabled()
	# writes the player's real user://settings.cfg.
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	ANIMATOR._clear_anim_registry()
	CombatServices.clear()
	FogOfWarOverlay.reset_for_tests()
	_victim = add_child_autofree(Node3D.new())
	_victim.position = Vector3(4.0, 0.0, 6.0)


func after_each() -> void:
	if _numbers != null and is_instance_valid(_numbers):
		_numbers.clear_popups()
	_numbers = null
	FogOfWarOverlay.reset_for_tests()
	CombatServices.clear()
	ANIMATOR._clear_anim_registry()
	_guard.restore()


## In the tree: the normal, mounted-in-a-battle case.
func _mounted() -> FloatingCombatText:
	_numbers = add_child_autofree(FloatingCombatText.new())
	return _numbers


## Detached: what a signal arriving mid-teardown looks like.
func _detached() -> FloatingCombatText:
	_numbers = autofree(FloatingCombatText.new())
	return _numbers


## A live poison instance -- a Resource, so it never orphans.
func _poison() -> StatusCondition:
	var condition := StatusCondition.new()
	condition.id = &"poisoned"
	condition.display_name = "Poisoned"
	condition.duration_turns = 3
	condition.turns_left = 2
	return condition


## Every Label of popup [param i] (tag, main number, source line), in draw order.
func _labels_of(numbers: FloatingCombatText, i: int) -> Array[Label]:
	var out: Array[Label] = []
	if i < 0 or i >= numbers.get_child_count():
		return out  # no such popup: the caller's assertion reports it, without an engine error
	_collect_labels(numbers.get_child(i), out)
	return out


func _collect_labels(node: Node, out: Array[Label]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append(child as Label)
		else:
			_collect_labels(child, out)


## Popup [param i]'s label texts, in draw order.
func _texts_of(numbers: FloatingCombatText, i: int) -> Array:
	var out: Array = []
	for label in _labels_of(numbers, i):
		out.append(label.text)
	return out


## The label of popup [param i] that reads [param text], or null.
func _label_reading(numbers: FloatingCombatText, i: int, text: String) -> Label:
	for label in _labels_of(numbers, i):
		if label.text == text:
			return label
	return null


func _colour_of(label: Label) -> Color:
	return label.get_theme_color(&"font_color")


func _size_of(label: Label) -> int:
	return label.get_theme_font_size(&"font_size")


func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- No scene: spawn nothing, log nothing -------------------------------------

func test_damage_without_a_scene_spawns_nothing() -> void:
	var numbers := _detached()
	numbers._on_health_changed(30, 18, _victim)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a hit arriving while the layer is detached must produce no popup and no error")
	assert_eq(numbers.live_popup_count(), 0,
		"and nothing is left in flight to count against the cap once it is mounted again")


func test_heal_without_a_scene_spawns_nothing() -> void:
	var numbers := _detached()
	numbers._on_health_changed(10, 17, _victim)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a heal arriving while the layer is detached must produce no popup and no error")


func test_fully_null_payloads_are_survivable() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(30, 18, null)
	numbers._on_annotated(null, null)
	numbers._on_annotated(_victim, null)
	numbers.show_entry({})
	numbers.track_unit(null)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a payload with no unit (or no context) in it is dropped, not guessed at")


func test_non_positive_amounts_are_ignored() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(20, 20, _victim)
	# An annotated hit / heal that never moved HP and was not a shield soak has nothing to
	# show either: a zero hit, and a heal into full health.
	numbers._on_annotated(_victim, { "kind": CombatText.KIND_DAMAGE, "amount": 0 })
	numbers._on_annotated(_victim, { "kind": CombatText.KIND_HEAL, "amount": 6 })
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a zero-damage / zero-heal event has nothing to show")


# --- The happy path -----------------------------------------------------------

func test_a_hit_spawns_one_popup_carrying_the_amount() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(30, 18, _victim)
	# Unlike the old layer, nothing is buffered: the HP change IS the event.
	assert_eq(numbers.live_popup_count(), 1, "one HP change, exactly one popup")
	assert_eq(numbers.get_child_count(), 1, "and it is a child of the layer")
	var label := _label_reading(numbers, 0, "12")
	assert_not_null(label, "the popup shows the HP that was lost: %s" % [_texts_of(numbers, 0)])
	if label == null:
		return
	assert_eq(_colour_of(label), FloatingCombatText.COL_DAMAGE,
		"an ordinary hit is plain damage white, not the crit gold or the heal green")
	assert_eq(_size_of(label), int(FloatingCombatText.texts_for(
			{ "kind": CombatTextPairer.ENTRY_DAMAGE, "amount": 12 })["main_size"]),
		"and it is drawn at the base damage size")


func test_a_heal_spawns_a_signed_green_popup() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(10, 18, _victim)
	assert_eq(numbers.live_popup_count(), 1, "the heal spawns its popup")
	var label := _label_reading(numbers, 0, "+8")
	assert_not_null(label,
		"restored HP reads as a signed gain, not a bare number: %s" % [_texts_of(numbers, 0)])
	if label == null:
		return
	assert_eq(_colour_of(label), FloatingCombatText.COL_HEAL,
		"and it is green, the opposite of damage")


func test_the_popup_is_anchored_above_the_victim() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(10, 13, _victim)
	assert_eq(numbers.live_popup_count(), 1, "the popup exists for this assertion")
	# The on-screen position is a projection (no camera headless); the WORLD anchor it is
	# projected from is what the placement rule promises.
	var anchor: Vector3 = numbers._popups[0]["anchor"]
	assert_gt(anchor.y, _victim.global_position.y,
		"the number floats above the unit, clear of its body")
	assert_almost_eq(anchor.x, _victim.global_position.x, 0.001,
		"directly over the unit it belongs to (x)")
	assert_almost_eq(anchor.z, _victim.global_position.z, 0.001,
		"directly over the unit it belongs to (z)")


func test_a_burst_of_hits_stacks_instead_of_overlapping() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(40, 36, _victim)
	numbers._on_health_changed(36, 31, _victim)
	numbers._on_health_changed(31, 25, _victim)
	assert_eq(numbers.live_popup_count(), 3, "every hit of a multi-hit gets its own number")
	var slots: Array = []
	for p in numbers._popups:
		slots.append(int(p["slot"]))
	assert_eq(slots, [0, 1, 2], "and each stacks one row higher than the last")


func test_live_popups_are_capped() -> void:
	var numbers := _mounted()
	var cap: int = FloatingCombatText.MAX_LIVE_POPUPS
	for i in range(cap + 6):
		numbers._on_health_changed(500, 499 - i, _victim)
	assert_eq(numbers.live_popup_count(), cap,
		"a board-clearing AoE cannot flood the screen with numbers")
	assert_eq(numbers.get_child_count(), cap, "and no node is built past the cap")


# --- The load-bearing invariant: numbers never stall the AI --------------------

func test_popups_never_register_as_a_playing_animation() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(30, 18, _victim)
	numbers._on_health_changed(18, 30, _victim)
	numbers._on_status_applied(_victim, _poison())
	await get_tree().process_frame
	assert_gt(numbers.live_popup_count(), 0, "popups really are in flight for this assertion")
	assert_false(ANIMATOR.is_any_animation_playing(),
		"floating numbers are cosmetic: the AI must never wait on one")


# --- Status feedback ----------------------------------------------------------
#
# The report behind these: a player could not tell whether poison was doing anything,
# because a poison tick drew the SAME plain white number a sword hit does, from no visible
# source. The attribution now rides the [CombatText] annotation the tick emits BEFORE it
# changes HP.

func test_a_status_tick_is_recoloured_and_names_its_source() -> void:
	var numbers := _mounted()
	numbers._on_annotated(_victim, { "kind": CombatText.KIND_DAMAGE, "amount": 4,
		"source": "Poisoned", "source_kind": CombatText.SRC_STATUS, "source_id": &"poisoned" })
	numbers._on_health_changed(30, 26, _victim)
	assert_eq(numbers.live_popup_count(), 1, "a poison tick still produces a floating number")
	var number := _label_reading(numbers, 0, "4")
	assert_not_null(number, "carrying the HP it cost: %s" % [_texts_of(numbers, 0)])
	assert_not_null(_label_reading(numbers, 0, "Poisoned"),
		"and NAMING the status, so the player can see where the damage came from")
	if number != null:
		assert_ne(_colour_of(number), FloatingCombatText.COL_DAMAGE,
			"drawn in the environmental tint, not the plain sword-hit white")


func test_an_ordinary_hit_in_the_same_frame_is_untouched() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(30, 21, _victim)
	var label := _label_reading(numbers, 0, "9")
	assert_not_null(label, "an unattributed hit is still a bare number")
	assert_eq(_texts_of(numbers, 0).size(), 1, "with no source line under it")
	if label != null:
		assert_eq(_colour_of(label), FloatingCombatText.COL_DAMAGE, "and still plain white")


func test_a_regen_tick_stays_signed_and_names_its_source() -> void:
	var numbers := _mounted()
	numbers._on_annotated(_victim, { "kind": CombatText.KIND_HEAL, "amount": 5,
		"source": "Regeneration", "source_kind": CombatText.SRC_STATUS, "source_id": &"regen" })
	numbers._on_health_changed(20, 25, _victim)
	assert_not_null(_label_reading(numbers, 0, "+5"),
		"a regen tick reads as a signed heal: %s" % [_texts_of(numbers, 0)])
	assert_not_null(_label_reading(numbers, 0, "Regeneration"), "WITH its status named")


func test_a_tick_on_another_unit_does_not_claim_this_units_number() -> void:
	var other: Node3D = add_child_autofree(Node3D.new())
	other.position = Vector3(1.0, 0.0, 1.0)
	var numbers := _mounted()
	numbers._on_annotated(other, { "kind": CombatText.KIND_DAMAGE, "amount": 7,
		"source": "Poisoned", "source_kind": CombatText.SRC_STATUS, "source_id": &"poisoned" })
	numbers._on_health_changed(30, 23, _victim)
	assert_eq(_texts_of(numbers, 0), ["7"],
		"a condition only annotates its OWN unit, so it can never label another unit's number")
	await get_tree().process_frame
	assert_eq(numbers.live_popup_count(), 1,
		"and the other unit's unclaimed annotation (no HP moved, no shield) draws nothing")


func test_a_landing_status_shouts_its_name() -> void:
	var numbers := _mounted()
	numbers._on_status_applied(_victim, _poison())
	assert_eq(numbers.live_popup_count(), 1,
		"an applied status spawns inline -- there is nothing to correlate")
	var label := _label_reading(numbers, 0, "POISONED")
	assert_not_null(label,
		"the shout names the status the unit just picked up: %s" % [_texts_of(numbers, 0)])
	if label == null:
		return
	var tick_size := int(FloatingCombatText.texts_for({ "kind": CombatTextPairer.ENTRY_DAMAGE,
		"amount": 4, "source_kind": CombatText.SRC_STATUS })["main_size"])
	assert_lt(_size_of(label), tick_size,
		"a word must never out-shout the damage it is explaining")
	# (The old "sits ABOVE the tick number" placement rule is not expressible any more:
	# popups on one unit stack by arrival order, whatever their kind.)


func test_an_expiring_status_reports_quietly() -> void:
	var numbers := _mounted()
	var poison := _poison()
	numbers._on_status_expired(_victim, poison)
	var label := _label_reading(numbers, 0, "Poisoned faded")
	assert_not_null(label, "an expiry is good news, reported in sentence case")
	if label == null:
		return
	var vivid: Color = StatusVisuals.info_for(poison)["color"]
	assert_lt(_rgb_distance(_colour_of(label), FloatingCombatText.STATUS_EXPIRED_GREY),
		_rgb_distance(vivid, FloatingCombatText.STATUS_EXPIRED_GREY),
		"and is faded toward grey -- the quietest thing this layer draws")
	numbers._on_status_applied(_victim, poison)
	var shout := _label_reading(numbers, 1, "POISONED")
	if shout != null:
		assert_lt(_size_of(label), _size_of(shout), "and smaller than the shout it answers")


func test_status_labels_obey_every_existing_guard() -> void:
	# Detached layer (a signal arriving mid-teardown).
	var detached: FloatingCombatText = autofree(FloatingCombatText.new())
	detached._on_status_applied(_victim, _poison())
	detached._on_status_expired(_victim, _poison())
	assert_eq(detached.get_child_count(), 0, "no scene to draw into -> nothing, and no error")

	# Fog: a word rising over a unit you cannot see marks it as surely as a number would.
	FogOfWarOverlay.set_vision_override(BlindVision.new())
	var numbers := _mounted()
	numbers._on_status_applied(_victim, _poison())
	numbers._on_status_expired(_victim, _poison())
	numbers._on_health_changed(30, 18, _victim)
	assert_eq(numbers.live_popup_count(), 0,
		"nothing floats over a unit fog hides -- status words included")
	# (The old animations-off guard is gone on purpose: the merged layer still shows its
	# text, briefly, with animations off.)


func test_null_status_payloads_are_survivable() -> void:
	var numbers := _mounted()
	numbers._on_status_applied(null, null)
	numbers._on_status_applied(null, _poison())
	numbers._on_status_expired(_victim, null)
	numbers._on_status_expired()
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 0,
		"a payload with no condition (or no unit) in it is dropped, not guessed at")


# --- Teardown -----------------------------------------------------------------

func test_clear_popups_empties_the_layer_immediately() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(10, 15, _victim)
	await get_tree().process_frame
	assert_eq(numbers.get_child_count(), 1, "the heal popup is in flight")
	numbers.clear_popups()
	assert_eq(numbers.get_child_count(), 0,
		"a scene reset drops every in-flight popup in the same frame, not next frame")
	assert_eq(numbers.live_popup_count(), 0, "and forgets it")


func test_a_fresh_board_clears_the_previous_battles_popups() -> void:
	var numbers := _mounted()
	numbers._on_health_changed(30, 18, _victim)
	numbers._on_annotated(_victim, { "kind": CombatText.KIND_MISS })
	numbers._on_board_ready()
	assert_eq(numbers.get_child_count(), 0,
		"a map load / rematch leaves nothing floating from the last battle")
	await get_tree().process_frame
	assert_eq(numbers.live_popup_count(), 0,
		"and a pending annotation from the old board cannot surface on the new one")
