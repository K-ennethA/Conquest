extends GutTest

## THE TOURNAMENT LADDER, pure (docs/design/DECISIONS.md #33; TournamentResource, TournamentLedger,
## RunTournamentCommand against a scripted host + a fake session):
##   * entering takes the fee and opens a run (refused when short / already running / nobody fit);
##   * bouts advance in order; a lost bout ends the run; withdrawing forfeits it;
##   * the last bout wins the cup: prize gold + the first-cup item + the title the first time,
##     the repeat prize after; repeat cups scale on the wins flag;
##   * the arena heals the living before a bout WITHOUT counting a rest;
##   * the run lives in flags, so a save / reload mid-ladder resumes at the same round, no new fee;
##   * the command: enter -> fight x4 -> the cup, saving after every bout, the ladder re-opened
##     between bouts, "leave" keeps the run.


class LadderHost extends StoryScriptHost:
	var picks: Array = []
	var opened: int = 0
	var said: Array = []
	var toasts: Array = []

	func open_ladder(_tournament, _state) -> String:
		opened += 1
		return String(picks.pop_front()) if not picks.is_empty() else "leave"

	func show_dialogue(scene: StoryScene) -> void:
		for b in scene.playable_beats():
			said.append(b.text)

	func toast(text: String, _kind: String = "") -> void:
		toasts.append(text)


class FakeSession extends RefCounted:
	var outcomes: Array = []
	var requests: Array = []
	var saves: int = 0

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		var o: String = String(outcomes.pop_front()) if not outcomes.is_empty() else BattleResult.OUTCOME_VICTORY
		return BattleResult.make(request.encounter_id, o)

	func save_game() -> Dictionary:
		saves += 1
		return {"success": true, "reason": ""}

	func hero_name() -> String:
		return "Wren"


func _cup() -> TournamentResource:
	var t := TournamentResource.new()
	t.id = &"test_cup"
	t.display_name = "The Test Cup"
	t.host_name = "Bex"
	t.entry_fee = 100
	t.prize_gold = 400
	var items: Array[StringName] = [&"sunleaf_totem"]
	t.first_prize_items = items
	t.repeat_prize_gold = 200
	t.title = "Test Champion"
	var rounds: Array[BattleSpec] = []
	for pair in [["Tamsin", "mycothrall", 0.9], ["Harl", "blightcap", 1.0], ["Isolde", "oakheart", 0.85]]:
		var spec := BattleSpec.new()
		spec.kind = BattleSpec.Kind.DUEL
		spec.opponent_name = String(pair[0])
		var team: Array[Dictionary] = [{"character_id": String(pair[1]), "strength": float(pair[2])}]
		spec.opponent_team = team
		spec.spar = true
		spec.defeat_policy = BattleSpec.DefeatPolicy.CONTINUE
		spec.scale_flag = t.wins_flag()
		spec.scale_step = 0.05
		spec.scale_max_steps = 4
		rounds.append(spec)
	t.rounds = rounds
	return t


func _state(gold: int = 500) -> StoryState:
	var s := StoryState.new()
	s.add_member("vineweave")
	s.gold = gold
	return s


func _win() -> BattleResult:
	return BattleResult.make("", BattleResult.OUTCOME_VICTORY)


func test_the_shipped_cup_validates() -> void:
	var t := TournamentResource.load_by_id("crown_cup")
	assert_not_null(t, "the Crown Cup ships")
	if t == null:
		return
	var issues: Array[String] = []
	t.validate(issues)
	assert_eq(issues, [] as Array[String], "and validates clean")
	assert_gte(t.round_count(), 3, "a ladder of at least three bouts")
	for spec in t.rounds:
		assert_true(spec.spar, "%s's bout is a friendly (no permadeath)" % spec.opponent_name)
	assert_gt(t.entry_fee, 0, "an entry fee")
	assert_false(t.first_prize_items.is_empty(), "an item prize")
	assert_false(t.title.is_empty(), "and a title")


