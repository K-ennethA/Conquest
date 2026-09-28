extends GutTest

## The pure seams of the story <-> evolution <-> duel wiring (docs/STORY_MODE.md "Wiring"): the
## story party member IS a RosterLedger record (story-scoped), story Growth runs the shared
## GrowthTracker maths off a BattleResult (only members that FOUGHT), StoryFlagTrigger reads the
## journey's flags, and the duel adapter / result speak the overworld contract (one wild foe,
## the encounter rules, the befriend offer only when the roll offered). No tree, no disk.


func _win(entries: Array) -> BattleResult:
	var r := BattleResult.make("mossway.grass.petalfang", BattleResult.OUTCOME_VICTORY)
	r.party_after = entries
	return r


func _rules(modes: Array = ["story"]) -> EvolutionRules:
	var rules := EvolutionRules.new()
	rules.growth_modes = PackedStringArray(modes)
	return rules


# --- The member record -------------------------------------------------------------

func test_a_member_is_a_roster_ledger_record() -> void:
	var m := StoryPartyMember.create("tree_grunt", "tree_grunt", "Sprig")
	m.add_growth(2)
	var rec: Dictionary = m.ledger_record()
	assert_eq(rec["line"], "tree_grunt", "line = the evolution line root")
	assert_eq(rec["form"], "tree_grunt", "form = the current character")
	assert_eq(int(rec["growth"]), 2, "growth")
	assert_eq(rec["evolved"], [], "no history yet")
	assert_eq(rec["nickname"], "Sprig", "nickname")
	rec["form"] = "oakheart"
	rec["growth"] = 3
	rec["evolved"] = [{"edge": "tree_grunt__oakheart", "at": "x"}]
	m.apply_ledger_record(rec)
	assert_eq(m.character_id, "oakheart", "the record's form becomes the member's character")
	assert_eq(m.member_id, "tree_grunt", "the member id never changes")
	assert_eq(m.growth_points(), 3, "growth folded back")
	assert_eq(m.evolution_history().size(), 1, "history folded back")


func test_an_m1_save_without_growth_still_loads() -> void:
	var m := StoryPartyMember.from_dict({"member_id": "vineweave", "character_id": "vineweave",
		"current_hp": 30, "growth": {}})
	assert_not_null(m, "an M1 record (opaque empty growth) loads")
	assert_eq(m.growth_points(), 0, "as zero Growth")
	assert_eq(m.line, "vineweave", "its line defaults to the character's root")
	var keep := StoryPartyMember.from_dict({"member_id": "a", "character_id": "vineweave",
		"growth": {"growth": 4.0, "bond": 7}})
	assert_eq(keep.growth_points(), 4, "JSON floats read as ints")
	assert_eq(int(keep.to_dict()["growth"]["bond"]), 7, "unknown growth keys round-trip untouched")


func test_a_recruit_of_an_evolved_form_is_keyed_by_its_line() -> void:
	var s := StoryState.new()
	var m := s.add_member("oakheart")
	assert_eq(m.line, "tree_grunt", "an Oakheart belongs to the Barkling line")
	assert_eq(m.member_id, "tree_grunt", "and takes the line's uid")
	assert_eq(s.add_member("tree_grunt").member_id, "tree_grunt#2", "the next of the line is #2")


# --- Growth ----------------------------------------------------------------------------

func test_rows_only_for_members_that_fought() -> void:
	var r := _win([
		{"member_id": "vineweave", "current_hp": 40, "wounded": false, "fought": true, "kos": 1},
		{"member_id": "blightcap", "current_hp": 20, "wounded": false, "fought": false},
		{"member_id": "petalfang", "current_hp": 0, "wounded": true},
	])
	var rows: Array = StoryGrowth.rows_for(r)
	assert_eq(rows.size(), 2, "the bench that never took the field is not a row")
	assert_eq(rows[0], {"uid": "vineweave", "alive": true, "kos": 1}, "a survivor with its KOs")
	assert_eq(rows[1], {"uid": "petalfang", "alive": false, "kos": 0}, "fought defaults to true (tactical)")


func test_awards_follow_the_shared_rules_and_gates() -> void:
	var r := _win([{"member_id": "vineweave", "current_hp": 40, "wounded": false},
		{"member_id": "petalfang", "current_hp": 0, "wounded": true}])
	var ctx := StoryGrowth.gate_context()
	assert_eq(StoryGrowth.awards_for(r, _rules(), ctx), {"vineweave": 1}, "a survivor of a win earns growth_per_win")
	assert_eq(StoryGrowth.awards_for(r, _rules(["skirmish"]), ctx), {}, "no \"story\" in growth_modes: nothing")
	assert_eq(StoryGrowth.awards_for(r, _rules(), StoryGrowth.gate_context(true)), {}, "never while a replay plays")
	var fled := BattleResult.make("x", BattleResult.OUTCOME_FLED)
	fled.party_after = r.party_after
	assert_eq(StoryGrowth.awards_for(fled, _rules(), ctx), {}, "running is neither a win nor a loss")
	assert_true(EvolutionRules.current().earns_growth_in("story"), "the shipped rules list story")
	assert_false(EvolutionRules.current().earns_growth_in("duel"), "standalone duels ship without growth")


