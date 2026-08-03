extends GutTest

## Making a status VISIBLE: the glyph/label/grouping vocabulary added to [StatusVisuals],
## and the announce seam ([StatusController] -> the GameEvents status signals) that the
## presentation layer rides.
##
## The bug this pins is not "poison is broken" -- it is "poison is invisible". A player
## reported not being able to tell whether poison existed at all, and the reason was
## structural on three levels at once:
##
##   * `poisoned` had no row in the StatusVisuals table, so it drew as the anonymous tan
##     fallback pip on the health bar;
##   * a colour is not a readout at pip size, so even an authored row would not have said
##     WHAT was happening;
##   * three stacked poison instances rendered as three identical pips, which filled the
##     whole 4-slot budget and pushed every other status on the unit into the "+N" marker.
##
## And nothing announced any of it, so every surface had to poll unrelated beats.

const Doubles := preload("res://tests/helpers/test_doubles.gd")


class StubUnit:
	extends Node
	var _controller: StatusController = null

	func get_status_controller() -> StatusController:
		return _controller


func _condition(id: StringName, name_text: String, duration: int,
		stacking: int = StatusCondition.Stacking.REFRESH) -> StatusCondition:
	var condition := StatusCondition.new()
	condition.id = id
	condition.display_name = name_text
	condition.duration_turns = duration
	condition.stacking = stacking
	return condition


## A live instance (turns_left seeded), without needing a controller.
func _live(id: StringName, name_text: String, turns: int) -> StatusCondition:
	var condition := _condition(id, name_text, maxi(turns, 1))
	condition.turns_left = turns
	return condition


# --- The missing table row ----------------------------------------------------

func test_poison_is_an_authored_status_not_the_anonymous_fallback() -> void:
	assert_true(StatusVisuals.is_known_id(&"poisoned"),
		"poisoned.tres has existed for ages; the vocabulary must know about it")
	var info: Dictionary = StatusVisuals.info_for_id(&"poisoned")
	assert_eq(String(info["kind"]), "debuff", "poison hurts the unit carrying it")
	assert_ne(Color(info["color"]), Color(StatusVisuals.info_for_id(&"not_a_status")["color"]),
		"poison must not share the generic fallback colour -- that is the invisibility bug")
	assert_ne(Color(info["color"]), Color(StatusVisuals.info_for_id(&"regen")["color"]),
		"and it must not read as Regeneration, the other green in the table")


func test_every_authored_status_now_in_play_has_its_own_colour() -> void:
	var ids: Array[StringName] = [
		&"poisoned", &"infested", &"enthralled", &"braced", &"empowered",
		&"prism_guard", &"reprisal_charge",
	]
	var seen: Dictionary = {}
	for id in ids:
		assert_true(StatusVisuals.is_known_id(id), "%s should be an authored status" % id)
		var color: Color = StatusVisuals.info_for_id(id)["color"]
		assert_false(seen.has(color), "%s must not reuse another status' colour" % id)
		seen[color] = true


# --- Glyphs -------------------------------------------------------------------

func test_glyphs_say_what_kind_of_thing_is_happening() -> void:
	assert_eq(StatusVisuals.glyph_for_id(&"poisoned"), StatusVisuals.GLYPH_DOT,
		"poison is damage over time")
	assert_eq(StatusVisuals.glyph_for_id(&"burn"), StatusVisuals.GLYPH_DOT,
		"burn is the same category, so it is the same glyph")
	assert_eq(StatusVisuals.glyph_for_id(&"regen"), StatusVisuals.GLYPH_HOT,
		"regeneration is heal over time")
	assert_eq(StatusVisuals.glyph_for_id(&"guarded"), StatusVisuals.GLYPH_GUARD,
		"a damage-reduction buff is a guard, not a plain up-arrow")


