extends GutTest

# Unit tests for NetProtocol — the wire format shared by client and host.

func test_make_action_has_required_keys():
	var a = NetProtocol.make_action(NetProtocol.Action.WAIT, {"unit_id": "0:3"})
	assert_true(a.has(NetProtocol.KEY_TYPE), "action has type")
	assert_true(a.has(NetProtocol.KEY_DATA), "action has data")
	assert_true(a.has(NetProtocol.KEY_ACTOR), "action has actor")
	assert_true(a.has(NetProtocol.KEY_SEQ), "action has seq")
	assert_eq(a[NetProtocol.KEY_TYPE], NetProtocol.Action.WAIT, "type preserved")
	assert_eq(a[NetProtocol.KEY_SEQ], 0, "client seq starts at 0")

func test_make_action_deep_copies_data():
	var payload = {"unit_id": "0:0", "nested": {"x": 1}}
	var a = NetProtocol.make_action(NetProtocol.Action.WAIT, payload)
	payload["nested"]["x"] = 999
	assert_eq(a[NetProtocol.KEY_DATA]["nested"]["x"], 1, "data was deep-copied, not aliased")

func test_builders_are_well_formed():
	assert_true(NetProtocol.is_well_formed(NetProtocol.move("0:1", Vector3i(2, 3, 0))), "move")
	assert_true(NetProtocol.is_well_formed(NetProtocol.use_move("0:1", 2, Vector3i(2, 3, 0))), "use_move")
	assert_true(NetProtocol.is_well_formed(NetProtocol.wait("1:0")), "wait")
	assert_true(NetProtocol.is_well_formed(NetProtocol.end_turn()), "end_turn")

func test_well_formed_rejects_non_dictionary():
	assert_false(NetProtocol.is_well_formed("hello"), "string rejected")
	assert_false(NetProtocol.is_well_formed(42), "int rejected")
	assert_false(NetProtocol.is_well_formed(null), "null rejected")

func test_well_formed_rejects_missing_or_bad_type():
	assert_false(NetProtocol.is_well_formed({"data": {}}), "missing type rejected")
	assert_false(NetProtocol.is_well_formed({"type": "move", "data": {}}), "string type rejected")

func test_well_formed_rejects_out_of_range_type():
	assert_false(NetProtocol.is_well_formed({"type": -1, "data": {}}), "negative type rejected")
	assert_false(NetProtocol.is_well_formed({"type": 9999, "data": {}}), "too-large type rejected")

func test_well_formed_rejects_bad_payloads():
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.WAIT, "data": "nope"}),
		"non-dictionary data rejected")
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.WAIT, "data": {}}),
		"wait without unit rejected")
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.MOVE, "data": {"unit_id": "0:0", "to": [1]}}),
		"one-component cell rejected")
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.MOVE, "data": {"unit_id": "0:0", "to": [1.5, 2]}}),
		"float cell rejected")
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.USE_MOVE, "data": {"unit_id": "0:0", "slot": "1", "aim": [1, 2]}}),
		"string slot rejected")

func test_cell_round_trip_is_generic():
	assert_eq(NetProtocol.cell_to_wire(Vector3i(3, 4, 1)), [3, 4, 1], "Vector3i -> [col, row, floor]")
	assert_eq(NetProtocol.cell_to_wire(Vector2i(3, 4)), [3, 4, 0], "legacy Vector2i lifts to floor 0")
	assert_eq(NetProtocol.cell_from_wire([3, 4, 1]), Vector3i(3, 4, 1), "floor survives the wire")
	assert_eq(NetProtocol.cell_from_wire([3, 4]), Vector3i(3, 4, 0), "missing floor reads as ground")
	assert_eq(NetProtocol.cell_from_wire("bad"), Cells.INVALID, "malformed -> fallback")
	assert_true(NetProtocol.is_well_formed(NetProtocol.move("0:0", Vector3i(1, 2, 1))), "upper-floor move is well-formed")
