extends Control

class_name ChallengeBrowse

## Browse + import screen for player-built CHALLENGES (Challenge Maps, Phase A). Reached
## from the Solo screen's "Challenges" card. Built on the shared grove page
## ([MenuKit.build_page], [MenuTheme] -- see docs/UI_STYLE.md).
##
## Two ways a challenge gets here:
##   * LOCAL   -- every challenge already saved under user://challenges/ (built here, or
##                imported earlier) is listed as a card: name, author, squad size, map
##                size, defender count, and the player's personal best if they have one.
##   * IMPORT  -- paste a share code into the field and press Import: it is decoded,
##                validated (bad codes give a clear message and change nothing), saved,
##                and appears in the list.
##
## Above both sits the DAILY hero card: one challenge picked deterministically from the
## day's pool (built-ins + the player's local challenges) by [DailyChallenge], keyed on the
## UTC date so every install and every timezone sees the same pick and rolls over together.
##
## Selecting a card and pressing Play hands the challenge to [ChallengeController], which
## materialises its map, points the game at it, and routes into the squad pick -> battle.
## Every dependency is null-guarded so a missing autoload or an unreadable file degrades
## gracefully rather than crashing the screen.
##
## Input: moving focus onto a challenge card selects it; Confirm (Enter / A) on the selected
## card -- or the Play button -- plays it (with the mouse: click to select, click again to
## play). Cancel (Esc / B) goes back, except while typing in the share-code field.
##
## 720p budget. MenuKit's header + footer leave the body ~466 of 720. Body rows (16 apart):
##   daily hero 124 + import row 46 + import status 22 + the list (ONE EXPAND_FILL region)
## = 192 fixed + 3 * 16 = 240, so the list gets ~226 at 720p and every spare pixel above.

const SOLO_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"

## The community browser, owned by a parallel workstream. Navigation to it is guarded by
## [method ResourceLoader.exists] so this screen still builds (with the button disabled and
## explained) in a build where that scene is not present.
const COMMUNITY_SCENE := "res://menus/CommunityBrowse.tscn"

## The player's own published bases (the defender half of the community loop). Guarded the
## same way as [constant COMMUNITY_SCENE].
const MY_BASES_SCENE := "res://menus/MyBases.tscn"

var _entries: Array[Dictionary] = []      # [{ path, challenge }]
var _selected: Dictionary = {}            # the chosen entry, or {}

## Today's deterministic pick, or {} when the pool is empty / DailyChallenge is unavailable.
var _daily: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _list_box: VBoxContainer = null
var _row_group: ButtonGroup = null
var _rows: Array[Button] = []
var _code_edit: LineEdit = null
var _import_status: Label = null
var _play_btn: Button = null
var _back_btn: Button = null
var _daily_body: VBoxContainer = null
var _daily_play_btn: Button = null

## Whether the pressed row was ALREADY the selection when the press began, so the first
## click on a card selects it and a second click plays it (the card-list rule).
var _was_selected_before_press: bool = false


