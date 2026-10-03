class_name QuestLog
extends RefCounted

## THE QUEST / OBJECTIVE LOG: pure, data-driven and flag-derived (docs/design/OVERWORLD.md §4.2 --
## quests ARE flags). Nothing here is saved: every view is computed from a [StoryState]'s flags
## against the definitions in [constant DATA_PATH], so a quest can be added, reworded or reordered
## by editing JSON without a save migration. (The one saved quest choice -- which quest the player
## PINNED to the HUD tracker -- is [member StoryState.tracked_quest], read by [method tracked_entry].)
##
## A definition: {id, title, category ("main" / "side"), summary, start_flag, complete_flag,
## steps: [{flag, text}]}. A quest is LISTED once its [code]start_flag[/code] is set ("" = from the
## start); it is DONE once its [code]complete_flag[/code] is set (blank = every step's flag set);
## its CURRENT OBJECTIVE is the first step whose flag is not set yet.
##
## OPTIONAL POINTERS (additive -- an entry without them loads exactly as before), on the quest
## and / or on each step (a step's own wins):
##   location -- a [WorldLocation] id ("crownhaven") OR an area id ("oakvale_ruins"): where the
##               objective is on the WORLD MAP (an area id resolves to its place, [method resolve_location]);
##   area     -- the area id the objective is IN (in-area pointing: the HUD says "here");
##   npc      -- (step) the entity id to talk to there (the overworld marks that actor);
##   giver    -- (quest) the npc id who gives / anchors the quest.

const DATA_PATH := "res://game/overworld/content/quests.json"
const MAIN := "main"
const SIDE := "side"
const STATUS_ACTIVE := "active"
const STATUS_DONE := "done"
## Journey -> Quests filters ([method filtered]).
const FILTER_ALL := "all"
const FILTER_MAIN := "main"
const FILTER_SIDE := "side"
const FILTER_COMPLETED := "completed"
const FILTERS: Array[String] = [FILTER_ALL, FILTER_MAIN, FILTER_SIDE, FILTER_COMPLETED]
## Key order [method to_json] writes (a stable, reviewable diff for the quest editor).
const QUEST_KEYS: Array[String] = ["id", "title", "category", "summary", "giver", "location", "area",
	"start_flag", "complete_flag", "steps"]
const STEP_KEYS: Array[String] = ["flag", "text", "location", "area", "npc"]
## Keys a definition / step may leave out (written only when non-empty).
const OPTIONAL_KEYS: Array[String] = ["giver", "location", "area", "npc", "summary"]

static var _defs_cache: Array = []
static var _defs_loaded: bool = false
static var _atlas: WorldAtlas = null
static var _atlas_loaded: bool = false


## Every authored definition (cached). A missing / unreadable file reads as no quests.
static func definitions() -> Array:
	if _defs_loaded:
		return _defs_cache
	_defs_loaded = true
	_defs_cache = parse(FileAccess.get_file_as_string(DATA_PATH))
	return _defs_cache


## Tests: swap the definitions in ([param defs] = null reloads the shipped file).
static func set_definitions(defs) -> void:
	_defs_loaded = defs != null
	_defs_cache = defs if defs != null else []


## Tests: swap the world atlas used to resolve locations (null = the shipped world.tres).
static func set_atlas(atlas: WorldAtlas) -> void:
	_atlas = atlas
	_atlas_loaded = atlas != null


static func atlas() -> WorldAtlas:
	if not _atlas_loaded:
		_atlas_loaded = true
		_atlas = WorldAtlas.load_default()
	return _atlas


## The definitions in [param text] (the quests.json shape). Malformed input reads as no quests;
## an entry without an id is skipped.
static func parse(text: String) -> Array:
	var out: Array = []
	if text.strip_edges().is_empty():
		return out
	# JSON.new().parse returns its error instead of logging it (a malformed file is a handled case).
	var json := JSON.new()
	if json.parse(text) != OK:
		return out
	var parsed = json.data
	if not (parsed is Dictionary):
		return out
	var raw = parsed.get("quests", [])
	if not (raw is Array):
		return out
	for q in raw:
		if q is Dictionary and not String(q.get("id", "")).is_empty():
			out.append(q)
	return out


