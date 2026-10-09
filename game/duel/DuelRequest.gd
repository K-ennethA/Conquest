extends RefCounted
class_name DuelRequest

## Everything a duel needs to start (docs/design/DUEL_BATTLE.md §8.2): the two parties, the
## stage, the rules and the seed. What the stage, replays and saves use; built by DuelSetup
## (standalone), and later from OVERWORLD's BattleRequest ([method from_battle_request]).
##
## [method from_dict] is a STRICT importer (CONQUEST.md rule 8): a replay header is shared,
## untrusted JSON, so every id is checked against the libraries and no path is ever loaded.

const KIND_WILD := "wild"
const KIND_TRAINER := "trainer"
const KIND_STORY := "story"
const KIND_STANDALONE := "standalone"
const KIND_VERSUS := "versus"
const KINDS: Array[String] = [KIND_WILD, KIND_TRAINER, KIND_STORY, KIND_STANDALONE, KIND_VERSUS]

const ORIGIN_STANDALONE := "standalone"
const ORIGIN_STORY := "story"

## Stage looks the M1 stage can dress (DuelStage), and the station tile each implies.
const STAGES := {
	"meadow": &"grass_plains",
	"tall_grass": &"tall_grass",
	"grove": &"forest_dirt",
}
const RULESETS := {
	"default": "res://game/duel/rulesets/default_duel.tres",
}

## rules["opening"] values (mirror the overworld's BattleRequest.OPENING_*; see [method opening_side]).
const RULE_OPENING := "opening"
const OPENING_AMBUSH := "ambush"
const OPENING_AMBUSHED := "ambushed"
const OPENING_NEUTRAL := "neutral"
const OPENINGS: Array[String] = [OPENING_AMBUSH, OPENING_AMBUSHED, OPENING_NEUTRAL]

var kind: String = KIND_STANDALONE
var origin: String = ORIGIN_STANDALONE
## Side A (the player / challenger) and side B (the foe), lead first.
var player_party: Array[DuelCombatant] = []
var foe_party: Array[DuelCombatant] = []
var stage_id: String = "meadow"
## Tile both stations stand on ("" = the stage's own).
var station_tile_id: StringName = &""
var weather_id: StringName = &"clear"
var ruleset_id: String = "default"
## The duel RNG root. 0 = draw fresh entropy when the duel starts (DECISIONS.md: every
## battle starts from fresh entropy; the seed that was used is recorded in the result).
var seed: int = 0
var encounter_id: String = ""
## Who drives each side. The player side is human unless [member player_is_ai]
## (AI-vs-AI smoke runs, determinism tests).
var player_is_ai: bool = false
var foe_is_ai: bool = true
## BotController.Difficulty for the AI side(s); -1 = the ruleset's.
var ai_difficulty: int = -1
var player_ai_difficulty: int = -1
## The ENCOUNTER's rules, the story BattleRequest's `rules` subset the duel honours:
## {can_flee, can_befriend, story_critical, spar} (bools). A missing key = the kind's default: a
## WILD duel may be fled and its beaten foe may offer to join; any other duel neither. A
## story-critical recruit ALWAYS offers on a win (DECISIONS.md: never missable). `spar` only
## changes the intro line (a friendly -- the story decides what it means, DECISIONS.md #29).
var rules: Dictionary = {}
## The player side's BATTLE ITEMS ({item_id: count}) for the Items action -- the story bag's
## consumables usable in battle (a standalone duel has none). Only known battle consumables survive
## the importer.
var items: Dictionary = {}
## The FORMAT ([DuelFormat]: team size, switching, KO replacement, item rules, species clause,
## strength cap). Null = Singles (the strict 1v1 every older request meant). Each side's TEAM is
## the first team_size members of its party ([method team_of]); the rest never take the field.
var format: DuelFormat = null


## A standalone 1v1 of two roster ids.
static func standalone(player_id: StringName, foe_id: StringName, difficulty: int = -1) -> DuelRequest:
	var r := DuelRequest.new()
	r.player_party.append(DuelCombatant.make(player_id))
	r.foe_party.append(DuelCombatant.make(foe_id))
	r.ai_difficulty = difficulty
	return r


