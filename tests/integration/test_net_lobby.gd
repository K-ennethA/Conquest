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
	_client2["session"].join_rejected.connect(func(reason): rejected.append(reason))
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
	_client2["session"].join_rejected.connect(func(reason): rejected.append(reason))
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
