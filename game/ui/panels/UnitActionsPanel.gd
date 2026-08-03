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
## Holds only the two demoted legacy buttons above -- hidden as a whole so it (and its
## VBox separation) takes zero sidebar space. See the hide in _ready().
@onready var actions_container: VBoxContainer = $MarginContainer/ContentContainer/ActionsContainer
@onready var unit_summary_button: Button = $MarginContainer/ContentContainer/UnitSummaryButton
@onready var stats_container: VBoxContainer = $MarginContainer/ContentContainer/StatsContainer
@onready var health_label: Label = $MarginContainer/ContentContainer/StatsContainer/HealthLabel
@onready var attack_label: Label = $MarginContainer/ContentContainer/StatsContainer/AttackLabel
@onready var defense_label: Label = $MarginContainer/ContentContainer/StatsContainer/DefenseLabel
@onready var speed_label: Label = $MarginContainer/ContentContainer/StatsContainer/SpeedLabel
@onready var movement_label: Label = $MarginContainer/ContentContainer/StatsContainer/MovementLabel
@onready var range_label: Label = $MarginContainer/ContentContainer/StatsContainer/RangeLabel
@onready var end_player_turn_button: Button = $MarginContainer/ContentContainer/EndPlayerTurnButton
@onready var cancel_button: Button = $MarginContainer/ContentContainer/CancelButton

var selected_unit: Unit = null
## The in-flight movement slide (see [method _animate_unit_movement]). Held so a second
## move can KILL the previous one instead of letting two tweens fight over the same
## `global_position`.
var _move_tween: Tween = null
var stats_expanded: bool = false
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

# --- Enemy DANGER-ZONE overlays: two SEPARATE channels ----------------------
# Both draw red threat quads through the MovementVisualizer's danger channel (keyed by
# the enemy's instance id), but they differ in lifetime:
#
#   PERSISTENT (the T hotkey): every enemy's zone lit at once, stays up until T again.
#     Tracked in _persistent_danger_enemies. Survives deselects and is NEVER cleared by
#     a transient click below.
#
#   TRANSIENT (clicking / inspecting a single enemy): shows that one enemy's zone, and
#     clears on the NEXT click -- selecting a different unit (a new enemy swaps the
#     overlay to itself), clicking an empty tile, or deselecting. Tracked as the single
#     _transient_danger_enemy. Because inspecting an enemy IS selecting it, the next
#     selection change fires unit_deselected, which tears this overlay down.
#
# Both are computed on demand (toggle / inspect) and refreshed on turn start (positions
# move), never per frame. When the same enemy is in BOTH channels, clearing the transient
# leaves its overlay up (persistent still owns it) -- see _clear_transient_danger.
var _persistent_danger_enemies: Array[Unit] = []
var _transient_danger_enemy: Unit = null

# Move system variables
var move_selection_panel: MoveSelectionPanel
var moves_button: Button
var move_mode: bool = false
var selected_move_index: int = -1

# --- Touch-readiness: on-screen equivalents for keyboard-only actions --------
# Danger Zones mirrors the T hotkey (_toggle_all_enemy_danger); Next Unit mirrors
# Tab/Q (_cycle_to_next_commandable_unit). Built in code and appended to the same
# ActionsContainer the Move/MOVES/End Turn buttons live in (see _setup_touch_buttons),
# so a touch player without a physical keyboard can still reach them.
var danger_zones_button: Button
var next_unit_button: Button

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
var _tentative_origin_cell: Vector2i = Vector2i.ZERO
var _tentative_dest_cell: Vector2i = Vector2i.ZERO
var _tentative_origin_world: Vector3 = Vector3.ZERO

# Frame on which the SELECT MOVE popup closed itself in response to ESC/BACK
# (MoveSelectionPanel emits move_cancelled -> _on_move_cancelled). Both that panel
# and this one process the same ESC in the _input phase, in an order Godot does not
# guarantee; when the popup already consumed an ESC on THIS frame, _on_cancel_pressed
# must not also back out a further level. Exact-frame equality avoids a stale flag
# (a mouse BACK on an earlier frame never matches the current frame).
var _popup_closed_frame: int = -1

func _ready() -> void:
	# Ensure proper mouse handling
	mouse_filter = Control.MOUSE_FILTER_STOP  # Make sure panel stops mouse events
	
	# Connect to game events
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		GameEvents.cursor_selected.connect(_on_cursor_selected)
		# Enemy danger overlays expire when the enemy dies.
		if not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated_danger):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated_danger)
	else:
		push_error("GameEvents not found!")

	# Ride the ACTIVE turn system's turn_started to recompute toggled enemy danger zones
	# (their positions move each turn). Per the project's live-turn-signal rule, this uses
	# the turn system's signal, NOT PlayerManager's (which never fires on AI turns).
	if TurnSystemManager:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated_danger):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated_danger)
		if TurnSystemManager.has_active_turn_system():
			_hook_turn_system_for_danger(TurnSystemManager.get_active_turn_system())

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
		push_error("Unit Summary button not found!")

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

	# Move (M) and End Turn (E) are DEMOTED legacy: the contextual UnitActionMenu
	# (post-move popup) is the golden path now. Hide them -- and the ActionsContainer
	# that only holds them -- so they take zero sidebar space; the M/E keyboard
	# shortcuts (_input below) still call _on_move_pressed / _on_end_unit_turn_pressed
	# directly and never check the button's visible/disabled state, so they keep working.
	if move_button:
		move_button.visible = false
	if end_unit_turn_button:
		end_unit_turn_button.visible = false
	if actions_container:
		actions_container.visible = false

	# Hide panel initially
	_hide_panel()
	
	# Style the unit header background
	_setup_unit_header_styling()
	
	# Initialize move system
	_setup_move_system()

	# On-screen buttons for the two keyboard-only actions (Danger Zones / Next Unit).
	_setup_touch_buttons()

	# Tooltips + theme style-role metadata on the (simplified) sidebar buttons.
	_setup_sidebar_tooltips_and_meta()

