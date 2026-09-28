extends GutTest

## BattleRequest / BattleResult round trip through JSON (the shared contract with feat/duel),
## strict decoding, and BattleSpec -> request.


func test_request_round_trip_through_json() -> void:
	var r := BattleRequest.new()
	r.kind = BattleRequest.KIND_DUEL
	r.encounter_id = "mossway.grass.petalfang"
	r.source = BattleRequest.SOURCE_WILD
	r.seed = 123456
	r.party = [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": 40, "item_id": "", "growth": {}}]
	r.opponent = {"name": "Wild Petalfang", "speaker_id": "petalfang", "portrait": "petalfang",
		"team": [{"character_id": "petalfang", "strength": 1.0}]}
	r.rules = {"can_flee": true, "can_befriend": true, "defeat_policy": "whiteout", "story_critical": false}
	r.rewards = {"gold": 10, "items": [], "points": 0, "flags": []}
	r.return_to = {"area_id": "mossway", "cell": [5, 6, 0], "facing": "east"}
	var back: BattleRequest = BattleRequest.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_not_null(back, "a JSON round trip decodes")
	assert_eq(back.kind, "duel", "kind")
	assert_eq(back.seed, 123456, "seed survives as an int")
	assert_eq(int(back.party[0]["current_hp"]), 40, "party HP")
	assert_true(back.party[0]["current_hp"] is int, "HP is coerced back to int")
	assert_eq(back.lead_foe_id(), "petalfang", "the lead foe")
	assert_true(back.can_befriend(), "rules")
	assert_eq(back.defeat_policy(), "whiteout", "defeat policy")
	assert_eq(back.return_to["area_id"], "mossway", "return point")


func test_request_decode_is_strict() -> void:
	assert_null(BattleRequest.from_dict({"kind": "chess"}), "an unknown kind is refused")
	assert_null(BattleRequest.from_dict("nope"), "a non-dictionary is refused")
	var r: BattleRequest = BattleRequest.from_dict({"kind": "tactical", "party": [1, {"member_id": "a"}]})
	assert_eq(r.party.size(), 1, "non-dictionary party entries are dropped")
	assert_eq(r.defeat_policy(), "whiteout", "a missing policy defaults to whiteout")


func test_result_round_trip() -> void:
	var res := BattleResult.make("trainer.mossway.bram", BattleResult.OUTCOME_VICTORY)
	res.party_after = [{"member_id": "vineweave", "current_hp": 12, "wounded": false}]
	res.defeated = ["tree_grunt", "petalfang"]
	res.befriend_offer = {"character_id": "petalfang", "accepted": false}
	res.turns = 7
	var back: BattleResult = BattleResult.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	assert_eq(back.outcome, "victory", "outcome")
	assert_eq(back.party_after[0]["current_hp"], 12, "party HP")
	assert_eq(back.defeated.size(), 2, "defeated list")
	assert_true(back.has_open_offer(), "an unaccepted befriend offer is open")
	assert_eq(back.turns, 7, "turns")
	assert_null(BattleResult.from_dict({"outcome": "draw"}), "an unknown outcome is refused")


func test_spec_to_request() -> void:
	var spec := BattleSpec.new()
	spec.map_path = "res://x.tres"
	spec.opponent_name = "Bram"
	spec.reward_gold = 120
	spec.defeat_policy = BattleSpec.DefeatPolicy.RETRY
	spec.clash_intro = true
	var r: BattleRequest = spec.to_request(BattleRequest.SOURCE_TRAINER, "trainer.mossway.bram")
	assert_eq(r.kind, "tactical", "a tactical spec")
	assert_eq(r.encounter_id, "trainer.mossway.bram", "the fallback id names it")
	assert_eq(int(r.rewards["gold"]), 120, "rewards carried")
	assert_eq(r.defeat_policy(), "retry", "policy carried")
	assert_true(r.clash_intro, "clash intro carried")
