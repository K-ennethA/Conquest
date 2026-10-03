@tool
extends Control

## QUEST EDITOR PANEL (the "Quests" bottom-panel tab; plugin.gd mounts it). Edits
## game/overworld/content/quests.json -- the flag-derived quest log ([QuestLog]) -- as data:
##
##   * left: the quests grouped MAIN / SIDE; Add main / Add side / Duplicate / Remove / Up / Down
##     (Up / Down reorder within the quest's group -- the file order is the log's tie-break order);
##   * right: the selected quest -- id, title, category, summary, giver (npc id), location (a
##     world place or area id), area, start / complete flag, and its STEPS (flag, text, location,
##     area, npc; add / remove / reorder). Every flag and place field has a picker ("v") filled
##     from what the story content actually uses ([QuestValidator.scan_project]: the builder's F_*
##     constants and flag literals, the generated .tres) -- free text is always allowed;
##   * Validate: [QuestValidator.validate] (unknown flags, unreachable quests whose start flag no
##     content sets, duplicate ids, empty text, unknown places) into the report pane;
##   * Story flow: [QuestValidator.story_flow] -- the quests in the order their start flags are
##     reached;
##   * Save: [QuestLog.to_json] -- tab-indented, keys in a fixed order, empty optional keys left out,
##     so the file diffs cleanly; Reload drops unsaved edits.

const CATEGORIES: Array[String] = ["main", "side"]

## The file edited (tests point it at a temp copy).
var data_path: String = QuestLog.DATA_PATH
## The definitions being edited (plain dictionaries, the quests.json shape).
var defs: Array = []
var dirty: bool = false

var _scan: Dictionary = {}
var _sel: int = -1
var _tree: Tree = null
var _form: VBoxContainer = null
var _steps_box: VBoxContainer = null
var _report: RichTextLabel = null
var _status: Label = null
var _building: bool = false


func _init() -> void:
	name = "QuestEditor"
	custom_minimum_size = Vector2(0, 320)


func _ready() -> void:
	_build_ui()
	reload()


# =====================================================================================
#  Data
# =====================================================================================

## Re-read [member data_path] (unsaved edits are dropped) and rescan the story content.
func reload() -> void:
	defs = []
	for d in QuestLog.parse(FileAccess.get_file_as_string(data_path)):
		defs.append((d as Dictionary).duplicate(true))
	_scan = QuestValidator.scan_project()
	dirty = false
	_sel = 0 if not defs.is_empty() else -1
	_rebuild_tree()
	_rebuild_form()
	_set_status("Loaded %d quests from %s" % [defs.size(), data_path])


## Write the definitions to [member data_path] as stable, pretty JSON. Returns OK or an error code.
func save() -> int:
	var f := FileAccess.open(data_path, FileAccess.WRITE)
	if f == null:
		_set_status("Could not write %s" % data_path)
		return FileAccess.get_open_error()
	f.store_string(QuestLog.to_json(defs))
	f.close()
	dirty = false
	QuestLog.set_definitions(null)
	# Looked up by name: this panel also runs outside the editor (tests), where the class is absent.
	if Engine.is_editor_hint() and Engine.has_singleton(&"EditorInterface"):
		Engine.get_singleton(&"EditorInterface").get_resource_filesystem().update_file(data_path)
	var errs: Array = QuestValidator.errors(QuestValidator.validate(defs, _scan))
	_set_status("Saved %s%s" % [data_path, "" if errs.is_empty() else "  (%d validation errors)" % errs.size()])
	return OK


func selected_index() -> int:
	return _sel


func select_quest(index: int) -> void:
	_sel = clampi(index, -1, defs.size() - 1)
	_rebuild_tree()
	_rebuild_form()


## Add a new quest of [param category] after the last one of that group; returns its index.
func add_quest(category: String = "side") -> int:
	var base: String = "new_quest"
	var id: String = base
	var n: int = 2
	while _index_of(id) >= 0:
		id = "%s_%d" % [base, n]
		n += 1
	var q := {"id": id, "title": "New Quest", "category": category, "summary": "", "start_flag": "",
		"complete_flag": "", "steps": [{"flag": "", "text": ""}]}
	var at: int = defs.size()
	for i in range(defs.size()):
		if String(defs[i].get("category", "")) == category:
			at = i + 1
	defs.insert(at, q)
	_touch()
	select_quest(at)
	return at


