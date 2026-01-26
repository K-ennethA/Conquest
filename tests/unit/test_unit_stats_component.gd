extends GutTest

# Unit tests for UnitStats component integration
# Tests component functionality and Unit class integration

var test_unit: Unit
var unit_stats: UnitStats
var warrior_resource: UnitStatsResource

func before_each():
	# Create test unit with UnitStats component
	test_unit = Unit.new()
	
	# Create warrior stats resource
	warrior_resource = UnitStatsResource.new()
	warrior_resource.unit_name = "Test Warrior"
	warrior_resource.unit_type = UnitType.new(UnitType.Type.WARRIOR)
	warrior_resource.base_health = 120
	warrior_resource.base_attack = 25
	warrior_resource.base_defense = 15
	warrior_resource.base_speed = 8
	warrior_resource.base_movement = 3
	warrior_resource.base_actions = 1
	warrior_resource.attack_range = 1
	
	# Set up unit with stats resource
	test_unit.stats_resource = warrior_resource
	
	# Manually call _ready to initialize component
	test_unit._ready()
	unit_stats = test_unit.unit_stats

func after_each():
	if test_unit:
		test_unit.queue_free()

func test_component_initialization():
	assert_not_null(unit_stats, "UnitStats component should be created")
	assert_not_null(unit_stats.stats_resource, "Stats resource should be assigned")
	assert_eq(unit_stats.stats_resource.unit_name, "Test Warrior", "Resource should be correctly assigned")

func test_stat_access_through_unit():
	# Test getting stats through Unit interface
	assert_eq(test_unit.get_stat("health"), 120, "Health should be accessible through unit")
	assert_eq(test_unit.get_stat("attack"), 25, "Attack should be accessible through unit")
	assert_eq(test_unit.get_stat("defense"), 15, "Defense should be accessible through unit")
	assert_eq(test_unit.get_stat("speed"), 8, "Speed should be accessible through unit")
	assert_eq(test_unit.get_stat("movement"), 3, "Movement should be accessible through unit")

func test_legacy_property_compatibility():
	# Test that legacy properties still work
	assert_eq(test_unit.speed, 8, "Legacy speed property should work")
	assert_eq(test_unit.max_movement, 3, "Legacy max_movement property should work")
	assert_eq(test_unit.unit_name, "Test Warrior", "Legacy unit_name property should work")

func test_stat_modification():
	# Test stat modification through component
	var original_attack = test_unit.get_stat("attack")
	test_unit.modify_stat("attack", 5)
	
	assert_eq(test_unit.get_stat("attack"), original_attack + 5, "Attack should be modified")
	assert_eq(test_unit.get_base_stat("attack"), original_attack, "Base attack should remain unchanged")

func test_health_management():
	# Test health-related methods
	assert_eq(test_unit.current_health, 120, "Current health should match base health")
	assert_eq(test_unit.max_health, 120, "Max health should match base health")
	assert_true(test_unit.is_alive(), "Unit should be alive")
	assert_true(test_unit.is_at_full_health(), "Unit should be at full health")
	
	# Test damage
	test_unit.take_damage(30)
	assert_eq(test_unit.current_health, 90, "Health should decrease after damage")
	assert_true(test_unit.is_alive(), "Unit should still be alive")
	assert_false(test_unit.is_at_full_health(), "Unit should not be at full health")
	
	# Test healing
	test_unit.heal(20)
	assert_eq(test_unit.current_health, 110, "Health should increase after healing")
	
	# Test death
	test_unit.take_damage(200)
	assert_eq(test_unit.current_health, 0, "Health should not go below 0")
	assert_false(test_unit.is_alive(), "Unit should be dead")

func test_temporary_modifiers():
	# Test adding temporary stat modifiers
	var original_speed = test_unit.get_stat("speed")
	var modifier_id = test_unit.add_stat_modifier("speed", 5, 3)
	
	assert_ne(modifier_id, -1, "Modifier ID should be valid")
	assert_eq(test_unit.get_stat("speed"), original_speed + 5, "Speed should be modified")
	
	# Test removing modifier
	var removed = test_unit.remove_stat_modifier(modifier_id)
	assert_true(removed, "Modifier should be removed successfully")
	assert_eq(test_unit.get_stat("speed"), original_speed, "Speed should return to original value")

func test_unit_type_integration():
	# Test unit type methods
	var unit_type = test_unit.get_unit_type()
	assert_not_null(unit_type, "Unit type should be available")
	assert_eq(unit_type.type, UnitType.Type.WARRIOR, "Unit type should be warrior")
	
	assert_eq(test_unit.get_display_name(), "Test Warrior", "Display name should match resource")
	assert_false(test_unit.is_ranged_unit(), "Warrior should not be ranged")

func test_movement_integration():
	# Test movement-related methods
	assert_eq(test_unit.get_movement_range(), 3, "Movement range should match stats")
	assert_true(test_unit.can_move_to(Vector3(1, 0, 1)), "Should be able to move to valid position")

func test_stat_validation():
	# Test that stats are properly validated
	assert_true(unit_stats.validate_stats(), "Stats should be valid")
	
	# Test bounds checking
	test_unit.set_stat("health", 1000)  # Above max
	assert_true(test_unit.get_stat("health") <= UnitStatsResource.MAX_HEALTH, "Health should be clamped to max")
	
	test_unit.set_stat("attack", -10)  # Below min
	assert_true(test_unit.get_stat("attack") >= UnitStatsResource.MIN_ATTACK, "Attack should be clamped to min")

func test_signal_emission():
	# Test that stat change signals are emitted
	watch_signals(unit_stats)
	
	test_unit.modify_stat("attack", 10)
	
	assert_signal_emitted(unit_stats, "stat_changed", "Stat changed signal should be emitted")
	
	# Test health change signal
	test_unit.take_damage(20)
	assert_signal_emitted(unit_stats, "health_changed", "Health changed signal should be emitted")

func test_debug_functionality():
	# Test debug methods
	var debug_info = test_unit.get_debug_info()
	assert_true(debug_info.has("name"), "Debug info should include name")
	assert_true(debug_info.has("alive"), "Debug info should include alive status")
	assert_true(debug_info.has("stats_component"), "Debug info should include component status")
	
	var unit_string = str(test_unit)
	assert_true(unit_string.contains("Test Warrior"), "String representation should include unit name")

func test_turn_processing():
	# Test turn-related methods
	test_unit.add_stat_modifier("speed", 5, 2)  # 2-turn modifier
	
	test_unit.process_turn_start()
	assert_eq(test_unit.get_stat("speed"), 13, "Speed should be modified")  # 8 + 5
	
	# Process turn end (modifier should still be active)
	test_unit.process_turn_end()
	assert_eq(test_unit.get_stat("speed"), 13, "Speed should still be modified after 1 turn")
	
	# Process another turn start (modifier should expire after 2 turns)
	test_unit.process_turn_start()
	# Note: This test might need adjustment based on exact modifier duration logic

func test_backward_compatibility():
	# Test that Unit functionality works with stats resource
	var legacy_unit = Unit.new()
	legacy_unit.stats_resource = warrior_resource  # Use the existing resource
	add_child(legacy_unit)
	
	assert_not_null(legacy_unit.unit_stats, "Unit should have stats component")
	assert_eq(legacy_unit.get_display_name(), "Test Warrior", "Unit should have correct name")
	assert_eq(legacy_unit.get_stat("speed"), 8, "Unit should have correct speed")
	
	legacy_unit.queue_free()