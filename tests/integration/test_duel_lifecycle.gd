extends GutTest

## The combat core's lifecycle rules, unchanged inside a duel (docs/design/DUEL_BATTLE.md
## §10): Braced expires at the owner's next turn start, Prism Bulwark switches to its alt
## mode after its guard, Firstward's opening ward lands once, cooldowns are booked through the
## applier, a flinch skips exactly one turn, an ultimate announces its cut-in, the struggle is
## offered when nothing is ready -- and a wild victory surfaces the befriend offer (with the
## subdue bonus when the foe was subdued).


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _battle(a: StringName = &"vineweave", b: StringName = &"gem_knight", seed_value: int = 31,
		kind: String = DuelRequest.KIND_STANDALONE) -> DuelBattle:
	var req := DuelRequest.standalone(a, b)
	req.seed = seed_value
	req.kind = kind
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	battle.start()
	return battle


func _slot(unit, move_id: StringName) -> int:
	for i in range(unit.character_resource.move_count()):
		if unit.get_move(i).move_id == move_id:
			return i
	return -1


func _has(unit, id: StringName) -> bool:
	return unit.get_status_controller().has_status(id)


func test_braced_lasts_until_the_owners_next_turn() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	b.submit_slot(_slot(vw, &"thornward"))
	assert_true(_has(vw, &"braced"), "Thornward braces Vineweave through Geode's turn")
	b.pass_turn()  # Geode
	assert_eq(b.current_actor(), vw)
	assert_false(_has(vw, &"braced"), "and it expires as Vineweave's next turn opens")


func test_prism_bulwark_turns_into_its_release_after_the_guard() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	var bulwark: MoveResource = geode.get_move(_slot(geode, &"prism_bulwark"))
	b.pass_turn()  # R1 Vineweave
	b.submit_slot(_slot(geode, &"prism_bulwark"))
	assert_true(_has(geode, &"prism_guard"), "the guard is up")
	vw.get_move(_slot(vw, &"bramble_cleave")).accuracy = 1.0  # private copy: no miss roll in this test
	b.submit_slot(_slot(vw, &"bramble_cleave"))  # R2: hit the guard
	assert_true(_has(geode, &"reprisal_charge"), "Reprisal stores the blow")
	assert_false(bulwark.is_alt_mode(geode), "still the guard while it holds")
	b.pass_turn()  # R2 Geode
	b.pass_turn()  # R3 Vineweave
	assert_eq(b.current_actor(), geode)
	assert_false(_has(geode, &"prism_guard"), "the guard dropped at Geode's turn start")
	assert_true(bulwark.is_alt_mode(geode), "Prism Bulwark is now the release")
	assert_eq(DuelBrain.aim_for(geode, vw, b.board, _slot(geode, &"prism_bulwark")), b.board.station(0),
		"aimed at the foe, not at itself")
	var hp_before: int = vw.get_hp()
	var rec := b.submit_slot(_slot(geode, &"prism_bulwark"))
	assert_true(bool(rec.get("ok", false)), "the release resolves")
	assert_lt(vw.get_hp(), hp_before, "and hits Vineweave")


func test_firstward_opens_with_its_ward_once() -> void:
	var b := _battle()
	var geode = b.unit_of(1)
	var opening: int = geode.get_shield()
	assert_gt(opening, 0, "Geode takes the field sheathed in its ward")
	b.pass_turn()
	b.pass_turn()
	b.pass_turn()
	assert_true(b.turn_system._battle_start_dispatched, "the battle-start pass ran once and latched")


func test_cooldowns_are_booked_through_the_applier() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var slot := _slot(vw, &"splinter_volley")
	var move: MoveResource = vw.get_move(slot)
	b.submit_slot(slot)
	var mc = vw.get_moveset_controller()
	assert_eq(int(mc.remaining(move)), move.cooldown, "the cast booked its cooldown")
	b.pass_turn()  # Geode -> round 2
	assert_false(slot in b.legal_slots(vw), "not ready next turn")
	var again := b.submit_slot(slot)
	assert_false(bool(again.get("ok", true)), "a slot on cooldown is refused (a value, not an error)")
	assert_eq(String(again.get("reason", "")), "slot_unavailable")


func test_flinch_skips_exactly_one_turn() -> void:
	var b := _battle()
	var geode = b.unit_of(1)
	var flinch: StatusCondition = (load("res://game/combat/status/flinched.tres") as StatusCondition).duplicate(true)
	geode.get_status_controller().add_status(flinch)
	b.pass_turn()  # Vineweave
	assert_eq(b.current_actor(), geode)
	assert_true(b.must_pass(geode), "the flinched Geode must pass")
	assert_eq(String(b.submit_slot(0).get("reason", "")), "must_pass")
	b.pass_turn()
	b.pass_turn()  # Vineweave, round 2
	assert_eq(b.current_actor(), geode)
	assert_false(b.must_pass(geode), "only one turn was lost")


