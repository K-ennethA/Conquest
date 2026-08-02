extends Control

class_name ChallengeBrowse

## Browse + import screen for player-built CHALLENGES (Challenge Maps, Phase A). Reached
## from the Solo screen's "Challenges" card. Dark "Legends" menu look via [MenuTheme].
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

const SOLO_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"

## The community browser, owned by a parallel workstream. Navigation to it is guarded by
## [method ResourceLoader.exists] so this screen still builds (with the button disabled and
## explained) in a build where that scene is not present.
const COMMUNITY_SCENE := "res://menus/CommunityBrowse.tscn"

var _entries: Array[Dictionary] = []      # [{ path, challenge }]
var _selected: Dictionary = {}            # the chosen entry, or {}

## Today's deterministic pick, or {} when the pool is empty / DailyChallenge is unavailable.
var _daily: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _list_box: VBoxContainer = null
var _row_group: ButtonGroup = null
var _code_edit: LineEdit = null
var _import_status: Label = null
var _play_btn: Button = null
var _daily_body: VBoxContainer = null
var _daily_play_btn: Button = null


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_row_group = ButtonGroup.new()
	_build_ui()
	_refresh_daily()
	_refresh_list()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(760.0, 700.0)
	page.add_theme_constant_override("separation", 14)
	center.add_child(page)

	var title := Label.new()
	title.text = "CHALLENGES"
	page.add_child(title)
	# 32 not 40: the page's fixed minimums (this title + subtitle + daily card + import
	# row + status + footer) plus the list's floor must sum under 720 at 1080p-scaled-down
	# / 720p or the CenterContainer clips BOTH ends -- see the scroll floor below, the
	# actual overflow driver (same bug class fixed on ProfileScreen and MatchSetup).
	MenuTheme.style_title(title, 32)

	var subtitle := Label.new()
	subtitle.text = "Beat a map someone else built -- or import a share code"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	# --- Daily hero ----------------------------------------------------------
	page.add_child(_build_daily_card())

	# --- Import row ----------------------------------------------------------
	page.add_child(_build_import_row())

	_import_status = Label.new()
	_import_status.text = ""
	_import_status.custom_minimum_size = Vector2(0.0, 20.0)
	page.add_child(_import_status)
	MenuTheme.style_caption(_import_status)

	# --- Local challenge list ------------------------------------------------
	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 150 not 340: this scroll is the page's ONLY flexible region (list_card above is
	# SIZE_EXPAND_FILL) -- its floor is what decides whether the footer (Back / Community
	# / PLAY) fits on a 720p screen. At 340 the fixed items (title 52 + subtitle 21 +
	# daily card ~106 + import row ~40 + status 20 + footer 48 + hint ~16 + 7 gaps * 14
	# separation = 98) summed to ~765 against a 720 budget -- the footer rendered below
	# the screen edge, which was the reported bug. At 150 the same sum is ~565, safely
	# under the page's explicit 700 floor, and the leftover (700 - 565 = 135) is what
	# the container hands back to this scroll via EXPAND_FILL, so the list still shows
	# several rows on a normal window.
	scroll.custom_minimum_size = Vector2(0.0, 150.0)
	list_card.add_child(scroll)

	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_list_box)

	# --- Actions -------------------------------------------------------------
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	page.add_child(actions)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160.0, 48.0)
	back.pressed.connect(_on_back_pressed)
	actions.add_child(back)

	var community := Button.new()
	community.text = "Community"
	community.custom_minimum_size = Vector2(180.0, 48.0)
	var community_available: bool = ResourceLoader.exists(COMMUNITY_SCENE)
	community.disabled = not community_available
	community.tooltip_text = "Browse challenges shared by other players." if community_available \
		else "The community browser is not available in this build."
	community.pressed.connect(_on_community_pressed)
	actions.add_child(community)

	_play_btn = Button.new()
	_play_btn.text = "PLAY"
	_play_btn.theme_type_variation = "SelectedButton"
	_play_btn.custom_minimum_size = Vector2(220.0, 48.0)
	_play_btn.disabled = true
	_play_btn.pressed.connect(_on_play_pressed)
	actions.add_child(_play_btn)

	var hint := Label.new()
	hint.text = "Paste a code and Import  •  select a challenge  •  Enter to Play  •  ESC back"
	page.add_child(hint)
	MenuTheme.style_caption(hint)


