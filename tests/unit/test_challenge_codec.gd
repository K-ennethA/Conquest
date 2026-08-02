extends GutTest

## Unit tests for [ChallengeCodec] -- the serverless challenge format + share codec.
##
## Coverage:
##  - encode/decode is a lossless round-trip.
##  - A tampered checksum is rejected by validate().
##  - An unsupported format_version is rejected.
##  - validate() catches: a missing defense, an oversized challenger squad, and a map
##    with an unknown tile id (via the catalog-strict MapResource validator).
##  - A 12x12 map's share code stays comfortably under ~4 KB.
##  - A v1 (pre-mode/par) code still decodes, validates and reads through the accessors
##    with sane defaults -- old share codes must keep working after the v2 bump.

# --- Helpers ----------------------------------------------------------------

## A real roster character id (the codec's strict map validation resolves ids against
## CharacterLibrary, so tests must use a genuine one).
func _a_character_id() -> String:
	var ids: Array = CharacterLibrary.all_ids()
	assert_gt(ids.size(), 0, "roster must have at least one character for these tests")
	return String(ids[0])


## Build an in-memory MapResource that passes the strict validator. When [param with_defense]
## the player-2 slot names a character (a real defense); otherwise it is an empty start slot
## (still a second player, so the map is valid, but there is nothing to defend).
func _make_map(with_defense: bool) -> MapResource:
	var res := MapResource.new()
	res.map_name = "Codec Test Map"
	res.author = "Tester"
	res.width = 5
	res.height = 5
	res.max_players = 2
	res.create_default_layout()  # 25 NORMAL tiles, empty tile_id -> pass strict

	var cid := _a_character_id()
	# Player 0: the challenger's start slot (given a character so the map has 2 players).
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	# Player 1: the defender (or an empty slot when we want "no defense").
	if with_defense:
		res.set_character_spawn_at_position(Vector2i(4, 4), 1, cid)
	else:
		res.set_spawn_point_at_position(Vector2i(4, 4), 1, MapResource.SPAWN_KIND_START, {})
	return res


func _make_challenge(with_defense: bool = true, squad: int = 4) -> Dictionary:
	return ChallengeCodec.build_challenge(
		_make_map(with_defense), "My Gauntlet", "Tester", "2026-08-01T00:00:00", {
			"challenger_squad_size": squad,
			"turn_system": 0,
			"ai_difficulty": 1,
		})


## Build a genuine v1-shaped challenge: the pre-v2 field set (no mode / survive_turns /
## par_turns), stamped at format_version 1 and re-signed. This is byte-for-byte what an old
## build wrote, which is what makes it a real back-compat fixture rather than a v2 blob with
## keys removed.
func _make_v1_challenge(squad: int = 4) -> Dictionary:
	var v2: Dictionary = _make_challenge(true, squad)
	var v1: Dictionary = {
		"format_version": 1,
		"name": String(v2.get("name", "")),
		"author": String(v2.get("author", "")),
		"created": String(v2.get("created", "")),
		"map": v2.get("map", {}),
		"rules": {
			"challenger_squad_size": squad,
			"turn_system": 0,
			"ai_difficulty": 1,
		},
	}
	v1["checksum"] = ChallengeCodec.content_hash(v1)
	return v1


func _has_error_containing(errors: Array, needle: String) -> bool:
	for e in errors:
		if String(e).to_lower().contains(needle.to_lower()):
			return true
	return false


# --- Tests ------------------------------------------------------------------

func test_encode_decode_round_trip() -> void:
	var challenge := _make_challenge()
	var code := ChallengeCodec.encode(challenge)
	assert_gt(code.length(), 0, "encode should produce a non-empty code")

	var decoded := ChallengeCodec.decode(code)
	assert_false(decoded.is_empty(), "decode should recover a dict")
	assert_eq(String(decoded.get("name", "")), "My Gauntlet")
	assert_eq(String(decoded.get("author", "")), "Tester")
	assert_eq(int(decoded.get("format_version", -1)), ChallengeCodec.FORMAT_VERSION)
	assert_eq(String(decoded.get("checksum", "")), String(challenge.get("checksum", "")))
	# The decoded challenge is still valid (checksum + map + defense all intact).
	assert_eq(ChallengeCodec.validate(decoded).size(), 0, "round-tripped challenge should validate clean")


