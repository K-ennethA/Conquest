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
const OPENING_AREAS: Array[String] = ["oakvale", "oakvale_ruins", "mossway", "river_crossing", "crownhaven",
	"sparse_forest", "woodland_town"]
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
		["river_crossing", Vector3i(1, 14, 0), Vector3i(11, 0, 0), "River Crossing: the Mossway road -> over the Old Bridge -> north"],
		["crownhaven", Vector3i(15, 27, 0), Vector3i(24, 9, 0), "the south gate -> the Researcher"],
		["crownhaven", Vector3i(15, 27, 0), Vector3i(15, 15, 0), "the south gate -> the Wayshrine"],
		["crownhaven", Vector3i(15, 27, 0), Vector3i(7, 10, 0), "the south gate -> the barracks"],
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
	for aid in ["oakvale", "oakvale_ruins"]:
		var west := _area(aid).entity("west_exit") as WarpEntity
		assert_not_null(west, "%s: the mill lane runs out west toward Farm Hamlet" % aid)
		assert_eq(west.requires, "has(\"world.farm_hamlet_open\")", "%s: held by Farm Hamlet's flag" % aid)
		assert_ne(west.locked_scene, null, "%s: and answers with a scene until that chapter exists" % aid)
	assert_not_null(_area("mossway").entity("brook_sign"), "the Mossway's plank bridge is the Mossbrook")
	assert_null(_area("mossway").entity("river_crossing_sign"), "River Crossing is its own place now")


func test_after_the_opening_the_village_rebuilds_in_the_ruins() -> void:
	var ruins := _area("oakvale_ruins")
	var during := StoryFixture.sent_off(StoryState.new())
	during.set_flag("opening.attack", 1)
	var after := StoryFixture.past_opening(StoryState.new())
	for id in ["marra", "ned", "wick"]:
		var n := ruins.entity(id)
		assert_true(n is NpcEntity, "%s survives the raid" % id)
		assert_false(n.is_present(during), "%s is not out on the night of the raid" % id)
		assert_true(n.is_present(after), "%s is back to rebuild after the opening" % id)
	var fires: int = 0
	for e in ruins.present_entities(after):
		if e is PropEntity and (e as PropEntity).prop == "fire":
			fires += 1
	assert_eq(fires, 0, "the fires are out once the opening is over")
	assert_true(ruins.entity("rebuild_logs").is_present(after), "new timber on the inn's plot")


