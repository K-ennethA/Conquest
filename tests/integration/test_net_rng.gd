extends GutTest

## Commit-reveal combat randomness over a real (in-process, ENet 127.0.0.1)
## PLAYER-HOSTED session: nobody can derive a roll before the action consuming
## it was accepted, shares that fail verification end the match on the honest
## peer, chains re-commit when exhausted, and peers stay in lockstep.

const H := preload("res://tests/integration/net_test_harness.gd")
const F := preload("res://tests/integration/net_match_fixtures.gd")

var _host: Dictionary = {}
var _client: Dictionary = {}
var _hw: Dictionary = {}
var _cw: Dictionary = {}
var _port: int = 0


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	F.register_characters()
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")
	_hw = {}
	_cw = {}


func after_each() -> void:
	H.free_peer(_client)
	H.free_peer(_host)
	CombatServices.match_rng = null
	CombatServices.clear()
	CharacterLibrary.clear_cache()
	await H.wait_frames(get_tree(), 2)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _start(chain_length: int = NetCommitReveal.DEFAULT_CHAIN_LENGTH) -> bool:
	_hs().rng_chain_length = chain_length
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	if not await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1):
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match()
	if not await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match()):
		return false
	_hw = F.build_world(_host["root"], int(_hs().get_match_config()["seed"]))
	_cw = F.build_world(_client["root"], int(_cs().get_match_config()["seed"]))
	await H.wait_frames(get_tree(), 2)
	_hs().attach_game(_hw["rules"])
	_cs().attach_game(_cw["rules"])
	return true


func _submit(session: NetSessionNode, action: Dictionary) -> String:
	var rejected := []
	var cb := func(_a, reason): rejected.append(reason)
	session.intent_rejected.connect(cb)
	var target := _hs().last_applied_seq() + 1
	session.submit_intent(action)
	await H.wait_until(get_tree(), func():
		return rejected.size() > 0 or (_hs().last_applied_seq() >= target and _cs().last_applied_seq() >= target))
	session.intent_rejected.disconnect(cb)
	await H.wait_frames(get_tree(), 3)
	return String(rejected[0]) if rejected.size() > 0 else ""


func _expect_warning(text: String) -> int:
	var n := 0
	for e in get_errors():
		if text in str(e.code) or text in str(e.rationale):
			e.handled = true
			n += 1
	return n


# --- Tests --------------------------------------------------------------------

func test_both_players_commit_and_agree_on_the_setup_seed() -> void:
	assert_true(await _start(), "started")
	var hc := _hs().get_match_config()
	var cc := _cs().get_match_config()
	assert_eq(int(hc["seed"]), int(cc["seed"]), "setup seed agrees")
	assert_eq(_hs().rng_contributors(), [1, _cs().local_peer_id()], "host and client both contribute")
	assert_eq(_cs().rng_contributors(), _hs().rng_contributors(), "client agrees on the contributor set")


func test_host_actor_cannot_know_the_roll_before_the_client_reveals() -> void:
	assert_true(await _start(), "started")
	_cs().debug_hold_shares = true
	_hs().submit_intent(NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0)))  # 50% coin strike
	# The host accepted (and broadcast) seq 1, but the client is holding its share.
	await H.wait_until(get_tree(), func(): return _cs().randomness_known(1) or _cs().has_pending_actions())
	await H.wait_frames(get_tree(), 5)
	assert_false(_hs().randomness_known(1), "the acting host cannot derive the roll yet")
	assert_eq(_hs().last_applied_seq(), 0, "nothing applied on the host")
	# The (non-acting) client may already know it: the action is irrevocable.
	assert_true(_cs().randomness_known(1), "client holds both shares once the host accepted")
	var hp_before := F.hp(_hw, "1:1")
	_cs().release_held_shares()
	await H.wait_until(get_tree(), func(): return _hs().last_applied_seq() == 1 and _cs().last_applied_seq() == 1)
	await H.wait_frames(get_tree(), 3)
	assert_true(_hs().randomness_known(1), "known once revealed")
	assert_eq(F.hp(_hw, "1:1"), F.hp(_cw, "1:1"), "same outcome on both peers")
	assert_true(F.hp(_hw, "1:1") <= hp_before, "applied")


func test_client_actor_cannot_know_the_roll_before_the_host_accepts() -> void:
	assert_true(await _start(), "started")
	assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "", "host passes")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
	var next_seq := _hs().last_applied_seq() + 1
	_cs().submit_intent(NetProtocol.use_move("1:1", 1, Vector3i(4, 0, 0)))
	assert_false(_cs().randomness_known(next_seq), "at submit time the client has no host share for the action")
	await H.wait_until(get_tree(), func(): return _cs().last_applied_seq() >= next_seq and _hs().last_applied_seq() >= next_seq)
	assert_eq(F.hp(_hw, "0:1"), F.hp(_cw, "0:1"), "identical outcome")


