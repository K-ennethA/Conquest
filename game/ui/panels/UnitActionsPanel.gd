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
@onready var stats_container: GridContainer = $MarginContainer/ContentContainer/StatsContainer
@onready var health_label: Label = $MarginContainer/ContentContainer/StatsContainer/HealthLabel
@onready var attack_label: Label = $MarginContainer/ContentContainer/StatsContainer/AttackLabel
@onready var defense_label: Label = $MarginContainer/ContentContainer/StatsContainer/DefenseLabel
@onready var speed_label: Label = $MarginContainer/ContentContainer/StatsContainer/SpeedLabel
@onready var movement_label: Label = $MarginContainer/ContentContainer/StatsContainer/MovementLabel
@onready var range_label: Label = $MarginContainer/ContentContainer/StatsContainer/RangeLabel
@onready var end_player_turn_button: Button = $MarginContainer/ContentContainer/EndPlayerTurnButton
@onready var cancel_button: Button = $MarginContainer/ContentContainer/ActionsContainer/CancelButton

var selected_unit: Unit = null
var stats_expanded: bool = false
var movement_mode: bool = false
var movement_range_tiles: Array[Vector3] = []

# Move system variables
var move_selection_panel: MoveSelectionPanel
var moves_button: Button
var move_mode: bool = false
var selected_move_index: int = -1

# FE-style combat forecast overlay (preview-only; never mutates state). Shown
# while targeting an offensive move over an eligible enemy; updated live as the
# cursor moves; hidden when targeting is cancelled/cleared or the move resolves.
var combat_forecast_panel: CombatForecastPanel
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
	
	# Network matches: refresh when an accepted action (ours or the opponent's) lands.
	if GameModeManager and GameModeManager.has_signal("network_action_applied"):
		GameModeManager.network_action_applied.connect(_on_network_action_applied)

	# Hide panel initially
	_hide_panel()
	
	# Style the unit header background
	_setup_unit_header_styling()
	
	# Initialize move system
	_setup_move_system()

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
	if stats_container:
		ConquestTheme.keep_style(stats_container)
		for c in stats_container.get_children():
			if c is Label:
				(c as Label).add_theme_font_size_override("font_size", ConquestTheme.FS_SMALL)
				(c as Label).add_theme_color_override("font_color", ConquestTheme.TEXT_DIM)
	# Tooltips for the commands (mouse users; the key caps cover keyboard / pad).
	if move_button:
		move_button.tooltip_text = "Move this unit. Pick a blue tile, then act or Wait."
	if end_unit_turn_button:
		end_unit_turn_button.tooltip_text = "Wait: end this unit's action for the turn (keeps any move)."
	if unit_summary_button:
		unit_summary_button.tooltip_text = "Show / hide this unit's stats."
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
	_update_unit_stats()
	
	# Show movement range immediately when unit is selected (tactical style)
	_show_movement_range_on_selection()

	_show_panel()

func _show_movement_range_on_selection() -> void:
	"""Show movement range immediately when unit is selected (tactical style)"""
	if not selected_unit:
		return

	# An enemy / AI unit is INSPECTION-only. Still show WHERE IT COULD MOVE (its blue
	# threat range) so the player can read the danger, but via a display-only path that
	# does NOT record those cells as a move destination -- clicking them must never
	# relocate a unit the player can't command.
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

func _update_unit_stats() -> void:
	"""Update the compact stats grid (HP / ATK / DEF / SPD / MOV / RNG)."""
	if not selected_unit:
		return
	_update_header_hp()
	var st := func(n: String) -> int:
		return int(selected_unit.get_stat(n)) if selected_unit.has_method("get_stat") else 0
	if health_label:
		health_label.text = "HP  %d/%d" % [selected_unit.current_health, selected_unit.max_health]
	if attack_label:
		attack_label.text = "ATK  %d" % st.call("attack")
	if defense_label:
		defense_label.text = "DEF  %d" % st.call("defense")
	if speed_label:
		var speed: int = st.call("speed")
		# Show current speed if different from base (due to battle effects)
		var current_speed = speed
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system is SpeedFirstTurnSystem:
				current_speed = (turn_system as SpeedFirstTurnSystem).get_unit_current_speed(selected_unit)
		if current_speed != speed:
			speed_label.text = "SPD  %d (%d)" % [current_speed, speed]
		else:
			speed_label.text = "SPD  %d" % speed
	if movement_label:
		movement_label.text = "MOV  %d" % st.call("movement")
	if range_label:
		range_label.text = "RNG  %d" % st.call("range")

