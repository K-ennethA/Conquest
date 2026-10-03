extends GutTest

## WildSpawner (visible, grid-locked wild creatures) as pure logic: the deterministic roster, one
## cell per player step, the leash, each behaviour, contact openings, respawn rules, the save
## record -- plus the BattleRequest / DuelRequest "opening" rule key and the duel's round-1 order.
## In-memory fixture area (tests/helpers/wild_fixture.gd); no tree, no disk.

const Fix := preload("res://tests/helpers/wild_fixture.gd")
const FAR := Vector3i(13, 9, 0)


func _state(seed_value: int = 4242) -> StoryState:
	var s := StoryState.new()
	s.rng_seed = seed_value
	return s


func _spawner(a: OverworldAreaResource, s: StoryState, player: Vector3i = FAR) -> WildSpawner:
	var g := OverworldGrid.build(a, s)
	var w := WildSpawner.create(a, g, s)
	w.sync(player)
	return w


func _cells(w: WildSpawner) -> Array:
	var out: Array = []
	for c in w.creatures:
		out.append([c.key, c.character_id(), c.cell, c.facing])
	return out


## Put creature [param c] on [param cell] facing [param facing] (moving its grid blocker).
func _place(w: WildSpawner, c, cell: Vector3i, facing: Vector2i) -> void:
	if w.grid.blocker_at(c.cell) == WildSpawner.blocker_id(c.key):
		w.grid.clear_blocker(c.cell)
	var other = w.creature_at(cell)
	if other != null and other != c:
		# Swap the occupant out of the way (to this creature's old cell).
		other.cell = c.cell
		w.grid.set_blocker(other.cell, WildSpawner.blocker_id(other.key))
	c.cell = cell
	c.facing = facing
	w.grid.set_blocker(cell, WildSpawner.blocker_id(c.key))


## A one-creature zone of [param behaviour].
func _solo(behaviour: int, sense: int = 3) -> OverworldAreaResource:
	var e = Fix.entry("petalfang", behaviour)
	e.sense_range = sense
	e.move_chance = 1.0
	return Fix.area([Fix.zone([e], 1)])


func test_roster_is_deterministic_and_fills_the_zone() -> void:
	var a := Fix.area()
	var w1 := _spawner(a, _state())
	var w2 := _spawner(a, _state())
	assert_eq(w1.creatures.size(), 4, "max_active creatures are placed")
	assert_eq(_cells(w1), _cells(w2), "same seed, area and epoch -> the same roster")
	var seen: Dictionary = {}
	for c in w1.creatures:
		assert_true(Fix.GRASS.has_point(Vector2i(c.cell.x, c.cell.y)), "%s stands in the grass" % c.key)
		assert_false(seen.has(c.cell), "no two creatures share a cell")
		seen[c.cell] = true
		assert_eq(w1.grid.blocker_at(c.cell), WildSpawner.blocker_id(c.key), "each is a grid blocker")
		assert_true(["petalfang", "blightcap"].has(c.character_id()), "species from the table")
	var other := _spawner(a, _state(99))
	assert_ne(_cells(w1), _cells(other), "another journey seed lays out another roster")


func test_spawn_clearance_keeps_the_arrival_cell_clear() -> void:
	var a := Fix.area()
	var player := Vector3i(6, 4, 0)
	for seed_value in [1, 2, 3, 4, 5]:
		var w := _spawner(a, _state(seed_value), player)
		for c in w.creatures:
			assert_gt(Cells.manhattan_2d(c.cell, player), 3, "nothing spawns on top of the hero (seed %d)" % seed_value)


func test_hidden_zones_spawn_nothing() -> void:
	var z = Fix.zone([Fix.entry("petalfang")])
	z.mode = EncounterZone.Mode.HIDDEN
	var w := _spawner(Fix.area([z]), _state())
	assert_false(w.has_zones(), "a hidden zone is the grass roll's, not the spawner's")
	assert_eq(w.creatures.size(), 0, "no visible creatures")
	assert_eq(EncounterZone.new().mode, EncounterZone.Mode.VISIBLE, "VISIBLE is the default mode")


func test_wander_is_deterministic_and_leashed() -> void:
	var a := Fix.area([Fix.zone([Fix.entry("petalfang"), Fix.entry("blightcap")], 5)])
	var s1 := _state()
	var s2 := _state()
	var w1 := _spawner(a, s1)
	var w2 := _spawner(a, s2)
	var moved := false
	for i in range(60):
		s1.steps += 1
		s2.steps += 1
		var before: Array = _cells(w1)
		w1.tick(FAR)
		w2.tick(FAR)
		assert_eq(_cells(w1), _cells(w2), "same step clock -> the same walk (step %d)" % i)
		if _cells(w1) != before:
			moved = true
		for c in w1.creatures:
			assert_true(Fix.GRASS.has_point(Vector2i(c.cell.x, c.cell.y)), "leashed to its zone (step %d)" % i)
	assert_true(moved, "wanderers do wander")