## The log for [param state]: one entry per LISTED quest, main before side, active before done:
## {id, title, category, summary, status, objective, step_index, location, area, npc, giver,
## steps: [{text, done, location, area, npc}]}.
static func entries(state: StoryState, defs: Array = []) -> Array:
	var source: Array = defs if not defs.is_empty() else definitions()
	var rows: Array = []
	for i in range(source.size()):
		if not (source[i] is Dictionary):
			continue
		var e: Dictionary = entry_for(source[i], state)
		if e.is_empty():
			continue
		e["_order"] = i
		rows.append(e)
	rows.sort_custom(_before)
	for e in rows:
		e.erase("_order")
	return rows


## One definition's view, or {} while the quest is not listed yet.
static func entry_for(def: Dictionary, state: StoryState) -> Dictionary:
	if state == null:
		return {}
	var start: String = String(def.get("start_flag", ""))
	if not start.is_empty() and not state.has_flag(start):
		return {}
	var steps: Array = []
	var objective: String = ""
	var current: int = -1
	var all_done: bool = true
	var raw_steps = def.get("steps", [])
	if not (raw_steps is Array):
		raw_steps = []
	for s in raw_steps:
		if not (s is Dictionary):
			continue
		var done: bool = state.has_flag(String(s.get("flag", "")))
		steps.append({"text": String(s.get("text", "")), "done": done,
			"location": String(s.get("location", "")), "area": String(s.get("area", "")),
			"npc": String(s.get("npc", ""))})
		if not done:
			all_done = false
			if current < 0:
				current = steps.size() - 1
				objective = String(s.get("text", ""))
	var complete: String = String(def.get("complete_flag", ""))
	var finished: bool = state.has_flag(complete) if not complete.is_empty() else all_done
	if finished:
		current = -1
	var step: Dictionary = steps[current] if current >= 0 else {}
	return {
		"id": String(def.get("id", "")),
		"title": String(def.get("title", "")),
		"category": String(def.get("category", SIDE)),
		"summary": String(def.get("summary", "")),
		"status": STATUS_DONE if finished else STATUS_ACTIVE,
		"objective": "" if finished else objective,
		"step_index": current,
		"location": _pick_location(step, def),
		"area": _pick_area(step, def),
		"npc": String(step.get("npc", "")),
		"giver": String(def.get("giver", "")),
		"steps": steps,
	}


## The world-map place of an objective: the step's location / area, else the quest's.
static func _pick_location(step: Dictionary, def: Dictionary) -> String:
	for raw in [String(step.get("location", "")), String(step.get("area", "")),
			String(def.get("location", "")), String(def.get("area", ""))]:
		var id: String = resolve_location(raw)
		if not id.is_empty():
			return id
	return ""


## The area an objective is in: the step's area (or its location when that is an area), else the
## quest's; "" when it only names a place.
static func _pick_area(step: Dictionary, def: Dictionary) -> String:
	for raw in [String(step.get("area", "")), String(step.get("location", "")),
			String(def.get("area", "")), String(def.get("location", ""))]:
		if raw.is_empty():
			continue
		var a: WorldAtlas = atlas()
		if a != null and a.location(raw) != null:
			continue
		return raw
	return ""


## A [WorldLocation] id for [param raw] -- itself when it names a place, the place an area id
## belongs to, else "" (unknown, or no atlas).
static func resolve_location(raw: String, p_atlas: WorldAtlas = null) -> String:
	if raw.is_empty():
		return ""
	var a: WorldAtlas = p_atlas if p_atlas != null else atlas()
	if a == null:
		return ""
	if a.location(raw) != null:
		return raw
	var l: WorldLocation = a.location_for_area(raw)
	return String(l.id) if l != null else ""


static func _before(a: Dictionary, b: Dictionary) -> bool:
	var ka: Array = _sort_key(a)
	var kb: Array = _sort_key(b)
	for i in range(ka.size()):
		if ka[i] != kb[i]:
			return ka[i] < kb[i]
	return false


static func _sort_key(e: Dictionary) -> Array:
	return [0 if String(e["status"]) == STATUS_ACTIVE else 1,
		0 if String(e["category"]) == MAIN else 1, int(e.get("_order", 0))]


## The line to show as "what next": the first active MAIN quest's objective, else the first active
## side quest's, else "" (nothing in the log is open).
static func current_objective(state: StoryState, defs: Array = []) -> String:
	for e in entries(state, defs):
		if String(e["status"]) == STATUS_ACTIVE and not String(e["objective"]).is_empty():
			return String(e["objective"])
	return ""


