class_name StoryProgression
extends RefCounted

## PROGRESSION IN STORY (docs/design/PROGRESSION.md) -- pure rules over the story party, battle-kind
## agnostic, the XP / bond twin of [StoryGrowth]:
##
##   * XP: after every story battle each member earns, per DEFEATED FOE,
##     [method Progression.xp_for_foe] with ITS OWN level (the anti-grind factor, DECISIONS.md #79),
##     the battle's multiplier (wild / trainer / chief-legend), and its share (fought and survived /
##     fought and fell / bench). A loss multiplies by xp_on_loss_mult, a spar by xp_spar_mult; a
##     flee / abort earns nothing. Level-ups recompute stats; current HP keeps its ratio.
##   * BOND (DECISIONS.md #68): every member FIELDED earns bond XP ([method Progression.bond_for_battle]).
##   * GATES: the same as Growth's -- never in a replay, a networked or arena battle; only in mode
##     "story" ([method gate_reason]).
##
## The inputs are the battle's [BattleRequest] (source, boss flag, foe levels) and [BattleResult]
## (party_after rows, defeated foes and -- when the battle knows them -- their levels). No nodes,
## no disk: [StoryResultApplier] applies, StoryController previews for the end screens.

const MODE := "story"


## Why XP / bond are OFF for a battle described by [param ctx] ("" = on). Keys as
## [method StoryGrowth.gate_context]: replay, networked, arena, mode.
static func gate_reason(ctx: Dictionary) -> String:
	if bool(ctx.get("replay", false)):
		return "replay"
	if bool(ctx.get("networked", false)):
		return "networked"
	if bool(ctx.get("arena", false)):
		return "arena"
	if String(ctx.get("mode", "")) != MODE:
		return "mode"
	return ""


## The battle multiplier: wild / trainer-or-scripted / chief-or-legend (rules["boss"]).
static func battle_mult(request: BattleRequest, rules: ProgressionRules = null) -> float:
	var r: ProgressionRules = rules if rules != null else ProgressionRules.current()
	if request != null and request.is_boss_battle():
		return r.battle_mult_boss
	if request != null and request.source == BattleRequest.SOURCE_WILD:
		return r.battle_mult_wild
	return r.battle_mult_trainer


## The outcome multiplier: 1 for a win, xp_on_loss_mult for a loss, 0 for a flee / abort -- times
## xp_spar_mult for a friendly spar.
static func outcome_mult(request: BattleRequest, result: BattleResult, rules: ProgressionRules = null) -> float:
	var r: ProgressionRules = rules if rules != null else ProgressionRules.current()
	if result == null:
		return 0.0
	var m: float = 0.0
	if result.is_victory():
		m = 1.0
	elif result.is_defeat():
		m = r.xp_on_loss_mult
	if result.spar or (request != null and request.is_spar()):
		m *= r.xp_spar_mult
	return m


## The level of each of [param result]'s defeated foes (parallel to result.defeated): the battle's
## own [member BattleResult.defeated_levels] when it reports them, else the request's opponent row
## for that species (each row used once, in order), else [member BattleRequest.enemy_level];
## never below 1.
static func foe_levels(request: BattleRequest, result: BattleResult) -> Array[int]:
	var out: Array[int] = []
	if result == null:
		return out
	var known: bool = result.defeated_levels.size() == result.defeated.size()
	var used: Array = []
	var team: Array = []
	if request != null and request.opponent.get("team", []) is Array:
		team = request.opponent.get("team", [])
	for i in range(result.defeated.size()):
		var lv: int = int(result.defeated_levels[i]) if known else 0
		if lv <= 0 and request != null:
			var cid: String = String(result.defeated[i])
			for t in range(team.size()):
				if used.has(t) or not (team[t] is Dictionary):
					continue
				if String((team[t] as Dictionary).get("character_id", "")) == cid:
					used.append(t)
					lv = request.foe_level(t)
					break
			if lv <= 0:
				lv = request.enemy_level
		out.append(maxi(1, lv))
	return out


