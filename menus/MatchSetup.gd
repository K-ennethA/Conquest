extends Control

class_name MatchSetup

## Unified pre-battle SETUP screen. Replaces the old TurnSystemSelection + MapSelection +
## ArenaSetupScreen as three separate steps with one screen: a map list + preview on the
## LEFT and a reusable [MatchConfigPanel] config column on the RIGHT. What the Start button
## launches depends on [member requested_mode], set by the caller before it changes here:
##
##   * [constant MatchConfigPanel.MODE_SKIRMISH] -- Solo vs AI. Map + Turn System + AI
##       Difficulty. Start stages the map and goes to Character Select (which loads the
##       battle itself), exactly as MapSelection did.
##   * [constant MatchConfigPanel.MODE_ARENA]    -- Solo roguelite. Turn System + Run Length.
##       The map list is hidden (Arena picks its own compact maps each round); Start
##       duplicates arena_solo.tres, writes rounds + turn system, and stages the run on
##       ArenaController before going to Character Select, exactly as ArenaSetupScreen did.
##   * [constant MatchConfigPanel.MODE_LOCAL]    -- Local hot-seat versus. Map + Turn System.
##       Start stages the map and goes to Character Select.
##   * [constant MatchConfigPanel.MODE_SIEGE] / [constant MatchConfigPanel.MODE_SIEGE_LOCAL]
##       -- Siege, solo vs AI / hot-seat. Exactly the two above in every respect except one:
##       the list opens PRESELECTED on the mode's own lane/base map when the catalog
##       actually lists one (see [method _preferred_row]). Nothing is filtered out -- Siege
##       on a small skirmish map is a legal, if short, match, and a picker that hid every
##       map but one would be a launcher wearing a list.
##
## The mode is carried in a STATIC var so it survives the scene change AND a Back trip from
## Character Select (which returns here without re-picking the mode). Every dependency is
## null-guarded; a missing autoload or ruleset shows an inline message instead of crashing.

const BASE_RULESET_PATH := "res://game/arena/rulesets/arena_solo.tres"
const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const SOLO_MODE_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"
const MP_MODE_SELECT_SCENE := "res://menus/MultiplayerModeSelection.tscn"
## Where "Get more maps" goes, and where it comes BACK to (this screen), so a map downloaded
## for this match is one Back press away from the list it was fetched for.
const COMMUNITY_BROWSE_SCENE := "res://menus/CommunityBrowse.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"

## The shared row model: what the badges say, how the list is ordered, and which rows are
## refused. Preloaded BY PATH, not by class_name -- a brand new script is not in the global
## class cache until the project is next imported (the `menus/ReplayWatch.gd` rule).
const MapRowBuilder := preload("res://menus/MapRowBuilder.gd")

## Where the Siege mode controller lives when this build ships it. Tried in order, by PATH
## with a has-method guard, exactly as [MapRowBuilder] resolves the map catalog: the mode is
## built by a parallel workstream and this screen must parse and run in a build that does
## not ship it yet. Its `recommended_map_path()` is the AUTHORITY on which map Siege opens
## on; [method _siege_shaped_row] is the fallback for a build that has the map but not (yet)
## the controller.
const SIEGE_CONTROLLER_PATHS: Array[String] = [
	"res://game/modes/SiegeController.gd",
	"res://game/modes/siege/SiegeController.gd",
]
## The second probe: the controller as a member of this group, which is also the seam a UI
## test injects a stand-in through. Same pair [SiegeFeedback] resolves it with.
const SIEGE_CONTROLLER_GROUP: StringName = &"siege_controller"

## What a map has to say about itself to read as a SIEGE map, in the absence of a controller
## to ask. Any ONE of these is enough:
##   * map_type == "Siege" (the catalog's own classification), or
##   * a tag "siege", or
##   * an authored victory condition naming a base CAPTURE -- which is the CaptureBase
##     objective's own string, i.e. the same text WinConditionLibrary compiles and the
##     objective banner draws. Matched on both words rather than an exact phrase, for the
##     reason WinConditionLibrary.build_one matches "destroy"+"base" that way.
const SIEGE_MAP_TYPE: String = "siege"
const SIEGE_TAG: String = "siege"