func test_apply_awards_writes_the_member_and_reports_the_end_screen_rows() -> void:
	var s := StoryState.new()
	var bark := s.add_member("tree_grunt")
	bark.add_growth(2)
	s.add_member("vineweave")
	var preview: Array = StoryGrowth.preview_rows(s, {"tree_grunt": 1})
	assert_eq(bark.growth_points(), 2, "a preview writes nothing")
	assert_eq(preview.size(), 1, "one row")
	var rows: Array = StoryGrowth.apply_awards(s, {"tree_grunt": 1, "vineweave": 1})
	assert_eq(bark.growth_points(), 3, "applied")
	assert_eq(int(rows[0]["total"]), 3, "the row's total")
	assert_eq(int(rows[0]["goal"]), 3, "Barkling's goal")
	assert_true(bool(rows[0]["ready"]), "ready to evolve")
	assert_eq(preview[0], rows[0], "the preview matched what Continue applied")
	assert_eq(StoryGrowth.pending(s), ["tree_grunt"], "the Barkling now has an evolution pending")


# --- Story flags ---------------------------------------------------------------------

func test_story_flag_trigger_reads_the_journey_flags() -> void:
	var t := StoryFlagTrigger.new()
	t.flag = "shrine.cleansed"
	assert_false(t.is_met({}), "outside story (no story_flags) it is never met")
	assert_false(t.is_met({"story_flags": {}}), "unset")
	assert_true(t.is_met({"story_flags": {"shrine.cleansed": true}}), "set (bool)")
	assert_true(t.is_met({"story_flags": ["shrine.cleansed"]}), "set (array form)")
	t.min_value = 2
	assert_false(t.is_met({"story_flags": {"shrine.cleansed": 1}}), "below the quest stage")
	assert_true(t.is_met({"story_flags": {"shrine.cleansed": 2}}), "at the quest stage")
	var s := StoryState.new()
	s.set_flag("shrine.cleansed", 2)
	assert_true(t.is_met(StoryGrowth.evolution_context(s)), "StoryGrowth hands the trigger the journey's flags")


# --- The duel's side of the contract ---------------------------------------------------

func _story_request(source: String, team: Array, rules: Dictionary = {}) -> Dictionary:
	return {
		"kind": "duel", "encounter_id": "mossway.grass.petalfang", "source": source, "seed": 7,
		"party": [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": 40,
			"item_id": "heartwood_charm"}],
		"opponent": {"name": "Wild", "team": team},
		"backdrop": {"tile_id": "no_such_tile", "weather": "Not A Weather"},
		"rules": rules,
	}


func test_a_wild_story_request_becomes_a_one_foe_duel_with_its_rules() -> void:
	var team := [{"character_id": "petalfang", "strength": 1.0}, {"character_id": "blightcap", "strength": 1.0}]
	var res := DuelRequest.from_battle_request(_story_request("wild", team,
		{"can_flee": true, "can_befriend": false, "story_critical": false, "defeat_policy": "whiteout"}))
	assert_true(bool(res["success"]), "adapted (%s)" % String(res.get("reason", "")))
	var req: DuelRequest = res["request"]
	assert_eq(req.foe_party.size(), 1, "a wild encounter is one foe")
	assert_eq(req.origin, DuelRequest.ORIGIN_STORY, "story origin")
	assert_true(req.can_flee(), "can_flee carried")
	assert_false(req.can_befriend(), "can_befriend carried (overrides the wild default)")
	assert_eq(req.player_party[0].current_hp, 40, "carried HP")
	assert_eq(req.player_party[0].item_ids.size(), 1, "one story-bag item")
	assert_eq(req.player_party[0].item_ids[0], "heartwood_charm", "the member's own")
	assert_eq(req.station_tile_id, &"", "an unknown overworld tile falls back to the stage's own")
	assert_eq(req.weather_id, &"clear", "an unknown weather falls back to clear")
	var back := DuelRequest.from_dict(req.to_dict())
	assert_true(bool(back["success"]), "round trips")
	assert_eq((back["request"] as DuelRequest).rules, req.rules, "with its rules")
	var bad := req.to_dict()
	bad["rules"] = {"can_flee": "yes"}
	assert_false(bool(DuelRequest.from_dict(bad)["success"]), "a non-bool rule is refused (strict importer)")


func test_kind_defaults_when_no_rules_are_given() -> void:
	var wild := DuelRequest.standalone(&"vineweave", &"petalfang")
	wild.kind = DuelRequest.KIND_WILD
	assert_true(wild.can_flee() and wild.can_befriend(), "a wild duel may be fled and may befriend")
	var trainer := DuelRequest.standalone(&"vineweave", &"petalfang")
	assert_false(trainer.can_flee() or trainer.can_befriend(), "any other duel neither")
	assert_false(trainer.is_story_critical(), "nor is it story-critical")


func test_the_battle_result_carries_an_offer_only_when_the_roll_offered() -> void:
	var r := DuelResult.new()
	r.outcome = DuelResult.OUTCOME_VICTORY
	r.befriend_offer = {"character_id": "petalfang", "offered": false, "accepted": false, "chance": 0.25, "roll": 0.7}
	assert_eq(r.to_battle_result()["befriend_offer"], {}, "a declined roll is no offer")
	r.befriend_offer["offered"] = true
	var br := BattleResult.from_dict(r.to_battle_result())
	assert_true(br.has_open_offer(), "an offered roll opens the story prompt")
	assert_eq(br.befriend_offer, {"character_id": "petalfang", "accepted": false}, "in the overworld's shape")


func test_battle_result_keeps_fought_and_kos() -> void:
	var br := BattleResult.from_dict({"outcome": "victory", "party_after": [
		{"member_id": "a", "current_hp": 3, "wounded": false, "fought": false, "kos": 2},
		{"member_id": "b", "current_hp": 3, "wounded": false}]})
	assert_false(bool(br.party_after[0]["fought"]), "fought survives the decode")
	assert_eq(int(br.party_after[0]["kos"]), 2, "kos survives the decode")
	assert_true(bool(br.party_after[1]["fought"]), "an older result (no key) counts as fought")