## {member_id: XP} each member of [param state] earns from [param result] (only positive entries;
## empty when gated off).
static func awards_for(state: StoryState, request: BattleRequest, result: BattleResult,
		rules: ProgressionRules = null, ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	var r: ProgressionRules = rules if rules != null else ProgressionRules.current()
	if state == null or result == null or gate_reason(ctx) != "":
		return out
	var mult: float = battle_mult(request, r) * outcome_mult(request, result, r)
	if mult <= 0.0 or result.defeated.is_empty():
		return out
	var levels: Array[int] = foe_levels(request, result)
	for e in result.party_after:
		if not (e is Dictionary):
			continue
		var m: StoryPartyMember = state.member(String(e.get("member_id", "")))
		if m == null:
			continue
		var share: float = r.xp_share_bench
		if bool(e.get("fought", true)):
			var fell: bool = bool(e.get("wounded", false)) or int(e.get("current_hp", StoryPartyMember.HP_FULL)) == 0
			share = r.xp_share_fallen if fell else r.xp_share_fought
		var total: int = 0
		for i in range(result.defeated.size()):
			var foe: CharacterResource = CharacterLibrary.get_character(StringName(String(result.defeated[i])))
			total += Progression.xp_for_foe(Progression.xp_yield_of(foe, r), levels[i], m.level, mult, share, r)
		if total > 0:
			out[m.member_id] = maxi(int(out.get(m.member_id, 0)), total)
	return out


## Write [param awards] into the party (level-ups included) and return the end-screen rows.
static func apply_awards(state: StoryState, awards: Dictionary, rules: ProgressionRules = null) -> Array[Dictionary]:
	return _rows(state, awards, rules, true)


## The rows [method apply_awards] WOULD produce, without touching the party (the end screens show
## them before Continue applies the result).
static func preview_rows(state: StoryState, awards: Dictionary, rules: ProgressionRules = null) -> Array[Dictionary]:
	return _rows(state, awards, rules, false)


## Row shape: {uid, character_id, name, gained, level_before, level_after, xp, xp_next, progress,
## leveled}. Party order.
static func _rows(state: StoryState, awards: Dictionary, rules: ProgressionRules, write: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for m in state.party:
		if not awards.has(m.member_id):
			continue
		var res: Dictionary
		if write:
			res = m.add_xp(int(awards[m.member_id]), rules)
		else:
			res = Progression.add_xp(m.xp, int(awards[m.member_id]), rules)
		var total: int = int(res["xp"])
		out.append({
			"uid": m.member_id,
			"character_id": m.character_id,
			"name": m.display_name(),
			"gained": int(res["gained"]),
			"level_before": int(res["level_before"]),
			"level_after": int(res["level_after"]),
			"xp": total,
			"xp_next": Progression.xp_to_next(total, rules),
			"progress": Progression.level_progress(total, rules),
			"leveled": int(res["level_after"]) > int(res["level_before"]),
		})
	return out


## {member_id: bond XP} every member FIELDED in [param result] earns (DECISIONS.md #68: bond grows by
## fighting alongside the hero) -- win or lose, spar or not, never a flee / abort; the same gates
## as XP ([method gate_reason]). Only positive entries.
static func bond_for(state: StoryState, result: BattleResult, rules: ProgressionRules = null,
		ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {}
	if state == null or result == null or gate_reason(ctx) != "":
		return out
	for e in result.party_after:
		if not (e is Dictionary):
			continue
		var mid: String = String(e.get("member_id", ""))
		if state.member(mid) == null:
			continue
		var n: int = Progression.bond_for_battle(bool(e.get("fought", true)), result.outcome, rules)
		if n > 0:
			out[mid] = n
	return out


## Fold [param bond] ({member_id: bond XP}) into the party; returns {member_id: {gained, level}}.
static func apply_bond(state: StoryState, bond: Dictionary, rules: ProgressionRules = null) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	for mid in bond.keys():
		var m: StoryPartyMember = state.member(String(mid))
		if m != null:
			out[m.member_id] = {"gained": int(bond[mid]), "level": m.add_bond(int(bond[mid]), rules)}
	return out


## One end-screen line: "Barkling +86 XP" / "Barkling +312 XP  Lv 5 -> 7".
static func result_line(row: Dictionary) -> String:
	var line: String = "%s +%d XP" % [String(row.get("name", row.get("uid", ""))), int(row.get("gained", 0))]
	if bool(row.get("leveled", false)):
		line += "   Lv %d -> %d" % [int(row.get("level_before", 1)), int(row.get("level_after", 1))]
	else:
		line += "   Lv %d" % int(row.get("level_after", 1))
	return line
