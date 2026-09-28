extends GutTest

## THE DUEL'S ITEMS ACTION (docs/design/DECISIONS.md #28): the player uses a battle consumable from
## the side's bag -- the recorded USE_ITEM command through the duel's one apply path. It heals
## (clamped), costs the turn, spends the item, is refused when it would be wasted, is deterministic
## under a pinned seed and replays byte-for-byte; the story gets back what was used and takes it
## from the bag. The HUD's Items button opens the picker and hands the stage the pick.

const SEED := 4242


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	# The HUD repaints rows with queue_free: let them go before the orphan count.
	await get_tree().process_frame


func _request(items: Dictionary = {"mossleaf_tonic": 2, "bitterroot_salve": 1}, hp: int = 30,
		human: bool = true) -> DuelRequest:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight", DuelBrain.NORMAL)
	req.seed = SEED
	req.player_is_ai = not human
	req.player_party[0].current_hp = hp
	req.items = items.duplicate()
	return req


func _battle(req: DuelRequest) -> DuelBattle:
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), "the duel sets up: %s" % str(ok.get("reason", "")))
	battle.start()
	battle.run_to_end()   # AI turns until the human's
	return battle


## The scripted fight: the tonic on the first player turn, then the first ready move every turn.
## Returns {result, hashes}.
func _scripted(seed_value: int) -> Dictionary:
	var req := _request()
	req.seed = seed_value
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	battle.setup(req)
	var hashes: Array[int] = []
	battle.action_resolved.connect(func(rec): hashes.append(int(rec["hash"])))
	battle.start()
	var used: bool = false
	for i in range(200):
		battle.run_to_end()
		if battle.is_over:
			break
		var actor = battle.current_actor()
		if actor == null:
			break
		if battle.must_pass(actor):
			battle.pass_turn()
		elif not used:
			assert_true(bool(battle.use_item("mossleaf_tonic").get("ok", false)), "the tonic is used")
			used = true
		else:
			battle.submit_slot(battle.legal_slots(actor)[0])
	var out := {"result": battle.result, "hashes": hashes}
	battle.teardown()
	return out


func test_using_a_tonic_heals_and_costs_the_turn() -> void:
	var battle := _battle(_request())
	var me = battle.unit_of(0)
	assert_eq(battle.current_actor(), me, "the player's turn")
	assert_true(battle.can_use_items(), "Items is available (the ruleset allows it, the bag holds some)")
	var before: int = int(me.get_hp())
	var max_hp: int = int(me.get_base_stat("health"))
	var rec: Dictionary = battle.use_item("mossleaf_tonic")
	assert_true(bool(rec.get("ok", false)), "the USE_ITEM command applied")
	assert_eq(int(me.get_hp()), mini(max_hp, before + 25), "healed 25 HP (clamped at max)")
	assert_eq(int(rec["cmd"][NetProtocol.KEY_TYPE]), NetProtocol.Action.USE_ITEM, "recorded as USE_ITEM")
	assert_true(battle.result.commands.has(rec["cmd"]), "in the duel's command list (the replay)")
	assert_ne(int(rec["cmd"][NetProtocol.KEY_RNG]), 0, "stamped with its seq seed like any command")
	assert_eq(int(battle.items_left()["mossleaf_tonic"]), 1, "one tonic spent")
	assert_eq(int(battle.result.items_used["mossleaf_tonic"]), 1, "and reported as used")
	if not battle.is_over:
		assert_ne(battle.current_actor(), me, "it cost the turn: the foe acts next")


func test_a_wasted_item_is_refused_and_spends_nothing() -> void:
	var battle := _battle(_request({"mossleaf_tonic": 1, "bitterroot_salve": 1}, -1))
	var me = battle.unit_of(0)
	if battle.current_actor() != me:
		pending("the foe opened and the duel ended before the player's turn")
		return
	var full: bool = int(me.get_hp()) >= int(me.get_base_stat("health"))
	if full:
		assert_eq(String(battle.use_item("mossleaf_tonic")["reason"]), "full_hp", "no heal at full HP")
	assert_eq(String(battle.use_item("bitterroot_salve")["reason"]), "nothing_to_cure", "no poison to cure")
	assert_eq(String(battle.use_item("dawnpetal_draught")["reason"]), "no_item", "an item the side does not hold")
	assert_eq(battle.current_actor(), me, "a refusal keeps the turn")
	assert_true(battle.result.items_used.is_empty(), "nothing was used")
	var opts: Array[Dictionary] = battle.item_options(me)
	assert_eq(opts.size(), 2, "the picker lists both items")
	for o in opts:
		if String(o["item_id"]) == "bitterroot_salve":
			assert_false(bool(o["ok"]), "the salve row is disabled (it would be wasted)")


func test_items_need_the_ruleset_and_a_bag() -> void:
	var battle := _battle(_request({}))
	assert_false(battle.can_use_items(), "an empty bag: no Items action")
	assert_eq(String(battle.use_item("mossleaf_tonic")["reason"]), "no_item", "and nothing to use")
	var off := _request()
	var b2 := DuelBattle.new()
	add_child_autofree(b2)
	b2.setup(off)
	b2.rules = b2.rules.duplicate()
	b2.rules.allow_items = false
	b2.start()
	b2.run_to_end()
	assert_false(b2.can_use_items(), "a ruleset without items: no Items action")
	b2.teardown()
	battle.teardown()


