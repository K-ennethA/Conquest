extends GutTest

## DEDICATED SERVER mode in one process: a seatless server NetSession plus two
## client NetSessions (three MultiplayerAPI branches, real ENet on 127.0.0.1),
## each peer with its own copy of the game. Covers seating, lobby leadership,
## auto-start, commit-reveal with three contributors (and server-only mode),
## identical play, a rejected third client, and surviving a disconnect into a
## second match.

const H := preload("res://tests/integration/net_test_harness.gd")
const F := preload("res://tests/integration/net_match_fixtures.gd")

var _srv: Dictionary = {}
var _a: Dictionary = {}
var _b: Dictionary = {}
var _extra: Dictionary = {}
var _worlds: Dictionary = {}   # "srv" / "a" / "b" -> world
var _port: int = 0


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	F.register_characters()
	_port = H.random_port()
	_srv = H.make_peer(self, "ServerPeer")
	_a = H.make_peer(self, "ClientAPeer")
	_b = H.make_peer(self, "ClientBPeer")
	_extra = {}
	_worlds = {}


func after_each() -> void:
	H.free_peer(_extra)
	H.free_peer(_b)
	H.free_peer(_a)
	H.free_peer(_srv)
	CombatServices.match_rng = null
	CombatServices.clear()
	CharacterLibrary.clear_cache()
	await H.wait_frames(get_tree(), 2)


func _ss() -> NetSessionNode:
	return _srv["session"]


func _as() -> NetSessionNode:
	return _a["session"]


func _bs() -> NetSessionNode:
	return _b["session"]


## Server up, A joins first (slot 0), then B (slot 1).
func _seat_both(config: Dictionary = {"map_path": "res://game/maps/resources/default_skirmish.tres"},
		mode: NetSessionNode.RngMode = NetSessionNode.RngMode.ALL) -> bool:
	if _ss().host_dedicated(_port, config, mode) != OK:
		return false
	_as().join_game("127.0.0.1", "Alice", _port)
	if not await H.wait_until(get_tree(), func(): return _as().local_slot() == 0):
		return false
	_bs().join_game("127.0.0.1", "Bob", _port)
	return await H.wait_until(get_tree(), func(): return _bs().local_slot() == 1 and _ss().player_count() == 2)


## Ready both, wait for the auto-start, build + attach the three worlds.
func _start_match() -> bool:
	_as().set_ready(true)
	_bs().set_ready(true)
	if not await H.wait_until(get_tree(), func():
			return _ss().is_in_match() and _as().is_in_match() and _bs().is_in_match()):
		return false
	for key in ["srv", "a", "b"]:
		var peer: Dictionary = {"srv": _srv, "a": _a, "b": _b}[key]
		_worlds[key] = F.build_world(peer["root"], int(peer["session"].get_match_config()["seed"]))
	await H.wait_frames(get_tree(), 2)
	_ss().attach_game(_worlds["srv"]["rules"])
	_as().attach_game(_worlds["a"]["rules"])
	_bs().attach_game(_worlds["b"]["rules"])
	return true


func _applied_everywhere(seq: int) -> bool:
	return _ss().last_applied_seq() >= seq and _as().last_applied_seq() >= seq and _bs().last_applied_seq() >= seq


func _submit(session: NetSessionNode, action: Dictionary) -> String:
	var rejected := []
	var cb := func(_a2, reason): rejected.append(reason)
	session.intent_rejected.connect(cb)
	var target := _ss().last_applied_seq() + 1
	session.submit_intent(action)
	await H.wait_until(get_tree(), func(): return rejected.size() > 0 or _applied_everywhere(target))
	session.intent_rejected.disconnect(cb)
	await H.wait_frames(get_tree(), 3)
	return String(rejected[0]) if rejected.size() > 0 else ""


func _digests() -> Array:
	return [_worlds["srv"]["rules"].state_digest(), _worlds["a"]["rules"].state_digest(), _worlds["b"]["rules"].state_digest()]


