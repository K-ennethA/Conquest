extends CanvasLayer
class_name DuelHUD

## The duel HUD v1 (docs/design/DUEL_BATTLE.md §6.2), grove look at a 1280x720 base:
##   top-left     foe card ([DuelUnitCard])
##   top-centre   round ribbon, turn-order strip, weather chip
##   top-right    Log toggle + the BattleLog drawer
##   bottom       command panel: the 2x2 move grid ([DuelMoveRow], live forecast chips)
##                + Party / Items / Flee / Info; collapses to "Foe is thinking..." off-turn
##   above it     narration ribbon (left) and the player card (right)
##   centre       intro ribbon, results card
##
## Pure presentation: it never touches game state. The stage asks it for a slot
## ([signal slot_chosen]) and applies the command itself.
##
## Input: move rows are focusable buttons (keyboard / gamepad via focus, mouse / touch by
## click, each row >= 64 px tall); 1-4 pick a slot directly; Info (the unit_info action)
## toggles the focused move's details; L toggles the log.

signal slot_chosen(slot: int)
signal rematch_requested
signal setup_requested
signal menu_requested
## Story duels: the results card's Continue (the stage then reports to StoryController).
signal continue_requested

## [signal slot_chosen]'s value for the Flee button (never a move slot).
const FLEE_SLOT := -2

const MARGIN := 16.0
const PANEL_H := 226.0
const RIGHT_COL_W := 184.0
const LAYER := 20

var battle: DuelBattle = null
var foe_card: DuelUnitCard
var player_card: DuelUnitCard
var rows: Array[DuelMoveRow] = []

var _root: Control
var _panel: PanelContainer
var _grid: GridContainer
var _detail: Label
var _waiting: Label
var _struggle: Button
var _side_buttons: Dictionary = {}
var _round_ribbon: PanelContainer
var _order: HBoxContainer
var _narration: PanelContainer
var _narration_text: Label
var _intro: PanelContainer
var _results: PanelContainer
var _log_holder: VBoxContainer
var _log: BattleLog
var _actor = null
var _accepting: bool = false


func _ready() -> void:
	layer = LAYER
	name = "DuelHUD"
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	ConquestTheme.apply_to(_root)
	_build_cards()
	_build_top()
	_build_command_panel()
	_build_narration()
	_build_intro()
	_build_log()


# --- Build ---------------------------------------------------------------------------

func _build_cards() -> void:
	foe_card = DuelUnitCard.new(1)
	_root.add_child(foe_card)
	foe_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	foe_card.position = Vector2(MARGIN, MARGIN)

	player_card = DuelUnitCard.new(0)
	_root.add_child(player_card)
	player_card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	player_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	player_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	player_card.offset_right = -MARGIN
	player_card.offset_left = -MARGIN - DuelUnitCard.CARD_WIDTH
	player_card.offset_bottom = -(MARGIN + PANEL_H + 10.0)
	player_card.offset_top = player_card.offset_bottom


func _build_top() -> void:
	var col := VBoxContainer.new()
	col.name = "TopCentre"
	col.set_anchors_preset(Control.PRESET_CENTER_TOP)
	col.grow_horizontal = Control.GROW_DIRECTION_BOTH
	col.offset_top = MARGIN
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(col)
	_round_ribbon = ConquestTheme.title_ribbon("ROUND 1", ConquestTheme.GOLD_DK, ConquestTheme.FS_BODY)
	_round_ribbon.custom_minimum_size = Vector2(190, 0)
	_round_ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_round_ribbon)
	_order = HBoxContainer.new()
	_order.name = "TurnOrder"
	_order.alignment = BoxContainer.ALIGNMENT_CENTER
	_order.add_theme_constant_override("separation", 6)
	_order.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_order)
	var weather := WeatherChip.new()
	col.add_child(weather)