func _ready() -> void:
	_row_group = ButtonGroup.new()
	_build_ui()
	_refresh_daily()
	_refresh_list()
	if _daily_play_btn != null and not _daily_play_btn.disabled:
		_focus_later(_daily_play_btn)
	elif not _rows.is_empty():
		_focus_later(_rows[0])
	else:
		_focus_later(_code_edit)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var page := MenuKit.build_page(self, ["Solo"], "Challenges",
		"Beat a map someone else built -- or import a share code.")

	# --- Daily hero ----------------------------------------------------------
	page.body.add_child(_build_daily_card())

	# --- Import row + its status line -----------------------------------------
	page.body.add_child(_build_import_row())

	_import_status = MenuKit.label("", &"DimLabel")
	_import_status.name = "ImportStatus"
	_import_status.custom_minimum_size = Vector2(0.0, 22.0)
	_import_status.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	page.body.add_child(_import_status)

	# --- Local challenge list ------------------------------------------------
	var list_well := MenuKit.card(&"InsetPanel")
	list_well.name = "ChallengeList"
	list_well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(list_well)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	# 120 floor: this scroll is the page's ONLY flexible region (see the class budget) --
	# its floor is what decides whether the footer (Back / Community / My Bases / PLAY) fits
	# on a 720p screen; EXPAND_FILL hands it everything the fixed rows leave.
	scroll.custom_minimum_size = Vector2(0.0, 120.0)
	list_well.add_child(scroll)

	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_theme_constant_override("margin_right", 14)  # focus glow + scrollbar
	scroll.add_child(pad)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", MenuTheme.SP_S)
	pad.add_child(_list_box)

	# --- Actions -------------------------------------------------------------
	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 130)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)

	var community := MenuKit.button("Community", &"", 170)
	community.name = "CommunityButton"
	var community_available: bool = ResourceLoader.exists(COMMUNITY_SCENE)
	community.disabled = not community_available
	community.tooltip_text = "Browse challenges shared by other players." if community_available \
		else "The community browser is not available in this build."
	community.pressed.connect(_on_community_pressed)
	page.actions.add_child(community)

	var bases := MenuKit.button("My Bases", &"", 150)
	bases.name = "MyBasesButton"
	var bases_available: bool = ResourceLoader.exists(MY_BASES_SCENE)
	bases.disabled = not bases_available
	bases.tooltip_text = "Your published challenges and how their defenses are holding." \
		if bases_available else "The base screen is not available in this build."
	bases.pressed.connect(_on_my_bases_pressed)
	page.actions.add_child(bases)

	_play_btn = MenuKit.button("Play  >", MenuKit.PRIMARY, 190, 54)
	_play_btn.name = "PlayButton"
	_play_btn.disabled = true
	_play_btn.pressed.connect(_on_play_pressed)
	page.actions.add_child(_play_btn)

	MenuKit.add_standard_hints(page.hints, "Play")


## The DAILY hero: a gold-edged crest card whose contents are rebuilt by [method
## _refresh_daily]. Built empty here so the card's frame + Play button are wired once and
## only the body is torn down on refresh.
func _build_daily_card() -> Control:
	var card := PanelContainer.new()
	card.name = "DailyCard"
	var sb := MenuTheme.accented_card(MenuTheme.GOLD, SIDE_LEFT, MenuTheme.PANEL, 0.96, true)
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(0.0, 124.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	card.add_child(row)

	_daily_body = VBoxContainer.new()
	_daily_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_daily_body.add_theme_constant_override("separation", 3)
	row.add_child(_daily_body)

	_daily_play_btn = MenuKit.button("Play Daily", MenuKit.PRIMARY, 200, 54)
	_daily_play_btn.name = "DailyPlayButton"
	_daily_play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_daily_play_btn.disabled = true
	_daily_play_btn.pressed.connect(_on_daily_play_pressed)
	row.add_child(_daily_play_btn)

	return card


## Pick today's challenge and repaint the hero card. The date is read ONCE here (UTC) and
## passed into the pure picker, so the screen -- not the picker -- owns the clock.
func _refresh_daily() -> void:
	if _daily_body == null:
		return
	# remove_child BEFORE queue_free: a queued node is not actually gone until the end of the
	# frame, so on a repaint (after an import) the old labels would otherwise lay out
	# alongside the new ones for a frame and visibly jump the card.
	for child in _daily_body.get_children():
		_daily_body.remove_child(child)
		child.queue_free()

	var date_utc: String = DailyChallenge.today_utc()
	_daily = DailyChallenge.pick_for_date(DailyChallenge.full_pool(), date_utc)

	_daily_body.add_child(MenuKit.section("Daily Challenge   ·   %s UTC" % date_utc))

	if _daily.is_empty():
		var none := MenuKit.label(
			"No challenges available yet -- build one in the Map Maker or import a code.",
			&"DimLabel", true)
		none.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		_daily_body.add_child(none)
		if _daily_play_btn != null:
			_daily_play_btn.disabled = true
		return

	# Name + mode badge on one line.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	_daily_body.add_child(title_row)

	var name_lbl := MenuKit.label(String(_daily.get("name", "Untitled")), &"SubheadingLabel")
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# A clipping Label has no minimum width of its own: let it take the row, badge after it.
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_lbl)
	title_row.add_child(_mode_chip(_daily))

	var detail := MenuKit.label(_detail_line(_daily), &"DimLabel")
	detail.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_daily_body.add_child(detail)

	var best := MenuKit.label(_daily_best_line(_daily), &"DimLabel")
	best.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	best.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	_daily_body.add_child(best)

	if _daily_play_btn != null:
		_daily_play_btn.disabled = false


