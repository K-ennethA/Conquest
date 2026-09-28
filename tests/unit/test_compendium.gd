extends GutTest

## Compendium (menus/Compendium.gd + menus/CompendiumData.gd): the data model must
## cover EVERY authored weather, tile effect, status, roster unit, move and ability,
## so future content cannot be forgotten; plus the scene, cross-links, the in-battle
## overlay and the shared tooltip wording.


func before_each() -> void:
	CompendiumData.clear_cache()


static func _entry_text(e: Dictionary) -> String:
	var parts: Array[String] = [String(e["title"]), String(e.get("subtitle", ""))]
	for b in e["blocks"]:
		for k in ["text"]:
			if b.has(k):
				parts.append(String(b[k]))
		for item in b.get("items", []):
			parts.append(String(item))
		for row in b.get("rows", []):
			for cell in row:
				parts.append(String(cell))
	return "\n".join(parts)


func _ids(section: String) -> Array:
	return CompendiumData.entries(section).map(func(e): return String(e["id"]))


# --- Coverage: nothing authored may be missing -----------------------------------------

func test_every_weather_has_an_entry_with_its_rules() -> void:
	var ids := _ids(CompendiumData.SECTION_WEATHER)
	for wid in Weather.all_ids():
		assert_true(String(wid) in ids, "weather %s listed" % wid)
		var w := Weather.get_weather(wid)
		var e := CompendiumData.find(CompendiumData.SECTION_WEATHER, String(wid))
		var text := _entry_text(e)
		assert_string_contains(text, w.display_name)
		for el in w.element_damage_scale:
			assert_string_contains(text, String(el).capitalize(), "%s damage row" % wid)
		for rule in w.turn_start_rules + w.stat_rules:
			assert_string_contains(text, rule.display_name, "%s rule %s" % [wid, rule.display_name])
		if not w.is_neutral():
			assert_gt(CompendiumData.weather_effect_rows(w).size(), 0, "%s has effect rows" % wid)


func test_every_tile_effect_resource_has_an_entry() -> void:
	var ids := _ids(CompendiumData.SECTION_TILES)
	var dir := DirAccess.open(CompendiumData.TILE_EFFECT_DIR)
	assert_not_null(dir)
	var n := 0
	for f in dir.get_files():
		var name := f.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var te = load(CompendiumData.TILE_EFFECT_DIR + name)
		assert_true(te is TileEffectResource)
		assert_true(String(te.id) in ids, "tile effect %s listed" % te.id)
		n += 1
	assert_gt(n, 8)


func test_every_status_has_an_entry_with_a_description() -> void:
	var ids := _ids(CompendiumData.SECTION_STATUSES)
	for s in StatusCatalog.all_statuses():
		assert_true(String(s.id) in ids, "status %s listed" % s.id)
		var e := CompendiumData.find(CompendiumData.SECTION_STATUSES, String(s.id))
		assert_ne(String(e["subtitle"]), "", "status %s described" % s.id)


func test_every_roster_unit_lists_all_moves_and_abilities() -> void:
	var ids := _ids(CompendiumData.SECTION_UNITS)
	for cid in CharacterLibrary.all_ids():
		var c := CharacterLibrary.get_character(cid)
		assert_true(String(c.character_id) in ids, "unit %s listed" % cid)
		var text := _entry_text(CompendiumData.find(CompendiumData.SECTION_UNITS, String(c.character_id)))
		for m in c.moveset:
			if m == null:
				continue
			assert_string_contains(text, m.display_name, "%s move %s" % [cid, m.display_name])
			for fx in m.effects:
				if fx != null and String(fx.describe()) != "":
					assert_string_contains(CompendiumData._strip_bb(text), String(fx.describe()),
						"%s / %s full effect text" % [cid, m.display_name])
		for a in c.abilities:
			if a != null:
				assert_string_contains(text, a.display_name, "%s ability %s" % [cid, a.display_name])
		if c.element != &"":
			assert_string_contains(text, String(c.element).capitalize())
		for t in c.tags:
			assert_string_contains(text, String(t))


func test_rules_cover_the_element_chart_and_mechanics() -> void:
	var ids := _ids(CompendiumData.SECTION_RULES)
	for id in ["elements", "hit", "height", "floors", "tiles", "fog", "weather", "turns", "facing", "controls"]:
		assert_true(id in ids, "rules entry %s" % id)
	# Every element the chart RESOURCE authors (element_chart.tres, the one matchup
	# source the damage pipeline reads) is summarised on the rules page.
	var chart := _entry_text(CompendiumData.find(CompendiumData.SECTION_RULES, "elements"))
	for el in ElementChart.vocabulary():
		assert_string_contains(chart, String(el).capitalize())
	var height := _entry_text(CompendiumData.find(CompendiumData.SECTION_RULES, "height"))
	assert_string_contains(height, CompendiumData._num(Elevation.HIGH_GROUND_DAMAGE_SCALE))
	var controls := _entry_text(CompendiumData.find(CompendiumData.SECTION_RULES, "controls"))
	for d in InputActions.REBINDABLE:
		assert_string_contains(controls, String(d["label"]))


