extends GutTest

## ONLINE PARTY DUELS over the real network core (host + client NetSessionNodes in one process,
## real ENet on 127.0.0.1 -- net_test_harness.gd). The match config carries the FORMAT and each
## seat's TEAM ([DuelNetConfig]); SWITCH and the KO replacement picks are validated intents like
## any move (host + every client) and the digest covers both parties.
##   * a whole 3v3 -- moves, switches, replacement picks -- applies identically on both peers;
##   * illegal switches / picks are refused (not your turn, the other seat's pick, a fainted or
##     fielded member, a move while a pick is pending, Singles has no switching);
##   * a desync on a BENCHED unit is caught at the next checkpoint;
##   * configs are strict (team size, species clause, eligibility, format), and a dedicated
##     `--duel-format trio` server folds both seats' announced teams into the start;
##   * the NetDuelStage prompts the fainted side's seat with the replacement picker.

const H := preload("res://tests/integration/net_test_harness.gd")
const STAGE := preload("res://game/duel/net/NetDuelStage.tscn")

const TEAMS := {0: ["vineweave", "gem_knight", "petalfang"], 1: ["gem_knight", "blightcap", "monster"]}

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
	DuelController.record_profile = false
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
	DuelController.record_profile = true
	CombatServices.match_rng = null
	CombatServices.clear()
	await H.wait_frames(get_tree(), 3)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _connect_and_start(cfg: Dictionary) -> bool:
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	if not await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1):
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match(cfg)
	return await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match())


## Start a Trio match (optionally with weakened side-B leads to force KOs) and attach a duel on
## both peers.
func _start(teams: Dictionary = TEAMS, format_id: String = DuelFormat.TRIO, weaken: bool = true) -> bool:
	var cfg := DuelNetConfig.final_config(teams, "meadow", "clear", DuelFormat.preset(format_id))
	if not await _connect_and_start(cfg):
		return false
	_hb = _build(_host, _hs().get_match_config(), weaken)
	_cb = _build(_client, _cs().get_match_config(), weaken)
	if _hb == null or _cb == null:
		return false
	_hr = DuelNetRules.new(_hb)
	_cr = DuelNetRules.new(_cb)
	_hs().attach_game(_hr)
	_cs().attach_game(_cr)
	await H.wait_frames(get_tree(), 2)
	return true


func _build(peer: Dictionary, cfg: Dictionary, weaken: bool) -> DuelBattle:
	var res := DuelNetConfig.build_request(cfg)
	assert_true(bool(res["success"]), "the config builds a duel (%s)" % String(res["reason"]))
	if not bool(res["success"]):
		return null
	var req: DuelRequest = res["request"]
	if weaken:
		# Identical on both peers (the same edit to the same request): a short, KO-rich fight.
		for c in req.foe_party:
			c.current_hp = 5
	var b := DuelBattle.new()
	(peer["root"] as Node).add_child(b)
	assert_true(bool(b.setup(req)["success"]), "duel set up")
	b.start()
	return b


func _session_for(slot: int) -> NetSessionNode:
	return _hs() if slot == 0 else _cs()


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


# --- Tests --------------------------------------------------------------------------

func test_the_config_carries_the_format_and_both_teams() -> void:
	assert_true(await _start(TEAMS, DuelFormat.TRIO, false), "started")
	var cc := _cs().get_match_config()
	assert_eq(DuelNetConfig.format_of(cc).team_size, 3, "the format rides the config")
	assert_eq(DuelNetConfig.team_of(cc, 0), TEAMS[0], "slot 0's team")
	assert_eq(DuelNetConfig.team_of(cc, 1), TEAMS[1], "slot 1's team")
	for side in 2:
		assert_eq(_hb.team_size(side), 3)
		for i in 3:
			assert_eq(NetUnitIds.id_of(_hb.team(side)[i]["unit"]), NetUnitIds.id_of(_cb.team(side)[i]["unit"]),
				"member ids agree on both peers")
	assert_eq(_hr.state_digest(), _cr.state_digest(), "identical opening digest (parties included)")


