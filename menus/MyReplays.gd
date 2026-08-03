extends Control

class_name MyReplays

## THIS DEVICE'S OWN RECORDINGS. Every finished battle is written to disk by
## [ReplayRecorder] as a [code].cqrep[/code] container; this is the screen where the player
## finds one again, watches it, and deletes the ones they are done with.
##
## Sibling of [MyBases], not a tab inside it, and deliberately so:
##   * a recording is not a BASE. Replays come from every mode -- skirmish, arena, campaign,
##     challenge, versus -- while My Bases is about the three community challenges this
##     player published. Filing them together would mean one screen answering two questions.
##   * My Bases' 720p budget already spends its single EXPAND_FILL region on the retired
##     bench. A tab would need a second flexible region (or a mode-swap of the first) plus a
##     re-derivation of that page's whole sum; a separate page costs one footer button.
## The attack-log flow on [MyBases] watches a replay the SERVICE holds; this one watches a
## replay the DISK holds. Both route through [code]ReplayWatch[/code], so a decode failure or
## a version mismatch is worded identically on both screens.
##
## Listing is CHEAP by design in [method ReplayLog.list_replays] -- it does not parse -- but
## a list of filenames is not a screen. So each row's header is read with
## [method ReplayLog.load_from_file] (the same hardened, quiet validator playback uses) and
## the count is capped by [constant MAX_ROWS]. A file that does not validate is still LISTED,
## with the reason in place of its details and its Watch button closed: silently hiding a
## replay the player can see in their filesystem would read as data loss.
##
## Deleting is a two-step ARM on the row itself rather than a modal: the page's budget has no
## room for a dialog, and a confirm that lives on the button being confirmed is harder to
## mis-click than one that appears under the cursor.

const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const MY_BASES_SCENE := "res://menus/MyBases.tscn"

## Shared replay copy + the playback seam. Preloaded BY PATH, not by `class_name` -- a brand
## new script is not in the project's global class cache until the project is next imported.
const ReplayWatch := preload("res://menus/ReplayWatch.gd")

## Ceiling on rendered rows. Each one costs a file read + a validate, so this is a real cost,
## not just a layout one. [method ReplayLog.list_replays] caps itself far higher (512).
const MAX_ROWS := 60

## What the Delete button says once it is armed. A constant so the two-step is pinned by a
## test rather than by reading the screen.
const DELETE_ARMED_TEXT := "Confirm?"

# --- State ------------------------------------------------------------------
## Untyped injected stand-in for the playback launcher; null uses the real one through
## [code]ReplayWatch[/code]. See [method set_replay_playback].
var _playback = null

## One per rendered row: { path, filename, log, text, watchable, reason }.
var _rows: Array = []
var _row_text: PackedStringArray = PackedStringArray()
var _watch_buttons: Array[Button] = []
var _delete_buttons: Array[Button] = []
## Which row's Delete is armed (-1 = none). Only ever one at a time.
var _armed: int = -1

# --- Node refs --------------------------------------------------------------
var _list_box: VBoxContainer = null
var _notice: Label = null


## Inject the playback launcher (anything with
## [code]launch(Dictionary) -> Dictionary[/code]). THE seam that keeps a screen test from
## changing scene: with a stand-in here, Watch runs end to end and returns a result.
func set_replay_playback(playback) -> void:
	_playback = playback


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_build_ui()
	refresh()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# 720p budget for this page (separation 12, no MarginContainer -- this page IS the
	# viewport, so the floor must sit clear of 720 by itself):
	#   title 52 + subtitle 21 + notice 22
	#   + list card (180 scroll floor + 24 panel padding = 204) + actions 48 + hint 16
	#   = 363 fixed, plus 5 gaps * 12 = 60  ->  423
	# against this 640 floor, which is 80px clear of 720. The 217px of slack flows into the
	# ONE flexible region (the list scroll, below) via EXPAND_FILL, so it opens to ~397px and
	# the footer stays pinned. Add a fixed row here and re-run this sum -- do not eyeball it.
	#
	# Width: 760 floor against the two widest rows --
	#   footer   180 + 200 + 18 = 398
	#   list row 220 title column (expands) + 110 Watch + 120 Delete + 2 * 12 = 474,
	#            inside 760 - 20 (card padding) - 12 (scrollbar) - 20 (row padding) = 708
	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(760.0, 640.0)
	page.add_theme_constant_override("separation", 12)
	center.add_child(page)

	var title := Label.new()
	title.text = "MY REPLAYS"
	page.add_child(title)
	MenuTheme.style_title(title, 32)

	var subtitle := Label.new()
	subtitle.text = "Battles this device recorded, newest first"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	# Inline notice: every watch failure and every delete result lands here. Fixed height so
	# the page never reflows when a message appears or clears.
	_notice = Label.new()
	_notice.text = ""
	_notice.custom_minimum_size = Vector2(0.0, 22.0)
	page.add_child(_notice)
	MenuTheme.style_caption(_notice)
	_notice.add_theme_color_override("font_color", MenuTheme.GOLD)

	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The page's ONLY EXPAND_FILL region, with a modest floor -- see the budget above.
	scroll.custom_minimum_size = Vector2(0.0, 180.0)
	list_card.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	page.add_child(actions)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(180.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

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
	hint.text = "Watch a recording  •  Delete asks twice  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


# --- Loading ----------------------------------------------------------------

## Re-read the replay directory and repaint. Disarms any pending delete: after a repaint the
## row under the cursor may not be the row that was armed.
func refresh() -> void:
	_armed = -1
	_rows = []
	for entry in ReplayLog.list_replays():
		if _rows.size() >= MAX_ROWS:
			break
		if not (entry is Dictionary):
			continue
		var file: Dictionary = entry
		var path: String = String(file.get("path", ""))
		if path.is_empty():
			continue
		# The hardened, QUIET reader: a corrupt / foreign-protocol file answers {} rather
		# than logging, which is the whole reason a bad row can be rendered honestly.
		var log: Dictionary = ReplayLog.load_from_file(path)
		_rows.append(_describe(path, String(file.get("filename", "")), log))

	# Newest first, by the header's own recorded time (ISO strings sort chronologically).
	# A row whose header would not load has no time, so it sorts by filename alone -- the
	# recorder stamps UTC into the name, so that is still roughly chronological.
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var at: String = String(a.get("at", ""))
		var bt: String = String(b.get("at", ""))
		if at != bt:
			return at > bt
		return String(a.get("filename", "")) > String(b.get("filename", "")))
	_render()