func test_decode_garbage_returns_empty() -> void:
	assert_true(ChallengeCodec.decode("").is_empty(), "empty code -> empty dict")
	assert_true(ChallengeCodec.decode("!!!not base64!!!").is_empty(), "junk code -> empty dict")


func test_tampered_checksum_rejected() -> void:
	var challenge := _make_challenge()
	# A valid challenge validates clean...
	assert_eq(ChallengeCodec.validate(challenge).size(), 0)
	# ...but flipping any content without recomputing the checksum is caught.
	challenge["name"] = "Tampered Name"
	var errors := ChallengeCodec.validate(challenge)
	assert_true(_has_error_containing(errors, "checksum"), "tampered content must fail the checksum check")


func test_unknown_format_version_rejected() -> void:
	var challenge := _make_challenge()
	challenge["format_version"] = 999
	challenge["checksum"] = ChallengeCodec.content_hash(challenge)  # keep checksum honest
	var errors := ChallengeCodec.validate(challenge)
	assert_true(_has_error_containing(errors, "format_version"), "unsupported version must be rejected")


func test_missing_defense_rejected() -> void:
	var challenge := _make_challenge(false)
	assert_eq(ChallengeCodec.defense_count(challenge), 0, "no player-2+ character means no defense")
	var errors := ChallengeCodec.validate(challenge)
	assert_true(_has_error_containing(errors, "defender"), "a challenge with no defense must be rejected")


func test_oversized_squad_rejected() -> void:
	var challenge := _make_challenge()
	# build_challenge clamps to 1..6, so force an out-of-band value and re-sign it.
	challenge["rules"]["challenger_squad_size"] = 8
	challenge["checksum"] = ChallengeCodec.content_hash(challenge)
	var errors := ChallengeCodec.validate(challenge)
	assert_true(_has_error_containing(errors, "squad"), "an oversized squad size must be rejected")


func test_invalid_map_bad_tile_id_rejected() -> void:
	var challenge := _make_challenge()
	# Inject an unknown tile_id into the first tile; the catalog-strict validator must reject it.
	var tiles: Array = challenge["map"]["layout"]["tiles"]
	assert_gt(tiles.size(), 0)
	tiles[0]["tile_id"] = "definitely_not_a_real_tile_xyz"
	challenge["checksum"] = ChallengeCodec.content_hash(challenge)  # isolate the map error
	var errors := ChallengeCodec.validate(challenge)
	assert_true(_has_error_containing(errors, "map"), "an unknown tile id must fail map validation")


func test_share_code_of_12x12_stays_small() -> void:
	var res := MapResource.new()
	res.map_name = "Twelve"
	res.author = "Tester"
	res.width = 12
	res.height = 12
	res.max_players = 2
	res.create_default_layout()  # 144 tiles
	var cid := _a_character_id()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(11, 11), 1, cid)

	var challenge := ChallengeCodec.build_challenge(res, "Twelve", "Tester", "2026-08-01", {
		"challenger_squad_size": 4, "turn_system": 0, "ai_difficulty": 1,
	})
	assert_eq(ChallengeCodec.validate(challenge).size(), 0, "the 12x12 challenge should be valid")

	var code := ChallengeCodec.encode(challenge)
	assert_lt(code.length(), 4096, "a 12x12 share code should stay under ~4 KB (was %d)" % code.length())
	# And it must still round-trip.
	assert_false(ChallengeCodec.decode(code).is_empty(), "the compact code must still decode")


# --- v1 back-compat ---------------------------------------------------------

func test_v1_challenge_still_validates() -> void:
	# The v2 bump added rules.mode / survive_turns / par_turns AND hashes them into the
	# checksum -- but only for v2+ blobs, so a v1 code's own checksum must still verify.
	var v1 := _make_v1_challenge()
	var errors := ChallengeCodec.validate(v1)
	assert_eq(errors.size(), 0, "a v1 challenge must still validate clean: %s" % "; ".join(errors))


