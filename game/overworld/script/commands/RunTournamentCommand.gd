class_name RunTournamentCommand
extends StoryCommand

## THE ARENA MASTER'S DESK (docs/design/DECISIONS.md #33): runs a [TournamentResource] ladder.
## Loop: the host shows the [TournamentLadderPanel] ([code]host.open_ladder(tournament, state)[/code]
## -> "enter" / "fight" / "withdraw" / "leave"), then
##   * ENTER    -- [method TournamentLedger.enter] takes the fee and opens a run, and round 1 starts;
##   * FIGHT    -- the next bout of the open run: the arena heals the party, the announcer calls it,
##                 the duel runs through the SESSION (like StartBattle: the script waits across the
##                 whole round trip and resumes on the new overworld), [method TournamentLedger.record]
##                 folds the result in (advance / the cup / out) and the journey is saved;
##   * WITHDRAW -- give up the run (the fee is gone);
##   * LEAVE    -- walk away; an open run keeps its place (one bout per visit is fine).
## After every bout the panel opens again, so a ladder can be fought back-to-back. With no host (a
## dry run) it leaves at once.

const ACTION_ENTER := "enter"
const ACTION_FIGHT := "fight"
const ACTION_WITHDRAW := "withdraw"
const ACTION_LEAVE := "leave"

@export var tournament: TournamentResource


func run(ctx: ScriptContext) -> void:
	if tournament == null:
		return
	while not ctx.stopped:
		var action: String = ACTION_LEAVE
		if ctx.has_host_method(&"open_ladder"):
			action = String(await ctx.host.open_ladder(tournament, ctx.state))
		match action:
			ACTION_ENTER:
				var r: Dictionary = TournamentLedger.enter(ctx.state, tournament)
				if not bool(r["ok"]):
					await _announce(ctx, [_refusal(String(r["reason"]))])
					continue
				if int(r["paid"]) > 0 and ctx.has_host_method(&"toast"):
					ctx.host.toast("-%d gold (entry fee)" % int(r["paid"]), "gold")
				ctx.world_changed()
				if not await _fight(ctx):
					return
			ACTION_FIGHT:
				if not await _fight(ctx):
					return
			ACTION_WITHDRAW:
				if bool(TournamentLedger.withdraw(ctx.state, tournament)["ok"]):
					ctx.world_changed()
					_save(ctx)
					await _announce(ctx, ["{hero} withdraws from the %s. Better luck next time!" % tournament.display_name])
			_:
				return


## One bout of the open run. False when the script should stop (no bout could be fought).
func _fight(ctx: ScriptContext) -> bool:
	var t: TournamentResource = tournament
	if not TournamentLedger.is_running(ctx.state, t):
		return true
	var i: int = TournamentLedger.next_round(ctx.state, t)
	var spec: BattleSpec = t.rounds[i] if i < t.round_count() else null
	if spec == null:
		return false
	TournamentLedger.prepare_bout(ctx.state, t)
	var foe: String = _species_name(spec)
	var calling: String = "Round %d of %d! {hero} faces %s%s!" % [i + 1, t.round_count(), spec.opponent_name,
		(" and " + foe) if not foe.is_empty() else ""]
	if i + 1 == t.round_count():
		calling = "The final! {hero} against %s%s -- for the %s!" % [spec.opponent_name,
			(" and " + foe) if not foe.is_empty() else "", t.display_name]
	var lines: Array = []
	if t.heal_between_bouts and i > 0:
		lines.append("The arena's healers see to your partner between bouts.")
	lines.append(calling)
	await _announce(ctx, lines)
	var request: BattleRequest = TournamentLedger.bout_request(ctx.state, t)
	if request == null or not ctx.has_session_method(&"run_battle"):
		ctx.stop("no_session")
		return false
	var result = await ctx.session.run_battle(request)
	ctx.last_result = result
	if ctx.stopped:
		return false
	var rec: Dictionary = TournamentLedger.record(ctx.state, t, result)
	ctx.world_changed()
	match String(rec["outcome"]):
		TournamentLedger.ADVANCED:
			_save(ctx)
			await _announce(ctx, ["%s goes down! {hero} takes round %d and moves on." % [spec.opponent_name, int(rec["round"])]])
		TournamentLedger.CUP_WON:
			_save(ctx)
			var won: Array = ["It's over! {hero} wins the %s!" % t.display_name]
			if bool(rec["first_cup"]) and not t.title.is_empty():
				won.append("From this day, the city will know you as %s." % t.title)
			await _announce(ctx, won)
			if ctx.has_host_method(&"toast"):
				if bool(rec["first_cup"]) and not t.title.is_empty():
					ctx.host.toast("Title: %s" % t.title, "quest")
				if int(rec["gold"]) > 0:
					ctx.host.toast("+%d gold" % int(rec["gold"]), "gold")
				for item_id in rec["items"]:
					var item: ItemResource = ItemLibrary.get_item(String(item_id))
					if item != null:
						ctx.host.toast("Prize: %s" % item.display_name, "item")
		TournamentLedger.ELIMINATED:
			_save(ctx)
			await _announce(ctx, ["%s takes the bout. That's the end of the road for {hero} -- this time." % spec.opponent_name])
		_:
			# Nobody could be fielded (or the duel was abandoned): the run keeps its place.
			await _announce(ctx, ["The bout can't go on. Your place in the ladder is kept -- come back when your partner can fight."])
			return false
	return true


func _species_name(spec: BattleSpec) -> String:
	if spec.opponent_team.is_empty():
		return ""
	var chr: CharacterResource = CharacterLibrary.get_character(
		StringName(String(spec.opponent_team[0].get("character_id", ""))))
	return ("a " + chr.display_name) if chr != null else ""


func _refusal(reason: String) -> String:
	match reason:
		TournamentLedger.REASON_GOLD:
			return "The entry fee is %d gold. Come back when your purse is heavier." % tournament.entry_fee
		TournamentLedger.REASON_NO_PARTY:
			return "You'll need a partner who can fight. See a healer first."
		TournamentLedger.REASON_RUNNING:
			return "You're already entered -- your next bout is waiting."
	return "The %s isn't taking entrants today." % tournament.display_name


## The announcer's lines (the tournament's host speaking).
func _announce(ctx: ScriptContext, lines: Array) -> void:
	var say := SayCommand.new()
	var beats: Array[Resource] = []
	for l in lines:
		beats.append(SayCommand.beat(tournament.host_speaker_id, tournament.host_name, String(l), StoryBeat.SIDE_RIGHT))
	say.beats = beats
	await say.run(ctx)


func _save(ctx: ScriptContext) -> void:
	if ctx.has_session_method(&"save_game"):
		ctx.session.save_game()


func describe() -> String:
	return "Run tournament %s" % (String(tournament.id) if tournament != null else "(none)")


func validate(issues: Array[String]) -> void:
	if tournament == null:
		issues.append("no tournament")
		return
	tournament.validate(issues)
