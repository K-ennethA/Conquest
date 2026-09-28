extends Control

## STORY START (Solo -> Story): the three journey slots as grove option cards
## (docs/design/OVERWORLD.md §4.10). A filled slot shows where you are, how long you have
## walked, your party's crests and the journey's difficulty tier -- pressing it CONTINUES; an
## empty slot starts a NEW JOURNEY, which first asks for the DIFFICULTY TIER
## (docs/design/DECISIONS.md #29 refinements): two grove choice cards, CLASSIC (permadeath) and
## CASUAL (knocked-out companions recover for gold), each explained, with the rule that a journey
## may later move DOWN a tier but never up. "Delete" (press twice to confirm) clears the focused
## slot.
##
## Keyboard: 1-3 pick a slot, Del deletes the focused one, Esc / B back to the Solo picker. In the
## tier picker: 1 Classic, 2 Casual (or arrows + Confirm), Esc / B back to the slots.

const SOLO_SCENE := "res://menus/SoloModeSelect.tscn"
const CARD_SIZE := Vector2(340, 200)
const TIER_CARD_SIZE := Vector2(420, 330)

var _cards: Array[Button] = []
var _delete_button: Button = null
var _status: Label = null
var _armed_delete: int = 0
var _story = null
var _slot_row: HBoxContainer = null
## The New Journey tier picker (hidden until an empty slot is pressed).
var _tier_box: VBoxContainer = null
var _tier_cards: Dictionary = {}
var _tier_slot: int = 0


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
	_slot_row = row
	_tier_box = _build_tier_picker()
	col.add_child(_tier_box)
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
		var tier: String = String(data.get("tier", StoryState.TIER_CASUAL))
		var tier_l := MenuKit.label(StoryPermadeath.tier_name(tier), &"MutedLabel")
		tier_l.name = "TierTag"
		tier_l.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
		tier_l.add_theme_color_override("font_color",
			MenuTheme.DANGER if tier == StoryState.TIER_CLASSIC else MenuTheme.TEXT_MUTED)
		v.add_child(tier_l)
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


## An empty slot: ask for the difficulty tier first.
func _on_new(slot: int) -> void:
	open_tier_picker(slot)


# --- The New Journey tier picker ----------------------------------------------------------

func _build_tier_picker() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "TierPicker"
	box.add_theme_constant_override("separation", MenuTheme.SP_L)
	box.visible = false
	var head := MenuKit.label("Choose your journey's difficulty", &"SubheadingLabel")
	head.name = "TierHeading"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	var row := HBoxContainer.new()
	row.name = "TierCards"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	box.add_child(row)
	var rs: StoryRuleset = _story.ruleset() if _story != null and _story.has_method("ruleset") else null
	var fee: int = rs.revive_fee_per_member if rs != null else 50
	var classic := MenuKit.choice_card("Classic", "Permadeath",
		StoryPermadeath.tier_blurb(StoryState.TIER_CLASSIC, rs),
		["A fallen companion's item returns to your bag; their story stays in Journey > Party.",
			"Losing the hero, or someone you swore to protect, ends the journey.",
			"You may lower the difficulty later -- never raise it again."],
		MenuTheme.DANGER, null, TIER_CARD_SIZE)
	classic.name = "ClassicCard"
	classic.pressed.connect(_on_tier_picked.bind(StoryState.TIER_CLASSIC))
	row.add_child(classic)
	var casual := MenuKit.choice_card("Casual", "Knocked out, never lost",
		StoryPermadeath.tier_blurb(StoryState.TIER_CASUAL, rs),
		[("Revive at any Wayshrine for %d gold each." % fee) if fee > 0 else "Revive at any Wayshrine for free.",
			"Revive items from merchants work anywhere.",
			"Losing the hero, or someone you swore to protect, still ends the journey."],
		MenuTheme.EL_NATURE, null, TIER_CARD_SIZE)
	casual.name = "CasualCard"
	casual.pressed.connect(_on_tier_picked.bind(StoryState.TIER_CASUAL))
	row.add_child(casual)
	classic.focus_neighbor_right = classic.get_path_to(casual)
	casual.focus_neighbor_left = casual.get_path_to(classic)
	_tier_cards = {StoryState.TIER_CLASSIC: classic, StoryState.TIER_CASUAL: casual}
	return box


## Show the difficulty picker for a new journey in [param slot] (the default tier focused).
func open_tier_picker(slot: int) -> void:
	_tier_slot = slot
	_slot_row.visible = false
	_delete_button.visible = false
	_tier_box.visible = true
	var rs: StoryRuleset = _story.ruleset() if _story != null and _story.has_method("ruleset") else null
	var default_tier: String = rs.default_tier if rs != null else StoryState.TIER_CASUAL
	var focus: Button = _tier_cards.get(default_tier, _tier_cards[StoryState.TIER_CASUAL])
	MenuNav.focus_deferred(focus)
	MenuKit.set_status(_status, "Journey %d -- you can move down a tier later if it's too hard, but never back up." % slot, "")


func is_tier_picker_open() -> bool:
	return _tier_box != null and _tier_box.visible


func close_tier_picker() -> void:
	var slot: int = _tier_slot
	_tier_slot = 0
	_tier_box.visible = false
	_slot_row.visible = true
	_delete_button.visible = true
	MenuKit.set_status(_status, "", "")
	if slot > 0 and slot <= _cards.size():
		_cards[slot - 1].grab_focus()


## The tier cards ({"classic": Button, "casual": Button}).
func tier_cards() -> Dictionary:
	return _tier_cards


func _on_tier_picked(tier: String) -> void:
	if _story == null or _tier_slot <= 0:
		return
	var r: Dictionary = _story.new_journey(_tier_slot, tier)
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
	if is_tier_picker_open():
		close_tier_picker()
		return
	MenuNav.change_scene(self, SOLO_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if is_tier_picker_open():
		var pick: String = ""
		if k.keycode == KEY_1:
			pick = StoryState.TIER_CLASSIC
		elif k.keycode == KEY_2:
			pick = StoryState.TIER_CASUAL
		if not pick.is_empty():
			get_viewport().set_input_as_handled()
			(_tier_cards[pick] as Button).grab_focus()
			(_tier_cards[pick] as Button).pressed.emit()
		return
	if k.keycode == KEY_DELETE:
		get_viewport().set_input_as_handled()
		_on_delete_pressed()
		return
	var idx: int = k.keycode - KEY_1
	if idx >= 0 and idx < _cards.size():
		get_viewport().set_input_as_handled()
		_cards[idx].grab_focus()
		_cards[idx].pressed.emit()
