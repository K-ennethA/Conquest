extends GutTest

# [StatusVisuals] -- the shared vocabulary that makes status conditions readable
# on the health bar, the unit summary, and the hover card. If this table drifts,
# a status looks like one thing on the map and another in the panel, so these
# tests pin the contract: known ids resolve, unknown ids fall back rather than
# error, lookups are stable, and the formatting helpers say what a player expects.
#
# Deliberately does NOT touch StatusCondition.rule_flags -- that field is landing
# concurrently, and StatusVisuals reads it defensively, so nothing here depends on
# whether it exists yet.


# --- Stubs -------------------------------------------------------------------
# Plain objects rather than real StatusConditions/Units: these tests are about
# StatusVisuals' own behaviour, not the status layer's.

class StubCondition:
	extends RefCounted
	var id: StringName = &""
	var display_name: String = ""
	var turns_left: int = 0
	var tick_effects: Array = []

	func _init(p_id: StringName = &"", p_turns: int = 0) -> void:
		id = p_id
		turns_left = p_turns


class StubController:
	extends Node
	var _active: Array = []

	func get_active() -> Array:
		return _active


class StubEffect:
	extends RefCounted
	var text: String = ""

	func _init(p_text: String) -> void:
		text = p_text

	func describe() -> String:
		return text


func _unit_with_statuses(conditions: Array) -> Node:
	var unit := Node.new()
	unit.name = "StubUnit"
	var controller := StubController.new()
	controller.name = "StatusController"
	controller._active = conditions
	unit.add_child(controller)
	add_child_autofree(unit)
	return unit


# --- Vocabulary --------------------------------------------------------------

func test_known_ids_resolve_to_distinct_colours() -> void:
	var ids: Array[StringName] = [
		&"ensnared", &"entangled", &"burn", &"regen", &"fortified", &"hastened",
	]
	var seen: Dictionary = {}
	for id in ids:
		assert_true(StatusVisuals.is_known_id(id), "%s should be an authored status" % id)
		var info: Dictionary = StatusVisuals.info_for_id(id)
		var color: Color = info.get("color", Color.BLACK)
		assert_false(seen.has(color), "%s must not reuse another status' colour" % id)
		seen[color] = true


func test_buffs_and_debuffs_differ_in_kind() -> void:
	assert_eq(String(StatusVisuals.info_for_id(&"ensnared").get("kind", "")), "debuff",
		"Ensnared immobilises -- it is a debuff")
	assert_eq(String(StatusVisuals.info_for_id(&"entangled").get("kind", "")), "debuff",
		"Entangled slows -- it is a debuff")
	assert_eq(String(StatusVisuals.info_for_id(&"regen").get("kind", "")), "buff")
	assert_ne(
		String(StatusVisuals.info_for_id(&"ensnared").get("kind", "")),
		String(StatusVisuals.info_for_id(&"regen").get("kind", "")),
		"a debuff and a buff must never share a kind")


func test_authored_statuses_have_readable_names() -> void:
	assert_eq(String(StatusVisuals.info_for_id(&"ensnared").get("name", "")), "Ensnared")
	assert_eq(String(StatusVisuals.info_for_id(&"entangled").get("name", "")), "Entangled")


func test_unknown_id_returns_the_fallback_instead_of_erroring() -> void:
	var info: Dictionary = StatusVisuals.info_for_id(&"a_status_authored_next_week")
	assert_false(info.is_empty(), "an unknown id must still render, generically")
	assert_eq(String(info.get("kind", "")), "neutral", "unknown statuses read as neutral")
	assert_true(info.has("color"), "the fallback must still carry a colour")
	assert_false(StatusVisuals.is_known_id(&"a_status_authored_next_week"))


func test_vocabulary_is_stable_across_calls() -> void:
	# Two lookups of the same id must agree exactly -- no per-call allocation drift
	# that would make the same status a different colour on two surfaces.
	var first: Dictionary = StatusVisuals.info_for_id(&"ensnared")
	var second: Dictionary = StatusVisuals.info_for_id(&"ensnared")
	assert_eq(first.keys(), second.keys(), "repeat lookups must expose the same fields")
	assert_eq(Color(first.get("color", Color.BLACK)), Color(second.get("color", Color.WHITE)),
		"the same status must never change colour between calls")
	assert_eq(String(first.get("name", "")), String(second.get("name", "x")))
	assert_eq(String(first.get("kind", "")), String(second.get("kind", "x")))

	# ...and the returned dictionary must be a COPY, so a caller tinting its own
	# chip can never poison the shared table for everyone else.
	first["color"] = Color.MAGENTA
	assert_ne(Color(StatusVisuals.info_for_id(&"ensnared").get("color", Color.BLACK)),
		Color.MAGENTA, "mutating a returned descriptor must not edit the table")


