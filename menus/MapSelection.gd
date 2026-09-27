extends Control

class_name MapSelection

## Map picker for Single Player and Local Versus. Left: one card per map (top-down
## thumbnail, name, size / players / difficulty, badges such as Multi-floor or
## Draft). Right: the selected map in a live 3D preview with its description, key
## facts and -- in single player -- the enemy AI difficulty.
##
## Which maps are listed is MapLoader's job (get_available_maps(true), drafts
## included so freshly built maps can be play-tested); this screen only decides
## how they are displayed. Built in code; the .tscn is only the root.
##
## Input: moving focus onto a card selects it; Confirm on the selected card (or the
## "Choose Squad" button) continues. With the mouse, click a card to select it and
## click it again (or the button) to continue.

signal map_selected(map_path: String)
signal back_pressed()

const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const TURN_SYSTEM_SCENE := "res://menus/TurnSystemSelection.tscn"

# UI
var map_cards: VBoxContainer
var select_button: Button
var back_button: Button
var _card_group := ButtonGroup.new()
var _cards: Array[Button] = []
var _count_label: Label
var _scroll: ScrollContainer
var _preview: MapPreview3D
var _name_label: Label
var _badges: HBoxContainer
var _description_label: Label
var _facts: HBoxContainer
var _difficulty_row: Control
var _difficulty_option: OptionButton

# Data
var available_maps: Array[String] = []
var current_selected_map: String = ""
var map_resources: Array[MapResource] = []
var _paths_for_resources: Array[String] = []
var _selected_index: int = -1
# Whether the pressed card was ALREADY the selection when the press began, so the
# first click on a card selects it and a second click continues.
var _was_selected_before_press: bool = false


func _ready() -> void:
	var versus := GameSettings.game_mode == GameSettings.GameMode.VERSUS
	var page := MenuKit.build_page(self, ["Local Versus" if versus else "Single Player"],
		"Choose a Battlefield", "")
	(page.subtitle as Label).visible = false
	_build_body(page.body)

	back_button = MenuKit.button("Back", MenuKit.GHOST, 140)
	back_button.name = "BackButton"
	back_button.pressed.connect(_on_back_button_pressed)
	page.actions.add_child(back_button)
	select_button = MenuKit.button("Choose Squad  >", MenuKit.PRIMARY, 240, 54)
	select_button.name = "SelectButton"
	select_button.disabled = true
	select_button.pressed.connect(_on_select_button_pressed)
	page.actions.add_child(select_button)
	MenuKit.add_standard_hints(page.hints, "Choose map")

	_setup_difficulty_picker()
	_difficulty_row.visible = not versus
	_load_available_maps()
	if not _cards.is_empty():
		_reveal_selected_card()


## Focus the selected card and scroll it into view once layout has settled.
func _reveal_selected_card() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _cards.is_empty() or not is_inside_tree():
		return
	var card := _cards[clampi(_selected_index, 0, _cards.size() - 1)]
	card.grab_focus()
	_scroll.ensure_control_visible(card)


func _build_body(body: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	body.add_child(row)

	# --- Left: map cards -----------------------------------------------------------
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", MenuTheme.SP_S)
	row.add_child(left)
	_count_label = MenuKit.section("Maps")
	left.add_child(_count_label)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.name = "MapScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	left.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_theme_constant_override("margin_right", 14)  # room for focus glow + scrollbar
	scroll.add_child(pad)
	map_cards = VBoxContainer.new()
	map_cards.name = "MapCards"
	map_cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_cards.add_theme_constant_override("separation", 10)
	pad.add_child(map_cards)

	# --- Right: detail pane --------------------------------------------------------
	var detail := MenuKit.card()
	detail.name = "MapDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", MenuTheme.SP_M)
	detail.add_child(dv)

	var well := MenuKit.card(&"InsetPanel")
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.custom_minimum_size = Vector2(0, 200)
	var well_sb := MenuTheme.inset_box()
	well_sb.hatch_alpha = 0.0
	well_sb.set_content_margin_all(3)
	well.add_theme_stylebox_override("panel", well_sb)
	dv.add_child(well)
	_preview = MapPreview3D.new()
	_preview.name = "MapPreview"
	_preview.background_color = MenuTheme.PANEL_SUNK
	_preview.turntable_speed = 0.25
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_child(_preview)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", MenuTheme.SP_M)
	dv.add_child(name_row)
	_name_label = MenuKit.label("", &"HeadingLabel")
	_name_label.name = "MapNameLabel"
	name_row.add_child(_name_label)
	_badges = HBoxContainer.new()
	_badges.add_theme_constant_override("separation", MenuTheme.SP_S)
	_badges.alignment = BoxContainer.ALIGNMENT_BEGIN
	name_row.add_child(_badges)

	_description_label = MenuKit.label("", &"DimLabel", true)
	_description_label.name = "MapDescriptionLabel"
	dv.add_child(_description_label)

	_facts = HBoxContainer.new()
	_facts.name = "MapFacts"
	_facts.add_theme_constant_override("separation", MenuTheme.SP_XXL)
	dv.add_child(_facts)

	_difficulty_row = VBoxContainer.new()
	dv.add_child(_difficulty_row)


