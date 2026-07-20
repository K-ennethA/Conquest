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
	print("Connecting to GameEvents...")
	if GameEvents:
		GameEvents.unit_selected.connect(_on_unit_selected)
		GameEvents.unit_deselected.connect(_on_unit_deselected)
		GameEvents.cursor_selected.connect(_on_cursor_selected)
		print("GameEvents connections established")
	else:
		print("ERROR: GameEvents not found!")
	
	# Connect to player management events
	if PlayerManager:
		PlayerManager.player_turn_started.connect(_on_player_turn_changed)
		PlayerManager.player_turn_ended.connect(_on_player_turn_changed)
		PlayerManager.game_state_changed.connect(_on_game_state_changed)
		print("PlayerManager connections established")
	else:
		print("ERROR: PlayerManager not found!")
	
	# Connect button signals and ensure they can receive mouse input
	if move_button:
		move_button.mouse_filter = Control.MOUSE_FILTER_STOP
		move_button.pressed.connect(_on_move_pressed)
		print("Move button connected")
	else:
		print("ERROR: Move button not found!")
		
	if end_unit_turn_button:
		end_unit_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_unit_turn_button.pressed.connect(_on_end_unit_turn_pressed)
		# Add mouse event debugging to the button
		end_unit_turn_button.gui_input.connect(_on_end_unit_turn_button_input)
		print("End Unit Turn button connected")
	else:
		print("ERROR: End Unit Turn button not found!")
	
	if unit_summary_button:
		unit_summary_button.mouse_filter = Control.MOUSE_FILTER_STOP
		unit_summary_button.pressed.connect(_on_unit_summary_pressed)
		print("Unit Summary button connected")
	else:
		print("ERROR: Unit Summary button not found!")
	
	if end_player_turn_button:
		end_player_turn_button.mouse_filter = Control.MOUSE_FILTER_STOP
		end_player_turn_button.pressed.connect(_on_end_player_turn_pressed)
		print("End Player Turn button connected")
	else:
		print("ERROR: End Player Turn button not found!")
		
	if cancel_button:
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP
		cancel_button.pressed.connect(_on_cancel_pressed)
		print("Cancel button connected")
	else:
		print("ERROR: Cancel button not found!")
	
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
	print("=== UnitActionsPanel: Unit selection received ===")
	print("Unit: " + unit.name)
	print("Position: " + str(position))
	print("Current selected_unit before: " + (selected_unit.name if selected_unit else "None"))

	# Selection == inspection: any living unit may be selected so the player can read
	# its info (including enemy / AI-owned units). Commanding is gated separately via
	# _human_may_command() -- _update_actions() renders disabled buttons for units the
	# player cannot command. The single-player AI hard-gate, the PlayerManager gate and
	# the Traditional can-act gate that used to REJECT selection here are gone. The
	# multiplayer rejection branch is intentionally kept for this pass.
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER:
		print("Multiplayer mode detected - validating unit ownership")
		
		# Get local player ID and unit owner
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(unit)
		
		print("Local player ID: " + str(local_player_id))
		print("Unit owner: " + (unit_owner.player_name if unit_owner else "None"))
		print("Unit owner ID: " + str(unit_owner.player_id if unit_owner else -1))
		
		if not unit_owner:
			print("Selection rejected: Unit has no owner")
			return
		
		# Ensure player_id is int for comparison and arithmetic
		var owner_player_id = int(unit_owner.player_id) if unit_owner.player_id is String else unit_owner.player_id
		
		if owner_player_id != local_player_id:
			print("Selection rejected: Unit belongs to Player " + str(owner_player_id + 1) + ", you are Player " + str(local_player_id + 1))
			# Could show a message to the player here
			return
		
		print("Unit ownership validated - selection allowed")
	else:
		# Local (single-player / hotseat): accept every selection for inspection.
		# _update_actions() gates the actual commands via _human_may_command().
		print("Local mode: accepting selection for inspection (commands gated in _update_actions)")

	print("Unit selection accepted: " + unit.name)
	selected_unit = unit
	print("Selected unit set to: " + selected_unit.name)
	
	_update_unit_header()
	_update_actions()
	_update_unit_stats()
	
	# Show movement range immediately when unit is selected (tactical style)
	print("About to call _show_movement_range_on_selection()...")
	_show_movement_range_on_selection()
	
	_show_panel()
	print("=== UnitActionsPanel: Unit selection processing complete ===")

