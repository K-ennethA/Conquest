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
## [{member_id, current_hp, wounded, fought, kos}] -- `fought` (default true) is false for a
## duel's bench member who never took the field; `kos` = enemy KOs it scored (EVOLUTION growth
## input, [StoryGrowth]).
var party_after: Array = []
## Character ids of defeated foes (growth / evolution input).
var defeated: Array = []
var befriended: String = ""
## {character_id, accepted} or {} when no offer.
var befriend_offer: Dictionary = {}
var turns: int = 0


func is_victory() -> bool:
	return outcome == OUTCOME_VICTORY or outcome == OUTCOME_BEFRIENDED


func is_defeat() -> bool:
	return outcome == OUTCOME_DEFEAT


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
		"befriended": befriended,
		"befriend_offer": befriend_offer.duplicate(true),
		"turns": turns,
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
				})
	var df = d.get("defeated", [])
	if df is Array:
		for e in df:
			r.defeated.append(String(e))
	r.befriended = String(d.get("befriended", ""))
	var off = d.get("befriend_offer", {})
	if off is Dictionary and not off.is_empty():
		r.befriend_offer = {
			"character_id": String(off.get("character_id", "")),
			"accepted": bool(off.get("accepted", false)),
		}
	r.turns = maxi(0, int(d.get("turns", 0)))
	return r


func _to_string() -> String:
	return "BattleResult(%s %s)" % [encounter_id, outcome]
