extends Control

class_name MyBases

## The DEFENDER half of the community loop: the challenges this player published, and how
## their defenses are holding up against everyone who has attacked them. [CommunityBrowse] is
## where you go to attack other people's bases; this is where you see yours being attacked.
##
## Three SLOTS sit at the top, because "how many bases can I field" is the whole rule of the
## mode: at most [constant MAX_SLOTS] challenges may be active at once. A filled slot shows
## the title, how many players attacked it, how many it turned away, and the derived defense
## rate. An empty slot is an invitation, not a blank -- it says what to do to fill it and
## opens the PUBLISH flow.
##
## Everything below the slots is the bench: retired bases (and any active overflow the
## service reports) with a Reactivate / Retire action. Reactivate is disabled while all three
## slots are full, but the service is still the authority -- when it answers
## [code]base_limit[/code] anyway (another device claimed a slot first), that lands in the
## inline notice line, never as a crash.
##
## THREE FLOWS LIVE HERE, and two of them are OVERLAYS over this page rather than separate
## scenes, so the loaded bases survive a look and a publish (see [method _open_overlay]):
##
##   * ATTACK LOG -- every base card (slot or bench) opens a paged, newest-first list of the
##     attempts made against it: DEFENDED or CLEARED, the attacker's score and turn count,
##     when it happened, and -- when the attempt carries one -- a WATCH button. Watching
##     fetches the replay blob, decodes the container and hands the log to the playback
##     launcher; every way that can fail is a sentence in the overlay's notice line, sourced
##     from [code]ReplayWatch[/code] so the two replay screens can never word it differently.
##
##   * PUBLISH -- an empty slot picks one of the player's LOCAL authored challenges, confirms
##     it, and uploads it. This is the only caller of [method CommunityClient.upload] in the
##     game; before it, a challenge could be built and shared by code but never published.
##     The payload is the authored challenge dictionary itself (see [method _publish_payload]).
##
##   * MY REPLAYS -- a footer link to the sibling screen that lists this device's own
##     recordings. Deliberately its own scene, not a tab here: local recordings span every
##     mode, while this page is about community bases, and this page's 720p budget has no
##     room for a second flexible region.
##
## Talks only to [CommunityClient], through the same async {ok, data} / {ok:false, error}
## contract as the browse screen, and every callback re-checks the tree AND that the overlay
## it was launched from is still the one on screen: the local sandbox answers synchronously
## but a live service does not, so a reply can arrive after the player has already left,
## closed the panel, or opened a different base's log.

const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const COMMUNITY_SCENE := "res://menus/CommunityBrowse.tscn"
const MY_REPLAYS_SCENE := "res://menus/MyReplays.tscn"

## Shared replay copy + the codec/playback seams. Preloaded BY PATH, not by `class_name`:
## a brand new script is not in the project's global class cache until the project is next
## imported (the same reason the screen suites preload their subject by path).
const ReplayWatch := preload("res://menus/ReplayWatch.gd")

## How many bases may defend at once. The service enforces it; this screen mirrors it so the
## player is told BEFORE they press a button that cannot succeed.
const MAX_SLOTS := 3

## The invitation on an unclaimed slot. A constant so the wording is asserted by a test
## rather than retyped in two places.
const EMPTY_SLOT_INVITE := "Publish a challenge to claim this slot"

## Which panel (if any) is over the page. Read back by [method overlay_mode].
const OVERLAY_NONE := ""
const OVERLAY_ATTACK_LOG := "attack_log"
const OVERLAY_PUBLISH := "publish"
const OVERLAY_CONFIRM := "confirm"

## What one attempt READS as. The defender's framing, not the attacker's: an attempt the
## attacker cleared is a LOSS for this base, so "CLEARED" is the alarming one.
const RESULT_DEFENDED := "DEFENDED"
const RESULT_CLEARED := "CLEARED"

## Warm sage / warm brick. Held inside this screen rather than in [MenuTheme] because they
## are the only two semantic (good/bad) colours in the menus, and both are pulled toward the
## amber palette so a green tick never reads as a different app.
const DEFENDED_COLOR := Color("8bbf6e")
const CLEARED_COLOR := Color("d4694f")

## Ceiling on rendered attempt rows, however many pages the player asks for. The list is a
## scroll, not a spreadsheet; past this the ledger is telling a story no one is reading.
const MAX_ATTEMPT_ROWS := 200

# --- State ------------------------------------------------------------------
## Untyped, and injected the same way [CommunityBrowse] takes one -- see
## [method set_community_client].
var _client = null

## Untyped injected stand-ins for the replay workstream's two entry points; null uses the
## real ones through [code]ReplayWatch[/code]. See [method set_replay_playback] /
## [method set_replay_codec].
var _playback = null
var _codec = null
## Untyped injected stand-in for the local challenge library (anything with
## [code]list_saved()[/code]); null uses [ChallengeCodec]. See [method set_challenge_source].
var _challenge_source = null

## Every base the service returned, newest call wins. Split into [member _slotted] (the
## first [constant MAX_SLOTS] active ones) and [member _bench] (retired + any overflow).
var _bases: Array = []
var _slotted: Array = []
var _bench: Array = []
var _loading: bool = false

## What each slot currently READS as, and the bench's titles, kept as plain strings beside
## the nodes. The screen is built from these, and tests assert on them instead of walking a
## container tree that is free to be re-laid-out.
var _slot_text: PackedStringArray = PackedStringArray(["", "", ""])
var _bench_titles: PackedStringArray = PackedStringArray()
## The bench rows' one action button each, parallel to [member _bench_titles].
var _bench_buttons: Array[Button] = []

# --- Overlay state ----------------------------------------------------------
var _overlay_mode: String = OVERLAY_NONE
var _overlay_title_text: String = ""

## The attack log currently on screen.
var _log_base_id: String = ""
var _log_page: int = 0
var _log_entries: Array = []
var _log_has_more: bool = false
var _log_loading: bool = false
## Row text + WATCH buttons, parallel to [member _log_entries] (the rendered prefix of it).
var _log_row_text: PackedStringArray = PackedStringArray()
var _log_watch_buttons: Array[Button] = []
## True while a replay fetch is in flight, so a second click cannot start a second one.
var _watching: bool = false

## The publish picker.
var _publish_entries: Array = []
var _publish_rows: PackedStringArray = PackedStringArray()
var _publish_index: int = -1
var _publishing: bool = false

