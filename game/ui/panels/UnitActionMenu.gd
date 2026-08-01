extends Control

class_name UnitActionMenu

## Fire-Emblem post-move CONTEXTUAL ACTION MENU.
##
## After a unit lands a (tentative) move -- or when the player clicks the selected
## unit's own tile to act in place -- this compact vertical menu pops up next to the
## unit's screen position: its usable moves, then Wait, then Cancel. It replaces the
## old centered SELECT MOVE modal on the golden path so commanding a unit never yanks
## the player's eye to the middle of the screen.
##
## This node is purely presentational + input: it renders the rows and emits a signal
## per choice. UnitActionsPanel owns every consequence (enter targeting, commit + Wait,
## revert + back out) so the state machine stays in one place.
##
## Robustness contract mirrors the rest of the HUD: every unit/moveset/controller slot
## may be null and get_viewport()/get_camera_3d() may be absent (headless harness), and
## nothing here errors when they are.

## A usable move slot was chosen -> caller enters TARGETING for that slot.
signal move_chosen(slot: int)
## Wait chosen -> caller commits the tentative move and ends the unit's turn (no action).
signal wait_chosen
## Cancel chosen (also right-click / ESC while the menu is up) -> caller reverts the
## tentative move and returns to the plain selected state with the range re-shown.
signal cancel_chosen

const MENU_MIN_WIDTH := 168.0
## Keep the menu fully on-screen: this much padding from every viewport edge.
const SCREEN_MARGIN := 12.0

var _card: PanelContainer
var _rows: VBoxContainer
var _unit: Node = null

func _ready() -> void:
	name = "UnitActionMenu"
	# Detach from the parent sidebar Container's layout (same reasoning as
	# MoveSelectionPanel): top_level makes our transform viewport-relative so we can
	# free-float next to the unit instead of being force-fit into the sidebar rect.
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # only the card catches clicks
	z_as_relative = false
	z_index = 90  # above the board, below the SELECT MOVE modal (100)
	_build_ui()
	visible = false

