extends GutTest

## THE element-matchup framework: the one editable chart resource, its lookups, and the
## labels the UI reads off them.
##
## The load-bearing property here is NOT what the seeded numbers are -- those are content
## and will be retuned. It is that the chart CANNOT CRASH and CANNOT LOG: an element it
## has never heard of, a null, an int, a Vector2i, an empty name -- every one of them has
## to come back 1.0 (neutral) as a returned value. GUT fails a test on any engine error,
## so the garbage-input tests below double as proof that nothing in this path pushes one.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const CHART_PATH: String = "res://game/combat/resources/element_chart.tres"

## Every type in the shipped vocabulary (owner, 2026-10-12: the 15 types).
const ALL: Array[StringName] = [
	&"basic", &"martial", &"fire", &"water", &"plant", &"bug", &"electric", &"ice",
	&"wind", &"earth", &"metal", &"poison", &"radiant", &"grim", &"dragon",
]

const SELF_RESIST: float = 0.75
const OPPOSITE_STRONG: float = 1.25
const STRONG: float = 1.25
const RESISTED: float = 0.75


## The chart is a static cache, which makes it GLOBAL state -- restored here rather than
## at the end of a test body, so a failing assertion cannot leak an injected chart into
## every later suite (tests/README.md rule 3).
func after_each() -> void:
	ElementChart.reset_chart()


# --- The shipped resource ----------------------------------------------------


func test_the_shipped_chart_resource_loads() -> void:
	assert_true(ResourceLoader.exists(CHART_PATH),
		"the element chart .tres is the ONE place matchup numbers live; it must exist")
	var chart := ElementChart.chart()
	assert_true(chart is ElementChartResource,
		"ElementChart.chart() hands back the authored resource, not a stand-in")
	assert_eq(chart.elements.size(), ALL.size(),
		"the authored vocabulary is the owner's fifteen types")
	for element in ALL:
		assert_true(chart.has_element(element),
			"%s is part of the authored element vocabulary" % element)


func test_the_resource_documents_what_it_seeded() -> void:
	# The chart is a design decision someone will want to revisit. The record of WHY lives in
	# the resource as data (a semicolon comment would be stripped when the editor re-saves the file).
	assert_ne(ElementChart.chart().notes.strip_edges(), "",
		"the chart resource carries its own authoring notes")


# --- The owner's calls (2026-10-12) ------------------------------------------


func test_the_classic_triangle() -> void:
	assert_almost_eq(ElementChart.multiplier(&"fire", &"plant"), STRONG, 0.001, "fire burns plant")
	assert_almost_eq(ElementChart.multiplier(&"water", &"fire"), STRONG, 0.001, "water douses fire")
	assert_almost_eq(ElementChart.multiplier(&"plant", &"water"), STRONG, 0.001, "plant drinks water")
	assert_almost_eq(ElementChart.multiplier(&"fire", &"water"), RESISTED, 0.001, "and back the other way it is resisted")


func test_the_owner_calls_beyond_the_obvious() -> void:
	assert_almost_eq(ElementChart.multiplier(&"earth", &"metal"), STRONG, 0.001, "earth beats metal")
	assert_almost_eq(ElementChart.multiplier(&"metal", &"dragon"), STRONG, 0.001, "metal beats dragon -- the knight's tale")
	assert_almost_eq(ElementChart.multiplier(&"radiant", &"metal"), RESISTED, 0.001, "metal RESISTS radiant")
	assert_almost_eq(ElementChart.multiplier(&"metal", &"radiant"), 1.0, 0.001, "but does not beat it")
	assert_almost_eq(ElementChart.multiplier(&"poison", &"radiant"), RESISTED, 0.001, "radiant is too pure for poison")
	assert_almost_eq(ElementChart.multiplier(&"bug", &"radiant"), STRONG, 0.001, "bug beats radiant")
	assert_almost_eq(ElementChart.multiplier(&"martial", &"basic"), STRONG, 0.001, "martial beats basic")
	assert_almost_eq(ElementChart.multiplier(&"basic", &"grim"), RESISTED, 0.001, "grim shrugs off basic blows")


