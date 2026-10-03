@tool
extends Control

# Dialogue Editor panel - the main-screen UI of addons/dialogue_editor (built in code, like the
# other Conquest tools). It edits game/overworld/content/dialogue.json, the DialogueBank the game
# reads at runtime, so a saved change shows on the next talk with no rebuild:
#
#   LEFT   Town / Area -> NPC tree (search box; "only NPCs present in the phase" filter).
#   TOP    the STORY PHASE (derived from the main quests in quests.json -- StoryPhases) and some
#          story time (rests / steps since the flags were set); every view simulates that.
#   TABS   Lines      - the NPC's variants in order: condition (shown readably), the phases each
#                       variant plays in, the line editor (speaker, side, text), add / remove /
#                       reorder / duplicate; the variant that plays in the simulated state glows.
#          Town now   - tick flags and see what EVERY NPC of a town would say right now.
#          Cutscenes  - the area's scripted dialogue (ceremony, raid, ...) READ-ONLY, each line
#                       labelled with the condition that gates it (it lives in the builder).
#          Search     - every line (bank + cutscenes) containing the search text.
#          Missing    - NPCs with no lines, NPCs silent in a phase, TODO / placeholder lines.
#          Issues     - the validator (run on every save).
#   SAVE   writes stable, pretty JSON (DialogueBank.to_json: sorted keys, tabs).
#
# The content is read through StoryContentIndex, which only reads PROPERTIES of the loaded area
# resources: in the editor the overworld scripts are not @tool, so their methods cannot be called.

const AREA_ORDER: Array[String] = ["oakvale", "mossway", "river_crossing", "crownhaven", "oakvale_ruins",
	"sparse_forest", "woodland_town"]
const COLOR_PLAYS := Color(0.42, 0.82, 0.5)
const COLOR_DIM := Color(0.6, 0.6, 0.64)
const COLOR_BAD := Color(0.95, 0.45, 0.4)
const COLOR_WARN := Color(0.95, 0.78, 0.4)
const TAB_LINES := 0
const TAB_TOWN := 1
const TAB_CUTSCENES := 2
const TAB_SEARCH := 3
const TAB_MISSING := 4
const TAB_ISSUES := 5

var bank_path: String = DialogueBank.DATA_PATH

var _data: Dictionary = {}
var _index: StoryContentIndex = null
var _phases: Array[Dictionary] = []
var _phase: int = 0
var _ticked: Dictionary = {}          # the simulated flag set: flag -> true
var _rests: int = 0
var _steps: int = 0
var _sel_area: String = ""
var _sel_npc: String = ""
var _dirty: bool = false
var _loaded: bool = false
var _issues: Array[String] = []

# --- UI ---
var _status: Label
var _phase_opt: OptionButton
var _rests_spin: SpinBox
var _steps_spin: SpinBox
var _filter_check: CheckBox
var _search: LineEdit
var _tree: Tree
var _tabs: TabContainer
var _lines_box: VBoxContainer
var _town_area_opt: OptionButton
var _flags_tree: Tree
var _town_out: RichTextLabel
var _cut_out: RichTextLabel
var _search_list: ItemList
var _missing_out: RichTextLabel
var _issues_out: RichTextLabel
var _flag_pick: Array[OptionButton] = []


func _init() -> void:
	name = "DialogueEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_create_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and not _loaded:
		load_bank()


# =====================================================================================
#  Data (public: the GUT smoke test drives these)
# =====================================================================================

## (Re)load the bank file and the story content. {ok, error}.
func load_bank(path: String = "") -> Dictionary:
	if not path.is_empty():
		bank_path = path
	_loaded = true
	var text: String = FileAccess.get_file_as_string(bank_path) if FileAccess.file_exists(bank_path) else ""
	var r: Dictionary = DialogueBank.parse_text(text) if not text.is_empty() else {"ok": true, "data": DialogueBank.empty(), "error": ""}
	_data = r["data"]
	if not bool(r["ok"]):
		_set_status("Could not read %s: %s -- starting from an empty bank." % [bank_path, r["error"]], COLOR_BAD)
	_index = StoryContentIndex.build()
	QuestLog.set_definitions(null)
	_phases = StoryPhases.phases()
	_phase = clampi(_phase, 0, maxi(0, _phases.size() - 1))
	_reset_ticks_to_phase()
	_dirty = false
	_fill_phase_options()
	_fill_town_areas()
	_refresh_all()
	if bool(r["ok"]):
		_set_status("Loaded %s: %d NPC entries." % [bank_path, entry_count()], COLOR_DIM)
	return {"ok": bool(r["ok"]), "error": String(r["error"])}


## Validate and write the bank. {ok, error, issues}.
func save_bank(path: String = "") -> Dictionary:
	var target: String = path if not path.is_empty() else bank_path
	_issues = DialogueBank.validate(_data, _index)
	var r: Dictionary = DialogueBank.save(_data, target)
	if bool(r["ok"]):
		_dirty = false
		if target == DialogueBank.path():
			DialogueBank.set_data(_data)
		_set_status("Saved %s -- %s." % [target, "no issues" if _issues.is_empty() else "%d issue(s), see Issues" % _issues.size()],
			COLOR_PLAYS if _issues.is_empty() else COLOR_WARN)
	else:
		_set_status(String(r["error"]), COLOR_BAD)
	_refresh_issues()
	if not _issues.is_empty() and _tabs != null:
		_tabs.current_tab = TAB_ISSUES
	return {"ok": bool(r["ok"]), "error": String(r["error"]), "issues": _issues.duplicate()}


func data() -> Dictionary:
	return _data


func is_dirty() -> bool:
	return _dirty


func entry_count() -> int:
	var n: int = 0
	for aid in _data.get("areas", {}):
		n += (_data["areas"][aid] as Dictionary).size()
	return n


