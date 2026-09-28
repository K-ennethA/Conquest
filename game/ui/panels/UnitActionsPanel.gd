extends Control

class_name UnitActionsPanel

# UI panel for unit actions (Move, End Turn, etc.)
# Only appears when a unit is selected (not hovered)

@onready var margin_container: MarginContainer = $MarginContainer
@onready var content_container: VBoxContainer = $MarginContainer/ContentContainer
@onready var unit_header_container: HBoxContainer = $MarginContainer/ContentContainer/UnitHeaderContainer
@onready var unit_header_background: Panel = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitHeaderBackground
@onready var unit_icon: TextureRect = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitIcon
@onready var unit_info_container: VBoxContainer = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer
@onready var unit_name_label: Label = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer/UnitNameLabel
@onready var unit_type_label: Label = $MarginContainer/ContentContainer/UnitHeaderContainer/UnitInfoContainer/UnitTypeLabel
@onready var move_button: Button = $MarginContainer/ContentContainer/ActionsContainer/MoveButton
@onready var end_unit_turn_button: Button = $MarginContainer/ContentContainer/ActionsContainer/EndUnitTurnButton
@onready var unit_summary_button: Button = $MarginContainer/ContentContainer/ActionsContainer/UnitSummaryButton
## The FE command list (Move / Skills / Wait / Info / Cancel, HudCommand rows with key
## hints). "Info" opens the full-screen [UnitDetailPage] -- the stat surfaces are exactly
## three and do not overlap: the compact battle card ([UnitInfoPanel], live battle facts),
## the detail page (everything general) and the combat forecast (damage maths).
@onready var actions_container: VBoxContainer = $MarginContainer/ContentContainer/ActionsContainer
@onready var end_player_turn_button: Button = $MarginContainer/ContentContainer/EndPlayerTurnButton
@onready var cancel_button: Button = $MarginContainer/ContentContainer/ActionsContainer/CancelButton

var selected_unit: Unit = null
## The in-flight movement slide (see [method _animate_unit_movement]). Held so a second
## move can KILL the previous one instead of letting two tweens fight over the same
## `global_position`.
var _move_tween: Tween = null
var movement_mode: bool = false
var movement_range_tiles: Array[Vector3] = []

# --- Explicit command state machine ------------------------------------------
# The golden Fire-Emblem loop is one clean progression -- select a unit, (tentatively)
# move it, pick an action from the contextual menu, aim it -- and every back-out is one
# step in reverse. Modelling that as an explicit state instead of deriving it from a
# soup of booleans (movement_mode / move_mode / _tentative_active) means the cancel
# chain, the cursor's routing, and the tests all read from ONE authority.
#
#   IDLE          nothing selected
#   UNIT_SELECTED a commandable unit is selected, its movement range shown
#   ACTION_MENU   the contextual action menu is up (post-move or act-in-place)
#   TARGETING     aiming a chosen move at the board
#
# Forward:  IDLE -> UNIT_SELECTED -> ACTION_MENU -> TARGETING
# Cancel:   each step backs out to the previous one (see cancel_target_state()).
#
# The legacy `movement_mode` path (non-character / no-board units that commit instantly)
# still works, but it lives OUTSIDE this enum -- those units never stage a tentative
# move, so they never enter ACTION_MENU; they go straight through the committed move.
enum CommandState { IDLE, UNIT_SELECTED, ACTION_MENU, TARGETING }
var _state: int = CommandState.IDLE

# The contextual post-move action menu (created in _setup_move_system).
var action_menu: UnitActionMenu

# --- Enemy threat: ONE implementation, two reads ------------------------------
#   PERSISTENT: the DangerZoneOverlay (danger_zone action, default Z / pad L3, or the
#     touch "Danger Zone" toggle below) paints every hostile unit's strike cells until
#     toggled off. It recomputes itself on moves / deaths / turn starts, and skips units
#     the fog of war hides (see _compute_enemy_threat_cells for the same rule).
#   SINGLE ENEMY: selecting (inspecting) an enemy shows ITS blue movement range plus the
#     red attack fringe it could strike from anywhere it can reach
#     (_show_inspect_movement_range). It clears with the selection.

# While a network MOVE intent for this unit is in flight: when the accepted move lands,
# the contextual action menu opens on it (see _on_network_action_applied).
var _awaiting_net_move_unit: Unit = null

# Move system variables
var move_selection_panel: MoveSelectionPanel
var moves_button: Button
var move_mode: bool = false
var selected_move_index: int = -1

# --- Touch-readiness: on-screen equivalents for keyboard-only actions --------
# Danger mirrors the danger_zone action (DangerZoneOverlay.toggle); Next mirrors
# cycle_next (the board cursor's cycle_ready_unit); End Turn mirrors end_turn (the Map
# Menu's confirm). Built in code under the command list (see _setup_touch_buttons), so a
# touch player without a physical keyboard can still reach them.
var danger_zones_button: Button
var next_unit_button: Button
## Touch / mouse End Turn (routes through the Map Menu's End Turn confirm).
var end_turn_row_button: Button

# FE-style combat forecast overlay (preview-only; never mutates state). Shown
# while targeting an offensive move over an eligible enemy; updated live as the
# cursor moves; hidden when targeting is cancelled/cleared or the move resolves.
var combat_forecast_panel: CombatForecastPanel
# The enemy the forecast is currently shown for (or null). Lets _refresh_move_forecast
# own its own "stays sticky until the target genuinely changes" guarantee locally,
# rather than depending on GameEvents.cursor_moved only firing on real cell changes --
# see the TOUCH-READY STICKINESS note there.
var _forecast_target_enemy: Unit = null
# Latest board-cursor tile (tracked from GameEvents.cursor_moved) so a move
# selected while the cursor already rests on an enemy previews immediately.
var _last_cursor_tile: Vector3 = Vector3.ZERO

# --- Fire-Emblem TENTATIVE-MOVE state ----------------------------------------
# Canonical FE loop: clicking a reachable cell moves the unit there TENTATIVELY
# (visual + logical position updated, but NOT committed -- mark_moved / the
# unit_moved event / action-consumption are deferred). The player then picks an
# action; CONFIRM commits the move and executes, CANCEL reverts the unit to its
# origin cell with the unit still fully available.
#
# Because BoardAdapter derives each unit's cell live from its world position,
# snapping the unit onto the destination cell (board.move_unit) makes
# board.cell_of(unit) == dest immediately, so the movement-range / targeting /
# forecast / execution math all read the tentative position with no extra
# plumbing. Nothing is "committed" until _commit_tentative_move() runs, because
# commit is the only place mark_moved() + GameEvents.unit_moved fire.
var _tentative_active: bool = false
var _tentative_unit: Unit = null
var _tentative_origin_cell: Vector3i = Vector3i.ZERO
var _tentative_dest_cell: Vector3i = Vector3i.ZERO
var _tentative_origin_world: Vector3 = Vector3.ZERO
## Facing before the staged walk, restored on undo (visual only; see UnitFacing).
var _tentative_origin_facing: Vector2i = Vector2i.ZERO

# Frame on which the SELECT MOVE popup closed itself in response to ESC/BACK
# (MoveSelectionPanel emits move_cancelled -> _on_move_cancelled). Both that panel
# and this one process the same ESC in the _input phase, in an order Godot does not
# guarantee; when the popup already consumed an ESC on THIS frame, _on_cancel_pressed
# must not also back out a further level. Exact-frame equality avoids a stale flag
# (a mouse BACK on an earlier frame never matches the current frame).
var _popup_closed_frame: int = -1

# Fire-Emblem path arrow: the resolver that produced the CURRENT blue range (kept so
# path_to() can answer "how would I walk to the hovered cell" without re-flooding),
# the cell it was flooded from, and whether an arrow is on the board right now.
var _range_resolver: MovementResolver = null
var _range_origin: Vector3i = Cells.INVALID
var _path_shown: bool = false
# The red fringe last published for the current range (grid coords), so it can be
# hidden while aiming a move (the attack-range highlight takes over) and restored.
var _fringe_grid: Array = []

# Code-built header pieces (portrait emblem + HP row); see _setup_unit_header_styling.
var _portrait: PanelContainer = null
var _hp_row: HBoxContainer = null
var _hp_bar: ProgressBar = null
var _hp_text: Label = null

func _ready() -> void:
	add_to_group("unit_actions_panel")
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP  # Make sure panel stops mouse events
	
	# Connect to game events
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		GameEvents.cursor_selected.connect(_on_cursor_selected)
		# A dead selected unit is dropped at the source (see _on_unit_eliminated_danger).
		if not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated_danger):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated_danger)
		# The touch Danger Zone toggle mirrors the overlay, whoever toggled it (Z / L3 too).
		if GameEvents.has_signal("danger_zone_changed") \
				and not GameEvents.danger_zone_changed.is_connected(_on_danger_zone_changed):
			GameEvents.danger_zone_changed.connect(_on_danger_zone_changed)
	else:
		push_error("GameEvents not found!")

	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
	else:
		push_error("PlayerManager not found!")

	# Connect button signals and ensure they can receive mouse input
	if move_button:
		move_button.mouse_filter = Control.MOUSE_FILTER_STOP
		move_button.pressed.connect(_on_move_pressed)
	else:
		push_error("Move button not found!")

	if end_unit_turn_button:
		end_unit_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_unit_turn_button.pressed.connect(_on_end_unit_turn_pressed)
		# Add mouse event debugging to the button
		end_unit_turn_button.gui_input.connect(_on_end_unit_turn_button_input)
	else:
		push_error("End Unit Turn button not found!")

	if unit_summary_button:
		unit_summary_button.mouse_filter = Control.MOUSE_FILTER_STOP
		unit_summary_button.pressed.connect(_on_unit_summary_pressed)
	else:
		push_error("Info button not found!")

	if end_player_turn_button:
		end_player_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_player_turn_button.pressed.connect(_on_end_player_turn_pressed)
	else:
		push_error("End Player Turn button not found!")

	if cancel_button:
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
		cancel_button.pressed.connect(_on_cancel_pressed)
	else:
		push_error("Cancel button not found!")

	# Network matches: refresh when an accepted action (ours or the opponent's) lands, and
	# drop a pending "open the menu when my move lands" if the host refused the intent.
	if GameModeManager and GameModeManager.has_signal("network_action_applied"):
		GameModeManager.network_action_applied.connect(_on_network_action_applied)
	if GameModeManager and GameModeManager.has_signal("network_intent_rejected"):
		GameModeManager.network_intent_rejected.connect(_on_network_intent_rejected)

	# Hide panel initially
	_hide_panel()
	
	# Style the unit header background
	_setup_unit_header_styling()
	
	# Initialize move system
	_setup_move_system()

	# On-screen buttons for the board-level actions (Danger Zone / Next Unit / End Turn).
	_setup_touch_buttons()

	# The one-line "this route springs a trap" warning (see _setup_trap_warning).
	_setup_trap_warning()

	# Tooltips + theme style-role metadata on the (simplified) sidebar buttons.
	_setup_sidebar_tooltips_and_meta()

func _setup_sidebar_tooltips_and_meta() -> void:
	"""Tooltips for mouse users (the key caps on each command row cover keyboard / pad).
	The command rows are HudCommand rows; the plain buttons below them carry a
	`style_role` that ConquestTheme.apply_button_role reads (secondary / destructive)."""
	if move_button:
		move_button.tooltip_text = "Move this unit: pick a blue tile (or click one straight away), then act or Wait."
	if end_unit_turn_button:
		end_unit_turn_button.tooltip_text = "Wait: end this unit's action for the turn (keeps any move)."
	if moves_button:
		moves_button.tooltip_text = "Attack or use a skill: pick one of this unit's moves, then a target."
	if unit_summary_button:
		unit_summary_button.tooltip_text = "Open this unit's full page -- stats, moves, abilities, statuses."
	if end_player_turn_button:
		end_player_turn_button.tooltip_text = "End the whole player turn. Confirms if units still have actions."
		end_player_turn_button.set_meta("style_role", "destructive")
	if cancel_button:
		cancel_button.tooltip_text = "Back out one step (undo the move, then deselect). Right-click works too."

	# Shared UI-click SFX on every sidebar button, including the dynamically built
	# moves_button (idempotent -- guarded by a meta inside UIFeedback).
	UIFeedback.attach_sfx(self)

func _setup_touch_buttons() -> void:
	"""On-screen equivalents for the board-level actions a touch / mouse player has no key
	for -- Danger Zone (danger_zone), Next Unit (cycle_next) and End Turn (end_turn) --
	laid out as one compact row under the command list, so the turn-control block stays
	grouped at the bottom. Same secondary style_role + tooltip-names-the-key pattern as
	the rest of the card; wired for SFX by the attach_sfx call in
	_setup_sidebar_tooltips_and_meta, which runs after this."""
	var content_container := get_node_or_null("MarginContainer/ContentContainer")
	if content_container == null:
		return

	danger_zones_button = Button.new()
	danger_zones_button.name = "DangerZonesButton"
	danger_zones_button.text = "Danger"
	danger_zones_button.toggle_mode = true
	danger_zones_button.custom_minimum_size = Vector2(0, 44)
	danger_zones_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	danger_zones_button.tooltip_text = InputActions.with_hint("Show / hide every enemy's threat range", InputActions.DANGER_ZONE)
	danger_zones_button.mouse_filter = Control.MOUSE_FILTER_STOP
	danger_zones_button.set_meta("style_role", "secondary")
	danger_zones_button.pressed.connect(_on_danger_zones_button_pressed)

	next_unit_button = Button.new()
	next_unit_button.name = "NextUnitButton"
	next_unit_button.text = "Next"
	next_unit_button.custom_minimum_size = Vector2(0, 44)
	next_unit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_unit_button.tooltip_text = InputActions.with_hint("Select the next unit that can still act", InputActions.CYCLE_NEXT)
	next_unit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	next_unit_button.set_meta("style_role", "secondary")
	next_unit_button.pressed.connect(_on_next_unit_button_pressed)

	end_turn_row_button = Button.new()
	end_turn_row_button.name = "EndTurnRowButton"
	end_turn_row_button.text = "End Turn"
	end_turn_row_button.custom_minimum_size = Vector2(0, 44)
	end_turn_row_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_turn_row_button.tooltip_text = InputActions.with_hint(
		"End the whole player turn (asks first while units can still act)", InputActions.END_TURN)
	end_turn_row_button.mouse_filter = Control.MOUSE_FILTER_STOP
	end_turn_row_button.set_meta("style_role", "destructive")
	end_turn_row_button.pressed.connect(_on_end_player_turn_pressed)

	# Two short toggles side by side, End Turn full width under them (a 290px card cannot
	# hold three Cinzel plates in one row).
	var utility_row := VBoxContainer.new()
	utility_row.name = "UtilityRow"
	utility_row.add_theme_constant_override("separation", 6)
	var toggles := HBoxContainer.new()
	toggles.name = "Toggles"
	toggles.add_theme_constant_override("separation", 6)
	toggles.add_child(danger_zones_button)
	toggles.add_child(next_unit_button)
	utility_row.add_child(toggles)
	utility_row.add_child(end_turn_row_button)
	content_container.add_child(utility_row)
	# Directly under the command list (ActionsContainer), above the hidden legacy
	# End Player Turn button.
	if actions_container != null and actions_container.get_parent() == content_container:
		content_container.move_child(utility_row, actions_container.get_index() + 1)

	_sync_danger_zones_button()

# --- Trap route warning ------------------------------------------------------
#
# TRAPS SPRING WHERE YOU STEP (CONQUEST.md rule 10), so a route can cost the player a move
# they never saw coming: the destination tile is clean, but a trap two cells back catches
# the unit on the way. Traps are VISIBLE tiles -- nothing here reveals anything the player
# could not already see on the board -- so the honest thing is to say so BEFORE the move is
# confirmed rather than let the confirm be a surprise.
#
# Two moments, one line:
#   * sweeping the cursor over the movement range (before the click), and
#   * while a tentative move is staged and awaiting its confirm.
# The staged case owns the line until the move is committed or cancelled, so the warning
# that made the player think twice does not vanish the instant they stop moving the cursor.


## Leading mark on the warning line. PLAIN ASCII, deliberately: the theme font has no
## Geometric Shapes coverage, so the obvious warning triangle draws as tofu -- this project
## has shipped that twice (see the probe table in unit/test_status_feedback.gd).
const TRAP_WARNING_MARK := "!"

## The warning line itself. Built in code (like the utility row above) and pinned at the top
## of the sidebar's content, directly under the unit header, so it reads as a property of
## the unit's pending move rather than of any one button.
var trap_warning_label: Label = null


