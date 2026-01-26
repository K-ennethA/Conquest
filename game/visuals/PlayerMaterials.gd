extends Resource

class_name PlayerMaterials

# Resource for managing player-specific visual themes
# Uses PlayerTeam enum to avoid naming conflicts with Player class

enum PlayerTeam {
	PLAYER_1,
	PLAYER_2,
	NEUTRAL
}

# Player color themes
const PLAYER_1_PRIMARY = Color(0.2, 0.4, 0.8, 1.0)    # Blue
const PLAYER_1_SECONDARY = Color(0.4, 0.6, 0.9, 1.0)  # Light Blue
const PLAYER_2_PRIMARY = Color(0.8, 0.2, 0.2, 1.0)    # Red
const PLAYER_2_SECONDARY = Color(0.9, 0.4, 0.4, 1.0)  # Light Red
const NEUTRAL_PRIMARY = Color(0.6, 0.6, 0.6, 1.0)     # Gray
const NEUTRAL_SECONDARY = Color(0.8, 0.8, 0.8, 1.0)   # Light Gray

# Cached materials
var _player_materials: Dictionary = {}

func get_player_primary_color(player_team: PlayerTeam) -> Color:
	match player_team:
		PlayerTeam.PLAYER_1:
			return PLAYER_1_PRIMARY
		PlayerTeam.PLAYER_2:
			return PLAYER_2_PRIMARY
		PlayerTeam.NEUTRAL:
			return NEUTRAL_PRIMARY
		_:
			return NEUTRAL_PRIMARY

func get_player_secondary_color(player_team: PlayerTeam) -> Color:
	match player_team:
		PlayerTeam.PLAYER_1:
			return PLAYER_1_SECONDARY
		PlayerTeam.PLAYER_2:
			return PLAYER_2_SECONDARY
		PlayerTeam.NEUTRAL:
			return NEUTRAL_SECONDARY
		_:
			return NEUTRAL_SECONDARY

func get_player_material(player_team: PlayerTeam, unit_type: UnitType.Type = UnitType.Type.WARRIOR) -> StandardMaterial3D:
	var key = str(player_team) + "_" + str(unit_type)
	
	if not _player_materials.has(key):
		_player_materials[key] = _create_player_material(player_team, unit_type)
	
	return _player_materials[key]

func _create_player_material(player_team: PlayerTeam, unit_type: UnitType.Type) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	
	# Base color based on player
	material.albedo_color = get_player_primary_color(player_team)
	
	# Unit type variations
	match unit_type:
		UnitType.Type.WARRIOR:
			material.metallic = 0.3
			material.roughness = 0.7
		UnitType.Type.ARCHER:
			material.metallic = 0.1
			material.roughness = 0.8
			# Slightly darker for archers
			material.albedo_color = material.albedo_color.darkened(0.1)
		UnitType.Type.SCOUT:
			material.metallic = 0.0
			material.roughness = 0.9
			# Slightly brighter for scouts
			material.albedo_color = material.albedo_color.lightened(0.1)
		UnitType.Type.TANK:
			material.metallic = 0.6
			material.roughness = 0.4
			# Darker and more metallic for tanks
			material.albedo_color = material.albedo_color.darkened(0.2)
		UnitType.Type.MAGE:
			material.metallic = 0.0
			material.roughness = 0.6
			# Add some emission for mages
			material.emission_enabled = true
			material.emission = material.albedo_color * 0.2
	
	return material

func get_selection_material(base_color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = base_color.lightened(0.3)
	material.emission_enabled = true
	material.emission = base_color * 0.3
	material.rim_enabled = true
	material.rim = Color.WHITE
	material.rim_tint = 0.5
	return material