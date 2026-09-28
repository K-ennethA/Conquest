class_name JourneyMenu
extends CanvasLayer

## The JOURNEY MENU (Esc / Start on the overworld) -- the grove MapMenu look: a gold-framed card
## of command rows. M1 ships Resume · Party · Save · Title; Bag, Quests, Map and Settings are M2
## (docs/design/OVERWORLD.md §4.10). Modal: in InputActions.OVERLAY_GROUP while open.

const LAYER_INDEX: int = 60

signal closed
signal save_requested
signal title_requested

var _root: Control = null
var _card: PanelContainer = null
var _rows: VBoxContainer = null
var _party: VBoxContainer = null
var _status: Label = null
var _buttons: Array[Button] = []
var _state: StoryState = null


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "JourneyRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = ConquestTheme.build()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(MenuTheme.BG_DEEP, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 48)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	_card = PanelContainer.new()
	_card.name = "JourneyCard"
	_card.custom_minimum_size = Vector2(300, 0)
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(18)
	sb.content_margin_top = 26
	_card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(_card)
	row.add_child(_card)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	_card.add_child(_rows)
	var title := ConquestTheme.title_ribbon("JOURNEY", MenuTheme.GOLD_DK, MenuTheme.FS_SUBHEADING)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_rows.add_child(title)
	_add_row("Resume", close)
	_add_row("Party", _toggle_party)
	_add_row("Save", func() -> void: save_requested.emit())
	_add_row("Title Screen", func() -> void: title_requested.emit())
	_status = MenuKit.label("", &"DimLabel")
	_status.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(_status)

	_party = VBoxContainer.new()
	_party.name = "PartyPanel"
	_party.custom_minimum_size = Vector2(420, 0)
	_party.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_party.add_theme_constant_override("separation", 8)
	_party.visible = false
	row.add_child(_party)


func _add_row(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.name = text.replace(" ", "") + "Row"
	b.theme_type_variation = &"HudCommand"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	MenuNav.hover_focus(b)
	_rows.add_child(b)
	_buttons.append(b)


func is_open() -> bool:
	return _root.visible


func open(state: StoryState) -> void:
	_state = state
	_status.text = "Gold %d  ·  %s" % [state.gold if state != null else 0,
		StorySnapshot.format_play_time(int(state.play_seconds)) if state != null else ""]
	_party.visible = false
	_root.visible = true
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func close() -> void:
	if not _root.visible:
		return
	_root.visible = false
	_root.remove_from_group(InputActions.OVERLAY_GROUP)
	closed.emit()


func set_status(text: String) -> void:
	_status.text = text


func _toggle_party() -> void:
	_party.visible = not _party.visible
	if not _party.visible:
		return
	for c in _party.get_children():
		_party.remove_child(c)
		c.queue_free()
	if _state == null:
		return
	var head := ConquestTheme.title_ribbon("PARTY", MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	head.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_party.add_child(head)
	for i in range(_state.party.size()):
		_party.add_child(_member_card(_state.party[i], i == 0))


func _member_card(m: StoryPartyMember, is_lead: bool) -> PanelContainer:
	var c: CharacterResource = m.character()
	var el_col: Color = MenuKit.element_color(String(c.element)) if c != null else MenuTheme.GOLD
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuTheme.accented_card(el_col))
	ConquestTheme.keep_style(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	row.add_child(ConquestTheme.portrait(m.display_name().substr(0, 1), el_col, MenuTheme.GOLD_DK, 44))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name_l := MenuKit.label(m.display_name() + ("  ·  Lead" if is_lead else ""), &"SubheadingLabel")
	name_l.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	col.add_child(name_l)
	var bar := ConquestTheme.hp_bar(10.0)
	bar.max_value = m.max_hp()
	bar.value = m.hp_value()
	ConquestTheme.tint_hp_bar(bar, float(m.hp_value()) / float(maxi(1, m.max_hp())))
	col.add_child(bar)
	var hp := MenuKit.label("HP %d / %d%s" % [m.hp_value(), m.max_hp(), "  ·  Wounded" if m.wounded else ""], &"DimLabel")
	hp.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(hp)
	return card


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if MenuNav.is_back_event(event) or event.is_action_pressed(InputActions.MAP_MENU):
		get_viewport().set_input_as_handled()
		close()
