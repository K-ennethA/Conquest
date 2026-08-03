extends GutTest

## Unit tests for [ReplayLog] -- the battle-replay FORMAT and its codec.
##
## Coverage:
##  - Command encode/decode is a lossless round-trip in the NetProtocol vocabulary, and
##    Vector2i cells survive the JSON flattening.
##  - The vocabulary gate: only APPLIABLE_TYPES pass; ATTACK_UNIT (no apply branch) does not.
##  - The strict importer refuses hostile / malformed input QUIETLY (garbage JSON, non-object
##    JSON, wrong format_version, wrong protocol_version, unknown command types, oversized
##    lists and strings) -- every rejection is a returned value, never an engine error.
##  - The state checksum is deterministic, PERMUTATION-INVARIANT (the whole point) and
##    sensitive to every field it hashes.
##  - The on-disk container round-trips, and a tampered / truncated / mis-magicked one is
##    refused before the decompressor ever sees it.
##  - save/load/list/delete work against an INJECTED directory (never the player's real one).

const TEMP_DIR := "user://test_replay_log/"


func before_all() -> void:
	ReplayLog.set_replay_dir(TEMP_DIR)


func after_all() -> void:
	_purge_temp_dir()
	ReplayLog.set_replay_dir(ReplayLog.DEFAULT_REPLAY_DIR)


func before_each() -> void:
	_purge_temp_dir()


func _purge_temp_dir() -> void:
	var dir := DirAccess.open(TEMP_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_DIR.path_join(entry)))
		entry = dir.get_next()
	dir.list_dir_end()


# --- Helpers ----------------------------------------------------------------

func _a_cast() -> Dictionary:
	return NetProtocol.make_cast_move(7, 2, Vector2i(3, 4), 1)


func _a_log(entry_count: int = 3) -> Dictionary:
	var log: Dictionary = ReplayLog.make_log({
		"mode": ReplayLog.MODE_CHALLENGE,
		"map": { "path": "res://maps/forgotten_forest.tres", "name": "Forgotten Forest" },
		"participants": [
			{ "slot": 0, "name": "Player 1", "is_ai": false,
			  "squad": ["vineweave"], "items": ["ironband"], "skins": { "vineweave": "ashen" } },
			{ "slot": 1, "name": "Bot", "is_ai": true, "squad": ["blightcap"] },
		],
		"rng": { "match_seed": 123456789 },
		"turn_system": 1,
		"difficulty": 2,
		"challenge_id": "abcdef",
	})
	for i in entry_count:
		log["entries"].append(ReplayLog.make_entry(i, i % 2, NetProtocol.make_move_unit(i, Vector2i(i, i + 1), i % 2)))
		log["checksums"].append(ReplayLog.make_checksum(i, ReplayLog.to_hex64(i * 977)))
	log["outcome"] = ReplayLog.make_outcome(ReplayLog.RESULT_VICTORY, 0, entry_count)
	return log


func _rows(ids: Array, hp: int = 10) -> Array:
	var out: Array = []
	for id in ids:
		out.append({ "id": int(id), "cell": Vector2i(int(id), int(id) * 2), "hp": hp })
	return out


# --- Command codec ----------------------------------------------------------

func test_cast_command_round_trips_losslessly() -> void:
	var live := _a_cast()
	var decoded := ReplayLog.decode_command(ReplayLog.encode_command(live))
	assert_false(decoded.is_empty(), "a well-formed CAST_MOVE survives the round trip")
	assert_eq(int(decoded[NetProtocol.KEY_TYPE]), int(NetProtocol.Action.CAST_MOVE), "type preserved")
	assert_eq(int(decoded[NetProtocol.KEY_ACTOR]), 1, "actor preserved")
	var data: Dictionary = decoded[NetProtocol.KEY_DATA]
	assert_eq(int(data[NetProtocol.KEY_UNIT_ID]), 7, "unit id preserved")
	assert_eq(int(data[NetProtocol.KEY_MOVE_SLOT]), 2, "move slot preserved")
	assert_eq(data[NetProtocol.KEY_AIM_CELL], Vector2i(3, 4), "aim cell comes back a Vector2i")


