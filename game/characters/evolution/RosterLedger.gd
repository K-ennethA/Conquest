extends RefCounted
class_name RosterLedger

## The persistent ROSTER MEMBER store: how far each of YOUR units has grown, which form it
## currently is, and which evolved forms you have unlocked. docs/design/EVOLUTION.md §3.5.
##
## Deliberately a copy of [ItemInventory]'s shape: static, lazy-loaded, EXPLICIT [method save]
## (mutators never write, so a screen or a test can stage changes freely), and
## [method set_save_path] / [method reset] for tests. File: user://roster.json.
##
## MEMBERS. A member is one individual unit, keyed by a stable uid:
##   * open modes (Skirmish / Campaign / Challenge ...) have ONE implicit member per evolution
##     LINE, whose uid is the line's root id ("tree_grunt"). [method member_for_character]
##     resolves any form of the line to it, and the record is created lazily on first write.
##   * STORY: the overworld party is made of individuals with the same uid scheme
##     ("tree_grunt", "tree_grunt#2"...) and THIS record shape (one record type, not two --
##     docs/design/DECISIONS.md "Shared contracts"), but each journey keeps its members'
##     records inside its own save slot ([StoryPartyMember] is the story-scoped view of one)
##     and runs them through the RECORD-LEVEL API below ([method record_evolutions],
##     [method evolve_record]); only the open-mode UNLOCK lands in this store.
##     [method create_member] remains for a store-held individual ("tree_grunt#2").
##
## IDENTITY SEMANTICS (owner decision 2). In OPEN modes evolving UNLOCKS the new form: both
## Barkling and Oakheart stay pickable ([method is_form_unlocked]). In STORY the member itself
## BECOMES the new form ([method form_of] is what the party spawns). One evolve() serves both:
## it sets the member's form AND unlocks it.
##
## NEVER READ BY THE SIMULATION (EVOLUTION.md §1.3 invariant 1). A form enters a battle only as
## a character id in the squad; the ledger is consulted by menus, the post-battle
## [GrowthTracker] and the overworld, never inside the battle.
##
## Save schema (user://roster.json):
##   {
##     "version": 1,
##     "members": {
##       "<uid>": { "line": "<root id>", "form": "<character id>", "growth": <int>,
##                  "evolved": [ { "edge": "<edge id>", "at": "<ISO datetime>" } ],
##                  "nickname": "",
##                  "hold": false,        # HOLD: no automatic evolve prompts (DECISIONS #27)
##                  "feats": { "wins": 0, "kos": 0, "clutch_wins": 0,
##                             "element_kos": { "<element>": <int> } } }   # BattleFeatTrigger
##     },
##     "unlocked_forms": ["<character id>", ...]
##   }
## "hold" / "feats" are additive (the version stays 1): an older file loads them as off / zero.

const DEFAULT_SAVE_PATH: String = "user://roster.json"
const VERSION: int = 1
## Separator between a line root and a story member's ordinal ("tree_grunt#2").
const MEMBER_SEPARATOR: String = "#"

static var _save_path: String = DEFAULT_SAVE_PATH
static var _data: Dictionary = {}
static var _loaded: bool = false


# --- Store lifecycle --------------------------------------------------------

## Load from disk if not yet read. Every accessor calls this. A missing, unreadable or corrupt
## file yields a BLANK ledger -- never an engine error (CONQUEST.md rule 1): losing the
## player's growth to a bad file is bad, crashing the menu on it is worse.
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data = _blank()
	if not FileAccess.file_exists(_save_path):
		return
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return
	var text: String = file.get_as_text()
	file.close()
	# JSON.new().parse reports a failure as a return code; JSON.parse_string would log it.
	var json := JSON.new()
	if json.parse(text) != OK:
		return
	if json.data is Dictionary:
		_data = _normalize(json.data)


## Write the ledger. Returns false when the file cannot be opened.
static func save() -> bool:
	ensure_loaded()
	var dir: String = _save_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()
	return true


## Point the store at another file and drop the cache (tests; a future profile slot).
static func set_save_path(path: String) -> void:
	_save_path = path if not path.strip_edges().is_empty() else DEFAULT_SAVE_PATH
	_loaded = false
	_data = {}


static func save_path() -> String:
	return _save_path


## Wipe the in-memory ledger WITHOUT touching disk, marked loaded (tests, "start over").
static func reset() -> void:
	_data = _blank()
	_loaded = true


