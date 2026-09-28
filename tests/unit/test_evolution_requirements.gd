extends GutTest

## EVOLUTION REQUIREMENTS (docs/design/DECISIONS.md #26, EVOLUTION.md §3.2a): every requirement
## type -- met / unmet / progress / describe --, the ALL semantics of an edge, open-mode
## degradation (story requirements are unmet outside story unless the edge skips them),
## auto-offer relevance, the promotion words, the validator, and the battle-feat maths.
## Pure: requirements are handed context dictionaries; nothing touches disk or autoload state.


func _edge(reqs: Array, skip_story: bool = false) -> EvolutionResource:
	var e := EvolutionResource.new()
	e.id = &"test__edge"
	e.from_id = &"tree_grunt"
	e.to_id = &"oakheart"
	var typed: Array[EvolutionTrigger] = []
	for r in reqs:
		typed.append(r)
	e.triggers = typed
	e.skip_story_requirements_outside_story = skip_story
	return e


func _growth(n: int) -> GrowthTrigger:
	var t := GrowthTrigger.new()
	t.growth_required = n
	return t


func _wins(n: int) -> BattleFeatTrigger:
	var t := BattleFeatTrigger.new()
	t.feat = BattleFeatTrigger.Feat.WINS
	t.count = n
	return t


func _location(areas: Array, region: String = "") -> LocationTrigger:
	var t := LocationTrigger.new()
	t.area_ids = PackedStringArray(areas)
	t.region_id = region
	return t


# --- Each requirement type ------------------------------------------------------------

func test_growth_requirement() -> void:
	var t := _growth(3)
	assert_false(t.is_met({"growth": 2}), "Growth 2 of 3 is unmet")
	assert_true(t.is_met({"growth": 3}), "Growth 3 meets it")
	assert_eq(t.describe(), "Growth 3", "describes itself")
	assert_eq(t.progress({"growth": 2}), "2/3", "progress toward the goal")
	assert_eq(t.progress({"growth": 9}), "3/3", "progress is capped at the goal")
	assert_false(t.needs_story(), "works in every mode")
	assert_true(t.responds_to({"kinds": ["battle"]}), "a battle can change it")
	assert_false(t.responds_to({"kinds": ["area"]}), "an area change cannot")


func test_battle_feat_requirements() -> void:
	var feats := {"wins": 1, "kos": 4, "clutch_wins": 0, "element_kos": {"dark": 2}}
	var wins := _wins(2)
	assert_false(wins.is_met({"feats": feats}), "1 win of 2")
	assert_eq(wins.progress({"feats": feats}), "1/2", "progress in wins")
	assert_eq(wins.describe(), "Win 2 battles with it", "reads as a feat")
	assert_true(wins.is_met({"feats": {"wins": 2}}), "2 wins meet it")
	var kos := BattleFeatTrigger.new()
	kos.feat = BattleFeatTrigger.Feat.KOS
	kos.count = 3
	assert_true(kos.is_met({"feats": feats}), "4 KOs meet 3")
	assert_eq(kos.describe(), "Land 3 KOs", "KO text")
	var dark := BattleFeatTrigger.new()
	dark.feat = BattleFeatTrigger.Feat.ELEMENT_KOS
	dark.count = 2
	dark.element = "dark"
	assert_true(dark.is_met({"feats": feats}), "2 dark KOs meet it")
	assert_eq(dark.describe(), "KO 2 Dark foes", "element KO text")
	dark.element = "nature"
	assert_false(dark.is_met({"feats": feats}), "no nature KOs")
	var clutch := BattleFeatTrigger.new()
	clutch.feat = BattleFeatTrigger.Feat.CLUTCH_WINS
	assert_false(clutch.is_met({"feats": feats}), "no clutch win yet")
	assert_string_contains(clutch.describe(), "%d%% HP" % roundi(EvolutionRules.current().clutch_hp_ratio * 100.0),
		"the clutch threshold comes from evolution_rules.tres")
	assert_false(wins.is_met({}), "no feats in the context = unmet, never an error")
	assert_true(wins.responds_to({"kinds": ["battle"]}), "a battle can change a feat")


