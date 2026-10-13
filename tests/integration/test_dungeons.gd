extends GutTest

## THE DUNGEONS -- the areas before the big battles (DECISIONS.md #101-#106), against the SHIPPED content:
##   * the ICE dungeon (the Frozen Cave): each slide floor is SOLVED with the overworld's own slide rule
##     (OverworldGrid.slide_path) -- the hole down is reachable, it takes a real number of slides, and
##     wrong slides end in cracks that drop you back to the floor's start; then the legend's chamber;
##   * the SEA dungeon (the Island of Tides): down through whirlpools and holes -- some holes lead back UP
##     -- to the depths and the legend, walked across areas (riding the water);
##   * the UNDERWORLD (the Old Crypt): two mini bosses (duels) bar the way, then the boss;
##   * the VOLCANO: a straightforward climb (its legend an encounter battle -- test_postgame.gd);
##   * the HIDDEN DEPTHS: four areas of cave and ruins, strong encounters, and the boss whose awakening
##     begins the post-game (#98).

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const POSTGAME := "postgame.hidden_depths_awakened"
const ICE_FLOORS: Array[String] = ["glacier_cave", "glacier_cave_2"]


func _area(id: String) -> OverworldAreaResource:
	return load(StoryController.area_path(id)) as OverworldAreaResource


func _past(flags: Array = []) -> StoryState:
	var s := StoryFixture.past_opening(StoryState.new())
	for f in flags:
		s.set_flag(String(f), 1)
	return s


func _warp_on(a: OverworldAreaResource, s: StoryState, c: Vector3i) -> WarpEntity:
	for e in a.present_entities(s):
		if e is WarpEntity and e.occupies(c) and (e as WarpEntity).is_open(s):
			return e as WarpEntity
	return null


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


func _spec_of(e: OverworldEntity) -> BattleSpec:
	for c in _flatten(e.on_interact):
		if c is StartBattleCommand:
			return (c as StartBattleCommand).spec
	return null


# --- The ice (#102) -------------------------------------------------------------------------------

## Solve an ice floor: BFS over the hero's stops, each move a slide (OverworldGrid.slide_path). Returns
## {moves: slides to the hole down (-1 = unreachable), cracks: stops that fall through a crack}.
func _solve_ice(id: String, s: StoryState) -> Dictionary:
	var a := _area(id)
	var g := OverworldGrid.build(a, s)
	var stop_at := func(c: Vector3i) -> bool: return _warp_on(a, s, c) != null
	var start: Vector3i = a.entry(a.entry_ids()[0])["cell"]
	var seen: Dictionary = {start: 0}
	var queue: Array[Vector3i] = [start]
	var moves: int = -1
	var cracks: int = 0
	while not queue.is_empty():
		var c: Vector3i = queue.pop_front()
		var w := _warp_on(a, s, c)
		if w != null:
			if String(w.id) == "hole_down":
				if moves < 0:
					moves = int(seen[c])
			elif String(w.id).begins_with("crack_"):
				cracks += 1
			continue
		for d in OverworldGrid.DIRS:
			var path: Array[Vector3i] = g.slide_path(c, d, a.slide_tiles, stop_at)
			if path.is_empty():
				continue
			var stop: Vector3i = path.back()
			if not seen.has(stop):
				seen[stop] = int(seen[c]) + 1
				queue.append(stop)
	return {"moves": moves, "cracks": cracks}


func test_the_ice_floors_are_slide_puzzles_with_a_solution() -> void:
	var s := _past([POSTGAME])
	for id in ICE_FLOORS:
		var a := _area(id)
		assert_true(a.slide_tiles.has(&"ice_sheet"), "%s: the ice slides" % id)
		var r: Dictionary = _solve_ice(id, s)
		assert_gt(int(r["moves"]), 0, "%s: the hole down can be reached" % id)
		assert_gte(int(r["moves"]), 8, "%s: a real puzzle (%d slides)" % [id, int(r["moves"])])
		assert_gte(int(r["cracks"]), 2, "%s: wrong slides end in cracks" % id)
		for e in a.entity_list():
			if e is WarpEntity and String(e.id).begins_with("crack_"):
				assert_eq(String((e as WarpEntity).target_area), id, "%s/%s: a crack resets you to this floor's start" % [id, e.id])
				assert_eq(String((e as WarpEntity).target_entry), String(a.entry_ids()[0]), "at its start")
	assert_eq(String((_area("glacier_cave").entity("hole_down") as WarpEntity).target_area), "glacier_cave_2", "down a level")
	assert_eq(String((_area("glacier_cave_2").entity("hole_down") as WarpEntity).target_area), "glacier_cave_3", "and down again")
	assert_eq(String((_area("glacier_cave_2").entity("ladder_up") as WarpEntity).target_area), "glacier_cave", "a ladder back up")
	assert_true(_area("glacier_cave_3").slide_tiles.is_empty(), "the legend's chamber does not slide")
	assert_true(_area("frostpeak_village").slide_tiles.is_empty(), "nor does Frostpeak's pond")