## The variant to build, set by the caller (SoloModeSelect / MultiplayerModeSelection)
## before change_scene. Static so it persists across the scene load and a Back trip from
## Character Select. Defaults to Skirmish so the screen is never left in an undefined mode.
## (Value literal rather than MatchConfigPanel.MODE_SKIRMISH so this static initializer
## never depends on another class's load order.)
static var requested_mode: String = "skirmish"

var _mode: String = MatchConfigPanel.MODE_SKIRMISH

# --- Map data (ported from MapSelection) ------------------------------------
## Parallel arrays, one entry per LIST ROW and in the list's own order: the path, the loaded
## resource (null when the library lists a map this build cannot read), and the row model
## that decided its badge. Index-aligned with `_map_list` -- rebuilt together, always.
var _available_maps: Array[String] = []
var _map_resources: Array[MapResource] = []
var _map_rows: Array = []
var _current_selected_map: String = ""

# --- Live node refs ---------------------------------------------------------
var _map_list: ItemList = null
var _map_name_label: Label = null
## Holder for the preview card's source chip (CUSTOM / COMMUNITY). An ItemList row is text
## only, so this is where the real themed chip lives; the row itself carries the bracketed
## text badge.
var _map_source_slot: HBoxContainer = null
var _map_minimap: TextureRect = null
var _minimap_placeholder: Label = null
var _map_desc_label: Label = null
var _map_details_label: Label = null

## Cache of rendered minimap textures keyed by map path, so re-selecting a map (or
## returning to it) never re-renders. Cheap to build, but the cache avoids redundant
## tile-resource loads (see [MapPreview]).
var _minimap_cache: Dictionary = {}
var _config_panel: MatchConfigPanel = null
var _start_btn: Button = null
var _message_label: Label = null


func _ready() -> void:
	_mode = requested_mode
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()
	if _uses_map_list():
		_load_available_maps()
	# The Get-more-maps round trip is a SCENE CHANGE, so coming back re-runs `_ready` above
	# and the new download is already listed. This covers the other shape -- a build (or a
	# test) that keeps one MatchSetup alive and hides it -- for the price of one connection.
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if visible and _uses_map_list():
		refresh_map_list()


func _uses_map_list() -> bool:
	return _mode != MatchConfigPanel.MODE_ARENA


func _title_text() -> String:
	match _mode:
		MatchConfigPanel.MODE_ARENA:
			return "ARENA RUN"
		MatchConfigPanel.MODE_LOCAL:
			return "LOCAL VERSUS"
		MatchConfigPanel.MODE_SIEGE:
			return "SIEGE"
		MatchConfigPanel.MODE_SIEGE_LOCAL:
			return "LOCAL SIEGE"
		_:
			return "SKIRMISH"


## True when this screen is setting up a hot-seat match, i.e. Back goes to the VERSUS mode
## picker rather than the SOLO one.
func _is_hotseat() -> bool:
	return _mode == MatchConfigPanel.MODE_LOCAL or _mode == MatchConfigPanel.MODE_SIEGE_LOCAL


# --- UI construction --------------------------------------------------------
#
# 720p BUDGET, and what the community-map work did to it: NOTHING. The three additions are
# all height-neutral, so the floors below (list 168, minimap 150, details scroll 96) are the
# same arithmetic they were:
#   * the source CHIP shares the preview card's name line -- caption font (12) + 2/2 padding
#     ~= 20px against the 20pt name label's ~27, and it is SHRINK_CENTER, so the row is still
#     the label's height;
#   * the row BADGE is text inside the existing ItemList -- an ItemList row's height comes
#     from the font, not from the string, and the text is ellipsised, not wrapped;
#   * "Source:" is one more line inside the details ScrollContainer, which scrolls in place;
#   * "Get More Maps" (48 tall) joins a footer row whose height is already the 52 of Start.
# The page keeps exactly ONE EXPAND_FILL region per column (main -> the map list on the left,
# the config panel on the right), and the footer stays pinned as the page's last child.