func test_held_item_requirement() -> void:
	var t := HeldItemTrigger.new()
	t.item_id = "heartwood_charm"
	assert_true(t.is_met({"held_item": "heartwood_charm"}), "met while worn")
	assert_false(t.is_met({"held_item": "ironbark_sigil"}), "another item is not it")
	assert_false(t.is_met({}), "nothing worn")
	assert_eq(t.describe(), "Hold %s" % ItemLibrary.get_item(&"heartwood_charm").display_name, "names the item")
	assert_false(t.needs_story(), "open modes can hold items too (ItemInventory)")
	assert_eq(t.problem(), "", "a real item validates")
	t.item_id = "no_such_item"
	assert_ne(t.problem(), "", "an unknown item is a content problem")


func test_use_item_requirement() -> void:
	var t := UseItemTrigger.new()
	t.item_id = "sunstone"
	assert_false(t.is_met({"bag": {"sunstone": 2}}), "owning it is not using it")
	assert_true(t.is_met({"used_item": "sunstone"}), "met at the moment it is used")
	assert_false(t.is_met({"used_item": "heartwood_charm"}), "another item does nothing")
	assert_eq(t.progress({"bag": {"sunstone": 2}}), "2 in bag", "progress = what the bag holds")
	assert_eq(t.progress({"bag": {}}), "none in bag", "or that it holds none")
	assert_eq(t.describe(), "Use Sunstone", "names the item")
	assert_eq(t.used_item_id(), "sunstone", "reports the item it uses")
	assert_true(t.needs_story(), "the bag is story-only")
	assert_eq(t.problem(), "", "the shipped example catalyst validates")


func test_location_requirement() -> void:
	var t := _location(["crownhaven"])
	assert_true(t.is_met({"area_id": "crownhaven"}), "met in the area")
	assert_false(t.is_met({"area_id": "mossway"}), "not elsewhere")
	assert_false(t.is_met({}), "no area outside story")
	var crown := OverworldAreaResource.load_by_id("crownhaven")
	assert_eq(t.describe(), "Be at %s" % crown.display_name, "names the area")
	t.place_label = "the Crownhaven barracks"
	assert_eq(t.describe(), "Be at the Crownhaven barracks", "or the authored place")
	assert_eq(t.progress({"area_id": "crownhaven"}), "here now", "progress says you are there")
	var region := _location([], "greenwold")
	assert_true(region.is_met({"area_id": "anywhere", "region_id": "greenwold"}), "a region matches any of its areas")
	assert_true(t.needs_story(), "a story requirement")
	assert_true(t.responds_to({"kinds": ["area"]}), "entering an area can change it")
	assert_ne(_location([]).problem(), "", "no area and no region is a content problem")


func test_weather_requirement() -> void:
	var ids: Array = Weather.all_ids()
	var wid: String = ""
	for id in ids:
		if String(id) != "clear":
			wid = String(id)
			break
	assert_ne(wid, "", "a non-clear weather ships")
	var t := WeatherTrigger.new()
	t.weathers = PackedStringArray([wid])
	assert_true(t.is_met({"weather": wid}), "met in that weather")
	assert_false(t.is_met({"weather": "clear"}), "not in clear skies")
	assert_eq(t.describe(), "During %s" % Weather.get_weather(StringName(wid)).display_name, "names the weather")
	assert_true(t.needs_story(), "menus have no current weather outside story")


func test_knows_move_requirement() -> void:
	var bark: CharacterResource = CharacterLibrary.get_character(&"tree_grunt")
	var move: MoveResource = bark.moveset[0]
	var t := KnowsMoveTrigger.new()
	t.move_id = move.move_id
	assert_true(t.is_met({"form": &"tree_grunt"}), "Barkling knows its own move")
	var other_knows := false
	for m in CharacterLibrary.get_character(&"gem_knight").moveset:
		if m != null and m.move_id == move.move_id:
			other_knows = true
	assert_eq(t.is_met({"form": &"gem_knight"}), other_knows, "read off the form's roster moveset")
	assert_eq(t.describe(), "Knows %s" % move.display_name, "names the move")
	assert_false(t.needs_story(), "works in every mode")


func test_story_flag_requirement() -> void:
	var t := StoryFlagTrigger.new()
	t.flag = "shrine.cleansed"
	assert_true(t.is_met({"story_flags": {"shrine.cleansed": true}}), "met once set")
	assert_false(t.is_met({"story_flags": {}}), "unmet while unset")
	assert_false(t.is_met({}), "unmet outside story")
	assert_eq(t.describe(), "Story: shrine.cleansed", "default text")
	t.label = "Cleanse the shrine"
	assert_eq(t.describe(), "Cleanse the shrine", "authored text")
	assert_true(t.responds_to({"kinds": ["flag"], "flags": ["shrine.cleansed"]}), "its flag changing")
	assert_false(t.responds_to({"kinds": ["flag"], "flags": ["other.flag"]}), "another flag is not news")


