class_name DialogueBank
extends RefCounted

## THE DIALOGUE BANK: what townsfolk SAY, as data (game/overworld/content/dialogue.json), so the
## owner can edit and extend NPC talk without touching the content builder or the saves -- the
## same discipline as [QuestLog]: nothing here is saved, every pick is computed from a
## [StoryState]'s flags and clocks, so a line can be added, reworded or re-gated by editing JSON
## (by hand or with the Dialogue editor, addons/dialogue_editor) and it shows on the next talk.
##
## SCHEMA (keys are written sorted, tab-indented -- see [method to_json]):
## [codeblock]
## {
##   "_about": "free text",
##   "areas": {
##     "<area_id>": {
##       "<npc_id>": {                      an NpcEntity id in that area's area.tres
##         "note": "optional author note",
##         "variants": [                    ORDERED: the FIRST whose "if" passes plays
##           {
##             "if": "after('opening.attack') and rests_since('opening.complete') < 3",
##             "label": "optional short name",
##             "lines": [
##               {"speaker": "self", "text": "..."},       the NPC itself (right side)
##               {"speaker": "hero", "text": "..."},       the player's hero (left side)
##               {"speaker": "narrator", "text": "..."},   narration, no portraits
##               {"speaker": "<npc id>", "text": "..."},   another NPC of the same area
##               optional per line: "side": "left"/"right", "name": display-name override
##             ]
##           }
##         ]
##       }
##     }
##   },
##   "version": 1
## }
## [/codeblock]
## "if" is a [ConditionContext] expression (blank = always): has / after / before, flag(),
## visited(), party_has(), and story TIME -- rests_since / steps_since / minutes_since a flag
## (StoryState.flag_times), rests(), steps(), play_minutes(). {hero} / {lead} / {gold} in a line
## are filled at runtime like any [SayCommand].
##
## RUNTIME ([NpcEntity.interact_script]): an NPC WITH an entry says its first matching variant
## (nothing when none matches) INSTEAD of its authored .tres [member NpcEntity.dialogue]; its
## [member OverworldEntity.on_interact] (a ceremony, a spar offer, a shop) still runs after it. An
## NPC with no entry keeps the authored .tres dialogue. Cutscenes stay in the builder.
##
## Failures are values (CONQUEST.md rule 1): a missing / malformed file reads as an EMPTY bank and
## never logs; [method validate] reports what is wrong instead.

const DATA_PATH := "res://game/overworld/content/dialogue.json"
const VERSION := 1

const SPEAKER_SELF := "self"
const SPEAKER_HERO := "hero"
const SPEAKER_NARRATOR := "narrator"
const SIDE_LEFT := "left"
const SIDE_RIGHT := "right"

## Marks a line as unfinished (the editor's "missing dialogue" view lists them).
const PLACEHOLDER_MARKERS: Array[String] = ["TODO", "TBD", "FIXME", "???"]

## The condition helpers that take a FLAG name as their first argument (the validator checks the
## flag exists; the editor shows them readably).
const FLAG_FUNCS: Array[String] = ["has", "after", "before", "flag", "rests_since", "steps_since", "minutes_since"]

static var _cache: Dictionary = {}
static var _loaded: bool = false
static var _path: String = DATA_PATH


# =====================================================================================
#  Loading
# =====================================================================================

## The bank (normalised, cached). A missing or unreadable file is an empty bank.
static func data() -> Dictionary:
	if _loaded:
		return _cache
	_loaded = true
	_cache = parse_text(FileAccess.get_file_as_string(_path)).get("data", empty())
	return _cache


## Tests / the editor: swap the bank in ([param d] = null reloads the shipped file on next use).
static func set_data(d) -> void:
	if d == null:
		_loaded = false
		_cache = {}
		return
	_loaded = true
	_cache = normalize(d)


## Point the bank at another file (tests); "" = the shipped one. Forgets the cache.
static func set_path(path: String) -> void:
	_path = path if not path.is_empty() else DATA_PATH
	set_data(null)


static func path() -> String:
	return _path


static func empty() -> Dictionary:
	return {"areas": {}, "version": VERSION}


