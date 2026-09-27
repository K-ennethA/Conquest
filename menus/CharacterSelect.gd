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
## Layout (built in code with MenuKit / MenuTheme; the .tscn is just a Control root):
##   squad bar (numbered slots + count)  |  unit card grid  |  detail pane for the
##   focused / hovered unit (3D model or emblem, role, description, stat bars).
## Every dependency is null-guarded: a missing autoload, an unreadable map, or an empty
## roster all degrade gracefully (fall back to MAX=4 / "Battle", or offer only BACK).

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const MAP_SELECTION_SCENE := "res://menus/MapSelection.tscn"
const ARENA_SETUP_SCENE := "res://game/arena/ui/ArenaSetupScreen.tscn"
const DEFAULT_MAX := 4
const GRID_COLUMNS := 3

# Characters excluded from the pickable roster regardless of is_boss: the neutral
# beast and the summon-only undead body are never player squad picks.
const EXCLUDED_IDS := ["undead"]

## Stats shown as bars in the detail pane: [key, label].
const STAT_ROWS := [
	["health", "HP"], ["attack", "Attack"], ["defense", "Defense"], ["magic", "Magic"],
	["magic_defense", "Resist"], ["speed", "Speed"], ["movement", "Move"], ["range", "Range"],
]

# --- Mode / selection state -------------------------------------------------
var _is_arena: bool = false
var _max_units: int = DEFAULT_MAX
var _destination: String = "Battle"
# Ordered list of chosen character_id STRINGS (click order preserved).
var _chosen_ids: Array = []
# character_id String -> its toggle Button, so we can refresh visuals / disabled state.
var _unit_buttons: Dictionary = {}
# character_id String -> the order badge Label on its card ("1", "2", ...).
var _order_badges: Dictionary = {}
# character_id String -> roster entry Dictionary.
var _entries: Dictionary = {}
var _stat_max: Dictionary = {}

# --- Live node refs ---------------------------------------------------------
var _counter_label: Label = null
var _message_label: Label = null
var _confirm_btn: Button = null
var _back_btn: Button = null
var _slots: HBoxContainer = null
var _detail_name: Label = null
var _detail_tags: HBoxContainer = null
var _detail_desc: Label = null
var _detail_stats: GridContainer = null
var _detail_moves: Label = null
var _detail_model: UnitPreview3D = null
var _detail_emblem: PanelContainer = null
var _detail_emblem_label: Label = null
var _detail_action_hint: Label = null
var _shown_id: String = ""


func _ready() -> void:
	_resolve_mode()
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

func _crumbs() -> Array:
	if _is_arena:
		return ["Arena"]
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null and settings.game_mode == GameSettings.GameMode.VERSUS:
		return ["Local Versus", _destination]
	return ["Single Player", _destination]


func _build_ui() -> void:
	var page := MenuKit.build_page(self, _crumbs(), "Assemble Your Squad",
		"Choose up to %d unit%s for %s. Selected units deploy in the order you pick them." % [
			_max_units, "" if _max_units == 1 else "s", _destination])

	var roster := _build_roster()

	# --- Squad bar -----------------------------------------------------------
	var bar := HBoxContainer.new()
	bar.name = "SquadBar"
	bar.add_theme_constant_override("separation", MenuTheme.SP_M)
	page.body.add_child(bar)
	var bar_label := MenuKit.section("Squad")
	bar_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(bar_label)
	_slots = HBoxContainer.new()
	_slots.add_theme_constant_override("separation", MenuTheme.SP_S)
	bar.add_child(_slots)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_counter_label = MenuKit.label("", &"HeadingLabel")
	_counter_label.name = "Counter"
	bar.add_child(_counter_label)

	# --- Grid + detail ---------------------------------------------------------
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", MenuTheme.SP_XL)
	page.body.add_child(row)

	if roster.is_empty():
		# Degrade gracefully: no pickable characters -> message, BACK only.
		var empty_card := MenuKit.card()
		empty_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(empty_card)
		var empty_lbl := MenuKit.label("No characters are available to pick.", &"HeadingLabel")
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_card.add_child(empty_lbl)
	else:
		var scroll := ScrollContainer.new()
		scroll.name = "RosterScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_stretch_ratio = 2.3
		scroll.follow_focus = true
		row.add_child(scroll)
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["left", "top", "bottom", "right"]:
			pad.add_theme_constant_override("margin_" + side, 12 if side != "right" else 18)
		scroll.add_child(pad)
		var grid := GridContainer.new()
		grid.name = "RosterGrid"
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override("h_separation", MenuTheme.SP_M)
		grid.add_theme_constant_override("v_separation", MenuTheme.SP_M)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pad.add_child(grid)
		for entry in roster:
			grid.add_child(_make_unit_cell(entry))
		row.add_child(_build_detail_pane())

	# --- Inline message (limit-reached flash / guards) ----------------------
	_message_label = MenuKit.label("", &"")
	_message_label.name = "Message"
	_message_label.visible = false
	page.hints.add_child(_message_label)

	# --- Actions -------------------------------------------------------------
	_back_btn = MenuKit.button("Back", MenuKit.GHOST, 140)
	_back_btn.name = "BackButton"
	_back_btn.pressed.connect(_on_back_pressed)
	page.actions.add_child(_back_btn)
	_confirm_btn = MenuKit.button("Start Run  >" if _is_arena else "To Battle  >", MenuKit.PRIMARY, 240, 54)
	_confirm_btn.name = "ConfirmButton"
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	# With no pickable roster there is nothing to confirm; hide it, offer only BACK.
	_confirm_btn.visible = not roster.is_empty()
	page.actions.add_child(_confirm_btn)
	MenuKit.add_standard_hints(page.hints, "Add / remove")
	page.hints.move_child(_message_label, page.hints.get_child_count() - 1)

	_update_counter()
	if not roster.is_empty():
		var first: Button = _unit_buttons[String(roster[0]["id"])]
		MenuNav.focus_deferred(first)
		_show_detail(String(roster[0]["id"]))
	else:
		MenuNav.focus_deferred(_back_btn)


