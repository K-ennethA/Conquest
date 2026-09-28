class_name StoryResultApplier
extends RefCounted

## PURE: fold a [BattleResult] into the [StoryState] (docs/design/OVERWORLD.md §4.5-§4.6). The
## one place a battle changes the journey, and battle-kind agnostic (tactical and duel results
## have the same shape). No nodes, no disk -- StoryController calls it and then saves.
##
##   * party HP / wounded from party_after (a member at max HP stores the HP_FULL sentinel);
##   * VICTORY: rewards (gold, bag items, flags) and, for a trainer, his defeated flag;
##   * DEFEAT under WHITEOUT: the party is healed, [member StoryRuleset.whiteout_gold_penalty] is
##     taken, and the caller is told to send the player to the respawn Wayshrine;
##   * FLED / CONTINUE-defeat: HP only (a story-critical encounter stays in the world);
##   * GROWTH (EVOLUTION, [StoryGrowth]) when [param growth_ctx] is given: the members that
##     fought earn Growth by the shared rules and gates -- before a whiteout heals the party,
##     so a loss awards exactly what growth_on_loss says -- and, under the same gates, the
##     members' BATTLE FEAT counters (wins, KOs, KOs by element, clutch wins);
##   * every outcome: the BATTLE ITEMS used ([member BattleResult.items_used]) leave the bag, and a
##     few grace steps pass before the grass may roll again;
##   * VICTORY gold = the authored purse (rewards.gold) + per defeated foe the ruleset's
##     [member StoryRuleset.wild_gold_per_foe] (a wild encounter) or
##     [member StoryRuleset.battle_gold_per_foe] (any other battle).
##   * the DIFFICULTY TIER ([StoryPermadeath]), once the HP is in: CLASSIC -- every member knocked
##     out in a real battle FALLS (out of the party for good, its item back in the bag); a SPAR --
##     nobody falls, and its knocked-out get up at 1 HP (the ruleset's spar_ko_recovers); CASUAL --
##     the knocked-out stay down until revived. A whiteout then rests the living (and, with the
##     ruleset's whiteout_revives, the knocked-out; never the fallen).
##   * a FOUGHT spar (won or lost) stamps its encounter id for the sparring-partner cooldown
##     ([StorySparring]).
## A GAME-OVER result ([method BattleResult.is_game_over]) is never applied -- StoryController
## sends the player back to the last save instead.
## Befriending is NOT applied here -- the offer is the story prompt's decision
## ([BefriendPromptCommand]). Nor is evolving: StoryController offers the Evolution screen once
## the overworld is back.
##
## Returns {whiteout: bool, rewarded: bool, gold: int, items: Array, flags: Array,
## growth: Array (the end-screen rows), feats: Dictionary ({member_id: feat deltas}),
## items_used: Dictionary, fallen: Array (member ids that fell), spar_recovered: Array}.


static func apply(state: StoryState, request: BattleRequest, result: BattleResult,
		ruleset: StoryRuleset = null, growth_ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"whiteout": false, "rewarded": false, "gold": 0, "items": [], "flags": [],
		"growth": [], "feats": {}, "items_used": {}, "fallen": [], "spar_recovered": []}
	if state == null or result == null or result.is_game_over():
		return out

	for item_id in result.items_used.keys():
		var n: int = mini(int(result.items_used[item_id]), state.item_count(String(item_id)))
		if n > 0:
			state.take_item(String(item_id), n)
			out["items_used"][String(item_id)] = n

	if not growth_ctx.is_empty():
		var awards: Dictionary = StoryGrowth.awards_for(result, EvolutionRules.current(), growth_ctx)
		# Feats first: the rows' "ready" must see this battle's win.
		var feats: Dictionary = StoryGrowth.feats_for(state, result, EvolutionRules.current(), growth_ctx)
		StoryGrowth.apply_feats(state, feats)
		out["feats"] = feats
		out["growth"] = StoryGrowth.apply_awards(state, awards)

	for entry in result.party_after:
		if not (entry is Dictionary):
			continue
		var m: StoryPartyMember = state.member(String(entry.get("member_id", "")))
		if m == null:
			continue
		var hp: int = int(entry.get("current_hp", StoryPartyMember.HP_FULL))
		var wounded: bool = bool(entry.get("wounded", false)) or hp == 0
		if hp == StoryPartyMember.HP_FULL or hp >= m.max_hp():
			m.current_hp = StoryPartyMember.HP_FULL
		else:
			m.current_hp = maxi(0, hp)
		m.wounded = wounded

	# The difficulty tier decides what being knocked out in this battle MEANS.
	if result.spar or (request != null and request.is_spar()):
		if ruleset == null or ruleset.spar_ko_recovers:
			out["spar_recovered"] = StoryPermadeath.recover_spar_knockouts(state, result)
		# A fought spar starts that partner's cooldown ([StorySparring], DECISIONS.md #33).
		if StorySparring.was_fought(result):
			var sid: String = result.encounter_id if not result.encounter_id.is_empty() \
				else (request.encounter_id if request != null else "")
			StorySparring.note_bout(state, sid)
	else:
		out["fallen"] = StoryPermadeath.apply_fallen(state, request, result)

	if result.is_victory() and request != null:
		var rw: Dictionary = request.rewards
		var gold: int = maxi(0, int(rw.get("gold", 0))) + gold_for_foes(request, result, ruleset)
		if gold > 0:
			state.add_gold(gold)
			out["gold"] = gold
		var items = rw.get("items", [])
		if items is Array:
			for i in items:
				if ItemLibrary.has_item(String(i)):
					state.add_item(String(i))
					out["items"].append(String(i))
		var flags = rw.get("flags", [])
		if flags is Array:
			for f in flags:
				state.set_flag(String(f), 1)
				out["flags"].append(String(f))
		if request.source == BattleRequest.SOURCE_TRAINER and not request.encounter_id.is_empty():
			var df: String = request.encounter_id + ".defeated"
			state.set_flag(df, 1)
			out["flags"].append(df)
		out["rewarded"] = true
	elif result.is_defeat():
		var policy: String = request.defeat_policy() if request != null else BattleRequest.DEFEAT_WHITEOUT
		if policy == BattleRequest.DEFEAT_WHITEOUT:
			state.heal_party(ruleset == null or ruleset.whiteout_revives)
			var penalty: int = ruleset.whiteout_gold_penalty if ruleset != null else 0
			if penalty > 0:
				state.add_gold(-penalty)
			out["whiteout"] = true

	state.grace_steps = ruleset.grace_steps if ruleset != null else 3
	return out


## The per-foe gold a won battle pays on top of its purse (0 without a ruleset).
static func gold_for_foes(request: BattleRequest, result: BattleResult, ruleset: StoryRuleset) -> int:
	if ruleset == null or result == null:
		return 0
	var wild: bool = request != null and request.source == BattleRequest.SOURCE_WILD
	var per: int = ruleset.wild_gold_per_foe if wild else ruleset.battle_gold_per_foe
	return maxi(0, per) * result.defeated.size()