func _setup_trap_warning() -> void:
	"""Create the (initially hidden) trap warning line and pin it under the unit header."""
	var content_container := get_node_or_null("MarginContainer/ContentContainer")
	if content_container == null:
		return

	trap_warning_label = Label.new()
	trap_warning_label.name = "TrapWarningLabel"
	trap_warning_label.text = ""
	trap_warning_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
	# Its own colour on purpose: keep the HUD-wide theme sweep off it.
	ConquestTheme.keep_style(trap_warning_label)
	trap_warning_label.add_theme_color_override("font_color", MoveStatVisuals.NERF_COLOR)
	trap_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trap_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trap_warning_label.visible = false
	content_container.add_child(trap_warning_label)

	var header := content_container.get_node_or_null("UnitHeaderContainer")
	if header != null:
		content_container.move_child(trap_warning_label, header.get_index() + 1)


## Repaint the warning for the route to [param grid_pos] (a Vector3(col, 0, row) grid coord
## under the cursor). Reads only -- [method TileEffectSystem.preview_route] applies nothing.
func _refresh_trap_warning(grid_pos: Vector3) -> void:
	if trap_warning_label == null or not is_instance_valid(trap_warning_label):
		return
	# A staged tentative move owns the line until confirm/cancel (see the block note).
	if _tentative_active:
		return
	if not movement_mode or selected_unit == null or not _is_grid_pos_in_range(grid_pos):
		_set_trap_warning(null)
		return
	var board = CombatServices.board()
	if board == null:
		_set_trap_warning(null)
		return
	var route: Dictionary = TileEffectSystem.preview_route(
		selected_unit, board.cell_of(selected_unit), _grid_tile_to_cell(grid_pos), board)
	_set_trap_warning(route.get("trap", null))


## Show the warning line for [param trap], or hide it when [param trap] is null. The trap's
## name comes from [TileEffectVisuals] -- the same source the terrain card's chip and the
## board's own overlay pip use -- so the warning names the tile the player can see.
func _set_trap_warning(trap) -> void:
	if trap_warning_label == null or not is_instance_valid(trap_warning_label):
		return
	if trap == null:
		trap_warning_label.text = ""
		trap_warning_label.visible = false
		return
	var label: String = String(TileEffectVisuals.info_for(trap).get("name", "a trap"))
	trap_warning_label.text = "%s Springs %s" % [TRAP_WARNING_MARK, label]
	trap_warning_label.visible = true


## The cell a move to [param dest_cell] would actually END on for the selected unit -- the
## destination, or the armed halting trap that stops it short. Public so the ghost, the
## commit and a test all ask the ONE function (see TileEffectSystem.preview_route).
func planned_stop_cell(unit, dest_cell: Vector3i) -> Vector3i:
	var board = CombatServices.board()
	if board == null or unit == null:
		return dest_cell
	return TileEffectSystem.preview_route(unit, board.cell_of(unit), dest_cell, board).get("stop", dest_cell)


func _on_danger_zones_button_pressed() -> void:
	"""On-screen equivalent of the danger_zone action: toggle every enemy's threat. The
	button's pressed look is synced from the overlay's own state (see
	_sync_danger_zones_button), so it stays right whoever toggled it."""
	_toggle_all_enemy_danger()
	_sync_danger_zones_button()

func _sync_danger_zones_button() -> void:
	"""Keep the on-screen Danger toggle in lockstep with the DangerZoneOverlay."""
	if danger_zones_button:
		var dz := _danger_zone_overlay()
		danger_zones_button.set_pressed_no_signal(dz != null and bool(dz.active))

func _on_danger_zone_changed(_active: bool = false, _count: int = 0) -> void:
	_sync_danger_zones_button()

func _on_next_unit_button_pressed() -> void:
	"""On-screen equivalent of cycle_next. Same guard as the keyboard path: skip while
	the contextual action menu / targeting is up so it cannot yank selection
	mid-command."""
	if _state == CommandState.ACTION_MENU or _state == CommandState.TARGETING:
		return
	_cycle_to_next_commandable_unit()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_RESIZED:
			# Resize notification - no logging to prevent spam
			pass
		NOTIFICATION_VISIBILITY_CHANGED:
			# Visibility notification - no logging to prevent spam
			pass

func _setup_unit_header_styling() -> void:
	"""Build the FE-style unit header: a circular portrait emblem (initial on the
	unit's element colour, ringed in its team colour), the full name (wraps -- never
	truncated; tooltip carries it too), a side / element subtitle, and a slim HP bar
	with numbers. The command rows below get key-hint caps (see _set_command)."""
	if unit_header_container and _portrait == null:
		_portrait = ConquestTheme.portrait("?", ConquestTheme.GOLD, ConquestTheme.BORDER, 52.0)
		unit_header_container.add_child(_portrait)
		unit_header_container.move_child(_portrait, unit_info_container.get_index() if unit_info_container else 0)
	if unit_name_label:
		unit_name_label.theme_type_variation = &"SubheadingLabel"
		unit_name_label.clip_text = false
		unit_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit_name_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if unit_type_label:
		unit_type_label.clip_text = false
		unit_type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if unit_info_container and _hp_row == null:
		_hp_row = HBoxContainer.new()
		_hp_row.name = "HPRow"
		_hp_row.add_theme_constant_override("separation", 8)
		_hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ConquestTheme.keep_style(_hp_row)
		unit_info_container.add_child(_hp_row)
		_hp_bar = ConquestTheme.hp_bar(9.0)
		_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_hp_row.add_child(_hp_bar)
		_hp_text = Label.new()
		_hp_text.name = "HPText"
		_hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_text.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
		_hp_text.add_theme_color_override("font_color", ConquestTheme.CREAM)
		_hp_row.add_child(_hp_text)
	# Tooltips for the commands (mouse users; the key caps cover keyboard / pad).
	if move_button:
		move_button.tooltip_text = "Move this unit. Pick a blue tile, then act or Wait."
	if end_unit_turn_button:
		end_unit_turn_button.tooltip_text = "Wait: end this unit's action for the turn (keeps any move)."
	if unit_summary_button:
		unit_summary_button.tooltip_text = "Open this unit's full page."
	if cancel_button:
		cancel_button.tooltip_text = "Back out one step (undo the move, then deselect)."
	for b in [move_button, end_unit_turn_button, unit_summary_button, cancel_button]:
		if b:
			b.theme_type_variation = &"HudCommand"
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.focus_mode = Control.FOCUS_NONE


## Set a command row's label and its right-aligned hint: a key cap for [param action]
## (from InputActions -- follows rebinding and shows the pad glyph when a gamepad is
## connected), or a short [param note] ("Done", "4/4 ready") instead.
func _set_command(button: Button, label: String, action: StringName = &"", note: String = "",
		note_color: Color = ConquestTheme.TEXT_MUTED) -> void:
	if button == null:
		return
	button.text = label
	ConquestTheme.set_button_hint(button, ConquestTheme.action_glyph(action) if note == "" else "", note, note_color)


## The key-hint text currently shown on a command row ("" when none) -- tests.
func command_hint_text(button: Button) -> String:
	var hint := button.get_node_or_null("Hint") if button else null
	if hint == null:
		return ""
	for c in hint.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is Label:
			return (c as Label).text
		var k := c.get_node_or_null("Key") as Label
		if k != null:
			return k.text
	return ""


func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - show actions for selected unit"""
	# Selection == inspection: any living unit may be selected so the player can read
	# its info (including enemy / AI-owned units). Commanding is gated separately via
	# _human_may_command() -- _update_actions() renders disabled buttons for units the
	# player cannot command. The single-player AI hard-gate, the PlayerManager gate and
	# the Traditional can-act gate that used to REJECT selection here are gone -- in
	# network matches too: _player_is_human() compares against the local network seat,
	# so an opponent's unit is inspectable but never commandable.
	selected_unit = unit

	_update_unit_header()
	_update_actions()

	# Show movement range immediately when unit is selected (tactical style)
	_show_movement_range_on_selection()

	_show_panel()

	# Drive the state machine: a commandable unit enters the golden path at UNIT_SELECTED
	# (range shown, awaiting a move / act-in-place click). An inspection-only enemy leaves
	# the machine IDLE -- it is not part of the command loop.
	if _human_may_command(selected_unit):
		_set_state(CommandState.UNIT_SELECTED)
	else:
		_set_state(CommandState.IDLE)

func _show_movement_range_on_selection() -> void:
	"""Show movement range immediately when unit is selected (tactical style)"""
	if not selected_unit:
		return

	# An enemy / AI unit is INSPECTION-only. Still show WHERE IT COULD MOVE (its blue
	# range) and the red fringe it could strike from there, so the player can read the
	# danger -- via a display-only path that does NOT record those cells as a move
	# destination, so clicking them never relocates a unit the player can't command. It
	# clears with the selection (the next click).
	if not _human_may_command(selected_unit):
		_show_inspect_movement_range()
		return

	# Calculate and show movement range
	_calculate_and_show_movement_range()

func _update_unit_header() -> void:
	"""Update the unit header: portrait, full name (never truncated), side / element
	subtitle in the team colour, and HP."""
	if not selected_unit:
		return
	var player = selected_unit.get_owner_player()
	var display_name: String = selected_unit.get_display_name()

	if unit_name_label:
		unit_name_label.text = display_name
		unit_name_label.tooltip_text = display_name

	# Subtitle: "Ally · Nature · Vineweave" (the type only when it adds information).
	if unit_type_label:
		var parts: PackedStringArray = [ConquestTheme.side_label(player)]
		var el := String(selected_unit.get_element()) if selected_unit.has_method("get_element") else ""
		if el != "":
			parts.append(el.capitalize())
		if selected_unit.has_method("is_boss") and selected_unit.is_boss():
			parts.append("Boss")
		var type_text := _humanize_id(selected_unit.get_unit_type())
		if type_text != "" and not display_name.to_lower().contains(type_text.to_lower()):
			parts.append(type_text)
		unit_type_label.text = "  ·  ".join(parts)
		unit_type_label.visible = true
		unit_type_label.add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
		unit_type_label.add_theme_color_override("font_color", ConquestTheme.team_text_color(player))

	if _portrait:
		var cols := ConquestTheme.unit_portrait_colors(selected_unit)
		ConquestTheme.set_portrait(_portrait, display_name, cols[0], cols[1])
	# Team-coloured edge stripe on the command card (element lives in the crest).
	add_theme_stylebox_override("panel", ConquestTheme.unit_card_box(selected_unit, 0.96))
	_update_header_hp()

	# Legacy icon texture (hidden node; kept so callers / tests stay valid).
	if unit_icon:
		_update_unit_icon()
	if unit_header_background:
		_update_header_background_color()


func _update_header_hp() -> void:
	if not selected_unit or _hp_bar == null:
		return
	var cur: int = int(selected_unit.current_health)
	var mx: int = maxi(1, int(selected_unit.max_health))
	var frac := clampf(float(cur) / float(mx), 0.0, 1.0)
	_hp_bar.value = frac
	ConquestTheme.tint_hp_bar(_hp_bar, frac)
	_hp_text.text = "%d/%d" % [cur, mx]

## Turn a snake_case id ("vineweave") into a display string
## ("Torvald Ironhide"). Empty in -> empty out.
func _humanize_id(id: String) -> String:
	if id == "":
		return ""
	var out: PackedStringArray = []
	for w in id.replace("_", " ").split(" ", false):
		if w.length() > 0:
			out.append(w.substr(0, 1).to_upper() + w.substr(1))
	return " ".join(out)


## Deterministic vibrant tint for a character id, so portraits read distinctly.
func _color_for_type(unit_type: String) -> Color:
	if unit_type == "":
		return Color(0.6, 0.6, 0.6, 1.0)
	var hue := float(absi(hash(unit_type)) % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85, 1.0)


func _update_unit_icon() -> void:
	"""Update the unit icon based on unit type and player"""
	if not selected_unit or not unit_icon:
		return
	
	# For now, create a simple colored rectangle as the unit icon
	# This can be replaced with actual unit sprites later
	var unit_type = selected_unit.get_unit_type()
	var player = selected_unit.get_owner_player()
	
	# Create a simple colored texture based on unit type and player
	var image = Image.create(36, 36, false, Image.FORMAT_RGBA8)

	# Base color derived from the character id (unit_type is a String now), so
	# each character gets a distinct, vibrant portrait tint.
	var base_color: Color = _color_for_type(unit_type)
	
	# Tint based on player
	if player:
		if player.player_id == 0:
			# Player 1 - add blue tint
			base_color = base_color.lerp(Color(0.2, 0.4, 0.8, 1.0), 0.3)
		elif player.player_id == 1:
			# Player 2 - add red tint
			base_color = base_color.lerp(Color(0.8, 0.2, 0.2, 1.0), 0.3)
	
	# Fill the image with the color
	image.fill(base_color)
	
	# Add a simple border
	var border_color = Color(1.0, 1.0, 1.0, 0.8)
	# Top and bottom borders
	for x in range(36):
		image.set_pixel(x, 0, border_color)
		image.set_pixel(x, 35, border_color)
	# Left and right borders
	for y in range(36):
		image.set_pixel(0, y, border_color)
		image.set_pixel(35, y, border_color)
	
	# Create texture from image
	var texture = ImageTexture.new()
	texture.set_image(image)
	unit_icon.texture = texture

func _update_header_background_color() -> void:
	"""Team colour now lives in the portrait ring + subtitle; the old header plate
	is hidden. Kept as a no-op-safe hook for callers."""
	if not selected_unit or not unit_header_background:
		return
	unit_header_background.visible = false

func _on_unit_summary_pressed() -> void:
	"""INFO (the unit_info action, default I): open the full-screen [UnitDetailPage] on the
	selected unit. No toggling, no in-sidebar stat block: the page is a single per-battle
	overlay ([method UnitDetailPage.open_for] finds or mounts it) and closes on Esc or its
	own Close button, returning the player to exactly this state -- same selection, same
	staged command. Works for an inspected ENEMY too, because the page only ever reads."""
	if not is_instance_valid(selected_unit):
		return
	UnitDetailPage.open_for(self, selected_unit)


## Old name for [method _on_unit_summary_pressed] (the local sidebar's DETAILS button).
func _on_details_pressed() -> void:
	_on_unit_summary_pressed()


func _update_unit_stats() -> void:
	"""Refresh the live numbers this card shows (the HP row). The full stat table lives
	on the detail page and the compact battle card; kept as a hook for callers."""
	_update_header_hp()

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection - hide actions"""
	if selected_unit == unit:
		# Catch-all: a deselect can arrive mid-targeting (right-click / ui_cancel via
		# the cursor, or the player selecting a different unit). Route it through the
		# single reset so the attack/AoE highlight, SELECT MOVE popup and forecast are
		# always torn down -- otherwise targeting state would outlive the unit and the
		# stale highlight would be stuck with no way to clear it. Idempotent when not
		# targeting.
		_cancel_move_targeting()

		# A deselect can also arrive with a tentative (uncommitted) move still staged
		# -- the player clicked away, selected another unit, or the turn ended. Revert
		# the unit's visual position to its origin so no half-finished move is left on
		# the board. Nothing was committed, so the unit stays fully available.
		_revert_tentative_move()

		selected_unit = null

		# Clear movement range when unit is deselected
		_clear_movement_range()

		_clear_unit_header()
		_hide_panel()

		# Back to IDLE (closes the contextual menu if it was somehow still up).
		_set_state(CommandState.IDLE)

func _clear_movement_range() -> void:
	"""Clear movement range visualization"""
	movement_range_tiles.clear()
	_path_shown = false
	GameEvents.movement_range_cleared.emit()
	# No range means no route to warn about. A tentative move that is being staged right
	# now re-asserts its own warning immediately after clearing the range.
	_set_trap_warning(null)

func _clear_unit_header() -> void:
	"""Clear the unit header information"""
	if unit_name_label:
		unit_name_label.text = "No Unit Selected"
	if unit_type_label:
		unit_type_label.text = ""
	if unit_icon:
		unit_icon.texture = null

func _on_network_action_applied(_action: Dictionary, _result: Dictionary) -> void:
	"""An accepted network action was applied to the board on this peer."""
	if selected_unit != null and not is_instance_valid(selected_unit):
		selected_unit = null
		_awaiting_net_move_unit = null
		_hide_panel()
		return
	if move_selection_panel and move_selection_panel.visible:
		move_selection_panel.update_move_cooldowns()
	_update_actions()
	# Our MOVE landed: open the contextual action menu on the unit (the FE loop's
	# post-move menu), exactly where local play opens it after a staged move.
	var awaited := _awaiting_net_move_unit
	if awaited != null and is_instance_valid(awaited) and awaited == selected_unit \
			and awaited.has_method("can_move") and not awaited.can_move():
		_awaiting_net_move_unit = null
		if _human_may_command(awaited) and _state != CommandState.TARGETING:
			_set_state(CommandState.ACTION_MENU)


