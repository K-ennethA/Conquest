extends GutTest

## THE DIFFICULTY TIERS, pure (docs/design/DECISIONS.md #29 + "Permadeath refinements";
## StoryPermadeath, StoryState, StoryResultApplier, the snapshot, the consumables):
##   * a tier is chosen per journey and may only move DOWN (Classic -> Casual);
##   * Classic: a member knocked out in a real battle FALLS -- tactical and duel result shapes --
##     kept as a record (form, growth), its item back in the bag, out of every squad / heal /
##     revive / party cap; a SPAR never marks anyone (its KOs get up at 1 HP);
##   * Casual: the knocked-out stay down until revived -- a Wayshrine asks a gold fee per member
##     (ReviveOfferCommand), a whiteout still revives, revive items work but never on the fallen;
##   * the game-over rule: the hero (a stub party entry flagged hero), a protected member, a
##     Classic wipe; spars never end the journey through the hero;
##   * saves: tier + fallen round-trip; a save from before tiers loads as Casual;
##   * ProtectUnit as a GUARD lose condition, and "Protect <name>" map strings.

const Doubles := preload("res://tests/helpers/test_doubles.gd")


class ChoosingHost extends StoryScriptHost:
	var pick: int = 0
	var choices: int = 0

	func show_choice(_prompt: StoryBeat, _options: PackedStringArray, _cancel_index: int = -1) -> int:
		choices += 1
		return pick


class FakeSession extends RefCounted:
	var rs: StoryRuleset
	var saves: int = 0

	func _init(p_rs: StoryRuleset) -> void:
		rs = p_rs

	func ruleset() -> StoryRuleset:
		return rs

	func save_game() -> Dictionary:
		saves += 1
		return {"success": true}


class CharRes extends RefCounted:
	var character_id: StringName = &""


class NamedUnit extends RefCounted:
	var team: int = 0
	var hp: int = 10
	var display_name: String = ""
	var character_resource = null

	func _init(p_team: int, p_hp: int, p_cid: String = "", p_name: String = "") -> void:
		team = p_team
		hp = p_hp
		display_name = p_name
		if not p_cid.is_empty():
			character_resource = CharRes.new()
			character_resource.character_id = StringName(p_cid)


func _state(tier: String = StoryState.TIER_CLASSIC) -> StoryState:
	var s := StoryState.new()
	s.tier = tier
	s.add_member("vineweave")
	s.add_member("blightcap")
	s.set_location("mossway", Vector3i(3, 4, 0), "east")
	return s


func _request(kind: String = BattleRequest.KIND_TACTICAL, policy: String = "whiteout") -> BattleRequest:
	var r := BattleRequest.new()
	r.kind = kind
	r.encounter_id = "trainer.mossway.bram"
	r.source = BattleRequest.SOURCE_TRAINER
	r.rules = {"defeat_policy": policy}
	r.opponent = {"name": "Bram", "team": []}
	r.backdrop = {"area_id": "mossway"}
	r.party = [{"member_id": "vineweave", "character_id": "vineweave"},
		{"member_id": "blightcap", "character_id": "blightcap"}]
	return r


func _result(outcome: String, rows: Array) -> BattleResult:
	var res := BattleResult.make("trainer.mossway.bram", outcome)
	res.party_after = rows
	return res


func _ruleset() -> StoryRuleset:
	var rs := StoryRuleset.new()
	rs.revive_fee_per_member = 50
	return rs


# --- Tiers --------------------------------------------------------------------------------