func duplicate_quest() -> int:
	if _sel < 0:
		return -1
	var q: Dictionary = (defs[_sel] as Dictionary).duplicate(true)
	q["id"] = String(q.get("id", "quest")) + "_copy"
	defs.insert(_sel + 1, q)
	_touch()
	select_quest(_sel + 1)
	return _sel


func remove_quest() -> void:
	if _sel < 0:
		return
	defs.remove_at(_sel)
	_touch()
	select_quest(mini(_sel, defs.size() - 1))


## Move the selected quest up (-1) / down (+1) past the neighbouring quest of its own category.
func move_quest(dir: int) -> void:
	if _sel < 0:
		return
	var cat: String = String(defs[_sel].get("category", ""))
	var j: int = _sel + dir
	while j >= 0 and j < defs.size() and String(defs[j].get("category", "")) != cat:
		j += dir
	if j < 0 or j >= defs.size():
		return
	var q = defs[_sel]
	defs.remove_at(_sel)
	defs.insert(j, q)
	_touch()
	select_quest(j)


func validate() -> Array:
	var issues: Array = QuestValidator.validate(defs, _scan)
	var lines: PackedStringArray = []
	if issues.is_empty():
		lines.append("[color=#74d68e]No problems found in %d quests.[/color]" % defs.size())
	for i in issues:
		var col: String = "#ff8070" if String(i["severity"]) == QuestValidator.SEVERITY_ERROR else "#ffc857"
		lines.append("[color=%s]%s[/color]  [b]%s[/b]: %s" % [col, String(i["severity"]).to_upper(),
			String(i["quest"]), String(i["message"])])
	_report.text = "\n".join(lines)
	_set_status("%d errors, %d warnings" % [QuestValidator.errors(issues).size(),
		issues.size() - QuestValidator.errors(issues).size()])
	return issues


func show_story_flow() -> Array:
	var flow: Array = QuestValidator.story_flow(defs, _scan)
	var lines: PackedStringArray = ["[b]Story flow[/b] (quests in the order their start flags are reached)"]
	for i in range(flow.size()):
		var r: Dictionary = flow[i]
		var start: String = String(r["start_flag"])
		var how: String = "from the start" if start.is_empty() else "opens on [code]%s[/code]" % start
		if not String(r["after"]).is_empty():
			how += " (progress in %s)" % String(r["after"])
		if not bool(r["reachable"]):
			how += "  [color=#ff8070]UNREACHABLE: nothing sets it[/color]"
		lines.append("%d. [%s] [b]%s[/b] (%s) -- %s" % [i + 1, String(r["category"]).to_upper(),
			String(r["title"]), String(r["id"]), how])
	_report.text = "\n".join(lines)
	return flow


func _index_of(id: String) -> int:
	for i in range(defs.size()):
		if String(defs[i].get("id", "")) == id:
			return i
	return -1


func _touch() -> void:
	dirty = true
	_set_status("Unsaved changes")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# =====================================================================================
#  UI
# =====================================================================================

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	split.add_child(left)
	_tree = Tree.new()
	_tree.name = "QuestTree"
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)
	var lb := HFlowContainer.new()
	left.add_child(lb)
	_btn(lb, "+ Main", func() -> void: add_quest("main"))
	_btn(lb, "+ Side", func() -> void: add_quest("side"))
	_btn(lb, "Duplicate", duplicate_quest)
	_btn(lb, "Remove", remove_quest)
	_btn(lb, "Up", func() -> void: move_quest(-1))
	_btn(lb, "Down", func() -> void: move_quest(1))

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_btn(bar, "Reload", reload)
	_btn(bar, "Save", save)
	_btn(bar, "Validate", validate)
	_btn(bar, "Story flow", show_story_flow)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	bar.add_child(_status)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(520, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_form = VBoxContainer.new()
	_form.name = "QuestForm"
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)
	_report = RichTextLabel.new()
	_report.name = "Report"
	_report.bbcode_enabled = true
	_report.selection_enabled = true
	_report.custom_minimum_size = Vector2(260, 0)
	_report.text = "Validate / Story flow results appear here."
	body.add_child(_report)


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func() -> void: cb.call())
	parent.add_child(b)
	return b


