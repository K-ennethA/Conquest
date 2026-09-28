class_name ReviveOfferCommand
extends StoryCommand

## THE WAYSHRINE'S REVIVE (docs/design/DECISIONS.md #29 "Permadeath refinements"): in a CASUAL
## journey knocked-out members are recovered AT A COST OF GOLD -- "Revive 2 knocked-out
## companions for 100 gold?" ([member StoryRuleset.revive_fee_per_member] each,
## [method StoryPermadeath.revive_quote]). Yes pays and revives them to full HP and saves; Not now
## keeps the gold (they stay down); short of gold, the shrine says what it costs.
##
## Free (no question) when reviving costs nothing: a CLASSIC journey (its only knocked-out are
## spar KOs -- the fallen are not in the party and are never revived) or a fee of 0; and when
## nobody can fight and the fee cannot be paid (a journey is never stuck).
## ctx.vars["revived"] = how many got up.

## Who speaks the offer (the shrine's name).
@export var speaker_name: String = "Wayshrine"


func run(ctx: ScriptContext) -> void:
	ctx.vars["revived"] = 0
	var ruleset: StoryRuleset = ctx.session.ruleset() if ctx.has_session_method(&"ruleset") else null
	var q: Dictionary = StoryPermadeath.revive_quote(ctx.state, ruleset)
	var count: int = int(q["count"])
	if count == 0:
		return
	var down: Array[StoryPartyMember] = ctx.state.knocked_out_members()
	var who: String = down[0].display_name() if count == 1 else "%d knocked-out companions" % count
	if not bool(q["costs_gold"]) or bool(q["pity"]):
		ctx.vars["revived"] = StoryPermadeath.revive_all(ctx.state)
		_save(ctx)
		var line: String = "The light lifts %s back to their feet." % who
		if bool(q["pity"]):
			line = "You cannot pay the shrine's keeping -- but the light is kind today. It lifts %s back to their feet." % who
		await _say(ctx, line)
		return
	var total: int = int(q["total"])
	if not bool(q["affordable"]):
		await _say(ctx, "Reviving %s costs %d gold. You have %d." % [who, total, ctx.state.gold])
		return
	var prompt := SayCommand.beat(StoryBeat.NARRATOR, speaker_name,
		"%s %s knocked out. Revive %s for %d gold?" % [who, "is" if count == 1 else "are",
			"them" if count > 1 else "it", total])
	var labels := PackedStringArray(["Revive (%d gold)" % total, "Not now"])
	var picked: int = 1
	if ctx.has_host_method(&"show_choice"):
		picked = int(await ctx.host.show_choice(SayCommand.resolve_beat(prompt, ctx), labels, 1))
	if picked != 0:
		return
	if not ctx.state.take_gold(total):
		return
	ctx.vars["revived"] = StoryPermadeath.revive_all(ctx.state)
	_save(ctx)
	await _say(ctx, "The light lifts %s back to their feet." % who)


func _save(ctx: ScriptContext) -> void:
	if ctx.has_session_method(&"save_game"):
		ctx.session.save_game()


func _say(ctx: ScriptContext, text: String) -> void:
	var say := SayCommand.new()
	say.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, speaker_name, text)])
	await say.run(ctx)


func describe() -> String:
	return "Offer to revive the knocked-out (Casual: for gold)"