func _setup_sidebar_tooltips_and_meta() -> void:
	"""With the contextual action menu now carrying the per-unit commands, the sidebar is
	a status + turn-control strip. Give every remaining button a tooltip, and tag the two
	that a parallel ConquestTheme change reads via `style_role` (harmless if unread):
	End Player Turn is destructive, Cancel is secondary. The per-unit Move / MOVES / End
	Turn (E) buttons are DEMOTED from the golden path -- kept working for the keyboard /
	legacy path, but tooltip'd as such."""
	if move_button:
		move_button.tooltip_text = "Enter movement mode (M) -- legacy; click a reachable tile instead"
	if end_unit_turn_button:
		end_unit_turn_button.tooltip_text = "End just this unit's turn (E) -- or pick Wait from the action menu"
	if moves_button:
		moves_button.tooltip_text = "Open this unit's moves -- or pick one from the action menu after moving"
	if unit_summary_button:
		unit_summary_button.tooltip_text = "Show / hide this unit's full stats (S)"
	if end_player_turn_button:
		end_player_turn_button.tooltip_text = "End the whole player turn (P). Confirms if units still have actions."
		end_player_turn_button.set_meta("style_role", "destructive")
	if cancel_button:
		cancel_button.tooltip_text = "Back out one step (C / ESC / right-click)"
		cancel_button.set_meta("style_role", "secondary")

	# Shared UI-click SFX on every sidebar button, including the dynamically built
	# moves_button (idempotent -- guarded by a meta inside UIFeedback).
	UIFeedback.attach_sfx(self)

func _setup_touch_buttons() -> void:
	"""On-screen equivalents for two keyboard-only actions -- Danger Zones (T) and Next
	Unit (Tab/Q) -- laid out side-by-side in one half-width row (compact, per the
	sidebar-length pass) and inserted into ContentContainer directly above the
	EndPlayerTurn divider, so the turn-control block stays grouped at the bottom. Same
	secondary style_role + tooltip-names-the-hotkey pattern as the rest of the sidebar;
	wired for SFX by the attach_sfx call in _setup_sidebar_tooltips_and_meta, which runs
	after this."""
	var content_container := get_node_or_null("MarginContainer/ContentContainer")
	if content_container == null:
		return

	danger_zones_button = Button.new()
	danger_zones_button.text = "Danger Zones"
	danger_zones_button.toggle_mode = true
	danger_zones_button.custom_minimum_size = Vector2(0, 44)
	danger_zones_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	danger_zones_button.tooltip_text = "Show/hide every enemy's threat range (T)"
	danger_zones_button.mouse_filter = Control.MOUSE_FILTER_STOP
	danger_zones_button.set_meta("style_role", "secondary")
	danger_zones_button.pressed.connect(_on_danger_zones_button_pressed)

	next_unit_button = Button.new()
	next_unit_button.text = "Next Unit"
	next_unit_button.custom_minimum_size = Vector2(0, 44)
	next_unit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_unit_button.tooltip_text = "Select the next un-acted unit (Tab)"
	next_unit_button.mouse_filter = Control.MOUSE_FILTER_STOP
	next_unit_button.set_meta("style_role", "secondary")
	next_unit_button.pressed.connect(_on_next_unit_button_pressed)

	var utility_row := HBoxContainer.new()
	utility_row.name = "UtilityRow"
	utility_row.add_theme_constant_override("separation", 8)
	utility_row.add_child(danger_zones_button)
	utility_row.add_child(next_unit_button)
	content_container.add_child(utility_row)

	var end_turn_separator := content_container.get_node_or_null("HSeparator3")
	if end_turn_separator:
		content_container.move_child(utility_row, end_turn_separator.get_index())

	_sync_danger_zones_button()

func _on_danger_zones_button_pressed() -> void:
	"""On-screen equivalent of the T hotkey: toggle every enemy's persistent danger
	overlay. The button's pressed/toggled visual is synced from the resulting state
	(see _sync_danger_zones_button), not driven by toggle_mode alone, so it stays
	correct even when the T key or a unit death changes the underlying set."""
	_toggle_all_enemy_danger()

func _sync_danger_zones_button() -> void:
	"""Keep the on-screen Danger Zones button's toggled-looking state in lockstep
	with _persistent_danger_enemies (the T set), regardless of what changed it --
	the T hotkey, this button, or an enemy dying. Called from every mutation point."""
	if danger_zones_button:
		danger_zones_button.set_pressed_no_signal(not _persistent_danger_enemies.is_empty())

