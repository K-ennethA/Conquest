extends Control

class_name Compendium

# Compendium - the single in-game encyclopedia.
#
# SECTIONS. Units / Tiles / Maps are the EXISTING UnitGallery, TileGallery and
# MapGallery scenes instantiated into a tab each (they build their own UI; hosting
# them costs an add_child()). Weather / Tile Effects / Statuses / Rules are ENTRY
# BROWSERS built here from [CompendiumData], the data model that derives every entry
# from the authored resources -- so new weather, tile effects, statuses, units,
# moves and abilities appear on their own.
#
# SEARCH. The search box above the tabs looks through EVERY section's entries (units
# included) and jumps to the one you pick. Entries cross-link with
# [url=<section>:<id>] BBCode (a weather named in a unit's ability jumps to it).
#
# OVERLAY. [method open_overlay] shows the Compendium over a running battle (Map Menu
# > Encyclopedia): it lives on its own CanvasLayer in [constant
# InputActions.OVERLAY_GROUP] so the board ignores input, and Back / Esc closes it
# instead of leaving the battle.
#
# LAZY HOSTING. Each tab starts as an empty host Control and is built the first time
# it is shown (see _ensure_section). INPUT OWNERSHIP: _input is enabled only on the
# section on screen (see _sync_section_input).

signal closed

## Section index -> tab title. Order here IS the tab order.
const SECTION_TITLES: Array[String] = ["Units", "Tiles", "Maps", "Weather", "Tile Effects", "Statuses", "Rules"]

const SECTION_UNITS := 0
const SECTION_TILES := 1
const SECTION_MAPS := 2
const SECTION_WEATHER := 3
const SECTION_TILE_EFFECTS := 4
const SECTION_STATUSES := 5
const SECTION_RULES := 6

## Hosted gallery scenes, by section index.
const HOSTED_SCENES: Dictionary = {
	SECTION_UNITS: "res://menus/UnitGallery.tscn",
	SECTION_TILES: "res://menus/TileGallery.tscn",
	SECTION_MAPS: "res://menus/MapGallery.tscn",
}

## Browser sections: tab index -> CompendiumData section id.
const BROWSER_SECTIONS: Dictionary = {
	SECTION_WEATHER: CompendiumData.SECTION_WEATHER,
	SECTION_TILE_EFFECTS: CompendiumData.SECTION_TILES,
	SECTION_STATUSES: CompendiumData.SECTION_STATUSES,
	SECTION_RULES: CompendiumData.SECTION_RULES,
}

const MUTED := MenuTheme.TEXT_MUTED
const MAP_MAKER_SCENE := "res://game/mapmaker/MapMakerScene.tscn"
const SCENE_PATH := "res://menus/Compendium.tscn"

## True when shown over a battle (Back closes instead of changing scene).
var overlay_mode: bool = false

# --- Shell ---
var tab_container: TabContainer
var back_button: Button
var search_box: LineEdit
var search_results: ItemList
var _search_hits: Array = []

## Host Control per section index; the section's content is added under it.
var _section_hosts: Dictionary = {}
## Section indices already populated, so a tab is only built once.
var _built_sections: Dictionary = {}

## Per browser section: { list, filter, detail, scroll, entries, shown }.
var _browsers: Dictionary = {}

## Kept for callers / tests that read the Statuses browser directly.
var status_list: ItemList
var status_search: LineEdit
var status_detail: VBoxContainer


## Show the Compendium over the current scene (the battle) and return it. Closes on
## Back / Esc; board input is blocked while it is open.
static func open_overlay(tree: SceneTree, start_section: int = SECTION_WEATHER) -> Compendium:
	if tree == null:
		return null
	var layer := CanvasLayer.new()
	layer.name = "CompendiumOverlay"
	layer.layer = 50
	var packed := load(SCENE_PATH) as PackedScene
	var comp := packed.instantiate() as Compendium
	comp.overlay_mode = true
	comp.add_to_group(InputActions.OVERLAY_GROUP)
	layer.add_child(comp)
	# Added AFTER the Compendium so its _input runs FIRST (reverse tree order): the
	# hosted galleries' own Esc handlers would otherwise leave the battle.
	var catcher := _BackCatcher.new()
	catcher.target = comp
	layer.add_child(catcher)
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(layer)
	comp.closed.connect(layer.queue_free)
	comp.select_tab(start_section)
	return comp