func test_a_tier_only_ever_moves_down() -> void:
	var s := StoryState.new()
	assert_eq(s.tier, StoryState.TIER_CASUAL, "an unset journey is Casual")
	s.tier = StoryState.TIER_CLASSIC
	assert_true(s.is_classic(), "Classic")
	assert_true(s.can_lower_tier_to(StoryState.TIER_CASUAL), "Classic may lower to Casual")
	assert_eq(s.lower_tier("hardcore")["reason"], "unknown_tier", "an unknown tier is refused")
	assert_eq(s.lower_tier(StoryState.TIER_CLASSIC)["reason"], "same_tier", "the same tier is no change")
	assert_true(bool(s.lower_tier(StoryState.TIER_CASUAL)["ok"]), "lowering works")
	assert_eq(s.tier, StoryState.TIER_CASUAL, "now Casual")
	var up: Dictionary = s.lower_tier(StoryState.TIER_CLASSIC)
	assert_false(bool(up["ok"]), "never back up")
	assert_eq(up["reason"], "cannot_raise", "with the reason")
	assert_eq(s.tier, StoryState.TIER_CASUAL, "still Casual")


# --- Classic: falling -----------------------------------------------------------------------

func test_classic_tactical_knockouts_fall_with_their_record_and_item() -> void:
	var s := _state()
	var vine: StoryPartyMember = s.member("vineweave")
	vine.item_id = "heartwood_charm"
	vine.add_growth(4)
	vine.nickname = "Ivy"
	var res := _result(BattleResult.OUTCOME_VICTORY, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true},
		{"member_id": "blightcap", "current_hp": 20, "wounded": false, "fought": true}])
	var out: Dictionary = StoryResultApplier.apply(s, _request(), res, _ruleset())
	assert_eq(out["fallen"], ["vineweave"], "the knocked-out member fell")
	assert_null(s.member("vineweave"), "it left the party")
	var f: StoryPartyMember = s.fallen_member("vineweave")
	assert_not_null(f, "kept as a fallen record")
	if f == null:
		return
	assert_true(f.is_fallen(), "marked fallen")
	assert_eq(f.character_id, "vineweave", "its form kept")
	assert_eq(f.growth_points(), 4, "its growth kept")
	assert_eq(f.nickname, "Ivy", "its name kept")
	assert_eq(f.item_id, "", "its item is off")
	assert_eq(s.item_count("heartwood_charm"), 1, "and back in the bag")
	assert_eq(String(f.fallen_info["item_id"]), "heartwood_charm", "the record remembers what it wore")
	assert_eq(String(f.fallen_info["area_id"]), "mossway", "where it fell")
	assert_eq(String(f.fallen_info["foe"]), "Bram", "against whom")
	assert_eq(s.healthy_members().size(), 1, "out of every squad and duel")
	assert_eq(s.healthy_members()[0].member_id, "blightcap", "only the survivor is fieldable")
	assert_false(f.is_fieldable(), "a fallen member is never fieldable")
	assert_eq(StoryBattleBridge.fielded_members(s, 3).size(), 1, "the tactical squad leaves it out")


func test_classic_duel_lead_that_fainted_falls_and_the_bench_does_not() -> void:
	var s := _state()
	var res := _result(BattleResult.OUTCOME_DEFEAT, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true},
		{"member_id": "blightcap", "current_hp": -1, "wounded": false, "fought": false}])
	var out: Dictionary = StoryResultApplier.apply(s, _request(BattleRequest.KIND_DUEL), res, _ruleset())
	assert_eq(out["fallen"], ["vineweave"], "the lead that fainted fell")
	assert_not_null(s.member("blightcap"), "the bench (never fought) is untouched")
	assert_true(bool(out["whiteout"]), "the loss still whites out")
	assert_false(s.member("blightcap").wounded, "and the living are rested")


func test_the_fallen_are_never_healed_revived_or_counted_against_the_cap() -> void:
	var s := _state()
	s.mark_fallen("vineweave", {"kind": "tactical"})
	s.heal_party()
	assert_true(s.fallen_member("vineweave").is_fallen(), "a rest does not bring the fallen back")
	assert_eq(s.fallen_member("vineweave").current_hp, 0, "nor heal it")
	var again: StoryPartyMember = s.add_member("vineweave")
	assert_eq(again.member_id, "vineweave#2", "a new recruit never inherits a fallen member's uid")
	for i in range(4):
		s.add_member("petalfang")
	assert_eq(s.party.size(), 6, "the fallen do not take a party slot")


