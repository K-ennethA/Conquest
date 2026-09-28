extends GutTest

## ONLINE DUELS over the real network core (docs/design/DECISIONS.md #32): a host and a client
## NetSessionNode in ONE process (real ENet over 127.0.0.1, net_test_harness.gd), each building
## its OWN [DuelBattle] from the host's match config ([DuelNetConfig]) and attaching a
## [DuelNetRules]. Proves: the duel lobby mode rides the handshake, both peers build the same
## duel from the config, a full duel applies identically (commands, per-action commit-reveal
## seeds, HP timeline, winner, digest), the host validates (turn, slot, aim, items / moves /
## end-turn refused online), clients re-validate, the acting peer cannot derive its roll before
## the other reveals, desyncs are caught, and forfeits / disconnects reach the other seat.

const H := preload("res://tests/integration/net_test_harness.gd")

const UNITS := {0: "vineweave", 1: "gem_knight"}

var _host: Dictionary = {}
var _client: Dictionary = {}
var _port: int = 0
var _hb: DuelBattle = null
var _cb: DuelBattle = null
var _hr: DuelNetRules = null
var _cr: DuelNetRules = null


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")
	_hs().lobby_mode = NetProtocol.MODE_DUEL
	_cs().lobby_mode = NetProtocol.MODE_DUEL
	_hb = null
	_cb = null


func after_each() -> void:
	for b in [_hb, _cb]:
		if b != null and is_instance_valid(b):
			b.teardown()
	H.free_peer(_client)
	H.free_peer(_host)
	CombatServices.match_rng = null
	CombatServices.clear()
	await H.wait_frames(get_tree(), 2)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _connect() -> bool:
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	return await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1)


## Connect, ready, start with [param units], build + attach a duel on both peers.
func _start(units: Dictionary = UNITS) -> bool:
	if not await _connect():
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match(DuelNetConfig.final_config(units, "meadow", "clear"))
	if not await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match()):
		return false
	_hb = _build(_host, _hs().get_match_config())
	_cb = _build(_client, _cs().get_match_config())
	if _hb == null or _cb == null:
		return false
	_hr = DuelNetRules.new(_hb)
	_cr = DuelNetRules.new(_cb)
	_hs().attach_game(_hr)
	_cs().attach_game(_cr)
	await H.wait_frames(get_tree(), 2)
	return true


func _build(peer: Dictionary, cfg: Dictionary) -> DuelBattle:
	var res := DuelNetConfig.build_request(cfg)
	assert_true(bool(res["success"]), "the config builds a duel (%s)" % String(res["reason"]))
	if not bool(res["success"]):
		return null
	var b := DuelBattle.new()
	(peer["root"] as Node).add_child(b)
	var ok := b.setup(res["request"])
	assert_true(bool(ok["success"]), "duel set up")
	b.start()
	return b


## The session whose seat acts now (by the host's copy).
func _actor_session() -> NetSessionNode:
	var slot := _hr.current_turn_slot()
	return _hs() if slot == 0 else _cs()


func _other_session() -> NetSessionNode:
	return _cs() if _actor_session() == _hs() else _hs()


func _rules_of(session: NetSessionNode) -> DuelNetRules:
	return _hr if session == _hs() else _cr


## Submit and wait until applied on BOTH peers or refused. Returns the refusal ("" = applied).
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


## The acting seat's natural intent: its forced pass, or its first legal move.
func _next_intent() -> Dictionary:
	var s := _actor_session()
	var r := _rules_of(s)
	var actor = r.battle.current_actor()
	if r.battle.must_pass(actor):
		return r.pass_intent()
	return r.use_move_intent(r.battle.legal_slots(actor)[0])


func _expect_warning(text: String) -> int:
	var n := 0
	for e in get_errors():
		if text in str(e.code) or text in str(e.rationale):
			e.handled = true
			n += 1
	return n


# --- Tests --------------------------------------------------------------------

