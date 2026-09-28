extends Control

class_name CommunityBrowse

## Browse, rank and download COMMUNITY maps + challenges. The sibling of [ChallengeBrowse]
## (which handles the player's own local challenges + share codes); this screen is the
## public square where other players' creations surface, get voted on, and are pulled into
## the local library. Built on the shared grove page ([MenuKit.build_page], [MenuTheme] --
## see docs/UI_STYLE.md).
##
## It talks only to [CommunityClient], which hides whether we are online (an [HttpProvider]
## against a configured service) or offline (the [LocalProvider] sandbox). When offline a
## banner says so. Sorting (Recommended / Top / New / Daily), a free-text search and a type
## filter (Maps / Challenges / All) drive the list; each card shows a lazily-generated minimap
## thumbnail (maps), a net vote score with up/down buttons (optimistic, reverts on error), a
## derived defense readout for challenges, and a Download button that routes through the
## client's hardened validate+save path.
##
## Every dependency is null-guarded so a missing autoload or unreadable payload degrades to
## a message rather than a crash.
##
## SEARCH is DEBOUNCED, not submit-on-enter: typing restarts a 0.4s one-shot timer and the
## query fires when the player stops. Enter flushes it immediately (a shortcut, not the only
## way in), and emptying the field is just another query -- it debounces back to the plain
## browse feed. Debounce over submit because the sort tabs already reload on a single click;
## making search the one control that needs a second keystroke to commit would read as broken.
##
## Input: arrows / D-pad move focus between the tabs, the cards' vote + Download buttons and
## the footer; Prev / Next page (Q / R, LB / RB) cycles the sort tab; Cancel (Esc / B) goes
## back -- except while typing in the search field.
##
## 720p budget. MenuKit's header + footer leave the body ~466 of 720 (the search field sits
## on the title row, like the Compendium's, so it costs no height). Body rows (16 apart):
##   offline banner 22 (local sandbox only) + filter bar 44 + the list (ONE EXPAND_FILL
##   region, floor 150) + Load more 44 (only while more pages remain)
## worst case = 260 fixed + 3 * 16 = 308, leaving the list ~158; ~270 in the common case.

const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const MY_BASES_SCENE := "res://menus/MyBases.tscn"
## This device's own battle recordings. Sits beside My Bases in the footer because it is the
## same "your stuff" half of the loop; guarded by [method ResourceLoader.exists] like every
## other cross-screen hop here.
const MY_REPLAYS_SCENE := "res://menus/MyReplays.tscn"

## Mirrors [code]CommunityProvider.SORT_RECOMMENDED[/code] (byte-identical string). Held here
## rather than referenced so this screen still PARSES in a tree where the client-side constant
## has not landed yet -- a missing constant is a load-time error that would take the whole
## screen down, while the value itself is part of the pinned wire vocabulary.
const SORT_RECOMMENDED := "recommended"

## How long the search field stays quiet before the query is sent.
const SEARCH_DEBOUNCE := 0.4

# --- Entry hint (optional, additive) -----------------------------------------
# A caller that already knows WHAT the player came for sets these before changing scene, and
# `_ready` consumes them ONCE. Static, so they survive the scene change; consumed, so the
# next plain entry to this screen is the ordinary unfiltered browse feed rather than
# inheriting a filter set an hour ago. Nothing else about the screen changes: the type tabs
# are still there and still one click away.
#
#     CommunityBrowse.open_filtered(CommunityProvider.TYPE_MAP, "res://menus/MatchSetup.tscn")
#     get_tree().change_scene_to_file("res://menus/CommunityBrowse.tscn")

## The type tab to open on ("" = the screen's own default).
static var entry_type: String = ""
## Where Back goes ("" = the usual ChallengeBrowse). A screen that sent the player here to
## fetch something needs them BACK on itself, not on the general library.
static var entry_return_scene: String = ""

## Where Back goes for THIS instance, read off the hint in `_ready`.
var _return_scene: String = ""


## Open this screen pre-filtered. [param type] is a [CommunityProvider] TYPE_* value; an
## unrecognised one is ignored (the screen opens on its default) rather than filtering the
## list down to nothing. Both arguments are consumed by the next [method _ready].
static func open_filtered(type: String, return_scene: String = "") -> void:
	entry_type = type
	entry_return_scene = return_scene

