extends Control

class_name CampaignScreen

## The campaign chapter list, reached from SoloModeSelect's Campaign card. Renders the
## ordered [CampaignData] chapters as a vertical column of cards in the dark "Legends"
## menu register ([MenuTheme]). Each card shows its chapter number, title, story blurb,
## map name, and a status line -- CLEARED (with the best turn count) for a beaten chapter,
## or LOCKED (dimmed, non-interactive) for one whose predecessor is still standing.
##
## Progress + unlock state come from [b]CampaignController[/b] (the autoload that also
## persists them). Choosing a chapter stages it there and hands off to Character Select
## via CampaignController.begin(). The list opens focused on the first unlocked-and-
## uncleared chapter (where the player should resume); cleared chapters can be replayed.
##
## Keyboard: Up / Down move the selection between PLAYABLE chapters, Enter plays the
## selected one, ESC returns to SoloModeSelect.

const SOLO_MODE_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"

## Parallel to CampaignData.chapters(): the card Button for each chapter, and whether it
## is playable (unlocked). Selection only ever lands on a playable card.
var _cards: Array[Button] = []
var _playable: Array[bool] = []
var _chapters: Array = []
var _selected: int = -1

var _hint_label: Label = null


func _ready() -> void:
	theme = MenuTheme.build()
	MenuTheme.apply_backdrop(self)
	_chapters = CampaignData.chapters()
	_build_ui()
	_select_default()


func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var page := VBoxContainer.new()
	page.custom_minimum_size = Vector2(920.0, 0.0)
	page.add_theme_constant_override("separation", 14)
	center.add_child(page)

	var title := Label.new()
	title.text = "CAMPAIGN"
	page.add_child(title)
	MenuTheme.style_title(title, 40)

	var subtitle := Label.new()
	subtitle.text = "Drive the blight from the Forgotten Forest, chapter by chapter."
	page.add_child(subtitle)
	MenuTheme.style_subtitle(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	page.add_child(spacer)

	# Scrollable chapter column (fits any future chapter count without overflowing).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 470.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)

	for i in range(_chapters.size()):
		var unlocked: bool = _chapter_unlocked(_chapters[i])
		_playable.append(unlocked)
		var card := _make_chapter_card(i, _chapters[i], unlocked)
		_cards.append(card)
		list.add_child(card)

	var foot := Control.new()
	foot.custom_minimum_size = Vector2(0.0, 6.0)
	page.add_child(foot)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0.0, 44.0)
	back.pressed.connect(_on_back_pressed)
	page.add_child(back)

	_hint_label = Label.new()
	_hint_label.text = "Up / Down select  •  Enter play  •  ESC back"
	page.add_child(_hint_label)
	MenuTheme.style_caption(_hint_label)


