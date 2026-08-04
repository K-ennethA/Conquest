extends GutTest

## [ElementVisuals] -- the element/matchup VOCABULARY, tested as pure functions.
##
## Everything here is a static with no tree and no state, so this suite proves the WORDS
## and the COLOURS. Whether the badge and the two forecast rows are actually DRAWN (and
## drawn wide enough to read) is a question about a rendered tree, and it is answered by
## `integration/test_battle_element_readout.gd` -- the two halves are deliberately not
## the same test, because the reason this project has a live-HUD suite at all is that
## text-only assertions once passed while the screen was wrong.


# --- Colour: one palette, not a second one ------------------------------------

func test_the_badge_colour_is_the_same_one_the_move_stripes_use() -> void:
	# The whole point of routing through ConquestTheme: a unit's element badge and its
	# moves' element stripes cannot be different hues, because there is only one function.
	for element in ["nature", "fire", "frost", "arcane", "holy", "steel"]:
		assert_eq(ElementVisuals.color_for(element), ConquestTheme.element_color(element),
				"'%s' badges in the same colour the move rows stripe with" % element)


func test_an_unknown_element_falls_back_to_the_huds_amber() -> void:
	assert_eq(ElementVisuals.color_for(&"wildcard"), ConquestTheme.AMBER,
			"an element with no authored hue still gets an in-palette colour")


func test_every_chart_element_has_its_own_hue() -> void:
	# The chart treats dark/wind/earth as distinct types, so their badges must be
	# distinguishable: dark once fell through to the amber fallback (indistinguishable
	# from UNELEMENTED) and wind/earth both collapsed onto nature green.
	assert_ne(ElementVisuals.color_for(&"dark"), ConquestTheme.AMBER,
			"a dark unit's badge is not the unelemented fallback")
	assert_ne(ElementVisuals.color_for(&"wind"), ElementVisuals.color_for(&"nature"),
			"wind is not nature green")
	assert_ne(ElementVisuals.color_for(&"earth"), ElementVisuals.color_for(&"nature"),
			"earth is not nature green")
	assert_ne(ElementVisuals.color_for(&"wind"), ElementVisuals.color_for(&"earth"),
			"wind and earth are distinct from each other too")


# --- The badge's text ----------------------------------------------------------

func test_an_element_reads_as_its_capitalised_name() -> void:
	assert_eq(ElementVisuals.label_for(&"nature"), "Nature", "the badge names the element")
	assert_eq(ElementVisuals.label_for(&"deep_water"), "Deep Water",
			"and a multi-word authored id is humanised rather than printed raw")


func test_no_element_produces_no_badge_text_at_all() -> void:
	# The rule the panels branch on: "" means DO NOT DRAW. A chip reading "Neutral" on
	# two thirds of the roster is furniture, so the absence has to be representable.
	assert_eq(ElementVisuals.label_for(&""), "", "an unelemented unit has nothing to badge")
	assert_eq(ElementVisuals.label_for("   "), "", "and neither has a whitespace-only one")


# --- Reading the element off a subject ------------------------------------------

class _ElementUnit:
	extends RefCounted
	var element: StringName = &""
	func _init(e: StringName) -> void:
		element = e


class _MethodUnit:
	extends RefCounted
	var _e: StringName = &""
	func _init(e: StringName) -> void:
		_e = e
	func get_element() -> StringName:
		return _e


func test_a_units_element_is_read_through_the_accessor_gameplay_uses() -> void:
	assert_eq(ElementVisuals.of_unit(_MethodUnit.new(&"fire")), &"fire",
			"a live Unit answers get_element(), which reads its CharacterResource")
	assert_eq(ElementVisuals.of_unit(_ElementUnit.new(&"frost")), &"frost",
			"a mock exposing a plain property is read too")
	assert_eq(ElementVisuals.of_unit(null), &"",
			"and a null subject is unelemented rather than an error")


func test_a_moves_element_is_read_the_same_way() -> void:
	var move := MoveResource.new()
	move.element = &"holy"
	assert_eq(ElementVisuals.of_move(move), &"holy", "the move's authored element")
	assert_eq(ElementVisuals.of_move(null), &"", "null is neutral, never an error")


# --- The matchup verdict ---------------------------------------------------------