func entry(area_id: String, npc_id: String) -> Dictionary:
	return DialogueBank.entry(area_id, npc_id, _data) if not _data.is_empty() else {}


## The entry of the selected NPC, creating it (one TODO line) when [param create].
func selected_entry(create: bool = false) -> Dictionary:
	if _sel_area.is_empty() or _sel_npc.is_empty():
		return {}
	var areas: Dictionary = _data["areas"]
	if not areas.has(_sel_area):
		if not create:
			return {}
		areas[_sel_area] = {}
	var npcs: Dictionary = areas[_sel_area]
	if not npcs.has(_sel_npc):
		if not create:
			return {}
		npcs[_sel_npc] = {"variants": [_new_variant("")]}
		_mark_dirty()
	return npcs[_sel_npc]


func select_npc(area_id: String, npc_id: String) -> void:
	_sel_area = area_id
	_sel_npc = npc_id
	_render_lines()
	_render_cutscenes()
	if _town_area_opt != null:
		for i in range(_town_area_opt.item_count):
			if String(_town_area_opt.get_item_metadata(i)) == area_id:
				_town_area_opt.select(i)
		_render_town()


func set_phase(i: int) -> void:
	_phase = clampi(i, 0, maxi(0, _phases.size() - 1))
	if _phase_opt != null and _phase < _phase_opt.item_count:
		_phase_opt.select(_phase)
	_reset_ticks_to_phase()
	_refresh_all()


func set_time(rests: int, steps: int) -> void:
	_rests = maxi(0, rests)
	_steps = maxi(0, steps)
	_refresh_all()


func set_flag_ticked(flag: String, on: bool) -> void:
	if on:
		_ticked[flag] = true
	else:
		_ticked.erase(flag)
	_render_lines()
	_render_town()


## The state every view simulates: the ticked flags (the phase's milestones unless changed),
## stamped at the start of time, then [member _rests] rests and [member _steps] steps.
func sim_state() -> StoryState:
	return StoryPhases.state_for({"flags": _ticked.keys()}, [], [], _rests, _steps)


func phases() -> Array[Dictionary]:
	return _phases


func add_entry() -> void:
	selected_entry(true)
	_refresh_tree()
	_render_lines()


func delete_entry() -> void:
	var areas: Dictionary = _data["areas"]
	if areas.has(_sel_area) and (areas[_sel_area] as Dictionary).has(_sel_npc):
		(areas[_sel_area] as Dictionary).erase(_sel_npc)
		if (areas[_sel_area] as Dictionary).is_empty():
			areas.erase(_sel_area)
		_mark_dirty()
	_refresh_tree()
	_render_lines()


func add_variant(condition: String = "", at_top: bool = true) -> void:
	var e: Dictionary = selected_entry(true)
	var v: Dictionary = _new_variant(condition)
	if at_top:
		(e["variants"] as Array).insert(0, v)
	else:
		(e["variants"] as Array).append(v)
	_mark_dirty()
	_render_lines()
	_refresh_tree()


func remove_variant(vi: int) -> void:
	var vs: Array = selected_entry().get("variants", [])
	if vi >= 0 and vi < vs.size():
		vs.remove_at(vi)
		_mark_dirty()
	_render_lines()
	_refresh_tree()


func duplicate_variant(vi: int) -> void:
	var vs: Array = selected_entry().get("variants", [])
	if vi >= 0 and vi < vs.size():
		vs.insert(vi + 1, (vs[vi] as Dictionary).duplicate(true))
		_mark_dirty()
	_render_lines()


func move_variant(vi: int, delta: int) -> void:
	var vs: Array = selected_entry().get("variants", [])
	var to: int = vi + delta
	if vi < 0 or vi >= vs.size() or to < 0 or to >= vs.size():
		return
	var v = vs[vi]
	vs.remove_at(vi)
	vs.insert(to, v)
	_mark_dirty()
	_render_lines()


func set_variant_field(vi: int, key: String, value: String) -> void:
	var vs: Array = selected_entry().get("variants", [])
	if vi < 0 or vi >= vs.size():
		return
	if key == "label" and value.strip_edges().is_empty():
		(vs[vi] as Dictionary).erase("label")
	else:
		vs[vi][key] = value
	_mark_dirty()


func add_line(vi: int, speaker: String = DialogueBank.SPEAKER_SELF, text: String = "") -> void:
	var vs: Array = selected_entry().get("variants", [])
	if vi < 0 or vi >= vs.size():
		return
	(vs[vi]["lines"] as Array).append({"speaker": speaker, "text": text})
	_mark_dirty()
	_render_lines()


func remove_line(vi: int, li: int) -> void:
	var lines: Array = _lines_of(vi)
	if li >= 0 and li < lines.size():
		lines.remove_at(li)
		_mark_dirty()
	_render_lines()


func move_line(vi: int, li: int, delta: int) -> void:
	var lines: Array = _lines_of(vi)
	var to: int = li + delta
	if li < 0 or li >= lines.size() or to < 0 or to >= lines.size():
		return
	var l = lines[li]
	lines.remove_at(li)
	lines.insert(to, l)
	_mark_dirty()
	_render_lines()


func set_line_field(vi: int, li: int, key: String, value: String) -> void:
	var lines: Array = _lines_of(vi)
	if li < 0 or li >= lines.size():
		return
	if (key == "side" or key == "name") and value.is_empty():
		(lines[li] as Dictionary).erase(key)
	else:
		lines[li][key] = value
	_mark_dirty()


func _lines_of(vi: int) -> Array:
	var vs: Array = selected_entry().get("variants", [])
	if vi < 0 or vi >= vs.size():
		return []
	return vs[vi]["lines"]