func _on_network_intent_rejected(_action: Dictionary, _reason: String) -> void:
	"""The host refused one of our intents (NetToast tells the player why): forget any
	pending post-move menu and redraw from the real state."""
	_awaiting_net_move_unit = null
	if is_instance_valid(selected_unit):
		_update_actions()
		if _human_may_command(selected_unit) and selected_unit.can_move() \
				and _state == CommandState.UNIT_SELECTED:
			_calculate_and_show_movement_range()

func _on_player_turn_changed(player: Player) -> void:
	"""Handle player turn changes"""
	_update_actions()
	# When control is no longer the local human's, drop any lingering movement highlight
	# and revert an uncommitted tentative move, so nothing stale reads as commandable or
	# can be clicked during the enemy's turn. (The commit paths also hard-gate on
	# _human_may_command, so this is the visual half of the same guard.)
	# is_instance_valid, not `!= null`: a freed Unit compares non-null in Godot 4, and this
	# handler runs on every turn change -- including the one right after the selected unit
	# died -- so `!= null` would hand a freed instance to _human_may_command.
	if is_instance_valid(selected_unit) and not _human_may_command(selected_unit):
		if _tentative_active:
			_revert_tentative_move()
		_clear_movement_range()

func _on_game_state_changed(new_state: PlayerManager.GameState) -> void:
	"""Handle game state changes"""
	_update_actions()

# --- Command gating (selection is inspection; commanding is separately gated) ---

func _current_turn_player() -> Player:
	"""The player whose turn it currently is, per the turn system (falling back to
	PlayerManager). Same source of truth _update_actions uses for action gating."""
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		var p = TurnSystemManager.get_active_turn_system().get_current_active_player()
		if p:
			return p
	return PlayerManager.get_current_player() if PlayerManager else null

func _player_is_human(player: Player) -> bool:
	"""True when `player` is human-controlled locally. Single-player/hotseat: not AI.
	Multiplayer: the player is this client. Essential for command gating: during the
	AI's turn the AI IS the current player, so ownership alone is not enough."""
	if player == null:
		return false
	# REPLAY PLAYBACK: the viewer is a SPECTATOR. Every command in a replay comes from the log
	# (through the CommandApplier, exactly as a networked one does), so nobody on the board is
	# locally controllable -- and this predicate is the ONE gate that covers both command paths
	# (_human_may_command ends in it, and End Player Turn calls it directly). Selection, the
	# cursor, the inspection panels and the camera are untouched: watching is still watching.
	if ReplayPlayback.is_playing():
		return false
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		var local_id_raw = GameModeManager.get_local_player_id() if GameModeManager else -1
		var local_id = int(local_id_raw) if local_id_raw is String else local_id_raw
		# player.player_id is statically typed int, so no String coercion needed.
		return int(player.player_id) == local_id
	return not player.is_ai

## True when [param unit] has acted but still owes its one CANTO movement (see the block
## note on [Unit]). Duck-typed so a legacy/mock unit simply answers no; this is the ONE
## place the panel asks, and every canto branch below reads it.
func _unit_has_canto(unit) -> bool:
	return unit != null and is_instance_valid(unit) \
		and unit.has_method("has_canto") and bool(unit.has_canto())

func _human_may_command(unit: Unit) -> bool:
	"""True only when the LOCAL human may issue commands to `unit` this turn: there is
	a current turn player, that player owns the unit, AND that player is human. Any
	living unit can still be SELECTED (inspected) -- this only gates commanding."""
	# Every caller can hand this a unit that died since it was captured (the panel's own
	# selected_unit, a bound button callback, a cycling helper). owns_unit() below raises
	# on a freed instance, and a dead unit is never commandable anyway.
	if unit == null or not is_instance_valid(unit):
		return false
	var current_player := _current_turn_player()
	if current_player == null:
		return false
	if not current_player.owns_unit(unit):
		return false
	return _player_is_human(current_player)

# --- Networked command routing ------------------------------------------------
# In a network match every golden-path action is an INTENT submitted through
# GameModeManager (request_move / request_use_move / request_wait / request_end_turn ->
# NetSession.submit_intent); the host validates it (NetGameRules) and the accepted action
# is applied on every peer, host included, with the per-action commit-reveal RNG. Local
# play (single player / hotseat / local versus) falls through UNCHANGED -- every routing
# branch is gated on _is_networked_match(), which is false off the wire.
#
# TENTATIVE-MOVE RECONCILIATION: when a staged tentative move is finalized in a network
# match we REVERT the local tentative visual first, then submit a MOVE for its
# destination. The accepted MOVE then applies origin->dest on every peer symmetrically
# (correct unit_moved from/to, correct tile ON_EXIT/ON_ENTER), and the local board is
# never left mutated outside an accepted action, so the host's digests stay identical.

func _is_networked_match() -> bool:
	"""True only in a live network match -- the single gate for routing a command as an
	intent instead of executing it locally."""
	return GameModeManager != null and GameModeManager.is_multiplayer_active()

func _net_submit_pending_move(unit) -> void:
	"""If a tentative move is staged for [param unit], revert its local visual and submit
	the destination as a MOVE intent (see the reconciliation note above). No-op when no
	tentative move is staged."""
	if not _tentative_active or _tentative_unit != unit:
		return
	var dest: Vector3i = _tentative_dest_cell
	_revert_tentative_move()
	GameModeManager.request_move(unit, dest)

func _update_actions() -> void:
	"""Update available actions based on selected unit and game state"""
	# selected_unit outlives the unit it points at: it is set on selection and only
	# cleared on deselection, so when the selected unit DIES this still holds a freed
	# reference -- and `not selected_unit` is false for one. Everything below
	# (owns_unit, can_move, can_act, get_display_name) raises on it, once per UI refresh,
	# which is the single loudest source of debugger spam in a real match. Drop the stale
	# reference here so the rest of the panel's ~50 dereferences are unreachable with it.
	if not is_instance_valid(selected_unit):
		selected_unit = null
		return
	if not PlayerManager:
		return
	
	# Use the turn system's current player as the source of truth for "whose turn
	# it is" — PlayerManager's current-player index and player ACTIVE state can
	# drift out of sync with the turn system, which is what movement validation
	# (can_unit_act) actually uses. Falling back to PlayerManager if no system.
	var current_player: Player = null
	if TurnSystemManager and TurnSystemManager.has_active_turn_system():
		current_player = TurnSystemManager.get_active_turn_system().get_current_active_player()
	if not current_player:
		current_player = PlayerManager.get_current_player()
	var game_active = PlayerManager.current_game_state == PlayerManager.GameState.IN_PROGRESS
	# Commanding is gated by _human_may_command: current turn player owns the unit AND
	# is human-controlled. Selecting an enemy / AI unit still shows the panel (read-only
	# inspection), but every command button below stays disabled for it. The turn
	# system's can_unit_act handles the "has this unit already acted" gating separately.
	var can_control = _human_may_command(selected_unit)
	
	# Determine action availability based on turn system
	var can_perform_unit_actions = false
	var action_restriction_reason = ""
	
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		
		if turn_system is TraditionalTurnSystem:
			# Traditional mode: use existing logic
			can_perform_unit_actions = turn_system.can_unit_act(selected_unit)
			
			if not can_perform_unit_actions:
				var trad_system = turn_system as TraditionalTurnSystem
				if selected_unit in trad_system.get_units_that_acted():
					action_restriction_reason = "already acted this turn"
				elif not current_player.owns_unit(selected_unit):
					action_restriction_reason = "not your unit"
				else:
					action_restriction_reason = "cannot act"
		
		elif turn_system is SpeedFirstTurnSystem:
			# Speed First mode: only current acting unit can perform actions
			var speed_system = turn_system as SpeedFirstTurnSystem
			var current_acting_unit = speed_system.get_current_acting_unit()
			
			if selected_unit == current_acting_unit:
				can_perform_unit_actions = speed_system.can_unit_act(selected_unit)
				if not can_perform_unit_actions:
					if selected_unit in speed_system.get_units_that_acted_this_round():
						action_restriction_reason = "already acted this round"
					else:
						action_restriction_reason = "cannot act"
			else:
				can_perform_unit_actions = false
				if selected_unit in speed_system.get_units_that_acted_this_round():
					action_restriction_reason = "already acted this round"
				else:
					action_restriction_reason = "not this unit's turn"
		else:
			can_perform_unit_actions = turn_system.can_unit_act(selected_unit)
			if not can_perform_unit_actions:
				action_restriction_reason = "not your turn"
	else:
		# No turn system active
		can_perform_unit_actions = can_control
		if not can_perform_unit_actions:
			action_restriction_reason = "no turn system active"
	
	# Update Move button - only available if unit can perform actions. Also disabled
	# while a tentative move is staged: the unit has already moved (pending confirm),
	# so re-entering movement would let it move twice. It reverts to available if the
	# tentative move is cancelled.
	# FE command list: Move / Skills / Wait / Info / Cancel. Each row shows its key
	# (or pad) glyph from InputActions; an unavailable command shows WHY instead.
	var reason_note := "N/A"
	if not can_control:
		reason_note = "Not yours" if not (current_player and current_player.owns_unit(selected_unit)) else "Not your turn"
	elif action_restriction_reason == "not this unit's turn":
		reason_note = "Not its turn"
	elif action_restriction_reason in ["already acted this round", "already acted this turn"]:
		reason_note = "Done"

	# Move is also disabled while a tentative move is staged: the unit has already
	# moved (pending confirm), so re-entering movement would let it move twice. It
	# reverts to available if the tentative move is cancelled.
	if move_button:
		var can_move = can_control and can_perform_unit_actions and selected_unit.can_move() and not _tentative_active
		move_button.disabled = not can_move
		if can_move:
			_set_command(move_button, "Move", InputActions.UNIT_MOVE)
		elif can_control and can_perform_unit_actions and (_tentative_active or not selected_unit.can_move()):
			_set_command(move_button, "Move", &"", "Moved")
		else:
			_set_command(move_button, "Move", &"", reason_note)

	# Update Moves (action) button - available if the unit still has its action.
	if moves_button:
		moves_button.disabled = not (can_control and can_perform_unit_actions and selected_unit.can_act())

	# WAIT: ends THIS unit's action (the old "End Turn (E)" label read like ending
	# the whole phase -- that lives in the Map Menu now).
	if end_unit_turn_button:
		var can_end_unit_turn = can_control and can_perform_unit_actions and selected_unit.can_act()
		end_unit_turn_button.disabled = not can_end_unit_turn
		if can_end_unit_turn:
			_set_command(end_unit_turn_button, "Wait", InputActions.WAIT)
		else:
			_set_command(end_unit_turn_button, "Wait", &"", reason_note)

	# End Player Turn is not part of the per-unit command list any more (Map Menu >
	# End Turn, the end_turn action, or the touch End Turn row below). The hidden button
	# keeps its state in sync for any caller that still reads it.
	var can_end_player_turn: bool = game_active and _player_is_human(current_player)
	if end_player_turn_button:
		end_player_turn_button.disabled = not can_end_player_turn
		end_player_turn_button.visible = false
	if end_turn_row_button:
		end_turn_row_button.disabled = not can_end_player_turn
	_sync_danger_zones_button()

	# INFO is always available while a unit is selected -- reading a unit's page is not a
	# command, so it is never gated on whose turn it is or whether the unit can act.
	if unit_summary_button:
		unit_summary_button.disabled = false
		_set_command(unit_summary_button, "Info", InputActions.UNIT_INFO)

	# Cancel is always available when a unit is selected.
	if cancel_button:
		cancel_button.disabled = false
		_set_command(cancel_button, "Cancel", InputActions.CANCEL)

	# Update Moves button availability
	_update_moves_button_availability()

func _on_move_pressed() -> void:
	"""Handle Move button press - enter movement mode"""
	if not selected_unit:
		return

	# Handler-level command guard: keyboard shortcut (KEY_M) bypasses the disabled
	# button, so re-check command permission here before acting on an enemy / AI unit.
	if not _human_may_command(selected_unit):
		return

	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		if turn_system.validate_turn_action(selected_unit, "move"):
			_enter_movement_mode()
	else:
		_enter_movement_mode()

func _on_end_unit_turn_pressed() -> void:
	"""Handle End Unit Turn button press - only ends this unit's turn"""
	if not selected_unit:
		return

	# Network match: WAIT is an intent (host-validated, applied on every peer through
	# NetGameRules, which refreshes this panel). A staged move goes first as its own MOVE
	# intent (see _net_submit_pending_move); the local UI just closes the command loop.
	if _is_networked_match():
		if not _human_may_command(selected_unit) or not GameModeManager.is_my_turn():
			return
		var unit := selected_unit
		_cancel_move_targeting()
		_net_submit_pending_move(unit)
		GameModeManager.request_wait(unit)
		_finish_command(unit)
		return

	# Handler-level command guard: the KEY_E shortcut bypasses the disabled button and
	# the local path calls mark_unit_acted(selected_unit) unchecked, which would let the
	# human end an enemy / AI unit's turn. Re-check command permission here.
	if not _human_may_command(selected_unit):
		return

	# WAIT: ending the unit's turn is the "commit move, take no action" branch of the
	# FE loop. Drop any half-aimed move UI, then commit the tentative move (if one is
	# staged) so the unit stays where it previewed before its turn ends.
	_cancel_move_targeting()
	# CANTO (see _on_action_menu_wait_chosen): the unit has no action left to spend, so
	# ending its turn means giving up the movement it still owed. Committing a staged step
	# already does that; finish_canto is idempotent and covers the un-staged case. Both run
	# BEFORE the mark_unit_acted call below, which for a canto unit is a no-op (the turn
	# system already holds it in its acted list).
	var canto_end: bool = _unit_has_canto(selected_unit)
	_commit_tentative_move()
	if canto_end and selected_unit.has_method("finish_canto"):
		selected_unit.finish_canto("wait")

	# LOCAL COMMAND RNG: begin this WAIT before it resolves, so whatever it sets off (the turn
	# ending, the next turn's ticks) rolls from the generator its replay will re-install.
	NetSessionNode.begin_local_command_rng()
	ReplayRecorder.note_wait_unit(selected_unit)  # REPLAY: solo WAIT_UNIT (End Unit Turn)

	# Remember who is acting so _finish_command can tell whether Speed First has already
	# advanced selection to the next unit (see _finish_command).
	var acted_unit := selected_unit

	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()

		if turn_system is TraditionalTurnSystem:
			(turn_system as TraditionalTurnSystem).mark_unit_acted(selected_unit)
		elif turn_system is SpeedFirstTurnSystem:
			(turn_system as SpeedFirstTurnSystem).mark_unit_acted(selected_unit)

		# Emit action completed signal
		GameEvents.unit_action_completed.emit(selected_unit, "end_turn")

		# Force update unit visuals immediately
		var tree = get_tree()
		var visual_manager = null
		if tree != null and tree.current_scene != null:
			visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
		if visual_manager:
			visual_manager.update_all_unit_visuals()

	# Update actions to reflect the unit has acted
	_update_actions()

	# Close the command loop (also tears down the contextual action menu if it was up).
	_finish_command(acted_unit)

func _on_end_player_turn_pressed() -> void:
	"""End Player Turn from a button (the touch End Turn row / the legacy hidden button):
	ask through the Map Menu's End Turn confirm (the same one the end_turn action opens)
	so there is exactly ONE confirm. Without a Map Menu (bare harness) fall back to the
	local confirm dialog below."""
	var mm := _map_menu()
	if mm != null and mm.has_method("request_end_turn"):
		mm.request_end_turn()
		return
	_end_player_turn(false)


func _map_menu() -> Node:
	"""The battle's MapMenu (owned by the UILayoutManager this panel lives under)."""
	var n: Node = get_parent()
	while n != null:
		if "map_menu" in n:
			var mm = n.get("map_menu")
			if mm != null and is_instance_valid(mm):
				return mm
		n = n.get_parent()
	return null


