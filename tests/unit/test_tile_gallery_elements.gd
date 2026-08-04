extends GutTest

## THE COMPENDIUM'S TILE PAGE, ELEMENTED -- the derivation half.
##
## The tile gallery predates the element work, so a tile's page said nothing about the
## matchup the board actually resolves for it. It does now, and the rules for WHERE that
## element comes from are pure statics on [TileGallery], pinned here:
##
##   * the element is read from `element_chart.tres` and nowhere else (CONQUEST.md rule 9)
##     -- never a field on the tile, so elementing new terrain stays a one-file content
##     edit;
##   * a tile is elemented by its OWN id (deep_water, molten_lava -- terrain that grows its
##     own effect, including terrain whose effect is a legacy TileEffect with no id to key
##     on) or by the first elemented effect it carries;
##   * an ELEMENTLESS tile stays elementless. The chart leaves pure-utility terrain neutral
##     on purpose, and inventing a badge there would promise a matchup the board never
##     resolves.
##
## The page as it is DRAWN -- badge present, badge wide enough for its text, absent for an
## elementless tile -- is `integration/test_compendium_tile_elements.gd`.


func after_each() -> void:
	# The chart is a static cache, i.e. global state. Restored from the hook so a failing
	# assertion cannot leak a swapped chart into a later suite.
	ElementChart.reset_chart()


## A tile with an authored id and (optionally) authored effects. Real [TileResource]s, not
## a double: they are plain Resources, so a unit test can hold them, and using the real
## class is what makes `get_id()` / `default_effects` the shapes the gallery reads.
func _tile(id: StringName, effects: Array = []) -> TileResource:
	var tile := TileResource.new()
	tile.id = id
	tile.tile_name = String(id).capitalize()
	tile.default_effects = effects
	tile.has_default_effects = not effects.is_empty()
	return tile


func _effect(id: StringName) -> TileEffectResource:
	var effect := TileEffectResource.new()
	effect.id = id
	effect.display_name = String(id).capitalize()
	return effect


# --- Where a tile's element comes from -----------------------------------------

func test_a_tile_is_elemented_by_its_own_id() -> void:
	# How terrain that grows its own effect is elemented: `deep_water -> water` is a TILE
	# id entry in the chart, and deep water carries no effect resource to key on at all.
	assert_eq(TileGallery.tile_element_of(_tile(&"deep_water")), &"water",
			"deep water reads its element off the chart's tile-id map")
	assert_eq(TileGallery.tile_element_of(_tile(&"molten_lava")), &"fire",
			"and so does lava, whose burn is a legacy TileEffect with no id")


func test_a_tile_is_otherwise_elemented_by_the_effect_it_carries() -> void:
	var tile: TileResource = _tile(&"unlisted_meadow", [_effect(&"sacred_meadow")])
	assert_eq(TileGallery.tile_element_of(tile), &"nature",
			"an authored effect elements the tile that carries it")


func test_the_tile_id_wins_over_the_effect_when_both_are_authored() -> void:
	var tile: TileResource = _tile(&"deep_water", [_effect(&"fire")])
	assert_eq(TileGallery.tile_element_of(tile), &"water",
			"the tile's own entry is the specific one, so it is the one that answers")


func test_an_unelemented_tile_stays_unelemented() -> void:
	assert_eq(TileGallery.tile_element_of(_tile(&"grass_plains")), &"",
			"the chart leaves pure-utility terrain neutral, and absence is the answer")
	assert_eq(TileGallery.tile_element_of(_tile(&"obsidian")), &"",
			"same for obsidian -- a badge here would promise a matchup nothing resolves")
	assert_eq(TileGallery.tile_element_of(null), &"", "and nothing at all is not elemented")


func test_an_effect_answers_for_itself_before_it_inherits_the_tile() -> void:
	var tile: TileResource = _tile(&"deep_water")
	assert_eq(TileGallery.effect_element_of(_effect(&"fire"), tile), &"fire",
			"an elemented effect resource carries its OWN element, wherever it sits")


func test_a_legacy_effect_with_no_id_inherits_the_tiles_element() -> void:
	# TileEffect (the legacy class) has no id at all, which is exactly why the chart
	# elements `molten_lava` as a TILE: the entry stands in for the burn that terrain
	# applies.
	var legacy := TileEffect.new()
	assert_eq(TileGallery.effect_element_of(legacy, _tile(&"molten_lava")), &"fire",
			"the burn on lava is fire because the lava is")
	assert_eq(TileGallery.effect_element_of(legacy, _tile(&"grass_plains")), &"",
			"and an effect on unelemented terrain stays unelemented")


# --- The matchup hint -----------------------------------------------------------

func test_the_matchup_hint_is_read_from_the_live_matrix() -> void:
	# Never a hand-written sentence: every name in the line comes out of the chart, so
	# retuning element_chart.tres retunes the Compendium with no code edit.
	var hint: String = TileGallery.matchup_hint(&"fire")
	gut.p("  fire hint: \"%s\"" % hint)
	for defender in ElementChartGallery.strong_against(&"fire"):
		assert_true(hint.contains(ElementVisuals.label_for(defender).to_lower()),
				"the hint names %s, which fire hits harder" % defender)
	for defender in TileGallery.resisted_against(&"fire"):
		assert_true(hint.contains(ElementVisuals.label_for(defender).to_lower()),
				"and %s, which resists it" % defender)


func test_resisted_against_is_the_other_half_of_the_row() -> void:
	# The chart has no implied symmetry -- every direction is authored -- so "hits harder"
	# and "hits softer" are two separate reads of the same row.
	for defender in TileGallery.resisted_against(&"fire"):
		assert_lt(ElementChart.multiplier(&"fire", defender), 1.0,
				"fire really does less to %s" % defender)
		assert_false(defender in ElementChartGallery.strong_against(&"fire"),
				"and %s is on exactly one side of the row" % defender)


func test_an_elementless_subject_has_nothing_to_say() -> void:
	assert_eq(TileGallery.matchup_hint(&""), "",
			"no element, no hint -- the row is hidden whole rather than filled with 'none'")
	assert_true(TileGallery.resisted_against(&"").is_empty(),
			"and it resists nothing, because it is not in the matrix")


func test_an_element_the_chart_has_authored_no_matchup_for_says_so() -> void:
	# Reported rather than papered over: an element with an empty row is a CONTENT gap, and
	# the Compendium's job is to show the content as it is.
	var unmatched: StringName = &""
	for element in ElementChartGallery.elements():
		if ElementChartGallery.strong_against(element).is_empty() \
				and TileGallery.resisted_against(element).is_empty():
			unmatched = element
			break
	if unmatched == &"":
		gut.p("  every shipped element has a matchup today -- nothing to assert")
		pass_test("no unmatched element in the shipped chart")
		return
	gut.p("  unmatched element: %s" % unmatched)
	assert_eq(TileGallery.matchup_hint(unmatched), ElementChartGallery.NO_MATCHUPS_TEXT,
			"an empty row reports itself")
