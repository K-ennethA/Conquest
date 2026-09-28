extends GutTest

## Lobby + connection lifecycle of NetSessionNode, host and clients running IN
## ONE PROCESS over real ENet on 127.0.0.1 (see net_test_harness.gd).

const H := preload("res://tests/integration/net_test_harness.gd")

var _host: Dictionary = {}
var _client: Dictionary = {}
var _client2: Dictionary = {}
var _port: int = 0


func before_each() -> void:
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")
	_client2 = {}


func after_each() -> void:
	H.free_peer(_client2)
	H.free_peer(_client)
	H.free_peer(_host)
	_client2 = {}
	await H.wait_frames(get_tree(), 2)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


## Host + one seated client.
func _connect_pair() -> bool:
	assert_eq(_hs().host_game("Hosty", _port), OK, "host listens")
	assert_eq(_cs().join_game("127.0.0.1", "Clienty", _port), OK, "client dials")
	return await H.wait_until(get_tree(), func(): return _cs().local_slot() == 1 and _hs().player_count() == 2)


func test_client_connects_and_is_seated_in_slot_1() -> void:
	var ok := await _connect_pair()
	assert_true(ok, "client seated within timeout")
	assert_eq(_hs().local_slot(), 0, "host is slot 0")
	assert_eq(_cs().local_slot(), 1, "client is slot 1")
	var roster: Dictionary = _cs().get_roster()
	assert_eq(roster.size(), 2, "client sees both players")
	var names := []
	for pid in roster:
		names.append(roster[pid]["name"])
	names.sort()
	assert_eq(names, ["Clienty", "Hosty"], "names synced to the client")


func test_start_requires_everyone_ready_and_is_single_shot() -> void:
	assert_true(await _connect_pair(), "connected")
	_hs().set_match_config({"map_path": "res://x.tres", "turn_system": 0})
	await H.wait_until(get_tree(), func(): return _cs().get_match_config().get("map_path", "") == "res://x.tres")
	assert_eq(_cs().get_match_config().get("map_path", ""), "res://x.tres", "config reaches the client")

	assert_false(_hs().start_match(), "cannot start: nobody ready")
	_hs().set_ready(true)
	assert_false(_hs().start_match(), "cannot start: client not ready")
	_cs().set_ready(true)
	await H.wait_until(get_tree(), func(): return _hs().can_start_match())
	assert_true(_hs().can_start_match(), "all ready -> startable")

	var host_started := []
	var client_started := []
	_hs().match_started.connect(func(cfg): host_started.append(cfg))
	_cs().match_started.connect(func(cfg): client_started.append(cfg))
	assert_true(_hs().start_match(), "start succeeds once")
	assert_false(_hs().start_match(), "second start is refused (single start guard)")
	await H.wait_until(get_tree(), func(): return client_started.size() == 1)
	assert_eq(host_started.size(), 1, "host got match_started exactly once")
	assert_eq(client_started.size(), 1, "client got match_started exactly once")
	var cfg: Dictionary = client_started[0]
	assert_eq(int(cfg["seed"]), int(host_started[0]["seed"]), "setup seed (derived from the RNG commitments) agrees")
	assert_eq(cfg["anchors"].size(), 2, "host + client committed a hash-chain anchor")
	assert_eq(cfg["map_path"], "res://x.tres", "map synced")
	assert_eq(String(cfg["slots"][1]), "Clienty", "slot assignment synced")
	assert_true(_cs().is_in_match(), "client is in match")


func test_config_change_clears_ready() -> void:
	assert_true(await _connect_pair(), "connected")
	_hs().set_ready(true)
	_cs().set_ready(true)
	await H.wait_until(get_tree(), func(): return _hs().can_start_match())
	_hs().set_match_config({"map_path": "res://other.tres"})
	assert_false(_hs().can_start_match(), "changing the map un-readies everyone")


func test_third_peer_is_rejected() -> void:
	assert_true(await _connect_pair(), "connected")
	_client2 = H.make_peer(self, "Client2Peer")
	var rejected := []
	_client2["session"].join_rejected.connect(func(reason, _info): rejected.append(reason))
	_client2["session"].join_game("127.0.0.1", "Third", _port)
	await H.wait_until(get_tree(), func(): return rejected.size() > 0)
	assert_eq(rejected, ["lobby_full"], "third player told the lobby is full")
	assert_eq(_hs().player_count(), 2, "host roster unchanged")
	assert_false(_client2["session"].is_active(), "rejected session closed itself")


func test_join_during_match_is_rejected() -> void:
	assert_true(await _connect_pair(), "connected")
	_hs().set_ready(true)
	_cs().set_ready(true)
	await H.wait_until(get_tree(), func(): return _hs().can_start_match())
	_hs().start_match()
	# Free a seat mid-match is impossible, but a late joiner must still be refused.
	_client2 = H.make_peer(self, "Client2Peer")
	var rejected := []
	_client2["session"].join_rejected.connect(func(reason, _info): rejected.append(reason))
	_client2["session"].join_game("127.0.0.1", "Late", _port)
	await H.wait_until(get_tree(), func(): return rejected.size() > 0)
	assert_eq(rejected, ["match_in_progress"], "late joiner refused")


func test_client_leaving_lobby_frees_slot() -> void:
	assert_true(await _connect_pair(), "connected")
	_cs().leave()
	await H.wait_until(get_tree(), func(): return _hs().player_count() == 1)
	assert_eq(_hs().player_count(), 1, "host dropped the leaver from the roster")
	assert_false(_cs().is_active(), "client session closed")