func test_one_cell_per_step() -> void:
	var w := _spawner(_solo(EncounterEntry.Behaviour.WANDER), _state())
	var c = w.creatures[0]
	for i in range(20):
		var before: Vector3i = c.cell
		w.state.steps += 1
		w.tick(FAR)
		assert_lte(Cells.manhattan_2d(before, c.cell), 1, "never more than one cell per step")


func test_timid_steps_away() -> void:
	var w := _spawner(_solo(EncounterEntry.Behaviour.TIMID, 3), _state())
	var c = w.creatures[0]
	_place(w, c, Vector3i(6, 4, 0), Vector2i(0, 1))
	var hero := Vector3i(4, 4, 0)
	w.state.steps += 1
	var r: Dictionary = w.tick(hero)
	assert_true((r["moved"] as Array).has(c), "it moves when the hero is near")
	assert_gt(Cells.manhattan_2d(c.cell, hero), 2, "and gets further away")
	_place(w, c, Vector3i(10, 7, 0), Vector2i(0, 1))
	w.state.steps += 1
	w.tick(Vector3i(9, 7, 0))
	assert_true(Fix.GRASS.has_point(Vector2i(c.cell.x, c.cell.y)), "a cornered creature never leaves its zone")


func test_aggressive_spots_approaches_and_walks_into_you() -> void:
	var w := _spawner(_solo(EncounterEntry.Behaviour.AGGRESSIVE, 4), _state())
	var c = w.creatures[0]
	_place(w, c, Vector3i(4, 4, 0), Vector2i(1, 0))
	var hero := Vector3i(7, 4, 0)
	w.state.steps += 1
	var r: Dictionary = w.tick(hero)
	assert_true((r["alerted"] as Array).has(c), "it sees the hero along its facing")
	assert_eq(c.cell, Vector3i(5, 4, 0), "and closes in one cell")
	w.state.steps += 1
	w.tick(hero)
	assert_eq(c.cell, Vector3i(6, 4, 0), "then another")
	w.state.steps += 1
	r = w.tick(hero, false)
	assert_null(r["contact"], "during grace (no contact allowed) it only glares")
	assert_eq(c.cell, Vector3i(6, 4, 0), "without stepping onto the hero")
	w.state.steps += 1
	r = w.tick(hero, true)
	assert_eq(r["contact"], c, "it walks into the hero: contact")
	# Out of sight (behind it) it just wanders.
	_place(w, c, Vector3i(8, 4, 0), Vector2i(1, 0))
	w.state.steps += 1
	r = w.tick(Vector3i(5, 4, 0))
	assert_false((r["alerted"] as Array).has(c), "a hero behind it is not seen")


func test_creatures_block_walking_but_not_sight() -> void:
	var e1 = Fix.entry("petalfang", EncounterEntry.Behaviour.AGGRESSIVE)
	e1.sense_range = 5
	var e2 = Fix.entry("blightcap", EncounterEntry.Behaviour.SLEEPING)
	var a := Fix.area([Fix.zone([e1], 1), Fix.zone([e2], 1)])
	var w := _spawner(a, _state())
	var hunter = w.creatures[0]
	var sleeper = w.creatures[1]
	_place(w, hunter, Vector3i(3, 3, 0), Vector2i(1, 0))
	_place(w, sleeper, Vector3i(5, 3, 0), Vector2i(0, 1))
	w.state.steps += 1
	var r: Dictionary = w.tick(Vector3i(7, 3, 0))
	assert_true((r["alerted"] as Array).has(hunter), "it looks over the sleeper (creatures never block sight)")
	assert_eq(hunter.cell, Vector3i(4, 3, 0), "and closes in")
	w.state.steps += 1
	w.tick(Vector3i(7, 3, 0))
	assert_eq(hunter.cell, Vector3i(4, 3, 0), "but cannot walk through the sleeper")
	assert_false(w.grid.blocks_sight(sleeper.cell), "the grid: a creature's cell is see-through")
	assert_false(w.grid.is_walkable(sleeper.cell), "but not walkable")


func test_sleeping_never_moves_and_is_always_an_ambush() -> void:
	var w := _spawner(_solo(EncounterEntry.Behaviour.SLEEPING), _state())
	var c = w.creatures[0]
	var start: Vector3i = c.cell
	for i in range(30):
		w.state.steps += 1
		w.tick(FAR)
	assert_eq(c.cell, start, "asleep: stationary")
	var front := Vector3i(c.cell.x + c.facing.x, c.cell.y + c.facing.y, 0)
	assert_eq(WildSpawner.contact_opening(c, front), BattleRequest.OPENING_AMBUSH,
		"even face to face, a sleeper is caught unaware")


