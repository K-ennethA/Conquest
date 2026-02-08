@tool
extends RefCounted

class_name MapTemplateManager

# MapTemplateManager - Handles saving and loading of map templates
# Templates are reusable map configurations that can be applied to new maps

const TEMPLATE_DIR = "res://addons/map_creator/templates/"

static func save_template(map_resource: MapResource, template_name: String) -> bool:
	"""Save a map as a template"""
	if not map_resource or template_name.is_empty():
		return false
	
	# Ensure template directory exists
	if not DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		DirAccess.open("res://").make_dir_recursive("addons/map_creator/templates")
	
	# Create template data (simplified version of map)
	var template_data = {
		"name": template_name,
		"description": map_resource.description,
		"width": map_resource.width,
		"height": map_resource.height,
		"difficulty": map_resource.difficulty,
		"map_type": map_resource.map_type,
		"tile_layout": map_resource.tile_layout.duplicate(true),
		"unit_spawns": map_resource.unit_spawns.duplicate(true),
		"creation_date": Time.get_datetime_string_from_system()
	}
	
	# Save as JSON for easy editing
	var json_string = JSON.stringify(template_data, "\t")
	var file_path = TEMPLATE_DIR + template_name.to_lower().replace(" ", "_") + ".json"
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Template saved: " + file_path)
		return true
	else:
		print("Failed to save template: " + file_path)
		return false

static func load_template(template_name: String) -> Dictionary:
	"""Load a map template"""
	var file_path = TEMPLATE_DIR + template_name.to_lower().replace(" ", "_") + ".json"
	
	if not FileAccess.file_exists(file_path):
		print("Template not found: " + file_path)
		return {}
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("Failed to open template: " + file_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse template JSON: " + json.get_error_message())
		return {}
	
	return json.data

static func apply_template_to_map(template_data: Dictionary, map_resource: MapResource) -> bool:
	"""Apply template data to a map resource"""
	if template_data.is_empty() or not map_resource:
		return false
	
	# Apply template properties
	map_resource.width = template_data.get("width", 5)
	map_resource.height = template_data.get("height", 5)
	map_resource.difficulty = template_data.get("difficulty", "Normal")
	map_resource.map_type = template_data.get("map_type", "Skirmish")
	
	# Apply layout data
	map_resource.tile_layout = template_data.get("tile_layout", [])
	map_resource.unit_spawns = template_data.get("unit_spawns", [])
	
	print("Template applied to map")
	return true

static func get_available_templates() -> Array[String]:
	"""Get list of available template names"""
	var templates: Array[String] = []
	
	if not DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		return templates
	
	var dir = DirAccess.open(TEMPLATE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name.ends_with(".json") and not file_name.begins_with("."):
				var template_name = file_name.get_basename().replace("_", " ").capitalize()
				templates.append(template_name)
			file_name = dir.get_next()
		
		dir.list_dir_end()
	
	return templates

static func delete_template(template_name: String) -> bool:
	"""Delete a template"""
	var file_path = TEMPLATE_DIR + template_name.to_lower().replace(" ", "_") + ".json"
	
	if not FileAccess.file_exists(file_path):
		return false
	
	var dir = DirAccess.open("res://")
	if dir:
		var result = dir.remove(file_path)
		if result == OK:
			print("Template deleted: " + template_name)
			return true
	
	print("Failed to delete template: " + template_name)
	return false

static func create_default_templates():
	"""Create default map templates"""
	_create_small_arena_template()
	_create_large_battlefield_template()
	_create_river_crossing_template()

static func _create_small_arena_template():
	"""Create a small arena template"""
	var map = MapResource.new()
	map.map_name = "Small Arena"
	map.description = "A compact 4x4 arena with walls around the edges"
	map.width = 4
	map.height = 4
	map.difficulty = "Easy"
	map.map_type = "Skirmish"
	
	# Create layout with walls around edges
	for x in range(4):
		for y in range(4):
			if x == 0 or x == 3 or y == 0 or y == 3:
				map.set_tile_at_position(Vector2i(x, y), "WALL", "")
			else:
				map.set_tile_at_position(Vector2i(x, y), "NORMAL", "")
	
	# Add unit spawns in corners
	map.set_unit_spawn_at_position(Vector2i(1, 1), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 2), 1, "WARRIOR", "")
	
	save_template(map, "Small Arena")

static func _create_large_battlefield_template():
	"""Create a large battlefield template"""
	var map = MapResource.new()
	map.map_name = "Large Battlefield"
	map.description = "A 7x7 battlefield with varied terrain"
	map.width = 7
	map.height = 7
	map.difficulty = "Hard"
	map.map_type = "Skirmish"
	
	# Create varied terrain
	for x in range(7):
		for y in range(7):
			map.set_tile_at_position(Vector2i(x, y), "NORMAL", "")
	
	# Add some obstacles
	map.set_tile_at_position(Vector2i(2, 2), "WATER", "")
	map.set_tile_at_position(Vector2i(4, 4), "WATER", "")
	map.set_tile_at_position(Vector2i(3, 1), "DIFFICULT_TERRAIN", "")
	map.set_tile_at_position(Vector2i(3, 5), "DIFFICULT_TERRAIN", "")
	map.set_tile_at_position(Vector2i(3, 3), "SACRED_GROUND", "")
	
	# Add unit spawns
	# Player 1 (left side)
	map.set_unit_spawn_at_position(Vector2i(0, 1), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(0, 3), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(0, 5), 0, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(1, 2), 0, "ARCHER", "")
	
	# Player 2 (right side)
	map.set_unit_spawn_at_position(Vector2i(6, 1), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(6, 3), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(6, 5), 1, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(5, 4), 1, "ARCHER", "")
	
	save_template(map, "Large Battlefield")

static func _create_river_crossing_template():
	"""Create a river crossing template"""
	var map = MapResource.new()
	map.map_name = "River Crossing"
	map.description = "A 6x6 map with a river running through the middle"
	map.width = 6
	map.height = 6
	map.difficulty = "Normal"
	map.map_type = "Skirmish"
	
	# Create layout
	for x in range(6):
		for y in range(6):
			if y == 2 or y == 3:
				# River in the middle
				map.set_tile_at_position(Vector2i(x, y), "WATER", "")
			else:
				map.set_tile_at_position(Vector2i(x, y), "NORMAL", "")
	
	# Add bridges
	map.set_tile_at_position(Vector2i(1, 2), "NORMAL", "")
	map.set_tile_at_position(Vector2i(1, 3), "NORMAL", "")
	map.set_tile_at_position(Vector2i(4, 2), "NORMAL", "")
	map.set_tile_at_position(Vector2i(4, 3), "NORMAL", "")
	
	# Add unit spawns
	# Player 1 (bottom)
	map.set_unit_spawn_at_position(Vector2i(0, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(2, 0), 0, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(4, 0), 0, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(1, 1), 0, "ARCHER", "")
	
	# Player 2 (top)
	map.set_unit_spawn_at_position(Vector2i(1, 5), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(3, 5), 1, "WARRIOR", "")
	map.set_unit_spawn_at_position(Vector2i(5, 5), 1, "ARCHER", "")
	map.set_unit_spawn_at_position(Vector2i(4, 4), 1, "ARCHER", "")
	
	save_template(map, "River Crossing")