# --- State ------------------------------------------------------------------
## Untyped on purpose: tests inject a stand-in client, and the pinned client API
## (`list_items`'s trailing query, `my_bases`, `set_base_active`) is owned by a parallel
## workstream -- an untyped handle keeps this screen from hard-binding to an arity.
## Set it with [method set_community_client] BEFORE the node enters the tree.
var _client = null
var _sort: String = SORT_RECOMMENDED
var _type: String = CommunityProvider.TYPE_ALL
var _page: int = 0
var _loading: bool = false
var _daily_id: String = ""
## The live search string ("" = the plain browse feed).
var _query: String = ""

## Per-card live state, keyed by item id: {votes, my_vote, votes_label, up_btn, down_btn,
## download_btn, item}.
var _cards: Dictionary = {}
## Minimap textures generated lazily from map payloads, keyed by item id.
var _thumb_cache: Dictionary = {}

# --- Node refs --------------------------------------------------------------
var _list_box: VBoxContainer = null
var _load_more_btn: Button = null
var _status: Label = null
var _banner: Label = null
var _sort_btns: Dictionary = {}
var _type_btns: Dictionary = {}
var _search_edit: LineEdit = null
var _search_timer: Timer = null
var _back_btn: Button = null


## Inject the community client. Call BEFORE the node enters the tree (the script is live as
## soon as it is set, `_ready` is not) -- `_ready` only builds the real client when none was
## supplied, so a test never touches the on-disk sandbox.
func set_community_client(client) -> void:
	_client = client


func _ready() -> void:
	_consume_entry_hint()
	if _client == null:
		_client = CommunityClient.new()
	_build_ui()
	_refresh_banner()
	_load_daily_then_list()


## Read the entry hint and CLEAR it, before `_build_ui` so the filter bar is built with the
## right tab already highlighted and the first page load asks for the right type. Runs before
## anything else in `_ready`: an unconsumed hint would leak into the next entry.
func _consume_entry_hint() -> void:
	var hinted_type: String = entry_type
	_return_scene = entry_return_scene
	entry_type = ""
	entry_return_scene = ""
	# Validated, not trusted: an unknown type would ask the service for a filter nothing
	# matches, which reads to the player as "the community is empty".
	if hinted_type == CommunityProvider.TYPE_MAP \
			or hinted_type == CommunityProvider.TYPE_CHALLENGE \
			or hinted_type == CommunityProvider.TYPE_ALL:
		_type = hinted_type


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var page := MenuKit.build_page(self, _crumbs(), "Community",
		"Discover, rank and download maps and challenges built by other players.")

	# Search on the title row (right of "Community"), the Compendium's placement, so the
	# list keeps its height.
	var title_row := (page.title as Control).get_parent()
	var search_row := _build_search_row()
	if title_row is HBoxContainer:
		title_row.add_child(search_row)
	else:
		page.body.add_child(search_row)

	# Offline banner (only shown in local mode; text set in _refresh_banner).
	_banner = MenuKit.label("", &"DimLabel")
	_banner.name = "OfflineBanner"
	_banner.visible = false
	_banner.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_banner.add_theme_color_override("font_color", MenuTheme.WARNING)
	page.body.add_child(_banner)

	# Filter bar: sort tabs on the left, type filter on the right.
	page.body.add_child(_build_filter_bar())

	# The scrolling card list, in a sunken well.
	var list_well := MenuKit.card(&"InsetPanel")
	list_well.name = "ItemList"
	list_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(list_well)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	# The page's ONLY flexible region; its floor is what decides whether the footer fits
	# in the worst case (see the class budget). EXPAND_FILL hands it every spare pixel.
	scroll.custom_minimum_size = Vector2(0.0, 150.0)
	list_well.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 4)
	pad.add_theme_constant_override("margin_right", 14)  # focus glow + scrollbar
	scroll.add_child(pad)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", MenuTheme.SP_M)
	pad.add_child(_list_box)

	# Load more.
	_load_more_btn = MenuKit.button("Load more", &"", 0, 44)
	_load_more_btn.name = "LoadMoreButton"
	_load_more_btn.visible = false
	_load_more_btn.pressed.connect(_on_load_more)
	page.body.add_child(_load_more_btn)

	# Status line (download results / errors) lives in the footer, beside the key hints.
	page.hints.add_child(MenuKit.key_hint("Q / R", "LB / RB", "Sort"))
	page.hints.add_child(MenuKit.key_hint("Esc", "B", "Back"))
	_status = MenuKit.label("", &"DimLabel")
	_status.name = "StatusLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	page.hints.add_child(_status)

	# Actions.
	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)

	# My Bases lives beside Back rather than in the list: it is the OTHER half of the
	# community loop (what you published and how it is holding up), not a browse filter.
	var bases := MenuKit.button("My Bases", &"", 170)
	bases.name = "MyBasesButton"
	var bases_available: bool = ResourceLoader.exists(MY_BASES_SCENE)
	bases.disabled = not bases_available
	bases.tooltip_text = "Your published challenges and how their defenses are holding." \
		if bases_available else "The base screen is not available in this build."
	bases.pressed.connect(_on_my_bases_pressed)
	page.actions.add_child(bases)

	var replays := MenuKit.button("My Replays", &"", 190)
	replays.name = "MyReplaysButton"
	var replays_available: bool = ResourceLoader.exists(MY_REPLAYS_SCENE)
	replays.disabled = not replays_available
	replays.tooltip_text = "Battles this device recorded." if replays_available \
		else "The replay screen is not available in this build."
	replays.pressed.connect(_on_my_replays_pressed)
	page.actions.add_child(replays)

	_focus_later(_sort_btns.get(_sort, _back_btn))