func test_every_appliable_type_round_trips() -> void:
	var commands: Array = [
		NetProtocol.make_move_unit(1, Vector2i(5, 6), 0),
		NetProtocol.make_wait_unit(2, 0),
		NetProtocol.make_end_turn(1, 1),
		NetProtocol.make_cast_move(3, 0, Vector2i(-1, 9), 1),
	]
	for cmd in commands:
		var decoded := ReplayLog.decode_command(ReplayLog.encode_command(cmd))
		assert_false(decoded.is_empty(), "type %d round-trips" % int(cmd[NetProtocol.KEY_TYPE]))
		assert_eq(int(decoded[NetProtocol.KEY_TYPE]), int(cmd[NetProtocol.KEY_TYPE]), "type preserved")


func test_encoded_command_is_json_safe() -> void:
	# The whole reason cells are flattened: the encoded form has to survive JSON.
	var encoded := ReplayLog.encode_command(_a_cast())
	var text := JSON.stringify(encoded)
	assert_ne(text, "", "the encoded command stringifies")
	var reparsed := ReplayLog.parse_text(text)
	assert_false(ReplayLog.decode_command(reparsed).is_empty(), "and decodes after a JSON trip")


func test_attack_unit_is_outside_the_replayable_vocabulary() -> void:
	# ATTACK_UNIT exists in the enum but has no apply branch, so it can never be re-simulated.
	var cmd := NetProtocol.make_action(NetProtocol.Action.ATTACK_UNIT, { NetProtocol.KEY_UNIT_ID: 1 }, 0)
	assert_true(ReplayLog.encode_command(cmd).is_empty(), "ATTACK_UNIT is refused on encode")
	assert_true(ReplayLog.decode_command(cmd).is_empty(), "and on decode")


func test_malformed_commands_decode_to_empty() -> void:
	assert_true(ReplayLog.decode_command(null).is_empty(), "null is not a command")
	assert_true(ReplayLog.decode_command("not a dict").is_empty(), "a string is not a command")
	assert_true(ReplayLog.decode_command({}).is_empty(), "an empty dict is not a command")
	assert_true(ReplayLog.decode_command({ NetProtocol.KEY_TYPE: "cast" }).is_empty(),
		"a non-numeric type is refused")
	assert_true(ReplayLog.decode_command({ NetProtocol.KEY_TYPE: 9999 }).is_empty(),
		"an out-of-vocabulary type is refused")
	# MOVE_UNIT with no dest_cell: required field missing.
	assert_true(ReplayLog.decode_command({
		NetProtocol.KEY_TYPE: NetProtocol.Action.MOVE_UNIT,
		NetProtocol.KEY_DATA: { NetProtocol.KEY_UNIT_ID: 1 },
	}).is_empty(), "a MOVE_UNIT missing its dest_cell is refused")


func test_decode_cell_tolerates_junk() -> void:
	assert_eq(ReplayLog.decode_cell([2, 3]), Vector2i(2, 3), "the flattened form decodes")
	assert_eq(ReplayLog.decode_cell(Vector2i(4, 5)), Vector2i(4, 5), "a live Vector2i passes through")
	assert_eq(ReplayLog.decode_cell("nope", Vector2i(9, 9)), Vector2i(9, 9), "junk reads as the fallback")
	assert_eq(ReplayLog.decode_cell([1], Vector2i(9, 9)), Vector2i(9, 9), "a short array reads as the fallback")
	assert_eq(ReplayLog.decode_cell(["a", "b"], Vector2i(9, 9)), Vector2i(9, 9), "non-numbers read as the fallback")


# --- The strict importer ----------------------------------------------------