func _ready() -> void:
	theme = MenuTheme.build()
	_build_shell()
	_ensure_section(tab_container.current_tab)
	_sync_section_input()


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build_shell() -> void:
	var page := MenuKit.build_page(self, ["Battle"] if overlay_mode else [], "Compendium",
		"Every unit, tile, map, weather, effect and rule in the game.")
	(page.subtitle as Label).visible = false

	# Global search: across every section, jump to the pick. Sits on the title row
	# (right of "Compendium") so the browsers keep their height.
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	search_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.alignment = BoxContainer.ALIGNMENT_END
	search_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title_row := (page.title as Label).get_parent()
	if title_row is HBoxContainer:
		title_row.add_child(search_row)
	else:
		page.body.add_child(search_row)
	search_box = LineEdit.new()
	search_box.name = "GlobalSearch"
	search_box.placeholder_text = "Search units, moves, weather, tiles, statuses, rules..."
	search_box.custom_minimum_size = Vector2(560, 0)
	search_box.clear_button_enabled = true
	search_box.text_changed.connect(_on_global_search)
	search_box.text_submitted.connect(func(_t): _pick_search_result(0))
	search_box.gui_input.connect(_on_search_box_input)
	search_row.add_child(search_box)

	search_results = ItemList.new()
	search_results.name = "SearchResults"
	search_results.visible = false
	search_results.custom_minimum_size = Vector2(0, 180)
	search_results.item_activated.connect(_pick_search_result)
	search_results.item_clicked.connect(func(i, _p, _b): _pick_search_result(i))
	page.body.add_child(search_results)

	tab_container = TabContainer.new()
	tab_container.name = "Sections"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.body.add_child(tab_container)

	for i in SECTION_TITLES.size():
		var host := Control.new()
		host.name = SECTION_TITLES[i].replace(" ", "")
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		host.clip_contents = true
		tab_container.add_child(host)
		tab_container.set_tab_title(i, SECTION_TITLES[i])
		_section_hosts[i] = host

	tab_container.tab_changed.connect(_on_tab_changed)

	if not overlay_mode:
		# The in-game Map Maker lives here too: author your own battlefield.
		var map_maker_button := MenuKit.button("Map Maker", &"", 180)
		map_maker_button.name = "MapMakerButton"
		map_maker_button.tooltip_text = "Build and save your own maps (multi-floor, spawns, stairs)."
		map_maker_button.pressed.connect(_on_map_maker_pressed)
		page.actions.add_child(map_maker_button)

	back_button = MenuKit.button("Return to Battle" if overlay_mode else "Back", MenuKit.GHOST,
		200 if overlay_mode else 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_pressed)
	page.actions.add_child(back_button)
	page.hints.add_child(MenuKit.key_hint("Q / R", "LB / RB", "Switch section"))
	page.hints.add_child(MenuKit.key_hint("Arrows", "D-Pad", "Browse / scroll"))
	page.hints.add_child(MenuKit.key_hint("Esc", "B", "Close" if overlay_mode else "Back"))
	MenuNav.focus_deferred(tab_container.get_tab_bar())


func _on_map_maker_pressed() -> void:
	MenuNav.change_scene(self, MAP_MAKER_SCENE)


func _on_tab_changed(tab: int) -> void:
	_ensure_section(tab)
	_sync_section_input()


## Switch to tab [param index] (built on demand).
func select_tab(index: int) -> void:
	if tab_container == null:
		return
	index = clampi(index, 0, tab_container.get_tab_count() - 1)
	if tab_container.current_tab != index:
		tab_container.current_tab = index
	else:
		_on_tab_changed(index)


