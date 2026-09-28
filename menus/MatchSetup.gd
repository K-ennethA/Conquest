extends Control

class_name MatchSetup

## Unified pre-battle SETUP screen. Replaces the old TurnSystemSelection + MapSelection +
## ArenaSetupScreen as three separate steps with one screen: the map list on the LEFT, the
## selected map's live 3D preview + facts in the MIDDLE, and a reusable [MatchConfigPanel]
## config column on the RIGHT. What the Start button launches depends on
## [member requested_mode], set by the caller before it changes here:
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
## Look: the shared illuminated-grove page ([MenuKit.build_page]: breadcrumb, Cinzel title,
## key hints, Back + gold Start in the footer). The map rows carry a top-down thumbnail; the
## detail card shows the map turning in 3D ([MapPreview3D]; the flat [MapPreview] minimap
## is the fallback when there is no renderer, e.g. headless) with its badges (source,
## difficulty, multi-floor, boss, draft, weather) and key facts.
##
## The game mode register is re-asserted on Start from the requested mode (hot-seat ->
## VERSUS, everything else -> SINGLE_PLAYER), so a local hot-seat match can never silently
## turn into a single-player one on its way through setup (the bug the old turn-system
## screen had). The mode is carried in a STATIC var so it survives the scene change AND a
## Back trip from Character Select (which returns here without re-picking the mode). Every
## dependency is null-guarded; a missing autoload or ruleset shows an inline message
## instead of crashing.

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

## Map-row thumbnail (ItemList icon) size, px.
const THUMB_SIZE := Vector2i(72, 48)

## Column widths at the 1280x720 design size. The page body is 1280 - 2 * SP_PAGE = 1184
## wide; minus two SP_XL gaps that leaves 1136 for the three columns, so the detail card in
## the middle gets ~516. Every row inside the detail card must therefore be able to shrink
## (wrapping objective, badges in a flow row) -- one rigid row wider than its column pushes
## the settings column and the Start button off the right edge.
const LEFT_COLUMN_W := 300.0
const RIGHT_COLUMN_W := 320.0
const ARENA_RIGHT_COLUMN_W := 520.0

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
var _count_label: Label = null
var _map_name_label: Label = null
## Holder for the detail card's source chip (CUSTOM / COMMUNITY). An ItemList row is text
## only, so this is where the real themed chip lives; the row itself carries the bracketed
## text badge.
var _map_source_slot: HBoxContainer = null
## The detail card's other badges (difficulty, multi-floor, boss, draft, weather).
var _map_badges: HFlowContainer = null
var _preview_3d: MapPreview3D = null
var _map_minimap: TextureRect = null
var _minimap_placeholder: Label = null
var _map_desc_label: Label = null
var _map_facts: HBoxContainer = null
var _map_details_label: Label = null

## Cache of rendered minimap textures keyed by map path, so re-selecting a map (or
## returning to it) never re-renders. Cheap to build, but the cache avoids redundant
## tile-resource loads (see [MapPreview]). Also feeds the list-row thumbnails.
var _minimap_cache: Dictionary = {}
var _config_panel: MatchConfigPanel = null
var _start_btn: Button = null
var _message_label: Label = null
var _summary_label: Label = null


func _ready() -> void:
	_mode = requested_mode
	_build_ui()
	if _uses_map_list():
		_load_available_maps()
		MenuNav.focus_deferred(_map_list)
	elif _config_panel != null:
		var first := _first_focusable(_config_panel)
		if first != null:
			MenuNav.focus_deferred(first)
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


func _subtitle_text() -> String:
	match _mode:
		MatchConfigPanel.MODE_ARENA:
			return "Battle through escalating waves of AI enemies. Between rounds you draft upgrades for your squad."
		MatchConfigPanel.MODE_LOCAL, MatchConfigPanel.MODE_SIEGE_LOCAL:
			return "Two commanders, one device. Choose a battlefield and how turns work, then pick your squads."
		MatchConfigPanel.MODE_SIEGE:
			return "Push the lanes, hold your base, take theirs. Choose a battlefield, then pick your squad."
		_:
			return "Choose a battlefield and the rules, then pick your squad."