func _build_ui() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 24.0
	page.offset_right = -24.0
	page.offset_top = 24.0
	page.offset_bottom = -24.0
	page.add_theme_constant_override("separation", 12)
	add_child(page)

	var title := Label.new()
	title.text = _title_text()
	page.add_child(title)
	MenuTheme.style_title(title, 34)

	var subtitle := Label.new()
	subtitle.text = "Configure your match, then begin"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	page.add_child(main)

	main.add_child(_build_left_pane())
	main.add_child(_build_right_pane())

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", Color("d87a4a"))
	_message_label.visible = false
	page.add_child(_message_label)

	page.add_child(_build_actions())


## LEFT: map list + preview for map modes; a read-only note for Arena.
func _build_left_pane() -> Control:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.58
	left.add_theme_constant_override("separation", 8)

	if not _uses_map_list():
		var note_panel := PanelContainer.new()
		note_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var note := Label.new()
		note.text = "Arena picks its own compact maps\neach round.\n\nDraft augments between fights and\nsurvive as long as you can."
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		note_panel.add_child(note)
		left.add_child(note_panel)
		return left

	var list_label := Label.new()
	list_label.text = "AVAILABLE MAPS"
	MenuTheme.style_section_header(list_label)
	left.add_child(list_label)

	_map_list = ItemList.new()
	# Guaranteed height so the list always shows several rows and scrolls within
	# itself, no matter how tall the preview card below grows -- was crushed to
	# near-zero because the preview card competed for the same 0.5 stretch share.
	# 168 not 190: the pane's fixed minimums were arithmetic-tight at exactly 720p
	# under conservative font metrics; ~4.5 visible rows still reads fine and the
	# EXPAND_FILL ratio grows the list on any taller window.
	_map_list.custom_minimum_size = Vector2(0.0, 168.0)
	_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_list.size_flags_stretch_ratio = 1.0
	# Padded, card-like rows: extra breathing room between items and a distinct
	# left-accented selected/hover fill (theme overrides only -- the widget stays
	# a stock ItemList per the no-rebuild rule).
	_map_list.add_theme_constant_override("v_separation", 8)
	_map_list.add_theme_constant_override("icon_margin", 8)
	_map_list.item_selected.connect(_on_map_selected)
	_map_list.item_activated.connect(_on_map_activated)
	left.add_child(_map_list)

	# No EXPAND_FILL / stretch ratio here on purpose: the preview card is left at its
	# natural (bounded) minimum size instead of competing with the map list for extra
	# space, so a long description can never push it -- and the action row below it --
	# taller than the screen. The description + details are scrolled internally instead
	# (see below); only that inner ScrollContainer's min size feeds into this card's height.
	var preview := PanelContainer.new()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	preview.add_child(margin)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	margin.add_child(pv)

	# Name + source chip on ONE line. The chip is SHRINK_CENTER and its caption font (12 + 2/2
	# padding = ~20px) is shorter than the 20pt name label it sits beside, so this row's height
	# is still the name label's -- the left pane's vertical budget below is untouched.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	pv.add_child(name_row)

	_map_name_label = Label.new()
	_map_name_label.text = "Select a map"
	_map_name_label.add_theme_font_size_override("font_size", 20)
	_map_name_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	# A player-authored map name is arbitrary length: clip + ellipsis so it can never push
	# the chip off the right edge of the card.
	_map_name_label.clip_text = true
	_map_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_row.add_child(_map_name_label)

	# Explicit floor, like every other chip-sized control on these screens: without one it
	# collapses to its text width the moment the pane is squeezed.
	_map_source_slot = HBoxContainer.new()
	_map_source_slot.name = "SourceChipSlot"
	_map_source_slot.alignment = BoxContainer.ALIGNMENT_END
	_map_source_slot.custom_minimum_size = Vector2(MapRowBuilder.CHIP_MIN_WIDTH, 0.0)
	_map_source_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_map_source_slot)

	pv.add_child(_build_minimap_holder())

	# Description + details scroll internally with a firm cap, instead of pushing the
	# preview card's (and therefore the whole pane's) height out arbitrarily. A long
	# multi-line description now scrolls in place rather than shoving the action row
	# off the bottom of the screen.
	var details_scroll := ScrollContainer.new()
	details_scroll.custom_minimum_size = Vector2(0.0, 96.0)
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	pv.add_child(details_scroll)

	var details_box := VBoxContainer.new()
	details_box.add_theme_constant_override("separation", 6)
	details_scroll.add_child(details_box)

	_map_desc_label = Label.new()
	_map_desc_label.text = "Choose a map from the list to see its details."
	_map_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_box.add_child(_map_desc_label)

	_map_details_label = Label.new()
	details_box.add_child(_map_details_label)

	left.add_child(preview)
	return left


