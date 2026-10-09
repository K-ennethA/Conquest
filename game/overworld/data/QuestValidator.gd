@tool
class_name QuestValidator
extends RefCounted

## QUEST DATA CHECKS for content/quests.json (the Quest Editor plugin, addons/quest_editor, and the
## tests): what flags the story content knows and SETS, the problems in a set of definitions, and
## the STORY FLOW (quests in the order their start flags are reached). Pure and text-based -- it
## reads the builder and the generated .tres as TEXT, never runs content scripts -- so it works the
## same in the editor (where game scripts are not tool scripts) and at runtime.
##
## A flag is KNOWN when the builder or any content resource mentions it (an F_* constant, a quoted
## "a.b" literal, a has("a.b") condition); it is SET when content can actually set it: a SetFlag /
## IncFlag command's key, a join's flag_on_join, a field-move teach's learned_flag, a battle
## reward's flags, a trainer encounter's "<encounter_id>.defeated", a tournament's
## arena.<id>.run / round / wins / champion.

const BUILDER_PATH := "res://game/overworld/build/build_story_content.gd"
const CONTENT_DIR := "res://game/overworld/content/"
const WORLD_PATH := "res://game/overworld/content/world.tres"
const SEVERITY_ERROR := "error"
const SEVERITY_WARNING := "warning"

## "opening.sent_off", "arena.crown_cup.round2" -- dotted lower-case keys.
const FLAG_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"


## Every flag the project knows / sets, plus the place and area ids quests may point at, read from
## disk: {known: Array[String], set: Array[String], ranks: {flag: int}, locations: Array[String],
## areas: Array[String]}.
static func scan_project() -> Dictionary:
	var tres: Array = []
	_collect_tres(CONTENT_DIR, tres)
	var texts: Array = []
	for p in tres:
		texts.append(FileAccess.get_file_as_string(p))
	var tournaments: Array = []
	for p in tres:
		if String(p).contains("/tournaments/"):
			tournaments.append(String(p).get_file().get_basename())
	var out: Dictionary = collect_flags(FileAccess.get_file_as_string(BUILDER_PATH), texts, tournaments)
	out["locations"] = location_ids_from_world(FileAccess.get_file_as_string(WORLD_PATH))
	out["areas"] = _area_ids()
	return out