func test_most_types_resist_themselves() -> void:
	for element in [&"martial", &"fire", &"water", &"plant", &"bug", &"electric", &"ice", &"wind", &"earth", &"metal", &"poison", &"radiant"]:
		assert_almost_eq(ElementChart.multiplier(element, element), SELF_RESIST, 0.001,
			"%s is hardest to hurt with its own type" % element)
	assert_almost_eq(ElementChart.multiplier(&"grim", &"grim"), STRONG, 0.001, "spirits harm spirits")
	assert_almost_eq(ElementChart.multiplier(&"dragon", &"dragon"), STRONG, 0.001, "dragons are each other's bane")
	assert_almost_eq(ElementChart.multiplier(&"basic", &"basic"), 1.0, 0.001, "basic is plain against basic")


# --- Two types: the step rule ------------------------------------------------


func test_one_type_is_exactly_the_matrix() -> void:
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", [&"plant"]), STRONG, 0.001, "one type reads the matrix")
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", [&"plant", &"plant"]), STRONG, 0.001, "a repeated type counts once")
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", []), 1.0, 0.001, "no type at all is neutral")


func test_two_weaknesses_stack_to_one_and_a_half() -> void:
	# fire beats plant AND bug.
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", [&"plant", &"bug"]), 1.5, 0.001, "weak to both: x1.5")


func test_a_weakness_and_a_resist_cancel() -> void:
	# fire beats plant; water resists fire's... fire into water is resisted.
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", [&"plant", &"water"]), 1.0, 0.001, "they cancel exactly")


func test_two_resists_stack_to_a_half() -> void:
	# poison is resisted by earth AND metal.
	assert_almost_eq(ElementChart.multiplier_vs(&"poison", [&"earth", &"metal"]), 0.5, 0.001, "resists both: x0.5")


func test_a_neutral_second_type_changes_nothing() -> void:
	assert_almost_eq(ElementChart.multiplier_vs(&"fire", [&"plant", &"wind"]), STRONG, 0.001, "wind adds nothing against fire")


func test_a_unit_with_two_types_is_read_both_ways() -> void:
	var unit := _ElementUnit.new(&"plant")
	unit.element2 = &"bug"
	assert_eq(ElementChart.elements_of(unit), [&"plant", &"bug"] as Array[StringName], "both types, primary first")
	var move := MoveResource.new()
	move.element = &"fire"
	assert_almost_eq(ElementChart.damage_scale_for(move, unit, null), 1.5, 0.001, "a fire move hits a plant/bug for x1.5")


# --- Unknown pairs are neutral, never an error -------------------------------


func test_an_unauthored_pair_is_neutral() -> void:
	assert_almost_eq(ElementChart.multiplier(&"fire", &"radiant"), 1.0, 0.001,
		"fire and radiant have no matchup either way")
	assert_almost_eq(ElementChart.multiplier(&"grim", &"earth"), 1.0, 0.001,
		"an unlisted pairing is neutral, not a missing-data failure")


func test_an_element_the_chart_has_never_heard_of_is_neutral() -> void:
	# THE property that lets the content phase move: a character or move authored with a
	# brand-new element plays neutral until someone adds its row. It is never rejected.
	assert_almost_eq(ElementChart.multiplier(&"plasma", &"fire"), 1.0, 0.001,
		"an unknown ATTACKER element resolves neutral instead of failing")
	assert_almost_eq(ElementChart.multiplier(&"fire", &"plasma"), 1.0, 0.001,
		"an unknown DEFENDER element resolves neutral instead of failing")
	assert_almost_eq(ElementChart.multiplier(&"plasma", &"plasma"), 1.0, 0.001,
		"even the self-resist rule does not apply to an element with no authored row")


func test_garbage_element_names_are_quiet() -> void:
	# Every one of these must RETURN 1.0. If any of them pushed an error instead, GUT
	# would fail this test on the engine log alone (tests/README.md rule 1).
	var junk: Array = [null, 42, 3.5, Vector2i.ZERO, [], {}, &"", ""]
	for value in junk:
		assert_almost_eq(ElementChart.multiplier(value, &"fire"), 1.0, 0.001,
			"garbage as the attacker element is neutral, quietly")
		assert_almost_eq(ElementChart.multiplier(&"fire", value), 1.0, 0.001,
			"garbage as the defender element is neutral, quietly")
	assert_almost_eq(ElementChart.multiplier(null, null), 1.0, 0.001,
		"two nulls are neutral, quietly")