## A standalone PARTY duel: [param player_ids] vs [param foe_ids] (lead first) under
## [param p_format] (default: a custom format sized to the larger team, switching on).
static func teams(player_ids: Array, foe_ids: Array, p_format: DuelFormat = null, difficulty: int = -1) -> DuelRequest:
	var r := DuelRequest.new()
	for id in player_ids:
		r.player_party.append(DuelCombatant.make(StringName(String(id)), "%s_%d" % [String(id), r.player_party.size()]))
	for id in foe_ids:
		r.foe_party.append(DuelCombatant.make(StringName(String(id)), "%s_%d" % [String(id), r.foe_party.size()]))
	if p_format == null:
		p_format = DuelFormat.preset(DuelFormat.STORY)
		p_format.id = DuelFormat.CUSTOM
		p_format.display_name = "Custom"
		p_format.team_size = clampi(maxi(player_ids.size(), foe_ids.size()), 1, DuelFormat.MAX_TEAM)
	r.format = p_format
	r.ai_difficulty = difficulty
	return r


func is_wild() -> bool:
	return kind == KIND_WILD


## May the player run from this duel (the ruleset's allow_flee must agree -- DuelBattle)?
func can_flee() -> bool:
	return bool(rules.get("can_flee", is_wild()))


## May the beaten foe offer to join (rolled on VICTORY off the duel's seeded stream)?
func can_befriend() -> bool:
	return bool(rules.get("can_befriend", is_wild()))


## A non-missable story recruit: a won duel always offers.
func is_story_critical() -> bool:
	return bool(rules.get("story_critical", false))


## A friendly SPAR (a story training bout): the intro says so.
func is_spar() -> bool:
	return bool(rules.get("spar", false))


## The CONTACT OPENING of a story wild duel (rules["opening"], the overworld's BattleRequest
## RULE_OPENING): the side that acts first in ROUND 1 whatever the speeds -- 0 (the player:
## "ambush", the hero walked into its back), 1 (the foe: "ambushed", it walked into the hero), or
## -1 (speed order as always: "neutral" / no key). Read by [DuelBattle.setup] into
## [member DuelTurnSystem.first_side]. Recorded with the request, so a replay starts the same way.
func opening_side() -> int:
	match String(rules.get(RULE_OPENING, "")):
		OPENING_AMBUSH:
			return 0
		OPENING_AMBUSHED:
			return 1
	return -1


## The station tile to register ([member station_tile_id], else the stage's).
func resolved_station_tile_id() -> StringName:
	if station_tile_id != &"":
		return station_tile_id
	return StringName(STAGES.get(stage_id, &"grass_plains"))


## The ruleset this request names (the default when unknown) -- the SHARED resource; a duel
## plays on [method battle_rules] (the format applied to a copy).
func load_ruleset() -> DuelRuleset:
	var path: String = String(RULESETS.get(ruleset_id, ""))
	if path != "" and ResourceLoader.exists(path):
		var rs = load(path)
		if rs is DuelRuleset:
			return rs
	return DuelRuleset.load_default()


## The format in force ([member format], else Singles).
func effective_format() -> DuelFormat:
	return format if format != null else DuelFormat.preset(DuelFormat.SINGLES)


## The rules this duel plays by: the named ruleset with the format written onto a private copy.
func battle_rules() -> DuelRuleset:
	return effective_format().apply_to(load_ruleset())


## Side [param side]'s TEAM (0 = player, 1 = foe): the first team_size members of its party.
func team_of(side: int) -> Array[DuelCombatant]:
	var party: Array[DuelCombatant] = player_party if side == 0 else foe_party
	var n: int = mini(party.size(), effective_format().team_size)
	var out: Array[DuelCombatant] = []
	for i in range(n):
		out.append(party[i])
	return out


## Semantic validation. Returns { success, reason } (rule 1: never logs).
func validate() -> Dictionary:
	if not (kind in KINDS):
		return {"success": false, "reason": "unknown_kind"}
	if player_party.is_empty() or foe_party.is_empty():
		return {"success": false, "reason": "empty_party"}
	var known := CharacterLibrary.all_ids()
	for c in player_party + foe_party:
		if c == null or not (c.character_id in known):
			return {"success": false, "reason": "unknown_character"}
	if not STAGES.has(stage_id):
		return {"success": false, "reason": "unknown_stage"}
	if TileCatalog.find_by_id(resolved_station_tile_id()) == null:
		return {"success": false, "reason": "unknown_station_tile"}
	if not Weather.has_weather(weather_id):
		return {"success": false, "reason": "unknown_weather"}
	if not RULESETS.has(ruleset_id):
		return {"success": false, "reason": "unknown_ruleset"}
	var f := effective_format()
	var fcheck := f.validate()
	if not bool(fcheck["success"]):
		return fcheck
	for side in 2:
		var ids: Array = []
		for c in team_of(side):
			ids.append(String(c.character_id))
		var problem := f.team_problem(ids, false)
		if problem != "":
			return {"success": false, "reason": problem}
	return {"success": true, "reason": ""}