## The breadcrumb path BEFORE this screen: the challenge library by default, or whichever
## screen sent the player here through the entry hint (e.g. Match Setup's "Get more maps").
func _crumbs() -> Array:
	if not _return_scene.is_empty():
		return [_return_scene.get_file().get_basename().capitalize()]
	return ["Online", "Challenges"]


## The search field. Debounced (see the class docs): typing restarts [member _search_timer],
## Enter flushes immediately, and Clear empties the field which debounces back to the feed.
func _build_search_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "SearchRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", MenuTheme.SP_M)

	_search_edit = LineEdit.new()
	_search_edit.name = "SearchEdit"
	_search_edit.placeholder_text = "Search by title or author..."
	_search_edit.custom_minimum_size = Vector2(420.0, 44.0)
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.text_submitted.connect(func(_t: String): _flush_search())
	MenuNav.hover_focus(_search_edit)
	row.add_child(_search_edit)

	# The debounce clock. One-shot and RESTARTED per keystroke, so only the pause at the
	# end of typing costs a request.
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE
	_search_timer.timeout.connect(_flush_search)
	row.add_child(_search_timer)

	# Explicit minimum: this button's label is its only content, and a chip-sized button
	# with no explicit floor collapses to its text width on a narrow layout.
	var clear := MenuKit.button("Clear", MenuKit.GHOST, 110, 44)
	clear.name = "ClearSearchButton"
	clear.pressed.connect(_on_search_cleared)
	row.add_child(clear)

	return row


## Restart the debounce. The query itself is read in [method _flush_search], so a keystroke
## that lands after the timer already fired simply starts a fresh one.
func _on_search_text_changed(_text: String) -> void:
	if _search_timer != null:
		_search_timer.start(SEARCH_DEBOUNCE)


## Send the field's current contents as the query, if it actually changed. Called by the
## debounce timeout, by Enter, and by Clear -- all three land here so there is one path.
func _flush_search() -> void:
	if _search_timer != null:
		_search_timer.stop()
	var next: String = _search_edit.text.strip_edges() if _search_edit != null else ""
	if next == _query:
		return
	_query = next
	_reload()


func _on_search_cleared() -> void:
	if _search_edit != null:
		_search_edit.text = ""
	_flush_search()


