extends Node3D

class_name HealthBar

# 3D Health bar that floats above units

@onready var background: MeshInstance3D = $Background
@onready var health_fill: MeshInstance3D = $HealthFill
@onready var label: Label3D = $Label

var _background_material: StandardMaterial3D
var _health_material: StandardMaterial3D

func _ready():
	_setup_materials()
	_setup_meshes()

func _setup_materials():
	# Background material (subtle dark border)
	_background_material = StandardMaterial3D.new()
	_background_material.albedo_color = Color(0.0, 0.0, 0.0, 0.8)  # Dark border
	_background_material.flags_transparent = true
	_background_material.flags_unshaded = true
	
	# Health fill material (classic RPG style)
	_health_material = StandardMaterial3D.new()
	_health_material.albedo_color = Color(0.2, 0.8, 0.2, 1.0)  # Slightly darker green
	_health_material.flags_unshaded = true

func _setup_meshes():
	# Create background quad (readable Fire Emblem style)
	var bg_mesh = QuadMesh.new()
	bg_mesh.size = Vector2(1.2, 0.25)  # Larger for better visibility
	background.mesh = bg_mesh
	background.material_override = _background_material
	
	# Create health fill quad (fits inside background)
	var health_mesh = QuadMesh.new()
	health_mesh.size = Vector2(1.1, 0.2)  # Slightly smaller than background
	health_fill.mesh = health_mesh
	health_fill.material_override = _health_material
	health_fill.position.z = 0.01  # Slightly in front of background
	
	# Position label above the health bar (Pokemon style)
	if label:
		label.position = Vector3(0, 0.2, 0)  # Above the health bar for clean separation
		label.font_size = 16  # Large, readable text
		label.outline_size = 3  # Thick outline for excellent visibility
		label.outline_modulate = Color.BLACK

func update_health(percentage: float, current: int, maximum: int):
	"""Update health bar display"""
	# Clamp percentage
	percentage = clamp(percentage, 0.0, 1.0)
	
	# Update fill width
	if health_fill and health_fill.mesh:
		var mesh = health_fill.mesh as QuadMesh
		mesh.size.x = 1.1 * percentage  # Scale based on background size
		
		# Adjust position to keep left-aligned
		health_fill.position.x = (1.1 * percentage - 1.1) * 0.5
	
	# Update color based on health percentage (classic RPG style)
	if _health_material:
		if percentage > 0.7:
			_health_material.albedo_color = Color(0.2, 0.8, 0.2, 1.0)  # Green
		elif percentage > 0.4:
			_health_material.albedo_color = Color(0.9, 0.9, 0.2, 1.0)  # Yellow
		elif percentage > 0.2:
			_health_material.albedo_color = Color(0.9, 0.5, 0.1, 1.0)  # Orange
		else:
			_health_material.albedo_color = Color(0.8, 0.2, 0.2, 1.0)  # Red
	
	# Update text label
	if label:
		label.text = str(current) + "/" + str(maximum)
		label.modulate = Color.WHITE
		label.visible = true
		# Make sure text is readable and always faces camera
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func set_visible_state(visible: bool):
	"""Show or hide the health bar"""
	self.visible = visible