# --- Tests --------------------------------------------------------------------

func test_server_has_no_seat_and_clients_see_two_players() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_eq(_ss().local_slot(), -1, "server holds no seat")
	assert_false(_ss().get_roster().has(1), "server is not in the roster")
	assert_eq(_as().get_roster().size(), 2, "client A sees two players")
	assert_eq(_bs().get_roster().size(), 2, "client B sees two players")
	assert_true(_as().is_dedicated_server(), "clients know the host is a dedicated server")
	assert_false(_as().submit_intent(NetProtocol.end_turn()), "no intents in the lobby")
	assert_false(_ss().submit_intent(NetProtocol.end_turn()), "the seatless server cannot act")


func test_third_client_is_rejected() -> void:
	assert_true(await _seat_both(), "both seated")
	_extra = H.make_peer(self, "ClientCPeer")
	var rejected := []
	_extra["session"].join_rejected.connect(func(r): rejected.append(r))
	_extra["session"].join_game("127.0.0.1", "Carol", _port)
	await H.wait_until(get_tree(), func(): return rejected.size() > 0)
	assert_eq(rejected, ["lobby_full"], "third client refused")
	assert_eq(_ss().player_count(), 2, "roster unchanged")


func test_locked_config_cannot_be_changed_by_clients() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_false(_as().is_lobby_leader(), "server locked the map: no leader")
	_as().set_match_config({"map_path": "res://game/maps/resources/proving_grounds.tres"})
	await H.wait_frames(get_tree(), 10)
	assert_eq(_ss().get_match_config()["map_path"], "res://game/maps/resources/default_skirmish.tres", "unchanged")


func test_slot0_client_leads_an_unlocked_lobby() -> void:
	assert_true(await _seat_both({}), "both seated")
	assert_true(_as().is_lobby_leader(), "slot 0 leads")
	assert_false(_bs().is_lobby_leader(), "slot 1 does not")
	_bs().set_match_config({"map_path": "res://game/maps/resources/skirmish_arena.tres"})
	_as().set_match_config({"map_path": "res://game/maps/resources/proving_grounds.tres", "turn_system": 1, "evil": "x"})
	await H.wait_until(get_tree(), func(): return _bs().get_match_config().get("map_path", "") != "")
	assert_eq(_ss().get_match_config(), {"map_path": "res://game/maps/resources/proving_grounds.tres", "turn_system": 1},
		"leader's (sanitised) choice applied")
	assert_eq(_bs().get_match_config()["map_path"], "res://game/maps/resources/proving_grounds.tres", "synced to B")


func test_auto_start_with_three_contributors() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "auto-started once both were ready")
	var contributors: Array = _ss().rng_contributors()
	assert_eq(contributors.size(), 3, "server + both clients contribute randomness")
	assert_eq(_as().rng_contributors(), contributors, "A agrees")
	assert_eq(_bs().rng_contributors(), contributors, "B agrees")
	var cfg := _as().get_match_config()
	assert_eq(String(cfg["slots"][0]), "Alice", "slot 0")
	assert_eq(String(cfg["slots"][1]), "Bob", "slot 1")
	assert_eq(int(cfg["seed"]), int(_bs().get_match_config()["seed"]), "setup seed agrees")