func _end_player_turn(confirmed: bool) -> void:
	"""The guarded end-player-turn path: local-human only (never the AI's / opponent's
	turn), a network intent online, and -- unless [param confirmed] (the Map Menu already
	asked) -- a confirm while units can still act."""
	if not PlayerManager:
		return

	var current_player = PlayerManager.get_current_player()
	if not current_player:
		return

	# Network match: END_TURN is an intent (host-validated, applied on every peer). The
	# turn only advances when the accepted action applies.
	if _is_networked_match():
		if not _player_is_human(_current_turn_player()) or not GameModeManager.is_my_turn():
			return
		_cancel_move_targeting()
		GameModeManager.request_end_turn()
		return

	# Handler-level command guard: the KEY_P shortcut bypasses the disabled button.
	# Only end the player turn when the current turn player is human-controlled (never
	# during the AI's turn).
	if not _player_is_human(_current_turn_player()):
		return

	# CONFIRMATION: if the player still has un-acted units, warn before throwing away
	# their turns. When everyone has already acted there is nothing to lose (the turn
	# systems auto-end anyway), so end immediately with no prompt.
	var unacted := _count_unacted_friendly_units()
	if unacted > 0 and not confirmed:
		_prompt_end_player_turn(unacted)
		return

	_do_end_player_turn()

func _count_unacted_friendly_units() -> int:
	"""How many of the current player's units still have their turn (can act)."""
	var player := _current_turn_player()
	if player == null:
		return 0
	return player.get_units_that_can_act().size()

func _prompt_end_player_turn(unacted_count: int) -> void:
	"""Show a small confirm dialog before ending the turn with units still to act. ESC /
	Cancel dismisses; Confirm ends the turn. The dialog is created lazily and reused."""
	var dialog := _ensure_end_turn_dialog()
	var noun := "unit" if unacted_count == 1 else "units"
	dialog.dialog_text = "%d %s haven't acted -- end turn?" % [unacted_count, noun]
	dialog.popup_centered()

func _ensure_end_turn_dialog() -> ConfirmationDialog:
	var existing := get_node_or_null("EndTurnConfirmDialog")
	if existing is ConfirmationDialog:
		return existing as ConfirmationDialog
	var dialog := ConfirmationDialog.new()
	dialog.name = "EndTurnConfirmDialog"
	dialog.theme = MenuTheme.build()
	dialog.title = "End Player Turn"
	dialog.ok_button_text = "Confirm"
	# ConfirmationDialog exposes its cancel button via get_cancel_button() (no
	# cancel_button_text property in this Godot version); relabel it directly.
	var cancel_btn := dialog.get_cancel_button()
	if cancel_btn:
		cancel_btn.text = "Cancel"
	dialog.confirmed.connect(_do_end_player_turn)
	add_child(dialog)
	return dialog

func _do_end_player_turn() -> void:
	"""The actual end-player-turn path (previously inline in the button handler)."""
	# REPLAY: solo END_TURN, recorded BEFORE the turn system advances so the entry is stamped
	# with the turn it ended (the networked branch records apply-side instead).
	var ending_player := _current_turn_player()
	if ending_player != null:
		# LOCAL COMMAND RNG: the next turn's opening ticks roll from this END_TURN's generator,
		# the one its replay re-installs (see NetSessionNode.begin_local_command).
		NetSessionNode.begin_local_command_rng()
		ReplayRecorder.note_end_turn(int(ending_player.player_id))

	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()

		# End the player's turn THROUGH THE TURN SYSTEM so it actually advances to the
		# next player (and, in single-player, reaches the AI player so BotTurnDriver can
		# act). Previously this looked for a non-existent end_player_turn() method and
		# fell back to PlayerManager.end_current_player_turn(), which advanced
		# PlayerManager WITHOUT advancing the turn system -- leaving the two desynced and
		# the turn system stuck on the current player (so the banner froze and the AI
		# never got a turn). Same end-turn path MapMenu's End Turn uses.
		# end_turn_manually() already reports through its RETURN VALUE, and "you cannot end
		# the turn right now" (double-click, an action still resolving, the wrong phase) is
		# an ordinary UI outcome -- not a fault. Ignoring the false is the correct handling;
		# the button simply does nothing, which is what the player already sees.
		if turn_system is TraditionalTurnSystem:
			(turn_system as TraditionalTurnSystem).end_turn_manually()
		elif turn_system is SpeedFirstTurnSystem:
			(turn_system as SpeedFirstTurnSystem).end_turn_manually()
		elif turn_system.has_method("end_player_turn"):
			turn_system.end_player_turn()
		else:
			# Last-resort fallback: use PlayerManager directly.
			PlayerManager.end_current_player_turn()
	else:
		# Fallback: use PlayerManager directly
		PlayerManager.end_current_player_turn()

# Add mouse event debugging
func _gui_input(_event: InputEvent) -> void:
	pass

func _on_end_unit_turn_button_input(_event: InputEvent) -> void:
	pass

func _on_cancel_pressed() -> void:
	"""Handle Cancel button press (also C/ESC via _input) - back out of whatever
	interaction is active. Move-targeting is checked FIRST: while aiming a move the
	SELECT MOVE popup has already hidden itself, so without this branch a Cancel here
	would fall through to unit_deselected and drop the unit WITHOUT clearing the
	targeting highlight/forecast -- leaving the stale on-board selection stuck (the
	reported bug, most visible on self/ally/tile/no-valid-target moves that the
	player backs out of instead of committing)."""
	# Staged Fire-Emblem back-out, one level per press (ESC / right-click / this
	# button all funnel here). Precedence, most-nested first:
	#   1. SELECT MOVE popup open (choosing a move, pre-targeting) -> just close it.
	#   2. Aiming a move (targeting) -> drop the forecast + aim highlights, stay on
	#      the tentative position with the action menu (first ESC cancels targeting).
	#   3. Tentative move staged -> revert the unit to its origin cell, restore full
	#      availability, and re-show its movement range (second ESC undoes the move).
	#   4. Legacy movement mode -> exit it.
	#   5. Otherwise -> deselect the unit.
	# If the SELECT MOVE popup already consumed this same ESC by closing itself
	# (MoveSelectionPanel ran first this frame), stop -- do not back out further.
	if Engine.get_process_frames() == _popup_closed_frame:
		return

	# The legacy centered SELECT MOVE modal (fallback path only) still takes precedence
	# when it is open, so its BACK and this cancel agree.
	if move_selection_panel and move_selection_panel.visible:
		move_selection_panel.hide()
		return

	# Golden path: back out exactly one state per press (see cancel_target_state()).
	match _state:
		CommandState.TARGETING:
			# First ESC drops the aim and returns to the action menu (NOT a full
			# deselect) -- stay on the tentative position so the player can pick again.
			_cancel_move_targeting()
			_set_state(CommandState.ACTION_MENU)
			_update_actions()
			return
		CommandState.ACTION_MENU:
			# Cancel row behaviour: revert the tentative move, back to UNIT_SELECTED.
			_on_action_menu_cancel_chosen()
			return
		CommandState.UNIT_SELECTED:
			# Deselect (through the cursor so its selection state clears too).
			_finish_command()
			return

	# IDLE / legacy fallbacks (non-character or no-board units use movement_mode and
	# never enter the enum's golden path; also covers any stray flag state).
	if is_targeting_move():
		_cancel_move_targeting()
		_update_actions()
	elif _tentative_active:
		_revert_tentative_move()
		# Unit is fully available again: re-show its movement range and refresh actions.
		_calculate_and_show_movement_range()
		_update_actions()
	elif movement_mode:
		_exit_movement_mode()
	elif selected_unit:
		GameEvents.unit_deselected.emit(selected_unit)

func request_end_player_turn() -> void:
	"""Public End Turn entry (the Map Menu, AFTER its own confirm). Same guarded path as
	the button -- local-human only, and a network match submits the END_TURN intent --
	minus a second confirm."""
	_end_player_turn(true)


func request_cancel() -> void:
	"""Public entry point for an external cancel request (the board cursor's
	right-click back-out). Only acts while a unit is selected; routes through the
	same staged FE back-out as ESC / the Cancel button."""
	if selected_unit:
		_on_cancel_pressed()


func has_active_interaction() -> bool:
	"""True when there is a staged interaction the panel can back out of (move
	popup open, aiming a move, a tentative move, movement mode, or a selection).
	Lets callers decide whether to route a cancel here rather than plain deselect."""
	return (
		(move_selection_panel != null and move_selection_panel.visible)
		or is_targeting_move()
		or _tentative_active
		or movement_mode
		or selected_unit != null
		or _state != CommandState.IDLE
	)

# --- State machine -----------------------------------------------------------

## The ONE place `_state` changes. Keeps the contextual action menu's visibility in
## lockstep with the enum (open only in ACTION_MENU) so no caller can leave a stale
## menu up. Game-state side effects (staging/committing/reverting a move, showing the
## range) stay with the callers -- this only owns the enum + the menu widget.
func _set_state(new_state: int) -> void:
	_state = new_state
	if action_menu:
		if new_state == CommandState.ACTION_MENU:
			if selected_unit:
				action_menu.open_for_unit(selected_unit, _human_may_command(selected_unit))
		else:
			action_menu.close()

func get_command_state() -> int:
	"""Current command-machine state (for the cursor's routing / tests)."""
	return _state

## Pure back-out transition table (right-click / ESC / Cancel). Static + side-effect
## free so it can be unit-tested without instancing the scene-coupled panel: given a
## state, returns the state one cancel press should land in.
static func cancel_target_state(state: int) -> int:
	match state:
		CommandState.TARGETING:
			return CommandState.ACTION_MENU
		CommandState.ACTION_MENU:
			return CommandState.UNIT_SELECTED
		CommandState.UNIT_SELECTED:
			return CommandState.IDLE
		_:
			return CommandState.IDLE

## Pure forward transition table (the golden path). Mirror of cancel_target_state so a
## test can walk IDLE -> UNIT_SELECTED -> ACTION_MENU -> TARGETING and back down again.
static func forward_state(state: int) -> int:
	match state:
		CommandState.IDLE:
			return CommandState.UNIT_SELECTED
		CommandState.UNIT_SELECTED:
			return CommandState.ACTION_MENU
		CommandState.ACTION_MENU:
			return CommandState.TARGETING
		_:
			return state


func _show_panel() -> void:
	"""Show the actions panel"""
	visible = true
	modulate.a = 1.0
	
	# Force a layout update. The panel can be freed during the awaited frame (scene change,
	# or the whole HUD torn down on game over), so re-check before touching `self`.
	await get_tree().process_frame
	if not is_inside_tree():
		return

	# Try to resize to fit content
	_try_resize_to_content()

func _try_resize_to_content() -> void:
	"""Attempt to resize the panel to fit its content"""
	if not content_container:
		return
	
	# Get the minimum size needed for content
	var content_min_size = content_container.get_combined_minimum_size()
	
	# Add margin container padding
	if margin_container:
		var margin_top = margin_container.get_theme_constant("margin_top")
		var margin_bottom = margin_container.get_theme_constant("margin_bottom")

		# HEIGHT ONLY: this panel lives in the RightSidebar VBoxContainer with
		# size_flags_horizontal = EXPAND_FILL, so the sidebar (min width 220) drives
		# its WIDTH. Forcing custom_minimum_size.x from content -- which a long unit
		# name could inflate -- used to widen the whole sidebar and shove it over the
		# game area. We now only grow the height to fit the content and let the
		# container own the width; clip_text on the header labels keeps names in bounds.
		var needed_height: float = content_min_size.y + float(margin_top) + float(margin_bottom)
		custom_minimum_size.y = needed_height

		# (Dropped a trailing `await get_tree().process_frame` here: nothing followed it, so
		# it bought no layout -- it only made this a coroutine that could resume on a freed
		# panel and log "Resumed function ... after await, but the class instance is gone".
		# Setting custom_minimum_size already queues the layout pass.)

func _hide_panel() -> void:
	"""Hide the actions panel"""
	visible = false

# Public interface
func get_selected_unit() -> Unit:
	"""Get the currently selected unit"""
	return selected_unit

func is_showing_actions_for_unit(unit: Unit) -> bool:
	"""Check if panel is showing actions for specific unit"""
	return selected_unit == unit and visible

# Keyboard / gamepad shortcuts (named actions -- see InputActions).
func _input(event: InputEvent) -> void:
	# A full-screen overlay (Settings, ...) owns input while it is open.
	if InputActions.gameplay_input_blocked(get_tree()):
		return

	# Developer helpers: debug builds only, Ctrl+Shift held (never a plain key --
	# F1 used to end the selected unit's turn during normal play).
	if InputActions.is_debug_hotkey(event):
		match (event as InputEventKey).keycode:
			KEY_F1:
				_on_end_unit_turn_pressed()
			KEY_F2:
				_show_panel()
			KEY_F3:
				_hide_panel()
			KEY_F4:
				_test_manual_unit_selection()
			KEY_F5:
				_test_movement_range_calculation_direct()
		return

	# CANCEL (Esc / B / right-click via the cursor): the gate is has_active_interaction() --
	# the SAME predicate UILayoutManager (pause menu) and MapMenu (map menu) read to decide
	# whether Escape should instead open their overlay. Sharing one predicate makes the
	# ordering airtight: while anything is staged we back out ONE stage here and consume;
	# once the command state is IDLE this does nothing and the press falls through.
	if event.is_action_pressed(InputActions.CANCEL):
		if has_active_interaction():
			_on_cancel_pressed()
			# Consume cancel so the board cursor's own cancel handler does not ALSO fire
			# and deselect the unit -- that would collapse the staged FE back-out (drop
			# targeting -> revert tentative -> deselect) into a single press. This
			# panel's _input runs before the cursor's _unhandled_input, so marking it
			# handled keeps the staging intact.
			get_viewport().set_input_as_handled()
		return

	# Action shortcuts (named, rebindable actions -- see InputActions). Only while the
	# panel is showing a selected unit. Elsewhere, ONE owner per action: end_turn is the
	# MapMenu's (its End Turn confirm), cycle_next / cycle_prev the board cursor's, and
	# danger_zone the DangerZoneOverlay's -- so one press can never fire twice.
	if not (visible and selected_unit):
		return
	if event.is_action_pressed(InputActions.UNIT_MOVE):
		if movement_mode:
			_exit_movement_mode()
		else:
			_on_move_pressed()
	elif event.is_action_pressed(InputActions.WAIT):
		if not movement_mode:
			_on_end_unit_turn_pressed()
	elif event.is_action_pressed(InputActions.UNIT_INFO):
		if not movement_mode:
			_on_unit_summary_pressed()

func _test_manual_unit_selection() -> void:
	"""Test manual unit selection for debugging"""
	# Find a unit to test with
	var tree = get_tree()
	if tree == null:
		return
	var scene_root = tree.current_scene
	if scene_root == null:
		return
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				var world_pos = child.global_position
				_on_unit_selected(child, world_pos)
				return

func _test_movement_range_calculation_direct() -> void:
	"""Test movement range calculation directly"""
	# Find a unit to test with
	var tree = get_tree()
	if tree == null:
		return
	var scene_root = tree.current_scene
	if scene_root == null:
		return
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				# Set this as selected unit temporarily
				selected_unit = child

				# Test movement range calculation
				_calculate_and_show_movement_range()

				# Wait 3 seconds then clear
				await get_tree().create_timer(3.0).timeout
				_clear_movement_range()
				selected_unit = null
				return

# Movement system implementation
func _enter_movement_mode() -> void:
	"""Enter movement mode - show movement range and wait for destination selection"""
	if not selected_unit:
		return

	# A tentative move is already staged (unit visually at its destination, awaiting
	# confirm/cancel). Re-entering movement here would let it move a second time, so
	# block until the tentative move is confirmed or cancelled.
	if _tentative_active:
		return

	# A unit that already moved this turn cannot move again.
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		return

	movement_mode = true

	# Calculate and show movement range
	_calculate_and_show_movement_range()

	# Update UI to show movement mode
	_update_movement_ui()

func _exit_movement_mode() -> void:
	"""Exit movement mode and return to normal selection"""
	movement_mode = false
	movement_range_tiles.clear()
	
	# Clear movement range visualization
	GameEvents.movement_range_cleared.emit()
	
	# Update UI back to normal
	_update_actions()