func _on_next_unit_button_pressed() -> void:
	"""On-screen equivalent of the Tab/Q hotkey. Same guard as the keyboard path:
	skip while the contextual action menu / targeting is up so it cannot yank
	selection mid-command."""
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
	"""Setup styling for the unit header background"""
	if unit_header_background:
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
		style_box.border_width_left = 1
		style_box.border_width_top = 1
		style_box.border_width_right = 1
		style_box.border_width_bottom = 1
		style_box.corner_radius_top_left = 4
		style_box.corner_radius_top_right = 4
		style_box.corner_radius_bottom_left = 4
		style_box.corner_radius_bottom_right = 4
		unit_header_background.add_theme_stylebox_override("panel", style_box)

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection - show actions for selected unit"""
	# Selection == inspection: any living unit may be selected so the player can read
	# its info (including enemy / AI-owned units). Commanding is gated separately via
	# _human_may_command() -- _update_actions() renders disabled buttons for units the
	# player cannot command. The single-player AI hard-gate, the PlayerManager gate and
	# the Traditional can-act gate that used to REJECT selection here are gone. The
	# multiplayer rejection branch is intentionally kept for this pass.
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		# Get local player ID and unit owner
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(unit)

		if not unit_owner:
			return

		# Ensure player_id is int for comparison and arithmetic
		var owner_player_id = int(unit_owner.player_id) if unit_owner.player_id is String else unit_owner.player_id

		if owner_player_id != local_player_id:
			# Could show a message to the player here
			return
	else:
		# Local (single-player / hotseat): accept every selection for inspection.
		# _update_actions() gates the actual commands via _human_may_command().
		pass

	selected_unit = unit

	_update_unit_header()
	_update_actions()
	_update_unit_stats()
	
	# Show movement range immediately when unit is selected (tactical style)
	_show_movement_range_on_selection()

	_show_panel()

	# Drive the state machine: a commandable unit enters the golden path at UNIT_SELECTED
	# (range shown, awaiting a move / act-in-place click). An inspection-only enemy leaves
	# the machine IDLE -- it is not part of the command loop -- and its danger toggle is
	# handled above.
	if _human_may_command(selected_unit):
		_set_state(CommandState.UNIT_SELECTED)
	else:
		_set_state(CommandState.IDLE)

func _show_movement_range_on_selection() -> void:
	"""Show movement range immediately when unit is selected (tactical style)"""
	if not selected_unit:
		return

	# An enemy / AI unit is INSPECTION-only. Selecting it shows its TRANSIENT danger zone
	# (a distinct HOSTILE-red overlay via the separate danger channel) so the player can
	# see where the enemy could reach. This overlay is EPHEMERAL: it clears on the next
	# click -- selecting a different unit (a new enemy swaps the overlay to itself),
	# clicking an empty tile, or deselecting -- because inspecting an enemy IS selecting
	# it, so the next selection change fires unit_deselected and tears the overlay down
	# (see _on_unit_deselected). The PERSISTENT threat mode is the T hotkey
	# (_toggle_all_enemy_danger), a separate channel these transient clicks never clear.
	if not _human_may_command(selected_unit):
		_set_transient_danger_enemy(selected_unit)
		return

	# Commanding your own unit: drop any transient enemy inspect overlay first (the prior
	# enemy was already deselected, but clear defensively so starting a command never
	# leaves a stale red band up), then show this unit's blue movement range.
	_clear_transient_danger()
	_calculate_and_show_movement_range()

func _update_unit_header() -> void:
	"""Update the unit header with name, type, and icon"""
	if not selected_unit:
		return
	
	# Update unit name with player info
	if unit_name_label:
		var player = selected_unit.get_owner_player()
		var player_info = ""
		if player:
			player_info = " (" + player.get_display_name() + ")"
		unit_name_label.text = selected_unit.get_display_name() + player_info
	
	# Update unit type. Post-migration get_unit_type() returns a String (the
	# character_id), not an object -- show a humanized form, and hide the label
	# when it would just duplicate the unit's name.
	if unit_type_label:
		var unit_type: String = selected_unit.get_unit_type()
		var type_text := _humanize_id(unit_type)
		if type_text == "" or type_text == selected_unit.get_display_name():
			unit_type_label.visible = false
		else:
			unit_type_label.visible = true
			unit_type_label.text = type_text
	
	# Update unit icon
	if unit_icon:
		_update_unit_icon()
	
	# Update header background color based on player
	if unit_header_background:
		_update_header_background_color()

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
	"""Update header background color based on player"""
	if not selected_unit or not unit_header_background:
		return
	
	var player = selected_unit.get_owner_player()
	var style_box = StyleBoxFlat.new()
	
	# Base styling
	style_box.border_width_left = 1
	style_box.border_width_top = 1
	style_box.border_width_right = 1
	style_box.border_width_bottom = 1
	style_box.corner_radius_top_left = 4
	style_box.corner_radius_top_right = 4
	style_box.corner_radius_bottom_left = 4
	style_box.corner_radius_bottom_right = 4
	
	# Color based on player
	if player:
		if player.player_id == 0:
			# Player 1 - blue theme
			style_box.bg_color = Color(0.1, 0.2, 0.4, 0.8)
			style_box.border_color = Color(0.2, 0.4, 0.8, 0.8)
		elif player.player_id == 1:
			# Player 2 - red theme
			style_box.bg_color = Color(0.4, 0.1, 0.1, 0.8)
			style_box.border_color = Color(0.8, 0.2, 0.2, 0.8)
		else:
			# Neutral - gray theme
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
			style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
	else:
		# No player - default gray
		style_box.bg_color = Color(0.2, 0.2, 0.2, 0.8)
		style_box.border_color = Color(0.4, 0.4, 0.4, 0.8)
	
	unit_header_background.add_theme_stylebox_override("panel", style_box)

func _update_unit_stats() -> void:
	"""Update the unit stats display"""
	if not selected_unit:
		return
	
	# Update all stat labels
	if health_label:
		health_label.text = "Health: " + str(selected_unit.current_health) + "/" + str(selected_unit.max_health)
	
	if attack_label:
		var attack = selected_unit.get_stat("attack") if selected_unit.has_method("get_stat") else 0
		attack_label.text = "Attack: " + str(attack)
	
	if defense_label:
		var defense = selected_unit.get_stat("defense") if selected_unit.has_method("get_stat") else 0
		defense_label.text = "Defense: " + str(defense)
	
	if speed_label:
		var speed = selected_unit.get_stat("speed") if selected_unit.has_method("get_stat") else 0
		# Show current speed if different from base (due to battle effects)
		var current_speed = speed
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system is SpeedFirstTurnSystem:
				current_speed = (turn_system as SpeedFirstTurnSystem).get_unit_current_speed(selected_unit)
		
		if current_speed != speed:
			speed_label.text = "Speed: " + str(current_speed) + " (base: " + str(speed) + ")"
		else:
			speed_label.text = "Speed: " + str(speed)
	
	if movement_label:
		var movement = selected_unit.get_stat("movement") if selected_unit.has_method("get_stat") else 0
		movement_label.text = "Movement: " + str(movement)
	
	if range_label:
		var range_val = selected_unit.get_stat("range") if selected_unit.has_method("get_stat") else 0
		range_label.text = "Range: " + str(range_val)

func _on_unit_summary_pressed() -> void:
	"""Handle Unit Summary button press - toggle stats display"""
	stats_expanded = not stats_expanded
	
	if stats_container:
		stats_container.visible = stats_expanded
	
	if unit_summary_button:
		if stats_expanded:
			unit_summary_button.text = "Unit Summary ▲"
		else:
			unit_summary_button.text = "Unit Summary ▼"

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
		stats_expanded = false
		if stats_container:
			stats_container.visible = false
		if unit_summary_button:
			unit_summary_button.text = "Unit Summary ▼"

		# Clear movement range when unit is deselected
		_clear_movement_range()

		# Tear down the TRANSIENT enemy inspect overlay: deselecting (or selecting a
		# different unit, which deselects the old one first) is exactly the "any other
		# click" that ends a click-inspect. The PERSISTENT T overlays are untouched --
		# _clear_transient_danger keeps an enemy's overlay up when the T set also holds it.
		_clear_transient_danger()

		_clear_unit_header()
		_hide_panel()

		# Back to IDLE (closes the contextual menu if it was somehow still up).
		_set_state(CommandState.IDLE)

func _clear_movement_range() -> void:
	"""Clear movement range visualization"""
	movement_range_tiles.clear()
	GameEvents.movement_range_cleared.emit()

func _clear_unit_header() -> void:
	"""Clear the unit header information"""
	if unit_name_label:
		unit_name_label.text = "No Unit Selected"
	if unit_type_label:
		unit_type_label.text = ""
	if unit_icon:
		unit_icon.texture = null

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
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		var local_id_raw = GameModeManager.get_local_player_id() if GameModeManager else -1
		var local_id = int(local_id_raw) if local_id_raw is String else local_id_raw
		# player.player_id is statically typed int, so no String coercion needed.
		return int(player.player_id) == local_id
	return not player.is_ai

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

# --- Networked command routing (Phase 2) -------------------------------------
# In a CONNECTED networked match every golden-path action is submitted to NetSession as a
# NetProtocol command instead of executing locally; the real execution happens when the
# resolved command comes back through the CommandApplier (host stamps seq + rng_seed; all
# peers, host included, apply). Single-player / hotseat / local-versus (no live NetSession
# peer) fall through UNCHANGED -- every routing branch is gated on _is_networked_match(),
# which is false off the wire, so SP behaviour is byte-for-byte the existing direct path.
#
# TENTATIVE-MOVE RECONCILIATION (documented decision): when a staged tentative move is
# finalized in a networked match we REVERT the local tentative visual first, then submit a
# MOVE_UNIT for its destination. The resolved command then applies origin->dest on every
# peer symmetrically (correct unit_moved from/to, correct tile ON_EXIT/ON_ENTER), and the
# applier's board.move_unit is an ABSOLUTE set to the destination cell, so even if a slide
# raced ahead the apply cannot double-move. (The applier is idempotent; the revert just
# keeps the acting peer's event stream identical to every observer's.)

func _is_networked_match() -> bool:
	"""True only in a live, connected networked match with >1 participant -- the single gate
	for routing a command through NetSession instead of executing it locally."""
	return typeof(NetSession) == TYPE_OBJECT and NetSession != null and NetSession.is_networked_match()

func _net_id_of(unit) -> int:
	"""The deterministic net_id NetSession/CommandApplier use to name [param unit] across
	peers, or -1 if unknown (in which case the caller must NOT submit a command for it)."""
	if typeof(NetSession) == TYPE_OBJECT and NetSession != null:
		return NetSession.net_id_for(unit)
	return -1

func _net_submit_pending_move(unit) -> void:
	"""If a tentative move is staged for [param unit], revert its local visual and submit the
	destination as a MOVE_UNIT command (see the reconciliation note above). No-op when no
	tentative move is staged or the unit has no net_id."""
	if not _tentative_active or _tentative_unit != unit:
		return
	var nid: int = _net_id_of(unit)
	var dest: Vector2i = _tentative_dest_cell
	_revert_tentative_move()
	if nid >= 0:
		NetSession.submit_intent(NetProtocol.make_move_unit(nid, dest))

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
	if move_button:
		var can_move = can_control and can_perform_unit_actions and selected_unit.can_move() and not _tentative_active
		move_button.disabled = not can_move

		if can_move:
			move_button.text = "Move (M)"
		elif not can_control:
			move_button.text = "Move (M)\n[Not Yours]"
		elif action_restriction_reason == "not this unit's turn":
			move_button.text = "Move (M)\n[Not Turn]"
		elif action_restriction_reason == "already acted this round":
			move_button.text = "Move (M)\n[Used]"
		elif action_restriction_reason == "already acted this turn":
			move_button.text = "Move (M)\n[Used]"
		else:
			move_button.text = "Move (M)\n[N/A]"
	
	# Update Moves (action) button - available if the unit still has its action.
	if moves_button:
		moves_button.disabled = not (can_control and can_perform_unit_actions and selected_unit.can_act())

	# Update End Unit Turn button - only available if unit can perform actions
	if end_unit_turn_button:
		var can_end_unit_turn = can_control and can_perform_unit_actions and selected_unit.can_act()
		end_unit_turn_button.disabled = not can_end_unit_turn
		
		if can_end_unit_turn:
			end_unit_turn_button.text = "End Turn (E)"
		elif not can_control:
			end_unit_turn_button.text = "End Turn (E)\n[Not Yours]"
		elif action_restriction_reason == "not this unit's turn":
			end_unit_turn_button.text = "End Turn (E)\n[Not Turn]"
		elif action_restriction_reason == "already acted this round":
			end_unit_turn_button.text = "End Turn (E)\n[Used]"
		elif action_restriction_reason == "already acted this turn":
			end_unit_turn_button.text = "End Turn (E)\n[Used]"
		else:
			end_unit_turn_button.text = "End Turn (E)\n[N/A]"
	
	# Update End Player Turn button - decoupled from the INSPECTED unit: it is about
	# whose turn it is, not which unit is selected. Enabled only when the game is active
	# AND the current turn player is human-controlled (so it stays disabled during the
	# AI's turn / when it is not this client's turn).
	if end_player_turn_button:
		var current_is_human = _player_is_human(current_player)
		var can_end_player_turn = game_active and current_is_human
		end_player_turn_button.disabled = not can_end_player_turn

		if can_end_player_turn:
			end_player_turn_button.text = "End Player Turn (P)"
		elif not game_active:
			end_player_turn_button.text = "End Player Turn (P)\n[N/A]"
		elif GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
			end_player_turn_button.text = "End Player Turn (P)\n[Not Your Turn]"
		else:
			end_player_turn_button.text = "End Player Turn (P)\n[AI Turn]"
	
	# Unit Summary button is always available when unit is selected (handled in _on_unit_summary_pressed)
	if unit_summary_button:
		unit_summary_button.disabled = false
		if stats_expanded:
			unit_summary_button.text = "Unit Summary ▲"
		else:
			unit_summary_button.text = "Unit Summary ▼"
	
	# Cancel button is always available when unit is selected
	if cancel_button:
		cancel_button.disabled = false
		cancel_button.text = "Cancel (C/ESC)"
	
	# Update Moves button availability
	_update_moves_button_availability()

func _on_move_pressed() -> void:
	"""Handle Move button press - enter movement mode"""
	if not selected_unit:
		return

	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit and our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if not unit_owner or owner_player_id != local_player_id:
			return

		if not GameModeManager.is_my_turn():
			return

		# Submit move action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}

		if GameModeManager.submit_action("unit_move_start", action_data):
			_enter_movement_mode()
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

	# NETWORKED (Phase 2): Wait = commit any staged move (as MOVE_UNIT) then WAIT_UNIT. Both
	# resolve through the CommandApplier on every peer; local UI just closes the command loop.
	if _is_networked_match():
		if not _human_may_command(selected_unit):
			return
		var unit := selected_unit
		_cancel_move_targeting()
		var nid: int = _net_id_of(unit)
		if nid >= 0:
			_net_submit_pending_move(unit)
			NetSession.submit_intent(NetProtocol.make_wait_unit(nid))
		_finish_command(unit)
		return

	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit and our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if not unit_owner or owner_player_id != local_player_id:
			return

		if not GameModeManager.is_my_turn():
			return

		# Submit end unit turn action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}

		if GameModeManager.submit_action("end_unit_turn", action_data):
			# The action will be processed when received back from network
			pass
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
	_commit_tentative_move()

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
	"""Handle End Player Turn button press - ends the entire player's turn"""
	if not PlayerManager:
		return

	var current_player = PlayerManager.get_current_player()
	if not current_player:
		return

	# NETWORKED (Phase 2): route End Player Turn as an authoritative END_TURN command. The
	# turn only advances when the resolved command applies (via the CommandApplier's turn
	# hook) on every peer. Supersedes the legacy GameModeManager branch below when a live
	# NetSession match is connected; leaves it compiling for the legacy transport.
	if _is_networked_match():
		var turn_player := _current_turn_player()
		if not _player_is_human(turn_player):
			return
		var pid: int = int(current_player.player_id)
		NetSession.submit_intent(NetProtocol.make_end_turn(pid))
		return

	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that it's our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw

		# Ensure player_id is int for comparison
		var current_player_id = int(current_player.player_id) if current_player.player_id is String else current_player.player_id

		if current_player_id != local_player_id:
			return

		if not GameModeManager.is_my_turn():
			return

		# Submit end turn action through multiplayer system
		var action_data = {
			"player_id": local_player_id
		}

		if GameModeManager.submit_action("end_turn", action_data):
			# The action will be processed when received back from network
			pass
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
	if unacted > 0:
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
		# never got a turn). Match PlayerTurnPanel's working end-turn path.
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