func test_glyphs_fall_back_to_the_kind_then_to_neutral() -> void:
	assert_eq(StatusVisuals.glyph_for_id(&"hastened"), StatusVisuals.GLYPH_BUFF,
		"a buff with no override gets the up arrow")
	assert_eq(StatusVisuals.glyph_for_id(&"ensnared"), StatusVisuals.GLYPH_DEBUFF,
		"a debuff with no override gets the down arrow")
	assert_eq(StatusVisuals.glyph_for_id(&"authored_next_week"), StatusVisuals.GLYPH_NEUTRAL,
		"an unknown status still gets a glyph -- a badge with no glyph reads as a bug")


func test_glyph_for_a_live_condition_matches_its_id() -> void:
	assert_eq(StatusVisuals.glyph_for(_live(&"poisoned", "Poisoned", 2)),
		StatusVisuals.GLYPH_DOT)
	assert_eq(StatusVisuals.glyph_for(null), StatusVisuals.GLYPH_NEUTRAL,
		"a null condition must not crash a pip row mid-rebuild")


# --- Severity -----------------------------------------------------------------

func test_stack_suffix_appears_only_when_stacked() -> void:
	assert_eq(StatusVisuals.stack_suffix(1), "",
		"one instance is just the status -- no x1 noise on every chip")
	assert_eq(StatusVisuals.stack_suffix(0), "")
	assert_eq(StatusVisuals.stack_suffix(3), " x3", "three instances is severity 3")


func test_grouping_collapses_a_stack_into_one_entry() -> void:
	var groups: Array = StatusVisuals.group_by_id([
		_live(&"poisoned", "Poisoned", 1),
		_live(&"ensnared", "Ensnared", 2),
		_live(&"poisoned", "Poisoned", 3),
		_live(&"poisoned", "Poisoned", 2),
	])
	assert_eq(groups.size(), 2,
		"three poisons and one ensnare are TWO statuses, not four badges")
	assert_eq(int(groups[0]["count"]), 3, "the poison group carries its severity")
	assert_eq(int(groups[0]["turns_left"]), 3,
		"a stack lasts until its LONGEST instance runs out")
	assert_eq(int(groups[1]["count"]), 1)


func test_grouping_keeps_first_applied_order_and_drops_nulls() -> void:
	var first := _live(&"ensnared", "Ensnared", 2)
	var groups: Array = StatusVisuals.group_by_id([first, null, _live(&"regen", "Regen", 1)])
	assert_eq(groups.size(), 2, "a null entry is skipped, not rendered")
	assert_eq(groups[0]["condition"], first, "order is first-applied, so the row is stable")


func test_a_permanent_instance_outranks_a_finite_one_in_a_stack() -> void:
	var groups: Array = StatusVisuals.group_by_id([
		_live(&"guarded", "Guarded", 2),
		_live(&"guarded", "Guarded", -1),
	])
	assert_eq(int(groups[0]["turns_left"]), -1,
		"-1 is the permanent sentinel: the status is not leaving in 2 turns")


func test_grouping_an_empty_list_is_empty() -> void:
	assert_eq(StatusVisuals.group_by_id([]), [])


# --- Chip and float wording ---------------------------------------------------

func test_chip_text_reads_glyph_name_severity_duration() -> void:
	assert_eq(StatusVisuals.chip_text(_live(&"poisoned", "Poisoned", 2), 3),
		"%s Poisoned x3 · 2 turns" % StatusVisuals.GLYPH_DOT,
		"the hover card is where severity AND duration have to be answerable")


func test_chip_text_drops_the_severity_for_a_single_instance() -> void:
	assert_eq(StatusVisuals.chip_text(_live(&"ensnared", "Ensnared", 1)),
		"%s Ensnared · 1 turn" % StatusVisuals.GLYPH_DEBUFF)


func test_chip_text_can_be_handed_a_groups_longest_duration() -> void:
	# The chip is built from the first instance, but a stack lasts as long as its
	# longest -- so the caller passes the group's value rather than the instance's.
	assert_eq(StatusVisuals.chip_text(_live(&"poisoned", "Poisoned", 1), 2, 4),
		"%s Poisoned x2 · 4 turns" % StatusVisuals.GLYPH_DOT)


