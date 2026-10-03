class_name StoryContentIndex
extends RefCounted

## A READ-ONLY INDEX of the shipped story content (every area under
## [constant OverworldAreaResource.AREAS_DIR]) for the dialogue tools: which NPCs live in which
## area, every story FLAG the content sets or reads (so a dialogue condition naming a flag nothing
## knows is caught), and every line of SCRIPTED dialogue (cutscenes: on_enter, on_interact,
## on_step, trainer / warp scenes) with the condition that gates it.
##
## Used by [method DialogueBank.validate] (game + GUT) and by the Dialogue editor
## (addons/dialogue_editor). IMPORTANT: inside the EDITOR the area resources load with
## PLACEHOLDER script instances (the overworld scripts are not @tool) -- their exported
## properties are readable but their METHODS cannot be called. So this class only ever READS
## PROPERTIES of loaded content (and calls static helpers); never a method on an entity / command.

## Flags whose names are built at runtime from ids (spar cooldowns, tournament bouts): any flag
## under these prefixes is accepted by [method is_known_flag].
const DYNAMIC_PREFIXES: Array[String] = ["sparred.", "arena.", "trainer.", "wayshrine."]

var areas: Dictionary = {}            # area_id -> OverworldAreaResource
var area_ids: Array[String] = []      # sorted
## flag -> Array[String] of "where" (who sets / reads it).
var flags: Dictionary = {}
var _scripts: Dictionary = {}         # area_id -> Array[Dictionary] (see [method scripts])


## Index every shipped area (or just [param only]).
static func build(only: Array = []) -> StoryContentIndex:
	var idx := StoryContentIndex.new()
	var ids: Array[String] = []
	if only.is_empty():
		ids = shipped_area_ids()
	else:
		for a in only:
			ids.append(String(a))
	for aid in ids:
		var path: String = OverworldAreaResource.path_for(aid)
		if not ResourceLoader.exists(path):
			continue
		var a: Resource = load(path)
		if a == null:
			continue
		idx.areas[aid] = a
		idx.area_ids.append(aid)
	idx.area_ids.sort()
	idx._index_flags()
	return idx


## Every area directory holding an area.tres, sorted.
static func shipped_area_ids() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(OverworldAreaResource.AREAS_DIR)
	if dir == null:
		return out
	for d in dir.get_directories():
		if ResourceLoader.exists(OverworldAreaResource.path_for(d)):
			out.append(d)
	out.sort()
	return out


func has_area(area_id: String) -> bool:
	return areas.has(area_id)


func area(area_id: String) -> Resource:
	return areas.get(area_id, null)


func area_name(area_id: String) -> String:
	var a: Resource = area(area_id)
	if a == null:
		return area_id.capitalize()
	var n: String = String(a.get("display_name"))
	return n if not n.is_empty() else area_id.capitalize()


## The area's entities (typed, nulls dropped) -- read straight off the exported array.
func entities(area_id: String) -> Array[Resource]:
	var out: Array[Resource] = []
	var a: Resource = area(area_id)
	if a == null:
		return out
	for e in a.get("entities"):
		if e is OverworldEntity:
			out.append(e)
	return out


## The people of [param area_id]: every [NpcEntity] (merchants and trainers included), in file order.
func npcs(area_id: String) -> Array[Resource]:
	var out: Array[Resource] = []
	for e in entities(area_id):
		if e is NpcEntity:
			out.append(e)
	return out


func npc(area_id: String, npc_id: String) -> Resource:
	for e in npcs(area_id):
		if String(e.get("id")) == npc_id:
			return e
	return null


func has_npc(area_id: String, npc_id: String) -> bool:
	return npc(area_id, npc_id) != null


func npc_ids(area_id: String) -> Array[String]:
	var out: Array[String] = []
	for e in npcs(area_id):
		out.append(String(e.get("id")))
	return out


## The name an NPC shows on its plate.
static func npc_label(e: Resource) -> String:
	if e == null:
		return ""
	var sn: String = String(e.get("speaker_name"))
	if not sn.is_empty():
		return sn
	var dn: String = String(e.get("display_name"))
	return dn if not dn.is_empty() else String(e.get("id")).capitalize()


## "npc" / "shop" / "trainer" (the entity's kind, read from its class -- no method call).
static func npc_kind(e: Resource) -> String:
	if e is TrainerEntity:
		return "trainer"
	if e is ShopEntity:
		return "shop"
	return "npc"


## True when the NPC has SCRIPTED behaviour beyond plain talk (on_interact commands, a shop, a
## battle) -- the editor marks those so the owner knows a ceremony / offer still runs after the line.
static func has_script(e: Resource) -> bool:
	if e == null:
		return false
	if not (e.get("on_interact") as Array).is_empty():
		return true
	return e is ShopEntity or e is TrainerEntity


# =====================================================================================
#  Flags
# =====================================================================================

