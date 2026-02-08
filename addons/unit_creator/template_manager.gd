@tool
extends RefCounted

class_name UnitTemplateManager

# Manages unit templates for the Unit Creator tool

const TEMPLATES_DIR = "res://addons/unit_creator/templates/"

static func save_template(unit_data: Dictionary, template_name: String) -> bool:
	"""Save unit data as a template"""
	# Create templates directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(TEMPLATES_DIR):
		DirAccess.open("res://").make_dir_recursive("addons/unit_creator/templates")
	
	var template_path = TEMPLATES_DIR + template_name + ".json"
	var file = FileAccess.open(template_path, FileAccess.WRITE)
	
	if not file:
		print("Failed to create template file: " + template_path)
		return false
	
	# Add metadata
	var template_data = unit_data.duplicate()
	template_data["template_info"] = {
		"name": template_name,
		"created_date": Time.get_datetime_string_from_system(),
		"version": "1.0"
	}
	
	file.store_string(JSON.stringify(template_data, "\t"))
	file.close()
	
	print("Template saved: " + template_path)
	return true

static func load_template(template_name: String) -> Dictionary:
	"""Load unit template by name"""
	var template_path = TEMPLATES_DIR + template_name + ".json"
	
	if not FileAccess.file_exists(template_path):
		print("Template not found: " + template_path)
		return {}
	
	var file = FileAccess.open(template_path, FileAccess.READ)
	if not file:
		print("Failed to open template: " + template_path)
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse template JSON: " + json.get_error_message())
		return {}
	
	print("Template loaded: " + template_name)
	return json.data

static func get_available_templates() -> Array[String]:
	"""Get list of available template names"""
	var templates: Array[String] = []
	
	if not DirAccess.dir_exists_absolute(TEMPLATES_DIR):
		return templates
	
	var dir = DirAccess.open(TEMPLATES_DIR)
	if not dir:
		return templates
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".json"):
			var template_name = file_name.get_basename()
			templates.append(template_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return templates

static func delete_template(template_name: String) -> bool:
	"""Delete a template"""
	var template_path = TEMPLATES_DIR + template_name + ".json"
	
	if not FileAccess.file_exists(template_path):
		print("Template not found: " + template_path)
		return false
	
	var result = DirAccess.remove_absolute(template_path)
	if result == OK:
		print("Template deleted: " + template_name)
		return true
	else:
		print("Failed to delete template: " + template_name)
		return false

static func create_default_templates():
	"""Create default unit templates"""
	var templates = [
		{
			"name": "basic_warrior",
			"data": {
				"name": "basic_warrior",
				"display_name": "Basic Warrior",
				"description": "A standard melee fighter with balanced stats",
				"unit_type": "Warrior",
				"stats": {
					"health": 120,
					"attack": 25,
					"defense": 20,
					"magic": 5,
					"speed": 10,
					"movement": 3,
					"range": 1
				},
				"model_path": "",
				"profile_image_path": "",
				"moves": ["Basic Attack", "Power Strike", "Shield Wall"]
			}
		},
		{
			"name": "basic_archer",
			"data": {
				"name": "basic_archer",
				"display_name": "Basic Archer",
				"description": "A ranged fighter with high speed and accuracy",
				"unit_type": "Archer",
				"stats": {
					"health": 80,
					"attack": 20,
					"defense": 10,
					"magic": 8,
					"speed": 15,
					"movement": 3,
					"range": 4
				},
				"model_path": "",
				"profile_image_path": "",
				"moves": ["Basic Attack", "Poison Dart", "Power Strike"]
			}
		},
		{
			"name": "basic_mage",
			"data": {
				"name": "basic_mage",
				"display_name": "Basic Mage",
				"description": "A magic user with powerful spells and low defense",
				"unit_type": "Mage",
				"stats": {
					"health": 60,
					"attack": 10,
					"defense": 8,
					"magic": 25,
					"speed": 12,
					"movement": 2,
					"range": 3
				},
				"model_path": "",
				"profile_image_path": "",
				"moves": ["Basic Attack", "Fireball", "Heal", "Earthquake"]
			}
		}
	]
	
	for template in templates:
		save_template(template.data, template.name)
	
	print("Default templates created")