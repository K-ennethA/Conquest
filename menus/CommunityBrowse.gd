extends Control

class_name CommunityBrowse

## Browse, rank and download COMMUNITY maps + challenges. The sibling of [ChallengeBrowse]
## (which handles the player's own local challenges + share codes); this screen is the
## public square where other players' creations surface, get voted on, and are pulled into
## the local library. Dark "Legends" register via [MenuTheme].
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

const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const MY_BASES_SCENE := "res://menus/MyBases.tscn"

## Mirrors [code]CommunityProvider.SORT_RECOMMENDED[/code] (byte-identical string). Held here
## rather than referenced so this screen still PARSES in a tree where the client-side constant
## has not landed yet -- a missing constant is a load-time error that would take the whole
## screen down, while the value itself is part of the pinned wire vocabulary.
const SORT_RECOMMENDED := "recommended"

## How long the search field stays quiet before the query is sent.
const SEARCH_DEBOUNCE := 0.4

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


## Inject the community client. Call BEFORE the node enters the tree (the script is live as
## soon as it is set, `_ready` is not) -- `_ready` only builds the real client when none was
## supplied, so a test never touches the on-disk sandbox.
func set_community_client(client) -> void:
	_client = client


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	if _client == null:
		_client = CommunityClient.new()
	_build_ui()
	_refresh_banner()
	_load_daily_then_list()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	# 700 not 660: raised alongside the scroll-floor trim below so the list (the page's
	# only EXPAND_FILL region) still gets real height back, while staying a 20px-safe
	# budget under the 720p viewport (no MarginContainer here -- this page IS the
	# viewport). 660 was already too small to matter: the WORST case (offline banner +
	# Load-more both visible) summed to ~785 on its own, well past even 720, so the
	# explicit floor was never the binding constraint -- the fixed items were.
	page.custom_minimum_size = Vector2(820.0, 700.0)
	page.add_theme_constant_override("separation", 16)
	center.add_child(page)

	var title := Label.new()
	title.text = "COMMUNITY"
	page.add_child(title)
	# 32 not 40: worst case (offline banner shown + Load-more visible) the fixed items --
	# title(52) + subtitle(21) + banner(16) + filter bar(40) + list(380 scroll + 24 panel
	# padding) + load-more(40) + status(20) + actions(48) + hint(16) -- plus 8 gaps * 16
	# separation summed to ~785 against a 720 screen: the Back button rendered off the
	# bottom edge even in the common case (~729 with banner/load-more hidden). Trimming
	# the title and the scroll floor (below) is what actually fixes it.
	MenuTheme.style_title(title, 32)

	var subtitle := Label.new()
	subtitle.text = "Discover, rank and download maps and challenges built by other players"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	# Offline banner (only shown in local mode; text set in _refresh_banner).
	_banner = Label.new()
	_banner.visible = false
	MenuTheme.style_caption(_banner)
	_banner.add_theme_color_override("font_color", MenuTheme.GOLD)
	page.add_child(_banner)

	# Filter bar: sort tabs on the left, type filter on the right.
	page.add_child(_build_filter_bar())

	# Search row (one more 40px fixed item; see the scroll floor below for the budget).
	page.add_child(_build_search_row())

	# The scrolling card list.
	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 150 not 380: list_card above is already SIZE_EXPAND_FILL, so this scroll is the
	# page's ONLY flexible region and its floor is what decides whether the footer fits.
	# Worst case (offline banner + Load-more both visible) the fixed items now sum to
	#   title 52 + subtitle 21 + banner 16 + filter bar 40 + SEARCH ROW 40 + list card
	#   (150 floor + 24 panel padding) + load-more 40 + status 20 + actions 48 + hint 16
	#   = 467, plus 9 gaps * 16 separation = 144  ->  611
	# against the page's 700 budget (itself 20px clear of a 720p viewport). The leftover
	# 89px flows back into this scroll via EXPAND_FILL (~239px of rows). The search row
	# cost 56 of the old ~145px of slack; there is still room, but the next fixed item
	# added to this page must re-run this sum, not eyeball it.
	scroll.custom_minimum_size = Vector2(0.0, 150.0)
	list_card.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_list_box)

	# Load more.
	_load_more_btn = Button.new()
	_load_more_btn.text = "Load more"
	_load_more_btn.custom_minimum_size = Vector2(0.0, 40.0)
	_load_more_btn.visible = false
	_load_more_btn.pressed.connect(_on_load_more)
	page.add_child(_load_more_btn)

	# Status line (download results / errors).
	_status = Label.new()
	_status.custom_minimum_size = Vector2(0.0, 20.0)
	MenuTheme.style_caption(_status)
	page.add_child(_status)

	# Actions.
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	page.add_child(actions)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(200.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

	# My Bases lives beside Back rather than in the list: it is the OTHER half of the
	# community loop (what you published and how it is holding up), not a browse filter.
	var bases := Button.new()
	bases.text = "My Bases"
	bases.custom_minimum_size = Vector2(200.0, 48.0)
	var bases_available: bool = ResourceLoader.exists(MY_BASES_SCENE)
	bases.disabled = not bases_available
	bases.tooltip_text = "Your published challenges and how their defenses are holding." \
		if bases_available else "The base screen is not available in this build."
	bases.pressed.connect(_on_my_bases_pressed)
	actions.add_child(bases)

	var hint := Label.new()
	hint.text = "Search  •  Recommended / Top / New / Daily  •  vote and Download  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## The search field. Debounced (see the class docs): typing restarts [member _search_timer],
## Enter flushes immediately, and Clear empties the field which debounces back to the feed.
func _build_search_row() -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 40.0)
	row.add_theme_constant_override("separation", 10)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search by title or author..."
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.text_submitted.connect(func(_t: String): _flush_search())
	row.add_child(_search_edit)

	# The debounce clock. One-shot and RESTARTED per keystroke, so only the pause at the
	# end of typing costs a request.
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DEBOUNCE
	_search_timer.timeout.connect(_flush_search)
	row.add_child(_search_timer)

	var clear := Button.new()
	clear.text = "Clear"
	# Explicit minimum: this button's label is its only content, and a chip-sized button
	# with no explicit floor collapses to its text width on a narrow layout.
	clear.custom_minimum_size = Vector2(96.0, 40.0)
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