func test_ultimate_announces_its_cut_in_and_the_struggle_does_not() -> void:
	var b := _battle()
	var vw = b.unit_of(0)
	var geode = b.unit_of(1)
	watch_signals(GameEvents)
	var roots := b.submit_slot(_slot(vw, &"strangling_roots"))
	assert_signal_emit_count(GameEvents, "ultimate_casting", 1, "the ultimate plays its cut-in")
	var ensnared := false
	for e in roots["result"]["events"]:
		if String(e.get("status", "")) == "ensnared" and bool(e.get("applied", false)):
			ensnared = true
	assert_true(ensnared, "and ensnares (inert in duels, but it still lands)")
	var mc = geode.get_moveset_controller()
	for i in range(geode.character_resource.move_count()):
		mc.cooldown_started(geode.get_move(i), 5)
	assert_eq(b.legal_slots(geode), [DuelCharacter.STRUGGLE_SLOT] as Array[int],
		"nothing ready: Desperate Strike is offered")
	var hp_before: int = vw.get_hp()
	var rec := b.submit_slot(DuelCharacter.STRUGGLE_SLOT)
	assert_true(bool(rec.get("ok", false)), "the struggle is an ordinary USE_MOVE")
	assert_lt(vw.get_hp(), hp_before)
	assert_signal_emit_count(GameEvents, "ultimate_casting", 1, "no cut-in for the struggle")


func test_wild_victory_offers_to_join_from_the_seeded_stream() -> void:
	var b := _battle(&"monster", &"petalfang", 5, DuelRequest.KIND_WILD)
	var duskmaw = b.unit_of(0)
	var claw := _slot(duskmaw, &"umbral_claw")
	var runs := 0
	while not b.is_over and runs < 20:
		if b.current_actor() == duskmaw and claw in b.legal_slots(duskmaw):
			b.submit_slot(claw)
		else:
			b.pass_turn()
		runs += 1
	assert_true(b.is_over)
	assert_eq(b.result.outcome, DuelResult.OUTCOME_VICTORY)
	var offer := b.result.befriend_offer
	assert_eq(String(offer.get("character_id", "")), "petalfang")
	assert_almost_eq(float(offer["chance"]), b.rules.join_chance(false), 0.0001)
	assert_false(bool(offer["subdued"]))
	assert_false(bool(offer["accepted"]), "M1 has no acceptance flow; StoryController decides")
	var br := b.result.to_battle_result()
	assert_true(br.has("befriend_offer"), "surfaced on the BattleResult shape")
	assert_eq(br["defeated"], ["petalfang"])
	assert_eq(bool(offer["offered"]), b.result.befriend_line() != "")


func test_subdued_wild_foe_gets_the_bonus() -> void:
	var b := _battle(&"monster", &"petalfang", 5, DuelRequest.KIND_WILD)
	var duskmaw = b.unit_of(0)
	var petal = b.unit_of(1)
	var claw := _slot(duskmaw, &"umbral_claw")
	# The duel copy is private (rule 7): make its claw a subduing strike for this cast.
	var dmg: DamageEffect = null
	for e in duskmaw.get_move(claw).effects:
		if e is DamageEffect:
			dmg = e
	dmg.subdue = true
	var hit := false
	var runs := 0
	while not b.is_over and runs < 30:
		if b.current_actor() == duskmaw and claw in b.legal_slots(duskmaw):
			b.submit_slot(claw)
			if petal.get_hp() == 1:
				hit = true
				dmg.subdue = false  # the next claw finishes it
		else:
			b.pass_turn()
		runs += 1
	assert_true(hit, "the subdue claw left Petalfang on exactly 1 HP")
	assert_eq(b.result.outcome, DuelResult.OUTCOME_VICTORY)
	var offer := b.result.befriend_offer
	assert_true(bool(offer["subdued"]), "the subdue is remembered to the end")
	assert_almost_eq(float(offer["chance"]), b.rules.join_chance(true), 0.0001)


func test_no_offer_outside_wild_duels() -> void:
	var b := _battle(&"monster", &"petalfang", 5, DuelRequest.KIND_TRAINER)
	var duskmaw = b.unit_of(0)
	var claw := _slot(duskmaw, &"umbral_claw")
	var runs := 0
	while not b.is_over and runs < 20:
		if b.current_actor() == duskmaw and claw in b.legal_slots(duskmaw):
			b.submit_slot(claw)
		else:
			b.pass_turn()
		runs += 1
	assert_eq(b.result.outcome, DuelResult.OUTCOME_VICTORY)
	assert_true(b.result.befriend_offer.is_empty(), "a trainer's unit never offers to join")