# --- Node refs --------------------------------------------------------------
var _slots_row: HBoxContainer = null
var _bench_box: VBoxContainer = null
var _notice: Label = null
var _summary: Label = null

var _overlay: Control = null
var _overlay_panel: PanelContainer = null
var _overlay_box: VBoxContainer = null
var _overlay_notice: Label = null
var _overlay_list: VBoxContainer = null
var _log_more_btn: Button = null
var _confirm_btn: Button = null


## Inject the community client. Call BEFORE the node enters the tree; [method _ready] only
## builds a real client when none was supplied.
func set_community_client(client) -> void:
	_client = client


## Inject the playback launcher (anything with [code]launch(Dictionary) -> Dictionary[/code]).
## THE seam that keeps a screen test from changing scene: with a stand-in here, "watch" runs
## end to end and returns a result instead of taking the battle scene up.
func set_replay_playback(playback) -> void:
	_playback = playback


## Inject the replay container codec (anything with
## [code]decode_container(PackedByteArray) -> Dictionary[/code]). Null uses [ReplayLog].
func set_replay_codec(codec) -> void:
	_codec = codec


## Inject the local challenge library (anything with [code]list_saved() -> Array[/code] in
## [method ChallengeCodec.list_saved]'s shape). Null uses [ChallengeCodec] itself, which
## reads the player's real user://challenges/ -- which is exactly what a test must not do.
func set_challenge_source(source) -> void:
	_challenge_source = source


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	if _client == null:
		_client = CommunityClient.new()
	_build_ui()
	refresh()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# 720p budget for this page (separation 12, and no MarginContainer -- this page IS the
	# viewport, so the floor must sit clear of 720 by itself):
	#   title 52 + subtitle 21 + notice 22 + slots row 132 + section header 21
	#   + bench card (120 scroll floor + 24 panel padding = 144) + actions 48 + hint 16
	#   = 456 fixed, plus 7 gaps * 12 = 84  ->  540
	# against this 660 floor, which is 60px clear of 720. The 120px of slack flows into the
	# ONE flexible region (the bench scroll, below) via EXPAND_FILL, so it opens to ~240px
	# and the footer stays pinned on screen. NOTHING below adds a fixed row: the attack log
	# and publish flows are OVERLAYS with their own budgets (see _open_overlay), which is the
	# reason they are overlays.
	#
	# Width: 780 floor against the two widest fixed rows --
	#   slots row  3 * 248 + 2 * 14 = 772  (the slot card grew from 240 to fit its second
	#                                       button; 8px spare)
	#   footer     180 + 200 + 200 + 2 * 18 = 616  (Back / Community / My Replays)
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(780.0, 660.0)
	page.add_theme_constant_override("separation", 12)
	center.add_child(page)

	var title := Label.new()
	title.text = "MY BASES"
	page.add_child(title)
	MenuTheme.style_title(title, 32)

	_summary = Label.new()
	_summary.text = "Your published challenges, defending while you are away"
	page.add_child(_summary)
	MenuTheme.style_subtitle(_summary)

	# The inline notice: base_limit, not_owner and every other refused action lands here.
	# Fixed height so the page never reflows when a message appears or clears.
	_notice = Label.new()
	_notice.text = ""
	_notice.custom_minimum_size = Vector2(0.0, 22.0)
	page.add_child(_notice)
	MenuTheme.style_caption(_notice)
	_notice.add_theme_color_override("font_color", MenuTheme.GOLD)

	# --- The three slots -----------------------------------------------------
	_slots_row = HBoxContainer.new()
	_slots_row.custom_minimum_size = Vector2(0.0, 132.0)
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_row.add_theme_constant_override("separation", 14)
	page.add_child(_slots_row)

	var bench_header := Label.new()
	bench_header.text = "RETIRED BASES"
	page.add_child(bench_header)
	MenuTheme.style_section_header(bench_header)

	# --- The bench -----------------------------------------------------------
	var bench_card := PanelContainer.new()
	bench_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(bench_card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The page's ONLY EXPAND_FILL region, with a modest floor -- see the budget above. Raise
	# this and the footer is what pays for it.
	scroll.custom_minimum_size = Vector2(0.0, 120.0)
	bench_card.add_child(scroll)

	_bench_box = VBoxContainer.new()
	_bench_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_bench_box)

	# --- Footer --------------------------------------------------------------
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	page.add_child(actions)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

	var community := Button.new()
	community.text = "Community"
	community.custom_minimum_size = Vector2(200.0, 48.0)
	var community_available: bool = ResourceLoader.exists(COMMUNITY_SCENE)
	community.disabled = not community_available
	community.tooltip_text = "Attack the bases other players are defending." if community_available \
		else "The community browser is not available in this build."
	community.pressed.connect(_on_community_pressed)
	actions.add_child(community)

	# The sibling replay screen. Guarded like every other cross-screen hop.
	var replays := Button.new()
	replays.text = "My Replays"
	replays.custom_minimum_size = Vector2(200.0, 48.0)
	var replays_available: bool = ResourceLoader.exists(MY_REPLAYS_SCENE)
	replays.disabled = not replays_available
	replays.tooltip_text = "Battles this device recorded." if replays_available \
		else "The replay screen is not available in this build."
	replays.pressed.connect(_on_my_replays_pressed)
	actions.add_child(replays)

	var hint := Label.new()
	hint.text = "Up to %d bases defend at once  •  retire one to free a slot  •  ESC back" % MAX_SLOTS
	page.add_child(hint)
	MenuTheme.style_caption(hint)

	# The overlay host, added LAST so it draws over the page. Hidden until a flow opens it.
	_build_overlay_host()


# --- Loading ----------------------------------------------------------------

## Pull the player's bases and repaint. Safe to call repeatedly; overlapping calls are
## dropped rather than queued.
func refresh() -> void:
	if _loading:
		return
	if _client == null or not _client.has_method("my_bases"):
		_bases = []
		_render()
		_set_notice("Base defense is not available in this build.")
		return
	_loading = true
	_client.my_bases(func(result: Dictionary): _on_bases_loaded(result))


func _on_bases_loaded(result: Dictionary) -> void:
	# A live service answers late: the player may already have left the screen.
	if _slots_row == null or not is_instance_valid(_slots_row):
		return
	_loading = false
	if not bool(result.get("ok", false)):
		_bases = []
		_render()
		_set_notice("Could not load your bases: %s" % String(result.get("error", "unknown error")))
		return
	var data: Variant = result.get("data", [])
	_bases = (data as Array) if data is Array else []
	_render()


