extends Control

class_name CampaignScreen

## The campaign chapter list, reached from SoloModeSelect's Campaign card. Renders the
## ordered [CampaignData] chapters as a vertical column of grove cards ([MenuKit] /
## [MenuTheme], see docs/UI_STYLE.md). Each card shows its chapter number as a heraldic
## crest, the title, story blurb, map name and difficulty, and a status badge -- CLEARED
## (with the best turn count) for a beaten chapter, READY for one still to play, or LOCKED
## (sunk, non-interactive) for one whose predecessor is still standing.
##
## Progress + unlock state come from [b]CampaignController[/b] (the autoload that also
## persists them). Choosing a chapter stages it there and hands off to Character Select
## via CampaignController.begin(). The list opens focused on the first unlocked-and-
## uncleared chapter (where the player should resume); cleared chapters can be replayed.
##
## Input: Up / Down (arrows, D-pad) move between PLAYABLE chapters -- locked cards take no
## focus, so focus navigation skips them -- and focusing a card selects it. Confirm (Enter /
## A) or a click on a card plays it, as does the "Play Chapter" button; Cancel (Esc / B)
## returns to SoloModeSelect.

const SOLO_MODE_SELECT_SCENE := "res://menus/SoloModeSelect.tscn"

## Parallel to CampaignData.chapters(): the card Button for each chapter, and whether it
## is playable (unlocked). Selection only ever lands on a playable card.
var _cards: Array[Button] = []
var _playable: Array[bool] = []
var _chapters: Array = []
var _selected: int = -1

var _play_btn: Button = null
var _back_btn: Button = null
var _scroll: ScrollContainer = null


func _ready() -> void:
	_chapters = CampaignData.chapters()
	_build_ui()
	_select_default()


func _build_ui() -> void:
	# Page chrome (backdrop, breadcrumb, title, rule, footer) from the shared kit. The body
	# is ONE EXPAND_FILL scroll, so the footer stays pinned at 720p however many chapters
	# ship: MenuKit's header + footer take ~255 of 720 and the scroll absorbs the rest.
	var page := MenuKit.build_page(self, ["Solo"], "Campaign",
		"Drive the blight from the Forgotten Forest, chapter by chapter.")

	_scroll = ScrollContainer.new()
	_scroll.name = "ChapterScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	page.body.add_child(_scroll)

	# Room for the focus ring's glow + the scrollbar, like the other card columns.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_theme_constant_override("margin_right", 14)
	_scroll.add_child(pad)

	var list := VBoxContainer.new()
	list.name = "ChapterList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", MenuTheme.SP_M)
	pad.add_child(list)

	for i in range(_chapters.size()):
		var unlocked: bool = _chapter_unlocked(_chapters[i])
		_playable.append(unlocked)
		var card := _make_chapter_card(i, _chapters[i], unlocked)
		_cards.append(card)
		list.add_child(card)

	if _chapters.is_empty():
		list.add_child(MenuKit.label("No chapters in this build yet.", &"DimLabel"))

	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)

	_play_btn = MenuKit.button("Play Chapter  >", MenuKit.PRIMARY, 240, 54)
	_play_btn.name = "PlayButton"
	_play_btn.disabled = true
	_play_btn.pressed.connect(func() -> void: _play(_selected))
	page.actions.add_child(_play_btn)

	page.hints.add_child(MenuKit.key_hint("Up/Down", "D-Pad", "Choose"))
	MenuKit.add_standard_hints(page.hints, "Play")


