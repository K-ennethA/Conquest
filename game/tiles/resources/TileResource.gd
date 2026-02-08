extends Resource

class_name TileResource

# Resource for storing tile configurations and properties
# Used by the Tile Creator tool and tile system

@export var tile_name: String = ""
@export var tile_type: Tile.TileType = Tile.TileType.NORMAL
@export var description: String = ""

# Movement Properties
@export var base_movement_cost: int = 1
@export var is_passable: bool = true
@export var blocks_line_of_sight: bool = false

# Visual Properties
@export var base_color: Color = Color.WHITE
@export var emission_enabled: bool = false
@export var emission_color: Color = Color.BLACK
@export var metallic: float = 0.0
@export var roughness: float = 1.0
@export var texture_path: String = ""
@export var model_path: String = ""

# Effect Properties
@export var has_default_effects: bool = false
@export var default_effects: Array = []

# Audio Properties
@export var step_sound: AudioStream
@export var ambient_sound: AudioStream

# Gameplay Properties
@export var provides_cover: bool = false
@export var cover_bonus: int = 0
@export var elevation: int = 0  # Height advantage
@export var special_properties: Array[String] = []

# Rarity and Cost (for procedural generation)
@export var rarity: String = "Common"  # Common, Uncommon, Rare, Epic, Legendary
@export var generation_weight: float = 1.0

func _init():
	resource_name = "TileResource"

func create_tile_effects() -> Array[TileEffect]:
	"""Create tile effects based on configuration"""
	var effects: Array[TileEffect] = []
	
	# Add default effects based on tile type
	match tile_type:
		Tile.TileType.LAVA:
			var fire_effect = TileEffect.new()
			fire_effect.effect_name = "Lava Burn"
			fire_effect.effect_type = TileEffect.EffectType.FIRE_DAMAGE
			fire_effect.strength = 2
			fire_effect.duration = -1  # Permanent
			fire_effect.triggers_on_enter = true
			fire_effect.triggers_on_turn_start = true
			effects.append(fire_effect)
		
		Tile.TileType.ICE:
			var ice_effect = TileEffect.new()
			ice_effect.effect_name = "Slippery Ice"
			ice_effect.effect_type = TileEffect.EffectType.SLOW
			ice_effect.strength = 1
			ice_effect.duration = 2
			ice_effect.triggers_on_enter = true
			effects.append(ice_effect)
		
		Tile.TileType.SWAMP:
			var slow_effect = TileEffect.new()
			slow_effect.effect_name = "Swamp Mud"
			slow_effect.effect_type = TileEffect.EffectType.DIFFICULT_TERRAIN
			slow_effect.strength = 1
			slow_effect.duration = -1
			effects.append(slow_effect)
		
		Tile.TileType.SACRED_GROUND:
			var healing_effect = TileEffect.new()
			healing_effect.effect_name = "Sacred Blessing"
			healing_effect.effect_type = TileEffect.EffectType.HEALING_SPRING
			healing_effect.strength = 1
			healing_effect.duration = -1
			healing_effect.triggers_on_turn_start = true
			effects.append(healing_effect)
		
		Tile.TileType.CORRUPTED:
			var poison_effect = TileEffect.new()
			poison_effect.effect_name = "Corruption"
			poison_effect.effect_type = TileEffect.EffectType.POISON_DAMAGE
			poison_effect.strength = 1
			poison_effect.duration = -1
			poison_effect.triggers_on_enter = true
			poison_effect.triggers_on_turn_start = true
			effects.append(poison_effect)
	
	# Add custom default effects (safely handle untyped array)
	for effect in default_effects:
		if effect != null and effect is TileEffect:
			effects.append(effect)
	
	return effects

func get_movement_cost() -> int:
	"""Get base movement cost for this tile type"""
	match tile_type:
		Tile.TileType.NORMAL:
			return 1
		Tile.TileType.DIFFICULT_TERRAIN:
			return 2
		Tile.TileType.WATER:
			return 3
		Tile.TileType.WALL:
			return 999  # Impassable
		Tile.TileType.SPECIAL:
			return 1
		Tile.TileType.LAVA:
			return 4
		Tile.TileType.ICE:
			return 1
		Tile.TileType.SWAMP:
			return 3
		Tile.TileType.SACRED_GROUND:
			return 1
		Tile.TileType.CORRUPTED:
			return 2
		_:
			return base_movement_cost

func is_tile_passable() -> bool:
	"""Check if this tile type is passable"""
	return is_passable and tile_type != Tile.TileType.WALL

func get_display_info() -> Dictionary:
	"""Get formatted info for UI display"""
	return {
		"name": tile_name,
		"type": Tile.TileType.keys()[tile_type],
		"description": description,
		"movement_cost": get_movement_cost(),
		"passable": is_tile_passable(),
		"has_effects": has_default_effects,
		"effect_count": default_effects.size(),
		"rarity": rarity,
		"provides_cover": provides_cover,
		"elevation": elevation
	}

