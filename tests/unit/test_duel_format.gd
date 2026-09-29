extends GutTest

## DUEL FORMATS as data ([DuelFormat]): the presets (Singles 1v1, Trio 3v3, Full 6v6, the story
## party), the strict importer (a match config / replay header is untrusted), team checks
## (size, species clause), the strength cap, and that applying a format never touches the
## shared ruleset (rule 7). Plus the wire half: the SWITCH action's shape, wording and replay
## encoding, and the protocol bump.


func test_the_presets() -> void:
	var s := DuelFormat.preset(DuelFormat.SINGLES)
	assert_eq(s.team_size, 1)
	assert_false(s.allow_switch, "Singles has no bench to switch to")
	var t := DuelFormat.preset(DuelFormat.TRIO)
	assert_eq(t.team_size, 3)
	assert_true(t.allow_switch and t.ko_replacement and t.species_clause, "Trio: switching, picks, clause")
	assert_eq(t.versus_label(), "3v3")
	var f := DuelFormat.preset(DuelFormat.FULL)
	assert_eq(f.team_size, 6)
	var story := DuelFormat.preset(DuelFormat.STORY)
	assert_eq(story.team_size, 3, "story: the lead plus up to two bench members")
	assert_false(story.species_clause, "a journey may own several of one species")
	assert_null(DuelFormat.preset("quad"), "unknown ids are no format")
	assert_ne(DuelFormat.preset(DuelFormat.TRIO), DuelFormat.preset(DuelFormat.TRIO), "every call is a fresh copy")
	assert_eq(DuelFormat.menu_presets().size(), 3, "the menus offer Singles / Trio / Full")
	assert_true(t.summary().contains("3v3") and t.summary().contains("species clause"), t.summary())


func test_the_importer_is_strict() -> void:
	var by_id := DuelFormat.from_dict("trio")
	assert_true(bool(by_id["success"]))
	assert_eq((by_id["format"] as DuelFormat).team_size, 3)
	var round_trip := DuelFormat.from_dict(DuelFormat.preset(DuelFormat.FULL).to_dict())
	assert_eq((round_trip["format"] as DuelFormat).id, DuelFormat.FULL, "an untouched preset keeps its id")
	var custom := DuelFormat.from_dict({"id": "trio", "team_size": 4})
	assert_true(bool(custom["success"]))
	assert_eq((custom["format"] as DuelFormat).id, DuelFormat.CUSTOM, "a changed preset becomes custom")
	assert_eq((custom["format"] as DuelFormat).team_size, 4)
	for bad in [{"team_size": 0}, {"team_size": 7}, {"team_size": "3"}, {"allow_switch": 1},
			{"active_per_side": 2}, {"strength_cap": -1.0}, 42, "hexa", {"id": 5}]:
		assert_false(bool(DuelFormat.from_dict(bad)["success"]), "refused: %s" % str(bad))


func test_team_checks_and_the_strength_cap() -> void:
	var t := DuelFormat.preset(DuelFormat.TRIO)
	assert_eq(t.team_problem(["a", "b", "c"]), "")
	assert_eq(t.team_problem(["a", "b"]), "bad_team_size", "exactly three for a versus team")
	assert_eq(t.team_problem(["a", "b"], false), "", "up to three for a story party")
	assert_eq(t.team_problem(["a", "b", "a"]), "species_clause")
	assert_eq(t.team_problem([]), "bad_team_size")
	var story := DuelFormat.preset(DuelFormat.STORY)
	assert_eq(story.team_problem(["a", "a"], false), "", "no clause in story")
	t.strength_cap = 1.0
	assert_eq(t.clamp_strength(1.8), 1.0)
	assert_eq(t.clamp_strength(0.7), 0.7)


func test_applying_a_format_never_touches_the_shared_ruleset() -> void:
	var shared := DuelRuleset.load_default()
	var before := [shared.party_size, shared.allow_switch, shared.ko_replacement, shared.species_clause]
	var rules := DuelFormat.preset(DuelFormat.FULL).apply_to(shared)
	assert_ne(rules, shared, "a private copy")
	assert_eq(rules.party_size, 6)
	assert_true(rules.allow_switch and rules.ko_replacement and rules.species_clause)
	assert_eq([shared.party_size, shared.allow_switch, shared.ko_replacement, shared.species_clause], before,
		"the shipped ruleset is unchanged (rule 7)")
	var singles := DuelFormat.preset(DuelFormat.SINGLES).apply_to(shared)
	assert_false(singles.allow_switch or singles.ko_replacement, "no bench, no switching")
	assert_true(shared.persists_on_switch(&"poisoned"), "poison survives a switch-out")
	assert_false(shared.persists_on_switch(&"braced"), "a guard does not")


func test_a_request_enforces_its_format() -> void:
	var req := DuelRequest.teams(["vineweave", "vineweave", "petalfang"], ["gem_knight"], DuelFormat.preset(DuelFormat.TRIO))
	assert_eq(String(req.validate()["reason"]), "species_clause", "a repeated species under the clause")
	var ok := DuelRequest.teams(["vineweave", "gem_knight", "petalfang", "monster"], ["gem_knight"],
		DuelFormat.preset(DuelFormat.TRIO))
	assert_true(bool(ok.validate()["success"]))
	assert_eq(ok.team_of(0).size(), 3, "the team is the first team_size members")
	assert_eq(ok.team_of(1).size(), 1)
	assert_eq(DuelRequest.standalone(&"vineweave", &"gem_knight").effective_format().id, DuelFormat.SINGLES,
		"an older request means Singles")
	var back := DuelRequest.from_dict(ok.to_dict())
	assert_true(bool(back["success"]))
	assert_eq((back["request"] as DuelRequest).effective_format().team_size, 3, "the format rides to_dict")
	var tampered := ok.to_dict()
	tampered["format"] = {"team_size": 9}
	assert_false(bool(DuelRequest.from_dict(tampered)["success"]), "a tampered format is refused")


func test_the_switch_action_on_the_wire() -> void:
	assert_eq(NetProtocol.PROTOCOL_VERSION, 6, "protocol 6 = party duels + the online turn clock")
	var sw := NetProtocol.switch_to("0:2")
	assert_eq(int(sw[NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH)
	assert_true(NetProtocol.is_well_formed(sw))
	assert_false(NetProtocol.is_well_formed(NetProtocol.make_action(NetProtocol.Action.SWITCH, {})), "needs a unit id")
	assert_eq(NetProtocol.type_name(NetProtocol.Action.SWITCH), "SWITCH")
	assert_eq(NetProtocol.describe_intent_rejection(NetProtocol.INTENT_MUST_PICK, sw),
		"Switch rejected — choose who fights next first")
	assert_true(NetProtocol.describe_intent_rejection(NetProtocol.INTENT_ILLEGAL_SWITCH, sw).contains("cannot come in"))
	var stamped := NetProtocol.stamp_resolution(sw.duplicate(true), 7, 1234567)
	var enc := ReplayLog.encode_command(stamped)
	assert_false(enc.is_empty(), "a replay can carry a SWITCH")
	var dec := ReplayLog.decode_command(enc)
	assert_eq(String(dec[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), "0:2")
	assert_eq(int(dec[NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH)


func test_a_tactical_board_has_no_switch() -> void:
	var rules := NetGameRules.new(func(): return null, func(): return null)
	var res := rules.apply_action(NetProtocol.stamp_resolution(NetProtocol.switch_to("0:1"), 1, 5))
	assert_false(bool(res["ok"]), "no board with a party: nothing to switch")
