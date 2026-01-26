extends GutTest

# Unit tests for UnitStatsResource system
# Tests resource loading, stat validation, and utility methods

var warrior_stats: UnitStatsResource
var archer_stats: UnitStatsResource
var scout_stats: UnitStatsResource
var tank_stats: UnitStatsResource

func before_each():
	# Load test unit resources
	warrior_stats = load("res://game/units/resources/unit_types/Warrior.tres")
	archer_stats = load("res://game/units/resources/unit_types/Archer.tres")
	scout_stats = load("res://game/units/resources/unit_types/Scout.tres")
	tank_stats = load("res://game/units/resources/unit_types/Tank.tres")

func test_resource_loading():
	assert_not_null(warrior_stats, "Warrior stats should load successfully")
	assert_not_null(archer_stats, "Archer stats should load successfully")
	assert_not_null(scout_stats, "Scout stats should load successfully")
	assert_not_null(tank_stats, "Tank stats should load successfully")

func test_unit_type_properties():
	assert_eq(warrior_stats.unit_type.type, UnitType.Type.WARRIOR, "Warrior should have correct type")
	assert_eq(archer_stats.unit_type.type, UnitType.Type.ARCHER, "Archer should have correct type")
	assert_eq(scout_stats.unit_type.type, UnitType.Type.SCOUT, "Scout should have correct type")
	assert_eq(tank_stats.unit_type.type, UnitType.Type.TANK, "Tank should have correct type")

func test_stat_validation():
	assert_true(warrior_stats.validate_stats(), "Warrior stats should be valid")
	assert_true(archer_stats.validate_stats(), "Archer stats should be valid")
	assert_true(scout_stats.validate_stats(), "Scout stats should be valid")
	assert_true(tank_stats.validate_stats(), "Tank stats should be valid")

func test_stat_getter_methods():
	# Test warrior stats
	assert_eq(warrior_stats.get_stat("health"), 120, "Warrior health should be 120")
	assert_eq(warrior_stats.get_stat("attack"), 25, "Warrior attack should be 25")
	assert_eq(warrior_stats.get_stat("defense"), 15, "Warrior defense should be 15")
	assert_eq(warrior_stats.get_stat("speed"), 8, "Warrior speed should be 8")
	
	# Test archer stats
	assert_eq(archer_stats.get_stat("range"), 3, "Archer range should be 3")
	assert_true(archer_stats.is_ranged_unit(), "Archer should be ranged unit")
	
	# Test scout stats
	assert_eq(scout_stats.get_stat("movement"), 5, "Scout movement should be 5")
	assert_eq(scout_stats.get_stat("actions"), 2, "Scout should have 2 actions")

func test_unit_type_characteristics():
	# Test movement types
	assert_eq(warrior_stats.unit_type.movement_type, UnitType.MovementType.GROUND, "Warrior should have ground movement")
	assert_false(warrior_stats.unit_type.can_fly(), "Warrior should not be able to fly")
	
	# Test attack types
	assert_eq(archer_stats.unit_type.attack_type, UnitType.AttackType.RANGED, "Archer should have ranged attack")
	assert_true(archer_stats.unit_type.is_ranged_unit(), "Archer should be ranged unit")
	
	assert_eq(warrior_stats.unit_type.attack_type, UnitType.AttackType.MELEE, "Warrior should have melee attack")
	assert_false(warrior_stats.unit_type.is_ranged_unit(), "Warrior should not be ranged unit")

func test_stat_ranges():
	# Test that all stats are within valid ranges
	assert_ge(warrior_stats.base_health, UnitStatsResource.MIN_HEALTH, "Health should be >= minimum")
	assert_le(warrior_stats.base_health, UnitStatsResource.MAX_HEALTH, "Health should be <= maximum")
	
	assert_ge(archer_stats.base_attack, UnitStatsResource.MIN_ATTACK, "Attack should be >= minimum")
	assert_le(archer_stats.base_attack, UnitStatsResource.MAX_ATTACK, "Attack should be <= maximum")
	
	assert_ge(scout_stats.base_speed, UnitStatsResource.MIN_SPEED, "Speed should be >= minimum")
	assert_le(scout_stats.base_speed, UnitStatsResource.MAX_SPEED, "Speed should be <= maximum")

func test_display_names():
	assert_eq(warrior_stats.get_display_name(), "Warrior", "Warrior should have correct display name")
	assert_eq(archer_stats.get_display_name(), "Archer", "Archer should have correct display name")
	assert_eq(scout_stats.get_display_name(), "Scout", "Scout should have correct display name")
	assert_eq(tank_stats.get_display_name(), "Tank", "Tank should have correct display name")

func test_combat_calculations():
	# Test combat power calculation
	var warrior_power = warrior_stats.get_total_combat_power()
	var tank_power = tank_stats.get_total_combat_power()
	
	assert_gt(tank_power, warrior_power, "Tank should have higher combat power than warrior")
	
	# Test mobility rating
	var scout_mobility = scout_stats.get_mobility_rating()
	var tank_mobility = tank_stats.get_mobility_rating()
	
	assert_gt(scout_mobility, tank_mobility, "Scout should have higher mobility than tank")

func test_stat_modification():
	# Test creating modified copies
	var modifiers = {"health": 20, "attack": -5, "speed": 3}
	var modified_warrior = warrior_stats.create_modified_copy(modifiers)
	
	assert_eq(modified_warrior.base_health, 140, "Modified health should be 120 + 20")
	assert_eq(modified_warrior.base_attack, 20, "Modified attack should be 25 - 5")
	assert_eq(modified_warrior.base_speed, 11, "Modified speed should be 8 + 3")
	
	# Original should be unchanged
	assert_eq(warrior_stats.base_health, 120, "Original health should be unchanged")
	assert_eq(warrior_stats.base_attack, 25, "Original attack should be unchanged")

func test_get_all_stats():
	var all_stats = warrior_stats.get_all_stats()
	
	assert_true(all_stats.has("health"), "Should include health stat")
	assert_true(all_stats.has("attack"), "Should include attack stat")
	assert_true(all_stats.has("defense"), "Should include defense stat")
	assert_true(all_stats.has("speed"), "Should include speed stat")
	assert_true(all_stats.has("movement"), "Should include movement stat")
	assert_true(all_stats.has("actions"), "Should include actions stat")
	assert_true(all_stats.has("range"), "Should include range stat")
	
	assert_eq(all_stats["health"], 120, "Health value should match")
	assert_eq(all_stats["attack"], 25, "Attack value should match")

func test_invalid_stat_requests():
	# Test requesting non-existent stats
	assert_eq(warrior_stats.get_stat("invalid_stat"), 0, "Invalid stat should return 0")
	assert_eq(warrior_stats.get_stat(""), 0, "Empty stat name should return 0")

func test_unit_balance():
	# Basic balance validation - ensure no unit is overpowered
	var units = [warrior_stats, archer_stats, scout_stats, tank_stats]
	
	for unit in units:
		var total_stats = unit.base_health + unit.base_attack + unit.base_defense + unit.base_speed + (unit.base_movement * 10)
		assert_gt(total_stats, 100, unit.get_display_name() + " should have reasonable total stats")
		assert_lt(total_stats, 400, unit.get_display_name() + " should not be overpowered")

func test_to_string_method():
	var warrior_string = str(warrior_stats)
	assert_true(warrior_string.contains("Warrior"), "String should contain unit name")
	assert_true(warrior_string.contains("HP:120"), "String should contain health")
	assert_true(warrior_string.contains("ATK:25"), "String should contain attack")