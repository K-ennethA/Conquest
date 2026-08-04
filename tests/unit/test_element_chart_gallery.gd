extends GutTest

## The Compendium ELEMENTS page's derivations, against CRAFTED charts.
##
## The load-bearing claim of that page is that it hardcodes NOTHING: not "there are
## seven elements", not 1.25, not "fire beats nature". Every one of these tests hands
## [ElementChart] a chart the shipped .tres has never seen and asserts the page's
## own rules read it back. If a content author adds an eighth element or retunes a
## matchup, this suite is what says the reference screen follows.
##
## The interesting cases are the ones a symmetric mental model gets wrong:
##   * an ASYMMETRIC pairing (a hits b hard; b does nothing back) -- the chart has no
##     implied inverse, so "strong against" and "weak to" are two separate reads;
##   * an UNPAIRED element that still resists itself (wind, as shipped) -- self
##     resistance is not a matchup, and the page must say "No matchups yet" rather
##     than invent an opposite;
##   * a NEUTRAL cell, which renders as nothing at all.

## The chart is a static cache, i.e. GLOBAL state. Restored from after_each -- which
## GUT runs even when a test fails -- so a failing assertion cannot leak a crafted
## chart into every later suite (tests/README.md rule 3).
func after_each() -> void:
	ElementChart.reset_chart()


# --- Fixtures ----------------------------------------------------------------

## Element ids as plain Strings. The derivations answer `Array[StringName]`, and an
## untyped literal on the other side of an assert_eq would compare unequal for reasons
## that have nothing to do with the rule under test.
func _names(list: Array) -> Array:
	var out: Array = []
	for entry in list:
		out.append(String(entry))
	return out


## Install a chart with exactly [param vocab] as its vocabulary and [param matrix] as
## its matrix. Everything else is left at the resource's own defaults.
func _install(vocab: Array, matrix: Dictionary) -> ElementChartResource:
	var res := ElementChartResource.new()
	var typed: Array[StringName] = []
	for entry in vocab:
		typed.append(StringName(entry))
	res.elements = typed
	res.matrix = matrix
	ElementChart.set_chart(res)
	return res


## a -> b is strong; c -> a is strong; b and c are hit by nothing else. Deliberately
## NOT symmetric: b takes extra from a but gives nothing back.
func _install_asymmetric() -> void:
	_install([&"aero", &"bio", &"cryo"], {
		&"aero": {&"bio": 1.5},
		&"cryo": {&"aero": 1.25},
	})


# --- The vocabulary ----------------------------------------------------------

func test_the_page_enumerates_the_charts_own_vocabulary_not_a_fixed_seven() -> void:
	_install([&"aero", &"bio", &"cryo"], {})
	assert_eq(_names(ElementChartGallery.elements()), ["aero", "bio", "cryo"],
		"the grid is built from the resource's element list, in authored order -- the "
		+ "shipped seven are content, not a code constant")


func test_an_element_only_the_matrix_mentions_still_gets_a_row() -> void:
	# An unlisted element is a LEGAL lookup (ElementChartResource never rejects one), so a
	# pairing authored against it really does apply in combat. A reference screen that
	# showed only the curated vocabulary would be quietly lying about live damage.
	_install([&"aero"], {&"aero": {&"umbra": 1.25}})
	var found: Array[StringName] = ElementChartGallery.elements()
	assert_true(found.has(&"aero"), "the authored vocabulary is listed first")
	assert_true(found.has(&"umbra"),
		"and an element the matrix pairs against, but the vocabulary forgot, still gets a row")


func test_each_element_appears_exactly_once() -> void:
	# Every element is named three times over in a two-way matrix (vocabulary, attacker
	# key, defender key); a duplicate would draw a duplicate row AND a duplicate sibling
	# node name.
	_install([&"aero", &"bio"], {
		&"aero": {&"bio": 1.25, &"aero": 0.75},
		&"bio": {&"aero": 1.25, &"bio": 0.75},
	})
	assert_eq(ElementChartGallery.elements().size(), 2,
		"an element named in the vocabulary and on both axes of the matrix is one row")


func test_an_empty_chart_lists_no_elements() -> void:
	_install([], {})
	assert_eq(ElementChartGallery.elements().size(), 0,
		"a chart with no vocabulary and no matrix has nothing to draw, and says so")


# --- One cell ----------------------------------------------------------------

func test_a_neutral_cell_is_blank_so_the_exceptions_pop() -> void:
	assert_eq(ElementChartGallery.cell_text(1.0), "",
		"a neutral pairing prints NOTHING -- a matrix is mostly 1.0, and 'x1' in forty "
		+ "cells buries the nine that matter")


func test_a_decided_cell_prints_its_multiplier() -> void:
	assert_eq(ElementChartGallery.cell_text(1.25), "×1.25", "a strong pairing shows its number")
	assert_eq(ElementChartGallery.cell_text(0.75), "×0.75", "so does a resisted one")
	assert_eq(ElementChartGallery.cell_text(2.0), "×2",
		"with no trailing-zero noise, so it reads as a multiplier and not as money")