# --- Members ----------------------------------------------------------------

## The member uid that plays [param char_id] in OPEN modes: its line's root id. Any form of a
## line resolves to the same member, so Barkling and Oakheart share one growth record.
static func member_for_character(char_id) -> String:
	var key: String = String(char_id)
	if key.is_empty():
		return ""
	return String(EvolutionLibrary.line_root(StringName(key)))


## True when [param uid] has a stored record (implicit open-mode members have none until
## something is written).
static func has_member(uid) -> bool:
	ensure_loaded()
	return (_data["members"] as Dictionary).has(String(uid))


## Every stored member uid, sorted.
static func members() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for k in (_data["members"] as Dictionary).keys():
		out.append(String(k))
	out.sort()
	return out


## A COPY of [param uid]'s record (the implicit default when none is stored).
static func member(uid) -> Dictionary:
	return _record(String(uid), false).duplicate(true)


## STORY: create a new individual playing [param character_id] and return its uid. With an
## empty [param member_id] the uid is "<line root>#<n>" with the first free n >= 2 (n = 1 is
## the implicit open-mode member, the bare root id). A recruit may join as an evolved form
## ("oakheart"); its line is still the root. Returns "" for an unknown character or a taken
## explicit uid.
static func create_member(character_id, member_id: String = "") -> String:
	var cid: String = String(character_id)
	if cid.is_empty() or CharacterLibrary.get_character(cid) == null:
		return ""
	ensure_loaded()
	var members_dict: Dictionary = _data["members"]
	var line: String = member_for_character(cid)
	var uid: String = member_id.strip_edges()
	if uid.is_empty():
		var n: int = 2
		while members_dict.has("%s%s%d" % [line, MEMBER_SEPARATOR, n]):
			n += 1
		uid = "%s%s%d" % [line, MEMBER_SEPARATOR, n]
	elif members_dict.has(uid):
		return ""
	var rec: Dictionary = _default_record(line)
	rec["form"] = cid
	members_dict[uid] = rec
	_unlock(cid)
	return uid


static func nickname_of(uid) -> String:
	return String(_record(String(uid), false).get("nickname", ""))


static func set_nickname(uid, nickname: String) -> void:
	var rec: Dictionary = _record(String(uid), true)
	if not rec.is_empty():
		rec["nickname"] = nickname


# --- Hold (DECISIONS.md #27) --------------------------------------------------

## True when [param uid] is on HOLD: no automatic evolution prompts (a manual EVOLVE from a menu
## still works). Off for an unknown / implicit member.
static func is_held(uid) -> bool:
	return bool(_record(String(uid), false).get("hold", false))


## Put [param uid] on / off HOLD (creating the implicit record). Does not save.
static func set_hold(uid, on: bool) -> void:
	var rec: Dictionary = _record(String(uid), true)
	if not rec.is_empty():
		rec["hold"] = on


# --- Battle feats ([BattleFeatTrigger]) ----------------------------------------

## A zeroed feat-counter block.
static func blank_feats() -> Dictionary:
	return { "wins": 0, "kos": 0, "clutch_wins": 0, "element_kos": {} }


## [param raw] coerced into a feat block (missing / wrong-typed fields read as zero).
static func normalize_feats(raw) -> Dictionary:
	var out: Dictionary = blank_feats()
	if not (raw is Dictionary):
		return out
	for k in ["wins", "kos", "clutch_wins"]:
		out[k] = maxi(0, int(raw.get(k, 0)))
	var by = raw.get("element_kos", {})
	if by is Dictionary:
		for el in by.keys():
			var n: int = maxi(0, int(by[el]))
			if not String(el).is_empty() and n > 0:
				out["element_kos"][String(el)] = n
	return out


## Add the feat deltas [param delta] ({wins, kos, clutch_wins, element_kos}) into the record
## [param rec] in place (also a record held outside this store -- the story's member).
static func apply_feats(rec: Dictionary, delta: Dictionary) -> void:
	var f: Dictionary = normalize_feats(rec.get("feats", {}))
	var d: Dictionary = normalize_feats(delta)
	for k in ["wins", "kos", "clutch_wins"]:
		f[k] = int(f[k]) + int(d[k])
	for el in (d["element_kos"] as Dictionary).keys():
		f["element_kos"][el] = int((f["element_kos"] as Dictionary).get(el, 0)) + int(d["element_kos"][el])
	rec["feats"] = f


