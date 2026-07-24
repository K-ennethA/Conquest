extends CanvasLayer

class_name GameUI

# Main UI controller for the tactical combat game
# Manages all UI panels and responsive layout

@onready var unit_info_panel: UnitInfoPanel = $UnitInfoPanel
@onready var unit_actions_panel: UnitActionsPanel = $UnitActionsPanel

# Responsive design breakpoints
const MOBILE_WIDTH = 800
const TABLET_WIDTH = 1200

func _ready() -> void:
	# Connect to viewport size changes for responsive design
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	
	# Initial layout setup
	_update_layout()

func _on_viewport_size_changed() -> void:
	"""Handle viewport size changes for responsive design"""
	_update_layout()

func _update_layout() -> void:
	"""Update UI layout based on screen size"""
	var viewport_size = get_viewport().size
	
	if viewport_size.x <= MOBILE_WIDTH:
		_setup_mobile_layout()
	elif viewport_size.x <= TABLET_WIDTH:
		_setup_tablet_layout()
	else:
		_setup_desktop_layout()

func _setup_mobile_layout() -> void:
	"""Setup UI for mobile screens (stacked layout)"""
	if unit_info_panel:
		# Stack info panel at bottom
		unit_info_panel.anchors_preset = Control.PRESET_BOTTOM_WIDE
		unit_info_panel.offset_left = 10
		unit_info_panel.offset_right = -10
		unit_info_panel.offset_top = -180
		unit_info_panel.offset_bottom = -10
	
	if unit_actions_panel:
		# Stack actions panel above info panel
		unit_actions_panel.anchors_preset = Control.PRESET_BOTTOM_WIDE
		unit_actions_panel.offset_left = 10
		unit_actions_panel.offset_right = -10
		unit_actions_panel.offset_top = -320
		unit_actions_panel.offset_bottom = -190

func _setup_tablet_layout() -> void:
	"""Setup UI for tablet screens (side-by-side, smaller)"""
	if unit_info_panel:
		# Left side, smaller
		unit_info_panel.anchors_preset = Control.PRESET_BOTTOM_LEFT
		unit_info_panel.offset_left = 10
		unit_info_panel.offset_right = 250
		unit_info_panel.offset_top = -280
		unit_info_panel.offset_bottom = -10
	
	if unit_actions_panel:
		# Right side, smaller
		unit_actions_panel.anchors_preset = Control.PRESET_TOP_RIGHT
		unit_actions_panel.offset_left = -190
		unit_actions_panel.offset_right = -10
		unit_actions_panel.offset_top = 10
		unit_actions_panel.offset_bottom = 180

func _setup_desktop_layout() -> void:
	"""Setup UI for desktop screens (default layout)"""
	if unit_info_panel:
		# Left side, full size
		unit_info_panel.anchors_preset = Control.PRESET_BOTTOM_LEFT
		unit_info_panel.offset_left = 20
		unit_info_panel.offset_right = 300
		unit_info_panel.offset_top = -340
		unit_info_panel.offset_bottom = -20
	
	if unit_actions_panel:
		# Right side, full size
		unit_actions_panel.anchors_preset = Control.PRESET_TOP_RIGHT
		unit_actions_panel.offset_left = -220
		unit_actions_panel.offset_right = -20
		unit_actions_panel.offset_top = 20
		unit_actions_panel.offset_bottom = 220

# Public interface for other systems
func show_unit_info(unit: Unit) -> void:
	"""Show unit information"""
	if unit_info_panel:
		unit_info_panel._update_unit_info(unit)
		unit_info_panel._show_panel()

func hide_unit_info() -> void:
	"""Hide unit information"""
	if unit_info_panel:
		unit_info_panel._hide_panel()

func show_unit_actions(unit: Unit) -> void:
	"""Show unit actions"""
	if unit_actions_panel:
		unit_actions_panel.selected_unit = unit
		unit_actions_panel._update_actions()
		unit_actions_panel._show_panel()

func hide_unit_actions() -> void:
	"""Hide unit actions"""
	if unit_actions_panel:
		unit_actions_panel._hide_panel()

func get_unit_info_panel() -> UnitInfoPanel:
	"""Get the unit info panel"""
	return unit_info_panel

func get_unit_actions_panel() -> UnitActionsPanel:
	"""Get the unit actions panel"""
	return unit_actions_panel
