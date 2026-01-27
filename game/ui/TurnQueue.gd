extends Control

class_name TurnQueue

# Unified UI component for Speed First turn system
# Combines turn indicator and queue display into one cohesive interface

@onready var main_container: VBoxContainer = $MainContainer
@onready var current_unit_container: VBoxContainer = $MainContainer/CurrentUnitContainer
@onready var current_unit_label: Label = $MainContainer/CurrentUnitContainer/CurrentUnitLabel
@onready var round_info_label: Label = $MainContainer/CurrentUnitContainer/RoundInfoLabel
@onready var queue_section: VBoxContainer = $MainContainer/QueueSection
@onready var queue_title_label: Label = $MainContainer/QueueSection/QueueTitle
@onready var queue_controls: HBoxContainer = $MainContainer/QueueSection/QueueControls
@onready var scroll_left_button: Button = $MainContainer/QueueSection/QueueControls/ScrollLeftButton
@onready var queue_container: HBoxContainer = $MainContainer/QueueSection/QueueControls/QueueContainer
@onready var scroll_right_button: Button = $MainContainer/QueueSection/QueueControls/ScrollRightButton

var turn_system: SpeedFirstTurnSystem = null
var unit_portraits: Array[Control] = []

# Portrait settings
const PORTRAIT_SIZE = Vector2(64, 64)
const PORTRAIT_MARGIN = 8
const PORTRAITS_PER_PAGE = 4  # Show 4 portraits at a time

# Scroll state
var scroll_offset: int = 0
var total_units: int = 0

# Signals for interaction
signal unit_portrait_clicked(unit: Unit)
signal unit_portrait_hovered(unit: Unit)
signal unit_portrait_unhovered(unit: Unit)

func _ready() -> void:
	print("TurnQueue: _ready() called")
	
	# Make visible initially for testing
	visible = true
	
	# Connect scroll buttons
	if scroll_left_button:
		scroll_left_button.pressed.connect(_on_scroll_left_pressed)
	if scroll_right_button:
		scroll_right_button.pressed.connect(_on_scroll_right_pressed)
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		print("TurnQueue: Connected to TurnSystemManager")
	else:
		print("TurnQueue: TurnSystemManager not found!")
	
	# Initial setup
	_update_display()
	print("TurnQueue: Initialized")
	
	# Test display with dummy data
	_test_display()

func _on_turn_system_activated(system: TurnSystemBase) -> void:
	"""Handle turn system activation"""
	print("TurnQueue: Turn system activated - " + system.system_name)
	
	if system is SpeedFirstTurnSystem:
		turn_system = system as SpeedFirstTurnSystem
		print("TurnQueue: Speed First system detected, connecting events")
		
		# Connect to turn system events
		if turn_system.turn_started.is_connected(_on_turn_started):
			turn_system.turn_started.disconnect(_on_turn_started)
		if turn_system.turn_ended.is_connected(_on_turn_ended):
			turn_system.turn_ended.disconnect(_on_turn_ended)
		
		turn_system.turn_started.connect(_on_turn_started)
		turn_system.turn_ended.connect(_on_turn_ended)
		
		_update_display()
		visible = true
		print("TurnQueue: Made visible for Speed First system")
	else:
		# Hide for non-speed-first systems
		turn_system = null
		visible = false
		print("TurnQueue: Hidden for non-Speed First system (" + system.system_name + ")")

func _on_turn_started(player_or_unit) -> void:
	"""Handle turn start"""
	_update_display()

func _on_turn_ended(player_or_unit) -> void:
	"""Handle turn end"""
	_update_display()

func _update_display() -> void:
	"""Update the unified turn display"""
	if not queue_container:
		print("TurnQueue: queue_container is null!")
		return
	
	# Clear existing portraits
	_clear_portraits()
	
	if not turn_system:
		_show_inactive_state()
		return
	
	# Get current turn information
	var current_unit = turn_system.get_current_acting_unit()
	var progress = turn_system.get_current_round_progress()
	var queue = turn_system.get_turn_queue()
	
	print("TurnQueue: Updating unified display with " + str(queue.size()) + " units in queue")
	
	# Update current unit display
	_update_current_unit_display(current_unit, progress)
	
	# Update queue display
	_update_queue_display(queue, current_unit)

