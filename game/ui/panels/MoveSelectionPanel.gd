extends Control

class_name MoveSelectionPanel

# UI for selecting and using a unit's real MoveResource moveset (up to 4 slots).
# Reads unit.get_moveset() / unit.get_moveset_controller() directly.

signal move_selected(move_index: int)
signal move_cancelled

const MAX_SLOTS := 4
## The card's PREFERRED width: what it renders at whenever every label fits. It may
## GROW past this (see [method _fit_width]) but only as far as a real label needs.
const CARD_WIDTH := 340.0
## Hard ceiling on growth. Past this a centered modal starts hiding the battlefield the
## player is choosing a move FOR. A label that still does not fit at this width first
## demotes its "(range ...)" hint to a caption line, and only then ellipsizes the name.
const CARD_MAX_WIDTH := 460.0
## Never let the modal card exceed this fraction of the viewport width, so on a
## narrow window it shrinks instead of clipping past the screen edges.
const CARD_MAX_FRAC := 0.92
const CARD_MIN_WIDTH := 200.0
## Element stripe width + the gap between it and the button column (kept as constants
## because [method _fit_width] has to account for both when it works out how much of
## the card's width is actually text space).
const SWATCH_WIDTH := 7
const ROW_SEPARATION := 6

@onready var moves_container: VBoxContainer
@onready var move_info_label: Label
@onready var back_button: Button

var current_unit: Node
var move_buttons: Array[Button] = []
var _card: PanelContainer
## One record per rendered move row, driving [method _fit_width]:
## { button, caption, boost, inline, name, hint } -- the button, the hidden Label the
## hint demotes onto when inline cannot fit, the optional boost caption, the full
## inline string ("Name (range 1-2) (CD 2/3)"), the bare name, and the hint alone.
## Rebuilt with the rows on every _populate_moves.
var _fit_entries: Array[Dictionary] = []

## READ-ONLY inspection: when true, the panel merely LISTS an (uncommandable) unit's
## moves and shows each move's details on hover/click. It never emits move_selected, so
## the caller never enters targeting or executes. Set per-open via show_moves_for_unit.
var view_only: bool = false
## Cached so _on_move_selected can resolve the clicked slot back to its MoveResource /
## controller when showing details in view-only mode (the number-key path only has an
## index). Refreshed on every show_moves_for_unit.
var _current_moveset: Array[MoveResource] = []
var _current_controller: MovesetController = null
## Title label kept so its text can reflect the mode (SELECT vs VIEW).
var _title_label: Label

## "<unit instance id>:<move_id>" -> the cooldown count this panel last DREW for that
## move. The only reason it exists is the READY FLASH: "just came back up" is a
## transition, not a state, so it cannot be read off the controller -- the controller
## only knows the move is ready now, not that it was charging when the player last saw
## it. Keyed by unit as well as move so two units' copies of the same move never flash
## for each other. Bounded by (units x moves) in one battle and cleared with the panel.
var _last_remaining: Dictionary = {}

func _ready() -> void:
	name = "MoveSelectionPanel"

	# This panel is add_child'd directly onto UnitActionsPanel (see
	# UnitActionsPanel._setup_move_system), which is itself a small PanelContainer
	# pinned to the right-edge sidebar. Left alone, that parent Container would
	# force-fit us into its own tiny rect every layout pass (Container._resort()
	# calls fit_child_in_rect() on every non-top_level child), and our real
	# content (title + up to 4 move buttons + info label + back button) is far
	# bigger than that -- hence it rendering stretched on top of / overlapping
	# the sidebar's own text and buttons.
	#
	# top_level detaches our transform+anchors from the parent (they become
	# relative to the viewport instead) and Container skips top_level children
	# when laying out, so we can freely size and center ourselves as a real
	# modal over the battlefield, entirely independent of the sidebar's rect.
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Draw above sibling HUD panels regardless of where we sit in the tree
	# (z_as_relative = false makes z_index absolute within the canvas layer).
	z_as_relative = false
	z_index = 100

	_create_ui()

	# Keep the card capped to the viewport as the window (and canvas_items scale)
	# changes. get_viewport() can be null in a stripped harness -- guard it.
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_width):
		vp.size_changed.connect(_fit_width)

	visible = false