func test_apply_shouts_and_expiry_murmurs() -> void:
	var poison := _live(&"poisoned", "Poisoned", 3)
	assert_eq(StatusVisuals.applied_label(poison), "POISONED",
		"a landing status is a shout -- it competes with damage numbers")
	assert_eq(StatusVisuals.expired_label(poison), "Poisoned faded",
		"an expiry is sentence case, so the two are never confused at a glance")


func test_tick_text_signs_a_heal_and_leaves_damage_bare() -> void:
	var poison := _live(&"poisoned", "Poisoned", 2)
	var regen := _live(&"regen", "Regeneration", 2)
	assert_eq(StatusVisuals.tick_text(poison, 4, false), "%s 4" % StatusVisuals.GLYPH_DOT,
		"a poison tick is a damage number with a poison marker on it")
	assert_eq(StatusVisuals.tick_text(regen, 5, true), "%s +5" % StatusVisuals.GLYPH_HOT,
		"a regen tick is signed, exactly like an ordinary heal")
	assert_eq(StatusVisuals.tick_text(poison, 0, false), "",
		"a tick that moved no HP has nothing to show")


# --- The announce seam --------------------------------------------------------
#
# Signal -> presentation wiring, driven through a real StatusController with stub
# emitters on the other end. These are the beats the floating labels and the health-bar
# badges ride; before them, every surface had to poll unrelated turn/HP events.

func _controller() -> StatusController:
	var unit := StubUnit.new()
	unit.name = "StubUnit"
	add_child_autofree(unit)
	var controller: StatusController = StatusController.new()
	controller.name = "StatusController"
	unit.add_child(controller)  # freed with its parent
	unit._controller = controller
	controller.owner_unit = unit
	return controller


func test_a_landing_status_is_announced() -> void:
	var controller := _controller()
	watch_signals(GameEvents)
	var live := controller.add_status(_condition(&"poisoned", "Poisoned", 3))
	assert_signal_emitted(GameEvents, "status_applied",
		"a status landing must announce itself, not wait to be noticed")
	var params: Array = get_signal_parameters(GameEvents, "status_applied", -1)
	assert_eq(params[0], controller.owner_unit, "the announce names the afflicted unit")
	assert_eq(params[1], live, "and carries the LIVE instance, not the shared .tres")


func test_refreshing_a_status_does_not_re_announce_it() -> void:
	var controller := _controller()
	controller.add_status(_condition(&"poisoned", "Poisoned", 3))
	watch_signals(GameEvents)
	controller.add_status(_condition(&"poisoned", "Poisoned", 3))
	assert_signal_emit_count(GameEvents, "status_applied", 0,
		"a re-applied REFRESH status must not shout POISONED a second time")


func test_each_tick_is_announced_for_the_condition_that_ticked() -> void:
	var controller := _controller()
	controller.add_status(_condition(&"poisoned", "Poisoned", 3))
	controller.add_status(_condition(&"regen", "Regeneration", 3))
	watch_signals(GameEvents)
	controller.tick_all(Doubles.MinimalBoard.new())
	assert_signal_emit_count(GameEvents, "status_ticked", 2,
		"one announce per condition, so a listener can attribute the HP it just saw move")


func test_expiry_is_announced_once_the_duration_runs_out() -> void:
	var controller := _controller()
	controller.add_status(_condition(&"poisoned", "Poisoned", 1))
	var board = Doubles.MinimalBoard.new()
	watch_signals(GameEvents)
	controller.tick_all(board)
	assert_signal_emitted(GameEvents, "status_expired",
		"the one-turn poison is gone, and the player is told so")
	assert_eq(controller.get_active().size(), 0, "and it really left the unit")


func test_a_consumed_status_is_announced_too() -> void:
	var controller := _controller()
	controller.add_status(_condition(&"infested", "Infested", 5))
	watch_signals(GameEvents)
	assert_eq(controller.remove_status(&"infested"), 1)
	assert_signal_emitted(GameEvents, "status_expired",
		"a status SPENT by an effect leaves the unit just as visibly as one that timed out")