func _show_inactive_state() -> void:
	"""Show inactive state when no turn system is active"""
	if current_unit_label:
		current_unit_label.text = "No Active Turn System"
	if round_info_label:
		round_info_label.text = "Waiting for game to start..."
	if queue_title_label:
		queue_title_label.text = "Turn Queue (Inactive)"
	print("TurnQueue: No turn system active")

func _update_current_unit_display(current_unit: Unit, progress: Dictionary) -> void:
	"""Update the current unit information display"""
	if not current_unit_label or not round_info_label:
		return
	
	if current_unit:
		# Show current acting unit with player info
		var player = current_unit.get_owner_player()
		var player_name = player.get_display_name() if player else "Unknown"
		current_unit_label.text = current_unit.get_display_name() + " Acting (" + player_name + ")"
		
		# Show detailed round and speed info (simplified for center display)
		var round_num = progress.get("round_number", 1)
		var current_speed = progress.get("current_unit_speed", 0)
		var units_remaining = progress.get("units_remaining", 0)
		
		round_info_label.text = "Round " + str(round_num) + " • Speed: " + str(current_speed) + " • " + str(units_remaining) + " units left"
	else:
		current_unit_label.text = "No Acting Unit"
		round_info_label.text = "Round " + str(progress.get("round_number", 1))

func _update_queue_display(queue: Array, current_unit: Unit) -> void:
	"""Update the turn queue display with scroll functionality"""
	if not queue_title_label:
		return
	
	total_units = queue.size()
	
	# Update queue title with scroll info
	var visible_count = min(PORTRAITS_PER_PAGE, total_units)
	var page_info = ""
	if total_units > PORTRAITS_PER_PAGE:
		var current_page = (scroll_offset / PORTRAITS_PER_PAGE) + 1
		var total_pages = (total_units + PORTRAITS_PER_PAGE - 1) / PORTRAITS_PER_PAGE
		page_info = " (Page " + str(current_page) + "/" + str(total_pages) + ")"
	
	queue_title_label.text = "Upcoming Turns (" + str(visible_count) + "/" + str(total_units) + " shown)" + page_info
	
	# Update scroll button states
	_update_scroll_buttons()
	
	# Create portraits for visible units
	var start_index = scroll_offset
	var end_index = min(start_index + PORTRAITS_PER_PAGE, total_units)
	
	for i in range(start_index, end_index):
		var unit = queue[i]
		var is_current = (i == 0 and unit == current_unit)
		var portrait = _create_unit_portrait(unit, is_current, i)
		queue_container.add_child(portrait)
		unit_portraits.append(portrait)
		print("TurnQueue: Added portrait for " + unit.get_display_name() + " at position " + str(i))

func _update_scroll_buttons() -> void:
	"""Update scroll button enabled states"""
	if not scroll_left_button or not scroll_right_button:
		return
	
	# Left button: enabled if we can scroll left
	scroll_left_button.disabled = (scroll_offset <= 0)
	
	# Right button: enabled if we can scroll right
	var max_scroll = max(0, total_units - PORTRAITS_PER_PAGE)
	scroll_right_button.disabled = (scroll_offset >= max_scroll)
	
	# Hide buttons if not needed
	var needs_scrolling = total_units > PORTRAITS_PER_PAGE
	scroll_left_button.visible = needs_scrolling
	scroll_right_button.visible = needs_scrolling

func _on_scroll_left_pressed() -> void:
	"""Handle left scroll button press"""
	if scroll_offset > 0:
		scroll_offset = max(0, scroll_offset - PORTRAITS_PER_PAGE)
		_update_display()
		print("TurnQueue: Scrolled left to offset " + str(scroll_offset))