## The DAILY hero: a gold-accented card whose contents are rebuilt by [method _refresh_daily].
## Built empty here so the card's frame + Play button are wired once and only the body is
## torn down on refresh.
func _build_daily_card() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuTheme.card_box(MenuTheme.GOLD))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	_daily_body = VBoxContainer.new()
	_daily_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_daily_body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_daily_body.add_theme_constant_override("separation", 3)
	row.add_child(_daily_body)

	_daily_play_btn = Button.new()
	_daily_play_btn.text = "PLAY DAILY"
	_daily_play_btn.theme_type_variation = "SelectedButton"
	_daily_play_btn.custom_minimum_size = Vector2(180.0, 48.0)
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

	var heading := Label.new()
	heading.text = "DAILY CHALLENGE   ·   %s UTC" % date_utc
	heading.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	heading.add_theme_color_override("font_color", MenuTheme.GOLD)
	_daily_body.add_child(heading)

	if _daily.is_empty():
		var none := Label.new()
		none.text = "No challenges available yet -- build one in the Map Maker or import a code."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		none.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		_daily_body.add_child(none)
		if _daily_play_btn != null:
			_daily_play_btn.disabled = true
		return

	# Name + mode chip on one line.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	_daily_body.add_child(title_row)

	var name_lbl := Label.new()
	name_lbl.text = String(_daily.get("name", "Untitled"))
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	title_row.add_child(name_lbl)
	title_row.add_child(_mode_chip(_daily))

	var detail := Label.new()
	detail.text = _detail_line(_daily)
	detail.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	detail.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	_daily_body.add_child(detail)

	var best := Label.new()
	best.text = _daily_best_line(_daily)
	best.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	best.add_theme_color_override("font_color", MenuTheme.GOLD)
	_daily_body.add_child(best)

	if _daily_play_btn != null:
		_daily_play_btn.disabled = false


## A chip naming the challenge's mode -- "BREACH", or "SURVIVE 10" with the round target
## baked in (the number is the whole point of the mode, so it belongs on the chip).
func _mode_chip(challenge: Dictionary) -> Label:
	var mode: String = ChallengeCodec.rules_mode(challenge)
	if mode == ChallengeCodec.MODE_SURVIVE:
		return MenuTheme.make_chip("SURVIVE %d" % ChallengeCodec.rules_survive_turns(challenge),
			MenuTheme.GOLD)
	return MenuTheme.make_chip("BREACH", MenuTheme.CREAM_DIM)


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
	row.add_theme_constant_override("separation", 10)

	_code_edit = LineEdit.new()
	_code_edit.placeholder_text = "Paste a challenge share code..."
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.text_submitted.connect(func(_t: String): _on_import_pressed())
	row.add_child(_code_edit)

	var import_btn := Button.new()
	import_btn.text = "Import"
	import_btn.custom_minimum_size = Vector2(120.0, 0.0)
	import_btn.pressed.connect(_on_import_pressed)
	row.add_child(import_btn)

	return row


# --- List population --------------------------------------------------------

func _refresh_list() -> void:
	if _list_box == null:
		return
	for child in _list_box.get_children():
		child.queue_free()
	_selected = {}
	if _play_btn != null:
		_play_btn.disabled = true

	_entries = ChallengeCodec.list_saved()
	if _entries.is_empty():
		var empty := Label.new()
		empty.text = "No challenges yet. Build one in the Map Maker (Export as Challenge) or import a code above."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		MenuTheme.style_subtitle(empty)
		_list_box.add_child(empty)
		return

	for entry in _entries:
		_list_box.add_child(_make_row(entry))