func test_crownhaven_has_five_gates_on_the_world_map_roads() -> void:
	var ch := _area("crownhaven")
	var kinds := _prop_kinds(ch)
	for k in ["chapel", "smithy", "keep", "gate", "lamp"]:
		assert_true(kinds.has(k), "Crownhaven has a %s" % k)
	assert_gte(int(kinds.get("gate", 0)), 5, "south, west, north, east and harbour gatehouses")
	for id in ["maribel", "veyra", "odalys", "garrick", "gate_warden"]:
		assert_true(ch.entity(id) is NpcEntity, "%s lives in Crownhaven" % id)
	var s := StoryFixture.past_opening(StoryState.new())
	# [exit, target area, open after the opening, the map's direction]
	for spec in [["south_exit", &"river_crossing", true, "south: River Crossing / Oakvale"],
			["west_exit", &"sparse_forest", true, "west: the Sparse Forest / Woodland Town"],
			["north_exit", &"crownhaven", false, "north: Mountain Base (closed)"],
			["east_exit", &"crownhaven", false, "east: the Rocky Badlands (closed)"],
			["harbour_exit", &"crownhaven", false, "south-east: Beach Village (closed)"]]:
		var w := ch.entity(spec[0]) as WarpEntity
		assert_not_null(w, spec[3])
		if w == null:
			continue
		assert_eq(w.target_area, spec[1], "%s targets %s" % [spec[3], spec[1]])
		assert_eq(w.is_open(s), spec[2], "%s is %s after the opening" % [spec[3], "open" if spec[2] else "closed"])
	assert_false((ch.entity("west_exit") as WarpEntity).is_open(StoryFixture.sent_off(StoryState.new())),
		"the west road is held until the opening is over")
	assert_true((ch.entity("south_exit") as WarpEntity).is_open(StoryState.new()), "the road home is always open")
	# A river city: the river runs along the whole south side, crossed only by the stone bridge.
	var g := OverworldGrid.from_map(ch.terrain)
	for x in range(ch.width()):
		for y in [25, 26]:
			var c := Vector3i(x, y, 0)
			if x >= 14 and x <= 16:
				assert_eq(String(g.tile_id_at(c)), "flagstones", "the bridge deck at %s" % c)
			else:
				assert_false(g.is_terrain_passable(c), "the river at %s" % c)


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
	# Oakvale -> the Mossway -> River Crossing -> Crownhaven -> the Sparse Forest -> Woodland Town,
	# once the opening is over.
	var s := StoryFixture.past_opening(StoryState.new())
	var oak := _area("oakvale")
	var moss := _area("mossway")
	var rc := _area("river_crossing")
	var ch := _area("crownhaven")
	var sf := _area("sparse_forest")
	var wt := _area("woodland_town")
	var legs := [
		[oak, Vector3i(22, 9, 0), Vector3i(10, 11, 0), "Oakvale: east gate -> the green"],
		[oak, Vector3i(10, 11, 0), Vector3i(16, 9, 0), "Oakvale: the green -> the inn path"],
		[oak, Vector3i(10, 11, 0), Vector3i(1, 12, 0), "Oakvale: the green -> the Farm Hamlet track"],
		[oak, Vector3i(10, 11, 0), Vector3i(10, 19, 0), "Oakvale: the green -> the jetty on the coast"],
		[_area("oakvale_ruins"), Vector3i(21, 9, 0), Vector3i(1, 12, 0), "the ruins: east road -> the Farm Hamlet track"],
		[rc, Vector3i(1, 14, 0), Vector3i(22, 14, 0), "River Crossing: the Mossway road -> the coast road"],
		[rc, Vector3i(22, 14, 0), Vector3i(11, 1, 0), "River Crossing: the coast road -> over the bridge, north"],
		[ch, Vector3i(15, 27, 0), Vector3i(1, 13, 0), "Crownhaven: south gate -> west gate"],
		[ch, Vector3i(15, 27, 0), Vector3i(9, 1, 0), "Crownhaven: south gate -> north gate"],
		[ch, Vector3i(15, 27, 0), Vector3i(25, 12, 0), "Crownhaven: south gate -> the chapel"],
		[ch, Vector3i(15, 27, 0), Vector3i(26, 17, 0), "Crownhaven: south gate -> Harbour Lane by the forge"],
		[ch, Vector3i(15, 27, 0), Vector3i(14, 21, 0), "Crownhaven: south gate -> the guildhall"],
		[ch, Vector3i(15, 27, 0), Vector3i(28, 13, 0), "Crownhaven: south gate -> the east road"],
		[ch, Vector3i(15, 27, 0), Vector3i(28, 17, 0), "Crownhaven: south gate -> the harbour road"],
		[sf, Vector3i(26, 6, 0), Vector3i(1, 6, 0), "the Sparse Forest, east -> west"],
		[wt, Vector3i(26, 12, 0), Vector3i(1, 12, 0), "Woodland Town: east road -> west road"],
		[wt, Vector3i(26, 12, 0), Vector3i(13, 14, 0), "Woodland Town: east road -> the Wayshrine"],
		[wt, Vector3i(26, 12, 0), Vector3i(24, 19, 0), "Woodland Town: east road -> the lumber yard"],
		[wt, Vector3i(26, 12, 0), Vector3i(12, 18, 0), "Woodland Town: east road -> the camp"],
		[wt, Vector3i(26, 12, 0), Vector3i(4, 22, 0), "Woodland Town: east road -> the south trail"],
		[wt, Vector3i(26, 12, 0), Vector3i(17, 1, 0), "Woodland Town: east road -> the north trail"],
		[wt, Vector3i(26, 12, 0), Vector3i(4, 8, 0), "Woodland Town: east road -> the archery range"],
	]
	for leg in legs:
		var g := OverworldGrid.build(leg[0], s)
		assert_false(TapPathfinder.find_path(g, leg[1], leg[2]).is_empty(), "%s is walkable" % leg[3])
	# The warps chain, both ways.
	var hops := [
		[oak, "east_exit", &"mossway", &"west"],
		[moss, "east_exit", &"river_crossing", &"west"],
		[rc, "west_exit", &"mossway", &"east"],
		[rc, "north_exit", &"crownhaven", &"south_gate"],
		[ch, "south_exit", &"river_crossing", &"north"],
		[ch, "west_exit", &"sparse_forest", &"east"],
		[sf, "east_exit", &"crownhaven", &"west_gate"],
		[sf, "west_exit", &"woodland_town", &"east_road"],
		[wt, "east_exit", &"sparse_forest", &"west"],
	]
	for h in hops:
		var w := (h[0] as OverworldAreaResource).entity(h[1]) as WarpEntity
		assert_not_null(w, "%s/%s exists" % [(h[0] as OverworldAreaResource).area_id, h[1]])
		if w == null:
			continue
		assert_eq(w.target_area, h[2], "%s leads to %s" % [h[1], h[2]])
		assert_eq(w.target_entry, h[3], "at %s" % h[3])
		assert_true(w.is_open(s), "%s/%s is open after the opening" % [(h[0] as OverworldAreaResource).area_id, h[1]])