## Build section [param index] if it has not been built yet. Every failure mode
## degrades to a placeholder inside that one tab.
func _ensure_section(index: int) -> void:
	if _built_sections.has(index):
		return
	_built_sections[index] = true

	var host: Control = _section_hosts.get(index, null) as Control
	if host == null:
		return

	if HOSTED_SCENES.has(index):
		_build_hosted_section(host, String(HOSTED_SCENES[index]))
		return
	if BROWSER_SECTIONS.has(index):
		_build_browser(host, index, String(BROWSER_SECTIONS[index]))
		return
	_add_placeholder(host, "This section is not available.")


## Instantiate an existing gallery scene into [param host].
func _build_hosted_section(host: Control, scene_path: String) -> void:
	if not ResourceLoader.exists(scene_path):
		_add_placeholder(host, "This section could not be loaded.\nMissing: %s" % scene_path)
		return

	var packed = load(scene_path)
	if not (packed is PackedScene):
		_add_placeholder(host, "This section could not be loaded.\nNot a scene: %s" % scene_path)
		return

	var inst = (packed as PackedScene).instantiate()
	if not (inst is Control):
		_add_placeholder(host, "This section could not be loaded.\nUnexpected root in: %s" % scene_path)
		if inst is Node:
			(inst as Node).queue_free()
		return

	var gallery: Control = inst as Control
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(gallery)
	# The standalone scene's flat background would cover the tab panel.
	var gallery_bg := gallery.get_node_or_null("Background")
	if gallery_bg is CanvasItem:
		(gallery_bg as CanvasItem).visible = false

	# The shell supplies the single back control: hide the gallery's own.
	if "back_button" in gallery:
		var gallery_back = gallery.get("back_button")
		if gallery_back is Button:
			(gallery_back as Button).visible = false
			var header := (gallery_back as Button).get_parent()
			if header is HBoxContainer and header.get_child_count() <= 2:
				(header as HBoxContainer).visible = false


func _add_placeholder(host: Control, message: String) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(center)

	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = &"MutedLabel"
	center.add_child(label)


## Enable _input only on the section currently on screen.
func _sync_section_input() -> void:
	if tab_container == null:
		return
	var current: int = tab_container.current_tab
	for key in _section_hosts:
		var index: int = int(key)
		var host: Control = _section_hosts[key] as Control
		if host == null:
			continue
		for child in host.get_children():
			child.set_process_input(index == current)
			child.set_process_unhandled_input(index == current)


# ---------------------------------------------------------------------------
# Entry browsers (Weather / Tile Effects / Statuses / Rules)
# ---------------------------------------------------------------------------

func _build_browser(host: Control, index: int, section: String) -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", MenuTheme.SP_XL)
	host.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(300, 0)
	left.add_theme_constant_override("separation", MenuTheme.SP_S)
	split.add_child(left)

	var filter := LineEdit.new()
	filter.placeholder_text = "Filter %s..." % SECTION_TITLES[index].to_lower()
	filter.clear_button_enabled = true
	left.add_child(filter)

	var list := ItemList.new()
	list.name = "EntryList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(290, 300)
	list.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	left.add_child(list)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.card_box())
	split.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.name = "DetailScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	card.add_child(scroll)

	var detail := VBoxContainer.new()
	detail.name = "Detail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", MenuTheme.SP_S)
	scroll.add_child(detail)

	var b := { "list": list, "filter": filter, "detail": detail, "scroll": scroll,
		"entries": CompendiumData.entries(section), "shown": [] }
	_browsers[index] = b
	if index == SECTION_STATUSES:
		status_list = list
		status_search = filter
		status_detail = detail

	filter.text_changed.connect(func(_t): _refresh_browser(index))
	list.item_selected.connect(func(i): _show_entry(index, i))
	list.gui_input.connect(func(e): _on_list_input(index, e))
	scroll.gui_input.connect(func(e): _on_scroll_input(index, e))
	_refresh_browser(index)
	if list.item_count > 0:
		list.select(0)
		_show_entry(index, 0)