func _on_unit_summary_pressed() -> void:
	"""Handle Unit Summary button press - toggle stats display"""
	stats_expanded = not stats_expanded
	
	if stats_container:
		stats_container.visible = stats_expanded
	
	if unit_summary_button:
		_set_command(unit_summary_button, "Info ▴" if stats_expanded else "Info", InputActions.UNIT_INFO)

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
			unit_summary_button.text = "Info"

		# Clear movement range when unit is deselected
		_clear_movement_range()
		
		_clear_unit_header()
		_hide_panel()

func _clear_movement_range() -> void:
	"""Clear movement range visualization"""
	movement_range_tiles.clear()
	_path_shown = false
	GameEvents.movement_range_cleared.emit()

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
		_hide_panel()
		return
	if move_selection_panel and move_selection_panel.visible:
		move_selection_panel.update_move_cooldowns()
	_update_actions()

func _on_player_turn_changed(player: Player) -> void:
	"""Handle player turn changes"""
	_update_actions()

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
	if unit == null:
		return false
	var current_player := _current_turn_player()
	if current_player == null:
		return false
	if not current_player.owns_unit(unit):
		return false
	return _player_is_human(current_player)

func _update_actions() -> void:
	"""Update available actions based on selected unit and game state"""
	if not selected_unit or not PlayerManager:
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
	# End Turn, or the end_turn action). The hidden button keeps its state in sync
	# for any caller that still reads it.
	if end_player_turn_button:
		var current_is_human = _player_is_human(current_player)
		end_player_turn_button.disabled = not (game_active and current_is_human)
		end_player_turn_button.visible = false

	# Info is always available when a unit is selected.
	if unit_summary_button:
		unit_summary_button.disabled = false
		_set_command(unit_summary_button, "Info ▴" if stats_expanded else "Info", InputActions.UNIT_INFO)

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
	
	# Network match: WAIT is an intent; the host validates it and the accepted
	# action is applied on every peer (NetGameRules), which refreshes this panel.
	if GameModeManager and GameModeManager.is_multiplayer_active():
		if _human_may_command(selected_unit) and GameModeManager.is_my_turn():
			_cancel_move_targeting()
			GameModeManager.request_wait(selected_unit)
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

func _on_end_player_turn_pressed() -> void:
	"""Handle End Player Turn button press - ends the entire player's turn"""
	if not PlayerManager:
		return

	var current_player = PlayerManager.get_current_player()
	if not current_player:
		return

	# Network match: END_TURN is an intent (host-validated, applied on every peer).
	if GameModeManager and GameModeManager.is_multiplayer_active():
		if GameModeManager.is_my_turn():
			_cancel_move_targeting()
			GameModeManager.request_end_turn()
		return

	# Handler-level command guard: the KEY_P shortcut bypasses the disabled button.
	# Only end the player turn when the current turn player is human-controlled (never
	# during the AI's turn).
	if not _player_is_human(_current_turn_player()):
		return

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
		if turn_system is TraditionalTurnSystem:
			var ended := (turn_system as TraditionalTurnSystem).end_turn_manually()
			if not ended:
				push_warning("End Player Turn FAILED: TraditionalTurnSystem.end_turn_manually() returned false (invalid turn state)")
		elif turn_system is SpeedFirstTurnSystem:
			var ended := (turn_system as SpeedFirstTurnSystem).end_turn_manually()
			if not ended:
				push_warning("End Player Turn FAILED: SpeedFirstTurnSystem.end_turn_manually() returned false (invalid turn state)")
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
	if move_selection_panel and move_selection_panel.visible:
		move_selection_panel.hide()
	elif is_targeting_move():
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
	"""Public End Turn entry (the map menu). Same guarded path as the End Player Turn
	button: local-human only, and multiplayer submits the network action."""
	_on_end_player_turn_pressed()


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
	)