func test_a_spar_never_marks_anyone_fallen() -> void:
	var s := _state()
	var req := _request(BattleRequest.KIND_DUEL, "continue")
	req.rules["spar"] = true
	var res := _result(BattleResult.OUTCOME_DEFEAT, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true}])
	var out: Dictionary = StoryResultApplier.apply(s, req, res, _ruleset())
	assert_eq((out["fallen"] as Array).size(), 0, "nobody falls in a spar, even in Classic")
	assert_eq(out["spar_recovered"], ["vineweave"], "its knocked-out get back up")
	var m: StoryPartyMember = s.member("vineweave")
	assert_false(m.wounded, "not knocked out")
	assert_eq(m.current_hp, 1, "at 1 HP")
	# The knob off: a spar KO is an ordinary knock-out (still never a fall).
	var s2 := _state()
	var rs := _ruleset()
	rs.spar_ko_recovers = false
	var out2: Dictionary = StoryResultApplier.apply(s2, req, res, rs)
	assert_eq((out2["fallen"] as Array).size(), 0, "still nobody falls")
	assert_true(s2.member("vineweave").wounded, "the KO stays down with the knob off")


func test_casual_knockouts_stay_down_and_never_fall() -> void:
	var s := _state(StoryState.TIER_CASUAL)
	var res := _result(BattleResult.OUTCOME_VICTORY, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true},
		{"member_id": "blightcap", "current_hp": 20, "wounded": false, "fought": true}])
	var out: Dictionary = StoryResultApplier.apply(s, _request(), res, _ruleset())
	assert_eq((out["fallen"] as Array).size(), 0, "Casual: nobody falls")
	assert_true(s.member("vineweave").wounded, "knocked out until revived")
	assert_eq(s.knocked_out_members().size(), 1, "one to revive")


func test_a_whiteout_revives_the_knocked_out_unless_the_knob_says_no() -> void:
	var s := _state(StoryState.TIER_CASUAL)
	var res := _result(BattleResult.OUTCOME_DEFEAT, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true}])
	StoryResultApplier.apply(s, _request(), res, _ruleset())
	assert_false(s.member("vineweave").wounded, "a whiteout wakes everyone at the Wayshrine")
	var s2 := _state(StoryState.TIER_CASUAL)
	var rs := _ruleset()
	rs.whiteout_revives = false
	StoryResultApplier.apply(s2, _request(), res, rs)
	assert_true(s2.member("vineweave").wounded, "whiteout_revives off: still knocked out")


# --- Casual: the Wayshrine's gold revive -----------------------------------------------------

func test_the_revive_quote_charges_casual_per_member() -> void:
	var s := _state(StoryState.TIER_CASUAL)
	s.gold = 120
	s.member("vineweave").wounded = true
	s.member("blightcap").wounded = true
	var q: Dictionary = StoryPermadeath.revive_quote(s, _ruleset())
	assert_eq(int(q["count"]), 2, "two knocked out")
	assert_eq(int(q["total"]), 100, "50 gold each")
	assert_true(bool(q["costs_gold"]) and bool(q["affordable"]), "affordable")
	assert_false(bool(q["pity"]), "no pity while it can be paid")
	s.gold = 10
	var broke: Dictionary = StoryPermadeath.revive_quote(s, _ruleset())
	assert_false(bool(broke["affordable"]), "10 gold is not enough")
	assert_true(bool(broke["pity"]), "but nobody can fight: the shrine takes pity")
	s.tier = StoryState.TIER_CLASSIC
	assert_false(bool(StoryPermadeath.revive_quote(s, _ruleset())["costs_gold"]),
		"Classic never charges (only spar KOs are down)")