func _build_detail_pane() -> Control:
	var card := MenuKit.card(&"CrestCard")
	card.name = "UnitDetail"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(340, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", MenuTheme.SP_S)
	card.add_child(v)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", MenuTheme.SP_L)
	v.add_child(top)
	var art := Control.new()
	art.custom_minimum_size = Vector2(110, 110)
	top.add_child(art)
	_detail_emblem = _emblem("?", MenuTheme.GOLD, 96)
	_detail_emblem.position = Vector2(14, 7)
	art.add_child(_detail_emblem)
	_detail_emblem_label = _detail_emblem.get_child(0) as Label
	_detail_model = UnitPreview3D.new()
	_detail_model.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(_detail_model)

	var id_col := VBoxContainer.new()
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.alignment = BoxContainer.ALIGNMENT_CENTER
	id_col.add_theme_constant_override("separation", 6)
	top.add_child(id_col)
	_detail_name = MenuKit.label("", &"HeadingLabel")
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_col.add_child(_detail_name)
	_detail_tags = HBoxContainer.new()
	_detail_tags.add_theme_constant_override("separation", 6)
	id_col.add_child(_detail_tags)
	_detail_action_hint = MenuKit.label("", &"MutedLabel")
	id_col.add_child(_detail_action_hint)

	_detail_desc = MenuKit.label("", &"DimLabel", true)
	_detail_desc.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	_detail_desc.max_lines_visible = 3
	_detail_desc.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_detail_desc)

	_detail_stats = GridContainer.new()
	_detail_stats.columns = 6
	_detail_stats.add_theme_constant_override("h_separation", MenuTheme.SP_M)
	_detail_stats.add_theme_constant_override("v_separation", 5)
	v.add_child(_detail_stats)

	_detail_moves = MenuKit.label("", &"MutedLabel", true)
	v.add_child(_detail_moves)
	return card


## Assemble the sorted, filtered pickable roster. Each entry is a small Dictionary
## { id, name, element, role, stats, chr }.
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
		var stats := {
			"health": chr.base_health, "attack": chr.base_attack, "defense": chr.base_defense,
			"magic": chr.base_magic, "magic_defense": chr.base_magic_defense,
			"speed": chr.base_speed, "movement": chr.base_movement, "range": chr.attack_range,
		}
		for k in stats:
			_stat_max[k] = maxi(int(_stat_max.get(k, 1)), int(stats[k]))
		var entry := {
			"id": id_str,
			"name": chr.display_name,
			"element": _element_label(chr.element),
			"role": _role_for(chr),
			"stats": stats,
			"chr": chr,
		}
		entries.append(entry)
		_entries[id_str] = entry
	entries.sort_custom(func(a, b): return String(a["name"]).naturalnocasecmp_to(String(b["name"])) < 0)
	return entries