func test_cells_are_tinted_with_the_shared_buff_nerf_pair() -> void:
	# The SAME green/red the battle forecast tints its effectiveness line with. This
	# screen must not introduce a second "better/worse" palette.
	assert_eq(ElementChartGallery.cell_color(1.25), MoveStatVisuals.BUFF_COLOR,
		"a pairing in the attacker's favour is the buff green")
	assert_eq(ElementChartGallery.cell_color(0.75), MoveStatVisuals.NERF_COLOR,
		"a pairing against the attacker is the nerf red")
	assert_eq(ElementChartGallery.cell_color(1.0), MenuTheme.CREAM_DIM,
		"and a neutral cell is dimmed, not coloured")


func test_a_neutral_cell_still_explains_itself_in_its_tooltip() -> void:
	_install([&"aero", &"bio"], {})
	var tip: String = ElementChartGallery.cell_tooltip(&"aero", &"bio", 1.0)
	assert_true(tip.contains("Aero") and tip.contains("Bio"),
		"the tooltip names both sides of the pairing")
	assert_true(tip.contains("Neutral"),
		"and says 'Neutral' -- the cell renders as nothing, so the tooltip is where the "
		+ "blank is explained rather than left ambiguous")


# --- Both directions ---------------------------------------------------------

func test_strong_against_reads_the_attackers_row() -> void:
	_install_asymmetric()
	assert_eq(_names(ElementChartGallery.strong_against(&"aero")), ["bio"],
		"aero's row authors one strong pairing, against bio")
	assert_eq(_names(ElementChartGallery.strong_against(&"bio")), [],
		"bio's row authors none -- the chart has NO implied inverse, so taking extra "
		+ "damage from aero does not make bio strong against it")


func test_weak_to_reads_the_defenders_column() -> void:
	_install_asymmetric()
	assert_eq(_names(ElementChartGallery.weak_to(&"bio")), ["aero"],
		"bio is hit hard by aero, read off the column rather than inferred from bio's row")
	assert_eq(_names(ElementChartGallery.weak_to(&"aero")), ["cryo"],
		"and aero, which is strong against bio, is itself weak to cryo")
	assert_eq(_names(ElementChartGallery.weak_to(&"cryo")), [],
		"nothing in this chart is strong against cryo")


func test_an_unknown_element_derives_nothing_rather_than_erroring() -> void:
	_install_asymmetric()
	assert_eq(_names(ElementChartGallery.strong_against(&"nonesuch")), [],
		"an element the chart never heard of has no matchups")
	assert_eq(_names(ElementChartGallery.weak_to(null)), [],
		"and a null is a returned empty list, never an engine error")
	assert_eq(ElementChartGallery.self_resist_text(null), "",
		"same for the self-resistance line")


# --- Self resistance, and the unpaired element -------------------------------

func test_self_resistance_reads_its_number_off_the_chart() -> void:
	_install([&"aero"], {&"aero": {&"aero": 0.5}})
	assert_eq(ElementChartGallery.self_resist_text(&"aero"), "Resists itself ×0.5",
		"the number comes from the resource -- 0.75 is the SEEDED convention, not a law")


func test_an_element_that_does_not_resist_itself_shows_no_such_line() -> void:
	_install([&"aero"], {})
	assert_eq(ElementChartGallery.self_resist_text(&"aero"), "",
		"self-resistance is authored per element; an element without it gets no line")


func test_self_resistance_is_not_a_matchup() -> void:
	# This is the wind case, in miniature. An element that resists itself and is
	# otherwise unpaired must still read as unpaired -- otherwise the page implies a
	# matchup the chart deliberately withheld.
	_install([&"aero", &"bio", &"gale"], {
		&"aero": {&"bio": 1.25},
		&"bio": {&"aero": 1.25},
		&"gale": {&"gale": 0.5},
	})
	assert_true(ElementChartGallery.has_no_matchups(&"gale"),
		"gale resists itself and has no opposite -- that is 'no matchups yet', not a matchup")
	assert_eq(ElementChartGallery.self_resist_text(&"gale"), "Resists itself ×0.5",
		"and its self-resistance is still reported")
	assert_false(ElementChartGallery.has_no_matchups(&"aero"),
		"while a paired element is not reported as unpaired")


func test_being_weak_to_something_counts_as_a_matchup() -> void:
	_install_asymmetric()
	assert_false(ElementChartGallery.has_no_matchups(&"bio"),
		"bio authors no strong pairing of its own, but something is strong against it -- "
		+ "that is a matchup, in the direction that matters to the player")


# --- The shipped chart -------------------------------------------------------

func test_the_shipped_chart_leaves_wind_unpaired() -> void:
	ElementChart.reset_chart()
	assert_true(ElementChartGallery.has_no_matchups(&"wind"),
		"wind ships with NO opposite on purpose (it has no content yet) -- the page says "
		+ "so rather than inventing one")
	assert_ne(ElementChartGallery.self_resist_text(&"wind"), "",
		"it does still resist itself, and that line is shown")


func test_the_shipped_chart_reads_fire_and_nature_both_ways() -> void:
	ElementChart.reset_chart()
	assert_true(ElementChartGallery.strong_against(&"fire").has(&"nature"),
		"fire burns wood")
	assert_true(ElementChartGallery.weak_to(&"fire").has(&"nature"),
		"and green chokes out flame -- the pair is authored in both directions")
	assert_eq(ElementChartGallery.cell_text(ElementChart.multiplier(&"fire", &"nature")),
		"×1.25", "which the grid cell prints as its seeded multiplier")