## A badge naming the challenge's mode -- "BREACH", or "SURVIVE 10" with the round target
## baked in (the number is the whole point of the mode, so it belongs on the badge).
func _mode_chip(challenge: Dictionary) -> Control:
	var mode: String = ChallengeCodec.rules_mode(challenge)
	var chip: PanelContainer
	if mode == ChallengeCodec.MODE_SURVIVE:
		chip = MenuKit.badge("SURVIVE %d" % ChallengeCodec.rules_survive_turns(challenge),
			MenuTheme.GOLD)
	else:
		chip = MenuKit.badge("BREACH", MenuTheme.TEXT_DIM)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return chip


## The player's standing on today's pick: their best score (with a perfect badge) or a nudge
## when they have not played it yet.
func _daily_best_line(challenge: Dictionary) -> String:
	var rec: Dictionary = _result_for(challenge)
	if rec.is_empty() or not bool(rec.get("won", false)):
		return "Par %d turns   ·   not cleared yet" % ChallengeCodec.rules_par_turns(challenge)
	var line: String = "Your best: %d pts" % int(rec.get("best_score", 0))
	if bool(rec.get("best_perfect", false)):
		line += "   ·   PERFECT (no losses)"
	return line


func _build_import_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "ImportRow"
	row.add_theme_constant_override("separation", MenuTheme.SP_M)

	_code_edit = LineEdit.new()
	_code_edit.name = "CodeEdit"
	_code_edit.placeholder_text = "Paste a challenge share code..."
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.custom_minimum_size = Vector2(0.0, 46.0)
	_code_edit.text_submitted.connect(func(_t: String): _on_import_pressed())
	MenuNav.hover_focus(_code_edit)
	row.add_child(_code_edit)

	var import_btn := MenuKit.button("Import", &"", 140, 46)
	import_btn.name = "ImportButton"
	import_btn.pressed.connect(_on_import_pressed)
	row.add_child(import_btn)

	return row


# --- List population --------------------------------------------------------

func _refresh_list() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		_list_box.remove_child(child)
		child.queue_free()
	_rows.clear()
	_selected = {}
	if _play_btn != null:
		_play_btn.disabled = true

	_entries = ChallengeCodec.list_saved()
	if _entries.is_empty():
		var empty := MenuKit.label(
			"No challenges yet. Build one in the Map Maker (Export as Challenge) or import a code above.",
			&"DimLabel", true)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_box.add_child(empty)
		return

	for entry in _entries:
		var row := _make_row(entry)
		_rows.append(row)
		_list_box.add_child(row)