func is_known_flag(flag: String) -> bool:
	if flags.has(flag):
		return true
	for p in DYNAMIC_PREFIXES:
		if flag.begins_with(p):
			return true
	return false


## Every known flag name, sorted.
func flag_names() -> Array[String]:
	var out: Array[String] = []
	for k in flags:
		out.append(String(k))
	out.sort()
	return out


func _note(flag: String, where: String) -> void:
	if flag.strip_edges().is_empty():
		return
	if not flags.has(flag):
		flags[flag] = []
	if not (flags[flag] as Array).has(where):
		(flags[flag] as Array).append(where)


func _note_condition(cond: String, where: String) -> void:
	for f in DialogueBank.flags_in(cond):
		_note(f, where + " (reads)")


func _index_flags() -> void:
	# The quest log's flags (quests.json is the phase timeline too).
	for q in QuestLog.definitions():
		var qid: String = "quest " + String(q.get("id", ""))
		_note(String(q.get("start_flag", "")), qid)
		_note(String(q.get("complete_flag", "")), qid)
		for s in q.get("steps", []):
			if s is Dictionary:
				_note(String(s.get("flag", "")), qid)
	# The world map's closed places open with world.* flags.
	var atlas: Resource = load(WorldAtlas.PATH) if ResourceLoader.exists(WorldAtlas.PATH) else null
	if atlas != null:
		for l in atlas.get("locations"):
			if l != null:
				_note(String(l.get("open_flag")), "world map")
	for aid in area_ids:
		var a: Resource = areas[aid]
		_walk(a.get("on_enter"), aid + "/on_enter", aid)
		for e in entities(aid):
			var eid: String = String(e.get("id"))
			var where: String = "%s/%s" % [aid, eid]
			_note_condition(String(e.get("visible_if")), where)
			for f in _auto_flags(aid, e):
				_note(f, where)
			_walk(e.get("on_interact"), where, aid)
			_walk(e.get("on_step"), where, aid)
			if e is WarpEntity:
				_note_condition(String(e.get("requires")), where)
			if e is TrainerEntity:
				_note_spec(e.get("battle"), where)


## The flag an entity kind sets by itself (a trainer beaten, a chest opened, a once-trigger fired,
## a Wayshrine lit) -- the same formats as the kinds' auto_flag(), without calling them.
func _auto_flags(aid: String, e: Resource) -> Array[String]:
	var eid: String = String(e.get("id"))
	if e is TrainerEntity:
		return [TrainerEntity.defeated_flag(aid, eid)]
	if e is ChestEntity:
		return [ChestEntity.opened_flag(aid, eid)]
	if e is TriggerZone and bool(e.get("once")):
		return ["%s.%s.fired" % [aid, eid]]
	if e is WayshrineEntity:
		return ["wayshrine.%s.%s.lit" % [aid, eid]]
	return []


func _note_spec(spec: Resource, where: String) -> void:
	if spec == null:
		return
	for f in spec.get("reward_flags"):
		_note(String(f), where)
	_note(String(spec.get("scale_flag")), where)


## Walk a command list (nested If / Choice branches included), noting every flag set or read.
func _walk(commands, where: String, aid: String) -> void:
	if not (commands is Array):
		return
	for c in commands:
		if c == null:
			continue
		if c is SetFlagCommand or c is IncFlagCommand:
			_note(String(c.get("key")), where)
		elif c is JoinPartyCommand or c is BefriendPromptCommand:
			_note(String(c.get("flag_on_join")), where)
		elif c is StartBattleCommand or c is StartDuelCommand:
			_note_spec(c.get("spec"), where)
		elif c is RunTournamentCommand:
			var t: Resource = c.get("tournament")
			if t != null:
				var tid: String = String(t.get("id"))
				for suffix in ["run", "round", "wins", "champion"]:
					_note("arena.%s.%s" % [tid, suffix], where)
		elif c is IfCommand:
			_note_condition(String(c.get("condition")), where)
			_walk(c.get("then_commands"), where, aid)
			_walk(c.get("else_commands"), where, aid)
		elif c is ChoiceCommand:
			for o in c.get("options"):
				if o != null:
					_note_condition(String(o.get("condition")), where)
					_walk(o.get("commands"), where, aid)


# =====================================================================================
#  Scripted dialogue (the editor's read-only "Cutscenes & scripts" view)
# =====================================================================================

