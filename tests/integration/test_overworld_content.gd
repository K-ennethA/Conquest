extends GutTest

## CONTENT VALIDATION for story mode (docs/design/OVERWORLD.md Â§4.13): every shipped area loads,
## its terrain validates, entity ids are unique, warps target a real area + entry, every
## condition parses, every referenced scene / map / character / item exists, every trainer has a
## battle whose board validates -- and none of it ever leaks into a map picker.
##
## Plus the story OPENING's content (build_story_content.gd): Oakvale (home) and its ruins,
## the Mossway joining them to Crownhaven, the Crownhaven castle town (size budget, the
## ceremony, the raid, walkable streets) and the first fight's board.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OPENING_AREAS: Array[String] = ["oakvale", "oakvale_ruins", "mossway", "crownhaven", "woodland_town"]
const FIRST_FIGHT_MAP := "res://game/overworld/content/battles/ow_oakvale_ashes.tres"
## docs/design/OVERWORLD.md Â§4.3: every cell is a tile node -- keep areas <= ~32x32 (a route may
## be long and thin: the budget is the cell COUNT, each side within MapResource's 40).
const MAX_AREA_CELLS := 32
const MAX_AREA_SIDE := 40


func _areas() -> Array[OverworldAreaResource]:
	var out: Array[OverworldAreaResource] = []
	for id in StoryController.all_area_ids():
		var a := load(StoryController.area_path(id)) as OverworldAreaResource
		if a != null:
			out.append(a)
	return out


func _area(id: String) -> OverworldAreaResource:
	return load(StoryController.area_path(id)) as OverworldAreaResource


## Every command in [param commands], nested branches included.
func _flatten(commands: Array) -> Array:
	var out: Array = []
	var stack: Array = commands.duplicate()
	while not stack.is_empty():
		var c = stack.pop_front()
		if not (c is StoryCommand):
			continue
		out.append(c)
		for l in (c as StoryCommand).child_lists():
			stack.append_array(l)
	return out


func test_the_story_ships_the_opening_areas() -> void:
	var ids: Array[String] = StoryController.all_area_ids()
	for id in OPENING_AREAS:
		assert_true(ids.has(id), "%s ships" % id)
	assert_eq(_areas().size(), ids.size(), "every area directory holds a loadable area.tres")


func test_every_area_validates() -> void:
	for a in _areas():
		var issues: Array[String] = a.validate()
		assert_eq(issues, [] as Array[String], "%s validates clean: %s" % [a.area_id, str(issues)])
		assert_eq(String(a.area_id), a.resource_path.get_base_dir().get_file(),
			"%s: area_id matches its folder" % a.area_id)


func test_every_area_fits_the_size_budget() -> void:
	for a in _areas():
		assert_lte(a.width() * a.height(), MAX_AREA_CELLS * MAX_AREA_CELLS,
			"%s holds at most 32x32 cells (%dx%d)" % [a.area_id, a.width(), a.height()])
		assert_lte(maxi(a.width(), a.height()), MAX_AREA_SIDE, "%s: each side within %d" % [a.area_id, MAX_AREA_SIDE])


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
			if e is PropEntity and e.blocking:
				for c in e.cells():
					assert_true(g.is_terrain_passable(c), "%s/%s: a blocking prop stands on open ground" % [a.area_id, e.id])


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
	assert_gt(trainers, 0, "the story has a trainer (Bram)")


func test_the_road_is_walkable_end_to_end() -> void:
	# A traveller at the very start of the opening (sent off, no creature) can walk every leg.
	var s := StoryFixture.sent_off(StoryState.new())
	var legs := [
		["oakvale", Vector3i(3, 6, 0), Vector3i(23, 9, 0), "home -> the east exit"],
		["mossway", Vector3i(1, 6, 0), Vector3i(33, 6, 0), "the Mossway, west -> east"],
		["crownhaven", Vector3i(1, 13, 0), Vector3i(24, 9, 0), "the west gate -> the Researcher"],
		["crownhaven", Vector3i(1, 13, 0), Vector3i(15, 15, 0), "the west gate -> the Wayshrine"],
		["crownhaven", Vector3i(1, 13, 0), Vector3i(7, 10, 0), "the west gate -> the barracks"],
	]
	for leg in legs:
		var g := OverworldGrid.build(_area(leg[0]), s)
		var path: Array[Vector3i] = TapPathfinder.find_path(g, leg[1], leg[2])
		assert_false(path.is_empty(), "%s has a walkable path" % leg[3])
	var after := StoryFixture.past_opening(StoryState.new())
	after.clear_flag("opening.complete")
	var ruins := OverworldGrid.build(_area("oakvale_ruins"), after)
	assert_false(TapPathfinder.path_to_adjacent(ruins, Vector3i(21, 9, 0), Vector3i(13, 9, 0)).is_empty(),
		"in the ruins the Sergeant can be reached from the road")