static func _new_variant(condition: String) -> Dictionary:
	return {"if": condition, "lines": [{"speaker": DialogueBank.SPEAKER_SELF, "text": "TODO: write this line"}]}


func _mark_dirty() -> void:
	_dirty = true
	_set_status("Unsaved changes.", COLOR_WARN)


## What every NPC of [param area_id] says in [method sim_state]: [{npc, name, present, source
## ("bank" / "tres" / "none"), variant (index or -1), label, cond, lines: [{speaker, text}], scripted}].
func simulate(area_id: String) -> Array:
	var out: Array = []
	if _index == null:
		return out
	var st: StoryState = sim_state()
	for e in _index.npcs(area_id):
		var nid: String = String(e.get("id"))
		var row: Dictionary = {"npc": nid, "name": StoryContentIndex.npc_label(e),
			"present": ConditionContext.evaluate(String(e.get("visible_if")), st),
			"source": "none", "variant": -1, "label": "", "cond": "", "lines": [],
			"scripted": StoryContentIndex.has_script(e), "kind": StoryContentIndex.npc_kind(e)}
		var en: Dictionary = entry(area_id, nid)
		if not en.is_empty():
			row["source"] = "bank"
			var i: int = DialogueBank.pick(en, st)
			row["variant"] = i
			if i >= 0:
				var v: Dictionary = en["variants"][i]
				row["label"] = String(v.get("label", ""))
				row["cond"] = String(v.get("if", ""))
				for l in v.get("lines", []):
					row["lines"].append({"speaker": String(l.get("speaker", "self")), "text": String(l.get("text", ""))})
		elif e.get("dialogue") != null:
			row["source"] = "tres"
			for b in e.get("dialogue").get("beats"):
				if b != null:
					row["lines"].append({"speaker": String(b.get("speaker_id")), "text": String(b.get("text"))})
		out.append(row)
	return out


## Every line containing [param query] (case-insensitive): [{kind ("bank" / "cutscene"), area,
## npc, variant, text, where}].
func search(query: String) -> Array:
	var out: Array = []
	var q: String = query.strip_edges().to_lower()
	if q.is_empty() or _index == null:
		return out
	for aid in _sorted_area_ids():
		var npcs: Dictionary = _data["areas"].get(aid, {})
		for nid in npcs:
			var vs: Array = npcs[nid].get("variants", [])
			for vi in range(vs.size()):
				var hit_cond: bool = String(vs[vi].get("if", "")).to_lower().contains(q)
				for l in vs[vi].get("lines", []):
					var t: String = String(l.get("text", ""))
					if t.to_lower().contains(q) or hit_cond or String(nid).to_lower().contains(q):
						out.append({"kind": "bank", "area": aid, "npc": String(nid), "variant": vi, "text": t,
							"where": "%s/%s #%d" % [aid, nid, vi + 1]})
		for s in _index.scripts(aid):
			for l in s["lines"]:
				if String(l["text"]).to_lower().contains(q):
					out.append({"kind": "cutscene", "area": aid, "npc": String(s["owner"]), "variant": -1,
						"text": String(l["text"]), "where": "%s/%s %s (cutscene)" % [aid, s["owner"], s["source"]]})
	return out


## The "missing dialogue" report: {no_entry: [{area, npc, name, why}], silent: [{area, npc, phase}],
## placeholders: [{area, npc, variant, line, text}], never: [{area, npc, variant}]}.
func missing_report() -> Dictionary:
	var out: Dictionary = {"no_entry": [], "silent": [], "placeholders": [], "never": []}
	if _index == null:
		return out
	var states: Array = []
	for p in _phases:
		states.append(StoryPhases.state_for(p, [], [], _rests, _steps))
	for aid in _sorted_area_ids():
		for e in _index.npcs(aid):
			var nid: String = String(e.get("id"))
			var en: Dictionary = entry(aid, nid)
			if en.is_empty():
				var why: String = "no lines at all"
				if e.get("dialogue") != null:
					why = "only the builder's .tres line"
				elif StoryContentIndex.has_script(e):
					why = "scripted only (%s)" % StoryContentIndex.npc_kind(e)
				out["no_entry"].append({"area": aid, "npc": nid, "name": StoryContentIndex.npc_label(e), "why": why})
				continue
			var vis: String = String(e.get("visible_if"))
			var played: Dictionary = {}
			for pi in range(_phases.size()):
				var st: StoryState = states[pi]
				if not ConditionContext.evaluate(vis, st):
					continue
				var pick: int = DialogueBank.pick(en, st)
				if pick < 0:
					out["silent"].append({"area": aid, "npc": nid, "phase": String(_phases[pi]["short"])})
				else:
					played[pick] = true
			var vs: Array = en.get("variants", [])
			for vi in range(vs.size()):
				var cond: String = String(vs[vi].get("if", ""))
				var timed: bool = cond.contains("_since") or cond.contains("rests()") or cond.contains("steps()") or cond.contains("minutes")
				if not played.has(vi) and not timed:
					out["never"].append({"area": aid, "npc": nid, "variant": vi})
				var ls: Array = vs[vi].get("lines", [])
				for li in range(ls.size()):
					var t: String = String(ls[li].get("text", ""))
					if DialogueBank.is_placeholder(t):
						out["placeholders"].append({"area": aid, "npc": nid, "variant": vi, "line": li, "text": t})
	return out


func _sorted_area_ids() -> Array[String]:
	var out: Array[String] = []
	if _index == null:
		return out
	for a in AREA_ORDER:
		if _index.has_area(a):
			out.append(a)
	for a in _index.area_ids:
		if not out.has(a):
			out.append(a)
	return out


func _reset_ticks_to_phase() -> void:
	_ticked = {}
	if _phase >= 0 and _phase < _phases.size():
		for f in _phases[_phase]["flags"]:
			_ticked[String(f)] = true