func _on_scroll_right_pressed() -> void:
	"""Handle right scroll button press"""
	var max_scroll = max(0, total_units - PORTRAITS_PER_PAGE)
	if scroll_offset < max_scroll:
		scroll_offset = min(max_scroll, scroll_offset + PORTRAITS_PER_PAGE)
		_update_display()
		print("TurnQueue: Scrolled right to offset " + str(scroll_offset))

func _clear_portraits() -> void:
	"""Clear all unit portraits and reset scroll"""
	for portrait in unit_portraits:
		if portrait and is_instance_valid(portrait):
			portrait.queue_free()
	unit_portraits.clear()
	
	# Also clear any remaining children
	if queue_container:
		for child in queue_container.get_children():
			child.queue_free()
	
	# Reset scroll when clearing
	scroll_offset = 0

func _create_unit_portrait(unit: Unit, is_current: bool, queue_position: int) -> Control:
	"""Create a portrait for a unit with position indicator"""
	var portrait_container = Control.new()
	portrait_container.custom_minimum_size = PORTRAIT_SIZE + Vector2(PORTRAIT_MARGIN * 2, PORTRAIT_MARGIN * 2 + 15)  # Extra space for position
	portrait_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Store unit reference for interaction
	portrait_container.set_meta("unit", unit)
	
	# Create clickable button for interaction
	var button = Button.new()
	button.size = PORTRAIT_SIZE + Vector2(PORTRAIT_MARGIN * 2, PORTRAIT_MARGIN * 2 + 15)
	button.position = Vector2.ZERO
	button.flat = true
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Connect button signals
	button.pressed.connect(_on_portrait_clicked.bind(unit))
	button.mouse_entered.connect(_on_portrait_hovered.bind(unit))
	button.mouse_exited.connect(_on_portrait_unhovered.bind(unit))
	
	# Position indicator at the top
	var position_label = Label.new()
	if is_current:
		position_label.text = "NOW"
		position_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		position_label.text = str(queue_position + 1)
		position_label.add_theme_color_override("font_color", Color.WHITE)
	
	position_label.size = Vector2(PORTRAIT_SIZE.x + PORTRAIT_MARGIN * 2, 15)
	position_label.position = Vector2.ZERO
	position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	position_label.add_theme_font_size_override("font_size", 10)
	position_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	position_label.add_theme_constant_override("shadow_offset_x", 1)
	position_label.add_theme_constant_override("shadow_offset_y", 1)
	position_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(position_label)
	
	# Background panel (moved down to make room for position)
	var background = Panel.new()
	background.size = PORTRAIT_SIZE + Vector2(PORTRAIT_MARGIN * 2, PORTRAIT_MARGIN * 2)
	background.position = Vector2(0, 15)  # Offset for position label
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Style the background
	var style_box = StyleBoxFlat.new()
	if is_current:
		style_box.bg_color = Color(1.0, 1.0, 0.3, 0.9)  # Bright yellow for current unit
		style_box.border_color = Color(1.0, 1.0, 1.0, 1.0)  # White border
		style_box.border_width_left = 3
		style_box.border_width_top = 3
		style_box.border_width_right = 3
		style_box.border_width_bottom = 3
	else:
		# Get player color
		var player = unit.get_owner_player()
		if player and player.player_id == 0:
			style_box.bg_color = Color(0.2, 0.4, 0.8, 0.7)  # Blue for Player 1
		elif player and player.player_id == 1:
			style_box.bg_color = Color(0.8, 0.2, 0.2, 0.7)  # Red for Player 2
		else:
			style_box.bg_color = Color(0.5, 0.5, 0.5, 0.7)  # Gray for neutral
		
		style_box.border_color = Color(0.8, 0.8, 0.8, 0.8)
		style_box.border_width_left = 1
		style_box.border_width_top = 1
		style_box.border_width_right = 1
		style_box.border_width_bottom = 1
	
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	
	background.add_theme_stylebox_override("panel", style_box)
	portrait_container.add_child(background)
	
	# Unit icon/representation
	var icon_container = Control.new()
	icon_container.size = PORTRAIT_SIZE
	icon_container.position = Vector2(PORTRAIT_MARGIN, PORTRAIT_MARGIN + 15)  # Offset for position label
	icon_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# For now, use a simple colored rectangle to represent the unit
	var unit_icon = ColorRect.new()
	unit_icon.size = PORTRAIT_SIZE
	unit_icon.position = Vector2.ZERO
	unit_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set icon color based on unit type
	var unit_type = unit.get_unit_type()
	if unit_type and unit_type.display_name == "Warrior":
		unit_icon.color = Color(0.8, 0.6, 0.2, 1.0)  # Golden for warriors
	elif unit_type and unit_type.display_name == "Archer":
		unit_icon.color = Color(0.2, 0.8, 0.2, 1.0)  # Green for archers
	else:
		unit_icon.color = Color(0.6, 0.6, 0.6, 1.0)  # Gray for unknown
	
	icon_container.add_child(unit_icon)
	portrait_container.add_child(icon_container)
	
	# Unit name label
	var name_label = Label.new()
	name_label.text = unit.get_display_name()
	name_label.size = Vector2(PORTRAIT_SIZE.x, 20)
	name_label.position = Vector2(PORTRAIT_MARGIN, PORTRAIT_SIZE.y + PORTRAIT_MARGIN)  # Adjusted for position label
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(name_label)
	
	# Speed indicator
	var speed_label = Label.new()
	var current_speed = turn_system.get_unit_current_speed(unit) if turn_system else unit.get_stat("speed")
	speed_label.text = "SPD:" + str(current_speed)
	speed_label.size = Vector2(PORTRAIT_SIZE.x, 12)
	speed_label.position = Vector2(PORTRAIT_MARGIN, PORTRAIT_MARGIN + 17)  # Adjusted for position label
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 8)
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	speed_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	speed_label.add_theme_constant_override("shadow_offset_x", 1)
	speed_label.add_theme_constant_override("shadow_offset_y", 1)
	speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(speed_label)
	
	# Add the button on top for interaction
	portrait_container.add_child(button)
	
	return portrait_container