## Split the loaded bases into slots + bench and rebuild both regions.
func _render() -> void:
	_slotted = []
	_bench = []
	for entry in _bases:
		if not (entry is Dictionary):
			continue
		var base: Dictionary = entry
		# Overflow (a 4th "active" base, which the service should never send) falls to the
		# bench rather than being dropped -- the player must be able to see and retire it.
		if bool(base.get("active", false)) and _slotted.size() < MAX_SLOTS:
			_slotted.append(base)
		else:
			_bench.append(base)
	_render_slots()
	_render_bench()


func _render_slots() -> void:
	if _slots_row == null:
		return
	# remove_child before queue_free: a synchronous LocalProvider reply can repaint mid-frame,
	# and a queued node still lays out until the frame ends.
	for child in _slots_row.get_children():
		_slots_row.remove_child(child)
		child.queue_free()
	_slot_text = PackedStringArray(["", "", ""])
	for i in MAX_SLOTS:
		if i < _slotted.size():
			_slots_row.add_child(_make_filled_slot(i, _slotted[i]))
		else:
			_slots_row.add_child(_make_empty_slot(i))


## A defending base: title, the counters the service last reported, and the derived rate.
func _make_filled_slot(index: int, base: Dictionary) -> Control:
	var card := PanelContainer.new()
	# 248 not 240: the card carries TWO buttons now (Attack log 112 + Retire 96 + 8
	# separation = 216) inside card_box's 10px content margins, so it needs 236 of width and
	# 248 leaves 12px of slack. Three of them plus 2 * 14 separation = 772 <= the page's 780.
	card.custom_minimum_size = Vector2(248.0, 132.0)
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	col.add_child(head)

	var title_lbl := Label.new()
	title_lbl.text = _base_title(base)
	title_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	# The card is a fixed 248 wide; a player-authored title must ellipsis inside it rather
	# than stretch the row and push the third slot off the page.
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.custom_minimum_size = Vector2(80.0, 0.0)
	head.add_child(title_lbl)
	head.add_child(MenuTheme.make_chip("ACTIVE", MenuTheme.GOLD))

	var lines: PackedStringArray = _counter_lines(base)
	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		col.add_child(lbl)

	var id: String = String(base.get("id", ""))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	buttons.add_child(_make_attack_log_button(id, _base_title(base), Vector2(112.0, 32.0)))

	var retire := Button.new()
	retire.text = "Retire"
	# Explicit minimum: a Button's full-rect children contribute nothing to its minimum size,
	# and even a plain-text button in a fixed-width card needs a floor it cannot fall below.
	retire.custom_minimum_size = Vector2(96.0, 32.0)
	retire.pressed.connect(func(): _set_active(id, false))
	buttons.add_child(retire)

	_slot_text[index] = "%s\n%s" % [_base_title(base), "\n".join(lines)]
	return card


## The one affordance every base card carries: open THIS base's attack log. Disabled (and
## explained) rather than absent when the client predates the ledger endpoints, so the
## screen still tells the truth on an old build.
func _make_attack_log_button(id: String, title: String, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = "Attack log"
	btn.custom_minimum_size = size
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var available: bool = id != "" and _client != null and _client.has_method("attempt_log")
	btn.disabled = not available
	btn.tooltip_text = "Who attacked this base, and how it went." if available \
		else ReplayWatch.LOG_UNAVAILABLE
	btn.pressed.connect(func(): open_attack_log(id, title))
	return btn


## An empty slot reads as an invitation, not as a hole in the layout.
func _make_empty_slot(index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(248.0, 132.0)
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.BORDER))

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)

	var head := Label.new()
	head.text = "SLOT %d" % (index + 1)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	head.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(head)

	var invite := Label.new()
	invite.text = EMPTY_SLOT_INVITE
	invite.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	invite.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	invite.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	invite.add_theme_color_override("font_color", MenuTheme.CREAM)
	col.add_child(invite)

	# The real publishing flow (this was a link to the challenge screen; nothing in the game
	# called CommunityClient.upload before it).
	var publish := Button.new()
	publish.text = "Publish"
	publish.custom_minimum_size = Vector2(120.0, 32.0)
	publish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	publish.tooltip_text = "Put one of your challenges up for others to attack."
	publish.pressed.connect(open_publish_picker)
	col.add_child(publish)

	_slot_text[index] = "SLOT %d\n%s" % [index + 1, EMPTY_SLOT_INVITE]
	return card


func _render_bench() -> void:
	if _bench_box == null:
		return
	for child in _bench_box.get_children():
		_bench_box.remove_child(child)
		child.queue_free()
	_bench_titles = PackedStringArray()
	_bench_buttons.clear()

	if _bench.is_empty():
		var empty := Label.new()
		empty.text = "No retired bases. Anything you retire waits here until you field it again."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(empty)
		_bench_box.add_child(empty)
		return

	var slots_free: bool = _slotted.size() < MAX_SLOTS
	for entry in _bench:
		var base: Dictionary = entry
		_bench_titles.append(_base_title(base))
		_bench_box.add_child(_make_bench_row(base, slots_free))


## One benched base: title + counters on the left, its attack log and its one action on the
## right. A retired base is still worth reading the log of -- that is often WHY it was retired.
func _make_bench_row(base: Dictionary, slots_free: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.BORDER))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var title_lbl := Label.new()
	title_lbl.text = _base_title(base)
	title_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	title_lbl.clip_text = true
	title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.custom_minimum_size = Vector2(120.0, 0.0)
	col.add_child(title_lbl)

	var meta := Label.new()
	meta.text = "   ·   ".join(_counter_lines(base))
	meta.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	meta.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(meta)

	var id: String = String(base.get("id", ""))
	var is_active: bool = bool(base.get("active", false))
	# Row width inside the bench scroll: title column (120 floor, expands) + 120 + 140 plus
	# 2 * 12 separation = 404 against the page's 780 minus the card and scroll chrome.
	row.add_child(_make_attack_log_button(id, _base_title(base), Vector2(120.0, 40.0)))

	var action := Button.new()
	action.custom_minimum_size = Vector2(140.0, 40.0)
	action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_active:
		# Overflow: the service says this one is active but the three slots are already taken.
		action.text = "Retire"
		action.pressed.connect(func(): _set_active(id, false))
	else:
		action.text = "Reactivate"
		action.disabled = not slots_free
		action.tooltip_text = "Field this base again." if slots_free \
			else "All %d slots are full. Retire one first." % MAX_SLOTS
		action.pressed.connect(func(): _set_active(id, true))
	row.add_child(action)
	_bench_buttons.append(action)

	return panel


