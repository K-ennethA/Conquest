extends GutTest

## The USE_ITEM command (protocol 3, docs/design/DECISIONS.md #28): its shape, the protocol
## bump, and that a replay log carries it through encode / decode unchanged (a duel item use
## is part of the recorded command list like any move).


func test_use_item_is_a_well_formed_command() -> void:
	var c: Dictionary = NetProtocol.use_item("0:1", "mossleaf_tonic")
	assert_eq(int(c[NetProtocol.KEY_TYPE]), NetProtocol.Action.USE_ITEM, "its own action type")
	assert_true(NetProtocol.is_well_formed(c), "well-formed")
	assert_eq(String(c[NetProtocol.KEY_DATA][NetProtocol.K_TARGET]), "0:1", "the target defaults to the user")
	assert_eq(NetProtocol.type_name(NetProtocol.Action.USE_ITEM), "USE_ITEM", "named")
	assert_eq(NetProtocol.describe_action(c), "Item", "and described")


func test_a_malformed_use_item_is_rejected() -> void:
	var no_item: Dictionary = NetProtocol.make_action(NetProtocol.Action.USE_ITEM, {NetProtocol.K_UNIT: "0:1",
		NetProtocol.K_TARGET: "0:1"})
	assert_false(NetProtocol.is_well_formed(no_item), "no item id")
	var no_target: Dictionary = NetProtocol.make_action(NetProtocol.Action.USE_ITEM, {NetProtocol.K_UNIT: "0:1",
		NetProtocol.K_ITEM: "mossleaf_tonic"})
	assert_false(NetProtocol.is_well_formed(no_target), "no target")
	assert_false(NetProtocol.is_well_formed({"type": NetProtocol.Action.ATTACK_UNIT, "data": {"unit_id": "0:1"}}),
		"the reserved id inside the range is still never well-formed")


func test_the_protocol_version_was_bumped_for_the_new_command() -> void:
	assert_gte(NetProtocol.PROTOCOL_VERSION, 3, "protocol 3 = USE_ITEM (peers / replays on 2 refuse it)")
	assert_gte(NetProtocol.PROTOCOL_VERSION, 4, "protocol 4 = lobby modes + the online duel config")
	assert_eq(NetProtocol.PROTOCOL_VERSION, 5, "protocol 5 = party duels (SWITCH, duel_format / duel_teams)")


func test_a_replay_log_round_trips_use_item() -> void:
	var c: Dictionary = NetProtocol.stamp_resolution(NetProtocol.use_item("0:1", "mossleaf_tonic", "0:1"), 7, 123456789)
	var enc: Dictionary = ReplayLog.encode_command(c)
	assert_false(enc.is_empty(), "USE_ITEM is an appliable replay command")
	var back: Dictionary = ReplayLog.decode_command(JSON.parse_string(JSON.stringify(enc)))
	assert_false(back.is_empty(), "and decodes")
	assert_eq(String(back[NetProtocol.KEY_DATA][NetProtocol.K_ITEM]), "mossleaf_tonic", "the item")
	assert_eq(String(back[NetProtocol.KEY_DATA][NetProtocol.K_TARGET]), "0:1", "the target")
	assert_eq(int(back[NetProtocol.KEY_SEQ]), 7, "the seq")
	assert_eq(int(back[NetProtocol.KEY_RNG]), 123456789, "the per-action seed")
	var bad: Dictionary = enc.duplicate(true)
	(bad[NetProtocol.KEY_DATA] as Dictionary).erase(NetProtocol.K_ITEM)
	assert_true(ReplayLog.decode_command(bad).is_empty(), "a USE_ITEM with no item is refused at the gate")
