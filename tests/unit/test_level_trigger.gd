extends GutTest

## LevelTrigger (docs/design/PROGRESSION.md §6, DECISIONS.md #82): ONE MORE evolution trigger kind,
## met once a story member's level reaches the authored level. Story supplies "level" through the
## member context; open modes have no levels, so there it is unmet (fails closed). Growth edges are
## untouched.

const EvoFixture := preload("res://tests/helpers/evolution_fixture.gd")


func _trigger(n: int) -> LevelTrigger:
	var t := LevelTrigger.new()
	t.level_required = n
	return t


func _edge(triggers: Array) -> EvolutionResource:
	var e := EvolutionResource.new()
	e.id = &"test__level"
	e.from_id = &"tree_grunt"
	e.to_id = &"petalfang"
	var typed: Array[EvolutionTrigger] = []
	for t in triggers:
		typed.append(t)
	e.triggers = typed
	return e


func test_met_at_or_above_the_level() -> void:
	var t := _trigger(16)
	assert_false(t.is_met({"level": 15, "mode": "story"}), "one level short is unmet")
	assert_true(t.is_met({"level": 16, "mode": "story"}), "the level itself is met")
	assert_true(t.is_met({"level": 30, "mode": "story"}), "above it is met")
	assert_eq(t.describe(), "Reach Lv 16", "the checklist text")
	assert_eq(t.progress({"level": 9}), "Lv 9/16", "the checklist progress")


func test_open_modes_never_fire() -> void:
	var t := _trigger(1)
	assert_false(t.is_met({"growth": 99}), "no story level in the context = never met (fails closed)")
	assert_true(t.needs_story(), "it is a story-only requirement")


func test_story_member_context_carries_the_level() -> void:
	var s := StoryState.new()
	var m: StoryPartyMember = s.add_member("tree_grunt", "", 6, 12)
	var ctx: Dictionary = StoryGrowth.member_context(m, {"mode": "story"})
	assert_eq(int(ctx["level"]), 12, "the member context hands the trigger its level")
	var e := _edge([_trigger(12)])
	assert_true(e.is_available(RosterLedger.record_context(m.ledger_record(), m.member_id, ctx)),
		"a Level edge is available at the level")
	m.set_level(11)
	var ctx2: Dictionary = StoryGrowth.member_context(m, {"mode": "story"})
	assert_false(e.is_available(RosterLedger.record_context(m.ledger_record(), m.member_id, ctx2)),
		"and not below it")


func test_answers_battle_events_and_validates_the_cap() -> void:
	var t := _trigger(16)
	assert_true(t.responds_to({"kinds": ["battle"]}), "a battle can raise a level: re-offer after one")
	assert_false(t.responds_to({"kinds": ["area"]}), "walking somewhere cannot")
	assert_eq(t.problem(), "", "a level under the cap is fine")
	assert_ne(_trigger(999).problem(), "", "a level above the cap is a content problem")


func test_the_shipped_item_edge_has_no_level_trigger() -> void:
	var e: EvolutionResource = EvolutionLibrary.get_edge(&"tree_grunt__ember_stump")
	assert_not_null(e, "the shipped Barkling -> Cinderbark (Sunstone) edge exists")
	if e == null:
		return
	var has_level: bool = false
	var has_use: bool = false
	for t in e.triggers:
		has_level = has_level or t is LevelTrigger
		has_use = has_use or t is UseItemTrigger
	assert_false(has_level, "the item edge was not migrated to a level trigger")
	assert_true(has_use, "it still evolves by using the Sunstone")


func test_growth_edges_never_need_a_level() -> void:
	var e: EvolutionResource = EvoFixture.build()   # Growth 3 + 2 wins, no level
	for t in e.triggers:
		assert_false(t is LevelTrigger, "a Growth edge carries no level trigger")
	assert_true(e.is_available({"growth": 3, "feats": {"wins": 2}}),
		"an open-mode context with no level at all still evolves by Growth + wins")
