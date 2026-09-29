extends GutTest

## The ONLINE TURN CLOCK over the real network core (host + client NetSessionNode in ONE
## process, real ENet over 127.0.0.1 -- net_test_harness.gd), with a per-peer copy of the game
## (net_match_fixtures.gd) or a per-peer online duel. Proves: the host opens and broadcasts the
## deadline (seat, budget, remaining) once every peer's battle is attached; on expiry the HOST
## plays the timeout as a normal accepted action on both peers -- Traditional END_TURN, Speed
## First the active unit's WAIT, the duel's pass -- stamped `timeout` and identical (digests);
## a client cannot issue one; a host timing a seat out EARLY is caught; N consecutive
## expiries forfeit; the HUD chip shows the host's countdown on both seats.

const H := preload("res://tests/integration/net_test_harness.gd")
const F := preload("res://tests/integration/net_match_fixtures.gd")
const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

## A short clock for the expiry tests (ms).
const SHORT_MS := 350

var _host: Dictionary = {}
var _client: Dictionary = {}
var _hw: Dictionary = {}
var _cw: Dictionary = {}
var _port: int = 0
var _hb: DuelBattle = null
var _cb: DuelBattle = null


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	F.register_characters()
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")
	_hw = {}
	_cw = {}
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
	CharacterLibrary.clear_cache()
	await H.wait_frames(get_tree(), 2)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


# --- Fixtures -------------------------------------------------------------------------------

## One peer's world (Traditional, or Speed First when [param speed_first]).
func _build_world(parent: Node, seed_value: int, speed_first: bool) -> Dictionary:
	if not speed_first:
		return F.build_world(parent, seed_value)
	var world := Node3D.new()
	world.name = "World"
	parent.add_child(world)
	var map := Node3D.new()
	map.name = "Map"
	world.add_child(map)
	var players: Array = [Player.new(0, "P1"), Player.new(1, "P2")]
	for spec in F.LAYOUT:
		var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
		unit.character_resource = CharacterLibrary.get_character(spec["id"])
		unit.position = BoardAdapter.new(GRID, []).cell_to_world(spec["cell"])
		map.add_child(unit)
		players[spec["owner"]].add_unit(unit)
	var ts := SpeedFirstTurnSystem.new()
	world.add_child(ts)
	for p in players:
		ts.register_player(p)
	ts.start_turn_system()
	var board := BoardAdapter.new(GRID, map)
	var rules := NetGameRules.new(func(): return board, func(): return ts, seed_value)
	rules.assign_initial_ids()
	return {"world": world, "map": map, "players": players, "ts": ts, "board": board, "rules": rules}


func _connect_and_start(final_config: Dictionary = {}) -> bool:
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	if not await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1):
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match(final_config)
	return await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match())


## Start a Conquest match and attach a world on both peers ([param attach_client] false leaves
## the client's battle "still loading").
func _start(speed_first: bool = false, attach_client: bool = true, final_config: Dictionary = {}) -> bool:
	if not await _connect_and_start(final_config):
		return false
	_hw = _build_world(_host["root"], int(_hs().get_match_config()["seed"]), speed_first)
	_cw = _build_world(_client["root"], int(_cs().get_match_config()["seed"]), speed_first)
	await H.wait_frames(get_tree(), 2)
	_hs().attach_game(_hw["rules"])
	if attach_client:
		_cs().attach_game(_cw["rules"])
	return true


func _short_clock(afk: int = 3) -> void:
	_hs().turn_clock_override_ms = SHORT_MS
	_hs().turn_clock_grace_ms = 0
	_hs().afk_limit = afk


## Wait until both peers applied [param seq].
func _both_applied(seq: int, timeout_ms: int = 5000) -> bool:
	var ok: bool = await H.wait_until(get_tree(), func():
		return _hs().last_applied_seq() >= seq and _cs().last_applied_seq() >= seq, timeout_ms)
	await H.wait_frames(get_tree(), 3)
	return ok


func _record_applied(session: NetSessionNode) -> Array:
	var log := []
	session.action_applied.connect(func(a, _r): log.append(a.duplicate(true)))
	return log


# --- Deadline broadcast ------------------------------------------------------------------------