func _create_ui() -> void:
	"""Create the move selection UI as a centered modal popup over the battlefield."""
	# Dim backdrop: reads as a modal, and blocks clicks from reaching the
	# battlefield/sidebar underneath while a move is being chosen.
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# Centers the card in the middle of the viewport.
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# The card: an opaque amber panel (ConquestTheme.apply_to below turns this
	# PanelContainer's background into the signature panel_box() look) so
	# nothing behind it shows through.
	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)
	_card = card

	# Main container
	var main_container = VBoxContainer.new()
	card.add_child(main_container)

	# Title
	var title = Label.new()
	title.text = "SELECT MOVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	main_container.add_child(title)
	_title_label = title

	# Separator
	var separator = HSeparator.new()
	main_container.add_child(separator)

	# Moves container
	moves_container = VBoxContainer.new()
	moves_container.name = "MovesContainer"
	main_container.add_child(moves_container)

	# Move info display
	move_info_label = Label.new()
	move_info_label.name = "MoveInfoLabel"
	move_info_label.text = "Hover over a move to see details"
	move_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Width 0: let the label take the card's width (capped by _fit_width) and wrap,
	# rather than forcing a 300px floor that could widen the card past a narrow
	# viewport. Only the height floor is kept so the info area never collapses.
	move_info_label.custom_minimum_size = Vector2(0, 60)
	move_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_container.add_child(move_info_label)

	# Back button
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.pressed.connect(_on_back_pressed)
	main_container.add_child(back_button)

	# Apply the amber HUD theme to the whole subtree: amber-izes the Card's
	# background, dark-inks the labels, themes the buttons -- so the popup
	# matches the rest of the HUD instead of the default grey Control theme.
	ConquestTheme.apply_to(self)

	_fit_width()

func show_moves_for_unit(unit: Node, view_only_mode: bool = false) -> void:
	"""Display the unit's real moveset (up to 4 MoveResource slots).

	view_only_mode == true is READ-ONLY inspection: the moves are listed and their
	details shown on hover/click, but selecting a move NEVER emits move_selected (so the
	caller cannot enter targeting or execute). Used for enemy / AI / not-your-turn units.
	Defaults to false so the existing commandable-unit call path is unchanged."""
	current_unit = unit
	view_only = view_only_mode

	if not unit:
		hide()
		return

	var moveset: Array[MoveResource] = unit.get_moveset()
	var controller := unit.get_moveset_controller() as MovesetController

	_current_moveset = moveset
	_current_controller = controller

	# Title + hint reflect the mode so the read-only state is legible.
	if _title_label:
		_title_label.text = "VIEW MOVES" if view_only else "SELECT MOVE"
	if move_info_label:
		if view_only:
			move_info_label.text = "Hover or click a move to read its details"
		else:
			move_info_label.text = "Hover over a move to see details"

	_populate_moves(moveset, controller)
	show()