func test_the_future_roads_stay_closed_for_now() -> void:
	var s := StoryFixture.past_opening(StoryState.new())
	var atlas := WorldAtlas.load_default()
	# [area, exit, the closed place it leads toward]
	for spec in [["woodland_town", "west_exit", "deepwood_village"], ["woodland_town", "south_exit", "thieves_guild"],
			["woodland_town", "north_exit", "frostpeak_village"], ["crownhaven", "north_exit", "mountain_base"],
			["crownhaven", "east_exit", "redrock_village"], ["crownhaven", "harbour_exit", "beach_village"],
			["river_crossing", "east_exit", "beach_village"], ["oakvale", "west_exit", "farm_hamlet"],
			["oakvale_ruins", "west_exit", "farm_hamlet"]]:
		var w := _area(spec[0]).entity(spec[1]) as WarpEntity
		assert_not_null(w, "%s/%s exists" % [spec[0], spec[1]])
		if w == null:
			continue
		assert_false(w.is_open(s), "%s/%s is closed" % [spec[0], spec[1]])
		assert_not_null(w.locked_scene, "%s/%s explains itself" % [spec[0], spec[1]])
		var place := atlas.location(spec[2])
		assert_false(place.is_built(), "%s is not built yet" % spec[2])
		assert_eq(w.requires, "has(\"%s\")" % place.open_flag, "%s/%s opens with %s's flag" % [spec[0], spec[1], spec[2]])
		assert_true(atlas.has_road(String(atlas.location_for_area(spec[0]).id), spec[2]),
			"the map has a road from %s toward %s" % [spec[0], spec[2]])


# --- The world map (WorldAtlas: content/world.tres) ---------------------------------------------

func test_the_world_atlas_registers_every_place_on_the_map() -> void:
	var atlas := WorldAtlas.load_default()
	assert_not_null(atlas, "content/world.tres ships")
	if atlas == null:
		return
	assert_eq(atlas.validate(), [] as Array[String], "and validates clean")
	for id in ["oakvale", "farm_hamlet", "mossway", "river_crossing", "crownhaven", "sparse_forest", "woodland_town",
			"thieves_guild", "deepwood_village", "depths_of_the_wood", "frostpeak_village", "mountain_base",
			"mountain_pass", "hidden_depths", "cindral", "redrock_village", "beach_village", "sunrise_isle",
			"island_of_tides", "stormreef_isle"]:
		assert_not_null(atlas.location(id), "%s is on the map" % id)
	# Every shipped area belongs to exactly one place, and shares its map position and region.
	for a in _areas():
		var l := atlas.location_for_area(String(a.area_id))
		assert_not_null(l, "%s is on the world map" % a.area_id)
		if l == null:
			continue
		assert_true(l.is_built(), "%s's place is BUILT" % a.area_id)
		assert_eq(a.world_map_pos, l.map_pos, "%s sits where the map puts %s" % [a.area_id, l.id])
		assert_eq(a.region_id, l.region_id, "%s is in %s's region" % [a.area_id, l.id])
	# Every built place's areas exist; a closed place has none yet, and a flag that opens it.
	for l in atlas.locations:
		for aid in l.area_ids:
			assert_not_null(_area(String(aid)), "%s's area %s ships" % [l.id, aid])
		if not l.is_built():
			assert_true(l.open_flag.begins_with("world."), "%s opens with a world.* flag" % l.id)
	# The built heartland is one connected road, Oakvale to Woodland Town.
	var reach: Array[String] = atlas.reachable_built("oakvale")
	for id in ["mossway", "river_crossing", "crownhaven", "sparse_forest", "woodland_town"]:
		assert_true(reach.has(id), "%s is reachable from Oakvale over built roads" % id)
	assert_eq(atlas.neighbours("beach_village", "sea").size(), 3, "Beach Village is the port for three isles")