func test_the_slide_rule() -> void:
	var m := MapResource.new()
	m.width = 6
	m.height = 1
	for x in range(6):
		m.set_tile_at_position(Vector2i(x, 0), "NORMAL", "", "ice_sheet" if x >= 1 and x <= 3 else "frozen_tundra")
	var g := OverworldGrid.from_map(m)
	var ice: Array[StringName] = [&"ice_sheet"]
	assert_eq(g.slide_path(Vector3i(0, 0, 0), Vector2i(1, 0), ice),
		[Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(3, 0, 0), Vector3i(4, 0, 0)] as Array[Vector3i],
		"across the ice, stopping on the first ground")
	g.set_blocker(Vector3i(3, 0, 0), "rock")
	assert_eq(g.slide_path(Vector3i(0, 0, 0), Vector2i(1, 0), ice),
		[Vector3i(1, 0, 0), Vector3i(2, 0, 0)] as Array[Vector3i], "a rock stops you before it")
	assert_eq(g.slide_path(Vector3i(0, 0, 0), Vector2i(-1, 0), ice), [] as Array[Vector3i], "a wall: no move")
	g.clear_blocker(Vector3i(3, 0, 0))
	var hole := func(c: Vector3i) -> bool: return c == Vector3i(2, 0, 0)
	assert_eq(g.slide_path(Vector3i(0, 0, 0), Vector2i(1, 0), ice, hole),
		[Vector3i(1, 0, 0), Vector3i(2, 0, 0)] as Array[Vector3i], "a hole stops the slide (you fall)")


# --- Across areas: the sea dungeon, the Hidden Depths -----------------------------------------------

## Every (area, cell) the hero can reach from [param area_id] / [param entry], walking -- and riding the
## water when [param ride] -- through every open, present warp. {area_id: {cell: true}}.
func _walk_world(area_id: String, entry: String, s: StoryState, ride: bool, limit_areas: Array) -> Dictionary:
	var out: Dictionary = {}
	var grids: Dictionary = {}
	var start_area := _area(area_id)
	var queue: Array = [[area_id, start_area.entry(entry)["cell"]]]
	while not queue.is_empty():
		var it: Array = queue.pop_front()
		var aid: String = it[0]
		var c: Vector3i = it[1]
		if not out.has(aid):
			out[aid] = {}
		if (out[aid] as Dictionary).has(c):
			continue
		(out[aid] as Dictionary)[c] = true
		var a := _area(aid)
		if not grids.has(aid):
			var g := OverworldGrid.build(a, s)
			if ride:
				var tiles: Array[StringName] = [&"deep_water"]
				g.riding_tiles = tiles
			grids[aid] = g
		var w := _warp_on(a, s, c)
		if w != null:
			var to: String = String(w.target_area)
			if limit_areas.has(to):
				queue.append([to, _area(to).entry(String(w.target_entry))["cell"]])
			continue
		for n in (grids[aid] as OverworldGrid).walkable_neighbours(c):
			queue.append([aid, n])
	return out


func _next_to(cells: Dictionary, c: Vector3i) -> bool:
	for d in OverworldGrid.DIRS:
		if cells.has(c + Vector3i(d.x, d.y, 0)):
			return true
	return false