func _calculate_and_show_movement_range() -> void:
	"""Calculate movement range and show visual indicators"""
	if not selected_unit:
		return

	# Inspection-only units (enemy / AI, or not this player's turn) show no range.
	if not _human_may_command(selected_unit):
		_clear_movement_range()
		return

	# A unit that has already moved this turn shows NO movement range and cannot
	# move again (until reset at its next turn start, or an extra-move grant). This
	# gates BOTH the select-time tactical highlight (_show_movement_range_on_selection)
	# and movement mode (_enter_movement_mode), since both funnel through here.
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		_clear_movement_range()
		return

	# Character-backed units route the range through MovementResolver + the shared
	# BoardAdapter (CombatServices.board()). Non-character units, or the case where
	# no live board exists yet, fall through to the legacy BFS below.
	if _try_show_movement_range_via_resolver():
		return

	# Get unit's current position
	var grid = preload("res://board/Grid.tres")
	var unit_world_pos = selected_unit.global_position
	var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)

	# Get movement range from unit
	var movement_range = selected_unit.get_movement_range()

	if movement_range <= 0:
		return

	# Calculate reachable tiles using BFS (similar to board.gd logic)
	movement_range_tiles = _calculate_reachable_tiles(unit_grid_pos, movement_range, grid)

	if movement_range_tiles.size() == 0:
		return

	# Emit event to show movement range visually
	GameEvents.movement_range_calculated.emit(movement_range_tiles)

# --- MovementResolver / BoardAdapter integration (character-backed units) ----

## Display-only movement range for an INSPECTED enemy/AI unit: runs the same
## reachable-cell flood the player's own units use and publishes it to the visualizer
## (the blue tiles), but deliberately leaves movement_range_tiles EMPTY so no click can
## treat those cells as a legal move -- you can see where the enemy could go, not send it.
func _show_inspect_movement_range() -> void:
	if selected_unit == null or not selected_unit.has_character():
		_clear_movement_range()
		return
	var board = CombatServices.board()
	var profile = selected_unit.get_movement_profile()
	if board == null or profile == null:
		_clear_movement_range()
		return
	var origin: Vector3i = board.cell_of(selected_unit)
	var cells: Array[Vector3i] = MovementResolver.new().reachable_cells(origin, profile, BoardSnapshot.of(board), selected_unit)
	# Visual only -- the move-target set stays empty so the enemy can never be commanded.
	movement_range_tiles = []
	_range_resolver = null
	# Include its own cell (FE shows the inspected unit standing in its blue range).
	var shown: Array[Vector3i] = [origin]
	shown.append_array(cells)
	GameEvents.movement_range_calculated.emit(_cells_to_grid_tiles(shown))
	# FE threat read: the red cells it could strike from anywhere it can reach.
	_emit_attack_fringe(origin, cells, board)


func _try_show_movement_range_via_resolver() -> bool:
	"""Compute + publish the movement range through MovementResolver on the shared
	BoardAdapter. Returns true when it handled the range (so the caller must not run
	the legacy BFS); returns false to signal a fallback (non-character unit, no live
	board, or no movement profile)."""
	if not selected_unit or not selected_unit.has_character():
		return false

	var board = CombatServices.board()
	if board == null:
		return false

	var profile = selected_unit.get_movement_profile()
	if profile == null:
		# Character present but no usable profile yet -> let the BFS fallback run.
		return false

	# origin cell (Vector3i(col, row, floor)) straight from the board.
	var origin: Vector3i = board.cell_of(selected_unit)
	# Pass the unit so a multi-cell unit (e.g. a 2x2 boss) only gets cells where its
	# WHOLE footprint fits. Omitting it would resolve every unit as 1x1. The resolver is
	# kept: its path_to() drives the path arrow and the walk animation.
	_range_resolver = MovementResolver.new()
	_range_origin = origin
	# BoardSnapshot: occupancy indexed once instead of walking every unit per step.
	var cells: Array[Vector3i] = _range_resolver.reachable_cells(origin, profile, BoardSnapshot.of(board), selected_unit)

	# Convert each cell into the Vector3(col, floor, row) grid-coord form the
	# visualizer + GameEvents.movement_range_calculated + downstream validation expect.
	movement_range_tiles = _cells_to_grid_tiles(cells)

	# Keep the same highlight flow: emit the calculated range for the visualizer.
	GameEvents.movement_range_calculated.emit(movement_range_tiles)
	_path_shown = false
	# FE red attack fringe around the blue range.
	_emit_attack_fringe(origin, cells, board)
	# The cursor may already rest on a reachable cell (e.g. re-shown after an undo).
	_refresh_path_preview(_last_cursor_tile)
	return true


func _emit_attack_fringe(origin: Vector3i, reachable: Array[Vector3i], board) -> void:
	"""Publish the red attack fringe for selected_unit: every cell its offensive moves
	could hit from its own cell or any reachable one, minus those cells (ThreatResolver)."""
	if selected_unit == null or board == null:
		return
	var stands: Array = [origin]
	stands.append_array(reachable)
	var fringe := ThreatResolver.fringe_from(stands, selected_unit, board)
	_fringe_grid = _cells_to_grid_vec3(fringe)
	GameEvents.attack_fringe_calculated.emit(_fringe_grid)


func _refresh_path_preview(grid_pos: Vector3) -> void:
	"""FE path arrow: while the selected (commandable) unit's blue range is up, draw
	its route to the hovered cell (MovementResolver.path_to of the range's own flood).
	Hidden off-range, on the unit itself, while aiming, or once a move is staged."""
	var route: Array = []
	if selected_unit != null and _range_resolver != null and not movement_range_tiles.is_empty() \
			and not is_targeting_move() and not _tentative_active:
		var board = CombatServices.board()
		if board != null and board.cell_of(selected_unit) == _range_origin and _is_grid_pos_in_range(grid_pos):
			route = _cells_to_grid_vec3(_range_resolver.path_to(Cells.from_grid(grid_pos)))
	if route.size() < 2:
		if _path_shown:
			_path_shown = false
			GameEvents.path_preview_updated.emit([])
		return
	_path_shown = true
	GameEvents.path_preview_updated.emit(route)


func _cells_to_grid_tiles(cells: Array[Vector3i]) -> Array[Vector3]:
	"""Vector3i(col, row, floor) cells -> Vector3(col, floor, row) grid coords used
	everywhere downstream (movement_range_tiles, the visualizer, GameEvents)."""
	var out: Array[Vector3] = []
	for cell in cells:
		out.append(Cells.to_grid(cell))
	return out


func _grid_tile_to_cell(grid_pos: Vector3) -> Vector3i:
	"""Vector3(col, floor, row) grid coord -> Vector3i(col, row, floor) board cell."""
	return Cells.from_grid(grid_pos)


func _is_grid_pos_in_range(grid_pos: Vector3) -> bool:
	"""True when grid_pos matches a tile in the current reachable set (which, for
	character-backed units, is the MovementResolver output)."""
	for tile in movement_range_tiles:
		if abs(tile.x - grid_pos.x) < 0.1 and abs(tile.z - grid_pos.z) < 0.1 and abs(tile.y - grid_pos.y) < 0.1:
			return true
	return false


func _try_execute_move_via_board(destination: Vector3) -> bool:
	"""Execute a character-backed unit's move through the shared BoardAdapter while
	preserving the existing tween animation, GameEvents.unit_moved emission, and
	mark_moved() semantics. Returns true when it handled the move (including a
	rejected out-of-range destination); false to fall back to the legacy path."""
	if not selected_unit or not selected_unit.has_character():
		return false

	var board = CombatServices.board()
	if board == null:
		return false

	var dest_cell: Vector3i = _grid_tile_to_cell(destination)

	# Validate the destination is within the reachable set before moving.
	if not _is_grid_pos_in_range(destination):
		return true  # handled (rejected); do NOT fall back to BFS for a character unit

	var old_cell: Vector3i = board.cell_of(selected_unit)

	# Authoritative board move: snaps the unit onto the cell center (preserving its
	# height, lifted/lowered by whole floors). The unit node stays there; UnitAnimator
	# hears unit_moved below and walks the MODEL cell by cell along the route.
	board.move_unit(selected_unit, dest_cell)

	# unit_moved contract: Vector3(col, floor, row) grid coords.
	var old_grid_pos := Cells.to_grid(old_cell)
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)

	# mark_moved() semantics: consumes the move but NOT the action.
	_complete_movement_action()
	return true


func _calculate_reachable_tiles(start_pos: Vector3, max_distance: int, grid: Grid) -> Array[Vector3]:
	"""Calculate all tiles reachable within movement range using BFS"""
	var reachable: Array[Vector3] = []
	var queue: Array = [{pos = start_pos, distance = 0}]
	var visited: Dictionary = {start_pos: 0}
	
	while not queue.is_empty():
		var current = queue.pop_front()
		var current_pos = current.pos
		var current_distance = current.distance
		
		# Add adjacent tiles if within movement range
		if current_distance < max_distance:
			var directions = [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
			
			for direction in directions:
				var next_pos = current_pos + direction
				
				# Check if tile is valid and not visited
				if grid.is_within_bounds(next_pos) and not visited.has(next_pos):
					# Check if tile is passable (not occupied by another unit)
					if _is_tile_passable(next_pos):
						visited[next_pos] = current_distance + 1
						queue.append({pos = next_pos, distance = current_distance + 1})
						reachable.append(next_pos)

	return reachable

func _is_tile_passable(grid_pos: Vector3) -> bool:
	"""Check if a tile can be entered: impassable TERRAIN blocks it, as does another
	unit standing on it."""
	# Terrain first. A wall or a tree is impassable regardless of occupancy, and
	# this legacy BFS previously only looked at units -- which made solid trees show
	# up as reachable instead of forcing a path around them.
	var cell := Cells.from_grid(grid_pos)
	var tile: TileResource = CombatServices.tile_at(cell)
	if tile != null and not tile.is_tile_passable():
		return false

	# Find all units in scene and check if any occupy this position
	var units = _find_all_units_in_scene()
	var grid = preload("res://board/Grid.tres")
	
	for unit in units:
		if unit == selected_unit:
			continue  # Skip the moving unit itself
		
		var unit_world_pos = unit.global_position
		var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
		
		# Check if positions match (with tolerance)
		if abs(unit_grid_pos.x - grid_pos.x) < 0.1 and abs(unit_grid_pos.z - grid_pos.z) < 0.1:
			return false  # Tile is occupied
	
	return true  # Tile is passable

func _find_all_units_in_scene() -> Array[Unit]:
	"""Find all units in the current scene"""
	var units: Array[Unit] = []
	var tree = get_tree()
	if tree == null:
		return units
	var scene_root = tree.current_scene
	if scene_root == null:
		return units

	# Look for units in Player1 and Player2 nodes
	var player_nodes = ["Map/Player1", "Map/Player2"]
	
	for player_path in player_nodes:
		var player_node = scene_root.get_node_or_null(player_path)
		if player_node:
			for child in player_node.get_children():
				if child is Unit:
					units.append(child)
	
	return units

func _update_movement_ui() -> void:
	"""Update UI to show movement mode state"""
	if move_button:
		move_button.text = "Moving...\n(Select Destination)"
		move_button.disabled = true
	
	if cancel_button:
		cancel_button.text = "Cancel Move (C/ESC)"

func _on_cursor_selected(position: Vector3) -> void:
	"""Handle cursor selection - used for movement destination"""
	# Check if we're in movement mode or if there's a movement range displayed
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			# Let the UnitActionsPanel handle the movement
			unit_actions_panel.handle_movement_destination_selected(position)
			return

	# If not in movement mode, handle normal selection
	if not movement_mode or not selected_unit:
		return

	# Check if position is within movement range
	if position in movement_range_tiles:
		_execute_movement(position)

func _get_unit_actions_panel() -> Node:
	"""Get reference to UnitActionsPanel"""
	var tree = get_tree()
	if tree == null:
		return null
	var scene_root = tree.current_scene
	if scene_root == null:
		return null
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		return ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	return null

func _execute_movement(destination: Vector3) -> void:
	"""Execute the actual unit movement"""
	if not selected_unit:
		return

	# Same hard turn gate as handle_movement_destination_selected: this legacy path must
	# never move a unit the human may not command this turn either.
	if not _human_may_command(selected_unit):
		_clear_movement_range()
		return

	# Network match: never move locally -- submit the intent (see _move_to_destination).
	if _is_networked_match():
		_move_to_destination(destination)
		_exit_movement_mode()
		return

	# Character-backed units route through the shared BoardAdapter (resolver-backed).
	if _try_execute_move_via_board(destination):
		_exit_movement_mode()
		return

	# FALLBACK: legacy grid-based movement for non-character units / no live board.
	# Get grid for position calculations
	var grid = preload("res://board/Grid.tres")
	var old_world_pos = selected_unit.global_position
	var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)

	# Calculate new world position
	var new_world_pos = grid.calculate_map_position(destination)
	# Preserve the unit's original Y height (units are at Y=1.5)
	new_world_pos.y = selected_unit.global_position.y

	# Animate the unit movement
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)

	# Emit movement event
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)

	# Mark unit as having acted
	_complete_movement_action()

	# Exit movement mode
	_exit_movement_mode()

func _animate_unit_movement(unit: Unit, from_pos: Vector3, to_pos: Vector3) -> void:
	"""Animate unit movement with a smooth tween"""
	# is_inside_tree as well as validity: the tween drives the UNIT's global_position, so
	# it must be bound to the unit (a tween created on the PANEL outlives the unit and
	# keeps writing to a freed object when the unit dies mid-slide, e.g. to a trap).
	if not is_instance_valid(unit) or not unit.is_inside_tree():
		return

	# One slide at a time. Two overlapping tweens on the same `global_position` fight each
	# other, and a second move started inside the 0.5s window used to do exactly that.
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	var tween = unit.create_tween()
	_move_tween = tween
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUART)

	# Animate the movement over 0.5 seconds
	tween.tween_property(unit, "global_position", to_pos, 0.5)

	# Optional: Add a small bounce effect
	tween.tween_callback(_on_movement_animation_complete.bind(unit))

func _complete_movement_action() -> void:
	"""Complete the movement action and update turn system"""
	if not selected_unit:
		return

	# Moving consumes only the unit's MOVE for this turn, not its action: the unit
	# can still attack / use a move, or End Turn. Re-moving is blocked by can_move()
	# until an ability or move effect grants extra movement.
	selected_unit.mark_moved()
	
	# Force update unit visuals
	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()

func _on_movement_animation_complete(_unit: Unit) -> void:
	"""Called when movement animation finishes"""
	pass

# tactical style movement handling
func is_showing_movement_range() -> bool:
	"""Check if movement range is currently displayed"""
	return movement_range_tiles.size() > 0

func handle_movement_destination_selected(destination: Vector3) -> void:
	"""Handle selection of a movement destination (tactical style)"""
	if not selected_unit:
		return

	# HARD TURN GATE: never move a unit the local human may not command RIGHT NOW -- an
	# enemy/AI unit, or ANY unit while it is not the human's turn. A movement range shown
	# for your own unit before control passed to the enemy could otherwise still be clicked
	# to slide it DURING the enemy turn. _human_may_command re-checks the live current
	# player, so a stale highlight can never commit a move.
	if not _human_may_command(selected_unit):
		_clear_movement_range()
		return

	# Hard gate: a unit that already moved this turn cannot move again, even if a
	# stale range highlight is somehow still present (no active turn system, etc.).
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		_clear_movement_range()
		return

	# ACT IN PLACE: clicking the unit's OWN cell opens the action menu without staging a
	# move (Fire-Emblem "wait/act here"). No tentative move is staged, so Cancel from the
	# menu simply returns to the selected state and Wait finalizes from the origin.
	if _is_unit_own_cell(destination):
		_clear_movement_range()
		_set_state(CommandState.ACTION_MENU)
		return

	# Check if destination is in movement range
	var is_valid_destination = false
	for tile in movement_range_tiles:
		if abs(tile.x - destination.x) < 0.1 and abs(tile.z - destination.z) < 0.1 \
				and abs(tile.y - destination.y) < 0.1:
			is_valid_destination = true
			break

	if is_valid_destination:
		# Validate with turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system.validate_turn_action(selected_unit, "move"):
				_move_to_destination(destination)
		else:
			_move_to_destination(destination)
	else:
		# Unreachable cell: give the click FEEDBACK instead of silently swallowing it.
		_flash_invalid_action()


func _is_unit_own_cell(destination: Vector3) -> bool:
	"""True when [param destination] (a Vector3(col,floor,row) grid coord) is the selected
	unit's current board cell -- i.e. the player clicked the unit's own tile."""
	if selected_unit == null:
		return false
	var board = CombatServices.board()
	if board == null:
		return false
	var own_cell: Vector3i = board.cell_of(selected_unit)
	var clicked_cell: Vector3i = _grid_tile_to_cell(destination)
	return own_cell == clicked_cell