func to_dict() -> Dictionary:
	var a: Array = []
	for c in player_party:
		a.append(c.to_dict())
	var b: Array = []
	for c in foe_party:
		b.append(c.to_dict())
	return {
		"kind": kind,
		"origin": origin,
		"player_party": a,
		"foe_party": b,
		"stage_id": stage_id,
		"station_tile_id": String(station_tile_id),
		"weather_id": String(weather_id),
		"ruleset_id": ruleset_id,
		"seed": seed,
		"encounter_id": encounter_id,
		"player_is_ai": player_is_ai,
		"foe_is_ai": foe_is_ai,
		"ai_difficulty": ai_difficulty,
		"player_ai_difficulty": player_ai_difficulty,
		"rules": rules.duplicate(),
		"items": items.duplicate(),
		"format": effective_format().to_dict(),
	}


## STRICT importer. Returns { success, reason, request }.
static func from_dict(d) -> Dictionary:
	if not (d is Dictionary):
		return _fail("not_a_dictionary")
	var r := DuelRequest.new()
	r.kind = _str(d.get("kind", KIND_STANDALONE))
	r.origin = _str(d.get("origin", ORIGIN_STANDALONE))
	if not (r.origin in [ORIGIN_STANDALONE, ORIGIN_STORY]):
		return _fail("unknown_origin")
	for key in ["player_party", "foe_party"]:
		var raw = d.get(key, [])
		if not (raw is Array):
			return _fail("bad_" + key)
		var party: Array[DuelCombatant] = []
		for entry in raw:
			var res := DuelCombatant.from_dict(entry)
			if not bool(res["success"]):
				return _fail(String(res["reason"]))
			party.append(res["combatant"])
		if key == "player_party":
			r.player_party = party
		else:
			r.foe_party = party
	r.stage_id = _str(d.get("stage_id", "meadow"))
	r.station_tile_id = StringName(_str(d.get("station_tile_id", "")))
	r.weather_id = StringName(_str(d.get("weather_id", "clear")))
	r.ruleset_id = _str(d.get("ruleset_id", "default"))
	for key in ["seed", "ai_difficulty", "player_ai_difficulty"]:
		var v = d.get(key, 0 if key == "seed" else -1)
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			return _fail("bad_" + key)
	r.seed = int(d.get("seed", 0))
	r.ai_difficulty = clampi(int(d.get("ai_difficulty", -1)), -1, 3)
	r.player_ai_difficulty = clampi(int(d.get("player_ai_difficulty", -1)), -1, 3)
	r.encounter_id = _str(d.get("encounter_id", ""))
	r.player_is_ai = bool(d.get("player_is_ai", false))
	r.foe_is_ai = bool(d.get("foe_is_ai", true))
	var raw_rules = d.get("rules", {})
	if not (raw_rules is Dictionary):
		return _fail("bad_rules")
	for key in ["can_flee", "can_befriend", "story_critical", "spar"]:
		if (raw_rules as Dictionary).has(key):
			var v = raw_rules[key]
			if typeof(v) != TYPE_BOOL:
				return _fail("bad_rules")
			r.rules[key] = v
	# The contact opening (a visible wild creature): a known string or nothing.
	if (raw_rules as Dictionary).has(RULE_OPENING):
		var o = raw_rules[RULE_OPENING]
		if not (o is String or o is StringName) or not OPENINGS.has(String(o)):
			return _fail("bad_rules")
		r.rules[RULE_OPENING] = String(o)
	var raw_items = d.get("items", {})
	if not (raw_items is Dictionary):
		return _fail("bad_items")
	r.items = battle_item_counts(raw_items)
	if d.has("format"):
		var fres := DuelFormat.from_dict(d["format"])
		if not bool(fres["success"]):
			return _fail(String(fres["reason"]))
		r.format = fres["format"]
	var check := r.validate()
	if not bool(check["success"]):
		return _fail(String(check["reason"]))
	return {"success": true, "reason": "", "request": r}


## {item_id: count} kept only for known consumables usable in battle with a positive count
## (untrusted input: ids resolved through [ItemLibrary], never paths).
static func battle_item_counts(raw) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for k in raw.keys():
		var v = raw[k]
		var n: int = int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else 0
		var item: ItemResource = ItemLibrary.get_item(String(k))
		if n > 0 and item != null and item.consumable != null and item.consumable.usable_in_battle:
			out[String(k)] = mini(n, 999)
	return out


