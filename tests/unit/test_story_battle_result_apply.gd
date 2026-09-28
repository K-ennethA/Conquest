extends GutTest

## StoryResultApplier (pure): HP / wounded, rewards and the trainer flag on victory, whiteout
## on defeat, nothing but HP on a flee, grace steps always; and the DuelStub's result builder
## (the contract feat/duel will honour: offers roll on VICTORY off the battle seed).


func _state() -> StoryState:
	var s := StoryState.new()
	s.add_member("vineweave")
	s.add_member("blightcap")
	return s


func _request(source: String = BattleRequest.SOURCE_TRAINER, policy: String = "whiteout") -> BattleRequest:
	var r := BattleRequest.new()
	r.encounter_id = "trainer.mossway.bram"
	r.source = source
	r.rules = {"defeat_policy": policy}
	r.rewards = {"gold": 120, "items": ["sagebloom_poultice"], "flags": ["mossway.bram.talked"]}
	return r


func test_victory_applies_hp_rewards_and_trainer_flag() -> void:
	var s := _state()
	var res := BattleResult.make("trainer.mossway.bram", BattleResult.OUTCOME_VICTORY)
	res.party_after = [
		{"member_id": "vineweave", "current_hp": 20, "wounded": false},
		{"member_id": "blightcap", "current_hp": 0, "wounded": true},
	]
	var out: Dictionary = StoryResultApplier.apply(s, _request(), res, null)
	assert_eq(s.member("vineweave").current_hp, 20, "HP carries")
	assert_true(s.member("blightcap").wounded, "a KO'd member is wounded")
	assert_eq(s.gold, 120, "reward gold")
	assert_eq(s.item_count("sagebloom_poultice"), 1, "reward item into the story bag")
	assert_true(s.has_flag("mossway.bram.talked"), "reward flags")
	assert_true(s.has_flag("trainer.mossway.bram.defeated"), "the trainer's defeated flag")
	assert_false(bool(out["whiteout"]), "no whiteout on a win")
	assert_eq(s.grace_steps, 3, "grace steps after any battle")


func test_full_hp_stores_the_sentinel() -> void:
	var s := _state()
	var res := BattleResult.make("x", BattleResult.OUTCOME_VICTORY)
	res.party_after = [{"member_id": "vineweave", "current_hp": 9999, "wounded": false}]
	StoryResultApplier.apply(s, _request(), res, null)
	assert_eq(s.member("vineweave").current_hp, StoryPartyMember.HP_FULL, "max HP is stored as HP_FULL")


func test_whiteout_heals_and_reports() -> void:
	var s := _state()
	var res := BattleResult.make("x", BattleResult.OUTCOME_DEFEAT)
	res.party_after = [{"member_id": "vineweave", "current_hp": 0, "wounded": true}]
	var out: Dictionary = StoryResultApplier.apply(s, _request(), res, null)
	assert_true(bool(out["whiteout"]), "a WHITEOUT defeat whites out")
	assert_false(s.member("vineweave").wounded, "the party is healed")
	assert_eq(s.gold, 0, "no reward on a loss")
	assert_false(s.has_flag("trainer.mossway.bram.defeated"), "the trainer stays undefeated")


func test_continue_policy_keeps_wounds_and_flee_changes_only_hp() -> void:
	var s := _state()
	var res := BattleResult.make("x", BattleResult.OUTCOME_DEFEAT)
	res.party_after = [{"member_id": "vineweave", "current_hp": 0, "wounded": true}]
	var out: Dictionary = StoryResultApplier.apply(s, _request(BattleRequest.SOURCE_SCRIPT, "continue"), res, null)
	assert_false(bool(out["whiteout"]), "CONTINUE never whites out")
	assert_true(s.member("vineweave").wounded, "the wound stays until a Wayshrine")
	var s2 := _state()
	var fled := BattleResult.make("x", BattleResult.OUTCOME_FLED)
	fled.party_after = [{"member_id": "vineweave", "current_hp": 30, "wounded": false}]
	StoryResultApplier.apply(s2, _request(BattleRequest.SOURCE_WILD), fled, null)
	assert_eq(s2.member("vineweave").current_hp, 30, "a flee keeps the damage")
	assert_eq(s2.gold, 0, "and pays nothing")


func test_unknown_members_are_ignored() -> void:
	var s := _state()
	var res := BattleResult.make("x", BattleResult.OUTCOME_VICTORY)
	res.party_after = [{"member_id": "ghost", "current_hp": 1, "wounded": true}]
	StoryResultApplier.apply(s, _request(), res, null)
	assert_eq(s.party.size(), 2, "an unknown member id changes nothing")


func test_duel_stub_result_contract() -> void:
	var r := BattleRequest.new()
	r.kind = BattleRequest.KIND_DUEL
	r.encounter_id = "mossway.grass.petalfang"
	r.seed = 77
	r.party = [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": -1},
		{"member_id": "blightcap", "character_id": "blightcap", "current_hp": 30}]
	r.opponent = {"team": [{"character_id": "petalfang"}]}
	r.rules = {"can_befriend": true}
	var win: BattleResult = DuelStub.build_result(r, BattleResult.OUTCOME_VICTORY, true, 0.0)
	assert_eq(win.befriend_offer, {"character_id": "petalfang", "accepted": false}, "a forced win offers")
	assert_eq(win.defeated, ["petalfang"], "the foe is defeated")
	assert_eq(int(win.party_after[1]["current_hp"]), 30, "the bench keeps its HP")
	var no_offer: BattleResult = DuelStub.build_result(r, BattleResult.OUTCOME_VICTORY, false, 0.0)
	assert_true(no_offer.befriend_offer.is_empty(), "chance 0 and no force -> no offer")
	r.rules["story_critical"] = true
	assert_false(DuelStub.build_result(r, BattleResult.OUTCOME_VICTORY, false, 0.0).befriend_offer.is_empty(),
		"a story-critical recruit always offers on a win")
	var loss: BattleResult = DuelStub.build_result(r, BattleResult.OUTCOME_DEFEAT, true, 1.0)
	assert_true(loss.befriend_offer.is_empty(), "no offer on a loss")
	assert_true(bool(loss.party_after[0]["wounded"]), "the lead is KO'd")