func validate_configuration() -> Dictionary:
	"""Validate tile configuration"""
	var issues: Array[String] = []
	var warnings: Array[String] = []
	
	# Check required fields
	if tile_name.is_empty():
		issues.append("Tile name is required")
	
	if description.is_empty():
		warnings.append("Description is recommended")
	
	# Check movement cost
	if base_movement_cost < 1:
		issues.append("Movement cost must be at least 1")
	
	if base_movement_cost > 10:
		warnings.append("Very high movement cost: " + str(base_movement_cost))
	
	# Check color values
	if base_color.a < 0.1:
		warnings.append("Tile may be too transparent")
	
	# Check effects
	if has_default_effects and default_effects.is_empty():
		warnings.append("Has effects enabled but no effects defined")
	
	return {
		"valid": issues.is_empty(),
		"issues": issues,
		"warnings": warnings
	}

func create_material() -> StandardMaterial3D:
	"""Create material based on tile configuration"""
	var material = StandardMaterial3D.new()
	
	material.albedo_color = base_color
	material.metallic = metallic
	material.roughness = roughness
	
	if emission_enabled:
		material.emission_enabled = true
		material.emission = emission_color
	
	# Load texture if specified
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		var texture = load(texture_path) as Texture2D
		if texture:
			material.albedo_texture = texture
	
	return material

func export_to_json() -> String:
	"""Export tile data to JSON format"""
	var data = {
		"tile_name": tile_name,
		"tile_type": Tile.TileType.keys()[tile_type],
		"description": description,
		"movement": {
			"base_movement_cost": base_movement_cost,
			"is_passable": is_passable,
			"blocks_line_of_sight": blocks_line_of_sight
		},
		"visual": {
			"base_color": {
				"r": base_color.r,
				"g": base_color.g,
				"b": base_color.b,
				"a": base_color.a
			},
			"emission_enabled": emission_enabled,
			"emission_color": {
				"r": emission_color.r,
				"g": emission_color.g,
				"b": emission_color.b,
				"a": emission_color.a
			},
			"metallic": metallic,
			"roughness": roughness,
			"texture_path": texture_path,
			"model_path": model_path
		},
		"gameplay": {
			"provides_cover": provides_cover,
			"cover_bonus": cover_bonus,
			"elevation": elevation,
			"special_properties": special_properties,
			"rarity": rarity,
			"generation_weight": generation_weight
		},
		"effects": {
			"has_default_effects": has_default_effects,
			"effect_count": default_effects.size()
		}
	}
	
	return JSON.stringify(data, "\t")

static func import_from_json(json_string: String) -> TileResource:
	"""Import tile data from JSON format"""
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("Failed to parse JSON: " + json.get_error_message())
		return null
	
	var data = json.data
	var resource = TileResource.new()
	
	# Basic info
	resource.tile_name = data.get("tile_name", "")
	resource.description = data.get("description", "")
	
	# Tile type
	var type_name = data.get("tile_type", "NORMAL")
	for i in range(Tile.TileType.size()):
		if Tile.TileType.keys()[i] == type_name:
			resource.tile_type = i
			break
	
	# Movement
	var movement = data.get("movement", {})
	resource.base_movement_cost = movement.get("base_movement_cost", 1)
	resource.is_passable = movement.get("is_passable", true)
	resource.blocks_line_of_sight = movement.get("blocks_line_of_sight", false)
	
	# Visual
	var visual = data.get("visual", {})
	var base_color_data = visual.get("base_color", {"r": 1, "g": 1, "b": 1, "a": 1})
	resource.base_color = Color(
		base_color_data.get("r", 1),
		base_color_data.get("g", 1),
		base_color_data.get("b", 1),
		base_color_data.get("a", 1)
	)
	
	var emission_color_data = visual.get("emission_color", {"r": 0, "g": 0, "b": 0, "a": 1})
	resource.emission_color = Color(
		emission_color_data.get("r", 0),
		emission_color_data.get("g", 0),
		emission_color_data.get("b", 0),
		emission_color_data.get("a", 1)
	)
	
	resource.emission_enabled = visual.get("emission_enabled", false)
	resource.metallic = visual.get("metallic", 0.0)
	resource.roughness = visual.get("roughness", 1.0)
	resource.texture_path = visual.get("texture_path", "")
	resource.model_path = visual.get("model_path", "")
	
	# Gameplay
	var gameplay = data.get("gameplay", {})
	resource.provides_cover = gameplay.get("provides_cover", false)
	resource.cover_bonus = gameplay.get("cover_bonus", 0)
	resource.elevation = gameplay.get("elevation", 0)
	resource.special_properties = gameplay.get("special_properties", [])
	resource.rarity = gameplay.get("rarity", "Common")
	resource.generation_weight = gameplay.get("generation_weight", 1.0)
	
	# Effects
	var effects = data.get("effects", {})
	resource.has_default_effects = effects.get("has_default_effects", false)
	
	return resource