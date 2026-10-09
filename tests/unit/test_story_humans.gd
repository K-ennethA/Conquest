extends GutTest

## HUMANS IN STORY, the pure rules (docs/design/HUMANS.md; DECISIONS.md #6, #61, #63-#66): the hero
## as a party record, temporary guests, human uniqueness, the duel lineup, the deploy picker's rules
## (SquadPick), weapon swaps, bonds and the bond activation hook, the wild-table validator and the
## promotion audit. No scene tree, no autoloads.


func _state_with_hero() -> StoryState:
	var s := StoryState.new()
	s.add_hero("wren", "Wren", 5)
	return s


# --- The hero record ----------------------------------------------------------------------

func test_hero_is_a_party_record_that_never_takes_a_slot() -> void:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 5)
	var hero := s.add_hero("wren", "Wren", 5)
	assert_not_null(hero)
	assert_true(hero.is_hero)
	assert_eq(s.party[0], hero, "the hero heads the record list")
	assert_eq(s.lead().character_id, "tree_grunt", "the LEAD is the partner creature")
	assert_eq(s.capped_count(), 1)
	assert_eq(s.add_hero("wren"), hero, "one hero only")
	for i in range(5):
		assert_not_null(s.add_member("petalfang", "", 6, 5))
	assert_null(s.add_member("petalfang", "", 6, 5), "cap 6 counts creatures only")
	assert_eq(s.party.size(), 7)


func test_hero_alone_is_the_lead_and_cannot_leave_or_fall() -> void:
	var s := _state_with_hero()
	assert_eq(s.lead(), s.hero_member())
	assert_eq(String(s.remove_member(s.hero_member().member_id)["reason"]), "hero_cannot_leave")
	assert_null(s.mark_fallen(s.hero_member().member_id, {"kind": "battle"}), "the hero never falls (game over instead)")
	assert_eq(s.party.size(), 1)


func test_can_battle_needs_a_partner_unless_the_knob_allows_the_hero_alone() -> void:
	var s := _state_with_hero()
	assert_false(s.can_battle(), "the opening: the hero alone walks past")
	assert_true(s.can_battle(true))
	s.add_member("tree_grunt", "", 6, 5)
	assert_true(s.can_battle())
	s.member("tree_grunt").wounded = true
	assert_false(s.can_battle(), "only the hero standing")


func test_duel_lineup_puts_the_hero_behind_the_partner() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	s.add_member("petalfang", "", 6, 5)
	var ids := func(arr: Array) -> Array:
		return arr.map(func(m): return m.character_id)
	assert_eq(ids.call(s.duel_lineup(1)), ["tree_grunt", "wren", "petalfang"])
	assert_eq(ids.call(s.duel_lineup(0)), ["wren", "tree_grunt", "petalfang"])
	assert_eq(ids.call(s.duel_lineup(9)), ["tree_grunt", "petalfang", "wren"])
	assert_eq(ids.call(s.duel_lineup(-1)), ["wren", "tree_grunt", "petalfang"], "plain party order")


func test_a_temporary_guest_never_fights_the_partys_duels() -> void:
	# DECISIONS.md #61 / #94: a rival keeping the hero company (Lyra in the Deep Woods) deploys in the
	# tactical battle she came for -- never in a wild / trainer / chief duel's lineup.
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	s.join("lyra", "", 6, 5, true, "deepwood.eldroot_beaten")
	var ids := func(arr: Array) -> Array:
		return arr.map(func(m): return m.character_id)
	assert_eq(ids.call(s.duel_lineup(1, false)), ["tree_grunt"], "a creatures' duel: no guest")
	assert_eq(ids.call(s.duel_lineup(1, true)), ["tree_grunt", "wren"], "a hero-required duel: still no guest")
	s.member("tree_grunt").wounded = true
	assert_false(s.can_battle(), "the guest alone does not carry the party into a fight")
	s.member("tree_grunt").wounded = false
	var cands: Array[Dictionary] = SquadPick.candidates(s, BattleRequest.new())
	var lyra: Dictionary = SquadPick.find(cands, s.member("lyra").member_id)
	assert_false(lyra.is_empty(), "she is a candidate in a tactical battle's squad pick")
	assert_true(bool(lyra["guest"]), "shown as a guest")


# --- Joins, guests, uniqueness -----------------------------------------------------------