func _refresh_browser(index: int) -> void:
	var b: Dictionary = _browsers[index]
	var list: ItemList = b["list"]
	b["shown"] = CompendiumData.search(b["entries"], (b["filter"] as LineEdit).text)
	list.clear()
	for e in b["shown"]:
		var i := list.add_item(String(e["title"]))
		list.set_item_custom_fg_color(i, (e["color"] as Color).lightened(0.35))
		list.set_item_tooltip(i, String(e.get("subtitle", "")))
	if list.item_count == 0:
		list.add_item("Nothing matches")
		list.set_item_disabled(0, true)


func _show_entry(index: int, i: int) -> void:
	var b: Dictionary = _browsers[index]
	var shown: Array = b["shown"]
	if i < 0 or i >= shown.size():
		return
	render_entry(b["detail"], shown[i])
	(b["scroll"] as ScrollContainer).scroll_vertical = 0


## Select entry [param id] in browser tab [param index] (clearing its filter).
func show_entry_by_id(index: int, id: String) -> bool:
	select_tab(index)
	if not _browsers.has(index):
		return false
	var b: Dictionary = _browsers[index]
	(b["filter"] as LineEdit).text = ""
	_refresh_browser(index)
	var shown: Array = b["shown"]
	for i in shown.size():
		if String(shown[i]["id"]) == id:
			(b["list"] as ItemList).select(i)
			(b["list"] as ItemList).ensure_current_is_visible()
			_show_entry(index, i)
			return true
	return false


## Render one [CompendiumData] entry into [param detail].
func render_entry(detail: VBoxContainer, e: Dictionary) -> void:
	for c in detail.get_children():
		c.free()
	var accent: Color = e.get("color", MenuTheme.GOLD)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", MenuTheme.SP_M)
	detail.add_child(head)
	if StringName(e.get("icon", &"")) != &"":
		var icon := WeatherIcon.new(StringName(e["icon"]), accent, 40.0)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(icon)
	else:
		var gem := GroveGem.new()
		gem.color = accent
		gem.custom_minimum_size = Vector2(22, 22)
		gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(gem)
	var title := Label.new()
	title.text = String(e["title"])
	title.add_theme_font_override("font", MenuTheme.display_font(2))
	title.add_theme_font_size_override("font_size", MenuTheme.FS_HEADING + 4)
	title.add_theme_color_override("font_color", accent.lerp(MenuTheme.GOLD_LITE, 0.45))
	head.add_child(title)
	var rule := GroveRule.new()
	rule.color = accent
	rule.custom_minimum_size = Vector2(260, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail.add_child(rule)

	for block in e.get("blocks", []):
		match String(block.get("type", "")):
			"heading":
				var h := Label.new()
				h.text = String(block["text"]).to_upper()
				h.theme_type_variation = &"SectionLabel"
				h.add_theme_color_override("font_color", MenuTheme.GOLD)
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 4)
				detail.add_child(gap)
				detail.add_child(h)
			"text":
				detail.add_child(_rich(String(block["text"])))
			"bullets":
				var lines: Array[String] = []
				for item in block.get("items", []):
					lines.append("[color=#%s]◆[/color] %s" % [accent.lightened(0.2).to_html(false), String(item)])
				detail.add_child(_rich("\n".join(lines), 6))
			"fields":
				var grid := GridContainer.new()
				grid.columns = 2
				grid.add_theme_constant_override("h_separation", MenuTheme.SP_L)
				grid.add_theme_constant_override("v_separation", 4)
				detail.add_child(grid)
				for row in block.get("rows", []):
					var k := Label.new()
					k.text = String(row[0])
					k.add_theme_color_override("font_color", MUTED)
					k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
					grid.add_child(k)
					var v := _rich(String(row[1]))
					v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					grid.add_child(v)
			"table":
				detail.add_child(_table(block))


