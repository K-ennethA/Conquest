class_name QuestLog
extends RefCounted

## THE QUEST / OBJECTIVE LOG: pure, data-driven and flag-derived (docs/design/OVERWORLD.md §4.2 --
## quests ARE flags). Nothing here is saved: every view is computed from a [StoryState]'s flags
## against the definitions in [constant DATA_PATH], so a quest can be added, reworded or reordered
## by editing JSON without a save migration.
##
## A definition: {id, title, category ("main" / "side"), summary, start_flag, complete_flag,
## steps: [{flag, text}]}. A quest is LISTED once its [code]start_flag[/code] is set ("" = from the
## start); it is DONE once its [code]complete_flag[/code] is set (blank = every step's flag set);
## its CURRENT OBJECTIVE is the first step whose flag is not set yet.

const DATA_PATH := "res://game/overworld/content/quests.json"
const MAIN := "main"
const SIDE := "side"
const STATUS_ACTIVE := "active"
const STATUS_DONE := "done"

static var _defs_cache: Array = []
static var _defs_loaded: bool = false


## Every authored definition (cached). A missing / unreadable file reads as no quests.
static func definitions() -> Array:
	if _defs_loaded:
		return _defs_cache
	_defs_loaded = true
	_defs_cache = _parse(FileAccess.get_file_as_string(DATA_PATH))
	return _defs_cache


## Tests: swap the definitions in ([param defs] = null reloads the shipped file).
static func set_definitions(defs) -> void:
	_defs_loaded = defs != null
	_defs_cache = defs if defs != null else []


static func _parse(text: String) -> Array:
	var out: Array = []
	if text.strip_edges().is_empty():
		return out
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return out
	for q in parsed.get("quests", []):
		if q is Dictionary and not String(q.get("id", "")).is_empty():
			out.append(q)
	return out


## The log for [param state]: one entry per LISTED quest, main before side, active before done:
## {id, title, category, summary, status, objective, steps: [{text, done}]}.
static func entries(state: StoryState, defs: Array = []) -> Array:
	var source: Array = defs if not defs.is_empty() else definitions()
	var rows: Array = []
	for i in range(source.size()):
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
	var all_done: bool = true
	for s in def.get("steps", []):
		var done: bool = state.has_flag(String(s.get("flag", "")))
		steps.append({"text": String(s.get("text", "")), "done": done})
		if not done:
			all_done = false
			if objective.is_empty():
				objective = String(s.get("text", ""))
	var complete: String = String(def.get("complete_flag", ""))
	var finished: bool = state.has_flag(complete) if not complete.is_empty() else all_done
	return {
		"id": String(def.get("id", "")),
		"title": String(def.get("title", "")),
		"category": String(def.get("category", SIDE)),
		"summary": String(def.get("summary", "")),
		"status": STATUS_DONE if finished else STATUS_ACTIVE,
		"objective": "" if finished else objective,
		"steps": steps,
	}


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