func _test_display() -> void:
	"""Test the display with dummy data"""
	if not queue_container:
		print("TurnQueue: queue_container not found!")
		return
	
	print("TurnQueue: Creating test display")
	queue_title_label.text = "Turn Queue (TEST MODE)"
	
	# Create some test portraits
	for i in range(3):
		var test_portrait = _create_test_portrait("Test Unit " + str(i + 1), i == 0)
		queue_container.add_child(test_portrait)
		unit_portraits.append(test_portrait)
	
	print("TurnQueue: Test display created with " + str(unit_portraits.size()) + " portraits")

func _create_test_portrait(unit_name: String, is_current: bool) -> Control:
	"""Create a test portrait"""
	var portrait_container = Control.new()
	portrait_container.custom_minimum_size = PORTRAIT_SIZE + Vector2(PORTRAIT_MARGIN * 2, PORTRAIT_MARGIN * 2)
	
	# Background panel
	var background = Panel.new()
	background.size = PORTRAIT_SIZE + Vector2(PORTRAIT_MARGIN * 2, PORTRAIT_MARGIN * 2)
	background.position = Vector2.ZERO
	
	# Style the background
	var style_box = StyleBoxFlat.new()
	if is_current:
		style_box.bg_color = Color(1.0, 1.0, 0.3, 0.9)  # Bright yellow for current unit
		style_box.border_color = Color(1.0, 1.0, 1.0, 1.0)  # White border
		style_box.border_width_left = 3
		style_box.border_width_top = 3
		style_box.border_width_right = 3
		style_box.border_width_bottom = 3
	else:
		style_box.bg_color = Color(0.2, 0.4, 0.8, 0.7)  # Blue
		style_box.border_color = Color(0.8, 0.8, 0.8, 0.8)
		style_box.border_width_left = 1
		style_box.border_width_top = 1
		style_box.border_width_right = 1
		style_box.border_width_bottom = 1
	
	style_box.corner_radius_top_left = 8
	style_box.corner_radius_top_right = 8
	style_box.corner_radius_bottom_left = 8
	style_box.corner_radius_bottom_right = 8
	
	background.add_theme_stylebox_override("panel", style_box)
	portrait_container.add_child(background)
	
	# Unit name label
	var name_label = Label.new()
	name_label.text = unit_name
	name_label.size = Vector2(PORTRAIT_SIZE.x, 20)
	name_label.position = Vector2(PORTRAIT_MARGIN, PORTRAIT_SIZE.y + PORTRAIT_MARGIN - 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	portrait_container.add_child(name_label)
	
	return portrait_container

func _on_portrait_clicked(unit: Unit) -> void:
	"""Handle portrait click - show unit details"""
	print("TurnQueue: Portrait clicked for " + unit.get_display_name())
	unit_portrait_clicked.emit(unit)
	
	# Also trigger unit info panel to show details
	GameEvents.unit_selected.emit(unit, unit.global_position)

func _on_portrait_hovered(unit: Unit) -> void:
	"""Handle portrait hover - show preview info"""
	print("TurnQueue: Portrait hovered for " + unit.get_display_name())
	unit_portrait_hovered.emit(unit)

func _on_portrait_unhovered(unit: Unit) -> void:
	"""Handle portrait unhover - hide preview info"""
	unit_portrait_unhovered.emit(unit)

# Public interface
func get_displayed_queue_size() -> int:
	"""Get the number of units currently displayed in the queue"""
	return unit_portraits.size()

func is_queue_visible() -> bool:
	"""Check if the turn queue is currently visible"""
	return visible and turn_system != null

func get_unit_at_queue_position(position: int) -> Unit:
	"""Get the unit at a specific position in the queue"""
	if turn_system and position >= 0:
		var queue = turn_system.get_turn_queue()
		if position < queue.size():
			return queue[position]
	return null

func scroll_to_unit(unit: Unit) -> bool:
	"""Scroll the queue to show a specific unit"""
	if not turn_system:
		return false
	
	var queue = turn_system.get_turn_queue()
	var unit_index = queue.find(unit)
	
	if unit_index >= 0:
		# Calculate which page this unit is on
		var target_page = unit_index / PORTRAITS_PER_PAGE
		scroll_offset = target_page * PORTRAITS_PER_PAGE
		_update_display()
		return true
	
	return false

func reset_scroll() -> void:
	"""Reset scroll to the beginning"""
	scroll_offset = 0
	_update_display()

func get_scroll_info() -> Dictionary:
	"""Get current scroll information"""
	return {
		"offset": scroll_offset,
		"total_units": total_units,
		"portraits_per_page": PORTRAITS_PER_PAGE,
		"current_page": (scroll_offset / PORTRAITS_PER_PAGE) + 1,
		"total_pages": (total_units + PORTRAITS_PER_PAGE - 1) / PORTRAITS_PER_PAGE if total_units > 0 else 1
	}

func highlight_portrait(unit: Unit, highlight: bool) -> void:
	"""Highlight a specific unit's portrait"""
	for portrait in unit_portraits:
		var portrait_unit = portrait.get_meta("unit", null)
		if portrait_unit == unit:
			var background = portrait.get_child(0)  # Background panel
			if background is Panel:
				var style_box = background.get_theme_stylebox("panel").duplicate()
				if highlight:
					style_box.border_color = Color.YELLOW
					style_box.border_width_left = 3
					style_box.border_width_top = 3
					style_box.border_width_right = 3
					style_box.border_width_bottom = 3
				else:
					style_box.border_color = Color(0.8, 0.8, 0.8, 0.8)
					style_box.border_width_left = 1
					style_box.border_width_top = 1
					style_box.border_width_right = 1
					style_box.border_width_bottom = 1
				background.add_theme_stylebox_override("panel", style_box)
			break