func _show_movement_range_on_selection() -> void:
	"""Show movement range immediately when unit is selected (tactical style)"""
	if not selected_unit:
		return

	# Only show range for units the local human may actually command. Selecting an
	# enemy / AI unit is inspection-only, so no range highlight (this also stops the
	# cursor from hijacking clicks into a movement destination for enemy units).
	if not _human_may_command(selected_unit):
		_clear_movement_range()
		return

	# Calculate and show movement range
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

## Turn a snake_case id ("torvald_ironhide") into a display string
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
	
	print("Unit stats " + ("expanded" if stats_expanded else "collapsed"))

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
		
		_clear_unit_header()
		_hide_panel()

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
		print("Move pressed but no unit selected")
		return
	
	print("Move action for unit: " + selected_unit.get_display_name())
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that this is our unit and our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		var unit_owner = PlayerManager.get_player_owning_unit(selected_unit)
		
		# Ensure player_id is int for comparison
		var owner_player_id = int(unit_owner.player_id) if (unit_owner and unit_owner.player_id is String) else (unit_owner.player_id if unit_owner else -1)
		
		if not unit_owner or owner_player_id != local_player_id:
			print("Move action rejected: not your unit")
			return
		
		if not GameModeManager.is_my_turn():
			print("Move action rejected: not your turn in multiplayer")
			return
		
		# Submit move action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("unit_move_start", action_data):
			print("Move action submitted to multiplayer system")
			_enter_movement_mode()
		else:
			print("Move action rejected by multiplayer system")
		return

	# Handler-level command guard: keyboard shortcut (KEY_M) bypasses the disabled
	# button, so re-check command permission here before acting on an enemy / AI unit.
	if not _human_may_command(selected_unit):
		print("Move blocked: " + selected_unit.get_display_name() + " is not commandable by the local player")
		return

	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Validating move with turn system: " + turn_system.system_name)
		
		if turn_system.validate_turn_action(selected_unit, "move"):
			print("Move validated by turn system - entering movement mode")
			_enter_movement_mode()
		else:
			print("Move action not allowed by turn system")
	else:
		print("No active turn system - entering movement mode anyway")
		_enter_movement_mode()