func test_the_mossway_leads_home_to_whichever_oakvale_is_standing() -> void:
	var moss := _area("mossway")
	var before := StoryFixture.sent_off(StoryState.new())
	var raided := StoryState.new()
	raided.set_flag("opening.attack", 1)
	for pair in [[before, &"oakvale"], [raided, &"oakvale_ruins"]]:
		var targets: Array = []
		for e in moss.present_entities(pair[0]):
			if e is WarpEntity and e.occupies(Vector3i(0, 6, 0)):
				targets.append((e as WarpEntity).target_area)
		assert_eq(targets, [pair[1]], "exactly one west exit, to %s" % pair[1])
	var bram := moss.entity("bram")
	assert_false(bram.is_present(before), "Bram only takes the road after the opening")
	assert_true(bram.is_present(StoryFixture.past_opening(StoryState.new())), "and then he does")


func test_oakvale_home_opens_with_the_send_off() -> void:
	var oak := _area("oakvale")
	var rs := StoryRuleset.load_default()
	assert_eq(String(rs.start_area), "oakvale", "a new journey starts in Oakvale")
	assert_eq(rs.starting_party.size(), 0, "with no creature (the starter comes from the ceremony)")
	assert_eq(oak.entry("start")["cell"], Vector3i(3, 6, 0), "on the hero's own doorstep")
	assert_not_null(oak.entity("briony"), "the hero's mother is home")
	var flags: Array = []
	for c in _flatten(oak.on_enter):
		if c is SetFlagCommand:
			flags.append((c as SetFlagCommand).key)
	assert_true(flags.has("opening.sent_off"), "the first boot's send-off sets opening.sent_off")
	var props: int = 0
	for e in oak.entity_list():
		if e is PropEntity:
			props += 1
	assert_gt(props, 8, "a village's worth of scenery (houses, windmill, fields, well, fences)")


func test_the_ruins_mourn_offer_the_fight_and_hook_act_one() -> void:
	var ruins := _area("oakvale_ruins")
	assert_eq(ruins.lighting_preset(), "Night", "the ruins are night-lit")
	var vents: int = 0
	for e in ruins.terrain.tile_layout:
		if String(e.get("tile_id", "")) == "magma_vent":
			vents += 1
	assert_gt(vents, 10, "the burned houses smoulder (ember tiles under the ruins)")
	var battles: Array = []
	var flags: Array = []
	for c in _flatten(ruins.on_enter):
		if c is StartBattleCommand:
			battles.append(c)
		if c is SetFlagCommand:
			flags.append((c as SetFlagCommand).key)
	assert_eq(battles.size(), 1, "arriving leads to the Sergeant's offer of the first fight")
	var spec: BattleSpec = (battles[0] as StartBattleCommand).spec
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "the first fight is a TACTICAL battle")
	assert_eq(spec.map_path, FIRST_FIGHT_MAP, "on the mill-road board")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "a loss can be retried")
	for f in ["opening.ruins_seen", "opening.complete", "act1.find_rowan"]:
		assert_true(flags.has(f), "the ruins' script sets %s" % f)
	var cairn := ruins.entity("cairn") as SignEntity
	assert_not_null(cairn, "a cairn for the hero's mother")
	assert_eq(cairn.look, "stone", "a standing stone, not a signpost")
	assert_false(cairn.is_present(StoryState.new()), "raised only after the fight")


