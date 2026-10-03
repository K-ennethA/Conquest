class_name StorySnapshot
extends RefCounted

## PURE serializer between a live [StoryState] and the versioned JSON a story slot stores
## (docs/design/OVERWORLD.md §4.11). Same discipline as [BattleSnapshot]:
##   * FORMAT_VERSION stamped; a newer (unknown) version is REJECTED, never guessed at;
##   * ids, never resource paths (areas, characters, items are keys into shipped content);
##   * unknown ids are SKIPPED, never raised (a save from a build that shipped a character this
##     one does not have loses that member, not the whole journey);
##   * every read goes through a coercion helper (CONQUEST.md rule 3), no ResourceLoader on
##     save data (rule 8).
## No disk access here -- [StorySaveManager] owns the files.
##
## VERSION 2 = the story OPENING (Oakvale home -> the Crownhaven shard ceremony -> the raid).
## A version-1 journey was played in the M1 slice's world (Elder Wynn's quest, a starting party
## of two), which the opening replaced: its flags, party and position mean nothing to the new
## story, so it is NOT migrated -- it loads as OUTDATED ("outdated_journey"): the slot card says
## a new journey is required, Continue Journey skips it, and Delete clears it. Nothing crashes.

const FORMAT_VERSION: int = 2
## The oldest version this build still plays (pre-release: no migrations, see above).
const MIN_FORMAT_VERSION: int = 2
const REASON_OUTDATED := "outdated_journey"


static func to_dict(state: StoryState) -> Dictionary:
	var party: Array = []
	for m in state.party:
		party.append(m.to_dict())
	var fallen: Array = []
	for m in state.fallen:
		fallen.append(m.to_dict())
	var positions: Dictionary = {}
	for key in state.actor_positions:
		var rec: Dictionary = state.actor_positions[key]
		positions[key] = {
			"cell": Cells.to_array(rec.get("cell", Vector3i.ZERO)),
			"facing": String(rec.get("facing", "south")),
		}
	return {
		"format_version": FORMAT_VERSION,
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"play_seconds": int(state.play_seconds),
		"location": {
			"area_id": state.location_area(),
			"cell": Cells.to_array(state.location_cell()),
			"facing": state.location_facing(),
		},
		"respawn": {
			"area_id": String(state.respawn.get("area_id", "")),
			"entry": String(state.respawn.get("entry", "")),
		},
		"flags": state.flags.duplicate(true),
		"flag_times": state.flag_times.duplicate(true),
		"party": party,
		"bag": state.bag.duplicate(true),
		"gold": state.gold,
		"visited_areas": state.visited_areas.duplicate(),
		"lit_wayshrines": state.lit_wayshrines.duplicate(),
		"rng": {"seed": state.rng_seed, "steps": state.steps, "grace": state.grace_steps},
		"actor_positions": positions,
		"shops": state.shops.duplicate(true),
		"rests": state.rests,
		"wild": {"visit": state.visit_serial, "zones": state.wild.duplicate(true)},
		"tier": state.tier,
		"fallen": fallen,
		"tracked_quest": state.tracked_quest,
		"pending": {},
	}