func test_entering_takes_the_fee() -> void:
	var t := _cup()
	var s := _state(150)
	var r: Dictionary = TournamentLedger.enter(s, t)
	assert_true(bool(r["ok"]), "entered")
	assert_eq(s.gold, 50, "the fee was paid")
	assert_true(TournamentLedger.is_running(s, t), "a run is open")
	assert_eq(TournamentLedger.next_round(s, t), 0, "at round 1")
	assert_eq(String(TournamentLedger.enter(s, t)["reason"]), TournamentLedger.REASON_RUNNING, "no second entry")
	var poor := _state(99)
	assert_eq(String(TournamentLedger.enter(poor, t)["reason"]), TournamentLedger.REASON_GOLD, "99 gold is short")
	assert_eq(poor.gold, 99, "and nothing was taken")
	var down := _state()
	down.party[0].wounded = true
	assert_eq(String(TournamentLedger.can_enter(down, t)["reason"]), TournamentLedger.REASON_NO_PARTY,
		"nobody able to fight: no entry")


func test_the_ladder_advances_and_the_cup_pays_the_first_prize_once() -> void:
	var t := _cup()
	var s := _state()
	TournamentLedger.enter(s, t)
	var r1: Dictionary = TournamentLedger.record(s, t, _win())
	assert_eq(String(r1["outcome"]), TournamentLedger.ADVANCED, "round 1 won: advance")
	assert_eq(int(r1["round"]), 1, "it was round 1")
	assert_eq(TournamentLedger.next_round(s, t), 1, "round 2 is next")
	var rows: Array[Dictionary] = TournamentLedger.ladder_rows(s, t)
	assert_eq([rows[0]["status"], rows[1]["status"], rows[2]["status"]], ["won", "next", "ahead"], "the ladder shows it")
	TournamentLedger.record(s, t, _win())
	var gold_before: int = s.gold
	var r3: Dictionary = TournamentLedger.record(s, t, _win())
	assert_eq(String(r3["outcome"]), TournamentLedger.CUP_WON, "the final won: the cup")
	assert_true(bool(r3["first_cup"]), "the first cup")
	assert_eq(s.gold, gold_before + 400, "the prize gold")
	assert_eq(s.item_count("sunleaf_totem"), 1, "the prize item")
	assert_true(TournamentLedger.is_champion(s, t), "the title")
	assert_eq(TournamentLedger.cups_won(s, t), 1, "one cup")
	assert_false(TournamentLedger.is_running(s, t), "the run is closed")
	# A second cup: the repeat prize, no second item -- and every bout is 5% stronger.
	TournamentLedger.enter(s, t)
	var req: BattleRequest = TournamentLedger.bout_request(s, t)
	assert_almost_eq(float(req.opponent["team"][0]["strength"]), 0.945, 0.0001, "repeat cups scale on the wins flag")
	for i in range(3):
		TournamentLedger.record(s, t, _win())
	assert_eq(s.item_count("sunleaf_totem"), 1, "the item is a first-cup prize only")
	assert_eq(TournamentLedger.cups_won(s, t), 2, "two cups")


func test_a_loss_ends_the_run_and_withdrawing_forfeits_it() -> void:
	var t := _cup()
	var s := _state()
	TournamentLedger.enter(s, t)
	TournamentLedger.record(s, t, _win())
	var fled: Dictionary = TournamentLedger.record(s, t, BattleResult.make("", BattleResult.OUTCOME_ABORTED))
	assert_eq(String(fled["outcome"]), TournamentLedger.NO_CHANGE, "an aborted bout changes nothing")
	assert_eq(TournamentLedger.next_round(s, t), 1, "still at round 2")
	var out: Dictionary = TournamentLedger.record(s, t, BattleResult.make("", BattleResult.OUTCOME_DEFEAT))
	assert_eq(String(out["outcome"]), TournamentLedger.ELIMINATED, "a lost bout: out")
	assert_false(TournamentLedger.is_running(s, t), "the run is over")
	assert_false(TournamentLedger.is_champion(s, t), "no title")
	TournamentLedger.enter(s, t)
	assert_true(bool(TournamentLedger.withdraw(s, t)["ok"]), "withdraw")
	assert_false(TournamentLedger.is_running(s, t), "no run")
	assert_eq(s.gold, 300, "both fees are gone")


func test_the_arena_heals_before_a_bout_without_a_rest() -> void:
	var t := _cup()
	var s := _state()
	s.add_member("blightcap")
	s.party[0].current_hp = 5
	s.party[1].wounded = true
	s.party[1].current_hp = 0
	var rests: int = s.rests
	TournamentLedger.prepare_bout(s, t)
	assert_eq(s.party[0].current_hp, StoryPartyMember.HP_FULL, "the lead is healed")
	assert_true(s.party[1].wounded, "the knocked-out stay down (no free revive)")
	assert_eq(s.rests, rests, "not a rest: sparring partners and merchants are not refreshed")