func test_a_whole_3v3_with_switches_and_picks_applies_identically() -> void:
	assert_true(await _start(), "started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	var switches := 0
	var picks := 0
	var n := 0
	while not _hb.is_over and n < 200:
		n += 1
		var slot := _hr.current_turn_slot()
		assert_eq(slot, _cr.current_turn_slot(), "both peers agree whose turn it is")
		var session := _session_for(slot)
		var r := _rules_of(session)
		var intent: Dictionary
		if r.battle.has_pending_replacement():
			intent = r.default_intent(slot)
			picks += 1
		else:
			var actor = r.battle.current_actor()
			if switches < 3 and r.battle.can_switch(actor) and n % 3 == 1:
				intent = r.switch_intent(r.battle.usable_bench(slot)[0])
				switches += 1
			else:
				intent = r.default_intent(slot)
		var reason := await _submit(session, intent)
		assert_eq(reason, "", "the seat's legal intent is accepted (action %d: %s)" % [n, str(intent)])
		if reason != "":
			break
		assert_eq(_hr.state_digest(), _cr.state_digest(), "digests agree after action %d" % n)
	assert_true(_hb.is_over and _cb.is_over, "decided on both peers (%d actions)" % n)
	assert_gt(switches, 0, "voluntary switches happened")
	assert_gt(picks, 0, "KO replacement picks happened")
	assert_eq(_hb.result.commands, _cb.result.commands, "the same command log")
	assert_eq(_hb.result.hp_timeline, _cb.result.hp_timeline, "the same HP of every member")
	assert_eq(_hb.result.winner_side, _cb.result.winner_side, "the same winner")
	assert_eq(desyncs, [], "no desync")


func test_illegal_switches_and_picks_are_refused() -> void:
	assert_true(await _start(), "started")
	var slot := _hr.current_turn_slot()
	var mover := _session_for(slot)
	var waiter := _session_for(1 - slot)
	var r := _rules_of(mover)
	assert_eq(await _submit(waiter, NetProtocol.switch_to(DuelBattle.member_id(1 - slot, 1))),
		NetProtocol.INTENT_NOT_YOUR_TURN, "the waiting seat may not switch")
	assert_eq(await _submit(mover, NetProtocol.switch_to(DuelBattle.member_id(slot, 0))),
		NetProtocol.INTENT_ILLEGAL_SWITCH, "the fielded member cannot come in")
	assert_eq(await _submit(mover, NetProtocol.switch_to(DuelBattle.member_id(1 - slot, 1))),
		NetProtocol.INTENT_NOT_YOUR_UNIT, "not the opponent's bench")
	assert_eq(await _submit(mover, NetProtocol.switch_to("0:9")), NetProtocol.INTENT_UNKNOWN_UNIT, "no such member")
	assert_eq(_hs().last_applied_seq(), 0, "nothing applied")
	# Drive until side B's (weakened) lead faints and a pick is pending.
	var n := 0
	while not _hb.has_pending_replacement() and not _hb.is_over and n < 40:
		n += 1
		var s := _hr.current_turn_slot()
		assert_eq(await _submit(_session_for(s), _rules_of(_session_for(s)).default_intent(s)), "")
	assert_true(_hb.has_pending_replacement(), "a KO replacement is pending")
	var pside: int = _hb.pending_replacements()[0]
	var ps := _session_for(pside)
	var other := _session_for(1 - pside)
	var fainted_idx := -1
	for rec in _hb.team(pside):
		if bool(rec["fainted"]):
			fainted_idx = int(rec["index"])
	var before := _hs().last_applied_seq()
	assert_eq(await _submit(other, NetProtocol.use_move(DuelBattle.member_id(1 - pside, 0), 0, Vector3i.ZERO)),
		NetProtocol.INTENT_NOT_YOUR_TURN, "the other seat waits for the pick")
	assert_eq(await _submit(ps, NetProtocol.use_move(DuelBattle.member_id(pside, 0), 0, Vector3i.ZERO)),
		NetProtocol.INTENT_MUST_PICK, "the fainted side must pick first")
	assert_eq(await _submit(ps, _rules_of(ps).replacement_intent(pside, fainted_idx)),
		NetProtocol.INTENT_ILLEGAL_SWITCH, "a fainted member cannot come back")
	assert_eq(_hs().last_applied_seq(), before, "none of it applied")
	assert_eq(await _submit(ps, _rules_of(ps).default_intent(pside)), "", "the legal pick is accepted")
	assert_false(_hb.has_pending_replacement() or _cb.has_pending_replacement(), "resolved on both peers")
	assert_eq(_hr.state_digest(), _cr.state_digest())


func test_singles_online_has_no_switching() -> void:
	assert_true(await _start({0: ["vineweave"], 1: ["gem_knight"]}, DuelFormat.SINGLES, false), "started")
	var slot := _hr.current_turn_slot()
	assert_eq(await _submit(_session_for(slot), NetProtocol.switch_to(DuelBattle.member_id(slot, 1))),
		NetProtocol.INTENT_UNKNOWN_UNIT, "a Singles team has no bench member")
	assert_eq(_hr.validate_intent(NetProtocol.switch_to(DuelBattle.member_id(slot, 0)), slot),
		NetProtocol.INTENT_NO_SWITCHING, "and switching is off")


func test_a_desync_on_a_benched_unit_is_detected() -> void:
	assert_true(await _start(TEAMS, DuelFormat.TRIO, false), "started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	# Corrupt the CLIENT's copy of a BENCHED member behind the protocol's back.
	(_cb.team(1)[2]["unit"] as Unit).take_damage(4)
	var slot := _hr.current_turn_slot()
	assert_eq(await _submit(_session_for(slot), _rules_of(_session_for(slot)).default_intent(slot)), "", "accepted")
	await H.wait_until(get_tree(), func(): return desyncs.size() > 0)
	assert_eq(desyncs.size(), 1, "the party digest caught the benched unit")
	for e in get_errors():
		if "DESYNC" in str(e.code) or "DESYNC" in str(e.rationale):
			e.handled = true


func test_configs_are_strict_about_teams_and_formats() -> void:
	var trio := DuelFormat.preset(DuelFormat.TRIO).to_dict()
	var base := {NetProtocol.CONFIG_MODE: NetProtocol.MODE_DUEL, "seed": 3, DuelNetConfig.KEY_FORMAT: trio}
	var ok := base.duplicate(true)
	ok[DuelNetConfig.KEY_TEAMS] = TEAMS.duplicate(true)
	assert_true(bool(DuelNetConfig.build_request(ok)["success"]), "a legal Trio config")
	var short := base.duplicate(true)
	short[DuelNetConfig.KEY_TEAMS] = {0: ["vineweave", "gem_knight"], 1: TEAMS[1]}
	assert_eq(String(DuelNetConfig.build_request(short)["reason"]), "bad_team_size", "a team of two in a 3v3")
	var twice := base.duplicate(true)
	twice[DuelNetConfig.KEY_TEAMS] = {0: ["vineweave", "vineweave", "petalfang"], 1: TEAMS[1]}
	assert_eq(String(DuelNetConfig.build_request(twice)["reason"]), "species_clause", "a repeat under the clause")
	var bad := base.duplicate(true)
	bad[DuelNetConfig.KEY_TEAMS] = {0: ["vineweave", "bastion", "petalfang"], 1: TEAMS[1]}
	assert_eq(String(DuelNetConfig.build_request(bad)["reason"]), "ineligible_unit", "a unit that cannot duel")
	var path := base.duplicate(true)
	path[DuelNetConfig.KEY_TEAMS] = {0: ["res://evil.tres", "gem_knight", "petalfang"], 1: TEAMS[1]}
	assert_eq(String(DuelNetConfig.build_request(path)["reason"]), "ineligible_unit", "a path is never a unit id")
	var doubles := base.duplicate(true)
	doubles[DuelNetConfig.KEY_FORMAT] = {"id": "custom", "team_size": 3, "active_per_side": 2}
	assert_eq(String(DuelNetConfig.build_request(doubles)["reason"]), "doubles_not_built", "doubles is a follow-up")
	var junk := base.duplicate(true)
	junk[DuelNetConfig.KEY_FORMAT] = {"team_size": "three"}
	assert_eq(String(DuelNetConfig.build_request(junk)["reason"]), "bad_format", "an unreadable format refuses")
	var legacy := {"seed": 9, DuelNetConfig.KEY_UNITS: {0: "petalfang", 1: "gem_knight"}}
	var lres := DuelNetConfig.build_request(legacy)
	assert_true(bool(lres["success"]), "a Singles-era config (no format, one unit each) still builds")
	assert_eq((lres["request"] as DuelRequest).effective_format().team_size, 1)
	var clean := DuelNetConfig.sanitize({DuelNetConfig.KEY_TEAMS: {0: ["vineweave", "bastion", 7]},
		DuelNetConfig.KEY_FORMAT: {"team_size": 99}})
	assert_eq(clean[DuelNetConfig.KEY_TEAMS][0], ["vineweave"], "the sanitiser keeps only eligible ids")
	assert_false(clean.has(DuelNetConfig.KEY_FORMAT), "and drops an invalid format")
	var filled := DuelNetConfig.final_config({0: ["petalfang"], 1: "monster"}, "", "", DuelFormat.preset(DuelFormat.FULL))
	assert_eq((filled[DuelNetConfig.KEY_TEAMS][0] as Array).size(), 6, "final_config fills a short pick to the format")
	assert_eq(filled[DuelNetConfig.KEY_TEAMS][0][0], "petalfang", "the seat's own lead first")
	assert_true(bool(DuelNetConfig.build_request(filled)["success"]), "and the filled config builds")


func test_a_dedicated_trio_server_folds_both_teams_into_the_start() -> void:
	var server := H.make_peer(self, "ServerPeer")
	var srv := DedicatedServer.new()
	(server["root"] as Node).add_child(srv)
	var ss: NetSessionNode = server["session"]
	assert_eq(srv.start(PackedStringArray(["--mode", "duel", "--port", str(_port), "--duel-format", "trio"]), ss), OK,
		"a --duel-format trio server listens")
	assert_eq(DuelNetConfig.format_of(ss.get_match_config()).id, DuelFormat.TRIO, "its lobby plays Trio")
	assert_true(ss.config_locked, "the operator's format is locked")
	for pair in [[_hs(), "A"], [_cs(), "B"]]:
		(pair[0] as NetSessionNode).join_game("127.0.0.1", "Bot" + String(pair[1]), _port)
	assert_true(await H.wait_until(get_tree(), func(): return ss.player_count() == 2 and _hs().local_slot() >= 0 and _cs().local_slot() >= 0),
		"both seated")
	var a: NetSessionNode = _hs() if _hs().local_slot() == 0 else _cs()
	var b: NetSessionNode = _cs() if a == _hs() else _hs()
	a.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": "petalfang", "team": ["petalfang", "monster", "undead", "oakheart"]})
	b.send_lobby_message(DuelNetConfig.MSG_PICK, {"character_id": "bastion", "team": ["bastion", "gem_knight"]})
	a.set_ready(true)
	b.set_ready(true)
	assert_true(await H.wait_until(get_tree(), func(): return a.is_in_match() and b.is_in_match()), "the server auto-starts")
	var cfg := a.get_match_config()
	assert_eq(DuelNetConfig.team_of(cfg, 0), ["petalfang", "monster", "undead"], "slot 0's preference, trimmed to three")
	var t1: Array = DuelNetConfig.team_of(cfg, 1)
	assert_eq(t1.size(), 3, "slot 1 filled to three")
	assert_eq(t1[0], "gem_knight", "the ineligible pick dropped, the rest kept in order")
	assert_true(bool(DuelNetConfig.build_request(cfg)["success"]), "every peer can build it")
	assert_eq(cfg, b.get_match_config(), "both seats got the same config")
	H.free_peer(server)


func test_a_dedicated_server_refuses_an_unknown_format() -> void:
	var server := H.make_peer(self, "ServerPeer")
	var srv := DedicatedServer.new()
	(server["root"] as Node).add_child(srv)
	assert_eq(srv.start(PackedStringArray(["--mode", "duel", "--port", str(_port), "--duel-format", "quad"]),
		server["session"]), ERR_INVALID_PARAMETER, "an unknown format is refused at boot")
	H.free_peer(server)


func test_the_net_stage_prompts_the_fainted_seat_to_pick() -> void:
	var cfg := DuelNetConfig.final_config(TEAMS, "meadow", "clear", DuelFormat.preset(DuelFormat.TRIO))
	assert_true(await _connect_and_start(cfg), "started")
	var hst: NetDuelStage = _net_stage(_host, _hs().get_match_config())
	var cst: NetDuelStage = _net_stage(_client, _cs().get_match_config())
	await H.wait_frames(get_tree(), 3)
	var prompted_pick := false
	var n := 0
	while not (hst.battle.is_over and cst.battle.is_over) and n < 4000:
		n += 1
		await get_tree().process_frame
		for st in [hst, cst]:
			if st.hud.party_open() and st.hud.replacement_side == st.local_slot:
				prompted_pick = true
				assert_true(st.battle.is_pending(st.local_slot), "only the fainted side's seat is asked")
				st.hud.choose_member(st.battle.usable_bench(st.local_slot)[0])
			elif st._prompted and st.hud._accepting:
				var actor = st.battle.current_actor()
				st.hud._choose(st.battle.legal_slots(actor)[0])
	assert_true(hst.battle.is_over and cst.battle.is_over, "decided on both seats")
	assert_true(prompted_pick, "a seat picked its KO replacement on its HUD")
	assert_eq(hst.battle.result.commands, cst.battle.result.commands, "one command log")
	assert_eq(hst.rules.state_digest(), cst.rules.state_digest(), "one final state")


func _net_stage(peer: Dictionary, cfg: Dictionary) -> NetDuelStage:
	var st: NetDuelStage = STAGE.instantiate()
	st.session = peer["session"]
	var req: DuelRequest = DuelNetConfig.build_request(cfg)["request"]
	for c in req.foe_party:
		c.current_hp = 5
	st.net_request = req
	st.instant = true
	(peer["root"] as Node).add_child(st)
	return st