func test_two_clients_play_with_identical_state() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "started")
	var desyncs := []
	_as().desync_detected.connect(func(s, _x, _y): desyncs.append(s))
	_bs().desync_detected.connect(func(s, _x, _y): desyncs.append(s))
	assert_eq(await _submit(_bs(), NetProtocol.move("1:1", Vector3i(3, 4, 0))), "not_your_turn", "B waits")
	assert_eq(await _submit(_as(), NetProtocol.move("0:1", Vector3i(3, 1, 0))), "", "A moves")
	assert_eq(await _submit(_as(), NetProtocol.use_move("0:0", 0, Vector3i(0, 1, 0))), "", "A strikes")
	assert_eq(await _submit(_as(), NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0))), "", "A coin-strikes")
	await H.wait_until(get_tree(), func(): return _bs().current_turn_slot() == 1)
	assert_eq(_bs().current_turn_slot(), 1, "B's turn (auto end-of-turn)")
	assert_eq(await _submit(_bs(), NetProtocol.use_move("1:0", 1, Vector3i(0, 0, 0))), "", "B coin-strikes")
	assert_eq(await _submit(_bs(), NetProtocol.end_turn()), "", "B ends turn")
	await H.wait_until(get_tree(), func(): return _as().current_turn_slot() == 0)
	for i in range(4):
		assert_eq(await _submit(_as(), NetProtocol.use_move("0:0", 1, Vector3i(0, 1, 0))), "", "A coin %d" % i)
		assert_eq(await _submit(_as(), NetProtocol.end_turn()), "", "A ends %d" % i)
		await H.wait_until(get_tree(), func(): return _bs().current_turn_slot() == 1)
		assert_eq(await _submit(_bs(), NetProtocol.end_turn()), "", "B ends %d" % i)
		await H.wait_until(get_tree(), func(): return _as().current_turn_slot() == 0)
	var d := _digests()
	assert_eq(d[0], d[1], "server == A")
	assert_eq(d[1], d[2], "A == B")
	assert_eq(F.hp(_worlds["srv"], "1:0"), F.hp(_worlds["b"], "1:0"), "same HP")
	assert_eq(desyncs, [], "no desync")


func test_acting_client_cannot_derive_roll_until_the_other_client_reveals() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "started")
	_bs().debug_hold_shares = true
	_as().submit_intent(NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0)))
	await H.wait_until(get_tree(), func(): return _as().has_pending_actions() and _bs().has_pending_actions())
	await H.wait_frames(get_tree(), 5)
	assert_false(_as().randomness_known(1), "the actor holds the server's share and its own, but not B's")
	assert_false(_ss().randomness_known(1), "the server cannot derive it either")
	assert_eq(_as().last_applied_seq(), 0, "not applied yet")
	_bs().release_held_shares()
	await H.wait_until(get_tree(), func(): return _applied_everywhere(1))
	await H.wait_frames(get_tree(), 3)
	var d := _digests()
	assert_eq(d[0], d[1], "server == A")
	assert_eq(d[1], d[2], "A == B")


func test_tampering_client_ends_the_match_for_both() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "started")
	var a_aborted := []
	var b_aborted := []
	_as().match_aborted.connect(func(r): a_aborted.append(r))
	_bs().match_aborted.connect(func(r): b_aborted.append(r))
	_bs().debug_tamper_shares = true
	_as().submit_intent(NetProtocol.move("0:1", Vector3i(3, 0, 0)))
	await H.wait_until(get_tree(), func(): return a_aborted.size() > 0 and b_aborted.size() > 0)
	assert_eq(a_aborted, ["rng_verification_failed"], "the honest client is told")
	assert_eq(_ss().state, NetSessionNode.State.LOBBY, "server back to the lobby")
	assert_eq(_as().last_applied_seq(), 0, "never applied")
	for e in get_errors():
		if "verification FAILED" in str(e.code) or "verification FAILED" in str(e.rationale):
			e.handled = true


func test_server_only_randomness_mode() -> void:
	assert_true(await _seat_both({"map_path": "res://game/maps/resources/default_skirmish.tres"},
		NetSessionNode.RngMode.SERVER_ONLY), "both seated")
	assert_true(await _start_match(), "started")
	assert_eq(_ss().rng_contributors(), [1], "only the trusted server contributes")
	for i in range(3):
		assert_eq(await _submit(_as(), NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0)) if i == 0 else NetProtocol.end_turn()), "", "A %d" % i)
		if i > 0:
			await H.wait_until(get_tree(), func(): return _bs().current_turn_slot() == 1)
			assert_eq(await _submit(_bs(), NetProtocol.end_turn()), "", "B %d" % i)
			await H.wait_until(get_tree(), func(): return _as().current_turn_slot() == 0)
	var d := _digests()
	assert_eq(d[0], d[1], "server == A")
	assert_eq(d[1], d[2], "A == B")