## One row's whole description, derived once so the renderer and the read-back seam can
## never disagree about what a row says.
func _describe(path: String, filename: String, log: Dictionary) -> Dictionary:
	if log.is_empty():
		return {
			"path": path, "filename": filename, "log": {}, "at": "",
			"text": "%s   ·   %s" % [filename, ReplayWatch.UNAVAILABLE],
			"watchable": false, "reason": ReplayWatch.UNAVAILABLE,
		}
	var map_data: Variant = log.get("map", {})
	var map_dict: Dictionary = map_data if map_data is Dictionary else {}
	var map_name: String = String(map_dict.get("name", "")).strip_edges()
	if map_name.is_empty():
		map_name = String(map_dict.get("path", "")).get_file().get_basename()
	if map_name.is_empty():
		map_name = "unknown map"
	var at: String = String(log.get("recorded_at_utc", "")).strip_edges()
	var text: String = "%s   ·   %s   ·   %s   ·   %s" % [
		String(log.get("mode", ReplayLog.MODE_SKIRMISH)).to_upper(),
		map_name,
		at.replace("T", " ") if not at.is_empty() else "undated",
		outcome_label(log.get("outcome", {})),
	]
	# The SOFT gate: the container read fine, but this build cannot re-simulate a recording
	# from another one. Said here, in the row, rather than only after a click that fails.
	if not ReplayLog.matches_this_build(log):
		return {
			"path": path, "filename": filename, "log": log, "at": at,
			"text": "%s   ·   %s" % [text, ReplayWatch.VERSION_MISMATCH],
			"watchable": false, "reason": ReplayWatch.VERSION_MISMATCH,
		}
	return {"path": path, "filename": filename, "log": log, "at": at,
		"text": text, "watchable": true, "reason": ""}


## "Victory in 12 turns" / "Defeat" / "Draw" / "Unfinished". Static + pure so a test pins the
## wording without a screen in the tree. An empty result is the quit-mid-match case, which is
## a real thing the recorder writes -- not an error.
static func outcome_label(value: Variant) -> String:
	var outcome: Dictionary = value if value is Dictionary else {}
	var turns: int = maxi(0, int(outcome.get("turns", 0)))
	var suffix: String = "" if turns <= 0 else " in %d turn%s" % [turns, "" if turns == 1 else "s"]
	match String(outcome.get("result", ReplayLog.RESULT_UNKNOWN)):
		ReplayLog.RESULT_VICTORY:
			return "Victory" + suffix
		ReplayLog.RESULT_DEFEAT:
			return "Defeat" + suffix
		ReplayLog.RESULT_DRAW:
			return "Draw" + suffix
	return "Unfinished" + suffix


func _render() -> void:
	if _list_box == null:
		return
	# remove_child before queue_free: a queued node still lays out until the frame ends, and
	# refresh() repaints synchronously after a delete.
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_row_text = PackedStringArray()
	_watch_buttons.clear()
	_delete_buttons.clear()

	if _rows.is_empty():
		var empty := Label.new()
		empty.text = ReplayWatch.NO_RECORDINGS
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(empty)
		_list_box.add_child(empty)
		return

	for i in _rows.size():
		_row_text.append(String((_rows[i] as Dictionary).get("text", "")))
		_list_box.add_child(_make_row(i, _rows[i]))


