extends Control

class_name MapSelection

# Map Selection UI - Allows users to choose maps before starting a game

signal map_selected(map_path: String)
signal back_pressed()

# UI Elements
@onready var map_list: ItemList = $VBoxContainer/MapListContainer/MapList
@onready var map_preview_container: Control = $VBoxContainer/MapPreviewContainer
@onready var map_name_label: Label = $VBoxContainer/MapPreviewContainer/MapInfoPanel/VBoxContainer/MapNameLabel
@onready var map_description_label: Label = $VBoxContainer/MapPreviewContainer/MapInfoPanel/VBoxContainer/MapDescriptionLabel
@onready var map_details_label: Label = $VBoxContainer/MapPreviewContainer/MapInfoPanel/VBoxContainer/MapDetailsLabel
@onready var select_button: Button = $VBoxContainer/ButtonContainer/SelectButton
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton
@onready var refresh_button: Button = $VBoxContainer/ButtonContainer/RefreshButton

# Data
var available_maps: Array[String] = []
var current_selected_map: String = ""
var map_resources: Array[MapResource] = []

func _ready() -> void:
	print("MapSelection: Initializing map selection UI")
	
	# Connect signals
	if map_list:
		map_list.item_selected.connect(_on_map_selected)
		map_list.item_activated.connect(_on_map_activated)
	
	if select_button:
		select_button.pressed.connect(_on_select_button_pressed)
		select_button.disabled = true
	
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	
	if refresh_button:
		refresh_button.pressed.connect(_on_refresh_button_pressed)
	
	# Load available maps
	_load_available_maps()

func _load_available_maps() -> void:
	"""Load all available map files"""
	print("Loading available maps...")
	
	available_maps.clear()
	map_resources.clear()
	
	if map_list:
		map_list.clear()
	
	# Get available map files
	available_maps = MapLoader.get_available_maps()
	
	# If no maps exist, create a default one
	if available_maps.is_empty():
		print("No maps found, creating default map")
		_create_default_map()
		available_maps = MapLoader.get_available_maps()
	
	# Load map resources and populate list
	for map_path in available_maps:
		var map_resource = load(map_path) as MapResource
		if map_resource:
			map_resources.append(map_resource)
			
			if map_list:
				var display_name = map_resource.map_name
				if display_name.is_empty():
					display_name = map_path.get_file().get_basename()
				
				map_list.add_item(display_name)
		else:
			print("Failed to load map: " + map_path)
	
	print("Loaded " + str(map_resources.size()) + " maps")
	
	# Select first map by default
	if map_list and map_list.get_item_count() > 0:
		map_list.select(0)
		_on_map_selected(0)

func _create_default_map() -> void:
	"""Create and save a default map"""
	var default_map = MapLoader.create_default_map()
	MapLoader.save_map(default_map, "default_skirmish")
	print("Created default map")

func _on_map_selected(index: int) -> void:
	"""Handle map selection from list"""
	if index < 0 or index >= map_resources.size():
		return
	
	var map_resource = map_resources[index]
	current_selected_map = available_maps[index]
	
	_display_map_info(map_resource)
	
	if select_button:
		select_button.disabled = false

func _on_map_activated(index: int) -> void:
	"""Handle double-click on map (auto-select)"""
	_on_map_selected(index)
	_on_select_button_pressed()

func _display_map_info(map_resource: MapResource) -> void:
	"""Display detailed information about the selected map"""
	if not map_resource:
		return
	
	var info = map_resource.get_display_info()
	
	# Update map name
	if map_name_label:
		map_name_label.text = info.get("name", "Unknown Map")
	
	# Update description
	if map_description_label:
		var description = info.get("description", "No description available")
		map_description_label.text = description
		map_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	# Update details
	if map_details_label:
		var details = []
		details.append("Size: " + info.get("size", "Unknown"))
		details.append("Players: " + str(info.get("players", 0)) + "/" + str(info.get("max_players", 2)))
		details.append("Difficulty: " + info.get("difficulty", "Normal"))
		details.append("Type: " + info.get("map_type", "Skirmish"))
		
		if not info.get("author", "").is_empty():
			details.append("Author: " + info.get("author", ""))
		
		details.append("Units: " + str(info.get("total_spawns", 0)))
		details.append("Tiles: " + str(info.get("total_tiles", 0)))
		
		map_details_label.text = "\n".join(details)
	
	# Show preview container
	if map_preview_container:
		map_preview_container.visible = true

func _on_select_button_pressed() -> void:
	"""Handle select button press"""
	if current_selected_map.is_empty():
		return
	
	print("Map selected: " + current_selected_map)
	
	# Store selected map in GameSettings
	GameSettings.set_selected_map(current_selected_map)
	
	# Start the game
	get_tree().change_scene_to_file("res://game/world/GameWorld.tscn")

func _on_back_button_pressed() -> void:
	"""Handle back button press"""
	print("Back button pressed")
	get_tree().change_scene_to_file("res://menus/TurnSystemSelection.tscn")

func _on_refresh_button_pressed() -> void:
	"""Handle refresh button press"""
	print("Refreshing map list...")
	_load_available_maps()

# Input handling for keyboard navigation
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	
	if event is InputEventKey:
		match event.keycode:
			KEY_ENTER:
				if not select_button.disabled:
					_on_select_button_pressed()
			KEY_ESCAPE:
				_on_back_button_pressed()
			KEY_F5:
				_on_refresh_button_pressed()
			KEY_UP:
				if map_list and map_list.get_selected_items().size() > 0:
					var current = map_list.get_selected_items()[0]
					if current > 0:
						map_list.select(current - 1)
						_on_map_selected(current - 1)
			KEY_DOWN:
				if map_list and map_list.get_selected_items().size() > 0:
					var current = map_list.get_selected_items()[0]
					if current < map_list.get_item_count() - 1:
						map_list.select(current + 1)
						_on_map_selected(current + 1)

func get_selected_map_path() -> String:
	"""Get the currently selected map path"""
	return current_selected_map

func get_selected_map_resource() -> MapResource:
	"""Get the currently selected map resource"""
	if map_list and map_list.get_selected_items().size() > 0:
		var index = map_list.get_selected_items()[0]
		if index >= 0 and index < map_resources.size():
			return map_resources[index]
	return null