func test_host_leaving_disconnects_client() -> void:
	assert_true(await _connect_pair(), "connected")
	var lost := []
	_cs().disconnected.connect(func(reason): lost.append(reason))
	_hs().leave()
	await H.wait_until(get_tree(), func(): return lost.size() > 0)
	assert_eq(lost, ["host_disconnected"], "client notified the host is gone")
	assert_false(_cs().is_active(), "client session reset")
	assert_eq(_cs().local_slot(), -1, "client slot cleared")


# --- Merged-in local features over real sockets ---------------------------------

func test_a_protocol_mismatch_is_refused_at_the_door_with_a_reason() -> void:
	# The build gate: the joiner's FIRST message is its hello; a different PROTOCOL_VERSION is
	# refused before it is seated, with the version detail a menu can explain.
	assert_eq(_hs().host_game("Hosty", _port), OK, "host listens")
	var refused_on_host := []
	_hs().peer_join_refused.connect(func(_pid, reason, _info): refused_on_host.append(reason))
	var rejected := []
	_cs().join_rejected.connect(func(reason, info): rejected.append([reason, info]))
	_cs().debug_hello_protocol_version = NetProtocol.PROTOCOL_VERSION + 100
	assert_eq(_cs().join_game("127.0.0.1", "OldBuild", _port), OK, "client dials")
	await H.wait_until(get_tree(), func(): return rejected.size() > 0)
	assert_eq(rejected.size(), 1, "the client was told once")
	assert_eq(rejected[0][0], NetProtocol.REJECT_VERSION_MISMATCH, "why: version mismatch")
	var info: Dictionary = rejected[0][1]
	assert_eq(int(info.get("client_pv", -1)), NetProtocol.PROTOCOL_VERSION + 100, "info names the joiner's protocol")
	assert_eq(int(info.get("host_pv", -1)), NetProtocol.PROTOCOL_VERSION, "and the host's")
	assert_true(NetProtocol.describe_rejection(rejected[0][0], info).begins_with("Version mismatch"),
		"which reads as a sentence for the join screen")
	assert_eq(refused_on_host, [NetProtocol.REJECT_VERSION_MISMATCH], "the host saw the refusal too")
	assert_eq(_hs().player_count(), 1, "the mismatched build never took a seat")
	assert_eq(_cs().last_join_rejection().get("reason", ""), NetProtocol.REJECT_VERSION_MISMATCH,
		"and the refusal survives the disconnect that follows it")


func test_lobby_messages_reach_the_other_side_only() -> void:
	assert_true(await _connect_pair(), "connected")
	var at_host := []
	var at_client := []
	_hs().lobby_message.connect(func(t, d, s): at_host.append([t, d, s]))
	_cs().lobby_message.connect(func(t, d, s): at_client.append([t, d, s]))
	_cs().send_lobby_message("map_vote", {"map_path": "res://m.tres"})
	_hs().send_lobby_message("profile_info", {"name": "Hosty"})
	await H.wait_until(get_tree(), func(): return at_host.size() > 0 and at_client.size() > 0)
	await H.wait_frames(get_tree(), 3)
	assert_eq(at_host.size(), 1, "the host got exactly the client's message")
	assert_eq(at_host[0][0], "map_vote", "type survived")
	assert_eq(int(at_host[0][2]), 1, "stamped with the sender's seat by the host")
	assert_eq(at_client.size(), 1, "the client got exactly the host's message (never its own)")
	assert_eq(at_client[0][0], "profile_info", "type survived")
	assert_eq(int(at_client[0][2]), 0, "stamped with the host's seat")


func test_start_match_carries_the_lobbys_final_config() -> void:
	# The collaborative lobby settles the map (votes / coin flip) and the host's squad at the
	# last moment: start_match(final_config) folds them into the match config every peer
	# receives, without un-readying anyone.
	assert_true(await _connect_pair(), "connected")
	_hs().set_ready(true)
	_cs().set_ready(true)
	await H.wait_until(get_tree(), func(): return _hs().can_start_match())
	var got := []
	_cs().match_started.connect(func(cfg): got.append(cfg))
	assert_true(_hs().start_match({"map_path": "res://final.tres", "host_squad": ["gem_knight"], "versus_rounds": 3}),
		"the host starts with its final config")
	await H.wait_until(get_tree(), func(): return got.size() > 0)
	assert_eq(got.size(), 1, "the client started once")
	assert_eq(String(got[0].get("map_path", "")), "res://final.tres", "with the settled map")
	assert_eq(got[0].get("host_squad", []), ["gem_knight"], "the host's squad")
	assert_eq(int(got[0].get("versus_rounds", 0)), 3, "and the host's best-of")


func test_forfeit_reaches_the_opponent_before_the_disconnect() -> void:
	assert_true(await _connect_pair(), "connected")
	_hs().set_ready(true)
	_cs().set_ready(true)
	await H.wait_until(get_tree(), func(): return _hs().can_start_match())
	_hs().start_match()
	await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match())
	var forfeits := []
	var left := []
	_hs().opponent_forfeited.connect(func(slot): forfeits.append(slot))
	_hs().opponent_left.connect(func(): left.append(true))
	assert_true(_cs().forfeit_match(), "the client forfeits a live match")
	await H.wait_until(get_tree(), func(): return left.size() > 0)
	assert_eq(forfeits, [1], "the host learned the client (slot 1) forfeited")
	assert_eq(left.size(), 1, "and then saw it leave -- the battle resolves both as the same loss")