# Debug method to test button functionality
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
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

			# UNIT CYCLING: Tab (and Q as a fallback that never fights UI focus) selects the
			# next un-acted commandable friendly unit. Skipped while the action menu /
			# targeting is up so it can't yank focus mid-command. Consume the event so Tab
			# does not also trigger the viewport's focus navigation.
			KEY_TAB, KEY_Q:
				if _state == CommandState.ACTION_MENU or _state == CommandState.TARGETING:
					return
				_cycle_to_next_commandable_unit()
				get_viewport().set_input_as_handled()

			# THREAT RANGES: T toggles ALL enemies' danger zones on/off at once -- the
			# PERSISTENT mode (stays up until T again), separate from the transient
			# single-enemy overlay a click/inspect shows.
			KEY_T:
				_toggle_all_enemy_danger()

			# Keyboard shortcuts for actions (only when panel is visible and unit selected)
			KEY_M:
				if visible and selected_unit:
					if movement_mode:
						_exit_movement_mode()
					else:
						_on_move_pressed()
			KEY_E:
				if visible and selected_unit and not movement_mode:
					_on_end_unit_turn_pressed()
			KEY_P:
				if visible and selected_unit and not movement_mode:
					_on_end_player_turn_pressed()
			KEY_S:
				if visible and selected_unit and not movement_mode:
					_on_unit_summary_pressed()
			KEY_C, KEY_ESCAPE:
				# The gate is has_active_interaction() -- the SAME predicate
				# UILayoutManager reads to decide whether Escape should instead open the
				# pause menu (see its _unhandled_input). Sharing one predicate is what
				# makes the ordering airtight: exactly one of the two fires per press.
				# While anything is staged we back out ONE stage here and consume; once
				# the command state is IDLE this does nothing, the press falls through to
				# _unhandled_input, and the pause menu opens.
				if has_active_interaction():
					_on_cancel_pressed()
					# Consume ESC so the board cursor's own ui_cancel handler does not
					# ALSO fire and deselect the unit -- that would collapse the staged
					# FE back-out (drop targeting -> revert tentative -> deselect) into a
					# single press. This panel's _input runs before the cursor's
					# _unhandled_input, so marking it handled keeps the staging intact.
					get_viewport().set_input_as_handled()

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
	var origin: Vector2i = board.cell_of(selected_unit)
	var cells: Array[Vector2i] = MovementResolver.new().reachable_cells(origin, profile, board, selected_unit)
	# Visual only -- the move-target set stays empty so the enemy can never be commanded.
	movement_range_tiles = []
	GameEvents.movement_range_calculated.emit(_cells_to_grid_tiles(cells))


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

	# origin cell (Vector2i(col, row)) straight from the board.
	var origin: Vector2i = board.cell_of(selected_unit)
	# Pass the unit so a multi-cell unit (e.g. a 2x2 boss) only gets cells where its
	# WHOLE footprint fits. Omitting it would resolve every unit as 1x1.
	var cells: Array[Vector2i] = MovementResolver.new().reachable_cells(origin, profile, board, selected_unit)

	# Convert each Vector2i(col, row) into the Vector3(col, 0, row) grid-coord form the
	# visualizer + GameEvents.movement_range_calculated + downstream validation expect.
	movement_range_tiles = _cells_to_grid_tiles(cells)

	# Keep the same highlight flow: emit the calculated range for the visualizer.
	GameEvents.movement_range_calculated.emit(movement_range_tiles)
	return true


