class_name StoryPartyMember
extends RefCounted

## ONE PERSISTENT INDIVIDUAL in the story party -- the record the overworld save stores, the
## battle bridge fields and the duel receives (BattleRequest.party[]).
##
## SHARED CONTRACT (docs/design/DECISIONS.md "Shared contracts"): the story party stores
## EVOLUTION's RosterLedger-style member records -- one record type, not two. EVOLUTION's
## RosterLedger is not on this branch yet, so this is the minimal COMPATIBLE record:
##
##   RosterLedger member         StoryPartyMember
##   ------------------------    ----------------------------------------------------
##   uid (dictionary key)        member_id  -- same scheme: "<line>" then "<line>#2" ...
##   line                        line       -- the evolution line's root character id
##   form                        character_id -- the CURRENT form (what spawns / fights)
##   nickname                    nickname
##   growth, evolved             growth     -- opaque dictionary, owned by EVOLUTION
##   (story only)                current_hp, wounded, item_id
##
## At the merge with feat/evolution: `growth` carries RosterLedger's growth/evolved payload
## verbatim, and RosterLedger.member_for_character / form_of can be answered from these
## records (see the merge notes in docs/STORY_MODE.md). The overworld only
## ever READS/WRITES member_id, character_id, nickname, current_hp, wounded and item_id;
## member_id NEVER changes (an evolution rewrites character_id and keeps everything else).

## current_hp sentinel: full health (the same idea as ArenaUnitState.HP_FULL).
const HP_FULL: int = -1

var member_id: String = ""
var character_id: String = ""
var line: String = ""
var nickname: String = ""
var current_hp: int = HP_FULL
## KO'd in the last battle: cannot be fielded until healed (a Wayshrine).
var wounded: bool = false
var item_id: String = ""
## EVOLUTION-owned growth payload. Opaque to the overworld; round-tripped unchanged.
var growth: Dictionary = {}


static func create(p_member_id: String, p_character_id: String, p_nickname: String = "") -> StoryPartyMember:
	var m := StoryPartyMember.new()
	m.member_id = p_member_id
	m.character_id = p_character_id
	m.line = p_character_id
	m.nickname = p_nickname
	return m


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


## Can this member be sent into a battle?
func is_fieldable() -> bool:
	return not wounded and hp_value() > 0


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
		"growth": growth.duplicate(true),
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
	m.line = String(d.get("line", cid))
	if m.line.is_empty():
		m.line = cid
	m.nickname = String(d.get("nickname", ""))
	m.current_hp = int(d.get("current_hp", HP_FULL))
	if m.current_hp < HP_FULL:
		m.current_hp = HP_FULL
	m.wounded = bool(d.get("wounded", false))
	m.item_id = String(d.get("item_id", ""))
	var g = d.get("growth", {})
	m.growth = (g as Dictionary).duplicate(true) if g is Dictionary else {}
	return m


func _to_string() -> String:
	return "Member %s (%s, hp %s%s)" % [member_id, character_id,
		"full" if current_hp == HP_FULL else str(current_hp), ", wounded" if wounded else ""]