# =====================================================================================
#  UI construction
# =====================================================================================

func _create_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Toolbar.
	var bar := HBoxContainer.new()
	root.add_child(bar)
	var title := Label.new()
	title.text = "DIALOGUE"
	title.add_theme_font_size_override("font_size", 16)
	bar.add_child(title)
	bar.add_child(_button("Save", func() -> void: save_bank()))
	bar.add_child(_button("Reload", func() -> void: load_bank()))
	bar.add_child(_button("Validate", _on_validate))
	bar.add_child(VSeparator.new())
	bar.add_child(_label("Story phase:"))
	_phase_opt = OptionButton.new()
	_phase_opt.custom_minimum_size = Vector2(320, 0)
	_phase_opt.fit_to_longest_item = false
	_phase_opt.tooltip_text = "Derived from the MAIN quests of quests.json: phase k = the first k milestone flags are set. Every view simulates this phase (plus the flags ticked in Town now)."
	_phase_opt.item_selected.connect(func(i: int) -> void: set_phase(i))
	bar.add_child(_phase_opt)
	bar.add_child(_label("+ rests"))
	_rests_spin = SpinBox.new()
	_rests_spin.max_value = 99
	_rests_spin.tooltip_text = "Story time: rests taken since the simulated flags were set (rests_since)."
	_rests_spin.value_changed.connect(func(v: float) -> void: set_time(int(v), _steps))
	bar.add_child(_rests_spin)
	bar.add_child(_label("+ steps"))
	_steps_spin = SpinBox.new()
	_steps_spin.max_value = 99999
	_steps_spin.step = 50
	_steps_spin.tooltip_text = "Story time: steps walked since the simulated flags were set (steps_since)."
	_steps_spin.value_changed.connect(func(v: float) -> void: set_time(_rests, int(v)))
	bar.add_child(_steps_spin)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.clip_text = true
	bar.add_child(_status)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 280
	root.add_child(split)

	# Left: search + tree.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(260, 0)
	split.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search every line..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void:
		_refresh_tree()
		_render_search())
	left.add_child(_search)
	_filter_check = CheckBox.new()
	_filter_check.text = "Only NPCs present in this phase"
	_filter_check.toggled.connect(func(_on: bool) -> void: _refresh_tree())
	left.add_child(_filter_check)
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = true
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)
	var legend := Label.new()
	legend.text = "* = scripted too   (no lines) = no bank entry"
	legend.add_theme_color_override("font_color", COLOR_DIM)
	left.add_child(legend)

	# Right: tabs.
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)

	var lines_scroll := ScrollContainer.new()
	lines_scroll.name = "Lines"
	lines_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(lines_scroll)
	_lines_box = VBoxContainer.new()
	_lines_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines_scroll.add_child(_lines_box)

	var town := HSplitContainer.new()
	town.name = "Town now"
	town.split_offset = 260
	_tabs.add_child(town)
	var town_left := VBoxContainer.new()
	town_left.custom_minimum_size = Vector2(240, 0)
	town.add_child(town_left)
	town_left.add_child(_label("Simulated flags (tick / untick):"))
	var flag_buttons := HBoxContainer.new()
	flag_buttons.add_child(_button("Phase flags", func() -> void:
		_reset_ticks_to_phase()
		_refresh_all()))
	flag_buttons.add_child(_button("None", func() -> void:
		_ticked = {}
		_refresh_all()))
	town_left.add_child(flag_buttons)
	_flags_tree = Tree.new()
	_flags_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_flags_tree.hide_root = true
	_flags_tree.item_edited.connect(_on_flag_edited)
	town_left.add_child(_flags_tree)
	var town_right := VBoxContainer.new()
	town.add_child(town_right)
	var town_bar := HBoxContainer.new()
	town_bar.add_child(_label("Town / area:"))
	_town_area_opt = OptionButton.new()
	_town_area_opt.item_selected.connect(func(_i: int) -> void: _render_town())
	town_bar.add_child(_town_area_opt)
	town_right.add_child(town_bar)
	_town_out = _rich()
	_town_out.meta_clicked.connect(_on_meta)
	town_right.add_child(_town_out)

	_cut_out = _rich()
	_cut_out.name = "Cutscenes"
	_tabs.add_child(_cut_out)

	_search_list = ItemList.new()
	_search_list.name = "Search"
	_search_list.item_activated.connect(_on_search_activated)
	_tabs.add_child(_search_list)

	_missing_out = _rich()
	_missing_out.name = "Missing"
	_missing_out.meta_clicked.connect(_on_meta)
	_tabs.add_child(_missing_out)

	_issues_out = _rich()
	_issues_out.name = "Issues"
	_issues_out.meta_clicked.connect(_on_meta)
	_tabs.add_child(_issues_out)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _rich() -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.selection_enabled = true
	r.scroll_following = false
	return r


func _set_status(text: String, color: Color) -> void:
	if _status == null:
		return
	_status.text = text
	_status.add_theme_color_override("font_color", color)


static func _esc(text: String) -> String:
	return text.replace("[", "[lb]")


# =====================================================================================
#  Rendering
# =====================================================================================

func _refresh_all() -> void:
	_refresh_tree()
	_refresh_flags_tree()
	_render_lines()
	_render_town()
	_render_cutscenes()
	_render_search()
	_render_missing()
	_refresh_issues()


func _fill_phase_options() -> void:
	if _phase_opt == null:
		return
	_phase_opt.clear()
	for p in _phases:
		_phase_opt.add_item(String(p["label"]))
	if _phase < _phase_opt.item_count:
		_phase_opt.select(_phase)


func _fill_town_areas() -> void:
	if _town_area_opt == null:
		return
	_town_area_opt.clear()
	var i: int = 0
	for aid in _sorted_area_ids():
		_town_area_opt.add_item(_index.area_name(aid))
		_town_area_opt.set_item_metadata(i, aid)
		i += 1


