class_name TournamentLedger
extends RefCounted

## PURE: the rules of a [TournamentResource] ladder over a [StoryState] (docs/design/DECISIONS.md
## #33). No nodes, no disk; [RunTournamentCommand] drives it and StoryController saves. Progress
## lives in ordinary story FLAGS (the resource's run / round / wins / title flags), so a run
## survives save / reload exactly like any quest stage: quit between bouts -- or in the middle of
## one (the pre-battle autosave holds the run as it was before that bout) -- and the arena master
## offers "Round N" again, with no second fee.
##
## Every call returns a value ({ok, reason, ...}); nothing logs (CONQUEST.md rule 1).

const REASON_RUNNING := "running"
const REASON_NOT_RUNNING := "not_running"
const REASON_GOLD := "not_enough_gold"
const REASON_NO_ROUNDS := "no_rounds"
const REASON_NO_PARTY := "no_fieldable_members"

## What [method record] made of a bout.
const ADVANCED := "advanced"
const CUP_WON := "cup_won"
const ELIMINATED := "eliminated"
const NO_CHANGE := "none"


static func is_running(state: StoryState, t: TournamentResource) -> bool:
	return state != null and t != null and state.has_flag(t.run_flag())


## Bouts won in the open run (0 without one) -- also the index of the next bout.
static func cleared(state: StoryState, t: TournamentResource) -> int:
	if not is_running(state, t):
		return 0
	return clampi(state.get_flag_int(t.round_flag()), 0, t.round_count())


static func next_round(state: StoryState, t: TournamentResource) -> int:
	return cleared(state, t)


static func cups_won(state: StoryState, t: TournamentResource) -> int:
	return state.get_flag_int(t.wins_flag()) if state != null and t != null else 0


static func is_champion(state: StoryState, t: TournamentResource) -> bool:
	return state != null and t != null and state.has_flag(t.title_flag())


## May a new run be opened? {ok, reason}.
static func can_enter(state: StoryState, t: TournamentResource) -> Dictionary:
	if state == null or t == null or t.round_count() == 0:
		return {"ok": false, "reason": REASON_NO_ROUNDS}
	if is_running(state, t):
		return {"ok": false, "reason": REASON_RUNNING}
	if state.healthy_members().is_empty():
		return {"ok": false, "reason": REASON_NO_PARTY}
	if state.gold < t.entry_fee:
		return {"ok": false, "reason": REASON_GOLD}
	return {"ok": true, "reason": ""}


## Pay the fee and open a run at round 1. {ok, reason, paid}.
static func enter(state: StoryState, t: TournamentResource) -> Dictionary:
	var can: Dictionary = can_enter(state, t)
	if not bool(can["ok"]):
		return {"ok": false, "reason": String(can["reason"]), "paid": 0}
	if not state.take_gold(maxi(0, t.entry_fee)):
		return {"ok": false, "reason": REASON_GOLD, "paid": 0}
	state.set_flag(t.run_flag(), 1)
	state.set_flag(t.round_flag(), 0)
	return {"ok": true, "reason": "", "paid": maxi(0, t.entry_fee)}


## Give up the open run (the fee is not returned). {ok, reason}.
static func withdraw(state: StoryState, t: TournamentResource) -> Dictionary:
	if not is_running(state, t):
		return {"ok": false, "reason": REASON_NOT_RUNNING}
	_close_run(state, t)
	return {"ok": true, "reason": ""}


## The arena's healers before a bout: every LIVING member back to full HP. Not a rest -- the rest
## counter (sparring partners, ON_REST merchants) is untouched, and the knocked-out stay down.
static func prepare_bout(state: StoryState, t: TournamentResource) -> void:
	if state == null or t == null or not t.heal_between_bouts:
		return
	for m in state.party:
		if not ConsumableEffect.member_is_down(m):
			m.heal_full()


## The [BattleRequest] for the open run's next bout (null without a run / past the last round):
## a DUEL from the round's spec, source "script", encounter id [method TournamentResource.bout_encounter_id],
## its rematch scaling applied for [param state].
static func bout_request(state: StoryState, t: TournamentResource) -> BattleRequest:
	if not is_running(state, t):
		return null
	var i: int = next_round(state, t)
	if i >= t.round_count() or t.rounds[i] == null:
		return null
	var spec: BattleSpec = t.rounds[i]
	var req: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT, t.bout_encounter_id(i))
	req.encounter_id = t.bout_encounter_id(i)
	req.kind = BattleRequest.KIND_DUEL
	spec.apply_scaling(req, state)
	return req


## Fold a bout's [param result] into the run. Returns {outcome (ADVANCED / CUP_WON / ELIMINATED /
## NO_CHANGE), round (the bout's 1-based number), gold, items (Array[String]), first_cup (bool)}.
## A fled / aborted bout changes nothing (the run stays at that round).
static func record(state: StoryState, t: TournamentResource, result: BattleResult) -> Dictionary:
	var out: Dictionary = {"outcome": NO_CHANGE, "round": 0, "gold": 0, "items": [], "first_cup": false}
	if not is_running(state, t) or result == null:
		return out
	var i: int = next_round(state, t)
	out["round"] = i + 1
	if result.is_defeat():
		_close_run(state, t)
		out["outcome"] = ELIMINATED
		return out
	if not result.is_victory():
		return out
	if i + 1 < t.round_count():
		state.set_flag(t.round_flag(), i + 1)
		out["outcome"] = ADVANCED
		return out
	# The last bout: the cup.
	var first: bool = not is_champion(state, t)
	var gold: int = t.prize_gold if first or t.repeat_prize_gold <= 0 else t.repeat_prize_gold
	if gold > 0:
		state.add_gold(gold)
	var items: Array[String] = []
	if first:
		for item_id in t.first_prize_items:
			if ItemLibrary.has_item(item_id):
				state.add_item(String(item_id))
				items.append(String(item_id))
		state.set_flag(t.title_flag(), 1)
	state.inc_flag(t.wins_flag())
	_close_run(state, t)
	out["outcome"] = CUP_WON
	out["gold"] = gold
	out["items"] = items
	out["first_cup"] = first
	return out


## One row per round for the ladder panel: {index, name, character_id, strength, status}
## (status "won" / "next" / "ahead"; with no run open every round is "ahead").
static func ladder_rows(state: StoryState, t: TournamentResource) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if t == null:
		return out
	var running: bool = is_running(state, t)
	var done: int = cleared(state, t)
	for i in range(t.round_count()):
		var spec: BattleSpec = t.rounds[i]
		if spec == null:
			continue
		var cid: String = ""
		if not spec.opponent_team.is_empty():
			cid = String(spec.opponent_team[0].get("character_id", ""))
		var status: String = "ahead"
		if running and i < done:
			status = "won"
		elif running and i == done:
			status = "next"
		out.append({"index": i, "name": spec.opponent_name, "character_id": cid,
			"strength": spec.lead_strength(state), "status": status})
	return out


static func _close_run(state: StoryState, t: TournamentResource) -> void:
	state.clear_flag(t.run_flag())
	state.clear_flag(t.round_flag())