# --- Activation -------------------------------------------------------------

## Ask the service to field or bench a base. The refusal reasons the contract names --
## [code]base_limit[/code] (a 4th base) and [code]not_owner[/code] -- become sentences in the
## notice line; anything else is reported verbatim. Nothing here assumes success, so the
## screen simply reloads and shows whatever the service now says is true.
func _set_active(id: String, active: bool) -> void:
	if id.is_empty():
		return
	if _client == null or not _client.has_method("set_base_active"):
		_set_notice("Base defense is not available in this build.")
		return
	_set_notice("")
	_client.set_base_active(id, active, func(result: Dictionary): _on_set_active_done(result))


func _on_set_active_done(result: Dictionary) -> void:
	if _slots_row == null or not is_instance_valid(_slots_row):
		return
	if bool(result.get("ok", false)):
		refresh()
		return
	_set_notice(notice_for_error(String(result.get("error", ""))))
	# Still reload: whatever the service refused, its view of the slots is the true one.
	refresh()


## Turn a contract error code into a sentence a player can act on. Static + pure so the
## wording is pinned by a test rather than by reading the screen.
static func notice_for_error(error: String) -> String:
	match error:
		"base_limit":
			return "You can defend with %d bases at once. Retire one to free a slot." % MAX_SLOTS
		"not_owner":
			return "That base is not yours to change."
		"":
			return "That base could not be updated."
	return "That base could not be updated: %s" % error


# =============================================================================
# OVERLAYS
# =============================================================================
# One host, three contents. An overlay rather than a scene change because both flows are
# ABOUT a base the player is looking at: changing scene would drop the loaded slots, and
# coming back would cost a second my_bases round trip to show the same thing.

func _build_overlay_host() -> void:
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.visible = false
	add_child(_overlay)

	# The scrim both dims the page and EATS clicks, so a card behind the panel cannot be
	# pressed through it.
	var scrim := ColorRect.new()
	scrim.color = Color(MenuTheme.DARK.r, MenuTheme.DARK.g, MenuTheme.DARK.b, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(scrim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	_overlay_panel = PanelContainer.new()
	_overlay_panel.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD))
	center.add_child(_overlay_panel)

	_overlay_box = VBoxContainer.new()
	_overlay_box.add_theme_constant_override("separation", 10)
	_overlay_panel.add_child(_overlay_box)


## Clear the panel and size it for [param mode]. [param size] is the panel's OUTER minimum;
## each caller documents its own 720p sum against it (see the three builders below).
func _open_overlay(mode: String, heading: String, subject: String, size: Vector2) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	_overlay_mode = mode
	_overlay_title_text = subject
	_overlay_notice = null
	_overlay_list = null
	_log_more_btn = null
	_confirm_btn = null
	_log_watch_buttons.clear()
	for child in _overlay_box.get_children():
		_overlay_box.remove_child(child)
		child.queue_free()
	_overlay_panel.custom_minimum_size = size
	_overlay.visible = true

	# Header: what this is, whose it is, and the way out. 36 tall.
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0.0, 36.0)
	head.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(head)

	var heading_lbl := Label.new()
	heading_lbl.text = heading if subject.is_empty() else "%s  ·  %s" % [heading, subject]
	heading_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	heading_lbl.add_theme_color_override("font_color", MenuTheme.GOLD)
	heading_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A player-authored base name is arbitrary length; it ellipsises rather than widening the
	# panel past the budget below.
	heading_lbl.clip_text = true
	heading_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_lbl.custom_minimum_size = Vector2(160.0, 0.0)
	head.add_child(heading_lbl)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(96.0, 32.0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(close_overlay)
	head.add_child(close)


## The overlay's own inline notice: loading states, refusals, and every replay failure.
## Fixed height, so a message appearing never reflows the panel.
func _add_overlay_notice() -> void:
	_overlay_notice = Label.new()
	_overlay_notice.text = ""
	_overlay_notice.custom_minimum_size = Vector2(0.0, 20.0)
	_overlay_notice.clip_text = true
	_overlay_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_overlay_box.add_child(_overlay_notice)
	MenuTheme.style_caption(_overlay_notice)
	_overlay_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_overlay_notice.add_theme_color_override("font_color", MenuTheme.GOLD)


## The overlay's ONE EXPAND_FILL region: a scrolling list card with an explicit floor.
func _add_overlay_list(scroll_floor: float) -> void:
	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay_box.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, scroll_floor)
	card.add_child(scroll)

	_overlay_list = VBoxContainer.new()
	_overlay_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_overlay_list)


func _set_overlay_notice(text: String) -> void:
	if _overlay_notice != null and is_instance_valid(_overlay_notice):
		_overlay_notice.text = text


## Tear the panel down and hand the page back. Idempotent.
func close_overlay() -> void:
	_overlay_mode = OVERLAY_NONE
	_overlay_title_text = ""
	_overlay_notice = null
	_overlay_list = null
	_log_more_btn = null
	_confirm_btn = null
	_log_watch_buttons.clear()
	_log_row_text = PackedStringArray()
	_publish_rows = PackedStringArray()
	if _overlay == null or not is_instance_valid(_overlay):
		return
	for child in _overlay_box.get_children():
		_overlay_box.remove_child(child)
		child.queue_free()
	_overlay.visible = false


# --- Attack log -------------------------------------------------------------