func test_world_map_positions_follow_the_owners_map() -> void:
	var atlas := WorldAtlas.load_default()
	var pos := {}
	for l in atlas.locations:
		pos[String(l.id)] = l.map_pos
	# The map's landmarks, compass-checked: x grows east, y grows south. Each position sits on the
	# place's ART (the houses / keep / cave the painting draws just above its label), so the world
	# map's marker covers the drawing, not the label text (docs/screenshots/world_map/map_alignment.png).
	assert_lt(pos["oakvale"].distance_to(Vector2(0.426, 0.63)), 0.025, "Oakvale (the Starting Village)")
	assert_lt(pos["river_crossing"].distance_to(Vector2(0.544, 0.655)), 0.025, "River Crossing")
	assert_lt(pos["crownhaven"].distance_to(Vector2(0.498, 0.41)), 0.025, "Crownhaven (the Central Kingdom)")
	assert_lt(pos["woodland_town"].distance_to(Vector2(0.301, 0.384)), 0.025, "Woodland Town")
	assert_lt(pos["beach_village"].distance_to(Vector2(0.678, 0.685)), 0.025, "Beach Village")
	assert_lt(pos["thieves_guild"].distance_to(Vector2(0.275, 0.478)), 0.025, "the Thieves Guild's cave")
	assert_gt(pos["oakvale"].y, pos["crownhaven"].y, "Oakvale is south of the capital")
	assert_gt(pos["river_crossing"].x, pos["oakvale"].x, "River Crossing is east of Oakvale")
	assert_lt(pos["woodland_town"].x, pos["crownhaven"].x, "Woodland Town is west of the capital")
	assert_lt(pos["mountain_base"].y, pos["crownhaven"].y, "the mountains are north")
	assert_gt(pos["redrock_village"].x, pos["crownhaven"].x, "the Badlands are east")
	assert_gt(pos["beach_village"].x, pos["crownhaven"].x, "Beach Village is east...")
	assert_gt(pos["beach_village"].y, pos["crownhaven"].y, "...and south of the capital")
	assert_lt(pos["frostpeak_village"].y, pos["woodland_town"].y, "Frostpeak is north of Woodland Town")
	assert_lt(pos["deepwood_village"].x, pos["woodland_town"].x, "Deepwood is west of Woodland Town")
	assert_lt(pos["cindral"].y, pos["mountain_pass"].y, "Cindral lies beyond the Pass")


func test_the_thieves_guild_stays_a_secret() -> void:
	var atlas := WorldAtlas.load_default()
	var guild := atlas.location("thieves_guild")
	assert_true(guild.secret, "the Hidden Thieves Guild is a secret place")
	assert_false(guild.is_known(StoryFixture.past_opening(StoryState.new())), "off the map until it is found")
	var found := StoryState.new()
	found.set_flag(guild.open_flag, 1)
	assert_true(guild.is_known(found), "and on it once the way opens")
	# Woodland Town never names it: not on arrival, not on a sign.
	var wt := _area("woodland_town")
	for c in _flatten(wt.on_enter):
		if c is SayCommand:
			for b in (c as SayCommand).beats:
				assert_false(String((b as StoryBeat).text).contains("Thieves"), "the arrival scene keeps the secret")
	for e in wt.entity_list():
		if e is SignEntity:
			assert_false((e as SignEntity).text.contains("Thieves"), "%s keeps the secret" % e.id)


