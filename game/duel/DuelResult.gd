extends RefCounted
class_name DuelResult

## How a duel ended (docs/design/DUEL_BATTLE.md §8.3). A superset of OVERWORLD's
## BattleResult: [method to_battle_result] produces exactly that contract's shape
## (plus DECISIONS.md's befriend_offer), the rest feeds the results card, replays and stats.
##
## The duel never writes the story save, gold, flags, inventory or the RosterLedger.

const OUTCOME_VICTORY := "victory"
const OUTCOME_DEFEAT := "defeat"
const OUTCOME_FLED := "fled"
const OUTCOME_BEFRIENDED := "befriended"
const OUTCOME_ABORTED := "aborted"

var encounter_id: String = ""
var outcome: String = OUTCOME_ABORTED
## 0 = the player side (A) won, 1 = the foe side (B), -1 = nobody (aborted).
var winner_side: int = -1
var rounds: int = 0
## Commands applied (each unit action is one turn).
var turns: int = 0
## The duel RNG root actually used (fresh entropy unless the request pinned one).
var seed: int = 0
## [{member_id, character_id, current_hp, wounded}] for the player side, bench included.
var party_after: Array = []
## Foe character ids KO'd in this duel.
var defeated: Array = []
## character_id when a befriend offer was ACCEPTED ("" in M1: no acceptance UI yet).
var befriended: String = ""
## Wild duels won: {character_id, offered, accepted, chance, roll, subdued}; {} otherwise.
var befriend_offer: Dictionary = {}
## Per side (0 / 1): {damage_dealt, damage_taken, kos, moves_used: {move_id: n}}.
var stats: Array = [{}, {}]
## The applied command list (each stamped with its seq and per-action seed): the replay.
var commands: Array = []
## One row per applied command: {seq, actor, hp: [side A hp, side B hp]}.
var hp_timeline: Array = []
var replay_path: String = ""
## STANDALONE duels: the Growth this duel awarded (GrowthTracker's latch-row shape), for the
## results card. Empty in story (the story party's growth is StoryController's) and whenever
## "duel" is not in EvolutionRules.growth_modes.
var growth: Array = []


func player_won() -> bool:
	return winner_side == 0


## OVERWORLD's BattleResult shape (docs/design/OVERWORLD.md §7.2 + DECISIONS.md), as a
## Dictionary for [method BattleResult.from_dict]. The befriend offer is carried only when the
## roll actually OFFERED ({character_id, accepted}); a declined roll is no offer at all.
func to_battle_result() -> Dictionary:
	var offer: Dictionary = {}
	if bool(befriend_offer.get("offered", false)):
		offer = {"character_id": String(befriend_offer.get("character_id", "")),
			"accepted": bool(befriend_offer.get("accepted", false))}
	return {
		"encounter_id": encounter_id,
		"outcome": outcome,
		"party_after": party_after.duplicate(true),
		"defeated": defeated.duplicate(),
		"befriended": befriended,
		"turns": turns,
		"befriend_offer": offer,
	}


func to_dict() -> Dictionary:
	var d := to_battle_result()
	d["winner_side"] = winner_side
	d["rounds"] = rounds
	d["seed"] = seed
	d["stats"] = stats.duplicate(true)
	d["commands"] = commands.duplicate(true)
	d["hp_timeline"] = hp_timeline.duplicate(true)
	d["replay_path"] = replay_path
	return d


## One line for the results card ("Petalfang wants to join you!"), "" when there is none.
func befriend_line() -> String:
	if befriend_offer.is_empty() or not bool(befriend_offer.get("offered", false)):
		return ""
	var ch := CharacterLibrary.get_character(StringName(String(befriend_offer.get("character_id", ""))))
	var who: String = ch.display_name if ch != null else String(befriend_offer.get("character_id", ""))
	return "%s wants to join you!" % who