## One selectable challenge card: name + author heading over a details line, plus the
## personal-best line when the player has a record. Toggling it selects the challenge.
func _make_row(entry: Dictionary) -> Button:
	var challenge: Dictionary = entry.get("challenge", {})

	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_group = _row_group
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tall enough for the four lines a played challenge shows (name+chip, details,
	# personal best, defense rating) without the text clipping the button's frame.
	btn.custom_minimum_size = Vector2(0.0, 96.0)
	btn.toggled.connect(func(pressed: bool): _on_row_toggled(pressed, entry))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	col.add_child(title_row)

	var name_lbl := Label.new()
	name_lbl.text = String(challenge.get("name", "Untitled"))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	title_row.add_child(name_lbl)

	var chip: Label = _mode_chip(challenge)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(chip)

	var detail_lbl := Label.new()
	detail_lbl.text = _detail_line(challenge)
	detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	detail_lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(detail_lbl)

	var pb: String = _personal_best_line(challenge)
	if not pb.is_empty():
		var pb_lbl := Label.new()
		pb_lbl.text = pb
		pb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pb_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		pb_lbl.add_theme_color_override("font_color", MenuTheme.GOLD)
		col.add_child(pb_lbl)

	var rating: String = _defense_rating_line(challenge)
	if not rating.is_empty():
		var rating_lbl := Label.new()
		rating_lbl.text = rating
		rating_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rating_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
		rating_lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
		col.add_child(rating_lbl)

	btn.add_child(col)
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


func _on_row_toggled(pressed: bool, entry: Dictionary) -> void:
	if not pressed:
		return
	_selected = entry
	if _play_btn != null:
		_play_btn.disabled = false


# --- Import -----------------------------------------------------------------

func _on_import_pressed() -> void:
	if _code_edit == null:
		return
	var code: String = _code_edit.text.strip_edges()
	if code.is_empty():
		_set_import_status("Paste a share code first.")
		return

	var challenge: Dictionary = ChallengeCodec.decode(code)
	if challenge.is_empty():
		_set_import_status("Could not read that code -- it may be incomplete or corrupted.")
		return

	var errors: Array[String] = ChallengeCodec.validate(challenge)
	if not errors.is_empty():
		_set_import_status("Invalid challenge: " + errors[0])
		return

	var path: String = ChallengeCodec.save_to_file(challenge)
	if path.is_empty():
		_set_import_status("Could not save the imported challenge.")
		return

	_code_edit.text = ""
	_set_import_status("Imported '%s'." % String(challenge.get("name", "challenge")))
	# The import joins the daily POOL, so today's pick can change -- repaint the hero too.
	_refresh_daily()
	_refresh_list()


func _set_import_status(text: String) -> void:
	if _import_status != null:
		_import_status.text = text


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
		_set_import_status("Challenge system unavailable.")
		return
	controller.prepare(challenge)
	if not controller.begin():
		_set_import_status("This challenge could not be started (map failed validation).")
		controller.cancel()


## Open the community browser. The scene belongs to a parallel workstream, so the button is
## disabled with an explanatory tooltip when this build does not ship it (see
## [constant COMMUNITY_SCENE]) rather than changing scene to a missing path.
func _on_community_pressed() -> void:
	if not ResourceLoader.exists(COMMUNITY_SCENE):
		_set_import_status("The community browser is not available in this build.")
		return
	get_tree().change_scene_to_file(COMMUNITY_SCENE)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SOLO_SELECT_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		# Don't steal typing while the code field is focused.
		if _code_edit != null and _code_edit.has_focus():
			return
		match (event as InputEventKey).keycode:
			KEY_ENTER, KEY_KP_ENTER:
				if _play_btn != null and not _play_btn.disabled:
					_on_play_pressed()
			KEY_ESCAPE:
				_on_back_pressed()
