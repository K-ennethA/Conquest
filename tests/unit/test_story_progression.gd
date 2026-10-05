extends GutTest

## Story progression (pure): party members' level / XP / save fields, XP after a battle
## ([StoryProgression] -- shares, battle multipliers, outcomes, gates), the levels a battle request
## carries to the duel and the tactical board, and the wild level rolls. The maths itself is
## pinned in test_progression_math.gd; here every number reads the SHIPPED rules (the spec's).

const STORY_CTX := {"replay": false, "networked": false, "arena": false, "mode": "story"}


func _rules() -> ProgressionRules:
	return ProgressionRules.current()


func _state(level: int = 5) -> StoryState:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, level)
	s.add_member("petalfang", "", 6, level)
	return s


func _wild_request(foe: String = "petalfang", level: int = 5) -> BattleRequest:
	var r := BattleRequest.new()
	r.kind = BattleRequest.KIND_DUEL
	r.encounter_id = "mossway.wild.%s" % foe
	r.source = BattleRequest.SOURCE_WILD
	r.opponent = {"name": "Wild", "team": [{"character_id": foe, "strength": 1.0, "level": level}]}
	r.rules = {"can_flee": true, "can_befriend": true, "defeat_policy": "whiteout"}
	return r


func _plain(a: Array) -> Array:
	var out: Array = []
	out.assign(a)
	return out


func _won(foes: Array = ["petalfang"]) -> BattleResult:
	var res := BattleResult.make("x", BattleResult.OUTCOME_VICTORY)
	res.party_after = [
		{"member_id": "tree_grunt", "current_hp": StoryPartyMember.HP_FULL, "wounded": false, "fought": true},
		{"member_id": "petalfang", "current_hp": StoryPartyMember.HP_FULL, "wounded": false, "fought": false},
	]
	res.defeated = foes.duplicate()
	return res


# --- Members ---------------------------------------------------------------------------

func test_member_joins_at_its_level_with_that_levels_xp() -> void:
	var s := _state(7)
	var m: StoryPartyMember = s.member("tree_grunt")
	assert_eq(m.level, 7, "add_member's level is the join level")
	assert_eq(m.xp, Progression.xp_for_level(7), "it starts with exactly that level's XP")
	var base: int = m.character().base_health
	assert_eq(m.max_hp(), Progression.max_hp_at(m.character(), 7), "max HP is the level's, not the base")
	assert_gt(m.max_hp(), base, "a level-7 member is tougher than its roster base")


func test_default_member_is_level_one_at_base_stats() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("tree_grunt")
	assert_eq(m.level, 1, "with no level a member is level 1")
	assert_eq(m.max_hp(), m.character().base_health, "level 1 = the roster base stat block")


func test_level_up_keeps_hp_ratio() -> void:
	var s := _state(5)
	var m: StoryPartyMember = s.member("tree_grunt")
	m.current_hp = m.max_hp() / 2
	var ratio: float = float(m.current_hp) / float(m.max_hp())
	var out: Dictionary = m.add_xp(Progression.xp_for_level(9) - m.xp)
	assert_eq(int(out["level_after"]), 9, "enough XP for level 9")
	assert_eq(m.level, 9, "the member is level 9")
	assert_almost_eq(float(m.current_hp) / float(m.max_hp()), ratio, 0.03, "current HP keeps its ratio")
	var full: StoryPartyMember = s.member("petalfang")
	full.add_xp(5000)
	assert_eq(full.current_hp, StoryPartyMember.HP_FULL, "a full member stays full through a level-up")


func test_knocked_out_member_stays_down_through_a_level_up() -> void:
	var s := _state(5)
	var m: StoryPartyMember = s.member("tree_grunt")
	m.current_hp = 0
	m.wounded = true
	m.add_xp(5000)
	assert_eq(m.current_hp, 0, "a level-up never revives")


func test_save_round_trip_and_legacy_default() -> void:
	var s := _state(12)
	var m: StoryPartyMember = s.member("tree_grunt")
	m.add_xp(250)
	m.bond_xp = 7
	var back: StoryPartyMember = StoryPartyMember.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	assert_eq(back.level, m.level, "level round-trips")
	assert_eq(back.xp, m.xp, "XP round-trips")
	assert_eq(back.bond_xp, 7, "bond XP round-trips")
	var legacy: Dictionary = m.to_dict()
	legacy.erase("level")
	legacy.erase("xp")
	legacy.erase("bond_xp")
	legacy["current_hp"] = 20
	var old: StoryPartyMember = StoryPartyMember.from_dict(legacy)
	assert_eq(old.level, _rules().legacy_level, "an older save loads at legacy_level")
	assert_eq(old.xp, Progression.xp_for_level(_rules().legacy_level), "with that level's XP")
	assert_eq(old.bond_xp, 0, "and no bond")
	var base_max: int = old.character().base_health
	assert_almost_eq(float(old.current_hp) / float(old.max_hp()), 20.0 / float(base_max), 0.03,
		"its saved HP keeps its ratio of the old (level-less) max")


