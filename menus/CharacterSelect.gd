extends Control

## Squad-picker screen shown before a battle, for BOTH map modes (Single Player /
## Versus) and Arena. The player chooses which characters make up their player-0
## squad, up to a mode-derived limit, then confirms into the battle.
##
## Launch paths (both change to THIS scene, then Character Select dispatches):
##   * Map launch    -- MapSelection stages GameSettings.selected_map_path and comes here.
##                      MAX = number of player-0 spawn slots on that map. Confirm loads
##                      GameWorld.tscn itself.
##   * Arena launch   -- ArenaSetupScreen stages a pending run on ArenaController and comes
##                      here. MAX = ArenaController.pending_squad_size(). Confirm calls
##                      begin_pending_run(), which starts the run AND changes scene itself.
##
## The UI is built PROGRAMMATICALLY in _ready (the .tscn is just a Control root) using the
## warm-amber ConquestTheme palette, mirroring ArenaSetupScreen's look and structure. Every
## dependency is null-guarded: a missing autoload, an unreadable map, or an empty roster all
## degrade gracefully (fall back to MAX=4 / "Battle", or offer only BACK).

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MAP_SELECTION_SCENE := "res://menus/MapSelection.tscn"
const ARENA_SETUP_SCENE := "res://game/arena/ui/ArenaSetupScreen.tscn"
const DEFAULT_MAX := 4
const GRID_COLUMNS := 3

# Characters excluded from the pickable roster regardless of is_boss: the neutral
# beast and the summon-only undead body are never player squad picks.
const EXCLUDED_IDS := ["feral_thornbeast", "undead"]

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
var _max_units: int = DEFAULT_MAX
var _destination: String = "Battle"
# Ordered list of chosen character_id STRINGS (click order preserved).
var _chosen_ids: Array = []
# character_id String -> its toggle Button, so we can refresh visuals / disabled state.
var _unit_buttons: Dictionary = {}
# character_id String -> [name_label, element_label], so selection can recolor text
# (cream on the dim unselected plate, dark ink on the lit amber selected plate).
var _unit_labels: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _counter_label: Label = null
var _message_label: Label = null
var _confirm_btn: Button = null
var _back_btn: Button = null


func _ready() -> void:
	_load_palette()
	_resolve_mode()
	_build_background()
	_build_ui()
	_refresh_selection_visuals()


# --- Mode + limit resolution ------------------------------------------------

## Decide whether this is an Arena or Map launch and compute the pick limit MAX.
func _resolve_mode() -> void:
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
	page.add_theme_constant_override("separation", 14)
	# Keep everything inside the 1280x720 window with a comfortable margin.
	page.offset_left = 48.0
	page.offset_right = -48.0
	page.offset_top = 28.0
	page.offset_bottom = -28.0
	add_child(page)

	# --- Header --------------------------------------------------------------
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", _gold)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.text = "SELECT YOUR SQUAD"
	page.add_child(title)

	var subtitle := Label.new()
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", _cream)
	subtitle.text = _destination
	page.add_child(subtitle)

	# --- Counter / limit -----------------------------------------------------
	_counter_label = Label.new()
	_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter_label.add_theme_font_size_override("font_size", 18)
	_counter_label.add_theme_color_override("font_color", _cream_dim)
	page.add_child(_counter_label)

	# --- Roster ---------------------------------------------------------------
	var roster := _build_roster()

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_box())
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	if roster.is_empty():
		# Degrade gracefully: no pickable characters -> message, BACK only.
		var empty_lbl := Label.new()
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", _ink)
		empty_lbl.text = "No characters are available to pick."
		margin.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin.add_child(scroll)

		var grid := GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)

		for entry in roster:
			grid.add_child(_make_unit_cell(entry))

	# --- Inline message (limit-reached flash / guards) ----------------------
	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 16)
	_message_label.add_theme_color_override("font_color", Color("d87a4a"))
	_message_label.visible = false
	page.add_child(_message_label)

	# --- Actions -------------------------------------------------------------
	page.add_child(_build_actions(roster.is_empty()))

	_update_counter()


