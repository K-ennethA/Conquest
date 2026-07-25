extends GutTest

# The command vocabulary added to NetProtocol: typed builders, strict per-command
# validation, and the authority's resolution stamp (seq + rng_seed + protocol version).

# --- builders round-trip ---------------------------------------------------

func test_cast_move_builder_roundtrip():
	var c := NetProtocol.make_cast_move(7, 2, Vector2i(3, 4), 0)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.CAST_MOVE, "type")
	assert_eq(c[NetProtocol.KEY_ACTOR], 0, "actor preserved")
	assert_eq(c[NetProtocol.KEY_SEQ], 0, "unresolved envelope carries seq 0")
	var d = c[NetProtocol.KEY_DATA]
	assert_eq(d[NetProtocol.KEY_UNIT_ID], 7, "unit id")
	assert_eq(d[NetProtocol.KEY_MOVE_SLOT], 2, "move slot")
	assert_eq(d[NetProtocol.KEY_AIM_CELL], Vector2i(3, 4), "aim cell")
	assert_true(NetProtocol.is_command_well_formed(c), "a built cast is well-formed")

func test_move_unit_builder_roundtrip():
	var c := NetProtocol.make_move_unit(5, Vector2i(8, 1), 1)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.MOVE_UNIT, "type")
	var d = c[NetProtocol.KEY_DATA]
	assert_eq(d[NetProtocol.KEY_UNIT_ID], 5, "unit id")
	assert_eq(d[NetProtocol.KEY_DEST_CELL], Vector2i(8, 1), "dest cell")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

func test_wait_unit_builder_roundtrip():
	var c := NetProtocol.make_wait_unit(9, 0)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.WAIT_UNIT, "type")
	assert_eq(c[NetProtocol.KEY_DATA][NetProtocol.KEY_UNIT_ID], 9, "unit id")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

func test_end_turn_builder_roundtrip():
	var c := NetProtocol.make_end_turn(1, 1)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.END_TURN, "type")
	assert_eq(c[NetProtocol.KEY_DATA][NetProtocol.KEY_PLAYER_ID], 1, "player id")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

# --- malformed commands rejected -------------------------------------------

func test_missing_required_key_rejected():
	var bad := NetProtocol.make_action(NetProtocol.Action.CAST_MOVE, {
		NetProtocol.KEY_UNIT_ID: 1, NetProtocol.KEY_MOVE_SLOT: 0,
	})   # no aim_cell
	assert_false(NetProtocol.is_command_well_formed(bad), "a cast without an aim cell is rejected")

func test_wrong_type_rejected():
	var bad := NetProtocol.make_action(NetProtocol.Action.CAST_MOVE, {
		NetProtocol.KEY_UNIT_ID: "seven", NetProtocol.KEY_MOVE_SLOT: 0, NetProtocol.KEY_AIM_CELL: Vector2i.ZERO,
	})
	assert_false(NetProtocol.is_command_well_formed(bad), "a string unit id is rejected")

	var bad2 := NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {
		NetProtocol.KEY_UNIT_ID: 1, NetProtocol.KEY_DEST_CELL: [8, 1],
	})
	assert_false(NetProtocol.is_command_well_formed(bad2), "an array where a Vector2i is required is rejected")

func test_non_dictionary_rejected():
	assert_false(NetProtocol.is_command_well_formed("nope"), "a string is not a command")
	assert_false(NetProtocol.is_command_well_formed(null), "null is not a command")
	assert_false(NetProtocol.is_command_well_formed(42), "an int is not a command")

func test_loose_is_well_formed_still_accepts_base_envelope():
	# Backward compatibility: the original loose check keeps working for existing paths.
	var a := NetProtocol.make_end_turn(0, 0)
	assert_true(NetProtocol.is_well_formed(a), "the loose envelope check still passes")

# --- resolution stamp ------------------------------------------------------

func test_stamp_resolution_marks_a_command_resolved():
	var c := NetProtocol.make_cast_move(1, 0, Vector2i.ZERO, 0)
	assert_false(NetProtocol.is_resolved(c), "unstamped commands are not resolved")

	NetProtocol.stamp_resolution(c, 5, 987654)
	assert_eq(c[NetProtocol.KEY_SEQ], 5, "seq stamped")
	assert_eq(c[NetProtocol.KEY_RNG_SEED], 987654, "rng seed stamped")
	assert_eq(c[NetProtocol.KEY_PV], NetProtocol.PROTOCOL_VERSION, "protocol version stamped")
	assert_true(NetProtocol.is_resolved(c), "now it is resolved")

func test_is_resolved_requires_positive_seq():
	var c := NetProtocol.make_wait_unit(1, 0)
	NetProtocol.stamp_resolution(c, 0, 123)
	assert_false(NetProtocol.is_resolved(c), "seq 0 is the unresolved sentinel, never a resolved order")

func test_is_resolved_requires_matching_protocol_version():
	var c := NetProtocol.make_cast_move(1, 0, Vector2i.ZERO, 0)
	NetProtocol.stamp_resolution(c, 1, 1)
	c[NetProtocol.KEY_PV] = NetProtocol.PROTOCOL_VERSION + 999
	assert_false(NetProtocol.is_resolved(c), "a foreign protocol version is refused")

func test_stamp_excludes_wall_clock_time():
	# Nothing gameplay-affecting may depend on real time: a resolved command carries
	# exactly seq/rng_seed/pv and no timestamp key.
	var c := NetProtocol.make_cast_move(1, 0, Vector2i.ZERO, 0)
	NetProtocol.stamp_resolution(c, 2, 42)
	for k in c.keys():
		assert_false(String(k).to_lower().contains("time"), "no time-derived key on a command: %s" % str(k))
