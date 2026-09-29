extends RefCounted
class_name DuelNetConfig

## The ONLINE DUEL's match config (docs/design/DECISIONS.md #32): what a duel lobby agrees on
## and how every peer turns it into the SAME [DuelRequest]. Pure statics, no networking.
##
## A duel lobby is a [NetSession] lobby whose mode is [constant NetProtocol.MODE_DUEL]. On top of
## the session's own config keys the host's final config carries:
##
##   duel_format   the FORMAT ([DuelFormat.to_dict]: team size, switching, KO replacement,
##                 species clause, strength cap) -- the host's / leader's pick, or a dedicated
##                 server's --duel-format; absent = Singles
##   duel_teams    {slot: [character_id, ...]} -- each seat's TEAM, lead first, exactly the
##                 format's team size
##   duel_units    {slot: character_id}  -- each seat's LEAD (slot 0 = side A, 1 = side B; the
##                 Singles-era key, kept alongside the teams)
##   duel_stage    one of DuelRequest.STAGES ("meadow" / "tall_grass" / "grove")
##   duel_weather  a Weather id ("clear" ...)
##   seed          the public setup seed NetSession derived from the RNG commitments
##
## Each seat announces its pick on the lobby channel ([constant MSG_PICK]: its lead plus a team
## PREFERENCE list); the player-host ([DuelLobby]) or the dedicated server ([DedicatedServer])
## folds both into [constant KEY_TEAMS] / [constant KEY_UNITS] at the start, trimmed / filled to
## the format's size ([method teams_for]). Everything here is UNTRUSTED peer input: [method sanitize] keeps only
## whitelisted ids and every peer re-validates the picks against the duel-eligible roster
## ([method build_request]) -- a pick that is not eligible refuses the match on every peer, so
## a modified host cannot field a unit the rules would not offer.
##
## The request is a VERSUS duel: both sides human, no AI, no items, no running, no befriend
## (items and flee are local / story actions; an online duel is a straight team fight). The seed is
## the setup seed, so the speed tie-break, the weather and the opening ticks are identical on
## every peer; every action then rolls from its own commit-reveal seed.

const KEY_UNITS := "duel_units"
const KEY_TEAMS := "duel_teams"
const KEY_FORMAT := "duel_format"
## Config keys that belong to ONE match (the seats' own picks): never kept in a standing lobby
## config, and taken even when a dedicated server's config is locked.
const PER_MATCH_KEYS: Array[String] = [KEY_UNITS, KEY_TEAMS]
const KEY_STAGE := "duel_stage"
const KEY_WEATHER := "duel_weather"
const DEFAULT_STAGE := "meadow"
const DEFAULT_WEATHER := "clear"
## Lobby message: this seat's pick, { character_id: String (the lead), team: [String] (a
## preference list, lead first; the start trims / fills it to the format's size) }.
const MSG_PICK := "duel_pick"
## The M1 slice (side A, side B) when a seat never picked.
const DEFAULT_UNITS: Array[StringName] = [&"vineweave", &"gem_knight"]


## True when [param config] describes an online duel.
static func is_duel(config) -> bool:
	return NetProtocol.mode_of(config) == NetProtocol.MODE_DUEL


## Roster ids a duel can field (the duel-eligible ones -- [method DuelMoveCompiler.is_duel_eligible]),
## sorted by id. Humans and creatures alike (DECISIONS.md #7).
static func eligible_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	var rules := DuelRuleset.load_default()
	for id in CharacterLibrary.all_ids():
		var ch := CharacterLibrary.get_character(StringName(String(id)))
		if ch != null and DuelMoveCompiler.is_duel_eligible(ch, rules):
			out.append(StringName(String(id)))
	out.sort_custom(func(a, b): return String(a) < String(b))
	return out


## True when [param id] names a duel-eligible roster unit.
static func is_eligible(id) -> bool:
	if not (id is String or id is StringName):
		return false
	var s := String(id)
	if s == "" or s.length() > 64:
		return false
	var ch := CharacterLibrary.get_character(StringName(s))
	return ch != null and DuelMoveCompiler.is_duel_eligible(ch, DuelRuleset.load_default())


## The combatant a seat fields when it never picked: the slice's unit for that side, else the
## first eligible one.
static func default_unit(slot: int) -> String:
	var want: StringName = DEFAULT_UNITS[clampi(slot, 0, 1)]
	if is_eligible(want):
		return String(want)
	var ids := eligible_ids()
	return String(ids[0]) if not ids.is_empty() else String(want)