func test_humans_are_unique_and_guests_leave_on_their_flag() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	var r: Dictionary = s.join("lyra", "", 6, 8, true, "deepwood.eldroot_done")
	var lyra: StoryPartyMember = r["member"]
	assert_not_null(lyra)
	assert_true(lyra.is_temporary())
	assert_eq(String(s.join("lyra", "", 6, 8)["reason"]), "already_in_party", "one Lyra")
	assert_eq(String(s.join("wren")["reason"]), "already_in_party", "the hero is not recruited twice")
	lyra.add_xp(500)
	var lv: int = lyra.level
	s.set_flag("deepwood.eldroot_done", 1)
	assert_null(s.member(lyra.member_id), "the guest left when her flag was set")
	assert_eq(s.guests_away.size(), 1)
	# She comes back for the final battles as the SAME record.
	var back: StoryPartyMember = s.join("lyra", "", 6, 3, true)["member"]
	assert_eq(back, lyra)
	assert_eq(back.level, lv, "level kept (never lowered)")
	assert_true(s.guests_away.is_empty())


func test_a_creature_can_still_join_twice() -> void:
	var s := StoryState.new()
	assert_not_null(s.join("petalfang")["member"])
	assert_not_null(s.join("petalfang")["member"], "species, not individuals")


# --- Weapons and bonds ---------------------------------------------------------------------

func test_equip_weapon_rules() -> void:
	var s := _state_with_hero()
	var v: StoryPartyMember = s.join("varden", "", 6, 10)["member"]
	assert_eq(String(s.equip_weapon(v.member_id, "iron_lance")["reason"]), "")
	assert_eq(v.weapon().weapon_id, &"iron_lance")
	assert_eq(String(s.equip_weapon(v.member_id, "study_tome")["reason"]), "cannot_wield")
	assert_eq(String(s.equip_weapon(v.member_id, "nope")["reason"]), "unknown_weapon")
	assert_true(bool(s.equip_weapon(v.member_id, "iron_sword")["ok"]))
	assert_eq(v.weapon_id, "", "back to his own weapon = no override")
	var g: StoryPartyMember = s.add_member("tree_grunt", "", 6, 5)
	assert_eq(String(s.equip_weapon(g.member_id, "iron_lance")["reason"]), "not_human")


func test_bond_partner_rules() -> void:
	var s := _state_with_hero()
	var hero := s.hero_member()
	var g: StoryPartyMember = s.add_member("tree_grunt", "", 6, 5)
	var v: StoryPartyMember = s.join("varden", "", 6, 10)["member"]
	assert_eq(String(s.set_bond_partner(hero.member_id, v.member_id)["reason"]), "not_creature")
	assert_eq(String(s.set_bond_partner(g.member_id, hero.member_id)["reason"]), "not_human")
	assert_true(bool(s.set_bond_partner(hero.member_id, g.member_id)["ok"]))
	assert_true(bool(s.set_bond_partner(v.member_id, g.member_id)["ok"]))
	assert_eq(hero.bond_partner, "", "a creature bonds with one human at a time")
	assert_eq(v.bond_partner, g.member_id)


func test_new_member_fields_round_trip_a_save() -> void:
	var s := _state_with_hero()
	var g: StoryPartyMember = s.add_member("tree_grunt", "", 6, 5)
	var v: StoryPartyMember = s.join("varden", "", 6, 10, true, "war.over")["member"]
	s.equip_weapon(v.member_id, "iron_lance")
	s.set_bond_partner(v.member_id, g.member_id)
	var c: StoryPartyMember = s.join("cael", "", 6, 9, true)["member"]
	s.remove_member(c.member_id)
	var d: Dictionary = StorySnapshot.to_dict(s)
	var back: Dictionary = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(bool(back.get("success", false)), str(back.get("reason", "")))
	var s2: StoryState = back["state"]
	assert_true(s2.hero_member() != null and s2.hero_member().is_hero)
	var v2: StoryPartyMember = s2.member(v.member_id)
	assert_true(v2.temporary)
	assert_eq(v2.guest_until, "war.over")
	assert_eq(v2.weapon_id, "iron_lance")
	assert_eq(v2.bond_partner, g.member_id)
	assert_eq(s2.guests_away.size(), 1)
	assert_eq(s2.guests_away[0].character_id, "cael")


# --- The deploy picker's rules (SquadPick) ----------------------------------------------

func _tactical(squad: int = 2, hero_required: bool = false, guests: Array = []) -> BattleRequest:
	var r := BattleRequest.new()
	r.kind = BattleRequest.KIND_TACTICAL
	r.squad_size = squad
	if hero_required:
		r.rules["hero_deploy"] = SquadPick.HERO_REQUIRED
	if not guests.is_empty():
		r.rules["offered_guests"] = guests
	return r


