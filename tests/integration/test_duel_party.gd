extends GutTest

## PARTY DUELS, the engine (docs/design/DUEL_BATTLE.md §4.2, DECISIONS.md #3): a [DuelFormat]
## team per side -- a lead on the station, the rest benched.
##   * a SWITCH costs the switching side's turn and resolves in its own speed slot; the
##     newcomer never acts again that round (both when the faster and the slower side switches);
##   * a KO'd lead's owner must PICK its replacement before anything else (free, immediate, the
##     newcomer waits for the next round); with ko_replacement off the next member enters by itself;
##   * a side with nobody left standing loses; faints are all recorded (party_after, defeated);
##   * what survives a switch-out: HP, cooldowns (frozen on the bench), poison -- battle buffs,
##     debuffs and shields are cleared;
##   * a 3v3 AI duel under a seed replays byte-for-byte (commands, HP of every member, hashes);
##   * DuelBrain switches out of a bad matchup at NORMAL (never at EASY) and picks the
##     best-matched replacement.

const POISON_PATH := "res://game/combat/status/poisoned.tres"


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _trio() -> DuelFormat:
	return DuelFormat.preset(DuelFormat.TRIO)


## A human-vs-human (both sides driven by the test) party duel.
func _battle(a: Array, b: Array, f: DuelFormat = null, seed_value: int = 77) -> DuelBattle:
	var req := DuelRequest.teams(a, b, f if f != null else _trio())
	req.kind = DuelRequest.KIND_VERSUS
	req.seed = seed_value
	req.player_is_ai = false
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	battle.start()
	return battle


## A damaging slot the acting unit is certain to land (100% forecast hit).
func _sure_hit(b: DuelBattle):
	var actor = b.current_actor()
	for slot in b.legal_slots(actor):
		var move: MoveResource = actor.get_move(slot)
		if move.targeting_for(actor).target_kind == CombatTypes.TargetKind.SELF:
			continue
		var f: Dictionary = MoveExecutor.preview_vs(move, actor, b.foe_of(actor), b.board)
		if float(f.get("hit_pct", 0.0)) >= 100.0 and int(f.get("damage", 0)) > 0:
			return slot
	return -1


# --- Switching --------------------------------------------------------------------------

