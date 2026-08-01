extends Control

## Squad-picker screen shown before a battle, for BOTH map modes (Skirmish / Local Versus)
## and Arena. The player chooses which characters make up their player-0 squad, up to a
## mode-derived limit, then confirms into the battle.
##
## Launch paths (all change to THIS scene, then Character Select dispatches):
##   * Map launch    -- MatchSetup stages GameSettings.selected_map_path and comes here.
##                      MAX = number of player-0 spawn slots on that map. Confirm loads
##                      GameWorld.tscn itself.
##   * Arena launch   -- MatchSetup (arena variant) stages a pending run on ArenaController
##                      and comes here. MAX = ArenaController.pending_squad_size(). Confirm
##                      calls begin_pending_run(), which starts the run AND changes scene.
##
## Layout (built PROGRAMMATICALLY in _ready over the warm-amber ConquestTheme palette):
##   LEFT   -- roster grid of toggle cells (pick membership; MAX enforced).
##   RIGHT  -- a details pane that populates on HOVER and on SELECTION: name, element chip,
##             HP/ATK/DEF/SPD, ability name+description, and the four moves.
##   BOTTOM -- squad slot chips filling with picked unit names in order; click a chip to
##             unpick that unit.
## Every dependency is null-guarded: a missing autoload, an unreadable map, or an empty
## roster all degrade gracefully (fall back to MAX=4 / "Battle", or offer only BACK).

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MATCH_SETUP_SCENE := "res://menus/MatchSetup.tscn"
const CHALLENGE_BROWSE_SCENE := "res://menus/ChallengeBrowse.tscn"
const DEFAULT_MAX := 4
const GRID_COLUMNS := 2

# Characters excluded from the pickable roster regardless of is_boss: the neutral
# beast and the summon-only undead body are never player squad picks.
const EXCLUDED_IDS := ["undead"]

# --- Warm palette (ConquestTheme with hardcoded fallbacks so a missing constant
# can never crash the screen; mirrors ArenaSetupScreen). ----------------------
var _bg_top: Color = Color(0.10, 0.075, 0.05, 1.0)
var _bg_bottom: Color = Color(0.05, 0.035, 0.02, 1.0)
var _ink: Color = Color("2a1608")
var _cream: Color = Color("fcefd6")
var _cream_dim: Color = Color("e7d3ad")
var _amber: Color = Color("e6a64b")
var _amber_lite: Color = Color("f0c072")
var _amber_dk: Color = Color("c6822f")
var _brown: Color = Color("5a3a1e")
var _brown_dk: Color = Color("37220f")
var _gold: Color = Color("f0c040")

# --- Mode / selection state -------------------------------------------------
var _is_arena: bool = false
var _is_challenge: bool = false
var _max_units: int = DEFAULT_MAX
var _destination: String = "Battle"
# Ordered list of chosen character_id STRINGS (click order preserved).
var _chosen_ids: Array = []
# character_id String -> its toggle Button, so we can refresh visuals / disabled state.
var _unit_buttons: Dictionary = {}
# character_id String -> [name_label, element_label], so selection can recolor text.
var _unit_labels: Dictionary = {}
# character_id String -> CharacterResource, cached for the details pane.
var _char_by_id: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _counter_label: Label = null
var _message_label: Label = null
var _confirm_btn: Button = null
var _back_btn: Button = null
var _slots_row: HBoxContainer = null

# Details pane refs.
var _detail_name: Label = null
var _detail_chip_panel: PanelContainer = null
var _detail_chip_label: Label = null
var _detail_stats: Label = null
var _detail_ability_box: VBoxContainer = null
var _detail_moves_box: VBoxContainer = null
var _detail_hint: Label = null


func _ready() -> void:
	_load_palette()
	_resolve_mode()
	_build_background()
	_build_ui()
	_refresh_selection_visuals()
	_refresh_slots()
	_show_details("")  # prompt state until a unit is hovered / picked.


# --- Mode + limit resolution ------------------------------------------------

