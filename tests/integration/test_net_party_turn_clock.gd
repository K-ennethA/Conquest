extends GutTest

## PARTY DUELS x the ONLINE TURN CLOCK (host + client NetSessionNodes in one process, real ENet
## on 127.0.0.1 -- net_test_harness.gd). The integration of the two features:
##   * a pending KO replacement pick gets its OWN clock (kind "pick", its own key and budget);
##   * a clock expiry during that pick AUTO-PICKS the seat's first healthy benched member in team
##     order -- a host-issued SWITCH stamped timeout, applied identically on both peers (same
##     member fielded, same digest, same command log) and counted as a strike;
##   * an ACTION expiry in a party duel still PASSES (no damage), never the first legal move;
##   * a real SWITCH (or the seat's own pick) resets that seat's strikes;
##   * a pick dressed up as a timeout that is not the canonical auto-pick is refused.

const H := preload("res://tests/integration/net_test_harness.gd")

const TEAMS := {0: ["vineweave", "gem_knight", "petalfang"], 1: ["gem_knight", "blightcap", "monster"]}
## The pick clock in the expiry test (ms): long enough to inspect it, short enough to expire.
const PICK_MS := 1500
## A clock nobody runs out of while the test drives the seats.
const LONG_MS := 20000
## A clock that expires at once (the action-expiry test).
const SHORT_MS := 350

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


func _session_for(slot: int) -> NetSessionNode:
	return _hs() if slot == 0 else _cs()


func _rules_of(session: NetSessionNode) -> DuelNetRules:
	return _hr if session == _hs() else _cr


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


## A Trio match on both peers ([param weaken]: side B's members start on 5 HP, so KOs come fast).
func _start(weaken: bool) -> bool:
	var cfg := DuelNetConfig.final_config(TEAMS, "meadow", "clear", DuelFormat.preset(DuelFormat.TRIO))
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
		for c in req.foe_party:
			c.current_hp = 5
	var b := DuelBattle.new()
	(peer["root"] as Node).add_child(b)
	assert_true(bool(b.setup(req)["success"]), "duel set up")
	b.start()
	return b


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


func _record_applied(session: NetSessionNode) -> Array:
	var log := []
	session.action_applied.connect(func(a, _r): log.append(a.duplicate(true)))
	return log


func _fielded(b: DuelBattle, side: int) -> String:
	return NetUnitIds.id_of(b.unit_of(side)) if b.unit_of(side) != null else ""


# --- Pure: the pick kind ------------------------------------------------------------------------

func test_the_pick_kind_has_its_own_budget_and_wording() -> void:
	assert_eq(NetTurnClock.budget_ms(NetTurnClock.PRESET_STANDARD, NetTurnClock.KIND_PICK), 15000, "Standard: 15s per KO pick")
	assert_eq(NetTurnClock.budget_ms(NetTurnClock.PRESET_RAPID, NetTurnClock.KIND_PICK, 6), 10000,
		"no per-unit allowance on a pick")
	assert_lt(NetTurnClock.budget_ms(NetTurnClock.PRESET_RELAXED, NetTurnClock.KIND_PICK),
		NetTurnClock.budget_ms(NetTurnClock.PRESET_RELAXED, NetTurnClock.KIND_ACTION), "a pick is shorter than an action")
	var auto := NetProtocol.switch_to("1:1")
	auto[NetProtocol.KEY_TIMEOUT] = true
	assert_string_contains(NetTurnClock.describe_timeout(auto, true), "auto-picked")
	assert_string_contains(NetTurnClock.describe(NetTurnClock.PRESET_STANDARD), "15s per KO pick")


# --- A timeout during a pending KO pick auto-picks, identically on both peers --------------------

