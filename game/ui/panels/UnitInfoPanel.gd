extends Control

class_name UnitInfoPanel

# UI panel that displays information about the selected unit
# Updated to work with separate Unit Actions Panel

@onready var unit_name_label: Label = $MarginContainer/VBoxContainer/BasicInfoContainer/UnitNameLabel
@onready var unit_type_label: Label = $MarginContainer/VBoxContainer/BasicInfoContainer/UnitTypeLabel
@onready var health_label: Label = $MarginContainer/VBoxContainer/StatsContainer/HealthLabel
@onready var attack_label: Label = $MarginContainer/VBoxContainer/StatsContainer/AttackLabel
@onready var defense_label: Label = $MarginContainer/VBoxContainer/StatsContainer/DefenseLabel
@onready var speed_label: Label = $MarginContainer/VBoxContainer/StatsContainer/SpeedLabel
@onready var movement_label: Label = $MarginContainer/VBoxContainer/StatsContainer/MovementLabel
@onready var range_label: Label = $MarginContainer/VBoxContainer/StatsContainer/RangeLabel
@onready var unit_portrait: ColorRect = $MarginContainer/VBoxContainer/PortraitContainer/UnitPortrait

var current_unit: Unit = null

func _ready() -> void:
	# Connect to game events
	GameEvents.unit_selected.connect(_on_unit_selected)
	GameEvents.unit_deselected.connect(_on_unit_deselected)
	GameEvents.unit_hover_started.connect(_on_unit_hover_started)
	GameEvents.unit_hover_ended.connect(_on_unit_hover_ended)
	
	# Hide panel initially
	_hide_panel()

func _on_unit_selected(unit: Unit, position: Vector3) -> void:
	"""Handle unit selection"""
	print("UI: Selected unit: ", unit.name)
	current_unit = unit
	_update_unit_info(unit)
	_show_panel()

func _on_unit_deselected(unit: Unit) -> void:
	"""Handle unit deselection"""
	print("UI: Deselected unit: ", unit.name)
	if current_unit == unit:
		current_unit = null
		_hide_panel()

func _on_unit_hover_started(unit: Unit) -> void:
	"""Handle unit hover start - show preview info"""
	if not current_unit:  # Only show hover info if no unit is selected
		_update_unit_info(unit)
		_show_panel()

func _on_unit_hover_ended(unit: Unit) -> void:
	"""Handle unit hover end"""
	if not current_unit:  # Only hide if no unit is selected
		_hide_panel()

func _update_unit_info(unit: Unit) -> void:
	"""Update the panel with unit information"""
	if not unit:
		return
	
	# Basic info - with null checks
	if unit_name_label:
		unit_name_label.text = unit.get_display_name()
		
		# Add player ownership info
		var owner = unit.get_owner_player()
		if owner:
			unit_name_label.text += " (" + owner.get_display_name() + ")"
	
	if unit_type_label:
		var unit_type = unit.get_unit_type()
		if unit_type:
			unit_type_label.text = unit_type.get_type_name()
		else:
			unit_type_label.text = "Unknown"
	
	# Stats - with null checks
	if health_label:
		health_label.text = "Health: " + str(unit.current_health) + "/" + str(unit.max_health)
	if attack_label:
		attack_label.text = "Attack: " + str(unit.get_stat("attack"))
	if defense_label:
		defense_label.text = "Defense: " + str(unit.get_stat("defense"))
	if speed_label:
		speed_label.text = "Speed: " + str(unit.get_stat("speed"))
	if movement_label:
		movement_label.text = "Movement: " + str(unit.get_stat("movement"))
	if range_label:
		range_label.text = "Range: " + str(unit.get_stat("range"))
	
	# Set portrait color based on unit type and player
	_update_portrait(unit)

func _update_portrait(unit: Unit) -> void:
	"""Update unit portrait based on type and player"""
	if not unit_portrait:
		return
	
	# Determine player color from owner
	var player_color = Color.GRAY
	var owner = unit.get_owner_player()
	if owner:
		player_color = owner.get_team_color()
	else:
		# Fallback to old method if no owner set
		var parent = unit.get_parent()
		if parent:
			if parent.name.to_lower().contains("player1"):
				player_color = Color.BLUE
			elif parent.name.to_lower().contains("player2"):
				player_color = Color.RED
	
	# Adjust color based on unit type
	var unit_type = unit.get_unit_type()
	if unit_type:
		match unit_type.type:
			UnitType.Type.WARRIOR:
				unit_portrait.color = player_color
			UnitType.Type.ARCHER:
				unit_portrait.color = player_color.lightened(0.3)
			UnitType.Type.SCOUT:
				unit_portrait.color = player_color.darkened(0.2)
			UnitType.Type.TANK:
				unit_portrait.color = player_color.darkened(0.4)
			_:
				unit_portrait.color = player_color
	else:
		unit_portrait.color = player_color

func _show_panel() -> void:
	"""Show the info panel"""
	visible = true
	modulate.a = 1.0

func _hide_panel() -> void:
	"""Hide the info panel"""
	visible = false

# Public interface
func get_current_unit() -> Unit:
	"""Get the currently displayed unit"""
	return current_unit

func is_showing_unit(unit: Unit) -> bool:
	"""Check if panel is showing specific unit"""
	return current_unit == unit