func test_candidates_put_the_hero_first_and_list_offered_guests() -> void:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 5)
	s.add_member("petalfang", "", 6, 5)
	s.add_hero("wren", "Wren", 5)
	var cands := SquadPick.candidates(s, _tactical(2, false, ["lyra", "tree_grunt"]))
	assert_eq(cands.map(func(c): return c["character_id"]), ["wren", "tree_grunt", "petalfang", "lyra"],
		"hero first; an offered guest already in the party is not offered twice")
	assert_eq(String(cands[3]["id"]), "guest:lyra")
	assert_false(bool(cands[3]["member"]))
	assert_eq(SquadPick.default_picks(cands, 2), ["wren", "tree_grunt"] as Array[String],
		"no-UI default: hero first, guests only when picked")


func test_without_a_hero_the_default_squad_is_unchanged() -> void:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 5)
	s.add_member("petalfang", "", 6, 5)
	s.add_member("blightcap", "", 6, 5)
	var f := StoryBattleBridge.fielded_members(s, 2)
	assert_eq(f.map(func(m): return m.character_id), ["tree_grunt", "petalfang"])


func test_required_hero_is_locked_and_the_squad_is_capped() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	s.add_member("petalfang", "", 6, 5)
	var cands := SquadPick.candidates(s, _tactical(2, true))
	var picks: Array[String] = SquadPick.default_picks(cands, 2)
	assert_true(picks.has("wren"))
	assert_eq(SquadPick.toggle(picks, "wren", cands, 2), picks, "a required hero cannot be dropped")
	assert_eq(SquadPick.toggle(picks, "petalfang", cands, 2), picks, "full: nothing added")
	var dropped := SquadPick.toggle(picks, "tree_grunt", cands, 2)
	assert_eq(dropped, ["wren"] as Array[String])
	assert_eq(SquadPick.toggle(dropped, "petalfang", cands, 2), ["wren", "petalfang"] as Array[String])
	assert_eq(String(SquadPick.validate(["tree_grunt"], cands, 2)["reason"]), "missing_required:wren")
	assert_eq(String(SquadPick.validate([], cands, 2)["reason"]), "empty")
	assert_true(bool(SquadPick.validate(["wren"], cands, 2)["ok"]))
	# An optional hero may sit out.
	var opt := SquadPick.candidates(s, _tactical(2, false))
	assert_true(bool(SquadPick.validate(["tree_grunt", "petalfang"], opt, 2)["ok"]))


func test_picked_offered_guest_snapshots_as_a_non_member() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 7)
	var req := _tactical(3, false, ["cael"])
	var cands := SquadPick.candidates(s, req)
	var snap: Array = SquadPick.snapshot(s, ["wren", "guest:cael"], cands)
	assert_eq(snap.size(), 2)
	assert_true(bool(snap[0]["hero"]))
	assert_eq(String(snap[1]["member_id"]), "guest:cael")
	assert_true(bool(snap[1]["guest"]))
	assert_eq(int(snap[1]["level"]), 7, "a guest fights at the party's top level")


func test_battle_spec_writes_deploy_rules_only_when_set() -> void:
	var spec := BattleSpec.new()
	var plain := spec.to_request(BattleRequest.SOURCE_SCRIPT, "x")
	assert_false(plain.rules.has("hero_deploy"))
	assert_false(plain.rules.has("offered_guests"))
	spec.hero_deploy = BattleSpec.HeroDeploy.REQUIRED
	var g: Array[StringName] = [&"lyra"]
	spec.offered_guests = g
	var r := spec.to_request(BattleRequest.SOURCE_SCRIPT, "x")
	assert_eq(SquadPick.hero_rule(r), SquadPick.HERO_REQUIRED)
	assert_eq(SquadPick.offered_guests(r), ["lyra"] as Array[String])


func test_hero_down_in_a_real_battle_is_a_game_over() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	var req := BattleRequest.new()
	req.kind = BattleRequest.KIND_DUEL
	req.party = StoryBattleBridge.party_snapshot(s.duel_lineup(1))
	var res := BattleResult.make("x", BattleResult.OUTCOME_DEFEAT)
	res.party_after = [{"member_id": "tree_grunt", "current_hp": 0, "wounded": true, "fought": true},
		{"member_id": "wren", "current_hp": 0, "wounded": true, "fought": true}]
	assert_eq(StoryPermadeath.game_over_reason(s, req, res), StoryPermadeath.REASON_HERO)
	req.rules["spar"] = true
	assert_eq(StoryPermadeath.game_over_reason(s, req, res), "", "a spar only knocks him out")


# --- Bond activation hook -------------------------------------------------------------------

class MockStats:
	var base := {"attack": 20, "defense": 10, "magic": 0, "magic_defense": 5}
	var mods: Dictionary = {}
	var next_id: int = 1
	func get_base_stat(s: String) -> int:
		return int(base.get(s, 0))
	func add_stat_modifier(s: String, amount: int, _duration: int = -1) -> int:
		mods[next_id] = [s, amount]
		next_id += 1
		return next_id - 1
	func remove_stat_modifier(id: int) -> bool:
		return mods.erase(id)

