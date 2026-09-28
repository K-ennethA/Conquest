extends GutTest

# The command-log vocabulary on NetProtocol: typed builders, per-command validation, and the
# resolution stamp (seq + rng seed + protocol version).
#
# MERGED CORE: the command-log names (MOVE_UNIT / CAST_MOVE / WAIT_UNIT, KEY_UNIT_ID ...) are
# aliases of the ONE network vocabulary (MOVE / USE_MOVE / WAIT), so a recorded command and a
# network action are the same dictionary. Unit ids are NetUnitIds strings ("<slot>:<n>") and
# cells travel as [col, row, floor] int arrays (an in-process Vector3i / Vector2i is also
# accepted by the validators). Assertions that pinned the old int ids / live-Vector3i payloads
# were updated to the merged shape; what each test proves is unchanged.

# --- builders round-trip ---------------------------------------------------

func test_cast_move_builder_roundtrip():
	var c := NetProtocol.make_cast_move("0:7", 2, Vector3i(3, 4, 0), 0)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.CAST_MOVE, "type")
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.USE_MOVE, "CAST_MOVE is the network USE_MOVE")
	assert_eq(c[NetProtocol.KEY_ACTOR], 0, "actor preserved")
	assert_eq(c[NetProtocol.KEY_SEQ], 0, "unresolved envelope carries seq 0")
	var d = c[NetProtocol.KEY_DATA]
	assert_eq(d[NetProtocol.KEY_UNIT_ID], "0:7", "unit id")
	assert_eq(d[NetProtocol.KEY_MOVE_SLOT], 2, "move slot")
	assert_eq(NetProtocol.cell_from_wire(d[NetProtocol.KEY_AIM_CELL]), Vector3i(3, 4, 0), "aim cell")
	assert_true(NetProtocol.is_command_well_formed(c), "a built cast is well-formed")

func test_move_unit_builder_roundtrip():
	var c := NetProtocol.make_move_unit("1:5", Vector3i(8, 1, 2), 1)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.MOVE_UNIT, "type")
	var d = c[NetProtocol.KEY_DATA]
	assert_eq(d[NetProtocol.KEY_UNIT_ID], "1:5", "unit id")
	assert_eq(d[NetProtocol.KEY_DEST_CELL], [8, 1, 2], "dest cell rides as [col, row, floor]")
	assert_eq(NetProtocol.cell_from_wire(d[NetProtocol.KEY_DEST_CELL]), Vector3i(8, 1, 2), "and the floor survives")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

func test_wait_unit_builder_roundtrip():
	var c := NetProtocol.make_wait_unit("0:9", 0)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.WAIT_UNIT, "type")
	assert_eq(c[NetProtocol.KEY_DATA][NetProtocol.KEY_UNIT_ID], "0:9", "unit id")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

func test_end_turn_builder_roundtrip():
	var c := NetProtocol.make_end_turn(1, 1)
	assert_eq(c[NetProtocol.KEY_TYPE], NetProtocol.Action.END_TURN, "type")
	assert_eq(c[NetProtocol.KEY_DATA][NetProtocol.KEY_PLAYER_ID], 1, "player id")
	assert_true(NetProtocol.is_command_well_formed(c), "well-formed")

func test_in_process_cells_are_accepted_too():
	# Replay decoding / tests hand a live Vector3i (or a legacy Vector2i) straight in.
	var c := NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {
		NetProtocol.KEY_UNIT_ID: "0:1", NetProtocol.KEY_DEST_CELL: Vector3i(2, 3, 1),
	})
	assert_true(NetProtocol.is_command_well_formed(c), "a Vector3i cell is well-formed")
	c[NetProtocol.KEY_DATA][NetProtocol.KEY_DEST_CELL] = Vector2i(2, 3)
	assert_true(NetProtocol.is_command_well_formed(c), "a legacy Vector2i cell reads as floor 0")

# --- malformed commands rejected -------------------------------------------