## Open [param base_id]'s attempt ledger, newest first. [param title] is only the heading.
func open_attack_log(base_id: String, title: String) -> void:
	if base_id.strip_edges().is_empty():
		return
	_log_base_id = base_id
	_log_page = 0
	_log_entries = []
	_log_has_more = false
	_watching = false

	# 720p budget for this panel (VBox separation 10, inside card_box's 10px margins):
	#   header 36 + subtitle 18 + notice 20 + column head 18
	#   + list card (200 scroll floor + 20 card padding = 220) + footer 44
	#   = 356 fixed, plus 5 gaps * 10 = 50  ->  406, plus the panel's own 20 of padding = 426
	# against the 470 floor below -- 250px clear of a 720p viewport, with the 44px of slack
	# flowing into the ONE EXPAND_FILL region (the list) so it opens to ~244px.
	# Width 660: content 640, minus the list card's 20 and a ~12 scrollbar leaves 608 for a
	# row, whose own card padding leaves 588 against the row's 530 + 4 * 10 = 570.
	_open_overlay(OVERLAY_ATTACK_LOG, "ATTACK LOG", title, Vector2(660.0, 470.0))

	var subtitle := Label.new()
	subtitle.text = "Every attempt against this base, newest first"
	subtitle.custom_minimum_size = Vector2(0.0, 18.0)
	_overlay_box.add_child(subtitle)
	MenuTheme.style_caption(subtitle)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	_add_overlay_notice()

	var column_head := HBoxContainer.new()
	column_head.custom_minimum_size = Vector2(0.0, 18.0)
	column_head.add_theme_constant_override("separation", 10)
	_overlay_box.add_child(column_head)
	for spec in [
		{"text": "RESULT", "width": 90.0}, {"text": "SCORE", "width": 90.0},
		{"text": "TURNS", "width": 80.0}, {"text": "WHEN", "width": 160.0},
		{"text": "", "width": 110.0},
	]:
		var lbl := Label.new()
		lbl.text = String(spec["text"])
		lbl.custom_minimum_size = Vector2(float(spec["width"]), 0.0)
		lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		column_head.add_child(lbl)

	_add_overlay_list(200.0)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0.0, 44.0)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_child(footer)

	_log_more_btn = Button.new()
	_log_more_btn.text = "Load more"
	_log_more_btn.custom_minimum_size = Vector2(180.0, 40.0)
	_log_more_btn.visible = false
	_log_more_btn.pressed.connect(attack_log_load_more)
	footer.add_child(_log_more_btn)

	_load_attempt_page()


## Ask for the next page. Bounded by [constant MAX_ATTEMPT_ROWS] on the render side.
func attack_log_load_more() -> void:
	if _overlay_mode != OVERLAY_ATTACK_LOG or _log_loading or not _log_has_more:
		return
	_log_page += 1
	_load_attempt_page()


func _load_attempt_page() -> void:
	if _client == null or not _client.has_method("attempt_log"):
		_render_attempt_rows()
		_set_overlay_notice(ReplayWatch.LOG_UNAVAILABLE)
		return
	_log_loading = true
	_render_attempt_rows()
	_set_overlay_notice(ReplayWatch.LOADING_LOG)
	# Captured BY VALUE, which is the point: a reply that lands after the player opened a
	# DIFFERENT base's log (or paged on) must be dropped, not merged into the wrong list.
	var want_id: String = _log_base_id
	var want_page: int = _log_page
	_client.attempt_log(_log_base_id, _log_page,
		func(result: Dictionary): _on_attempt_page(want_id, want_page, result))


func _on_attempt_page(want_id: String, want_page: int, result: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay_mode != OVERLAY_ATTACK_LOG or _log_base_id != want_id or _log_page != want_page:
		return
	_log_loading = false
	if not bool(result.get("ok", false)):
		_render_attempt_rows()
		_set_overlay_notice(ReplayWatch.attempt_log_notice(String(result.get("error", ""))))
		return

	var data: Variant = result.get("data", {})
	var payload: Dictionary = data if data is Dictionary else {}
	var entries: Variant = payload.get("entries", [])
	for item in (entries as Array if entries is Array else []):
		if item is Dictionary and _log_entries.size() < MAX_ATTEMPT_ROWS:
			_log_entries.append(item)
	_log_has_more = bool(payload.get("has_more", false)) and _log_entries.size() < MAX_ATTEMPT_ROWS
	_render_attempt_rows()
	_set_overlay_notice("")


func _render_attempt_rows() -> void:
	if _overlay_list == null or not is_instance_valid(_overlay_list):
		return
	for child in _overlay_list.get_children():
		_overlay_list.remove_child(child)
		child.queue_free()
	_log_row_text = PackedStringArray()
	_log_watch_buttons.clear()

	if _log_entries.is_empty():
		var empty := Label.new()
		empty.text = ReplayWatch.LOADING_LOG if _log_loading else ReplayWatch.NO_ATTACKS
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(empty)
		_overlay_list.add_child(empty)
	else:
		for i in _log_entries.size():
			_overlay_list.add_child(_make_attempt_row(i, _log_entries[i]))

	if _log_more_btn != null and is_instance_valid(_log_more_btn):
		_log_more_btn.visible = _log_has_more
		_log_more_btn.disabled = _log_loading


## One attempt. The WATCH button exists only when the ledger says a replay was kept -- an
## always-present button that answers "not_found" half the time is a worse screen than one
## that shows what is actually watchable.
func _make_attempt_row(index: int, entry: Dictionary) -> Control:
	var cleared: bool = bool(entry.get("cleared", false))
	var score: int = int(entry.get("score", 0))
	var turns: int = int(entry.get("turns", 0))
	var when: String = format_when(entry.get("at", ""))
	var has_replay: bool = bool(entry.get("has_replay", false))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		MenuTheme.card_box(CLEARED_COLOR if cleared else DEFENDED_COLOR))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var result_lbl := Label.new()
	result_lbl.text = RESULT_CLEARED if cleared else RESULT_DEFENDED
	result_lbl.custom_minimum_size = Vector2(90.0, 0.0)
	result_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	result_lbl.add_theme_color_override("font_color", CLEARED_COLOR if cleared else DEFENDED_COLOR)
	result_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(result_lbl)

	for spec in [
		{"text": "%d pts" % score, "width": 90.0},
		{"text": "%d turns" % turns, "width": 80.0},
		{"text": when, "width": 160.0},
	]:
		var lbl := Label.new()
		lbl.text = String(spec["text"])
		lbl.custom_minimum_size = Vector2(float(spec["width"]), 0.0)
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		lbl.add_theme_color_override("font_color", MenuTheme.CREAM)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var watch := Button.new()
	watch.text = "Watch"
	watch.custom_minimum_size = Vector2(110.0, 32.0)
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch.disabled = not has_replay or _watching
	watch.tooltip_text = "Watch this attack." if has_replay \
		else "No replay was kept for this attempt."
	watch.pressed.connect(func(): attack_log_watch(index))
	row.add_child(watch)
	_log_watch_buttons.append(watch)

	_log_row_text.append("%s   ·   %d pts   ·   %d turns   ·   %s" % [
		result_lbl.text, score, turns, when])
	return panel