## One selectable challenge card: name + mode badge over a details line, plus the
## personal-best and defense lines when the player has a record. Focusing (or first
## clicking) it selects the challenge; pressing the selected card plays it.
func _make_row(entry: Dictionary) -> Button:
	var challenge: Dictionary = entry.get("challenge", {})

	var parts := MenuKit.option_card(Vector2(0.0, 96.0), true)
	var btn: Button = parts["button"]
	btn.button_group = _row_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col: VBoxContainer = parts["content"]
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", MenuTheme.SP_S)
	col.add_child(title_row)

	var name_lbl := MenuKit.label(String(challenge.get("name", "Untitled")), &"SubheadingLabel")
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# A clipping Label has no minimum width of its own: let it take the row, badge after it.
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(name_lbl)
	title_row.add_child(_mode_chip(challenge))

	var detail_lbl := MenuKit.label(_detail_line(challenge), &"DimLabel")
	detail_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(detail_lbl)

	var pb: String = _personal_best_line(challenge)
	if not pb.is_empty():
		var pb_lbl := MenuKit.label(pb, &"DimLabel")
		pb_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		pb_lbl.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
		col.add_child(pb_lbl)

	var rating: String = _defense_rating_line(challenge)
	if not rating.is_empty():
		var rating_lbl := MenuKit.label(rating, &"MutedLabel")
		rating_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		col.add_child(rating_lbl)

	MenuKit.ignore_mouse(btn)
	btn.focus_entered.connect(func() -> void:
		# A mouse press also focuses the card; let the click itself decide (select first).
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_select_entry(entry, btn))
	btn.button_down.connect(func() -> void:
		_was_selected_before_press = not _selected.is_empty() and _selected == entry)
	btn.pressed.connect(func() -> void:
		if _was_selected_before_press:
			_on_play_pressed()
		else:
			_select_entry(entry, btn))
	return btn


## "by <author>  ·  Squad <n>  ·  <W>x<H>  ·  <d> defenders".
func _detail_line(challenge: Dictionary) -> String:
	var author: String = String(challenge.get("author", "")).strip_edges()
	var rules: Dictionary = challenge.get("rules", {})
	var squad: int = int(rules.get("challenger_squad_size", 0))
	var map_dict: Dictionary = challenge.get("map", {})
	var dims: Dictionary = map_dict.get("dimensions", {})
	var w: int = int(dims.get("width", 0))
	var h: int = int(dims.get("height", 0))
	var defenders: int = ChallengeCodec.defense_count(challenge)

	var parts: Array = []
	if not author.is_empty():
		parts.append("by %s" % author)
	parts.append("Squad %d" % squad)
	parts.append("%dx%d" % [w, h])
	parts.append("%d defender%s" % [defenders, "" if defenders == 1 else "s"])
	return "   ·   ".join(PackedStringArray(parts))


## This install's stored record for [param challenge] ({} when never played, or when the
## controller autoload is missing).
func _result_for(challenge: Dictionary) -> Dictionary:
	var controller := get_node_or_null("/root/ChallengeController")
	if controller == null or not controller.has_method("result_for"):
		return {}
	var rec: Variant = controller.result_for(ChallengeCodec.challenge_id(challenge))
	return rec if rec is Dictionary else {}


## Personal-best line from the local results file, or "" if never played. Leads with the
## SCORE (the thing being competed on) and badges a flawless clear.
func _personal_best_line(challenge: Dictionary) -> String:
	var rec: Dictionary = _result_for(challenge)
	if rec.is_empty():
		return ""
	if not bool(rec.get("won", false)):
		return "Attempted -- not yet cleared"
	var line: String = "Best: %d pts" % int(rec.get("best_score", 0))
	var best_turns: int = int(rec.get("best_turns", -1))
	if best_turns >= 0:
		line += "   ·   %d turns (par %d)" % [best_turns, ChallengeCodec.rules_par_turns(challenge)]
	if bool(rec.get("best_perfect", false)):
		line += "   ·   PERFECT"
	return line


## How well this AUTHORED defense has held up -- "Held 3/5 (60%)" -- from the local
## {attempts, clears} tally. LOCAL ONLY: it counts this install's runs, never other players',
## so the label says "your runs" rather than implying a global win rate. Empty until the
## challenge has been attempted at least once.
func _defense_rating_line(challenge: Dictionary) -> String:
	var rec: Dictionary = _result_for(challenge)
	var attempts: int = int(rec.get("attempts", 0))
	if attempts <= 0:
		return ""
	var clears: int = int(rec.get("clears", 0))
	var held: int = maxi(0, attempts - clears)
	var pct: int = int(round(100.0 * float(held) / float(attempts)))
	return "Defense held %d/%d (%d%%) of your runs" % [held, attempts, pct]