func test_a_plain_string_looks_up_the_same_as_a_stringname() -> void:
	assert_almost_eq(ElementChart.multiplier("fire", "plant"), OPPOSITE_STRONG, 0.001,
		"a String element name resolves identically to a StringName one")


# --- Labels ------------------------------------------------------------------


func test_label_for_names_the_three_verdicts() -> void:
	assert_eq(ElementChart.label_for(1.25), ElementChart.LABEL_STRONG,
		"anything above 1.0 reads as strong")
	assert_eq(ElementChart.label_for(0.75), ElementChart.LABEL_RESISTED,
		"anything below 1.0 reads as resisted")
	assert_eq(ElementChart.label_for(1.0), ElementChart.LABEL_NEUTRAL,
		"exactly 1.0 reads as neutral")
	assert_eq(ElementChart.LABEL_STRONG, &"strong", "the strong label is &\"strong\"")
	assert_eq(ElementChart.LABEL_RESISTED, &"resisted", "the resisted label is &\"resisted\"")
	assert_eq(ElementChart.LABEL_NEUTRAL, &"neutral", "the neutral label is &\"neutral\"")


func test_label_for_is_not_fooled_by_float_noise() -> void:
	assert_eq(ElementChart.label_for(1.0000001), ElementChart.LABEL_NEUTRAL,
		"a multiplier that is 1.0 to within float noise is neutral, not strong")
	assert_eq(ElementChart.label_for(NAN), ElementChart.LABEL_NEUTRAL,
		"a non-finite multiplier degrades to neutral rather than claiming a matchup")


# --- The resource is swappable (balancing is content work) -------------------


func test_an_injected_chart_replaces_the_shipped_one() -> void:
	var custom := ElementChartResource.new()
	var vocabulary: Array[StringName] = [&"steam"]
	custom.elements = vocabulary
	custom.matrix = { &"steam": { &"fire": 2.0 } }
	ElementChart.set_chart(custom)

	assert_almost_eq(ElementChart.multiplier(&"steam", &"fire"), 2.0, 0.001,
		"the chart is DATA -- swapping the resource retunes every matchup at once")
	assert_almost_eq(ElementChart.multiplier(&"fire", &"plant"), 1.0, 0.001,
		"and the shipped pairs are gone with it, proving nothing is hard-coded")

	ElementChart.reset_chart()
	assert_almost_eq(ElementChart.multiplier(&"fire", &"plant"), OPPOSITE_STRONG, 0.001,
		"resetting goes back to the authored .tres")


func test_a_mis_authored_default_cannot_erase_damage() -> void:
	var broken := ElementChartResource.new()
	broken.default_multiplier = 0.0
	ElementChart.set_chart(broken)
	assert_almost_eq(ElementChart.multiplier(&"fire", &"water"), 1.0, 0.001,
		"a 0 default is ignored: an unauthored pair can never zero out a hit")


func test_a_mis_authored_matrix_entry_falls_back_to_neutral() -> void:
	var broken := ElementChartResource.new()
	broken.matrix = { &"fire": { &"water": "very effective", &"plant": -3.0 } }
	ElementChart.set_chart(broken)
	assert_almost_eq(ElementChart.multiplier(&"fire", &"water"), 1.0, 0.001,
		"a non-numeric multiplier is neutral, quietly")
	assert_almost_eq(ElementChart.multiplier(&"fire", &"plant"), 1.0, 0.001,
		"a negative multiplier is neutral -- damage can never invert into healing")


# --- Reading elements off moves and units ------------------------------------


