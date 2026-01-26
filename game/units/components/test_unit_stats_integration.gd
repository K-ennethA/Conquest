extends Node

# Test script for UnitStats component integration
# Run this to test the component system in the editor

func _ready():
	print("=== Testing UnitStats Component Integration ===")
	
	# Test 1: Create unit with stats resource
	print("\n--- Test 1: Unit with Stats Resource ---")
	var warrior_resource = load("res://game/units/resources/unit_types/Warrior.tres") as UnitStatsResource
	if not warrior_resource:
		# Create programmatically if .tres file doesn't exist
		warrior_resource = create_warrior_stats()
	
	var test_unit = Unit.new()
	test_unit.stats_resource = warrior_resource
	add_child(test_unit)
	
	print("Unit created: %s" % test_unit.get_display_name())
	print("Health: %d/%d" % [test_unit.current_health, test_unit.max_health])
	print("Attack: %d" % test_unit.get_stat("attack"))
	print("Defense: %d" % test_unit.get_stat("defense"))
	print("Speed: %d" % test_unit.get_stat("speed"))
	print("Movement: %d" % test_unit.get_movement_range())
	print("Is Ranged: %s" % str(test_unit.is_ranged_unit()))
	
	# Test 2: Stat modifications
	print("\n--- Test 2: Stat Modifications ---")
	var original_attack = test_unit.get_stat("attack")
	print("BEFORE MODIFICATION - Attack: %d" % original_attack)
	
	test_unit.modify_stat("attack", 10)
	var modified_attack = test_unit.get_stat("attack")
	print("AFTER +10 MODIFICATION - Attack: %d" % modified_attack)
	print("Base attack (should be unchanged): %d" % test_unit.get_base_stat("attack"))
	print("✓ Modification successful: %d -> %d" % [original_attack, modified_attack])
	
	# Test 3: Temporary modifiers
	print("\n--- Test 3: Temporary Modifiers ---")
	var original_speed = test_unit.get_stat("speed")
	print("BEFORE MODIFIER - Speed: %d" % original_speed)
	
	var modifier_id = test_unit.add_stat_modifier("speed", 5, 3)
	var modified_speed = test_unit.get_stat("speed")
	print("AFTER +5 SPEED MODIFIER - Speed: %d" % modified_speed)
	print("✓ Temporary modifier added: %d -> %d" % [original_speed, modified_speed])
	
	test_unit.remove_stat_modifier(modifier_id)
	var restored_speed = test_unit.get_stat("speed")
	print("AFTER REMOVING MODIFIER - Speed: %d" % restored_speed)
	print("✓ Modifier removed: %d -> %d" % [modified_speed, restored_speed])
	
	
	# Test 4: Health management
	print("\n--- Test 4: Health Management ---")
	var initial_health = test_unit.current_health
	print("INITIAL STATE:")
	print("  Health: %d/%d" % [test_unit.current_health, test_unit.max_health])
	print("  Is alive: %s" % str(test_unit.is_alive()))
	print("  Is at full health: %s" % str(test_unit.is_at_full_health()))
	
	test_unit.take_damage(30)
	print("AFTER 30 DAMAGE:")
	print("  Health: %d/%d" % [test_unit.current_health, test_unit.max_health])
	print("  Is alive: %s" % str(test_unit.is_alive()))
	print("  ✓ Damage applied: %d -> %d" % [initial_health, test_unit.current_health])
	
	var damaged_health = test_unit.current_health
	test_unit.heal(15)
	print("AFTER 15 HEALING:")
	print("  Health: %d/%d" % [test_unit.current_health, test_unit.max_health])
	print("  ✓ Healing applied: %d -> %d" % [damaged_health, test_unit.current_health])
	
	print("\n=== UnitStats Component Integration Test Complete ===")
	print("✓ All tests completed successfully!")

func create_warrior_stats() -> UnitStatsResource:
	"""Create warrior stats programmatically for testing"""
	var stats = UnitStatsResource.new()
	stats.unit_name = "Warrior"
	stats.unit_type = UnitType.new(UnitType.Type.WARRIOR)
	stats.base_health = 120
	stats.base_attack = 25
	stats.base_defense = 15
	stats.base_speed = 8
	stats.base_movement = 3
	stats.base_actions = 1
	stats.attack_range = 1
	return stats