func test_a_switch_costs_the_faster_sides_turn_and_the_newcomer_waits() -> void:
	var b := _battle(["vineweave", "gem_knight", "petalfang"], ["gem_knight", "blightcap", "petalfang"])
	var vw = b.unit_of(0)
	assert_eq(b.current_actor(), vw, "Vineweave (SPD 12) opens round 1")
	assert_true(b.can_switch(vw), "Trio allows switching")
	var foe_hp: int = int(b.unit_of(1).get_hp())
	var rec := b.submit_switch(1)
	assert_true(bool(rec["ok"]), "the switch applies")
	assert_eq(int(rec["cmd"][NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH, "a recorded SWITCH command")
	var geode = b.unit_of(0)
	assert_ne(geode, vw, "Geode took the station")
	assert_eq(b.active_index(0), 1)
	assert_false(vw.visible, "Vineweave is benched (hidden)")
	assert_false(vw in b.board.all_units(), "and invisible to the board")
	assert_eq(int(b.unit_of(1).get_hp()), foe_hp, "switching dealt nothing")
	assert_eq(b.current_actor(), b.unit_of(1), "the switch SPENT side A's turn: side B acts")
	assert_eq(b.round_number(), 1)
	assert_true(bool(b.submit_slot(b.legal_slots(b.current_actor())[0])["ok"]), "side B acts")
	assert_eq(b.round_number(), 2, "the round closed: the newcomer never acted in round 1")
	assert_true(b.result.commands.size() == 2, "exactly two commands")


func test_the_slower_side_switches_in_its_own_speed_slot() -> void:
	var b := _battle(["vineweave", "gem_knight"], ["gem_knight", "monster"], _trio())
	assert_eq(b.current_actor(), b.unit_of(0), "Vineweave first")
	b.pass_turn()
	assert_eq(b.side_of(b.current_actor()), 1, "then side B (Geode, SPD 8)")
	var rec := b.submit_switch(1)
	assert_true(bool(rec["ok"]))
	assert_eq(b.round_number(), 2, "B's switch was its whole round-1 turn")
	assert_eq(String(b.unit_of(1).character_resource.character_id), "monster")
	assert_eq(b.current_actor(), b.unit_of(1), "round 2: Monster (SPD 14) now outpaces Vineweave (12)")


func test_illegal_switches_are_refused_and_spend_nothing() -> void:
	var b := _battle(["vineweave", "gem_knight"], ["gem_knight", "blightcap"])
	assert_eq(String(b.submit_switch(0)["reason"]), NetProtocol.INTENT_ILLEGAL_SWITCH, "the fielded unit cannot come in")
	assert_eq(String(b.submit_switch(5)["reason"]), NetProtocol.INTENT_ILLEGAL_SWITCH, "no such member")
	assert_eq(b.switch_problem(1, 1, false), NetProtocol.INTENT_NOT_YOUR_TURN, "the waiting side may not switch")
	assert_eq(String(b.choose_replacement(0, 1)["reason"]), NetProtocol.INTENT_ILLEGAL_SWITCH, "no replacement is pending")
	assert_eq(b.result.commands.size(), 0, "nothing applied")
	var singles := _battle(["vineweave"], ["gem_knight"], DuelFormat.preset(DuelFormat.SINGLES))
	assert_false(singles.can_switch(singles.unit_of(0)), "Singles has no bench")
	var no_switch := _trio()
	no_switch.allow_switch = false
	var locked := _battle(["vineweave", "gem_knight"], ["gem_knight", "blightcap"], no_switch)
	assert_eq(String(locked.submit_switch(1)["reason"]), NetProtocol.INTENT_NO_SWITCHING, "a format without switching")


# --- KO replacement + the end ---------------------------------------------------------------

func test_a_ko_makes_the_owner_pick_a_replacement_first() -> void:
	var b := DuelRequest.teams(["vineweave", "gem_knight"], ["petalfang", "blightcap", "tree_grunt"], _trio())
	b.kind = DuelRequest.KIND_VERSUS
	b.seed = 5
	b.player_is_ai = false
	b.foe_is_ai = false
	b.foe_party[0].current_hp = 1
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	assert_true(bool(battle.setup(b)["success"]))
	var needed := []
	battle.replacement_needed.connect(func(side): needed.append(side))
	battle.start()
	var slot = _sure_hit(battle)
	assert_ne(slot, -1, "Vineweave has a sure hit")
	battle.submit_slot(slot)
	assert_eq(needed, [1], "side B must pick")
	assert_true(battle.is_pending(1))
	assert_null(battle.current_actor(), "nobody acts while the pick is pending")
	assert_eq(String(battle.submit_slot(0)["reason"]), "no_actor", "no move in the meantime")
	assert_eq(String(battle.choose_replacement(1, 0)["reason"]), NetProtocol.INTENT_ILLEGAL_SWITCH, "not the fainted lead")
	assert_eq(String(battle.choose_replacement(0, 1)["reason"]), NetProtocol.INTENT_ILLEGAL_SWITCH, "not the other side")
	var rec := battle.choose_replacement(1, 2)
	assert_true(bool(rec["ok"]), "the pick applies")
	assert_true(bool(rec["switch"]["replacement"]), "recorded as a KO replacement")
	assert_eq(String(battle.unit_of(1).character_resource.character_id), "tree_grunt", "Tree Grunt came in")
	assert_eq(battle.round_number(), 2, "free and immediate: the round closed, the newcomer waits for round 2")
	assert_eq(battle.current_actor(), battle.unit_of(0), "round 2 opens in speed order")
	assert_false(battle.is_over)
	var view := battle.team_view(1)
	assert_true(bool(view[0]["fainted"]), "the lead reads fainted")
	assert_true(bool(view[2]["active"]), "the newcomer is on the station")


func test_ai_picks_and_a_side_with_nobody_left_loses() -> void:
	var req := DuelRequest.teams(["vineweave", "gem_knight", "petalfang"], ["tree_grunt", "undead"], _trio())
	req.seed = 9
	req.player_is_ai = true
	req.foe_is_ai = true
	for c in req.foe_party:
		c.strength = 0.2
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	var res := b.run_to_end()
	assert_not_null(res, "the AI duel finishes (replacement picks included)")
	assert_eq(res.winner_side, 0, "side B ran out of members")
	assert_true(b.is_side_out(1))
	assert_eq(res.defeated.size(), 2, "both foes were KO'd")
	assert_eq(int(res.stats[0]["kos"]), 2)
	var replacements := res.commands.filter(func(c): return int(c[NetProtocol.KEY_TYPE]) == NetProtocol.Action.SWITCH)
	assert_gte(replacements.size(), 1, "side B's replacement was a recorded pick")
	assert_eq(res.party_after.size(), 3, "every player member reported")


func test_without_ko_replacement_the_next_member_enters_by_itself() -> void:
	var f := _trio()
	f.ko_replacement = false
	var req := DuelRequest.teams(["vineweave"], ["petalfang", "blightcap", "tree_grunt"], f)
	req.kind = DuelRequest.KIND_VERSUS
	req.seed = 5
	req.player_is_ai = false
	req.foe_is_ai = false
	req.foe_party[0].current_hp = 1
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	b.start()
	b.submit_slot(_sure_hit(b))
	assert_false(b.has_pending_replacement(), "no pick")
	assert_eq(String(b.unit_of(1).character_resource.character_id), "blightcap", "the next member in team order")
	assert_eq(b.result.commands.size(), 1, "and no command: nothing was chosen")


func test_party_after_marks_every_member_that_fainted() -> void:
	var req := DuelRequest.teams(["vineweave", "gem_knight", "petalfang", "oakheart"], ["monster", "undead"], _trio())
	req.seed = 21
	req.player_is_ai = true
	req.foe_is_ai = true
	for c in req.player_party:
		c.strength = 0.15
	for c in req.foe_party:
		c.strength = 3.0
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	var res := b.run_to_end()
	assert_not_null(res)
	assert_eq(res.outcome, DuelResult.OUTCOME_DEFEAT)
	for i in 3:
		var row: Dictionary = res.party_after[i]
		assert_true(bool(row["fought"]), "team member %d took the field" % i)
		assert_true(bool(row["wounded"]), "team member %d fainted (Classic marks it fallen)" % i)
		assert_eq(int(row["current_hp"]), 0)
	assert_false(bool(res.party_after[3]["fought"]), "a party member past the team size never fought")
	assert_false(bool(res.party_after[3]["wounded"]))
	var br := BattleResult.from_dict(res.to_battle_result())
	assert_eq(StoryPermadeath.downed_members(br).size(), 3, "all three switched-in / lead members are downed")


# --- What survives the bench ----------------------------------------------------------

func test_switching_out_keeps_hp_poison_and_cooldowns_but_clears_battle_buffs() -> void:
	var b := _battle(["vineweave", "gem_knight"], ["gem_knight", "blightcap"])
	var vw = b.unit_of(0)
	# Vineweave uses a move with a cooldown, then takes some poison and a buff.
	var cd_slot := -1
	for s in b.legal_slots(vw):
		if vw.get_move(s).cooldown > 0 and vw.get_move(s).targeting_for(vw).target_kind != CombatTypes.TargetKind.SELF:
			cd_slot = s
			break
	assert_ne(cd_slot, -1, "Vineweave has a cooldown move")
	b.submit_slot(cd_slot)
	b.pass_turn()  # side B
	assert_eq(b.current_actor(), vw, "round 2")
	var cd_move: MoveResource = vw.get_move(cd_slot)
	var cooldown_before: int = int(vw.get_moveset_controller().remaining(cd_move))
	assert_gt(cooldown_before, 0, "on cooldown")
	vw.get_status_controller().add_status((load(POISON_PATH) as StatusCondition).duplicate())
	vw.add_stat_modifier("attack", 5, 3)
	vw.grant_shield(10)
	var atk_buffed: int = int(vw.get_stat("attack"))
	var hp_before: int = int(vw.get_hp())
	assert_true(vw.get_status_controller().has_status(&"poisoned"))
	b.submit_switch(1)
	assert_true(vw.get_status_controller().has_status(&"poisoned"), "poison persists on the bench")
	assert_eq(int(vw.get_stat("attack")), atk_buffed - 5, "the battle buff is cleared")
	assert_eq(vw.get_shield(), 0, "the shield is gone")
	assert_eq(int(vw.get_hp()), hp_before, "HP persists")
	# Several turns pass with Vineweave benched: nothing ticks for it.
	for i in 4:
		b.pass_turn()
	assert_eq(int(vw.get_moveset_controller().remaining(cd_move)), cooldown_before, "its cooldown is frozen")
	assert_eq(int(vw.get_hp()), hp_before, "no poison tick on the bench")
	# Back in: it resumes.
	while b.side_of(b.current_actor()) != 0:
		b.pass_turn()
	b.submit_switch(0)
	assert_eq(b.unit_of(0), vw, "Vineweave returns")
	assert_true(vw.visible)


# --- Determinism + the brain -----------------------------------------------------------------

func _ai_trio(seed_value: int) -> DuelRequest:
	var req := DuelRequest.teams(["vineweave", "gem_knight", "petalfang"], ["gem_knight", "blightcap", "monster"], _trio())
	req.seed = seed_value
	req.player_is_ai = true
	req.foe_is_ai = true
	req.ai_difficulty = DuelBrain.NORMAL
	req.player_ai_difficulty = DuelBrain.NORMAL
	return req


func _run(req: DuelRequest) -> Dictionary:
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	var hashes: Array[int] = []
	b.action_resolved.connect(func(rec): hashes.append(int(rec["hash"])))
	var res := b.run_to_end(600)
	var out := {"result": res, "hashes": hashes}
	b.teardown()
	return out


func test_a_3v3_under_a_seed_replays_byte_for_byte() -> void:
	var a := _run(_ai_trio(4242))
	var c := _run(_ai_trio(4242))
	var ra: DuelResult = a["result"]
	var rc: DuelResult = c["result"]
	assert_not_null(ra, "the 3v3 finishes")
	gut.p("3v3 seed 4242: %s in %d rounds, %d commands (%d switches)" % [ra.outcome, ra.rounds,
		ra.commands.size(), _cmd_types_of(ra).count(NetProtocol.Action.SWITCH)])
	assert_gt(ra.defeated.size() + int(ra.stats[1]["kos"]), 1, "more than one KO: a real team fight")
	assert_eq(ra.commands, rc.commands, "identical command list")
	assert_eq(ra.hp_timeline, rc.hp_timeline, "identical HP timeline, every member included")
	assert_eq(a["hashes"], c["hashes"], "identical state hash (parties included) after every command")
	assert_eq(ra.winner_side, rc.winner_side)
	# Replay the recorded commands into a fresh duel.
	var req := _ai_trio(ra.seed)
	req.player_is_ai = false
	req.foe_is_ai = false
	var replay := DuelBattle.new()
	add_child_autofree(replay)
	assert_true(bool(replay.setup(req)["success"]))
	var hashes := replay.replay_commands(ra.commands)
	assert_eq(hashes, a["hashes"], "the replay hashes match after every command")
	assert_true(replay.is_over)
	assert_eq(replay.result.winner_side, ra.winner_side)
	assert_eq(replay.result.hp_timeline, ra.hp_timeline)
	replay.teardown()


static func _cmd_types_of(r: DuelResult) -> Array:
	return r.commands.map(func(c): return int(c[NetProtocol.KEY_TYPE]))


func test_the_brain_switches_out_of_a_bad_matchup_at_normal() -> void:
	# Petalfang (nature, frail) against a strong nature foe: resisted, and one hit from falling.
	# Monster (dark, fast) on the bench matches up far better.
	var req := DuelRequest.teams(["petalfang", "monster"], ["oakheart"], _trio())
	req.kind = DuelRequest.KIND_VERSUS
	req.seed = 3
	req.player_is_ai = true
	req.player_ai_difficulty = DuelBrain.NORMAL
	req.foe_is_ai = false
	req.player_party[0].current_hp = 12
	req.foe_party[0].strength = 1.6
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	b.start()
	# Let Petalfang have its first turn on the field (no switch on the turn it came in).
	var guard := 0
	while b.side_of(b.current_actor()) != 0 and guard < 4:
		b.pass_turn()
		guard += 1
	var pf = b.unit_of(0)
	var first := b.decide_for(pf)
	assert_false(first.has("switch"), "a unit that just came in fights at least once")
	b.pass_turn()
	while b.side_of(b.current_actor()) != 0:
		b.pass_turn()
	var foe = b.unit_of(1)
	var mine := DuelBrain.matchup(pf, foe, b.board)
	var theirs := DuelBrain.matchup(b.team(0)[1]["unit"], foe, b.board)
	gut.p("matchup petalfang %.3f vs monster %.3f" % [mine, theirs])
	assert_gt(theirs - mine, b.rules.ai_switch_margin, "the bench member matches up clearly better")
	var d := b.decide_for(pf)
	assert_true(d.has("switch"), "NORMAL switches out of the bad matchup: %s" % str(d))
	assert_eq(int(d.get("switch", -1)), 1, "to Monster")
	var easy := DuelBrain.consider_switch(pf, foe, b.board, b.rules, DuelBrain.EASY, b.bench_units(0), {}, 9)
	assert_eq(easy, -1, "EASY never switches by choice")
	var rec := b.play_ai_turn()
	assert_eq(int(rec["cmd"][NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH, "and plays it as a SWITCH")
	assert_eq(String(b.unit_of(0).character_resource.character_id), "monster")


func test_the_brain_keeps_a_good_matchup_and_picks_the_best_replacement() -> void:
	var req := DuelRequest.teams(["monster", "petalfang", "gem_knight"], ["oakheart"], _trio())
	req.kind = DuelRequest.KIND_VERSUS
	req.seed = 3
	req.player_is_ai = true
	req.foe_is_ai = false
	var b := DuelBattle.new()
	add_child_autofree(b)
	assert_true(bool(b.setup(req)["success"]))
	b.start()
	var foe = b.unit_of(1)
	var mon = b.unit_of(0)
	assert_eq(DuelBrain.consider_switch(mon, foe, b.board, b.rules, DuelBrain.NORMAL, b.bench_units(0), {}, 9), -1,
		"no switch without a clearly better bench member")
	var pick := DuelBrain.pick_replacement(foe, b.board, b.rules, DuelBrain.NORMAL, b.bench_units(0))
	var best := -INF
	var best_idx := -1
	for row in b.bench_units(0):
		var m := DuelBrain.matchup(row["unit"], foe, b.board)
		if m > best:
			best = m
			best_idx = int(row["index"])
	assert_eq(pick, best_idx, "NORMAL sends the best-matched member")
	assert_eq(DuelBrain.pick_replacement(foe, b.board, b.rules, DuelBrain.EASY, b.bench_units(0)), 1,
		"EASY sends the next in team order")


# --- Requests ---------------------------------------------------------------------------------

func test_a_story_request_fields_the_party_as_a_team_and_a_trainer_team() -> void:
	var br := {
		"kind": "duel", "source": "trainer", "encounter_id": "trainer.test",
		"party": [
			{"member_id": "m1", "character_id": "vineweave", "current_hp": -1},
			{"member_id": "m2", "character_id": "blightcap", "current_hp": 20},
			{"member_id": "m3", "character_id": "petalfang", "current_hp": -1},
			{"member_id": "m4", "character_id": "oakheart", "current_hp": -1},
		],
		"opponent": {"name": "Fenna", "team": [{"character_id": "petalfang", "strength": 0.85},
			{"character_id": "undead", "strength": 0.7}]},
		"rules": {"can_flee": false},
	}
	var res := DuelRequest.from_battle_request(br)
	assert_true(bool(res["success"]), str(res.get("reason", "")))
	var req: DuelRequest = res["request"]
	assert_eq(req.effective_format().id, DuelFormat.STORY, "story duels use the story format")
	assert_eq(req.team_of(0).size(), 3, "the lead plus two bench members")
	assert_eq(req.team_of(1).size(), 2, "the trainer's team")
	assert_false(req.effective_format().species_clause, "a journey may own several of one species")
	var wild := br.duplicate(true)
	wild["source"] = "wild"
	var w: DuelRequest = DuelRequest.from_battle_request(wild)["request"]
	assert_eq(w.foe_party.size(), 1, "a wild encounter stays one foe")
	var back := DuelRequest.from_dict(req.to_dict())
	assert_true(bool(back["success"]), "the format survives the round trip")
	assert_eq((back["request"] as DuelRequest).effective_format().to_dict(), req.effective_format().to_dict())
