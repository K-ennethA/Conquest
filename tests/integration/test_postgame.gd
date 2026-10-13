extends GutTest

## THE POST-GAME against the SHIPPED content (DECISIONS.md #98-#100):
##   * it begins when the Hidden Depths boss awakens (postgame.hidden_depths_awakened -- a knob until the
##     Hidden Depths is built): a volcano erupts off Stormreef Isle -- a NEW ISLAND in the sea south of
##     Beach Village, reached riding the sea move, a new LEGEND on its crater;
##   * a BLIZZARD covers the Snowy Peaks (Frostpeak and the high trail north of it), and the ice that
##     sealed a cave on the trail is gone: a new LEGEND waits inside;
##   * after the FINAL BOSS (story.final_boss_beaten -- a knob until the final battle is built), a grave
##     in the graveyard on Crownhaven's outskirts is open: down to the Old Crypt and a BOSS at its end.

const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const POSTGAME := "postgame.hidden_depths_awakened"
const FINAL := "story.final_boss_beaten"


class SeqHost extends StoryScriptHost:
	var picks: Array[int] = [0]
	var asked: int = 0

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		var p: int = picks[mini(asked, picks.size() - 1)]
		asked += 1
		return p


class FakeSession extends RefCounted:
	var requests: Array = []
	var state: StoryState = null

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		if state != null:
			for f in request.rewards.get("flags", []):
				state.set_flag(f, 1)
		var r := BattleResult.new()
		r.outcome = BattleResult.OUTCOME_VICTORY
		return r


func _area(id: String) -> OverworldAreaResource:
	return load(StoryController.area_path(id)) as OverworldAreaResource


func _past(flags: Array = []) -> StoryState:
	var s := StoryFixture.past_opening(StoryState.new())
	for f in flags:
		s.set_flag(String(f), 1)
	return s


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


func _tactical_in(commands: Array) -> BattleSpec:
	for c in _flatten(commands):
		if c is StartBattleCommand and not (c is StartDuelCommand):
			return (c as StartBattleCommand).spec
	return null


func _present(area_id: String, id: String, s: StoryState) -> bool:
	var e := _area(area_id).entity(id)
	return e != null and e.is_present(s)


func _reach(a: OverworldAreaResource, s: StoryState, from: String, riding: bool) -> Dictionary:
	var g := OverworldGrid.build(a, s)
	if riding:
		var tiles: Array[StringName] = [&"deep_water"]
		g.riding_tiles = tiles
	var start: Vector3i = a.entry(from)["cell"]
	var seen: Dictionary = {start: true}
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_front()
		for n in g.walkable_neighbours(c):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _next_to(reach: Dictionary, c: Vector3i) -> bool:
	for d in OverworldGrid.DIRS:
		if reach.has(c + Vector3i(d.x, d.y, 0)):
			return true
	return false


## A legend's battle: TACTICAL, FIXED above the post-game band, Try Again, no base -- then the bond.
func _assert_legend(area_id: String, id: String, s: StoryState, bonded_flag: String) -> void:
	var e := _area(area_id).entity(id)
	assert_not_null(e, "%s waits in %s" % [id, area_id])
	if e == null:
		return
	var spec := _tactical_in(e.on_interact)
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "%s: a TACTICAL legend battle (#74)" % id)
	assert_eq(spec.level_mode, BattleSpec.LevelMode.FIXED, "%s: never scaled (#81)" % id)
	assert_eq(spec.enemy_level, Progression.legend_level(Vector2i(30, 40)), "%s: above the post-game band" % id)
	assert_eq(spec.defeat_policy, BattleSpec.DefeatPolicy.RETRY, "%s: Try Again on a loss" % id)
	assert_true(spec.protect.is_empty(), "%s: nothing to protect" % id)
	var m := load(spec.map_path) as MapResource
	assert_eq(m.victory_conditions, ["Eliminate All Enemies"] as Array[String], "%s: eliminate all enemies" % id)
	var session := FakeSession.new()
	session.state = s
	await StoryScriptRunner.run_list(e.on_interact, ScriptContext.new(s, SeqHost.new(), session, area_id))
	assert_eq(session.requests.size(), 1, "%s: the battle was fought" % id)
	assert_true(s.has_flag(bonded_flag), "%s: bonded (#75)" % id)
	assert_true(s.legends.has(String(e.visual_character)), "%s: in the legend list, not the party" % id)
	assert_false(e.is_present(s), "%s: gone once bonded" % id)