func test_the_host_broadcasts_the_opening_deadline_to_both_seats() -> void:
	assert_true(await _start(), "started")
	var cfg := _cs().get_match_config()
	assert_eq(String(cfg.get(NetTurnClock.CONFIG_PRESET, "")), NetTurnClock.DEFAULT_PRESET, "the match runs the default Standard clock")
	assert_eq(int(cfg.get(NetTurnClock.CONFIG_AFK_LIMIT, -1)), NetTurnClock.DEFAULT_AFK_LIMIT, "the forfeit limit is stamped")
	assert_true(await H.wait_until(get_tree(), func(): return not _cs().turn_clock().is_empty()), "the client hears the clock")
	var hc := _hs().turn_clock()
	var cc := _cs().turn_clock()
	assert_eq(int(hc["slot"]), 0, "the opening side's clock runs (host)")
	assert_eq(int(cc["slot"]), 0, "the same seat on the client")
	assert_eq(String(cc["key"]), String(hc["key"]), "the same timed turn")
	assert_eq(String(cc["kind"]), NetTurnClock.KIND_SIDE, "Traditional clocks the side")
	# Standard: 90s per side + 5s for each of the side's 2 living units.
	assert_eq(int(cc["budget_ms"]), 100000, "the side's budget includes the per-unit allowance")
	assert_between(int(cc["remaining_ms"]), 95000, 100000, "the client counts the host's deadline down")
	assert_eq(_cs().turn_clock_slot(), 0)
	assert_eq(_hs().last_applied_seq(), 0, "opening the clock applies nothing")


func test_the_clock_waits_until_every_seat_has_its_battle_up() -> void:
	assert_true(await _start(false, false), "started (client still loading)")
	await H.wait_frames(get_tree(), 10)
	assert_true(_hs().turn_clock().is_empty(), "no clock while a seat is still loading its battle")
	_cs().attach_game(_cw["rules"])
	assert_true(await H.wait_until(get_tree(), func(): return not _cs().turn_clock().is_empty()),
		"the clock opens once every seat reported its battle attached")


func test_a_new_turn_opens_a_new_clock() -> void:
	assert_true(await _start(), "started")
	assert_true(await H.wait_until(get_tree(), func(): return _cs().turn_clock_slot() == 0))
	var first := String(_cs().turn_clock()["key"])
	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await _both_applied(1), "END_TURN applied")
	assert_true(await H.wait_until(get_tree(), func(): return _cs().turn_clock_slot() == 1), "slot 1's clock runs now")
	assert_ne(String(_cs().turn_clock()["key"]), first, "a fresh timed turn")
	assert_eq(_hs().turn_clock_slot(), 1, "host agrees")


# --- Expiry: the timeout is an accepted action, identical on both peers ------------------------

func test_traditional_expiry_ends_the_turn_identically_on_both_peers() -> void:
	_short_clock()
	assert_true(await _start(), "started")
	var host_log := _record_applied(_hs())
	var client_log := _record_applied(_cs())
	var timed := []
	_cs().turn_timed_out.connect(func(slot, _a, strikes): timed.append([slot, strikes]))
	assert_true(await _both_applied(1, 4000), "the host played the timeout")
	var a: Dictionary = host_log[0]
	assert_eq(int(a[NetProtocol.KEY_TYPE]), NetProtocol.Action.END_TURN, "Traditional timeout = END_TURN")
	assert_true(NetProtocol.is_timeout(a), "stamped as a timeout")
	assert_eq(int(a[NetProtocol.KEY_ACTOR]), 0, "for the seat whose clock ran out")
	assert_eq(client_log[0][NetProtocol.KEY_TYPE], a[NetProtocol.KEY_TYPE], "the client applied the same action")
	assert_true(NetProtocol.is_timeout(client_log[0]), "...stamped the same")
	assert_eq(int(client_log[0][NetProtocol.KEY_SEQ]), 1, "in the normal sequence")
	assert_eq(_hw["rules"].current_turn_slot(), 1, "the turn passed (host)")
	assert_eq(_cw["rules"].current_turn_slot(), 1, "the turn passed (client)")
	assert_eq(_hw["rules"].state_digest(), _cw["rules"].state_digest(), "identical state")
	assert_eq(timed, [[0, 1]], "the client heard slot 0's first strike")
	assert_eq(_cs().turn_clock_strikes(0), 1)


func test_an_own_action_clears_the_strikes() -> void:
	_short_clock()
	assert_true(await _start(), "started")
	assert_true(await _both_applied(1, 4000), "slot 0 timed out")
	assert_eq(_hs().turn_clock_strikes(0), 1)
	# Slot 1 acts before its clock runs out; slot 0's strike stays until IT acts.
	_hs().turn_clock_override_ms = 20000
	await H.wait_frames(get_tree(), 2)
	_cs().submit_intent(NetProtocol.end_turn())
	assert_true(await _both_applied(2), "slot 1 ended its own turn")
	assert_eq(_cs().turn_clock_strikes(1), 0, "an own action is no strike")
	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await _both_applied(3), "slot 0 acted")
	assert_eq(_hs().turn_clock_strikes(0), 0, "slot 0's own action cleared its strike (host)")
	assert_eq(_cs().turn_clock_strikes(0), 0, "...and on the client")


