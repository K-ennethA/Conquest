extends GutTest

## EncounterRoller: DETERMINISTIC (a pure function of seed, area and step -- never randf()),
## rate-respecting, weight-respecting, condition-filtered; befriend rolls off the battle seed.


func _zone(rate: float, entries: Array) -> EncounterZone:
	var z := EncounterZone.new()
	z.rate = rate
	var t: Array[Resource] = []
	for pair in entries:
		var e := EncounterEntry.new()
		e.character_id = StringName(pair[0])
		e.weight = pair[1]
		if pair.size() > 2:
			e.condition = pair[2]
		t.append(e)
	z.table = t
	return z


func test_same_inputs_same_roll() -> void:
	var z := _zone(0.5, [["petalfang", 1.0], ["blightcap", 1.0]])
	for step in range(50):
		var a: Dictionary = EncounterRoller.roll(1234, "mossway", step, z)
		var b: Dictionary = EncounterRoller.roll(1234, "mossway", step, z)
		assert_eq(a["hit"], b["hit"], "step %d rolls the same hit twice" % step)
		assert_eq(a["entry"], b["entry"], "and the same entry")


func test_different_seeds_differ_somewhere() -> void:
	var z := _zone(0.5, [["petalfang", 1.0]])
	var diff: int = 0
	for step in range(64):
		if EncounterRoller.roll(1, "mossway", step, z)["hit"] != EncounterRoller.roll(2, "mossway", step, z)["hit"]:
			diff += 1
	assert_gt(diff, 0, "another journey seed rolls a different sequence")


func test_rate_is_respected_statistically() -> void:
	var z := _zone(0.1, [["petalfang", 1.0]])
	var hits: int = 0
	for step in range(4000):
		if EncounterRoller.roll(99, "mossway", step, z)["hit"]:
			hits += 1
	assert_between(hits, 280, 520, "about 10%% of 4000 steps hit (%d)" % hits)
	assert_false(EncounterRoller.roll(99, "mossway", 1, _zone(0.0, [["petalfang", 1.0]]))["hit"], "rate 0 never hits")


func test_weights_and_conditions() -> void:
	var z := _zone(1.0, [["petalfang", 3.0], ["blightcap", 1.0], ["tree_grunt", 5.0, "has(\"late\")"]])
	var counts: Dictionary = {}
	var s := StoryState.new()
	for step in range(2000):
		var r: Dictionary = EncounterRoller.roll(7, "mossway", step, z, s)
		assert_true(r["hit"], "rate 1 always hits")
		var id: String = String((r["entry"] as EncounterEntry).character_id)
		counts[id] = int(counts.get(id, 0)) + 1
	assert_false(counts.has("tree_grunt"), "a gated entry never appears while its condition fails")
	assert_between(int(counts.get("petalfang", 0)), 1300, 1700, "weight 3 of 4 (%s)" % str(counts))
	s.set_flag("late", 1)
	var seen: bool = false
	for step in range(200):
		if String((EncounterRoller.roll(7, "mossway", step, z, s)["entry"] as EncounterEntry).character_id) == "tree_grunt":
			seen = true
	assert_true(seen, "once the condition holds the gated entry can appear")


func test_zone_membership_by_tile_and_rect() -> void:
	var z := EncounterZone.new()
	assert_true(z.contains(Vector3i(3, 3, 0), &"tall_grass"), "the default zone is the tall grass itself")
	assert_false(z.contains(Vector3i(3, 3, 0), &"grass_plains"), "not plain grass")
	z.area_rect = Rect2i(0, 0, 2, 2)
	assert_false(z.contains(Vector3i(3, 3, 0), &"tall_grass"), "outside its rect")
	assert_true(z.contains(Vector3i(1, 1, 0), &"tall_grass"), "inside its rect")


func test_befriend_roll_is_deterministic_off_the_battle_seed() -> void:
	for seed_value in [1, 2, 3, 42, 99999]:
		assert_eq(EncounterRoller.befriend_offered(seed_value, 0.5), EncounterRoller.befriend_offered(seed_value, 0.5),
			"seed %d offers the same way twice" % seed_value)
	assert_false(EncounterRoller.befriend_offered(5, 0.0), "chance 0 never offers")
	assert_true(EncounterRoller.befriend_offered(5, 1.0), "chance 1 always offers")