## True when this screen is setting up a hot-seat match, i.e. Back goes to the VERSUS mode
## picker rather than the SOLO one.
func _is_hotseat() -> bool:
	return _mode == MatchConfigPanel.MODE_LOCAL or _mode == MatchConfigPanel.MODE_SIEGE_LOCAL


# --- UI construction --------------------------------------------------------
#
# 720p BUDGET: build_page's header (~120) + footer (~64) leave ~480px of body. The page
# keeps exactly ONE EXPAND_FILL region per column (the map list on the left, the 3D preview
# well in the middle, the config panel on the right) so nothing can push the footer (Back /
# Get More Maps / Start) off the bottom of the screen; the description + details scroll in
# place with a firm cap.

func _build_ui() -> void:
	var crumbs: Array = ["Versus"] if _is_hotseat() else ["Solo"]
	var page := MenuKit.build_page(self, crumbs, _title_text(), _subtitle_text())

	var row := HBoxContainer.new()
	row.name = "Columns"
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	page.body.add_child(row)

	if _uses_map_list():
		row.add_child(_build_left_pane())
		row.add_child(_build_detail_pane())
	else:
		row.add_child(_build_arena_note())
	row.add_child(_build_right_pane())

	_build_actions(page)


## LEFT: the map list (map modes).
func _build_left_pane() -> Control:
	var left := VBoxContainer.new()
	left.name = "MapColumn"
	left.custom_minimum_size = Vector2(LEFT_COLUMN_W, 0.0)
	left.size_flags_horizontal = Control.SIZE_FILL
	left.add_theme_constant_override("separation", MenuTheme.SP_S)

	_count_label = MenuKit.section("Maps")
	left.add_child(_count_label)

	_map_list = ItemList.new()
	_map_list.name = "MapList"
	# Guaranteed height so the list always shows several rows and scrolls within itself.
	_map_list.custom_minimum_size = Vector2(0.0, 168.0)
	_map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Card-like rows with a top-down thumbnail (theme styles the rows, hover and the gold
	# selected wash -- the widget stays a stock ItemList).
	_map_list.fixed_icon_size = THUMB_SIZE
	_map_list.icon_mode = ItemList.ICON_MODE_LEFT
	_map_list.add_theme_constant_override("v_separation", 10)
	_map_list.add_theme_constant_override("icon_margin", 12)
	_map_list.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_list.focus_mode = Control.FOCUS_ALL
	_map_list.item_selected.connect(_on_map_selected)
	_map_list.item_activated.connect(_on_map_activated)
	left.add_child(_map_list)
	return left


## MIDDLE: the selected map -- 3D preview well, name + badges, description, facts.
func _build_detail_pane() -> Control:
	var detail := MenuKit.card()
	detail.name = "MapDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_stretch_ratio = 1.4
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", MenuTheme.SP_S)
	detail.add_child(dv)

	dv.add_child(_build_minimap_holder())

	# Name + chips on ONE line; the name clips (player-authored names are arbitrary length).
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", MenuTheme.SP_S)
	dv.add_child(name_row)
	_map_name_label = MenuKit.label("Select a map", &"HeadingLabel")
	_map_name_label.name = "MapNameLabel"
	_map_name_label.clip_text = true
	_map_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_name_label.custom_minimum_size = Vector2(120.0, 0.0)
	name_row.add_child(_map_name_label)
	_map_source_slot = HBoxContainer.new()
	_map_source_slot.name = "SourceChipSlot"
	_map_source_slot.alignment = BoxContainer.ALIGNMENT_END
	_map_source_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(_map_source_slot)
	# The other badges get their own FLOW row under the name: a map can carry up to six
	# (difficulty, multi-floor, boss, siege, draft, weather) and one fixed row that long is
	# wider than the card.
	_map_badges = HFlowContainer.new()
	_map_badges.name = "Badges"
	_map_badges.add_theme_constant_override("h_separation", 6)
	_map_badges.add_theme_constant_override("v_separation", 4)
	dv.add_child(_map_badges)

	# Description + details scroll internally with a firm cap, so a long description never
	# pushes the card (and the footer) past the screen.
	var details_scroll := ScrollContainer.new()
	details_scroll.custom_minimum_size = Vector2(0.0, 64.0)
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	dv.add_child(details_scroll)
	var details_box := VBoxContainer.new()
	details_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_box.add_theme_constant_override("separation", 4)
	details_scroll.add_child(details_box)
	_map_desc_label = MenuKit.label("Choose a map from the list to see its details.", &"DimLabel", true)
	_map_desc_label.name = "MapDescriptionLabel"
	details_box.add_child(_map_desc_label)
	_map_details_label = MenuKit.label("", &"MutedLabel", true)
	_map_details_label.name = "MapDetailsLabel"
	_map_details_label.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	details_box.add_child(_map_details_label)

	_map_facts = HBoxContainer.new()
	_map_facts.name = "MapFacts"
	_map_facts.add_theme_constant_override("separation", MenuTheme.SP_L)
	dv.add_child(_map_facts)
	return detail


## The preview well: the map turning in 3D, or -- with no renderer (headless) -- the flat
## top-down minimap (NEAREST-filtered, aspect kept so non-square maps letterbox), with a
## neutral placeholder until a map is selected or when a map has no drawable layout.
func _build_minimap_holder() -> Control:
	var holder := MenuKit.card(&"InsetPanel")
	holder.name = "PreviewWell"
	holder.custom_minimum_size = Vector2(0.0, 150.0)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var well_sb := MenuTheme.inset_box()
	well_sb.hatch_alpha = 0.0
	well_sb.set_content_margin_all(3)
	holder.add_theme_stylebox_override("panel", well_sb)

	if DisplayServer.get_name() != "headless":
		_preview_3d = MapPreview3D.new()
		_preview_3d.name = "MapPreview"
		_preview_3d.background_color = MenuTheme.PANEL_SUNK
		_preview_3d.turntable_speed = 0.25
		_preview_3d.visible = false
		holder.add_child(_preview_3d)

	_map_minimap = TextureRect.new()
	_map_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_minimap.visible = false
	holder.add_child(_map_minimap)

	_minimap_placeholder = MenuKit.label("No preview available", &"MutedLabel")
	_minimap_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(_minimap_placeholder)
	return holder


## The minimap texture for [param index] (rendered once, then cached by path), or null.
func _minimap_for(index: int) -> Texture2D:
	if index < 0 or index >= _map_resources.size() or _map_resources[index] == null:
		return null
	var map_path: String = _available_maps[index]
	if _minimap_cache.has(map_path):
		return _minimap_cache[map_path]
	# Same generator for every source: a downloaded or player-built map is a MapResource
	# like any other by the time it reaches here, so it gets a real minimap for free.
	var tex: Texture2D = MapPreview.generate(_map_resources[index])
	_minimap_cache[map_path] = tex  # cache null too, so an empty map isn't retried
	return tex


## Show the map at [param index] in the preview well: the 3D turntable when there is a
## renderer, else the cached flat minimap, else the neutral placeholder.
func _update_minimap(index: int) -> void:
	if _map_minimap == null or _minimap_placeholder == null:
		return
	if index < 0 or index >= _map_resources.size() or _map_resources[index] == null:
		_show_minimap_placeholder("No preview available")
		return

	if _preview_3d != null:
		_preview_3d.show_map(_map_resources[index])
		_preview_3d.visible = true
		_map_minimap.visible = false
		_minimap_placeholder.visible = false
		return

	var tex: Texture2D = _minimap_for(index)
	if tex == null:
		_show_minimap_placeholder("No preview available")
		return
	_map_minimap.texture = tex
	_map_minimap.visible = true
	_minimap_placeholder.visible = false


func _show_minimap_placeholder(text: String) -> void:
	if _preview_3d != null:
		_preview_3d.visible = false
	if _map_minimap != null:
		_map_minimap.visible = false
	if _minimap_placeholder != null:
		_minimap_placeholder.text = text
		_minimap_placeholder.visible = true


## LEFT (Arena): Arena picks its own compact maps each round, so instead of a map list the
## page explains the run and shows a live summary of what Start will launch.
func _build_arena_note() -> Control:
	var card := MenuKit.card(&"CrestCard")
	card.name = "ArenaNote"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.2
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", MenuTheme.SP_M)
	card.add_child(v)
	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.centered = true
	rule.custom_minimum_size = Vector2(160, 12)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rule)
	var head := MenuKit.label("The Gauntlet", &"HeadingLabel")
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var note := MenuKit.label(
		"Arena picks its own compact maps each round.\n\nDraft augments between fights and survive as long as you can.",
		&"DimLabel", true)
	note.name = "ArenaNoteText"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	_summary_label = MenuKit.label("", &"SubheadingLabel")
	_summary_label.name = "Summary"
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_label.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	v.add_child(_summary_label)
	return card


