extends Node

# Centralized resource management for shaders, materials, and other assets
# Implements pooling and caching to improve performance

var _shader_cache: Dictionary = {}
var _material_cache: Dictionary = {}

# Shader resources
const SELECTION_SHADER = preload("res://selected_shader.gdshader")

func _ready() -> void:
	name = "ResourceManager"

# Get or create a selection shader material
func get_selection_material(original_color: Color) -> ShaderMaterial:
	var cache_key = "selection_" + str(original_color)
	
	if not _material_cache.has(cache_key):
		var material = ShaderMaterial.new()
		material.shader = SELECTION_SHADER
		material.set_shader_parameter("original_color", original_color)
		material.set_shader_parameter("is_selected", false)
		_material_cache[cache_key] = material
	
	return _material_cache[cache_key]

# Update selection state for a material
func set_selection_state(material: ShaderMaterial, is_selected: bool) -> void:
	if material and material.shader == SELECTION_SHADER:
		material.set_shader_parameter("is_selected", is_selected)

# Clear unused materials (call periodically to manage memory)
func clear_unused_materials() -> void:
	# In a more complex system, you'd track usage and clear unused materials
	# For now, this is a placeholder for future optimization
	pass