func _make_row(index: int, row: Dictionary) -> Control:
	var watchable: bool = bool(row.get("watchable", false))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		MenuTheme.card_box(MenuTheme.GOLD if watchable else MenuTheme.BORDER))

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(220.0, 0.0)
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)

	var head := Label.new()
	head.text = String(row.get("filename", ""))
	# A filename is arbitrary length (it carries the map name); it ellipsises rather than
	# pushing the two buttons off the right edge.
	head.clip_text = true
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	col.add_child(head)

	var meta := Label.new()
	meta.text = String(row.get("text", ""))
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	meta.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(meta)

	var watch := Button.new()
	watch.text = "Watch"
	# Explicit minimum: a chip-sized button with no floor collapses to its text width.
	watch.custom_minimum_size = Vector2(110.0, 36.0)
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch.disabled = not watchable
	watch.tooltip_text = "Re-watch this battle." if watchable else String(row.get("reason", ""))
	watch.pressed.connect(func(): row_watch(index))
	box.add_child(watch)
	_watch_buttons.append(watch)

	var del := Button.new()
	del.text = DELETE_ARMED_TEXT if _armed == index else "Delete"
	del.custom_minimum_size = Vector2(120.0, 36.0)
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del.tooltip_text = "Press again to delete this recording for good." if _armed == index \
		else "Delete this recording."
	del.pressed.connect(func(): row_delete(index))
	box.add_child(del)
	_delete_buttons.append(del)

	return panel


# --- Watching ---------------------------------------------------------------

## Load row [param index] off disk and hand it to playback. Every refusal is a sentence in
## the notice line; nothing here assumes the launcher succeeded.
func row_watch(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var row: Dictionary = _rows[index]
	if not bool(row.get("watchable", false)):
		_set_notice(String(row.get("reason", ReplayWatch.UNAVAILABLE)))
		return
	# Re-read rather than trusting the cached header: the file may have been replaced or
	# removed since the list was built.
	var log: Dictionary = ReplayLog.load_from_file(String(row.get("path", "")))
	if log.is_empty():
		_set_notice(ReplayWatch.UNAVAILABLE)
		refresh()
		return
	var launched: Dictionary = ReplayWatch.launch(_playback, log)
	if bool(launched.get("ok", false)):
		return  # the scene has changed; this screen is on its way out
	_set_notice(ReplayWatch.playback_notice(String(launched.get("error", ""))))


# --- Deleting ---------------------------------------------------------------

## Two-step delete. The first press ARMS row [param index] (its button becomes
## [constant DELETE_ARMED_TEXT] and the notice says what is about to happen); the second one
## on the SAME row deletes the file. Arming any other row disarms this one, so a stray click
## is a re-aim, never a deletion.
func row_delete(index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	if _armed != index:
		_armed = index
		_set_notice("Delete '%s'? Press Confirm to remove it for good." % String(
			(_rows[index] as Dictionary).get("filename", "")))
		_render()
		return

	var row: Dictionary = _rows[index]
	var filename: String = String(row.get("filename", ""))
	_armed = -1
	if ReplayLog.delete_replay(String(row.get("path", ""))):
		_set_notice("Deleted '%s'." % filename)
	else:
		_set_notice("'%s' could not be deleted." % filename)
	refresh()


func _set_notice(text: String) -> void:
	if _notice != null:
		_notice.text = text


# --- Read-back seams --------------------------------------------------------

## The rendered rows' detail lines, newest first.
func replay_rows() -> PackedStringArray:
	return _row_text


## The rendered rows' filenames, newest first.
func replay_filenames() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for row in _rows:
		out.append(String((row as Dictionary).get("filename", "")))
	return out


## Whether row [param index]'s Watch button can be pressed. False for a recording this build
## cannot read or re-simulate, and out of range.
func replay_watch_enabled(index: int) -> bool:
	if index < 0 or index >= _watch_buttons.size():
		return false
	var btn: Button = _watch_buttons[index]
	return is_instance_valid(btn) and not btn.disabled


## What row [param index]'s Delete button currently says ("Delete", or
## [constant DELETE_ARMED_TEXT] once armed). "" out of range.
func delete_button_text(index: int) -> String:
	if index < 0 or index >= _delete_buttons.size():
		return ""
	var btn: Button = _delete_buttons[index]
	return btn.text if is_instance_valid(btn) else ""


## The inline notice line's current contents ("" when nothing is being reported).
func notice_text() -> String:
	return _notice.text if _notice != null else ""


# --- Navigation -------------------------------------------------------------

func _on_my_bases_pressed() -> void:
	if not ResourceLoader.exists(MY_BASES_SCENE):
		_set_notice("The base screen is not available in this build.")
		return
	get_tree().change_scene_to_file(MY_BASES_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				# ESC disarms a pending delete first -- the same "dismiss before leave" rule
				# the overlays on [MyBases] follow.
				if _armed >= 0:
					_armed = -1
					_set_notice("")
					_render()
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
