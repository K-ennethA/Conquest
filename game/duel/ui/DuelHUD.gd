extends CanvasLayer
class_name DuelHUD

## The duel HUD v1 (docs/design/DUEL_BATTLE.md §6.2), grove look at a 1280x720 base:
##   top-left     foe card ([DuelUnitCard])
##   top-centre   round ribbon, turn-order strip, weather chip
##   top-right    Log toggle + the BattleLog drawer
##   bottom       command panel: the 2x2 move grid ([DuelMoveRow], live forecast chips)
##                + Party / Items / Flee / Info; collapses to "Foe is thinking..." off-turn.
##                Items swaps the grid for the ITEM PICKER (the side's battle consumables; an
##                item that would be wasted is shown disabled with the reason) -- picking one
##                hands the stage [constant ITEM_SLOT] with [member chosen_item_id]; Back / Esc
##                returns to the moves.
##   above it     narration ribbon (left) and the player card (right)
##   centre       intro ribbon, results card
##
## PARTY DUELS (a [DuelFormat] with a bench):
##   cards        each card carries its side's team pips ([DuelPartyStrip]: HP, fainted crosses,
##                the fielded member ringed gold) and rebinds to whoever takes the station
##   Party        (enabled when the format allows switching and a healthy member waits) swaps the
##                grid for the PARTY PICKER -- one row per member, fainted / fielded ones
##                disabled; picking hands the stage [constant SWITCH_SLOT] with
##                [member chosen_member] (it costs the turn); Back / Esc returns to the moves
##   replacement  after a faint, [method show_replacement] opens the same picker with no way
##                back: the owner MUST choose ([signal replacement_chosen])
##   team preview [method show_team_preview]: both teams, shown during the intro
##
## Pure presentation: it never touches game state. The stage asks it for a slot
## ([signal slot_chosen]) and applies the command itself.
##
## Input: move rows are focusable buttons (keyboard / gamepad via focus, mouse / touch by
## click, each row >= 64 px tall); 1-4 pick a slot directly (1-6 pick a member while a picker
## is up); Info (the unit_info action) toggles the focused move's details; L toggles the log.

signal slot_chosen(slot: int)
## PARTY DUELS: the KO replacement picker's choice (a team index of [member replacement_side]).
signal replacement_chosen(index: int)
signal rematch_requested
signal setup_requested
signal menu_requested
## Story duels: the results card's Continue (the stage then reports to StoryController).
signal continue_requested

## [signal slot_chosen]'s value for the Flee button (never a move slot).
const FLEE_SLOT := -2
## [signal slot_chosen]'s value for an item pick ([member chosen_item_id] says which).
const ITEM_SLOT := -3
## [signal slot_chosen]'s value for a Party switch ([member chosen_member] says who comes in).
const SWITCH_SLOT := -4

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
## The item picker (replaces the move grid while open) and its rows.
var _items_box: VBoxContainer = null
var _items_grid: GridContainer = null
## The item the last [constant ITEM_SLOT] pick chose.
var chosen_item_id: String = ""
## The party picker (switch / KO replacement; replaces the move grid while open) and its rows.
var _party_box: VBoxContainer = null
var _party_grid: GridContainer = null
var _party_caption: Label = null
var _party_back: Button = null
## "switch" (the Party action, Back allowed) or "replace" (a KO replacement, no way back).
var _party_mode: String = ""
## The team index the last [constant SWITCH_SLOT] pick chose.
var chosen_member: int = -1
## The side whose KO replacement the picker is choosing (-1 = none).
var replacement_side: int = -1
var _team_preview: PanelContainer = null