func _build_filter_bar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)

	# Sort tabs.
	var sort_row := HBoxContainer.new()
	sort_row.add_theme_constant_override("separation", 6)
	bar.add_child(sort_row)
	# Recommended leads AND is the default (see [member _sort]): the server-ranked feed is the
	# one that surfaces a challenge a player has not seen, which is the point of the screen.
	# Top/New/Daily stay, unchanged, one click away. Widths: 136 + 3*88 + 3*6 gaps = 418,
	# against the type row's 3*96 + 2*6 = 300 and the page's 820 floor -- the bar fits with
	# ~80px to spare, so the spacer between them never collapses.
	for spec in [
		{"label": "Recommended", "value": SORT_RECOMMENDED, "width": 136.0},
		{"label": "Top", "value": CommunityProvider.SORT_TOP, "width": 88.0},
		{"label": "New", "value": CommunityProvider.SORT_NEW, "width": 88.0},
		{"label": "Daily", "value": CommunityProvider.SORT_DAILY, "width": 88.0},
	]:
		var b := Button.new()
		b.text = String(spec["label"])
		b.custom_minimum_size = Vector2(float(spec["width"]), 40.0)
		var value: String = String(spec["value"])
		b.pressed.connect(func(): _on_sort_selected(value))
		sort_row.add_child(b)
		_sort_btns[value] = b

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	# Type filter.
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 6)
	bar.add_child(type_row)
	for spec in [
		{"label": "Maps", "value": CommunityProvider.TYPE_MAP},
		{"label": "Challenges", "value": CommunityProvider.TYPE_CHALLENGE},
		{"label": "All", "value": CommunityProvider.TYPE_ALL},
	]:
		var b := Button.new()
		b.text = String(spec["label"])
		b.custom_minimum_size = Vector2(96.0, 40.0)
		var value: String = String(spec["value"])
		b.pressed.connect(func(): _on_type_selected(value))
		type_row.add_child(b)
		_type_btns[value] = b

	_sync_filter_highlights()
	return bar