# --- River Crossing: a real river --------------------------------------------------------------

func test_river_crossing_is_a_real_river_with_one_stone_bridge() -> void:
	var rc := _area("river_crossing")
	assert_not_null(rc, "River Crossing ships")
	if rc == null:
		return
	assert_eq(rc.kind, OverworldAreaResource.Kind.TOWN, "a village (no wild grass)")
	var g := OverworldGrid.from_map(rc.terrain)
	var bridge: Array[Vector3i] = []
	for x in range(rc.width()):
		for y in range(7, 10):
			var c := Vector3i(x, y, 0)
			var tid: String = String(g.tile_id_at(c))
			if tid == "flagstones":
				bridge.append(c)
			elif tid != "wooden_planks":
				assert_eq(tid, "deep_water", "the river runs edge to edge at %s" % c)
	assert_eq(bridge.size(), 6, "a two-wide stone bridge over three rows of water")
	# Without the bridge there is no way over: the south bank cannot reach the north bank.
	var s := StoryFixture.past_opening(StoryState.new())
	var full := OverworldGrid.build(rc, s)
	assert_false(TapPathfinder.find_path(full, Vector3i(1, 14, 0), Vector3i(11, 1, 0)).is_empty(), "over the bridge")
	for c in bridge:
		full.set_blocker(c, "test")
	assert_true(TapPathfinder.find_path(full, Vector3i(1, 14, 0), Vector3i(11, 1, 0)).is_empty(),
		"and no way round it")
	for id in ["hobb", "nan", "joss"]:
		assert_true(rc.entity(id) is NpcEntity, "%s lives at River Crossing" % id)
	var kinds := _prop_kinds(rc)
	assert_gte(int(kinds.get("house", 0)), 3, "a toll-house and cottages")
	assert_not_null(rc.entity("wayshrine"), "a Wayshrine")
	# Hobb tells the same story twice (Marra warns you in Oakvale).
	var older: int = 0
	for c in _flatten((rc.entity("hobb") as NpcEntity).on_interact):
		if c is SayCommand:
			for b in (c as SayCommand).beats:
				if String((b as StoryBeat).text).to_lower().contains("older than the kingdom"):
					older += 1
	assert_eq(older, 2, "the bridge is older than the kingdom -- he says so twice")


func test_the_mossbrook_cannot_be_walked_round() -> void:
	var moss := _area("mossway")
	var g := OverworldGrid.build(moss, StoryFixture.past_opening(StoryState.new()))
	assert_false(TapPathfinder.find_path(g, Vector3i(1, 6, 0), Vector3i(32, 6, 0)).is_empty(), "the road runs through")
	g.set_blocker(Vector3i(21, 6, 0), "test")
	assert_true(TapPathfinder.find_path(g, Vector3i(1, 6, 0), Vector3i(32, 6, 0)).is_empty(),
		"the plank bridge (the ambush) is the only way over the brook")


# --- Three towns that look like three different places -------------------------------------------

func _tile_counts(a: OverworldAreaResource) -> Dictionary:
	var out: Dictionary = {}
	for e in a.terrain.tile_layout:
		var tid: String = String(e.get("tile_id", ""))
		out[tid] = int(out.get(tid, 0)) + 1
	return out