func test_patrol_walks_its_loop() -> void:
	var e = Fix.entry("petalfang", EncounterEntry.Behaviour.PATROL)
	var pts: Array[Vector2i] = [Vector2i(4, 3), Vector2i(7, 3), Vector2i(7, 5)]
	e.patrol = pts
	var w := _spawner(Fix.area([Fix.zone([e], 1)]), _state())
	var c = w.creatures[0]
	assert_eq(c.cell, Vector3i(4, 3, 0), "a patrol starts on its first waypoint")
	var visited: Array = []
	for i in range(14):
		w.state.steps += 1
		w.tick(FAR)
		visited.append(Vector2i(c.cell.x, c.cell.y))
	assert_true(visited.has(Vector2i(7, 3)), "reaches the second waypoint")
	assert_true(visited.has(Vector2i(7, 5)), "and the third")
	assert_eq(visited.count(Vector2i(4, 3)) >= 1, true, "and loops back to the first")
	var issues: Array[String] = []
	var bad = Fix.entry("petalfang", EncounterEntry.Behaviour.PATROL)
	Fix.zone([bad], 1).validate(issues, "t")
	assert_true(issues.size() > 0, "a patrol with no route is a content error")


func test_contact_opening_from_behind_side_and_front() -> void:
	var w := _spawner(_solo(EncounterEntry.Behaviour.WANDER), _state())
	var c = w.creatures[0]
	_place(w, c, Vector3i(6, 4, 0), Vector2i(1, 0))
	assert_eq(WildSpawner.contact_opening(c, Vector3i(5, 4, 0)), BattleRequest.OPENING_AMBUSH, "from behind: ambush")
	assert_eq(WildSpawner.contact_opening(c, Vector3i(6, 3, 0)), BattleRequest.OPENING_AMBUSH, "from the side: ambush")
	assert_eq(WildSpawner.contact_opening(c, Vector3i(7, 4, 0)), BattleRequest.OPENING_NEUTRAL, "face to face: neutral")


func test_removed_creatures_stay_gone_until_reenter() -> void:
	var a := Fix.area()
	var s := _state()
	var w := _spawner(a, s)
	var key: String = w.creatures[1].key
	w.remove(key)
	assert_null(w.creature(key), "beaten: off the map")
	var again := _spawner(a, s)
	assert_eq(again.creatures.size(), 3, "same visit (a battle round trip / reload): still gone")
	assert_null(again.creature(key), "that slot stays empty")
	s.on_area_changed()
	var next := _spawner(a, s)
	assert_eq(next.creatures.size(), 4, "ON_REENTER: a new visit rolls a full roster")


func test_on_rest_respawn() -> void:
	var a := Fix.area([Fix.zone([Fix.entry("petalfang")], 3, EncounterZone.Respawn.ON_REST)])
	var s := _state()
	var w := _spawner(a, s)
	var key: String = w.creatures[0].key
	w.remove(key)
	s.on_area_changed()
	var w2 := _spawner(a, s)
	assert_null(w2.creature(key), "ON_REST: leaving and coming back does not bring it back")
	assert_eq(w2.creatures.size(), 2, "the survivors are still there")
	assert_eq(w2.refresh_respawns(FAR).size(), 0, "nothing to refill before a rest")
	s.heal_party()
	var back: Array = w2.refresh_respawns(FAR)
	assert_eq(back.size(), 1, "a rest refills the empty slot")
	assert_eq(w2.creatures.size(), 3, "a full zone again")


func test_every_n_steps_respawn() -> void:
	var z = Fix.zone([Fix.entry("petalfang")], 2, EncounterZone.Respawn.EVERY_N_STEPS)
	z.respawn_steps = 10
	var s := _state()
	var w := _spawner(Fix.area([z]), s)
	w.remove(w.creatures[0].key)
	s.steps += 9
	assert_eq(w.refresh_respawns(FAR).size(), 0, "not yet")
	s.steps += 1
	assert_eq(w.refresh_respawns(FAR).size(), 1, "after N steps the slot refills")


func test_conditions_filter_the_pool() -> void:
	var night = Fix.entry("blightcap")
	night.condition = "has(\"night\")"
	var a := Fix.area([Fix.zone([Fix.entry("petalfang"), night], 6)])
	var w := _spawner(a, _state())
	for c in w.creatures:
		assert_eq(c.character_id(), "petalfang", "a failing condition keeps a species out")


