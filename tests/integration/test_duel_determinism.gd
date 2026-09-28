extends GutTest

## THE KEY DUEL TEST (docs/design/DUEL_BATTLE.md §10): Vineweave vs Geode, seed 1234,
## NORMAL vs NORMAL, headless. Two runs from the same seed produce the identical command
## list (each stamped with its per-action seed), HP timeline, status timeline and winner; a
## different seed produces a different roll sequence; and re-applying the recorded commands
## to a fresh duel reproduces the state hash after every command.

const SEED := 1234


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _request(seed_value: int) -> DuelRequest:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight", DuelBrain.NORMAL)
	req.seed = seed_value
	req.player_is_ai = true
	req.player_ai_difficulty = DuelBrain.NORMAL
	return req


## Run one AI-vs-AI duel to the end; also returns the state hash after every command.
func _run(seed_value: int) -> Dictionary:
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(_request(seed_value))
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	var hashes: Array[int] = []
	battle.action_resolved.connect(func(rec): hashes.append(int(rec["hash"])))
	var res := battle.run_to_end()
	assert_not_null(res, "the duel finishes")
	var out := {"result": res, "hashes": hashes}
	battle.teardown()
	return out


func test_same_seed_twice_is_identical() -> void:
	var a := _run(SEED)
	var b := _run(SEED)
	var ra: DuelResult = a["result"]
	var rb: DuelResult = b["result"]
	gut.p("seed %d: %s in %d rounds, %d commands, HP %s" % [SEED, ra.outcome, ra.rounds,
		ra.commands.size(), str(ra.hp_timeline.map(func(r): return r["hp"]))])
	assert_gt(ra.commands.size(), 2, "a real fight, not a one-shot")
	assert_eq(ra.seed, SEED, "the pinned seed is the one recorded")
	assert_eq(ra.commands, rb.commands, "identical command list (incl. per-action seeds)")
	assert_eq(ra.hp_timeline, rb.hp_timeline, "identical HP + status timeline")
	assert_eq(ra.winner_side, rb.winner_side, "identical winner")
	assert_eq(ra.outcome, rb.outcome)
	assert_eq(a["hashes"], b["hashes"], "identical state hash after every command")
	for cmd in ra.commands:
		assert_ne(int(cmd.get(NetProtocol.KEY_RNG, 0)), 0, "every command carries its own seed")


func test_a_different_seed_rolls_differently() -> void:
	var a: DuelResult = _run(SEED)["result"]
	var b: DuelResult = _run(SEED + 1)["result"]
	var rolls_a: Array = a.commands.map(func(c): return c[NetProtocol.KEY_RNG])
	var rolls_b: Array = b.commands.map(func(c): return c[NetProtocol.KEY_RNG])
	assert_ne(rolls_a, rolls_b, "a different seed stamps a different roll sequence")
	var any_differs := a.hp_timeline != b.hp_timeline
	for s in [7, 99, 2024]:
		if any_differs:
			break
		any_differs = _run(s)["result"].hp_timeline != a.hp_timeline
	assert_true(any_differs, "and the fight itself plays out differently")


func test_fresh_entropy_when_no_seed_is_pinned() -> void:
	var a: DuelResult = _run(0)["result"]
	var b: DuelResult = _run(0)["result"]
	assert_ne(a.seed, 0, "the entropy seed actually used is recorded")
	assert_ne(a.seed, b.seed, "every duel starts from fresh entropy")


func test_replaying_the_commands_reproduces_every_state() -> void:
	var live := _run(SEED)
	var recorded: DuelResult = live["result"]
	var replay := DuelBattle.new()
	add_child_autofree(replay)
	var req := _request(recorded.seed)
	req.player_is_ai = false  # playback applies the commands; nobody decides anything
	req.foe_is_ai = false
	assert_true(bool(replay.setup(req)["success"]))
	var hashes := replay.replay_commands(recorded.commands)
	assert_eq(hashes, live["hashes"], "CommandApplier.hash_match_state matches after every command")
	assert_true(replay.is_over, "the replay reaches the same end")
	assert_eq(replay.result.winner_side, recorded.winner_side)
	assert_eq(replay.result.hp_timeline, recorded.hp_timeline)
	replay.teardown()
