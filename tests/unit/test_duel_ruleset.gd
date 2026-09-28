extends GutTest

## The pure duel rules on DuelRuleset (DECISIONS.md: befriend join chance + subdue bonus as
## ruleset data, rolled from the battle's seeded stream) and DuelRequest's strict importer.


func _rules() -> DuelRuleset:
	var r := DuelRuleset.new()
	r.befriend_base_chance = 0.25
	r.befriend_subdue_bonus = 0.35
	return r


func test_join_chance_is_base_plus_subdue_bonus() -> void:
	var r := _rules()
	assert_almost_eq(r.join_chance(false), 0.25, 0.0001)
	assert_almost_eq(r.join_chance(true), 0.60, 0.0001)
	r.befriend_subdue_bonus = 0.9
	assert_almost_eq(r.join_chance(true), 1.0, 0.0001, "clamped to 1")


func test_roll_join_is_reproducible_from_the_seeded_stream() -> void:
	var r := _rules()
	var outcomes: Array = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 424242
		outcomes.append(r.roll_join(rng, true))
	assert_eq(outcomes[0], outcomes[1], "same seed -> same roll, same offer")
	var roll: Dictionary = outcomes[0]
	assert_eq(bool(roll["offered"]), float(roll["roll"]) < float(roll["chance"]))
	assert_true(bool(roll["subdued"]))


func test_subdue_raises_the_offer_rate() -> void:
	var r := _rules()
	var plain := 0
	var subdued := 0
	for i in 400:
		var a := RandomNumberGenerator.new()
		a.seed = 1000 + i
		var b := RandomNumberGenerator.new()
		b.seed = 1000 + i
		if bool(r.roll_join(a, false)["offered"]):
			plain += 1
		if bool(r.roll_join(b, true)["offered"]):
			subdued += 1
	assert_gt(subdued, plain, "subdued units offer more often (%d vs %d of 400)" % [subdued, plain])


func test_certain_and_impossible_offers_never_draw() -> void:
	var r := _rules()
	r.befriend_base_chance = 0.0
	r.befriend_subdue_bonus = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var before := rng.state
	assert_false(bool(r.roll_join(rng, true)["offered"]))
	assert_eq(rng.state, before, "a 0 chance does not advance the stream")
	r.befriend_base_chance = 1.0
	assert_true(bool(r.roll_join(rng, false)["offered"]))
	assert_eq(rng.state, before, "nor does a certainty")


func test_flee_chance_and_bench_are_data() -> void:
	var r := _rules()
	assert_almost_eq(r.flee_chance(10, 10, 0), r.flee_base, 0.0001)
	assert_gt(r.flee_chance(14, 8, 0), r.flee_chance(8, 14, 0))
	assert_gte(r.flee_chance(1, 99, 0), r.flee_min, "never below the floor")
	assert_eq(r.bench_size(), 0, "M1 is strict 1v1")
	r.party_size = 3
	assert_eq(r.bench_size(), 2, "M2 knob: lead + 2 bench")


func test_request_round_trips_and_rejects_unknown_ids() -> void:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight", 0)
	req.kind = DuelRequest.KIND_WILD
	req.seed = 99
	var back := DuelRequest.from_dict(req.to_dict())
	assert_true(bool(back["success"]), str(back["reason"]))
	assert_eq((back["request"] as DuelRequest).to_dict(), req.to_dict(), "lossless round trip")

	var bad := req.to_dict()
	bad["foe_party"] = [{"character_id": "res://evil.tres"}]
	var r := DuelRequest.from_dict(bad)
	assert_false(bool(r["success"]), "an unknown character id is refused")
	assert_string_contains(String(r["reason"]), "unknown_character")

	var bad_stage := req.to_dict()
	bad_stage["stage_id"] = "volcano_of_doom"
	assert_false(bool(DuelRequest.from_dict(bad_stage)["success"]))
	var bad_seed := req.to_dict()
	bad_seed["seed"] = "1234"
	assert_false(bool(DuelRequest.from_dict(bad_seed)["success"]), "types are checked")
	assert_false(bool(DuelRequest.from_dict("nope")["success"]))


func test_request_from_battle_request_shape() -> void:
	var br := {
		"kind": "duel", "encounter_id": "mossway.grass.petalfang", "source": "wild", "seed": 5,
		"party": [{"member_id": "m1", "character_id": "vineweave", "current_hp": 40, "item_id": ""}],
		"opponent": {"name": "", "team": [{"character_id": "petalfang", "strength": 1.0}]},
		"backdrop": {"tile_id": "tall_grass", "weather": "rain"},
		"rules": {"can_flee": true, "can_befriend": true},
	}
	var res := DuelRequest.from_battle_request(br)
	assert_true(bool(res["success"]), str(res["reason"]))
	var req: DuelRequest = res["request"]
	assert_true(req.is_wild())
	assert_eq(req.origin, DuelRequest.ORIGIN_STORY)
	assert_eq(req.player_party[0].current_hp, 40)
	assert_eq(req.resolved_station_tile_id(), &"tall_grass")
	assert_eq(req.weather_id, &"rain")
	assert_eq(req.encounter_id, "mossway.grass.petalfang")
