extends Resource

class_name UnitType

# Unit type enumeration for different unit classes
enum Type {
	WARRIOR,
	ARCHER,
	SCOUT,
	TANK,
	MAGE
}

# Movement type enumeration
enum MovementType {
	GROUND,		# Standard ground movement, blocked by obstacles
	FLYING,		# Can move over obstacles and units
	TELEPORT	# Instant movement, ignores all obstacles
}

# Attack type enumeration  
enum AttackType {
	MELEE,		# Adjacent tile attacks only
	RANGED,		# Can attack at distance
	AREA		# Area of effect attacks
}

@export var type: Type = Type.WARRIOR
@export var display_name: String = ""
@export var description: String = ""
@export var movement_type: MovementType = MovementType.GROUND
@export var attack_type: AttackType = AttackType.MELEE

# Visual identification
@export var icon: Texture2D
@export var primary_color: Color = Color.WHITE
@export var secondary_color: Color = Color.GRAY

func _init(unit_type: Type = Type.WARRIOR):
	type = unit_type
	_set_default_values()

func _set_default_values() -> void:
	match type:
		Type.WARRIOR:
			display_name = "Warrior"
			description = "Balanced melee fighter with good health and attack"
			movement_type = MovementType.GROUND
			attack_type = AttackType.MELEE
			primary_color = Color.STEEL_BLUE
		Type.ARCHER:
			display_name = "Archer"
			description = "Ranged attacker with moderate health"
			movement_type = MovementType.GROUND
			attack_type = AttackType.RANGED
			primary_color = Color.FOREST_GREEN
		Type.SCOUT:
			display_name = "Scout"
			description = "Fast, lightly armored unit with high mobility"
			movement_type = MovementType.GROUND
			attack_type = AttackType.MELEE
			primary_color = Color.GOLD
		Type.TANK:
			display_name = "Tank"
			description = "Heavy armored unit with high health but low speed"
			movement_type = MovementType.GROUND
			attack_type = AttackType.MELEE
			primary_color = Color.DIM_GRAY
		Type.MAGE:
			display_name = "Mage"
			description = "Magical unit with area attacks and special abilities"
			movement_type = MovementType.GROUND
			attack_type = AttackType.AREA
			primary_color = Color.PURPLE

func get_type_name() -> String:
	return display_name

func is_ranged_unit() -> bool:
	return attack_type == AttackType.RANGED or attack_type == AttackType.AREA

func can_fly() -> bool:
	return movement_type == MovementType.FLYING

func can_teleport() -> bool:
	return movement_type == MovementType.TELEPORT