extends VBoxContainer

class_name MapSelectorPanel

# Reusable map selection component with visual gallery
# Shows map previews with images and names
# Can be embedded in lobbies, menus, or any UI that needs map selection
# Follows Godot best practices: modular, signal-based, self-contained

signal map_changed(map_path: String, map_resource: MapResource)

# Configuration
@export var show_title: bool = true
@export var title_text: String = "Map Selection:"
@export var show_description: bool = true
@export var show_details: bool = true
@export var gallery_mode: bool = true  # Show visual gallery with previews
@export var compact_mode: bool = false  # Simplified UI for lobbies
@export var auto_select_first: bool = true
@export var preview_size: Vector2 = Vector2(200, 150)  # Size of preview images
@export var columns: int = 3  # Number of columns in gallery

# UI Elements (created dynamically)
var title_label: Label
var gallery_container: GridContainer  # For gallery mode
var map_dropdown: OptionButton  # For dropdown mode
var description_label: Label
var details_label: Label
var selected_map_panel: Panel  # Shows currently selected map

# Data
var available_maps: Array[String] = []
var map_resources: Array[MapResource] = []
var current_map_index: int = -1
var map_buttons: Array[Button] = []  # Gallery buttons

# Default preview image for maps without custom preview
const DEFAULT_PREVIEW_PATH = "res://icon.svg"

func _ready() -> void:
	_build_ui()
	_load_available_maps()

func _build_ui() -> void:
	"""Build the UI components dynamically"""
	# Clear any existing children
	for child in get_children():
		child.queue_free()
	
	# Title
	if show_title:
		title_label = Label.new()
		title_label.text = title_text
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", 20 if not compact_mode else 16)
		add_child(title_label)
		
		# Spacing
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		add_child(spacer)
	
	# Gallery or Dropdown mode
	if gallery_mode and not compact_mode:
		_build_gallery_ui()
	else:
		_build_dropdown_ui()
	
	# Description
	if show_description:
		var spacer2 = Control.new()
		spacer2.custom_minimum_size = Vector2(0, 10)
		add_child(spacer2)
		
		description_label = Label.new()
		description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.custom_minimum_size = Vector2(300, 0)
		description_label.add_theme_font_size_override("font_size", 12 if compact_mode else 14)
		add_child(description_label)
	
	# Details
	if show_details and not compact_mode:
		var spacer3 = Control.new()
		spacer3.custom_minimum_size = Vector2(0, 10)
		add_child(spacer3)
		
		details_label = Label.new()
		details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		details_label.add_theme_font_size_override("font_size", 11)
		add_child(details_label)

func _build_gallery_ui() -> void:
	"""Build the visual gallery with map previews"""
	# Create scroll container for gallery
	var scroll_container = ScrollContainer.new()
	scroll_container.custom_minimum_size = Vector2(0, 400)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_container)
	
	# Create grid container for map cards
	gallery_container = GridContainer.new()
	gallery_container.columns = columns
	gallery_container.add_theme_constant_override("h_separation", 15)
	gallery_container.add_theme_constant_override("v_separation", 15)
	scroll_container.add_child(gallery_container)

func _build_dropdown_ui() -> void:
	"""Build the dropdown selector UI"""
	# Map dropdown
	map_dropdown = OptionButton.new()
	map_dropdown.custom_minimum_size = Vector2(300, 40) if not compact_mode else Vector2(250, 35)
	map_dropdown.item_selected.connect(_on_map_selected)
	
	# Center the dropdown
	var dropdown_container = HBoxContainer.new()
	dropdown_container.alignment = BoxContainer.ALIGNMENT_CENTER
	dropdown_container.add_child(map_dropdown)
	add_child(dropdown_container)

func _load_available_maps() -> void:
	"""Load all available map files"""
	available_maps.clear()
	map_resources.clear()
	map_buttons.clear()
	
	if map_dropdown:
		map_dropdown.clear()
	
	if gallery_container:
		for child in gallery_container.get_children():
			child.queue_free()
	
	# Get available map files
	available_maps = MapLoader.get_available_maps()
	
	# If no maps exist, create a default one
	if available_maps.is_empty():
		print("MapSelectorPanel: No maps found, creating default map")
		_create_default_map()
		available_maps = MapLoader.get_available_maps()
	
	# Load map resources and populate UI
	for i in range(available_maps.size()):
		var map_path = available_maps[i]
		var map_resource = load(map_path) as MapResource
		
		if map_resource:
			map_resources.append(map_resource)
			
			if gallery_mode and not compact_mode and gallery_container:
				_create_map_card(i, map_resource)
			elif map_dropdown:
				var display_name = _format_map_name(map_resource)
				map_dropdown.add_item(display_name)
				map_dropdown.set_item_metadata(i, map_path)
		else:
			print("MapSelectorPanel: Failed to load map: " + map_path)
	
	print("MapSelectorPanel: Loaded " + str(map_resources.size()) + " maps")
	
	# Auto-select first map or default map
	if auto_select_first and map_resources.size() > 0:
		var default_index = _find_default_map_index()
		if gallery_mode and not compact_mode:
			_select_map_card(default_index)
		elif map_dropdown and map_dropdown.get_item_count() > 0:
			map_dropdown.selected = default_index
		_on_map_selected(default_index)