func test_saved_xp_never_below_its_level() -> void:
	var d: Dictionary = StoryPartyMember.create("tree_grunt", "tree_grunt", "", 10).to_dict()
	d["xp"] = 3
	var m: StoryPartyMember = StoryPartyMember.from_dict(d)
	assert_eq(m.level, 10, "the saved level holds")
	assert_eq(m.xp, Progression.xp_for_level(10), "XP is lifted to the level's floor")


func test_join_party_command_defaults_to_the_starter_level() -> void:
	var j := JoinPartyCommand.new()
	j.character_id = &"tree_grunt"
	assert_eq(j.join_level(), _rules().starter_level, "no authored level = the starter level (5)")
	j.level = 9
	assert_eq(j.join_level(), 9, "an authored join level wins")


func test_party_top_level() -> void:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 4)
	s.add_member("petalfang", "", 6, 11)
	assert_eq(s.party_top_level(), 11, "the highest level in the party")
	assert_eq(StoryState.new().party_top_level(), 1, "an empty party reads level 1")


# --- XP after a battle ---------------------------------------------------------------

func test_fought_member_earns_xp_and_bench_earns_none() -> void:
	var s := _state(5)
	var awards: Dictionary = StoryProgression.awards_for(s, _wild_request(), _won(), null, STORY_CTX)
	var foe: CharacterResource = CharacterLibrary.get_character(&"petalfang")
	var expected: int = Progression.xp_for_foe(Progression.xp_yield_of(foe), 5, 5, 1.0, 1.0)
	assert_eq(int(awards.get("tree_grunt", 0)), expected, "the fighter earns the wild foe's XP")
	assert_false(awards.has("petalfang"), "the bench earns nothing (xp_share_bench 0)")


func test_fallen_member_earns_half() -> void:
	var s := _state(5)
	var res := _won()
	res.party_after[0]["current_hp"] = 0
	res.party_after[0]["wounded"] = true
	var awards: Dictionary = StoryProgression.awards_for(s, _wild_request(), res, null, STORY_CTX)
	var foe: CharacterResource = CharacterLibrary.get_character(&"petalfang")
	assert_eq(int(awards["tree_grunt"]), Progression.xp_for_foe(Progression.xp_yield_of(foe), 5, 5, 1.0, 0.5),
		"fought and fell = xp_share_fallen (0.5)")


func test_trainer_battle_pays_more_than_wild() -> void:
	var s := _state(5)
	var wild: int = int(StoryProgression.awards_for(s, _wild_request(), _won(), null, STORY_CTX)["tree_grunt"])
	var trainer := _wild_request()
	trainer.source = BattleRequest.SOURCE_TRAINER
	var t: int = int(StoryProgression.awards_for(s, trainer, _won(), null, STORY_CTX)["tree_grunt"])
	assert_gt(t, wild, "a trainer battle multiplies XP (1.5)")
	trainer.rules["boss"] = true
	var b: int = int(StoryProgression.awards_for(s, trainer, _won(), null, STORY_CTX)["tree_grunt"])
	assert_gt(b, t, "a chief / legend battle multiplies more (2.0)")


func test_stronger_foe_gives_more_xp_than_a_weaker_one() -> void:
	var s := _state(10)
	var strong: int = int(StoryProgression.awards_for(s, _wild_request("petalfang", 14), _won(), null, STORY_CTX)["tree_grunt"])
	var weak: int = int(StoryProgression.awards_for(s, _wild_request("petalfang", 6), _won(), null, STORY_CTX)["tree_grunt"])
	var grey: int = int(StoryProgression.awards_for(s, _wild_request("petalfang", 4), _won(), null, STORY_CTX)["tree_grunt"])
	assert_gt(strong, weak, "anti-grind: a stronger foe pays more")
	assert_gt(weak, grey, "and a grey foe barely anything")