## "2026-08-01 12:03:11" from either an ISO string or a unix timestamp. Static + pure so the
## formatting is pinned by a test; anything unreadable says so rather than printing "0".
static func format_when(value: Variant) -> String:
	if value is int or value is float:
		var stamp: int = int(value)
		if stamp <= 0:
			return "unknown"
		return Time.get_datetime_string_from_unix_time(stamp, true)
	var text: String = String(value).strip_edges()
	if text.is_empty():
		return "unknown"
	return text.replace("T", " ")


# --- Watching one attempt ---------------------------------------------------

## Fetch, decode and play attempt [param index]'s replay. Every failure between here and the
## battle scene is an inline sentence in the overlay's notice line: a service refusal, a blob
## that is not base64, a container that decodes to nothing, and a launcher that refuses the
## build the recording came from.
func attack_log_watch(index: int) -> void:
	if index < 0 or index >= _log_entries.size():
		return
	var entry: Dictionary = _log_entries[index]
	if not bool(entry.get("has_replay", false)):
		_set_overlay_notice(ReplayWatch.NOT_FOUND)
		return
	_watch_attempt(String(entry.get("attempt_id", "")))


func _watch_attempt(attempt_id: String) -> void:
	if attempt_id.strip_edges().is_empty():
		_set_overlay_notice(ReplayWatch.NOT_FOUND)
		return
	if _watching:
		return
	if _client == null or not _client.has_method("fetch_attempt_replay"):
		_set_overlay_notice(ReplayWatch.PLAYBACK_UNAVAILABLE)
		return
	_watching = true
	_set_watch_buttons_disabled(true)
	_set_overlay_notice(ReplayWatch.LOADING_REPLAY)
	var want_id: String = _log_base_id
	_client.fetch_attempt_replay(attempt_id,
		func(result: Dictionary): _on_replay_fetched(want_id, result))


func _on_replay_fetched(want_id: String, result: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay_mode != OVERLAY_ATTACK_LOG or _log_base_id != want_id:
		return
	_watching = false
	_set_watch_buttons_disabled(false)

	if not bool(result.get("ok", false)):
		_set_overlay_notice(ReplayWatch.fetch_notice(String(result.get("error", ""))))
		return

	var encoded: String = String(result.get("data", "")).strip_edges()
	# Shape-checked BEFORE the decoder: Marshalls.base64_to_raw logs an engine error on
	# malformed input, and a truncated / hostile blob off a service is an EXPECTED case.
	if not ReplayWatch.is_base64(encoded):
		_set_overlay_notice(ReplayWatch.UNAVAILABLE)
		return
	var log: Dictionary = ReplayWatch.decode_container(_codec, Marshalls.base64_to_raw(encoded))
	if log.is_empty():
		_set_overlay_notice(ReplayWatch.UNAVAILABLE)
		return

	var launched: Dictionary = ReplayWatch.launch(_playback, log)
	if bool(launched.get("ok", false)):
		# The scene has changed; drop the panel so nothing is left behind if it has not.
		close_overlay()
		return
	_set_overlay_notice(ReplayWatch.playback_notice(String(launched.get("error", ""))))


## Grey every WATCH button while one fetch is in flight. Buttons for attempts with no replay
## stay disabled either way.
func _set_watch_buttons_disabled(disabled: bool) -> void:
	for i in _log_watch_buttons.size():
		var btn: Button = _log_watch_buttons[i]
		if btn == null or not is_instance_valid(btn):
			continue
		var has_replay: bool = i < _log_entries.size() \
			and bool((_log_entries[i] as Dictionary).get("has_replay", false))
		btn.disabled = disabled or not has_replay


# --- Publish ----------------------------------------------------------------

## Open the picker of LOCAL authored challenges. When there are none the list says so and the
## footer routes to the screen where challenges are built and imported -- an empty picker
## with a dead button would be the worst version of this.
func open_publish_picker() -> void:
	_publish_index = -1
	_publishing = false
	_publish_entries = _local_challenges()

	# 720p budget (VBox separation 10, inside card_box's 10px margins):
	#   header 36 + subtitle 18 + notice 20 + list card (180 floor + 20 padding = 200)
	#   + footer 44 = 318 fixed, plus 4 gaps * 10 = 40  ->  358, plus 20 panel padding = 378
	# against the 430 floor below -- 290px clear of 720, the 52px of slack going to the ONE
	# EXPAND_FILL region (the list) so it opens to ~232px.
	# Width 660: the footer's single 220 button and a row's 200-floor title column both sit
	# far inside the 640 of content.
	_open_overlay(OVERLAY_PUBLISH, "PUBLISH A BASE", "", Vector2(660.0, 430.0))

	var subtitle := Label.new()
	subtitle.text = "Pick one of your challenges to put up for others to attack"
	subtitle.custom_minimum_size = Vector2(0.0, 18.0)
	_overlay_box.add_child(subtitle)
	MenuTheme.style_caption(subtitle)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	_add_overlay_notice()
	_add_overlay_list(180.0)

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0.0, 44.0)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_box.add_child(footer)

	var builder := Button.new()
	builder.text = "Build a challenge"
	builder.custom_minimum_size = Vector2(220.0, 40.0)
	var builder_available: bool = ResourceLoader.exists(CHALLENGE_BROWSE_SCENE)
	builder.disabled = not builder_available
	builder.tooltip_text = "Build or import a challenge first." if builder_available \
		else "The challenge screen is not available in this build."
	builder.pressed.connect(_on_open_builder)
	footer.add_child(builder)

	_render_publish_rows()


## The player's local challenges, in [method ChallengeCodec.list_saved]'s
## [code][{path, challenge}][/code] shape.
func _local_challenges() -> Array:
	if _challenge_source != null and _challenge_source.has_method("list_saved"):
		var injected: Variant = _challenge_source.list_saved()
		return injected if injected is Array else []
	return ChallengeCodec.list_saved()


func _render_publish_rows() -> void:
	if _overlay_list == null or not is_instance_valid(_overlay_list):
		return
	for child in _overlay_list.get_children():
		_overlay_list.remove_child(child)
		child.queue_free()
	_publish_rows = PackedStringArray()

	if _publish_entries.is_empty():
		# THE no-challenges route: say what is missing and where it is made. The footer
		# button below is the way there.
		var hint := Label.new()
		hint.text = "You have not built a challenge yet.\nBuild one in the Map Maker (Export as Challenge) or import a share code, then publish it here."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(hint)
		_overlay_list.add_child(hint)
		return

	for i in _publish_entries.size():
		var entry: Variant = _publish_entries[i]
		if not (entry is Dictionary):
			continue
		var challenge: Dictionary = (entry as Dictionary).get("challenge", {})
		_publish_rows.append("%s   ·   %s" % [_challenge_title(challenge), _challenge_detail(challenge)])
		_overlay_list.add_child(_make_publish_row(i, challenge))