func test_party_has_requirement() -> void:
	var t := PartyHasTrigger.new()
	t.character_id = "petalfang"
	var party := [{"member_id": "tree_grunt", "character_id": "tree_grunt", "line": "tree_grunt"},
		{"member_id": "petalfang", "character_id": "petalfang", "line": "petalfang"}]
	assert_true(t.is_met({"uid": "tree_grunt", "party_members": party}), "a Petalfang travels with it")
	assert_false(t.is_met({"uid": "petalfang", "party_members": party}), "a member never counts itself")
	assert_false(t.is_met({"uid": "tree_grunt"}), "no party outside story")
	var line := PartyHasTrigger.new()
	line.character_id = "tree_grunt"
	var oak := [{"member_id": "tree_grunt", "character_id": "oakheart", "line": "tree_grunt"}]
	assert_true(line.is_met({"uid": "x", "party_members": oak}), "a line id matches any of its forms")
	assert_string_contains(t.describe(), "Petalfang", "names the companion")
	assert_true(t.needs_story(), "a story requirement")
	assert_true(t.responds_to({"kinds": ["party"]}), "a join can change it")


# --- The edge: ALL semantics, checklist, degradation ----------------------------------

func test_every_requirement_must_be_met() -> void:
	var e := _edge([_growth(3), _wins(2)])
	assert_false(e.is_available({"growth": 3, "feats": {"wins": 1}}), "Growth alone is not enough")
	assert_false(e.is_available({"growth": 2, "feats": {"wins": 5}}), "nor wins alone")
	assert_true(e.is_available({"growth": 3, "feats": {"wins": 2}}), "both together are")
	assert_eq(e.unmet_count({"growth": 3, "feats": {"wins": 1}}), 1, "one requirement missing")
	assert_eq(e.describe_triggers(), "Growth 3 + Win 2 battles with it", "the requirement text joins with +")
	assert_eq(e.growth_goal(), 3, "the Growth goal")
	var none := _edge([])
	assert_false(none.is_available({"growth": 99}), "no requirements = never available out of battle")
	var holey := _edge([_growth(0)])
	holey.triggers.append(null)
	assert_false(holey.is_available({"growth": 5}), "an empty slot fails closed")


func test_the_checklist_rows() -> void:
	var e := _edge([_growth(3), _wins(2)])
	var rows: Array[Dictionary] = e.requirement_rows({"growth": 3, "feats": {"wins": 1}})
	assert_eq(rows.size(), 2, "one row per requirement")
	assert_eq(rows[0]["text"], "Growth 3", "in authored order")
	assert_true(bool(rows[0]["met"]), "Growth is met")
	assert_eq(rows[0]["progress"], "3/3", "with progress")
	assert_false(bool(rows[1]["met"]), "the wins are not")
	assert_eq(rows[1]["progress"], "1/2", "1 of 2")


func test_story_requirements_are_unmet_in_open_modes_unless_the_edge_skips_them() -> void:
	var strict := _edge([_growth(1), _location(["crownhaven"])])
	var open_ctx := {"growth": 1}
	var story_ctx := {"growth": 1, "mode": "story", "area_id": "crownhaven"}
	assert_false(strict.is_available(open_ctx), "open modes: a Location requirement is unmet")
	assert_true(strict.is_available(story_ctx), "story: met in the right area")
	var lenient := _edge([_growth(1), _location(["crownhaven"])], true)
	assert_true(lenient.is_available(open_ctx), "an opted-in edge IGNORES it outside story")
	assert_false(lenient.is_available({"growth": 1, "mode": "story", "area_id": "mossway"}),
		"but still needs it inside story")
	var rows := lenient.requirement_rows(open_ctx)
	assert_true(bool(rows[1]["skipped"]), "the checklist marks it skipped")
	assert_false(bool(rows[1]["met"]), "and not met")
	assert_eq(lenient.unmet_count(open_ctx), 0, "a skipped requirement never counts as missing")


func test_edges_respond_to_the_events_their_requirements_watch() -> void:
	var e := _edge([_growth(1), _location(["crownhaven"])])
	assert_true(e.responds_to({"kinds": ["battle"]}), "Growth watches battles")
	assert_true(e.responds_to({"kinds": ["area"]}), "Location watches area changes")
	assert_false(e.responds_to({"kinds": ["flag"], "flags": ["x"]}), "nothing here watches flags")


