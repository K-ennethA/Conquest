@tool
extends EditorScript

# Script to create unit resources programmatically
# Run this in the editor to generate .tres files

func _run():
	print("Creating unit resources...")
	
	# Create directory if it doesn't exist
	if not DirAccess.dir_exists_absolute("res://game/units/resources/unit_types"):
		DirAccess.open("res://").make_dir_recursive("game/units/resources/unit_types")
	
	# Create Warrior
	var warrior = UnitStatsResource.new()
	warrior.unit_name = "Warrior"
	warrior.unit_type = UnitType.new(UnitType.Type.WARRIOR)
	warrior.base_health = 120
	warrior.base_attack = 25
	warrior.base_defense = 15
	warrior.base_speed = 8
	warrior.base_movement = 3
	warrior.base_actions = 1
	warrior.attack_range = 1
	ResourceSaver.save(warrior, "res://game/units/resources/unit_types/Warrior.tres")
	
	# Create Archer
	var archer = UnitStatsResource.new()
	archer.unit_name = "Archer"
	archer.unit_type = UnitType.new(UnitType.Type.ARCHER)
	archer.base_health = 80
	archer.base_attack = 30
	archer.base_defense = 8
	archer.base_speed = 12
	archer.base_movement = 3
	archer.base_actions = 1
	archer.attack_range = 3
	ResourceSaver.save(archer, "res://game/units/resources/unit_types/Archer.tres")
	
	# Create Scout
	var scout = UnitStatsResource.new()
	scout.unit_name = "Scout"
	scout.unit_type = UnitType.new(UnitType.Type.SCOUT)
	scout.base_health = 60
	scout.base_attack = 18
	scout.base_defense = 5
	scout.base_speed = 18
	scout.base_movement = 5
	scout.base_actions = 2
	scout.attack_range = 1
	ResourceSaver.save(scout, "res://game/units/resources/unit_types/Scout.tres")
	
	# Create Tank
	var tank = UnitStatsResource.new()
	tank.unit_name = "Tank"
	tank.unit_type = UnitType.new(UnitType.Type.TANK)
	tank.base_health = 180
	tank.base_attack = 20
	tank.base_defense = 25
	tank.base_speed = 4
	tank.base_movement = 2
	tank.base_actions = 1
	tank.attack_range = 1
	ResourceSaver.save(tank, "res://game/units/resources/unit_types/Tank.tres")
	
	print("Unit resources created successfully!")
	print("- Warrior.tres")
	print("- Archer.tres") 
	print("- Scout.tres")
	print("- Tank.tres")