func test_validate_round_trips_a_real_log() -> void:
	var log := _a_log(4)
	var out := ReplayLog.validate(ReplayLog.parse_text(ReplayLog.to_json(log)))
	assert_false(out.is_empty(), "a log we wrote validates")
	assert_eq(int(out["format_version"]), ReplayLog.FORMAT_VERSION, "format version preserved")
	assert_eq(String(out["mode"]), ReplayLog.MODE_CHALLENGE, "mode preserved")
	assert_eq((out["entries"] as Array).size(), 4, "all entries survive")
	assert_eq((out["checksums"] as Array).size(), 4, "all checksums survive")
	assert_eq((out["participants"] as Array).size(), 2, "both participants survive")
	assert_eq(int((out["rng"] as Dictionary)["match_seed"]), 123456789, "the match seed survives")
	assert_eq(String((out["outcome"] as Dictionary)["result"]), ReplayLog.RESULT_VICTORY, "outcome preserved")


func test_validate_refuses_junk_quietly() -> void:
	# Every one of these is an EXPECTED input. None may reach the engine log (convention #1);
	# GUT fails this test if any of them does.
	assert_true(ReplayLog.validate(null).is_empty(), "null is not a replay")
	assert_true(ReplayLog.validate("garbage").is_empty(), "a string is not a replay")
	assert_true(ReplayLog.validate([1, 2, 3]).is_empty(), "an array is not a replay")
	assert_true(ReplayLog.validate({}).is_empty(), "an empty dict is not a replay")
	assert_true(ReplayLog.parse_text("{ not json ]").is_empty(), "garbage text parses to nothing")
	assert_true(ReplayLog.parse_text("[1,2,3]").is_empty(), "valid JSON that is not an object is refused")
	assert_true(ReplayLog.parse_text("").is_empty(), "empty text parses to nothing")


func test_validate_refuses_a_wrong_format_version() -> void:
	var log := _a_log(1)
	log["format_version"] = ReplayLog.FORMAT_VERSION + 1
	assert_true(ReplayLog.validate(log).is_empty(), "a future format_version is hard-refused")
	log["format_version"] = 0
	assert_true(ReplayLog.validate(log).is_empty(), "a missing/zero format_version is hard-refused")


func test_validate_refuses_a_wrong_protocol_version() -> void:
	var log := _a_log(1)
	log["protocol_version"] = NetProtocol.PROTOCOL_VERSION + 1
	assert_true(ReplayLog.validate(log).is_empty(),
		"a file written against another command vocabulary cannot be re-simulated")


func test_validate_refuses_a_body_that_is_not_a_list() -> void:
	var log := _a_log(1)
	log["entries"] = { "nope": true }
	assert_true(ReplayLog.validate(log).is_empty(), "a non-array body is hard-refused")


func test_validate_drops_unknown_commands_and_junk_entries() -> void:
	var log := _a_log(2)
	log["entries"].append({ "turn": 0, "actor_slot": 0, "cmd": { NetProtocol.KEY_TYPE: 9999 } })
	log["entries"].append({ "turn": 0, "actor_slot": 0, "cmd": "not a command" })
	log["entries"].append("not even an entry")
	log["checksums"].append({ "turn": "x", "hash": 12 })
	var out := ReplayLog.validate(log)
	assert_false(out.is_empty(), "the file still validates -- bad ENTRIES are dropped, not fatal")
	assert_eq((out["entries"] as Array).size(), 2, "only the two real entries survive")
	assert_eq((out["checksums"] as Array).size(), 2, "the malformed checksum is dropped")


func test_validate_drops_unknown_top_level_keys() -> void:
	var log := _a_log(1)
	log["evil_payload"] = { "script": "res://anything.gd" }
	var out := ReplayLog.validate(log)
	assert_false(out.has("evil_payload"), "unknown keys are dropped, never carried through")