func test_use_item_edges_name_and_spend_their_item() -> void:
	var use := UseItemTrigger.new()
	use.item_id = "sunstone"
	var keep := UseItemTrigger.new()
	keep.item_id = "heartwood_charm"
	keep.consume = false
	var e := _edge([use, keep])
	assert_eq(e.use_item_ids(), PackedStringArray(["sunstone", "heartwood_charm"]), "the items it uses")
	assert_eq(e.consumed_items("sunstone"), PackedStringArray(["sunstone"]), "a consumed item is spent")
	assert_eq(e.consumed_items("heartwood_charm"), PackedStringArray(), "a reusable one is not")


func test_promotion_words() -> void:
	var e := _edge([_growth(1)])
	assert_eq(e.verb(), "Evolve", "default: an evolution")
	assert_eq(e.progressive_text(), "is evolving...", "evolving")
	e.kind_label = "Promote"
	assert_true(e.is_promotion(), "a class promotion")
	assert_eq(e.verb(), "Promote", "PROMOTE button")
	assert_eq(e.progressive_text(), "is being promoted...", "the ribbon")
	assert_eq(e.past_text(), "was promoted to", "the reveal")
	assert_eq(e.noun(), "promotion", "the noun")


func test_the_validator_reports_bad_requirements() -> void:
	var bad := _edge([_location([]), _wins(0)])
	bad.kind_label = "Transmute"
	var g := EvolutionGraph.new([bad])
	var lookup := func(cid) -> CharacterResource: return CharacterLibrary.get_character(cid)
	var problems: Array[String] = g.validate(lookup, 1.75)
	var text := "\n".join(problems)
	assert_string_contains(text, "names no area", "an empty Location")
	assert_string_contains(text, "asks for 0", "a zero feat count")
	assert_string_contains(text, "kind_label", "an unknown kind label")


func test_the_shipped_barkling_edge_needs_growth_and_wins() -> void:
	EvolutionLibrary.rescan()
	var e: EvolutionResource = EvolutionLibrary.get_edge(&"tree_grunt__oakheart")
	assert_eq(e.triggers.size(), 2, "two requirements")
	assert_eq(e.describe_triggers(), "Growth 3 + Win 2 battles with it", "Growth 3 + 2 wins")
	assert_false(e.is_available({"growth": 3}), "Growth alone no longer evolves it")
	assert_true(e.is_available({"growth": 3, "feats": {"wins": 2}}), "Growth 3 + 2 wins does")


func test_example_edges_load_and_validate() -> void:
	var sun := load("res://tests/helpers/evolution_examples/example_sunstone.tres") as EvolutionResource
	var promo := load("res://tests/helpers/evolution_examples/example_location_promotion.tres") as EvolutionResource
	assert_not_null(sun, "the UseItem example loads")
	assert_not_null(promo, "the Location promotion example loads")
	assert_eq(sun.use_item_ids(), PackedStringArray(["sunstone"]), "uses the Sunstone")
	assert_true(promo.is_promotion(), "the promotion example reads as a promotion")
	var lookup := func(cid) -> CharacterResource: return CharacterLibrary.get_character(cid)
	var problems: Array[String] = EvolutionGraph.new([sun, promo]).validate(lookup, 99.0)
	for p in problems:
		assert_false(p.contains("requirement"), "no requirement problem: %s" % p)


# --- Battle feats maths ---------------------------------------------------------------

func test_compute_feats_counts_wins_kos_elements_and_clutch() -> void:
	var rules := EvolutionRules.new()
	rules.clutch_hp_ratio = 0.25
	var rows := [
		{"uid": "a", "alive": true, "kos": 2, "element_kos": {"dark": 2}, "hp_ratio": 0.2},
		{"uid": "b", "alive": false, "kos": 1, "element_kos": {"nature": 1}, "hp_ratio": 0.0},
		{"uid": "c", "alive": true, "kos": 0, "hp_ratio": 0.9},
	]
	var won: Dictionary = GrowthTracker.compute_feats(rows, true, rules)
	assert_eq(int(won["a"]["wins"]), 1, "a survivor of a win counts the win")
	assert_eq(int(won["a"]["clutch_wins"]), 1, "at 20% HP it is a clutch win")
	assert_eq(int(won["a"]["kos"]), 2, "its KOs")
	assert_eq(int(won["a"]["element_kos"]["dark"]), 2, "by element")
	assert_eq(int(won["b"]["wins"]), 1, "a fallen member still fought in the win")
	assert_eq(int(won["b"]["clutch_wins"]), 0, "but a fallen member is no clutch win")
	assert_eq(int(won["c"]["clutch_wins"]), 0, "90% HP is no clutch win")
	var lost: Dictionary = GrowthTracker.compute_feats(rows, false, rules)
	assert_false(lost.has("c"), "nothing to add for a KO-less member of a loss")
	assert_eq(int(lost["a"]["wins"]), 0, "a loss is no win")
	assert_eq(int(lost["a"]["kos"]), 2, "but its KOs still count")


