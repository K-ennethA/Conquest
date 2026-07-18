extends Control

class_name UILayoutManager

# Comprehensive UI Layout Manager
# Manages all UI components with proper container-based layout to prevent overlapping

# UI Component References
@onready var margin_container: MarginContainer = $MarginContainer
@onready var main_container: VBoxContainer = $MarginContainer/MainContainer
@onready var top_bar: HBoxContainer = $MarginContainer/MainContainer/TopBar
@onready var center_top_container: VBoxContainer = $MarginContainer/MainContainer/TopBar/CenterTopContainer
@onready var middle_area: HBoxContainer = $MarginContainer/MainContainer/MiddleArea
@onready var left_sidebar: VBoxContainer = $MarginContainer/MainContainer/MiddleArea/LeftSidebar
@onready var game_area: Control = $MarginContainer/MainContainer/MiddleArea/GameArea
@onready var right_sidebar: VBoxContainer = $MarginContainer/MainContainer/MiddleArea/RightSidebar

# UI Panel References
@onready var turn_queue: Control = $MarginContainer/MainContainer/TopBar/CenterTopContainer/TurnQueue
@onready var turn_indicator: Control = $MarginContainer/MainContainer/TopBar/CenterTopContainer/TurnIndicator
@onready var unit_actions_panel: Control = $MarginContainer/MainContainer/MiddleArea/RightSidebar/UnitActionsPanel

# Layout state
var current_turn_system_type: TurnSystemBase.TurnSystemType = TurnSystemBase.TurnSystemType.TRADITIONAL
var is_layout_initialized: bool = false

func _ready() -> void:
	# CRITICAL: Set mouse filter to IGNORE so clicks pass through to game area
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Connect to turn system events
	if TurnSystemManager:
		TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
	
	# Initialize layout
	_initialize_layout()
	_update_layout_for_turn_system()
	
	is_layout_initialized = true

func _initialize_layout() -> void:
	"""Initialize the layout system with proper sizing and constraints"""
	
	# CRITICAL: Set mouse filters for all container elements to allow click passthrough
	if margin_container:
		margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if main_container:
		main_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top_bar:
		top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center_top_container:
		center_top_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if middle_area:
		middle_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if left_sidebar:
		left_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if game_area:
		game_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if right_sidebar:
		right_sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Set minimum sizes for main areas with proper spacing
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 180)  # Taller to accommodate TurnQueue
	
	if middle_area:
		# This will expand to fill available space
		middle_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Set sidebar constraints - only right sidebar now
	if left_sidebar:
		left_sidebar.custom_minimum_size = Vector2(0, 0)  # No minimum width needed
		left_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	if right_sidebar:
		right_sidebar.custom_minimum_size = Vector2(220, 0)
		right_sidebar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Game area should expand to fill remaining space
	if game_area:
		game_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		game_area.size_flags_vertical = Control.SIZE_EXPAND_FILL

func _update_layout_for_turn_system() -> void:
	"""Update layout based on current turn system"""
	
	if current_turn_system_type == TurnSystemBase.TurnSystemType.INITIATIVE:
		# Speed First mode: Show TurnQueue, hide TurnIndicator
		_show_speed_first_layout()
	else:
		# Traditional mode: Show TurnIndicator, hide TurnQueue
		_show_traditional_layout()

func _show_speed_first_layout() -> void:
	"""Configure layout for Speed First turn system"""
	
	if turn_queue:
		turn_queue.visible = true
		turn_queue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		turn_queue.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	if turn_indicator:
		turn_indicator.visible = false
	
	# Adjust top bar height for Speed First display
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 180)  # Taller for queue with proper spacing

func _show_traditional_layout() -> void:
	"""Configure layout for Traditional turn system"""
	
	if turn_queue:
		turn_queue.visible = false
	
	if turn_indicator:
		turn_indicator.visible = true
		turn_indicator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		turn_indicator.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Standard top bar height for Traditional display
	if top_bar:
		top_bar.custom_minimum_size = Vector2(0, 120)  # Smaller for traditional indicator

func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	"""Handle turn system activation and update layout accordingly"""
	
	var new_type = turn_system.system_type
	if new_type != current_turn_system_type:
		current_turn_system_type = new_type
		_update_layout_for_turn_system()

# Public interface for layout management
func show_panel(panel_name: String, show: bool = true) -> void:
	"""Show or hide a specific UI panel"""
	match panel_name.to_lower():
		"unit_actions":
			if unit_actions_panel:
				unit_actions_panel.visible = show
		"turn_queue":
			if turn_queue:
				turn_queue.visible = show
		"turn_indicator":
			if turn_indicator:
				turn_indicator.visible = show
		_:
			pass

func get_game_area() -> Control:
	"""Get the game area control for 3D scene rendering"""
	return game_area

func get_panel(panel_name: String) -> Control:
	"""Get a reference to a specific UI panel"""
	match panel_name.to_lower():
		"unit_actions":
			return unit_actions_panel
		"turn_queue":
			return turn_queue
		"turn_indicator":
			return turn_indicator
		_:
			return null

func is_mouse_over_ui(mouse_position: Vector2) -> bool:
	"""Check if mouse position is over any UI element"""
	# Check if mouse is over any visible UI panel
	var panels = []
	
	# Always check right sidebar (unit actions panel)
	if unit_actions_panel and unit_actions_panel.visible:
		panels.append({"name": "unit_actions_panel", "panel": unit_actions_panel})
	
	# Add turn system specific panels
	if current_turn_system_type == TurnSystemBase.TurnSystemType.INITIATIVE and turn_queue and turn_queue.visible:
		panels.append({"name": "turn_queue", "panel": turn_queue})
	elif turn_indicator and turn_indicator.visible:
		panels.append({"name": "turn_indicator", "panel": turn_indicator})
	
	for panel_info in panels:
		var panel = panel_info.panel
		if panel and panel.visible:
			var panel_rect = Rect2(panel.global_position, panel.size)
			if panel_rect.has_point(mouse_position):
				return true
	
	return false

func get_layout_info() -> Dictionary:
	"""Get information about current layout state"""
	return {
		"turn_system_type": TurnSystemBase.TurnSystemType.keys()[current_turn_system_type],
		"is_initialized": is_layout_initialized,
		"visible_panels": {
			"unit_actions": unit_actions_panel.visible if unit_actions_panel else false,
			"turn_queue": turn_queue.visible if turn_queue else false,
			"turn_indicator": turn_indicator.visible if turn_indicator else false
		},
		"layout_areas": {
			"top_bar_height": top_bar.custom_minimum_size.y if top_bar else 0,
			"left_sidebar_width": 0,  # No longer used
			"right_sidebar_width": right_sidebar.custom_minimum_size.x if right_sidebar else 0
		}
	}

# Responsive layout adjustments
func _on_viewport_size_changed() -> void:
	"""Handle viewport size changes for responsive layout"""
	var viewport_size = get_viewport().get_visible_rect().size
	
	# Adjust sidebar visibility based on screen width - only right sidebar now
	if viewport_size.x < 1200:
		# On smaller screens, make right sidebar slightly smaller
		if right_sidebar:
			right_sidebar.custom_minimum_size.x = 180  # Slightly smaller
	else:
		# On larger screens, use full sidebar width
		if right_sidebar:
			right_sidebar.custom_minimum_size.x = 220

func force_layout_update() -> void:
	"""Force a complete layout update (useful for debugging)"""
	_initialize_layout()
	_update_layout_for_turn_system()
	
	# Force container updates
	if main_container:
		main_container.queue_sort()