func _cells_to_grid_tiles(cells: Array[Vector2i]) -> Array[Vector3]:
	"""Vector2i(col, row) cells -> Vector3(col, 0, row) grid coords used everywhere
	downstream (movement_range_tiles, the visualizer, GameEvents)."""
	var out: Array[Vector3] = []
	for cell in cells:
		out.append(Vector3(cell.x, 0, cell.y))
	return out


func _grid_tile_to_cell(grid_pos: Vector3) -> Vector2i:
	"""Vector3(col, 0, row) grid coord -> Vector2i(col, row) board cell."""
	return Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))


func _is_grid_pos_in_range(grid_pos: Vector3) -> bool:
	"""True when grid_pos matches a tile in the current reachable set (which, for
	character-backed units, is the MovementResolver output)."""
	for tile in movement_range_tiles:
		if abs(tile.x - grid_pos.x) < 0.1 and abs(tile.z - grid_pos.z) < 0.1:
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

	var dest_cell: Vector2i = _grid_tile_to_cell(destination)

	# Validate the destination is within the reachable set before moving.
	if not _is_grid_pos_in_range(destination):
		return true  # handled (rejected); do NOT fall back to BFS for a character unit

	var old_world_pos: Vector3 = selected_unit.global_position
	var old_cell: Vector2i = board.cell_of(selected_unit)

	# Authoritative board move: snaps the unit onto the cell center (preserving its
	# height). We then rewind the world position so the existing tween can animate
	# from the old spot to the cell's world center.
	board.move_unit(selected_unit, dest_cell)

	var new_world_pos: Vector3 = board.cell_to_world(dest_cell)
	new_world_pos.y = old_world_pos.y
	selected_unit.global_position = old_world_pos
	_animate_unit_movement(selected_unit, old_world_pos, new_world_pos)

	# Preserve the legacy unit_moved contract: Vector3(col, 0, row) grid coords.
	var old_grid_pos := Vector3(old_cell.x, 0, old_cell.y)
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
	var cell := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))
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

	# NETWORKED (Phase 2): route the legacy movement-mode commit as an authoritative
	# MOVE_UNIT too, so the keyboard/Move-button path stays in lockstep with the tactical path.
	if _is_networked_match():
		var nid: int = _net_id_of(selected_unit)
		if nid >= 0:
			NetSession.submit_intent(NetProtocol.make_move_unit(nid, _grid_tile_to_cell(destination)))
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

	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if unit_owner and owner_player_id == local_player_id:
			# Submit movement completion action through multiplayer system
			var action_data = {
				"unit_id": selected_unit.get_display_name(),
				"player_id": local_player_id,
				"from_position": selected_unit.global_position,
				"to_position": selected_unit.global_position  # Current position after move
			}
			
			GameModeManager.submit_action("unit_move_complete", action_data)

		# Still do local processing for immediate feedback
	
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
		if abs(tile.x - destination.x) < 0.1 and abs(tile.z - destination.z) < 0.1:
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
	"""True when [param destination] (a Vector3(col,0,row) grid coord) is the selected
	unit's current board cell -- i.e. the player clicked the unit's own tile."""
	if selected_unit == null:
		return false
	var board = CombatServices.board()
	if board == null:
		return false
	var own_cell: Vector2i = board.cell_of(selected_unit)
	var clicked_cell: Vector2i = _grid_tile_to_cell(destination)
	return own_cell == clicked_cell