func test_feat_rows_sharing_a_member_merge() -> void:
	var rows := [{"uid": "tree_grunt", "alive": true, "kos": 3, "hp_ratio": 1.0},
		{"uid": "tree_grunt", "alive": false, "kos": 3, "hp_ratio": 0.0}]
	var f: Dictionary = GrowthTracker.compute_feats(rows, true, EvolutionRules.new())
	assert_eq(int(f["tree_grunt"]["wins"]), 1, "one win per member, not per unit")
	assert_eq(int(f["tree_grunt"]["kos"]), 3, "KOs are per member already: never doubled")


# --- Records: hold + feats ------------------------------------------------------------

func test_feats_normalize_and_apply() -> void:
	var rec := {"feats": {"wins": 2.0, "kos": "x", "element_kos": {"dark": 1, "": 4, "fire": -2}}}
	var n: Dictionary = RosterLedger.normalize_feats(rec["feats"])
	assert_eq(int(n["wins"]), 2, "JSON floats read as ints")
	assert_eq(int(n["kos"]), 0, "junk reads as zero")
	assert_eq(n["element_kos"], {"dark": 1}, "blank and negative element entries are dropped")
	RosterLedger.apply_feats(rec, {"wins": 1, "element_kos": {"dark": 2, "nature": 1}})
	assert_eq(int(rec["feats"]["wins"]), 3, "wins add up")
	assert_eq(rec["feats"]["element_kos"], {"dark": 3, "nature": 1}, "element KOs add up per element")


func test_story_member_hold_and_feats_round_trip() -> void:
	var m := StoryPartyMember.create("tree_grunt", "tree_grunt")
	m.hold = true
	m.add_feats({"wins": 2, "kos": 1})
	var back := StoryPartyMember.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	assert_true(back.hold, "Hold round-trips")
	assert_eq(int(back.feats()["wins"]), 2, "feat counters round-trip")
	assert_eq(int(back.ledger_record()["feats"]["kos"]), 1, "and reach the ledger record")
	var old := StoryPartyMember.from_dict({"member_id": "tree_grunt", "character_id": "tree_grunt",
		"growth": {"growth": 3}})
	assert_false(old.hold, "an older save (no 'hold') loads with Hold off")
	assert_eq(int(old.feats()["wins"]), 0, "and zero feats")


func test_story_state_drains_flag_and_party_changes() -> void:
	var s := StoryState.new()
	s.set_flag("a", true)
	s.set_flag("a", true)
	s.inc_flag("b")
	s.add_member("tree_grunt")
	var ch: Dictionary = s.drain_changes()
	assert_eq(ch["flags"], ["a", "b"], "each changed flag once, in order")
	assert_true(bool(ch["party"]), "a member joined")
	assert_false(s.has_changes(), "drained")
	s.set_flag("a", true)
	assert_false(s.has_changes(), "setting a flag to the value it has is not a change")
	s.set_flag("a", 1)
	assert_true(s.has_changes(), "a different value (type) is")


# --- Items --------------------------------------------------------------------------

func test_catalysts_are_never_equipment() -> void:
	var sun: ItemResource = ItemLibrary.get_item(&"sunstone")
	assert_not_null(sun, "the example catalyst ships")
	assert_true(sun.catalyst, "flagged as a catalyst")
	assert_true(ItemLibrary.catalysts().has(sun), "listed as a catalyst")
	for r in [ItemResource.Rarity.COMMON, ItemResource.Rarity.RARE, ItemResource.Rarity.EPIC]:
		assert_false(ItemLibrary.items_of_rarity(r).has(sun), "never in a drop pool")
	for sc in [ItemResource.Scope.UNIT, ItemResource.Scope.TEAM]:
		assert_false(ItemLibrary.items_with_scope(sc).has(sun), "never in an equip picker")