## The minimap pane: a fixed-height panel holding the top-down map texture (NEAREST-
## filtered, aspect kept so non-square maps letterbox) with a neutral placeholder
## label shown until a map is selected or when a map has no drawable layout.
func _build_minimap_holder() -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(0.0, 150.0)
	holder.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD_DK))

	_map_minimap = TextureRect.new()
	_map_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_minimap.visible = false
	holder.add_child(_map_minimap)

	_minimap_placeholder = Label.new()
	_minimap_placeholder.text = "No preview available"
	_minimap_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_placeholder.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	holder.add_child(_minimap_placeholder)

	return holder


## Render (or fetch from cache) the minimap for the map at [param index] and show it,
## falling back to the neutral placeholder when there is nothing to draw.
func _update_minimap(index: int) -> void:
	if _map_minimap == null or _minimap_placeholder == null:
		return
	if index < 0 or index >= _map_resources.size():
		_show_minimap_placeholder("No preview available")
		return

	if _map_resources[index] == null:
		_show_minimap_placeholder("No preview available")
		return

	var map_path: String = _available_maps[index]
	var tex: Texture2D = null
	if _minimap_cache.has(map_path):
		tex = _minimap_cache[map_path]
	else:
		# Same generator for every source: a downloaded or player-built map is a MapResource
		# like any other by the time it reaches here, so it gets a real minimap for free.
		tex = MapPreview.generate(_map_resources[index])
		_minimap_cache[map_path] = tex  # cache null too, so an empty map isn't retried

	if tex == null:
		_show_minimap_placeholder("No preview available")
		return

	_map_minimap.texture = tex
	_map_minimap.visible = true
	_minimap_placeholder.visible = false


func _show_minimap_placeholder(text: String) -> void:
	if _map_minimap != null:
		_map_minimap.visible = false
	if _minimap_placeholder != null:
		_minimap_placeholder.text = text
		_minimap_placeholder.visible = true


## RIGHT: the reusable config column.
func _build_right_pane() -> Control:
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.42
	right.add_theme_constant_override("separation", 8)

	var heading := Label.new()
	heading.text = "MATCH SETTINGS"
	MenuTheme.style_section_header(heading)
	right.add_child(heading)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	_config_panel = MatchConfigPanel.new()
	_config_panel.custom_minimum_size = Vector2(320.0, 220.0)
	_config_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_config_panel)
	_config_panel.configure(_mode)

	right.add_child(panel)
	return right


func _build_actions() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	row.add_child(back)

	# "Get more maps" lands in the FOOTER, not the left pane: at 48 tall it is shorter than
	# the 52 Start button already in this row, so the row's height -- and therefore the whole
	# page's vertical budget -- is unchanged. Width: 160 + 200 + 240 + 2 gaps * 24 separation
	# = 648, against the page's 1232 (1280 - 2*24 margins) at 720p. Arena has no map list, so
	# it has nothing to browse for.
	if _uses_map_list():
		var more := Button.new()
		more.name = "GetMoreMapsButton"
		more.text = "Get More Maps"
		more.custom_minimum_size = Vector2(200.0, 48.0)
		var browse_available: bool = ResourceLoader.exists(COMMUNITY_BROWSE_SCENE)
		more.disabled = not browse_available
		more.tooltip_text = "Browse and download community maps." if browse_available \
			else "The community browser is not available in this build."
		more.pressed.connect(_on_more_maps_pressed)
		row.add_child(more)

	_start_btn = Button.new()
	_start_btn.text = "Start Run" if _mode == MatchConfigPanel.MODE_ARENA else "Start Match"
	_start_btn.theme_type_variation = &"SelectedButton"  # solid gold, prominent
	_start_btn.custom_minimum_size = Vector2(240.0, 52.0)
	_start_btn.add_theme_font_size_override("font_size", 20)
	_start_btn.pressed.connect(_on_start_pressed)
	# Map modes need a selected map first; arena can start immediately.
	_start_btn.disabled = _uses_map_list()
	row.add_child(_start_btn)

	return row


