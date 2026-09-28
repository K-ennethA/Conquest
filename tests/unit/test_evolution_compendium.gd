extends GutTest

## The Compendium's EVOLUTION content (EVOLUTION.md task 1.8): a unit page in a line shows the
## line as cross-links both ways, units in no line are unchanged, and Rules gains a
## "Growth & Evolution" entry read off evolution_rules.tres. Kept apart from test_compendium.gd
## so that shared suite is untouched.


func before_each() -> void:
	CompendiumData.clear_cache()
	EvolutionLibrary.rescan()


static func _text(e: Dictionary) -> String:
	var parts: Array[String] = [String(e.get("title", "")), String(e.get("subtitle", ""))]
	for b in e.get("blocks", []):
		if b.has("text"):
			parts.append(String(b["text"]))
		for item in b.get("items", []):
			parts.append(String(item))
	return "\n".join(parts)


func test_barkling_links_to_oakheart_and_back() -> void:
	var bark := _text(CompendiumData.find(CompendiumData.SECTION_UNITS, "tree_grunt"))
	var oak := _text(CompendiumData.find(CompendiumData.SECTION_UNITS, "oakheart"))
	assert_string_contains(bark, "[url=units:oakheart]Oakheart[/url]", "Barkling's page links to Oakheart")
	assert_string_contains(oak, "[url=units:tree_grunt]Barkling[/url]", "Oakheart's page links back to Barkling")
	assert_string_contains(bark, "Evolves into", "Barkling's page says what it becomes")
	assert_string_contains(oak, "Evolves from", "Oakheart's page says where it comes from")
	assert_string_contains(bark, "Growth 3", "with the trigger text")
	assert_string_contains(bark, "Requires all of", "every requirement is listed (DECISIONS.md #26)")
	assert_string_contains(bark, "Win 2 battles with it", "the battle-feat requirement too")


func test_units_in_no_line_have_no_evolution_block() -> void:
	var vine := CompendiumData.find(CompendiumData.SECTION_UNITS, "vineweave")
	for b in vine["blocks"]:
		assert_ne(String(b.get("text", "")), "Evolution", "Vineweave has no Evolution heading")
	assert_eq(CompendiumData.evolution_blocks(CharacterLibrary.get_character(&"vineweave")), [],
		"evolution_blocks is empty for a unit in no line")


func test_search_finds_evolution() -> void:
	var hits := CompendiumData.search(CompendiumData.unit_entries(), "evolve")
	var ids: Array = hits.map(func(e): return String(e["id"]))
	assert_true(ids.has("tree_grunt") and ids.has("oakheart"), "searching 'evolve' finds both forms")


func test_rules_explain_growth_from_the_rules_resource() -> void:
	var entry := CompendiumData.find(CompendiumData.SECTION_RULES, "evolution")
	assert_false(entry.is_empty(), "Rules has a Growth & Evolution entry")
	var text := _text(entry)
	assert_string_contains(text, "+%d" % EvolutionRules.current().growth_per_win, "it quotes growth_per_win")
	assert_string_contains(text, "[url=units:oakheart]", "and lists the shipped lines")
