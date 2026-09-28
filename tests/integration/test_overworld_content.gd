extends GutTest

## CONTENT VALIDATION for story mode (docs/design/OVERWORLD.md §4.13): every shipped area loads,
## its terrain validates, entity ids are unique, warps target a real area + entry, every
## condition parses, every referenced scene / map / character / item exists, every trainer has a
## battle whose board validates -- and none of it ever leaks into a map picker.


func _areas() -> Array[OverworldAreaResource]:
	var out: Array[OverworldAreaResource] = []
	for id in StoryController.all_area_ids():
		var a := load(StoryController.area_path(id)) as OverworldAreaResource
		if a != null:
			out.append(a)
	return out


func test_the_slice_ships_oakvale_and_the_mossway() -> void:
	var ids: Array[String] = StoryController.all_area_ids()
	assert_true(ids.has("oakvale"), "Oakvale ships")
	assert_true(ids.has("mossway"), "Route 1 ships")
	assert_eq(_areas().size(), ids.size(), "every area directory holds a loadable area.tres")


func test_every_area_validates() -> void:
	for a in _areas():
		var issues: Array[String] = a.validate()
		assert_eq(issues, [] as Array[String], "%s validates clean: %s" % [a.area_id, str(issues)])
		assert_eq(String(a.area_id), a.resource_path.get_base_dir().get_file(),
			"%s: area_id matches its folder" % a.area_id)


func test_warps_target_real_areas_and_entries() -> void:
	for a in _areas():
		for e in a.entity_list():
			if not (e is WarpEntity):
				continue
			var w := e as WarpEntity
			var target := load(StoryController.area_path(String(w.target_area))) as OverworldAreaResource
			assert_not_null(target, "%s/%s targets an existing area" % [a.area_id, w.id])
			if target != null:
				assert_false(target.entry(String(w.target_entry)).is_empty(),
					"%s/%s targets an existing entry" % [a.area_id, w.id])
			for c in w.cells():
				assert_true(OverworldGrid.build(a, StoryState.new()).is_terrain_passable(c),
					"%s/%s: its cells can be walked onto" % [a.area_id, w.id])


func test_entries_and_actors_stand_on_walkable_ground() -> void:
	for a in _areas():
		var g := OverworldGrid.from_map(a.terrain)
		for eid in a.entry_ids():
			assert_true(g.is_terrain_passable(a.entry(eid)["cell"]), "%s entry '%s' is walkable" % [a.area_id, eid])
		for e in a.entity_list():
			if e is NpcEntity or e is ChestEntity or e is SignEntity:
				assert_true(g.is_terrain_passable(e.cell), "%s/%s stands on walkable ground" % [a.area_id, e.id])


func test_trainers_have_battles_and_can_see_the_road() -> void:
	var trainers: int = 0
	for a in _areas():
		for e in a.entity_list():
			if not (e is TrainerEntity):
				continue
			trainers += 1
			var t := e as TrainerEntity
			assert_not_null(t.battle, "%s has a battle" % t.id)
			var g := OverworldGrid.build(a, StoryState.new())
			var seen: Array[Vector3i] = TrainerSight.sight_cells(g, t.cell, OverworldEntity.facing_vector(t.facing), t.sight_range)
			assert_gt(seen.size(), 0, "%s is not staring into a wall" % t.id)
	assert_gt(trainers, 0, "the slice has a trainer (Bram)")


func test_the_elder_asks_a_question_with_a_quest_flag() -> void:
	var oak := load(StoryController.area_path("oakvale")) as OverworldAreaResource
	var elder: OverworldEntity = oak.entity("elder")
	assert_not_null(elder, "the Elder exists")
	var found_choice := false
	var stack: Array = elder.on_interact.duplicate()
	while not stack.is_empty():
		var c = stack.pop_back()
		if c is ChoiceCommand:
			found_choice = true
		if c is StoryCommand:
			for l in (c as StoryCommand).child_lists():
				stack.append_array(l)
	assert_true(found_choice, "her conversation offers a choice")


func test_story_content_never_appears_in_map_pickers() -> void:
	var content_paths: Array[String] = []
	for a in _areas():
		content_paths.append(a.terrain.resource_path)
	content_paths.append("res://game/overworld/content/battles/ow_mossway_clearing.tres")
	for listing in [MapLoader.get_available_maps(), MapLoader.get_available_maps(true)]:
		for p in listing:
			assert_false(String(p).begins_with("res://game/overworld/"), "picker lists %s" % p)
	for entry in MapLoader.get_available_map_entries(true):
		assert_false(String(entry.get("path", "")).begins_with("res://game/overworld/"), "entries list story content")
	for p in content_paths:
		var m := load(p) as MapResource
		assert_eq(m.status, "Inactive", "%s is an Inactive draft (belt and braces)" % p)


func test_hero_and_ruleset() -> void:
	var hero := HeroResource.load_default()
	assert_not_null(hero.model_scene, "the hero has a (placeholder) model, configured in ONE place")
	var inst: Node = hero.model_scene.instantiate()
	assert_not_null(inst, "that instantiates")
	if inst != null:
		inst.free()
	var rs := StoryRuleset.load_default()
	var start := load(StoryController.area_path(String(rs.start_area))) as OverworldAreaResource
	assert_not_null(start, "the ruleset's start area exists")
	assert_false(start.entry(String(rs.start_entry)).is_empty(), "and its start entry")
	for cid in rs.starting_party:
		assert_not_null(CharacterLibrary.get_character(cid), "starting member %s exists" % cid)