func _rebuild_tree() -> void:
	if _tree == null:
		return
	_tree.clear()
	var root := _tree.create_item()
	var groups: Dictionary = {}
	for c in CATEGORIES:
		var g := _tree.create_item(root)
		g.set_text(0, c.to_upper())
		g.set_selectable(0, false)
		groups[c] = g
	for i in range(defs.size()):
		var cat: String = String(defs[i].get("category", "side"))
		var parent: TreeItem = groups.get(cat, groups["side"])
		var it := _tree.create_item(parent)
		it.set_text(0, "%s  (%s)" % [String(defs[i].get("title", "")), String(defs[i].get("id", ""))])
		it.set_metadata(0, i)
		if i == _sel:
			it.select(0)


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null or it.get_metadata(0) == null:
		return
	var i: int = int(it.get_metadata(0))
	if i != _sel:
		_sel = i
		_rebuild_form()


func _rebuild_form() -> void:
	if _form == null:
		return
	_building = true
	for c in _form.get_children():
		_form.remove_child(c)
		c.queue_free()
	if _sel < 0 or _sel >= defs.size():
		var none := Label.new()
		none.text = "No quest selected. Add one on the left."
		_form.add_child(none)
		_building = false
		return
	var q: Dictionary = defs[_sel]
	var grid := GridContainer.new()
	grid.columns = 2
	_form.add_child(grid)
	_field(grid, "Id", q, "id", [], true)
	_field(grid, "Title", q, "title", [], true)
	var cat_row := HBoxContainer.new()
	_grid_label(grid, "Category")
	grid.add_child(cat_row)
	var cat := OptionButton.new()
	cat.name = "Category"
	for c in CATEGORIES:
		cat.add_item(c)
	cat.select(maxi(0, CATEGORIES.find(String(q.get("category", "side")))))
	cat.item_selected.connect(func(idx: int) -> void:
		q["category"] = CATEGORIES[idx]
		_touch()
		_rebuild_tree())
	cat_row.add_child(cat)
	_grid_label(grid, "Summary")
	var summary := TextEdit.new()
	summary.name = "Summary"
	summary.text = String(q.get("summary", ""))
	summary.custom_minimum_size = Vector2(0, 54)
	summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.text_changed.connect(func() -> void:
		q["summary"] = summary.text
		_touch())
	grid.add_child(summary)
	_field(grid, "Giver (npc id)", q, "giver", [])
	_field(grid, "Location", q, "location", _place_items())
	_field(grid, "Area", q, "area", _area_items())
	_field(grid, "Start flag", q, "start_flag", _flag_items())
	_field(grid, "Complete flag", q, "complete_flag", _flag_items())

	var head := Label.new()
	head.text = "Steps (the first one whose flag is unset is the current objective)"
	_form.add_child(head)
	_steps_box = VBoxContainer.new()
	_steps_box.name = "Steps"
	_form.add_child(_steps_box)
	var steps: Array = q.get("steps", [])
	if not (q.get("steps") is Array):
		q["steps"] = steps
	for si in range(steps.size()):
		_step_row(q, si)
	var add := Button.new()
	add.text = "+ Step"
	add.pressed.connect(func() -> void:
		(q["steps"] as Array).append({"flag": "", "text": ""})
		_touch()
		_rebuild_form())
	_form.add_child(add)
	_building = false