func _build_ui() -> void:
	_card = PanelContainer.new()
	_card.name = "Card"
	_card.custom_minimum_size = Vector2(MENU_MIN_WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_card.add_child(margin)

	_rows = VBoxContainer.new()
	_rows.name = "Rows"
	_rows.add_theme_constant_override("separation", 4)
	margin.add_child(_rows)

	# Amber HUD skin, matching the rest of the panels (same call MoveSelectionPanel uses).
	ConquestTheme.apply_to(self)

## Populate + show the menu for [param unit], positioned next to its screen location.
## [param can_command] gates whether the move/Wait rows are actionable (they always
## are on the golden path; the flag exists so a future inspect-menu could reuse this).
func open_for_unit(unit: Node, can_command: bool = true) -> void:
	_unit = unit
	if unit == null:
		hide()
		return

	# Rebuild rows from the unit's live moveset.
	for child in _rows.get_children():
		child.queue_free()

	var moveset: Array = []
	if unit.has_method("get_moveset"):
		moveset = unit.get_moveset()
	var controller = null
	if unit.has_method("get_moveset_controller"):
		controller = unit.get_moveset_controller()

	var has_action := true
	if unit.has_method("can_act"):
		has_action = unit.can_act()

	var slot := 0
	for move in moveset:
		if move != null:
			_add_move_row(move, slot, controller, can_command and has_action)
		slot += 1

	if moveset.is_empty():
		var none_label := Label.new()
		none_label.text = "No moves"
		none_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(none_label)

	# Wait: commit where you stand and end the unit's turn (the missing finalize).
	var wait_btn := _make_button("Wait", can_command)
	wait_btn.tooltip_text = "Stay here and end this unit's turn"
	wait_btn.pressed.connect(func() -> void: wait_chosen.emit())
	_rows.add_child(wait_btn)

	# Cancel: back out one level (revert the tentative move), always available.
	var cancel_btn := _make_button("Cancel", true)
	cancel_btn.tooltip_text = "Undo this move and pick again (right-click / ESC)"
	cancel_btn.set_meta("style_role", "secondary")
	cancel_btn.pressed.connect(func() -> void: cancel_chosen.emit())
	_rows.add_child(cancel_btn)

	ConquestTheme.apply_to(_card)
	# Wire the shared UI-click SFX onto every (re)built row button (idempotent).
	UIFeedback.attach_sfx(self)

	visible = true
	# Position after a layout pass so the card has its real size to clamp against.
	_reposition_to_unit()
	call_deferred("_reposition_to_unit")

func _add_move_row(move, slot: int, controller, actionable: bool) -> void:
	var usable := true
	if controller != null and controller.has_method("can_use"):
		usable = controller.can_use(move)

	var label_text := ""
	if "display_name" in move:
		label_text = str(move.display_name)
	if label_text == "":
		label_text = "Move %d" % (slot + 1)

	# Small damage / range hint, best-effort (never errors on a legacy move).
	var hint := _move_hint(move, controller)
	if hint != "":
		label_text += "  " + hint

	var btn := _make_button(label_text, actionable and usable)
	btn.tooltip_text = _move_tooltip(move)
	# Element stripe down the left, Pokemon-menu style (guarded like above).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	var swatch := ColorRect.new()
	swatch.color = ConquestTheme.element_color(_move_element(move))
	swatch.custom_minimum_size = Vector2(6, 0)
	swatch.size_flags_vertical = Control.SIZE_FILL
	row.add_child(swatch)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var captured_slot := slot
	btn.pressed.connect(func() -> void: move_chosen.emit(captured_slot))
	row.add_child(btn)
	_rows.add_child(row)

func _make_button(text: String, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	# >=44px hit target (touch-readiness): was 30, kept dense by padding rather
	# than growing the font.
	btn.custom_minimum_size = Vector2(0, 44)
	btn.clip_text = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	return btn

func _move_element(move) -> String:
	if move != null and "element" in move:
		return String(move.element)
	return ""

func _move_hint(move, controller) -> String:
	var parts: PackedStringArray = []
	if move != null and "targeting" in move and move.targeting != null:
		if move.targeting.has_method("describe_range"):
			parts.append(move.targeting.describe_range())
	if controller != null and controller.has_method("remaining"):
		var rem: int = controller.remaining(move)
		if rem > 0:
			parts.append("CD %d" % rem)
	return "(" + ", ".join(parts) + ")" if not parts.is_empty() else ""

func _move_tooltip(move) -> String:
	"""Compact hover tooltip: name -- one-line mechanical effect, then range/cooldown.
	Deliberately NOT move.full_description(), which prepends the authored flavor text
	and can run several lines -- unreadable in a small hover bubble. The full multi-line
	writeup still lives in MoveSelectionPanel's dedicated info panel."""
	if move == null:
		return ""
	var name_str := "Move"
	if "display_name" in move:
		name_str = str(move.display_name)

	var bits: PackedStringArray = []
	var effect := _move_effect_line(move)
	if effect != "":
		bits.append(effect)

	var meta: PackedStringArray = []
	if move != null and "targeting" in move and move.targeting != null and move.targeting.has_method("describe_range"):
		meta.append(move.targeting.describe_range())
	if "cooldown" in move and move.cooldown > 0:
		meta.append("CD %d" % move.cooldown)
	if not meta.is_empty():
		bits.append(", ".join(meta))

	if bits.is_empty():
		return name_str
	return "%s -- %s" % [name_str, " | ".join(bits)]


func _move_effect_line(move) -> String:
	"""Best-effort one-line mechanical summary: each effect's describe(), joined --
	the same source full_description() uses for its mechanics line, minus the authored
	flavor text that made the old tooltip multi-line."""
	if move == null or not ("effects" in move):
		return ""
	var parts: PackedStringArray = []
	for e in move.effects:
		if e and e.has_method("describe"):
			var d: String = e.describe()
			if d != "":
				parts.append(d)
	return " · ".join(parts)

func _reposition_to_unit() -> void:
	"""Place the card next to the unit's projected screen position, clamped to the
	viewport so it is always fully visible. Falls back to a fixed corner when there is
	no camera/viewport (headless)."""
	if _card == null or not is_instance_valid(_card):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var view_size: Vector2 = vp.get_visible_rect().size
	var card_size: Vector2 = _card.get_combined_minimum_size()
	card_size.x = maxf(card_size.x, MENU_MIN_WIDTH)

	var anchor := Vector2(view_size.x * 0.5, view_size.y * 0.5)
	var cam := vp.get_camera_3d()
	if cam != null and _unit != null and _unit is Node3D:
		var world_pos: Vector3 = (_unit as Node3D).global_position
		if not cam.is_position_behind(world_pos):
			anchor = cam.unproject_position(world_pos)

	# Prefer placing the card to the RIGHT of the unit; flip left if it would clip.
	var pos := Vector2(anchor.x + 28.0, anchor.y - card_size.y * 0.5)
	if pos.x + card_size.x + SCREEN_MARGIN > view_size.x:
		pos.x = anchor.x - card_size.x - 28.0
	pos.x = clampf(pos.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, view_size.x - card_size.x - SCREEN_MARGIN))
	pos.y = clampf(pos.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, view_size.y - card_size.y - SCREEN_MARGIN))
	_card.position = pos
	_card.size = card_size

func close() -> void:
	"""Hide the menu and drop its unit reference (no side effects on game state)."""
	_unit = null
	visible = false