func _on_end_unit_turn_pressed() -> void:
	"""Handle End Unit Turn button press - only ends this unit's turn"""
	print("=== END UNIT TURN BUTTON PRESSED ===")
	print("Ending turn for unit: " + selected_unit.get_display_name())
	
	if not selected_unit:
		print("No unit selected")
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
			print("End unit turn action rejected: not your unit")
			return
		
		if not GameModeManager.is_my_turn():
			print("End unit turn action rejected: not your turn in multiplayer")
			return
		
		# Submit end unit turn action through multiplayer system
		var action_data = {
			"unit_id": selected_unit.get_display_name(),
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("end_unit_turn", action_data):
			print("End unit turn action submitted to multiplayer system")
			# The action will be processed when received back from network
		else:
			print("End unit turn action rejected by multiplayer system")
		return

	# Handler-level command guard: the KEY_E shortcut bypasses the disabled button and
	# the local path calls mark_unit_acted(selected_unit) unchecked, which would let the
	# human end an enemy / AI unit's turn. Re-check command permission here.
	if not _human_may_command(selected_unit):
		print("End unit turn blocked: " + selected_unit.get_display_name() + " is not commandable by the local player")
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
			print("Marking unit acted (Traditional)")
			(turn_system as TraditionalTurnSystem).mark_unit_acted(selected_unit)
		elif turn_system is SpeedFirstTurnSystem:
			print("Marking unit acted (Speed First)")
			(turn_system as SpeedFirstTurnSystem).mark_unit_acted(selected_unit)
		
		# Emit action completed signal
		GameEvents.unit_action_completed.emit(selected_unit, "end_turn")
		
		# Force update unit visuals immediately
		var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
		if visual_manager:
			print("Updating unit visuals via UnitVisualManager")
			visual_manager.update_all_unit_visuals()
		
		print("Unit " + selected_unit.get_display_name() + " has ended their turn")
	else:
		print("No active turn system")
	
	# Update actions to reflect the unit has acted
	_update_actions()
	
	print("=== END UNIT TURN PROCESSING COMPLETE ===")

func _on_end_player_turn_pressed() -> void:
	"""Handle End Player Turn button press - ends the entire player's turn"""
	print("=== END PLAYER TURN BUTTON PRESSED ===")
	
	if not PlayerManager:
		print("PlayerManager not available")
		return
	
	var current_player = PlayerManager.get_current_player()
	if not current_player:
		print("No current player")
		return
	
	print("Ending turn for player: " + current_player.player_name)
	
	# Check if we're in multiplayer mode and submit action through GameModeManager
	if GameSettings.game_mode == GameSettings.GameMode.MULTIPLAYER and GameModeManager:
		# Validate that it's our turn
		var local_player_id_raw = GameModeManager.get_local_player_id()
		var local_player_id = int(local_player_id_raw) if local_player_id_raw is String else local_player_id_raw
		
		# Ensure player_id is int for comparison
		var current_player_id = int(current_player.player_id) if current_player.player_id is String else current_player.player_id
		
		if current_player_id != local_player_id:
			print("End player turn action rejected: not your turn (current: " + str(current_player_id) + ", local: " + str(local_player_id) + ")")
			return
		
		if not GameModeManager.is_my_turn():
			print("End player turn action rejected: not your turn in multiplayer")
			return
		
		# Submit end turn action through multiplayer system
		var action_data = {
			"player_id": local_player_id
		}
		
		if GameModeManager.submit_action("end_turn", action_data):
			print("End player turn action submitted to multiplayer system")
			# The action will be processed when received back from network
		else:
			print("End player turn action rejected by multiplayer system")
		return

	# Handler-level command guard: the KEY_P shortcut bypasses the disabled button.
	# Only end the player turn when the current turn player is human-controlled (never
	# during the AI's turn).
	if not _player_is_human(_current_turn_player()):
		print("End player turn blocked: it is not a human-controlled player's turn")
		return

	# Local game logic (existing)
	if TurnSystemManager.has_active_turn_system():
		var turn_system = TurnSystemManager.get_active_turn_system()
		print("Using turn system to end player turn: " + turn_system.system_name)

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
				print("End Player Turn FAILED: TraditionalTurnSystem.end_turn_manually() returned false (invalid turn state)")
		elif turn_system is SpeedFirstTurnSystem:
			var ended := (turn_system as SpeedFirstTurnSystem).end_turn_manually()
			if not ended:
				print("End Player Turn FAILED: SpeedFirstTurnSystem.end_turn_manually() returned false (invalid turn state)")
		elif turn_system.has_method("end_player_turn"):
			turn_system.end_player_turn()
		else:
			# Last-resort fallback: use PlayerManager directly.
			print("Turn system has no manual end-turn method, using PlayerManager")
			PlayerManager.end_current_player_turn()
	else:
		# Fallback: use PlayerManager directly
		print("No active turn system, using PlayerManager")
		PlayerManager.end_current_player_turn()
	
	print("=== END PLAYER TURN PROCESSING COMPLETE ===")

# Add mouse event debugging
func _gui_input(event: InputEvent) -> void:
	# Only log mouse button events, not movement
	if event is InputEventMouseButton:
		print("UnitActionsPanel mouse button: " + str(event.button_index) + " pressed: " + str(event.pressed))

func _on_end_unit_turn_button_input(event: InputEvent) -> void:
	# Only log mouse button events, not movement
	if event is InputEventMouseButton:
		print("End Unit Turn button mouse: " + str(event.button_index) + " pressed: " + str(event.pressed))

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
		print("Cancel: SELECT MOVE popup already handled this ESC - stopping here")
		return
	if move_selection_panel and move_selection_panel.visible:
		print("Canceling: closing SELECT MOVE popup")
		move_selection_panel.hide()
	elif is_targeting_move():
		print("Canceling move targeting")
		_cancel_move_targeting()
		_update_actions()
	elif _tentative_active:
		print("Canceling tentative move - reverting to origin")
		_revert_tentative_move()
		# Unit is fully available again: re-show its movement range and refresh actions.
		_calculate_and_show_movement_range()
		_update_actions()
	elif movement_mode:
		print("Canceling movement mode")
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
		var margin_left = margin_container.get_theme_constant("margin_left")
		var margin_right = margin_container.get_theme_constant("margin_right") 
		var margin_top = margin_container.get_theme_constant("margin_top")
		var margin_bottom = margin_container.get_theme_constant("margin_bottom")
		
		var needed_size = Vector2(
			content_min_size.x + margin_left + margin_right,
			content_min_size.y + margin_top + margin_bottom
		)
		
		# Try to set the size
		custom_minimum_size = needed_size
		size = needed_size
		
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

# Debug method to test button functionality
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_F1:
				print("F1 pressed - testing End Unit Turn button directly")
				_on_end_unit_turn_pressed()
			KEY_F2:
				print("F2 pressed - showing panel for testing")
				_show_panel()
			KEY_F3:
				print("F3 pressed - hiding panel")
				_hide_panel()
			KEY_F4:
				print("F4 pressed - testing manual unit selection")
				_test_manual_unit_selection()
			KEY_F5:
				print("F5 pressed - testing movement range calculation directly")
				_test_movement_range_calculation_direct()
			
			# Keyboard shortcuts for actions (only when panel is visible and unit selected)
			KEY_M:
				if visible and selected_unit:
					if movement_mode:
						print("M key pressed - canceling movement mode")
						_exit_movement_mode()
					else:
						print("M key pressed - triggering Move action")
						_on_move_pressed()
			KEY_E:
				if visible and selected_unit and not movement_mode:
					print("E key pressed - triggering End Unit Turn action")
					_on_end_unit_turn_pressed()
			KEY_P:
				if visible and selected_unit and not movement_mode:
					print("P key pressed - triggering End Player Turn action")
					_on_end_player_turn_pressed()
			KEY_S:
				if visible and selected_unit and not movement_mode:
					print("S key pressed - triggering Unit Summary toggle")
					_on_unit_summary_pressed()
			KEY_C, KEY_ESCAPE:
				if visible and selected_unit:
					print("C/ESC key pressed - triggering Cancel action")
					_on_cancel_pressed()
					# Consume ESC so the board cursor's own ui_cancel handler does not
					# ALSO fire and deselect the unit -- that would collapse the staged
					# FE back-out (drop targeting -> revert tentative -> deselect) into a
					# single press. This panel's _input runs before the cursor's
					# _unhandled_input, so marking it handled keeps the staging intact.
					get_viewport().set_input_as_handled()

func _test_manual_unit_selection() -> void:
	"""Test manual unit selection for debugging"""
	print("=== Testing manual unit selection ===")
	
	# Find a unit to test with
	var scene_root = get_tree().current_scene
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				print("Found test unit: " + child.name)
				var world_pos = child.global_position
				print("Manually triggering unit selection...")
				_on_unit_selected(child, world_pos)
				return
	
	print("No units found for testing")

func _test_movement_range_calculation_direct() -> void:
	"""Test movement range calculation directly"""
	print("=== Testing Movement Range Calculation Directly ===")
	
	# Find a unit to test with
	var scene_root = get_tree().current_scene
	var player1_node = scene_root.get_node_or_null("Map/Player1")
	if player1_node:
		for child in player1_node.get_children():
			if child is Unit:
				print("Found test unit: " + child.name)
				
				# Set this as selected unit temporarily
				selected_unit = child
				
				# Test movement range calculation
				print("Testing movement range calculation...")
				_calculate_and_show_movement_range()
				
				# Wait 3 seconds then clear
				await get_tree().create_timer(3.0).timeout
				_clear_movement_range()
				selected_unit = null
				return
	
	print("No units found for testing")

# Movement system implementation
func _enter_movement_mode() -> void:
	"""Enter movement mode - show movement range and wait for destination selection"""
	if not selected_unit:
		return

	# A tentative move is already staged (unit visually at its destination, awaiting
	# confirm/cancel). Re-entering movement here would let it move a second time, so
	# block until the tentative move is confirmed or cancelled.
	if _tentative_active:
		print("Tentative move in progress - re-entering movement blocked")
		return

	# A unit that already moved this turn cannot move again.
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		print("Unit has already moved this turn - movement blocked")
		return

	print("=== Entering Movement Mode ===")
	movement_mode = true
	
	# Calculate and show movement range
	_calculate_and_show_movement_range()
	
	# Update UI to show movement mode
	_update_movement_ui()
	
	print("Movement mode active - select destination tile")

func _exit_movement_mode() -> void:
	"""Exit movement mode and return to normal selection"""
	print("=== Exiting Movement Mode ===")
	movement_mode = false
	movement_range_tiles.clear()
	
	# Clear movement range visualization
	GameEvents.movement_range_cleared.emit()
	
	# Update UI back to normal
	_update_actions()

func _calculate_and_show_movement_range() -> void:
	"""Calculate movement range and show visual indicators"""
	if not selected_unit:
		print("DEBUG: No selected unit for movement range calculation")
		return

	# Inspection-only units (enemy / AI, or not this player's turn) show no range.
	if not _human_may_command(selected_unit):
		print("DEBUG: " + selected_unit.get_display_name() + " is not commandable by the local player - no movement range shown")
		_clear_movement_range()
		return

	# A unit that has already moved this turn shows NO movement range and cannot
	# move again (until reset at its next turn start, or an extra-move grant). This
	# gates BOTH the select-time tactical highlight (_show_movement_range_on_selection)
	# and movement mode (_enter_movement_mode), since both funnel through here.
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		print("DEBUG: " + selected_unit.get_display_name() + " has already moved this turn - no movement range shown")
		_clear_movement_range()
		return

	print("DEBUG: Calculating movement range for " + selected_unit.get_display_name())

	# Character-backed units route the range through MovementResolver + the shared
	# BoardAdapter (CombatServices.board()). Non-character units, or the case where
	# no live board exists yet, fall through to the legacy BFS below.
	if _try_show_movement_range_via_resolver():
		return

	# Get unit's current position
	var grid = preload("res://board/Grid.tres")
	var unit_world_pos = selected_unit.global_position
	var unit_grid_pos = grid.calculate_grid_coordinates(unit_world_pos)
	
	print("DEBUG: Unit world pos: " + str(unit_world_pos))
	print("DEBUG: Unit grid pos: " + str(unit_grid_pos))
	
	# Get movement range from unit
	var movement_range = selected_unit.get_movement_range()
	print("DEBUG: Movement range: " + str(movement_range))
	
	if movement_range <= 0:
		print("DEBUG: Movement range is 0 or negative, aborting")
		return
	
	# Calculate reachable tiles using BFS (similar to board.gd logic)
	movement_range_tiles = _calculate_reachable_tiles(unit_grid_pos, movement_range, grid)
	
	print("DEBUG: Calculated " + str(movement_range_tiles.size()) + " reachable tiles")
	
	if movement_range_tiles.size() == 0:
		print("DEBUG: No reachable tiles calculated, aborting")
		return
	
	# Show first few tiles for debugging
	for i in range(min(3, movement_range_tiles.size())):
		print("DEBUG: Reachable tile " + str(i) + ": " + str(movement_range_tiles[i]))
	
	# Emit event to show movement range visually
	print("DEBUG: Emitting movement_range_calculated signal with " + str(movement_range_tiles.size()) + " tiles")
	GameEvents.movement_range_calculated.emit(movement_range_tiles)
	print("DEBUG: Signal emitted")

# --- MovementResolver / BoardAdapter integration (character-backed units) ----

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

	print("DEBUG: Resolver produced " + str(movement_range_tiles.size()) + " reachable tiles from origin " + str(origin))

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
		print("DEBUG: Destination cell " + str(dest_cell) + " not in reachable set - move rejected")
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
	print("Unit moved from " + str(old_grid_pos) + " to " + str(destination) + " (via BoardAdapter)")
	GameEvents.unit_moved.emit(selected_unit, old_grid_pos, destination)

	# mark_moved() semantics: consumes the move but NOT the action.
	_complete_movement_action()
	return true


func _calculate_reachable_tiles(start_pos: Vector3, max_distance: int, grid: Grid) -> Array[Vector3]:
	"""Calculate all tiles reachable within movement range using BFS"""
	print("DEBUG: BFS starting from " + str(start_pos) + " with max distance " + str(max_distance))
	
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
	
	print("DEBUG: BFS completed, found " + str(reachable.size()) + " reachable tiles")
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
	var scene_root = get_tree().current_scene
	
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
	
	# Show movement range info in unit summary if expanded
	if stats_expanded and selected_unit:
		var movement_range = selected_unit.get_movement_range()
		print("Movement mode active - unit can move " + str(movement_range) + " tiles")
		print("Highlighted " + str(movement_range_tiles.size()) + " reachable tiles")

func _on_cursor_selected(position: Vector3) -> void:
	"""Handle cursor selection - used for movement destination"""
	print("=== Cursor Selected ===")
	print("Selected position: " + str(position))
	
	# Check if we're in movement mode or if there's a movement range displayed
	var unit_actions_panel = _get_unit_actions_panel()
	if unit_actions_panel and unit_actions_panel.has_method("is_showing_movement_range"):
		if unit_actions_panel.is_showing_movement_range():
			print("Movement range is showing - checking if position is valid destination")
			# Let the UnitActionsPanel handle the movement
			unit_actions_panel.handle_movement_destination_selected(position)
			return
	
	# If not in movement mode, handle normal selection
	if not movement_mode or not selected_unit:
		return
	
	print("Movement mode active - processing destination selection")
	
	# Check if position is within movement range
	if position in movement_range_tiles:
		print("Valid movement destination - executing move")
		_execute_movement(position)
	else:
		print("Invalid movement destination - not in range")

func _get_unit_actions_panel() -> Node:
	"""Get reference to UnitActionsPanel"""
	var scene_root = get_tree().current_scene
	var ui_layout = scene_root.get_node_or_null("UI/GameUILayout")
	if ui_layout:
		return ui_layout.get_node_or_null("MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel")
	return null

func _execute_movement(destination: Vector3) -> void:
	"""Execute the actual unit movement"""
	if not selected_unit:
		return
	
	print("=== Executing Unit Movement ===")
	print("Moving " + selected_unit.get_display_name() + " to " + str(destination))

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

	print("Unit moved from " + str(old_grid_pos) + " to " + str(destination))

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
	
	print("Animating movement from " + str(from_pos) + " to " + str(to_pos))
	
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
	
	print("=== Completing Movement Action ===")
	
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
			
			if GameModeManager.submit_action("unit_move_complete", action_data):
				print("Movement completion action submitted to multiplayer system")
			else:
				print("Movement completion action rejected by multiplayer system")
		
		# Still do local processing for immediate feedback
	
	# Moving consumes only the unit's MOVE for this turn, not its action: the unit
	# can still attack / use a move, or End Turn. Re-moving is blocked by can_move()
	# until an ability or move effect grants extra movement.
	selected_unit.mark_moved()
	
	# Force update unit visuals
	var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		print("Updating unit visuals via UnitVisualManager")
		visual_manager.update_all_unit_visuals()
	
	print("Movement action completed")

func _on_movement_animation_complete(unit: Unit) -> void:
	"""Called when movement animation finishes"""
	print("Movement animation completed for " + unit.get_display_name())

# tactical style movement handling
func is_showing_movement_range() -> bool:
	"""Check if movement range is currently displayed"""
	var showing = movement_range_tiles.size() > 0
	print("DEBUG: is_showing_movement_range() = " + str(showing) + " (tiles: " + str(movement_range_tiles.size()) + ")")
	return showing

func handle_movement_destination_selected(destination: Vector3) -> void:
	"""Handle selection of a movement destination (tactical style)"""
	print("DEBUG: handle_movement_destination_selected called with destination: " + str(destination))
	
	if not selected_unit:
		print("DEBUG: No unit selected for movement")
		return

	# Hard gate: a unit that already moved this turn cannot move again, even if a
	# stale range highlight is somehow still present (no active turn system, etc.).
	if selected_unit.has_method("can_move") and not selected_unit.can_move():
		print("DEBUG: " + selected_unit.get_display_name() + " has already moved this turn - destination ignored")
		_clear_movement_range()
		return

	print("DEBUG: Selected unit: " + selected_unit.get_display_name())
	print("DEBUG: Available movement tiles: " + str(movement_range_tiles.size()))
	
	# Check if destination is in movement range
	var is_valid_destination = false
	for tile in movement_range_tiles:
		if abs(tile.x - destination.x) < 0.1 and abs(tile.z - destination.z) < 0.1:
			is_valid_destination = true
			print("DEBUG: Found matching tile: " + str(tile) + " for destination: " + str(destination))
			break
	
	print("DEBUG: Is valid destination: " + str(is_valid_destination))
	
	if is_valid_destination:
		print("DEBUG: Valid destination - moving to destination")

		# Validate with turn system
		if TurnSystemManager.has_active_turn_system():
			var turn_system = TurnSystemManager.get_active_turn_system()
			if turn_system.validate_turn_action(selected_unit, "move"):
				_move_to_destination(destination)
			else:
				print("DEBUG: Movement not allowed by turn system")
		else:
			_move_to_destination(destination)
	else:
		print("DEBUG: Invalid destination - not in movement range")
		# Could play error sound or show message here


func _move_to_destination(destination: Vector3) -> void:
	"""Route a validated destination click to either the Fire-Emblem TENTATIVE move
	(character-backed unit, live board, single-player) or the legacy INSTANT-commit
	move (non-character unit / no board / multiplayer, which keeps its existing
	authoritative networked flow). The tentative path is the canonical FE loop:
	the unit moves for preview only and does not commit until the player confirms
	an action (attack or Wait)."""
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
	
	print("=== Executing Movement to Destination ===")
	print("Moving " + selected_unit.get_display_name() + " to " + str(destination))

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

	print("Unit moved from " + str(old_grid_pos) + " to " + str(destination))

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
	var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()
	_update_actions()

	print("Tentative move: " + selected_unit.get_display_name()
		+ " " + str(_tentative_origin_cell) + " -> " + str(dest_cell)
		+ " (preview only, awaiting confirm/cancel)")


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

	var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()

	print("Committed tentative move: " + unit.get_display_name()
		+ " " + str(origin_cell) + " -> " + str(dest_cell))


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

	var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
	if visual_manager:
		visual_manager.update_all_unit_visuals()

	print("Reverted tentative move: " + unit.get_display_name() + " back to " + str(origin_cell))


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
	moves_button.text = "MOVES"
	moves_button.custom_minimum_size = Vector2(120, 40)
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
	
	print("Move system initialized")

func _on_moves_pressed() -> void:
	"""Handle Moves button press - list the selected unit's real moveset.

	Gated on the unit still having its action for the turn. Character-backed units
	expose their authored MoveResource moveset via get_moveset(); legacy
	(non-character) units have no moveset, so the panel degrades to an empty list."""
	if not selected_unit:
		return

	# Handler-level command guard: the KEY_P/Moves shortcut bypasses the disabled
	# button. Only the local human may open moves for a unit they command.
	if not _human_may_command(selected_unit):
		print("Moves blocked: " + selected_unit.get_display_name() + " is not commandable by the local player")
		return

	# The unit must still have its action available this turn.
	if selected_unit.has_method("can_act") and not selected_unit.can_act():
		print("Moves unavailable: " + selected_unit.get_display_name() + " has no action left")
		return

	print("Moves button pressed for " + selected_unit.get_display_name())

	# MoveSelectionPanel reads unit.get_moveset() / get_moveset_controller() itself,
	# so this works for both character units (real moveset) and legacy units (empty).
	if not selected_unit.has_character():
		# LEGACY guard: no CharacterResource -> no MoveResource moveset. Show the
		# panel anyway (it renders "No moves available") instead of fabricating moves.
		print("Legacy unit has no character moveset - showing empty move panel")
	move_selection_panel.show_moves_for_unit(selected_unit)

func _on_move_selected(slot: int) -> void:
	"""A move slot was chosen from the panel: enter targeting for that move and
	publish its in-range aim cells so the TargetingVisualizer can highlight them."""
	if not selected_unit:
		return

	var move: MoveResource = selected_unit.get_move(slot)
	if move == null or move.targeting == null:
		print("Move slot " + str(slot) + " is empty or has no targeting pattern - ignoring")
		return

	selected_move_index = slot
	move_mode = true

	print("Move selected: " + move.display_name + " (slot " + str(slot) + ")")

	# Compute every legal aim cell (within [min_range, max_range]) from the unit's
	# current board cell and emit them as Vector3 grid coords for the visualizer.
	var aim_cells := _compute_in_range_aim_cells(move)
	GameEvents.attack_range_calculated.emit(_cells_to_grid_vec3(aim_cells))
	print("Targeting active for " + move.display_name + " - " + str(aim_cells.size()) + " in-range cell(s)")

	# Seed the forecast off the cursor's current tile, so if it already rests on an
	# enemy the prediction shows at once instead of waiting for the next move.
	_refresh_move_forecast(_last_cursor_tile)

func _on_move_cancelled() -> void:
	"""Handle move selection cancellation (panel BACK button / its own ESC)."""
	print("Move selection cancelled")
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
		print("No live board (CombatServices.board() is null) - cannot resolve move target")
		_cancel_move_targeting()
		return

	var origin: Vector2i = board.cell_of(selected_unit)
	# Vector3(col, 0, row) grid coord -> Vector2i(col, row) board cell.
	var aim := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

	# Must be a legal aim point for this pattern (respects min/max range).
	if not move.can_aim_at(origin, aim):
		print("Aim cell " + str(aim) + " out of range for " + move.display_name + " - keep targeting")
		return  # stay in targeting mode

	# Preview the full area footprint this aim would affect.
	var area_cells := move.targeting.resolve_cells(origin, aim)
	GameEvents.aoe_preview_calculated.emit(_cells_to_grid_vec3(area_cells))

	# Unit-target moves (ENEMY / ALLY / ANY_UNIT) require an eligible occupant at
	# the aim cell; tile-target moves accept any in-range cell.
	if _move_requires_unit_target(move):
		if not _has_eligible_unit_at(board, move, aim):
			print("No eligible target unit at " + str(aim) + " for " + move.display_name + " - keep targeting")
			return  # stay in targeting mode

	_execute_move_on_target(aim, move, selected_move_index)

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

	# CONFIRM: clicking a valid target commits the whole action. First lock in the
	# tentative move (snap onto the destination, mark_moved, emit unit_moved) so the
	# attack resolves from the committed cell, THEN execute the move for real below.
	# No-op when there was no tentative move (e.g. attacking without moving, or a
	# legacy/multiplayer committed move already applied).
	_commit_tentative_move()

	print("Executing " + move.display_name + " aimed at cell " + str(aim_cell))

	var result: Dictionary = selected_unit.perform_move(slot, aim_cell, board)

	if result.get("success", false):
		# Cooldown / charge bookkeeping (null-safe: legacy units have no controller).
		var controller = selected_unit.get_moveset_controller()
		if controller and controller.has_method("on_used"):
			controller.on_used(move)

		# Surface the resolved effect events for downstream systems / debugging.
		print("Move resolved successfully. Events: " + str(result.get("events", [])))

		# Using a move consumes the unit's action for the turn.
		if selected_unit.has_method("mark_action_completed"):
			selected_unit.mark_action_completed("move")

		# Refresh the move panel's cooldown display if it is still visible.
		if move_selection_panel and move_selection_panel.visible:
			move_selection_panel.update_move_cooldowns()

		# Clear targeting highlights (also re-emitted by _cancel_move_targeting below).
		GameEvents.targeting_cleared.emit()

		# Force an immediate unit-visual refresh, mirroring the movement path.
		var visual_manager = get_tree().current_scene.get_node_or_null("UnitVisualManager")
		if visual_manager:
			visual_manager.update_all_unit_visuals()
	else:
		print("Move failed: " + str(result.get("reason", "unknown")))

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
	if combat_forecast_panel:
		combat_forecast_panel.hide_forecast()

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
	reads MoveExecutor.preview_vs() only."""
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

	var origin: Vector2i = board.cell_of(selected_unit)
	# Vector3(col, 0, row) grid coord -> Vector2i(col, row) board cell.
	var aim := Vector2i(int(round(grid_pos.x)), int(round(grid_pos.z)))

	# Forecast only a legal aim that lands on an enemy the caster may attack.
	if not move.can_aim_at(origin, aim):
		combat_forecast_panel.hide_forecast()
		return

	var enemy = _first_enemy_at(board, aim)
	if enemy == null:
		combat_forecast_panel.hide_forecast()
		return

	combat_forecast_panel.show_forecast(selected_unit, enemy, move)

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
	i.e. cells whose Manhattan distance is within [min_range, max_range]."""
	var cells: Array[Vector2i] = []
	if not selected_unit or move == null or move.targeting == null:
		return cells

	var board = CombatServices.board()
	if board == null:
		return cells

	var origin: Vector2i = board.cell_of(selected_unit)
	var pattern := move.targeting
	var max_r: int = pattern.max_range
	for dx in range(-max_r, max_r + 1):
		for dy in range(-max_r, max_r + 1):
			var aim := origin + Vector2i(dx, dy)
			if pattern.in_range(origin, aim):
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
	if move == null or move.targeting == null:
		return false
	match move.targeting.target_kind:
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

	var kind = move.targeting.target_kind
	for occupant in occupants:
		if occupant == null:
			continue
		match kind:
			CombatTypes.TargetKind.ENEMY:
				if board.are_enemies(selected_unit, occupant):
					return true
			CombatTypes.TargetKind.ALLY:
				if occupant == selected_unit:
					if move.targeting.affects_caster_tile:
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

	var has_action := true
	if selected_unit.has_method("can_act"):
		has_action = selected_unit.can_act()

	# Also gate on command permission so an enemy / AI unit's Moves button stays
	# disabled during inspection.
	moves_button.disabled = usable == 0 or not has_action or not _human_may_command(selected_unit)

	if moveset.is_empty():
		moves_button.text = "MOVES (None)"
	elif usable == 0:
		moves_button.text = "MOVES (All on cooldown)"
	else:
		moves_button.text = "MOVES (" + str(usable) + " available)"