func _make_publish_row(index: int, challenge: Dictionary) -> Control:
	var btn := Button.new()
	# A Button's full-rect children contribute nothing to its minimum size, so the two lines
	# inside need an explicit floor or the row collapses to nothing.
	btn.custom_minimum_size = Vector2(0.0, 56.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func(): publish_select(index))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.text = _challenge_title(challenge)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	col.add_child(name_lbl)

	var detail_lbl := Label.new()
	detail_lbl.text = _challenge_detail(challenge)
	detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_lbl.clip_text = true
	detail_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	detail_lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(detail_lbl)

	btn.add_child(col)
	return btn


## Move to the confirm sheet for picker row [param index].
func publish_select(index: int) -> void:
	if index < 0 or index >= _publish_entries.size():
		return
	_publish_index = index
	var challenge: Dictionary = _selected_challenge()

	# 720p budget (VBox separation 10, inside card_box's 10px margins):
	#   header 36 + name 22 + map 18 + rules 18 + author 18 + body 44 + notice 20 + footer 44
	#   = 220 fixed, plus 7 gaps * 10 = 70  ->  290, plus 20 panel padding = 310
	# against the 340 floor below -- 380px clear of 720. This sheet has NO flexible region on
	# purpose: it is a question, and a question that grows with the window reads as a page.
	# Width 560: footer 140 + 180 + 18 = 338 against 540 of content.
	_open_overlay(OVERLAY_CONFIRM, "PUBLISH", "", Vector2(560.0, 340.0))

	var name_lbl := Label.new()
	name_lbl.text = _challenge_title(challenge)
	name_lbl.custom_minimum_size = Vector2(0.0, 22.0)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	name_lbl.add_theme_color_override("font_color", MenuTheme.CREAM)
	_overlay_box.add_child(name_lbl)

	for text in [_challenge_map_line(challenge), _challenge_detail(challenge),
			"by %s" % _challenge_author(challenge)]:
		var lbl := Label.new()
		lbl.text = String(text)
		lbl.custom_minimum_size = Vector2(0.0, 18.0)
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		_overlay_box.add_child(lbl)

	var body := Label.new()
	body.text = "Published bases are playable by anyone and are attacked by other players. You can retire it again at any time."
	body.custom_minimum_size = Vector2(0.0, 44.0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	body.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	_overlay_box.add_child(body)

	_add_overlay_notice()

	var footer := HBoxContainer.new()
	footer.custom_minimum_size = Vector2(0.0, 44.0)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 18)
	_overlay_box.add_child(footer)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140.0, 40.0)
	cancel.pressed.connect(open_publish_picker)
	footer.add_child(cancel)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Publish"
	_confirm_btn.theme_type_variation = "SelectedButton"
	_confirm_btn.custom_minimum_size = Vector2(180.0, 40.0)
	_confirm_btn.pressed.connect(publish_confirm)
	footer.add_child(_confirm_btn)


## Send the selected challenge to the service. THE only call to
## [method CommunityClient.upload] in the game.
func publish_confirm() -> void:
	if _overlay_mode != OVERLAY_CONFIRM or _publishing:
		return
	var challenge: Dictionary = _selected_challenge()
	if challenge.is_empty():
		_set_overlay_notice("That challenge could not be read.")
		return
	if _client == null or not _client.has_method("upload"):
		_set_overlay_notice("Publishing is not available in this build.")
		return
	_publishing = true
	if _confirm_btn != null and is_instance_valid(_confirm_btn):
		_confirm_btn.disabled = true
	_set_overlay_notice("Publishing...")
	_client.upload(_publish_payload(challenge), func(result: Dictionary): _on_upload_done(result))


## What actually goes on the wire: the AUTHORED CHALLENGE DICTIONARY itself, deep-copied so
## nothing here can mutate the file on disk, with our own client-side bookkeeping key
## [code]community_id[/code] stripped.
##
## That key is stamped into a challenge by [method CommunityClient.install_payload] when it
## is DOWNLOADED, so it is our metadata about someone else's item rather than part of what
## the author wrote -- sending it would put a foreign service id inside a payload the service
## is about to hash and re-own. Everything else is left exactly as authored:
## [code]{format_version, name, author, created, checksum, map:{...}, rules:{...}}[/code].
## Both providers take the payload in this shape ([LocalProvider] derives the summary from
## it; [HttpProvider] POSTs it to /v1/items), and the service re-validates and re-computes
## the checksum regardless -- a client is never a validator.
func _publish_payload(challenge: Dictionary) -> Dictionary:
	var payload: Dictionary = challenge.duplicate(true)
	payload.erase("community_id")
	return payload