# --- Difficulty -----------------------------------------------------------------------

func _setup_difficulty_picker() -> void:
	"""The single-player 'Enemy AI' difficulty dropdown (written to GameSettings)."""
	_difficulty_row.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.name = "DifficultyRow"
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	_difficulty_row.add_child(row)

	var label := MenuKit.label("Enemy AI", &"SubheadingLabel")
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	_difficulty_option = OptionButton.new()
	_difficulty_option.name = "DifficultyOption"
	_difficulty_option.custom_minimum_size = Vector2(170, 46)
	for i in range(4):  # BotController.Difficulty: EASY..BRUTAL
		_difficulty_option.add_item(BotController.difficulty_name(i), i)
	_difficulty_option.select(clampi(GameSettings.ai_difficulty, 0, 3))
	_difficulty_option.item_selected.connect(_on_difficulty_selected)
	MenuNav.hover_focus(_difficulty_option)
	row.add_child(_difficulty_option)

	var note := MenuKit.label("Harder AI plays sharper -- and some maps field extra enemies on Hard and above.", &"MutedLabel", true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(note)


func _on_difficulty_selected(index: int) -> void:
	"""Store the chosen AI difficulty for the game to read."""
	GameSettings.set_ai_difficulty(_difficulty_option.get_item_id(index))


# --- Map discovery (listing logic unchanged: MapLoader decides WHICH maps) -------------

func _load_available_maps() -> void:
	"""Load all available map files and build a card for each."""
	available_maps.clear()
	map_resources.clear()
	_paths_for_resources.clear()
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_selected_index = -1

	# Drafts (Inactive) ARE included here: this is the local / single-player picker,
	# and you must be able to play-test a map you just built. Network setup keeps its
	# own draft-free list (see NetworkMultiplayerSetup).
	available_maps = MapLoader.get_available_maps(true)

	# If no maps exist, create a default one
	if available_maps.is_empty():
		print("No maps found, creating default map")
		_create_default_map()
		available_maps = MapLoader.get_available_maps(true)

	for map_path in available_maps:
		var map_resource = load(map_path) as MapResource
		if map_resource:
			map_resources.append(map_resource)
			_paths_for_resources.append(map_path)
			var card := _make_map_card(map_resource, map_resources.size() - 1)
			map_cards.add_child(card)
			_cards.append(card)
		else:
			push_warning("MapSelection: failed to load map " + map_path)

	_count_label.text = "MAPS  (%d)" % map_resources.size()

	# Re-select the previously chosen map, else the first.
	var start := _paths_for_resources.find(String(GameSettings.selected_map_path))
	if map_resources.size() > 0:
		_on_map_selected(start if start >= 0 else 0)


func _create_default_map() -> void:
	"""Create and save a default map"""
	var default_map = MapLoader.create_default_map()
	MapLoader.save_map(default_map, "default_skirmish")


func _make_map_card(res: MapResource, index: int) -> Button:
	var parts := MenuKit.option_card(Vector2(0, 104), true)
	var b: Button = parts["button"]
	b.name = "MapCard%d" % index
	b.button_group = _card_group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = parts["margin"]
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var content: VBoxContainer = parts["content"]

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", MenuTheme.SP_L)
	content.add_child(h)

	var thumb_frame := PanelContainer.new()
	var thumb_sb := MenuTheme.inset_box()
	thumb_sb.corner = 6.0
	thumb_sb.border_color = MenuTheme.GOLD_DK
	thumb_sb.set_content_margin_all(3)
	thumb_frame.add_theme_stylebox_override("panel", thumb_sb)
	thumb_frame.custom_minimum_size = Vector2(118, 78)
	thumb_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(thumb_frame)
	var thumb := TextureRect.new()
	thumb.texture = MapPreview3D.thumbnail(res, 8)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	thumb_frame.add_child(thumb)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 4)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(text)
	var title := MenuKit.label(_display_name(res), &"SubheadingLabel")
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(title)
	var meta := MenuKit.label("%d x %d   %d players   %s" % [res.width, res.height,
		maxi(res.max_players, 1), res.difficulty], &"DimLabel")
	meta.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	text.add_child(meta)
	var badges := _badges_for(res)
	if badges.get_child_count() > 0:
		text.add_child(badges)

	MenuKit.ignore_mouse(b)
	b.focus_entered.connect(_on_card_focused.bind(index))
	b.button_down.connect(_remember_selection.bind(index))
	b.pressed.connect(_on_card_pressed.bind(index))
	return b