func test_speed_first_expiry_makes_the_active_unit_wait() -> void:
	_short_clock()
	assert_true(await _start(true), "started (Speed First)")
	var ts: SpeedFirstTurnSystem = _hw["ts"]
	var acting := NetUnitIds.id_of(ts.current_acting_unit)
	assert_ne(acting, "", "a unit is acting")
	var slot: int = _hw["rules"].current_turn_slot()
	assert_true(await H.wait_until(get_tree(), func(): return _cs().turn_clock_slot() == slot))
	assert_eq(String(_cs().turn_clock()["kind"]), NetTurnClock.KIND_UNIT, "Speed First clocks the unit")
	assert_eq(int(_cs().turn_clock()["budget_ms"]), SHORT_MS)
	var host_log := _record_applied(_hs())
	var client_log := _record_applied(_cs())
	assert_true(await _both_applied(1, 4000), "the host played the timeout")
	var a: Dictionary = host_log[0]
	assert_eq(int(a[NetProtocol.KEY_TYPE]), NetProtocol.Action.WAIT, "Speed First timeout = the active unit WAITs")
	assert_eq(String(a[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), acting, "the unit whose clock ran out")
	assert_true(NetProtocol.is_timeout(a) and NetProtocol.is_timeout(client_log[0]), "stamped on both peers")
	assert_ne(NetUnitIds.id_of(_hw["ts"].current_acting_unit), acting, "the queue moved on (host)")
	assert_eq(NetUnitIds.id_of(_hw["ts"].current_acting_unit), NetUnitIds.id_of(_cw["ts"].current_acting_unit), "same next unit")
	assert_eq(_hw["rules"].state_digest(), _cw["rules"].state_digest(), "identical state")


# --- Trust: only the host issues timeouts, and never early -------------------------------------

func test_a_client_cannot_issue_a_timeout() -> void:
	assert_true(await _start(), "started")
	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await _both_applied(1), "slot 1's turn")
	var log := _record_applied(_hs())
	# A modified client sends its END_TURN dressed up as a clock timeout (straight to the RPC).
	var forged := NetProtocol.end_turn(1)
	forged[NetProtocol.KEY_TIMEOUT] = true
	forged[NetProtocol.KEY_ACTOR] = 1
	_cs()._my_intents.append(forged.duplicate(true))
	_cs()._rpc_intent.rpc_id(1, forged)
	assert_true(await _both_applied(2), "applied as an ordinary intent")
	assert_false(NetProtocol.is_timeout(log[0]), "the host stripped the client's timeout claim")
	assert_eq(_hs().turn_clock_strikes(1), 0, "no strike for a claimed timeout")
	# And the host's own validator refuses a timeout that is not the rules' canonical one.
	var fake := NetProtocol.wait("1:0")
	fake[NetProtocol.KEY_TIMEOUT] = true
	assert_eq(_hs()._validate(0, fake), NetProtocol.INTENT_TIMEOUT_MISMATCH, "only the canonical timeout is legal")


func test_a_host_timing_a_seat_out_early_is_caught() -> void:
	_hs().debug_premature_timeouts = true
	_hs().turn_clock_override_ms = 8000
	var cheats := []
	var aborts := []
	_cs().cheat_detected.connect(func(_p, reason): cheats.append(reason))
	_cs().match_aborted.connect(func(reason): aborts.append(reason))
	assert_true(await _start(), "started")
	assert_true(await H.wait_until(get_tree(), func(): return aborts.size() > 0, 4000), "the client left")
	assert_eq(cheats, ["premature_timeout"], "an early timeout is caught")
	assert_eq(aborts, ["host_verification_failed"], "and ends the match")
	var n := 0
	for e in get_errors():
		if "host verification FAILED" in str(e.code) or "host verification FAILED" in str(e.rationale):
			e.handled = true
			n += 1
	assert_gt(n, 0, "the client warned")


# --- Anti-AFK ------------------------------------------------------------------------------------