## Decide whether this is an Arena or Map launch and compute the pick limit MAX.
func _resolve_mode() -> void:
	# Challenge launch: the map is already staged in GameSettings by ChallengeController.
	# MAX = the author's challenger_squad_size. Confirm runs the normal map -> GameWorld
	# path (no special-casing needed there); only the pick limit + header differ.
	var challenge := get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("has_pending_challenge") and challenge.has_pending_challenge():
		_is_challenge = true
		_destination = challenge.pending_name() if challenge.has_method("pending_name") else "Challenge"
		var csize := DEFAULT_MAX
		if challenge.has_method("pending_squad_size"):
			csize = int(challenge.pending_squad_size())
		_max_units = csize if csize > 0 else DEFAULT_MAX
		return

	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run():
		_is_arena = true
		_destination = "Arena Run"
		var size := DEFAULT_MAX
		if arena.has_method("pending_squad_size"):
			size = int(arena.pending_squad_size())
		_max_units = size if size > 0 else DEFAULT_MAX
		return

	# Map launch: MAX = number of player-0 spawn slots on the selected map.
	_is_arena = false
	_max_units = DEFAULT_MAX
	_destination = "Battle"

	var settings := get_node_or_null("/root/GameSettings")
	var map_path := ""
	if settings != null and "selected_map_path" in settings:
		map_path = String(settings.selected_map_path)

	if map_path.is_empty():
		return

	var res := load(map_path) as MapResource
	if res == null:
		return

	if not String(res.map_name).is_empty():
		_destination = String(res.map_name)

	var player0_slots := 0
	for sd in res.unit_spawns:
		if sd is Dictionary and int(sd.get("player_id", 0)) == 0:
			player0_slots += 1

	_max_units = maxi(1, player0_slots) if player0_slots > 0 else DEFAULT_MAX


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var page := VBoxContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("separation", 10)
	page.offset_left = 40.0
	page.offset_right = -40.0
	page.offset_top = 22.0
	page.offset_bottom = -22.0
	add_child(page)

	# --- Header --------------------------------------------------------------
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", _gold)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.text = "SELECT YOUR SQUAD"
	page.add_child(title)

	var subtitle := Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", _cream)
	subtitle.text = _destination
	page.add_child(subtitle)

	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 16)
	_counter_label.add_theme_color_override("font_color", _cream_dim)
	page.add_child(_counter_label)

	# --- Main: roster (left) + details (right) -------------------------------
	var roster := _build_roster()

	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	page.add_child(main)

	main.add_child(_build_roster_pane(roster))
	main.add_child(_build_details_pane())

	# --- Squad slots ---------------------------------------------------------
	_slots_row = HBoxContainer.new()
	_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots_row.add_theme_constant_override("separation", 8)
	page.add_child(_slots_row)

	# --- Inline message ------------------------------------------------------
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 15)
	_message_label.add_theme_color_override("font_color", Color("d87a4a"))
	_message_label.visible = false
	page.add_child(_message_label)

	# --- Actions -------------------------------------------------------------
	page.add_child(_build_actions(roster.is_empty()))

	_update_counter()


## LEFT: the roster card holding the scrollable grid (or an empty-state message).
func _build_roster_pane(roster: Array) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 0.56
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	card.add_child(margin)

	if roster.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", _ink)
		empty_lbl.text = "No characters are available to pick."
		margin.add_child(empty_lbl)
		return card

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for entry in roster:
		grid.add_child(_make_unit_cell(entry))
	return card