## Rebuild a state from [param data]. Returns {success, state, reason}; never logs.
static func from_dict(data) -> Dictionary:
	if not (data is Dictionary):
		return {"success": false, "state": null, "reason": "not_a_dictionary"}
	var version: int = int(data.get("format_version", 0))
	if version <= 0:
		return {"success": false, "state": null, "reason": "missing_version"}
	if version > FORMAT_VERSION:
		return {"success": false, "state": null, "reason": "newer_version"}
	if version < MIN_FORMAT_VERSION:
		return {"success": false, "state": null, "reason": REASON_OUTDATED}

	var state := StoryState.new()
	state.play_seconds = maxf(0.0, float(data.get("play_seconds", 0)))

	var loc = data.get("location", {})
	if loc is Dictionary:
		var cell: Vector3i = Cells.from_variant(loc.get("cell", [0, 0, 0]))
		if cell == Cells.INVALID:
			cell = Vector3i.ZERO
		state.set_location(String(loc.get("area_id", "")), cell, String(loc.get("facing", "south")))

	var resp = data.get("respawn", {})
	if resp is Dictionary:
		state.respawn = {"area_id": String(resp.get("area_id", "")), "entry": String(resp.get("entry", ""))}

	var flags = data.get("flags", {})
	if flags is Dictionary:
		for key in flags:
			state.set_flag(String(key), flags[key])
	# When each flag was set (story time: "3 rests since ..."; added within format 2). set_flag just
	# stamped every flag with the load-time clocks -- replace them with the saved stamps; a flag with
	# none (an older save) counts as set at the journey's start.
	state.flag_times = StoryState.sanitize_flag_times(data.get("flag_times", {}), state.flags)

	var party = data.get("party", [])
	if party is Array:
		for raw in party:
			var m: StoryPartyMember = StoryPartyMember.from_dict(raw)
			if m == null:
				continue
			# Unknown ids skipped, not raised: a member whose character this build does not
			# ship is dropped (and so is a duplicate uid).
			if CharacterLibrary.get_character(StringName(m.character_id)) == null:
				continue
			if state.member(m.member_id) != null:
				continue
			state.party.append(m)

	var bag = data.get("bag", {})
	if bag is Dictionary:
		for item_id in bag:
			var n: int = int(bag[item_id])
			if n > 0 and ItemLibrary.has_item(String(item_id)):
				state.bag[String(item_id)] = n

	state.gold = maxi(0, int(data.get("gold", 0)))
	state.visited_areas = _to_string_array(data.get("visited_areas", []))
	state.lit_wayshrines = _to_string_array(data.get("lit_wayshrines", []))

	var rng = data.get("rng", {})
	if rng is Dictionary:
		state.rng_seed = int(rng.get("seed", 0))
		state.steps = maxi(0, int(rng.get("steps", 0)))
		state.grace_steps = maxi(0, int(rng.get("grace", 0)))

	var positions = data.get("actor_positions", {})
	if positions is Dictionary:
		for key in positions:
			var rec = positions[key]
			if not (rec is Dictionary):
				continue
			var c: Vector3i = Cells.from_variant(rec.get("cell", null))
			if c == Cells.INVALID:
				continue
			state.actor_positions[String(key)] = {"cell": c, "facing": String(rec.get("facing", "south"))}

	# Merchants (added in format 2 -- an older save has none: every shop fully stocked).
	state.shops = ShopLedger.sanitize_saved(data.get("shops", {}))
	state.rests = maxi(0, int(data.get("rests", 0)))

	# Visible wild creatures (added within format 2 -- an older save has none: every visible
	# zone rolls a fresh roster on the next load; malformed records are dropped).
	var wild = data.get("wild", {})
	if wild is Dictionary:
		state.visit_serial = maxi(0, int(wild.get("visit", 0)))
		state.wild = WildSpawner.sanitize_saved(wild.get("zones", {}))

	# The difficulty tier (DECISIONS.md #29): a save from before tiers existed was played without
	# permadeath, so it loads as CASUAL; an unknown tier string does too.
	var tier: String = String(data.get("tier", StoryState.TIER_CASUAL))
	state.tier = tier if StoryState.is_tier(tier) else StoryState.TIER_CASUAL
	# Fallen members: kept records (unknown characters / duplicate uids skipped like the party's).
	var fallen = data.get("fallen", [])
	if fallen is Array:
		for raw in fallen:
			var f: StoryPartyMember = StoryPartyMember.from_dict(raw)
			if f == null or CharacterLibrary.get_character(StringName(f.character_id)) == null:
				continue
			if state.member(f.member_id) != null or state.fallen_member(f.member_id) != null:
				continue
			if f.fallen_info.is_empty():
				f.fallen_info = StoryPartyMember.sanitize_fallen({"kind": "battle"})
			state.fallen.append(f)

	# The quest pinned to the HUD tracker (added within format 2 -- an older save has none: the main
	# quest is tracked). Kept as written: an id this build does not ship just falls back
	# (QuestLog.tracked_entry), so no quest list is consulted here.
	var pin = data.get("tracked_quest", "")
	state.tracked_quest = String(pin).strip_edges() if pin is String else ""

	return {"success": true, "state": state, "reason": ""}


## True when [param data] is a story save from before the opening (a new journey is required).
static func is_outdated(data: Dictionary) -> bool:
	var version: int = int(data.get("format_version", 0))
	return version > 0 and version < MIN_FORMAT_VERSION


## A one-line caption for a slot card / the main-menu row: "Mossway · 2h 15m".
static func describe(data: Dictionary, area_names: Dictionary = {}) -> String:
	var loc = data.get("location", {})
	var area_id: String = String(loc.get("area_id", "")) if loc is Dictionary else ""
	var area_name: String = String(area_names.get(area_id, area_id.capitalize()))
	return "%s  ·  %s" % [area_name, format_play_time(int(data.get("play_seconds", 0)))]


static func format_play_time(seconds: int) -> String:
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % m


## JSON Array -> Array[String] element-wise (CONQUEST.md rule 3).
static func _to_string_array(raw) -> Array[String]:
	var out: Array[String] = []
	if raw is Array:
		for v in raw:
			var s: String = String(v)
			if not s.is_empty() and not out.has(s):
				out.append(s)
	return out