func test_loss_flee_spar_and_gates_award_nothing() -> void:
	var s := _state(5)
	var lost := _won()
	lost.outcome = BattleResult.OUTCOME_DEFEAT
	assert_true(StoryProgression.awards_for(s, _wild_request(), lost, null, STORY_CTX).is_empty(),
		"a loss earns nothing (xp_on_loss_mult 0)")
	var fled := _won()
	fled.outcome = BattleResult.OUTCOME_FLED
	assert_true(StoryProgression.awards_for(s, _wild_request(), fled, null, STORY_CTX).is_empty(), "a flee earns nothing")
	var spar := _wild_request()
	spar.rules["spar"] = true
	assert_true(StoryProgression.awards_for(s, spar, _won(), null, STORY_CTX).is_empty(),
		"a friendly spar earns no XP (xp_spar_mult 0)")
	var replay: Dictionary = STORY_CTX.duplicate()
	replay["replay"] = true
	assert_true(StoryProgression.awards_for(s, _wild_request(), _won(), null, replay).is_empty(), "never in a replay")
	var net: Dictionary = STORY_CTX.duplicate()
	net["networked"] = true
	assert_true(StoryProgression.awards_for(s, _wild_request(), _won(), null, net).is_empty(), "never networked")
	assert_true(StoryProgression.awards_for(s, _wild_request(), _won(), null, {"mode": "skirmish"}).is_empty(),
		"only in story")


func test_loss_multiplier_is_a_knob() -> void:
	var s := _state(5)
	var r := ProgressionRules.new()
	r.xp_on_loss_mult = 0.5
	var lost := _won()
	lost.outcome = BattleResult.OUTCOME_DEFEAT
	assert_gt(int(StoryProgression.awards_for(s, _wild_request(), lost, r, STORY_CTX).get("tree_grunt", 0)), 0,
		"a ruleset may pay for a loss")


func test_foe_levels_prefer_the_battle_then_the_rows_then_enemy_level() -> void:
	var req := _wild_request("petalfang", 9)
	req.enemy_level = 3
	var res := _won(["petalfang", "tree_grunt"])
	assert_eq(_plain(StoryProgression.foe_levels(req, res)), [9, 3],
		"a row's own level, else the request's enemy_level")
	res.defeated_levels = [12, 0]
	assert_eq(_plain(StoryProgression.foe_levels(req, res)), [12, 3],
		"a level the battle reports wins; an unknown one (0) falls back")


func test_apply_awards_levels_up_and_reports_rows() -> void:
	var s := _state(5)
	var m: StoryPartyMember = s.member("tree_grunt")
	var rows: Array[Dictionary] = StoryProgression.apply_awards(s, {"tree_grunt": 300})
	assert_eq(rows.size(), 1, "one row per member that earned XP")
	assert_eq(int(rows[0]["gained"]), 300, "the row says what landed")
	assert_eq(int(rows[0]["level_before"]), 5, "from level 5")
	assert_eq(int(rows[0]["level_after"]), m.level, "to the member's new level")
	assert_true(bool(rows[0]["leveled"]), "a level-up is flagged")
	assert_true(StoryProgression.result_line(rows[0]).contains("Lv 5 -> %d" % m.level), "the line names the level-up")
	var preview: Array[Dictionary] = StoryProgression.preview_rows(s, {"tree_grunt": 10})
	var before: int = m.xp
	assert_eq(int(preview[0]["xp"]), before + 10, "a preview computes the new total...")
	assert_eq(m.xp, before, "...without touching the member")


func test_result_applier_awards_xp_under_the_story_gate() -> void:
	var s := _state(5)
	var before: int = s.member("tree_grunt").xp
	var out: Dictionary = StoryResultApplier.apply(s, _wild_request(), _won(), null, STORY_CTX)
	assert_gt(s.member("tree_grunt").xp, before, "a won story battle pays XP")
	assert_eq((out["xp"] as Array).size(), 1, "and reports the row")
	var s2 := _state(5)
	StoryResultApplier.apply(s2, _wild_request(), _won(), null, {})
	assert_eq(s2.member("tree_grunt").xp, before, "no gate context (a tool / test apply) = no XP")


# --- Requests carry levels ---------------------------------------------------------------

func test_party_snapshot_carries_levels() -> void:
	var s := _state(8)
	var snap: Array = StoryBattleBridge.party_snapshot(s.party)
	assert_eq(int(snap[0]["level"]), 8, "the request's party rows carry each member's level")


func test_battle_spec_carries_enemy_level_and_boss() -> void:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	var team: Array[Dictionary] = [{"character_id": "petalfang", "strength": 1.0, "level": 6},
		{"character_id": "tree_grunt", "strength": 1.0}]
	spec.opponent_team = team
	spec.enemy_level = 4
	var r: BattleRequest = spec.to_request(BattleRequest.SOURCE_TRAINER, "t")
	assert_eq(r.enemy_level, 4, "the spec's enemy level reaches the request")
	assert_eq(r.foe_level(0), 6, "a row's own level")
	assert_eq(r.foe_level(1), 4, "a row without one reads enemy_level")
	assert_false(r.is_boss_battle(), "not a boss battle by default")
	spec.boss_battle = true
	assert_true(spec.to_request(BattleRequest.SOURCE_SCRIPT, "t").is_boss_battle(), "boss_battle reaches the rules")
	var back: BattleRequest = BattleRequest.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(back.enemy_level, 4, "enemy_level round-trips")


