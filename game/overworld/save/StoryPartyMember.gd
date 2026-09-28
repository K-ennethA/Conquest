class_name StoryPartyMember
extends RefCounted

## ONE PERSISTENT INDIVIDUAL in the story party -- the record the overworld save stores, the
## battle bridge fields and the duel receives (BattleRequest.party[]).
##
## SHARED CONTRACT (docs/design/DECISIONS.md "Shared contracts"): the story party stores
## EVOLUTION's RosterLedger member records -- one record type, not two. A StoryPartyMember IS
## the STORY-SCOPED VIEW of one RosterLedger member record, kept inside the journey's own save
## slot (docs/STORY_MODE.md "Party records"):
##
##   RosterLedger member         StoryPartyMember
##   ------------------------    ----------------------------------------------------
##   uid (dictionary key)        member_id  -- same scheme: "<line>" then "<line>#2" ...
##   line                        line       -- the evolution line's root character id
##   form                        character_id -- the CURRENT form (what spawns / fights)
##   nickname                    nickname
##   growth, evolved, feats      growth     -- {"growth": int, "evolved": [{edge, at}],
##                                             "feats": {wins, kos, clutch_wins, element_kos}}
##   hold                        hold       -- no automatic evolve prompts (DECISIONS.md #27)
##   (story only)                current_hp, wounded, item_id
##
## [method ledger_record] hands EVOLUTION the exact RosterLedger record and
## [method apply_ledger_record] folds an evolved one back, so every evolution rule runs through
## RosterLedger's record-level API ([StoryGrowth]); the global roster.json only receives the
## open-mode UNLOCK. The overworld itself only READS/WRITES member_id, character_id, nickname,
## current_hp, wounded and item_id; member_id NEVER changes (an evolution rewrites
## character_id and keeps everything else). Unknown keys inside `growth` round-trip untouched.

## current_hp sentinel: full health (the same idea as ArenaUnitState.HP_FULL).
const HP_FULL: int = -1
## Keys of the RosterLedger payload inside [member growth].
const GROWTH_KEY := "growth"
const EVOLVED_KEY := "evolved"
const FEATS_KEY := "feats"

var member_id: String = ""
var character_id: String = ""
var line: String = ""
var nickname: String = ""
var current_hp: int = HP_FULL
## KO'd in the last battle: cannot be fielded until healed (a Wayshrine).
var wounded: bool = false
var item_id: String = ""
## HOLD (DECISIONS.md #27): no automatic evolution prompts for this member while true; a manual
## EVOLVE from Journey -> Party still works. Saved as "hold"; an older save loads it as false.
var hold: bool = false
## EVOLUTION-owned growth payload ({"growth": int, "evolved": [...]}, RosterLedger's). Opaque to
## the overworld; read and written only through the ledger-record helpers below.
var growth: Dictionary = {}
## FALLEN (the Classic tier's permadeath, docs/design/DECISIONS.md #29 + refinements): where and
## when this member fell -- {area_id, encounter_id, foe, kind, play_seconds, at_utc, item_id} --
## or {} while it lives. A fallen member is KEPT as a record (form, growth, nickname) in
## [member StoryState.fallen], never deleted, so a later mechanic can bring it back. Saved as
## "fallen"; an older save loads it as {}.
var fallen_info: Dictionary = {}
## The MAIN CHARACTER as a battle unit (the hero is not one yet -- this is the hook): falling in
## any real battle is always a GAME OVER ([StoryPermadeath]). Saved as "hero".
var is_hero: bool = false


static func create(p_member_id: String, p_character_id: String, p_nickname: String = "") -> StoryPartyMember:
	var m := StoryPartyMember.new()
	m.member_id = p_member_id
	m.character_id = p_character_id
	m.line = line_of(p_character_id)
	m.nickname = p_nickname
	return m


## The evolution LINE [param p_character_id] belongs to (its root form; itself outside any line).
static func line_of(p_character_id: String) -> String:
	if p_character_id.is_empty():
		return ""
	var root: String = String(EvolutionLibrary.line_root(StringName(p_character_id)))
	return root if not root.is_empty() else p_character_id


# --- The RosterLedger record ------------------------------------------------------

## This member as EVOLUTION's RosterLedger record {line, form, growth, evolved, nickname}
## (a copy: hand it to RosterLedger's record-level API, then [method apply_ledger_record]).
func ledger_record() -> Dictionary:
	return {
		"line": line,
		"form": character_id,
		"growth": growth_points(),
		"evolved": evolution_history(),
		"nickname": nickname,
		"hold": hold,
		"feats": feats(),
	}


## Fold a (possibly evolved) RosterLedger record back into this member: the form becomes
## [member character_id], growth / history land in [member growth]. member_id, nickname, HP and
## the item are the member's own and are not touched here.
func apply_ledger_record(rec: Dictionary) -> void:
	var form: String = String(rec.get("form", ""))
	if not form.is_empty():
		character_id = form
	var rec_line: String = String(rec.get("line", ""))
	if not rec_line.is_empty():
		line = rec_line
	growth[GROWTH_KEY] = maxi(0, int(rec.get("growth", 0)))
	var ev = rec.get("evolved", [])
	growth[EVOLVED_KEY] = (ev as Array).duplicate(true) if ev is Array else []
	if rec.has("feats"):
		growth[FEATS_KEY] = RosterLedger.normalize_feats(rec["feats"])