func test_the_three_towns_are_built_differently() -> void:
	var oak := _area("oakvale")
	var ch := _area("crownhaven")
	var wt := _area("woodland_town")
	var oak_tiles := _tile_counts(oak)
	# Oakvale: an open farming village -- no paving, a dirt green with a well, one roof colour, the sea.
	assert_eq(int(oak_tiles.get("flagstones", 0)), 0, "Oakvale is unpaved")
	assert_gt(int(oak_tiles.get("deep_water", 0)), 2 * oak.width(), "Oakvale looks out on the sea to the south")
	var well := oak.entity("well") as PropEntity
	assert_not_null(well, "a well")
	if well != null:
		assert_true(Rect2i(7, 6, 7, 7).has_point(Vector2i(well.cell.x, well.cell.y)), "on the village green")
	var roofs: Array[Color] = []
	for e in oak.entity_list():
		if e is PropEntity and (e as PropEntity).prop == "house" and String(e.id) != "house_barn":
			roofs.append((e as PropEntity).tint)
	for r in roofs:
		assert_almost_eq(r.h, roofs[0].h, 0.03, "every Oakvale roof is the same terracotta")
		assert_gt(r.r, r.b + 0.3, "warm red-orange, not slate")
	# Crownhaven: a walled river city, paved, slate roofs.
	var ch_tiles := _tile_counts(ch)
	assert_gt(int(ch_tiles.get("flagstones", 0)), 120, "Crownhaven is paved")
	assert_gt(int(ch_tiles.get("deep_water", 0)), 2 * ch.width(), "Crownhaven stands on its river")
	for e in ch.entity_list():
		if e is PropEntity and String(e.id).begins_with("house_"):
			assert_gt((e as PropEntity).tint.b, (e as PropEntity).tint.r, "%s: a slate roof" % e.id)
	# Woodland Town: a forest clearing -- cabins, no paving, no wild grass in town.
	var wt_tiles := _tile_counts(wt)
	assert_eq(int(wt_tiles.get("flagstones", 0)), 0, "Woodland Town is unpaved")
	assert_eq(int(wt_tiles.get("tall_grass", 0)), 0, "no tall grass in a town with no encounter table")
	assert_eq(int(_prop_kinds(wt).get("house", 0)), 0, "log cabins, not houses")


# --- Everyone can be reached, whatever the story has done -------------------------------------

## The cells walkable from any entry of [param a] under [param s].
func _reach(a: OverworldAreaResource, s: StoryState) -> Dictionary:
	var g := OverworldGrid.build(a, s)
	var reach: Dictionary = {}
	var queue: Array[Vector3i] = []
	for eid in a.entry_ids():
		var c: Vector3i = a.entry(eid)["cell"]
		if g.is_walkable(c) and not reach.has(c):
			reach[c] = true
			queue.append(c)
	var head: int = 0
	while head < queue.size():
		var c: Vector3i = queue[head]
		head += 1
		for n in g.walkable_neighbours(c):
			if not reach.has(n):
				reach[n] = true
				queue.append(n)
	return reach


func test_everyone_can_be_reached_at_every_stage_of_the_story() -> void:
	# The fullest stage: past the opening, the rival met and moved to the arena, the cup won (the
	# champion out), the ambush cleared, the Sergeant's detail joined. (The forge's barrels and the
	# arena's rival once sealed Smith Garrick and Champion Isolde into Crownhaven's south-east corner.)
	var everything := StoryFixture.past_opening(StoryState.new())
	for f in ["act1.met_rowan", "rival.met", "rival.duel1", "arena.crown_cup.champion", "mossway.ambush.sprung",
			"mossway.ambush.cleared", "woodland.arrived", "river_crossing.arrived"]:
		everything.set_flag(f, 1)
	var raided := StoryFixture.sent_off(StoryState.new())
	raided.set_flag("opening.attack", 1)
	var stages := {"new": StoryState.new(), "sent_off": StoryFixture.sent_off(StoryState.new()), "raided": raided,
		"past_opening": StoryFixture.past_opening(StoryState.new()), "everything": everything}
	for a in _areas():
		for stage in stages:
			var s: StoryState = stages[stage]
			var reach := _reach(a, s)
			for e in a.present_entities(s):
				if not e.is_interactable() or not e.has_actor():
					continue
				var ok := false
				for c in e.cells():
					for d in OverworldGrid.DIRS:
						if reach.has(Vector3i(c.x + d.x, c.y + d.y, 0)):
							ok = true
				assert_true(ok, "%s/%s can be reached and talked to (%s)" % [a.area_id, e.id, stage])
	# The bug itself, by name: Garrick, Isolde and the rival by the arena.
	var ch := _area("crownhaven")
	var g := OverworldGrid.build(ch, everything)
	for id in ["garrick", "isolde", "lark_arena", "arena_master"]:
		assert_false(TapPathfinder.path_to_adjacent(g, ch.entry("south_gate")["cell"], ch.entity(id).cell).is_empty(),
			"%s is reachable from the south gate with every flag set" % id)