func test_every_charted_element_has_an_entry_read_off_the_chart() -> void:
	var ids := _ids(CompendiumData.SECTION_ELEMENTS)
	for el in ElementChartGallery.elements():
		assert_true(String(el) in ids, "element %s listed" % el)
		var text := _entry_text(CompendiumData.find(CompendiumData.SECTION_ELEMENTS, String(el)))
		for strong in ElementChartGallery.strong_against(el):
			assert_string_contains(text, String(strong).capitalize(), "%s strong vs %s" % [el, strong])
		for weak in ElementChartGallery.weak_to(el):
			assert_string_contains(text, String(weak).capitalize(), "%s weak to %s" % [el, weak])
		for c in CompendiumData.units_of_element(el):
			assert_string_contains(text, CompendiumData._char_name(c), "%s unit %s" % [el, c.character_id])


func test_tile_effect_entries_carry_the_charted_element_and_trap_rules() -> void:
	for te in CompendiumData.tile_effects():
		var text := _entry_text(CompendiumData.find(CompendiumData.SECTION_TILES, String(te.id)))
		var el := ElementChart.tile_element_of(te)
		if el != &"":
			assert_string_contains(text, String(el).capitalize(), "%s element" % te.id)
		if te.springs_on_pass:
			assert_string_contains(text, String(te.trap_descriptor()), "%s trap line" % te.id)


# --- Derived relations ---------------------------------------------------------------

func test_weather_links_its_units_and_maps() -> void:
	var rain := _entry_text(CompendiumData.find(CompendiumData.SECTION_WEATHER, "rain"))
	assert_string_contains(rain, "Rain Bath", "weather-conditioned ability")
	assert_string_contains(rain, "Fire", "douses fire")
	var bloom := _entry_text(CompendiumData.find(CompendiumData.SECTION_WEATHER, "overbloom"))
	assert_string_contains(bloom, "Verdant Call", "summoning move")
	assert_string_contains(bloom, "Forgotten Forest", "map schedule")
	var storm := _entry_text(CompendiumData.find(CompendiumData.SECTION_WEATHER, "desert_storm"))
	assert_string_contains(storm, "Sand Veil")
	assert_string_contains(storm, "-15")


func test_tile_effect_entry_derives_trigger_numbers_and_weather() -> void:
	var fire := _entry_text(CompendiumData.find(CompendiumData.SECTION_TILES, "fire"))
	assert_string_contains(fire, "15", "damage from its DamageEffect")
	assert_string_contains(fire, "Rain", "doused by rain")
	assert_string_contains(fire, "start of each turn")


func test_tooltips_share_the_compendium_wording() -> void:
	var rain := Weather.get_weather(&"rain")
	var tip := CompendiumData.weather_tooltip(rain)
	assert_string_contains(tip, rain.description)
	assert_string_contains(tip, "Water moves x1.3")
	var poison: StatusCondition = StatusCatalog.find_by_id(&"poisoned")
	assert_string_contains(CompendiumData.status_tooltip(poison, 2), CompendiumData.status_description(poison))
	var fire := load("res://game/tiles/effects/resources/fire.tres")
	assert_string_contains(CompendiumData.tile_effect_tooltip(fire), "Doused by Rain")


func test_search_spans_sections() -> void:
	var hits := CompendiumData.search(CompendiumData.all_entries(), "rain")
	var sections := hits.map(func(e): return String(e["section"]))
	assert_true(CompendiumData.SECTION_WEATHER in sections)
	assert_true(CompendiumData.SECTION_UNITS in sections, "Mycothrall (Rain Bath)")


# --- Scene -------------------------------------------------------------------------------

func test_scene_builds_every_section_and_follows_links() -> void:
	var comp: Compendium = load("res://menus/Compendium.tscn").instantiate()
	add_child_autofree(comp)
	await get_tree().process_frame
	for i in Compendium.SECTION_TITLES.size():
		if i in Compendium.HOSTED_SCENES:
			continue  # 3D galleries are covered by their own screens
		comp.select_tab(i)
		await get_tree().process_frame
	assert_true(comp.follow_link("weather:rain"))
	assert_eq(comp.tab_container.current_tab, Compendium.SECTION_WEATHER)
	assert_true(comp.follow_link("tiles:fire"))
	assert_eq(comp.tab_container.current_tab, Compendium.SECTION_TILE_EFFECTS)
	assert_true(comp.follow_link("rules:elements"))
	assert_gt(comp.status_list.item_count, 5)


func test_overlay_blocks_board_input_and_closes() -> void:
	var comp := Compendium.open_overlay(get_tree(), Compendium.SECTION_RULES)
	assert_not_null(comp)
	await get_tree().process_frame
	assert_true(comp.overlay_mode)
	assert_true(InputActions.gameplay_input_blocked(get_tree()), "board input blocked while open")
	var layer := comp.get_parent()
	comp.handle_back()
	await get_tree().process_frame
	assert_false(is_instance_valid(layer) and layer.is_inside_tree(), "overlay removed")
	assert_false(InputActions.gameplay_input_blocked(get_tree()))
