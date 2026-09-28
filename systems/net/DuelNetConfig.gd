extends RefCounted
class_name DuelNetConfig

## The ONLINE DUEL's match config (docs/design/DECISIONS.md #32): what a duel lobby agrees on
## and how every peer turns it into the SAME [DuelRequest]. Pure statics, no networking.
##
## A duel lobby is a [NetSession] lobby whose mode is [constant NetProtocol.MODE_DUEL]. On top of
## the session's own config keys the host's final config carries:
##
##   duel_units    {slot: character_id}  -- each seat's combatant (slot 0 = side A, 1 = side B)
##   duel_stage    one of DuelRequest.STAGES ("meadow" / "tall_grass" / "grove")
##   duel_weather  a Weather id ("clear" ...)
##   seed          the public setup seed NetSession derived from the RNG commitments
##
## Each seat announces its pick on the lobby channel ([constant MSG_PICK]); the player-host
## ([DuelLobby]) or the dedicated server ([DedicatedServer]) folds both into [constant KEY_UNITS]
## at the start. Everything here is UNTRUSTED peer input: [method sanitize] keeps only
## whitelisted ids and every peer re-validates the picks against the duel-eligible roster
## ([method build_request]) -- a pick that is not eligible refuses the match on every peer, so
## a modified host cannot field a unit the rules would not offer.
##
## The request is a VERSUS duel: both sides human, no AI, no items, no running, no befriend
## (items and flee are local / story actions; an online duel is a straight 1v1). The seed is
## the setup seed, so the speed tie-break, the weather and the opening ticks are identical on
## every peer; every action then rolls from its own commit-reveal seed.

const KEY_UNITS := "duel_units"
const KEY_STAGE := "duel_stage"
const KEY_WEATHER := "duel_weather"
const DEFAULT_STAGE := "meadow"
const DEFAULT_WEATHER := "clear"
## Lobby message: this seat's combatant, { character_id: String }.
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


## The whitelisted duel keys of [param config] (unknown / invalid values dropped).
static func sanitize(config) -> Dictionary:
	var out := {}
	if not (config is Dictionary):
		return out
	var d: Dictionary = config
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


## The start's last word for a duel: both seats' units (+ stage / weather when given).
static func final_config(picks: Dictionary, stage: String = "", weather: String = "") -> Dictionary:
	var cfg := {KEY_UNITS: units_for(picks)}
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


## Build the duel every peer plays from the host's [param config]. Returns
## { success, reason, request } (rule 1: a refusal is a value). Refuses a pick that is not a
## duel-eligible roster unit ("ineligible_unit") or a stage / weather this build does not know.
static func build_request(config: Dictionary) -> Dictionary:
	var ids: Array[String] = []
	for slot in [0, 1]:
		var id := unit_of(config, slot)
		if id == "":
			id = default_unit(slot)
		if not is_eligible(id):
			return _fail("ineligible_unit")
		ids.append(id)
	var stage := String(config.get(KEY_STAGE, DEFAULT_STAGE))
	if not DuelRequest.STAGES.has(stage):
		return _fail("unknown_stage")
	var weather := String(config.get(KEY_WEATHER, DEFAULT_WEATHER))
	if not Weather.has_weather(StringName(weather)):
		return _fail("unknown_weather")
	var req := DuelRequest.new()
	req.kind = DuelRequest.KIND_VERSUS
	req.origin = DuelRequest.ORIGIN_STANDALONE
	req.player_party.append(DuelCombatant.make(StringName(ids[0])))
	req.foe_party.append(DuelCombatant.make(StringName(ids[1])))
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
