extends GutTest

## The Compendium's EVOLUTION content (EVOLUTION.md task 1.8): a unit page in a line shows the
## line as cross-links both ways, units in no line are unchanged, and Rules gains a
## "Growth & Evolution" entry read off evolution_rules.tres. Kept apart from test_compendium.gd
## so that shared suite is untouched.

## The test-only Barkling -> Mycothrall edge (Growth 3 + 2 wins), for the multi-requirement text.
const EvoFixture := preload("res://tests/helpers/evolution_fixture.gd")
## A unit in no evolution line (shipped or fixture).
const NO_LINE := &"gem_knight"


func before_each() -> void:
	CompendiumData.clear_cache()
	EvolutionLibrary.rescan()


func after_each() -> void:
	EvoFixture.uninstall()
	CompendiumData.clear_cache()


static func _text(e: Dictionary) -> String:
	var parts: Array[String] = [String(e.get("title", "")), String(e.get("subtitle", ""))]
	for b in e.get("blocks", []):
		if b.has("text"):
			parts.append(String(b["text"]))
		for item in b.get("items", []):
			parts.append(String(item))
	return "\n".join(parts)


func test_barkling_links_to_cinderbark_and_back() -> void:
	var bark := _text(CompendiumData.find(CompendiumData.SECTION_UNITS, "tree_grunt"))
	var cinder := _text(CompendiumData.find(CompendiumData.SECTION_UNITS, "ember_stump"))
	assert_string_contains(bark, "[url=units:ember_stump]Cinderbark[/url]", "Barkling's page links to Cinderbark")
	assert_string_contains(cinder, "[url=units:tree_grunt]Barkling[/url]", "Cinderbark's page links back to Barkling")
	assert_string_contains(bark, "Evolves into", "Barkling's page says what it becomes")
	assert_string_contains(cinder, "Evolves from", "Cinderbark's page says where it comes from")
	assert_string_contains(bark, "Use ", "with the trigger text (use the Sunstone)")
	assert_string_contains(bark, "(story only)", "a used item is marked story only")


func test_a_multi_requirement_edge_lists_every_requirement() -> void:
	EvoFixture.install()
	CompendiumData.clear_cache()
	var bark := _text(CompendiumData.find(CompendiumData.SECTION_UNITS, "tree_grunt"))
	assert_string_contains(bark, "[url=units:mycothrall]Mycothrall[/url]", "the fixture branch is linked too")
	assert_string_contains(bark, "Growth 3", "with the trigger text")
	assert_string_contains(bark, "Requires all of", "every requirement is listed (DECISIONS.md #26)")
	assert_string_contains(bark, "Win 2 battles with it", "the battle-feat requirement too")


func test_units_in_no_line_have_no_evolution_block() -> void:
	var page := CompendiumData.find(CompendiumData.SECTION_UNITS, String(NO_LINE))
	assert_false(page.is_empty(), "the unit has a page")
	for b in page.get("blocks", []):
		assert_ne(String(b.get("text", "")), "Evolution", "a unit in no line has no Evolution heading")
	assert_eq(CompendiumData.evolution_blocks(CharacterLibrary.get_character(NO_LINE)), [],
		"evolution_blocks is empty for a unit in no line")


func test_search_finds_evolution() -> void:
	var hits := CompendiumData.search(CompendiumData.unit_entries(), "evolve")
	var ids: Array = hits.map(func(e): return String(e["id"]))
	assert_true(ids.has("tree_grunt") and ids.has("ember_stump"), "searching 'evolve' finds both forms")


func test_rules_explain_growth_from_the_rules_resource() -> void:
	var entry := CompendiumData.find(CompendiumData.SECTION_RULES, "evolution")
	assert_false(entry.is_empty(), "Rules has a Growth & Evolution entry")
	var text := _text(entry)
	assert_string_contains(text, "+%d" % EvolutionRules.current().growth_per_win, "it quotes growth_per_win")
	for e in EvolutionLibrary.all():
		assert_string_contains(text, "[url=units:%s]" % e.to_id, "and lists the shipped lines (%s)" % e.id)
