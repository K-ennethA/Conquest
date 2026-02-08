extends Control

class_name MoveSelectionPanel

# UI for selecting and using moves

signal move_selected(move_index: int)
signal move_cancelled

@onready var moves_container: VBoxContainer
@onready var move_info_label: Label
@onready var back_button: Button

var current_unit: Node
var move_buttons: Array[Button] = []

func _ready() -> void:
	name = "MoveSelectionPanel"
	_create_ui()
	visible = false

func _create_ui() -> void:
	"""Create the move selection UI"""
	# Main container
	var main_container = VBoxContainer.new()
	add_child(main_container)
	
	# Title
	var title = Label.new()
	title.text = "SELECT MOVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	main_container.add_child(title)
	
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
	move_info_label.custom_minimum_size = Vector2(300, 60)
	move_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main_container.add_child(move_info_label)
	
	# Back button
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.pressed.connect(_on_back_pressed)
	main_container.add_child(back_button)

func show_moves_for_unit(unit: Node) -> void:
	"""Display moves for the specified unit"""
	current_unit = unit
	
	if not unit:
		hide()
		return
	
	var move_manager = unit.get_node_or_null("MoveManager")
	if not move_manager:
		print("Unit %s has no MoveManager" % unit.name)
		hide()
		return
	
	_populate_moves(move_manager)
	show()

func _populate_moves(move_manager: MoveManager) -> void:
	"""Populate the UI with the unit's moves"""
	# Clear existing buttons
	for button in move_buttons:
		if button:
			button.queue_free()
	move_buttons.clear()
	
	# Clear container
	for child in moves_container.get_children():
		child.queue_free()
	
	# Get moves info
	var moves_info = move_manager.get_moves_info()
	
	if moves_info.is_empty():
		var no_moves_label = Label.new()
		no_moves_label.text = "No moves available"
		no_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		moves_container.add_child(no_moves_label)
		return
	
	# Create button for each move
	for move_info in moves_info:
		var move_button = _create_move_button(move_info)
		moves_container.add_child(move_button)
		move_buttons.append(move_button)

func _create_move_button(move_info: Dictionary) -> Button:
	"""Create a button for a move"""
	var button = Button.new()
	
	# Button text with cooldown info
	var button_text = move_info.name
	if move_info.cooldown_remaining > 0:
		button_text += " (Cooldown: %d)" % move_info.cooldown_remaining
	
	button.text = button_text
	button.disabled = not move_info.available
	button.custom_minimum_size = Vector2(250, 40)
	
	# Connect signals
	var move_index = move_info.index
	button.pressed.connect(func(): _on_move_selected(move_index))
	button.mouse_entered.connect(func(): _show_move_info(move_info))
	button.mouse_exited.connect(func(): _clear_move_info())
	
	# Style based on availability
	if not move_info.available:
		button.modulate = Color(0.6, 0.6, 0.6, 1.0)
	
	return button

func _show_move_info(move_info: Dictionary) -> void:
	"""Display detailed move information"""
	var info_text = ""
	info_text += "Name: %s\n" % move_info.name
	info_text += "Type: %s\n" % move_info.type
	info_text += "Description: %s\n" % move_info.description
	info_text += "Power: %d\n" % move_info.power
	info_text += "Range: %d\n" % move_info.range
	info_text += "Accuracy: %d%%\n" % move_info.accuracy
	
	if move_info.cooldown > 0:
		info_text += "Cooldown: %d turns\n" % move_info.cooldown
	
	if move_info.area_effect:
		info_text += "Area Effect: Yes\n"
	
	if move_info.cooldown_remaining > 0:
		info_text += "\nCOOLDOWN: %d turns remaining" % move_info.cooldown_remaining
	
	move_info_label.text = info_text

func _clear_move_info() -> void:
	"""Clear move information display"""
	move_info_label.text = "Hover over a move to see details"

func _on_move_selected(move_index: int) -> void:
	"""Handle move selection"""
	print("Move selected: index %d" % move_index)
	move_selected.emit(move_index)
	hide()

func _on_back_pressed() -> void:
	"""Handle back button press"""
	move_cancelled.emit()
	hide()

func update_move_cooldowns() -> void:
	"""Update the display to reflect current cooldowns"""
	if current_unit and visible:
		show_moves_for_unit(current_unit)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_back_pressed()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var move_index = event.keycode - KEY_1
				if move_index < move_buttons.size() and move_buttons[move_index]:
					if not move_buttons[move_index].disabled:
						_on_move_selected(move_index)