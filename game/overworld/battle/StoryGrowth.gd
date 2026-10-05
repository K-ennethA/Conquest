class_name StoryGrowth
extends RefCounted

## EVOLUTION IN STORY (docs/design/EVOLUTION.md §6, OVERWORLD.md §7.1, DECISIONS.md #2, #26, #27)
## -- pure rules over the story party's member records, battle-kind agnostic:
##
##   * GROWTH: after every story battle (tactical or duel) each member that FOUGHT earns Growth
##     through the SAME maths as open modes ([method GrowthTracker.compute_awards]) and the same
##     gates ([method GrowthTracker.gate_reason]: "story" must be in
##     EvolutionRules.growth_modes, never in replays / network). The input is the battle's
##     [BattleResult] party_after -- "fought" (default true; a duel's bench is false), wounded
##     = fallen, "kos" the enemy KOs -- so tactical and duel award identically.
##   * BATTLE FEATS ([BattleFeatTrigger]): the same rows (plus "ko_elements" and the carried HP)
##     feed [method GrowthTracker.compute_feats] under the same gates; the counters land in the
##     member's record ([method StoryPartyMember.add_feats]).
##   * EVOLUTION: a member's pending evolutions come from RosterLedger's RECORD-LEVEL API run on
##     the member's own record ([method StoryPartyMember.ledger_record]) with the STORY context
##     ([method evolution_context]: flags, area, region, weather, party, bag, "mode" = "story")
##     plus the member's held item. Every listed requirement must be met (ALL). Evolving
##     REPLACES the member's form (story identity), unlocks the form for open modes and spends a
##     used item ([UseItemTrigger]).
##   * HOLD: [method pending] can leave held members out -- the automatic prompts respect Hold,
##     the Journey -> Party menu does not.
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
## screen shows them before Continue applies the result). [param feats]: the battle's feat
## deltas ([method feats_for]), counted into "ready" as Continue will.
static func preview_rows(state: StoryState, awards: Dictionary, extra: Dictionary = {},
		feats: Dictionary = {}) -> Array[Dictionary]:
	return _rows(state, awards, extra, false, feats)


