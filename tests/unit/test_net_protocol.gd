extends GutTest

# Unit tests for NetProtocol — the wire format shared by client and server.

func test_make_action_has_required_keys():
	var a = NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, {"unit_id": 3})
	assert_true(a.has(NetProtocol.KEY_TYPE), "action has type")
	assert_true(a.has(NetProtocol.KEY_DATA), "action has data")
	assert_true(a.has(NetProtocol.KEY_ACTOR), "action has actor")
	assert_true(a.has(NetProtocol.KEY_SEQ), "action has seq")
	assert_eq(a[NetProtocol.KEY_TYPE], NetProtocol.Action.MOVE_UNIT, "type preserved")
	assert_eq(a[NetProtocol.KEY_SEQ], 0, "client seq starts at 0")

func test_make_action_deep_copies_data():
	var payload = {"nested": {"x": 1}}
	var a = NetProtocol.make_action(NetProtocol.Action.MOVE_UNIT, payload)
	payload["nested"]["x"] = 999
	assert_eq(a[NetProtocol.KEY_DATA]["nested"]["x"], 1, "data was deep-copied, not aliased")

func test_well_formed_accepts_valid_action():
	var a = NetProtocol.make_action(NetProtocol.Action.END_TURN)
	assert_true(NetProtocol.is_well_formed(a), "canonical action is well-formed")

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

func test_well_formed_rejects_bad_data_payload():
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.WAIT_UNIT, "data": "nope"}),
		"non-dictionary data rejected")