## One chapter card: crest (chapter number) + title, blurb, map / difficulty line, and a
## status badge on the right (CLEARED + best turns, READY, or LOCKED). Locked cards are
## disabled (the OptionCard's sunk look) and take no focus.
func _make_chapter_card(index: int, chapter: Dictionary, unlocked: bool) -> Button:
	var id: String = String(chapter.get("id", ""))
	var cleared: bool = _chapter_cleared(id)

	var parts := MenuKit.option_card(Vector2(0.0, 104.0), true)
	var btn: Button = parts["button"]
	btn.name = "Chapter%d" % index
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.disabled = not unlocked
	# A cleared chapter wears the grove's "done" green down its edge; the others keep the
	# plain frame (gold is reserved for focus / selection).
	if unlocked and cleared:
		MenuKit.accent_card(btn, MenuTheme.SUCCESS)
	if unlocked:
		btn.pressed.connect(_on_card_pressed.bind(index))
		btn.focus_entered.connect(_on_card_focused.bind(index))
	else:
		btn.focus_mode = Control.FOCUS_NONE
	var content: VBoxContainer = parts["content"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	content.add_child(row)

	# Chapter number as a heraldic crest: grove green for a playable chapter, sunk for a
	# locked one; a gold rim once it is cleared.
	var number: int = int(chapter.get("number", index + 1))
	var field: Color = MenuTheme.EL_NATURE if unlocked else MenuTheme.BORDER
	var ring: Color = MenuTheme.GOLD if cleared else MenuTheme.GOLD_DK
	var crest := MenuKit.crest(str(number), field, ring, 56.0)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(crest)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	row.add_child(col)

	var head := MenuKit.label(String(chapter.get("title", "Chapter %d" % (index + 1))),
		&"SubheadingLabel")
	if not unlocked:
		head.add_theme_color_override("font_color", MenuTheme.TEXT_MUTED)
	col.add_child(head)

	var blurb := MenuKit.label(String(chapter.get("blurb", "")),
		&"DimLabel" if unlocked else &"MutedLabel", true)
	blurb.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	col.add_child(blurb)

	var meta := MenuKit.label("Map: %s      Difficulty: %s" % [
		_map_name_for(chapter), _difficulty_label(int(chapter.get("ai_difficulty", 1)))],
		&"MutedLabel")
	meta.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(meta)

	# Status column (right): CLEARED + best turns, READY, or LOCKED.
	var status := VBoxContainer.new()
	status.custom_minimum_size = Vector2(150.0, 0.0)
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_theme_constant_override("separation", 4)
	row.add_child(status)
	var badge: PanelContainer
	if not unlocked:
		badge = MenuKit.badge("LOCKED", MenuTheme.TEXT_MUTED)
	elif cleared:
		badge = MenuKit.badge("CLEARED", MenuTheme.SUCCESS)
	else:
		badge = MenuKit.badge("READY", MenuTheme.GOLD)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	status.add_child(badge)
	if unlocked and cleared:
		var bt: int = _chapter_best_turns(id)
		if bt > 0:
			var best := MenuKit.label("Best: %d turns" % bt, &"DimLabel")
			best.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
			best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			status.add_child(best)

	MenuKit.ignore_mouse(btn)
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
	elif _back_btn != null:
		_focus_later(_back_btn)


func _focus_card(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	_mark_selected(index)
	if _cards[index] != null and _playable[index]:
		_focus_later(_cards[index])


func _on_card_focused(index: int) -> void:
	_mark_selected(index)


## Record [param index] as the selection and show it: the selected card wears the
## OptionCard "pressed" frame (gold border + crest) and the Play button wakes up.
func _mark_selected(index: int) -> void:
	_selected = index
	for i in range(_cards.size()):
		_cards[i].set_pressed_no_signal(i == index and _playable[i])
	if _play_btn != null:
		_play_btn.disabled = index < 0 or index >= _playable.size() or not _playable[index]


func _on_card_pressed(index: int) -> void:
	_play(index)


## Move the selection to the next/previous PLAYABLE chapter (wrapping). Used when nothing
## on the page holds focus, so a D-pad press still lands somewhere sensible.
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
	MenuNav.change_scene(self, SOLO_MODE_SELECT_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
		return
	# Focus navigation already consumed Up / Down when a control holds focus; this only
	# catches the case where nothing does (e.g. the mouse clicked empty space).
	if get_viewport().gui_get_focus_owner() != null:
		return
	if event.is_pressed() and not event.is_echo():
		if event.is_action_pressed(&"ui_up"):
			_move_selection(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"ui_down"):
			_move_selection(1)
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