## RIGHT: the reusable config column.
func _build_right_pane() -> Control:
	var right := VBoxContainer.new()
	right.name = "SettingsColumn"
	# Arena has no map list or detail card, so its settings column can take the room the
	# side-by-side turn cards and run-length presets need; the map modes use the narrow one.
	right.custom_minimum_size = Vector2(RIGHT_COLUMN_W if _uses_map_list() else ARENA_RIGHT_COLUMN_W, 0.0)
	right.size_flags_horizontal = Control.SIZE_FILL
	right.add_theme_constant_override("separation", MenuTheme.SP_S)
	right.add_child(MenuKit.section("Match Settings"))

	var panel := MenuKit.card()
	panel.name = "SettingsCard"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)

	_config_panel = MatchConfigPanel.new()
	_config_panel.name = "MatchConfigPanel"
	# No width floor: the column sets the width, and in the narrow (map-mode) column the rows
	# stack so nothing inside asks for more than the column has.
	_config_panel.custom_minimum_size = Vector2(0.0, 200.0)
	_config_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_config_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_config_panel.narrow_layout = _uses_map_list()
	scroll.add_child(_config_panel)
	_config_panel.configure(_mode)
	_config_panel.changed.connect(_update_summary)
	_update_summary()
	return right


## Footer: key hints + inline message on the left; Back / Get More Maps / Start on the right.
func _build_actions(page: Dictionary) -> void:
	MenuKit.add_standard_hints(page.hints, "Choose map" if _uses_map_list() else "Select")
	_message_label = MenuKit.label("", &"")
	_message_label.name = "Message"
	_message_label.visible = false
	page.hints.add_child(_message_label)

	var back := MenuKit.button("Back", MenuKit.GHOST, 140)
	back.name = "BackButton"
	back.pressed.connect(_on_back_pressed)
	page.actions.add_child(back)

	# "Get More Maps" opens the community browser pre-filtered to maps and pointed back here.
	# Arena has no map list, so it has nothing to browse for.
	if _uses_map_list():
		var more := MenuKit.button("Get More Maps", &"", 200)
		more.name = "GetMoreMapsButton"
		var browse_available: bool = ResourceLoader.exists(COMMUNITY_BROWSE_SCENE)
		more.disabled = not browse_available
		more.tooltip_text = "Browse and download community maps." if browse_available \
			else "The community browser is not available in this build."
		more.pressed.connect(_on_more_maps_pressed)
		page.actions.add_child(more)

	_start_btn = MenuKit.button("Choose Squad  >", MenuKit.PRIMARY, 240, 54)
	_start_btn.name = "StartButton"
	_start_btn.tooltip_text = "Start the run with these settings." if _mode == MatchConfigPanel.MODE_ARENA \
		else "Stage this map and pick your squad."
	_start_btn.pressed.connect(_on_start_pressed)
	# Map modes need a selected map first; arena can start immediately.
	_start_btn.disabled = _uses_map_list()
	page.actions.add_child(_start_btn)