## Mark the active sort + type buttons with the gold "SelectedButton" chip look.
func _sync_filter_highlights() -> void:
	for value in _sort_btns:
		_sort_btns[value].theme_type_variation = "SelectedButton" if value == _sort else &"Button"
	for value in _type_btns:
		_type_btns[value].theme_type_variation = "SelectedButton" if value == _type else &"Button"


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
		_set_status("Could not load community items: %s" % String(result.get("error", "unknown error")))
		if _load_more_btn != null:
			_load_more_btn.visible = false
		return

	var items: Array = result.get("data", []) if result.get("data", []) is Array else []
	if _page == 0 and items.is_empty():
		var empty := Label.new()
		empty.text = "No results for \"%s\". Try a different title or author." % _query \
			if not _query.is_empty() \
			else "Nothing here yet. Be the first to share a map or challenge!"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(empty)
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

	var panel := PanelContainer.new()
	var accent: Color = MenuTheme.GOLD if item_type == CommunityProvider.TYPE_CHALLENGE else MenuTheme.BORDER
	if is_daily:
		accent = MenuTheme.GOLD
	panel.add_theme_stylebox_override("panel", MenuTheme.card_box(accent))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
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
	name_row.add_theme_constant_override("separation", 8)
	info.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = String(item.get("name", "Untitled"))
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	# A player-authored title is arbitrary length: clip + ellipsis so it can never push the
	# chips, vote column and Download button off the right edge of the card.
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	name_row.add_child(name_lbl)

	name_row.add_child(MenuTheme.make_chip(
		"CHALLENGE" if item_type == CommunityProvider.TYPE_CHALLENGE else "MAP",
		MenuTheme.GOLD if item_type == CommunityProvider.TYPE_CHALLENGE else MenuTheme.CREAM_DIM))
	if is_daily:
		name_row.add_child(MenuTheme.make_chip("DAILY", MenuTheme.GOLD))

	var author_lbl := Label.new()
	var author: String = String(item.get("author", "")).strip_edges()
	author_lbl.text = "by %s" % author if not author.is_empty() else "by unknown"
	author_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	author_lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	info.add_child(author_lbl)

	var meta_lbl := Label.new()
	meta_lbl.text = _meta_line(item)
	meta_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	meta_lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	info.add_child(meta_lbl)

	# --- Vote controls ---
	row.add_child(_make_vote_controls(id, item))

	# --- Download ---
	var download_btn := Button.new()
	download_btn.text = "Download"
	download_btn.custom_minimum_size = Vector2(120.0, 0.0)
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
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(64.0, 64.0)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var id: String = String(item.get("id", ""))
	var item_type: String = String(item.get("type", ""))

	if item_type == CommunityProvider.TYPE_MAP:
		if _thumb_cache.has(id):
			holder.add_child(_texture_rect(_thumb_cache[id]))
		else:
			var placeholder := Label.new()
			placeholder.text = "..."
			placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			MenuTheme.style_caption(placeholder)
			holder.add_child(placeholder)
			_generate_thumb_async(id, holder)
	else:
		var glyph := Label.new()
		glyph.text = "@"  # simple non-map glyph for challenges
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_color_override("font_color", MenuTheme.GOLD)
		glyph.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
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
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(88.0, 0.0)
	box.add_theme_constant_override("separation", 2)

	var up := Button.new()
	up.text = "Up"
	up.custom_minimum_size = Vector2(80.0, 30.0)
	up.pressed.connect(func(): _on_vote(id, 1))
	box.add_child(up)

	var votes_lbl := Label.new()
	votes_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	votes_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	box.add_child(votes_lbl)

	var down := Button.new()
	down.text = "Down"
	down.custom_minimum_size = Vector2(80.0, 30.0)
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
		up.theme_type_variation = "SelectedButton" if my_vote == 1 else &"Button"
	if down != null:
		down.theme_type_variation = "SelectedButton" if my_vote == -1 else &"Button"


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
			_set_status("Vote failed: %s" % String(result.get("error", "unknown error")))
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
				_set_status("'%s' is already in your library." % String(item.get("name", "item")))
			else:
				btn.text = "Downloaded"
				_set_status("Downloaded '%s' to your library." % String(item.get("name", "item")))
		else:
			btn.text = "Retry"
			btn.disabled = false
			_set_status("Download failed: %s" % String(result.get("error", "unknown error")))
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


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


## Open the player's own published bases. Guarded like the ChallengeBrowse -> Community hop:
## a build without the scene reports it rather than changing scene to a missing path.
func _on_my_bases_pressed() -> void:
	if not ResourceLoader.exists(MY_BASES_SCENE):
		_set_status("The base screen is not available in this build.")
		return
	get_tree().change_scene_to_file(MY_BASES_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		# Don't steal typing (or ESC-to-dismiss) while the search field is focused.
		if _search_edit != null and _search_edit.has_focus():
			return
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_DOWN:
				var next := find_next_valid_focus()
				if next != null:
					next.grab_focus()
			KEY_UP:
				var prev := find_prev_valid_focus()
				if prev != null:
					prev.grab_focus()
