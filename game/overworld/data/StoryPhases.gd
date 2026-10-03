class_name StoryPhases
extends RefCounted

## THE STORY TIMELINE the dialogue tools reason in, DERIVED from the MAIN quests of
## game/overworld/content/quests.json ([QuestLog]) -- never authored twice. Each main quest's
## start flag, step flags and completion flag, in file order, are the MILESTONES; phase 0 is a new
## journey, and phase k is "the first k milestones are done". A new main quest in quests.json is a
## new stretch of the timeline with no code change.
##
## [method state_for] builds the [StoryState] a phase stands for (its milestone flags set, plus
## anything ticked in the editor's "simulate flags" panel and some story time), and
## [method variant_phases] says in which phases a dialogue variant is the one that plays -- the
## "which route / phase does this line belong to" the Dialogue editor shows.
##
## Pure and static: it reads quests.json and builds states, nothing else (usable in the editor).


## Every milestone in story order: [{flag, quest_id, quest_title, text}] (unique flags).
static func milestones(defs: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen: Dictionary = {}
	var source: Array = defs if not defs.is_empty() else QuestLog.definitions()
	for q in source:
		if not (q is Dictionary) or String(q.get("category", "")) != QuestLog.MAIN:
			continue
		var qid: String = String(q.get("id", ""))
		var title: String = String(q.get("title", qid))
		var rows: Array = []
		rows.append([String(q.get("start_flag", "")), "%s begins" % title])
		for s in q.get("steps", []):
			if s is Dictionary:
				rows.append([String(s.get("flag", "")), String(s.get("text", ""))])
		rows.append([String(q.get("complete_flag", "")), "%s complete" % title])
		for r in rows:
			var f: String = String(r[0])
			if f.is_empty() or seen.has(f):
				continue
			seen[f] = true
			out.append({"flag": f, "quest_id": qid, "quest_title": title, "text": String(r[1])})
	return out


## The phases: index 0 = a new journey (no milestone), then one per milestone reached:
## [{index, flag ("" for 0), label, short, quest_title, flags: Array[String] (every milestone set)}].
static func phases(defs: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ms: Array[Dictionary] = milestones(defs)
	var first_quest: String = String(ms[0]["quest_title"]) if not ms.is_empty() else "the story"
	out.append({"index": 0, "flag": "", "label": "P0 · New journey (before %s)" % (ms[0]["flag"] if not ms.is_empty() else "anything"),
		"short": "P0", "quest_title": first_quest, "flags": [] as Array[String]})
	var set_flags: Array[String] = []
	for i in range(ms.size()):
		var m: Dictionary = ms[i]
		set_flags.append(String(m["flag"]))
		out.append({
			"index": i + 1,
			"flag": String(m["flag"]),
			"label": "P%d · %s › after %s" % [i + 1, m["quest_title"], m["flag"]],
			"short": "P%d" % (i + 1),
			"quest_title": String(m["quest_title"]),
			"text": String(m["text"]),
			"flags": set_flags.duplicate(),
		})
	return out


## The state phase [param phase] stands for: its milestone flags set (stamped at the start of
## time), [param extra_flags] set too and [param cleared_flags] cleared, then [param rests] rests
## and [param steps] steps pass -- so "rests_since(x) >= 3" holds with rests = 3.
static func state_for(phase: Dictionary, extra_flags: Array = [], cleared_flags: Array = [],
		rests: int = 0, steps: int = 0) -> StoryState:
	var s := StoryState.new()
	for f in phase.get("flags", []):
		s.set_flag(String(f), 1)
	for f in extra_flags:
		s.set_flag(String(f), 1)
	for f in cleared_flags:
		s.clear_flag(String(f))
	s.rests = maxi(0, rests)
	s.steps = maxi(0, steps)
	s.play_seconds = float(steps)
	return s


## For a bank entry: per variant, the phase indices in which it is the variant that PLAYS (first
## match wins). [param phase_list] = [method phases]. Extra / cleared flags and time as
## [method state_for].
static func variant_phases(entry: Dictionary, phase_list: Array, extra_flags: Array = [],
		cleared_flags: Array = [], rests: int = 0, steps: int = 0) -> Array:
	var vs: Array = entry.get("variants", [])
	var out: Array = []
	for i in range(vs.size()):
		out.append([])
	for p in phase_list:
		var st: StoryState = state_for(p, extra_flags, cleared_flags, rests, steps)
		var pick: int = DialogueBank.pick(entry, st)
		if pick >= 0:
			(out[pick] as Array).append(int(p["index"]))
	return out


## "P3-P5, P8" for a list of phase indices.
static func compact(indices: Array) -> String:
	if indices.is_empty():
		return "never"
	var sorted: Array = indices.duplicate()
	sorted.sort()
	var parts: Array[String] = []
	var start: int = int(sorted[0])
	var prev: int = start
	for i in range(1, sorted.size() + 1):
		var cur: int = int(sorted[i]) if i < sorted.size() else -99
		if cur == prev + 1:
			prev = cur
			continue
		parts.append("P%d" % start if start == prev else "P%d-P%d" % [start, prev])
		start = cur
		prev = cur
	return ", ".join(parts)