# --- Map listing (ported from MapSelection) ---------------------------------

## Rebuild the map list from the catalog, keeping the current selection when that map is
## still there. Public because it is also the return path from the community browser: a map
## downloaded mid-setup must be listed the moment the player is back here.
func refresh_map_list() -> void:
	_load_available_maps()


func _load_available_maps() -> void:
	if _map_list == null:
		return
	var previous: String = _current_selected_map
	_available_maps.clear()
	_map_resources.clear()
	_map_rows.clear()

	# EVERY source, one list: shipped maps, maps the player built, maps they downloaded --
	# badged, and ordered builtin -> custom -> community (see MapRowBuilder). Drafts are
	# included: this is the local picker, and you must be able to play-test a map you just
	# built. Nothing is refused here -- `false` = not networked, so a map too big to send to
	# an opponent is still perfectly playable hot-seat.
	var rows: Array = MapRowBuilder.versus_rows(false, true)
	if rows.is_empty():
		# Fresh install, empty library: seed the shipped default, exactly as MapSelection did.
		var default_map := MapLoader.create_default_map()
		MapLoader.save_map(default_map, "default_skirmish")
		rows = MapRowBuilder.versus_rows(false, true)

	# Drafts keep their "(draft)" tail; it is per-row state the catalog does not carry, so it
	# is passed to the renderer rather than baked into the shared row model.
	var suffixes: Dictionary = {}
	for row in rows:
		var path: String = String(row.get("path", ""))
		var resource = row.get("resource", null)
		var map_resource: MapResource = resource if resource is MapResource else null
		_available_maps.append(path)
		_map_resources.append(map_resource)
		_map_rows.append(row)
		if map_resource != null and not map_resource.is_active():
			suffixes[path] = "  (draft)"

	MapRowBuilder.apply_to_item_list(_map_list, rows, suffixes)

	var target: int = _available_maps.find(previous)
	if target < 0:
		target = _preferred_row()
	elif _map_list.is_item_disabled(target):
		target = _preferred_row()
	if target >= 0:
		_map_list.select(target)
		_on_map_selected(target)
	else:
		_current_selected_map = ""
		if _start_btn != null:
			_start_btn.disabled = true


## The row this screen should OPEN on: the mode's recommended map when there is one and it
## is launchable, otherwise the plain first-selectable row every other mode uses.
##
## Only Siege has a recommendation today. It is a PRESELECTION, never a filter -- the
## player can still pick any map in the list, which is why this returns a row index into the
## list that was already built rather than rebuilding it.
func _preferred_row() -> int:
	if MatchConfigPanel.is_siege_mode(_mode):
		var siege_row: int = _siege_row()
		if siege_row >= 0:
			return siege_row
	return _first_selectable_row()


## The listed row holding the Siege map, or -1. Asks the mode controller first (it owns
## which map Siege ships with); falls back to reading the maps' own declarations.
func _siege_row() -> int:
	var recommended: String = _siege_recommended_path()
	if not recommended.is_empty():
		var direct: int = _available_maps.find(recommended)
		if direct >= 0 and not _map_list.is_item_disabled(direct):
			return direct
	return _siege_shaped_row()


## [code]SiegeController.recommended_map_path()[/code], or "" when this build ships no
## controller / no recommendation. Resolved by PATH with a has-method guard (an autoload
## node wins if one is registered), so this screen never names a class that may not exist --
## the [MapRowBuilder.catalog] pattern.
func _siege_recommended_path() -> String:
	var source = get_node_or_null("/root/SiegeController")
	if source == null or not MapRowBuilder.responds(source, "recommended_map_path"):
		source = get_tree().get_first_node_in_group(SIEGE_CONTROLLER_GROUP) if get_tree() != null else null
	if source == null or not MapRowBuilder.responds(source, "recommended_map_path"):
		source = null
		for path in SIEGE_CONTROLLER_PATHS:
			if not ResourceLoader.exists(path):
				continue
			var script: Resource = load(path)
			if script != null and MapRowBuilder.responds(script, "recommended_map_path"):
				source = script
				break
	if source == null:
		return ""
	return String(source.recommended_map_path()).strip_edges()