func _show_panel() -> void:
	"""Show the actions panel"""
	visible = true
	modulate.a = 1.0
	
	# Force a layout update
	await get_tree().process_frame
	
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

		# Force layout update
		await get_tree().process_frame

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

	# Action shortcuts (named, rebindable actions -- see InputActions). Only while the
	# panel is showing a selected unit. End Player Turn (end_turn) is handled once by
	# PlayerTurnPanel so a single press can never end two turns.
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
	elif event.is_action_pressed(InputActions.CANCEL):
		_on_cancel_pressed()
		# Consume cancel so the board cursor's own cancel handler does not ALSO fire
		# and deselect the unit -- that would collapse the staged FE back-out (drop
		# targeting -> revert tentative -> deselect) into a single press. This
		# panel's _input runs before the cursor's _unhandled_input, so marking it
		# handled keeps the staging intact.
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

	# Network match: never move locally -- submit the intent (see _move_to_destination).
	if GameModeManager and GameModeManager.is_multiplayer_active():
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
	if not unit:
		return

	# Create a tween for smooth movement
	var tween = create_tween()
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

	# Hard gate: a unit that already moved this turn cannot move again, even if a
	# stale range highlight is somehow still present (no active turn system, etc.).
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		_clear_movement_range()
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
		# Could play error sound or show message here
		pass