func _build_command_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "CommandPanel"
	ConquestTheme.keep_style(_panel)
	var sb := ConquestTheme.panel_box(0.95)
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = MARGIN
	_panel.offset_right = -MARGIN
	_panel.offset_bottom = -MARGIN
	_panel.offset_top = -(MARGIN + PANEL_H)
	_root.add_child(_panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_panel.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_grid = GridContainer.new()
	_grid.name = "MoveGrid"
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 8)
	left.add_child(_grid)
	for slot in 4:
		var r := DuelMoveRow.new(slot)
		_grid.add_child(r)
		r.pressed.connect(_on_row_pressed.bind(slot))
		r.focus_entered.connect(_on_row_focused.bind(slot))
		r.mouse_entered.connect(_on_row_focused.bind(slot))
		rows.append(r)
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 10)
	left.add_child(detail_row)
	_detail = Label.new()
	_detail.name = "Detail"
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_detail.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_detail.clip_text = true
	_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_row.add_child(_detail)
	_struggle = Button.new()
	_struggle.name = "Struggle"
	_struggle.text = "Desperate Strike"
	_struggle.visible = false
	_struggle.custom_minimum_size = Vector2(0, 30)
	_struggle.pressed.connect(func() -> void: _choose(DuelCharacter.STRUGGLE_SLOT))
	detail_row.add_child(_struggle)
	_waiting = Label.new()
	_waiting.name = "Waiting"
	_waiting.visible = false
	_waiting.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_waiting.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_waiting.add_theme_font_override("font", MenuTheme.heading_font(2))
	_waiting.add_theme_font_size_override("font_size", ConquestTheme.FS_HUD_TITLE)
	_waiting.add_theme_color_override("font_color", ConquestTheme.GOLD_LITE)
	left.add_child(_waiting)

	var right := VBoxContainer.new()
	right.name = "SideColumn"
	right.custom_minimum_size = Vector2(RIGHT_COL_W, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	for spec in [["Party", "Switching arrives with party duels (M2)."],
			["Items", "Battle items are not in the game yet."],
			["Flee", "Run from a wild encounter (it may fail and cost the turn)."],
			["Info", "Details for the focused move (%s)." % ConquestTheme.action_glyph(InputActions.UNIT_INFO)]]:
		var b := Button.new()
		b.name = String(spec[0]) + "Button"
		b.text = String(spec[0])
		b.theme_type_variation = &"HudCommand"
		b.custom_minimum_size = Vector2(0, 36)
		b.tooltip_text = String(spec[1])
		b.disabled = spec[0] != "Info"
		right.add_child(b)
		_side_buttons[spec[0]] = b
	(_side_buttons["Info"] as Button).pressed.connect(_toggle_info)
	(_side_buttons["Flee"] as Button).pressed.connect(choose_flee)
	_wire_focus()


func _build_narration() -> void:
	_narration = PanelContainer.new()
	_narration.name = "Narration"
	ConquestTheme.keep_style(_narration)
	_narration.add_theme_stylebox_override("panel", MenuTheme.ribbon_box(ConquestTheme.PANEL_HI, ConquestTheme.GOLD_DK, 14.0))
	_narration.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_narration.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_narration.offset_left = MARGIN
	_narration.offset_right = MARGIN + 720.0
	_narration.offset_bottom = -(MARGIN + PANEL_H + 12.0)
	_narration.offset_top = _narration.offset_bottom - 40.0
	_narration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narration.visible = false
	_root.add_child(_narration)
	_narration_text = Label.new()
	_narration_text.name = "Text"
	_narration_text.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
	_narration_text.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_narration_text.clip_text = true
	_narration_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_narration.add_child(_narration_text)


func _build_intro() -> void:
	_intro = ConquestTheme.title_ribbon("", ConquestTheme.GOLD, ConquestTheme.FS_HUD_TITLE)
	_intro.name = "IntroRibbon"
	_intro.set_anchors_preset(Control.PRESET_CENTER)
	_intro.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_intro.grow_vertical = Control.GROW_DIRECTION_BOTH
	_intro.custom_minimum_size = Vector2(520, 56)
	_intro.position.y -= 110.0
	_intro.visible = false
	_root.add_child(_intro)


func _build_log() -> void:
	var holder := VBoxContainer.new()
	holder.name = "LogDrawer"
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	holder.offset_right = -MARGIN
	holder.offset_left = -MARGIN - 340.0
	holder.offset_top = MARGIN
	holder.alignment = BoxContainer.ALIGNMENT_BEGIN
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(holder)
	var toggle := Button.new()
	toggle.name = "LogToggle"
	toggle.text = "Log  (L)"
	toggle.theme_type_variation = MenuKit.GHOST
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.pressed.connect(toggle_log)
	holder.add_child(toggle)
	toggle.custom_minimum_size = Vector2(120, 34)
	_log_holder = holder
	_log = BattleLog.new()
	_log.visible = false
	holder.add_child(_log)


func _wire_focus() -> void:
	# 2x2 grid: left/right within a row, up/down between rows; the column wraps to Info.
	for i in rows.size():
		var r := rows[i]
		var right_i := i + 1 if i % 2 == 0 else i - 1
		var down_i := i + 2 if i < 2 else i - 2
		r.focus_neighbor_right = r.get_path_to(rows[right_i])
		r.focus_neighbor_left = r.get_path_to(rows[right_i])
		r.focus_neighbor_bottom = r.get_path_to(rows[down_i])
		r.focus_neighbor_top = r.get_path_to(rows[down_i])


# --- Binding & state -----------------------------------------------------------------

func bind(p_battle: DuelBattle) -> void:
	battle = p_battle
	player_card.bind(battle.unit_of(0))
	foe_card.bind(battle.unit_of(1))
	for r in rows:
		r.bind(battle.unit_of(0), battle.unit_of(1), battle.board)
	refresh()


## Re-read everything (rows, round, order). Cheap; the stage calls it after every action.
func refresh() -> void:
	if battle == null:
		return
	var round_label := _round_ribbon.get_node_or_null("Text") as Label
	if round_label != null:
		round_label.text = "ROUND %d" % maxi(1, battle.round_number())
	var legal: Array[int] = []
	if _actor != null and is_instance_valid(_actor):
		legal = battle.legal_slots(_actor)
	for r in rows:
		r.refresh(_accepting and r.slot in legal)
	_struggle.visible = _accepting and DuelCharacter.STRUGGLE_SLOT in legal
	(_side_buttons["Flee"] as Button).disabled = not (_accepting and battle.can_flee())
	_refresh_order()


func _refresh_order() -> void:
	for c in _order.get_children():
		_order.remove_child(c)
		c.queue_free()
	var order: Array = []
	var ts := battle.turn_system
	var current = battle.current_actor()
	if current != null:
		order.append(current)
	if ts != null:
		for u in ts.get_turn_queue():
			if u != null and is_instance_valid(u) and not (u in order):
				order.append(u)
	var first := true
	for u in order:
		if not first:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
			arrow.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
			_order.add_child(arrow)
		first = false
		var colors: Array = ConquestTheme.unit_portrait_colors(u)
		var crest := ConquestTheme.portrait(u.get_display_name(), colors[0], colors[1], 30.0)
		crest.tooltip_text = "%s · SPD %d" % [u.get_display_name(), int(u.get_stat("speed"))]
		crest.mouse_filter = Control.MOUSE_FILTER_PASS
		_order.add_child(crest)


## The player's turn: show the grid for [param actor] and wait for a pick.
func show_commands(actor) -> void:
	_actor = actor
	_accepting = true
	_grid.visible = true
	_waiting.visible = false
	_detail.visible = true
	refresh()
	var focus_row: DuelMoveRow = null
	for r in rows:
		if r.visible and not r.disabled:
			focus_row = r
			break
	if focus_row != null:
		focus_row.grab_focus()
		_on_row_focused(focus_row.slot)
	elif _struggle.visible:
		_struggle.grab_focus()
		_detail.text = "Nothing is ready -- Desperate Strike is always there."


## Someone else's turn: collapse the grid to a ribbon line.
func show_waiting(text: String) -> void:
	_actor = null
	_accepting = false
	_grid.visible = false
	_detail.visible = false
	_struggle.visible = false
	_waiting.visible = true
	_waiting.text = text
	refresh()


func set_command_panel_visible(on: bool) -> void:
	_panel.visible = on


func narrate(text: String) -> void:
	_narration.visible = text != ""
	_narration_text.text = text


func show_intro(text: String) -> void:
	var l := _intro.get_node_or_null("Text") as Label
	if l != null:
		l.text = text
	_intro.visible = text != ""


func toggle_log() -> void:
	_log.visible = not _log.visible
	if _log.visible:
		_log.set_height_budget(300.0)


func _toggle_info() -> void:
	_detail.visible = true
	var focused := _root.get_viewport().gui_get_focus_owner() if _root.get_viewport() != null else null
	var slot := (focused as DuelMoveRow).slot if focused is DuelMoveRow else 0
	var mv: MoveResource = rows[slot].move() if slot < rows.size() else null
	if mv != null:
		_detail.text = mv.full_description().replace("\n", " -- ")


# --- Results -------------------------------------------------------------------------

## The results card: outcome ribbon, a few numbers, the befriend line, and the way out.
func show_results(result: DuelResult, standalone: bool = true) -> void:
	show_waiting("")
	_panel.visible = false
	_narration.visible = false
	if _results != null:
		_results.queue_free()
	_results = PanelContainer.new()
	_results.name = "Results"
	ConquestTheme.keep_style(_results)
	var sb := MenuTheme.card_box()
	sb.crest = true
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 30
	sb.content_margin_bottom = 22
	_results.add_theme_stylebox_override("panel", sb)
	_results.set_anchors_preset(Control.PRESET_CENTER)
	_results.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_results.grow_vertical = Control.GROW_DIRECTION_BOTH
	_results.custom_minimum_size = Vector2(500, 0)
	_root.add_child(_results)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_results.add_child(col)
	var won := result.player_won()
	var title := "Victory" if won else ("Defeat" if result.outcome == DuelResult.OUTCOME_DEFEAT \
		else ("Got Away" if result.outcome == DuelResult.OUTCOME_FLED else "Duel Ended"))
	var ribbon := ConquestTheme.title_ribbon(title.to_upper(),
		ConquestTheme.GOLD if won else ConquestTheme.DANGER, ConquestTheme.FS_PHASE)
	ribbon.name = "Outcome"
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ribbon.custom_minimum_size = Vector2(260, 0)
	col.add_child(ribbon)
	var rule := GroveRule.new()
	rule.centered = true
	rule.custom_minimum_size = Vector2(0, 12)
	col.add_child(rule)
	var mine: Dictionary = result.stats[0] if result.stats.size() > 0 else {}
	var theirs: Dictionary = result.stats[1] if result.stats.size() > 1 else {}
	for line in [
		"%d rounds · %d actions" % [result.rounds, result.turns],
		"Damage dealt %d · taken %d" % [int(mine.get("damage_dealt", 0)), int(theirs.get("damage_dealt", 0))],
	]:
		var l := Label.new()
		l.text = line
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
		l.add_theme_color_override("font_color", ConquestTheme.CREAM)
		col.add_child(l)
	var join := result.befriend_line()
	if join != "":
		var j := Label.new()
		j.name = "Befriend"
		j.text = join
		j.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		j.add_theme_font_override("font", MenuTheme.heading_font(1))
		j.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
		j.add_theme_color_override("font_color", ConquestTheme.SUCCESS)
		col.add_child(j)
	if not result.growth.is_empty():
		var growth_box := VBoxContainer.new()
		growth_box.name = "GrowthRows"
		growth_box.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(growth_box)
		GrowthGems.fill_result_rows(growth_box, result.growth, ConquestTheme.FS_BODY)
	var seed_line := Label.new()
	seed_line.text = "Seed %d" % result.seed
	seed_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_line.add_theme_font_size_override("font_size", ConquestTheme.FS_CAPTION)
	seed_line.add_theme_color_override("font_color", ConquestTheme.TEXT_MUTED)
	col.add_child(seed_line)
	if standalone:
		var buttons := HBoxContainer.new()
		buttons.alignment = BoxContainer.ALIGNMENT_CENTER
		buttons.add_theme_constant_override("separation", 12)
		col.add_child(buttons)
		var rematch := MenuKit.button("Rematch", MenuKit.PRIMARY, 140)
		rematch.name = "Rematch"
		rematch.pressed.connect(func() -> void: rematch_requested.emit())
		buttons.add_child(rematch)
		var change := MenuKit.button("Change Units", &"", 160)
		change.name = "ChangeUnits"
		change.pressed.connect(func() -> void: setup_requested.emit())
		buttons.add_child(change)
		var menu := MenuKit.button("Menu", MenuKit.GHOST, 110)
		menu.name = "Menu"
		menu.pressed.connect(func() -> void: menu_requested.emit())
		buttons.add_child(menu)
		rematch.call_deferred("grab_focus")
	else:
		# STORY: one way on -- back to the overworld (StoryController applies the result).
		var cont := MenuKit.button("Continue Journey", MenuKit.PRIMARY, 220)
		cont.name = "Continue"
		cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cont.pressed.connect(func() -> void: continue_requested.emit(), CONNECT_ONE_SHOT)
		col.add_child(cont)
		cont.call_deferred("grab_focus")


## The results card's Continue button (story duels), or null.
func continue_button() -> Button:
	if _results == null or not is_instance_valid(_results):
		return null
	return _results.find_child("Continue", true, false) as Button


func results_visible() -> bool:
	return _results != null and is_instance_valid(_results) and _results.visible


# --- Input ---------------------------------------------------------------------------

func _on_row_pressed(slot: int) -> void:
	_choose(slot)


func _choose(slot: int) -> void:
	if not _accepting or battle == null or _actor == null:
		return
	if not (slot in battle.legal_slots(_actor)):
		return
	_accepting = false
	slot_chosen.emit(slot)


## The Flee button: hand the director [constant FLEE_SLOT] (it rolls the escape).
func choose_flee() -> void:
	if not _accepting or battle == null or _actor == null or not battle.can_flee():
		return
	_accepting = false
	slot_chosen.emit(FLEE_SLOT)


func _on_row_focused(slot: int) -> void:
	if slot < 0 or slot >= rows.size():
		return
	var mv := rows[slot].move()
	if mv == null:
		return
	var desc := mv.description if mv.description != "" else mv.full_description()
	_detail.text = "%s -- %s" % [mv.display_name_for(_actor if _actor != null else battle.unit_of(0)), desc.replace("\n", " ")]


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		if event.is_action_pressed(InputActions.UNIT_INFO):
			_toggle_info()
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_L:
		toggle_log()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(InputActions.UNIT_INFO):
		_toggle_info()
		get_viewport().set_input_as_handled()
		return
	if _accepting and key >= KEY_1 and key <= KEY_4:
		var slot := int(key - KEY_1)
		if slot < rows.size() and rows[slot].visible and not rows[slot].disabled:
			get_viewport().set_input_as_handled()
			_choose(slot)