func test_the_host_stamps_the_duel_mode_and_both_peers_build_the_same_duel() -> void:
	assert_true(await _start(), "started")
	var hc := _hs().get_match_config()
	var cc := _cs().get_match_config()
	assert_eq(NetProtocol.mode_of(hc), NetProtocol.MODE_DUEL, "the host stamped the lobby mode")
	assert_true(DuelNetConfig.is_duel(cc), "the client sees a duel config")
	assert_eq(DuelNetConfig.unit_of(cc, 0), "vineweave", "slot 0's pick rides the config")
	assert_eq(DuelNetConfig.unit_of(cc, 1), "gem_knight", "slot 1's pick rides the config")
	assert_eq(_hb.request.seed, int(hc["seed"]), "the duel seed is the public setup seed")
	assert_eq(_hb.request.seed, _cb.request.seed, "identical on both peers")
	assert_eq(_hb.request.kind, DuelRequest.KIND_VERSUS, "an online duel is a versus duel")
	assert_false(_hb.can_flee(), "no running online")
	assert_false(_hb.can_use_items(), "no items online")
	for side in 2:
		assert_eq(NetUnitIds.id_of(_hb.unit_of(side)), NetUnitIds.id_of(_cb.unit_of(side)), "same ids")
		assert_eq(String(_hb.unit_of(side).character_resource.character_id),
			String(_cb.unit_of(side).character_resource.character_id), "same combatants")
	assert_eq(_hr.current_turn_slot(), _cr.current_turn_slot(), "same speed order opens the duel")
	assert_eq(_hr.state_digest(), _cr.state_digest(), "identical opening digest")


