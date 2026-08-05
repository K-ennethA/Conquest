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
## Hard ceiling on the card's width. The menu FLOATS next to the unit, so every pixel it
## is wide is board it covers -- past this it stops being a context menu and starts being
## a modal. A label that still does not fit at this width ellipsizes (see [method _fit_width]);
## no shipped move name comes close (the longest, "Heartwood Guard", needs 188px of card).
const MENU_MAX_WIDTH := 300.0
## Keep the menu fully on-screen: this much padding from every viewport edge.
const SCREEN_MARGIN := 12.0

## MarginContainer inset around the rows (kept as a constant because [method _fit_width]
## has to account for it when it works out how much of the card is text space).
const ROW_MARGIN := 6
## Element stripe width + the gap between it and the button column, same reason.
const SWATCH_WIDTH := 6
const ROW_SEPARATION := 5

var _card: PanelContainer
var _rows: VBoxContainer
var _unit: Node = null
## Every Control in the current rows whose TEXT has to fit: the move/Wait/Cancel buttons
## and the small hint captions. Rebuilt with the rows; drives [method _fit_width].
var _fit_texts: Array[Control] = []

## "<unit instance id>:<move_id>" -> the cooldown count this menu last DREW. Only the
## READY FLASH needs it: "came back up" is a transition and the MovesetController only
## knows the present, so the previous value has to be remembered by whoever last drew it.
## See the same field on [MoveSelectionPanel].
var _last_remaining: Dictionary = {}

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
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", ROW_MARGIN)
	margin.add_theme_constant_override("margin_right", ROW_MARGIN)
	margin.add_theme_constant_override("margin_top", ROW_MARGIN)
	margin.add_theme_constant_override("margin_bottom", ROW_MARGIN)
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
	#
	# REMOVE FIRST, free after. A queue_free()d Control is still a CHILD (and still
	# visible) until the delete queue flushes at the end of the frame, so it keeps
	# counting toward the VBox's minimum size -- and both the immediate and the
	# call_deferred() _reposition_to_unit() below run BEFORE that flush. The old code
	# therefore baked "last menu + this menu" into _card.size on every reopen and, since
	# that is an explicit size, nothing ever shrank it back: measured 345px of content in
	# a 654px card from the second open onward. remove_child() takes the ghost rows out of
	# the layout on the spot; queue_free() still defers the actual delete, so freeing a
	# button from inside its own `pressed` handler stays safe.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_fit_texts.clear()

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
	# Widths are worked out AFTER the theme lands: the button styleboxes (and therefore
	# the padding around each label) come from it.
	_fit_width()
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

	# The range/cooldown hint gets its OWN caption line below the button rather than being
	# glued onto the name. Inline, the widest shipped pairing needs ~335px of card
	# ("Heartwood Guard" 113px + a 141px hint + 75px of padding) -- past MENU_MAX_WIDTH, so
	# the ellipsis landed in the middle of the NAME, which is the one part the player is
	# reading. Split, the name alone sets the width (188px) and the hint rides at caption
	# size underneath, where it costs 15px of height and never truncates anything.
	var hint := _move_hint(move, controller)

	var btn := _make_button(label_text, actionable and usable)
	btn.tooltip_text = _move_tooltip(move)
	# Element stripe down the left, Pokemon-menu style (guarded like above).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ROW_SEPARATION)
	var swatch := ColorRect.new()
	swatch.color = ConquestTheme.element_color(_move_element(move))
	swatch.custom_minimum_size = Vector2(SWATCH_WIDTH, 0)
	swatch.size_flags_vertical = Control.SIZE_FILL
	row.add_child(swatch)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var captured_slot := slot
	btn.pressed.connect(func() -> void: move_chosen.emit(captured_slot))

	# Button, its hint caption and its recharge bar share one column, so a move with
	# nothing to report (no cooldown, no reach) costs no extra height at all.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(btn)

	if hint != "":
		var caption := Label.new()
		caption.name = "Hint"
		caption.text = hint
		caption.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(caption)
		_fit_texts.append(caption)

	var total_cd: int = int(move.cooldown) if ("cooldown" in move) else 0
	var remaining: int = 0
	if controller != null and controller.has_method("remaining"):
		remaining = int(controller.remaining(move))
	if total_cd > 0:
		var bar := MoveStatVisuals.make_recharge_bar()
		MoveStatVisuals.update_recharge_bar(bar, remaining, total_cd)
		column.add_child(bar)

	row.add_child(column)
	_rows.add_child(row)
	_note_cooldown(move, remaining, row)


func _note_cooldown(move, remaining: int, row: Control) -> void:
	"""Remember this move's cooldown for this unit and pulse the row once on the turn it
	comes back up. A move that was ALREADY ready last time the menu was drawn must not
	flash again every time the menu reopens -- that is what became_ready() guarantees."""
	if move == null or not ("move_id" in move):
		return
	var key: String = "%d:%s" % [
		_unit.get_instance_id() if is_instance_valid(_unit) else 0,
		String(move.move_id),
	]
	var previous: int = int(_last_remaining.get(key, remaining))
	_last_remaining[key] = remaining
	if MoveStatVisuals.became_ready(previous, remaining):
		# Deferred: the row is not in the tree on the frame it is built, and a Tween
		# cannot be created on a detached node.
		call_deferred("_flash_row", row)