## RIGHT: the details pane, populated on hover / selection by [method _show_details].
func _build_details_pane() -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _panel_box(_brown_dk.lerp(_ink, 0.4)))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 0.44
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	# Prompt shown until a unit is hovered / picked.
	_detail_hint = Label.new()
	_detail_hint.text = "Hover a unit to see its stats, ability, and moves."
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_hint.add_theme_font_size_override("font_size", 16)
	_detail_hint.add_theme_color_override("font_color", _cream_dim)
	col.add_child(_detail_hint)

	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 26)
	_detail_name.add_theme_color_override("font_color", _cream)
	col.add_child(_detail_name)

	# Element chip: a small colored pill with dark-ink text.
	var chip_wrap := HBoxContainer.new()
	_detail_chip_panel = PanelContainer.new()
	_detail_chip_panel.add_theme_stylebox_override("panel", _pill_box(_amber))
	_detail_chip_label = Label.new()
	_detail_chip_label.add_theme_font_size_override("font_size", 14)
	_detail_chip_label.add_theme_color_override("font_color", _ink)
	_detail_chip_panel.add_child(_detail_chip_label)
	chip_wrap.add_child(_detail_chip_panel)
	col.add_child(chip_wrap)

	_detail_stats = Label.new()
	_detail_stats.add_theme_font_size_override("font_size", 16)
	_detail_stats.add_theme_color_override("font_color", _amber_lite)
	col.add_child(_detail_stats)

	col.add_child(_detail_separator())

	var ability_head := Label.new()
	ability_head.text = "ABILITY"
	ability_head.add_theme_font_size_override("font_size", 14)
	ability_head.add_theme_color_override("font_color", _gold)
	col.add_child(ability_head)

	_detail_ability_box = VBoxContainer.new()
	_detail_ability_box.add_theme_constant_override("separation", 2)
	col.add_child(_detail_ability_box)

	col.add_child(_detail_separator())

	var moves_head := Label.new()
	moves_head.text = "MOVES"
	moves_head.add_theme_font_size_override("font_size", 14)
	moves_head.add_theme_color_override("font_color", _gold)
	col.add_child(moves_head)

	_detail_moves_box = VBoxContainer.new()
	_detail_moves_box.add_theme_constant_override("separation", 6)
	col.add_child(_detail_moves_box)

	# Hidden until a unit is shown.
	_set_details_visible(false)
	return card


func _detail_separator() -> HSeparator:
	var sep := HSeparator.new()
	var box := StyleBoxFlat.new()
	box.bg_color = _brown.darkened(0.1)
	box.content_margin_top = 1.0
	box.content_margin_bottom = 1.0
	sep.add_theme_stylebox_override("separator", box)
	return sep


## Assemble the sorted, filtered pickable roster. Each entry is a small Dictionary
## { id, name, element }. Also caches the CharacterResource by id for the details pane.
func _build_roster() -> Array:
	var entries: Array = []
	var ids: Array = CharacterLibrary.all_ids()
	for id in ids:
		var chr: CharacterResource = CharacterLibrary.get_character(id)
		if chr == null:
			continue
		if chr.is_boss:
			continue
		var id_str := String(chr.character_id)
		if id_str in EXCLUDED_IDS:
			continue
		_char_by_id[id_str] = chr
		entries.append({
			"id": id_str,
			"name": chr.display_name,
			"element": _element_label(chr.element),
		})
	entries.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return entries


## A clickable unit cell: an amber toggle button with the display name and, dimmer, the
## element. Clicking toggles membership; hovering shows the unit in the details pane.
func _make_unit_cell(entry: Dictionary) -> Control:
	var id_str := String(entry["id"])

	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0.0, 62.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	_style_choice_button(btn)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", _cream)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = String(entry["name"])
	col.add_child(name_lbl)

	var el_lbl := Label.new()
	el_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el_lbl.add_theme_font_size_override("font_size", 12)
	el_lbl.add_theme_color_override("font_color", _cream_dim)
	el_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	el_lbl.text = String(entry["element"])
	col.add_child(el_lbl)

	btn.add_child(col)
	btn.pressed.connect(_on_unit_pressed.bind(id_str))
	btn.mouse_entered.connect(_show_details.bind(id_str))
	btn.focus_entered.connect(_show_details.bind(id_str))
	_unit_buttons[id_str] = btn
	_unit_labels[id_str] = [name_lbl, el_lbl]
	return btn