func _move_to_destination(destination: Vector3) -> void:
	"""Route a validated destination click to either the Fire-Emblem TENTATIVE move
	(character-backed unit, live board, local play), the legacy INSTANT-commit move
	(non-character unit / no board), or -- in a network match -- a MOVE intent.
	The tentative path is the canonical FE loop: the unit moves for preview only and
	does not commit until the player confirms an action (attack or Wait).

	Network matches commit immediately through the host instead of previewing: the
	local board is never mutated outside an accepted action, so every peer's state
	(and the host's desync checkpoints) stay identical. When the accepted MOVE lands,
	the contextual action menu opens on the unit (see _on_network_action_applied)."""
	if _is_networked_match():
		if GameModeManager.is_my_turn() and selected_unit != null:
			_awaiting_net_move_unit = selected_unit
			GameModeManager.request_move(selected_unit, _grid_tile_to_cell(destination))
		_clear_movement_range()
		movement_mode = false
		_update_actions()
		return

	var use_tentative := (
		selected_unit.has_character()
		and CombatServices.board() != null
	)
	if use_tentative:
		_begin_tentative_move(destination)
	else:
		# Legacy (non-character unit / no board): commit immediately.
		_execute_movement_to_destination(destination)

func _execute_movement_to_destination(destination: Vector3) -> void:
	"""Execute movement to destination (tactical style)"""
	if not selected_unit:
		return

	# Character-backed units route through the shared BoardAdapter (resolver-backed).
	# Validation happens against the reachable set inside the helper before it moves.
	if _try_execute_move_via_board(destination):
		# Clear the highlighted range now that the move is under way.
		_clear_movement_range()
		# Update UI to reflect unit has moved
		_update_actions()
		return

	# FALLBACK: legacy grid-based movement for non-character units / no live board.
	# Get grid for position calculations
	var grid = preload("res://board/Grid.tres")
	var old_world_pos = selected_unit.global_position
	var old_grid_pos = grid.calculate_grid_coordinates(old_world_pos)

	# Calculate new world position
	var new_world_pos = grid.calculate_map_position(destination)
	# Preserve the unit's original Y height (units are at Y=1.5)
	new_world_pos.y = selected_unit.global_position.y

	# Clear movement range first
	_clear_movement_range()

	# Animate the unit movement
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)

	# Emit movement event
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)

	# Mark unit as having acted
	_complete_movement_action()

	# Update UI to reflect unit has moved
	_update_actions()

# --- Fire-Emblem tentative move: begin / commit / revert ---------------------

func _begin_tentative_move(destination: Vector3) -> void:
	"""Stage a TENTATIVE move to [param destination] (a Vector3(col,0,row) grid coord):
	snap the unit onto the destination cell so its VISUAL position updates and
	board.cell_of(unit) reads the new cell (which is what the move-range / targeting
	/ forecast / execution math all key off), remember the ORIGIN cell, but do NOT
	commit -- no mark_moved(), no GameEvents.unit_moved, no action consumed. The
	movement-range highlight is cleared so the action menu (Moves / End Turn) takes
	over, exactly like Fire Emblem's post-move menu.

	Commit happens only on confirm (_commit_tentative_move, from an attack or Wait);
	cancel reverts to the origin (_revert_tentative_move)."""
	if not selected_unit:
		return

	var board = CombatServices.board()
	if board == null:
		# Shouldn't happen (the caller gates on a live board), but stay safe: fall
		# back to the legacy committed move rather than staging a broken preview.
		_execute_movement_to_destination(destination)
		return

	var clicked_cell: Vector3i = _grid_tile_to_cell(destination)
	# THE GHOST SHOWS WHERE THE UNIT ACTUALLY STOPS. A route across an armed halting trap
	# ends ON the trap, so the tentative preview stages there rather than at the cell the
	# player clicked -- the FE loop's ghost IS the unit at its pending position, and a ghost
	# standing somewhere the move cannot reach would be a lie the confirm then corrects.
	# preview_route is the same derivation the move-apply seam walks, so what the player
	# confirms and what the board resolves are the same cell by construction.
	var trap_route: Dictionary = TileEffectSystem.preview_route(
		selected_unit, board.cell_of(selected_unit), clicked_cell, board)
	var dest_cell: Vector3i = trap_route.get("stop", clicked_cell)
	_tentative_origin_cell = board.cell_of(selected_unit)
	_tentative_origin_world = selected_unit.global_position
	_tentative_origin_facing = selected_unit.get_facing() if selected_unit.has_method("get_facing") else Vector2i.ZERO
	# The route the range flood found (walks through allies, climbs stairs).
	var route: Array[Vector3i] = []
	if _range_resolver != null and _range_origin == _tentative_origin_cell:
		route = _range_resolver.path_to(dest_cell)
	_tentative_dest_cell = dest_cell
	_tentative_unit = selected_unit
	_tentative_active = true

	# Snap the unit onto the destination cell (preserves its height). This updates
	# the visual position AND makes board.cell_of(unit) == dest immediately, with no
	# tween race: every subsequent cell query reads the tentative position at once.
	board.move_unit(selected_unit, dest_cell)
	# Walk the MODEL along the route (visual only -- the unit node is already on the
	# destination, so every cell query above stays exact). Speed / on-off follow the
	# Battle Speed and Animations settings; fast-forward speeds it up.
	_walk_unit(selected_unit, route)

	# The post-move action menu replaces the movement-range highlight.
	_clear_movement_range()
	movement_mode = false

	# The warning stands until the move is confirmed or cancelled (see _set_trap_warning).
	# Asserted AFTER _clear_movement_range, which drops the cursor-sweep warning with the
	# range it belonged to.
	_set_trap_warning(trap_route.get("trap", null))

	# Refresh unit visuals (health bar etc. follow the moved node) and the action UI
	# (Move now disabled; Moves / End Turn drive confirm-or-Wait).
	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()
	_update_actions()

	# The move landed: open the contextual action menu (Moves / Wait / Cancel) right
	# next to the unit. THIS is the golden-path replacement for the old centered SELECT
	# MOVE modal / the sidebar End Turn press.
	_set_state(CommandState.ACTION_MENU)


func _commit_tentative_move() -> void:
	"""COMMIT the staged tentative move for real: snap the unit exactly onto the
	destination cell, mark_moved() (consumes the move but not the action), and emit
	GameEvents.unit_moved so downstream systems (tile effects, visuals) observe it.
	This is the ONLY place the tentative move touches committed board/turn state.
	Idempotent no-op when no tentative move is staged. Callers that also execute an
	attack call this FIRST so the attack resolves from the committed destination."""
	if not _tentative_active or _tentative_unit == null:
		return

	var unit := _tentative_unit
	var origin_cell := _tentative_origin_cell
	var dest_cell := _tentative_dest_cell
	# Drop the tentative bookkeeping up front so a re-entrant call can't double-commit.
	_clear_tentative_state()
	# LOCAL COMMAND RNG: this commit is a MOVE_UNIT; begin it before it resolves so a trap or
	# terrain roll it springs draws from the generator its replay re-installs.
	NetSessionNode.begin_local_command_rng()

	var board = CombatServices.board()
	if board != null:
		# Re-snap to the exact cell center (the unit is already visually here) so the
		# committed logical position is exact regardless of any in-flight animation.
		board.move_unit(unit, dest_cell)

	# mark_moved(): consumes only the MOVE for the turn, not the action. The unit may
	# still have an action pending (the attack we're about to run, or it just Waited).
	if unit.has_method("mark_moved"):
		unit.mark_moved()

	var from_grid := Cells.to_grid(origin_cell)
	var to_grid := Cells.to_grid(dest_cell)
	# The walk already played when the move was staged; tell the animator the unit is
	# home so unit_moved does not replay a glide from the origin.
	var animator := _unit_animator()
	if animator != null:
		animator.sync_position(unit)
	GameEvents.unit_moved.emit(unit, from_grid, to_grid)

	# REPLAY: this is the ONE place a solo/hotseat move becomes committed board state, so it
	# is the one place a MOVE_UNIT is recorded for the local FE loop (the networked branch
	# records apply-side instead). No-op when no recorder is mounted.
	ReplayRecorder.note_move_unit(unit, dest_cell)

	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()


func _revert_tentative_move() -> void:
	"""CANCEL the staged tentative move: snap the unit back onto its ORIGIN cell and
	drop the tentative state. Nothing was ever committed, so there is no board/turn
	state to undo -- the unit stays fully available (it did not move or act). This
	does NOT re-show the movement range or refresh the action UI; callers that return
	to the normal selection state do that around this call. Idempotent no-op when no
	tentative move is staged."""
	if not _tentative_active or _tentative_unit == null:
		_clear_tentative_state()
		return

	var unit := _tentative_unit
	var origin_cell := _tentative_origin_cell
	var origin_world := _tentative_origin_world  # capture BEFORE clearing (which zeroes it)
	var origin_facing := _tentative_origin_facing
	_clear_tentative_state()

	var board = CombatServices.board()
	if board != null:
		# Snap straight back to the origin cell -> board.cell_of(unit) == origin again,
		# so a re-shown movement range is computed correctly from the original spot.
		board.move_unit(unit, origin_cell)
	else:
		# No board (shouldn't happen for a staged tentative move): fall back to the
		# remembered world position.
		unit.global_position = origin_world
	# Cut any walk still playing and put the model back on the (restored) unit.
	var animator := _unit_animator()
	if animator != null:
		animator.stop_motion(unit)
	# Undo also restores the facing the unit had before the staged walk.
	if origin_facing != Vector2i.ZERO and unit.has_method("set_facing"):
		unit.set_facing(origin_facing)

	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()


func _unit_animator() -> Node:
	"""The UnitAnimator autoload (null in bare harnesses)."""
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	var a := tree.root.get_node_or_null("UnitAnimator")
	return a if a != null and a.has_method("walk_path") else null


func _walk_unit(unit: Unit, route: Array[Vector3i]) -> void:
	"""Animate [param unit]'s model along [param route] to where the unit now stands."""
	var animator := _unit_animator()
	if animator == null:
		return
	if route.size() >= 2:
		animator.walk_path(unit, route)
	else:
		animator.stop_motion(unit)


func _clear_tentative_state() -> void:
	"""Drop all tentative-move bookkeeping (does NOT move the unit)."""
	# The trap warning belonged to the staged move; it goes with it, on BOTH the commit and
	# the cancel path (both funnel through here).
	_set_trap_warning(null)
	_tentative_active = false
	_tentative_unit = null
	_tentative_origin_cell = Vector3i.ZERO
	_tentative_dest_cell = Vector3i.ZERO
	_tentative_origin_world = Vector3.ZERO
	_tentative_origin_facing = Vector2i.ZERO


func is_tentative_move_active() -> bool:
	"""True while a tentative (uncommitted) move is staged, awaiting confirm/cancel."""
	return _tentative_active


# Move System Implementation
func _setup_move_system() -> void:
	"""Initialize the move system"""
	# Create move selection panel
	move_selection_panel = MoveSelectionPanel.new()
	add_child(move_selection_panel)
	
	# Connect move selection signals
	move_selection_panel.move_selected.connect(_on_move_selected)
	move_selection_panel.move_cancelled.connect(_on_move_cancelled)

	# Contextual post-move action menu (the golden-path replacement for the centered
	# SELECT MOVE modal). Floats next to the unit; emits one signal per choice, which we
	# route into the same targeting / commit / revert paths the modal used.
	action_menu = UnitActionMenu.new()
	add_child(action_menu)
	action_menu.move_chosen.connect(_on_action_menu_move_chosen)
	action_menu.wait_chosen.connect(_on_action_menu_wait_chosen)
	action_menu.cancel_chosen.connect(_on_action_menu_cancel_chosen)

	# Combat forecast overlay: one instance, added like the move panel. It is a
	# non-modal, mouse-ignoring floating overlay, so it never blocks targeting
	# clicks. Driven live off GameEvents.cursor_moved (see _on_cursor_moved_forecast)
	# so it updates as the player sweeps the cursor from one enemy to another.
	combat_forecast_panel = CombatForecastPanel.new()
	add_child(combat_forecast_panel)
	if GameEvents and not GameEvents.cursor_moved.is_connected(_on_cursor_moved_forecast):
		GameEvents.cursor_moved.connect(_on_cursor_moved_forecast)

	# The SKILLS command row: the entry to the unit's kit from the command list (the
	# contextual action menu lists the same moves at the unit after a move).
	moves_button = Button.new()
	moves_button.name = "MovesButton"
	moves_button.text = "Skills"
	moves_button.theme_type_variation = &"HudCommand"
	moves_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	moves_button.focus_mode = Control.FOCUS_NONE
	moves_button.tooltip_text = "Attack or use a skill: pick one of this unit's moves, then a target."
	moves_button.pressed.connect(_on_moves_pressed)

	# Into the command list, right after Move (Move / Skills / Wait / Info / Cancel).
	if actions_container:
		actions_container.add_child(moves_button)
		if move_button and move_button.get_parent() == actions_container:
			actions_container.move_child(moves_button, move_button.get_index() + 1)

func _on_moves_pressed() -> void:
	"""Handle Moves button press - list the selected unit's real moveset.

	Gated on the unit still having its action for the turn. Character-backed units
	expose their authored MoveResource moveset via get_moveset(); legacy
	(non-character) units have no moveset, so the panel degrades to an empty list."""
	if not selected_unit:
		return

	# Selection == inspection: a unit the local human may NOT command (enemy / AI /
	# not-your-turn) can still have its move list opened READ-ONLY, so the player can
	# read what each move does. Commandable units keep exactly today's behaviour.
	var may_command: bool = _human_may_command(selected_unit)

	# Commandable units require the action still be available this turn before opening
	# moves (so they can actually pick + execute). View-only inspection has no such
	# gate -- you can read an enemy's kit whenever it is selected.
	if may_command:
		if selected_unit.has_method("can_act") and not selected_unit.can_act():
			return

	# MoveSelectionPanel reads unit.get_moveset() / get_moveset_controller() itself,
	# so this works for both character units (real moveset) and legacy units (empty).
	if not selected_unit.has_character():
		# LEGACY guard: no CharacterResource -> no MoveResource moveset. Show the
		# panel anyway (it renders "No moves available") instead of fabricating moves.
		pass
	# Pass view-only = not may_command: in that mode the popup lists the moves and shows
	# each move's details on hover/click but NEVER emits move_selected (no targeting).
	move_selection_panel.show_moves_for_unit(selected_unit, not may_command)

func _on_move_selected(slot: int) -> void:
	"""A move slot was chosen from the panel: enter targeting for that move and
	publish its in-range aim cells so the TargetingVisualizer can highlight them."""
	if not selected_unit:
		return

	# READ-ONLY HARD GUARD: never enter targeting / set move_mode / compute aim cells
	# for a unit the local human may not command. In view-only mode MoveSelectionPanel
	# does not even emit move_selected (it reveals the move's details instead), but this
	# guard guarantees no path can aim or execute an enemy / AI unit's move.
	if not _human_may_command(selected_unit):
		return

	var move: MoveResource = selected_unit.get_move(slot)
	if move == null or move.targeting == null:
		return

	# COOLDOWN / CHARGES ENFORCEMENT: never enter targeting for a move the unit
	# cannot currently use. The panel greys the button, but this guards every path
	# into targeting (mouse, number keys, a re-entered/stale panel) so a move on
	# cooldown can never even be aimed -- and _execute_move_on_target re-checks again
	# at resolve time. Null-safe for legacy units without a MovesetController.
	var select_controller = selected_unit.get_moveset_controller()
	if select_controller and select_controller.has_method("can_use") and not select_controller.can_use(move):
		return

	selected_move_index = slot
	move_mode = true

	# Compute every legal aim cell (within [min_range, max_range]) from the unit's
	# current board cell and emit them as Vector3 grid coords for the visualizer.
	var aim_cells := _compute_in_range_aim_cells(move)
	# While aiming, the move's own red range replaces the threat fringe and path arrow.
	GameEvents.attack_fringe_calculated.emit([])
	_path_shown = false
	GameEvents.path_preview_updated.emit([])
	GameEvents.attack_range_calculated.emit(_cells_to_grid_vec3(aim_cells))

	# Seed the forecast off the cursor's current tile, so if it already rests on an
	# enemy the prediction shows at once instead of waiting for the next move.
	_refresh_move_forecast(_last_cursor_tile)

func _on_move_cancelled() -> void:
	"""Handle move selection cancellation (panel BACK button / its own ESC)."""
	# Stamp the frame so a same-frame _on_cancel_pressed (ESC seen by both panels)
	# knows the popup already consumed this ESC and does not back out a further level.
	_popup_closed_frame = Engine.get_process_frames()
	_cancel_move_targeting()

# --- Contextual action menu handlers (the golden-path command loop) ----------