func test_crownhaven_is_a_walled_castle_town() -> void:
	var ch := _area("crownhaven")
	assert_not_null(ch, "Crownhaven ships")
	assert_eq(ch.validate(), [] as Array[String], "and validates clean")
	assert_lte(ch.width(), MAX_AREA_CELLS, "within the size budget (width)")
	assert_lte(ch.height(), MAX_AREA_CELLS, "within the size budget (height)")
	var kinds: Dictionary = {}
	for e in ch.entity_list():
		if e is PropEntity:
			kinds[(e as PropEntity).prop] = int(kinds.get((e as PropEntity).prop, 0)) + 1
	for k in ["keep", "gate", "tower", "stall", "crystal", "house", "banner"]:
		assert_true(kinds.has(k), "Crownhaven has a %s" % k)
	assert_gte(int(kinds.get("stall", 0)), 4, "a market square of stalls")
	var walls: int = 0
	for e in ch.terrain.tile_layout:
		if String(e.get("tile_id", "")) == "stone_wall":
			walls += 1
	assert_gt(walls, 80, "a stone wall rings the town")
	assert_not_null(ch.entity("wayshrine"), "a Wayshrine in the market")
	for id in ["linnea", "tam", "rowan", "lisk", "orwin", "dalla", "fenwick", "brisa", "corin"]:
		assert_true(ch.entity(id) is NpcEntity, "%s lives in Crownhaven" % id)


func test_the_ceremony_gives_the_starter_and_the_shard_then_the_raid() -> void:
	var ch := _area("crownhaven")
	var linnea := ch.entity("linnea") as NpcEntity
	var cmds: Array = _flatten(linnea.on_interact)
	var joins: Array = []
	var flags: Array = []
	var warps: Array = []
	for c in cmds:
		if c is JoinPartyCommand:
			joins.append(c)
		if c is SetFlagCommand:
			flags.append((c as SetFlagCommand).key)
		if c is WarpCommand:
			warps.append(c)
	assert_eq(joins.size(), 1, "the ceremony gives exactly one creature")
	var starter: CharacterResource = CharacterLibrary.get_character((joins[0] as JoinPartyCommand).character_id)
	assert_not_null(starter, "the starter is a real roster character")
	for f in ["key.bonding_shard", "opening.starter_received", "opening.attack", "opening.researcher_taken",
			"opening.raiders_fled", "opening.chase"]:
		assert_true(flags.has(f) or (joins[0] as JoinPartyCommand).flag_on_join == f, "the ceremony + raid set %s" % f)
	assert_eq(warps.size(), 1, "the raid ends in the chase to Oakvale")
	assert_eq(String((warps[0] as WarpCommand).area_id), "oakvale_ruins", "to the burning village")
	var raided := StoryState.new()
	raided.set_flag("opening.attack", 1)
	assert_true(ch.entity("raider_captain").is_present(raided), "raiders appear when the raid begins")
	assert_false(ch.entity("raider_captain").is_present(StoryState.new()), "and not before")


func test_the_first_fight_board() -> void:
	var m := load(FIRST_FIGHT_MAP) as MapResource
	assert_not_null(m, "the first fight's board ships")
	assert_true(bool(m.validate_map(true).get("valid", false)), "and validates")
	var starts: int = 0
	var guest: Array = []
	var foes: Array = []
	for sp in m.unit_spawns:
		var pid: int = int(sp.get("player_id", 0))
		var kind: String = m.get_spawn_kind(sp)
		if pid == 0 and kind == MapResource.SPAWN_KIND_START:
			starts += 1
		elif pid == 0:
			guest.append(sp)
		else:
			foes.append(String(sp.get("character_id", "")))
	assert_gt(starts, 0, "squad chairs for the party")
	assert_eq(guest.size(), 1, "one guest ally slot (the Sergeant's creature)")
	if guest.size() == 1:
		assert_true(m.is_initial_spawn(guest[0]), "placed at load, never replaced by the squad pick")
		assert_not_null(CharacterLibrary.get_character(StringName(String(guest[0].get("character_id", "")))),
			"a real roster character")
	assert_eq(foes.size(), 3, "three raider creatures (placeholders)")
	for cid in foes:
		assert_not_null(CharacterLibrary.get_character(StringName(cid)), "raider unit %s exists" % cid)