func test_validate_caps_oversized_input() -> void:
	var log := _a_log(0)
	var cmd := NetProtocol.make_wait_unit(1, 0)
	for i in (ReplayLog.MAX_ENTRIES + 50):
		log["entries"].append(ReplayLog.make_entry(0, 0, cmd))
	var many_participants: Array = []
	for i in (ReplayLog.MAX_PARTICIPANTS + 10):
		many_participants.append({ "slot": i, "name": "P%d" % i })
	log["participants"] = many_participants
	var out := ReplayLog.validate(log)
	assert_eq((out["entries"] as Array).size(), ReplayLog.MAX_ENTRIES, "the entry cap holds")
	assert_eq((out["participants"] as Array).size(), ReplayLog.MAX_PARTICIPANTS, "the participant cap holds")


func test_validate_clips_oversized_strings() -> void:
	var log := _a_log(0)
	log["challenge_id"] = "z".repeat(ReplayLog.MAX_STRING * 4)
	log["map"] = { "path": "p".repeat(ReplayLog.MAX_PATH * 4), "name": "n".repeat(ReplayLog.MAX_STRING * 4) }
	var out := ReplayLog.validate(log)
	assert_eq(String(out["challenge_id"]).length(), ReplayLog.MAX_STRING, "ids are clipped")
	assert_eq(String((out["map"] as Dictionary)["path"]).length(), ReplayLog.MAX_PATH, "paths are clipped")
	assert_eq(String((out["map"] as Dictionary)["name"]).length(), ReplayLog.MAX_STRING, "names are clipped")


func test_validate_normalises_an_unknown_mode() -> void:
	# A mode is a LABEL, not a simulation input, so an unknown one is normalised rather than
	# rejecting an otherwise replayable file.
	var log := _a_log(1)
	log["mode"] = "definitely_not_a_mode"
	var out := ReplayLog.validate(log)
	assert_eq(String(out["mode"]), ReplayLog.MODE_SKIRMISH, "an unknown mode falls back to skirmish")


func test_validate_caps_an_embedded_map_payload() -> void:
	var payload: Dictionary = {}
	for i in (ReplayLog.MAX_PAYLOAD_KEYS + 20):
		payload["k%d" % i] = i
	var log := _a_log(0)
	log["map"] = { "path": "user://x.json", "custom": true, "payload": payload }
	var out := ReplayLog.validate(log)
	assert_eq((((out["map"] as Dictionary)["payload"]) as Dictionary).size(), 0,
		"an oversized embedded payload is dropped entirely")


func test_matches_this_build_is_the_soft_gate() -> void:
	var log := ReplayLog.make_log({})
	assert_true(ReplayLog.matches_this_build(log), "a freshly made log matches this build")
	log["game_version"] = "some-other-build"
	assert_false(ReplayLog.matches_this_build(log), "a foreign game_version does not")


# --- The state checksum -----------------------------------------------------

func test_checksum_is_deterministic() -> void:
	var a := ReplayLog.state_checksum(_rows([1, 2, 3]))
	var b := ReplayLog.state_checksum(_rows([1, 2, 3]))
	assert_eq(a, b, "the same state hashes the same, twice")
	assert_eq(a.length(), 16, "a checksum is a fixed 16-char hex string")


func test_checksum_is_permutation_invariant() -> void:
	# THE point of the sort: scene order is not stable across peers, so the same board walked
	# in a different order must hash identically.
	var forward := ReplayLog.state_checksum(_rows([1, 2, 3, 4]))
	var reversed := ReplayLog.state_checksum(_rows([4, 3, 2, 1]))
	var shuffled := ReplayLog.state_checksum(_rows([3, 1, 4, 2]))
	assert_eq(forward, reversed, "reversed row order hashes identically")
	assert_eq(forward, shuffled, "shuffled row order hashes identically")


