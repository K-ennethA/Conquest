extends Control
class_name MapMenu

## Fire Emblem's MAP MENU: opened with `map_menu` (Esc / Start) or `cancel` while no
## unit is selected and nothing is staged, during the local human's turn.
##
##   Units         -- the viewer's units that can still act; picking one jumps the
##                    board cursor (and camera) onto it.
##   Objective     -- the map's victory / defeat conditions ([ObjectiveText]).
##   Encyclopedia  -- the Compendium as an overlay over the battle ([method
##                    Compendium.open_overlay]); Back / Esc returns to the board.
##   Settings      -- opens the existing [SettingsPanel].
##   End Turn      -- ends the turn (asks first when units can still act). Only the
##                    current LOCAL human may end it (same guard as PlayerTurnPanel,
##                    routed through UnitActionsPanel's end-turn path so multiplayer
##                    still submits a network action).
##   Return to Title -- asks first, then loads the main menu.
##
## Modal: while open it is in [constant InputActions.OVERLAY_GROUP], so the board
## cursor / unit panel / danger zone ignore input. Keyboard + gamepad navigable
## (focus moves with ui_up/ui_down, ui_accept picks, cancel / map_menu go back).
## Also handles the `end_turn` shortcut (the HUD has no PlayerTurnPanel in the
## battle scene), opening the SAME End Turn confirm -- also while a unit is
## selected, since the per-unit command list no longer carries "End Player Turn".
## A confirm opened by the shortcut closes straight back to the board on Cancel.

signal closed

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

## Pages.
enum Page { MAIN, UNITS, OBJECTIVE, CONFIRM_END, CONFIRM_TITLE }

var unit_actions_panel: Node = null   ## set by UILayoutManager
var settings_panel: Node = null       ## set by UILayoutManager
var turn_transition: Node = null      ## set by UILayoutManager (blocks opening mid-wipe)
## The in-battle Compendium overlay while it is open (Encyclopedia), else null.
var encyclopedia: Node = null

var page: int = Page.MAIN
var _backdrop: ColorRect
var _card: PanelContainer
var _title: Label
var _body: VBoxContainer
var _hint: Label
var _footer: HBoxContainer
## True when the End Turn confirm was opened straight from the `end_turn` shortcut
## (not from the main page): Cancel / Esc then close the menu instead of showing MAIN.
var _direct_confirm: bool = false


func _ready() -> void:
	name = "MapMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	add_to_group(InputActions.OVERLAY_GROUP)
	_build_ui()
	ConquestTheme.apply_to(self)
	_style()


func _build_ui() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.03, 0.08, 0.55)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(380, 0)
	center.add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_card.add_child(vb)

	_title = Label.new()
	_title.name = "Title"
	vb.add_child(_title)
	vb.add_child(ConquestTheme.accent_rule())

	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.add_theme_constant_override("separation", 2)
	vb.add_child(_body)

	vb.add_child(HSeparator.new())
	_footer = HBoxContainer.new()
	_footer.name = "Footer"
	_footer.add_theme_constant_override("separation", 18)
	vb.add_child(_footer)
	# Legacy one-line hint (kept for callers reading it; the footer shows key caps).
	_hint = Label.new()
	_hint.visible = false
	vb.add_child(_hint)


func _style() -> void:
	var sb := ConquestTheme.panel_box(0.97)
	sb.border_color = ConquestTheme.GOLD_DK
	sb.crest = true
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 14
	_card.add_theme_stylebox_override("panel", sb)
	_title.add_theme_font_override("font", MenuTheme.display_font(2))
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", ConquestTheme.GOLD_LITE)


# --- Open / close ---------------------------------------------------------------

## May the menu open right now? Only on the local human's turn, with nothing
## selected or staged, no other overlay up and no turn wipe playing.
func can_open() -> bool:
	if visible or not is_inside_tree():
		return false
	if InputActions.gameplay_input_blocked(get_tree()):
		return false
	if turn_transition != null and turn_transition.has_method("is_blocking_input") and turn_transition.is_blocking_input():
		return false
	if unit_actions_panel != null and unit_actions_panel.has_method("has_active_interaction") \
			and unit_actions_panel.has_active_interaction():
		return false
	return LocalPlayer.current_is_local_human()


