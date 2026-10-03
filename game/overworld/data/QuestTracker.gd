class_name QuestTracker
extends RefCounted

## QUEST TRANSITIONS (docs/STORY_MODE.md "Quest tracking"): which quests STARTED, ADVANCED to a new
## objective or COMPLETED since the last look -- found by DIFFING two [QuestLog] views, never by
## listening to individual flags, so every way a flag gets set (a script, a battle result, a
## debug console) is covered and nothing new is saved.
##
## [method reset] takes a baseline WITHOUT events (a loaded save, a new journey, Try Again's
## restored state: none of that is news); [method poll] diffs against it once
## [member StoryState.flags_revision] moved and returns the events, oldest view first:
##   {kind: "started" | "advanced" | "completed", id, title, category, objective}
## Pure: the StoryController owns one and the overworld shows its events as toasts.

const STARTED := "started"
const ADVANCED := "advanced"
const COMPLETED := "completed"

## Definitions override (tests); empty = the shipped quests.json.
var defs: Array = []

var _state: StoryState = null
var _revision: int = -1
var _last: Dictionary = {}


## The comparable view of every listed quest: id -> {status, step, title, category, objective}.
static func snapshot(state: StoryState, p_defs: Array = []) -> Dictionary:
	var out: Dictionary = {}
	if state == null:
		return out
	for e in QuestLog.entries(state, p_defs):
		out[String(e["id"])] = {
			"status": String(e["status"]),
			"step": int(e["step_index"]),
			"title": String(e["title"]),
			"category": String(e["category"]),
			"objective": String(e["objective"]),
		}
	return out


## The transitions from [param before] to [param after] (two [method snapshot]s). A quest that
## appears already finished reports only "completed"; a quest whose flags were CLEARED (it went
## back, or left the log) reports nothing -- only forward progress is news.
static func diff(before: Dictionary, after: Dictionary) -> Array:
	var events: Array = []
	for id in after:
		var a: Dictionary = after[id]
		var done: bool = String(a["status"]) == QuestLog.STATUS_DONE
		if not before.has(id):
			events.append(_event(COMPLETED if done else STARTED, String(id), a))
			continue
		var b: Dictionary = before[id]
		var was_done: bool = String(b["status"]) == QuestLog.STATUS_DONE
		if done and not was_done:
			events.append(_event(COMPLETED, String(id), a))
		elif not done and not was_done and int(a["step"]) > int(b["step"]):
			events.append(_event(ADVANCED, String(id), a))
	return events


static func _event(kind: String, id: String, view: Dictionary) -> Dictionary:
	return {"kind": kind, "id": id, "title": String(view["title"]), "category": String(view["category"]),
		"objective": String(view["objective"])}


## Baseline [param state] as it stands now (no events).
func reset(state: StoryState) -> void:
	_state = state
	_revision = state.flags_revision if state != null else -1
	_last = snapshot(state, defs)


## The transitions since the last poll / reset. A DIFFERENT state object than the baseline's (a
## load, Try Again) is re-baselined silently. Cheap when no flag changed.
func poll(state: StoryState) -> Array:
	if state != _state:
		reset(state)
		return []
	if state == null or state.flags_revision == _revision:
		return []
	_revision = state.flags_revision
	var now: Dictionary = snapshot(state, defs)
	var events: Array = diff(_last, now)
	_last = now
	return events


## The one-line toast for event [param e]: "New quest: X", "X: <objective>", "Quest complete: X".
static func toast_text(e: Dictionary) -> String:
	match String(e.get("kind", "")):
		STARTED:
			return "New quest: %s" % String(e.get("title", ""))
		ADVANCED:
			var obj: String = String(e.get("objective", ""))
			return "%s: %s" % [String(e.get("title", "")), obj] if not obj.is_empty() else String(e.get("title", ""))
		COMPLETED:
			return "Quest complete: %s" % String(e.get("title", ""))
	return ""