func test_checksum_is_sensitive_to_every_field() -> void:
	var base := ReplayLog.state_checksum([{ "id": 1, "cell": Vector2i(2, 3), "hp": 10 }])
	assert_ne(base, ReplayLog.state_checksum([{ "id": 2, "cell": Vector2i(2, 3), "hp": 10 }]), "id matters")
	assert_ne(base, ReplayLog.state_checksum([{ "id": 1, "cell": Vector2i(9, 3), "hp": 10 }]), "cell.x matters")
	assert_ne(base, ReplayLog.state_checksum([{ "id": 1, "cell": Vector2i(2, 9), "hp": 10 }]), "cell.y matters")
	assert_ne(base, ReplayLog.state_checksum([{ "id": 1, "cell": Vector2i(2, 3), "hp": 4 }]), "hp matters")
	assert_ne(base, ReplayLog.state_checksum(_rows([1, 2])), "unit COUNT matters")


func test_checksum_accepts_the_flattened_cell_form() -> void:
	# Rows may arrive from a decoded file (arrays) or from the live board (Vector2i).
	var live := ReplayLog.state_checksum([{ "id": 1, "cell": Vector2i(2, 3), "hp": 10 }])
	var flat := ReplayLog.state_checksum([{ "id": 1, "cell": [2, 3], "hp": 10 }])
	assert_eq(live, flat, "both cell spellings hash the same")


func test_checksum_skips_junk_rows() -> void:
	var clean := ReplayLog.state_checksum(_rows([1, 2]))
	var dirty_rows := _rows([1, 2])
	dirty_rows.append("not a row")
	dirty_rows.append(null)
	assert_eq(ReplayLog.state_checksum(dirty_rows), clean, "non-dictionary rows are skipped, not raised on")
	assert_eq(ReplayLog.state_checksum([]).length(), 16, "an empty board still hashes")


func test_to_hex64_handles_negative_values() -> void:
	# "%x" on a negative int prints a sign; the split-halves formatting must not.
	var hex := ReplayLog.to_hex64(-1)
	assert_eq(hex, "ffffffffffffffff", "-1 formats as the full bit pattern")
	assert_eq(ReplayLog.to_hex64(0), "0000000000000000", "0 is zero-padded to 16 chars")
	assert_false(ReplayLog.to_hex64(-123456789).contains("-"), "no sign ever appears")


# --- The on-disk container --------------------------------------------------

func test_container_round_trips() -> void:
	var log := _a_log(5)
	var bytes := ReplayLog.to_bytes(log)
	assert_gt(bytes.size(), ReplayLog.CONTAINER_HEADER_SIZE, "the container has a payload")
	var out := ReplayLog.from_bytes(bytes)
	assert_false(out.is_empty(), "the container decodes back to a valid log")
	assert_eq((out["entries"] as Array).size(), 5, "all entries survive the gzip round trip")


func test_container_refuses_tampering_quietly() -> void:
	var bytes := ReplayLog.to_bytes(_a_log(3))

	var bad_magic := bytes.duplicate()
	bad_magic.encode_u8(0, 0x58)  # "X"
	assert_true(ReplayLog.from_bytes(bad_magic).is_empty(), "bad magic is refused")

	var bad_version := bytes.duplicate()
	bad_version.encode_u32(4, ReplayLog.CONTAINER_VERSION + 7)
	assert_true(ReplayLog.from_bytes(bad_version).is_empty(), "a foreign container version is refused")

	# A flipped payload byte must be caught by the DIGEST, before the decompressor sees it.
	var corrupt := bytes.duplicate()
	corrupt.encode_u8(corrupt.size() - 1, (corrupt.decode_u8(corrupt.size() - 1) + 1) % 256)
	assert_true(ReplayLog.from_bytes(corrupt).is_empty(), "a corrupted payload is refused by the digest")

	var truncated := bytes.slice(0, bytes.size() - 8)
	assert_true(ReplayLog.from_bytes(truncated).is_empty(), "a truncated file is refused")

	assert_true(ReplayLog.from_bytes(PackedByteArray()).is_empty(), "empty bytes are refused")
	assert_true(ReplayLog.from_bytes(bytes.slice(0, 10)).is_empty(), "a stub shorter than the header is refused")