# --- VERSUS (online / hot-seat) -----------------------------------------------------------
## The side this screen belongs to: its combatant gets the player card (bottom-right), the
## other side the foe card, and the results read Victory / Defeat for it. 0 everywhere except
## an online duel seated in slot 1. Set before [method bind].
var perspective_side: int = 0
## Hot-seat: the two sides' names ("Player 1", "Player 2"). When set, the results name the
## winner instead of Victory / Defeat (nobody at a shared screen "lost" to themselves).
var side_names: Array[String] = []
## Online: the results card offers only the way out (no rematch / change units).
var results_menu_only: bool = false
## The unit the move rows currently show (rebound when another side's human takes the turn).
var _rows_unit = null


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
	_build_item_picker(left)
	_build_party_picker(left)

	var right := VBoxContainer.new()
	right.name = "SideColumn"
	right.custom_minimum_size = Vector2(RIGHT_COL_W, 0)
	right.add_theme_constant_override("separation", 6)
	row.add_child(right)
	for spec in [["Party", "Switch in a partner from your team (it costs the turn)."],
			["Items", "Use a battle item from your bag (it costs the turn)."],
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
	(_side_buttons["Items"] as Button).pressed.connect(open_items)
	(_side_buttons["Party"] as Button).pressed.connect(open_party)
	_wire_focus()


## The party picker: a caption, a 2-column grid of member rows, and Back (switch mode only).
func _build_party_picker(left: VBoxContainer) -> void:
	_party_box = VBoxContainer.new()
	_party_box.name = "PartyPicker"
	_party_box.visible = false
	_party_box.add_theme_constant_override("separation", 6)
	left.add_child(_party_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_party_box.add_child(head)
	_party_caption = Label.new()
	_party_caption.name = "Caption"
	_party_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_caption.add_theme_font_override("font", MenuTheme.heading_font(1))
	_party_caption.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	_party_caption.add_theme_color_override("font_color", ConquestTheme.GOLD_LITE)
	head.add_child(_party_caption)
	_party_back = Button.new()
	_party_back.name = "PartyBack"
	_party_back.text = "Back"
	_party_back.theme_type_variation = MenuKit.GHOST
	_party_back.custom_minimum_size = Vector2(96, 30)
	_party_back.pressed.connect(close_party)
	head.add_child(_party_back)
	_party_grid = GridContainer.new()
	_party_grid.name = "PartyGrid"
	_party_grid.columns = 2
	_party_grid.add_theme_constant_override("h_separation", 10)
	_party_grid.add_theme_constant_override("v_separation", 6)
	_party_box.add_child(_party_grid)


## The item picker: a caption, a 2-column grid of item rows, and Back. Hidden until Items.
func _build_item_picker(left: VBoxContainer) -> void:
	_items_box = VBoxContainer.new()
	_items_box.name = "ItemPicker"
	_items_box.visible = false
	_items_box.add_theme_constant_override("separation", 6)
	left.add_child(_items_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_items_box.add_child(head)
	var cap := Label.new()
	cap.name = "Caption"
	cap.text = "ITEMS  ·  using one costs the turn"
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_theme_font_override("font", MenuTheme.heading_font(1))
	cap.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	cap.add_theme_color_override("font_color", ConquestTheme.GOLD_LITE)
	head.add_child(cap)
	var back := Button.new()
	back.name = "ItemsBack"
	back.text = "Back"
	back.theme_type_variation = MenuKit.GHOST
	back.custom_minimum_size = Vector2(96, 30)
	back.pressed.connect(close_items)
	head.add_child(back)
	_items_grid = GridContainer.new()
	_items_grid.name = "ItemGrid"
	_items_grid.columns = 2
	_items_grid.add_theme_constant_override("h_separation", 10)
	_items_grid.add_theme_constant_override("v_separation", 6)
	_items_box.add_child(_items_grid)


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
	var me := clampi(perspective_side, 0, 1)
	player_card.bind(battle.unit_of(me))
	foe_card.bind(battle.unit_of(1 - me))
	_bind_rows(battle.unit_of(me))
	if not battle.combatant_entered.is_connected(_on_combatant_entered):
		battle.combatant_entered.connect(_on_combatant_entered)
	refresh()


## The card of [param side] (this screen's side gets the player card).
func card_for(side: int) -> DuelUnitCard:
	return player_card if side == clampi(perspective_side, 0, 1) else foe_card


## A team member took the station: its side's card follows it.
func _on_combatant_entered(side: int, unit, _previous) -> void:
	card_for(side).bind(unit)
	# The move rows follow their side's fielded unit, and re-read their forecasts against a new foe.
	var rows_side := clampi(perspective_side, 0, 1)
	if _rows_unit != null and is_instance_valid(_rows_unit) and battle.side_of(_rows_unit) >= 0:
		rows_side = battle.side_of(_rows_unit)
	if battle.unit_of(rows_side) != null:
		_bind_rows(battle.unit_of(rows_side))
	refresh()


## Point the move rows at [param unit] (and its foe).
func _bind_rows(unit) -> void:
	_rows_unit = unit
	for r in rows:
		r.bind(unit, battle.foe_of(unit) if battle != null else null, battle.board if battle != null else null)


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
	(_side_buttons["Items"] as Button).disabled = not (_accepting and battle.can_use_items())
	(_side_buttons["Party"] as Button).disabled = not (_accepting and _actor != null and battle.can_switch(_actor))
	for side in 2:
		card_for(side).set_team(battle.team_view(side))
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
	if actor != _rows_unit and battle != null:
		_bind_rows(actor)  # hot-seat: the other human's turn / a switched-in partner
	_items_box.visible = false
	_party_box.visible = false
	_party_mode = ""
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
	_items_box.visible = false
	_party_box.visible = false
	_party_mode = ""
	replacement_side = -1
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
	var me := clampi(perspective_side, 0, 1)
	var won := result.player_won() if me == 0 else result.winner_side == 1
	var title := "Victory" if won else ("Defeat" if result.outcome == DuelResult.OUTCOME_DEFEAT \
		else ("Got Away" if result.outcome == DuelResult.OUTCOME_FLED else "Duel Ended"))
	if me == 1 and not won and result.winner_side == 0:
		title = "Defeat"
	if side_names.size() == 2 and result.winner_side >= 0:
		# Hot-seat: name the winner; the ribbon stays gold (somebody at this screen won).
		title = "%s wins" % side_names[result.winner_side]
		won = true
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
	var mine: Dictionary = result.stats[me] if result.stats.size() > me else {}
	var theirs: Dictionary = result.stats[1 - me] if result.stats.size() > 1 - me else {}
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
	if results_menu_only:
		# ONLINE: the match is over and the session is gone -- one way out.
		var leave := MenuKit.button("Back to Online", MenuKit.PRIMARY, 220)
		leave.name = "Menu"
		leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		leave.pressed.connect(func() -> void: menu_requested.emit(), CONNECT_ONE_SHOT)
		col.add_child(leave)
		leave.call_deferred("grab_focus")
	elif standalone:
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


## The Items button: swap the move grid for the item picker (the acting unit's options).
func open_items() -> void:
	if not _accepting or battle == null or _actor == null or not battle.can_use_items():
		return
	for c in _items_grid.get_children():
		_items_grid.remove_child(c)
		c.queue_free()
	var who: String = _actor.get_display_name() if _actor.has_method("get_display_name") else ""
	var first: Button = null
	for opt in battle.item_options(_actor):
		var item: ItemResource = opt["item"]
		var b := Button.new()
		b.name = "Item_" + String(opt["item_id"])
		b.text = "%s  %s  ×%d" % [item.icon_hint, item.display_name, int(opt["count"])]
		b.theme_type_variation = &"HudCommand"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		b.disabled = not bool(opt["ok"])
		var line: String = "%s -- %s" % [item.display_name, item.effect_summary()]
		if b.disabled:
			line = "%s -- %s" % [item.display_name, ConsumableEffect.reason_text(String(opt["reason"]), who)]
		b.tooltip_text = line
		b.pressed.connect(choose_item.bind(String(opt["item_id"])))
		b.focus_entered.connect(_on_item_focused.bind(line))
		b.mouse_entered.connect(_on_item_focused.bind(line))
		_items_grid.add_child(b)
		if first == null and not b.disabled:
			first = b
	_grid.visible = false
	_struggle.visible = false
	_party_box.visible = false
	_items_box.visible = true
	_detail.visible = true
	_detail.text = "Pick an item for %s." % (who if who != "" else "your partner")
	if first != null:
		first.grab_focus()
	else:
		(_items_box.find_child("ItemsBack", true, false) as Button).grab_focus()


# --- Party (switching, KO replacement, team preview) --------------------------------------

## The Party button: swap the move grid for the party picker (the acting side's team).
func open_party() -> void:
	if not _accepting or battle == null or _actor == null or not battle.can_switch(_actor):
		return
	_party_mode = "switch"
	_fill_party(battle.side_of(_actor), "PARTY  ·  switching costs the turn", false)


## KO REPLACEMENT: side [param side]'s combatant fainted -- open the picker with no way back
## ([signal replacement_chosen]). [param who] names the player on a shared screen ("Player 2").
func show_replacement(side: int, who: String = "") -> void:
	_actor = null
	_accepting = false
	replacement_side = side
	_party_mode = "replace"
	_panel.visible = true
	_waiting.visible = false
	var cap := "CHOOSE WHO FIGHTS NEXT"
	if who != "":
		cap = "%s  ·  %s" % [who.to_upper(), cap]
	_fill_party(side, cap, true)


## True while the party picker (switch or replacement) is up.
func party_open() -> bool:
	return _party_box != null and _party_box.visible


## Back from the party picker to the move grid (switch mode only; a replacement must be made).
func close_party() -> void:
	if not party_open() or _party_mode != "switch":
		return
	_party_box.visible = false
	_party_mode = ""
	if _accepting and _actor != null:
		show_commands(_actor)


## Pick team member [param index] in the open picker: a switch hands the stage
## [constant SWITCH_SLOT] ([member chosen_member]); a replacement emits
## [signal replacement_chosen]. A member that cannot come in is refused (its row is disabled).
func choose_member(index: int) -> void:
	if battle == null or not party_open():
		return
	if _party_mode == "switch":
		if not _accepting or _actor == null:
			return
		if battle.switch_problem(battle.side_of(_actor), index, false) != "":
			return
		chosen_member = index
		_accepting = false
		_party_box.visible = false
		_party_mode = ""
		slot_chosen.emit(SWITCH_SLOT)
	elif _party_mode == "replace":
		if battle.switch_problem(replacement_side, index, true) != "":
			return
		chosen_member = index
		_party_box.visible = false
		_party_mode = ""
		replacement_chosen.emit(index)


func _fill_party(side: int, caption: String, replacement: bool) -> void:
	for c in _party_grid.get_children():
		_party_grid.remove_child(c)
		c.queue_free()
	_party_caption.text = caption
	_party_back.visible = not replacement
	var first: Button = null
	for r in battle.team_view(side):
		var idx := int(r["index"])
		var b := Button.new()
		b.name = "Member%d" % idx
		var state := ""
		if bool(r["fainted"]):
			state = "Fainted"
		elif bool(r["active"]):
			state = "In battle"
		else:
			state = "HP %d/%d" % [int(r["hp"]), int(r["max_hp"])]
		b.text = "%d  %s  ·  %s" % [idx + 1, String(r["name"]), state]
		b.theme_type_variation = &"HudCommand"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		b.disabled = battle.switch_problem(side, idx, replacement) != ""
		var ch := CharacterLibrary.get_character(StringName(String(r["character_id"])))
		b.tooltip_text = "%s -- %s" % [String(r["name"]), state] if ch == null else \
			"%s (%s) -- %s" % [String(r["name"]), String(ch.element).capitalize(), state]
		b.pressed.connect(choose_member.bind(idx))
		b.focus_entered.connect(_on_item_focused.bind(b.tooltip_text))
		b.mouse_entered.connect(_on_item_focused.bind(b.tooltip_text))
		_party_grid.add_child(b)
		if first == null and not b.disabled:
			first = b
	_grid.visible = false
	_items_box.visible = false
	_struggle.visible = false
	_party_box.visible = true
	_detail.visible = true
	_detail.text = "Who comes in?" if replacement else "Pick a partner to switch in."
	if first != null:
		first.grab_focus()
	elif _party_back.visible:
		_party_back.grab_focus()


## TEAM PREVIEW (party duels, during the intro): both teams, lead first, side A on the left.
## [param names] labels the sides ("You" / the trainer, or the hot-seat players).
func show_team_preview(names: Array = []) -> void:
	hide_team_preview()
	if battle == null:
		return
	_team_preview = PanelContainer.new()
	_team_preview.name = "TeamPreview"
	ConquestTheme.keep_style(_team_preview)
	var sb := MenuTheme.card_box()
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_team_preview.add_theme_stylebox_override("panel", sb)
	_team_preview.set_anchors_preset(Control.PRESET_CENTER)
	_team_preview.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_team_preview.grow_vertical = Control.GROW_DIRECTION_BOTH
	_team_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_team_preview)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team_preview.add_child(row)
	var me := clampi(perspective_side, 0, 1)
	for side in [me, 1 - me]:
		var col := VBoxContainer.new()
		col.name = "Side%d" % side
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(col)
		var title: String = String(names[side]) if side < names.size() and String(names[side]) != "" \
			else ("Your team" if side == me else "Opponent")
		var head := ConquestTheme.section_label(title.to_upper())
		col.add_child(head)
		for r in battle.team_view(side):
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			col.add_child(line)
			var crest := ConquestTheme.portrait(String(r["name"]), ConquestTheme.element_color(String(r["element"])),
				ConquestTheme.TEAM_BLUE if side == 0 else ConquestTheme.TEAM_RED, 30.0)
			line.add_child(crest)
			var l := Label.new()
			l.text = String(r["name"])
			l.add_theme_font_size_override("font_size", ConquestTheme.FS_BODY)
			l.add_theme_color_override("font_color", ConquestTheme.CREAM)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			line.add_child(l)
			line.add_child(ElementVisuals.make_badge(r["element"], ConquestTheme.FS_CAPTION))


func hide_team_preview() -> void:
	if _team_preview != null and is_instance_valid(_team_preview):
		_team_preview.queue_free()
	_team_preview = null


func team_preview_visible() -> bool:
	return _team_preview != null and is_instance_valid(_team_preview) and not _team_preview.is_queued_for_deletion()


## True while the item picker is up.
func items_open() -> bool:
	return _items_box != null and _items_box.visible


## Back from the item picker to the move grid.
func close_items() -> void:
	if not items_open():
		return
	_items_box.visible = false
	if _accepting and _actor != null:
		show_commands(_actor)


## Pick [param item_id] from the picker: hand the director [constant ITEM_SLOT]. An item that
## would be wasted is refused here (its row is disabled anyway).
func choose_item(item_id: String) -> void:
	if not _accepting or battle == null or _actor == null:
		return
	var ok: bool = false
	for opt in battle.item_options(_actor):
		if String(opt["item_id"]) == item_id and bool(opt["ok"]):
			ok = true
	if not ok:
		return
	chosen_item_id = item_id
	_accepting = false
	_items_box.visible = false
	slot_chosen.emit(ITEM_SLOT)


func _on_item_focused(text: String) -> void:
	_detail.visible = true
	_detail.text = text


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
	if items_open() and MenuNav.is_back_event(event):
		get_viewport().set_input_as_handled()
		close_items()
		return
	if party_open():
		if _party_mode == "switch" and MenuNav.is_back_event(event):
			get_viewport().set_input_as_handled()
			close_party()
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var k := (event as InputEventKey).keycode
			if k >= KEY_1 and k <= KEY_6:
				get_viewport().set_input_as_handled()
				choose_member(int(k - KEY_1))
				return
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
	if _accepting and not party_open() and not items_open() and key >= KEY_1 and key <= KEY_4:
		var slot := int(key - KEY_1)
		if slot < rows.size() and rows[slot].visible and not rows[slot].disabled:
			get_viewport().set_input_as_handled()
			_choose(slot)