func _move_to_destination(destination: Vector3) -> void:
	"""Route a validated destination click to either the Fire-Emblem TENTATIVE move
	(character-backed unit, live board, local play), the legacy INSTANT-commit move
	(non-character unit / no board), or -- in a network match -- a MOVE intent.
	The tentative path is the canonical FE loop: the unit moves for preview only and
	does not commit until the player confirms an action (attack or Wait).

	Network matches commit immediately through the host instead of previewing: the
	local board is never mutated outside an accepted action, so every peer's state
	(and the host's desync checkpoints) stay identical."""
	if GameModeManager and GameModeManager.is_multiplayer_active():
		if GameModeManager.is_my_turn():
			GameModeManager.request_move(selected_unit, _grid_tile_to_cell(destination))
		_clear_movement_range()
		movement_mode = false
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

	var dest_cell: Vector3i = _grid_tile_to_cell(destination)
	_tentative_origin_cell = board.cell_of(selected_unit)
	_tentative_origin_world = selected_unit.global_position
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

	# Refresh unit visuals (health bar etc. follow the moved node) and the action UI
	# (Move now disabled; Moves / End Turn drive confirm-or-Wait).
	var tree = get_tree()
	var visual_manager = null
	if tree != null and tree.current_scene != null:
		visual_manager = tree.current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()
	_update_actions()


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

	var from_grid := Cells.to_grid(origin_cell)
	var to_grid := Cells.to_grid(dest_cell)
	# The walk already played when the move was staged; tell the animator the unit is
	# home so unit_moved does not replay a glide from the origin.
	var animator := _unit_animator()
	if animator != null:
		animator.sync_position(unit)
	GameEvents.unit_moved.emit(unit, from_grid, to_grid)

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
	# Cut any walk still playing and put the model back on the (restored) unit.
	var animator := _unit_animator()
	if animator != null:
		animator.stop_motion(unit)

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
	_tentative_active = false
	_tentative_unit = null
	_tentative_origin_cell = Vector3i.ZERO
	_tentative_dest_cell = Vector3i.ZERO
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

	# Combat forecast overlay: one instance, added like the move panel. It is a
	# non-modal, mouse-ignoring floating overlay, so it never blocks targeting
	# clicks. Driven live off GameEvents.cursor_moved (see _on_cursor_moved_forecast)
	# so it updates as the player sweeps the cursor from one enemy to another.
	combat_forecast_panel = CombatForecastPanel.new()
	add_child(combat_forecast_panel)
	if GameEvents and not GameEvents.cursor_moved.is_connected(_on_cursor_moved_forecast):
		GameEvents.cursor_moved.connect(_on_cursor_moved_forecast)

	# Create moves button and add it to the actions container
	moves_button = Button.new()
	moves_button.name = "MovesButton"
	moves_button.text = "Skills"
	moves_button.theme_type_variation = &"HudCommand"
	moves_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	moves_button.focus_mode = Control.FOCUS_NONE
	moves_button.tooltip_text = "Attack or use a skill: pick one of this unit's moves, then a target."
	moves_button.pressed.connect(_on_moves_pressed)
	
	# Add moves button to the actions container (after move button)
	var actions_container = get_node_or_null("MarginContainer/ContentContainer/ActionsContainer")
	if actions_container:
		# Insert after move button
		var move_button_index = -1
		for i in range(actions_container.get_child_count()):
			if actions_container.get_child(i) == move_button:
				move_button_index = i
				break
		
		if move_button_index >= 0:
			actions_container.add_child(moves_button)
			actions_container.move_child(moves_button, move_button_index + 1)
		else:
			actions_container.add_child(moves_button)

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
		return  # stay in targeting mode

	# Preview the full area footprint this aim would affect.
	var area_cells := move.targeting_for(selected_unit).resolve_cells(origin, aim)
	GameEvents.aoe_preview_calculated.emit(_cells_to_grid_vec3(area_cells))

	# Unit-target moves (ENEMY / ALLY / ANY_UNIT) require an eligible occupant at
	# the aim cell; tile-target moves accept any in-range cell.
	if _move_requires_unit_target(move):
		if not _has_eligible_unit_at(board, move, aim):
			return  # stay in targeting mode

	_execute_move_on_target(aim, move, selected_move_index)

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

	# Network match: the attack / ability is an intent. The host validates it and
	# every peer resolves it with the same seeded RNG when it is accepted.
	if GameModeManager and GameModeManager.is_multiplayer_active():
		if GameModeManager.is_my_turn():
			GameModeManager.request_use_move(selected_unit, slot, aim_cell)
		_cancel_move_targeting()
		_update_actions()
		return

	# CONFIRM: clicking a valid target commits the whole action. First lock in the
	# tentative move (snap onto the destination, mark_moved, emit unit_moved) so the
	# attack resolves from the committed cell, THEN execute the move for real below.
	# No-op when there was no tentative move (e.g. attacking without moving, or a
	# legacy/multiplayer committed move already applied).
	_commit_tentative_move()

	var result: Dictionary = selected_unit.perform_move(slot, aim_cell, board)

	if result.get("success", false):
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
	_refresh_path_preview(tile_position)

func _refresh_move_forecast(grid_pos: Vector3) -> void:
	"""Show the forecast for the current move against an eligible ENEMY at grid_pos
	(a legal aim cell), else hide it. Never mutates state -- CombatForecastPanel
	reads MoveExecutor.preview_vs() only."""
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
		combat_forecast_panel.hide_forecast()
		return

	var move: MoveResource = selected_unit.get_move(selected_move_index)
	if move == null or move.targeting == null:
		combat_forecast_panel.hide_forecast()
		return

	var board = CombatServices.board()
	if board == null:
		combat_forecast_panel.hide_forecast()
		return

	var origin: Vector3i = board.cell_of(selected_unit)
	# Vector3(col, floor, row) grid coord -> Vector3i(col, row, floor) board cell.
	var aim := Cells.from_grid(grid_pos)

	# Forecast only a legal aim that lands on an enemy the caster may attack.
	if not move.can_aim_at(origin, aim, selected_unit, board):
		combat_forecast_panel.hide_forecast()
		return

	var enemy = _first_enemy_at(board, aim)
	if enemy == null:
		combat_forecast_panel.hide_forecast()
		return

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
