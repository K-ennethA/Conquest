extends Control

class_name MoveSelectionPanel

# UI for selecting and using a unit's real MoveResource moveset (up to 4 slots).
# Reads unit.get_moveset() / unit.get_moveset_controller() directly — no
# MoveManager/MoveFactory/Move.gd involved.

signal move_selected(move_index: int)
signal move_cancelled

const MAX_SLOTS := 4

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
	"""Display the unit's real moveset (up to 4 MoveResource slots)."""
	current_unit = unit

	if not unit:
		hide()
		return

	var moveset: Array[MoveResource] = unit.get_moveset()
	var controller := unit.get_moveset_controller() as MovesetController

	_populate_moves(moveset, controller)
	show()

func _populate_moves(moveset: Array[MoveResource], controller: MovesetController) -> void:
	"""Populate the UI with the unit's moveset (up to MAX_SLOTS entries)."""
	# Clear existing buttons
	for button in move_buttons:
		if button:
			button.queue_free()
	move_buttons.clear()

	# Clear container
	for child in moves_container.get_children():
		child.queue_free()

	if moveset.is_empty():
		var no_moves_label = Label.new()
		no_moves_label.text = "No moves available"
		no_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		moves_container.add_child(no_moves_label)
		return

	var slot_count = mini(moveset.size(), MAX_SLOTS)
	for slot in range(slot_count):
		var move = moveset[slot]
		if move == null:
			continue
		var move_button = _create_move_button(move, slot, controller)
		moves_container.add_child(move_button)
		move_buttons.append(move_button)

func _create_move_button(move: MoveResource, slot: int, controller: MovesetController) -> Button:
	"""Create a button for a single moveset slot."""
	var button = Button.new()

	var can_use := true
	var suffix := ""
	if controller:
		can_use = controller.can_use(move)
		var remaining := controller.remaining(move)
		if remaining > 0:
			suffix = " (Cooldown: %d)" % remaining
		elif move.max_uses >= 0:
			suffix = " (%d/%d uses)" % [controller.uses_left(move), move.max_uses]

	var range_text := move.targeting.describe_range() if move.targeting else "no range"
	button.text = "%s (%s)%s" % [move.display_name, range_text, suffix]
	button.disabled = controller != null and not can_use
	button.custom_minimum_size = Vector2(250, 40)

	# Connect signals — slot is the index into the moveset (matches move_selected(slot)).
	button.pressed.connect(func(): _on_move_selected(slot))
	button.mouse_entered.connect(func(): _show_move_info(move, controller))
	button.mouse_exited.connect(func(): _clear_move_info())

	if button.disabled:
		button.modulate = Color(0.6, 0.6, 0.6, 1.0)

	return button

func _show_move_info(move: MoveResource, controller: MovesetController) -> void:
	"""Display detailed move information"""
	var info_text = ""
	info_text += "Name: %s\n" % move.display_name
	info_text += "Description: %s\n" % move.full_description()
	if move.energy_cost > 0:
		info_text += "Energy Cost: %d\n" % move.energy_cost
	if move.targeting:
		info_text += "Range: %s\n" % move.targeting.describe_range()
	info_text += "Accuracy: %d%%\n" % int(move.accuracy * 100)

	if move.cooldown > 0:
		info_text += "Cooldown: %d turns\n" % move.cooldown
	if move.max_uses >= 0:
		info_text += "Max Uses: %d\n" % move.max_uses

	if controller:
		var remaining := controller.remaining(move)
		if remaining > 0:
			info_text += "\nCOOLDOWN: %d turns remaining" % remaining

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
	"""Update the display to reflect current cooldowns/uses for the shown unit."""
	if current_unit and visible:
		show_moves_for_unit(current_unit)

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