## The first listed row whose MAP declares itself a siege map, or -1. See SIEGE_MAP_TYPE.
func _siege_shaped_row() -> int:
	for i in _map_resources.size():
		if _map_list.is_item_disabled(i):
			continue
		if _is_siege_map(_map_resources[i]):
			return i
	return -1


## Does [param map_resource] declare itself a siege map? Pure and null-safe.
static func _is_siege_map(map_resource) -> bool:
	if map_resource == null:
		return false
	var map_type = map_resource.get("map_type")
	if map_type != null and String(map_type).strip_edges().to_lower() == SIEGE_MAP_TYPE:
		return true
	var tags = map_resource.get("tags")
	if tags is Array:
		for tag in tags as Array:
			if String(tag).strip_edges().to_lower() == SIEGE_TAG:
				return true
	var conditions = map_resource.get("victory_conditions")
	if conditions is Array:
		for c in conditions as Array:
			var key: String = String(c).strip_edges().to_lower()
			if key.contains("captur") and key.contains("base"):
				return true
	return false


## The first row the player can actually launch, or -1 when there is none.
func _first_selectable_row() -> int:
	if _map_list == null:
		return -1
	for i in _map_list.get_item_count():
		if not _map_list.is_item_disabled(i):
			return i
	return -1


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= _map_resources.size():
		return
	var map_resource: MapResource = _map_resources[index]
	if map_resource == null:
		# The library lists it, but this build cannot read it. Say so and stage nothing --
		# an expected outcome for an untrusted download, so it is a message, never an error.
		var row: Dictionary = _map_rows[index] if index < _map_rows.size() else {}
		_current_selected_map = ""
		if _map_name_label != null:
			_map_name_label.text = String(row.get("name", "Unknown Map"))
		_update_source_chip(String(row.get("source", MapRowBuilder.SOURCE_BUILTIN)))
		if _map_desc_label != null:
			_map_desc_label.text = MapRowBuilder.UNREADABLE_TOOLTIP
		if _map_details_label != null:
			_map_details_label.text = ""
		_show_minimap_placeholder("No preview available")
		if _start_btn != null:
			_start_btn.disabled = true
		return
	_current_selected_map = _available_maps[index]
	_display_map_info(map_resource, _map_rows[index] if index < _map_rows.size() else {})
	_update_minimap(index)
	if _start_btn != null:
		_start_btn.disabled = false


func _on_map_activated(index: int) -> void:
	_on_map_selected(index)
	_on_start_pressed()


## The preview card for [param map_resource]. [param row] is that map's row model, whose only
## job here is the source chip + the "Source:" detail line -- the description, size, players
## and author still come from the map's OWN [method MapResource.get_display_info], so a
## downloaded or player-built map reads exactly like a shipped one with no second metadata
## path to keep in step.
func _display_map_info(map_resource: MapResource, row: Dictionary = {}) -> void:
	if map_resource == null:
		return
	var info := map_resource.get_display_info()
	var source: String = String(row.get("source", MapRowBuilder.SOURCE_BUILTIN))
	if _map_name_label != null:
		_map_name_label.text = info.get("name", "Unknown Map")
	_update_source_chip(source)
	if _map_desc_label != null:
		_map_desc_label.text = info.get("description", "No description available")
	if _map_details_label != null:
		var details: Array = []
		details.append("Source: " + MapRowBuilder.source_label(source))
		details.append("Size: " + info.get("size", "Unknown"))
		details.append("Players: " + str(info.get("players", 0)) + "/" + str(info.get("max_players", 2)))
		details.append("Difficulty: " + info.get("difficulty", "Normal"))
		details.append("Type: " + info.get("map_type", "Skirmish"))
		if not String(info.get("author", "")).is_empty():
			details.append("Author: " + info.get("author", ""))
		details.append("Units: " + str(info.get("total_spawns", 0)))
		details.append("Tiles: " + str(info.get("total_tiles", 0)))
		_map_details_label.text = "\n".join(details)