func test_consecutive_expiries_forfeit_the_match() -> void:
	_short_clock(2)
	var host_forfeits := []
	var client_forfeits := []
	var client_opp := []
	var host_opp := []
	var aborts := {"host": [], "client": []}
	_hs().clock_forfeit.connect(func(slot): host_forfeits.append(slot))
	_cs().clock_forfeit.connect(func(slot): client_forfeits.append(slot))
	_hs().opponent_forfeited.connect(func(slot): host_opp.append(slot))
	_cs().opponent_forfeited.connect(func(slot): client_opp.append(slot))
	_hs().match_aborted.connect(func(r): aborts["host"].append(r))
	_cs().match_aborted.connect(func(r): aborts["client"].append(r))
	assert_true(await _start(), "started")
	# Nobody acts: slot 0 strike 1, slot 1 strike 1, then slot 0's 2nd expiry = forfeit.
	assert_true(await H.wait_until(get_tree(), func(): return client_forfeits.size() > 0, 6000), "a seat forfeited on time")
	assert_true(await H.wait_until(get_tree(), func(): return aborts["client"].size() > 0, 3000), "the match ended for the client")
	assert_eq(host_forfeits, [0], "slot 0 (idle twice in a row) forfeits (host)")
	assert_eq(client_forfeits, [0], "...(client)")
	assert_eq(client_opp, [0], "the client (the survivor) sees its opponent forfeit")
	assert_eq(host_opp, [], "the forfeiting seat is not told its opponent forfeited")
	assert_eq(aborts["host"], [NetSessionNode.ABORT_CLOCK_FORFEIT], "host ends the match")
	assert_eq(aborts["client"], [NetSessionNode.ABORT_CLOCK_FORFEIT], "client told why")


func test_afk_limit_zero_never_forfeits() -> void:
	_short_clock(0)
	var forfeits := []
	_hs().clock_forfeit.connect(func(slot): forfeits.append(slot))
	assert_true(await _start(), "started")
	assert_true(await _both_applied(4, 8000), "four timeouts in a row were played out")
	assert_eq(forfeits, [], "no forfeit with the rule off")
	assert_eq(_hs().turn_clock_strikes(0), 2, "strikes still counted")


# --- Presets ------------------------------------------------------------------------------------

func test_the_lobby_preset_sets_the_budget() -> void:
	assert_true(await _start(true, true, {NetTurnClock.CONFIG_PRESET: NetTurnClock.PRESET_RAPID}), "started (Rapid, Speed First)")
	assert_eq(String(_cs().get_match_config()[NetTurnClock.CONFIG_PRESET]), NetTurnClock.PRESET_RAPID, "stamped")
	assert_true(await H.wait_until(get_tree(), func(): return not _cs().turn_clock().is_empty()))
	assert_eq(int(_cs().turn_clock()["budget_ms"]), NetTurnClock.budget_ms(NetTurnClock.PRESET_RAPID, NetTurnClock.KIND_UNIT),
		"Rapid Speed First per-unit clock")
	assert_eq(String(_cs().turn_clock()["preset"]), NetTurnClock.PRESET_RAPID)


func test_a_locked_server_preset_wins_over_the_lobby() -> void:
	_hs().turn_clock_preset = NetTurnClock.PRESET_RELAXED
	_hs().turn_clock_locked = true
	assert_true(await _start(false, true, {NetTurnClock.CONFIG_PRESET: NetTurnClock.PRESET_RAPID}), "started")
	assert_eq(String(_cs().get_match_config()[NetTurnClock.CONFIG_PRESET]), NetTurnClock.PRESET_RELAXED, "the fixed preset")


# --- HUD countdown -------------------------------------------------------------------------------

func test_the_hud_chip_counts_the_host_clock_down_on_both_seats() -> void:
	assert_true(await _start(), "started")
	var mine := TurnTimer.new()
	mine.session = _hs()
	var theirs := TurnTimer.new()
	theirs.session = _cs()
	add_child_autofree(mine)
	add_child_autofree(theirs)
	assert_true(await H.wait_until(get_tree(), func(): return theirs.is_net_mode() and mine.is_net_mode()), "both chips follow the network clock")
	await H.wait_frames(get_tree(), 2)
	assert_true(mine.visible and theirs.visible, "shown on both seats")
	assert_eq(mine.caption_text(), TurnTimer.CAPTION_MINE, "the acting seat reads YOUR TURN")
	assert_eq(theirs.caption_text(), TurnTimer.CAPTION_THEIRS, "the waiting seat reads OPPONENT")
	assert_true(mine.is_own_clock() and not theirs.is_own_clock())
	assert_between(theirs.seconds_left(), 95.0, 100.0, "the countdown follows the host's deadline")
	assert_eq(theirs.readout_text(), NetTurnClock.format_ms(int(ceil(theirs.seconds_left())) * 1000), "M:SS over a minute")
	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await _both_applied(1))
	assert_true(await H.wait_until(get_tree(), func(): return theirs.caption_text() == TurnTimer.CAPTION_MINE), "the client's turn now")
	assert_eq(mine.caption_text(), TurnTimer.CAPTION_THEIRS)