func test_a_casual_rest_heals_the_living_only_and_the_shrine_revives_for_gold() -> void:
	var s := _state(StoryState.TIER_CASUAL)
	s.gold = 100
	s.member("vineweave").wounded = true
	s.member("blightcap").current_hp = 5
	var session := FakeSession.new(_ruleset())
	var host := ChoosingHost.new()
	var ctx := ScriptContext.new(s, host, session, "oakvale")
	await StoryScriptRunner.run_list([HealPartyCommand.new()], ctx)
	assert_eq(s.member("blightcap").current_hp, StoryPartyMember.HP_FULL, "the living rest for free")
	assert_true(s.member("vineweave").wounded, "the knocked-out wait for the fee")
	host.pick = 1
	await StoryScriptRunner.run_list([ReviveOfferCommand.new()], ctx)
	assert_eq(host.choices, 1, "the shrine asks")
	assert_true(s.member("vineweave").wounded, "Not now: still down")
	assert_eq(s.gold, 100, "and no gold taken")
	host.pick = 0
	await StoryScriptRunner.run_list([ReviveOfferCommand.new()], ctx)
	assert_false(s.member("vineweave").wounded, "paid: revived")
	assert_eq(s.member("vineweave").current_hp, StoryPartyMember.HP_FULL, "to full")
	assert_eq(s.gold, 50, "for 50 gold")
	assert_eq(session.saves, 1, "and the journey saved")
	assert_eq(int(ctx.vars["revived"]), 1, "one got up")


func test_a_classic_rest_revives_spar_knockouts_for_free() -> void:
	var s := _state(StoryState.TIER_CLASSIC)
	s.member("vineweave").wounded = true
	var ctx := ScriptContext.new(s, ChoosingHost.new(), FakeSession.new(_ruleset()), "oakvale")
	await StoryScriptRunner.run_list([HealPartyCommand.new()], ctx)
	assert_false(s.member("vineweave").wounded, "no fee in Classic")


# --- Revive items refuse the fallen ----------------------------------------------------------

func test_revive_items_work_in_both_tiers_but_never_on_the_fallen() -> void:
	var revive: ItemResource = ItemLibrary.get_item("dawnpetal_draught")
	assert_not_null(revive, "the shipped revive item")
	if revive == null:
		return
	var s := _state(StoryState.TIER_CASUAL)
	s.member("blightcap").wounded = true
	s.add_item("dawnpetal_draught", 2)
	assert_true(bool(s.use_consumable("dawnpetal_draught", "blightcap")["ok"]), "Casual: a revive raises the knocked-out")
	var c := _state(StoryState.TIER_CLASSIC)
	c.add_item("dawnpetal_draught", 1)
	c.mark_fallen("vineweave", {"kind": "duel"})
	var f: StoryPartyMember = c.fallen_member("vineweave")
	assert_eq(revive.consumable.check_member(f)["reason"], "fallen", "check_member refuses a fallen member")
	assert_eq(c.use_consumable("dawnpetal_draught", "vineweave")["reason"], "fallen", "the bag refuses it too")
	assert_eq(c.item_count("dawnpetal_draught"), 1, "and nothing is spent")
	assert_true(ConsumableEffect.reason_text("fallen", "Vineweave").contains("fallen"), "with words for it")
	var tonic: ItemResource = ItemLibrary.get_item("mossleaf_tonic")
	assert_eq(tonic.consumable.check_member(f)["reason"], "fallen", "a heal refuses the fallen as well")


# --- Game over -------------------------------------------------------------------------------