func test_container_refuses_a_decompression_bomb_size() -> void:
	var bytes := ReplayLog.to_bytes(_a_log(1))
	var bomb := bytes.duplicate()
	bomb.encode_u32(8, ReplayLog.MAX_DECOMPRESSED_BYTES + 1)
	assert_true(ReplayLog.from_bytes(bomb).is_empty(), "an absurd declared size is refused before inflation")
	var zero := bytes.duplicate()
	zero.encode_u32(8, 0)
	assert_true(ReplayLog.from_bytes(zero).is_empty(), "a zero declared size is refused")


# --- Files ------------------------------------------------------------------

func test_save_and_load_round_trip() -> void:
	var log := _a_log(6)
	var path := ReplayLog.save_to_file(log, "roundtrip")
	assert_ne(path, "", "the file is written")
	assert_true(path.ends_with(ReplayLog.FILE_EXTENSION), "the extension is appended")
	assert_true(FileAccess.file_exists(path), "the file exists on disk")
	var loaded := ReplayLog.load_from_file(path)
	assert_false(loaded.is_empty(), "it loads back")
	assert_eq((loaded["entries"] as Array).size(), 6, "with every entry")
	assert_eq(String(loaded["challenge_id"]), "abcdef", "and its header")


func test_load_refuses_missing_and_junk_files_quietly() -> void:
	assert_true(ReplayLog.load_from_file("").is_empty(), "a blank path loads nothing")
	assert_true(ReplayLog.load_from_file(TEMP_DIR.path_join("nope.cqrep")).is_empty(),
		"a missing file loads nothing")
	var junk_path := TEMP_DIR.path_join("junk" + ReplayLog.FILE_EXTENSION)
	var f := FileAccess.open(junk_path, FileAccess.WRITE)
	assert_not_null(f, "the temp dir is writable")
	f.store_string("this is definitely not a replay container, not even close, no sir")
	f.close()
	assert_true(ReplayLog.load_from_file(junk_path).is_empty(), "a junk file loads nothing")


func test_list_and_delete_replays() -> void:
	ReplayLog.save_to_file(_a_log(1), "alpha")
	ReplayLog.save_to_file(_a_log(1), "beta")
	var listed := ReplayLog.list_replays()
	assert_eq(listed.size(), 2, "both replays are listed")
	var names: Array = []
	for row in listed:
		names.append(String((row as Dictionary)["filename"]))
		assert_gt(int((row as Dictionary)["bytes"]), 0, "each listing reports a size")
	assert_true(names.has("alpha" + ReplayLog.FILE_EXTENSION), "alpha is listed")
	assert_true(names.has("beta" + ReplayLog.FILE_EXTENSION), "beta is listed")

	var target := String((listed[0] as Dictionary)["path"])
	assert_true(ReplayLog.delete_replay(target), "delete reports success")
	assert_eq(ReplayLog.list_replays().size(), 1, "and the file is gone")
	assert_true(ReplayLog.delete_replay(target), "deleting an already-gone file is a no-op success")


func test_suggest_filename_is_sanitised() -> void:
	var log := ReplayLog.make_log({
		"mode": ReplayLog.MODE_ARENA,
		"map": { "path": "res://maps/King's Crossing!.tres" },
	})
	var name := ReplayLog.suggest_filename(log, "2026 08 02")
	assert_true(name.begins_with("arena_"), "the mode leads")
	assert_true(name.ends_with(ReplayLog.FILE_EXTENSION), "the extension trails")
	for ch in ["'", "!", " ", "/", ":"]:
		assert_false(name.contains(ch), "'%s' is sanitised out of the filename" % ch)


func test_make_outcome_normalises_an_unknown_result() -> void:
	var out := ReplayLog.make_outcome("exploded", 3, -5)
	assert_eq(String(out["result"]), ReplayLog.RESULT_UNKNOWN, "an unknown result falls back to unknown")
	assert_eq(int(out["turns"]), 0, "a negative turn count clamps to zero")
	assert_eq(int(out["winner_slot"]), 3, "the winner slot is preserved")
