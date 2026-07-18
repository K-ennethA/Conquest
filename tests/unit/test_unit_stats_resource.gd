extends GutTest

# Unit tests for UnitStatsResource (game/units/resources/UnitStatsResource.gd).
#
# SCHEMA MISMATCH (documented for follow-up):
# The .tres data files under game/units/resources/unit_types/ (Warrior.tres etc.)
# were authored against an OLDER schema: they set `base_health`, `base_movement`,
# and `unit_type` as a UnitType sub-resource. The CURRENT UnitStatsResource.gd
# instead defines `max_health`, `movement_range`, and a plain String `unit_type`
# (and has no UnitType field, no MIN_HEALTH const, and validate_stats() returns a
# Dictionary rather than a bool).
#
# The previous test loaded those .tres files and asserted the old schema, so it
# could never pass against the current script. UnitStatsResource.gd is OUTSIDE
# this change's editable scope, so -- per the task's instruction -- these tests
# are written against the CURRENT script API using in-code resources (not the
# stale .tres). FOLLOW-UP: reconcile UnitStatsResource.gd to the data (base_*/
# UnitType), then restore .tres-driven assertions.

func _make_warrior() -> UnitStatsResource:
	var res := UnitStatsResource.new()
	res.unit_name = "Warrior"
	res.unit_type = "warrior"
	res.description = "Balanced melee fighter"
	res.max_health = 120
	res.base_attack = 25
	res.base_defense = 15
	res.base_magic = 10
	res.base_speed = 8
	res.movement_range = 3
	res.attack_range = 1
	return res


func test_stat_getter_methods():
	var w := _make_warrior()
	assert_eq(w.get_stat("health"), 120, "Warrior health should be 120")
	assert_eq(w.get_stat("attack"), 25, "Warrior attack should be 25")
	assert_eq(w.get_stat("defense"), 15, "Warrior defense should be 15")
	assert_eq(w.get_stat("magic"), 10, "Warrior magic should be 10")
	assert_eq(w.get_stat("speed"), 8, "Warrior speed should be 8")
	assert_eq(w.get_stat("movement"), 3, "Warrior movement should be 3")
	assert_eq(w.get_stat("range"), 1, "Warrior range should be 1")

func test_stat_aliases():
	var w := _make_warrior()
	assert_eq(w.get_stat("hp"), w.get_stat("health"), "hp alias should match health")
	assert_eq(w.get_stat("atk"), w.get_stat("attack"), "atk alias should match attack")
	assert_eq(w.get_stat("def"), w.get_stat("defense"), "def alias should match defense")

func test_invalid_stat_requests():
	var w := _make_warrior()
	assert_eq(w.get_stat("invalid_stat"), 0, "Invalid stat should return 0")
	assert_eq(w.get_stat(""), 0, "Empty stat name should return 0")

func test_get_all_stats():
	var all_stats := _make_warrior().get_all_stats()
	for key in ["health", "attack", "defense", "magic", "speed", "movement", "range"]:
		assert_true(all_stats.has(key), "get_all_stats should include '%s'" % key)
	assert_eq(all_stats["health"], 120, "Health value should match")
	assert_eq(all_stats["attack"], 25, "Attack value should match")

func test_display_name():
	assert_eq(_make_warrior().get_display_name(), "Warrior", "Display name should match unit_name")
	var unnamed := UnitStatsResource.new()
	assert_eq(unnamed.get_display_name(), "Unnamed Unit", "Empty name should fall back to 'Unnamed Unit'")

func test_stat_total():
	var w := _make_warrior()
	# get_stat_total = health + attack + defense + magic + speed
	assert_eq(w.get_stat_total(), 120 + 25 + 15 + 10 + 8, "Stat total should sum the five core stats")

func test_validate_stats_returns_dictionary():
	var w := _make_warrior()
	var result := w.validate_stats()
	assert_true(result is Dictionary, "validate_stats should return a Dictionary")
	assert_true(result.has("valid"), "Result should have a 'valid' key")
	assert_true(result.valid, "A well-formed warrior should validate")

func test_validate_stats_flags_missing_fields():
	var res := UnitStatsResource.new()  # empty name + type
	var result := res.validate_stats()
	assert_false(result.valid, "A resource with no name/type should be invalid")
	assert_gt(result.issues.size(), 0, "Invalid resource should report issues")

func test_stat_bounds_constant():
	assert_eq(UnitStatsResource.MAX_HEALTH, 999, "MAX_HEALTH constant should be 999")
	assert_eq(UnitStatsResource.MIN_ATTACK, 1, "MIN_ATTACK constant should be 1")

func test_display_info_shape():
	var info := _make_warrior().get_display_info()
	for key in ["name", "type", "health", "attack", "defense", "magic", "speed", "movement", "range"]:
		assert_true(info.has(key), "Display info should include '%s'" % key)
	assert_eq(info["name"], "Warrior", "Display info name should match")