func test_the_hero_falling_is_always_a_game_over() -> void:
	var s := _state(StoryState.TIER_CASUAL)
	s.member("vineweave").is_hero = true
	var req := _request(BattleRequest.KIND_DUEL)
	req.party = StoryBattleBridge.party_snapshot([s.member("vineweave")])
	assert_eq(req.hero_member_ids(), ["vineweave"], "the hero flag rides the party snapshot")
	var rows: Array = [{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true}]
	var res := _result(BattleResult.OUTCOME_DEFEAT, rows)
	assert_eq(StoryPermadeath.game_over_reason(s, req, res, _ruleset()), StoryPermadeath.REASON_HERO, "the hero fell")
	res.game_over_reason = StoryPermadeath.REASON_HERO
	var hp_before: int = s.member("vineweave").current_hp
	var out: Dictionary = StoryResultApplier.apply(s, req, res, _ruleset())
	assert_false(bool(out["whiteout"]), "a game over is never applied")
	assert_eq(s.member("vineweave").current_hp, hp_before, "nothing changes")
	var spar := _request(BattleRequest.KIND_DUEL)
	spar.party = req.party
	spar.rules["spar"] = true
	assert_eq(StoryPermadeath.game_over_reason(s, spar, _result(BattleResult.OUTCOME_DEFEAT, rows), _ruleset()), "",
		"a friendly spar only knocks the hero out")
	var won := _result(BattleResult.OUTCOME_VICTORY, [
		{"member_id": "vineweave", "current_hp": 30, "wounded": false, "fought": true}])
	assert_eq(StoryPermadeath.game_over_reason(s, req, won, _ruleset()), "", "a standing hero is no game over")
	assert_true(StoryPermadeath.game_over_text(StoryPermadeath.REASON_HERO, "Wren").begins_with("Wren has fallen"),
		"the card names the hero")


func test_a_protected_member_falling_is_a_game_over_in_both_tiers() -> void:
	for tier in StoryState.TIERS:
		var s := _state(tier)
		var req := _request(BattleRequest.KIND_DUEL)
		req.rules["protect"] = ["Blightcap"]
		var res := _result(BattleResult.OUTCOME_DEFEAT, [
			{"member_id": "blightcap", "current_hp": 0, "wounded": true, "fought": true}])
		assert_eq(StoryPermadeath.game_over_reason(s, req, res, _ruleset()), "protect:Blightcap",
			"%s: the protected member fell" % tier)
	assert_true(StoryPermadeath.game_over_text("protect:Elias").begins_with("Elias has fallen"), "the card names them")


func test_a_classic_wipe_is_a_game_over_behind_its_knob() -> void:
	var s := StoryState.new()
	s.tier = StoryState.TIER_CLASSIC
	s.add_member("vineweave")
	var req := _request(BattleRequest.KIND_DUEL)
	req.party = [{"member_id": "vineweave", "character_id": "vineweave"}]
	var res := _result(BattleResult.OUTCOME_DEFEAT, [
		{"member_id": "vineweave", "current_hp": 0, "wounded": true, "fought": true}])
	assert_eq(StoryPermadeath.game_over_reason(s, req, res, _ruleset()), StoryPermadeath.REASON_WIPE,
		"Classic: nobody would be left")
	var rs := _ruleset()
	rs.classic_wipe_is_game_over = false
	assert_eq(StoryPermadeath.game_over_reason(s, req, res, rs), "", "knob off: a whiteout with nobody left")
	s.tier = StoryState.TIER_CASUAL
	assert_eq(StoryPermadeath.game_over_reason(s, req, res, _ruleset()), "", "Casual never wipes out")


# --- Saves ---------------------------------------------------------------------------------