func _flash_row(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return
	MoveStatVisuals.flash_ready(row)

func _make_button(text: String, enabled: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.disabled = not enabled
	# >=44px hit target (touch-readiness): was 30, kept dense by padding rather
	# than growing the font.
	btn.custom_minimum_size = Vector2(0, 44)
	# NOT clipped by default. clip_text makes a Button report a text width of ZERO from
	# get_minimum_size(), which is how every label in this menu ended up cut off at the
	# 168px floor ("Bramble Cleav"). _fit_width() sizes the card to the real labels and
	# re-arms clipping only on whatever still overflows MENU_MAX_WIDTH.
	btn.clip_text = false
	btn.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_fit_texts.append(btn)
	return btn


# --- Width budget --------------------------------------------------------------

## Size the card to the WIDEST label it is actually drawing, capped at [constant
## MENU_MAX_WIDTH], and ellipsize only what still does not fit at that cap.
##
## The widths are measured off the font rather than read from
## get_combined_minimum_size(): a Control with any text trimming set reports a 1px (Label)
## or padding-only (Button) minimum, so asking the engine "how wide do you need to be?"
## while trimming is on always answers "not very" -- the trap that made this menu look
## correctly sized while every move name was cut in half.
func _fit_width() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	var needed := MENU_MIN_WIDTH
	for c in _fit_texts:
		if is_instance_valid(c):
			needed = maxf(needed, _required_width(c))
	var target := clampf(ceilf(needed), MENU_MIN_WIDTH, MENU_MAX_WIDTH)
	_card.custom_minimum_size.x = target
	for c in _fit_texts:
		if is_instance_valid(c):
			_set_trimmed(c, _required_width(c) > target)


## How wide the CARD has to be for [param c] to draw its whole label.
## The +1 is sub-pixel headroom: Font.get_string_size and the shaper the Button/Label
## actually lays out with can disagree by a fraction, and losing that argument costs the
## last glyph.
func _required_width(c: Control) -> float:
	return _chrome_for(c) + _text_width(c) + 1.0


## How much of the card's width is NOT available to [param c]'s text: the panel's own
## content margins, the rows inset, the element stripe + its gap, and (for a Button) the
## button stylebox's own padding. Read off the live styleboxes so a theme retune moves
## this with it. The stripe allowance is charged to Wait/Cancel too -- they sit in no
## stripe row, so it only ever leaves them extra room.
func _chrome_for(c: Control) -> float:
	var chrome := float(ROW_MARGIN * 2 + SWATCH_WIDTH + ROW_SEPARATION)
	var panel_sb := _card.get_theme_stylebox("panel")
	if panel_sb != null:
		chrome += panel_sb.get_minimum_size().x
	if c is Button:
		var btn_sb := c.get_theme_stylebox("normal")
		if btn_sb != null:
			chrome += btn_sb.get_minimum_size().x
	return chrome


func _text_width(c: Control) -> float:
	var font: Font = c.get_theme_font("font")
	if font == null:
		return 0.0
	var size: int = c.get_theme_font_size("font_size")
	var text: String = String(c.get("text"))
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Turn ellipsis-on-overflow on or off for a Button or a Label. Off is the default so the
## control reports (and gets) its full text width; on is the last resort past the cap.
func _set_trimmed(c: Control, trimmed: bool) -> void:
	var behavior: int = TextServer.OVERRUN_TRIM_ELLIPSIS if trimmed else TextServer.OVERRUN_NO_TRIMMING
	if c is Button:
		(c as Button).clip_text = trimmed
		(c as Button).text_overrun_behavior = behavior
	elif c is Label:
		(c as Label).clip_text = trimmed
		(c as Label).text_overrun_behavior = behavior

func _move_element(move) -> String:
	if move != null and "element" in move:
		return String(move.element)
	return ""

func _move_hint(move, controller) -> String:
	"""The "(range 1-5, ▲+2, CD 2/3)" hint after a move's name.

	Reach is the EFFECTIVE reach for THIS unit -- read through
	MoveResource.effective_max_range, the same helper the executor and the targeting
	highlight use -- with the delta appended so a boost is visible as a CHANGE rather
	than as a number the player has no baseline for. Unboosted, the delta is empty and
	the hint reads exactly as it always did."""
	var parts: PackedStringArray = []
	if move != null and "targeting" in move and move.targeting != null:
		var phrase: String = MoveStatVisuals.range_phrase(move, _unit)
		if phrase != "":
			var range_dict: Dictionary = MoveStatVisuals.range_info(move, _unit)
			parts.append(phrase + String(range_dict.get("suffix", "")))
	if controller != null and controller.has_method("remaining"):
		var rem: int = controller.remaining(move)
		if rem > 0:
			var total: int = int(move.cooldown) if ("cooldown" in move) else 0
			parts.append(MoveStatVisuals.cooldown_badge(rem, total))
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
	# HUG THE CONTENT. The card's parent is a plain Control, so nothing lays the card out
	# for us -- its size is whatever was last assigned here, and an assignment that was too
	# tall stayed too tall. reset_size() re-reads the rows' real minimum every time, so a
	# menu can only ever be exactly its rows plus the panel's padding.
	_card.reset_size()
	var card_size: Vector2 = _card.size

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