func test_the_post_game_places_are_on_the_map() -> void:
	var atlas := WorldAtlas.load_default()
	for id in ["stormreef_waters", "stormreef_waters_erupted", "volcano_path", "volcano_crater", "snowy_peaks", "glacier_cave",
			"glacier_cave_2", "glacier_cave_3", "crownhaven_graveyard", "old_crypt", "old_crypt_depths", "old_crypt_end"]:
		var a := _area(id)
		assert_not_null(a, "%s loads" % id)
		if a == null:
			continue
		assert_eq(a.validate(), [] as Array[String], "%s validates" % id)
		assert_true(atlas.location_for_area(id).is_built(), "%s's place is built" % id)
	for id in ["glacier_cave", "old_crypt"]:
		assert_eq(_area(id).level_band, Vector2i(30, 40), "%s is in the post-game band" % id)
	assert_false(atlas.location("frozen_cave").is_known(_past()), "the frozen cave stays off the map...")
	assert_true(atlas.location("frozen_cave").is_known(_past([POSTGAME])), "...until the post-game")
	assert_false(atlas.location("old_crypt").is_known(_past([POSTGAME])), "the crypt stays off the map...")
	assert_true(atlas.location("old_crypt").is_known(_past([FINAL])), "...until the final boss is beaten")
	var units: Dictionary = {}
	for u in ["vineweave", "petalfang", "eldroot", "monster", "gem_knight", "eclipse_wolf"]:
		units[u] = true
	assert_eq(units.size(), 6, "every legend / mythical is a distinct unit (a bond is one of each)")


# --- The volcano off Stormreef Isle (#98) -------------------------------------------------------

func test_the_sea_route_leads_to_calm_water_then_to_the_new_island() -> void:
	var before := _past()
	var after := _past([POSTGAME])
	assert_true(_present("beach_village", "sea_route", before) and not _present("beach_village", "sea_route_erupted", before),
		"before: the calm sea")
	assert_true(_present("beach_village", "sea_route_erupted", after) and not _present("beach_village", "sea_route", after),
		"after the Hidden Depths: the erupted sea")
	var calm := OverworldGrid.from_map(_area("stormreef_waters").terrain)
	var erupted := OverworldGrid.from_map(_area("stormreef_waters_erupted").terrain)
	var land_calm: int = 0
	var land_erupted: int = 0
	for y in range(4, 14):
		for x in range(12, 23):
			var c := Vector3i(x, y, 0)
			if calm.is_terrain_passable(c):
				land_calm += 1
			if erupted.is_terrain_passable(c):
				land_erupted += 1
	assert_eq(land_calm, 0, "no island before the eruption")
	assert_gt(land_erupted, 30, "a new island after it")
	assert_eq(String(erupted.tile_id_at(Vector3i(17, 8, 0))), "molten_lava", "lava in its crater")


func test_the_island_is_reached_by_sea_and_its_volcano_climbed_to_an_encounter_battle() -> void:
	var s := _past([POSTGAME])
	var a := _area("stormreef_waters_erupted")
	var door := a.entity("volcano_path") as WarpEntity
	assert_eq(String(door.target_area), "volcano_path", "a way up the volcano on the new island")
	assert_false(_reach(a, s, "shore", false).has(door.cells()[0]), "not on foot from Stormreef's shore")
	assert_true(_reach(a, s, "north", true).has(door.cells()[0]), "riding the sea to the island, you can climb it")
	var path := _area("volcano_path")
	assert_true(_reach(path, s, "south", false).has((path.entity("north_exit") as WarpEntity).cells()[0]),
		"a straightforward climb to the crater (#105)")
	var crater := _area("volcano_crater")
	var legend := crater.entity("volcano_legend")
	assert_true(_next_to(_reach(crater, s, "south", false), legend.cell), "the legend on the crater's rim")
	var spec: BattleSpec = null
	for c in _flatten(legend.on_interact):
		if c is StartBattleCommand:
			spec = (c as StartBattleCommand).spec
	assert_eq(spec.kind, BattleSpec.Kind.DUEL, "an ENCOUNTER battle -- no tactical (#105)")
	assert_eq(spec.level_mode, BattleSpec.LevelMode.FIXED, "never scaled (#81)")
	assert_eq(spec.enemy_level, Progression.legend_level(Vector2i(30, 40)), "above the post-game band")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "a duel-eligible legend")
	var session := FakeSession.new()
	session.state = s
	await StoryScriptRunner.run_list(legend.on_interact, ScriptContext.new(s, SeqHost.new(), session, "volcano_crater"))
	assert_true(s.has_flag("legend.volcano.bonded"), "bonded (#75)")
	assert_false(legend.is_present(s), "gone once bonded")


# --- The blizzard and the frozen cave (#99) --------------------------------------------------------

func test_a_blizzard_covers_the_snowy_peaks_in_the_post_game() -> void:
	var blizzard := Weather.get_weather(&"blizzard")
	assert_eq(blizzard.id, &"blizzard", "the Blizzard weather ships")
	assert_eq(blizzard.fx_kind, &"snow", "with its own snow")
	for id in ["frostpeak_village", "snowy_peaks"]:
		assert_eq(_area(id).weather_id_for(_past()), "clear", "%s: clear before" % id)
		assert_eq(_area(id).weather_id_for(_past([POSTGAME])), "blizzard", "%s: a blizzard in the post-game" % id)
	assert_eq(_area("frostpeak_dream").weather_id_for(_past([POSTGAME])), "clear", "not in the dream")
	assert_eq(_area("beach_village").weather_id_for(_past([POSTGAME])), "clear", "only the peaks")