## Sort tabs (left) and type filter (right) as toggle buttons: the active one holds the
## theme's gold pressed plate.
func _build_filter_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.name = "FilterBar"
	bar.add_theme_constant_override("separation", MenuTheme.SP_M)

	# Sort tabs. Recommended leads AND is the default (see [member _sort]): the server-ranked
	# feed is the one that surfaces a challenge a player has not seen, which is the point of
	# the screen. Top/New/Daily stay, unchanged, one click away.
	bar.add_child(MenuKit.section("Sort"))
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	bar.add_child(sort_row)
	for spec in [
		{"label": "Recommended", "value": SORT_RECOMMENDED},
		{"label": "Top", "value": CommunityProvider.SORT_TOP},
		{"label": "New", "value": CommunityProvider.SORT_NEW},
		{"label": "Daily", "value": CommunityProvider.SORT_DAILY},
	]:
		var b := _make_filter_button(String(spec["label"]))
		var value: String = String(spec["value"])
		b.pressed.connect(func(): _on_sort_selected(value))
		sort_row.add_child(b)
		_sort_btns[value] = b

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Type filter.
	bar.add_child(MenuKit.section("Show"))
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 6)
	bar.add_child(type_row)
	for spec in [
		{"label": "Maps", "value": CommunityProvider.TYPE_MAP},
		{"label": "Challenges", "value": CommunityProvider.TYPE_CHALLENGE},
		{"label": "All", "value": CommunityProvider.TYPE_ALL},
	]:
		var b := _make_filter_button(String(spec["label"]))
		var value: String = String(spec["value"])
		b.pressed.connect(func(): _on_type_selected(value))
		type_row.add_child(b)
		_type_btns[value] = b

	for child in bar.get_children():
		if child is Label:
			(child as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			(child as Label).size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_sync_filter_highlights()
	return bar


func _make_filter_button(text: String) -> Button:
	var b := MenuKit.button(text, &"", 0, 44)
	b.toggle_mode = true
	return b


## Mark the active sort + type buttons: the toggle's gold pressed plate is the look; the
## "SelectedButton" variation name is kept on the active one as the readable marker.
func _sync_filter_highlights() -> void:
	for value in _sort_btns:
		_set_filter_active(_sort_btns[value], value == _sort)
	for value in _type_btns:
		_set_filter_active(_type_btns[value], value == _type)


func _set_filter_active(b: Button, active: bool) -> void:
	b.set_pressed_no_signal(active)
	b.theme_type_variation = &"SelectedButton" if active else &""


func _refresh_banner() -> void:
	if _banner == null or _client == null or not _client.has_method("is_local"):
		return
	if _client.is_local():
		_banner.text = "Showing local sandbox -- community service not connected"
		_banner.visible = true
	else:
		_banner.visible = false


# --- Loading ----------------------------------------------------------------

func _load_daily_then_list() -> void:
	if _client == null:
		return
	_client.daily(func(result: Dictionary):
		if bool(result.get("ok", false)):
			var data: Variant = result.get("data", {})
			if data is Dictionary:
				_daily_id = String((data as Dictionary).get("id", ""))
		_reload()
	)


## Reset the list and load page 0 for the current sort + type.
func _reload() -> void:
	_page = 0
	_cards.clear()
	if _list_box != null:
		for child in _list_box.get_children():
			child.queue_free()
	_set_status("")
	_load_page()


func _load_page() -> void:
	if _client == null or _loading:
		return
	_loading = true
	if _load_more_btn != null:
		_load_more_btn.disabled = true
	# The trailing query is part of the pinned client contract; "" is the plain browse feed.
	_client.list_items(_sort, _type, _page, func(result: Dictionary): _on_page_loaded(result), _query)


func _on_page_loaded(result: Dictionary) -> void:
	# A page can land after the screen closed (or after a newer query replaced this one):
	# the LocalProvider answers synchronously but HttpProvider does not, so nothing here may
	# assume the nodes are still alive.
	if _list_box == null or not is_instance_valid(_list_box):
		return
	_loading = false
	if _load_more_btn != null:
		_load_more_btn.disabled = false
	if not bool(result.get("ok", false)):
		_set_status("Could not load community items: %s" % String(result.get("error", "unknown error")), "error")
		if _load_more_btn != null:
			_load_more_btn.visible = false
		return

	var items: Array = result.get("data", []) if result.get("data", []) is Array else []
	if _page == 0 and items.is_empty():
		var empty := MenuKit.label("No results for \"%s\". Try a different title or author." % _query \
			if not _query.is_empty() \
			else "Nothing here yet. Be the first to share a map or challenge!", &"DimLabel", true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _list_box != null:
			_list_box.add_child(empty)

	for it in items:
		if it is Dictionary and _list_box != null:
			_list_box.add_child(_make_card(it))

	# More pages likely remain only if this page came back full.
	if _load_more_btn != null:
		_load_more_btn.visible = items.size() >= CommunityProvider.PAGE_SIZE


func _on_load_more() -> void:
	_page += 1
	_load_page()


# --- Card construction ------------------------------------------------------

func _make_card(item: Dictionary) -> Control:
	var id: String = String(item.get("id", ""))
	var item_type: String = String(item.get("type", ""))
	var is_daily: bool = not _daily_id.is_empty() and id == _daily_id

	# A grove card per item: challenges carry a gold edge, maps the plain frame, and
	# today's DAILY pick is a hero surface (gold edge + crest).
	var panel := PanelContainer.new()
	var sb: OrnateStyleBox
	if item_type == CommunityProvider.TYPE_CHALLENGE or is_daily:
		sb = MenuTheme.accented_card(MenuTheme.GOLD, SIDE_LEFT, MenuTheme.PANEL, 0.96, is_daily)
	else:
		sb = MenuTheme.card_box()
	sb.content_margin_left = 18.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 18.0 if is_daily else 14.0
	sb.content_margin_bottom = 12.0
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	panel.add_child(row)

	# --- Thumbnail (maps get a lazily-generated minimap; others a type glyph) ---
	var thumb := _make_thumb_slot(item)
	row.add_child(thumb)

	# --- Name + author + meta ---
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", MenuTheme.SP_S)
	info.add_child(name_row)

	var name_lbl := MenuKit.label(String(item.get("name", "Untitled")), &"SubheadingLabel")
	# A player-authored title is arbitrary length: clip + ellipsis so it can never push the
	# chips, vote column and Download button off the right edge of the card.
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	name_row.add_child(name_lbl)

	var type_badge := MenuKit.badge(
		"CHALLENGE" if item_type == CommunityProvider.TYPE_CHALLENGE else "MAP",
		MenuTheme.GOLD if item_type == CommunityProvider.TYPE_CHALLENGE else MenuTheme.ACCENT)
	type_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(type_badge)
	if is_daily:
		var daily_badge := MenuKit.badge("DAILY", MenuTheme.GOLD, true)
		daily_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(daily_badge)

	var author: String = String(item.get("author", "")).strip_edges()
	var author_lbl := MenuKit.label("by %s" % author if not author.is_empty() else "by unknown",
		&"DimLabel")
	author_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	info.add_child(author_lbl)

	var meta_lbl := MenuKit.label(_meta_line(item), &"MutedLabel")
	meta_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	info.add_child(meta_lbl)

	# --- Vote controls ---
	row.add_child(_make_vote_controls(id, item))

	# --- Download ---
	var download_btn := MenuKit.button("Download", &"", 150, 46)
	download_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	download_btn.pressed.connect(func(): _on_download(id, item, download_btn))
	row.add_child(download_btn)

	# Register card state.
	var state: Dictionary = _cards.get(id, {})
	state["item"] = item
	state["download_btn"] = download_btn
	_cards[id] = state

	return panel


## A 64x64 thumbnail slot. For map items we lazily fetch the payload, validate it into a
## MapResource and render a MapPreview minimap (cached by id); other types get a glyph.
func _make_thumb_slot(item: Dictionary) -> Control:
	# The map thumbnail frame: a sunk well with a gold-dark edge.
	var holder := PanelContainer.new()
	var frame := MenuTheme.inset_box()
	frame.corner = 6.0
	frame.border_color = MenuTheme.GOLD_DK
	frame.set_content_margin_all(3)
	holder.add_theme_stylebox_override("panel", frame)
	holder.custom_minimum_size = Vector2(70.0, 70.0)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var id: String = String(item.get("id", ""))
	var item_type: String = String(item.get("type", ""))

	if item_type == CommunityProvider.TYPE_MAP:
		if _thumb_cache.has(id):
			holder.add_child(_texture_rect(_thumb_cache[id]))
		else:
			var placeholder := MenuKit.label("...", &"MutedLabel")
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			holder.add_child(placeholder)
			_generate_thumb_async(id, holder)
	else:
		# Non-map items (challenges) get a small heraldic crest instead of a minimap.
		var glyph := MenuKit.crest("C", MenuTheme.GOLD_DK, MenuTheme.GOLD, 52.0)
		glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		holder.add_child(glyph)

	return holder


func _texture_rect(texture: Texture2D) -> TextureRect:
	var rect := MapPreview.make_texture_rect(texture)
	rect.custom_minimum_size = Vector2(60.0, 60.0)
	return rect


## Fetch + render a map thumbnail without blocking. On success the placeholder in
## [param holder] is replaced with the minimap; on failure it is left as-is.
func _generate_thumb_async(id: String, holder: Control) -> void:
	if _client == null:
		return
	_client.fetch_item(id, func(result: Dictionary):
		if not is_instance_valid(holder):
			return
		if not bool(result.get("ok", false)):
			return
		var payload: Variant = result.get("data", {})
		if not (payload is Dictionary):
			return
		# Catalog-strict by construction; `true` is the quiet flag (a thumbnail for an
		# unimportable map is an expected miss, not an error worth logging).
		var res: MapResource = MapResource.import_from_json(JSON.stringify(payload), true)
		if res == null:
			return
		var texture: ImageTexture = MapPreview.generate(res)
		if texture == null:
			return
		_thumb_cache[id] = texture
		# remove_child before queue_free so the container is single-child immediately (a
		# LocalProvider callback lands synchronously, mid-build).
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
		holder.add_child(_texture_rect(texture))
	)


## "Attacked 42  •  defended 71%  •  1.2 KB" style meta, omitting fields that don't apply.
## The defense readout is CHALLENGE-only: a bare map is never attacked, so a "0 attacks" line
## on one would be noise rather than information.
func _meta_line(item: Dictionary) -> String:
	var parts: Array = []
	if String(item.get("type", "")) == CommunityProvider.TYPE_CHALLENGE:
		parts.append(defense_label(item))
	var size_bytes: int = int(item.get("size_bytes", 0))
	if size_bytes > 0:
		parts.append(_fmt_size(size_bytes))
	return "   •   ".join(PackedStringArray(parts))


# --- Derived defense figures (pure; the single source of truth) --------------
# The service stores COUNTERS only -- attempts (how many players attacked this base) and
# clears (how many of them won). Everything the UI shows is arithmetic over those two, done
# here so the browse cards and the My Bases slots can never disagree. Static + dictionary-in
# so it is directly unit-testable with no screen in the tree.

## Derived figures for an item summary: { attacked, defended, rate }.
## [code]rate[/code] is 0.0..1.0, or -1.0 when the base has NEVER been attacked -- 0/0 is not
## 100%, it is "no data", and the sentinel forces every caller to say so in words.
## A payload claiming more clears than attempts is clamped rather than trusted (it is
## untrusted server data), so [code]defended[/code] can never go negative.
static func defense_stats(item: Dictionary) -> Dictionary:
	var attacked: int = maxi(0, int(item.get("attempts", 0)))
	var clears: int = clampi(int(item.get("clears", 0)), 0, attacked)
	var defended: int = attacked - clears
	var rate: float = -1.0 if attacked <= 0 else float(defended) / float(attacked)
	return {"attacked": attacked, "defended": defended, "rate": rate}


## One subtle line for a card: "Attacked 42   ·   defended 71%", or the honest
## "Not attacked yet" when there is nothing to average.
static func defense_label(item: Dictionary) -> String:
	var stats: Dictionary = defense_stats(item)
	var rate: float = float(stats["rate"])
	if rate < 0.0:
		return "Not attacked yet"
	return "Attacked %d   ·   defended %d%%" % [int(stats["attacked"]), defense_percent(item)]


## The defense rate as a whole percent. Returns -1 when the base has never been attacked, so
## a caller that formats it itself still cannot print "100%" for an untested base.
static func defense_percent(item: Dictionary) -> int:
	var rate: float = float(defense_stats(item)["rate"])
	if rate < 0.0:
		return -1
	return int(round(100.0 * rate))


func _fmt_size(bytes: int) -> String:
	if bytes >= 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes


# --- Voting -----------------------------------------------------------------

func _make_vote_controls(id: String, item: Dictionary) -> Control:
	# Up / score / Down. The two vote buttons are toggles: the player's current vote holds
	# the theme's gold pressed plate (see _update_vote_ui).
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(96.0, 0.0)
	box.add_theme_constant_override("separation", 2)

	var up := MenuKit.button("Up", &"", 92, 34)
	up.toggle_mode = true
	up.pressed.connect(func(): _on_vote(id, 1))
	box.add_child(up)

	var votes_lbl := MenuKit.label("", &"SubheadingLabel")
	votes_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(votes_lbl)

	var down := MenuKit.button("Down", &"", 92, 34)
	down.toggle_mode = true
	down.pressed.connect(func(): _on_vote(id, -1))
	box.add_child(down)

	# Seed card vote state. my_vote comes from the local provider when available.
	var my_vote: int = 0
	# has_method, not just null: the handle is untyped so a stand-in client need not carry
	# the local-only extras at all.
	if _client != null and _client.has_method("provider") and _client.provider() is LocalProvider:
		my_vote = (_client.provider() as LocalProvider).my_vote(id)
	var state: Dictionary = _cards.get(id, {})
	state["votes"] = int(item.get("votes", 0))
	state["my_vote"] = my_vote
	state["votes_label"] = votes_lbl
	state["up_btn"] = up
	state["down_btn"] = down
	_cards[id] = state
	_update_vote_ui(id)

	return box


func _update_vote_ui(id: String) -> void:
	var state: Dictionary = _cards.get(id, {})
	if state.is_empty():
		return
	var lbl: Label = state.get("votes_label", null)
	if lbl != null:
		lbl.text = str(int(state.get("votes", 0)))
	var my_vote: int = int(state.get("my_vote", 0))
	var up: Button = state.get("up_btn", null)
	var down: Button = state.get("down_btn", null)
	if up != null:
		up.set_pressed_no_signal(my_vote == 1)
	if down != null:
		down.set_pressed_no_signal(my_vote == -1)
	if lbl != null:
		lbl.add_theme_color_override("font_color", MenuTheme.SUCCESS if my_vote == 1 \
			else (MenuTheme.DANGER if my_vote == -1 else MenuTheme.CREAM))


## Optimistic vote: apply locally at once, then confirm with the service; revert on error.
func _on_vote(id: String, dir: int) -> void:
	if _client == null:
		return
	var state: Dictionary = _cards.get(id, {})
	if state.is_empty():
		return
	var prev_my: int = int(state.get("my_vote", 0))
	var prev_votes: int = int(state.get("votes", 0))
	# Toggling the active direction clears the vote.
	var new_my: int = 0 if prev_my == dir else dir
	state["my_vote"] = new_my
	state["votes"] = prev_votes + (new_my - prev_my)
	_cards[id] = state
	_update_vote_ui(id)

	_client.vote(id, new_my, func(result: Dictionary):
		var s: Dictionary = _cards.get(id, {})
		if s.is_empty():
			return
		if bool(result.get("ok", false)):
			var data: Variant = result.get("data", {})
			if data is Dictionary and (data as Dictionary).has("votes"):
				s["votes"] = int((data as Dictionary)["votes"])
				_cards[id] = s
				_update_vote_ui(id)
		else:
			# Revert the optimistic change.
			s["my_vote"] = prev_my
			s["votes"] = prev_votes
			_cards[id] = s
			_update_vote_ui(id)
			_set_status("Vote failed: %s" % String(result.get("error", "unknown error")), "error")
	)


# --- Download ---------------------------------------------------------------

func _on_download(id: String, item: Dictionary, btn: Button) -> void:
	if _client == null:
		return
	btn.disabled = true
	btn.text = "..."
	_client.download_to_library(item, func(result: Dictionary):
		if not is_instance_valid(btn):
			return
		if bool(result.get("ok", false)):
			var data: Dictionary = result.get("data", {}) if result.get("data", {}) is Dictionary else {}
			var status: String = String(data.get("status", "downloaded"))
			if status == "already_owned":
				btn.text = "Owned"
				_set_status("'%s' is already in your library." % String(item.get("name", "item")), "info")
			else:
				btn.text = "Downloaded"
				_set_status("Downloaded '%s' to your library." % String(item.get("name", "item")), "ok")
				# A fresh MAP install is recorded in MapCatalog's community index so the
				# versus pickers badge it COMMUNITY instead of CUSTOM (the two are
				# byte-identical on disk -- the index is the only record). Only fresh
				# downloads: "already_owned" may be the player's own authored map.
				if String(data.get("type", "")) == CommunityProvider.TYPE_MAP:
					var catalog: Variant = load("res://game/maps/MapCatalog.gd")
					if catalog != null and catalog.has_method("note_community_install"):
						catalog.note_community_install(String(data.get("path", "")))
		else:
			btn.text = "Retry"
			btn.disabled = false
			_set_status("Download failed: %s" % String(result.get("error", "unknown error")), "error")
	)


# --- Filters / navigation ---------------------------------------------------

func _on_sort_selected(sort: String) -> void:
	if sort == _sort:
		return
	_sort = sort
	_sync_filter_highlights()
	_reload()


func _on_type_selected(type: String) -> void:
	if type == _type:
		return
	_type = type
	_sync_filter_highlights()
	_reload()


## The footer status line. [param tone] is MenuKit.set_status's: "", "info", "ok", "warn",
## "error".
func _set_status(text: String, tone: String = "") -> void:
	if _status != null:
		MenuKit.set_status(_status, text, tone)


## Step the sort tab by [param step] (Prev / Next page input), wrapping.
func _cycle_sort(step: int) -> void:
	var order: Array = _sort_btns.keys()
	if order.is_empty():
		return
	var i: int = order.find(_sort)
	var next: String = String(order[wrapi(i + step, 0, order.size())])
	_on_sort_selected(next)
	var btn: Button = _sort_btns.get(next, null)
	if btn != null and is_instance_valid(btn):
		btn.grab_focus()


## Back goes wherever the entry hint said, falling back to the challenge library. A screen
## that sent the player here to fetch a map needs them back on ITSELF -- that round trip is
## what makes a fresh download show up in the list it was fetched for.
func _on_back_pressed() -> void:
	if not _return_scene.is_empty() and ResourceLoader.exists(_return_scene):
		MenuNav.change_scene(self, _return_scene)
		return
	MenuNav.change_scene(self, CHALLENGE_BROWSE_SCENE)


## Open the player's own published bases. Guarded like the ChallengeBrowse -> Community hop:
## a build without the scene reports it rather than changing scene to a missing path.
func _on_my_bases_pressed() -> void:
	if not ResourceLoader.exists(MY_BASES_SCENE):
		_set_status("The base screen is not available in this build.", "warn")
		return
	MenuNav.change_scene(self, MY_BASES_SCENE)


## Open this device's own recordings. Same guard as the My Bases hop above.
func _on_my_replays_pressed() -> void:
	if not ResourceLoader.exists(MY_REPLAYS_SCENE):
		_set_status("The replay screen is not available in this build.", "warn")
		return
	MenuNav.change_scene(self, MY_REPLAYS_SCENE)


## Up / Down between controls is the engine's focus navigation (arrows, D-pad, stick).
## Unhandled input only: a focused control -- and above all the search field, where Cancel's
## Backspace / X / C are just typing -- always sees its keys first.
func _unhandled_input(event: InputEvent) -> void:
	if _search_edit != null and _search_edit.has_focus():
		return
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif MenuNav.is_next_event(event):
		get_viewport().set_input_as_handled()
		_cycle_sort(1)
	elif MenuNav.is_prev_event(event):
		get_viewport().set_input_as_handled()
		_cycle_sort(-1)


## [MenuNav.focus_deferred], but safe when the control leaves the tree first (a repaint
## rebuilt it, or the screen closed) -- grab_focus() on a detached control is an engine error.
func _focus_later(c: Control) -> void:
	if c == null:
		return
	# Captured by instance id, not by reference: a freed capture is itself an engine error.
	var id: int = c.get_instance_id()
	(func() -> void:
		var ctl := instance_from_id(id) as Control
		if ctl != null and ctl.is_inside_tree() and ctl.is_visible_in_tree():
			ctl.grab_focus()).call_deferred()