func test_a_multiplier_is_classified_as_strong_resisted_or_neutral() -> void:
	assert_eq(ElementVisuals.label_for_multiplier(1.5), ElementVisuals.STRONG,
			"above 1.0 is a matchup in the attacker's favour")
	assert_eq(ElementVisuals.label_for_multiplier(1.25), ElementVisuals.STRONG,
			"however slim the edge")
	assert_eq(ElementVisuals.label_for_multiplier(0.75), ElementVisuals.RESISTED,
			"below 1.0 is a matchup against it")
	assert_eq(ElementVisuals.label_for_multiplier(1.0), ElementVisuals.NEUTRAL,
			"and exactly 1.0 is no matchup at all")


func test_float_noise_around_one_still_reads_as_neutral() -> void:
	# The multiplier is a PRODUCT of floats (effectiveness x tile amplifier x own-tile
	# benefit), so an exact == 1.0 test would print "Strong x1" on rounding dust.
	assert_eq(ElementVisuals.label_for_multiplier(1.0 + 0.0001), ElementVisuals.NEUTRAL,
			"a multiplier a rounding error above 1.0 is not a strong hit")
	assert_eq(ElementVisuals.label_for_multiplier(1.0 - 0.0001), ElementVisuals.NEUTRAL,
			"and one a rounding error below it is not a resisted one")


# --- The effectiveness LINE ------------------------------------------------------

func test_a_strong_matchup_names_the_verdict_and_the_number() -> void:
	var text: String = ElementVisuals.effectiveness_text(1.25, ElementVisuals.STRONG)
	assert_eq(text, "Strong ×1.25",
			"the row says both what happened and by how much: %s" % text)


func test_a_resisted_matchup_reads_the_same_way() -> void:
	assert_eq(ElementVisuals.effectiveness_text(0.75, ElementVisuals.RESISTED),
			"Resisted ×0.75", "the losing side of the chart is stated just as plainly")


func test_a_neutral_matchup_renders_nothing_at_all() -> void:
	# THE design rule for this row, and the reason it is a row that appears rather than a
	# row that is always there: the common case must cost the 720p card no height.
	assert_eq(ElementVisuals.effectiveness_text(1.0, ElementVisuals.NEUTRAL), "",
			"a neutral matchup produces no line, so the panel hides the whole row")
	assert_eq(ElementVisuals.effectiveness_text(1.0), "",
			"and that holds when the label is derived rather than supplied")


func test_the_multiplier_prints_without_trailing_zero_noise() -> void:
	assert_eq(ElementVisuals.format_multiplier(1.5), "1.5", "x1.50 reads as a multiplier")
	assert_eq(ElementVisuals.format_multiplier(0.75), "0.75", "two decimals when it needs them")
	assert_eq(ElementVisuals.format_multiplier(2.0), "2", "and a whole number as a whole number")


func test_an_unusable_label_falls_back_to_the_arithmetic() -> void:
	# A previewer that carries a label we do not recognise must not silence the row --
	# the NUMBER is still the ground truth.
	assert_eq(ElementVisuals.effectiveness_text(1.5, &"super_duper"), "Strong ×1.5",
			"an unknown label defers to the multiplier rather than blanking the row")


func test_the_matchup_colour_is_the_huds_buff_debuff_pair() -> void:
	# Reused rather than invented, so "green is better for me" is one rule across the HUD
	# and neither colour can be mistaken for an element hue.
	assert_eq(ElementVisuals.effectiveness_color(ElementVisuals.STRONG),
			MoveStatVisuals.BUFF_COLOR, "a strong matchup is the same green a buffed stat is")
	assert_eq(ElementVisuals.effectiveness_color(ElementVisuals.RESISTED),
			MoveStatVisuals.NERF_COLOR, "and a resisted one the same red a cut stat is")
	assert_eq(ElementVisuals.effectiveness_color(ElementVisuals.NEUTRAL, ConquestTheme.CREAM),
			ConquestTheme.CREAM, "neutral keeps whatever ink the caller passed")


# --- The ability LINE -------------------------------------------------------------

func test_an_ability_bonus_names_its_size_and_its_reason() -> void:
	var text: String = ElementVisuals.ability_bonus_text(30, ["Grass Cutter"])
	assert_eq(text, "+30% (Grass Cutter)",
			"the row says how much and which ability did it: %s" % text)


func test_a_negative_ability_effect_reads_as_a_reduction() -> void:
	assert_eq(ElementVisuals.ability_bonus_text(-25, ["Grovebound"]), "-25% (Grovebound)",
			"a defender's passive taking damage OFF states the minus sign")