func _move_to_destination(destination: Vector3) -> void:
	"""Route a validated destination click to either the Fire-Emblem TENTATIVE move
	(character-backed unit, live board, single-player) or the legacy INSTANT-commit
	move (non-character unit / no board / multiplayer, which keeps its existing
	authoritative networked flow). The tentative path is the canonical FE loop:
	the unit moves for preview only and does not commit until the player confirms
	an action (attack or Wait)."""
	# NETWORKED (Phase 2): submit the destination as an authoritative MOVE_UNIT and let every
	# peer apply it through the CommandApplier. Supersedes BOTH the tentative preview and the
	# legacy instant-commit MP branch. Submitted BEFORE any local slide, so apply drives the
	# move origin->dest cleanly on this peer and every observer.
	if _is_networked_match():
		var nid: int = _net_id_of(selected_unit)
		if nid >= 0:
			NetSession.submit_intent(NetProtocol.make_move_unit(nid, _grid_tile_to_cell(destination)))
		_clear_movement_range()
		_update_actions()
		return

	var use_tentative := (
		selected_unit.has_character()
		and CombatServices.board() != null
		and GameSettings.game_mode != GameSettings.GameMode.MULTIPLAYER
	)
	if use_tentative:
		_begin_tentative_move(destination)
	else:
		# Legacy / multiplayer: commit immediately (unchanged behavior).
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

	var dest_cell: Vector2i = _grid_tile_to_cell(destination)
	_tentative_origin_cell = board.cell_of(selected_unit)
	_tentative_origin_world = selected_unit.global_position
	_tentative_dest_cell = dest_cell
	_tentative_unit = selected_unit
	_tentative_active = true

	# Snap the unit onto the destination cell (preserves its height). This updates
	# the visual position AND makes board.cell_of(unit) == dest immediately, with no
	# tween race: every subsequent cell query reads the tentative position at once.
	board.move_unit(selected_unit, dest_cell)

	# The post-move action menu replaces the movement-range highlight.
	_clear_movement_range()
	movement_mode = false

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

	var board = CombatServices.board()
	if board != null:
		# Re-snap to the exact cell center (the unit is already visually here) so the
		# committed logical position is exact regardless of any in-flight animation.
		board.move_unit(unit, dest_cell)

	# mark_moved(): consumes only the MOVE for the turn, not the action. The unit may
	# still have an action pending (the attack we're about to run, or it just Waited).
	if unit.has_method("mark_moved"):
		unit.mark_moved()

	var from_grid := Vector3(origin_cell.x, 0, origin_cell.y)
	var to_grid := Vector3(dest_cell.x, 0, dest_cell.y)
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

	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()


func _clear_tentative_state() -> void:
	"""Drop all tentative-move bookkeeping (does NOT move the unit)."""
	_tentative_active = false
	_tentative_unit = null
	_tentative_origin_cell = Vector2i.ZERO
	_tentative_dest_cell = Vector2i.ZERO
	_tentative_origin_world = Vector3.ZERO


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

	# Create the VIEW MOVES button. This is the golden-path entry to a unit's kit (the
	# demoted per-unit Move/End Turn buttons live hidden in ActionsContainer -- see
	# _ready) so it is promoted next to the header, not buried further down.
	moves_button = Button.new()
	moves_button.text = "VIEW MOVES"
	moves_button.custom_minimum_size = Vector2(0, 40)
	moves_button.pressed.connect(_on_moves_pressed)

	var content_container := get_node_or_null("MarginContainer/ContentContainer")
	if content_container:
		content_container.add_child(moves_button)
		# Right after the header's separator, i.e. as high as possible.
		var header_separator := content_container.get_node_or_null("HSeparator")
		if header_separator:
			content_container.move_child(moves_button, header_separator.get_index() + 1)

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
		var nid: int = _net_id_of(unit)
		if nid >= 0:
			_net_submit_pending_move(unit)
			NetSession.submit_intent(NetProtocol.make_wait_unit(nid))
		_finish_command(unit)
		return

	_commit_tentative_move()
	if unit.has_method("mark_action_completed"):
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

# --- Enemy danger-zone overlays (transient click channel + persistent T channel) ---

func _set_transient_danger_enemy(enemy: Unit) -> void:
	"""Show a TRANSIENT click-inspect danger overlay for [param enemy], replacing any
	previous transient overlay. Cleared on the next click (see _clear_transient_danger).
	Does NOT disturb the persistent T-toggled set. Computed only here (never per frame)."""
	if enemy == null:
		return
	if _transient_danger_enemy == enemy:
		return  # already the inspected enemy -- nothing to redraw
	_clear_transient_danger()
	var vis := _get_movement_visualizer()
	if vis == null:
		return
	var cells: Array[Vector3] = _compute_enemy_threat_cells(enemy)
	if cells.is_empty():
		return
	_transient_danger_enemy = enemy
	if vis.has_method("set_danger_overlay"):
		vis.set_danger_overlay(enemy.get_instance_id(), cells)