func test_the_high_trail_and_its_sealed_cave() -> void:
	var fp := _area("frostpeak_village")
	var north := fp.entity("north_exit") as WarpEntity
	assert_eq(String(north.target_area), "snowy_peaks", "Frostpeak's north trail climbs to the Snowy Peaks")
	assert_true(north.is_open(_past()), "open (no gate)")
	var sp := _area("snowy_peaks")
	var before := _past()
	var after := _past([POSTGAME])
	var seal := sp.entity("ice_seal") as PropEntity
	assert_true(seal.is_present(before) and seal.is_blocking() and seal.is_interactable(), "the mouth is sealed (and says so)")
	assert_false(sp.entity("cave_exit").is_present(before), "no way in")
	assert_false(OverworldGrid.build(sp, before).is_walkable(seal.cell), "it blocks the mouth")
	assert_false(seal.is_present(after), "the storm has torn the ice away")
	assert_true(sp.entity("cave_exit").is_present(after), "the cave is open")
	assert_eq(String((sp.entity("cave_exit") as WarpEntity).target_area), "glacier_cave")
	assert_true(_next_to(_reach(sp, after, "south_trail", false), seal.cell), "the trail leads to it")


func test_the_frozen_caves_legend_can_be_bonded() -> void:
	var s := _past([POSTGAME])
	var cave := _area("glacier_cave_3")
	assert_true(_next_to(_reach(cave, s, "drop", false), cave.entity("glacier_legend").cell), "in the chamber at the bottom")
	await _assert_legend("glacier_cave_3", "glacier_legend", s, "legend.glacier.bonded")


# --- The graveyard and the crypt (#100) ------------------------------------------------------------

func test_the_graveyard_is_on_crownhavens_outskirts() -> void:
	var sf := _area("sparse_forest")
	var path := sf.entity("graveyard_exit") as WarpEntity
	assert_eq(String(path.target_area), "crownhaven_graveyard", "a path off the road outside the west gate")
	assert_true(path.is_open(_past()), "open")
	var gy := _area("crownhaven_graveyard")
	assert_true(_next_to(_reach(gy, _past(), "south_gate", false), gy.entity("gravekeeper").cell), "the gravekeeper")
	assert_true(DialogueBank.has_entry("crownhaven_graveyard", "gravekeeper"), "with his lines")
	var stones: int = 0
	for e in gy.entity_list():
		if e is SignEntity and (e as SignEntity).look == "grave":
			stones += 1
	assert_gte(stones, 15, "rows of gravestones")


func test_after_the_final_boss_a_grave_lies_open() -> void:
	var gy := _area("crownhaven_graveyard")
	var before := _past([POSTGAME])
	var after := _past([FINAL])
	assert_true(_present("crownhaven_graveyard", "old_grave", before), "the headstone in its place")
	for id in ["open_tomb", "tomb_stairs", "old_grave_moved"]:
		assert_false(_present("crownhaven_graveyard", id, before), "%s: not before the final boss" % id)
		assert_true(_present("crownhaven_graveyard", id, after), "%s: after it" % id)
	assert_false(_present("crownhaven_graveyard", "old_grave", after), "its headstone moved")
	var stairs := gy.entity("tomb_stairs") as WarpEntity
	assert_eq(String(stairs.target_area), "old_crypt", "down into the crypt")
	assert_false((gy.entity("open_tomb") as PropEntity).is_blocking(), "you step down into it")
	assert_true(_reach(gy, after, "south_gate", false).has(stairs.cells()[0]), "it can be walked onto")


func test_the_crypt_ends_in_a_boss() -> void:
	var cr := _area("old_crypt_end")
	var s := _past([FINAL])
	var boss := cr.entity("crypt_boss")
	assert_true(_next_to(_reach(cr, s, "south", false), boss.cell), "in the chamber at the crypt's end")
	var spec := _tactical_in(boss.on_interact)
	assert_eq(spec.kind, BattleSpec.Kind.TACTICAL, "a tactical boss battle")
	assert_true(spec.boss_battle, "a boss")
	assert_gt(spec.opponent_team.size(), 1, "with its minions")
	assert_between(spec.enemy_level, 30, 50, "post-game strength")
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues, [] as Array[String], "it validates")
	assert_false(cr.entity("crypt_chest").is_present(s), "no reward yet")
	var session := FakeSession.new()
	session.state = s
	await StoryScriptRunner.run_list(boss.on_interact, ScriptContext.new(s, SeqHost.new(), session, "old_crypt_end"))
	assert_true(s.has_flag("postgame.crypt_boss_beaten"), "beaten")
	assert_false(boss.is_present(s), "gone")
	assert_true(cr.entity("crypt_chest").is_present(s), "and its reward")