## Every scripted conversation of [param area_id], in content order: [{owner, owner_name, source,
## gate, lines: [{cond, speaker, text, marker}]}]. [code]source[/code] says where it hangs
## ("on_enter", "on_interact", "on_step", "dialogue", "pre_scene", "defeated_scene",
## "locked_scene"); [code]gate[/code] the owner's visible_if (+ a warp's requires); each line's
## [code]cond[/code] the If / choice branch it sits in ("" = unconditional); a marker line
## ([code]marker[/code] true) names what else the script does ("sets opening.attack", "battle").
func scripts(area_id: String) -> Array:
	if _scripts.has(area_id):
		return _scripts[area_id]
	var out: Array = []
	var a: Resource = area(area_id)
	if a == null:
		return out
	_add_script(out, "(area)", "Area arrival", "on_enter", "", a.get("on_enter"))
	for e in entities(area_id):
		var eid: String = String(e.get("id"))
		var nm: String = npc_label(e) if e is NpcEntity else String(e.get("display_name"))
		var gate: String = String(e.get("visible_if"))
		if e is WarpEntity and not String(e.get("requires")).is_empty():
			gate = ("%s · requires %s" % [gate, e.get("requires")]) if not gate.is_empty() else "requires %s" % e.get("requires")
		if e is NpcEntity and e.get("dialogue") != null:
			_add_scene(out, eid, nm, "dialogue (.tres fallback)", gate, e.get("dialogue"))
		if e is TrainerEntity:
			_add_scene(out, eid, nm, "pre_scene (challenge)", gate, e.get("pre_scene"))
			_add_scene(out, eid, nm, "defeated_scene", gate, e.get("defeated_scene"))
		if e is WarpEntity:
			_add_scene(out, eid, nm if not nm.is_empty() else eid, "locked_scene", gate, e.get("locked_scene"))
		_add_script(out, eid, nm, "on_interact", gate, e.get("on_interact"))
		_add_script(out, eid, nm, "on_step", gate, e.get("on_step"))
	_scripts[area_id] = out
	return out


func _add_scene(out: Array, owner: String, owner_name: String, source: String, gate: String, scene: Resource) -> void:
	if scene == null:
		return
	var lines: Array = []
	for b in scene.get("beats"):
		if b != null:
			lines.append(_line_row(b, ""))
	if not lines.is_empty():
		out.append({"owner": owner, "owner_name": owner_name, "source": source, "gate": gate, "lines": lines})


func _add_script(out: Array, owner: String, owner_name: String, source: String, gate: String, commands) -> void:
	if not (commands is Array) or commands.is_empty():
		return
	var lines: Array = []
	_collect(commands, "", lines)
	var has_text: bool = false
	for l in lines:
		if not bool(l["marker"]):
			has_text = true
	if has_text:
		out.append({"owner": owner, "owner_name": owner_name, "source": source, "gate": gate, "lines": lines})


static func _line_row(b: Resource, cond: String) -> Dictionary:
	var sid: String = String(b.get("speaker_id"))
	var sname: String = String(b.get("speaker_name"))
	var who: String = sname
	if who.is_empty():
		match sid:
			"self":
				who = "(self)"
			"hero":
				who = "(hero)"
			"narrator", "":
				who = "(narration)"
			_:
				who = sid
	return {"cond": cond, "speaker": who, "text": String(b.get("text")), "marker": false}


static func _marker(cond: String, text: String) -> Dictionary:
	return {"cond": cond, "speaker": "", "text": text, "marker": true}


static func _and(a: String, b: String) -> String:
	if a.is_empty():
		return b
	if b.is_empty():
		return a
	return "%s and %s" % [a, b]


func _collect(commands, cond: String, lines: Array) -> void:
	if not (commands is Array):
		return
	for c in commands:
		if c == null:
			continue
		if c is SayCommand:
			var scene: Resource = c.get("scene")
			if scene != null:
				for b in scene.get("beats"):
					if b != null:
						lines.append(_line_row(b, cond))
			for b in c.get("beats"):
				if b != null:
					lines.append(_line_row(b, cond))
		elif c is IfCommand:
			var ic: String = String(c.get("condition"))
			_collect(c.get("then_commands"), _and(cond, ic), lines)
			_collect(c.get("else_commands"), _and(cond, "not (%s)" % ic), lines)
		elif c is ChoiceCommand:
			var p: Resource = c.get("prompt")
			if p != null:
				lines.append(_line_row(p, cond))
			for o in c.get("options"):
				if o != null:
					var oc: String = _and(cond, "choice \"%s\"" % String(o.get("label")))
					_collect(o.get("commands"), oc, lines)
		elif c is SetFlagCommand or c is IncFlagCommand:
			lines.append(_marker(cond, "sets %s" % String(c.get("key"))))
		elif c is JoinPartyCommand:
			lines.append(_marker(cond, "%s joins the party" % String(c.get("character_id"))))
		elif c is StartBattleCommand or c is StartDuelCommand:
			var spec: Resource = c.get("spec")
			var foe: String = String(spec.get("opponent_name")) if spec != null else "?"
			lines.append(_marker(cond, "battle vs %s" % foe))
		elif c is WarpCommand:
			lines.append(_marker(cond, "warps to %s" % String(c.get("area_id"))))
		elif c is OpenShopCommand:
			lines.append(_marker(cond, "opens the shop"))
		elif c is RunTournamentCommand:
			lines.append(_marker(cond, "runs the tournament ladder"))
