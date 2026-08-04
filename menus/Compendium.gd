extends Control

class_name Compendium

# Compendium - the single in-game reference, replacing the three separate
# gallery entry points on the main menu.
#
# SHELL, NOT A REWRITE. The Units / Tiles / Maps sections are the EXISTING
# UnitGallery, TileGallery and MapGallery scenes instantiated into a host each.
# They are full-rect Controls that build their own UI, so hosting them costs
# nothing beyond an add_child() and keeps every bit of work already done on them
# intact. Only the Statuses section is built here; Weather is a stub.
#
# SIDEBAR NAV, NOT STOCK TABS. The shell is a slim vertical nav rail (brand title,
# a flat button per section with a live count badge, a Back button at the foot)
# beside a content host. The stock TabContainer is gone -- it read as default
# Godot, which is exactly the "clunky" the redesign is retiring.
#
# LAZY HOSTING. Each section starts as an empty host Control and its scene is
# instantiated the first time that section is shown (see _ensure_section). Three
# galleries eagerly spinning up their 3D SubViewports at once is pure waste when
# the player only ever looks at one at a time.
#
# INPUT OWNERSHIP. The hosted galleries each handle _input themselves (ESC to
# leave, arrows to page the dex, F5 to refresh). A hidden section is still in the
# tree and would still react, so input processing is enabled ONLY on the section
# currently on screen (see _sync_section_input).

## Section index -> nav title. Order here IS the nav order.
const SECTION_TITLES: Array[String] = ["Units", "Tiles", "Maps", "Statuses", "Elements", "Weather"]

const SECTION_UNITS := 0
const SECTION_TILES := 1
const SECTION_MAPS := 2
const SECTION_STATUSES := 3
const SECTION_ELEMENTS := 4
const SECTION_WEATHER := 5

## Hosted gallery scenes, by section index. Sections absent from this map are
## built in code by this script (Statuses, Weather).
const HOSTED_SCENES: Dictionary = {
	SECTION_UNITS: "res://menus/UnitGallery.tscn",
	SECTION_TILES: "res://menus/TileGallery.tscn",
	SECTION_MAPS: "res://menus/MapGallery.tscn",
	SECTION_ELEMENTS: "res://menus/ElementChartGallery.tscn",
}

## Where map resources live, for the Maps count badge (MapGallery owns loading).
const MAPS_DIR := "res://game/maps/resources/"

const MUTED := Color(0.72, 0.70, 0.78)

# --- Shell ---
var content_host: Control
var back_button: Button

## Host Control per section index; the section's content is added under it.
var _section_hosts: Dictionary = {}
## Section indices already populated, so a section is only built once.
var _built_sections: Dictionary = {}
## Nav rail button + count badge per section index, for active-state restyling.
var _nav_buttons: Dictionary = {}
var _nav_badges: Dictionary = {}
## Section currently on screen.
var _current_section: int = SECTION_UNITS

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


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuTheme.apply_backdrop(self)

	var shell := HBoxContainer.new()
	shell.name = "Shell"
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_constant_override("separation", 0)
	add_child(shell)

	shell.add_child(_build_nav_rail())

	# Content host: the galleries mount here full-rect and only the active one is
	# shown. clip_contents keeps a stray oversized child from bleeding over the rail.
	content_host = Control.new()
	content_host.name = "ContentHost"
	content_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_host.clip_contents = true
	shell.add_child(content_host)

	for i in SECTION_TITLES.size():
		var host := Control.new()
		host.name = SECTION_TITLES[i]
		host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.visible = false
		content_host.add_child(host)
		_section_hosts[i] = host

	# Populate + show whichever section opens first; the rest wait until shown.
	_show_section(_current_section)


func _build_nav_rail() -> PanelContainer:
	var rail := PanelContainer.new()
	rail.name = "NavRail"
	rail.custom_minimum_size = Vector2(216, 0)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	rail.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var brand := Label.new()
	brand.text = "COMPENDIUM"
	brand.add_theme_font_size_override("font_size", MenuTheme.FONT_DISPLAY)
	brand.add_theme_color_override("font_color", MenuTheme.GOLD)
	col.add_child(brand)

	var subtitle := Label.new()
	subtitle.text = "Field reference"
	subtitle.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	subtitle.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(subtitle)

	col.add_child(_rail_spacer(10))

	for i in SECTION_TITLES.size():
		col.add_child(_build_nav_entry(i))

	# Push the Back button to the foot of the rail.
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)

	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK"
	# >=44px hit target (touch-readiness).
	back_button.custom_minimum_size = Vector2(0, 44)
	back_button.pressed.connect(_on_back_pressed)
	col.add_child(back_button)

	return rail