func _on_upload_done(result: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	if _overlay_mode != OVERLAY_CONFIRM:
		return
	_publishing = false
	if _confirm_btn != null and is_instance_valid(_confirm_btn):
		_confirm_btn.disabled = false

	if not bool(result.get("ok", false)):
		_set_overlay_notice(ReplayWatch.publish_notice(String(result.get("error", ""))))
		return

	# Success. The service decides where it LANDS: past the active cap an upload is accepted
	# but retired (the provider's documented invariant), so the summary -- not our optimism --
	# is what the page reports.
	var data: Variant = result.get("data", {})
	var summary: Dictionary = data if data is Dictionary else {}
	var base_name: String = String(summary.get("name", "Your base"))
	var active: bool = bool(summary.get("active", true))
	close_overlay()
	if active:
		_set_notice("Published '%s'." % base_name)
	else:
		_set_notice("Published '%s' -- all %d slots were full, so it is waiting on the bench."
			% [base_name, MAX_SLOTS])
	refresh()


func _selected_challenge() -> Dictionary:
	if _publish_index < 0 or _publish_index >= _publish_entries.size():
		return {}
	var entry: Variant = _publish_entries[_publish_index]
	if not (entry is Dictionary):
		return {}
	var challenge: Variant = (entry as Dictionary).get("challenge", {})
	return challenge if challenge is Dictionary else {}


func _challenge_title(challenge: Dictionary) -> String:
	var title: String = String(challenge.get("name", "")).strip_edges()
	return title if not title.is_empty() else "Untitled"


func _challenge_author(challenge: Dictionary) -> String:
	var author: String = String(challenge.get("author", "")).strip_edges()
	return author if not author.is_empty() else "unknown"


## "Map Thornhold (8x8)" -- the map is the thing the player recognises a challenge by.
func _challenge_map_line(challenge: Dictionary) -> String:
	var map_dict: Variant = challenge.get("map", {})
	var map_data: Dictionary = map_dict if map_dict is Dictionary else {}
	var info_dict: Variant = map_data.get("map_info", {})
	var info: Dictionary = info_dict if info_dict is Dictionary else {}
	var map_name: String = String(info.get("name", "")).strip_edges()
	var dims: Variant = map_data.get("dimensions", {})
	var size: Dictionary = dims if dims is Dictionary else {}
	var w: int = int(size.get("width", 0))
	var h: int = int(size.get("height", 0))
	if map_name.is_empty():
		map_name = "Untitled map"
	return "Map %s (%dx%d)" % [map_name, w, h]


## "SURVIVE 10   ·   4 defenders   ·   squad 4" -- what an attacker is signing up for.
func _challenge_detail(challenge: Dictionary) -> String:
	var rules_dict: Variant = challenge.get("rules", {})
	var rules: Dictionary = rules_dict if rules_dict is Dictionary else {}
	var mode: String = ChallengeCodec.rules_mode(challenge)
	var mode_text: String = "SURVIVE %d" % ChallengeCodec.rules_survive_turns(challenge) \
		if mode == ChallengeCodec.MODE_SURVIVE else "BREACH"
	var defenders: int = ChallengeCodec.defense_count(challenge)
	return "%s   ·   %d defender%s   ·   squad %d" % [
		mode_text, defenders, "" if defenders == 1 else "s",
		int(rules.get("challenger_squad_size", 0))]


# --- Formatting -------------------------------------------------------------

## A base's display title. Summaries carry "name"; "title" is accepted too so a service that
## speaks the other word still renders.
func _base_title(base: Dictionary) -> String:
	var title: String = String(base.get("name", "")).strip_edges()
	if title.is_empty():
		title = String(base.get("title", "")).strip_edges()
	return title if not title.is_empty() else "Untitled"


## The last-known counters, as lines. Attacks and defends are COUNTS the service stores; the
## rate is derived (and absent, in words, when nothing has attacked yet) -- one shared
## implementation with the browse cards, see [method CommunityBrowse.defense_stats].
func _counter_lines(base: Dictionary) -> PackedStringArray:
	var stats: Dictionary = CommunityBrowse.defense_stats(base)
	var attacked: int = int(stats["attacked"])
	if attacked <= 0:
		return PackedStringArray(["Not attacked yet"])
	return PackedStringArray([
		"Attacked %d time%s" % [attacked, "" if attacked == 1 else "s"],
		"Defended %d" % int(stats["defended"]),
		"Defense rate %d%%" % CommunityBrowse.defense_percent(base),
	])


func _set_notice(text: String) -> void:
	if _notice != null:
		_notice.text = text


# --- Read-back seams (for tests and for anything that needs the rendered state) ---

## What slot [param index] currently reads as (title + counter lines, or the empty-slot
## invitation). "" for an out-of-range index.
func slot_text(index: int) -> String:
	if index < 0 or index >= _slot_text.size():
		return ""
	return _slot_text[index]


## Titles of the benched bases, top to bottom.
func bench_titles() -> PackedStringArray:
	return _bench_titles


## Whether bench row [param index]'s action (Reactivate / Retire) can be pressed. False for
## an out-of-range index.
func bench_action_enabled(index: int) -> bool:
	if index < 0 or index >= _bench_buttons.size():
		return false
	return not _bench_buttons[index].disabled


## The text on bench row [param index]'s action button ("" for an out-of-range index).
func bench_action_text(index: int) -> String:
	if index < 0 or index >= _bench_buttons.size():
		return ""
	return _bench_buttons[index].text


## The inline notice line's current contents ("" when nothing is being reported).
func notice_text() -> String:
	return _notice.text if _notice != null else ""


## Which panel is over the page: [constant OVERLAY_NONE] / [constant OVERLAY_ATTACK_LOG] /
## [constant OVERLAY_PUBLISH] / [constant OVERLAY_CONFIRM].
func overlay_mode() -> String:
	return _overlay_mode


## The subject the open overlay names (a base title, or "").
func overlay_title() -> String:
	return _overlay_title_text


## The open overlay's inline notice ("" when nothing is being reported, or when closed).
func overlay_notice() -> String:
	if _overlay_notice == null or not is_instance_valid(_overlay_notice):
		return ""
	return _overlay_notice.text


## The attack log's rendered rows, newest first.
func attack_log_rows() -> PackedStringArray:
	return _log_row_text


## Whether attempt row [param index]'s WATCH button can be pressed. False for a row whose
## attempt kept no replay, for a row while a fetch is in flight, and out of range.
func attack_log_watch_enabled(index: int) -> bool:
	if index < 0 or index >= _log_watch_buttons.size():
		return false
	var btn: Button = _log_watch_buttons[index]
	return is_instance_valid(btn) and not btn.disabled


## Whether the attack log is offering another page.
func attack_log_has_more() -> bool:
	return _log_has_more


## The publish picker's rows ("<name>   ·   <detail>"), in library order.
func publish_rows() -> PackedStringArray:
	return _publish_rows


# --- Navigation -------------------------------------------------------------

func _on_open_builder() -> void:
	if not ResourceLoader.exists(CHALLENGE_BROWSE_SCENE):
		_set_overlay_notice("The challenge screen is not available in this build.")
		return
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _on_community_pressed() -> void:
	if not ResourceLoader.exists(COMMUNITY_SCENE):
		_set_notice("The community browser is not available in this build.")
		return
	get_tree().change_scene_to_file(COMMUNITY_SCENE)


func _on_my_replays_pressed() -> void:
	if not ResourceLoader.exists(MY_REPLAYS_SCENE):
		_set_notice("The replay screen is not available in this build.")
		return
	get_tree().change_scene_to_file(MY_REPLAYS_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				# ESC dismisses the panel first: leaving the screen because a player wanted
				# to close a dialog is the classic overlay bug.
				if _overlay_mode != OVERLAY_NONE:
					close_overlay()
					return
				_on_back_pressed()
			KEY_DOWN:
				var next := find_next_valid_focus()
				if next != null:
					next.grab_focus()
			KEY_UP:
				var prev := find_prev_valid_focus()
				if prev != null:
					prev.grab_focus()