## May the `end_turn` shortcut open the End Turn confirm now? Like [method can_open]
## but a selected unit (or a staged move / aim) does not block it -- only another
## overlay, a turn wipe, or the SELECT MOVE popup being open does.
func can_open_end_turn() -> bool:
	if visible or not is_inside_tree():
		return false
	if InputActions.gameplay_input_blocked(get_tree()):
		return false
	if turn_transition != null and turn_transition.has_method("is_blocking_input") and turn_transition.is_blocking_input():
		return false
	if unit_actions_panel != null and "move_selection_panel" in unit_actions_panel:
		var msp = unit_actions_panel.move_selection_panel
		if msp != null and is_instance_valid(msp) and msp.visible:
			return false
	return LocalPlayer.current_is_local_human()


func open(start_page: int = Page.MAIN) -> void:
	_direct_confirm = false
	visible = true
	move_to_front()
	show_page(start_page)


func close() -> void:
	if not visible:
		return
	_direct_confirm = false
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	if visible:
		# Back out one level (sub-page -> main -> closed). ui_cancel covers Esc / B
		# even if the gameplay cancel action was rebound.
		if event.is_action_pressed(InputActions.CANCEL) or event.is_action_pressed(InputActions.MAP_MENU) \
				or event.is_action_pressed(&"ui_cancel"):
			if page == Page.MAIN or (page == Page.CONFIRM_END and _direct_confirm):
				close()
			else:
				show_page(Page.MAIN)
			get_viewport().set_input_as_handled()
		return
	# Opening. _input runs before the board cursor's _unhandled_input, and while a
	# unit is selected the UnitActionsPanel owns cancel (can_open is false then).
	if event.is_action_pressed(InputActions.MAP_MENU) or event.is_action_pressed(InputActions.CANCEL):
		if can_open():
			open()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(InputActions.END_TURN):
		# Same End Turn confirm the menu uses -- with or without a unit selected.
		if can_open_end_turn() and not _player_turn_panel_present():
			_on_end_turn()
			get_viewport().set_input_as_handled()


# --- Pages ------------------------------------------------------------------------

func show_page(p: int) -> void:
	page = p
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	match p:
		Page.MAIN:
			_title.text = "Map Menu"
			var n_ready := ready_units().size()
			_add_button("Units", func(): show_page(Page.UNITS), false, "",
				"%d ready" % n_ready if n_ready > 0 else "")
			_add_button("Objective", func(): show_page(Page.OBJECTIVE))
			_add_button("Encyclopedia", _on_encyclopedia)
			_add_button("Settings", _on_settings)
			_add_button("End Turn", _on_end_turn, not LocalPlayer.current_is_local_human(),
				ConquestTheme.action_glyph(InputActions.END_TURN))
			_add_button("Return to Title", func(): show_page(Page.CONFIRM_TITLE))
		Page.UNITS:
			_title.text = "Ready Units"
			var ready := ready_units()
			if ready.is_empty():
				_add_label("No units can act.")
			for u in ready:
				var b := _add_button(_name_of(u), func(): jump_to_unit(u), false, "",
					"%d/%d HP" % [_hp_of(u), _max_hp_of(u)])
				b.tooltip_text = "Jump the cursor to %s" % _name_of(u)
			_add_button("Back", func(): show_page(Page.MAIN))
		Page.OBJECTIVE:
			_title.text = "Objective"
			for line in ObjectiveText.detail_lines(_rules(), _rounds_done()):
				_add_label(line)
			_add_button("Back", func(): show_page(Page.MAIN))
		Page.CONFIRM_END:
			_title.text = "End Turn?"
			var n := ready_units().size()
			_add_label("%d unit%s can still act." % [n, "" if n == 1 else "s"])
			_add_button("End Turn", _do_end_turn)
			_add_button("Cancel", func():
				if _direct_confirm:
					close()
				else:
					show_page(Page.MAIN))
		Page.CONFIRM_TITLE:
			_title.text = "Return to Title?"
			_add_label("This battle's progress will be lost.")
			_add_button("Return to Title", _do_return_to_title)
			_add_button("Cancel", func(): show_page(Page.MAIN))
	var back_key := ConquestTheme.action_glyph(InputActions.CANCEL)
	if back_key == "":
		back_key = "Esc"
	var closes := p == Page.MAIN or (p == Page.CONFIRM_END and _direct_confirm)
	_hint.text = "%s: %s" % [back_key, "Close" if closes else "Back"]
	for c in _footer.get_children():
		_footer.remove_child(c)
		c.queue_free()
	_footer.add_child(ConquestTheme.key_hint(ConquestTheme.action_glyph(InputActions.CONFIRM), "Select"))
	_footer.add_child(ConquestTheme.key_hint(back_key, "Close" if closes else "Back"))
	_focus_first.call_deferred()


