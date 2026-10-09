class_name SquadPick
extends RefCounted

## PURE: WHO DEPLOYS into a story TACTICAL battle (docs/design/HUMANS.md "Deploying"). The
## [SquadPickScreen] is only a view over these rules, and the no-UI path (headless, tests, the
## picker switched off) takes [method default_picks] -- so a picked squad and an unpicked one are
## built the same way.
##
## A CANDIDATE is a Dictionary:
##   {id, character_id, name, level, kind: "human"/"creature", hero: bool, guest: bool,
##    temporary: bool, required: bool, member: bool}
## `id` is the party member id, or "guest:<character_id>" for a guest the BATTLE offers
## ([member BattleSpec.offered_guests]) who is not a party member. `member` false = such a guest.

const GUEST_PREFIX := "guest:"
## [member BattleSpec.hero_deploy] values, carried as request.rules["hero_deploy"].
const HERO_OPTIONAL := "optional"
const HERO_REQUIRED := "required"


## The hero rule of [param request] ("optional" unless it says "required").
static func hero_rule(request: BattleRequest) -> String:
	if request == null:
		return HERO_OPTIONAL
	return HERO_REQUIRED if String(request.rules.get("hero_deploy", HERO_OPTIONAL)) == HERO_REQUIRED else HERO_OPTIONAL


## The guests [param request] offers (character ids, request.rules["offered_guests"]).
static func offered_guests(request: BattleRequest) -> Array[String]:
	var out: Array[String] = []
	if request == null:
		return out
	var raw = request.rules.get("offered_guests", [])
	if raw is Array:
		for v in raw:
			var s: String = String(v).strip_edges()
			if not s.is_empty() and not out.has(s) and CharacterLibrary.get_character(StringName(s)) != null:
				out.append(s)
	return out


## Every unit that may deploy: the fieldable party (THE HERO FIRST, then party order) and the
## battle's offered guests not already in the party.
static func candidates(state: StoryState, request: BattleRequest) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null:
		return out
	var required_hero: bool = hero_rule(request) == HERO_REQUIRED
	var members: Array[StoryPartyMember] = state.healthy_members()
	var ordered: Array[StoryPartyMember] = []
	for m in members:
		if m.is_hero:
			ordered.append(m)
	for m in members:
		if not m.is_hero:
			ordered.append(m)
	for m in ordered:
		var c: CharacterResource = m.character()
		out.append({
			"id": m.member_id, "character_id": m.character_id, "name": m.display_name(),
			"level": m.level, "kind": "human" if c != null and c.is_human() else "creature",
			"hero": m.is_hero, "guest": m.is_temporary(), "temporary": m.is_temporary(),
			"required": m.is_hero and required_hero, "member": true,
		})
	var top: int = state.party_top_level()
	for cid in offered_guests(request):
		if state.party_has(cid):
			continue
		var gc: CharacterResource = CharacterLibrary.get_character(StringName(cid))
		out.append({
			"id": GUEST_PREFIX + cid, "character_id": cid,
			"name": gc.display_name if gc != null else cid.capitalize(),
			"level": request.ally_level if request != null and request.ally_level > 0 else top,
			"kind": "human" if gc != null and gc.is_human() else "creature",
			"hero": false, "guest": true, "temporary": true, "required": false, "member": false,
		})
	return out


## The NO-UI squad: every required candidate, then the rest in candidate order (so the hero
## first), PARTY MEMBERS ONLY (an offered guest deploys only when picked), up to [param squad_size].
## With no hero in the party this is exactly the old "first N healthy members".
static func default_picks(cands: Array, squad_size: int) -> Array[String]:
	var out: Array[String] = []
	var cap: int = maxi(1, squad_size)
	for c in cands:
		if bool(c.get("required", false)) and out.size() < cap:
			out.append(String(c["id"]))
	for c in cands:
		if out.size() >= cap:
			break
		if not bool(c.get("member", true)):
			continue
		var id: String = String(c["id"])
		if not out.has(id):
			out.append(id)
	return out


## Toggle [param id] in [param picks]: a required candidate cannot be dropped, nothing is added past
## [param squad_size], an unknown id is ignored. Returns the new picks (a copy).
static func toggle(picks: Array, id: String, cands: Array, squad_size: int) -> Array[String]:
	var out: Array[String] = []
	for p in picks:
		out.append(String(p))
	var cand: Dictionary = find(cands, id)
	if cand.is_empty():
		return out
	if out.has(id):
		if not bool(cand.get("required", false)):
			out.erase(id)
		return out
	if out.size() < maxi(1, squad_size):
		out.append(id)
	return out


## {ok, reason}: "empty", "too_many", "unknown:<id>", "missing_required:<id>".
static func validate(picks: Array, cands: Array, squad_size: int) -> Dictionary:
	if picks.is_empty():
		return {"ok": false, "reason": "empty"}
	if picks.size() > maxi(1, squad_size):
		return {"ok": false, "reason": "too_many"}
	for p in picks:
		if find(cands, String(p)).is_empty():
			return {"ok": false, "reason": "unknown:%s" % p}
	for c in cands:
		if bool(c.get("required", false)) and not picks.has(String(c["id"])):
			return {"ok": false, "reason": "missing_required:%s" % c["id"]}
	return {"ok": true, "reason": ""}


static func find(cands: Array, id: String) -> Dictionary:
	for c in cands:
		if c is Dictionary and String(c.get("id", "")) == id:
			return c
	return {}


## The picks as party records for the request snapshot: party members as themselves, offered
## guests as {member_id: "guest:<cid>", character_id, current_hp: full, guest: true, level}. Picks
## order is kept (the map's squad chairs fill in that order).
static func snapshot(state: StoryState, picks: Array, cands: Array) -> Array:
	var out: Array = []
	for p in picks:
		var id: String = String(p)
		var m: StoryPartyMember = state.member(id) if state != null else null
		if m != null:
			out.append_array(StoryBattleBridge.party_snapshot([m]))
			continue
		var c: Dictionary = find(cands, id)
		if c.is_empty():
			continue
		out.append({"member_id": id, "character_id": String(c["character_id"]),
			"current_hp": StoryPartyMember.HP_FULL, "item_id": "", "growth": {}, "hero": false,
			"level": int(c.get("level", 0)), "guest": true})
	return out