func _refresh_tree() -> void:
	if _tree == null or _index == null:
		return
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	var q: String = _search.text.strip_edges().to_lower() if _search != null else ""
	var only_present: bool = _filter_check != null and _filter_check.button_pressed
	var st: StoryState = sim_state()
	for aid in _sorted_area_ids():
		var area_item: TreeItem = null
		for e in _index.npcs(aid):
			var nid: String = String(e.get("id"))
			var nm: String = StoryContentIndex.npc_label(e)
			var en: Dictionary = entry(aid, nid)
			if only_present and not ConditionContext.evaluate(String(e.get("visible_if")), st):
				continue
			if not q.is_empty() and not _npc_matches(aid, nid, nm, en, q):
				continue
			if area_item == null:
				area_item = _tree.create_item(root)
				area_item.set_text(0, "%s  (%s)" % [_index.area_name(aid), aid])
				area_item.set_metadata(0, {"area": aid, "npc": ""})
				area_item.set_selectable(0, true)
			var it: TreeItem = _tree.create_item(area_item)
			var vs: int = (en.get("variants", []) as Array).size()
			var tag: String = "%d variant%s" % [vs, "" if vs == 1 else "s"] if not en.is_empty() else "(no lines)"
			it.set_text(0, "%s%s  -  %s" % [nm, " *" if StoryContentIndex.has_script(e) else "", tag])
			it.set_tooltip_text(0, "%s / %s (%s)%s" % [aid, nid, StoryContentIndex.npc_kind(e),
				"\nvisible_if: %s" % e.get("visible_if") if not String(e.get("visible_if")).is_empty() else ""])
			it.set_metadata(0, {"area": aid, "npc": nid})
			if en.is_empty():
				it.set_custom_color(0, COLOR_DIM)
			if aid == _sel_area and nid == _sel_npc:
				it.select(0)


func _npc_matches(aid: String, nid: String, nm: String, en: Dictionary, q: String) -> bool:
	if nid.to_lower().contains(q) or nm.to_lower().contains(q) or aid.contains(q):
		return true
	for v in en.get("variants", []):
		for l in v.get("lines", []):
			if String(l.get("text", "")).to_lower().contains(q):
				return true
	return false


func _on_tree_selected() -> void:
	var it: TreeItem = _tree.get_selected()
	if it == null:
		return
	var md = it.get_metadata(0)
	if not (md is Dictionary):
		return
	_sel_area = String(md["area"])
	_sel_npc = String(md["npc"])
	_render_lines()
	_render_cutscenes()
	for i in range(_town_area_opt.item_count):
		if String(_town_area_opt.get_item_metadata(i)) == _sel_area:
			_town_area_opt.select(i)
	_render_town()


func _refresh_flags_tree() -> void:
	if _flags_tree == null or _index == null:
		return
	_flags_tree.clear()
	var root: TreeItem = _flags_tree.create_item()
	var milestone_flags: Array[String] = []
	var ms_item: TreeItem = _flags_tree.create_item(root)
	ms_item.set_text(0, "Story milestones (quests.json)")
	ms_item.set_selectable(0, false)
	for m in StoryPhases.milestones():
		milestone_flags.append(String(m["flag"]))
		_flag_item(ms_item, String(m["flag"]), "%s -- %s" % [m["quest_title"], m["text"]])
	var groups: Dictionary = {}
	for f in _index.flag_names():
		if milestone_flags.has(f):
			continue
		var g: String = f.split(".")[0] if f.contains(".") else "(other)"
		if not groups.has(g):
			var gi: TreeItem = _flags_tree.create_item(root)
			gi.set_text(0, g)
			gi.set_selectable(0, false)
			gi.collapsed = true
			groups[g] = gi
		_flag_item(groups[g], f, ", ".join(_index.flags[f]))


func _flag_item(parent: TreeItem, flag: String, tip: String) -> void:
	var it: TreeItem = _flags_tree.create_item(parent)
	it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	it.set_editable(0, true)
	it.set_text(0, flag)
	it.set_checked(0, _ticked.has(flag))
	it.set_tooltip_text(0, tip)
	it.set_metadata(0, flag)
	if _ticked.has(flag) and parent.collapsed:
		parent.collapsed = false


func _on_flag_edited() -> void:
	var it: TreeItem = _flags_tree.get_edited()
	if it == null or not (it.get_metadata(0) is String):
		return
	set_flag_ticked(String(it.get_metadata(0)), it.is_checked(0))
	_refresh_tree()


# --- The Lines tab --------------------------------------------------------------------------