func _clear_transient_danger() -> void:
	"""Erase the transient click-inspect overlay, if any. Idempotent. Leaves the enemy's
	overlay UP when the persistent T set also holds it, so a transient click can never
	clear a T overlay -- the two channels are independent."""
	if _transient_danger_enemy == null:
		return
	var enemy := _transient_danger_enemy
	_transient_danger_enemy = null
	if enemy in _persistent_danger_enemies:
		return  # persistent channel still owns this overlay -- keep it drawn
	if not is_instance_valid(enemy):
		return  # a freed enemy's overlay is cleared by _on_unit_eliminated_danger
	var vis := _get_movement_visualizer()
	if vis and vis.has_method("clear_danger_overlay"):
		vis.clear_danger_overlay(enemy.get_instance_id())

func _compute_enemy_threat_cells(enemy: Unit) -> Array[Vector3]:
	"""The reachable cells for an enemy (its danger zone), as Vector3(col,0,row) grid
	coords -- the same MovementResolver flood a friendly unit uses, so the threat shown
	is exactly where the enemy could actually go."""
	if enemy == null or not enemy.has_character():
		return []
	var board = CombatServices.board()
	var profile = enemy.get_movement_profile()
	if board == null or profile == null:
		return []
	var origin: Vector2i = board.cell_of(enemy)
	var cells: Array[Vector2i] = MovementResolver.new().reachable_cells(origin, profile, board, enemy)
	return _cells_to_grid_tiles(cells)

func _toggle_all_enemy_danger() -> void:
	"""The T hotkey (PERSISTENT mode): if the T set is up, clear it; otherwise light up
	every living enemy's zone at once. The on/off decision reads ONLY the persistent set,
	NOT the visualizer's has_any_danger_overlay -- a transient click-inspect overlay must
	not make T think its own set is already shown (which would flip T to a clear)."""
	var vis := _get_movement_visualizer()
	if vis == null:
		return
	if not _persistent_danger_enemies.is_empty():
		_clear_all_persistent_danger()
		_sync_danger_zones_button()
		return
	for enemy in _all_enemy_units():
		var cells: Array[Vector3] = _compute_enemy_threat_cells(enemy)
		if cells.is_empty():
			continue
		if not (enemy in _persistent_danger_enemies):
			_persistent_danger_enemies.append(enemy)
		if vis.has_method("set_danger_overlay"):
			vis.set_danger_overlay(enemy.get_instance_id(), cells)
	_sync_danger_zones_button()

func _clear_all_persistent_danger() -> void:
	"""Turn off the T overlays. Clears each persistent enemy's overlay individually rather
	than the visualizer's clear_all -- so a live TRANSIENT click-inspect overlay survives
	T-off. If the inspected enemy is also in the T set, its overlay is kept (the transient
	channel still owns it)."""
	var vis := _get_movement_visualizer()
	for enemy in _persistent_danger_enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy == _transient_danger_enemy:
			continue  # keep -- the transient channel still wants this overlay
		if vis and vis.has_method("clear_danger_overlay"):
			vis.clear_danger_overlay(enemy.get_instance_id())
	_persistent_danger_enemies.clear()

func _refresh_danger_overlays() -> void:
	"""Recompute both channels' overlays (positions changed on a turn boundary), dropping
	any that died. Cheap: only the already-shown enemies, only on turn start."""
	var vis := _get_movement_visualizer()
	if vis == null:
		return

	# Persistent (T) set.
	var still: Array[Unit] = []
	for enemy in _persistent_danger_enemies:
		if enemy == null or not is_instance_valid(enemy) or not enemy.is_alive():
			if enemy != null and is_instance_valid(enemy) and vis.has_method("clear_danger_overlay"):
				vis.clear_danger_overlay(enemy.get_instance_id())
			continue
		var cells: Array[Vector3] = _compute_enemy_threat_cells(enemy)
		if cells.is_empty():
			# Only clear if the transient channel isn't keeping this overlay alive.
			if enemy != _transient_danger_enemy and vis.has_method("clear_danger_overlay"):
				vis.clear_danger_overlay(enemy.get_instance_id())
		else:
			if vis.has_method("set_danger_overlay"):
				vis.set_danger_overlay(enemy.get_instance_id(), cells)
			still.append(enemy)
	_persistent_danger_enemies = still
	_sync_danger_zones_button()

	# Transient (click-inspect) overlay: recompute the single inspected enemy, or drop it.
	if _transient_danger_enemy != null:
		var e := _transient_danger_enemy
		if not is_instance_valid(e) or not e.is_alive():
			_transient_danger_enemy = null
		else:
			var tcells: Array[Vector3] = _compute_enemy_threat_cells(e)
			if tcells.is_empty():
				_clear_transient_danger()
			elif vis.has_method("set_danger_overlay"):
				vis.set_danger_overlay(e.get_instance_id(), tcells)

func _on_unit_eliminated_danger(unit: Unit, _eliminator: Unit) -> void:
	"""A unit died: expire its danger overlay (both channels) so no stale threat band lingers."""
	if unit == null:
		return
	# ALSO drop it as the SELECTION. This is the only handler the panel has for a death, and
	# selected_unit was previously only cleared on an explicit deselect -- so killing the
	# selected unit left the panel holding a reference that is freed a frame later, and
	# every subsequent _update_actions() dereferenced it. Clearing at the source is what
	# makes that whole class of error impossible rather than merely guarded.
	if unit == selected_unit:
		selected_unit = null
	if unit in _persistent_danger_enemies:
		_persistent_danger_enemies.erase(unit)
		_sync_danger_zones_button()
	if unit == _transient_danger_enemy:
		_transient_danger_enemy = null
	var vis := _get_movement_visualizer()
	if vis and vis.has_method("clear_danger_overlay"):
		vis.clear_danger_overlay(unit.get_instance_id())

func _on_turn_system_activated_danger(turn_system) -> void:
	"""A new turn system became active -- hook its turn_started for danger refresh."""
	_hook_turn_system_for_danger(turn_system)