func _on_action_menu_move_chosen(slot: int) -> void:
	"""A move row in the contextual menu was clicked -> enter TARGETING for that slot,
	reusing the exact modal-path entry (_on_move_selected) so aim highlighting, cooldown
	gating and the forecast all behave identically."""
	if not selected_unit:
		return
	_on_move_selected(slot)
	# Only advance the state machine if targeting actually engaged (the move could be
	# on cooldown / invalid, in which case we stay on the action menu).
	if is_targeting_move():
		_set_state(CommandState.TARGETING)
	else:
		# Stay in the menu; re-open it so the player can pick again.
		_set_state(CommandState.ACTION_MENU)

func _on_action_menu_wait_chosen() -> void:
	"""WAIT: the missing finalize. Commit the tentative move (so the unit stays where it
	previewed), then consume its ACTION via mark_action_completed -- which emits
	unit_action_completed, greying the unit and letting the turn systems auto-end the
	player turn / advance the speed queue with NO separate End Turn press. Then deselect
	back to IDLE."""
	if not selected_unit or not _human_may_command(selected_unit):
		return
	var unit := selected_unit
	# Drop any half-aimed move UI first, then lock the move in.
	_cancel_move_targeting()

	# NETWORKED (Phase 2): submit the staged move (if any) + WAIT_UNIT rather than committing
	# locally; the applier finalizes both on every peer. See the reconciliation note above.
	if _is_networked_match():
		if GameModeManager.is_my_turn():
			_net_submit_pending_move(unit)
			GameModeManager.request_wait(unit)
		_finish_command(unit)
		return

	# CANTO: the unit already spent its action, so there is no action left to consume --
	# what Wait does here is give up the movement it still owed. _commit_tentative_move
	# above may already have closed the turn (mark_moved -> finish_canto) when a step was
	# staged; finish_canto is idempotent, so this covers the "stand still and be done"
	# case without double-announcing the one that moved.
	var canto_wait: bool = _unit_has_canto(unit)
	_commit_tentative_move()
	# LOCAL COMMAND RNG: the WAIT is its own command -- begin it before it resolves.
	NetSessionNode.begin_local_command_rng()
	if canto_wait:
		if unit.has_method("finish_canto"):
			unit.finish_canto("wait")
	elif unit.has_method("mark_action_completed"):
		unit.mark_action_completed("wait")
	ReplayRecorder.note_wait_unit(unit)  # REPLAY: solo WAIT_UNIT
	_refresh_unit_visuals()
	_finish_command(unit)

func _on_action_menu_cancel_chosen() -> void:
	"""Cancel row (also right-click / ESC in ACTION_MENU): revert the tentative move to
	the origin cell, leaving the unit fully available, and return to UNIT_SELECTED with
	its movement range re-shown -- exactly the Fire-Emblem 'change my mind' back-out."""
	_revert_tentative_move()
	_set_state(CommandState.UNIT_SELECTED)
	_calculate_and_show_movement_range()
	_update_actions()

func _finish_command(acted_unit: Unit = null) -> void:
	"""Tear down after an action fully resolves (Wait, or an attack): go IDLE and deselect
	the acted unit through the cursor so both the panel AND the cursor's selection state
	clear.

	Speed First subtlety: mark_action_completed (called by the caller BEFORE this) advances
	the queue synchronously, and the cursor AUTO-SELECTS the next human actor as part of
	that -- so by the time we get here `selected_unit` may already be a DIFFERENT unit. In
	that case we must not touch anything: the next unit's own selection already set the
	state to UNIT_SELECTED and showed its range. We only reset + deselect when the acted
	unit is still the selection (Traditional mode, or Speed First handing off to an AI)."""
	if acted_unit != null and selected_unit != null and selected_unit != acted_unit:
		return
	_set_state(CommandState.IDLE)
	var cursor := _get_board_cursor()
	if cursor and cursor.has_method("deselect_current"):
		cursor.deselect_current()
	elif selected_unit:
		GameEvents.unit_deselected.emit(selected_unit)

func _refresh_unit_visuals() -> void:
	"""Force an immediate unit-visual refresh (health bars, greyed-out acted state)."""
	var tree := get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()

func _get_board_cursor() -> Node:
	"""The board cursor, found via its group so it works regardless of scene path
	(Map/Cursor vs World/Board/Cursor)."""
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("board_cursor")

func _get_movement_visualizer() -> Node:
	"""The MovementVisualizer (direct child of the current scene) for danger overlays."""
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null("MovementVisualizer")

func _flash_invalid_action() -> void:
	"""Feedback for an unreachable-tile / invalid-target click: a quiet lower-pitch UI
	blip via the AudioManager autoload (reusing sfx_ui_click -- no new audio assets) and
	a brief red flash of the cursor bracket. Both are best-effort and never error when
	the autoload / cursor is absent."""
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		# Quieter than a real action so a mis-click reads as "denied", not "confirmed".
		audio.play_sfx(&"sfx_ui_click", -8.0)
	var cursor := _get_board_cursor()
	if cursor and cursor.has_method("flash_invalid"):
		cursor.flash_invalid()

# --- Enemy threat (danger zone) -----------------------------------------------

func _danger_zone_overlay() -> Node:
	"""The battle's DangerZoneOverlay (the ONE danger-zone implementation), or null."""
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"danger_zone_overlay")

func _toggle_all_enemy_danger() -> void:
	"""Toggle every hostile unit's danger zone (the danger_zone action's effect; used by
	the touch Danger button)."""
	var dz := _danger_zone_overlay()
	if dz != null and dz.has_method("toggle"):
		dz.toggle()

func _compute_enemy_threat_cells(enemy: Unit) -> Array[Vector3]:
	"""The cells [param enemy] threatens next turn -- everywhere it can move to plus every
	cell its offensive moves could strike from there (ThreatResolver.unit_threat's "move"
	and "attack" sets, the same flood the DangerZoneOverlay and the inspect fringe use) --
	as Vector3(col, floor, row) grid coords.

	FOG: threat is computed from VISIBLE enemies only. A danger zone drawn for a unit you
	cannot see is a free map of where it is standing -- the overlay would out the ambush
	the fog exists to hide -- so a hidden enemy yields an empty set (the overlay applies
	the same rule)."""
	if enemy == null or not is_instance_valid(enemy) or not enemy.has_character():
		return []
	if FogOfWarOverlay.unit_hidden(enemy):
		return []
	var board = CombatServices.board()
	if board == null:
		return []
	var threat: Dictionary = ThreatResolver.unit_threat(enemy, BoardSnapshot.of(board))
	var seen := {}
	var cells: Array[Vector3i] = []
	for key in ["move", "attack"]:
		for c in threat.get(key, []):
			if not seen.has(c):
				seen[c] = true
				cells.append(c)
	return _cells_to_grid_tiles(cells)

func _on_unit_eliminated_danger(unit: Unit, _eliminator: Unit) -> void:
	"""A unit died. Drop it as the SELECTION: selected_unit was previously only cleared on
	an explicit deselect -- so killing the selected unit left the panel holding a
	reference that is freed a frame later, and every subsequent _update_actions()
	dereferenced it. Clearing at the source makes that whole class of error impossible
	rather than merely guarded. (The danger zone itself refreshes on the death.)"""
	if unit == null:
		return
	if unit == selected_unit:
		selected_unit = null
	if unit == _awaiting_net_move_unit:
		_awaiting_net_move_unit = null

# --- Unit cycling ------------------------------------------------------------

func _cycle_to_next_commandable_unit() -> void:
	"""Next Unit (touch): select the NEXT un-acted, commandable friendly unit (wrap
	around), driving the same cursor selection path a click uses so every downstream
	system just works. Prefers the board cursor's own cycle (the cycle_next action:
	reading order, floor-aware, camera follow); falls back to the roster walk below.
	Skipped while the action menu / targeting is up (handled by the caller)."""
	var cursor_node := _get_board_cursor()
	if cursor_node != null and cursor_node.has_method("cycle_ready_unit"):
		var target = cursor_node.cycle_ready_unit(1)
		if target != null and cursor_node.has_method("select_unit_external") \
				and selected_unit != target:
			cursor_node.select_unit_external(target)
		if target != null:
			return
	var player := _current_turn_player()
	if player == null or not _player_is_human(player):
		return
	var candidates: Array[Unit] = []
	for u in player.get_units_that_can_act():
		if u != null and is_instance_valid(u) and u.is_alive() and _human_may_command(u):
			candidates.append(u)
	if candidates.is_empty():
		return

	# Start after the currently selected unit so repeated presses walk the roster.
	var start_index := -1
	if selected_unit != null:
		start_index = candidates.find(selected_unit)
	var next_unit: Unit = candidates[(start_index + 1) % candidates.size()]
	if next_unit == null:
		return

	var cursor := _get_board_cursor()
	if cursor and cursor.has_method("select_unit_external"):
		cursor.select_unit_external(next_unit)
	else:
		# Fallback: emit selection directly (cursor state may drift, but selection works).
		GameEvents.unit_selected.emit(next_unit, next_unit.global_position)

func is_targeting_move() -> bool:
	"""True while waiting for the player to click a move/attack target."""
	return move_mode and selected_move_index >= 0

func handle_move_target_selected(grid_pos: Vector3) -> void:
	"""Cursor clicked a cell (Vector3 grid coord) while targeting a move. Validate
	the aim against the move's TargetingPattern, then resolve it through
	perform_move -> MoveExecutor. Stays in targeting mode on an illegal aim."""
	if not is_targeting_move() or not selected_unit:
		return

	var move: MoveResource = selected_unit.get_move(selected_move_index)
	if move == null or move.targeting == null:
		_cancel_move_targeting()
		return

	var board = CombatServices.board()
	if board == null:
		_cancel_move_targeting()
		return

	var origin: Vector3i = board.cell_of(selected_unit)
	# Vector3(col, floor, row) grid coord -> Vector3i(col, row, floor) board cell.
	var aim := Cells.from_grid(grid_pos)

	# Must be a legal aim point for this pattern (respects min/max range plus the
	# unit's own range bonus -- see MoveResource.effective_max_range -- and the
	# pattern's board constraints, e.g. a leap's empty landing cell).
	if not move.can_target(origin, aim, selected_unit, board):
		_flash_invalid_action()
		return  # stay in targeting mode

	# Preview the full area footprint this aim would affect.
	var area_cells := move.targeting_for(selected_unit).resolve_cells(origin, aim)
	GameEvents.aoe_preview_calculated.emit(_cells_to_grid_vec3(area_cells))

	# Unit-target moves (ENEMY / ALLY / ANY_UNIT) require an eligible occupant at
	# the aim cell; tile-target moves accept any in-range cell.
	if _move_requires_unit_target(move):
		if not _has_eligible_unit_at(board, move, aim):
			_flash_invalid_action()
			return  # stay in targeting mode

	_execute_move_on_target(aim, move, selected_move_index)

func _await_ultimate_cutin(unit, move, slot: int) -> void:
	"""If [param move] is an ultimate (see [method MoveResource.is_ultimate_move]), emit
	GameEvents.ultimate_casting and HOLD until the cut-in overlay's `finished` signal, so the
	full-screen flash plays before the move resolves. The overlay lives in the
	"ultimate_cutin" group and self-triggers off the same signal; we look it up null-safely and
	skip the await entirely when it is absent (headless / tests) so the caller can never hang.
	A non-ultimate move returns immediately with no await and no signal, so ordinary casts are
	byte-for-byte unchanged."""
	if not MoveResource.is_ultimate_move(move, slot):
		return
	GameEvents.ultimate_casting.emit(unit, move)
	var tree := get_tree()
	if tree == null:
		return  # off-tree (defensive) -> emit only, never await
	var overlay := tree.get_first_node_in_group(&"ultimate_cutin")
	if overlay != null and overlay.has_signal(&"finished"):
		await overlay.finished


func _execute_move_on_target(aim_cell: Vector3i, move: MoveResource, slot: int) -> void:
	"""Resolve the selected move at aim_cell through the unit's perform_move
	(-> MoveExecutor). On success: record the use for cooldown/charges, print the
	resolved events, consume the unit's action, and clear targeting."""
	if not selected_unit:
		return

	var board = CombatServices.board()
	if board == null:
		_cancel_move_targeting()
		return

	# COOLDOWN / CHARGES ENFORCEMENT (authoritative, not just the greyed button).
	# The MoveSelectionPanel already disables a move that is on cooldown / out of
	# charges, but that is a UI-only gate. Re-check MovesetController.can_use at the
	# single execution chokepoint so a move that somehow reached here (stale panel,
	# keyboard path, a future caller) can NEVER resolve or consume the unit's action.
	# Null-safe: legacy units without a MovesetController fall through unchanged.
	var gate_controller = selected_unit.get_moveset_controller()
	if gate_controller and gate_controller.has_method("can_use") and not gate_controller.can_use(move):
		# Not usable -- abort without executing or spending the action; refresh the UI
		# (which reflects the remaining cooldown) and drop targeting.
		_cancel_move_targeting()
		_update_actions()
		return

	# Network match: the attack / ability is an intent. A staged move goes first as its own
	# MOVE intent, then USE_MOVE(unit, slot, aim_cell); the host validates both and every
	# peer resolves them with the same seeded RNG when accepted. No local perform_move --
	# the accepted action is the ONE mutation point.
	#
	# ULTIMATE CUT-IN (network): deliberately NOT played on this submit path -- it plays
	# where the cast APPLIES, so every peer (submitter included) flashes it in sync and
	# nobody flashes a cast the host then refuses (GameEvents.ultimate_casting from the
	# net apply path). Playing it here TOO would double-flash for the local caster.
	if _is_networked_match():
		var acting := selected_unit
		var submitted := false
		if GameModeManager.is_my_turn():
			_net_submit_pending_move(acting)
			submitted = GameModeManager.request_use_move(acting, slot, aim_cell)
		_cancel_move_targeting()
		_update_actions()
		if submitted:
			_finish_command(acting)
		return

	# ULTIMATE CUT-IN: if this cast is an ultimate (the 4th moveset slot, or a move flagged
	# is_ultimate -- see MoveResource.is_ultimate_move), sweep the full-screen flash across
	# FIRST and hold until it finishes, so the drama precedes the hit. Local / single-player /
	# hotseat path only (the networked branch above returned already). Headless / no overlay
	# -> the helper emits and returns without awaiting, so nothing hangs.
	var casting_unit: Unit = selected_unit
	await _await_ultimate_cutin(casting_unit, move, slot)
	# The brief await can be interrupted by a deselect / reselection (turn end, click-away,
	# picking another unit). Bail cleanly unless the SAME unit is still selected, rather than
	# resolving the move against a dropped or a different unit. Idempotent: no action was
	# consumed yet. (For a non-ultimate move the helper returns without yielding, so this guard
	# is a same-frame no-op and ordinary casts are unchanged.)
	if not is_instance_valid(selected_unit) or selected_unit != casting_unit:
		return

	# CONFIRM: clicking a valid target commits the whole action. First lock in the
	# tentative move (snap onto the destination, mark_moved, emit unit_moved) so the
	# attack resolves from the committed cell, THEN execute the move for real below.
	# No-op when there was no tentative move (e.g. attacking without moving, or a
	# legacy/multiplayer committed move already applied).
	_commit_tentative_move()

	# Remember who is acting: mark_action_completed below advances the Speed First queue
	# and may auto-select the next unit before _finish_command runs (see _finish_command).
	var acting_unit := selected_unit
	# LOCAL COMMAND RNG: roll this cast from the solo stream's next generator -- the one the
	# recorder stamps onto the CAST_MOVE and its replay re-rolls from. Null without a solo
	# stream, which is exactly the old unseeded behaviour.
	var command_rng: RandomNumberGenerator = NetSessionNode.begin_local_command_rng()
	var result: Dictionary = selected_unit.perform_move(slot, aim_cell, board, command_rng)

	if result.get("success", false):
		# REPLAY: the cast RESOLVED -- record it as CAST_MOVE in the same vocabulary the
		# networked path uses, so playback has one apply path for both. Recorded on success
		# only, so a refused/aborted aim never enters the log.
		ReplayRecorder.note_cast_move(acting_unit, slot, aim_cell)

		# Cooldown / charge bookkeeping (null-safe: legacy units have no controller).
		var controller = selected_unit.get_moveset_controller()
		if controller and controller.has_method("on_used"):
			controller.on_used(move)

		# Using a move consumes the unit's action for the turn.
		if selected_unit.has_method("mark_action_completed"):
			selected_unit.mark_action_completed("move")

		# Refresh the move panel's cooldown display if it is still visible.
		if move_selection_panel and move_selection_panel.visible:
			move_selection_panel.update_move_cooldowns()

		# Clear targeting highlights (also re-emitted by _cancel_move_targeting below).
		GameEvents.targeting_cleared.emit()

		# Force an immediate unit-visual refresh, mirroring the movement path.
		var tree = get_tree()
		var visual_manager = null
		if tree != null and tree.current_scene != null:
			visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
		if visual_manager:
			visual_manager.update_all_unit_visuals()

	# Reset targeting state (and emit targeting_cleared) and refresh the action UI.
	_cancel_move_targeting()
	_update_actions()

	# CANTO: the cast spent the unit's ACTION but left it owing ONE MOVEMENT (Shadow
	# Dash). Do NOT close the command loop -- drop straight back into MOVEMENT-ONLY
	# selection with the (now shortened, -2 from Void Surge) reachable range lit, so the
	# player finishes the step without having to re-select the unit. The contextual menu
	# that opens on the destination offers no moves at all, because Unit.can_act() is now
	# false; Wait there, or Cancel, are the only ways out and both end the turn honestly.
	if result.get("success", false) and _unit_has_canto(acting_unit):
		_set_state(CommandState.UNIT_SELECTED)
		_calculate_and_show_movement_range()
		_update_actions()
		return

	# The action fully resolved: close the command loop and deselect (Speed First then
	# auto-selects the next acting human unit via the cursor). Only when the action was
	# actually consumed -- if the move failed to execute the unit keeps its turn, so we
	# leave selection intact for a retry.
	if result.get("success", false):
		_finish_command(acting_unit)