func test_tier_and_fallen_round_trip_and_old_saves_load_casual() -> void:
	var s := _state(StoryState.TIER_CLASSIC)
	s.member("blightcap").item_id = "heartwood_charm"
	s.member("vineweave").is_hero = true
	s.mark_fallen("blightcap", {"area_id": "mossway", "foe": "Bram", "kind": "tactical", "play_seconds": 65})
	var data: Dictionary = JSON.parse_string(JSON.stringify(StorySnapshot.to_dict(s)))
	var back: Dictionary = StorySnapshot.from_dict(data)
	assert_true(bool(back["success"]), "loads")
	var t: StoryState = back["state"]
	assert_eq(t.tier, StoryState.TIER_CLASSIC, "the tier round-trips")
	assert_eq(t.fallen.size(), 1, "the fallen record round-trips")
	assert_null(t.member("blightcap"), "still out of the party")
	var f: StoryPartyMember = t.fallen_member("blightcap")
	assert_not_null(f, "found by id")
	if f == null:
		return
	assert_eq(String(f.fallen_info["foe"]), "Bram", "with where / when")
	assert_eq(int(f.fallen_info["play_seconds"]), 65, "the play time")
	assert_true(t.member("vineweave").is_hero, "the hero flag round-trips")
	assert_eq(t.item_count("heartwood_charm"), 1, "the returned item is in the saved bag")
	# A version-2 save from before tiers existed: no "tier", no "fallen".
	data.erase("tier")
	data.erase("fallen")
	var old: Dictionary = StorySnapshot.from_dict(data)
	assert_true(bool(old["success"]), "an older save still loads")
	assert_eq((old["state"] as StoryState).tier, StoryState.TIER_CASUAL, "as Casual (it had no permadeath)")
	assert_eq((old["state"] as StoryState).fallen.size(), 0, "with nobody fallen")
	data["tier"] = "nightmare"
	assert_eq((StorySnapshot.from_dict(data)["state"] as StoryState).tier, StoryState.TIER_CASUAL,
		"an unknown tier loads as Casual")


# --- Battle data -----------------------------------------------------------------------------