## Live "what will launch" line for the Arena note.
func _update_summary() -> void:
	if _summary_label == null or _config_panel == null:
		return
	_summary_label.text = "%s  ·  %s turns" % [_config_panel.run_length_text(),
		_config_panel.turn_system_name()]


func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Control and (c as Control).focus_mode == Control.FOCUS_ALL \
				and (c as Control).is_visible_in_tree():
			return c
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null


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
	# Top-down thumbnail beside each row (the same cached minimap the preview falls back to).
	for i in _map_list.get_item_count():
		var thumb: Texture2D = _minimap_for(i)
		if thumb != null:
			_map_list.set_item_icon(i, thumb)
	if _count_label != null:
		_count_label.text = "MAPS  (%d)" % _map_list.get_item_count()

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
		_clear_children(_map_badges)
		_clear_children(_map_facts)
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


## The detail card for [param map_resource]. [param row] is that map's row model, whose only
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
	_update_badges(map_resource, String(info.get("difficulty", "Normal")))
	if _map_desc_label != null:
		var desc: String = String(info.get("description", ""))
		_map_desc_label.text = desc if not desc.is_empty() else "No description available"
	if _map_details_label != null:
		var details: Array = []
		details.append("Source: " + MapRowBuilder.source_label(source))
		details.append("Size: " + String(info.get("size", "Unknown")))
		details.append("Type: " + String(info.get("map_type", "Skirmish")))
		if not String(info.get("author", "")).is_empty():
			details.append("Author: " + String(info.get("author", "")))
		details.append("Units: " + str(info.get("total_spawns", 0)))
		details.append("Tiles: " + str(info.get("total_tiles", 0)))
		_map_details_label.text = "  ·  ".join(details)
	_update_facts(map_resource, info)