func _cancel_move_targeting() -> void:
	"""THE single move-targeting reset path. Every exit from a move interaction --
	BACK/ESC/right-click cancel, successful execution, failed execution, and the
	'no valid target / on cooldown' dead-ends -- funnels through here so no branch
	can leave stale UI. Fully idempotent (safe to call when not targeting):

	  - exits targeting mode (is_targeting_move() -> false),
	  - clears the on-board attack-range AND AoE-preview highlights
		(GameEvents.targeting_cleared -> TargetingVisualizer),
	  - hides the SELECT MOVE popup,
	  - hides the combat forecast overlay.

	It intentionally does NOT touch selected_unit / the action panel; callers that
	also want to refresh or drop selection do that around this call."""
	var was_targeting := is_targeting_move()
	move_mode = false
	selected_move_index = -1
	_aoe_preview_active = false
	# Back out of aiming with the blue range still up: bring its fringe back.
	if was_targeting and selected_unit != null and not movement_range_tiles.is_empty() and not _fringe_grid.is_empty():
		GameEvents.attack_fringe_calculated.emit(_fringe_grid)
	# Clears both the attack-range and AoE-preview overlay meshes (the visualizer's
	# _on_targeting_cleared wipes both dictionaries). Covers cancel via BACK/ESC/
	# right-click AND move resolution, since every path funnels through here.
	GameEvents.targeting_cleared.emit()
	# Hide the SELECT MOVE popup. It normally hides itself when a move is picked or
	# BACK is pressed, but routing it through the single reset guarantees it is gone
	# on every exit (e.g. a deselect that happens while the popup is still up).
	if move_selection_panel:
		move_selection_panel.hide()
	# Drop the FE forecast too (cancel via BACK/ESC/right-click AND move resolution).
	# Also drop the sticky target tracker (see _refresh_move_forecast) so the NEXT
	# targeting session starts fresh instead of treating a same-named enemy as
	# already-shown.
	_forecast_target_enemy = null
	if combat_forecast_panel:
		combat_forecast_panel.hide_forecast()
	# Drop the overworld incoming-damage bands on every targeting exit.
	var tree = get_tree()
	var vm = null
	if tree != null and tree.current_scene != null:
		vm = tree.current_scene.get_node_or_null("UnitVisualManager")
	if vm and vm.has_method("clear_damage_previews"):
		vm.clear_damage_previews()

# --- Combat forecast (FE-style preview) -------------------------------------

func _on_cursor_moved_forecast(tile_position: Vector3) -> void:
	"""Live hook: the board cursor moved to a new tile. While targeting an
	offensive move, refresh the forecast for whatever enemy now sits under the
	cursor (or hide it) -- this is what gives the 'compare this enemy vs that'
	feel as the player sweeps the cursor. Purely additive: reads only."""
	_last_cursor_tile = tile_position
	_refresh_move_forecast(tile_position)
	# Same sweep, the movement half: warn when the route to this cell springs a trap, and
	# draw the FE path arrow to it.
	_refresh_trap_warning(tile_position)
	_refresh_path_preview(tile_position)

func _refresh_move_forecast(grid_pos: Vector3) -> void:
	"""Show the forecast for the current move against an eligible ENEMY at grid_pos
	(a legal aim cell), else hide it. Never mutates state -- CombatForecastPanel
	reads MoveExecutor.preview_vs() only.

	TOUCH-READY STICKINESS: once the forecast is up for a target enemy, it stays up
	as long as the aim keeps resolving to that SAME enemy -- see the early-return
	below. This panel owns that guarantee locally rather than depending on
	GameEvents.cursor_moved only firing on genuine cell changes (a property of
	board/cursor/cursor.gd's tile_position setter, not this file), so it can never
	flicker/hide just because motion paused or cursor_moved re-fired. Only a
	genuinely different (or absent) target, an illegal aim, or the targeting
	context ending (every branch below, plus _cancel_move_targeting) may hide it."""
	# Overworld multi-unit preview: blink every affected enemy's world bar with the
	# damage this aim would deal (the forecast card only covers the single enemy at
	# the cursor). Self-clears when the aim is illegal or off any unit.
	_refresh_overworld_damage_preview(grid_pos)
	# Live AoE footprint while aiming (not only after committing the attack).
	_refresh_aoe_preview(grid_pos)

	if combat_forecast_panel == null:
		return

	# Only while actively aiming a move for a commandable unit.
	if not is_targeting_move() or not selected_unit:
		_forecast_target_enemy = null
		combat_forecast_panel.hide_forecast()
		return

	var move: MoveResource = selected_unit.get_move(selected_move_index)
	if move == null or move.targeting == null:
		_forecast_target_enemy = null
		combat_forecast_panel.hide_forecast()
		return

	var board = CombatServices.board()
	if board == null:
		_forecast_target_enemy = null
		combat_forecast_panel.hide_forecast()
		return

	var origin: Vector3i = board.cell_of(selected_unit)
	# Vector3(col, floor, row) grid coord -> Vector3i(col, row, floor) board cell.
	var aim := Cells.from_grid(grid_pos)

	# Forecast only a legal aim that lands on an enemy the caster may attack.
	if not move.can_aim_at(origin, aim, selected_unit, board):
		_forecast_target_enemy = null
		combat_forecast_panel.hide_forecast()
		return

	var enemy = _first_enemy_at(board, aim)

	# Sticky: the aim still resolves to the SAME enemy already shown -- nothing to
	# update, and critically nothing to hide.
	if enemy != null and enemy == _forecast_target_enemy:
		return

	if enemy == null:
		_forecast_target_enemy = null
		combat_forecast_panel.hide_forecast()
		return

	_forecast_target_enemy = enemy
	combat_forecast_panel.show_forecast(selected_unit, enemy, move, board)

# True while this panel has an AoE footprint on the board from the live aim preview,
# so an illegal aim clears it exactly once instead of re-emitting every cursor step.
var _aoe_preview_active: bool = false

func _refresh_aoe_preview(grid_pos: Vector3) -> void:
	"""While aiming, paint the full area the move would hit at the cursor cell
	(GameEvents.aoe_preview_calculated) whenever that aim is LEGAL -- the same
	can_target test the executor runs -- and clear it once the aim turns illegal.
	Targeting exit clears it via _cancel_move_targeting (targeting_cleared)."""
	var cells: Array = []
	if is_targeting_move() and selected_unit:
		var move: MoveResource = selected_unit.get_move(selected_move_index)
		var board = CombatServices.board()
		if move != null and move.targeting != null and board != null:
			var origin: Vector3i = board.cell_of(selected_unit)
			var aim := Cells.from_grid(grid_pos)
			if move.can_target(origin, aim, selected_unit, board):
				cells = _cells_to_grid_vec3(move.targeting_for(selected_unit).resolve_cells(origin, aim))
	if cells.is_empty():
		if _aoe_preview_active:
			_aoe_preview_active = false
			GameEvents.aoe_preview_calculated.emit([])
		return
	_aoe_preview_active = true
	GameEvents.aoe_preview_calculated.emit(cells)

func _refresh_overworld_damage_preview(grid_pos: Vector3) -> void:
	"""Blink the world-space health bar of EVERY enemy this aim would hit with the
	damage it would take -- the overworld counterpart to the single-enemy forecast
	card, so a multi-target AoE shows its potential damage on all victims at once.
	Non-mutating (MoveExecutor.preview_vs only). Self-clears whenever the aim is
	illegal, off any unit, or targeting has ended."""
	var tree = get_tree()
	var vm = null
	if tree != null and tree.current_scene != null:
		vm = tree.current_scene.get_node_or_null("UnitVisualManager")
	if vm == null or not vm.has_method("preview_damage"):
		return

	if not is_targeting_move() or not selected_unit:
		vm.clear_damage_previews()
		return
	var move: MoveResource = selected_unit.get_move(selected_move_index)
	if move == null or move.targeting == null:
		vm.clear_damage_previews()
		return
	var board = CombatServices.board()
	if board == null:
		vm.clear_damage_previews()
		return

	var origin: Vector3i = board.cell_of(selected_unit)
	var aim := Cells.from_grid(grid_pos)
	# Only preview a legal aim (respects range + pattern constraints, same test the
	# executor runs), so bands never light up on a cell the move can't actually reach.
	if not move.can_target(origin, aim, selected_unit, board):
		vm.clear_damage_previews()
		return

	# Every cell this aim's pattern would strike, then each enemy standing on one.
	var previews: Dictionary = {}
	for cell in move.targeting_for(selected_unit).resolve_cells(origin, aim):
		for occupant in board.units_at(cell):
			if occupant == null or occupant == selected_unit or previews.has(occupant):
				continue
			if not board.are_enemies(selected_unit, occupant):
				continue  # never paint a red band on an ally (heals/friendly AoE)
			var preview: Dictionary = MoveExecutor.preview_vs(move, selected_unit, occupant, board)
			var dmg: int = int(preview.get("damage", 0))
			if dmg > 0:
				previews[occupant] = dmg
	vm.preview_damage(previews)

func _first_enemy_at(board, cell: Vector3i):
	"""First occupant of `cell` that is an enemy of selected_unit (per the shared
	BoardAdapter), else null. Matches how targeting resolves units at a cell."""
	var occupants: Array = board.units_at(cell)
	for occupant in occupants:
		if occupant == null or occupant == selected_unit:
			continue
		if board.are_enemies(selected_unit, occupant):
			return occupant
	return null

# --- Move targeting helpers -------------------------------------------------

func _compute_in_range_aim_cells(move: MoveResource) -> Array[Vector3i]:
	"""Every legal aim cell for [param move] from the unit's current board cell,
	i.e. cells whose Manhattan distance is within [min_range, effective max range]
	AND that satisfy the pattern's board constraints (an empty landing cell beside
	an enemy for a leap, ...).

	The sweep bound and the per-cell test both come from the unit's EFFECTIVE reach
	(MoveResource.effective_max_range / can_target), so the highlighted cells are
	exactly the cells MoveExecutor will accept -- a range bonus can never light up
	a cell the executor then rejects, or hide one it would allow. can_target rather
	than can_aim_at for the same reason: it is the check the executor runs, and the
	live board is right here to answer it. A move with no board constraints is
	unaffected -- the two agree cell for cell.

	MULTI-FLOOR: sweeps every floor of the board (the reach shrinks by the floor
	difference, and grows by the high-ground bonus when aiming down)."""
	var cells: Array[Vector3i] = []
	if not selected_unit or move == null or move.targeting == null:
		return cells

	var board = CombatServices.board()
	if board == null:
		return cells

	var origin: Vector3i = board.cell_of(selected_unit)
	var max_r: int = move.effective_max_range(selected_unit) + Elevation.HIGH_GROUND_RANGE_BONUS
	var floors: int = board.floor_count() if board.has_method("floor_count") else 1
	for f in range(floors):
		for dx in range(-max_r, max_r + 1):
			for dy in range(-max_r, max_r + 1):
				var aim := Vector3i(origin.x + dx, origin.y + dy, f)
				if f > 0 and board.has_method("has_tile") and not board.has_tile(aim):
					continue  # never offer an aim in the air (upper floors are sparse)
				if move.can_target(origin, aim, selected_unit, board):
					cells.append(aim)
	return cells

func _cells_to_grid_vec3(cells: Array[Vector3i]) -> Array:
	"""Vector3i(col, row, floor) board cells -> Vector3(col, floor, row) grid coords,
	the form GameEvents.attack_range_calculated / aoe_preview_calculated (and the
	TargetingVisualizer) expect."""
	var out: Array = []
	for c in cells:
		out.append(Cells.to_grid(c))
	return out

func _move_requires_unit_target(move: MoveResource) -> bool:
	"""True when the move must be aimed at an occupied cell (unit-target kinds)."""
	if move == null or move.targeting_for(selected_unit) == null:
		return false
	var pattern := move.targeting_for(selected_unit)
	# A pattern that demands an EMPTY landing cell (a leap/dash) is aimed at GROUND,
	# not at a unit -- its TargetKind only picks out which units the effects then
	# hit. Gating it on an occupant would make it impossible to aim.
	if pattern.requires_empty_cell:
		return false
	match pattern.target_kind:
		CombatTypes.TargetKind.ENEMY, CombatTypes.TargetKind.ALLY, CombatTypes.TargetKind.ANY_UNIT:
			return true
		_:
			return false

func _has_eligible_unit_at(board, move: MoveResource, aim: Vector3i) -> bool:
	"""True when the aim cell holds a unit the move may legally target, per its
	TargetKind (allegiance checked through the shared BoardAdapter)."""
	var occupants: Array = board.units_at(aim)
	if occupants.is_empty():
		return false

	var kind = move.targeting_for(selected_unit).target_kind
	for occupant in occupants:
		if occupant == null:
			continue
		match kind:
			CombatTypes.TargetKind.ENEMY:
				if board.are_enemies(selected_unit, occupant):
					return true
			CombatTypes.TargetKind.ALLY:
				if occupant == selected_unit:
					if move.targeting_for(selected_unit).affects_caster_tile:
						return true
				elif board.are_allies(selected_unit, occupant):
					return true
			CombatTypes.TargetKind.ANY_UNIT:
				return true
			_:
				return true
	return false

func _update_moves_button_availability() -> void:
	"""Enable the Moves button only when the (character-backed) unit still has its
	action and at least one usable move. Reads the real moveset + MovesetController
	directly."""
	if not moves_button or not selected_unit:
		return

	# Legacy (non-character) units have no authored MoveResource moveset.
	if not selected_unit.has_character():
		moves_button.disabled = true
		_set_command(moves_button, "Skills", &"", "None")
		return

	var moveset: Array[MoveResource] = selected_unit.get_moveset()
	var controller = selected_unit.get_moveset_controller()

	var usable := 0
	var total := 0
	for move in moveset:
		if move == null:
			continue
		total += 1
		if controller and controller.has_method("can_use"):
			if controller.can_use(move):
				usable += 1
		else:
			usable += 1

	# READ-ONLY VIEW: a unit the local human may NOT command (enemy / AI / not-your-turn)
	# can still open its move list to READ each move's details. Keep the button enabled
	# whenever the unit HAS a moveset; clicking opens the popup in view-only mode (no
	# targeting, no execution). Cooldown/uses do not matter for reading.
	if not _human_may_command(selected_unit):
		moves_button.disabled = moveset.is_empty()
		if moveset.is_empty():
			_set_command(moves_button, "Skills", &"", "None")
		else:
			_set_command(moves_button, "Skills", &"", "View %d" % total, ConquestTheme.TEXT_DIM)
		return

	var has_action := true
	if selected_unit.has_method("can_act"):
		has_action = selected_unit.can_act()

	moves_button.disabled = usable == 0 or not has_action

	if moveset.is_empty():
		_set_command(moves_button, "Skills", &"", "None")
	elif not has_action:
		_set_command(moves_button, "Skills", &"", "Done")
	elif usable == 0:
		_set_command(moves_button, "Skills", &"", "Cooldown")
	else:
		_set_command(moves_button, "Skills", &"", "%d/%d ready" % [usable, total], ConquestTheme.TEXT_DIM)