## Adapt OVERWORLD's BattleRequest (as its to_dict() shape) into a duel request: party ->
## player_party (lead first), opponent.team -> foe_party, backdrop -> stage / station tile /
## weather, source "wild" -> KIND_WILD. Strict like [method from_dict]. The real
## BattleRequest class lives on the overworld branch; this reads its documented fields only.
static func from_battle_request(br) -> Dictionary:
	if not (br is Dictionary):
		return _fail("not_a_dictionary")
	var party: Array = []
	for m in br.get("party", []):
		if m is Dictionary:
			party.append({"member_id": _str(m.get("member_id", "")),
				"character_id": m.get("character_id", ""), "current_hp": m.get("current_hp", -1),
				"item_ids": [m.get("item_id")] if _str(m.get("item_id", "")) != "" else [],
				"level": _level_of(m.get("level", 0)), "weapon_id": _str(m.get("weapon_id", ""))})
	var source := _str(br.get("source", "wild"))
	var foes: Array = []
	var opponent = br.get("opponent", {})
	# STORY LEVELS (PROGRESSION.md): a row's own "level", else the request's enemy_level.
	var enemy_level: int = _level_of(br.get("enemy_level", 0))
	if opponent is Dictionary:
		for t in opponent.get("team", []):
			if t is Dictionary:
				var lv: int = _level_of(t.get("level", 0))
				foes.append({"character_id": t.get("character_id", ""),
					"strength": t.get("strength", 1.0), "level": lv if lv > 0 else enemy_level})
	# A wild encounter is ONE foe (DECISIONS.md #3), whatever the table authored.
	if source == "wild" and foes.size() > 1:
		foes = foes.slice(0, 1)
	var backdrop = br.get("backdrop", {})
	var tile_id := ""
	var weather := "clear"
	if backdrop is Dictionary:
		tile_id = _str(backdrop.get("tile_id", ""))
		weather = _str(backdrop.get("weather", "clear")).to_lower()
	# The ground you stood on becomes the station tile when the duel knows it; an unknown
	# overworld tile or weather falls back to the stage's own instead of refusing the duel.
	if tile_id != "" and TileCatalog.find_by_id(StringName(tile_id)) == null:
		tile_id = ""
	if weather == "" or not Weather.has_weather(StringName(weather)):
		weather = "clear"
	var story_rules: Dictionary = {}
	var raw_rules = br.get("rules", {})
	# The story's duel FORMAT: the battle's own ("duel_format": a preset id), else the duel
	# ruleset's story default -- the party lead plus up to (team size - 1) bench members.
	var format_id: String = DuelRuleset.load_default().story_format
	if raw_rules is Dictionary:
		for key in ["can_flee", "can_befriend", "story_critical", "spar"]:
			if (raw_rules as Dictionary).has(key):
				story_rules[key] = bool(raw_rules[key])
		var raw_opening = (raw_rules as Dictionary).get(RULE_OPENING, "")
		if (raw_opening is String or raw_opening is StringName) and OPENINGS.has(String(raw_opening)):
			story_rules[RULE_OPENING] = String(raw_opening)
		var raw_format = (raw_rules as Dictionary).get("duel_format", "")
		if (raw_format is String or raw_format is StringName) and DuelFormat.preset(String(raw_format)) != null:
			format_id = String(raw_format)
	var d := {
		"kind": KIND_WILD if source == "wild" else (KIND_TRAINER if source == "trainer" else KIND_STORY),
		"origin": ORIGIN_STORY,
		"player_party": party,
		"foe_party": foes,
		"stage_id": "tall_grass" if tile_id == "tall_grass" else "meadow",
		"station_tile_id": tile_id,
		"weather_id": weather,
		"seed": br.get("seed", 0),
		"encounter_id": _str(br.get("encounter_id", "")),
		"rules": story_rules,
		"items": br.get("items", {}) if br.get("items", {}) is Dictionary else {},
		"format": format_id if DuelFormat.preset(format_id) != null else DuelFormat.STORY,
	}
	return from_dict(d)


static func _fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason, "request": null}


static func _str(v) -> String:
	return String(v) if (typeof(v) == TYPE_STRING or typeof(v) == TYPE_STRING_NAME) else ""


## A story level from untrusted JSON: a non-negative int, 0 for anything else.
static func _level_of(v) -> int:
	return clampi(int(v), 0, 200) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) else 0