func test_a_whole_duel_applies_identically_on_both_peers() -> void:
	assert_true(await _start(), "started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	var n := 0
	while not _hb.is_over and n < 80:
		var reason := await _submit(_actor_session(), _next_intent())
		assert_eq(reason, "", "the acting seat's legal intent is accepted (action %d)" % n)
		if reason != "":
			break
		assert_eq(_hr.state_digest(), _cr.state_digest(), "digests agree after action %d" % n)
		n += 1
	assert_true(_hb.is_over and _cb.is_over, "the duel is decided on both peers (%d actions)" % n)
	assert_eq(_hb.result.winner_side, _cb.result.winner_side, "the same winner")
	assert_eq(_hb.result.hp_timeline, _cb.result.hp_timeline, "the same HP + status timeline")
	assert_eq(_hb.result.commands, _cb.result.commands, "the same command log, seeds included")
	var local := MatchRng.new()
	local.begin_from_seed(_hb.request.seed)
	var from_local_stream := 0
	for cmd in _hb.result.commands:
		assert_ne(int(cmd.get(NetProtocol.KEY_RNG, 0)), 0, "every command carries its seed")
		if int(cmd[NetProtocol.KEY_RNG]) == local.seed_for(int(cmd[NetProtocol.KEY_SEQ])):
			from_local_stream += 1
	assert_eq(from_local_stream, 0, "network seeds are commit-reveal seeds, never the public setup stream")
	assert_eq(desyncs, [], "no desync across the whole duel")
	var late := NetProtocol.use_move("0:0", 0, Vector3i.ZERO)
	assert_eq(_hr.validate_intent(late, 0), NetProtocol.INTENT_DUEL_OVER, "nothing is accepted once decided")


func test_only_the_acting_seat_may_act() -> void:
	assert_true(await _start(), "started")
	var waiting := _other_session()
	var foreign := _rules_of(_actor_session()).use_move_intent(0)
	var digest := _hr.state_digest()
	assert_eq(await _submit(waiting, foreign), NetProtocol.INTENT_NOT_YOUR_TURN, "the waiting seat is refused")
	assert_eq(_hs().last_applied_seq(), 0, "nothing applied")
	assert_eq(_hr.state_digest(), digest, "state untouched")


func test_the_host_validates_the_duel_rules() -> void:
	assert_true(await _start(), "started")
	var s := _actor_session()
	var r := _rules_of(s)
	var actor = r.battle.current_actor()
	var id := NetUnitIds.id_of(actor)
	var good := r.use_move_intent(r.battle.legal_slots(actor)[0])
	var bad_aim := good.duplicate(true)
	bad_aim[NetProtocol.KEY_DATA][NetProtocol.K_AIM] = NetProtocol.cell_to_wire(Vector3i(1, 5, 0))
	assert_eq(await _submit(s, bad_aim), NetProtocol.INTENT_ILLEGAL_TARGET, "a duel has no free aiming")
	assert_eq(await _submit(s, NetProtocol.use_move(id, 7, Vector3i.ZERO)), NetProtocol.INTENT_NO_MOVE_IN_SLOT, "no such slot")
	assert_eq(await _submit(s, NetProtocol.use_item(id, "herb_poultice")), NetProtocol.INTENT_NOT_ONLINE, "no items online")
	assert_eq(await _submit(s, NetProtocol.move(id, Vector3i(1, 0, 0))), NetProtocol.INTENT_UNIT_CANNOT_MOVE, "stations never change")
	assert_eq(await _submit(s, NetProtocol.end_turn()), NetProtocol.INTENT_CANNOT_END_TURN, "a turn ends by acting")
	assert_eq(await _submit(s, NetProtocol.wait(id)), NetProtocol.INTENT_REJECTED_BY_GAME, "no free skip")
	var foe_id := NetUnitIds.id_of(r.battle.foe_of(actor))
	assert_eq(await _submit(s, NetProtocol.use_move(foe_id, 0, Vector3i.ZERO)), NetProtocol.INTENT_NOT_YOUR_UNIT,
		"the foe's combatant is not yours")
	assert_eq(_hs().last_applied_seq(), 0, "none of it applied")
	assert_eq(await _submit(s, good), "", "the legal pick is accepted")


func test_the_client_re_validates_what_the_host_accepted() -> void:
	assert_true(await _start(), "started")
	var client_aborted := []
	var cheats := []
	_cs().match_aborted.connect(func(r): client_aborted.append(r))
	_cs().cheat_detected.connect(func(_pid, r): cheats.append(r))
	_hs().debug_accept_everything = true
	var id := NetUnitIds.id_of(_hb.unit_of(0))
	_hs().submit_intent(NetProtocol.use_item(id, "herb_poultice"))   # never legal online
	await H.wait_until(get_tree(), func(): return client_aborted.size() > 0)
	assert_eq(client_aborted, ["host_verification_failed"], "the client refuses it")
	assert_true(not cheats.is_empty() and String(cheats[0]).begins_with("illegal_action:"), "re-validated on the client")
	_expect_warning("verification FAILED")


func test_the_acting_seat_cannot_know_its_roll_before_the_other_reveals() -> void:
	assert_true(await _start(), "started")
	if _actor_session() != _hs():
		# Make the host the actor: let the client act once first.
		assert_eq(await _submit(_cs(), _next_intent()), "", "client acts")
		if _hb.is_over or _actor_session() != _hs():
			pass_test("the host never got the next turn in this seed")
			return
	_cs().debug_hold_shares = true
	var seq := _hs().last_applied_seq() + 1
	_hs().submit_intent(_next_intent())
	await H.wait_until(get_tree(), func(): return _cs().randomness_known(seq))
	await H.wait_frames(get_tree(), 5)
	assert_false(_hs().randomness_known(seq), "the acting host cannot derive the roll yet")
	assert_eq(_hs().last_applied_seq(), seq - 1, "nothing applied on the host")
	_cs().release_held_shares()
	await H.wait_until(get_tree(), func(): return _hs().last_applied_seq() == seq and _cs().last_applied_seq() == seq)
	await H.wait_frames(get_tree(), 3)
	assert_eq(_hr.state_digest(), _cr.state_digest(), "same outcome once both revealed")
	var cmd: Dictionary = _hb.result.commands[-1]
	assert_eq(int(cmd[NetProtocol.KEY_RNG]), int(_cb.result.commands[-1][NetProtocol.KEY_RNG]), "same verified seed")


func test_a_desync_is_detected() -> void:
	assert_true(await _start(), "started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	_cb.unit_of(0).take_damage(3)   # corrupt the CLIENT's copy behind the protocol's back
	assert_eq(await _submit(_actor_session(), _next_intent()), "", "accepted")
	await H.wait_until(get_tree(), func(): return desyncs.size() > 0)
	assert_eq(desyncs.size(), 1, "the client flagged it at the next checkpoint")
	assert_eq(_expect_warning("DESYNC"), 1, "warned once")


func test_a_forfeit_and_a_disconnect_reach_the_other_seat() -> void:
	assert_true(await _start(), "started")
	var forfeited := []
	_hs().opponent_forfeited.connect(func(slot): forfeited.append(slot))
	assert_true(_cs().forfeit_match(), "the client forfeits the live duel")
	await H.wait_until(get_tree(), func(): return forfeited.size() > 0)
	assert_eq(forfeited, [1], "the host hears slot 1 forfeit (host-stamped)")
	_hb.concede(forfeited[0])
	assert_true(_hb.is_over, "the duel ends")
	assert_eq(_hb.result.winner_side, 0, "the seat that stayed wins")
	assert_eq(_hb.result.outcome, DuelResult.OUTCOME_VICTORY, "a victory for side A")


func test_a_client_dropping_mid_duel_is_the_hosts_win() -> void:
	assert_true(await _start(), "started")
	var left := []
	_hs().opponent_left.connect(func(): left.append(true))
	_cs().leave()
	await H.wait_until(get_tree(), func(): return left.size() > 0)
	assert_eq(left.size(), 1, "opponent_left raised on the host")


func test_a_conquest_joiner_is_refused_by_a_duel_host() -> void:
	_cs().lobby_mode = NetProtocol.MODE_CONQUEST
	var rejected := []
	_cs().join_rejected.connect(func(reason, info): rejected.append([reason, info]))
	assert_eq(_hs().host_game("Host", _port), OK)
	_cs().join_game("127.0.0.1", "Client", _port)
	await H.wait_until(get_tree(), func(): return rejected.size() > 0)
	assert_eq(String(rejected[0][0]), NetProtocol.REJECT_MODE_MISMATCH, "refused at the gate")
	var text := NetProtocol.describe_rejection(String(rejected[0][0]), rejected[0][1])
	assert_true(text.contains("Duel"), "the reason names the host's mode: %s" % text)
	assert_eq(_hs().player_count(), 1, "never seated")


func test_a_config_with_a_unit_that_cannot_duel_is_refused_everywhere() -> void:
	var cfg := {NetProtocol.CONFIG_MODE: NetProtocol.MODE_DUEL, "seed": 5,
		DuelNetConfig.KEY_UNITS: {0: "vineweave", 1: "bastion"}}
	var res := DuelNetConfig.build_request(cfg)
	assert_false(bool(res["success"]), "a pure self-guard kit cannot duel")
	assert_eq(String(res["reason"]), "ineligible_unit")
	assert_false(DuelNetConfig.sanitize(cfg)[DuelNetConfig.KEY_UNITS].has(1), "the sanitiser drops it")
	var bogus := DuelNetConfig.build_request({DuelNetConfig.KEY_UNITS: {0: "res://evil.tres", 1: "gem_knight"}})
	assert_false(bool(bogus["success"]), "a path is never a unit id")
	var stage := DuelNetConfig.build_request({DuelNetConfig.KEY_STAGE: "volcano", "seed": 1})
	assert_eq(String(stage["reason"]), "unknown_stage", "an unknown stage refuses")
	var fine := DuelNetConfig.build_request({"seed": 9})
	assert_true(bool(fine["success"]), "missing picks fall back to each slot's default")
	assert_eq(String(fine["request"].foe_party[0].character_id), "gem_knight")


func test_a_dedicated_duel_server_folds_both_seats_picks_into_the_start() -> void:
	var server := H.make_peer(self, "ServerPeer")
	var srv := DedicatedServer.new()
	(server["root"] as Node).add_child(srv)
	var ss: NetSessionNode = server["session"]
	assert_eq(srv.start(PackedStringArray(["--mode", "duel", "--port", str(_port), "--stage", "grove"]), ss), OK,
		"a --mode duel server listens")
	assert_eq(ss.lobby_mode, NetProtocol.MODE_DUEL, "its lobby is a duel lobby")
	for pair in [[_hs(), "A"], [_cs(), "B"]]:
		(pair[0] as NetSessionNode).join_game("127.0.0.1", "Bot" + String(pair[1]), _port)
	assert_true(await H.wait_until(get_tree(), func(): return ss.player_count() == 2 and _hs().local_slot() >= 0 and _cs().local_slot() >= 0),
		"both seated")
	var a: NetSessionNode = _hs() if _hs().local_slot() == 0 else _cs()
	var b: NetSessionNode = _cs() if a == _hs() else _hs()
	a.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": "petalfang"})
	b.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": "bastion"})   # cannot duel: dropped
	a.set_ready(true)
	b.set_ready(true)
	assert_true(await H.wait_until(get_tree(), func(): return a.is_in_match() and b.is_in_match()), "the server auto-starts")
	var cfg := a.get_match_config()
	assert_true(DuelNetConfig.is_duel(cfg), "a duel match")
	assert_eq(DuelNetConfig.unit_of(cfg, 0), "petalfang", "slot 0's pick")
	assert_eq(DuelNetConfig.unit_of(cfg, 1), DuelNetConfig.default_unit(1), "an ineligible pick falls back to the slot default")
	assert_eq(String(cfg.get(DuelNetConfig.KEY_STAGE, "")), "grove", "the server's locked stage")
	assert_eq((cfg["rng_contributors"] as Array).size(), 3, "server + both seats contribute randomness")
	assert_eq(cfg, b.get_match_config(), "both seats got the same config")
	H.free_peer(server)