func test_story_content_never_appears_in_map_pickers() -> void:
	var content_paths: Array[String] = []
	for a in _areas():
		content_paths.append(a.terrain.resource_path)
	content_paths.append("res://game/overworld/content/battles/ow_mossway_clearing.tres")
	content_paths.append(FIRST_FIGHT_MAP)
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
	assert_eq(hero.display_name, "Wren", "the default hero name")
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


# --- The three home towns, built out: Oakvale (farming village), Crownhaven (capital), Woodland Town ---

func _prop_kinds(a: OverworldAreaResource) -> Dictionary:
	var kinds: Dictionary = {}
	for e in a.entity_list():
		if e is PropEntity:
			kinds[(e as PropEntity).prop] = int(kinds.get((e as PropEntity).prop, 0)) + 1
	return kinds


func test_every_prop_kind_has_a_builder() -> void:
	for k in PropEntity.KINDS:
		var n: Node3D = OverworldProps.prop(k, Vector2i(2, 2), Color.WHITE, 1)
		assert_not_null(n, "%s builds" % k)
		if n != null:
			n.free()


func test_oakvale_is_a_farming_village_with_an_inn_and_a_farm_hamlet_track() -> void:
	var oak := _area("oakvale")
	var kinds := _prop_kinds(oak)
	for k in ["house", "windmill", "crops", "haystack", "scarecrow", "stall", "lamp", "fence", "well"]:
		assert_true(kinds.has(k), "Oakvale has a %s" % k)
	for id in ["marra", "ned", "wick", "briony", "tobin", "hessa", "pell"]:
		assert_true(oak.entity(id) is NpcEntity, "%s lives in Oakvale" % id)
	assert_not_null(oak.entity("house_inn"), "the Hearth & Hen")
	var west := oak.entity("west_exit") as WarpEntity
	assert_not_null(west, "the mill lane runs out west toward Farm Hamlet")
	assert_ne(west.locked_scene, null, "and answers with a scene until that chapter exists")
	assert_not_null(_area("mossway").entity("river_crossing_sign"), "the Mossway marks River Crossing")


func test_crownhaven_has_districts_and_three_gates() -> void:
	var ch := _area("crownhaven")
	var kinds := _prop_kinds(ch)
	for k in ["chapel", "smithy", "keep", "gate", "lamp"]:
		assert_true(kinds.has(k), "Crownhaven has a %s" % k)
	assert_gte(int(kinds.get("gate", 0)), 3, "west, north and east gatehouses")
	for id in ["maribel", "veyra", "odalys", "garrick", "gate_warden"]:
		assert_true(ch.entity(id) is NpcEntity, "%s lives in Crownhaven" % id)
	var north := ch.entity("north_exit") as WarpEntity
	assert_eq(north.target_area, &"woodland_town", "the north gate leads to Woodland Town")
	var s := StoryFixture.past_opening(StoryState.new())
	assert_true(north.is_present(s), "the north exit exists")
	assert_false(north.requires.is_empty(), "and is held until the opening is over")


func test_woodland_town_is_a_timber_town() -> void:
	var wt := _area("woodland_town")
	assert_not_null(wt, "Woodland Town ships")
	assert_eq(wt.validate(), [] as Array[String], "and validates clean")
	var kinds := _prop_kinds(wt)
	for k in ["cabin", "logs", "smithy", "lamp", "cart", "fire", "dummy", "crops"]:
		assert_true(kinds.has(k), "Woodland Town has a %s" % k)
	assert_gte(int(kinds.get("cabin", 0)), 6, "a town of log cabins")
	assert_gte(int(kinds.get("logs", 0)), 4, "a lumber yard of log stacks")
	var trees: int = 0
	var water: int = 0
	for e in wt.terrain.tile_layout:
		match String(e.get("tile_id", "")):
			"tree":
				trees += 1
			"deep_water":
				water += 1
	assert_gt(trees, 150, "the forest closes in on the town")
	assert_gt(water, 10, "a stream runs through it")
	for id in ["hale", "bryn", "sedge", "burr", "torvald", "ilse", "ferra", "wicke", "stranger"]:
		assert_true(wt.entity(id) is NpcEntity, "%s lives in Woodland Town" % id)
	assert_true(wt.entity("sedge") is ShopEntity, "the trading post sells")
	assert_not_null(wt.entity("wayshrine"), "a Wayshrine on the square")
	assert_not_null(wt.entity("yard_chest"), "a woodcutter's chest")