func test_wild_entry_request_carries_its_rolled_level() -> void:
	var e := EncounterEntry.new()
	e.character_id = &"petalfang"
	var r: BattleRequest = e.to_request("mossway", "wild", "", 7)
	assert_eq(r.foe_level(0), 7, "the wild row carries its level")
	assert_eq(e.to_request("mossway").foe_level(0), 0, "no level rolled = none")


func test_duel_request_takes_levels_from_the_story_request() -> void:
	var s := _state(9)
	var br := _wild_request("petalfang", 6)
	br.party = StoryBattleBridge.party_snapshot(s.party)
	var res: Dictionary = DuelRequest.from_battle_request(br.to_dict())
	assert_true(bool(res["success"]), "the story request converts")
	var dr: DuelRequest = res["request"]
	assert_eq(dr.player_party[0].level, 9, "the party lead fights at its level")
	assert_eq(dr.foe_party[0].level, 6, "the wild foe at its rolled level")


func test_duel_combatant_level_serialises_only_when_set() -> void:
	var c := DuelCombatant.make(&"petalfang")
	assert_false(c.to_dict().has("level"), "an open-mode combatant has no level key (replay headers unchanged)")
	c.level = 12
	var d: Dictionary = c.to_dict()
	assert_eq(int(d["level"]), 12, "a story combatant carries its level")
	var back: Dictionary = DuelCombatant.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq((back["combatant"] as DuelCombatant).level, 12, "and it round-trips")
	d["level"] = "high"
	assert_eq(String(DuelCombatant.from_dict(d)["reason"]), "bad_level", "a malformed level is refused")


func test_tactical_spawn_levels() -> void:
	var s := _state(8)
	var r := BattleRequest.new()
	r.party = StoryBattleBridge.party_snapshot(s.party)
	r.enemy_level = 6
	r.ally_level = 8
	assert_eq(StoryBattleBridge.level_for_spawn(r, 0, {MapLoader.SQUAD_SLOT_KEY: 1}), 8,
		"a squad pick fights at its party member's level")
	assert_eq(StoryBattleBridge.level_for_spawn(r, 0, {}), 8, "a guest ally at the ally level")
	assert_eq(StoryBattleBridge.level_for_spawn(r, 1, {}), 6, "a foe at the battle's enemy level")
	assert_eq(StoryBattleBridge.level_for_spawn(r, 1, {"level": 11}), 11, "a spawn's own level wins")
	assert_eq(StoryBattleBridge.level_for_spawn(null, 1, {}), 0, "no story request = no level")


func test_battle_result_round_trips_levels() -> void:
	var res := _won()
	res.defeated_levels = [7]
	res.befriend_offer = {"character_id": "petalfang", "accepted": false, "level": 7}
	var back: BattleResult = BattleResult.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	assert_eq(back.defeated_levels, [7], "defeated foe levels round-trip")
	assert_eq(int(back.befriend_offer["level"]), 7, "the offer keeps the level it was met at")


# --- Wild levels -----------------------------------------------------------------------

func test_wild_level_roll_is_deterministic_and_in_band() -> void:
	var band := Vector2i(2, 8)
	var seen: Dictionary = {}
	for step in range(200):
		var lv: int = EncounterRoller.roll_level(1234, "mossway|%d" % step, band)
		assert_between(lv, 2, 8, "a rolled level stays in the band")
		seen[lv] = true
	assert_gt(seen.size(), 4, "the rolls spread across the band")
	assert_eq(EncounterRoller.roll_level(1234, "mossway|7", band), EncounterRoller.roll_level(1234, "mossway|7", band),
		"the same seed + key always rolls the same level")


func test_zone_band_falls_back_to_the_area() -> void:
	var area := OverworldAreaResource.new()
	area.level_band = Vector2i(2, 8)
	var z := EncounterZone.new()
	assert_eq(z.band_in(area), Vector2i(2, 8), "an unset zone band is the area's")
	z.level_band = Vector2i(4, 5)
	assert_eq(z.band_in(area), Vector2i(4, 5), "a zone may narrow it")
	assert_eq(EncounterZone.new().band_in(null), Vector2i.ZERO, "nothing set = no levels")
