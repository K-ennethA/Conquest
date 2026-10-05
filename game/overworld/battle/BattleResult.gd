class_name BattleResult
extends RefCounted

## WHAT A BATTLE REPORTS BACK -- the return half of the shared contract (OVERWORLD.md §7.2,
## DUEL_BATTLE.md §8.3, DECISIONS.md). Produced by StoryBattleBridge (tactical) and by the duel
## (DuelResultBuilder; the debug DuelStub until feat/duel lands), delivered through
## StoryController.report_battle_result EXACTLY ONCE per battle.
##
## befriend_offer (DECISIONS.md): {character_id, accepted}. The battle only OFFERS (rolled on
## VICTORY off the battle's seeded stream, never randf()); the story prompt ("X wants to join
## you!") decides, and sets accepted / befriended when the player says yes.

const OUTCOME_VICTORY := "victory"
const OUTCOME_DEFEAT := "defeat"
const OUTCOME_FLED := "fled"
const OUTCOME_BEFRIENDED := "befriended"
const OUTCOME_ABORTED := "aborted"
const OUTCOMES: Array[String] = [OUTCOME_VICTORY, OUTCOME_DEFEAT, OUTCOME_FLED,
	OUTCOME_BEFRIENDED, OUTCOME_ABORTED]

var encounter_id: String = ""
var outcome: String = OUTCOME_ABORTED
## [{member_id, current_hp, wounded, fought, kos, ko_elements}] -- `fought` (default true) is
## false for a duel's bench member who never took the field; `kos` = enemy KOs it scored
## (EVOLUTION growth input, [StoryGrowth]); `ko_elements` (optional) = {element: KOs} of the foes
## it felled (battle feats, [BattleFeatTrigger]).
var party_after: Array = []
## Character ids of defeated foes (growth / evolution input).
var defeated: Array = []
## The STORY LEVEL of each defeated foe, parallel to [member defeated] (XP input,
## [StoryProgression]). May be empty (a result that does not know them): the XP maths then reads
## the request's opponent rows / enemy level instead.
var defeated_levels: Array = []
var befriended: String = ""
## {character_id, accepted, level} or {} when no offer (`level`: the foe's story level -- a
## befriended creature joins at it; 0 / missing = unknown).
var befriend_offer: Dictionary = {}
var turns: int = 0
## Battle items the player USED ({item_id: count}) -- taken from the story bag by
## [StoryResultApplier], whatever the outcome.
var items_used: Dictionary = {}
## A friendly SPAR (copied from the request): nobody falls for good in it.
var spar: bool = false
## Why this battle ENDED THE JOURNEY ("" = it did not): "hero" (the main character fell),
## "protect:<name>" (a unit the mission said to protect fell) or "wipe" (Classic: nobody left).
## Set by StoryController ([StoryPermadeath.game_over_reason]); a game over is never applied --
## the player goes back to the last save.
var game_over_reason: String = ""


func is_victory() -> bool:
	return outcome == OUTCOME_VICTORY or outcome == OUTCOME_BEFRIENDED


func is_defeat() -> bool:
	return outcome == OUTCOME_DEFEAT


func is_game_over() -> bool:
	return not game_over_reason.is_empty()


func has_open_offer() -> bool:
	return not befriend_offer.is_empty() \
		and not String(befriend_offer.get("character_id", "")).is_empty() \
		and not bool(befriend_offer.get("accepted", false))


static func make(p_encounter_id: String, p_outcome: String) -> BattleResult:
	var r := BattleResult.new()
	r.encounter_id = p_encounter_id
	r.outcome = p_outcome if OUTCOMES.has(p_outcome) else OUTCOME_ABORTED
	return r


func to_dict() -> Dictionary:
	return {
		"encounter_id": encounter_id,
		"outcome": outcome,
		"party_after": party_after.duplicate(true),
		"defeated": defeated.duplicate(),
		"defeated_levels": defeated_levels.duplicate(),
		"befriended": befriended,
		"befriend_offer": befriend_offer.duplicate(true),
		"turns": turns,
		"items_used": items_used.duplicate(),
		"spar": spar,
		"game_over_reason": game_over_reason,
	}


static func from_dict(d) -> BattleResult:
	if not (d is Dictionary):
		return null
	var o: String = String(d.get("outcome", ""))
	if not OUTCOMES.has(o):
		return null
	var r := BattleResult.new()
	r.encounter_id = String(d.get("encounter_id", ""))
	r.outcome = o
	var pa = d.get("party_after", [])
	if pa is Array:
		for e in pa:
			if e is Dictionary:
				r.party_after.append({
					"member_id": String(e.get("member_id", "")),
					"current_hp": int(e.get("current_hp", StoryPartyMember.HP_FULL)),
					"wounded": bool(e.get("wounded", false)),
					"fought": bool(e.get("fought", true)),
					"kos": maxi(0, int(e.get("kos", 0))),
					"ko_elements": _count_map(e.get("ko_elements", {})),
				})
	var df = d.get("defeated", [])
	if df is Array:
		for e in df:
			r.defeated.append(String(e))
	var dl = d.get("defeated_levels", [])
	if dl is Array:
		for e in dl:
			r.defeated_levels.append(maxi(0, int(e)) if (e is int or e is float) else 0)
	r.befriended = String(d.get("befriended", ""))
	var off = d.get("befriend_offer", {})
	if off is Dictionary and not off.is_empty():
		r.befriend_offer = {
			"character_id": String(off.get("character_id", "")),
			"accepted": bool(off.get("accepted", false)),
		}
		# The level it was met at -- only when the battle knew one (a level-less offer keeps its shape).
		var lv = off.get("level", 0)
		if (lv is int or lv is float) and int(lv) > 0:
			r.befriend_offer["level"] = int(lv)
	r.turns = maxi(0, int(d.get("turns", 0)))
	r.items_used = _count_map(d.get("items_used", {}))
	r.spar = bool(d.get("spar", false))
	r.game_over_reason = String(d.get("game_over_reason", ""))
	return r


## {String: int > 0} from a JSON-parsed map (CONQUEST.md rule 3); {} for anything else.
static func _count_map(raw) -> Dictionary:
	var out: Dictionary = {}
	if raw is Dictionary:
		for k in raw.keys():
			var n: int = int(raw[k]) if (raw[k] is int or raw[k] is float) else 0
			if not String(k).is_empty() and n > 0:
				out[String(k)] = n
	return out


func _to_string() -> String:
	return "BattleResult(%s %s)" % [encounter_id, outcome]