func _rail_spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


## One full-width nav entry: a flat button carrying the section name, with a small
## right-aligned count badge overlaid inside it.
func _build_nav_entry(index: int) -> Button:
	var btn := Button.new()
	btn.name = "Nav_" + SECTION_TITLES[index]
	btn.text = SECTION_TITLES[index]
	btn.theme_type_variation = "NavButton"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# >=44px hit target (touch-readiness).
	btn.custom_minimum_size = Vector2(0, 44)
	btn.pressed.connect(_show_section.bind(index))

	# Count badge, right-aligned, non-interactive so clicks fall through to the
	# button. Full-rect with a right inset places the glyphs at the right edge; the
	# button's own left-aligned label never collides with it.
	var badge := Label.new()
	badge.name = "Badge"
	badge.text = _section_badge_text(index)
	badge.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	badge.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	badge.offset_right = -14
	btn.add_child(badge)

	_nav_buttons[index] = btn
	_nav_badges[index] = badge
	return btn


## Live count shown on a section's nav badge. Weather has nothing to browse yet,
## so it reads "SOON" rather than "0".
func _section_badge_text(index: int) -> String:
	match index:
		SECTION_UNITS:
			return str(CharacterLibrary.all_ids().size())
		SECTION_TILES:
			return str(TileCatalog.all_paths().size())
		SECTION_MAPS:
			return str(_count_maps())
		SECTION_STATUSES:
			return str(StatusCatalog.all_paths().size())
		SECTION_ELEMENTS:
			# Read live off the chart resource, like every other badge here -- an
			# element authored during the content phase counts itself.
			return str(ElementChartGallery.elements().size())
		SECTION_WEATHER:
			return "SOON"
	return ""


## Cheap count of map resources for the badge, without loading them all (that is
## MapGallery's job when the section is actually opened).
func _count_maps() -> int:
	var count: int = 0
	var dir := DirAccess.open(MAPS_DIR)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			count += 1
		file_name = dir.get_next()
	dir.list_dir_end()
	return count


## Make [param index] the visible section: toggle host visibility, restyle the nav
## rail (active button + brighter badge), build the section on first view, and move
## input ownership to it.
func _show_section(index: int) -> void:
	if index < 0 or index >= SECTION_TITLES.size():
		return
	_current_section = index

	for key in _section_hosts:
		var host: Control = _section_hosts[key] as Control
		if host != null:
			host.visible = (int(key) == index)

	for key in _nav_buttons:
		var btn: Button = _nav_buttons[key] as Button
		if btn != null:
			btn.theme_type_variation = "NavButtonActive" if int(key) == index else "NavButton"

	for key in _nav_badges:
		var badge: Label = _nav_badges[key] as Label
		if badge != null:
			var col: Color = MenuTheme.GOLD if int(key) == index else MenuTheme.CREAM_DIM
			badge.add_theme_color_override("font_color", col)

	_ensure_section(index)
	_sync_section_input()


## Build section [param index] if it has not been built yet. Every failure mode
## degrades to a placeholder inside that one section -- a gallery scene that will
## not load must never take the whole Compendium down with it.
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


## Enable _input only on the section currently on screen. Hidden sections stay in
## the tree, and a hidden gallery still receiving key events would page a dex nobody
## is looking at -- or fire a second ESC handler.
func _sync_section_input() -> void:
	for key in _section_hosts:
		var index: int = int(key)
		var host: Control = _section_hosts[key] as Control
		if host == null:
			continue
		for child in host.get_children():
			child.set_process_input(index == _current_section)
			child.set_process_unhandled_input(index == _current_section)


# ---------------------------------------------------------------------------
# Statuses section
# ---------------------------------------------------------------------------