func _rich(bb: String, line_sep: int = 2) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.focus_mode = Control.FOCUS_NONE
	r.add_theme_constant_override("line_separation", line_sep)
	r.add_theme_font_size_override("normal_font_size", MenuTheme.FS_BODY)
	r.add_theme_font_size_override("bold_font_size", MenuTheme.FS_BODY)
	r.add_theme_font_override("bold_font", MenuTheme.heading_font())
	r.add_theme_color_override("default_color", MenuTheme.CREAM)
	r.meta_underlined = true
	r.text = bb.replace("[url=", "[color=#f7d68a][url=").replace("[/url]", "[/url][/color]")
	r.meta_clicked.connect(_on_meta_clicked)
	return r


func _table(block: Dictionary) -> Control:
	var cols: Array = block.get("columns", [])
	var grid := GridContainer.new()
	grid.columns = maxi(1, cols.size())
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var colors: Array = block.get("colors", [])
	var cells: Array = [cols]
	cells.append_array(block.get("rows", []))
	for r in cells.size():
		var row: Array = cells[r]
		for c in grid.columns:
			var txt := String(row[c]) if c < row.size() else ""
			var cell := PanelContainer.new()
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL if c > 0 or grid.columns > 4 else Control.SIZE_FILL
			var tint: Variant = null
			if r > 0 and r - 1 < colors.size() and c < (colors[r - 1] as Array).size():
				tint = colors[r - 1][c]
			var fill := MenuTheme.PANEL_HI if r == 0 else (MenuTheme.PANEL_SUNK if r % 2 == 1 else MenuTheme.PANEL)
			if tint is Color and c > 0:
				fill = (tint as Color).darkened(0.55)
			var sb := StyleBoxFlat.new()
			sb.bg_color = fill
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 4
			sb.content_margin_bottom = 4
			cell.add_theme_stylebox_override("panel", sb)
			var rt := _rich(txt)
			rt.custom_minimum_size = Vector2(0 if grid.columns > 4 else 110, 0)
			if r == 0 or c == 0:
				rt.text = "[b]%s[/b]" % rt.text
				if c == 0 and tint is Color and r > 0:
					rt.add_theme_color_override("default_color", (tint as Color).lightened(0.25))
				elif r == 0:
					rt.add_theme_color_override("default_color", MenuTheme.GOLD_LITE)
			if grid.columns > 4:
				rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(rt)
			grid.add_child(cell)
	return grid


func _on_list_input(index: int, e: InputEvent) -> void:
	# Right from the list moves into the detail pane (scroll it with Up / Down).
	if e.is_action_pressed(&"ui_right"):
		(_browsers[index]["scroll"] as ScrollContainer).grab_focus()
		accept_event()


func _on_scroll_input(index: int, e: InputEvent) -> void:
	var scroll: ScrollContainer = _browsers[index]["scroll"]
	if e.is_action_pressed(&"ui_down", true):
		scroll.scroll_vertical += 60
		accept_event()
	elif e.is_action_pressed(&"ui_up", true):
		scroll.scroll_vertical -= 60
		accept_event()
	elif e.is_action_pressed(&"ui_left") or e.is_action_pressed(&"ui_accept"):
		(_browsers[index]["list"] as ItemList).grab_focus()
		accept_event()


# ---------------------------------------------------------------------------
# Cross-links + global search
# ---------------------------------------------------------------------------

func _on_meta_clicked(meta) -> void:
	follow_link(String(meta))


## Follow "<section>:<id>" (CompendiumData.SECTION_* : entry id).
func follow_link(link: String) -> bool:
	var parts := link.split(":", true, 1)
	if parts.size() != 2:
		return false
	return show_section_entry(parts[0], parts[1])