func test_server_survives_a_disconnect_and_hosts_a_second_match() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "started")
	assert_eq(await _submit(_as(), NetProtocol.move("0:1", Vector3i(3, 0, 0))), "", "A moves")
	var a_aborted := []
	var srv_aborted := []
	_as().match_aborted.connect(func(r): a_aborted.append(r))
	_ss().match_aborted.connect(func(r): srv_aborted.append(r))
	_bs().leave()
	await H.wait_until(get_tree(), func(): return a_aborted.size() > 0 and srv_aborted.size() > 0)
	assert_eq(srv_aborted, ["opponent_disconnected"], "server noticed")
	assert_eq(a_aborted, ["opponent_disconnected"], "remaining client told")
	assert_eq(_ss().state, NetSessionNode.State.LOBBY, "server reopened the lobby")
	await H.wait_until(get_tree(), func(): return not _as().is_active())
	assert_eq(_ss().player_count(), 0, "empty lobby")
	assert_true(_ss().is_active(), "server still listening")
	for w in _worlds.values():
		w["world"].queue_free()
	_worlds = {}
	await H.wait_frames(get_tree(), 20)
	# Second match with the same two clients reconnecting.
	_as().join_game("127.0.0.1", "Alice", _port)
	assert_true(await H.wait_until(get_tree(), func(): return _as().local_slot() == 0), "A re-seated")
	_bs().join_game("127.0.0.1", "Bob", _port)
	assert_true(await H.wait_until(get_tree(), func(): return _bs().local_slot() == 1), "B re-seated")
	assert_true(await _start_match(), "second match started")
	assert_eq(_ss().last_applied_seq(), 0, "fresh ordering")
	assert_eq(await _submit(_as(), NetProtocol.use_move("0:0", 0, Vector3i(0, 1, 0))), "", "A strikes in match 2")
	var d := _digests()
	assert_eq(d[0], d[1], "server == A")
	assert_eq(d[1], d[2], "A == B")


func test_server_closes_a_finished_match_and_hosts_the_next() -> void:
	assert_true(await _seat_both(), "both seated")
	assert_true(await _start_match(), "started")
	assert_eq(await _submit(_as(), NetProtocol.use_move("0:0", 0, Vector3i(0, 1, 0))), "", "A strikes")
	var a_aborted := []
	var b_aborted := []
	_as().match_aborted.connect(func(r): a_aborted.append(r))
	_bs().match_aborted.connect(func(r): b_aborted.append(r))
	_ss().end_match("match_complete")
	await H.wait_until(get_tree(), func(): return a_aborted.size() > 0 and b_aborted.size() > 0)
	assert_eq(a_aborted, ["match_complete"], "A told the match is over")
	assert_eq(b_aborted, ["match_complete"], "B told the match is over")
	assert_eq(_as().last_applied_seq(), 0, "session reset after closing")
	await H.wait_until(get_tree(), func(): return not _as().is_active() and not _bs().is_active())
	for w in _worlds.values():
		w["world"].queue_free()
	_worlds = {}
	await H.wait_frames(get_tree(), 30)
	assert_eq(_ss().state, NetSessionNode.State.LOBBY, "lobby reopened")
	_as().join_game("127.0.0.1", "Alice2", _port)
	assert_true(await H.wait_until(get_tree(), func(): return _as().local_slot() == 0), "new A seated")
	_bs().join_game("127.0.0.1", "Bob2", _port)
	assert_true(await H.wait_until(get_tree(), func(): return _bs().local_slot() == 1), "new B seated")
	assert_true(await _start_match(), "second match started")