## The feat counters of [param uid] (a copy; zeros when unknown).
static func feats_of(uid) -> Dictionary:
	return normalize_feats(_record(String(uid), false).get("feats", {}))


## Add [param delta] to [param uid]'s feat counters (creating the implicit record). Does not save.
static func add_feats(uid, delta: Dictionary) -> void:
	var rec: Dictionary = _record(String(uid), true)
	if not rec.is_empty():
		apply_feats(rec, delta)


# --- Growth -----------------------------------------------------------------

## Cumulative Growth of [param uid] (0 when unknown).
static func growth_of(uid) -> int:
	return int(_record(String(uid), false).get("growth", 0))


## Add [param n] Growth to [param uid] (creating the implicit record) and return the new total.
## A non-positive n is a no-op. Does not save.
static func add_growth(uid, n: int) -> int:
	var rec: Dictionary = _record(String(uid), true)
	if rec.is_empty():
		return 0
	if n > 0:
		rec["growth"] = int(rec.get("growth", 0)) + n
	return int(rec.get("growth", 0))


## The Growth [param char_id]'s NEXT evolution asks for (smallest goal over its edges), or 0
## when it has no Growth-based evolution. What the growth pips count towards.
static func next_growth_goal(char_id) -> int:
	var goal: int = 0
	for e in EvolutionLibrary.edges_from(char_id):
		var g: int = e.growth_goal()
		if g > 0 and (goal == 0 or g < goal):
			goal = g
	return goal


# --- Forms ------------------------------------------------------------------

## The form [param uid] currently is -- what a STORY party spawns. The line root for an
## implicit member.
static func form_of(uid) -> StringName:
	return StringName(String(_record(String(uid), false).get("form", "")))


## The evolution history of [param uid]: [{edge, at}], oldest first.
static func evolution_history(uid) -> Array:
	return (_record(String(uid), false).get("evolved", []) as Array).duplicate(true)


## True when [param char_id] may be fielded in OPEN modes: a base form always, an evolved form
## once some member has evolved into it.
static func is_form_unlocked(char_id) -> bool:
	if not EvolutionLibrary.is_evolved_form(char_id):
		return true
	ensure_loaded()
	return (_data["unlocked_forms"] as Array).has(String(char_id))


## Every evolved form unlocked so far, sorted.
static func unlocked_forms() -> Array[String]:
	ensure_loaded()
	var out: Array[String] = []
	for f in (_data["unlocked_forms"] as Array):
		out.append(String(f))
	out.sort()
	return out


# --- Evolution --------------------------------------------------------------

## The trigger context for [param uid] (see [EvolutionTrigger]) merged with
## [param extra] (catalysts, story flags...). Built here, outside any battle.
static func context_for(uid, extra: Dictionary = {}) -> Dictionary:
	var rec: Dictionary = _record(String(uid), false)
	return record_context(rec, String(uid), open_extra(rec, extra))


