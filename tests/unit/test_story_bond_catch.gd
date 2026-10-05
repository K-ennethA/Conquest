extends GutTest

## BOND (DECISIONS.md #68) and CATCH RATE (#78), docs/design/PROGRESSION.md §4-§5:
##   * every member FIELDED in a story battle earns bond XP (more on a win), a flee / the bench none;
##     bond levels cap at bond_max and show on the party page;
##   * a species' catch rate multiplies the befriend chance (story only: open-mode rolls unchanged);
##   * the content validator flags a non-boss trainer fielding a hard-to-catch species (advisory --
##     the shipped content's report is printed, not failed on).

const STORY_CTX := {"replay": false, "networked": false, "arena": false, "mode": "story"}


func _state() -> StoryState:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 5)
	s.add_member("petalfang", "", 6, 5)
	return s


func _result(outcome: String) -> BattleResult:
	var res := BattleResult.make("x", outcome)
	res.party_after = [
		{"member_id": "tree_grunt", "current_hp": 10, "wounded": false, "fought": true},
		{"member_id": "petalfang", "current_hp": StoryPartyMember.HP_FULL, "wounded": false, "fought": false},
	]
	return res


# --- Bond --------------------------------------------------------------------------------

func test_bond_goes_to_the_fielded_by_outcome() -> void:
	var r: ProgressionRules = ProgressionRules.current()
	var s := _state()
	var won: Dictionary = StoryProgression.bond_for(s, _result(BattleResult.OUTCOME_VICTORY), null, STORY_CTX)
	assert_eq(int(won.get("tree_grunt", 0)), r.bond_per_win, "a fielded member's win = bond_per_win")
	assert_false(won.has("petalfang"), "the bench earns no bond")
	var lost: Dictionary = StoryProgression.bond_for(s, _result(BattleResult.OUTCOME_DEFEAT), null, STORY_CTX)
	assert_eq(int(lost.get("tree_grunt", 0)), r.bond_per_battle, "a loss still bonds (bond_per_battle)")
	assert_true(StoryProgression.bond_for(s, _result(BattleResult.OUTCOME_FLED), null, STORY_CTX).is_empty(),
		"a flee bonds nobody")
	var replay: Dictionary = STORY_CTX.duplicate()
	replay["replay"] = true
	assert_true(StoryProgression.bond_for(s, _result(BattleResult.OUTCOME_VICTORY), null, replay).is_empty(),
		"never in a replay")


func test_spar_still_builds_bond() -> void:
	var s := _state()
	var res := _result(BattleResult.OUTCOME_VICTORY)
	res.spar = true
	assert_false(StoryProgression.bond_for(s, res, null, STORY_CTX).is_empty(), "fighting alongside in a spar counts")


func test_result_applier_banks_bond_and_it_caps() -> void:
	var r: ProgressionRules = ProgressionRules.current()
	var s := _state()
	var req := BattleRequest.new()
	req.source = BattleRequest.SOURCE_TRAINER
	var out: Dictionary = StoryResultApplier.apply(s, req, _result(BattleResult.OUTCOME_VICTORY), null, STORY_CTX)
	assert_eq(s.member("tree_grunt").bond_xp, r.bond_per_win, "the applier banks the bond XP")
	assert_true((out["bond"] as Dictionary).has("tree_grunt"), "and reports it")
	s.member("tree_grunt").add_bond(100000)
	assert_eq(s.member("tree_grunt").bond_level(), r.bond_max, "bond level caps at bond_max")


func test_party_page_shows_level_xp_and_bond() -> void:
	var s := _state()
	var m: StoryPartyMember = s.member("tree_grunt")
	m.bond_xp = 12
	assert_eq(PartyDetailPage.level_line(m), "Lv 5", "the level line")
	assert_true(PartyDetailPage.xp_line(m).contains("to next level"), "the XP line says what is left")
	assert_eq(PartyDetailPage.bond_line(m), "Bond %d / %d" % [m.bond_level(), ProgressionRules.current().bond_max],
		"the bond line")


# --- Catch rate --------------------------------------------------------------------------

func test_catch_rate_multiplies_the_join_chance() -> void:
	var rules := DuelRuleset.new()
	rules.befriend_base_chance = 0.5
	rules.befriend_subdue_bonus = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	assert_almost_eq(float(rules.roll_join(rng, false)["chance"]), 0.5, 0.0001, "no catch rate = the plain chance (open modes)")
	assert_almost_eq(float(rules.roll_join(rng, false, 0.4)["chance"]), 0.2, 0.0001, "a 0.4 catch rate scales it")


func test_shipped_species_catch_rates_follow_their_strength() -> void:
	var easy: float = Progression.catch_rate_of(CharacterLibrary.get_character(&"tree_grunt"))
	var hard: float = Progression.catch_rate_of(CharacterLibrary.get_character(&"eldroot"))
	assert_eq(easy, 1.0, "an early-route species is easy")
	assert_lt(hard, ProgressionRules.current().low_catch_rate, "a legend-class species is hard")


func test_validator_flags_a_non_boss_trainer_with_a_hard_species() -> void:
	var spec := BattleSpec.new()
	spec.opponent_name = "Grunt"
	var team: Array[Dictionary] = [{"character_id": "eldroot", "strength": 1.0}, {"character_id": "tree_grunt", "strength": 1.0}]
	spec.opponent_team = team
	var w: Array[String] = spec.catch_warnings()
	assert_eq(w.size(), 1, "one warning: the hard species, not the easy one")
	assert_true(w[0].contains("eldroot"), "naming the species")
	spec.boss_battle = true
	assert_true(spec.catch_warnings().is_empty(), "a boss battle (chief / legend) may field anything")


func test_report_shipped_trainer_catch_rates() -> void:
	var specs: Array = []
	var seen: Dictionary = {}
	for aid in StoryController.all_area_ids():
		_collect(OverworldAreaResource.load_by_id(aid), specs, seen)
	var cup := load(TournamentResource.path_for("crown_cup")) as TournamentResource
	_collect(cup, specs, seen)
	assert_gt(specs.size(), 5, "the walk found the shipped story battles")
	var warnings: Array[String] = []
	for s in specs:
		warnings.append_array((s as BattleSpec).catch_warnings())
	for w in warnings:
		gut.p("[catch-rate advisory] " + w)
	pass_test("advisory report printed (%d warning(s)); content guidance, not a failure" % warnings.size())


## Every BattleSpec reachable from [param res] (scripts nest them in commands and branches).
func _collect(res, out: Array, seen: Dictionary) -> void:
	if res == null:
		return
	if res is Array:
		for v in res:
			_collect(v, out, seen)
		return
	if not (res is Resource):
		return
	var id: int = (res as Resource).get_instance_id()
	if seen.has(id):
		return
	seen[id] = true
	if res is BattleSpec:
		out.append(res)
	for p in (res as Resource).get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE):
			continue
		var t: int = int(p["type"])
		if t == TYPE_OBJECT or t == TYPE_ARRAY:
			var v = res.get(p["name"])
			if v is MapResource or v is Texture2D or v is PackedScene:
				continue
			_collect(v, out, seen)