func test_tampering_client_is_caught_by_the_host() -> void:
	assert_true(await _start(), "started")
	var host_aborted := []
	var client_aborted := []
	var cheats := []
	_hs().match_aborted.connect(func(r): host_aborted.append(r))
	_hs().cheat_detected.connect(func(pid, r): cheats.append([pid, r]))
	_cs().match_aborted.connect(func(r): client_aborted.append(r))
	_cs().debug_tamper_shares = true
	_hs().submit_intent(NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0)))
	await H.wait_until(get_tree(), func(): return host_aborted.size() > 0 and client_aborted.size() > 0)
	assert_eq(host_aborted, ["rng_verification_failed"], "honest host ends the match")
	assert_eq(client_aborted, ["rng_verification_failed"], "the client is told why")
	assert_eq(cheats.size(), 1, "one cheat reported")
	assert_eq(cheats[0][1], "bad_reveal", "the forged share failed the hash-chain check")
	assert_eq(_hs().last_applied_seq(), 0, "the action was never applied with forged randomness")
	assert_eq(_expect_warning("verification FAILED"), 1, "warned")


func test_tampering_host_is_caught_by_the_client() -> void:
	assert_true(await _start(), "started")
	var client_aborted := []
	var cheats := []
	_cs().match_aborted.connect(func(r): client_aborted.append(r))
	_cs().cheat_detected.connect(func(pid, r): cheats.append([pid, r]))
	_hs().debug_tamper_shares = true
	_hs().submit_intent(NetProtocol.move("0:1", Vector3i(3, 0, 0)))
	await H.wait_until(get_tree(), func(): return client_aborted.size() > 0)
	assert_eq(client_aborted, ["host_verification_failed"], "honest client ends the match")
	assert_eq(cheats, [[1, "bad_reveal"]], "the host's share failed verification")
	assert_eq(_cs().last_applied_seq(), 0, "nothing applied on the client")
	assert_false(_cs().is_active(), "client left the session")
	assert_eq(_expect_warning("verification FAILED"), 1, "warned")


func test_withheld_reveal_times_out() -> void:
	assert_true(await _start(), "started")
	_hs().reveal_timeout_ms = 300
	var host_aborted := []
	_hs().match_aborted.connect(func(r): host_aborted.append(r))
	_cs().debug_hold_shares = true
	_hs().submit_intent(NetProtocol.move("0:1", Vector3i(3, 0, 0)))
	await H.wait_until(get_tree(), func(): return host_aborted.size() > 0, 3000)
	assert_eq(host_aborted, ["reveal_timeout"], "a peer that refuses to reveal forfeits")
	_expect_warning("verification FAILED")


func test_chains_recommit_and_peers_stay_in_lockstep() -> void:
	# Chain length 3: 12 actions cross four epochs (each with a fresh commitment).
	assert_true(await _start(3), "started")
	var desyncs := []
	var cheats := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	_cs().cheat_detected.connect(func(p, r): cheats.append(r))
	_hs().cheat_detected.connect(func(p, r): cheats.append(r))
	for i in range(3):
		assert_eq(await _submit(_hs(), NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0))), "", "host coin strike %d" % i)
		assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "", "host ends %d" % i)
		await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
		assert_eq(await _submit(_cs(), NetProtocol.use_move("1:1", 1, Vector3i(4, 0, 0))), "", "client coin strike %d" % i)
		assert_eq(await _submit(_cs(), NetProtocol.end_turn()), "", "client ends %d" % i)
		await H.wait_until(get_tree(), func(): return _hs().current_turn_slot() == 0)
	assert_eq(_hs().last_applied_seq(), 12, "12 actions")
	assert_eq(_hw["rules"].state_digest(), _cw["rules"].state_digest(), "digests agree")
	assert_eq(F.hp(_hw, "1:1"), F.hp(_cw, "1:1"), "hp agrees")
	assert_eq(desyncs, [], "no desync")
	assert_eq(cheats, [], "no verification failure across re-commits")


func test_host_cannot_puppet_the_clients_units() -> void:
	assert_true(await _start(), "started")
	assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "", "host passes")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
	var client_aborted := []
	var cheats := []
	_cs().match_aborted.connect(func(r): client_aborted.append(r))
	_cs().cheat_detected.connect(func(pid, r): cheats.append(r))
	# A modified host injects an action in the CLIENT's seat.
	_hs()._intent_queue.append([1, NetProtocol.move("1:1", Vector3i(3, 4, 0))])
	await H.wait_until(get_tree(), func(): return client_aborted.size() > 0)
	assert_eq(client_aborted, ["host_verification_failed"], "client refuses an action it never sent")
	assert_eq(cheats, ["forged_action"], "reported as forged")
	assert_eq(F.cell(_cw, "1:1"), Vector3i(4, 4, 0), "client's unit did not move")
	assert_eq(_expect_warning("verification FAILED"), 1, "warned")


func test_client_rejects_an_illegal_action_the_host_accepted() -> void:
	assert_true(await _start(), "started")
	var client_aborted := []
	var cheats := []
	_cs().match_aborted.connect(func(r): client_aborted.append(r))
	_cs().cheat_detected.connect(func(pid, r): cheats.append(r))
	_hs().debug_accept_everything = true
	_hs().submit_intent(NetProtocol.move("0:1", Vector3i(0, 4, 0)))   # far beyond its movement
	await H.wait_until(get_tree(), func(): return client_aborted.size() > 0)
	assert_eq(client_aborted, ["host_verification_failed"], "client refuses the illegal move")
	assert_eq(cheats, ["illegal_action:illegal_destination"], "re-validated on the client")
	assert_eq(F.cell(_cw, "0:1"), Vector3i(4, 0, 0), "not applied on the client")
	assert_eq(_expect_warning("verification FAILED"), 1, "warned")