func _build_actions(roster_empty: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(160.0, 48.0)
	_back_btn.add_theme_font_size_override("font_size", 20)
	_back_btn.add_theme_stylebox_override("normal", _button_box(_brown.lerp(_amber, 0.10)))
	_back_btn.add_theme_stylebox_override("hover", _button_box(_brown.lerp(_amber, 0.22)))
	_back_btn.add_theme_stylebox_override("pressed", _button_box(_brown_dk))
	_back_btn.add_theme_color_override("font_color", _cream)
	_back_btn.add_theme_color_override("font_hover_color", _cream)
	_back_btn.pressed.connect(_on_back_pressed)
	row.add_child(_back_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = "TO BATTLE"
	_confirm_btn.custom_minimum_size = Vector2(240.0, 48.0)
	_confirm_btn.add_theme_font_size_override("font_size", 22)
	_confirm_btn.add_theme_stylebox_override("normal", _button_box(_amber_lite))
	_confirm_btn.add_theme_stylebox_override("hover", _button_box(_amber_lite.lightened(0.10)))
	_confirm_btn.add_theme_stylebox_override("pressed", _button_box(_amber_dk))
	_confirm_btn.add_theme_stylebox_override("disabled", _button_box(_amber.darkened(0.24).lerp(_brown, 0.15), _brown_dk))
	_confirm_btn.add_theme_color_override("font_color", _ink)
	_confirm_btn.add_theme_color_override("font_hover_color", _brown_dk)
	_confirm_btn.add_theme_color_override("font_disabled_color", Color("5c4020"))
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	_confirm_btn.visible = not roster_empty
	row.add_child(_confirm_btn)

	return row


# --- Details pane -----------------------------------------------------------

func _set_details_visible(shown: bool) -> void:
	if _detail_hint != null:
		_detail_hint.visible = not shown
	for node in [_detail_name, _detail_chip_panel, _detail_stats, _detail_ability_box, _detail_moves_box]:
		if node != null:
			(node as CanvasItem).visible = shown


## Populate the details pane for [param id_str]; empty string shows the prompt state.
func _show_details(id_str: String) -> void:
	if id_str.is_empty() or not _char_by_id.has(id_str):
		_set_details_visible(false)
		return
	var chr: CharacterResource = _char_by_id[id_str]
	if chr == null:
		_set_details_visible(false)
		return
	_set_details_visible(true)

	_detail_name.text = chr.display_name

	var el := _element_label(chr.element)
	_detail_chip_label.text = el
	_detail_chip_panel.add_theme_stylebox_override("panel", _pill_box(_element_color(chr.element)))

	_detail_stats.text = "HP %d    ATK %d    DEF %d    SPD %d" % [
		chr.base_health, chr.base_attack, chr.base_defense, chr.base_speed
	]

	# Ability (list all; usually one).
	for child in _detail_ability_box.get_children():
		child.queue_free()
	if chr.ability_count() == 0:
		_detail_ability_box.add_child(_detail_body_label("None", _cream_dim, true))
	else:
		for ab in chr.abilities:
			if ab == null:
				continue
			_detail_ability_box.add_child(_detail_title_label(ab.display_name))
			if not String(ab.description).is_empty():
				_detail_ability_box.add_child(_detail_body_label(ab.description, _cream_dim))

	# Moves (name colored by element + description).
	for child in _detail_moves_box.get_children():
		child.queue_free()
	if chr.move_count() == 0:
		_detail_moves_box.add_child(_detail_body_label("No moves.", _cream_dim, true))
	else:
		for i in range(chr.move_count()):
			var mv: MoveResource = chr.get_move(i)
			if mv == null:
				continue
			var name_lbl := _detail_title_label(mv.display_name)
			name_lbl.add_theme_color_override("font_color", _element_color(mv.element))
			_detail_moves_box.add_child(name_lbl)
			if not String(mv.description).is_empty():
				_detail_moves_box.add_child(_detail_body_label(mv.description, _cream_dim))


func _detail_title_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", _cream)
	return lbl


func _detail_body_label(text: String, color: Color, _italic: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	return lbl


# --- Squad slots ------------------------------------------------------------

## Rebuild the bottom row of slot chips: filled chips show a picked unit (click to unpick),
## empty chips read as "Empty".
func _refresh_slots() -> void:
	if _slots_row == null:
		return
	for child in _slots_row.get_children():
		child.queue_free()
	for i in range(_max_units):
		var filled: bool = i < _chosen_ids.size()
		var chip := Button.new()
		chip.custom_minimum_size = Vector2(120.0, 38.0)
		chip.focus_mode = Control.FOCUS_NONE
		if filled:
			var id_str := String(_chosen_ids[i])
			var chr: CharacterResource = _char_by_id.get(id_str)
			chip.text = chr.display_name if chr != null else id_str
			chip.add_theme_stylebox_override("normal", _button_box(_amber_lite))
			chip.add_theme_stylebox_override("hover", _button_box(_amber))
			chip.add_theme_stylebox_override("pressed", _button_box(_amber_dk))
			chip.add_theme_color_override("font_color", _ink)
			chip.add_theme_color_override("font_hover_color", _ink)
			chip.tooltip_text = "Click to remove %s" % chip.text
			chip.pressed.connect(_on_slot_clicked.bind(id_str))
		else:
			chip.text = "Empty"
			chip.disabled = true
			chip.add_theme_stylebox_override("disabled", _button_box(_brown.lerp(_ink, 0.35), _brown_dk))
			chip.add_theme_color_override("font_disabled_color", _cream_dim)
		_slots_row.add_child(chip)


func _on_slot_clicked(id_str: String) -> void:
	if _chosen_ids.has(id_str):
		_chosen_ids.erase(id_str)
		_hide_message()
		_refresh_selection_visuals()
		_update_counter()
		_refresh_slots()


# --- Selection logic --------------------------------------------------------

func _on_unit_pressed(id_str: String) -> void:
	var btn: Button = _unit_buttons.get(id_str)
	if _chosen_ids.has(id_str):
		_chosen_ids.erase(id_str)
	else:
		# Enforce MAX: ignore a new pick once full, and flash the counter.
		if _chosen_ids.size() >= _max_units:
			if btn != null:
				btn.set_pressed_no_signal(false)
			_flash_limit()
			return
		_chosen_ids.append(id_str)
	_hide_message()
	_show_details(id_str)
	_refresh_selection_visuals()
	_update_counter()
	_refresh_slots()


## Keep every button's toggled state and highlight in sync with _chosen_ids, and grey out
## unselected units when the squad is full.
func _refresh_selection_visuals() -> void:
	var full := _chosen_ids.size() >= _max_units
	for id_str in _unit_buttons.keys():
		var btn: Button = _unit_buttons[id_str]
		if btn == null:
			continue
		var selected: bool = _chosen_ids.has(id_str)
		btn.set_pressed_no_signal(selected)
		btn.modulate = Color(1, 1, 1, 1) if (selected or not full) else Color(1, 1, 1, 0.55)
		var labels: Array = _unit_labels.get(id_str, [])
		if labels.size() == 2:
			labels[0].add_theme_color_override("font_color", _ink if selected else _cream)
			labels[1].add_theme_color_override("font_color", _brown_dk if selected else _cream_dim)

	if _confirm_btn != null:
		_confirm_btn.disabled = _chosen_ids.is_empty()
		if not _chosen_ids.is_empty() and not _confirm_btn.has_focus():
			_confirm_btn.grab_focus()


func _update_counter() -> void:
	if _counter_label == null:
		return
	_counter_label.text = "Choose up to %d units      Selected: %d / %d" % [
		_max_units, _chosen_ids.size(), _max_units
	]


func _flash_limit() -> void:
	_show_message("Squad is full (%d). Deselect a unit to swap." % _max_units)


# --- Confirm / Back ---------------------------------------------------------

func _on_confirm_pressed() -> void:
	if _chosen_ids.is_empty():
		return

	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.has_method("set_selected_squad"):
		settings.set_selected_squad(_chosen_ids)

	# Challenge launch: the map is already staged in GameSettings, so this is a normal
	# map -> GameWorld start. Tell the controller the pick is locked in (so nothing else
	# is misread as this challenge) and change scene below.
	if _is_challenge:
		var challenge := get_node_or_null("/root/ChallengeController")
		if challenge != null and challenge.has_method("notify_squad_confirmed"):
			challenge.notify_squad_confirmed()
		get_tree().change_scene_to_file(GAME_WORLD_SCENE)
		return

	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run():
		# Arena: begin_pending_run changes to the GameWorld scene itself -- do not
		# change scene here.
		arena.begin_pending_run(_chosen_ids)
		return

	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


func _on_back_pressed() -> void:
	# Challenge launch: drop the staged run (so nothing records a stray result) and return
	# to the challenge browser.
	if _is_challenge:
		var challenge := get_node_or_null("/root/ChallengeController")
		if challenge != null and challenge.has_method("cancel"):
			challenge.cancel()
		get_tree().change_scene_to_file(CHALLENGE_BROWSE_SCENE)
		return

	var arena := get_node_or_null("/root/ArenaController")
	if _is_arena and arena != null:
		if arena.has_method("abort_run"):
			arena.abort_run()
		MatchSetup.requested_mode = MatchConfigPanel.MODE_ARENA
		get_tree().change_scene_to_file(MATCH_SETUP_SCENE)
		return
	# Map launch: return to Match Setup in whatever map variant it was (skirmish / local),
	# which the static requested_mode still holds.
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


# --- Keyboard ---------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if event is InputEventKey:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_ENTER, KEY_KP_ENTER:
				if _confirm_btn != null and not _confirm_btn.disabled:
					_on_confirm_pressed()


# --- Messages ---------------------------------------------------------------

func _show_message(text: String) -> void:
	if _message_label == null:
		return
	_message_label.text = text
	_message_label.visible = true


func _hide_message() -> void:
	if _message_label != null:
		_message_label.visible = false


# --- Helpers ----------------------------------------------------------------

## Capitalized element name for display; empty element reads as "Neutral".
func _element_label(element: StringName) -> String:
	var s := String(element)
	if s.is_empty():
		return "Neutral"
	return s.capitalize()


## Element chip color via the shared palette; neutral / unknown falls back to amber.
func _element_color(element: StringName) -> Color:
	var s := String(element)
	if s.is_empty():
		return _amber
	return ConquestTheme.element_color(s)


# --- Background -------------------------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = _bg_top
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var glow := ColorRect.new()
	glow.color = Color(_amber.r, _amber.g, _amber.b, 0.10)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.anchor_top = 0.45
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var vignette := ColorRect.new()
	vignette.color = Color(_bg_bottom.r, _bg_bottom.g, _bg_bottom.b, 0.55)
	vignette.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	vignette.anchor_top = 0.6
	vignette.offset_top = 0.0
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)


# --- Styleboxes -------------------------------------------------------------

func _card_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _amber
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(3)
	sb.border_color = _brown
	sb.set_content_margin_all(0.0)
	sb.shadow_color = Color(0, 0, 0, 0.42)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	sb.anti_aliasing = true
	return sb


## A darker recessed panel (used behind the details pane so its cream text reads well).
func _panel_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(2)
	sb.border_color = _brown
	sb.set_content_margin_all(0.0)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	return sb


func _button_box(fill: Color, border: Color = Color(0.35, 0.23, 0.12, 1.0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb


func _pill_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(8)
	sb.set_border_width_all(2)
	sb.border_color = _brown_dk
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 5.0
	return sb


## Segmented-choice look: unselected reads as a dim inset plate; the selected
## (pressed / toggled-on) state lights up amber so the current pick is obvious.
func _style_choice_button(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _button_box(_brown.lerp(_amber, 0.14)))
	btn.add_theme_stylebox_override("hover", _button_box(_brown.lerp(_amber, 0.28)))
	btn.add_theme_stylebox_override("pressed", _button_box(_amber_lite))
	btn.add_theme_stylebox_override("focus", _button_box(Color(0, 0, 0, 0), _cream))
	btn.add_theme_color_override("font_color", _cream)
	btn.add_theme_color_override("font_hover_color", _cream)
	btn.add_theme_color_override("font_pressed_color", _ink)


# --- Palette load -----------------------------------------------------------

## Pull the warm colours from ConquestTheme (a verified class_name; resolves at
## author time). The hardcoded defaults above stand in if the class is removed.
func _load_palette() -> void:
	_ink = ConquestTheme.INK
	_cream = ConquestTheme.CREAM
	_cream_dim = ConquestTheme.CREAM_DIM
	_amber = ConquestTheme.AMBER
	_amber_lite = ConquestTheme.AMBER_LITE
	_amber_dk = ConquestTheme.AMBER_DK
	_brown = ConquestTheme.BROWN
	_brown_dk = ConquestTheme.BROWN_DK
	_gold = ConquestTheme.EL_HOLY
	_bg_top = ConquestTheme.INK.lerp(Color.BLACK, 0.15)
	_bg_bottom = ConquestTheme.BROWN_DK.darkened(0.35)
