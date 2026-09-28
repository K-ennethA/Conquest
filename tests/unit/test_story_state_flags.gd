extends GutTest

## StoryState flags, party, bag/gold, and the ConditionContext expressions that read them
## (docs/design/OVERWORLD.md §4.2). Pure: no tree, no disk.


func test_flags_set_get_has_inc() -> void:
	var s := StoryState.new()
	assert_false(s.has_flag("quest.blight_road"), "an unset flag is falsy")
	assert_eq(s.get_flag_int("quest.blight_road"), 0, "an unset flag reads 0")
	s.set_flag("quest.blight_road", 1)
	assert_true(s.has_flag("quest.blight_road"), "a set flag is truthy")
	assert_eq(s.inc_flag("quest.blight_road"), 2, "inc adds one and returns the new value")
	s.set_flag("oakvale.chest.opened", true)
	assert_eq(s.get_flag_int("oakvale.chest.opened"), 1, "true reads as 1 numerically")
	s.set_flag("x", false)
	assert_false(s.has_flag("x"), "false is falsy")
	s.clear_flag("quest.blight_road")
	assert_false(s.has_flag("quest.blight_road"), "cleared")


func test_json_floats_normalize_to_ints() -> void:
	var s := StoryState.new()
	s.set_flag("stage", 3.0)
	assert_true(s.get_flag("stage") is int, "an integral JSON float folds back to int")


func test_conditions_read_flags_party_items_gold() -> void:
	var s := StoryState.new()
	s.set_flag("quest.blight_road", 1)
	s.add_member("vineweave")
	s.add_item("sagebloom_poultice", 2)
	s.gold = 50
	assert_true(ConditionContext.evaluate("flag(\"quest.blight_road\") >= 1", s), "flag compare")
	assert_true(ConditionContext.evaluate("not has(\"oakvale.guard.moved\")", s), "negated has")
	assert_true(ConditionContext.evaluate("party_has(\"vineweave\") and item(\"sagebloom_poultice\") == 2", s), "party + item")
	assert_true(ConditionContext.evaluate("gold() >= 50", s), "gold")
	assert_true(ConditionContext.evaluate("", s), "a blank condition gates nothing")
	assert_false(ConditionContext.evaluate("flag(\"quest.blight_road\") >= 2", s), "false condition")


func test_bad_conditions_are_false_and_flagged_invalid() -> void:
	var s := StoryState.new()
	assert_false(ConditionContext.evaluate("flag(\"a\" >=", s), "a parse error evaluates false (no log)")
	assert_false(ConditionContext.evaluate("nonsense_fn(1)", s), "an unknown function evaluates false")
	assert_false(bool(ConditionContext.check("flag(\"a\" >=").get("valid", true)), "check() reports the parse error")
	assert_false(bool(ConditionContext.check("nonsense_fn(1)").get("valid", true)), "check() reports the unknown call")
	assert_true(bool(ConditionContext.check("has(\"a\") or gold() > 3").get("valid", false)), "a good condition checks valid")


func test_outcome_reads_the_last_result() -> void:
	var s := StoryState.new()
	var r := BattleResult.make("x", BattleResult.OUTCOME_VICTORY)
	assert_true(ConditionContext.evaluate("outcome() == \"victory\"", s, r), "outcome() sees the result")
	assert_false(ConditionContext.evaluate("outcome() == \"victory\"", s, null), "no result -> empty outcome")


func test_member_ids_follow_the_roster_ledger_scheme() -> void:
	var s := StoryState.new()
	var a: StoryPartyMember = s.add_member("petalfang")
	var b: StoryPartyMember = s.add_member("petalfang")
	var c: StoryPartyMember = s.add_member("petalfang")
	assert_eq(a.member_id, "petalfang", "the first of a line is keyed by the line (RosterLedger uid)")
	assert_eq(b.member_id, "petalfang#2", "the second gets #2")
	assert_eq(c.member_id, "petalfang#3", "and #3")
	assert_eq(s.lead(), a, "index 0 is the lead")


func test_party_cap_refuses_extra_members() -> void:
	var s := StoryState.new()
	for i in range(2):
		s.add_member("vineweave", "", 2)
	assert_null(s.add_member("blightcap", "", 2), "a full party refuses a new member")
	assert_eq(s.party.size(), 2, "and stays at the cap")


func test_bag_and_gold() -> void:
	var s := StoryState.new()
	s.add_item("sagebloom_poultice")
	s.add_item("sagebloom_poultice")
	assert_eq(s.item_count("sagebloom_poultice"), 2, "items stack in the bag")
	assert_true(s.take_item("sagebloom_poultice", 2), "taking what you have succeeds")
	assert_false(s.take_item("sagebloom_poultice"), "taking from an empty stack fails")
	s.add_gold(30)
	assert_false(s.take_gold(40), "cannot spend more than you have")
	assert_eq(s.gold, 30, "gold unchanged after a refused spend")
	assert_true(s.take_gold(30), "exact spend works")


func test_wounded_members_are_not_fieldable_until_healed() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("vineweave")
	s.add_member("blightcap")
	m.wounded = true
	m.current_hp = 0
	assert_eq(s.healthy_members().size(), 1, "a wounded member cannot be fielded")
	s.heal_party()
	assert_eq(s.healthy_members().size(), 2, "a heal clears wounds")
	assert_eq(m.current_hp, StoryPartyMember.HP_FULL, "and restores full HP")


func test_actor_positions_persist_or_not() -> void:
	var s := StoryState.new()
	s.set_actor_position("oakvale", "guard", Vector3i(18, 10, 0), "south", true)
	s.set_actor_position("mossway", "bram", Vector3i(19, 5, 0), "south", false)
	assert_false(s.actor_override("oakvale", "guard").is_empty(), "a persisted move is recorded")
	assert_false(s.actor_override("mossway", "bram").is_empty(), "a transient move is recorded")
	s.on_area_changed()
	assert_true(s.actor_override("mossway", "bram").is_empty(), "leaving the area forgets a transient move")
	assert_false(s.actor_override("oakvale", "guard").is_empty(), "but keeps a persisted one")