func show_section_entry(section: String, id: String) -> bool:
	if section == CompendiumData.SECTION_UNITS:
		return _show_unit(id)
	for index in BROWSER_SECTIONS:
		if String(BROWSER_SECTIONS[index]) == section:
			return show_entry_by_id(int(index), id)
	return false


## Point the hosted UnitGallery at the roster unit [param id].
func _show_unit(id: String) -> bool:
	select_tab(SECTION_UNITS)
	var host: Control = _section_hosts.get(SECTION_UNITS)
	if host == null or host.get_child_count() == 0:
		return false
	var gallery = host.get_child(0)
	if not ("filtered_characters" in gallery) or not gallery.has_method("_select_index"):
		return false
	if "search_input" in gallery and gallery.search_input != null and gallery.search_input.text != "":
		gallery.search_input.text = ""
		if gallery.has_method("_apply_filters"):
			gallery._apply_filters()
	var list: Array = gallery.filtered_characters
	for i in list.size():
		if list[i] != null and String(list[i].character_id) == id:
			gallery._select_index(i)
			return true
	return false


func _on_global_search(text: String) -> void:
	_search_hits = CompendiumData.search(CompendiumData.all_entries(), text) if text.strip_edges() != "" else []
	search_results.clear()
	for e in _search_hits.slice(0, 40):
		var i := search_results.add_item("%s  ·  %s" % [String(e["title"]), _section_label(String(e["section"]))])
		search_results.set_item_custom_fg_color(i, (e["color"] as Color).lightened(0.35))
	search_results.visible = text.strip_edges() != ""
	if search_results.visible and search_results.item_count == 0:
		search_results.add_item("Nothing matches")
		search_results.set_item_disabled(0, true)


func _on_search_box_input(e: InputEvent) -> void:
	if e.is_action_pressed(&"ui_down") and search_results.visible and search_results.item_count > 0:
		search_results.grab_focus()
		search_results.select(0)
		accept_event()


func _pick_search_result(i: int) -> void:
	if i < 0 or i >= _search_hits.size():
		return
	var e: Dictionary = _search_hits[i]
	search_results.visible = false
	show_section_entry(String(e["section"]), String(e["id"]))
	tab_container.get_tab_bar().grab_focus()


func _section_label(section: String) -> String:
	match section:
		CompendiumData.SECTION_UNITS: return "Unit"
		CompendiumData.SECTION_WEATHER: return "Weather"
		CompendiumData.SECTION_TILES: return "Tile Effect"
		CompendiumData.SECTION_STATUSES: return "Status"
		CompendiumData.SECTION_RULES: return "Rules"
	return section


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	if overlay_mode:
		close()
		return
	MenuNav.change_scene(self, "res://menus/MainMenu.tscn")


## Close the overlay (overlay mode only).
func close() -> void:
	if not is_inside_tree():
		return
	visible = false
	closed.emit()


## Back / Esc: leave a text field first, then close / go back.
func handle_back() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and is_ancestor_of(focus):
		(focus as LineEdit).release_focus()
		if focus == search_box:
			search_results.visible = false
		tab_container.get_tab_bar().grab_focus()
		return
	_on_back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_next_event(event) or MenuNav.is_prev_event(event):
		var step := 1 if MenuNav.is_next_event(event) else -1
		var n := tab_container.get_tab_count()
		tab_container.current_tab = posmod(tab_container.current_tab + step, n)
		get_viewport().set_input_as_handled()
		return
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		handle_back()


## Overlay-only: consumes Back / Esc before the hosted galleries see it (their own
## Esc handlers change scene to the main menu, which must never happen mid-battle).
class _BackCatcher:
	extends Node
	var target: Compendium
	func _input(event: InputEvent) -> void:
		if target == null or not is_instance_valid(target) or not target.visible:
			return
		if MenuNav.is_back_event(event) or (event is InputEventKey and event.pressed \
				and not event.echo and (event as InputEventKey).keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			target.handle_back()