## Difficulty + map-shape badges beside the name: difficulty (colour-coded), Multi-floor
## (n), Boss, Siege, Draft and the map's weather.
func _update_badges(map_resource: MapResource, difficulty: String) -> void:
	if _map_badges == null:
		return
	_clear_children(_map_badges)
	var diff_color := MenuTheme.SUCCESS
	match difficulty.to_lower():
		"normal": diff_color = MenuTheme.ACCENT
		"hard": diff_color = MenuTheme.WARNING
		"expert", "brutal": diff_color = MenuTheme.DANGER
	_map_badges.add_child(MenuKit.badge(difficulty, diff_color))
	var floors: int = map_resource.get_floor_count() if map_resource.has_method("get_floor_count") else 1
	if floors > 1:
		_map_badges.add_child(MenuKit.badge("Multi-floor (%d)" % floors, MenuTheme.ACCENT))
	if "Defeat Boss" in map_resource.victory_conditions:
		_map_badges.add_child(MenuKit.badge("Boss", MenuTheme.DANGER))
	if _is_siege_map(map_resource):
		_map_badges.add_child(MenuKit.badge("Siege", MenuTheme.GOLD))
	if not map_resource.is_active():
		_map_badges.add_child(MenuKit.badge("Draft", MenuTheme.WARNING))
	if map_resource.has_method("weather_summary"):
		var summary: String = String(map_resource.weather_summary())
		if not summary.is_empty():
			var wcol: Color = MenuTheme.ACCENT
			var w = Weather.get_weather(map_resource.weather)
			if w != null:
				wcol = w.color
			_map_badges.add_child(MenuKit.badge(summary, wcol))


## Key facts under the description (Cinzel caption over the value): players, your squad
## size (START spawns only -- respawn / reinforcement points are not squad slots), floors
## on a multi-floor map, and the objective.
func _update_facts(map_resource: MapResource, info: Dictionary) -> void:
	if _map_facts == null:
		return
	_clear_children(_map_facts)
	var mine := 0
	for s in map_resource.unit_spawns:
		if int(s.get("player_id", -1)) != 0:
			continue
		var kind: String = String(s.get("spawn_kind", "Start"))
		if kind.is_empty() or kind.to_lower() == "start":
			mine += 1
	_map_facts.add_child(MenuKit.stat_block("Players", str(maxi(int(info.get("max_players", 2)), 1))))
	_map_facts.add_child(MenuKit.stat_block("Your squad", ("up to %d" % mine) if mine > 0 else "--"))
	var floors: int = map_resource.get_floor_count() if map_resource.has_method("get_floor_count") else 1
	if floors > 1:
		_map_facts.add_child(MenuKit.stat_block("Floors", str(floors)))
	var goal: String = ", ".join(map_resource.victory_conditions) \
		if not map_resource.victory_conditions.is_empty() else "Eliminate all enemies"
	var goal_block := MenuKit.stat_block("Objective", goal)
	goal_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The objective is the one open-ended value (several authored conditions join here): it
	# wraps inside the card rather than widening it.
	var goal_value := goal_block.get_child(goal_block.get_child_count() - 1) as Label
	if goal_value != null:
		goal_value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_facts.add_child(goal_block)