## The quest the HUD tracker follows: the PINNED one ([member StoryState.tracked_quest]) while it is
## listed and active, else the first active main quest, else the first active side quest; {} when
## nothing is open. A finished pin simply falls back -- nothing has to clear it.
static func tracked_entry(state: StoryState, defs: Array = []) -> Dictionary:
	if state == null:
		return {}
	var rows: Array = entries(state, defs)
	var pin: String = state.tracked_quest
	if not pin.is_empty():
		for e in rows:
			if String(e["id"]) == pin and String(e["status"]) == STATUS_ACTIVE:
				return e
	for e in rows:
		if String(e["status"]) == STATUS_ACTIVE and not String(e["objective"]).is_empty():
			return e
	return {}


## Is quest [param quest_id] listed and still active for [param state]?
static func is_active(state: StoryState, quest_id: String, defs: Array = []) -> bool:
	for e in entries(state, defs):
		if String(e["id"]) == quest_id:
			return String(e["status"]) == STATUS_ACTIVE
	return false


## The log narrowed by [param filter] (one of [constant FILTERS]): main / side = that category's
## ACTIVE quests, completed = every finished one, all = everything.
static func filtered(state: StoryState, filter: String, defs: Array = []) -> Array:
	var out: Array = []
	for e in entries(state, defs):
		var done: bool = String(e["status"]) == STATUS_DONE
		match filter:
			FILTER_MAIN:
				if not done and String(e["category"]) == MAIN:
					out.append(e)
			FILTER_SIDE:
				if not done and String(e["category"]) != MAIN:
					out.append(e)
			FILTER_COMPLETED:
				if done:
					out.append(e)
			_:
				out.append(e)
	return out


## The active objectives that point at a world-map place: [{id, title, category, location,
## objective}] (the world map's quest pennants).
static func map_pins(state: StoryState, defs: Array = []) -> Array:
	var out: Array = []
	for e in entries(state, defs):
		if String(e["status"]) != STATUS_ACTIVE or String(e["location"]).is_empty():
			continue
		out.append({"id": e["id"], "title": e["title"], "category": e["category"],
			"location": e["location"], "objective": e["objective"]})
	return out


## [param defs] as quests.json text: tab-indented, keys in [constant QUEST_KEYS] /
## [constant STEP_KEYS] order (unknown keys kept, sorted, after them), empty optional keys left out
## -- so a save from the quest editor diffs line by line.
static func to_json(defs: Array) -> String:
	var lines: PackedStringArray = ["{", "\t\"quests\": ["]
	for qi in range(defs.size()):
		var q: Dictionary = defs[qi]
		lines.append("\t\t{")
		var keys: Array = _ordered_keys(q, QUEST_KEYS)
		for ki in range(keys.size()):
			var k: String = keys[ki]
			var comma: String = "," if ki < keys.size() - 1 else ""
			if k == "steps":
				var steps: Array = q.get("steps", []) if q.get("steps", []) is Array else []
				if steps.is_empty():
					lines.append("\t\t\t\"steps\": []" + comma)
					continue
				lines.append("\t\t\t\"steps\": [")
				for si in range(steps.size()):
					var s: Dictionary = steps[si] if steps[si] is Dictionary else {}
					var parts: PackedStringArray = []
					for sk in _ordered_keys(s, STEP_KEYS):
						parts.append("%s: %s" % [JSON.stringify(sk), JSON.stringify(s[sk])])
					lines.append("\t\t\t\t{%s}%s" % [", ".join(parts), "," if si < steps.size() - 1 else ""])
				lines.append("\t\t\t]" + comma)
			else:
				lines.append("\t\t\t%s: %s%s" % [JSON.stringify(k), JSON.stringify(q[k]), comma])
		lines.append("\t\t}" + ("," if qi < defs.size() - 1 else ""))
	lines.append("\t]")
	lines.append("}")
	return "\n".join(lines) + "\n"


static func _ordered_keys(d: Dictionary, order: Array[String]) -> Array:
	var out: Array = []
	for k in order:
		if not d.has(k):
			continue
		if OPTIONAL_KEYS.has(k) and String(d[k]).is_empty():
			continue
		out.append(k)
	var extra: Array = []
	for k in d.keys():
		if not order.has(String(k)):
			extra.append(String(k))
	extra.sort()
	out.append_array(extra)
	return out