func test_several_notes_share_the_one_line() -> void:
	# The card has a width budget, not a height one, and two abilities on one hit is
	# already the rare case.
	assert_eq(ElementVisuals.ability_bonus_text(45, ["Grass Cutter", "Thornlust"]),
			"+45% (Grass Cutter, Thornlust)", "both reasons are named on the single row")


func test_a_bonus_with_no_note_still_states_the_number() -> void:
	assert_eq(ElementVisuals.ability_bonus_text(30, []), "+30%",
			"an unnamed source is still worth reporting -- the number is the fact")
	assert_eq(ElementVisuals.ability_bonus_text(30, null), "+30%",
			"and a missing notes array is not an error")


func test_blank_notes_are_dropped_rather_than_printed_as_gaps() -> void:
	assert_eq(ElementVisuals.ability_bonus_text(10, ["", "  ", "Deep Roots"]),
			"+10% (Deep Roots)", "empty entries never become stray commas")


func test_no_ability_bonus_renders_nothing_at_all() -> void:
	assert_eq(ElementVisuals.ability_bonus_text(0, ["Grass Cutter"]), "",
			"0% is no effect, so the row is hidden however many notes came with it")


func test_the_ability_colour_follows_who_the_bonus_helps() -> void:
	assert_eq(ElementVisuals.ability_bonus_color(30), MoveStatVisuals.BUFF_COLOR,
			"extra damage for the attacker is green")
	assert_eq(ElementVisuals.ability_bonus_color(-30), MoveStatVisuals.NERF_COLOR,
			"damage taken off it is red")


# --- The badge WIDGET (built, not yet rendered) --------------------------------------

func test_a_badge_for_an_element_carries_its_name_and_its_colour() -> void:
	var badge: PanelContainer = autofree(ElementVisuals.make_badge(&"nature"))
	assert_true(badge.visible, "an elemented unit gets a visible badge")
	var label := badge.get_node(ElementVisuals.BADGE_LABEL_NAME) as Label
	assert_eq(label.text, "Nature", "naming the element")
	var box := badge.get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box, "and painted with its own stylebox")
	if box != null:
		assert_eq(box.border_color, ConquestTheme.element_color("nature"),
				"framed in the shared element colour")


func test_a_badge_for_no_element_is_hidden_rather_than_blank() -> void:
	# A visible-but-empty pill is a smudge on the card. "No element" means no widget.
	var badge: PanelContainer = autofree(ElementVisuals.make_badge(&""))
	assert_false(badge.visible, "an unelemented unit's badge takes no slot on the row")


func test_re_pointing_a_badge_swaps_the_element_without_rebuilding_it() -> void:
	var badge: PanelContainer = autofree(ElementVisuals.make_badge(&"fire"))
	ElementVisuals.update_badge(badge, &"frost")
	var label := badge.get_node(ElementVisuals.BADGE_LABEL_NAME) as Label
	assert_eq(label.text, "Frost", "the badge follows the newly shown unit")
	ElementVisuals.update_badge(badge, &"")
	assert_false(badge.visible, "and disappears for a unit with no element")
	ElementVisuals.update_badge(badge, &"holy")
	assert_true(badge.visible, "then comes back for one that has")


func test_the_badge_label_states_a_real_minimum_width() -> void:
	# The trap this exists for: the label is clipped (so a long id trims instead of
	# widening the row), a clipped Label reports a 1px minimum, and the badge is laid out
	# at exactly its minimum inside an HBox. Without an explicit width it is a dot.
	var badge: PanelContainer = autofree(ElementVisuals.make_badge(&"nature"))
	var label := badge.get_node(ElementVisuals.BADGE_LABEL_NAME) as Label
	assert_true(label.custom_minimum_size.x > 1.0,
			"the badge claims room for its text (%.1fpx) rather than collapsing to a dot"
			% label.custom_minimum_size.x)
	assert_true(label.custom_minimum_size.x <= ElementVisuals.BADGE_MAX_WIDTH,
			"while staying inside the cap the rows budgeted for it")


func test_an_over_long_element_is_capped_rather_than_widening_its_row() -> void:
	var badge: PanelContainer = autofree(
			ElementVisuals.make_badge(&"impossibly_long_element_name_from_a_mod"))
	var label := badge.get_node(ElementVisuals.BADGE_LABEL_NAME) as Label
	assert_eq(label.custom_minimum_size.x, ElementVisuals.BADGE_MAX_WIDTH,
			"a long id stops at the cap -- the row's budget wins over the text")
	assert_eq(label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
			"and trims with an ellipsis rather than being cut mid-glyph")