func _grid_label(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	grid.add_child(l)


## A labelled LineEdit bound to [param d][[param key]] (+ a picker when [param items] is not empty).
func _field(grid: GridContainer, label: String, d: Dictionary, key: String, items: Array,
		retitle: bool = false) -> LineEdit:
	_grid_label(grid, label)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(row)
	var le := _line(d, key, retitle)
	le.name = label.replace(" ", "").replace("(", "").replace(")", "")
	row.add_child(le)
	if not items.is_empty():
		row.add_child(_picker(le, items))
	return le


func _line(d: Dictionary, key: String, retitle: bool = false) -> LineEdit:
	var le := LineEdit.new()
	le.text = String(d.get(key, ""))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(func(t: String) -> void:
		d[key] = t
		_touch()
		if retitle:
			_retitle_selected())
	return le


func _retitle_selected() -> void:
	var it := _tree.get_selected()
	if it != null and _sel >= 0:
		it.set_text(0, "%s  (%s)" % [String(defs[_sel].get("title", "")), String(defs[_sel].get("id", ""))])


## A "v" menu that fills [param le] (and fires its text_changed) -- [param items] are strings, or
## [group, [strings]] pairs shown as submenus.
func _picker(le: LineEdit, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = "v"
	mb.tooltip_text = "Pick from the story content (free text is fine too)"
	var pm := mb.get_popup()
	var values: Array = []
	for entry in items:
		if entry is Array:
			var sub := PopupMenu.new()
			for v in entry[1]:
				sub.add_item(String(v), values.size())
				values.append(String(v))
			sub.id_pressed.connect(func(id: int) -> void: _pick(le, values[id]))
			pm.add_submenu_node_item(String(entry[0]), sub)
		else:
			pm.add_item(String(entry), values.size())
			values.append(String(entry))
	pm.id_pressed.connect(func(id: int) -> void: _pick(le, values[id]))
	return mb


func _pick(le: LineEdit, value: String) -> void:
	le.text = value
	le.text_changed.emit(value)


func _step_row(q: Dictionary, si: int) -> void:
	var s: Dictionary = (q["steps"] as Array)[si]
	var row := HBoxContainer.new()
	row.name = "Step%d" % (si + 1)
	_steps_box.add_child(row)
	var n := Label.new()
	n.text = "%d." % (si + 1)
	row.add_child(n)
	var flag := _line(s, "flag")
	flag.placeholder_text = "flag"
	flag.custom_minimum_size = Vector2(170, 0)
	flag.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(flag)
	row.add_child(_picker(flag, _flag_items()))
	var text := _line(s, "text")
	text.placeholder_text = "objective text"
	text.custom_minimum_size = Vector2(220, 0)
	row.add_child(text)
	var loc := _line(s, "location")
	loc.placeholder_text = "location"
	loc.custom_minimum_size = Vector2(110, 0)
	loc.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(loc)
	row.add_child(_picker(loc, _place_items()))
	var area := _line(s, "area")
	area.placeholder_text = "area"
	area.custom_minimum_size = Vector2(100, 0)
	area.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(area)
	row.add_child(_picker(area, _area_items()))
	var npc := _line(s, "npc")
	npc.placeholder_text = "npc"
	npc.custom_minimum_size = Vector2(80, 0)
	npc.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(npc)
	for spec in [["^", -1], ["v", 1]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.pressed.connect(_move_step.bind(q, si, int(spec[1])))
		row.add_child(b)
	var del := Button.new()
	del.text = "x"
	del.pressed.connect(func() -> void:
		(q["steps"] as Array).remove_at(si)
		_touch()
		_rebuild_form.call_deferred())
	row.add_child(del)


func _move_step(q: Dictionary, si: int, dir: int) -> void:
	var steps: Array = q["steps"]
	var j: int = si + dir
	if j < 0 or j >= steps.size():
		return
	var s = steps[si]
	steps[si] = steps[j]
	steps[j] = s
	_touch()
	_rebuild_form.call_deferred()


## The flag picker's items: known flags grouped by their first segment ("opening", "arena", ...).
func _flag_items() -> Array:
	var groups: Dictionary = {}
	for f in _scan.get("known", []):
		var head: String = String(f).get_slice(".", 0)
		if not groups.has(head):
			groups[head] = []
		groups[head].append(String(f))
	var keys: Array = groups.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append([String(k), groups[k]])
	return out


func _place_items() -> Array:
	return [["Places", _scan.get("locations", [])], ["Areas", _scan.get("areas", [])]]


func _area_items() -> Array:
	return _scan.get("areas", [])