func test_bout_requests_are_scripted_spar_duels() -> void:
	var t := _cup()
	var s := _state()
	assert_null(TournamentLedger.bout_request(s, t), "no run, no bout")
	TournamentLedger.enter(s, t)
	TournamentLedger.record(s, t, _win())
	var req: BattleRequest = TournamentLedger.bout_request(s, t)
	assert_true(req.is_duel(), "a duel")
	assert_true(req.is_spar(), "a friendly")
	assert_eq(req.encounter_id, "arena.test_cup.round2", "round 2's encounter id")
	assert_eq(String(req.opponent["name"]), "Harl", "against the second entrant")


func test_a_run_survives_save_and_reload() -> void:
	var t := _cup()
	var s := _state()
	s.set_location("crownhaven", Vector3i(21, 22, 0), "east")
	TournamentLedger.enter(s, t)
	TournamentLedger.record(s, t, _win())
	var gold: int = s.gold
	var restored: Dictionary = StorySnapshot.from_dict(JSON.parse_string(JSON.stringify(StorySnapshot.to_dict(s))))
	assert_true(bool(restored["success"]), "the journey round-trips")
	var t2: StoryState = restored["state"]
	assert_true(TournamentLedger.is_running(t2, t), "the run is still open")
	assert_eq(TournamentLedger.next_round(t2, t), 1, "at round 2")
	assert_eq(t2.gold, gold, "no second fee")
	assert_eq(TournamentLedger.bout_request(t2, t).encounter_id, "arena.test_cup.round2", "the next bout is round 2")


func test_the_command_runs_a_whole_cup() -> void:
	var t := _cup()
	var s := _state()
	var host := LadderHost.new()
	host.picks = ["enter", "fight", "fight", "leave"]
	var session := FakeSession.new()
	var cmd := RunTournamentCommand.new()
	cmd.tournament = t
	var ctx := ScriptContext.new(s, host, session, "crownhaven")
	await StoryScriptRunner.new().run([cmd], ctx)
	assert_eq(session.requests.size(), 3, "three bouts fought")
	var ids: Array = []
	for r in session.requests:
		ids.append((r as BattleRequest).encounter_id)
	assert_eq(ids, ["arena.test_cup.round1", "arena.test_cup.round2", "arena.test_cup.round3"], "in ladder order")
	assert_eq(host.opened, 4, "the ladder re-opens after every bout")
	assert_true(TournamentLedger.is_champion(s, t), "the cup is won")
	assert_eq(s.gold, 500 - 100 + 400, "fee paid, prize won")
	assert_eq(session.saves, 3, "the journey saved after every bout")
	assert_true(host.toasts.has("Title: Test Champion"), "the title is announced")
	var announced: String = " ".join(host.said)
	assert_true(announced.contains("The final!"), "the final is called")


func test_leaving_keeps_the_place_and_a_loss_ends_it() -> void:
	var t := _cup()
	var s := _state()
	var host := LadderHost.new()
	host.picks = ["enter", "leave"]
	var session := FakeSession.new()
	var cmd := RunTournamentCommand.new()
	cmd.tournament = t
	await StoryScriptRunner.new().run([cmd], ScriptContext.new(s, host, session, "crownhaven"))
	assert_true(TournamentLedger.is_running(s, t), "leaving after round 1 keeps the run")
	assert_eq(TournamentLedger.next_round(s, t), 1, "at round 2")
	host.picks = ["fight", "leave"]
	session.outcomes = [BattleResult.OUTCOME_DEFEAT]
	await StoryScriptRunner.new().run([cmd], ScriptContext.new(s, host, session, "crownhaven"))
	assert_eq((session.requests[1] as BattleRequest).encounter_id, "arena.test_cup.round2", "the next visit fights round 2")
	assert_false(TournamentLedger.is_running(s, t), "the loss ended the run")
	assert_eq(s.gold, 400, "one fee only")
	host.picks = ["enter"]
	s.gold = 50
	await StoryScriptRunner.new().run([cmd], ScriptContext.new(s, host, session, "crownhaven"))
	assert_eq(session.requests.size(), 2, "short of the fee: no bout")
	assert_true(" ".join(host.said).contains("entry fee is 100"), "and the master says why")