## The format [param config] names (sanitised; Singles when it names none or an invalid one).
static func format_of(config) -> DuelFormat:
	if config is Dictionary and (config as Dictionary).has(KEY_FORMAT):
		var res := DuelFormat.from_dict(config[KEY_FORMAT])
		if bool(res["success"]):
			return online_format(res["format"])
	return online_format(DuelFormat.preset(DuelFormat.SINGLES))


## A private copy of [param f] for an online duel (the request owns it). Items need no rule
## here: an online duel carries no bag, and USE_ITEM is refused on the wire (DuelNetRules).
static func online_format(f: DuelFormat) -> DuelFormat:
	return f.duplicate() if f != null else DuelFormat.preset(DuelFormat.SINGLES)


## The format dict a config carries for preset [param id] ("singles" / "trio" / "full"), or {}
## for an unknown id.
static func format_config(id: String) -> Dictionary:
	var f := DuelFormat.preset(id)
	return f.to_dict() if f != null else {}


## An untrusted team / pick value -> the eligible ids in it, in order (at most MAX_TEAM; a single
## id reads as a team of one).
static func clean_team(v) -> Array:
	var out: Array = []
	if v is String or v is StringName:
		v = [v]
	if not (v is Array):
		return out
	for e in v:
		if out.size() >= DuelFormat.MAX_TEAM:
			break
		if is_eligible(e):
			out.append(String(e))
	return out


## Seat [param slot]'s team under [param f] when it named none: its default lead, then the
## eligible roster in order -- skipping repeats under a species clause.
static func default_team(slot: int, f: DuelFormat) -> Array:
	return fill_team([], slot, f)


## [param wanted] (a clean preference list) trimmed / filled to [param f]'s team size: repeats
## dropped under the species clause, gaps filled with the seat's defaults.
static func fill_team(wanted: Array, slot: int, f: DuelFormat) -> Array:
	var out: Array = []
	for id in wanted:
		if out.size() >= f.team_size:
			break
		if f.species_clause and String(id) in out:
			continue
		out.append(String(id))
	var fill: Array = [default_unit(slot)]
	for id in eligible_ids():
		fill.append(String(id))
	for id in fill:
		if out.size() >= f.team_size:
			break
		if f.species_clause and id in out:
			continue
		out.append(id)
	return out


## {0: [ids], 1: [ids]}: each seat's team for [param f] from per-slot [param picks] (a team list,
## or a single id -- the Singles-era pick), trimmed / filled to the team size.
static func teams_for(picks: Dictionary, f: DuelFormat) -> Dictionary:
	var out := {}
	for slot in [0, 1]:
		out[slot] = fill_team(clean_team(_slot_value(picks, slot)), slot, f)
	return out


## The whitelisted duel keys of [param config] (unknown / invalid values dropped).
static func sanitize(config) -> Dictionary:
	var out := {}
	if not (config is Dictionary):
		return out
	var d: Dictionary = config
	if d.has(KEY_FORMAT):
		var fres := DuelFormat.from_dict(d[KEY_FORMAT])
		if bool(fres["success"]):
			out[KEY_FORMAT] = (fres["format"] as DuelFormat).to_dict()
	var teams = d.get(KEY_TEAMS, null)
	if teams is Dictionary:
		var tclean := {}
		for slot in [0, 1]:
			var t := clean_team(_slot_value(teams, slot))
			if not t.is_empty():
				tclean[slot] = t
		if not tclean.is_empty():
			out[KEY_TEAMS] = tclean
	var stage = d.get(KEY_STAGE, null)
	if (stage is String or stage is StringName) and DuelRequest.STAGES.has(String(stage)):
		out[KEY_STAGE] = String(stage)
	var weather = d.get(KEY_WEATHER, null)
	if (weather is String or weather is StringName) and Weather.has_weather(StringName(String(weather))):
		out[KEY_WEATHER] = String(weather)
	var units = d.get(KEY_UNITS, null)
	if units is Dictionary:
		var clean := {}
		for slot in [0, 1]:
			var id = _slot_value(units, slot)
			if is_eligible(id):
				clean[slot] = String(id)
		if not clean.is_empty():
			out[KEY_UNITS] = clean
	return out


## {0: id, 1: id} from per-slot [param picks] (missing / ineligible -> [method default_unit]).
static func units_for(picks: Dictionary) -> Dictionary:
	var out := {}
	for slot in [0, 1]:
		var id = _slot_value(picks, slot)
		out[slot] = String(id) if is_eligible(id) else default_unit(slot)
	return out