func test_v1_challenge_round_trips_through_a_share_code() -> void:
	var v1 := _make_v1_challenge()
	var decoded := ChallengeCodec.decode(ChallengeCodec.encode(v1))
	assert_false(decoded.is_empty(), "a v1 code must still decode")
	assert_eq(int(decoded.get("format_version", -1)), 1, "decoding must not silently upgrade it")
	assert_eq(ChallengeCodec.validate(decoded).size(), 0, "the decoded v1 challenge is still valid")


func test_v1_rules_read_through_the_accessors_with_defaults() -> void:
	var v1 := _make_v1_challenge()
	var rules: Dictionary = v1.get("rules", {})
	assert_false(rules.has("mode"), "the fixture must really lack the v2 fields")
	assert_false(rules.has("survive_turns"))
	assert_false(rules.has("par_turns"))

	assert_eq(ChallengeCodec.rules_mode(v1), ChallengeCodec.MODE_BREACH,
		"a v1 challenge plays as the original breach mode")
	assert_eq(ChallengeCodec.rules_survive_turns(v1), ChallengeCodec.DEFAULT_SURVIVE_TURNS)
	# Par is derived from the defense size, matching what build_challenge would have chosen.
	assert_eq(ChallengeCodec.rules_par_turns(v1),
		ChallengeCodec.default_par_for(ChallengeCodec.defense_count(v1)),
		"a v1 challenge's par derives from its defender count")


func test_an_unknown_mode_is_rejected() -> void:
	var challenge := _make_challenge()
	challenge["rules"]["mode"] = "sudden_death"
	challenge["checksum"] = ChallengeCodec.content_hash(challenge)
	assert_true(_has_error_containing(ChallengeCodec.validate(challenge), "mode"),
		"an unknown mode must be rejected")


func test_survive_rules_round_trip() -> void:
	var res := _make_map(true)
	var challenge := ChallengeCodec.build_challenge(res, "Hold", "Tester", "2026-08-01", {
		"challenger_squad_size": 3,
		"turn_system": 0,
		"ai_difficulty": 1,
		"mode": ChallengeCodec.MODE_SURVIVE,
		"survive_turns": 12,
		"par_turns": 9,
	})
	assert_eq(ChallengeCodec.validate(challenge).size(), 0)

	var decoded := ChallengeCodec.decode(ChallengeCodec.encode(challenge))
	assert_eq(ChallengeCodec.rules_mode(decoded), ChallengeCodec.MODE_SURVIVE)
	assert_eq(ChallengeCodec.rules_survive_turns(decoded), 12)
	assert_eq(ChallengeCodec.rules_par_turns(decoded), 9)


func test_out_of_band_rule_values_are_clamped_at_build_time() -> void:
	var res := _make_map(true)
	var challenge := ChallengeCodec.build_challenge(res, "Extreme", "Tester", "2026-08-01", {
		"challenger_squad_size": 4,
		"mode": ChallengeCodec.MODE_SURVIVE,
		"survive_turns": 999,
		"par_turns": 0,
	})
	assert_eq(ChallengeCodec.rules_survive_turns(challenge), ChallengeCodec.MAX_SURVIVE_TURNS)
	assert_eq(ChallengeCodec.rules_par_turns(challenge), ChallengeCodec.MIN_PAR_TURNS)
	assert_eq(ChallengeCodec.validate(challenge).size(), 0,
		"clamped values must land inside the validated band")


func test_an_unknown_mode_falls_back_to_breach_at_build_time() -> void:
	var res := _make_map(true)
	var challenge := ChallengeCodec.build_challenge(res, "Odd", "Tester", "2026-08-01", {
		"challenger_squad_size": 4,
		"mode": "nonsense",
	})
	assert_eq(ChallengeCodec.rules_mode(challenge), ChallengeCodec.MODE_BREACH)
	assert_eq(ChallengeCodec.validate(challenge).size(), 0)