func _render_lines() -> void:
	if _lines_box == null:
		return
	for c in _lines_box.get_children():
		_lines_box.remove_child(c)
		c.queue_free()
	_flag_pick.clear()
	if _index == null or _sel_area.is_empty():
		_lines_box.add_child(_label("Pick a town and an NPC on the left."))
		return
	if _sel_npc.is_empty():
		_lines_box.add_child(_label("%s: pick an NPC on the left (Cutscenes shows this area's scripts)." % _index.area_name(_sel_area)))
		return
	var e: Resource = _index.npc(_sel_area, _sel_npc)
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vis: String = String(e.get("visible_if")) if e != null else ""
	head.text = "[b][font_size=18]%s[/font_size][/b]  [color=#999](%s / %s, %s)[/color]\n%s%s" % [
		_esc(StoryContentIndex.npc_label(e) if e != null else _sel_npc), _sel_area, _sel_npc,
		StoryContentIndex.npc_kind(e) if e != null else "unknown NPC",
		("Present: %s\n" % _esc(DialogueBank.describe_condition(vis))) if not vis.is_empty() else "",
		"[color=#e8c46a]Also SCRIPTED (on_interact / shop / battle): the bank line plays first, then the script -- see Cutscenes.[/color]\n" if StoryContentIndex.has_script(e) else ""]
	_lines_box.add_child(head)
	var en: Dictionary = entry(_sel_area, _sel_npc)
	if en.is_empty():
		_lines_box.add_child(_label("No dialogue-bank entry for this NPC yet."))
		if e != null and e.get("dialogue") != null:
			var fb: Array[String] = []
			for b in e.get("dialogue").get("beats"):
				if b != null:
					fb.append("  %s" % String(b.get("text")))
			_lines_box.add_child(_label("It says its builder (.tres) line instead:\n" + "\n".join(fb)))
		_lines_box.add_child(_button("Create a bank entry for %s" % _sel_npc, add_entry))
		return
	var note_row := HBoxContainer.new()
	note_row.add_child(_label("Note:"))
	var note := LineEdit.new()
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.placeholder_text = "author note (not shown in game)"
	note.text = String(en.get("note", ""))
	note.text_changed.connect(func(t: String) -> void:
		var cur: Dictionary = selected_entry()
		if t.strip_edges().is_empty():
			cur.erase("note")
		else:
			cur["note"] = t
		_mark_dirty())
	note_row.add_child(note)
	_lines_box.add_child(note_row)
	var help := _label("Variants are tried TOP TO BOTTOM: the first whose condition passes plays. Put the most specific first; leave the last one blank (always) as the fallback.")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", COLOR_DIM)
	_lines_box.add_child(help)
	var top := HBoxContainer.new()
	top.add_child(_button("+ Variant at top", func() -> void: add_variant("", true)))
	top.add_child(_button("+ Variant at bottom", func() -> void: add_variant("", false)))
	var del := _button("Delete entry", delete_entry)
	del.add_theme_color_override("font_color", COLOR_BAD)
	top.add_child(del)
	_lines_box.add_child(top)
	var st: StoryState = sim_state()
	var playing: int = DialogueBank.pick(en, st)
	var hits: Array = StoryPhases.variant_phases(en, _phases, [], [], _rests, _steps)
	var vs: Array = en["variants"]
	for vi in range(vs.size()):
		_lines_box.add_child(_variant_ui(vi, vs[vi], vi == playing, hits[vi] if vi < hits.size() else []))
	if playing < 0:
		var silent := _label("In the simulated state NO variant matches: this NPC says nothing.")
		silent.add_theme_color_override("font_color", COLOR_WARN)
		_lines_box.add_child(silent)