## OPEN-MODE context extras for the record [param rec]: what its current form wears in
## ItemInventory ([HeldItemTrigger]), unless [param extra] already says. No story keys -- story
## requirements are unmet (or skipped) here ([EvolutionTrigger]).
static func open_extra(rec: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var out: Dictionary = extra.duplicate()
	if not out.has("held_item"):
		var form: String = String(rec.get("form", ""))
		out["held_item"] = ItemInventory.equipped_item(form) if not form.is_empty() else ""
	return out


## The evolutions [param uid] can take RIGHT NOW from its current form, in edge-id order.
static func available_evolutions(uid, extra: Dictionary = {}) -> Array[EvolutionResource]:
	var key: String = String(uid)
	if key.is_empty():
		var none: Array[EvolutionResource] = []
		return none
	var rec: Dictionary = _record(key, false)
	return record_evolutions(rec, key, open_extra(rec, extra))


## The CHECKLIST of [param uid]'s next forms (open modes): one entry per edge leaving its current
## form, {edge, available, rows} (rows: [method EvolutionResource.requirement_rows]).
static func checklists(uid, extra: Dictionary = {}) -> Array[Dictionary]:
	var rec: Dictionary = _record(String(uid), false)
	return record_checklists(rec, String(uid), open_extra(rec, extra))


## Of [param uids], the ones with at least one evolution available, in the order given. With
## [param respect_hold] a member on HOLD is left out (the automatic-prompt question).
static func pending_evolutions(uids: Array, extra: Dictionary = {}, respect_hold: bool = false) -> Array[String]:
	var out: Array[String] = []
	for uid in uids:
		if respect_hold and is_held(uid):
			continue
		if not available_evolutions(uid, extra).is_empty():
			out.append(String(uid))
	return out


## Evolve [param uid] along [param edge]: re-checks availability, sets the member's form,
## records the step, unlocks the new form, carries the equipped UNIT item over
## ([member EvolutionResource.carry_item]) and SAVES the ledger (and the inventory when an
## item moved). Returns {success, reason, item_moved, from, to}; refusals ("no_edge",
## "wrong_form", "not_available", "unknown_form") never touch the store or the engine log.
static func evolve(uid, edge: EvolutionResource, extra: Dictionary = {}) -> Dictionary:
	return _evolve(String(uid), edge, extra, false)


## STORY / scripted: evolve [param uid] along the edge with id [param edge_id]. With
## [param scripted] the edge's triggers are skipped (a shrine awakening, a story beat) -- the
## member must still BE the edge's from-form.
static func evolve_member(uid, edge_id, scripted: bool = false) -> Dictionary:
	return _evolve(String(uid), EvolutionLibrary.get_edge(edge_id), {}, scripted)


static func _evolve(uid: String, edge: EvolutionResource, extra: Dictionary, scripted: bool) -> Dictionary:
	var rec: Dictionary = _record(uid, false)
	var result: Dictionary = _check_evolve(rec, uid, edge, open_extra(rec, extra), scripted)
	if not String(result["reason"]).is_empty():
		return result
	_commit_step(_record(uid, true), edge)
	var moved: bool = false
	if edge.carry_item:
		moved = ItemInventory.rekey_character(edge.from_id, edge.to_id)
	save()
	if moved:
		ItemInventory.save()
	result["success"] = true
	result["item_moved"] = moved
	return result


# --- Record-level API (members held OUTSIDE this store) ----------------------
#
# A member record is { line, form, growth, evolved, nickname }. Open-mode members live in THIS
# store; a STORY party keeps its members' records inside the story save slot instead
# (StoryPartyMember is the story-scoped view of one -- docs/STORY_MODE.md "Party records"), so
# three journeys never share one Barkling and "Try Again" rewinds growth with the rest of the
# journey. These functions run the SAME rules on a record the caller holds: one evolve path
# for both.

## A fresh member record for an individual that is [param character_id] (its line = the root).
static func new_record(character_id) -> Dictionary:
	var cid: String = String(character_id)
	var rec: Dictionary = _default_record(member_for_character(cid))
	rec["form"] = cid
	return rec


## The trigger context of the record [param rec] (member [param uid]) merged with [param extra].
static func record_context(rec: Dictionary, uid: String, extra: Dictionary = {}) -> Dictionary:
	var ctx: Dictionary = {
		"uid": uid,
		"form": StringName(String(rec.get("form", ""))),
		"growth": int(rec.get("growth", 0)),
		"feats": normalize_feats(rec.get("feats", {})),
	}
	for k in extra.keys():
		ctx[k] = extra[k]
	return ctx


## The evolutions the record [param rec] can take RIGHT NOW, in edge-id order.
static func record_evolutions(rec: Dictionary, uid: String, extra: Dictionary = {}) -> Array[EvolutionResource]:
	var out: Array[EvolutionResource] = []
	if rec.is_empty():
		return out
	var ctx: Dictionary = record_context(rec, uid, extra)
	for e in EvolutionLibrary.edges_from(ctx["form"]):
		if e.is_available(ctx):
			out.append(e)
	return out


## The checklist of the record [param rec]: {edge, available, rows} per edge leaving its form.
static func record_checklists(rec: Dictionary, uid: String, extra: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if rec.is_empty():
		return out
	var ctx: Dictionary = record_context(rec, uid, extra)
	for e in EvolutionLibrary.edges_from(ctx["form"]):
		out.append({ "edge": e, "available": e.is_available(ctx), "rows": e.requirement_rows(ctx) })
	return out


## Evolve the caller-held record [param rec] IN PLACE along [param edge] (the same checks and
## history as [method evolve]). The new form is also UNLOCKED in this store for open modes
## (owner decision 2) and the store saved. No ItemInventory re-key: a record held outside the
## store equips from its owner's bag (the story's member item). Returns
## {success, reason, item_moved, from, to}; a refusal leaves [param rec] untouched.
static func evolve_record(rec: Dictionary, uid: String, edge: EvolutionResource,
		extra: Dictionary = {}, scripted: bool = false) -> Dictionary:
	var result: Dictionary = _check_evolve(rec, uid, edge, extra, scripted)
	if not String(result["reason"]).is_empty():
		return result
	_commit_step(rec, edge)
	save()
	result["success"] = true
	return result


static func _check_evolve(rec: Dictionary, uid: String, edge: EvolutionResource, extra: Dictionary,
		scripted: bool) -> Dictionary:
	var result: Dictionary = { "success": false, "reason": "", "item_moved": false, "from": "", "to": "" }
	if edge == null or uid.is_empty() or rec.is_empty():
		result["reason"] = "no_edge"
		return result
	if StringName(String(rec.get("form", ""))) != edge.from_id:
		result["reason"] = "wrong_form"
		return result
	if not scripted and not edge.is_available(record_context(rec, uid, extra)):
		result["reason"] = "not_available"
		return result
	if CharacterLibrary.get_character(edge.to_id) == null:
		result["reason"] = "unknown_form"
		return result
	result["from"] = String(edge.from_id)
	result["to"] = String(edge.to_id)
	return result


## Write one evolution step into [param rec] and unlock the new form (no save).
static func _commit_step(rec: Dictionary, edge: EvolutionResource) -> void:
	rec["form"] = String(edge.to_id)
	if not (rec.get("evolved", null) is Array):
		rec["evolved"] = []
	(rec["evolved"] as Array).append({
		"edge": String(edge.id),
		"at": Time.get_datetime_string_from_system(),
	})
	ensure_loaded()
	_unlock(String(edge.to_id))


# --- internals --------------------------------------------------------------

static func _blank() -> Dictionary:
	return { "version": VERSION, "members": {}, "unlocked_forms": [] }


static func _default_record(line: String) -> Dictionary:
	return { "line": line, "form": line, "growth": 0, "evolved": [], "nickname": "", "hold": false,
		"feats": blank_feats() }


## The line a uid belongs to: the part before "#", resolved to its root.
static func _line_of_uid(uid: String) -> String:
	var base: String = uid.get_slice(MEMBER_SEPARATOR, 0)
	return member_for_character(base) if not base.is_empty() else ""


## The live record for [param uid]. With [param create] a missing one is stored (implicit
## member); without, a detached default is returned so reads never write. {} for "".
static func _record(uid: String, create: bool) -> Dictionary:
	if uid.is_empty():
		return {}
	ensure_loaded()
	var members_dict: Dictionary = _data["members"]
	if members_dict.has(uid):
		return members_dict[uid]
	var rec: Dictionary = _default_record(_line_of_uid(uid))
	if create:
		members_dict[uid] = rec
	return rec


static func _unlock(char_id: String) -> void:
	var forms: Array = _data["unlocked_forms"]
	if EvolutionLibrary.is_evolved_form(char_id) and not forms.has(char_id):
		forms.append(char_id)


## Coerce a parsed file into the exact shape the accessors assume. Repairs rather than
## rejects: wrong-typed fields fall back to defaults, members keep what is readable.
static func _normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = _blank()
	var members_raw: Variant = raw.get("members", {})
	if members_raw is Dictionary:
		for key in (members_raw as Dictionary).keys():
			var uid: String = String(key)
			var src: Variant = members_raw[key]
			if uid.is_empty() or not (src is Dictionary):
				continue
			var rec: Dictionary = _default_record(_line_of_uid(uid))
			if String(src.get("line", "")) != "":
				rec["line"] = String(src["line"])
			if String(src.get("form", "")) != "":
				rec["form"] = String(src["form"])
			rec["growth"] = maxi(0, int(src.get("growth", 0)))
			rec["nickname"] = String(src.get("nickname", ""))
			rec["hold"] = bool(src.get("hold", false))
			rec["feats"] = normalize_feats(src.get("feats", {}))
			var evolved_raw: Variant = src.get("evolved", [])
			if evolved_raw is Array:
				for step in evolved_raw:
					if step is Dictionary:
						rec["evolved"].append({ "edge": String(step.get("edge", "")), "at": String(step.get("at", "")) })
			out["members"][uid] = rec
	var forms_raw: Variant = raw.get("unlocked_forms", [])
	if forms_raw is Array:
		for f in forms_raw:
			var fid: String = String(f)
			if not fid.is_empty() and not (out["unlocked_forms"] as Array).has(fid):
				out["unlocked_forms"].append(fid)
	return out