## Parse JSON text: {ok, data (normalised; empty on failure), error}.
static func parse_text(text: String) -> Dictionary:
	if text.strip_edges().is_empty():
		return {"ok": false, "data": empty(), "error": "empty file"}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {"ok": false, "data": empty(),
			"error": "JSON error line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if not (json.data is Dictionary):
		return {"ok": false, "data": empty(), "error": "the top level is not an object"}
	return {"ok": true, "data": normalize(json.data), "error": ""}


## A schema-coerced DEEP COPY of [param raw] (CONQUEST.md rule 3: every field through a coercion,
## unknown keys dropped, empty optionals left out so the saved file stays minimal and diffs small).
static func normalize(raw) -> Dictionary:
	var out: Dictionary = empty()
	if not (raw is Dictionary):
		return out
	if raw.has("_about"):
		out["_about"] = String(raw["_about"])
	var areas = raw.get("areas", {})
	if not (areas is Dictionary):
		return out
	for aid in areas:
		var npcs = areas[aid]
		if not (npcs is Dictionary):
			continue
		var area_out: Dictionary = {}
		for nid in npcs:
			var e = npcs[nid]
			if e is Dictionary:
				area_out[String(nid)] = normalize_entry(e)
		out["areas"][String(aid)] = area_out
	return out


static func normalize_entry(e: Dictionary) -> Dictionary:
	var out: Dictionary = {"variants": []}
	var note: String = String(e.get("note", "")).strip_edges()
	if not note.is_empty():
		out["note"] = note
	var vs = e.get("variants", [])
	if vs is Array:
		for v in vs:
			if v is Dictionary:
				out["variants"].append(normalize_variant(v))
	return out


static func normalize_variant(v: Dictionary) -> Dictionary:
	var out: Dictionary = {"if": String(v.get("if", "")).strip_edges(), "lines": []}
	var label: String = String(v.get("label", "")).strip_edges()
	if not label.is_empty():
		out["label"] = label
	var ls = v.get("lines", [])
	if ls is Array:
		for l in ls:
			if l is Dictionary:
				out["lines"].append(normalize_line(l))
	return out


static func normalize_line(l: Dictionary) -> Dictionary:
	var speaker: String = String(l.get("speaker", SPEAKER_SELF)).strip_edges()
	if speaker.is_empty():
		speaker = SPEAKER_SELF
	var out: Dictionary = {"speaker": speaker, "text": String(l.get("text", ""))}
	var side: String = String(l.get("side", "")).strip_edges().to_lower()
	if not side.is_empty() and side != default_side(speaker):
		out["side"] = side
	var nm: String = String(l.get("name", "")).strip_edges()
	if not nm.is_empty():
		out["name"] = nm
	return out


## The side a speaker stands on when a line names none: the hero left, everyone else right.
static func default_side(speaker: String) -> String:
	return SIDE_LEFT if speaker == SPEAKER_HERO or speaker == SPEAKER_NARRATOR else SIDE_RIGHT


## The bank as STABLE, pretty JSON: keys sorted, tab indents, a trailing newline -- so saving the
## same data twice writes the same bytes and a one-line edit is a one-line diff.
static func to_json(d: Dictionary) -> String:
	return JSON.stringify(normalize(d), "\t", true) + "\n"


## Write [param d] to [param file_path] (the shipped file by default). {ok, error}.
static func save(d: Dictionary, file_path: String = "") -> Dictionary:
	var target: String = file_path if not file_path.is_empty() else _path
	var f := FileAccess.open(target, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "cannot write %s (%s)" % [target, error_string(FileAccess.get_open_error())]}
	f.store_string(to_json(d))
	f.close()
	if target == _path:
		set_data(d)
	return {"ok": true, "error": ""}


# =====================================================================================
#  Lookup + picking
# =====================================================================================

## The entry of [param npc_id] in [param area_id] ({} when the bank has none).
static func entry(area_id: String, npc_id: String, d: Dictionary = {}) -> Dictionary:
	var src: Dictionary = d if not d.is_empty() else data()
	var area = src.get("areas", {}).get(area_id, null)
	if not (area is Dictionary):
		return {}
	var e = area.get(npc_id, null)
	return e if e is Dictionary else {}


static func has_entry(area_id: String, npc_id: String) -> bool:
	return not entry(area_id, npc_id).is_empty()


## The index of the first variant of [param e] whose condition passes under [param state], or -1.
static func pick(e: Dictionary, state: StoryState) -> int:
	var vs = e.get("variants", [])
	if not (vs is Array):
		return -1
	for i in range(vs.size()):
		var v = vs[i]
		if v is Dictionary and ConditionContext.evaluate(String(v.get("if", "")), state):
			return i
	return -1


## What [param npc_id] says right now: a [SayCommand] of the first matching variant's lines, or
## null (no entry, nothing matches, or the variant has no lines).
static func say_command(area_id: String, npc_id: String, state: StoryState) -> SayCommand:
	var e: Dictionary = entry(area_id, npc_id)
	if e.is_empty():
		return null
	var i: int = pick(e, state)
	if i < 0:
		return null
	var beats: Array[StoryBeat] = beats_of(e["variants"][i], area_id)
	if beats.is_empty():
		return null
	var c := SayCommand.new()
	c.beats = StoryCommand.list(beats)
	return c


## The playable beats of one variant (speakers resolved against [param area_id]'s NPCs).
static func beats_of(variant: Dictionary, area_id: String) -> Array[StoryBeat]:
	var out: Array[StoryBeat] = []
	var lines = variant.get("lines", [])
	if not (lines is Array):
		return out
	var area: OverworldAreaResource = null
	for l in lines:
		if not (l is Dictionary):
			continue
		var speaker: String = String(l.get("speaker", SPEAKER_SELF))
		if area == null and not [SPEAKER_SELF, SPEAKER_HERO, SPEAKER_NARRATOR].has(speaker):
			area = OverworldAreaResource.load_by_id(area_id)
		out.append(make_beat(l, area))
	return out


## One JSON line -> a [StoryBeat]. "self" and "hero" stay placeholders [SayCommand] resolves at
## runtime; another NPC's id takes that entity's speaker id and name (from [param area]).
static func make_beat(l: Dictionary, area: OverworldAreaResource = null) -> StoryBeat:
	var b := StoryBeat.new()
	var speaker: String = String(l.get("speaker", SPEAKER_SELF)).strip_edges()
	b.text = String(l.get("text", ""))
	b.speaker_name = String(l.get("name", ""))
	match speaker:
		SPEAKER_SELF, "":
			b.speaker_id = SayCommand.SELF_ID
		SPEAKER_HERO:
			b.speaker_id = SayCommand.HERO_ID
		SPEAKER_NARRATOR:
			b.speaker_id = StoryBeat.NARRATOR
			b.clear_portraits = true
		_:
			var other: NpcEntity = area.entity(speaker) as NpcEntity if area != null else null
			if other != null:
				b.speaker_id = other.speaker_id if not String(other.speaker_id).is_empty() else StringName("npc_" + speaker)
				if b.speaker_name.is_empty():
					b.speaker_name = other.speaker_label()
			else:
				b.speaker_id = StringName("npc_" + speaker)
				if b.speaker_name.is_empty():
					b.speaker_name = speaker.capitalize()
	var side: String = String(l.get("side", default_side(speaker)))
	b.side = StoryBeat.SIDE_LEFT if side == SIDE_LEFT else StoryBeat.SIDE_RIGHT
	return b


# =====================================================================================
#  Conditions, readably
# =====================================================================================

## Every flag name a condition reads (has / after / before / flag / *_since), in order, unique.
static func flags_in(condition: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.create_from_string("\\b(%s)\\s*\\(\\s*[\"']([^\"']+)[\"']\\s*\\)" % "|".join(FLAG_FUNCS))
	for m in re.search_all(condition):
		var f: String = m.get_string(2)
		if not out.has(f):
			out.append(f)
	return out


## A condition as the editor shows it: "after: opening.attack · before: opening.complete · 3+ rests
## since opening.complete". Blank = "always". Anything it cannot rephrase stays as written.
static func describe_condition(condition: String) -> String:
	var text: String = condition.strip_edges()
	if text.is_empty():
		return "always"
	var q := "[\"']([^\"']+)[\"']"
	var rules: Array = [
		["not\\s+(?:has|after)\\s*\\(\\s*%s\\s*\\)" % q, "before: $1"],
		["not\\s+before\\s*\\(\\s*%s\\s*\\)" % q, "after: $1"],
		["\\b(?:has|after)\\s*\\(\\s*%s\\s*\\)" % q, "after: $1"],
		["\\bbefore\\s*\\(\\s*%s\\s*\\)" % q, "before: $1"],
		["\\brests_since\\s*\\(\\s*%s\\s*\\)\\s*>=\\s*(\\d+)" % q, "$2+ rests since $1"],
		["\\bsteps_since\\s*\\(\\s*%s\\s*\\)\\s*>=\\s*(\\d+)" % q, "$2+ steps since $1"],
		["\\bminutes_since\\s*\\(\\s*%s\\s*\\)\\s*>=\\s*(\\d+)" % q, "$2+ min since $1"],
		["\\brests_since\\s*\\(\\s*%s\\s*\\)\\s*<\\s*(\\d+)" % q, "under $2 rests since $1"],
		["\\bsteps_since\\s*\\(\\s*%s\\s*\\)\\s*<\\s*(\\d+)" % q, "under $2 steps since $1"],
		["\\bminutes_since\\s*\\(\\s*%s\\s*\\)\\s*<\\s*(\\d+)" % q, "under $2 min since $1"],
		["\\bflag\\s*\\(\\s*%s\\s*\\)\\s*(>=|<=|==|>|<|!=)\\s*(\\d+)" % q, "$1 $2 $3"],
		["\\bvisited\\s*\\(\\s*%s\\s*\\)" % q, "visited: $1"],
		["\\bparty_has\\s*\\(\\s*%s\\s*\\)" % q, "in party: $1"],
		["\\bspar_ready\\s*\\(\\s*%s\\s*\\)" % q, "spar ready: $1"],
		["\\s+and\\s+", " · "],
		["\\s+or\\s+", " OR "],
	]
	for r in rules:
		var re := RegEx.create_from_string(String(r[0]))
		text = re.sub(text, String(r[1]), true)
	return text


static func is_placeholder(text: String) -> bool:
	var t: String = text.strip_edges()
	if t.is_empty():
		return true
	for m in PLACEHOLDER_MARKERS:
		if t.contains(m):
			return true
	return false


# =====================================================================================
#  Validation
# =====================================================================================

## Content checks for [param d] against the shipped story ([param index]: a [StoryContentIndex];
## null = build one). Returns human-readable issues ("" never): unknown areas / NPCs / speakers,
## malformed conditions, unknown flags, entries with no variants, variants with no lines, empty
## lines, bad sides, and variants that can never play (an earlier one always matches).
static func validate(d: Dictionary, index: StoryContentIndex = null) -> Array[String]:
	var issues: Array[String] = []
	var idx: StoryContentIndex = index if index != null else StoryContentIndex.build()
	var areas = d.get("areas", {})
	if not (areas is Dictionary):
		issues.append("'areas' is not an object")
		return issues
	var aids: Array = areas.keys()
	aids.sort()
	for aid in aids:
		var a: String = String(aid)
		if not idx.has_area(a):
			issues.append("%s: unknown area" % a)
			continue
		var npcs: Dictionary = areas[aid] if areas[aid] is Dictionary else {}
		var nids: Array = npcs.keys()
		nids.sort()
		for nid in nids:
			_validate_entry(a, String(nid), npcs[nid], idx, issues)
	return issues


static func _validate_entry(aid: String, nid: String, e, idx: StoryContentIndex, issues: Array[String]) -> void:
	var where: String = "%s/%s" % [aid, nid]
	if not idx.has_npc(aid, nid):
		issues.append("%s: no NPC '%s' in %s's area.tres" % [where, nid, aid])
	if not (e is Dictionary):
		issues.append("%s: entry is not an object" % where)
		return
	var vs = e.get("variants", [])
	if not (vs is Array) or vs.is_empty():
		issues.append("%s: no variants" % where)
		return
	var always_at: int = -1
	for i in range(vs.size()):
		var v = vs[i]
		var vw: String = "%s variant %d" % [where, i + 1]
		if not (v is Dictionary):
			issues.append("%s: not an object" % vw)
			continue
		var cond: String = String(v.get("if", ""))
		if always_at >= 0:
			issues.append("%s: never plays (variant %d always matches first)" % [vw, always_at + 1])
		if cond.strip_edges().is_empty() and always_at < 0:
			always_at = i
		var chk: Dictionary = ConditionContext.check(cond)
		if not bool(chk.get("valid", false)):
			issues.append("%s: malformed condition '%s' (%s)" % [vw, cond, String(chk.get("error", ""))])
		for f in flags_in(cond):
			if not idx.is_known_flag(f):
				issues.append("%s: unknown flag '%s' (no script, quest or entity sets or reads it)" % [vw, f])
		var lines = v.get("lines", [])
		if not (lines is Array) or lines.is_empty():
			issues.append("%s: has no lines" % vw)
			continue
		for j in range(lines.size()):
			var l = lines[j]
			var lw: String = "%s line %d" % [vw, j + 1]
			if not (l is Dictionary):
				issues.append("%s: not an object" % lw)
				continue
			if String(l.get("text", "")).strip_edges().is_empty():
				issues.append("%s: empty text" % lw)
			var sp: String = String(l.get("speaker", SPEAKER_SELF))
			if not [SPEAKER_SELF, SPEAKER_HERO, SPEAKER_NARRATOR, ""].has(sp) and not idx.has_npc(aid, sp):
				issues.append("%s: unknown speaker '%s' (self / hero / narrator / an NPC id of %s)" % [lw, sp, aid])
			var side: String = String(l.get("side", ""))
			if not ["", SIDE_LEFT, SIDE_RIGHT].has(side):
				issues.append("%s: side '%s' is not left / right" % [lw, side])
