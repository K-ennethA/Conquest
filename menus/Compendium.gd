extends Control

class_name Compendium

# Compendium - the single in-game reference, replacing the three separate
# gallery entry points on the main menu.
#
# SHELL, NOT A REWRITE. The Units / Tiles / Maps sections are the EXISTING
# UnitGallery, TileGallery and MapGallery scenes instantiated into a tab each.
# They are full-rect Controls that build their own UI, so hosting them costs
# nothing beyond an add_child() and keeps every bit of work already done on them
# intact. Only the Statuses section is built here; Weather is a stub.
#
# LAZY HOSTING. Each tab starts as an empty host Control and its scene is
# instantiated the first time that tab is shown (see _ensure_section). Three
# galleries eagerly spinning up their 3D SubViewports at once is pure waste when
# the player only ever looks at one at a time.
#
# INPUT OWNERSHIP. The hosted galleries each handle _input themselves (ESC to
# leave, arrows to page the dex, F5 to refresh). A hidden tab is still in the
# tree and would still react, so input processing is enabled ONLY on the section
# currently on screen (see _sync_section_input).

## Section index -> tab title. Order here IS the tab order.
const SECTION_TITLES: Array[String] = ["Units", "Tiles", "Maps", "Statuses", "Weather"]

const SECTION_UNITS := 0
const SECTION_TILES := 1
const SECTION_MAPS := 2
const SECTION_STATUSES := 3
const SECTION_WEATHER := 4

## Hosted gallery scenes, by section index. Sections absent from this map are
## built in code by this script (Statuses, Weather).
const HOSTED_SCENES: Dictionary = {
	SECTION_UNITS: "res://menus/UnitGallery.tscn",
	SECTION_TILES: "res://menus/TileGallery.tscn",
	SECTION_MAPS: "res://menus/MapGallery.tscn",
}

const MUTED := Color(0.72, 0.70, 0.78)

# --- Shell ---
var tab_container: TabContainer
var back_button: Button

## Host Control per section index; the section's content is added under it.
var _section_hosts: Dictionary = {}
## Section indices already populated, so a tab is only built once.
var _built_sections: Dictionary = {}

# --- Statuses section ---
var status_list: ItemList
var status_search: LineEdit
var status_detail: VBoxContainer
var status_empty_label: Label

var all_statuses: Array[StatusCondition] = []
var filtered_statuses: Array[StatusCondition] = []


func _ready() -> void:
	theme = MenuTheme.build()  # dark Legends-style menu look
	_build_shell()
	# Populate whichever tab opens first; the rest wait until they are shown.
	_ensure_section(tab_container.current_tab)
	_sync_section_input()


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = MenuTheme.DARK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Header: ONE title and ONE back button for the whole reference. The hosted
	# galleries' own BACK buttons are hidden in _ensure_section so the shell does
	# not stack three of them down the left edge.
	var header := HBoxContainer.new()
	header.name = "Header"
	root.add_child(header)

	var title := Label.new()
	title.text = "COMPENDIUM"
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = MenuTheme.GOLD
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(80, 40)
	back_button.pressed.connect(_on_back_pressed)
	header.add_child(back_button)

	tab_container = TabContainer.new()
	tab_container.name = "Sections"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tab_container)

	for i in SECTION_TITLES.size():
		var host := Control.new()
		host.name = SECTION_TITLES[i]
		host.size_flags_vertical = Control.SIZE_EXPAND_FILL
		host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_container.add_child(host)
		tab_container.set_tab_title(i, SECTION_TITLES[i])
		_section_hosts[i] = host

	tab_container.tab_changed.connect(_on_tab_changed)


func _on_tab_changed(tab: int) -> void:
	_ensure_section(tab)
	_sync_section_input()


## Build section [param index] if it has not been built yet. Every failure mode
## degrades to a placeholder inside that one tab -- a gallery scene that will not
## load must never take the whole Compendium down with it.
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

	match index:
		SECTION_STATUSES:
			_build_statuses_section(host)
		SECTION_WEATHER:
			_build_weather_section(host)
		_:
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

	# The gallery builds its UI (and its BACK button) in _ready, which has now
	# run. Hide that button: the shell supplies the single back control. Guarded
	# by a property check so a gallery that stops exposing back_button, or names
	# it differently, simply keeps its own button rather than erroring.
	if "back_button" in gallery:
		var gallery_back = gallery.get("back_button")
		if gallery_back is Button:
			(gallery_back as Button).visible = false


func _add_placeholder(host: Control, message: String) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(center)

	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = MUTED
	center.add_child(label)