func test_move_and_unit_elements_are_read_duck_typed() -> void:
	var move := MoveResource.new()
	move.element = &"fire"
	assert_eq(ElementChart.move_element(move), &"fire", "a move's element is its own field")
	assert_eq(ElementChart.move_element(null), &"", "a null move carries no element")

	var unit := _ElementUnit.new(&"plant")
	assert_eq(ElementChart.element_of(unit), &"plant",
		"a unit's element comes from get_element()")
	assert_eq(ElementChart.element_of(null), &"", "a null unit carries no element")
	assert_eq(ElementChart.element_of(Doubles.CombatUnit.new(0, {})), &"",
		"a double that exposes no element at all is neutral, not an error")


# --- The full applied multiplier ---------------------------------------------


func test_damage_scale_is_a_no_op_without_elements() -> void:
	var move := MoveResource.new()  # element unset
	var target := _ElementUnit.new(&"plant")
	assert_almost_eq(ElementChart.damage_scale_for(move, target, null), 1.0, 0.001,
		"an unelemented MOVE scales nothing, so pre-element content is unchanged")

	move.element = &"fire"
	assert_almost_eq(ElementChart.damage_scale_for(move, _ElementUnit.new(&""), null), 1.0, 0.001,
		"an unelemented TARGET scales nothing either")


func test_damage_scale_applies_the_matchup() -> void:
	var move := MoveResource.new()
	move.element = &"fire"
	assert_almost_eq(
		ElementChart.damage_scale_for(move, _ElementUnit.new(&"plant"), null),
		OPPOSITE_STRONG, 0.001, "fire into its opposite nature is strong")
	assert_almost_eq(
		ElementChart.damage_scale_for(move, _ElementUnit.new(&"fire"), null),
		SELF_RESIST, 0.001, "fire into fire is resisted")


func test_a_matching_tile_amplifies_and_a_home_tile_protects() -> void:
	var board := Doubles.TileEffectBoard.new()
	var target := _ElementUnit.new(&"plant")
	board.place(target, Vector3i(1, 1, 0))
	board.set_tile_effects(Vector3i(1, 1, 0), [_TileEffect.new(&"tall_grass")])

	var fire := MoveResource.new()
	fire.element = &"fire"
	# fire>nature 1.25, no tile match for fire, nature standing on its own grass 0.9.
	assert_almost_eq(ElementChart.damage_scale_for(fire, target, board), 1.25 * 0.9, 0.001,
		"a nature unit at home on grass shaves the incoming matchup")

	var nature := MoveResource.new()
	nature.element = &"plant"
	# nature>nature 0.75, nature move matching the grass tile 1.25, home benefit 0.9.
	assert_almost_eq(
		ElementChart.damage_scale_for(nature, target, board), 0.75 * 1.25 * 0.9, 0.001,
		"matchup, tile amplifier and home benefit are three independent factors")


func test_tile_elements_are_read_from_the_chart_resource() -> void:
	var board := Doubles.TileEffectBoard.new()
	var target := _ElementUnit.new(&"plant")
	board.place(target, Vector3i(0, 0, 0))
	board.set_tile_effects(Vector3i(0, 0, 0), [_TileEffect.new(&"molten_lava"), null])
	assert_eq(ElementChart.tile_elements_under(target, board), [&"fire"],
		"a lava tile reads as fire, and a null effect in the list is skipped quietly")

	board.set_tile_effects(Vector3i(0, 0, 0), [_TileEffect.new(&"unmapped_terrain")])
	assert_eq(ElementChart.tile_elements_under(target, board), [],
		"terrain with no authored element contributes none, rather than erroring")


# --- Local doubles -----------------------------------------------------------
#
# Deliberately local, not added to tests/helpers/test_doubles.gd: `get_element` is one of
# the methods the production code BRANCHES on, so bolting it onto a shared double would
# silently reroute every other suite that uses it (see the warning at the top of that
# file).

## The smallest thing that carries an element.
class _ElementUnit:
	var element: StringName
	var element2: StringName = &""

	func _init(p_element: StringName) -> void:
		element = p_element

	func get_element() -> StringName:
		return element


## A stand-in for the tile-effect records a board serves: an id, and nothing else.
class _TileEffect:
	var id: StringName

	func _init(p_id: StringName) -> void:
		id = p_id
