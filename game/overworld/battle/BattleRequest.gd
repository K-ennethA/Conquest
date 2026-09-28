class_name BattleRequest
extends RefCounted

## WHAT STORY ASKS A BATTLE TO BE -- the launch half of the shared battle contract
## (docs/design/OVERWORLD.md §7.2, DUEL_BATTLE.md §8.2, DECISIONS.md "Shared contracts").
## The SAME shape goes to a tactical battle (StoryBattleBridge) and to a duel (DuelLauncher),
## so everything downstream is battle-kind agnostic. JSON-serialisable via to_dict/from_dict;
## from_dict is strict (unknown kinds refused, every field coerced -- CONQUEST.md rules 3, 8).

const KIND_TACTICAL := "tactical"
const KIND_DUEL := "duel"
const KINDS: Array[String] = [KIND_TACTICAL, KIND_DUEL]

const SOURCE_WILD := "wild"
const SOURCE_TRAINER := "trainer"
const SOURCE_SCRIPT := "script"

const DEFEAT_WHITEOUT := "whiteout"
const DEFEAT_CONTINUE := "continue"
const DEFEAT_RETRY := "retry"
const DEFEAT_POLICIES: Array[String] = [DEFEAT_WHITEOUT, DEFEAT_CONTINUE, DEFEAT_RETRY]

var kind: String = KIND_TACTICAL
## Stable id ("mossway.grass.petalfang", "trainer.mossway.bram").
var encounter_id: String = ""
var source: String = SOURCE_SCRIPT
## The battle's RNG root. Filled by StoryController with FRESH ENTROPY per battle
## (DECISIONS.md: every battle starts from fresh entropy; retrying re-rolls).
var seed: int = 0
## Ordered snapshot of the fielded party: [{member_id, character_id, current_hp, item_id, growth}].
var party: Array = []
## {name, speaker_id, portrait, team: [{character_id, strength, moves?}]}.
var opponent: Dictionary = {}
## {area_id, tile_id, environment_preset, lighting_preset, weather}.
var backdrop: Dictionary = {}
## {can_flee, can_befriend, defeat_policy, story_critical}.
var rules: Dictionary = {}
## Applied by StoryController, never by the battle: {gold, items: [...], points, flags: [...]}.
var rewards: Dictionary = {}
## The BATTLE ITEMS the player may use ({item_id: count}): the story bag's consumables that work in
## battle (StoryController fills it for a duel -- the Items action). What was used comes back as
## [member BattleResult.items_used] and is taken from the bag then.
var items: Dictionary = {}
var intro_scene: String = ""
var outro_scene: String = ""
# --- tactical only ---
var map_path: String = ""
var campaign_chapter: String = ""
var squad_size: int = 3
var ai_difficulty: int = 1
var clash_intro: bool = false
## {area_id, cell: [c, r, f], facing} -- where the player walks back in (StoryController fills it).
var return_to: Dictionary = {}


func is_duel() -> bool:
	return kind == KIND_DUEL


func defeat_policy() -> String:
	var p: String = String(rules.get("defeat_policy", DEFEAT_WHITEOUT))
	return p if DEFEAT_POLICIES.has(p) else DEFEAT_WHITEOUT


func can_flee() -> bool:
	return bool(rules.get("can_flee", kind == KIND_DUEL))


func can_befriend() -> bool:
	return bool(rules.get("can_befriend", false))


## Non-missable story recruit: a loss / flee leaves the encounter in the world.
func is_story_critical() -> bool:
	return bool(rules.get("story_critical", false))


func opponent_name() -> String:
	return String(opponent.get("name", ""))


## The first foe's character id ("" when none) -- a wild duel's befriend candidate.
func lead_foe_id() -> String:
	var team = opponent.get("team", [])
	if team is Array and not team.is_empty() and team[0] is Dictionary:
		return String(team[0].get("character_id", ""))
	return ""


func party_member_ids() -> Array:
	var out: Array = []
	for p in party:
		if p is Dictionary:
			out.append(String(p.get("member_id", "")))
	return out


func party_character_ids() -> Array:
	var out: Array = []
	for p in party:
		if p is Dictionary:
			out.append(String(p.get("character_id", "")))
	return out


func to_dict() -> Dictionary:
	return {
		"kind": kind,
		"encounter_id": encounter_id,
		"source": source,
		"seed": seed,
		"party": party.duplicate(true),
		"opponent": opponent.duplicate(true),
		"backdrop": backdrop.duplicate(true),
		"rules": rules.duplicate(true),
		"rewards": rewards.duplicate(true),
		"items": items.duplicate(true),
		"intro_scene": intro_scene,
		"outro_scene": outro_scene,
		"map_path": map_path,
		"campaign_chapter": campaign_chapter,
		"squad_size": squad_size,
		"ai_difficulty": ai_difficulty,
		"clash_intro": clash_intro,
		"return": return_to.duplicate(true),
	}


## Strict decode. Returns null (no log) for a blob that is not a request.
static func from_dict(d) -> BattleRequest:
	if not (d is Dictionary):
		return null
	var k: String = String(d.get("kind", ""))
	if not KINDS.has(k):
		return null
	var r := BattleRequest.new()
	r.kind = k
	r.encounter_id = String(d.get("encounter_id", ""))
	r.source = String(d.get("source", SOURCE_SCRIPT))
	r.seed = int(d.get("seed", 0))
	r.party = _dict_array(d.get("party", []))
	for p in r.party:
		p["current_hp"] = int(p.get("current_hp", StoryPartyMember.HP_FULL))
	r.opponent = _dict(d.get("opponent", {}))
	if r.opponent.has("team"):
		r.opponent["team"] = _dict_array(r.opponent["team"])
	r.backdrop = _dict(d.get("backdrop", {}))
	r.rules = _dict(d.get("rules", {}))
	r.rewards = _dict(d.get("rewards", {}))
	if r.rewards.has("gold"):
		r.rewards["gold"] = int(r.rewards["gold"])
	r.items = BattleResult._count_map(d.get("items", {}))
	r.intro_scene = String(d.get("intro_scene", ""))
	r.outro_scene = String(d.get("outro_scene", ""))
	r.map_path = String(d.get("map_path", ""))
	r.campaign_chapter = String(d.get("campaign_chapter", ""))
	r.squad_size = maxi(1, int(d.get("squad_size", 3)))
	r.ai_difficulty = int(d.get("ai_difficulty", 1))
	r.clash_intro = bool(d.get("clash_intro", false))
	r.return_to = _dict(d.get("return", {}))
	return r


static func _dict(v) -> Dictionary:
	return (v as Dictionary).duplicate(true) if v is Dictionary else {}


static func _dict_array(v) -> Array:
	var out: Array = []
	if v is Array:
		for e in v:
			if e is Dictionary:
				out.append((e as Dictionary).duplicate(true))
	return out


func _to_string() -> String:
	return "BattleRequest(%s %s vs %s)" % [kind, encounter_id, opponent_name()]