## A unit card: element emblem, name, element / role line, key stats, and an order
## badge once picked. Pressing toggles membership in the chosen squad; focusing or
## hovering it shows the unit in the detail pane.
func _make_unit_cell(entry: Dictionary) -> Control:
	var id_str := String(entry["id"])
	var parts := MenuKit.option_card(Vector2(236, 112), true)
	var btn: Button = parts["button"]
	btn.name = "Unit_" + id_str
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m: MarginContainer = parts["margin"]
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_bottom", 12)
	var content: VBoxContainer = parts["content"]

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	content.add_child(h)
	var ecol := MenuKit.element_color(String(entry["element"]))
	MenuKit.accent_card(btn, ecol)
	var emblem := _emblem(String(entry["name"]).left(1), ecol, 46)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(emblem)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(text)
	var name_lbl := MenuKit.label(String(entry["name"]), &"SubheadingLabel")
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_lbl)
	var kind := MenuKit.label("%s  ·  %s" % [entry["element"], entry["role"]], &"")
	kind.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	kind.add_theme_color_override("font_color", ecol.lightened(0.35))
	kind.clip_text = true
	text.add_child(kind)
	var st: Dictionary = entry["stats"]
	var line := MenuKit.label("HP %d · ATK %d · SPD %d" % [st["health"], maxi(st["attack"], st["magic"]), st["speed"]], &"DimLabel")
	line.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	line.clip_text = true
	text.add_child(line)

	# Pick-order badge (top-right), shown when the unit is in the squad.
	var order := PanelContainer.new()
	var order_sb := MenuTheme.pill_box(MenuTheme.GOLD, MenuTheme.GOLD_LITE)
	order_sb.sheen = 0.35
	order_sb.content_margin_left = 12
	order_sb.content_margin_right = 12
	order.add_theme_stylebox_override("panel", order_sb)
	order.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	order.offset_left = -50
	order.offset_top = 12
	order.offset_right = -14
	order.offset_bottom = 36
	order.visible = false
	var order_lbl := MenuKit.label("1", &"")
	order_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	order_lbl.add_theme_color_override("font_color", MenuTheme.INK)
	order_lbl.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	order.add_child(order_lbl)
	btn.add_child(order)
	_order_badges[id_str] = order

	MenuKit.ignore_mouse(btn)
	MenuNav.hover_focus(btn)
	btn.focus_entered.connect(_show_detail.bind(id_str))
	btn.pressed.connect(_on_unit_pressed.bind(id_str))
	_unit_buttons[id_str] = btn
	return btn


## The unit's heraldic crest: element-coloured shield, gold rim, Cinzel initial.
func _emblem(letter: String, color: Color, px: float) -> PanelContainer:
	return MenuKit.crest(letter, color, MenuTheme.GOLD_DK, px)


# --- Detail pane -------------------------------------------------------------