func _variant_ui(vi: int, v: Dictionary, plays: bool, hits: Array) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.19, 0.15) if plays else Color(0.14, 0.14, 0.16)
	sb.border_color = COLOR_PLAYS if plays else Color(0.3, 0.3, 0.34)
	sb.set_border_width_all(2 if plays else 1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	panel.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var num := Label.new()
	num.text = "#%d%s" % [vi + 1, "  >> PLAYS NOW" if plays else ""]
	if plays:
		num.add_theme_color_override("font_color", COLOR_PLAYS)
	head.add_child(num)
	var lab := LineEdit.new()
	lab.placeholder_text = "label (optional: 'after the raid')"
	lab.text = String(v.get("label", ""))
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.text_changed.connect(func(t: String) -> void: set_variant_field(vi, "label", t))
	head.add_child(lab)
	head.add_child(_button("Up", func() -> void: move_variant(vi, -1)))
	head.add_child(_button("Down", func() -> void: move_variant(vi, 1)))
	head.add_child(_button("Duplicate", func() -> void: duplicate_variant(vi)))
	head.add_child(_button("Remove", func() -> void: remove_variant(vi)))

	var cond_row := HBoxContainer.new()
	box.add_child(cond_row)
	cond_row.add_child(_label("if"))
	var cond := LineEdit.new()
	cond.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cond.placeholder_text = "blank = always.  e.g. after('opening.attack') and before('opening.complete')"
	cond.text = String(v.get("if", ""))
	var readable := Label.new()
	readable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	readable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_show_condition(readable, cond.text)
	cond.text_changed.connect(func(t: String) -> void:
		set_variant_field(vi, "if", t)
		_show_condition(readable, t))
	cond.text_submitted.connect(func(_t: String) -> void: _render_lines())
	cond_row.add_child(cond)
	box.add_child(readable)

	# Condition helpers: pick a flag, append after / before / N rests since.
	var helper := HBoxContainer.new()
	box.add_child(helper)
	helper.add_child(_label("add:"))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(220, 0)
	pick.fit_to_longest_item = false
	for m in StoryPhases.milestones():
		pick.add_item(String(m["flag"]))
	if _index != null:
		for f in _index.flag_names():
			var dup: bool = false
			for i in range(pick.item_count):
				if pick.get_item_text(i) == f:
					dup = true
			if not dup:
				pick.add_item(f)
	helper.add_child(pick)
	_flag_pick.append(pick)
	var rests_n := SpinBox.new()
	rests_n.min_value = 1
	rests_n.max_value = 99
	rests_n.value = 3
	helper.add_child(_button("after", func() -> void: _append_cond(vi, "after('%s')" % _picked(pick))))
	helper.add_child(_button("before", func() -> void: _append_cond(vi, "before('%s')" % _picked(pick))))
	helper.add_child(_button("rests since >=", func() -> void:
		_append_cond(vi, "rests_since('%s') >= %d" % [_picked(pick), int(rests_n.value)])))
	helper.add_child(rests_n)

	var chips := Label.new()
	var titles: Array[String] = []
	for pi in hits:
		var t: String = String(_phases[int(pi)]["quest_title"]) if int(pi) < _phases.size() else ""
		if not t.is_empty() and not titles.has(t):
			titles.append(t)
	chips.text = "plays in phases: %s%s" % [StoryPhases.compact(hits), ("   (%s)" % ", ".join(titles)) if not titles.is_empty() else ""]
	if hits.is_empty():
		chips.text += "   -- never on the timeline at +%d rests / +%d steps (time conditions or extra flags?)" % [_rests, _steps]
	chips.add_theme_color_override("font_color", COLOR_DIM if not hits.is_empty() else COLOR_WARN)
	chips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(chips)

	var lines: Array = v.get("lines", [])
	for li in range(lines.size()):
		box.add_child(_line_ui(vi, li, lines[li]))
	box.add_child(_button("+ Line", func() -> void: add_line(vi)))
	return panel


func _picked(pick: OptionButton) -> String:
	return pick.get_item_text(pick.selected) if pick.selected >= 0 else ""


func _append_cond(vi: int, piece: String) -> void:
	var vs: Array = selected_entry().get("variants", [])
	if vi < 0 or vi >= vs.size():
		return
	var cur: String = String(vs[vi].get("if", "")).strip_edges()
	set_variant_field(vi, "if", piece if cur.is_empty() else "%s and %s" % [cur, piece])
	_render_lines()


func _show_condition(l: Label, cond: String) -> void:
	var chk: Dictionary = ConditionContext.check(cond)
	if bool(chk.get("valid", false)):
		var unknown: Array[String] = []
		for f in DialogueBank.flags_in(cond):
			if _index != null and not _index.is_known_flag(f):
				unknown.append(f)
		l.text = "= %s%s" % [DialogueBank.describe_condition(cond),
			("   UNKNOWN FLAG: %s" % ", ".join(unknown)) if not unknown.is_empty() else ""]
		l.add_theme_color_override("font_color", COLOR_WARN if not unknown.is_empty() else COLOR_DIM)
	else:
		l.text = "MALFORMED: %s" % String(chk.get("error", ""))
		l.add_theme_color_override("font_color", COLOR_BAD)


func _line_ui(vi: int, li: int, l: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var speakers: Array[String] = [DialogueBank.SPEAKER_SELF, DialogueBank.SPEAKER_HERO, DialogueBank.SPEAKER_NARRATOR]
	if _index != null:
		for nid in _index.npc_ids(_sel_area):
			if nid != _sel_npc:
				speakers.append(nid)
	var cur: String = String(l.get("speaker", DialogueBank.SPEAKER_SELF))
	if not speakers.has(cur):
		speakers.append(cur)
	var sp := OptionButton.new()
	for s in speakers:
		sp.add_item(s)
	sp.select(speakers.find(cur))
	sp.custom_minimum_size = Vector2(110, 0)
	sp.item_selected.connect(func(i: int) -> void: set_line_field(vi, li, "speaker", sp.get_item_text(i)))
	row.add_child(sp)
	var side := OptionButton.new()
	for s in ["auto", "left", "right"]:
		side.add_item(s)
	var cs: String = String(l.get("side", ""))
	side.select(1 if cs == "left" else (2 if cs == "right" else 0))
	side.item_selected.connect(func(i: int) -> void: set_line_field(vi, li, "side", "" if i == 0 else side.get_item_text(i)))
	row.add_child(side)
	var te := TextEdit.new()
	te.text = String(l.get("text", ""))
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.scroll_fit_content_height = true
	te.custom_minimum_size = Vector2(0, 40)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if DialogueBank.is_placeholder(te.text):
		te.add_theme_color_override("font_color", COLOR_WARN)
	te.text_changed.connect(func() -> void: set_line_field(vi, li, "text", te.text))
	row.add_child(te)
	row.add_child(_button("Up", func() -> void: move_line(vi, li, -1)))
	row.add_child(_button("Down", func() -> void: move_line(vi, li, 1)))
	row.add_child(_button("X", func() -> void: remove_line(vi, li)))
	return row


# --- Town now, Cutscenes, Search, Missing, Issues -------------------------------------------

func _render_town() -> void:
	if _town_out == null or _town_area_opt == null or _town_area_opt.item_count == 0:
		return
	var aid: String = String(_town_area_opt.get_item_metadata(maxi(0, _town_area_opt.selected)))
	var lines: Array[String] = []
	lines.append("[b]%s[/b] in [b]%s[/b], +%d rests, +%d steps -- %d flags ticked" % [_esc(_index.area_name(aid)),
		_esc(String(_phases[_phase]["label"])) if _phase < _phases.size() else "?", _rests, _steps, _ticked.size()])
	for row in simulate(aid):
		var who: String = "[url=%s/%s]%s[/url]" % [aid, row["npc"], _esc(String(row["name"]))]
		if not bool(row["present"]):
			lines.append("\n[color=#777]%s -- not here in this state[/color]" % who)
			continue
		var tail: String = "  [color=#e8c46a](then scripted)[/color]" if bool(row["scripted"]) else ""
		match String(row["source"]):
			"bank":
				if int(row["variant"]) < 0:
					lines.append("\n%s -- [color=#f07060]says nothing (no variant matches)[/color]%s" % [who, tail])
					continue
				lines.append("\n%s -- variant #%d %s[color=#999]if %s[/color]%s" % [who, int(row["variant"]) + 1,
					("\"%s\" " % _esc(String(row["label"]))) if not String(row["label"]).is_empty() else "",
					_esc(DialogueBank.describe_condition(String(row["cond"]))), tail])
			"tres":
				lines.append("\n%s -- [color=#999](builder .tres line, no bank entry)[/color]%s" % [who, tail])
			_:
				lines.append("\n%s -- [color=#777](no lines)[/color]%s" % [who, tail])
		for l in row["lines"]:
			lines.append("    [i]%s:[/i] %s" % [_esc(String(l["speaker"])), _esc(String(l["text"]))])
	_town_out.text = "\n".join(lines)


func _render_cutscenes() -> void:
	if _cut_out == null or _index == null:
		return
	if _sel_area.is_empty():
		_cut_out.text = "Pick an area (or an NPC) on the left: its scripted dialogue shows here, read-only."
		return
	var out: Array[String] = []
	out.append("[b]%s[/b] -- scripted dialogue (READ-ONLY: it lives in game/overworld/build/build_story_content.gd; rebuild after editing it there)" % _esc(_index.area_name(_sel_area)))
	for s in _index.scripts(_sel_area):
		var mine: bool = String(s["owner"]) == _sel_npc
		out.append("\n[b]%s%s[/b]  [color=#999]%s%s[/color]" % ["> " if mine else "", _esc(String(s["owner_name"])),
			_esc(String(s["source"])), ("  -- present: %s" % _esc(DialogueBank.describe_condition(String(s["gate"])))) if not String(s["gate"]).is_empty() else ""])
		var last_cond: String = ""
		var first: bool = true
		for l in s["lines"]:
			var cond: String = String(l["cond"])
			if first or cond != last_cond:
				if not cond.is_empty():
					out.append("  [color=#8fb4e8]when %s:[/color]" % _esc(DialogueBank.describe_condition(cond)))
				last_cond = cond
				first = false
			if bool(l["marker"]):
				out.append("      [color=#888][i]-- %s[/i][/color]" % _esc(String(l["text"])))
			else:
				out.append("      [i]%s:[/i] %s" % [_esc(String(l["speaker"])), _esc(String(l["text"]))])
	_cut_out.text = "\n".join(out)


func _render_search() -> void:
	if _search_list == null:
		return
	_search_list.clear()
	var q: String = _search.text if _search != null else ""
	if q.strip_edges().is_empty():
		_search_list.add_item("Type in the search box (top left) to search every line, bank and cutscenes.")
		return
	for r in search(q):
		var i: int = _search_list.add_item("%s:  %s" % [r["where"], r["text"]])
		_search_list.set_item_metadata(i, r)
		if String(r["kind"]) == "cutscene":
			_search_list.set_item_custom_fg_color(i, COLOR_DIM)


func _on_search_activated(i: int) -> void:
	var r = _search_list.get_item_metadata(i)
	if not (r is Dictionary):
		return
	select_npc(String(r["area"]), String(r["npc"]) if String(r["kind"]) == "bank" else "")
	if String(r["kind"]) == "bank":
		_sel_npc = String(r["npc"])
		_refresh_tree()
		_render_lines()
		_tabs.current_tab = TAB_LINES
	else:
		_tabs.current_tab = TAB_CUTSCENES


func _render_missing() -> void:
	if _missing_out == null or _index == null:
		return
	var rep: Dictionary = missing_report()
	var out: Array[String] = []
	out.append("[b]Missing dialogue[/b]  (phases simulated at +%d rests / +%d steps)" % [_rests, _steps])
	out.append("\n[b]Placeholder / TODO lines (%d)[/b]" % rep["placeholders"].size())
	for r in rep["placeholders"]:
		out.append("  [url=%s/%s]%s/%s[/url] #%d line %d: %s" % [r["area"], r["npc"], r["area"], r["npc"], int(r["variant"]) + 1,
			int(r["line"]) + 1, _esc(String(r["text"]))])
	out.append("\n[b]Present but SILENT in a phase (%d)[/b] -- an entry exists but no variant matches" % rep["silent"].size())
	var by_npc: Dictionary = {}
	for r in rep["silent"]:
		var k: String = "%s/%s" % [r["area"], r["npc"]]
		if not by_npc.has(k):
			by_npc[k] = []
		by_npc[k].append(r["phase"])
	for k in by_npc:
		out.append("  [url=%s]%s[/url]: %s" % [k, k, ", ".join(by_npc[k])])
	out.append("\n[b]Variants that never play on the phase timeline (%d)[/b] -- shadowed, or gated by flags no milestone sets" % rep["never"].size())
	for r in rep["never"]:
		out.append("  [url=%s/%s]%s/%s[/url] #%d" % [r["area"], r["npc"], r["area"], r["npc"], int(r["variant"]) + 1])
	out.append("\n[b]NPCs with no bank entry (%d)[/b]" % rep["no_entry"].size())
	for r in rep["no_entry"]:
		out.append("  [url=%s/%s]%s[/url] (%s/%s) -- %s" % [r["area"], r["npc"], _esc(String(r["name"])), r["area"], r["npc"], r["why"]])
	_missing_out.text = "\n".join(out)


func _on_validate() -> void:
	_issues = DialogueBank.validate(_data, _index)
	_refresh_issues()
	_tabs.current_tab = TAB_ISSUES
	_set_status("Validator: %s." % ("no issues" if _issues.is_empty() else "%d issue(s)" % _issues.size()),
		COLOR_PLAYS if _issues.is_empty() else COLOR_WARN)


func _refresh_issues() -> void:
	if _issues_out == null:
		return
	if _issues.is_empty():
		_issues_out.text = "[color=#6c6]No issues.[/color] (The validator runs on every Save; press Validate to run it now.)"
		return
	var out: Array[String] = ["[b]%d issue(s)[/b]" % _issues.size()]
	for i in _issues:
		var key: String = i.split(":")[0].split(" ")[0]
		out.append("  [url=%s]%s[/url]" % [key, _esc(i)])
	_issues_out.text = "\n".join(out)


func _on_meta(meta) -> void:
	var parts: PackedStringArray = String(meta).split("/")
	if parts.size() < 2:
		return
	_sel_area = parts[0]
	_sel_npc = parts[1]
	_refresh_tree()
	_render_lines()
	_render_cutscenes()
	_tabs.current_tab = TAB_LINES