func test_spar_and_protect_ride_the_spec_request_and_result() -> void:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	var team: Array[Dictionary] = [{"character_id": "gem_knight", "strength": 0.8}]
	spec.opponent_team = team
	spec.spar = true
	var names: Array[String] = ["Elias", "gem_knight"]
	spec.protect = names
	var r: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT, "x.spar")
	assert_true(r.is_spar(), "the request is a spar")
	assert_eq(r.protect_targets(), names, "and names who to protect")
	r.party = [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": -1}]
	var back: BattleRequest = BattleRequest.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_true(back.is_spar(), "round-trips")
	assert_eq(back.protect_targets(), names, "both")
	var dr: Dictionary = DuelRequest.from_battle_request(r.to_dict())
	assert_true(bool(dr["success"]), "the duel accepts it (%s)" % String(dr.get("reason", "")))
	if bool(dr["success"]):
		assert_true((dr["request"] as DuelRequest).is_spar(), "and hears it's a spar (its intro says so)")
	var res := BattleResult.make("x", BattleResult.OUTCOME_DEFEAT)
	res.spar = true
	res.game_over_reason = "protect:Elias"
	var rb: BattleResult = BattleResult.from_dict(JSON.parse_string(JSON.stringify(res.to_dict())))
	assert_true(rb.spar, "the result carries the spar tag")
	assert_true(rb.is_game_over(), "and the game-over reason")


# --- ProtectUnit -----------------------------------------------------------------------------

func test_protect_unit_matches_by_meta_character_or_name_and_faction() -> void:
	var by_meta := Doubles.ObjectiveUnit.new(0, 30)
	by_meta.set_meta(&"story_member_id", "vineweave")
	var p := ProtectUnit.make("vineweave", "Ivy", 0)
	assert_eq(p.evaluate({"units": [by_meta]}), WinCondition.Status.ONGOING, "the member lives")
	by_meta.hp = 0
	assert_eq(p.evaluate({"units": [by_meta]}), WinCondition.Status.FAILED, "the member fell")
	assert_eq(p.evaluate({"units": []}), WinCondition.Status.FAILED, "gone from the board = fell")
	var guest := NamedUnit.new(0, 40, "gem_knight", "Geode")
	var foe_geode := NamedUnit.new(1, 0, "gem_knight", "Geode")
	var by_cid := ProtectUnit.make("gem_knight", "", 0)
	assert_eq(by_cid.evaluate({"units": [guest, foe_geode]}), WinCondition.Status.ONGOING,
		"an enemy of the same species is not the escort")
	var by_name := ProtectUnit.make("geode", "Geode", 0)
	assert_eq(by_name.evaluate({"units": [guest]}), WinCondition.Status.ONGOING, "matched by display name")
	guest.hp = 0
	assert_eq(by_name.evaluate({"units": [guest]}), WinCondition.Status.FAILED, "and its fall")
	assert_eq(by_name.describe(), "Keep Geode alive", "described by its label")
	assert_true(by_name.is_guard(), "a guard")


func test_a_guard_lose_condition_failing_is_a_defeat() -> void:
	var rules := GameModeRules.new()
	var win := DefeatAllEnemies.new()
	win.faction = 0
	rules.win_conditions = [win]
	var guard := ProtectUnit.make("vip", "VIP", 0)
	rules.lose_conditions = [guard]
	var vip := Doubles.ObjectiveUnit.new(0, 50, &"vip")
	var foe := Doubles.ObjectiveUnit.new(1, 50)
	assert_eq(rules.evaluate({"units": [vip, foe]}), GameModeRules.Outcome.ONGOING, "escort alive, foe standing")
	foe.hp = 0
	assert_eq(rules.evaluate({"units": [vip, foe]}), GameModeRules.Outcome.VICTORY, "the guard never blocks a win")
	vip.hp = 0
	assert_eq(rules.evaluate({"units": [vip, foe]}), GameModeRules.Outcome.DEFEAT, "the escort fell: defeat first")
	# A NON-guard lose condition reporting FAILED is not a defeat (the old contract).
	var rules2 := GameModeRules.new()
	var win2 := DefeatAllEnemies.new()
	win2.faction = 0
	rules2.win_conditions = [win2]
	var st := SurviveTurns.new()
	st.faction = 0
	st.turns = 5
	st.require_survivor = true
	rules2.lose_conditions = [st]
	var alive := Doubles.ObjectiveUnit.new(1, 50)
	assert_eq(rules2.evaluate({"units": [alive], "turn": 1}), GameModeRules.Outcome.ONGOING,
		"only a GUARD's FAILED loses")


func test_protect_strings_compile_to_the_lose_side() -> void:
	var rules: GameModeRules = WinConditionLibrary.build_rules(["Defeat Boss", "Protect Elias"])
	assert_eq(rules.win_conditions.size(), 1, "Protect is not a way to win")
	assert_true(rules.win_conditions[0] is DefeatBoss, "the boss is")
	var guards: Array = []
	for c in rules.lose_conditions:
		if c is ProtectUnit:
			guards.append(c)
	assert_eq(guards.size(), 1, "one guard on the lose side")
	if guards.is_empty():
		return
	assert_eq(String((guards[0] as ProtectUnit).protected_id), "Elias", "for Elias")
	assert_eq((guards[0] as ProtectUnit).faction, WinConditionLibrary.HUMAN_FACTION, "on the player's side")
	assert_eq(WinConditionLibrary.protect_target("Protect: Tam"), "Tam", "the colon form")
	assert_eq(WinConditionLibrary.protect_target("Protectorate"), "", "a word that merely starts with protect is not one")
	var only: GameModeRules = WinConditionLibrary.build_rules(["Protect Elias"])
	assert_true(only.win_conditions[0] is DefeatAllEnemies, "protect alone still needs a way to win: rout the enemy")
	assert_true(WinConditionLibrary.rules_are_map_authored(only), "and counts as an authored objective")
	var lines: PackedStringArray = ObjectiveText.detail_lines(rules)
	assert_true(lines.has("Defeat: Elias falls"), "the Objective page lists the guard (%s)" % str(lines))
	assert_eq(ObjectiveBanner.guard_text_for(guards), "Protect Elias", "the banner's tag")