## Assemble the sorted, filtered pickable roster. Each entry is a small Dictionary
## { id: String, name: String, element: String }.
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
		entries.append({
			"id": id_str,
			"name": chr.display_name,
			"element": _element_label(chr.element),
		})
	entries.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return entries


## A clickable unit cell: an amber toggle Button carrying the display name and, in a
## smaller dim line, the element. Clicking toggles membership in the chosen squad.
func _make_unit_cell(entry: Dictionary) -> Control:
	var id_str := String(entry["id"])

	var btn := Button.new()
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(230.0, 66.0)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.clip_text = true
	_style_choice_button(btn)

	# Two stacked labels (name big, element smaller) laid out over the button;
	# mouse_filter IGNORE so clicks fall through to the button itself.
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", _cream)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = String(entry["name"])
	col.add_child(name_lbl)

	var el_lbl := Label.new()
	el_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	el_lbl.add_theme_font_size_override("font_size", 13)
	el_lbl.add_theme_color_override("font_color", _cream_dim)
	el_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	el_lbl.text = String(entry["element"])
	col.add_child(el_lbl)

	btn.add_child(col)
	btn.pressed.connect(_on_unit_pressed.bind(id_str))
	_unit_buttons[id_str] = btn
	_unit_labels[id_str] = [name_lbl, el_lbl]
	return btn


func _build_actions(roster_empty: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)

	_back_btn = Button.new()
	_back_btn.text = "Back"
	_back_btn.custom_minimum_size = Vector2(160.0, 52.0)
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
	_confirm_btn.custom_minimum_size = Vector2(240.0, 52.0)
	_confirm_btn.add_theme_font_size_override("font_size", 24)
	_confirm_btn.add_theme_stylebox_override("normal", _button_box(_amber_lite))
	_confirm_btn.add_theme_stylebox_override("hover", _button_box(_amber_lite.lightened(0.10)))
	_confirm_btn.add_theme_stylebox_override("pressed", _button_box(_amber_dk))
	_confirm_btn.add_theme_stylebox_override("disabled", _button_box(_amber.darkened(0.24).lerp(_brown, 0.15), _brown_dk))
	_confirm_btn.add_theme_color_override("font_color", _ink)
	_confirm_btn.add_theme_color_override("font_hover_color", _brown_dk)
	_confirm_btn.add_theme_color_override("font_disabled_color", Color("5c4020"))
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	# With no pickable roster there is nothing to confirm; hide it, offer only BACK.
	_confirm_btn.visible = not roster_empty
	row.add_child(_confirm_btn)

	return row


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
	_refresh_selection_visuals()
	_update_counter()


## Keep every button's toggled state and highlight in sync with _chosen_ids, and
## grey out unselected units when the squad is full.
func _refresh_selection_visuals() -> void:
	var full := _chosen_ids.size() >= _max_units
	for id_str in _unit_buttons.keys():
		var btn: Button = _unit_buttons[id_str]
		if btn == null:
			continue
		var selected: bool = _chosen_ids.has(id_str)
		btn.set_pressed_no_signal(selected)
		btn.modulate = Color(1, 1, 1, 1) if (selected or not full) else Color(1, 1, 1, 0.55)
		# Recolor the cell text so it stays readable in either state: dark ink on the
		# lit amber selected plate, cream on the dim unselected plate.
		var labels: Array = _unit_labels.get(id_str, [])
		if labels.size() == 2:
			labels[0].add_theme_color_override("font_color", _ink if selected else _cream)
			labels[1].add_theme_color_override("font_color", _brown_dk if selected else _cream_dim)

	if _confirm_btn != null:
		_confirm_btn.disabled = _chosen_ids.is_empty()
		# Make CONFIRM the default focus once a selection exists (keyboard flow).
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

	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run():
		# Arena: begin_pending_run changes to the GameWorld scene itself -- do not
		# change scene here.
		arena.begin_pending_run(_chosen_ids)
		return

	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


func _on_back_pressed() -> void:
	var arena := get_node_or_null("/root/ArenaController")
	if _is_arena and arena != null:
		if arena.has_method("abort_run"):
			arena.abort_run()
		get_tree().change_scene_to_file(ARENA_SETUP_SCENE)
		return
	get_tree().change_scene_to_file(MAP_SELECTION_SCENE)


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