## Show (or clear) the detail card's source chip. Builtin is unbadged.
func _update_source_chip(source: String) -> void:
	if _map_source_slot == null:
		return
	_clear_children(_map_source_slot)
	var badge: String = MapRowBuilder.badge_for(source)
	if badge.is_empty():
		return
	var chip := MenuKit.badge(badge, MapRowBuilder.badge_color(source))
	chip.name = "SourceChip"
	_map_source_slot.add_child(chip)


## free(), not queue_free(): the old chips are ours alone and leave the tree first, and a
## DEFERRED free would still be counted as a live node by the time a test that rebuilt
## this list finishes (tests/README.md rule 2).
func _clear_children(holder: Node) -> void:
	if holder == null:
		return
	for child in holder.get_children():
		holder.remove_child(child)
		child.free()


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
	MenuNav.change_scene(self, COMMUNITY_BROWSE_SCENE)


# --- Start / Back -----------------------------------------------------------

func _on_start_pressed() -> void:
	if _config_panel == null:
		return
	_config_panel.apply_settings()
	_sync_game_mode()

	if _mode == MatchConfigPanel.MODE_ARENA:
		_start_arena()
		return
	_start_map_match()


## Re-assert the match register from the requested mode: hot-seat modes are two-human
## VERSUS matches, everything else here is single player vs the AI. (Ported fix: the old
## turn-system screen forced SINGLE_PLAYER and silently turned local hot-seat into a
## single-player match.)
func _sync_game_mode() -> void:
	if GameSettings == null or not GameSettings.has_method("set_game_mode"):
		return
	if _is_hotseat():
		GameSettings.set_game_mode(GameSettings.GameMode.VERSUS)
		if GameSettings.has_method("set_player_count"):
			GameSettings.set_player_count(2)
	else:
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)


func _start_map_match() -> void:
	if _current_selected_map.is_empty():
		_show_message("Pick a map first.")
		return
	GameSettings.set_selected_map(_current_selected_map)
	# Clear any Arena ruleset staged earlier so a map launch is never mistaken for a run.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	MenuNav.change_scene(self, CHARACTER_SELECT_SCENE)


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
	MenuNav.change_scene(self, CHARACTER_SELECT_SCENE)


func _on_back_pressed() -> void:
	# Discard any staged arena ruleset so it can't leak into a later launch.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	if _is_hotseat():
		MenuNav.change_scene(self, MP_MODE_SELECT_SCENE)
	else:
		MenuNav.change_scene(self, SOLO_MODE_SELECT_SCENE)


func _show_message(text: String) -> void:
	if _message_label == null:
		return
	MenuKit.set_status(_message_label, text, "error")
	_message_label.visible = true


# --- Keyboard / gamepad -------------------------------------------------------
#
# Focus drives everything (MenuNav): the map list takes Up/Down itself (selecting as it
# moves) and Enter on a row starts; Tab / D-pad reach the settings column and the footer.
# Back / Esc / pad B returns to the mode picker. F5 re-reads the map library.

func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_F5:
			if _uses_map_list():
				get_viewport().set_input_as_handled()
				refresh_map_list()
		KEY_ENTER, KEY_KP_ENTER:
			# Nothing focused consumed Enter: start with what is selected.
			if _start_btn != null and not _start_btn.disabled:
				get_viewport().set_input_as_handled()
				_on_start_pressed()


func _move_map_selection(delta: int) -> void:
	if _map_list == null or _map_list.get_item_count() == 0:
		return
	var selected := _map_list.get_selected_items()
	var current := selected[0] if selected.size() > 0 else 0
	var next := clampi(current + delta, 0, _map_list.get_item_count() - 1)
	if next != current:
		_map_list.select(next)
		_on_map_selected(next)
		_map_list.ensure_current_is_visible()