func _create_map_card(index: int, map_resource: MapResource) -> void:
	"""Create a visual card for a map in the gallery"""
	# Create card container
	var card = PanelContainer.new()
	card.custom_minimum_size = preview_size + Vector2(20, 60)  # Extra space for name
	
	# Create card content
	var card_content = VBoxContainer.new()
	card.add_child(card_content)
	
	# Create preview button
	var preview_button = Button.new()
	preview_button.custom_minimum_size = preview_size
	preview_button.flat = false
	preview_button.pressed.connect(_on_map_card_pressed.bind(index))
	
	# Load preview image
	var preview_texture = _load_map_preview(map_resource)
	if preview_texture:
		var texture_rect = TextureRect.new()
		texture_rect.texture = preview_texture
		texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.custom_minimum_size = preview_size
		preview_button.add_child(texture_rect)
	else:
		# Fallback: Show map size as text
		var fallback_label = Label.new()
		fallback_label.text = str(map_resource.width) + "x" + str(map_resource.height)
		fallback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback_label.add_theme_font_size_override("font_size", 32)
		preview_button.add_child(fallback_label)
	
	card_content.add_child(preview_button)
	
	# Add map name label
	var name_label = Label.new()
	name_label.text = map_resource.map_name if not map_resource.map_name.is_empty() else "Unnamed Map"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 14)
	card_content.add_child(name_label)
	
	# Add size info
	var size_label = Label.new()
	size_label.text = str(map_resource.width) + "x" + str(map_resource.height)
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_label.add_theme_font_size_override("font_size", 11)
	size_label.modulate = Color(0.7, 0.7, 0.7)
	card_content.add_child(size_label)
	
	gallery_container.add_child(card)
	map_buttons.append(preview_button)

func _load_map_preview(map_resource: MapResource) -> Texture2D:
	"""Load preview image for a map"""
	var preview_path = map_resource.preview_image_path
	
	# Try custom preview first
	if not preview_path.is_empty() and ResourceLoader.exists(preview_path):
		var texture = load(preview_path) as Texture2D
		if texture:
			return texture
	
	# Try default preview
	if ResourceLoader.exists(DEFAULT_PREVIEW_PATH):
		return load(DEFAULT_PREVIEW_PATH) as Texture2D
	
	return null

func _on_map_card_pressed(index: int) -> void:
	"""Handle map card button press"""
	_select_map_card(index)
	_on_map_selected(index)

func _select_map_card(index: int) -> void:
	"""Visually select a map card"""
	# Reset all buttons to normal state
	for i in range(map_buttons.size()):
		if map_buttons[i]:
			map_buttons[i].modulate = Color.WHITE
	
	# Highlight selected button
	if index >= 0 and index < map_buttons.size() and map_buttons[index]:
		map_buttons[index].modulate = Color(1.2, 1.2, 1.0)  # Slight yellow tint

func _format_map_name(map_resource: MapResource) -> String:
	"""Format map name for display"""
	var name = map_resource.map_name
	if name.is_empty():
		name = "Unnamed Map"
	
	if compact_mode:
		return name
	else:
		return "%s (%dx%d)" % [name, map_resource.width, map_resource.height]

func _find_default_map_index() -> int:
	"""Find the index of the default map"""
	for i in range(available_maps.size()):
		if available_maps[i].contains("default_skirmish"):
			return i
	return 0

func _create_default_map() -> void:
	"""Create and save a default map"""
	var default_map = MapLoader.create_default_map()
	MapLoader.save_map(default_map, "default_skirmish")
	print("MapSelectorPanel: Created default map")

func _on_map_selected(index: int) -> void:
	"""Handle map selection change"""
	if index < 0 or index >= map_resources.size():
		return
	
	current_map_index = index
	var map_resource = map_resources[index]
	var map_path = available_maps[index]
	
	# Update UI
	_update_map_info(map_resource)
	
	# Emit signal
	map_changed.emit(map_path, map_resource)

func _update_map_info(map_resource: MapResource) -> void:
	"""Update the info labels with map details"""
	if not map_resource:
		return
	
	var info = map_resource.get_display_info()
	
	# Update description
	if description_label:
		var description = info.get("description", "No description available")
		description_label.text = description
	
	# Update details
	if details_label:
		var details = []
		details.append("Size: " + info.get("size", "Unknown"))
		details.append("Players: " + str(info.get("max_players", 2)))
		details.append("Difficulty: " + info.get("difficulty", "Normal"))
		
		details_label.text = " • ".join(details)

# Public API
func get_selected_map_path() -> String:
	"""Get the currently selected map path"""
	if current_map_index >= 0 and current_map_index < available_maps.size():
		return available_maps[current_map_index]
	return ""

func get_selected_map_resource() -> MapResource:
	"""Get the currently selected map resource"""
	if current_map_index >= 0 and current_map_index < map_resources.size():
		return map_resources[current_map_index]
	return null

func set_selected_map(map_path: String) -> bool:
	"""Set the selected map by path"""
	for i in range(available_maps.size()):
		if available_maps[i] == map_path:
			if map_dropdown:
				map_dropdown.selected = i
			_on_map_selected(i)
			return true
	return false

func refresh_maps() -> void:
	"""Refresh the list of available maps"""
	_load_available_maps()

func get_map_count() -> int:
	"""Get the number of available maps"""
	return map_resources.size()

func set_gallery_mode(enabled: bool) -> void:
	"""Switch between gallery and dropdown mode"""
	gallery_mode = enabled
	_build_ui()
	_load_available_maps()

func set_preview_size(size: Vector2) -> void:
	"""Set the size of preview images in gallery mode"""
	preview_size = size
	if gallery_mode:
		_build_ui()
		_load_available_maps()

func set_columns(col_count: int) -> void:
	"""Set number of columns in gallery mode"""
	columns = max(1, col_count)
	if gallery_mode and gallery_container:
		gallery_container.columns = columns