## Cumulative Growth (RosterLedger's "growth"; 0 for a member that never earned any).
func growth_points() -> int:
	return maxi(0, int(growth.get(GROWTH_KEY, 0)))


## Add [param n] Growth (a non-positive n is a no-op) and return the new total.
func add_growth(n: int) -> int:
	if n > 0:
		growth[GROWTH_KEY] = growth_points() + n
	return growth_points()


## The battle-feat counters ([BattleFeatTrigger]; RosterLedger's "feats" shape, a copy).
func feats() -> Dictionary:
	return RosterLedger.normalize_feats(growth.get(FEATS_KEY, {}))


## Add the feat deltas [param delta] ([method GrowthTracker.compute_feats] shape).
func add_feats(delta: Dictionary) -> void:
	var rec: Dictionary = {"feats": feats()}
	RosterLedger.apply_feats(rec, delta)
	growth[FEATS_KEY] = rec["feats"]


## RosterLedger's evolution history [{edge, at}], oldest first (a copy).
func evolution_history() -> Array:
	var ev = growth.get(EVOLVED_KEY, [])
	var out: Array = []
	if ev is Array:
		for step in ev:
			if step is Dictionary:
				out.append({"edge": String(step.get("edge", "")), "at": String(step.get("at", ""))})
	return out


## The RosterLedger uid scheme: the first individual of a line is keyed by the line itself,
## later ones get "#2", "#3"... so a party can hold two Petalfangs without a schema change.
static func uid_for(p_line: String, taken: Array) -> String:
	if not taken.has(p_line):
		return p_line
	var n: int = 2
	while taken.has("%s#%d" % [p_line, n]):
		n += 1
	return "%s#%d" % [p_line, n]


func character() -> CharacterResource:
	return CharacterLibrary.get_character(StringName(character_id))


func display_name() -> String:
	if not nickname.strip_edges().is_empty():
		return nickname
	var c: CharacterResource = character()
	if c != null and not c.display_name.strip_edges().is_empty():
		return c.display_name
	return character_id.capitalize()


## Max HP from the roster (the unit's base_health), or 1 when the character is unknown.
func max_hp() -> int:
	var c: CharacterResource = character()
	return maxi(1, c.base_health) if c != null else 1


## The HP this member would enter a battle with (the HP_FULL sentinel resolved).
func hp_value() -> int:
	if current_hp == HP_FULL:
		return max_hp()
	return clampi(current_hp, 0, max_hp())


func is_full_hp() -> bool:
	return current_hp == HP_FULL or current_hp >= max_hp()


## Can this member be sent into a battle? (Never a FALLEN one.)
func is_fieldable() -> bool:
	return not is_fallen() and not wounded and hp_value() > 0


## True once this member FELL for good (Classic tier) -- see [member fallen_info].
func is_fallen() -> bool:
	return not fallen_info.is_empty()


func heal_full() -> void:
	current_hp = HP_FULL
	wounded = false


func to_dict() -> Dictionary:
	return {
		"member_id": member_id,
		"character_id": character_id,
		"line": line,
		"nickname": nickname,
		"current_hp": current_hp,
		"wounded": wounded,
		"item_id": item_id,
		"hold": hold,
		"growth": growth.duplicate(true),
		"fallen": fallen_info.duplicate(true),
		"hero": is_hero,
	}


## Rebuild from a JSON-parsed dictionary. Returns null (never logs -- CONQUEST.md rule 1) when
## the blob is not a usable record; the snapshot loader skips those.
static func from_dict(d) -> StoryPartyMember:
	if not (d is Dictionary):
		return null
	var cid: String = String(d.get("character_id", "")).strip_edges()
	var mid: String = String(d.get("member_id", "")).strip_edges()
	if cid.is_empty() or mid.is_empty():
		return null
	var m := StoryPartyMember.new()
	m.member_id = mid
	m.character_id = cid
	m.line = String(d.get("line", ""))
	if m.line.is_empty():
		m.line = line_of(cid)
	m.nickname = String(d.get("nickname", ""))
	m.current_hp = int(d.get("current_hp", HP_FULL))
	if m.current_hp < HP_FULL:
		m.current_hp = HP_FULL
	m.wounded = bool(d.get("wounded", false))
	m.item_id = String(d.get("item_id", ""))
	m.hold = bool(d.get("hold", false))
	var g = d.get("growth", {})
	m.growth = (g as Dictionary).duplicate(true) if g is Dictionary else {}
	m.fallen_info = sanitize_fallen(d.get("fallen", {}))
	m.is_hero = bool(d.get("hero", false))
	return m


## A saved fall record, coerced key by key (CONQUEST.md rule 3); {} for anything that is not one.
static func sanitize_fallen(raw) -> Dictionary:
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		return {}
	var d: Dictionary = raw
	return {
		"area_id": String(d.get("area_id", "")),
		"encounter_id": String(d.get("encounter_id", "")),
		"foe": String(d.get("foe", "")),
		"kind": String(d.get("kind", "")),
		"play_seconds": maxi(0, int(d.get("play_seconds", 0))),
		"at_utc": String(d.get("at_utc", "")),
		"item_id": String(d.get("item_id", "")),
	}


func _to_string() -> String:
	return "Member %s (%s, hp %s%s%s)" % [member_id, character_id,
		"full" if current_hp == HP_FULL else str(current_hp), ", wounded" if wounded else "",
		(", hold" if hold else "") + (", FALLEN" if is_fallen() else "")]