func test_item_use_is_deterministic_and_replays() -> void:
	var a := _scripted(SEED)
	var b := _scripted(SEED)
	var ra: DuelResult = a["result"]
	var rb: DuelResult = b["result"]
	assert_eq(ra.commands, rb.commands, "the same seed: identical command list, the item use included")
	assert_eq(a["hashes"], b["hashes"], "and identical state after every command")
	var types: Array = ra.commands.map(func(c): return int(c[NetProtocol.KEY_TYPE]))
	assert_true(types.has(NetProtocol.Action.USE_ITEM), "the item use is in the recording")
	assert_eq(ra.items_used, {"mossleaf_tonic": 1}, "one tonic used")

	var replay := DuelBattle.new()
	add_child_autofree(replay)
	var req := _request()
	req.foe_is_ai = false
	assert_true(bool(replay.setup(req)["success"]), "a fresh duel for the replay")
	var hashes := replay.replay_commands(ra.commands)
	assert_eq(hashes, a["hashes"], "re-applying the commands reproduces every state")
	assert_eq(replay.result.items_used, ra.items_used, "and the items used")
	replay.teardown()


func test_the_story_gets_back_what_was_used() -> void:
	var br := BattleRequest.new()
	br.kind = BattleRequest.KIND_DUEL
	br.source = BattleRequest.SOURCE_WILD
	br.encounter_id = "mossway.grass.petalfang"
	br.party = [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": 30, "item_id": ""}]
	br.opponent = {"name": "Wild Petalfang", "team": [{"character_id": "petalfang", "strength": 1.0}]}
	br.items = {"mossleaf_tonic": 3, "heartwood_charm": 1, "no_such_item": 2}
	var conv := DuelRequest.from_battle_request(br.to_dict())
	assert_true(bool(conv["success"]), "the duel request builds")
	var dr: DuelRequest = conv["request"]
	assert_eq(dr.items, {"mossleaf_tonic": 3}, "only battle consumables reach the duel")

	var res := DuelResult.new()
	res.outcome = DuelResult.OUTCOME_DEFEAT
	res.items_used = {"mossleaf_tonic": 2}
	res.party_after = [{"member_id": "vineweave", "current_hp": 0, "wounded": true}]
	var result := BattleResult.from_dict(res.to_battle_result())
	assert_eq(result.items_used, {"mossleaf_tonic": 2}, "the battle result carries them")
	var s := StoryState.new()
	s.add_member("vineweave")
	s.add_item("mossleaf_tonic", 3)
	StoryResultApplier.apply(s, br, result, null)
	assert_eq(s.item_count("mossleaf_tonic"), 1, "used items leave the bag whatever the outcome")


func test_a_won_wild_duel_pays_gold_per_foe() -> void:
	var rs := StoryRuleset.new()
	rs.wild_gold_per_foe = 15
	var br := BattleRequest.new()
	br.kind = BattleRequest.KIND_DUEL
	br.source = BattleRequest.SOURCE_WILD
	br.rewards = {"gold": 0}
	var r := BattleResult.make("mossway.grass.petalfang", BattleResult.OUTCOME_VICTORY)
	r.defeated = ["petalfang"]
	var s := StoryState.new()
	var out: Dictionary = StoryResultApplier.apply(s, br, r, rs)
	assert_eq(s.gold, 15, "a wild win pays the ruleset's gold per defeated foe")
	assert_eq(int(out["gold"]), 15, "and reports it")
	br.source = BattleRequest.SOURCE_TRAINER
	br.rewards = {"gold": 120}
	var s2 := StoryState.new()
	StoryResultApplier.apply(s2, br, r, rs)
	assert_eq(s2.gold, 120, "a trainer pays his authored purse (battle_gold_per_foe 0)")


func test_the_hud_items_button_and_picker() -> void:
	var battle := _battle(_request({"mossleaf_tonic": 2, "bitterroot_salve": 1}, 30))
	var me = battle.unit_of(0)
	if battle.current_actor() != me:
		pending("the duel ended before the player's turn")
		return
	var hud := DuelHUD.new()
	add_child_autofree(hud)
	hud.bind(battle)
	hud.show_commands(me)
	var items_btn := hud.find_child("ItemsButton", true, false) as Button
	assert_not_null(items_btn, "the Items button")
	assert_false(items_btn.disabled, "enabled on the player's turn with battle items")
	items_btn.pressed.emit()
	assert_true(hud.items_open(), "Items opens the picker")
	var tonic := hud.find_child("Item_mossleaf_tonic", true, false) as Button
	var salve := hud.find_child("Item_bitterroot_salve", true, false) as Button
	assert_true(tonic != null and salve != null, "a row per item")
	assert_false(tonic.disabled, "the tonic helps")
	assert_true(salve.disabled, "the salve would be wasted (nothing to cure)")
	hud.close_items()
	assert_false(hud.items_open(), "Back returns to the moves")
	items_btn.pressed.emit()
	var picked := {"slot": 0}
	hud.slot_chosen.connect(func(s: int) -> void: picked["slot"] = s)
	tonic.pressed.emit()
	assert_eq(int(picked["slot"]), DuelHUD.ITEM_SLOT, "a pick hands the stage the item slot")
	assert_eq(hud.chosen_item_id, "mossleaf_tonic", "naming the item")
	hud.show_waiting("")
	assert_true(items_btn.disabled, "off-turn the Items button is disabled")
	battle.teardown()