func test_save_round_trip_keeps_every_creature_in_place() -> void:
	var a := Fix.area()
	var s := _state()
	s.add_member("vineweave")
	var w := _spawner(a, s)
	for i in range(7):
		s.steps += 1
		w.tick(FAR)
	w.remove(w.creatures[0].key)
	var json: String = JSON.stringify(StorySnapshot.to_dict(s))
	var loaded: Dictionary = StorySnapshot.from_dict(JSON.parse_string(json))
	assert_true(bool(loaded["success"]), "the journey loads")
	var s2: StoryState = loaded["state"]
	assert_eq(s2.visit_serial, s.visit_serial, "the visit counter is saved")
	var w2 := _spawner(a, s2)
	assert_eq(_cells(w2), _cells(w), "after a reload every creature stands where it stood")
	s.steps += 1
	s2.steps += 1
	w.tick(FAR)
	w2.tick(FAR)
	assert_eq(_cells(w2), _cells(w), "and walks on exactly as it would have")


func test_old_and_malformed_saves_load() -> void:
	var s := _state()
	var d: Dictionary = StorySnapshot.to_dict(s)
	d.erase("wild")
	var r: Dictionary = StorySnapshot.from_dict(d)
	assert_true(bool(r["success"]), "a save from before visible spawns loads")
	assert_eq((r["state"] as StoryState).wild, {}, "with no wild records (fresh rosters)")
	var junk := WildSpawner.sanitize_saved({
		"bad": {"slots": {}},
		"a|z0": {"epoch": -3, "slots": {"0": {"cid": "petalfang", "cell": [1, 2, 0]}, "x": {}, "9": {"cid": "a", "cell": [0, 0]},
			"1": {"cid": "", "cell": [1, 1, 0]}, "2": "nope"}},
		"b|z1": "not a record",
	})
	assert_eq(junk.keys(), ["a|z0"], "keys without an area|zone shape and non-records are dropped")
	assert_eq((junk["a|z0"]["slots"] as Dictionary).keys(), ["0"], "only well-formed slots survive")
	assert_eq(int(junk["a|z0"]["epoch"]), 0, "numbers are clamped")
	# A saved creature whose species left the zone's table is dropped, not crashed on.
	var a := Fix.area()
	var s2 := _state()
	s2.wild = {"wild_test|z0": {"epoch": 0, "mark": 0, "visit": 0,
		"slots": {"0": {"cid": "no_such_creature", "cell": [5, 5, 0], "facing": "south", "wp": 0}}}}
	var w := _spawner(a, s2)
	assert_eq(w.creatures.size(), 0, "an unknown species is skipped")


func test_battle_request_opening_rule() -> void:
	var e = Fix.entry("petalfang")
	var r: BattleRequest = e.to_request("wild_test", "wild", BattleRequest.OPENING_AMBUSH)
	assert_eq(r.encounter_id, "wild_test.wild.petalfang", "a visible creature's encounter id")
	assert_eq(r.opening(), BattleRequest.OPENING_AMBUSH, "the opening rides on the rules")
	assert_eq(BattleRequest.from_dict(r.to_dict()).opening(), BattleRequest.OPENING_AMBUSH, "and round-trips")
	var grass: BattleRequest = e.to_request("wild_test")
	assert_eq(grass.encounter_id, "wild_test.grass.petalfang", "a hidden roll keeps its id")
	assert_false(grass.rules.has(BattleRequest.RULE_OPENING), "and has no opening")
	assert_eq(grass.opening(), BattleRequest.OPENING_NEUTRAL, "which reads neutral")


func test_duel_request_carries_the_opening() -> void:
	var e = Fix.entry("petalfang")
	var br: BattleRequest = e.to_request("wild_test", "wild", BattleRequest.OPENING_AMBUSHED)
	br.party = [{"member_id": "vineweave", "character_id": "vineweave", "current_hp": -1, "item_id": ""}]
	var d: Dictionary = DuelRequest.from_battle_request(br.to_dict())
	assert_true(bool(d["success"]), "the duel request builds")
	var dr: DuelRequest = d["request"]
	assert_eq(dr.opening_side(), 1, "ambushed: the foe opens round 1")
	var again: Dictionary = DuelRequest.from_dict(dr.to_dict())
	assert_eq((again["request"] as DuelRequest).opening_side(), 1, "recorded with the request (replays)")
	var raw: Dictionary = dr.to_dict()
	raw["rules"] = {"opening": "first_blood"}
	assert_false(bool(DuelRequest.from_dict(raw)["success"]), "an unknown opening is refused by the strict importer")
	br.rules["opening"] = BattleRequest.OPENING_AMBUSH
	assert_eq((DuelRequest.from_battle_request(br.to_dict())["request"] as DuelRequest).opening_side(), 0,
		"ambush: the player opens")
	br.rules.erase("opening")
	assert_eq((DuelRequest.from_battle_request(br.to_dict())["request"] as DuelRequest).opening_side(), -1,
		"no opening: speed order")
