extends GutTest

# [UltimateCutIn] + the ultimate RESOLUTION RULE + the cast-site headless contract.
#
# These pin the three things the feature promises:
#   1. MoveResource.is_ultimate_move(move, slot) = (move.is_ultimate OR slot == 3), null-safe.
#      This is the single authority every cast site (human / AI / here) resolves through, so if
#      it drifts the wrong moves would flash (or the 4th move would stop flashing).
#   2. Emitting GameEvents.ultimate_casting with NO overlay present must not error, and the
#      cast-site group-lookup fallback returns null there -- which is exactly what lets the human
#      panel and the AI driver SKIP the await headless, so GUT never hangs on a missing overlay.
#   3. A live UltimateCutIn.play() always drives its `finished` signal to fire within the scaled
#      duration -- both on the normal (animated) path and the animations-OFF static-flash path --
#      because a cast site is awaiting `finished` and can never be left hanging.


## Any test that forced the animations flag gets it put back here, NOT at the end of the
## test body -- an assertion that fails part-way through must not leave the rest of the run
## (and the player's session) with animations disabled.
func after_each() -> void:
	_restore_animations()


# --- 1. Resolution rule ------------------------------------------------------

func test_slot_three_is_ultimate_even_without_flag() -> void:
	var move := MoveResource.new()
	move.is_ultimate = false
	assert_true(MoveResource.is_ultimate_move(move, 3),
		"the 4th moveset slot (index 3) is an ultimate with zero .tres edits")


func test_earlier_slots_are_not_ultimate_by_default() -> void:
	var move := MoveResource.new()
	move.is_ultimate = false
	assert_false(MoveResource.is_ultimate_move(move, 0), "slot 0 is not an ultimate")
	assert_false(MoveResource.is_ultimate_move(move, 1), "slot 1 is not an ultimate")
	assert_false(MoveResource.is_ultimate_move(move, 2), "slot 2 is not an ultimate")


func test_flag_opts_in_from_any_slot() -> void:
	var move := MoveResource.new()
	move.is_ultimate = true
	assert_true(MoveResource.is_ultimate_move(move, 0),
		"is_ultimate flag makes an earlier-slot move an ultimate")
	assert_true(MoveResource.is_ultimate_move(move, 3),
		"flag AND slot 3 are both ultimate (still true)")


func test_null_move_and_unknown_slot_are_safe() -> void:
	assert_false(MoveResource.is_ultimate_move(null, 3), "a null move is never an ultimate")
	assert_false(MoveResource.is_ultimate_move(null, -1), "null + unknown slot is safe -> false")
	var move := MoveResource.new()
	move.is_ultimate = false
	assert_false(MoveResource.is_ultimate_move(move, -1),
		"unknown slot (-1) falls back to the flag alone")


# --- 2. Headless emit + cast-site fallback ----------------------------------

func test_emit_with_no_overlay_does_not_error() -> void:
	# No UltimateCutIn is mounted in this test. Emitting the signal must be harmless, and the
	# cast-site pattern (group lookup) must resolve to null so the caller skips its await.
	assert_eq(get_tree().get_first_node_in_group(&"ultimate_cutin"), null,
		"no overlay is mounted for this test")
	watch_signals(GameEvents)
	GameEvents.ultimate_casting.emit(null, null)
	assert_signal_emitted(GameEvents, "ultimate_casting",
		"ultimate_casting emits cleanly with no listener/overlay present")
	# The exact lookup the human panel / AI driver do; null here means they never await.
	assert_null(get_tree().get_first_node_in_group(&"ultimate_cutin"),
		"cast sites find no overlay headless and skip the await (no hang)")


# --- 3. Live overlay: finished always fires ---------------------------------

func test_play_fires_finished_when_animated() -> void:
	_force_animations(true)
	var overlay := _mount_overlay()
	overlay.play(_stub_unit("Torvald"), _stub_move("Iron Meteor"))
	var fired: bool = await wait_for_signal(overlay.finished, 4.0,
		"cut-in finished within the scaled animated duration")
	assert_true(fired, "play() drives finished to fire (animated path)")


func test_play_fires_finished_when_animations_off() -> void:
	# Animations OFF must still fire finished (a single short static flash), never skip -- else
	# an awaiting cast site would hang forever.
	_force_animations(false)
	var overlay := _mount_overlay()
	overlay.play(_stub_unit("Geode"), _stub_move("Prism Nova"))
	var fired: bool = await wait_for_signal(overlay.finished, 2.0,
		"static flash finished quickly with animations off")
	assert_true(fired, "play() fires finished on the animations-off static path")


func test_overlay_registers_in_group() -> void:
	var overlay := _mount_overlay()
	assert_true(overlay.is_in_group(&"ultimate_cutin"),
		"the overlay joins the group cast sites look it up by")
	# And once mounted, the cast-site lookup resolves to it.
	assert_eq(get_tree().get_first_node_in_group(&"ultimate_cutin"), overlay,
		"group lookup finds the mounted overlay")


# --- Helpers -----------------------------------------------------------------

func _mount_overlay():
	var overlay = UltimateCutIn.new()
	add_child_autofree(overlay)
	return overlay


func _stub_unit(display_name: String) -> Node:
	var unit := StubUnit.new()
	unit.display_name = display_name
	add_child_autofree(unit)
	return unit


func _stub_move(name: String) -> MoveResource:
	var move := MoveResource.new()
	move.display_name = name
	move.is_ultimate = true
	return move


var _saved_anim: bool = true
var _anim_touched: bool = false

func _force_animations(on: bool) -> void:
	# Set the flag DIRECTLY rather than via set_animations_enabled(), which persists to disk --
	# a test must not mutate the user's real settings file. Restored in _restore_animations.
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null and "animations_enabled" in GameSettings:
		_saved_anim = bool(GameSettings.animations_enabled)
		_anim_touched = true
		GameSettings.animations_enabled = on


func _restore_animations() -> void:
	if _anim_touched and typeof(GameSettings) == TYPE_OBJECT and GameSettings != null \
			and "animations_enabled" in GameSettings:
		GameSettings.animations_enabled = _saved_anim
		_anim_touched = false


# A minimal duck-typed unit exposing just get_display_name (what the overlay reads).
class StubUnit:
	extends Node
	var display_name: String = "Stub"

	func get_display_name() -> String:
		return display_name