func test_the_world_route_is_connected_and_walkable() -> void:
	# Oakvale -> the Mossway (River Crossing) -> Crownhaven -> Woodland Town, once the opening is over.
	var s := StoryFixture.past_opening(StoryState.new())
	var oak := _area("oakvale")
	var moss := _area("mossway")
	var ch := _area("crownhaven")
	var wt := _area("woodland_town")
	var legs := [
		[oak, Vector3i(22, 9, 0), Vector3i(10, 11, 0), "Oakvale: east gate -> the square"],
		[oak, Vector3i(10, 11, 0), Vector3i(16, 9, 0), "Oakvale: the square -> the inn path"],
		[oak, Vector3i(10, 11, 0), Vector3i(1, 12, 0), "Oakvale: the square -> the Farm Hamlet track"],
		[ch, Vector3i(1, 13, 0), Vector3i(9, 1, 0), "Crownhaven: west gate -> north gate"],
		[ch, Vector3i(1, 13, 0), Vector3i(25, 12, 0), "Crownhaven: west gate -> the chapel"],
		[ch, Vector3i(1, 13, 0), Vector3i(26, 17, 0), "Crownhaven: west gate -> the forge"],
		[ch, Vector3i(1, 13, 0), Vector3i(14, 21, 0), "Crownhaven: west gate -> the guildhall"],
		[ch, Vector3i(1, 13, 0), Vector3i(28, 13, 0), "Crownhaven: west gate -> the east road"],
		[wt, Vector3i(26, 12, 0), Vector3i(1, 12, 0), "Woodland Town: east road -> west road"],
		[wt, Vector3i(26, 12, 0), Vector3i(13, 14, 0), "Woodland Town: east road -> the Wayshrine"],
		[wt, Vector3i(26, 12, 0), Vector3i(24, 19, 0), "Woodland Town: east road -> the lumber yard"],
		[wt, Vector3i(26, 12, 0), Vector3i(12, 18, 0), "Woodland Town: east road -> the camp"],
		[wt, Vector3i(26, 12, 0), Vector3i(4, 22, 0), "Woodland Town: east road -> the south trail"],
		[wt, Vector3i(26, 12, 0), Vector3i(4, 8, 0), "Woodland Town: east road -> the archery range"],
	]
	for leg in legs:
		var g := OverworldGrid.build(leg[0], s)
		assert_false(TapPathfinder.find_path(g, leg[1], leg[2]).is_empty(), "%s is walkable" % leg[3])
	# The warps chain: Mossway east -> Crownhaven west gate; Crownhaven north -> Woodland east road
	# and back.
	var hops := [
		[moss, "east_exit", &"crownhaven", &"west_gate"],
		[ch, "north_exit", &"woodland_town", &"east_road"],
		[wt, "east_exit", &"crownhaven", &"north_gate"],
	]
	for h in hops:
		var w := (h[0] as OverworldAreaResource).entity(h[1]) as WarpEntity
		assert_not_null(w, "%s exists" % h[1])
		assert_eq(w.target_area, h[2], "%s leads to %s" % [h[1], h[2]])
		assert_eq(w.target_entry, h[3], "at %s" % h[3])


func test_the_future_roads_stay_closed_for_now() -> void:
	var s := StoryFixture.past_opening(StoryState.new())
	for pair in [["woodland_town", "west_exit"], ["woodland_town", "south_exit"], ["crownhaven", "east_exit"],
			["oakvale", "west_exit"]]:
		var w := _area(pair[0]).entity(pair[1]) as WarpEntity
		assert_not_null(w, "%s/%s exists" % pair)
		assert_false(w.requires.is_empty(), "%s/%s is gated" % pair)
		assert_not_null(w.locked_scene, "%s/%s explains itself" % pair)