## The start's last word for a duel: both seats' teams for [param format] (and their leads), plus
## the format and stage / weather when given. [param picks] = {slot: id or [ids]}; [param format]
## null = Singles (a config with no format key).
static func final_config(picks: Dictionary, stage: String = "", weather: String = "",
		format: DuelFormat = null) -> Dictionary:
	var f: DuelFormat = format if format != null else DuelFormat.preset(DuelFormat.SINGLES)
	var teams := teams_for(picks, f)
	var leads := {}
	for slot in [0, 1]:
		leads[slot] = String((teams[slot] as Array)[0]) if not (teams[slot] as Array).is_empty() else default_unit(slot)
	var cfg := {KEY_UNITS: leads, KEY_TEAMS: teams}
	if format != null:
		cfg[KEY_FORMAT] = format.to_dict()
	if stage != "":
		cfg[KEY_STAGE] = stage
	if weather != "":
		cfg[KEY_WEATHER] = weather
	return sanitize(cfg)


## The combatant id [param slot] fields under [param config] ("" when the config names none).
static func unit_of(config: Dictionary, slot: int) -> String:
	var units = config.get(KEY_UNITS, {})
	if not (units is Dictionary):
		return ""
	var id = _slot_value(units, slot)
	return String(id) if (id is String or id is StringName) else ""


## Seat [param slot]'s team as [param config] names it ([] when it names none): the teams key,
## else the Singles-era unit key as a team of one. RAW (not whitelisted): build_request judges it.
static func team_of(config: Dictionary, slot: int) -> Array:
	var teams = config.get(KEY_TEAMS, {})
	if teams is Dictionary:
		var t = _slot_value(teams, slot)
		if t is Array:
			return (t as Array).duplicate()
	var id := unit_of(config, slot)
	return [id] if id != "" else []


## Build the duel every peer plays from the host's [param config]. Returns
## { success, reason, request } (rule 1: a refusal is a value). Refuses an unreadable format
## (its own reason), a team that is not exactly the format's size ("bad_team_size"), a pick that
## is not a duel-eligible roster unit ("ineligible_unit"), a repeat under the species clause
## ("species_clause"), or a stage / weather this build does not know. A seat that named nothing
## fields its default team.
static func build_request(config: Dictionary) -> Dictionary:
	var f: DuelFormat = null
	if config.has(KEY_FORMAT):
		var fres := DuelFormat.from_dict(config[KEY_FORMAT])
		if not bool(fres["success"]):
			return _fail(String(fres["reason"]))
		f = online_format(fres["format"])
	else:
		f = online_format(DuelFormat.preset(DuelFormat.SINGLES))
	var teams: Array = []
	for slot in [0, 1]:
		var raw := team_of(config, slot)
		if raw.is_empty():
			raw = default_team(slot, f)
		for id in raw:
			if not is_eligible(id):
				return _fail("ineligible_unit")
		var problem := f.team_problem(raw, true)
		if problem != "":
			return _fail(problem)
		teams.append(raw)
	var stage := String(config.get(KEY_STAGE, DEFAULT_STAGE))
	if not DuelRequest.STAGES.has(stage):
		return _fail("unknown_stage")
	var weather := String(config.get(KEY_WEATHER, DEFAULT_WEATHER))
	if not Weather.has_weather(StringName(weather)):
		return _fail("unknown_weather")
	var req := DuelRequest.new()
	req.kind = DuelRequest.KIND_VERSUS
	req.origin = DuelRequest.ORIGIN_STANDALONE
	req.format = f
	for side in 2:
		var party: Array[DuelCombatant] = req.player_party if side == 0 else req.foe_party
		for i in range((teams[side] as Array).size()):
			party.append(DuelCombatant.make(StringName(String(teams[side][i])), "%d:%d" % [side, i]))
	req.stage_id = stage
	req.weather_id = StringName(weather)
	# 0 would mean "fresh entropy" -- two peers would then roll different setups.
	var seed_value := int(config.get("seed", 0))
	req.seed = seed_value if seed_value != 0 else 1
	req.player_is_ai = false
	req.foe_is_ai = false
	req.rules = {"can_flee": false, "can_befriend": false}
	req.encounter_id = "online_duel"
	var check := req.validate()
	if not bool(check["success"]):
		return _fail(String(check["reason"]))
	return {"success": true, "reason": "", "request": req}


## A Dictionary keyed by int slot, tolerating a String key ("0") from a re-encoded config.
static func _slot_value(d: Dictionary, slot: int):
	if d.has(slot):
		return d[slot]
	if d.has(str(slot)):
		return d[str(slot)]
	return null


static func _fail(reason: String) -> Dictionary:
	return {"success": false, "reason": reason, "request": null}
