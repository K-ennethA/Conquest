class_name StoryGrowth
extends RefCounted

## EVOLUTION IN STORY (docs/design/EVOLUTION.md §6, OVERWORLD.md §7.1, DECISIONS.md #2) -- pure
## rules over the story party's member records, battle-kind agnostic:
##
##   * GROWTH: after every story battle (tactical or duel) each member that FOUGHT earns Growth
##     through the SAME maths as open modes ([method GrowthTracker.compute_awards]) and the same
##     gates ([method GrowthTracker.gate_reason]: "story" must be in
##     EvolutionRules.growth_modes, never in replays / network). The input is the battle's
##     [BattleResult] party_after -- "fought" (default true; a duel's bench is false), wounded
##     = fallen, "kos" the enemy KOs -- so tactical and duel award identically.
##   * EVOLUTION: a member's pending evolutions come from RosterLedger's RECORD-LEVEL API run on
##     the member's own record ([method StoryPartyMember.ledger_record]); evolving REPLACES the
##     member's form (story identity) and unlocks the form for open modes. The context carries
##     the journey's flags as "story_flags" ([StoryFlagTrigger]).
##
## No nodes, no disk: StoryController calls these and saves.


const MODE := "story"


## The growth gate context for a story battle ([method GrowthTracker.gate_reason] keys).
static func gate_context(replay: bool = false) -> Dictionary:
	return {"replay": replay, "networked": false, "arena": false, "mode": MODE}


## [method GrowthTracker.compute_awards] rows for [param result]: one per member that fought.
static func rows_for(result: BattleResult) -> Array:
	var rows: Array = []
	if result == null:
		return rows
	for e in result.party_after:
		if not (e is Dictionary) or not bool(e.get("fought", true)):
			continue
		var mid: String = String(e.get("member_id", ""))
		if mid.is_empty():
			continue
		var alive: bool = not bool(e.get("wounded", false)) and int(e.get("current_hp", StoryPartyMember.HP_FULL)) != 0
		rows.append({"uid": mid, "alive": alive, "kos": maxi(0, int(e.get("kos", 0)))})
	return rows


## {member_id: gained} for [param result] under [param rules] (empty when gated off, or for a
## battle that was neither won nor lost -- a flee or an abort earns nothing).
static func awards_for(result: BattleResult, rules: EvolutionRules, ctx: Dictionary) -> Dictionary:
	if result == null or rules == null:
		return {}
	if GrowthTracker.gate_reason(ctx, rules) != "":
		return {}
	if not result.is_victory() and not result.is_defeat():
		return {}
	return GrowthTracker.compute_awards(rows_for(result), result.is_victory(), rules)


## Write [param awards] into the party and return the end-screen rows (GrowthTracker's latch
## shape: {uid, character_id, name, gained, total, goal, ready}).
static func apply_awards(state: StoryState, awards: Dictionary, extra: Dictionary = {}) -> Array[Dictionary]:
	return _rows(state, awards, extra, true)


## The rows [method apply_awards] WOULD produce, without touching the party (the tactical end
## screen shows them before Continue applies the result).
static func preview_rows(state: StoryState, awards: Dictionary, extra: Dictionary = {}) -> Array[Dictionary]:
	return _rows(state, awards, extra, false)


static func _rows(state: StoryState, awards: Dictionary, extra: Dictionary, write: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	for m in state.party:
		if not awards.has(m.member_id):
			continue
		var gained: int = int(awards[m.member_id])
		var rec: Dictionary = m.ledger_record()
		rec["growth"] = int(rec["growth"]) + maxi(0, gained)
		if write:
			m.add_growth(gained)
		out.append({
			"uid": m.member_id,
			"character_id": m.character_id,
			"name": m.display_name(),
			"gained": gained,
			"total": int(rec["growth"]),
			"goal": RosterLedger.next_growth_goal(m.character_id),
			"ready": not RosterLedger.record_evolutions(rec, m.member_id, evolution_context(state, extra)).is_empty(),
		})
	return out


# --- Evolution ------------------------------------------------------------------------

## The trigger context extras for a story evolution check: the journey's flags (for
## [StoryFlagTrigger]) plus [param extra] (trigger, area_id...).
static func evolution_context(state: StoryState, extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {"story_flags": state.story_flags() if state != null else {}}
	for k in extra.keys():
		ctx[k] = extra[k]
	return ctx


## The evolutions [param member] can take right now.
static func available_for(member: StoryPartyMember, ctx: Dictionary = {}) -> Array[EvolutionResource]:
	if member == null:
		var none: Array[EvolutionResource] = []
		return none
	return RosterLedger.record_evolutions(member.ledger_record(), member.member_id, ctx)


## Member ids of [param state]'s party with an evolution available, in party order.
static func pending(state: StoryState, ctx: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for m in state.party:
		if not available_for(m, ctx).is_empty():
			out.append(m.member_id)
	return out


## Evolve party member [param member_id] along [param edge]: the member BECOMES the new form
## (member_id, nickname and item kept), its HP follows the edge's hp_policy, and the form is
## unlocked for open modes. [param scripted] skips the triggers (a story beat). Returns
## RosterLedger's {success, reason, item_moved, from, to}; a refusal changes nothing.
static func evolve(state: StoryState, member_id: String, edge: EvolutionResource,
		ctx: Dictionary = {}, scripted: bool = false) -> Dictionary:
	var m: StoryPartyMember = state.member(member_id) if state != null else null
	if m == null:
		return {"success": false, "reason": "no_member", "item_moved": false, "from": "", "to": ""}
	var rec: Dictionary = m.ledger_record()
	var old_max: int = m.max_hp()
	var r: Dictionary = RosterLedger.evolve_record(rec, member_id, edge, ctx, scripted)
	if not bool(r.get("success", false)):
		return r
	m.apply_ledger_record(rec)
	_carry_hp(m, old_max, edge.hp_policy)
	return r


## HP across a form change, by [member EvolutionResource.hp_policy] (0 KEEP_RATIO -- a wounded
## member stays proportionally wounded, OVERWORLD.md §7.1; 1 KEEP_DAMAGE; 2 FULL_HEAL).
static func _carry_hp(m: StoryPartyMember, old_max: int, policy: int) -> void:
	if policy == 2:
		m.heal_full()
		return
	if m.current_hp == StoryPartyMember.HP_FULL or m.current_hp <= 0:
		return
	var new_max: int = m.max_hp()
	var hp: int
	if policy == 1:
		hp = new_max - maxi(0, old_max - m.current_hp)
	else:
		hp = roundi(float(m.current_hp) / float(maxi(1, old_max)) * float(new_max))
	hp = clampi(hp, 1, new_max)
	m.current_hp = StoryPartyMember.HP_FULL if hp >= new_max else hp