func _populate_moves(moveset: Array[MoveResource], controller: MovesetController) -> void:
	"""Populate the UI with the unit's moveset (up to MAX_SLOTS entries)."""
	# REMOVE FIRST, free after (same reasoning as UnitActionMenu.open_for_unit): a
	# queue_free()d row is still a child, still visible and still counted in the VBox's
	# minimum size until the frame's delete queue flushes, so a cooldown refresh on an
	# open panel briefly laid out last populate's rows on top of this one's.
	# remove_child() takes the ghosts out of the layout on the spot; queue_free() still
	# defers the actual delete, so repopulating from a button's own handler stays safe.
	move_buttons.clear()
	_fit_entries.clear()
	for child in moves_container.get_children():
		moves_container.remove_child(child)
		child.queue_free()

	if moveset.is_empty():
		var no_moves_label = Label.new()
		no_moves_label.text = "No moves available"
		no_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		moves_container.add_child(no_moves_label)
		_fit_width()
		return

	var slot_count = mini(moveset.size(), MAX_SLOTS)
	for slot in range(slot_count):
		var move = moveset[slot]
		if move == null:
			continue
		var move_button = _create_move_button(move, slot, controller)
		# Pokemon-style element cue: a colour-coded stripe down the left of each
		# move, keyed to the move's element (see ConquestTheme.element_color).
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ROW_SEPARATION)
		var swatch := ColorRect.new()
		swatch.color = ConquestTheme.element_color(String(move.element))
		swatch.custom_minimum_size = Vector2(SWATCH_WIDTH, 0)
		swatch.size_flags_vertical = Control.SIZE_FILL
		row.add_child(swatch)

		# The button plus its two optional readouts stack in one column, so the card's
		# width is unchanged and only a move that actually HAS something to report
		# (a cooldown, a boosted stat) costs any vertical space.
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(move_button)

		# The demotion target for this button's "(range ...) (CD ...)" hint: hidden
		# unless _fit_width decides the inline form cannot fit inside CARD_MAX_WIDTH.
		var hint_caption := Label.new()
		hint_caption.name = "HintCaption"
		hint_caption.text = String(move_button.get_meta("fit_hint", ""))
		hint_caption.add_theme_font_size_override("font_size", ConquestTheme.FONT_CAPTION)
		hint_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint_caption.visible = false
		column.add_child(hint_caption)

		var boost_caption := _build_boost_caption(move)
		if boost_caption != null:
			column.add_child(boost_caption)

		_fit_entries.append({
			"button": move_button,
			"caption": hint_caption,
			"boost": boost_caption,
			"inline": String(move_button.text),
			"name": String(move_button.get_meta("fit_name", "")),
			"hint": String(move_button.get_meta("fit_hint", "")),
		})

		# TOTAL through the controller (see UnitActionMenu): a move whose resolution chose
		# its own wait must divide the bar by the length actually running.
		var total_cd: int = int(controller.total(move)) if controller else int(move.cooldown)
		var remaining: int = controller.remaining(move) if controller else 0
		if total_cd > 0:
			var bar := MoveStatVisuals.make_recharge_bar()
			MoveStatVisuals.update_recharge_bar(bar, remaining, total_cd)
			column.add_child(bar)

		row.add_child(column)
		moves_container.add_child(row)
		move_buttons.append(move_button)
		_note_cooldown(move, remaining, column)

	# Widths are worked out AFTER the theme has reached the new rows: the button
	# styleboxes (and therefore the padding around each label) come from it.
	ConquestTheme.apply_to(_card)
	_fit_width()