## Show (or clear) the preview card's source chip. Builtin is unbadged -- the slot keeps its
## width either way, so the name label never reflows between selections.
func _update_source_chip(source: String) -> void:
	if _map_source_slot == null:
		return
	for child in _map_source_slot.get_children():
		# free(), not queue_free(): the old chip is ours alone and is gone from the tree on
		# the line above, and a DEFERRED free would still be counted as a live node by the
		# time a test that rebuilt this list finishes (tests/README.md rule 2).
		_map_source_slot.remove_child(child)
		child.free()
	var badge: String = MapRowBuilder.badge_for(source)
	if badge.is_empty():
		return
	var chip: Label = MenuTheme.make_chip(badge, MapRowBuilder.badge_color(source))
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_source_slot.add_child(chip)


# --- Community maps ---------------------------------------------------------

## Open the community browser PRE-FILTERED to maps, and told to come back here. Guarded like
## every other cross-screen hop in these menus: a build without the scene reports it rather
## than changing scene to a missing path.
func _on_more_maps_pressed() -> void:
	if not ResourceLoader.exists(COMMUNITY_BROWSE_SCENE):
		_show_message("The community browser is not available in this build.")
		return
	# The mode is a static on this class, so the Back trip lands on the same variant of this
	# screen the player left -- exactly as the Character Select round trip already does.
	CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP, MATCH_SETUP_SCENE)
	get_tree().change_scene_to_file(COMMUNITY_BROWSE_SCENE)


# --- Start / Back -----------------------------------------------------------

func _on_start_pressed() -> void:
	if _config_panel == null:
		return
	_config_panel.apply_settings()

	if _mode == MatchConfigPanel.MODE_ARENA:
		_start_arena()
		return
	_start_map_match()


func _start_map_match() -> void:
	if _current_selected_map.is_empty():
		_show_message("Pick a map first.")
		return
	GameSettings.set_selected_map(_current_selected_map)
	# Clear any Arena ruleset staged earlier so a map launch is never mistaken for a run.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _start_arena() -> void:
	var base: Resource = load(BASE_RULESET_PATH)
	if base == null:
		_show_message("Arena ruleset is missing -- cannot start a run.")
		return
	var arena := get_node_or_null("/root/ArenaController")
	if arena == null or not arena.has_method("prepare_run"):
		_show_message("Arena mode is not available.")
		return
	# Never mutate the shared .tres -- deep-duplicate, then write the chosen settings.
	var rs: Resource = base.duplicate(true)
	if rs == null:
		_show_message("Could not prepare the run.")
		return
	rs.total_rounds = _config_panel.get_run_length()
	rs.turn_system = _config_panel.get_turn_system()
	# Stage the ruleset and go pick a squad; Character Select calls begin_pending_run(),
	# which starts the run (and changes to the GameWorld scene) with the chosen units.
	arena.prepare_run(rs)
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)


func _on_back_pressed() -> void:
	# Discard any staged arena ruleset so it can't leak into a later launch.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	if _is_hotseat():
		get_tree().change_scene_to_file(MP_MODE_SELECT_SCENE)
	else:
		get_tree().change_scene_to_file(SOLO_MODE_SELECT_SCENE)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true


# --- Keyboard ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if not (event is InputEventKey):
		return
	match event.keycode:
		KEY_ESCAPE:
			_on_back_pressed()
		KEY_ENTER, KEY_KP_ENTER:
			if _start_btn != null and not _start_btn.disabled:
				_on_start_pressed()
		KEY_UP:
			_move_map_selection(-1)
		KEY_DOWN:
			_move_map_selection(1)


func _move_map_selection(delta: int) -> void:
	if _map_list == null or _map_list.get_item_count() == 0:
		return
	var selected := _map_list.get_selected_items()
	var current := selected[0] if selected.size() > 0 else 0
	var next := clampi(current + delta, 0, _map_list.get_item_count() - 1)
	if next != current:
		_map_list.select(next)
		_on_map_selected(next)
