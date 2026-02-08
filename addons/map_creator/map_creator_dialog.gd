@tool
extends AcceptDialog

class_name MapCreatorDialog

# Dialog for advanced map creator operations (load/save maps and templates)

signal map_selected(map_path: String)
signal template_selected(template_name: String)

enum DialogMode {
	LOAD_MAP,
	SAVE_MAP,
	LOAD_TEMPLATE,
	SAVE_TEMPLATE
}

var dialog_mode: DialogMode
var item_list: ItemList
var name_input: LineEdit
var description_label: Label

func _init(mode: DialogMode):
	dialog_mode = mode
	_setup_dialog()

func _setup_dialog():
	"""Set up the dialog based on mode"""
	match dialog_mode:
		DialogMode.LOAD_MAP:
			title = "Load Map"
			_setup_load_map_dialog()
		DialogMode.SAVE_MAP:
			title = "Save Map"
			_setup_save_map_dialog()
		DialogMode.LOAD_TEMPLATE:
			title = "Load Template"
			_setup_load_template_dialog()
		DialogMode.SAVE_TEMPLATE:
			title = "Save Template"
			_setup_save_template_dialog()
	
	# Set dialog size
	size = Vector2(400, 300)

func _setup_load_map_dialog():
	"""Set up dialog for loading maps"""
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var label = Label.new()
	label.text = "Select a map to load:"
	vbox.add_child(label)
	
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(350, 200)
	item_list.item_selected.connect(_on_item_selected)
	item_list.item_activated.connect(_on_item_activated)
	vbox.add_child(item_list)
	
	description_label = Label.new()
	description_label.text = "Select a map to see details..."
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size = Vector2(350, 50)
	vbox.add_child(description_label)
	
	# Load available maps
	_load_available_maps()

func _setup_save_map_dialog():
	"""Set up dialog for saving maps"""
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter map name:"
	vbox.add_child(label)
	
	name_input = LineEdit.new()
	name_input.placeholder_text = "Map name..."
	vbox.add_child(name_input)
	
	var existing_label = Label.new()
	existing_label.text = "Existing maps:"
	vbox.add_child(existing_label)
	
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(350, 150)
	vbox.add_child(item_list)
	
	# Load existing maps for reference
	_load_available_maps()

func _setup_load_template_dialog():
	"""Set up dialog for loading templates"""
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var label = Label.new()
	label.text = "Select a template to load:"
	vbox.add_child(label)
	
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(350, 200)
	item_list.item_selected.connect(_on_template_selected)
	item_list.item_activated.connect(_on_template_activated)
	vbox.add_child(item_list)
	
	description_label = Label.new()
	description_label.text = "Select a template to see details..."
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size = Vector2(350, 50)
	vbox.add_child(description_label)
	
	# Load available templates
	_load_available_templates()

func _setup_save_template_dialog():
	"""Set up dialog for saving templates"""
	var vbox = VBoxContainer.new()
	add_child(vbox)
	
	var label = Label.new()
	label.text = "Enter template name:"
	vbox.add_child(label)
	
	name_input = LineEdit.new()
	name_input.placeholder_text = "Template name..."
	vbox.add_child(name_input)
	
	var existing_label = Label.new()
	existing_label.text = "Existing templates:"
	vbox.add_child(existing_label)
	
	item_list = ItemList.new()
	item_list.custom_minimum_size = Vector2(350, 150)
	vbox.add_child(item_list)
	
	# Load existing templates for reference
	_load_available_templates()

func _load_available_maps():
	"""Load available maps into the list"""
	if not item_list:
		return
	
	item_list.clear()
	var available_maps = MapLoader.get_available_maps()
	
	for map_path in available_maps:
		var map_resource = load(map_path) as MapResource
		if map_resource:
			var display_name = map_resource.map_name
			if display_name.is_empty():
				display_name = map_path.get_file().get_basename()
			
			item_list.add_item(display_name)
			item_list.set_item_metadata(item_list.get_item_count() - 1, map_path)

func _load_available_templates():
	"""Load available templates into the list"""
	if not item_list:
		return
	
	item_list.clear()
	var available_templates = MapTemplateManager.get_available_templates()
	
	# Create default templates if none exist
	if available_templates.is_empty():
		MapTemplateManager.create_default_templates()
		available_templates = MapTemplateManager.get_available_templates()
	
	for template_name in available_templates:
		item_list.add_item(template_name)

func _on_item_selected(index: int):
	"""Handle map selection"""
	if not item_list or not description_label:
		return
	
	var map_path = item_list.get_item_metadata(index)
	if map_path:
		var map_resource = load(map_path) as MapResource
		if map_resource:
			var info = map_resource.get_display_info()
			var description_text = []
			description_text.append("Size: " + info.get("size", "Unknown"))
			description_text.append("Players: " + str(info.get("players", 0)))
			description_text.append("Difficulty: " + info.get("difficulty", "Normal"))
			description_text.append("Author: " + info.get("author", "Unknown"))
			
			description_label.text = "\n".join(description_text)

func _on_item_activated(index: int):
	"""Handle map double-click"""
	if dialog_mode == DialogMode.LOAD_MAP:
		var map_path = item_list.get_item_metadata(index)
		if map_path:
			map_selected.emit(map_path)
			hide()

func _on_template_selected(index: int):
	"""Handle template selection"""
	if not item_list or not description_label:
		return
	
	var template_name = item_list.get_item_text(index)
	var template_data = MapTemplateManager.load_template(template_name)
	
	if not template_data.is_empty():
		var description_text = []
		description_text.append("Size: " + str(template_data.get("width", 5)) + "x" + str(template_data.get("height", 5)))
		description_text.append("Difficulty: " + template_data.get("difficulty", "Normal"))
		description_text.append("Type: " + template_data.get("map_type", "Skirmish"))
		description_text.append("Description: " + template_data.get("description", "No description"))
		
		description_label.text = "\n".join(description_text)

func _on_template_activated(index: int):
	"""Handle template double-click"""
	if dialog_mode == DialogMode.LOAD_TEMPLATE:
		var template_name = item_list.get_item_text(index)
		template_selected.emit(template_name)
		hide()

func get_entered_name() -> String:
	"""Get the name entered by user"""
	if name_input:
		return name_input.text
	return ""

func get_selected_map_path() -> String:
	"""Get the selected map path"""
	if not item_list:
		return ""
	
	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		return ""
	
	return item_list.get_item_metadata(selected_items[0])

func get_selected_template_name() -> String:
	"""Get the selected template name"""
	if not item_list:
		return ""
	
	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		return ""
	
	return item_list.get_item_text(selected_items[0])