func _create_move_button(move: MoveResource, slot: int, controller: MovesetController) -> Button:
	"""Create a button for a single moveset slot."""
	var button = Button.new()

	var can_use := true
	var suffix := ""
	if controller:
		can_use = controller.can_use(move)
		var remaining := controller.remaining(move)
		if remaining > 0:
			# "CD 2/3" rather than the old bare "Cooldown: 2": the recharge bar under the
			# button shows the PROGRESS, and this says how far through the wait that is.
			suffix = " (%s)" % MoveStatVisuals.cooldown_badge(remaining, int(controller.total(move)))
		elif move.max_uses >= 0:
			suffix = " (%d/%d uses)" % [controller.uses_left(move), move.max_uses]

	# EFFECTIVE reach, read through MoveResource.effective_max_range for this unit --
	# never the authored pattern alone, which is what made Petalfang's extended reach
	# invisible on the very button used to pick the move.
	var range_text := MoveStatVisuals.range_phrase(move, current_unit)
	if range_text == "":
		range_text = "no range"
	# Name and hint kept apart (as metadata) so _fit_width can demote the hint to its
	# caption line when the inline form does not fit inside CARD_MAX_WIDTH.
	var name_text := str(move.display_name)
	var hint_text := "(%s)%s" % [range_text, suffix]
	button.text = "%s %s" % [name_text, hint_text]
	button.set_meta("fit_name", name_text)
	button.set_meta("fit_hint", hint_text)
	# In view-only mode every move stays clickable so clicking reliably reveals its
	# details (a disabled button would swallow the click). Cooldown/uses are still shown
	# in the label + details text. Commandable mode keeps the real can-use gating.
	button.disabled = (not view_only) and controller != null and not can_use
	# Height floor only; width 0 + EXPAND_FILL (set by the caller) lets the button
	# fill the card.
	button.custom_minimum_size = Vector2(0, 40)
	# NOT clipped by default. clip_text makes a Button report a text width of just its
	# stylebox padding from get_minimum_size(), so the card sat at CARD_WIDTH looking
	# correctly sized while a long label quietly lost its tail. _fit_width() sizes the
	# card to the real labels and re-arms clipping only on whatever still overflows
	# CARD_MAX_WIDTH after its hint has been demoted to a caption line.
	button.clip_text = false
	button.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING

	# Connect signals — slot is the index into the moveset (matches move_selected(slot)).
	button.pressed.connect(func(): _on_move_selected(slot))
	button.mouse_entered.connect(func(): _show_move_info(move, controller))
	button.mouse_exited.connect(func(): _clear_move_info())

	# NOTE: previously this also set `button.modulate = Color(0.6, 0.6, 0.6, 1.0)`
	# on disabled buttons. That multiplies the *entire* button (background and
	# text together) toward grey on top of the theme's own disabled stylebox /
	# font_disabled_color, which is what made disabled move labels nearly
	# invisible. ConquestTheme's disabled Button styling (darkened fill +
	# INK_SOFT text, both tuned for contrast) already communicates "disabled"
	# on its own, so the extra modulate is removed rather than fighting it.

	return button

func _build_boost_caption(move: MoveResource) -> Label:
	"""A small green (or red) caption under a move button naming every stat currently
	NOT at its authored value -- "Range 3 → 5 ▲+2". Returns null when nothing is
	modified, which is the whole point: an unbuffed move must render exactly as it did
	before this existed, with no empty row eating sidebar height.

	Range is read through MoveResource.effective_max_range and Attack through the unit's
	own get_stat/get_base_stat pair, so every source of a boost -- a status, a tile
	effect, an item, an arena augment -- surfaces here without this panel knowing any of
	them exist."""
	var lines: PackedStringArray = []
	var color: Color = MoveStatVisuals.BUFF_COLOR

	var range_dict: Dictionary = MoveStatVisuals.range_info(move, current_unit)
	if bool(range_dict.get("modified", false)):
		lines.append("%s%s" % [range_dict.get("text", ""), range_dict.get("suffix", "")])
		color = range_dict.get("color", color)

	# Attack only matters on a move that actually deals damage -- a buffed attack stat on
	# a pure heal/status move would be noise.
	if _move_deals_damage(move):
		var atk: Dictionary = MoveStatVisuals.stat_info(current_unit, "attack", "Attack")
		if bool(atk.get("modified", false)):
			lines.append("%s%s" % [atk.get("text", ""), atk.get("suffix", "")])
			color = atk.get("color", color)

	if lines.is_empty():
		return null

	var caption := Label.new()
	caption.name = "BoostCaption"
	caption.text = "  ".join(lines)
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", color)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Untrimmed by default -- a trimmed Label reports a 1px minimum, hiding its real
	# width from _fit_width(). Ellipsis is re-armed there only past CARD_MAX_WIDTH.
	caption.clip_text = false
	caption.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return caption


func _move_deals_damage(move: MoveResource) -> bool:
	"""True when the mode this move is in FOR THE SHOWN UNIT carries a damage effect."""
	if move == null:
		return false
	for effect in move.effects_for(current_unit):
		if effect is DamageEffect:
			return true
	return false


# --- Width budget --------------------------------------------------------------