func test_missing_required_key_rejected():
	var bad := NetProtocol.make_action(NetProtocol.Action.CAST_MOVE, {
		NetProtocol.KEY_UNIT_ID: "0:1", NetProtocol.KEY_MOVE_SLOT: 0,
	})   # no aim cell
	assert_false(NetProtocol.is_command_well_formed(bad), "a cast without an aim cell is rejected")

func test_wrong_type_rejected():
	var bad := NetProtocol.make_action(NetProtocol.Action.CAST_MOVE, {
		NetProtocol.KEY_UNIT_ID: 7, NetProtocol.KEY_MOVE_SLOT: 0, NetProtocol.KEY_AIM_CELL: Vector3i.ZERO,
	})
	assert_false(NetProtocol.is_command_well_formed(bad), "an int unit id (the retired registry id) is rejected")

	var bad2 := NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {
		NetProtocol.KEY_UNIT_ID: "0:1", NetProtocol.KEY_DEST_CELL: [8],
	})
	assert_false(NetProtocol.is_command_well_formed(bad2), "a one-component cell is rejected")

	var bad3 := NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {
		NetProtocol.KEY_UNIT_ID: "0:1", NetProtocol.KEY_DEST_CELL: [8.5, 1],
	})
	assert_false(NetProtocol.is_command_well_formed(bad3), "a float cell is rejected")

func test_non_dictionary_rejected():
	assert_false(NetProtocol.is_command_well_formed("nope"), "a string is not a command")
	assert_false(NetProtocol.is_command_well_formed(null), "null is not a command")
	assert_false(NetProtocol.is_command_well_formed(42), "an int is not a command")

func test_one_check_for_both_names():
	var a := NetProtocol.make_end_turn(0, 0)
	assert_true(NetProtocol.is_well_formed(a), "the network check accepts a command-log command")
	assert_eq(NetProtocol.is_well_formed(a), NetProtocol.is_command_well_formed(a), "they are one check")

# --- resolution stamp ------------------------------------------------------

func test_stamp_resolution_marks_a_command_resolved():
	var c := NetProtocol.make_cast_move("0:1", 0, Vector3i.ZERO, 0)
	assert_false(NetProtocol.is_resolved(c), "unstamped commands are not resolved")

	NetProtocol.stamp_resolution(c, 5, 987654)
	assert_eq(c[NetProtocol.KEY_SEQ], 5, "seq stamped")
	assert_eq(c[NetProtocol.KEY_RNG_SEED], 987654, "rng seed stamped")
	assert_eq(c[NetProtocol.KEY_RNG], 987654, "under the network key (KEY_RNG_SEED is its alias)")
	assert_eq(c[NetProtocol.KEY_PV], NetProtocol.PROTOCOL_VERSION, "protocol version stamped")
	assert_true(NetProtocol.is_resolved(c), "now it is resolved")

func test_is_resolved_requires_positive_seq():
	var c := NetProtocol.make_wait_unit("0:1", 0)
	NetProtocol.stamp_resolution(c, 0, 123)
	assert_false(NetProtocol.is_resolved(c), "seq 0 is the unresolved sentinel, never a resolved order")

func test_is_resolved_requires_matching_protocol_version():
	var c := NetProtocol.make_cast_move("0:1", 0, Vector3i.ZERO, 0)
	NetProtocol.stamp_resolution(c, 1, 1)
	c[NetProtocol.KEY_PV] = NetProtocol.PROTOCOL_VERSION + 999
	assert_false(NetProtocol.is_resolved(c), "a foreign protocol version is refused")

func test_stamp_excludes_wall_clock_time():
	# Nothing gameplay-affecting may depend on real time: a resolved command carries
	# exactly seq/rng/pv and no timestamp key.
	var c := NetProtocol.make_cast_move("0:1", 0, Vector3i.ZERO, 0)
	NetProtocol.stamp_resolution(c, 2, 42)
	for k in c.keys():
		assert_false(String(k).to_lower().contains("time"), "no time-derived key on a command: %s" % str(k))
