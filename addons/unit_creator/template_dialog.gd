@tool
extends AcceptDialog

# Template selection dialog for the Unit Creator tool

signal template_selected(template_name: String)

var template_list: ItemList
var load_button: Button
var delete_button: Button
var selected_template: String = ""

func _init():
	set_title("Load Template")
	set_size(Vector2(400, 300))
	
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	# Instructions
	var label = Label.new()
	label.text = "Select a template to load:"
	vbox.add_child(label)
	
	# Template list
	template_list = ItemList.new()
	template_list.custom_minimum_size = Vector2(350, 200)
	template_list.item_selected.connect(_on_template_selected)
	template_list.item_activated.connect(_on_template_activated)
	vbox.add_child(template_list)
	
	# Buttons
	var button_container = HBoxContainer.new()
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_container)
	
	load_button = Button.new()
	load_button.text = "Load"
	load_button.disabled = true
	load_button.pressed.connect(_on_load_pressed)
	button_container.add_child(load_button)
	
	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.disabled = true
	delete_button.pressed.connect(_on_delete_pressed)
	button_container.add_child(delete_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_container.add_child(cancel_button)
	
	# Load templates
	_refresh_template_list()

func _refresh_template_list():
	"""Refresh the list of available templates"""
	template_list.clear()
	var templates = UnitTemplateManager.get_available_templates()
	
	if templates.is_empty():
		# Create default templates if none exist
		UnitTemplateManager.create_default_templates()
		templates = UnitTemplateManager.get_available_templates()
	
	for template_name in templates:
		template_list.add_item(template_name)

func _on_template_selected(index: int):
	"""Handle template selection"""
	selected_template = template_list.get_item_text(index)
	load_button.disabled = false
	delete_button.disabled = false

func _on_template_activated(index: int):
	"""Handle template double-click"""
	selected_template = template_list.get_item_text(index)
	_load_selected_template()

func _on_load_pressed():
	"""Handle load button press"""
	_load_selected_template()

func _on_delete_pressed():
	"""Handle delete button press"""
	if selected_template.is_empty():
		return
	
	# Confirm deletion
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.dialog_text = "Are you sure you want to delete the template '" + selected_template + "'?"
	add_child(confirm_dialog)
	confirm_dialog.confirmed.connect(_confirm_delete)
	confirm_dialog.popup_centered()

func _confirm_delete():
	"""Confirm template deletion"""
	if UnitTemplateManager.delete_template(selected_template):
		_refresh_template_list()
		selected_template = ""
		load_button.disabled = true
		delete_button.disabled = true

func _on_cancel_pressed():
	"""Handle cancel button press"""
	hide()

func _load_selected_template():
	"""Load the selected template"""
	if selected_template.is_empty():
		return
	
	template_selected.emit(selected_template)
	hide()

func show_dialog():
	"""Show the template dialog"""
	_refresh_template_list()
	popup_centered()