func test_the_hud_chip_turns_urgent_and_flashes_times_up() -> void:
	_short_clock()
	_hs().turn_clock_override_ms = 1500
	assert_true(await _start(), "started")
	var chip := TurnTimer.new()
	chip.session = _cs()
	add_child_autofree(chip)
	assert_true(await H.wait_until(get_tree(), func(): return chip.is_net_mode()))
	await H.wait_frames(get_tree(), 2)
	assert_eq(chip.band(), 2, "under 5s: the urgent band")
	assert_true(await H.wait_until(get_tree(), func(): return chip.caption_text() == TurnTimer.CAPTION_TIMEOUT, 4000),
		"TIME'S UP flashes when the host's timeout lands")
	# The chip never expires anything itself: nothing but the host's one timeout was applied.
	assert_eq(_cs().last_applied_seq(), 1)


# --- Online duel: the timeout passes the acting combatant ----------------------------------------

func _start_duel() -> bool:
	_hs().lobby_mode = NetProtocol.MODE_DUEL
	_cs().lobby_mode = NetProtocol.MODE_DUEL
	if not await _connect_and_start(DuelNetConfig.final_config({0: "vineweave", 1: "gem_knight"}, "meadow", "clear")):
		return false
	_hb = _build_duel(_host, _hs().get_match_config())
	_cb = _build_duel(_client, _cs().get_match_config())
	if _hb == null or _cb == null:
		return false
	_hw = {"rules": DuelNetRules.new(_hb)}
	_cw = {"rules": DuelNetRules.new(_cb)}
	_hs().attach_game(_hw["rules"])
	_cs().attach_game(_cw["rules"])
	await H.wait_frames(get_tree(), 2)
	return true


func _build_duel(peer: Dictionary, cfg: Dictionary) -> DuelBattle:
	var res := DuelNetConfig.build_request(cfg)
	if not bool(res["success"]):
		return null
	var b := DuelBattle.new()
	(peer["root"] as Node).add_child(b)
	if not bool(b.setup(res["request"])["success"]):
		return null
	b.start()
	return b


func test_duel_expiry_passes_the_acting_combatant() -> void:
	_short_clock()
	assert_true(await _start_duel(), "duel started")
	var slot: int = _hw["rules"].current_turn_slot()
	var actor = _hb.current_actor()
	var actor_id := NetUnitIds.id_of(actor)
	assert_true(await H.wait_until(get_tree(), func(): return _cs().turn_clock_slot() == slot))
	assert_eq(String(_cs().turn_clock()["kind"]), NetTurnClock.KIND_ACTION, "the duel clocks each action")
	var hp_before := [_hb.unit_of(0).get_hp(), _hb.unit_of(1).get_hp()]
	var host_log := _record_applied(_hs())
	assert_true(await _both_applied(1, 4000), "the host played the timeout")
	var a: Dictionary = host_log[0]
	assert_eq(int(a[NetProtocol.KEY_TYPE]), NetProtocol.Action.WAIT, "the duel's timeout is a pass")
	assert_eq(String(a[NetProtocol.KEY_DATA][NetProtocol.K_UNIT]), actor_id, "for the acting combatant")
	assert_true(NetProtocol.is_timeout(a))
	assert_eq([_hb.unit_of(0).get_hp(), _hb.unit_of(1).get_hp()], hp_before, "a pass deals nothing")
	assert_eq(_hb.result.commands.size(), 1, "recorded in the duel's command log (host)")
	assert_eq(_cb.result.commands.size(), 1, "...and the client's")
	assert_true(NetProtocol.is_timeout(_cb.result.commands[0]), "recorded as a timeout")
	assert_eq(_hw["rules"].state_digest(), _cw["rules"].state_digest(), "identical duel state")
	# The duel refuses a FREE pass from a seat: only the clock may pass a combatant that can act.
	var free_pass: Dictionary = _hw["rules"].pass_intent()
	var next_slot: int = _hw["rules"].current_turn_slot()
	if not _hb.must_pass(_hb.current_actor()):
		assert_eq(_hw["rules"].validate_intent(free_pass, next_slot), NetProtocol.INTENT_REJECTED_BY_GAME,
			"a seat cannot skip on its own")
		var claimed := free_pass.duplicate(true)
		claimed[NetProtocol.KEY_TIMEOUT] = true
		assert_eq(_hw["rules"].validate_timeout(claimed, next_slot), NetProtocol.INTENT_OK,
			"but it is the canonical timeout the host may issue")
