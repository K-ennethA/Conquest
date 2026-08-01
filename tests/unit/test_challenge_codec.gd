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