func _show_detail(id_str: String) -> void:
	var entry: Dictionary = _entries.get(id_str, {})
	if entry.is_empty() or _detail_name == null:
		return
	_shown_id = id_str
	var chr: CharacterResource = entry["chr"]
	var ecol := MenuKit.element_color(String(entry["element"]))
	_detail_name.text = String(entry["name"])
	for c in _detail_tags.get_children():
		c.queue_free()
	_detail_tags.add_child(MenuKit.badge(String(entry["element"]), ecol))
	_detail_tags.add_child(MenuKit.badge(String(entry["role"]), MenuTheme.TEXT_DIM))
	if chr.movement_kind != CombatTypes.MovementKind.GROUND:
		_detail_tags.add_child(MenuKit.badge(String(CombatTypes.MovementKind.keys()[chr.movement_kind]).capitalize(), MenuTheme.ACCENT))
	_detail_desc.text = chr.description if chr.description != "" else "No field notes yet."

	var has_model := _detail_model.show_character(chr)
	_detail_model.visible = has_model
	_detail_emblem.visible = not has_model
	MenuKit.set_crest(_detail_emblem, String(entry["name"]), ecol)

	for c in _detail_stats.get_children():
		c.queue_free()
	var st: Dictionary = entry["stats"]
	for row in STAT_ROWS:
		var key: String = row[0]
		var name_l := MenuKit.label(row[1], &"DimLabel")
		name_l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		name_l.custom_minimum_size = Vector2(62, 0)
		_detail_stats.add_child(name_l)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = maxf(float(_stat_max.get(key, 1)), 1.0)
		bar.value = float(st[key])
		bar.custom_minimum_size = Vector2(40, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_detail_stats.add_child(bar)
		var val := MenuKit.label(str(st[key]), &"")
		val.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size = Vector2(30, 0)
		_detail_stats.add_child(val)

	var moves: Array[String] = []
	for mv in chr.moveset:
		if mv != null:
			moves.append(mv.display_name)
	_detail_moves.text = ("Moves: " + ", ".join(moves)) if not moves.is_empty() else ""
	_update_detail_hint()


func _update_detail_hint() -> void:
	if _detail_action_hint == null or _shown_id == "":
		return
	if _chosen_ids.has(_shown_id):
		_detail_action_hint.text = "In squad (#%d)" % (_chosen_ids.find(_shown_id) + 1)
		_detail_action_hint.add_theme_color_override("font_color", MenuTheme.SUCCESS)
	else:
		_detail_action_hint.text = "Not in squad"
		_detail_action_hint.remove_theme_color_override("font_color")


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
	# A full squad: jump to the confirm button so Confirm again starts the battle.
	if _chosen_ids.size() >= _max_units and _confirm_btn != null and _confirm_btn.visible:
		_confirm_btn.grab_focus()


## Keep every card's toggled state, order badge and dimming in sync with _chosen_ids.
func _refresh_selection_visuals() -> void:
	var full := _chosen_ids.size() >= _max_units
	for id_str in _unit_buttons.keys():
		var btn: Button = _unit_buttons[id_str]
		if btn == null:
			continue
		var selected: bool = _chosen_ids.has(id_str)
		btn.set_pressed_no_signal(selected)
		btn.modulate = Color(1, 1, 1, 1) if (selected or not full) else Color(1, 1, 1, 0.5)
		var badge: PanelContainer = _order_badges.get(id_str)
		if badge != null:
			badge.visible = selected
			if selected:
				(badge.get_child(0) as Label).text = str(_chosen_ids.find(id_str) + 1)

	if _confirm_btn != null:
		_confirm_btn.disabled = _chosen_ids.is_empty()
	_rebuild_slots()
	_update_detail_hint()


func _rebuild_slots() -> void:
	if _slots == null:
		return
	for c in _slots.get_children():
		c.queue_free()
	for i in _max_units:
		var filled := i < _chosen_ids.size()
		var text := "Empty"
		var color := MenuTheme.BORDER
		if filled:
			var e: Dictionary = _entries.get(String(_chosen_ids[i]), {})
			text = "%d  %s" % [i + 1, e.get("name", _chosen_ids[i])]
			color = MenuKit.element_color(String(e.get("element", "")))
		var slot := PanelContainer.new()
		var sb := MenuTheme.pill_box(Color(color, 0.2) if filled else Color(0, 0, 0, 0.25),
			color if filled else MenuTheme.BORDER)
		sb.corner = 14.0
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		if filled:
			sb.bg_color_end = Color(color.darkened(0.4), 0.25)
		slot.add_theme_stylebox_override("panel", sb)
		slot.custom_minimum_size = Vector2(150, 0)
		var l := MenuKit.label(text, &"" if filled else &"MutedLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		slot.add_child(l)
		_slots.add_child(slot)


func _update_counter() -> void:
	if _counter_label == null:
		return
	_counter_label.text = "%d / %d" % [_chosen_ids.size(), _max_units]
	_counter_label.add_theme_color_override("font_color",
		MenuTheme.GOLD_LITE if _chosen_ids.size() >= _max_units else MenuTheme.CREAM)


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

	MenuNav.change_scene(self, GAME_WORLD_SCENE)


func _on_back_pressed() -> void:
	var arena := get_node_or_null("/root/ArenaController")
	if _is_arena and arena != null:
		if arena.has_method("abort_run"):
			arena.abort_run()
		MenuNav.change_scene(self, ARENA_SETUP_SCENE)
		return
	MenuNav.change_scene(self, MAP_SELECTION_SCENE)


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


# --- Messages ---------------------------------------------------------------

func _show_message(text: String) -> void:
	if _message_label == null:
		return
	MenuKit.set_status(_message_label, text, "warn")
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


## A one-word battlefield role derived from base stats (display only).
func _role_for(chr: CharacterResource) -> String:
	if chr.attack_range >= 2:
		return "Caster" if chr.base_magic > chr.base_attack else "Ranged"
	if chr.base_magic > chr.base_attack:
		return "Caster"
	if chr.base_defense >= maxi(chr.base_attack, chr.base_speed):
		return "Defender"
	if chr.base_speed >= chr.base_attack:
		return "Skirmisher"
	return "Striker"
