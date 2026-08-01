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
## Selecting a card and pressing Play hands the challenge to [ChallengeController], which
## materialises its map, points the game at it, and routes into the squad pick -> battle.
## Every dependency is null-guarded so a missing autoload or an unreadable file degrades
## gracefully rather than crashing the screen.

const SOLO_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"

var _entries: Array[Dictionary] = []      # [{ path, challenge }]
var _selected: Dictionary = {}            # the chosen entry, or {}

# --- Live node refs ---------------------------------------------------------
var _list_box: VBoxContainer = null
var _row_group: ButtonGroup = null
var _code_edit: LineEdit = null
var _import_status: Label = null
var _play_btn: Button = null


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_row_group = ButtonGroup.new()
	_build_ui()
	_refresh_list()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(760.0, 620.0)
	page.add_theme_constant_override("separation", 14)
	center.add_child(page)

	var title := Label.new()
	title.text = "CHALLENGES"
	page.add_child(title)
	MenuTheme.style_title(title, 40)

	var subtitle := Label.new()
	subtitle.text = "Beat a map someone else built -- or import a share code"
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

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
	scroll.custom_minimum_size = Vector2(0.0, 340.0)
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
	btn.custom_minimum_size = Vector2(0.0, 74.0)
	btn.toggled.connect(func(pressed: bool): _on_row_toggled(pressed, entry))

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.text = String(challenge.get("name", "Untitled"))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_HEADER)
	col.add_child(name_lbl)

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


## Personal-best line from the local results file, or "" if never played.
func _personal_best_line(challenge: Dictionary) -> String:
	var controller := get_node_or_null("/root/ChallengeController")
	if controller == null or not controller.has_method("result_for"):
		return ""
	var id: String = ChallengeCodec.challenge_id(challenge)
	var rec: Dictionary = controller.result_for(id)
	if rec.is_empty():
		return ""
	if bool(rec.get("won", false)) and int(rec.get("best_turns", -1)) >= 0:
		return "Personal best: cleared in %d turns" % int(rec.get("best_turns"))
	return "Attempted -- not yet cleared"


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
	_refresh_list()


func _set_import_status(text: String) -> void:
	if _import_status != null:
		_import_status.text = text


# --- Play / Back ------------------------------------------------------------

func _on_play_pressed() -> void:
	if _selected.is_empty():
		return
	var challenge: Dictionary = _selected.get("challenge", {})
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
