extends Control

## STORY START (Solo -> Story): the three journey slots as grove option cards
## (docs/design/OVERWORLD.md §4.10). A filled slot shows where you are, how long you have
## walked and your party's crests -- pressing it CONTINUES; an empty slot starts a NEW JOURNEY.
## "Delete" (press twice to confirm) clears the focused slot.
##
## Keyboard: 1-3 pick a slot, Del deletes the focused one, Esc / B back to the Solo picker.

const SOLO_SCENE := "res://menus/SoloModeSelect.tscn"
const CARD_SIZE := Vector2(340, 200)

var _cards: Array[Button] = []
var _delete_button: Button = null
var _status: Label = null
var _armed_delete: int = 0
var _story = null


func _ready() -> void:
	_story = get_node_or_null("/root/StoryController")
	var page := MenuKit.build_page(self, ["Solo"], "Story",
		"Walk the Forgotten Forest: towns, roads, and the battles between them.")
	_build(page)
	if not _cards.is_empty():
		MenuNav.focus_deferred(_cards[0])


func _build(page: Dictionary) -> void:
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.body.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_L)
	center.add_child(col)
	var row := HBoxContainer.new()
	row.name = "SlotCards"
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	col.add_child(row)
	for slot in range(1, StorySaveManager.SLOT_COUNT + 1):
		var card := _slot_card(slot)
		row.add_child(card)
		_cards.append(card)
	_status = MenuKit.label("", &"DimLabel")
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)

	var back := MenuKit.button("Back", MenuKit.GHOST, 140)
	back.name = "BackButton"
	back.pressed.connect(_on_back)
	page.actions.add_child(back)
	_delete_button = MenuKit.button("Delete", MenuKit.GHOST, 140)
	_delete_button.name = "DeleteButton"
	_delete_button.pressed.connect(_on_delete_pressed)
	page.actions.add_child(_delete_button)
	page.actions.move_child(_delete_button, 0)

	MenuKit.add_standard_hints(page.hints, "Play")
	var hint := MenuKit.label("1-3 Slot  •  Del Delete", &"MutedLabel")
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	page.hints.add_child(hint)


func _slot_card(slot: int) -> Button:
	var parts := MenuKit.option_card(CARD_SIZE)
	var btn: Button = parts["button"]
	btn.name = "Slot%dCard" % slot
	var data: Dictionary = StorySaveManager.peek(slot)
	MenuKit.accent_card(btn, MenuTheme.EL_NATURE if not data.is_empty() else MenuTheme.GOLD_DK)
	var v: VBoxContainer = parts["content"]
	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(72, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(rule)
	var head := MenuKit.label("Journey %d" % slot, &"SubheadingLabel")
	head.add_theme_font_size_override("font_size", 22)
	v.add_child(head)
	if data.is_empty():
		var tag := MenuKit.label("NEW JOURNEY", &"SectionLabel")
		tag.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
		v.add_child(tag)
		v.add_child(MenuKit.label("An empty page. Begin at home in Oakvale, at the edge of the forest.", &"DimLabel", true))
		btn.pressed.connect(_on_new.bind(slot))
	elif StorySnapshot.is_outdated(data):
		# A journey from before the story opening (StorySnapshot: not migrated).
		var old := MenuKit.label("OLDER JOURNEY", &"SectionLabel")
		old.add_theme_color_override("font_color", MenuTheme.GOLD_DK)
		v.add_child(old)
		v.add_child(MenuKit.label("Written before the story's new opening. A new journey is required -- Delete it to begin again here.", &"DimLabel", true))
		btn.pressed.connect(_on_outdated.bind(slot))
	else:
		var tag2 := MenuKit.label("CONTINUE", &"SectionLabel")
		tag2.add_theme_color_override("font_color", MenuTheme.EL_NATURE.lightened(0.25))
		v.add_child(tag2)
		v.add_child(MenuKit.label(StorySnapshot.describe(data, _area_names()), &"DimLabel", true))
		v.add_child(_party_row(data))
		btn.pressed.connect(_on_continue.bind(slot))
	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
	btn.focus_entered.connect(func() -> void: _armed_delete = 0)
	return btn


func _party_row(data: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var party = data.get("party", [])
	if party is Array:
		for p in party:
			if not (p is Dictionary):
				continue
			var c: CharacterResource = CharacterLibrary.get_character(StringName(String(p.get("character_id", ""))))
			if c == null:
				continue
			var col: Color = MenuKit.element_color(String(c.element))
			row.add_child(MenuKit.crest(c.display_name.substr(0, 1), col, MenuTheme.GOLD_DK, 34))
	return row


func _area_names() -> Dictionary:
	var out: Dictionary = {}
	if _story == null:
		return out
	for id in _story.all_area_ids():
		out[id] = _story.area_display_name(id)
	return out


func _on_new(slot: int) -> void:
	if _story == null:
		return
	var r: Dictionary = _story.new_journey(slot)
	if not bool(r.get("success", false)):
		MenuKit.set_status(_status, "Could not start a journey (%s)." % String(r.get("reason", "")), "error")
		return
	_story.enter_overworld()


func _on_outdated(slot: int) -> void:
	_cards[slot - 1].grab_focus()
	MenuKit.set_status(_status,
		"Journey %d predates the new opening and cannot be continued. Press Delete to clear it, then start a new journey." % slot,
		"warn")


func _on_continue(slot: int) -> void:
	if _story == null:
		return
	var r: Dictionary = _story.continue_journey(slot)
	if not bool(r.get("success", false)):
		MenuKit.set_status(_status, "That journey could not be loaded (%s)." % String(r.get("reason", "")), "error")
		return
	_story.enter_overworld()


func _focused_slot() -> int:
	for i in range(_cards.size()):
		if _cards[i].has_focus():
			return i + 1
	return 0


func _on_delete_pressed() -> void:
	var slot: int = _focused_slot()
	if slot == 0:
		slot = _armed_delete
	if slot == 0 or not StorySaveManager.has_save(slot):
		MenuKit.set_status(_status, "Focus a saved journey to delete it.", "")
		return
	if _armed_delete != slot:
		_armed_delete = slot
		MenuKit.set_status(_status, "Press Delete again to erase Journey %d." % slot, "warn")
		_cards[slot - 1].grab_focus()
		_armed_delete = slot
		return
	StorySaveManager.delete(slot)
	_armed_delete = 0
	get_tree().reload_current_scene()


func _on_back() -> void:
	MenuNav.change_scene(self, SOLO_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.keycode == KEY_DELETE:
		get_viewport().set_input_as_handled()
		_on_delete_pressed()
		return
	var idx: int = k.keycode - KEY_1
	if idx >= 0 and idx < _cards.size():
		get_viewport().set_input_as_handled()
		_cards[idx].grab_focus()
		_cards[idx].pressed.emit()