## Make [param entry] the selection: its card shows the gold "selected" frame and Play
## wakes up.
func _select_entry(entry: Dictionary, btn: Button = null) -> void:
	_selected = entry
	if btn != null:
		btn.set_pressed_no_signal(true)
	if _play_btn != null:
		_play_btn.disabled = false


## Kept for callers that drive selection through a card's toggle (the pre-grove API).
func _on_row_toggled(pressed: bool, entry: Dictionary) -> void:
	if not pressed:
		return
	_select_entry(entry)


# --- Import -----------------------------------------------------------------

func _on_import_pressed() -> void:
	if _code_edit == null:
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		_set_import_status("Paste a share code first.", "warn")
		return

	var challenge: Dictionary = ChallengeCodec.decode(code)
	if challenge.is_empty():
		_set_import_status("Could not read that code -- it may be incomplete or corrupted.", "error")
		return

	var errors: Array[String] = ChallengeCodec.validate(challenge)
	if not errors.is_empty():
		_set_import_status("Invalid challenge: " + errors[0], "error")
		return

	var path: String = ChallengeCodec.save_to_file(challenge)
	if path.is_empty():
		_set_import_status("Could not save the imported challenge.", "error")
		return

	_code_edit.text = ""
	_set_import_status("Imported '%s'." % String(challenge.get("name", "challenge")), "ok")
	# The import joins the daily POOL, so today's pick can change -- repaint the hero too.
	_refresh_daily()
	_refresh_list()


func _set_import_status(text: String, tone: String = "") -> void:
	if _import_status != null:
		MenuKit.set_status(_import_status, text, tone)


# --- Play / Back ------------------------------------------------------------

func _on_play_pressed() -> void:
	if _selected.is_empty():
		return
	_start_challenge(_selected.get("challenge", {}))


## The daily hero's Play. Goes through the SAME controller path as a list row -- the daily is
## just a differently-chosen challenge, not a separate mode.
func _on_daily_play_pressed() -> void:
	_start_challenge(_daily)


## Hand [param challenge] to [ChallengeController] and let it stage the map + squad pick.
## Any failure is reported in the status line and the run is unwound, so a bad challenge
## never leaves the controller half-armed.
func _start_challenge(challenge: Dictionary) -> void:
	if challenge.is_empty():
		return
	var controller := get_node_or_null("/root/ChallengeController")
	if controller == null or not controller.has_method("prepare"):
		_set_import_status("Challenge system unavailable.", "error")
		return
	controller.prepare(challenge)
	if not controller.begin():
		_set_import_status("This challenge could not be started (map failed validation).", "error")
		controller.cancel()


## Open the community browser. The scene belongs to a parallel workstream, so the button is
## disabled with an explanatory tooltip when this build does not ship it (see
## [constant COMMUNITY_SCENE]) rather than changing scene to a missing path.
func _on_community_pressed() -> void:
	if not ResourceLoader.exists(COMMUNITY_SCENE):
		_set_import_status("The community browser is not available in this build.", "warn")
		return
	MenuNav.change_scene(self, COMMUNITY_SCENE)


## Open the player's own published bases.
func _on_my_bases_pressed() -> void:
	if not ResourceLoader.exists(MY_BASES_SCENE):
		_set_import_status("The base screen is not available in this build.", "warn")
		return
	MenuNav.change_scene(self, MY_BASES_SCENE)


func _on_back_pressed() -> void:
	MenuNav.change_scene(self, SOLO_SELECT_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	# Don't steal typing while the code field is focused (Cancel includes Backspace / X / C).
	if _code_edit != null and _code_edit.has_focus():
		return
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


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
