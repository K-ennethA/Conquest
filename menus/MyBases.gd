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
## links to the screen where challenges are built and shared.
##
## Everything below the slots is the bench: retired bases (and any active overflow the
## service reports) with a Reactivate / Retire action. Reactivate is disabled while all three
## slots are full, but the service is still the authority -- when it answers
## [code]base_limit[/code] anyway (another device claimed a slot first), that lands in the
## inline notice line, never as a crash.
##
## Talks only to [CommunityClient], through the same async {ok, data} / {ok:false, error}
## contract as the browse screen, and every callback re-checks the tree: the local sandbox
## answers synchronously but a live service does not, so a reply can arrive after the player
## has already left.

const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const COMMUNITY_SCENE := "res://menus/CommunityBrowse.tscn"

## How many bases may defend at once. The service enforces it; this screen mirrors it so the
## player is told BEFORE they press a button that cannot succeed.
const MAX_SLOTS := 3

## The invitation on an unclaimed slot. A constant so the wording is asserted by a test
## rather than retyped in two places.
const EMPTY_SLOT_INVITE := "Publish a challenge to claim this slot"

# --- State ------------------------------------------------------------------
## Untyped, and injected the same way [CommunityBrowse] takes one -- see
## [method set_community_client].
var _client = null

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

# --- Node refs --------------------------------------------------------------
var _slots_row: HBoxContainer = null
var _bench_box: VBoxContainer = null
var _notice: Label = null
var _summary: Label = null


## Inject the community client. Call BEFORE the node enters the tree; [method _ready] only
## builds a real client when none was supplied.
func set_community_client(client) -> void:
	_client = client


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
	# and the footer stays pinned on screen. Width: 780 floor vs the slots row's
	# 3 * 240 + 2 * 14 = 748 -- the widest fixed row fits with 32px to spare.
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

	var hint := Label.new()
	hint.text = "Up to %d bases defend at once  •  retire one to free a slot  •  ESC back" % MAX_SLOTS
	page.add_child(hint)
	MenuTheme.style_caption(hint)


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
	card.custom_minimum_size = Vector2(240.0, 132.0)
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
	# The card is a fixed 240 wide; a player-authored title must ellipsis inside it rather
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

	var retire := Button.new()
	retire.text = "Retire"
	# Explicit minimum: a Button's full-rect children contribute nothing to its minimum size,
	# and even a plain-text button in a fixed-width card needs a floor it cannot fall below.
	retire.custom_minimum_size = Vector2(100.0, 32.0)
	retire.size_flags_horizontal = Control.SIZE_SHRINK_END
	var id: String = String(base.get("id", ""))
	retire.pressed.connect(func(): _set_active(id, false))
	col.add_child(retire)

	_slot_text[index] = "%s\n%s" % [_base_title(base), "\n".join(lines)]
	return card


## An empty slot reads as an invitation, not as a hole in the layout.
func _make_empty_slot(index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240.0, 132.0)
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

	# Publishing already lives on the challenge screens (build / import / share). This is a
	# LINK to it, deliberately not a second upload flow.
	var publish := Button.new()
	publish.text = "Publish"
	publish.custom_minimum_size = Vector2(120.0, 32.0)
	publish.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var publish_available: bool = ResourceLoader.exists(CHALLENGE_BROWSE_SCENE)
	publish.disabled = not publish_available
	publish.tooltip_text = "Build, import or share a challenge." if publish_available \
		else "The challenge screen is not available in this build."
	publish.pressed.connect(_on_publish_pressed)
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


## One benched base: title + counters on the left, the one action on the right.
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


# --- Navigation -------------------------------------------------------------

func _on_publish_pressed() -> void:
	if not ResourceLoader.exists(CHALLENGE_BROWSE_SCENE):
		_set_notice("The challenge screen is not available in this build.")
		return
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _on_community_pressed() -> void:
	if not ResourceLoader.exists(COMMUNITY_SCENE):
		_set_notice("The community browser is not available in this build.")
		return
	get_tree().change_scene_to_file(COMMUNITY_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
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