func test_the_sea_dungeon_goes_down_through_whirlpools_and_holes() -> void:
	var tides: Array = ["island_of_tides", "tides_cave_1", "tides_pocket", "tides_cave_2", "tides_cave_3", "tides_depths"]
	var s := _past()
	for v in ["stormreef_waters", "stormreef_waters_erupted"]:
		var w := _area(v).entity("tides_whirlpool") as WarpEntity
		assert_not_null(w, "%s: a whirlpool off Stormreef Isle" % v)
		assert_eq(String(w.target_area), "island_of_tides", "it carries you to the Island of Tides (#44)")
	var world: Dictionary = _walk_world("island_of_tides", "whirlpool", s, true, tides)
	for id in tides:
		assert_true(world.has(id), "%s is reached" % id)
	var depths := _area("tides_depths")
	assert_true(_next_to(world.get("tides_depths", {}), depths.entity("tides_legend").cell), "down to the legend in the depths")
	# Down by whirlpools in the cave lakes, and some holes lead back UP (backtracking).
	var whirls: int = 0
	var up: int = 0
	var order := {"island_of_tides": 0, "tides_cave_1": 1, "tides_pocket": 2, "tides_cave_2": 2, "tides_cave_3": 3, "tides_depths": 4}
	for id in tides:
		var g := OverworldGrid.from_map(_area(id).terrain)
		for e in _area(id).entity_list():
			if not (e is WarpEntity) or not order.has(String((e as WarpEntity).target_area)):
				continue
			var w := e as WarpEntity
			if String(w.id).begins_with("whirl"):
				whirls += 1
				assert_eq(g.tile_id_at(w.cells()[0]), &"deep_water", "%s/%s: a whirlpool is on the water" % [id, w.id])
			if int(order[String(w.target_area)]) < int(order.get(id, 0)) and String(w.id).begins_with("hole"):
				up += 1
	assert_gte(whirls, 3, "whirlpools take you down")
	assert_gte(up, 2, "some holes lead back up")
	var pocket := _walk_world("tides_cave_1", "south", s, true, ["tides_cave_1", "tides_pocket"])
	assert_true(pocket.has("tides_pocket"), "cave 1's west hole drops into a hollow...")
	var spec := (load(StoryController.area_path("tides_depths")) as OverworldAreaResource).entity("tides_legend")
	assert_eq(_spec_of(spec).kind, BattleSpec.Kind.TACTICAL, "the sea legend: a tactical battle")


func test_the_hidden_depths_are_a_long_way_through_ruins_to_the_awakening() -> void:
	var depths: Array = ["hidden_depths", "hidden_depths_2", "hidden_depths_3", "hidden_depths_heart"]
	var s := _past()
	var world: Dictionary = _walk_world("hidden_depths", "south", s, false, depths)
	for id in depths:
		assert_true(world.has(id), "%s is on the way" % id)
	var strong: int = 0
	for id in depths:
		var a := _area(id)
		assert_eq(a.level_band, Vector2i(25, 35), "%s: in the Northern Mountains band" % id)
		strong += a.zones().size()
	assert_gte(strong, 3, "many strong encounters along the way")
	var boss := _area("hidden_depths_heart").entity("depths_boss")
	assert_true(_next_to(world["hidden_depths_heart"], boss.cell), "the boss at the heart")
	var spec := _spec_of(boss)
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "a tactical battle")
	assert_true(spec.reward_flags.has(POSTGAME), "beating it AWAKENS it: the post-game begins (#98)")
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "Try Again on a loss")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "it validates")


func test_the_underworld_has_mini_bosses_barring_the_way() -> void:
	var crypt: Array = ["old_crypt", "old_crypt_depths", "old_crypt_end"]
	var s := _past(["story.final_boss_beaten"])
	var before: Dictionary = _walk_world("old_crypt", "stairs", s, false, crypt)
	assert_false(before.has("old_crypt_depths"), "the first mini boss bars the way deeper")
	for id in [["old_crypt", "crypt_warden_1"], ["old_crypt_depths", "crypt_warden_2"]]:
		var mb := _area(id[0]).entity(id[1])
		assert_not_null(mb, "%s waits in %s" % [id[1], id[0]])
		var spec := _spec_of(mb)
		assert_eq(spec.kind, BattleSpec.Kind.DUEL, "%s: a duel" % id[1])
		assert_true(spec.boss_battle, "a mini boss")
		assert_gt(float(spec.opponent_team[0]["strength"]), 1.0, "tougher than its kind")
		assert_between(spec.enemy_level, 30, 50, "post-game strength")
		var issues: Array[String] = []
		spec.validate(issues)
		assert_eq(issues, [] as Array[String], "%s validates" % id[1])
		for f in spec.reward_flags:
			s.set_flag(f, 1)
	var after: Dictionary = _walk_world("old_crypt", "stairs", s, false, crypt)
	assert_true(after.has("old_crypt_end"), "with both beaten, the way to the boss is open")
	assert_true(_next_to(after["old_crypt_end"], _area("old_crypt_end").entity("crypt_boss").cell), "the boss")


func test_the_volcano_is_a_straightforward_climb() -> void:
	var s := _past([POSTGAME])
	var path := _area("volcano_path")
	var warps: int = 0
	for e in path.entity_list():
		if e is WarpEntity:
			warps += 1
	assert_eq(warps, 2, "one way up, one way down -- no maze")
	var world: Dictionary = _walk_world("volcano_path", "south", s, false, ["volcano_path", "volcano_crater"])
	assert_true(world.has("volcano_crater"), "up to the crater")
	assert_gt(path.zones().size(), 0, "wild creatures on the slopes")