## One chapter card: number badge + title on top, blurb + map name below, and a status
## line (CLEARED + best turns, or LOCKED). Locked cards are disabled and dimmed.
func _make_chapter_card(index: int, chapter: Dictionary, unlocked: bool) -> Button:
	var id: String = String(chapter.get("id", ""))
	var cleared: bool = _chapter_cleared(id)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0.0, 96.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggle_mode = true
	btn.disabled = not unlocked
	if unlocked:
		btn.pressed.connect(_on_card_pressed.bind(index))
		btn.focus_entered.connect(_on_card_focused.bind(index))
	else:
		btn.focus_mode = Control.FOCUS_NONE
		btn.modulate = Color(1, 1, 1, 0.55)

	# Content laid over the button; IGNORE mouse so clicks reach the button itself.
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 16.0
	row.offset_right = -16.0
	row.offset_top = 10.0
	row.offset_bottom = -10.0
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Chapter-number badge.
	var num := Label.new()
	num.text = str(int(chapter.get("number", index + 1)))
	num.custom_minimum_size = Vector2(52.0, 0.0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.add_theme_font_size_override("font_size", 40)
	num.add_theme_color_override("font_color", MenuTheme.GOLD if unlocked else MenuTheme.CREAM_DIM)
	row.add_child(num)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)

	var head := Label.new()
	head.text = String(chapter.get("title", "Chapter %d" % (index + 1)))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	head.add_theme_color_override("font_color", MenuTheme.CREAM if unlocked else MenuTheme.CREAM_DIM)
	col.add_child(head)

	var blurb := Label.new()
	blurb.text = String(chapter.get("blurb", ""))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blurb.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	blurb.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(blurb)

	var meta := Label.new()
	meta.text = "Map: %s      Difficulty: %s" % [
		_map_name_for(chapter), _difficulty_label(int(chapter.get("ai_difficulty", 1)))]
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	meta.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	col.add_child(meta)

	row.add_child(col)

	# Status column (right): CLEARED + best turns, or LOCKED.
	var status := Label.new()
	status.custom_minimum_size = Vector2(150.0, 0.0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	if not unlocked:
		status.text = "LOCKED"
		status.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
	elif cleared:
		var bt: int = _chapter_best_turns(id)
		status.text = "CLEARED" + ("\nBest: %d turns" % bt if bt > 0 else "")
		status.add_theme_color_override("font_color", MenuTheme.GOLD)
	else:
		status.text = "Ready"
		status.add_theme_color_override("font_color", MenuTheme.GOLD_DK)
	row.add_child(status)

	btn.add_child(row)
	return btn


# --- Selection --------------------------------------------------------------

## Focus the first unlocked-and-uncleared chapter (resume point), else the last playable.
func _select_default() -> void:
	var target: int = -1
	for i in range(_chapters.size()):
		if not _playable[i]:
			continue
		if target < 0:
			target = i  # first playable = fallback
		if not _chapter_cleared(String(_chapters[i].get("id", ""))):
			target = i
			break
	if target >= 0:
		_focus_card(target)


func _focus_card(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_selected = index
	for i in range(_cards.size()):
		_cards[i].set_pressed_no_signal(i == index and _playable[i])
	if _cards[index] != null and _playable[index]:
		_cards[index].grab_focus()


func _on_card_focused(index: int) -> void:
	_selected = index
	for i in range(_cards.size()):
		_cards[i].set_pressed_no_signal(i == index and _playable[i])


func _on_card_pressed(index: int) -> void:
	_play(index)


## Move the selection to the next/previous PLAYABLE chapter.
func _move_selection(step: int) -> void:
	if _cards.is_empty():
		return
	var i: int = _selected
	for _n in range(_cards.size()):
		i = wrapi(i + step, 0, _cards.size())
		if _playable[i]:
			_focus_card(i)
			return


func _play(index: int) -> void:
	if index < 0 or index >= _chapters.size() or not _playable[index]:
		return
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign == null:
		return
	campaign.prepare(_chapters[index])
	if campaign.has_method("begin"):
		campaign.begin()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(SOLO_MODE_SELECT_SCENE)


func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_UP:
				_move_selection(-1)
				get_viewport().set_input_as_handled()
			KEY_DOWN:
				_move_selection(1)
				get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER:
				if _selected >= 0:
					_play(_selected)
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				_on_back_pressed()
				get_viewport().set_input_as_handled()


# --- Controller queries (null-guarded so the screen renders without the autoload) ----

func _chapter_unlocked(chapter: Dictionary) -> bool:
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("is_unlocked"):
		return bool(campaign.is_unlocked(String(chapter.get("id", ""))))
	# No controller (isolated preview): only the first chapter is playable.
	return CampaignData.index_of_id(String(chapter.get("id", ""))) == 0


func _chapter_cleared(id: String) -> bool:
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("is_cleared"):
		return bool(campaign.is_cleared(id))
	return false


func _chapter_best_turns(id: String) -> int:
	var campaign := get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("best_turns"):
		return int(campaign.best_turns(id))
	return -1


# --- Display helpers --------------------------------------------------------

## The chapter map's authored name, falling back to the file stem when it will not load.
func _map_name_for(chapter: Dictionary) -> String:
	var path: String = String(chapter.get("map_path", ""))
	var res := load(path) as MapResource
	if res != null and not String(res.map_name).is_empty():
		return String(res.map_name)
	return path.get_file().get_basename().capitalize()


func _difficulty_label(diff: int) -> String:
	match diff:
		0: return "Easy"
		1: return "Normal"
		2: return "Hard"
		3: return "Brutal"
		_: return "Normal"
