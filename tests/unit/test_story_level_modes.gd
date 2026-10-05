extends GutTest

## Battle LEVEL MODES and the shipped content's levels (docs/design/PROGRESSION.md §3):
##   * FIXED (the default) keeps the authored level whatever the party;
##   * SCALED (chiefs, DECISIONS.md #80) follows the party's top level inside its band;
##   * a LEGEND (#81) is FIXED above its band and never scales;
##   * the shipped areas carry their region's band and every authored story battle has a level.


func _state(top: int) -> StoryState:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, top)
	s.add_member("petalfang", "", 6, maxi(1, top - 3))
	return s


func _spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	var team: Array[Dictionary] = [{"character_id": "petalfang", "strength": 1.0, "level": 9},
		{"character_id": "blightcap", "strength": 1.0}]
	spec.opponent_team = team
	spec.enemy_level = 9
	return spec


func _scaled_request(spec: BattleSpec, state: StoryState) -> BattleRequest:
	var r: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT, "t")
	spec.apply_scaling(r, state)
	return r


func test_fixed_keeps_the_authored_level() -> void:
	var spec := _spec()
	var r := _scaled_request(spec, _state(30))
	assert_eq(r.foe_level(0), 9, "a FIXED battle ignores the party's level")
	assert_eq(r.enemy_level, 9, "the authored enemy level stands")


func test_scaled_follows_the_party_inside_its_band() -> void:
	var spec := _spec()
	BattleSpec.make_chief(spec, Vector2i(8, 15), 1)
	assert_eq(spec.level_mode, BattleSpec.LevelMode.SCALED, "a chief is SCALED")
	assert_true(spec.boss_battle, "and a boss battle for XP")
	assert_eq(_scaled_request(spec, _state(11)).foe_level(0), 12, "party top 11 + offset 1")
	assert_eq(_scaled_request(spec, _state(11)).foe_level(1), 12, "every foe of a scaled battle")
	assert_eq(_scaled_request(spec, _state(3)).foe_level(0), 8, "never below the band")
	assert_eq(_scaled_request(spec, _state(40)).foe_level(0), 15, "never above the band")


func test_legend_is_above_its_band_and_never_scales() -> void:
	var spec := _spec()
	BattleSpec.make_legend(spec, Vector2i(8, 15))
	var expected: int = 15 + ProgressionRules.current().legend_over_band
	assert_eq(spec.level_mode, BattleSpec.LevelMode.FIXED, "a legend is FIXED")
	assert_eq(_scaled_request(spec, _state(5)).foe_level(0), expected, "band max + legend_over_band")
	assert_eq(_scaled_request(spec, _state(40)).foe_level(0), expected, "the party's level never moves it")
	assert_true(spec.boss_battle, "a legend is a boss battle for XP")


func test_scaling_still_composes_with_rematch_strength() -> void:
	var spec := _spec()
	BattleSpec.make_chief(spec, Vector2i(8, 15))
	spec.scale_flag = "rematch.n"
	spec.scale_step = 0.1
	spec.scale_max_steps = 3
	var s := _state(10)
	s.set_flag("rematch.n", 2)
	var r := _scaled_request(spec, s)
	assert_eq(r.foe_level(0), 10, "the scaled level")
	assert_almost_eq(float(r.opponent["team"][0]["strength"]), 1.2, 0.001, "and the rematch strength on top")


func test_validate_flags_bad_levels() -> void:
	var spec := _spec()
	spec.enemy_level = 999
	var issues: Array[String] = []
	spec.validate(issues)
	assert_true(issues.any(func(i: String) -> bool: return i.contains("level cap")), "a level above the cap is flagged")
	var s2 := _spec()
	s2.level_mode = BattleSpec.LevelMode.SCALED
	s2.scale_min = 20
	s2.scale_max = 10
	var issues2: Array[String] = []
	s2.validate(issues2)
	assert_true(issues2.any(func(i: String) -> bool: return i.contains("scale_min")), "an inverted scaled band is flagged")


# --- Shipped content -----------------------------------------------------------------

func test_shipped_areas_carry_their_region_band() -> void:
	for pair in [["oakvale", Vector2i(2, 8)], ["mossway", Vector2i(2, 8)], ["river_crossing", Vector2i(2, 8)],
			["crownhaven", Vector2i(2, 8)], ["sparse_forest", Vector2i(8, 15)], ["woodland_town", Vector2i(8, 15)]]:
		var a: OverworldAreaResource = OverworldAreaResource.load_by_id(String(pair[0]))
		assert_not_null(a, "%s exists" % pair[0])
		if a != null:
			assert_eq(a.level_band, pair[1], "%s's level band" % pair[0])


func test_every_shipped_wild_zone_rolls_levels() -> void:
	for aid in ["mossway", "sparse_forest"]:
		var a: OverworldAreaResource = OverworldAreaResource.load_by_id(aid)
		for z in a.zones():
			var band: Vector2i = z.band_in(a)
			assert_ne(band, Vector2i.ZERO, "%s's grass has a level band" % aid)
			assert_between(band.x, a.level_band.x, a.level_band.y, "%s's zone band sits in the area's" % aid)


func test_every_shipped_trainer_battle_has_a_level() -> void:
	var moss: OverworldAreaResource = OverworldAreaResource.load_by_id("mossway")
	var bram := moss.entity("bram") as TrainerEntity
	assert_eq(bram.battle.enemy_level, 5, "Bram fights at level 5")
	var fenna := moss.entity("fenna") as TrainerEntity
	assert_gt(fenna.battle.resolved_enemy_level(null), bram.battle.enemy_level, "Fenna (later on the road) is stronger")
	var cup := load(TournamentResource.path_for("crown_cup")) as TournamentResource
	if cup == null:
		pending("the Crown Cup resource is not shipped under that id")
		return
	var prev: int = 0
	for spec in cup.rounds:
		var lv: int = spec.resolved_enemy_level(null)
		assert_gt(lv, prev, "the arena ladder rises round by round")
		prev = lv