func _add_button(text: String, cb: Callable, disabled: bool = false, key: String = "",
		note: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = &"HudCommand"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(336, 44)
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus())
	b.pressed.connect(cb)
	_body.add_child(b)
	if key != "" or note != "":
		ConquestTheme.set_button_hint(b, key, note, ConquestTheme.TEXT_DIM)
	return b


func _add_label(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(336, 0)
	l.add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	_body.add_child(l)


func _focus_first() -> void:
	if not visible:
		return
	for c in _body.get_children():
		if c is Button and not (c as Button).disabled and not c.is_queued_for_deletion():
			(c as Button).grab_focus()
			return


## Button labels on the current page (tests / screenshots).
func button_texts() -> PackedStringArray:
	var out: PackedStringArray = []
	for c in _body.get_children():
		if c is Button and not c.is_queued_for_deletion():
			out.append((c as Button).text)
	return out


# --- Actions ------------------------------------------------------------------------

## The viewer's living units that can still act this turn, in roster order.
func ready_units() -> Array:
	var out: Array = []
	var viewer := LocalPlayer.viewer()
	if viewer == null:
		return out
	for u in viewer.owned_units:
		if u == null or not is_instance_valid(u):
			continue
		if u.has_method("is_alive") and not u.is_alive():
			continue
		if u.has_method("can_act") and not u.can_act():
			continue
		out.append(u)
	return out


## Move the board cursor (and camera) onto [param unit] and close the menu.
func jump_to_unit(unit) -> void:
	close()
	if unit == null or not is_instance_valid(unit):
		return
	var cursor := _cursor()
	var board = CombatServices.board() if CombatServices else null
	if cursor != null and board != null:
		cursor.tile_position = Cells.to_grid(board.cell_of(unit))
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.has_method("focus_on"):
		cam.focus_on((unit as Node3D).global_position)


## Open the Compendium over the battle (board input blocked while it is up; Back /
## Esc returns straight to the board).
func _on_encyclopedia() -> void:
	close()
	encyclopedia = Compendium.open_overlay(get_tree(), Compendium.SECTION_WEATHER)


func _on_settings() -> void:
	close()
	if settings_panel != null and settings_panel.has_method("open"):
		settings_panel.open()


func _on_end_turn() -> void:
	if not LocalPlayer.current_is_local_human():
		return
	if ready_units().is_empty():
		_do_end_turn()
	else:
		if not visible:
			open(Page.CONFIRM_END)
			_direct_confirm = true
			show_page(Page.CONFIRM_END)
		else:
			show_page(Page.CONFIRM_END)


func _do_end_turn() -> void:
	close()
	# Guard again at the point of action (never end the AI's / opponent's turn).
	if not LocalPlayer.current_is_local_human():
		return
	if unit_actions_panel != null and unit_actions_panel.has_method("request_end_player_turn"):
		unit_actions_panel.request_end_player_turn()


func _do_return_to_title() -> void:
	close()
	var tree := get_tree()
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)


# --- Lookups ------------------------------------------------------------------------

func _cursor() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var c := scene.get_node_or_null("Map/Cursor")
	return c if c != null and "tile_position" in c else null


func _rules() -> GameModeRules:
	var gwm := get_tree().get_first_node_in_group("game_world_manager")
	return gwm.get_game_mode_rules() if gwm != null and gwm.has_method("get_game_mode_rules") else null


func _rounds_done() -> int:
	var gwm := get_tree().get_first_node_in_group("game_world_manager")
	return gwm.get_objective_rounds_done() if gwm != null and gwm.has_method("get_objective_rounds_done") else 0


func _player_turn_panel_present() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.find_child("PlayerTurnPanel", true, false) != null


static func _name_of(u) -> String:
	return u.get_display_name() if u.has_method("get_display_name") else str(u)


static func _hp_of(u) -> int:
	return int(u.get_hp()) if u.has_method("get_hp") else 0


static func _max_hp_of(u) -> int:
	return maxi(1, int(u.get_stat("health"))) if u.has_method("get_stat") else maxi(1, _hp_of(u))
