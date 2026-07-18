extends GutTest

# Unit tests for the UnitStats component and its integration with Unit.
#
# Rewritten against the CURRENT schema: UnitStatsResource uses `max_health`,
# `movement_range`, and a String `unit_type` (no `base_health`/`base_movement`/
# `base_actions`, no UnitType object). The old suite also asserted removed legacy
# Unit properties (`speed`, `unit_name`, `max_movement`); those are gone and the
# tests were dropped. See tests/unit/test_unit_stats_resource.gd for the note on
# the .tres <-> script schema mismatch that is pending a follow-up.

var test_unit: Unit
var unit_stats: UnitStats
var warrior_resource: UnitStatsResource


func before_each():
	warrior_resource = UnitStatsResource.new()
	warrior_resource.unit_name = "Test Warrior"
	warrior_resource.unit_type = "warrior"
	warrior_resource.max_health = 120
	warrior_resource.base_attack = 25
	warrior_resource.base_defense = 15
	warrior_resource.base_speed = 8
	warrior_resource.movement_range = 3
	warrior_resource.attack_range = 1

	test_unit = Unit.new()
	test_unit.stats_resource = warrior_resource
	add_child(test_unit)  # triggers _ready(), which initializes the component
	unit_stats = test_unit.unit_stats


func after_each():
	if test_unit and is_instance_valid(test_unit):
		test_unit.free()
		test_unit = null


func test_component_initialization():
	assert_not_null(unit_stats, "UnitStats component should be created")
	assert_not_null(unit_stats.stats_resource, "Stats resource should be assigned")
	assert_eq(unit_stats.stats_resource.unit_name, "Test Warrior", "Resource should be correctly assigned")

func test_stat_access_through_unit():
	assert_eq(test_unit.get_stat("health"), 120, "Health should be accessible through unit")
	assert_eq(test_unit.get_stat("attack"), 25, "Attack should be accessible through unit")
	assert_eq(test_unit.get_stat("defense"), 15, "Defense should be accessible through unit")
	assert_eq(test_unit.get_stat("speed"), 8, "Speed should be accessible through unit")
	assert_eq(test_unit.get_stat("movement"), 3, "Movement should be accessible through unit")

func test_stat_modification():
	var original_attack := test_unit.get_stat("attack")
	test_unit.modify_stat("attack", 5)
	assert_eq(test_unit.get_stat("attack"), original_attack + 5, "Attack should be modified")
	assert_eq(test_unit.get_base_stat("attack"), original_attack, "Base attack should remain unchanged")

func test_health_management():
	assert_eq(test_unit.current_health, 120, "Current health should match base health")
	assert_eq(test_unit.max_health, 120, "Max health should match base health")
	assert_true(test_unit.is_alive(), "Unit should be alive")
	assert_true(test_unit.is_at_full_health(), "Unit should be at full health")

	test_unit.take_damage(30)
	assert_eq(test_unit.current_health, 90, "Health should decrease after damage")
	assert_true(test_unit.is_alive(), "Unit should still be alive")
	assert_false(test_unit.is_at_full_health(), "Unit should not be at full health")

	test_unit.heal(20)
	assert_eq(test_unit.current_health, 110, "Health should increase after healing")

	test_unit.take_damage(200)
	assert_eq(test_unit.current_health, 0, "Health should not go below 0")
	assert_false(test_unit.is_alive(), "Unit should be dead")

func test_temporary_modifiers():
	var original_speed := test_unit.get_stat("speed")
	var modifier_id := test_unit.add_stat_modifier("speed", 5, 3)

	assert_ne(modifier_id, -1, "Modifier ID should be valid")
	assert_eq(test_unit.get_stat("speed"), original_speed + 5, "Speed should be modified")

	var removed := test_unit.remove_stat_modifier(modifier_id)
	assert_true(removed, "Modifier should be removed successfully")
	assert_eq(test_unit.get_stat("speed"), original_speed, "Speed should return to original value")

func test_unit_type_is_string():
	# Current schema: unit_type is a plain String, and Unit.get_unit_type() returns it.
	assert_eq(test_unit.get_unit_type(), "warrior", "Unit type should be the resource's string")
	assert_eq(test_unit.get_display_name(), "Test Warrior", "Display name should match resource")

func test_movement_integration():
	assert_eq(test_unit.get_movement_range(), 3, "Movement range should match stats")
	assert_true(test_unit.can_move_to(Vector3(1, 0, 1)), "Should be able to move to a valid position")

func test_stat_validation_and_bounds():
	assert_true(unit_stats.validate_stats(), "Stats should be valid")

	test_unit.set_stat("health", 1000)  # above max
	assert_true(test_unit.get_stat("health") <= UnitStatsResource.MAX_HEALTH, "Health should be clamped to max")

	test_unit.set_stat("attack", -10)  # below min
	assert_true(test_unit.get_stat("attack") >= UnitStatsResource.MIN_ATTACK, "Attack should be clamped to min")

func test_signal_emission():
	watch_signals(unit_stats)

	test_unit.modify_stat("attack", 10)
	assert_signal_emitted(unit_stats, "stat_changed", "Stat changed signal should be emitted")

	test_unit.take_damage(20)
	assert_signal_emitted(unit_stats, "health_changed", "Health changed signal should be emitted")

func test_debug_functionality():
	var debug_info := test_unit.get_debug_info()
	assert_true(debug_info.has("name"), "Debug info should include name")
	assert_true(debug_info.has("alive"), "Debug info should include alive status")
	assert_true(debug_info.has("stats_component"), "Debug info should include component status")

	var unit_string := str(test_unit)
	assert_true(unit_string.contains("Test Warrior"), "String representation should include unit name")

func test_turn_processing():
	test_unit.add_stat_modifier("speed", 5, 2)  # 2-turn modifier

	test_unit.process_turn_start()
	assert_eq(test_unit.get_stat("speed"), 13, "Speed should be modified (8 + 5)")

	test_unit.process_turn_end()
	assert_eq(test_unit.get_stat("speed"), 13, "Speed should still be modified after one turn")