static func _collect_tres(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n: String = d.get_next()
	while not n.is_empty():
		if d.current_is_dir():
			if not n.begins_with("."):
				_collect_tres(dir_path.path_join(n), out)
		elif n.ends_with(".tres"):
			out.append(dir_path.path_join(n))
		n = d.get_next()
	d.list_dir_end()


static func _area_ids() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(CONTENT_DIR + "areas")
	if d == null:
		return out
	for n in d.get_directories():
		out.append(String(n))
	out.sort()
	return out


## The [WorldLocation] ids in world.tres's text (no script runs).
static func location_ids_from_world(text: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("(?m)^id = &\"([a-z0-9_]+)\"")
	for m in re.search_all(text):
		var id: String = m.get_string(1)
		if not out.has(id):
			out.append(id)
	return out


## The flags in [param builder_text] and [param tres_texts] (see the class doc), plus a RANK per
## flag: where it first appears in the builder text (the F_* constants are declared in story order),
## which the story flow sorts by. {known, set, ranks}.
static func collect_flags(builder_text: String, tres_texts: Array, tournament_ids: Array = []) -> Dictionary:
	var known: Dictionary = {}
	var set_flags: Dictionary = {}
	var ranks: Dictionary = {}
	var flag_re := RegEx.create_from_string(FLAG_PATTERN)
	var literal := RegEx.create_from_string("\"([a-z][a-z0-9_]*(?:\\.[a-z0-9_]+)+)\"")
	# The builder: every dotted literal (F_* constants, inline keys), ranked by first appearance.
	for m in literal.search_all(builder_text):
		var f: String = m.get_string(1)
		if f.get_extension() in ["tres", "tscn", "gd", "glb", "png", "webp", "json", "wav", "ogg"]:
			continue
		known[f] = true
		if not ranks.has(f):
			ranks[f] = m.get_start()
	var key_re := RegEx.create_from_string("(?m)^(?:key|flag_on_join|learned_flag) = \"([^\"]+)\"")
	var enc_re := RegEx.create_from_string("(?m)^encounter_id = \"([^\"]+)\"")
	# Battle rewards: a BattleSpec's reward_flags = Array[String]([...]), a request's {"flags": [...]}.
	var rewards_re := RegEx.create_from_string("(?m)(?:\"flags\": |^[a-z_]*flags = Array\\[String\\]\\()\\[([^\\]]*)\\]")
	var quoted := RegEx.create_from_string("\"([^\"]+)\"")
	var has_re := RegEx.create_from_string("has\\(\\\\?\"([a-z][a-z0-9_.]*)\\\\?\"\\)")
	for raw in tres_texts:
		var text: String = String(raw)
		for m in key_re.search_all(text):
			_add(m.get_string(1), known, set_flags, flag_re)
		for m in enc_re.search_all(text):
			_add(m.get_string(1) + ".defeated", known, set_flags, flag_re)
		for m in rewards_re.search_all(text):
			for q in quoted.search_all(m.get_string(1)):
				_add(q.get_string(1), known, set_flags, flag_re)
		for m in has_re.search_all(text):
			known[m.get_string(1)] = true
	for t in tournament_ids:
		for suffix in ["run", "round", "wins", "champion"]:
			_add("arena.%s.%s" % [String(t), suffix], known, set_flags, flag_re)
	return {"known": _sorted(known), "set": _sorted(set_flags), "ranks": ranks}


static func _add(f: String, known: Dictionary, set_flags: Dictionary, flag_re: RegEx) -> void:
	if flag_re.search(f) == null:
		return
	known[f] = true
	set_flags[f] = true


static func _sorted(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in d.keys():
		out.append(String(k))
	out.sort()
	return out


## The problems in [param defs] against [param scan] ([method scan_project] / [method collect_flags]
## + optional "locations" / "areas"): [{severity, quest, message}], errors first. Checked: duplicate
## / missing ids, empty title / step text / step flag, an unknown category, flags no content
## mentions, a start flag no content SETS (the quest can never appear), a complete flag nothing
## sets, and a location / area id the world does not have.
static func validate(defs: Array, scan: Dictionary) -> Array:
	var issues: Array = []
	var known: Array = scan.get("known", [])
	var set_flags: Array = scan.get("set", [])
	var steps_set: Dictionary = {}
	for d in defs:
		if d is Dictionary:
			for s in d.get("steps", []):
				if s is Dictionary:
					steps_set[String(s.get("flag", ""))] = true
	var locations: Array = scan.get("locations", [])
	var areas: Array = scan.get("areas", [])
	var seen: Dictionary = {}
	for i in range(defs.size()):
		var d = defs[i]
		if not (d is Dictionary):
			issues.append(_issue(SEVERITY_ERROR, "#%d" % i, "not an object"))
			continue
		var id: String = String(d.get("id", ""))
		var who: String = id if not id.is_empty() else "#%d" % i
		if id.is_empty():
			issues.append(_issue(SEVERITY_ERROR, who, "has no id"))
		elif seen.has(id):
			issues.append(_issue(SEVERITY_ERROR, who, "duplicate id"))
		seen[id] = true
		if String(d.get("title", "")).strip_edges().is_empty():
			issues.append(_issue(SEVERITY_ERROR, who, "empty title"))
		var cat: String = String(d.get("category", ""))
		if cat != QuestLog.MAIN and cat != QuestLog.SIDE:
			issues.append(_issue(SEVERITY_WARNING, who, "category '%s' is neither main nor side" % cat))
		var start: String = String(d.get("start_flag", ""))
		if not start.is_empty():
			if not known.has(start):
				issues.append(_issue(SEVERITY_WARNING, who, "start flag '%s' is unknown to the story content" % start))
			if not set_flags.has(start):
				issues.append(_issue(SEVERITY_ERROR, who, "unreachable: start flag '%s' is never set by any content" % start))
		var complete: String = String(d.get("complete_flag", ""))
		if not complete.is_empty() and not set_flags.has(complete):
			issues.append(_issue(SEVERITY_WARNING, who, "complete flag '%s' is never set by any content" % complete))
		_check_place(who, "quest", d, locations, areas, issues)
		var steps = d.get("steps", [])
		if not (steps is Array) or (steps as Array).is_empty():
			issues.append(_issue(SEVERITY_WARNING, who, "has no steps"))
			continue
		for si in range((steps as Array).size()):
			var s = steps[si]
			var where: String = "step %d" % (si + 1)
			if not (s is Dictionary):
				issues.append(_issue(SEVERITY_ERROR, who, "%s is not an object" % where))
				continue
			var flag: String = String(s.get("flag", ""))
			if flag.is_empty():
				issues.append(_issue(SEVERITY_ERROR, who, "%s has no flag" % where))
			elif not known.has(flag):
				issues.append(_issue(SEVERITY_WARNING, who, "%s flag '%s' is unknown to the story content" % [where, flag]))
			elif not set_flags.has(flag):
				issues.append(_issue(SEVERITY_WARNING, who, "%s flag '%s' is never set by any content" % [where, flag]))
			if String(s.get("text", "")).strip_edges().is_empty():
				issues.append(_issue(SEVERITY_ERROR, who, "%s has empty text" % where))
			_check_place(who, where, s, locations, areas, issues)
	# Errors first, each group in authoring order (a stable partition, not a sort).
	var out: Array = errors(issues)
	out.append_array(issues.filter(func(i: Dictionary) -> bool: return String(i["severity"]) != SEVERITY_ERROR))
	return out


static func _check_place(who: String, where: String, d: Dictionary, locations: Array, areas: Array,
		issues: Array) -> void:
	if locations.is_empty() and areas.is_empty():
		return
	var loc: String = String(d.get("location", ""))
	if not loc.is_empty() and not locations.has(loc) and not areas.has(loc):
		issues.append(_issue(SEVERITY_WARNING, who, "%s location '%s' is not a world place or area" % [where, loc]))
	var area: String = String(d.get("area", ""))
	if not area.is_empty() and not areas.has(area):
		issues.append(_issue(SEVERITY_WARNING, who, "%s area '%s' is not a built area" % [where, area]))


static func _issue(severity: String, quest: String, message: String) -> Dictionary:
	return {"severity": severity, "quest": quest, "message": message}


static func errors(issues: Array) -> Array:
	return issues.filter(func(i: Dictionary) -> bool: return String(i["severity"]) == SEVERITY_ERROR)


## THE STORY FLOW: [param defs] in the order their start flags are reached -- a quest open from the
## start first, then by the start flag's rank (its first appearance in the builder, where the F_*
## constants are declared in story order; a flag that is another quest's step / complete flag ranks
## just after that step). Quests whose start flag nothing sets come last, marked unreachable.
## [{id, title, category, start_flag, reachable, after}] ("after" = the quest whose progress opens
## it, "" when none).
static func story_flow(defs: Array, scan: Dictionary) -> Array:
	var ranks: Dictionary = scan.get("ranks", {})
	var set_flags: Array = scan.get("set", [])
	# A step / complete flag of quest Q: Q opens it.
	var opened_by: Dictionary = {}
	for d in defs:
		if not (d is Dictionary):
			continue
		for s in d.get("steps", []):
			if s is Dictionary and not opened_by.has(String(s.get("flag", ""))):
				opened_by[String(s.get("flag", ""))] = String(d.get("id", ""))
		var cf: String = String(d.get("complete_flag", ""))
		if not cf.is_empty() and not opened_by.has(cf):
			opened_by[cf] = String(d.get("id", ""))
	var rows: Array = []
	for i in range(defs.size()):
		var d = defs[i]
		if not (d is Dictionary):
			continue
		var start: String = String(d.get("start_flag", ""))
		var reachable: bool = start.is_empty() or set_flags.has(start)
		var rank: int = -1 if start.is_empty() else int(ranks.get(start, 1 << 30))
		rows.append({"id": String(d.get("id", "")), "title": String(d.get("title", "")),
			"category": String(d.get("category", "")), "start_flag": start, "reachable": reachable,
			"after": String(opened_by.get(start, "")) if not start.is_empty() else "",
			"_rank": rank if reachable else (1 << 31) - 1, "_i": i})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["_rank"]) != int(b["_rank"]):
			return int(a["_rank"]) < int(b["_rank"])
		return int(a["_i"]) < int(b["_i"]))
	for r in rows:
		r.erase("_rank")
		r.erase("_i")
	return rows