## Size the card to the WIDEST label it is actually drawing: from the preferred
## CARD_WIDTH up to CARD_MAX_WIDTH (and never past the viewport's CARD_MAX_FRAC --
## the old responsive rule, folded in here). A button whose inline
## "Name (range ...) (CD ...)" form cannot fit even at the cap first DEMOTES the hint
## onto its caption line, so the name -- the part the player is reading -- keeps the
## whole width; only a name that alone still overflows the cap falls back to ellipsis.
##
## The widths are measured off the font rather than read from
## get_combined_minimum_size(): a Control with any text trimming set reports a 1px
## (Label) or padding-only (Button) minimum, so asking the engine "how wide do you
## need to be?" while trimming is on always answers "not very" -- the trap that made
## this card look correctly sized while a long move name was cut mid-word.
func _fit_width() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	var cap := CARD_MAX_WIDTH
	var vp := get_viewport()
	if vp != null:
		cap = minf(cap, vp.get_visible_rect().size.x * CARD_MAX_FRAC)
	cap = maxf(cap, CARD_MIN_WIDTH)
	var base := minf(CARD_WIDTH, cap)

	var needed := base
	for entry in _fit_entries:
		var btn: Button = entry["button"]
		if btn == null or not is_instance_valid(btn):
			continue
		var inline_fits: bool = \
			_chrome_for(btn) + _string_width(btn, String(entry["inline"])) + 1.0 <= cap
		btn.text = String(entry["inline"]) if inline_fits else String(entry["name"])
		var caption: Label = entry["caption"]
		if caption != null and is_instance_valid(caption):
			caption.visible = not inline_fits and String(entry["hint"]) != ""
			if caption.visible:
				needed = maxf(needed, _required_width(caption))
		needed = maxf(needed, _required_width(btn))
		var boost: Label = entry["boost"]
		if boost != null and is_instance_valid(boost):
			needed = maxf(needed, _required_width(boost))
	var target := clampf(ceilf(needed), base, cap)
	_card.custom_minimum_size.x = target

	# Re-arm ellipsis only on whatever still cannot fit at the width we just granted.
	for entry in _fit_entries:
		for key in ["button", "caption", "boost"]:
			var c: Control = entry[key]
			if c != null and is_instance_valid(c) and c.visible:
				_set_trimmed(c, _required_width(c) > target)


## How wide the CARD has to be for [param c] to draw its whole current text. The +1 is
## sub-pixel headroom: Font.get_string_size and the shaper the control actually lays
## out with can disagree by a fraction, and losing that argument costs the last glyph.
func _required_width(c: Control) -> float:
	return _chrome_for(c) + _string_width(c, String(c.get("text"))) + 1.0


## How much of the card's width is NOT available to [param c]'s text: the panel's own
## content margins, the element stripe + its gap, and (for a Button) the button
## stylebox's own padding. Read off the live styleboxes so a theme retune moves this
## with it.
func _chrome_for(c: Control) -> float:
	var chrome := float(SWATCH_WIDTH + ROW_SEPARATION)
	var panel_sb := _card.get_theme_stylebox("panel")
	if panel_sb != null:
		chrome += panel_sb.get_minimum_size().x
	if c is Button:
		var btn_sb := (c as Button).get_theme_stylebox("normal")
		if btn_sb != null:
			chrome += btn_sb.get_minimum_size().x
	return chrome


## Width of [param text] in the font [param c] would draw it in.
func _string_width(c: Control, text: String) -> float:
	var font: Font = c.get_theme_font("font")
	if font == null:
		return 0.0
	var size: int = c.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Turn ellipsis-on-overflow on or off for a Button or a Label. Off is the default so
## the control reports (and gets) its full text width; on is the last resort past the cap.
func _set_trimmed(c: Control, trimmed: bool) -> void:
	var behavior: int = TextServer.OVERRUN_TRIM_ELLIPSIS if trimmed else TextServer.OVERRUN_NO_TRIMMING
	if c is Button:
		(c as Button).clip_text = trimmed
		(c as Button).text_overrun_behavior = behavior
	elif c is Label:
		(c as Label).clip_text = trimmed
		(c as Label).text_overrun_behavior = behavior