class MockUnit:
	extends Node
	var unit_stats = MockStats.new()


func test_bond_activation_is_off_by_default_and_refreshes() -> void:
	var rules := StoryRuleset.new()
	assert_false(rules.bond_activation_enabled, "OFF by default (balance)")
	var u := MockUnit.new()
	assert_eq(String(StoryBond.activate(u, 5, rules)["reason"]), "disabled")
	rules.bond_activation_enabled = true
	rules.bond_bonus_per_level = 0.1
	var r := StoryBond.activate(u, 2, rules)
	assert_true(bool(r["success"]))
	assert_eq(int(r["bonus"]["attack"]), 4, "20 x 0.1 x bond 2")
	assert_eq(int(r["bonus"]["defense"]), 2)
	assert_false((r["bonus"] as Dictionary).has("magic"), "nothing from a 0 stat")
	StoryBond.activate(u, 2, rules)
	assert_eq(u.unit_stats.mods.size(), 3, "a second activation REFRESHES, never stacks (rule 6)")
	assert_eq(String(StoryBond.activate(u, 0, rules)["reason"]), "no_bond")
	u.free()


func test_can_activate_needs_a_bonded_creature_with_bond() -> void:
	var rules := StoryRuleset.new()
	rules.bond_activation_enabled = true
	var s := _state_with_hero()
	var hero := s.hero_member()
	assert_eq(String(StoryBond.can_activate(s, hero.member_id, rules)["reason"]), "no_partner")
	var g: StoryPartyMember = s.add_member("tree_grunt", "", 6, 5)
	s.set_bond_partner(hero.member_id, g.member_id)
	assert_eq(String(StoryBond.can_activate(s, hero.member_id, rules)["reason"]), "no_bond")
	g.add_bond(100)
	assert_true(bool(StoryBond.can_activate(s, hero.member_id, rules)["ok"]))


func test_humans_earn_no_bond_xp() -> void:
	var s := _state_with_hero()
	s.add_member("tree_grunt", "", 6, 5)
	var res := BattleResult.make("x", BattleResult.OUTCOME_VICTORY)
	res.party_after = [{"member_id": "wren", "fought": true}, {"member_id": "tree_grunt", "fought": true}]
	var bond: Dictionary = StoryProgression.bond_for(s, res, null, {"mode": "story"})
	assert_false(bond.has("wren"))


# --- Content guards -------------------------------------------------------------------------

func test_wild_tables_refuse_humans() -> void:
	var zone := EncounterZone.new()
	var e := EncounterEntry.new()
	e.character_id = &"lyra"
	var table: Array[Resource] = [e]
	zone.table = table
	var issues: Array[String] = []
	zone.validate(issues, "test")
	assert_true(issues.any(func(i): return "HUMAN" in i), str(issues))
	var creature := EncounterEntry.new()
	creature.character_id = &"petalfang"
	var t2: Array[Resource] = [creature]
	zone.table = t2
	var ok: Array[String] = []
	zone.validate(ok, "test")
	assert_false(ok.any(func(i): return "HUMAN" in i))


func test_a_human_promotion_needs_an_item_or_place_and_may_list_specials() -> void:
	var wren := CharacterLibrary.get_character(&"wren")
	var promoted := wren.duplicate(false) as CharacterResource
	promoted.character_id = &"wren_promoted_test"
	promoted.base_health += 20
	var specials: Array[MoveResource] = [load("res://game/combat/moves/cleave.tres")]
	promoted.moveset = specials
	assert_eq(promoted.move_count(), 2, "an 'enhanced' form is just one that lists special moves")
	var lookup := func(id) -> CharacterResource:
		return {&"wren": wren, &"wren_promoted_test": promoted}.get(StringName(id), null)
	var e := EvolutionResource.new()
	e.id = &"wren__promoted"
	e.from_id = &"wren"
	e.to_id = &"wren_promoted_test"
	e.kind_label = "Promote"
	var g := GrowthTrigger.new()
	var t: Array[EvolutionTrigger] = [g]
	e.triggers = t
	var problems: Array[String] = EvolutionGraph.new([e]).validate(lookup, 10.0)
	assert_true(problems.any(func(p): return "#16" in p), str(problems))
	var place := LocationTrigger.new()
	place.area_ids = PackedStringArray(["crownhaven"])
	var t2: Array[EvolutionTrigger] = [g, place]
	e.triggers = t2
	problems = EvolutionGraph.new([e]).validate(lookup, 10.0)
	assert_false(problems.any(func(p): return "#16" in p or "Promote" in p), str(problems))