static func _rows(state: StoryState, awards: Dictionary, extra: Dictionary, write: bool,
		feats: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var ctx: Dictionary = evolution_context(state, extra)
	for m in state.party:
		if not awards.has(m.member_id):
			continue
		var gained: int = int(awards[m.member_id])
		var rec: Dictionary = m.ledger_record()
		rec["growth"] = int(rec["growth"]) + maxi(0, gained)
		if feats.has(m.member_id):
			RosterLedger.apply_feats(rec, feats[m.member_id])
		if write:
			m.add_growth(gained)
		out.append({
			"uid": m.member_id,
			"character_id": m.character_id,
			"name": m.display_name(),
			"gained": gained,
			"total": int(rec["growth"]),
			"goal": RosterLedger.next_growth_goal(m.character_id),
			"ready": not RosterLedger.record_evolutions(rec, m.member_id, member_context(m, ctx)).is_empty(),
		})
	return out


# --- Battle feats ------------------------------------------------------------------------

## [method GrowthTracker.compute_feats] rows for [param result] (members that fought): KOs, the
## KO'd foes' elements ("ko_elements"; a result without them -- the duel -- credits
## [member BattleResult.defeated] to its single fighter) and the HP ratio it ended on.
static func feat_rows_for(state: StoryState, result: BattleResult) -> Array:
	var rows: Array = []
	if state == null or result == null:
		return rows
	var fought: Array = []
	for e in result.party_after:
		if e is Dictionary and bool(e.get("fought", true)) and not String(e.get("member_id", "")).is_empty():
			fought.append(e)
	for e in fought:
		var mid: String = String(e.get("member_id", ""))
		var m: StoryPartyMember = state.member(mid)
		var hp: int = int(e.get("current_hp", StoryPartyMember.HP_FULL))
		var alive: bool = not bool(e.get("wounded", false)) and hp != 0
		var ratio: float = 1.0
		if alive and hp != StoryPartyMember.HP_FULL and m != null:
			ratio = float(hp) / float(maxi(1, m.max_hp()))
		var kos: int = maxi(0, int(e.get("kos", 0)))
		var by: Dictionary = {}
		var raw = e.get("ko_elements", {})
		if raw is Dictionary:
			by = (raw as Dictionary).duplicate()
		if by.is_empty() and kos > 0 and fought.size() == 1:
			var credited: int = 0
			for cid in result.defeated:
				if credited >= kos:
					break
				var chr: CharacterResource = CharacterLibrary.get_character(StringName(String(cid)))
				if chr != null and chr.element != &"":
					by[String(chr.element)] = int(by.get(String(chr.element), 0)) + 1
				credited += 1
		rows.append({"uid": mid, "alive": alive, "kos": kos, "element_kos": by, "hp_ratio": ratio if alive else 0.0})
	return rows


## {member_id: feat deltas} for [param result] -- the same gates as Growth ([method awards_for]).
static func feats_for(state: StoryState, result: BattleResult, rules: EvolutionRules, ctx: Dictionary) -> Dictionary:
	if state == null or result == null or rules == null:
		return {}
	if GrowthTracker.gate_reason(ctx, rules) != "":
		return {}
	if not result.is_victory() and not result.is_defeat():
		return {}
	return GrowthTracker.compute_feats(feat_rows_for(state, result), result.is_victory(), rules)


## Fold [param feats] ({member_id: delta}) into the party's records.
static func apply_feats(state: StoryState, feats: Dictionary) -> void:
	if state == null:
		return
	for mid in feats.keys():
		var m: StoryPartyMember = state.member(String(mid))
		if m != null:
			m.add_feats(feats[mid])


# --- Evolution ------------------------------------------------------------------------

## The STORY context for an evolution check ([EvolutionTrigger] keys): "mode" = "story", the
## journey's flags ([StoryFlagTrigger]), where the party stands -- area, region and weather
## ([LocationTrigger], [WeatherTrigger]) --, the party ([PartyHasTrigger]) and the bag
## ([UseItemTrigger] progress), plus [param extra] (trigger, used_item... -- it wins).
static func evolution_context(state: StoryState, extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {"mode": MODE, "story_flags": state.story_flags() if state != null else {}}
	if state != null:
		var area_id: String = state.location_area()
		ctx["area_id"] = area_id
		var area: OverworldAreaResource = OverworldAreaResource.load_by_id(area_id)
		ctx["region_id"] = String(area.region_id) if area != null else ""
		ctx["weather"] = area.weather_id() if area != null else ""
		var party: Array = []
		for m in state.party:
			party.append({"member_id": m.member_id, "character_id": m.character_id, "line": m.line})
		ctx["party_members"] = party
		ctx["bag"] = state.bag.duplicate()
	for k in extra.keys():
		ctx[k] = extra[k]
	return ctx


## [param ctx] plus what [param member] itself brings: the item it wears ([HeldItemTrigger]) and its
## story level ([LevelTrigger]).
static func member_context(member: StoryPartyMember, ctx: Dictionary) -> Dictionary:
	var out: Dictionary = ctx.duplicate()
	if member != null and not out.has("held_item"):
		out["held_item"] = member.item_id
	if member != null and not out.has("level"):
		out["level"] = member.level
	return out


## The evolutions [param member] can take right now.
static func available_for(member: StoryPartyMember, ctx: Dictionary = {}) -> Array[EvolutionResource]:
	if member == null:
		var none: Array[EvolutionResource] = []
		return none
	return RosterLedger.record_evolutions(member.ledger_record(), member.member_id, member_context(member, ctx))


## The CHECKLIST of [param member]'s next forms: {edge, available, rows} per edge leaving its
## current form (branching: one entry per edge), plus "use_item": the bag item that would make
## it available right now when used ("" = none).
static func checklists(member: StoryPartyMember, ctx: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if member == null:
		return out
	var mctx: Dictionary = member_context(member, ctx)
	for entry in RosterLedger.record_checklists(member.ledger_record(), member.member_id, mctx):
		entry["use_item"] = "" if bool(entry["available"]) else _bag_item_for(member, entry["edge"], mctx)
		out.append(entry)
	return out


## The edges the Journey -> Party EVOLVE button offers [param member]: available now, or
## available by USING an item the bag holds. {edges: Array[EvolutionResource], use_items:
## {edge id: item_id}}.
static func menu_edges(member: StoryPartyMember, ctx: Dictionary = {}) -> Dictionary:
	var edges: Array[EvolutionResource] = []
	var use_items: Dictionary = {}
	for entry in checklists(member, ctx):
		var e: EvolutionResource = entry["edge"]
		if bool(entry["available"]):
			edges.append(e)
		elif not String(entry["use_item"]).is_empty():
			edges.append(e)
			use_items[e.id] = String(entry["use_item"])
	return {"edges": edges, "use_items": use_items}


## The edges USING [param item_id] on [param member] makes available (the bag's Use).
static func edges_for_item(member: StoryPartyMember, item_id: String, ctx: Dictionary = {}) -> Array[EvolutionResource]:
	var out: Array[EvolutionResource] = []
	if member == null or item_id.is_empty():
		return out
	var mctx: Dictionary = member_context(member, ctx)
	mctx["used_item"] = item_id
	for e in RosterLedger.record_evolutions(member.ledger_record(), member.member_id, mctx):
		if e.use_item_ids().has(item_id):
			out.append(e)
	return out


## Every item id some shipped edge USES ([UseItemTrigger]) -- the bag's "Use" rows.
static func usable_item_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for e in EvolutionLibrary.all():
		for id in e.use_item_ids():
			if not out.has(id):
				out.append(id)
	return out


## The first bag item that, used, makes [param edge] available for [param member] ("" = none).
static func _bag_item_for(member: StoryPartyMember, edge: EvolutionResource, mctx: Dictionary) -> String:
	var bag = mctx.get("bag", {})
	if not (bag is Dictionary):
		return ""
	for item_id in edge.use_item_ids():
		if int((bag as Dictionary).get(item_id, 0)) <= 0:
			continue
		var c: Dictionary = mctx.duplicate()
		c["used_item"] = item_id
		if edge.is_available(RosterLedger.record_context(member.ledger_record(), member.member_id, c)):
			return item_id
	return ""


## The edges of [param member] worth offering AUTOMATICALLY for [param event] (available, and
## -- when [param event] is not empty -- touched by it, [method EvolutionResource.responds_to]).
## A member on HOLD gets none.
static func offerable_for(member: StoryPartyMember, ctx: Dictionary = {}, event: Dictionary = {}) -> Array[EvolutionResource]:
	var out: Array[EvolutionResource] = []
	if member == null or member.hold:
		return out
	for e in available_for(member, ctx):
		if event.is_empty() or e.responds_to(event):
			out.append(e)
	return out


## Member ids of [param state]'s party with an evolution available, in party order. With
## [param respect_hold] members on Hold are left out; with an [param event] only edges it
## touched count ([method offerable_for]).
static func pending(state: StoryState, ctx: Dictionary = {}, respect_hold: bool = false,
		event: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	if state == null:
		return out
	for m in state.party:
		if respect_hold and m.hold:
			continue
		for e in available_for(m, ctx):
			if event.is_empty() or e.responds_to(event):
				out.append(m.member_id)
				break
	return out


## Evolve party member [param member_id] along [param edge]: the member BECOMES the new form
## (member_id, nickname and item kept), its HP follows the edge's hp_policy, and the form is
## unlocked for open modes. When [param ctx] names a "used_item" the edge USES, one is spent
## from the bag ([UseItemTrigger] consume). [param scripted] skips the requirements (a story
## beat). Returns RosterLedger's {success, reason, item_moved, from, to} plus "consumed" (item
## ids spent); a refusal changes nothing.
static func evolve(state: StoryState, member_id: String, edge: EvolutionResource,
		ctx: Dictionary = {}, scripted: bool = false) -> Dictionary:
	var m: StoryPartyMember = state.member(member_id) if state != null else null
	if m == null:
		return {"success": false, "reason": "no_member", "item_moved": false, "from": "", "to": "", "consumed": []}
	var used: String = String(ctx.get("used_item", ""))
	if not used.is_empty() and edge != null and edge.use_item_ids().has(used) and state.item_count(used) <= 0:
		return {"success": false, "reason": "no_item", "item_moved": false, "from": "", "to": "", "consumed": []}
	var rec: Dictionary = m.ledger_record()
	var old_max: int = m.max_hp()
	var r: Dictionary = RosterLedger.evolve_record(rec, member_id, edge, member_context(m, ctx), scripted)
	r["consumed"] = []
	if not bool(r.get("success", false)):
		return r
	m.apply_ledger_record(rec)
	_carry_hp(m, old_max, edge.hp_policy)
	if not used.is_empty():
		for item_id in edge.consumed_items(used):
			if state.take_item(item_id):
				(r["consumed"] as Array).append(item_id)
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