## Enable _input only on the section currently on screen. Hidden tabs stay in the
## tree, and a hidden gallery still receiving key events would page a dex nobody
## is looking at -- or fire a second ESC handler.
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
# Statuses section
# ---------------------------------------------------------------------------

func _build_statuses_section(host: Control) -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(split)

	# Left: search + list.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	split.add_child(left)

	var search_label := Label.new()
	search_label.text = "Search:"
	left.add_child(search_label)

	status_search = LineEdit.new()
	status_search.placeholder_text = "Search statuses..."
	status_search.text_changed.connect(_on_status_search_changed)
	left.add_child(status_search)

	var list_label := Label.new()
	list_label.text = "Statuses:"
	left.add_child(list_label)

	status_list = ItemList.new()
	status_list.custom_minimum_size = Vector2(260, 400)
	status_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_list.item_selected.connect(_on_status_selected)
	left.add_child(status_list)

	# Right: detail pane, inside a scroll so long tick lists stay reachable.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	status_detail = VBoxContainer.new()
	status_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(status_detail)

	status_empty_label = Label.new()
	status_empty_label.text = "Select a status to see what it does."
	status_empty_label.modulate = MUTED
	status_detail.add_child(status_empty_label)

	_load_all_statuses()


func _load_all_statuses() -> void:
	all_statuses.clear()
	for status in StatusCatalog.all_statuses():
		if status != null:
			all_statuses.append(status)
	_apply_status_filter()


func _apply_status_filter() -> void:
	filtered_statuses.clear()

	var search_text: String = ""
	if status_search != null:
		search_text = status_search.text.strip_edges().to_lower()

	for status in all_statuses:
		if status == null:
			continue
		if search_text.is_empty():
			filtered_statuses.append(status)
			continue
		var haystack: String = "%s %s" % [status.display_name, String(status.id)]
		if haystack.to_lower().contains(search_text):
			filtered_statuses.append(status)

	filtered_statuses.sort_custom(_compare_status_names)
	_update_status_list()


func _compare_status_names(a: StatusCondition, b: StatusCondition) -> bool:
	return _status_title(a).naturalnocasecmp_to(_status_title(b)) < 0


## Best available human label for a condition: authored name, else its id, else
## a clear stand-in. Never returns an empty string, so no list row is blank.
func _status_title(status: StatusCondition) -> String:
	if status == null:
		return "(unknown status)"
	if not status.display_name.strip_edges().is_empty():
		return status.display_name
	if not String(status.id).is_empty():
		return String(status.id)
	return "(unnamed status)"


func _update_status_list() -> void:
	if status_list == null:
		return
	status_list.clear()

	if filtered_statuses.is_empty():
		var message: String = "No statuses found"
		if all_statuses.is_empty():
			message = "No statuses authored yet"
		status_list.add_item(message)
		status_list.set_item_disabled(0, true)
		return

	for status in filtered_statuses:
		status_list.add_item(_status_title(status))


func _on_status_search_changed(_new_text: String) -> void:
	_apply_status_filter()


func _on_status_selected(index: int) -> void:
	if index < 0 or index >= filtered_statuses.size():
		return
	_display_status(filtered_statuses[index])


func _display_status(status: StatusCondition) -> void:
	if status_detail == null:
		return

	for child in status_detail.get_children():
		child.queue_free()
	status_empty_label = null

	if status == null:
		_add_muted(status_detail, "This status could not be read.")
		return

	# Name + id.
	var name_label := Label.new()
	name_label.text = _status_title(status)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.modulate = MenuTheme.GOLD
	status_detail.add_child(name_label)

	var id_label := Label.new()
	id_label.text = String(status.id) if not String(status.id).is_empty() else "(no id)"
	id_label.add_theme_font_size_override("font_size", 12)
	id_label.modulate = MUTED
	status_detail.add_child(id_label)

	# Duration + stacking.
	_add_field(status_detail, "Duration", _duration_text(status))
	_add_field(status_detail, "Stacking", _stacking_text(status.stacking))

	# What it does each turn.
	_add_heading(status_detail, "Each turn:")
	var tick_lines: Array[String] = _tick_descriptions(status)
	if tick_lines.is_empty():
		_add_muted(status_detail, "No effects")
	else:
		for line in tick_lines:
			var effect_label := Label.new()
			effect_label.text = "• " + line
			effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status_detail.add_child(effect_label)

	# Standing rules imposed while active.
	_add_heading(status_detail, "While active:")
	var flag_lines: Array[String] = _rule_flag_descriptions(status)
	if flag_lines.is_empty():
		_add_muted(status_detail, "No flags")
	else:
		for line in flag_lines:
			var flag_label := Label.new()
			flag_label.text = "• " + line
			flag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			status_detail.add_child(flag_label)