func test_a_timeout_during_a_pending_ko_pick_auto_picks_identically_on_both_peers() -> void:
	_hs().turn_clock_override_ms = LONG_MS
	_hs().turn_clock_grace_ms = 0
	# Decide each new clock's budget as the state settles (before the host opens it): the pick
	# clock expires, action clocks never do while the test drives the seats.
	_hs().action_applied.connect(func(_a, _r):
		_hs().turn_clock_override_ms = PICK_MS if _hb != null and _hb.has_pending_replacement() else LONG_MS)
	assert_true(await _start(true), "started (Trio, side B weakened)")
	var host_log := _record_applied(_hs())
	var client_log := _record_applied(_cs())
	var timed := []
	_cs().turn_timed_out.connect(func(slot, a, strikes): timed.append([slot, int(a[NetProtocol.KEY_TYPE]), strikes]))
	var n := 0
	while not _hb.has_pending_replacement() and not _hb.is_over and n < 40:
		n += 1
		var slot := _hr.current_turn_slot()
		var s := _session_for(slot)
		assert_eq(await _submit(s, _rules_of(s).default_intent(slot)), "", "the seat's move is accepted")
	assert_true(_hb.has_pending_replacement() and _cb.has_pending_replacement(), "a KO replacement is pending on both peers")
	var side: int = _hb.pending_replacements()[0]
	assert_eq(_hr.current_turn_slot(), side, "the fainted side's seat is on the clock")
	# The pick has its own timed turn.
	assert_true(await H.wait_until(get_tree(), func():
		return String(_cs().turn_clock().get("kind", "")) == NetTurnClock.KIND_PICK, 3000), "a PICK clock opened")
	var clock := _cs().turn_clock()
	assert_eq(int(clock["slot"]), side, "for the picking seat")
	assert_eq(String(clock["key"]), _cr.clock_turn_key(), "keyed like the rules say")
	assert_true(String(clock["key"]).begins_with("pick:%d:" % side), "a pick key")
	assert_eq(int(clock["budget_ms"]), PICK_MS)
	# The canonical auto-pick: first healthy benched member in team order, the same on both peers.
	var expected: int = _hb.usable_bench(side)[0]
	assert_eq(_hr.auto_pick_index(side), expected)
	assert_eq(_cr.auto_pick_index(side), expected, "the client derives the same member")
	var canon := _hr.timeout_action(side)
	assert_eq(int(canon[NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH, "a pick timeout is a SWITCH")
	assert_eq(String(canon[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), DuelBattle.member_id(side, expected))
	assert_eq(_hr.timeout_action(1 - side), {}, "the other seat has no timeout now")
	var claimed := canon.duplicate(true)
	claimed[NetProtocol.KEY_TIMEOUT] = true
	assert_eq(_cr.validate_timeout(claimed, side), NetProtocol.INTENT_OK, "the client accepts the canonical auto-pick")
	var other: Array = _hb.usable_bench(side)
	if other.size() > 1:
		var forged := _hr.replacement_intent(side, int(other[1]))
		forged[NetProtocol.KEY_TIMEOUT] = true
		assert_eq(_cr.validate_timeout(forged, side), NetProtocol.INTENT_TIMEOUT_MISMATCH,
			"a free pick dressed up as a timeout is refused")
	var before := _hs().last_applied_seq()
	# Nobody picks: the host's clock runs out and plays the auto-pick.
	assert_true(await H.wait_until(get_tree(), func():
		return _hs().last_applied_seq() > before and _cs().last_applied_seq() > before, 5000), "the host played the timeout")
	await H.wait_frames(get_tree(), 3)
	var a: Dictionary = host_log[host_log.size() - 1]
	var c: Dictionary = client_log[client_log.size() - 1]
	assert_eq(int(a[NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH, "the timeout is the auto-pick SWITCH")
	assert_true(NetProtocol.is_timeout(a) and NetProtocol.is_timeout(c), "stamped timeout on both peers")
	assert_eq(int(a[NetProtocol.KEY_ACTOR]), side, "in the picking seat")
	assert_eq(String(a[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), DuelBattle.member_id(side, expected), "the first healthy member in team order")
	assert_eq(c[NetProtocol.KEY_DATA], a[NetProtocol.KEY_DATA], "the client applied the same pick")
	assert_eq(int(c[NetProtocol.KEY_SEQ]), int(a[NetProtocol.KEY_SEQ]), "at the same seq")
	assert_false(_hb.has_pending_replacement() or _cb.has_pending_replacement(), "the pick resolved on both peers")
	assert_eq(_fielded(_hb, side), DuelBattle.member_id(side, expected), "the auto-picked member is fielded (host)")
	assert_eq(_fielded(_cb, side), _fielded(_hb, side), "...and on the client")
	assert_eq(_hb.result.commands, _cb.result.commands, "the same command log")
	assert_true(NetProtocol.is_timeout(_cb.result.commands[_cb.result.commands.size() - 1]), "recorded as a timeout")
	assert_eq(_hr.state_digest(), _cr.state_digest(), "identical digest (parties included)")
	assert_eq(timed, [[side, NetProtocol.Action.SWITCH, 1]], "the client heard one timed-out pick: a strike")
	assert_eq(_hs().turn_clock_strikes(side), 1, "the auto-pick counts as a strike (host)")
	assert_eq(_cs().turn_clock_strikes(side), 1, "...(client)")
	# After the pick, the next action gets a fresh ACTION clock.
	assert_true(await H.wait_until(get_tree(), func():
		return String(_cs().turn_clock().get("kind", "")) == NetTurnClock.KIND_ACTION, 3000), "an action clock follows the pick")
	assert_eq(int(_cs().turn_clock()["budget_ms"]), LONG_MS, "with the action budget")


# --- An action expiry still passes; a real SWITCH resets the strikes ------------------------------

func test_an_action_timeout_passes_and_a_switch_resets_the_strikes() -> void:
	_hs().turn_clock_override_ms = SHORT_MS
	_hs().turn_clock_grace_ms = 0
	# Only the very first action clock is short: after the first timeout every clock is long.
	_hs().action_applied.connect(func(_a, _r): _hs().turn_clock_override_ms = LONG_MS)
	assert_true(await _start(false), "started (Trio)")
	var host_log := _record_applied(_hs())
	var idle: int = _hr.current_turn_slot()
	var idle_actor := _fielded(_hb, idle)
	var hp_before := [_hb.unit_of(0).get_hp(), _hb.unit_of(1).get_hp()]
	assert_true(await H.wait_until(get_tree(), func():
		return _hs().last_applied_seq() >= 1 and _cs().last_applied_seq() >= 1, 4000), "the first action timed out")
	await H.wait_frames(get_tree(), 3)
	var t: Dictionary = host_log[0]
	assert_eq(int(t[NetProtocol.KEY_TYPE]), NetProtocol.Action.WAIT, "a party duel's action timeout is a PASS")
	assert_eq(String(t[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), idle_actor, "of the acting combatant")
	assert_true(NetProtocol.is_timeout(t))
	assert_eq([_hb.unit_of(0).get_hp(), _hb.unit_of(1).get_hp()], hp_before, "the idle seat dealt no damage")
	assert_eq(_hs().turn_clock_strikes(idle), 1, "one strike")
	assert_eq(_cs().turn_clock_strikes(idle), 1)
	# Play on until the idle seat's next turn, and SWITCH there.
	var n := 0
	var switched := false
	while not _hb.is_over and n < 20:
		n += 1
		var slot := _hr.current_turn_slot()
		var s := _session_for(slot)
		var r := _rules_of(s)
		if slot == idle and not _hb.has_pending_replacement() and _hb.can_switch(_hb.current_actor()):
			assert_eq(_hs().turn_clock_strikes(idle), 1, "the strike stands until the seat acts")
			var sw := r.switch_intent(_hb.usable_bench(idle)[0])
			assert_eq(await _submit(s, sw), "", "the switch is accepted")
			switched = true
			break
		assert_eq(await _submit(s, r.default_intent(slot)), "", "the other seat's move is accepted")
	assert_true(switched, "the idle seat switched on its next turn")
	var last: Dictionary = host_log[host_log.size() - 1]
	assert_eq(int(last[NetProtocol.KEY_TYPE]), NetProtocol.Action.SWITCH, "a real SWITCH")
	assert_false(NetProtocol.is_timeout(last), "not a timeout")
	assert_eq(_hs().turn_clock_strikes(idle), 0, "a real SWITCH resets the strikes (host)")
	assert_eq(_cs().turn_clock_strikes(idle), 0, "...(client)")
	assert_eq(_hr.state_digest(), _cr.state_digest(), "identical state")