func _note_cooldown(move: MoveResource, remaining: int, row: Control) -> void:
	"""Record this move's cooldown for the shown unit and, when it just came back up,
	pulse its row once. See _last_remaining for why the previous value has to be kept
	here rather than asked of the MovesetController."""
	if move == null:
		return
	var key: String = "%d:%s" % [
		current_unit.get_instance_id() if is_instance_valid(current_unit) else 0,
		String(move.move_id),
	]
	var previous: int = int(_last_remaining.get(key, remaining))
	_last_remaining[key] = remaining
	if MoveStatVisuals.became_ready(previous, remaining):
		# Deferred: the row is not in the tree yet on the frame it is built, and a Tween
		# cannot be created on a detached node.
		call_deferred("_flash_row", row)


func _flash_row(row: Control) -> void:
	if row == null or not is_instance_valid(row):
		return
	MoveStatVisuals.flash_ready(row)


func _show_move_info(move: MoveResource, controller: MovesetController) -> void:
	"""Display detailed move information"""
	var info_text = ""
	info_text += "Name: %s\n" % move.display_name
	if String(move.element) != "":
		info_text += "Type: %s\n" % String(move.element).capitalize()
	info_text += "Description: %s\n" % move.full_description()
	if move.energy_cost > 0:
		info_text += "Energy Cost: %d\n" % move.energy_cost
	if move.targeting:
		# Base → effective when something is extending this unit's reach, so the details
		# pane says WHAT changed rather than just reporting a number that disagrees with
		# the .tres a curious player might go read.
		var range_dict: Dictionary = MoveStatVisuals.range_info(move, current_unit)
		if bool(range_dict.get("modified", false)):
			info_text += "Range: %s%s\n" % [
				MoveStatVisuals.range_phrase(move, current_unit), range_dict.get("suffix", "")]
		else:
			info_text += "Range: %s\n" % move.targeting.describe_range()
	info_text += "Accuracy: %d%%\n" % int(move.accuracy * 100)

	if move.cooldown > 0:
		info_text += "Cooldown: %d turns\n" % move.cooldown
	if move.max_uses >= 0:
		info_text += "Max Uses: %d\n" % move.max_uses

	if controller:
		var remaining := controller.remaining(move)
		if remaining > 0:
			info_text += "\nRECHARGING: %s left (%s)" % [
				MoveStatVisuals.cooldown_label(remaining),
				MoveStatVisuals.cooldown_badge(remaining, int(controller.total(move))),
			]

	move_info_label.text = info_text

func _clear_move_info() -> void:
	"""Clear move information display"""
	if view_only:
		move_info_label.text = "Hover or click a move to read its details"
	else:
		move_info_label.text = "Hover over a move to see details"

func _on_move_selected(move_index: int) -> void:
	"""Handle move selection. In view-only mode this is READ-ONLY: clicking a move (or
	its number key) only reveals that move's details -- it does NOT emit move_selected or
	close the panel, so the caller never enters targeting/execution."""
	if view_only:
		if move_index >= 0 and move_index < _current_moveset.size():
			var move: MoveResource = _current_moveset[move_index]
			if move != null:
				_show_move_info(move, _current_controller)
		return
	move_selected.emit(move_index)
	hide()

func _on_back_pressed() -> void:
	"""Handle back button press"""
	move_cancelled.emit()
	hide()

func update_move_cooldowns() -> void:
	"""Update the display to reflect current cooldowns/uses for the shown unit."""
	if current_unit and visible:
		# Preserve the current read-only/commandable mode across a cooldown refresh so a
		# refresh never silently drops the view-only guard on an inspected enemy.
		show_moves_for_unit(current_unit, view_only)

func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_1, KEY_2, KEY_3, KEY_4:
				var move_index = event.keycode - KEY_1
				if move_index < move_buttons.size() and move_buttons[move_index]:
					if not move_buttons[move_index].disabled:
						_on_move_selected(move_index)