func _display_name(res: MapResource) -> String:
	var n := res.map_name
	if n.is_empty():
		var i := map_resources.find(res)
		n = _paths_for_resources[i].get_file().get_basename() if i >= 0 else "Unnamed Map"
	return n


func _badges_for(res: MapResource) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var floors := res.get_floor_count() if res.has_method("get_floor_count") else 1
	if floors > 1:
		row.add_child(MenuKit.badge("Multi-floor (%d)" % floors, MenuTheme.ACCENT))
	if "Defeat Boss" in res.victory_conditions:
		row.add_child(MenuKit.badge("Boss", MenuTheme.DANGER))
	if not res.is_active():
		row.add_child(MenuKit.badge("Draft", MenuTheme.WARNING))
	return row


# --- Selection ----------------------------------------------------------------------------

func _on_card_focused(index: int) -> void:
	# A mouse press also focuses the card; let the click itself decide (select first).
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	_on_map_selected(index)


func _on_card_pressed(index: int) -> void:
	# Second press on the already-selected card continues (keyboard: focus already
	# selected it, so Confirm continues at once); otherwise just select it.
	if _was_selected_before_press:
		_on_select_button_pressed()
	else:
		_on_map_selected(index)


func _remember_selection(index: int) -> void:
	_was_selected_before_press = index == _selected_index


func _on_map_selected(index: int) -> void:
	"""Select map [param index]: highlight its card and fill the detail pane."""
	if index < 0 or index >= map_resources.size():
		return
	_selected_index = index
	current_selected_map = _paths_for_resources[index]
	for i in _cards.size():
		_cards[i].set_pressed_no_signal(i == index)
	_display_map_info(map_resources[index])
	if select_button:
		select_button.disabled = false


func _on_map_activated(index: int) -> void:
	_on_map_selected(index)
	_on_select_button_pressed()


func _display_map_info(map_resource: MapResource) -> void:
	"""Fill the detail pane for the selected map."""
	if not map_resource:
		return
	var info = map_resource.get_display_info()
	_name_label.text = _display_name(map_resource)
	for c in _badges.get_children():
		c.queue_free()
	var diff_color := MenuTheme.SUCCESS
	match String(info.get("difficulty", "Normal")).to_lower():
		"hard": diff_color = MenuTheme.WARNING
		"expert", "brutal": diff_color = MenuTheme.DANGER
		"normal": diff_color = MenuTheme.ACCENT
	_badges.add_child(MenuKit.badge(String(info.get("difficulty", "Normal")), diff_color))
	for b in _badges_for(map_resource).get_children():
		b.get_parent().remove_child(b)
		_badges.add_child(b)

	var desc := String(info.get("description", ""))
	_description_label.text = desc if desc != "" else "No description yet."

	for c in _facts.get_children():
		c.queue_free()
	var mine := 0
	for s in map_resource.unit_spawns:
		if int(s.get("player_id", -1)) == 0:
			mine += 1
	_facts.add_child(MenuKit.stat_block("Size", String(info.get("size", "?")).replace("x", " x ")))
	_facts.add_child(MenuKit.stat_block("Players", str(maxi(int(info.get("max_players", 2)), 1))))
	_facts.add_child(MenuKit.stat_block("Your squad", "up to %d" % mine if mine > 0 else "--"))
	var floors := map_resource.get_floor_count()
	if floors > 1:
		_facts.add_child(MenuKit.stat_block("Floors", str(floors)))
	var goal := ", ".join(map_resource.victory_conditions) if not map_resource.victory_conditions.is_empty() else "Eliminate all enemies"
	var goal_block := MenuKit.stat_block("Objective", goal)
	goal_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_facts.add_child(goal_block)

	if _preview:
		_preview.show_map(map_resource)


# --- Navigation ---------------------------------------------------------------------------

func _on_select_button_pressed() -> void:
	"""Store the selected map and continue to squad selection."""
	if current_selected_map.is_empty():
		return
	GameSettings.set_selected_map(current_selected_map)
	map_selected.emit(current_selected_map)

	# Pick a squad for this map before the battle starts (Character Select then launches
	# the GameWorld). Clear any Arena ruleset staged earlier so a map launch can never be
	# mistaken for an Arena run.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("abort_run"):
		arena.abort_run()
	MenuNav.change_scene(self, CHARACTER_SELECT_SCENE)


func _on_back_button_pressed() -> void:
	back_pressed.emit()
	MenuNav.change_scene(self, TURN_SYSTEM_SCENE)


func _on_refresh_button_pressed() -> void:
	_load_available_maps()


func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_button_pressed()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F5:
		_on_refresh_button_pressed()


func get_selected_map_path() -> String:
	"""Get the currently selected map path"""
	return current_selected_map


func get_selected_map_resource() -> MapResource:
	"""Get the currently selected map resource"""
	if _selected_index >= 0 and _selected_index < map_resources.size():
		return map_resources[_selected_index]
	return null