func _hook_turn_system_for_danger(turn_system) -> void:
	if turn_system == null or not turn_system.has_signal("turn_started"):
		return
	if not turn_system.turn_started.is_connected(_on_turn_started_refresh_danger):
		turn_system.turn_started.connect(_on_turn_started_refresh_danger)

func _on_turn_started_refresh_danger(_who = null) -> void:
	"""Turn boundary: recompute the toggled enemies' danger zones (they may have moved)."""
	_refresh_danger_overlays()

func _all_enemy_units() -> Array[Unit]:
	"""Every living unit NOT owned by the current turn player -- the danger-zone set for
	the T hotkey."""
	var out: Array[Unit] = []
	var me := _current_turn_player()
	for u in _find_all_units_in_scene():
		if u == null or not is_instance_valid(u) or not u.is_alive():
			continue
		var owner := u.get_owner_player()
		if owner == null:
			continue
		if me != null and owner == me:
			continue
		out.append(u)
	return out

# --- Unit cycling ------------------------------------------------------------

func _cycle_to_next_commandable_unit() -> void:
	"""Tab: select the NEXT un-acted, commandable friendly unit (wrap around), driving
	the same cursor selection path a click uses so every downstream system just works.
	Skipped while the action menu / targeting is up (handled by the caller)."""
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

	var origin: Vector2i = board.cell_of(selected_unit)
	# Vector3(col, 0, row) grid coord -> Vector2i(col, row) board cell.
	var aim := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

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


func _execute_move_on_target(aim_cell: Vector2i, move: MoveResource, slot: int) -> void:
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

	# NETWORKED (Phase 2): route the attack/cast as authoritative commands. First submit the
	# staged move (if any) as MOVE_UNIT, then the cast as CAST_MOVE(unit, slot, aim_cell). Both
	# resolve through the CommandApplier -> perform_move on every peer (host stamps the per-cast
	# rng_seed so accuracy/crit rolls match). No local perform_move here -- apply is the ONE
	# mutation point. Remote peers see the cast purely through apply + the effect-layer events.
	#
	# ULTIMATE CUT-IN (MP): deliberately NOT played on this submit path -- it plays where the
	# cast APPLIES, so every peer (submitter included) flashes it in sync and nobody flashes a
	# cast the server then refuses. That apply site is CommandApplier._announce_ultimate_cast
	# (the CAST_MOVE handler), which emits GameEvents.ultimate_casting for the overlay. Playing
	# it here TOO would double-flash for the local caster.
	if _is_networked_match():
		var acting := selected_unit
		var nid: int = _net_id_of(acting)
		if nid >= 0:
			_net_submit_pending_move(acting)
			NetSession.submit_intent(NetProtocol.make_cast_move(nid, slot, aim_cell))
		_cancel_move_targeting()
		_update_actions()
		if nid >= 0:
			_finish_command(acting)
		return

	# ULTIMATE CUT-IN: if this cast is an ultimate (the 4th moveset slot, or a move flagged
	# is_ultimate -- see MoveResource.is_ultimate_move), sweep the full-screen flash across
	# FIRST and hold until it finishes, so the drama precedes the hit. Local / single-player /
	# hotseat path only: the networked branch above returned already, and in a networked match
	# the cast resolves apply-side in CommandApplier._announce_ultimate_cast, which is where the
	# emit lives so every peer sees the flash exactly once. Headless / no overlay -> the helper
	# emits and returns without awaiting, so nothing hangs.
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
	var result: Dictionary = selected_unit.perform_move(slot, aim_cell, board)

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
	move_mode = false
	selected_move_index = -1
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

	var origin: Vector2i = board.cell_of(selected_unit)
	# Vector3(col, 0, row) grid coord -> Vector2i(col, row) board cell.
	var aim := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

	# Forecast only a legal aim that lands on an enemy the caster may attack.
	if not move.can_aim_at(origin, aim, selected_unit):
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
	combat_forecast_panel.show_forecast(selected_unit, enemy, move)

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

	var origin: Vector2i = board.cell_of(selected_unit)
	var aim := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))
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

func _first_enemy_at(board, cell: Vector2i):
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

func _compute_in_range_aim_cells(move: MoveResource) -> Array[Vector2i]:
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
	unaffected -- the two agree cell for cell."""
	var cells: Array[Vector2i] = []
	if not selected_unit or move == null or move.targeting == null:
		return cells

	var board = CombatServices.board()
	if board == null:
		return cells

	var origin: Vector2i = board.cell_of(selected_unit)
	var max_r: int = move.effective_max_range(selected_unit)
	for dx in range(-max_r, max_r + 1):
		for dy in range(-max_r, max_r + 1):
			var aim := origin + Vector2i(dx, dy)
			if move.can_target(origin, aim, selected_unit, board):
				cells.append(aim)
	return cells

func _cells_to_grid_vec3(cells: Array[Vector2i]) -> Array:
	"""Vector2i(col, row) board cells -> Vector3(col, 0, row) grid coords, the form
	GameEvents.attack_range_calculated / aoe_preview_calculated (and the
	TargetingVisualizer) expect."""
	var out: Array = []
	for c in cells:
		out.append(Vector3(c.x, 0, c.y))
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

func _has_eligible_unit_at(board, move: MoveResource, aim: Vector2i) -> bool:
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
		moves_button.text = "MOVES (None)"
		return

	var moveset: Array[MoveResource] = selected_unit.get_moveset()
	var controller = selected_unit.get_moveset_controller()

	var usable := 0
	for move in moveset:
		if move == null:
			continue
		if controller and controller.has_method("can_use"):
			if controller.can_use(move):
				usable += 1
		else:
			usable += 1

	# READ-ONLY VIEW: a unit the local human may NOT command (enemy / AI / not-your-turn)
	# can still open its move list to READ each move's details. Keep the button enabled
	# whenever the unit HAS a moveset and relabel it VIEW MOVES; clicking opens the popup
	# in view-only mode (no targeting, no execution). Cooldown/uses do not matter for
	# reading, so availability here is purely "does it have moves to show".
	if not _human_may_command(selected_unit):
		moves_button.disabled = moveset.is_empty()
		moves_button.text = "MOVES (None)" if moveset.is_empty() else "VIEW MOVES"
		return

	var has_action := true
	if selected_unit.has_method("can_act"):
		has_action = selected_unit.can_act()

	moves_button.disabled = usable == 0 or not has_action

	if moveset.is_empty():
		moves_button.text = "MOVES (None)"
	elif usable == 0:
		moves_button.text = "MOVES (All on cooldown)"
	else:
		moves_button.text = "MOVES (" + str(usable) + " available)"