## Player-readable duration. A condition authored as permanent (duration <= 0,
## canonically -1) never expires on its own and must not read as "0 turns".
func _duration_text(status: StatusCondition) -> String:
	if status == null:
		return "Unknown"
	var turns: int = status.duration_turns
	if turns <= 0:
		return "Permanent (never expires on its own)"
	if turns == 1:
		return "1 turn"
	return "%d turns" % turns


## Readable label for the stacking enum. Written as an explicit match rather than
## indexing Stacking.keys() so reordering or inserting an enum value cannot
## silently relabel every status in the list.
func _stacking_text(stacking: int) -> String:
	match stacking:
		StatusCondition.Stacking.REFRESH:
			return "Refreshes - reapplying resets the timer"
		StatusCondition.Stacking.STACK:
			return "Stacks - reapplying adds a second instance"
		StatusCondition.Stacking.IGNORE:
			return "Ignored - reapplying does nothing while it is active"
		_:
			return "Unknown"


## One description per tick effect, skipping nulls and effects with nothing to
## say so the list never shows blank bullets.
func _tick_descriptions(status: StatusCondition) -> Array[String]:
	var lines: Array[String] = []
	if status == null:
		return lines
	for effect in status.tick_effects:
		if effect == null:
			continue
		if not effect.has_method("describe"):
			continue
		var text: String = String(effect.describe()).strip_edges()
		if text.is_empty():
			continue
		lines.append(text)
	return lines


## Rule flags phrased for a player rather than dumped as a raw dictionary.
## Only flags that are actually ON are listed -- a flag explicitly set false is
## the same as absent, and saying "Cannot move: false" helps nobody.
##
## `rule_flags` is checked with `in` rather than assumed, so this keeps working
## against a StatusCondition build that predates the property.
func _rule_flag_descriptions(status: StatusCondition) -> Array[String]:
	var lines: Array[String] = []
	if status == null:
		return lines
	if not ("rule_flags" in status):
		return lines
	var flags = status.get("rule_flags")
	if not (flags is Dictionary):
		return lines
	for key in (flags as Dictionary):
		if not bool((flags as Dictionary)[key]):
			continue
		lines.append(_rule_flag_text(String(key)))
	lines.sort()
	return lines


## Known flags get authored wording; anything new falls back to a humanised key
## so a flag added by content authoring still reads as a sentence.
func _rule_flag_text(flag: String) -> String:
	match flag:
		"immobilized":
			return "Cannot move"
		"untargetable":
			return "Cannot be targeted by moves"
		"fortified":
			return "Takes reduced damage"
		_:
			return flag.replace("_", " ").capitalize()


func _add_field(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var key_label := Label.new()
	key_label.text = label_text + ":"
	key_label.modulate = MUTED
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)


func _add_heading(parent: VBoxContainer, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	parent.add_child(spacer)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = MenuTheme.GOLD
	parent.add_child(label)


func _add_muted(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.modulate = MUTED
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


# ---------------------------------------------------------------------------
# Weather section (placeholder)
# ---------------------------------------------------------------------------

## Weather is designed but not implemented, so this tab exists to say so rather
## than to be missing.
##
## TO A FUTURE IMPLEMENTER: weather is a SECTION, not a restructure. Once weather
## resources exist:
##   1. Add a WeatherCatalog next to StatusCatalog (same recursive-scan +
##      index-by-id shape) so discovery survives the assets being refiled.
##   2. Replace the body of this function with the browser -- a search box, an
##      ItemList and a detail pane, exactly like _build_statuses_section, which
##      is the closest template.
## Nothing outside this function needs to change: the tab, its title, its lazy
## instantiation and its input gating are all already wired.
func _build_weather_section(host: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(center)

	var box := VBoxContainer.new()
	center.add_child(box)

	var title := Label.new()
	title.text = "WEATHER"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = MenuTheme.GOLD
	box.add_child(title)

	var body := Label.new()
	body.text = "Weather is planned but not yet implemented.\nThere is nothing to browse here yet."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.modulate = MUTED
	box.add_child(body)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return
	# Only the shell's own ESC is handled here. A hosted gallery on screen keeps
	# its own ESC (which leaves to the main menu too), and hidden ones have had
	# input disabled, so ESC always means exactly "leave the Compendium".
	if key_event.keycode == KEY_ESCAPE:
		if status_search != null and status_search.has_focus():
			status_search.release_focus()
			return
		_on_back_pressed()