func test_info_for_prefers_an_authored_display_name() -> void:
	var condition := StubCondition.new(&"ensnared", 2)
	condition.display_name = "Bound In Vines"
	assert_eq(String(StatusVisuals.info_for(condition).get("name", "")), "Bound In Vines")
	# ...but keeps the table's colour, so it still reads as Ensnared.
	assert_eq(Color(StatusVisuals.info_for(condition).get("color", Color.BLACK)),
		Color(StatusVisuals.info_for_id(&"ensnared").get("color", Color.WHITE)))


func test_info_for_null_is_the_fallback() -> void:
	assert_eq(String(StatusVisuals.info_for(null).get("kind", "")), "neutral")


# --- Formatting helpers ------------------------------------------------------

func test_turns_label_pluralises() -> void:
	assert_eq(StatusVisuals.turns_label(3), "3 turns")
	assert_eq(StatusVisuals.turns_label(1), "1 turn", "one turn must not say 'turns'")
	assert_eq(StatusVisuals.turns_label(0), "0 turns")
	assert_eq(StatusVisuals.turns_label(-1), "Permanent", "-1 is the permanent sentinel")


func test_overflow_label() -> void:
	assert_eq(StatusVisuals.overflow_label(2), "+2")
	assert_eq(StatusVisuals.overflow_label(0), "", "nothing hidden -> no marker")
	assert_eq(StatusVisuals.overflow_label(-1), "")


func test_pip_budget_fits_everything_when_it_can() -> void:
	assert_eq(StatusVisuals.shown_count(0, 4), 0)
	assert_eq(StatusVisuals.shown_count(3, 4), 3)
	assert_eq(StatusVisuals.shown_count(4, 4), 4, "exactly at the cap, show them all")
	assert_eq(StatusVisuals.hidden_count(4, 4), 0, "nothing is hidden at the cap")


func test_pip_budget_spends_the_last_slot_on_overflow() -> void:
	# 6 statuses in 4 slots: 3 real pips + one "+3" marker == 4 slots total.
	assert_eq(StatusVisuals.shown_count(6, 4), 3)
	assert_eq(StatusVisuals.hidden_count(6, 4), 3)
	assert_eq(
		StatusVisuals.shown_count(6, 4) + 1, 4,
		"shown pips plus the overflow marker must exactly fill the cap")
	assert_eq(StatusVisuals.overflow_label(StatusVisuals.hidden_count(6, 4)), "+3")


func test_humanize() -> void:
	assert_eq(StatusVisuals.humanize("cannot_act"), "Cannot Act")
	assert_eq(StatusVisuals.humanize(""), "")


# --- Defensive status reading -------------------------------------------------

func test_active_conditions_is_empty_for_nothing_to_read() -> void:
	assert_eq(StatusVisuals.active_conditions(null), [], "null unit -> no statuses")
	var bare := Node.new()
	add_child_autofree(bare)
	assert_eq(StatusVisuals.active_conditions(bare), [],
		"a unit with no StatusController must behave exactly as before")


func test_active_conditions_reads_the_controller_and_drops_nulls() -> void:
	var a := StubCondition.new(&"ensnared", 2)
	var b := StubCondition.new(&"entangled", 1)
	var unit := _unit_with_statuses([a, null, b])
	var out: Array = StatusVisuals.active_conditions(unit)
	assert_eq(out.size(), 2, "a null entry in the list must be skipped, not crash")
	assert_eq(out[0], a)
	assert_eq(out[1], b)


func test_active_conditions_handles_an_empty_list() -> void:
	assert_eq(StatusVisuals.active_conditions(_unit_with_statuses([])), [])


func test_turns_left_of_is_null_safe() -> void:
	assert_eq(StatusVisuals.turns_left_of(null), 0)
	assert_eq(StatusVisuals.turns_left_of(StubCondition.new(&"burn", 4)), 4)


func test_describe_condition_joins_tick_effects() -> void:
	var condition := StubCondition.new(&"entangled", 1)
	condition.tick_effects = [StubEffect.new("-2 movement for 1 turns"), null]
	assert_eq(StatusVisuals.describe_condition(condition), "-2 movement for 1 turns",
		"a null effect in the list must be skipped, not printed")


func test_describe_condition_is_empty_when_there_is_nothing_to_say() -> void:
	assert_eq(StatusVisuals.describe_condition(StubCondition.new(&"ensnared", 1)), "",
		"no describable content -> empty string, so callers can omit the line")
	assert_eq(StatusVisuals.describe_condition(null), "")