func _build_statuses_section(host: Control) -> void:
	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_top", 24)
	outer.add_theme_constant_override("margin_bottom", 24)
	host.add_child(outer)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	outer.add_child(split)

	# Left: search + list.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)

	var heading := Label.new()
	heading.text = "STATUSES"
	heading.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	heading.add_theme_color_override("font_color", MenuTheme.GOLD)
	left.add_child(heading)

	status_search = LineEdit.new()
	status_search.placeholder_text = "Search statuses..."
	status_search.text_changed.connect(_on_status_search_changed)
	left.add_child(status_search)

	status_list = ItemList.new()
	status_list.custom_minimum_size = Vector2(260, 400)
	status_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	status_list.item_selected.connect(_on_status_selected)
	left.add_child(status_list)

	# Right: detail pane inside a deep translucent panel, in a scroll so long tick
	# lists stay reachable.
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(detail_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(scroll)

	status_detail = VBoxContainer.new()
	status_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_detail.add_theme_constant_override("separation", 8)
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

	# Each row is tinted with the status's own StatusVisuals colour, so the list
	# reads as buff/debuff at a glance without needing a separate swatch column.
	for status in filtered_statuses:
		var idx: int = status_list.add_item(_status_title(status))
		var info: Dictionary = StatusVisuals.info_for(status)
		var col: Color = info.get("color", MenuTheme.CREAM)
		status_list.set_item_custom_fg_color(idx, col)


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

	var info: Dictionary = StatusVisuals.info_for(status)
	var accent: Color = info.get("color", MenuTheme.GOLD)

	# Name + kind chip.
	var name_label := Label.new()
	name_label.text = _status_title(status)
	name_label.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	name_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	status_detail.add_child(name_label)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 8)
	status_detail.add_child(meta_row)

	meta_row.add_child(MenuTheme.make_chip(String(info.get("kind", "neutral")).capitalize(), accent))

	var id_text: String = String(status.id) if not String(status.id).is_empty() else "(no id)"
	var id_label := Label.new()
	id_label.text = id_text
	id_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	id_label.modulate = MUTED
	id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta_row.add_child(id_label)

	# One-line summary of what it does.
	var summary: String = StatusVisuals.describe_condition(status)
	if not summary.is_empty():
		var summary_label := Label.new()
		summary_label.text = summary
		summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
		status_detail.add_child(summary_label)

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
			effect_label.text = "- " + line
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
			flag_label.text = "- " + line
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
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var key_label := Label.new()
	key_label.text = label_text + ":"
	key_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	key_label.modulate = MUTED
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value_text
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)


func _add_heading(parent: VBoxContainer, text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	parent.add_child(spacer)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	label.add_theme_color_override("font_color", MenuTheme.GOLD)
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

## Weather is designed but not implemented, so this section exists to say so, as an
## intentional "coming soon" card rather than a bare label.
##
## TO A FUTURE IMPLEMENTER: weather is a SECTION, not a restructure. Once weather
## resources exist:
##   1. Add a WeatherCatalog next to StatusCatalog (same recursive-scan +
##      index-by-id shape) so discovery survives the assets being refiled.
##   2. Replace the body of this function with the browser -- a search box, an
##      ItemList and a detail pane, exactly like _build_statuses_section, which
##      is the closest template.
## Nothing outside this function needs to change: the nav entry, its badge, its
## lazy instantiation and its input gating are all already wired.
func _build_weather_section(host: Control) -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	pad.add_theme_constant_override("margin_top", 28)
	pad.add_theme_constant_override("margin_bottom", 28)
	card.add_child(pad)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pad.add_child(box)

	var title := Label.new()
	title.text = "WEATHER"
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var badge_row := CenterContainer.new()
	box.add_child(badge_row)
	badge_row.add_child(MenuTheme.make_chip("COMING SOON", MenuTheme.CREAM_DIM))

	var body := Label.new()
	body.text = "Weather is planned but not yet implemented.\nThere is nothing to browse here yet."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	body.modulate = MUTED
	box.add_child(body)


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _switch_section(step: int) -> void:
	_show_section(posmod(_current_section + step, SECTION_TITLES.size()))


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.echo:
		return

	# While a text field (a gallery / status search box) is focused, digits and
	# arrows belong to the field, not the nav -- otherwise typing "2" would jump
	# sections. ESC still defocuses it first.
	var focus_owner := get_viewport().gui_get_focus_owner()
	var typing: bool = focus_owner is LineEdit

	if key_event.keycode == KEY_ESCAPE:
		if typing:
			(focus_owner as LineEdit).release_focus()
			get_viewport().set_input_as_handled()
			return
		# The shell's single ESC leaves the Compendium. A hosted gallery on screen
		# keeps its own ESC (which leaves too), and hidden ones have input disabled,
		# so ESC always means exactly "leave".
		_on_back_pressed()
		return

	if typing:
		return

	# 1-9 jump straight to a section; Up/Down cycle. Galleries use Left/Right for
	# their pager, so these never collide. The range is the DIGIT ROW, not the
	# section count -- the bounds check below is what keeps it honest, so adding a
	# section never needs this line edited again.
	if key_event.keycode >= KEY_1 and key_event.keycode <= KEY_9:
		var target: int = key_event.keycode - KEY_1
		if target < SECTION_TITLES.size():
			_show_section(target)
			get_viewport().set_input_as_handled()
		return

	match key_event.keycode:
		KEY_UP:
			_switch_section(-1)
			get_viewport().set_input_as_handled()
		KEY_DOWN:
			_switch_section(1)
			get_viewport().set_input_as_handled()
