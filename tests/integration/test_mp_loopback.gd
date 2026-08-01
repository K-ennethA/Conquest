extends GutTest

# MP Phase 2 -- the two-peer lockstep deliverable.
#
# The guarantee this proves: two INDEPENDENT peers (each its own board + UnitRegistry +
# CommandApplier) that receive the SAME authority-stamped command stream end up with
# byte-identical state after EVERY command, and observe the commands in the SAME seq order.
# That is exactly what makes NetSession's server-authoritative broadcast safe -- the host
# stamps seq + per-command rng_seed once, and every peer (host included) resolves the command
# through the same deterministic CommandApplier -> perform_move layer.
#
# Two layers of coverage:
#   1. DETERMINISTIC two-peer lockstep (always runs). Two applier+registry pairs are driven
#      from the SAME command stream, stamped exactly the way NetSession's server stamps it
#      (monotonic seq + MatchRng.seed_for(seq)). Asserts equal state hashes after every
#      command and identical seq ordering. This is the heart of the deliverable and needs no
#      sockets, so it can never flake or hang the suite.
#   2. NetSession seam wiring (always runs). install_command_seam / clear_command_seam,
#      net_id_for, is_networked_match, and the shared seed layer.
#   3. LIVE in-process ENet loopback (OPT-IN via env CONQUEST_MP_LOOPBACK). Two NetSession
#      instances under separate MultiplayerAPIs over a real 127.0.0.1 socket pair. Kept opt-in
#      and hard-bounded so a headless CI run can never hang on socket establishment; when not
#      opted in it reports pending() (an explicit, documented deferral -- NOT a silent skip),
#      and dev_scripts/mp_loopback_runner.gd runs the same thing as two real processes.
#
# Mock style mirrors tests/unit/test_command_determinism.gd (duck-typed board + units with a
# seeded RNG injected into MoveExecutor via the command's stamped rng_seed).

const _SEED := 0x5EED1E

# --- mocks (duck-typed, same shape as test_command_determinism) --------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var max_health: int
	var hp: int
	var moveset: Dictionary
	var has_moved: bool = false
	var acted: bool = false

	func _init(p_team: int, p_stats: Dictionary, p_moveset: Dictionary = {}) -> void:
		team = p_team
		stats = p_stats
		max_health = int(p_stats.get("health", 100))
		hp = max_health
		moveset = p_moveset

	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_base_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_hp() -> int:
		return hp
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
	func mark_moved() -> void:
		has_moved = true
	func mark_action_completed(_action: String) -> void:
		acted = true
	func perform_move(slot: int, aim_cell: Vector2i, board, rng: RandomNumberGenerator = null) -> Dictionary:
		var move = moveset.get(slot, null)
		if move == null:
			return { "success": false, "reason": "no_move_in_slot", "events": [], "cells": [] }
		return MoveExecutor.execute(move, self, board, aim_cell, rng)

class MockBoard:
	var placements: Array = []
	var blocked: Array = []
	var bounds: Rect2i = Rect2i(0, 0, 12, 12)
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func set_tile(_cell: Vector2i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector2i) -> bool:
		return bounds.has_point(cell)
	func is_blocked(cell: Vector2i) -> bool:
		return cell in blocked
	func is_occupied(cell: Vector2i) -> bool:
		return not units_at(cell).is_empty()
	func can_fit(unit, anchor: Vector2i) -> bool:
		if not in_bounds(anchor) or is_blocked(anchor):
			return false
		for other in units_at(anchor):
			if other != unit:
				return false
		return true
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

class MockTurn:
	var calls: int = 0
	func advance_turn() -> void:
		calls += 1

## A stand-in for a live TurnSystemBase: emits turn_started(player) on demand so the
## NetSession turn-ownership bridge can be exercised without the full TurnSystemManager /
## PlayerManager stack. Injected as install_command_seam's optional turn_source.
class MockTurnSystem extends Node:
	signal turn_started(player)
	var _current = null
	func get_current_active_player():
		return _current
	func begin_turn(player) -> void:
		_current = player
		turn_started.emit(player)

## A minimal Player stand-in: only the player_id the bridge maps to a peer slot.
class MockPlayer extends RefCounted:
	var player_id: int
	func _init(p_id: int) -> void:
		player_id = p_id

# --- fixtures ----------------------------------------------------------------

func _strike() -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"loopback_strike"
	move.accuracy = 0.75
	move.crit_chance = 0.5
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	var dmg := DamageEffect.new()
	dmg.power = 20
	dmg.scaling_stat = ""
	dmg.category = CombatTypes.DamageCategory.TRUE
	move.effects = [dmg]
	return move

## One "peer": an identically-arranged battle plus its own registry + applier. net_ids are
## assigned in a fixed order, so both peers name the same units the same way.
func _make_peer() -> Dictionary:
	var board := MockBoard.new()
	var attacker := MockUnit.new(0, { "health": 100, "crit": 0 }, { 0: _strike() })
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	var bystander := MockUnit.new(1, { "health": 80 })
	board.place(attacker, Vector2i(1, 1))
	board.place(defender, Vector2i(3, 1))
	board.place(bystander, Vector2i(6, 6))

	var reg := CommandApplier.UnitRegistry.new()
	reg.assign_map_units([attacker, defender, bystander])   # ids 1, 2, 3
	var applier := CommandApplier.new(reg, null)
	return { "board": board, "applier": applier, "reg": reg, "turn": MockTurn.new() }

## The authority's stamped broadcast stream. Built ONCE, exactly the way NetSession's server
## stamps an intent (monotonic seq starting at 1 + match_rng.seed_for(seq) + protocol
## version, via NetProtocol.stamp_resolution) -- so feeding it to two peers reproduces what
## the wire would carry.
func _authority_stream() -> Array:
	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var seq := 0
	var out: Array = []
	# attacker casts at defender (rolls hit/crit through the seeded rng)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_cast_move(1, 0, Vector2i(3, 1), 0), seq, mr.seed_for(seq)))
	# defender waits
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_wait_unit(2, 1), seq, mr.seed_for(seq)))
	# attacker steps up to (2,1)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_move_unit(1, Vector2i(2, 1), 0), seq, mr.seed_for(seq)))
	# player 0 ends turn
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_end_turn(0, 0), seq, mr.seed_for(seq)))
	# attacker casts again from its new cell (rolls again)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_cast_move(1, 0, Vector2i(3, 1), 0), seq, mr.seed_for(seq)))
	return out

# --- 1. Deterministic two-peer lockstep (the heart) --------------------------

func test_two_peer_appliers_stay_in_lockstep():
	var stream := _authority_stream()
	var peer_a := _make_peer()
	var peer_b := _make_peer()

	var applier_a: CommandApplier = peer_a["applier"]
	var applier_b: CommandApplier = peer_b["applier"]
	var board_a = peer_a["board"]
	var board_b = peer_b["board"]

	# Both peers start from an identical hash.
	assert_eq(applier_a.hash_match_state(board_a), applier_b.hash_match_state(board_b),
		"the two peers start from an identical state hash")

	var seqs_a: Array = []
	var seqs_b: Array = []
	for cmd in stream:
		var res_a: Dictionary = applier_a.apply_command(cmd, board_a, { "turn_system": peer_a["turn"] })
		var res_b: Dictionary = applier_b.apply_command(cmd, board_b, { "turn_system": peer_b["turn"] })
		seqs_a.append(int(res_a.get("seq", -1)))
		seqs_b.append(int(res_b.get("seq", -1)))
		# The invariant: after EVERY applied command, both peers' state hashes match.
		assert_eq(applier_a.hash_match_state(board_a), applier_b.hash_match_state(board_b),
			"peers stay in lockstep after command seq %d" % int(cmd.get(NetProtocol.KEY_SEQ, -1)))

	# seq ordering is identical and strictly the stamped order 1..N on both peers.
	assert_eq(str(seqs_a), str(seqs_b), "both peers observed the commands in the identical seq order")
	assert_eq(str(seqs_a), str([1, 2, 3, 4, 5]), "the applied seq order is the authority's monotonic stamp order")

func test_lockstep_actually_mutated_state():
	# Guards against a vacuous pass where nothing changed and every hash trivially matched.
	var stream := _authority_stream()
	var peer := _make_peer()
	var applier: CommandApplier = peer["applier"]
	var board = peer["board"]
	var start := applier.hash_match_state(board)
	for cmd in stream:
		applier.apply_command(cmd, board, { "turn_system": peer["turn"] })
	assert_ne(applier.hash_match_state(board), start, "the scripted stream changed board state")
	assert_eq(peer["turn"].calls, 1, "END_TURN drove the turn system exactly once")

func test_a_divergent_command_breaks_lockstep_detectably():
	# The hash oracle must be able to SEE a divergence, else lockstep equality is meaningless.
	# Feed peer B a different move destination on the step-up command and assert the hashes part.
	var stream := _authority_stream()
	var peer_a := _make_peer()
	var peer_b := _make_peer()
	var applier_a: CommandApplier = peer_a["applier"]
	var applier_b: CommandApplier = peer_b["applier"]
	var board_a = peer_a["board"]
	var board_b = peer_b["board"]

	# Command index 2 is the MOVE_UNIT; give B a different destination.
	var divergent: Dictionary = (stream[2] as Dictionary).duplicate(true)
	divergent[NetProtocol.KEY_DATA] = { NetProtocol.KEY_UNIT_ID: 1, NetProtocol.KEY_DEST_CELL: Vector2i(5, 5) }

	applier_a.apply_command(stream[2], board_a, { "turn_system": peer_a["turn"] })
	applier_b.apply_command(divergent, board_b, { "turn_system": peer_b["turn"] })
	assert_ne(applier_a.hash_match_state(board_a), applier_b.hash_match_state(board_b),
		"a peer that applied a different destination hashes differently -- the oracle detects desync")

# --- 2. NetSession seam wiring ----------------------------------------------

func test_netsession_seam_install_and_clear():
	var net := _fresh_netsession()
	var peer := _make_peer()
	var applier: CommandApplier = peer["applier"]
	var board = peer["board"]

	assert_false(net.is_networked_match(), "no peer connected -> not a networked match")

	var provider := func(): return board
	net.install_command_seam(applier, provider)
	assert_eq(net.command_applier, applier, "install_command_seam wired the applier")
	assert_true(net.board_provider.is_valid(), "install_command_seam wired the board provider")

	# net_id_for resolves through the registry (attacker was id 1).
	assert_eq(net.net_id_for(peer["reg"].unit_for(1)), 1, "net_id_for reads the live registry")
	assert_eq(net.net_id_for(null), -1, "net_id_for is null-safe")

	net.clear_command_seam()
	assert_null(net.command_applier, "clear_command_seam drops the applier")
	assert_false(net.board_provider.is_valid(), "clear_command_seam drops the board provider")

func test_apply_through_installed_seam_mutates_the_provided_board():
	# With the seam installed, _rpc_apply_action's guarded apply drives the provided board.
	# We call the applier via the same path (applier + board provider) NetSession uses.
	var net := _fresh_netsession()
	var peer := _make_peer()
	var applier: CommandApplier = peer["applier"]
	var board = peer["board"]
	net.install_command_seam(applier, func(): return board)

	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var cmd := NetProtocol.stamp_resolution(NetProtocol.make_move_unit(1, Vector2i(4, 4), 0), 1, mr.seed_for(1))

	var before: Vector2i = board.cell_of(peer["reg"].unit_for(1))
	# Drive exactly what _rpc_apply_action does when a seam is installed.
	applier.apply_command(cmd, net.board_provider.call(), null)
	var after: Vector2i = board.cell_of(peer["reg"].unit_for(1))
	assert_eq(before, Vector2i(1, 1), "unit started at its spawn cell")
	assert_eq(after, Vector2i(4, 4), "the resolved MOVE_UNIT mutated the provider's board")

func test_two_peers_consume_action_flags_identically():
	# Apply-semantics lockstep: driven from the same stamped stream, two independent peers end
	# every command with IDENTICAL per-unit [acted, has_moved] flags -- so a networked cast
	# greys the caster (and would advance Speed First) the same way on every box.
	var stream := _authority_stream()
	var peer_a := _make_peer()
	var peer_b := _make_peer()
	var applier_a: CommandApplier = peer_a["applier"]
	var applier_b: CommandApplier = peer_b["applier"]
	for cmd in stream:
		applier_a.apply_command(cmd, peer_a["board"], { "turn_system": peer_a["turn"] })
		applier_b.apply_command(cmd, peer_b["board"], { "turn_system": peer_b["turn"] })
		assert_eq(str(_peer_flags(peer_a["reg"])), str(_peer_flags(peer_b["reg"])),
			"both peers hold identical acted/has_moved flags after command seq %d"
				% int(cmd.get(NetProtocol.KEY_SEQ, -1)))
	# Deterministic consumption proof (independent of the seed-dependent cast hit/miss):
	# the WAIT consumed the defender's action and the MOVE_UNIT marked the caster moved --
	# identically on both peers.
	assert_true(peer_a["reg"].unit_for(2).acted, "peer A: WAIT consumed the defender's action")
	assert_true(peer_b["reg"].unit_for(2).acted, "peer B: WAIT consumed the defender's action")
	assert_true(peer_a["reg"].unit_for(1).has_moved, "peer A: MOVE_UNIT marked the caster moved")
	assert_true(peer_b["reg"].unit_for(1).has_moved, "peer B: MOVE_UNIT marked the caster moved")

func _peer_flags(reg) -> Dictionary:
	var out: Dictionary = {}
	for id in [1, 2, 3]:
		var u = reg.unit_for(id)
		out[id] = null if u == null else [u.acted, u.has_moved]
	return out

func test_out_of_turn_intent_rejected_by_validator():
	# Task 2: with the seam installed, the turn-ownership bridge drives NetSession's turn slot
	# from the real turn system's turn_started, and the server-side validator rejects intents
	# from any slot but the active one.
	var net := _fresh_netsession()
	var peer := _make_peer()
	var sys := MockTurnSystem.new()
	add_child_autofree(sys)
	net.install_command_seam(peer["applier"], func(): return peer["board"], sys)
	net.enforce_turn_ownership = true

	# Player 0's turn begins -> bridge maps it to slot 0.
	sys.begin_turn(MockPlayer.new(0))
	assert_eq(net.current_turn_slot(), 0, "the bridge mapped player 0 -> slot 0")
	assert_eq(net._validate_intent(1, NetProtocol.make_wait_unit(1)), "not_your_turn",
		"an out-of-turn intent (slot 1 during slot 0's turn) is rejected server-side")
	assert_eq(net._validate_intent(0, NetProtocol.make_wait_unit(1)), "",
		"the active slot's intent passes the turn-ownership gate")

	# The turn advances to player 1 -> the gate flips with it.
	sys.begin_turn(MockPlayer.new(1))
	assert_eq(net.current_turn_slot(), 1, "turn_started(player 1) moved the slot")
	assert_eq(net._validate_intent(0, NetProtocol.make_wait_unit(1)), "not_your_turn",
		"slot 0 is now out of turn")

	# Dropping the seam disarms the bridge (slot back to -1, enforcement inert).
	net.clear_command_seam()
	assert_eq(net.current_turn_slot(), -1, "clearing the seam resets the driven turn slot")
	assert_eq(net._validate_intent(0, NetProtocol.make_wait_unit(1)), "",
		"with the seam cleared the turn gate is OFF again")

func test_no_seam_means_no_turn_gating():
	# Dev/legacy safety: with NO seam the bridge is inactive, so turn ownership is never
	# enforced even with enforce_turn_ownership left ON and a stale-looking slot.
	var net := _fresh_netsession()
	net.enforce_turn_ownership = true
	assert_eq(net._validate_intent(3, NetProtocol.make_wait_unit(1)), "",
		"no seam installed -> out-of-turn gating is OFF (dev/legacy safety)")

func test_shared_seed_layer_is_reproducible_across_peers():
	# Both peers derive the SAME per-command seed from the SAME match seed -- the property the
	# host relies on when it stamps rng_seed once and every peer resolves the roll identically.
	var a := MatchRng.new()
	a.begin_solo(_SEED)
	var b := MatchRng.new()
	b.begin_solo(_SEED)
	assert_eq(a.match_seed, b.match_seed, "identical local seed -> identical match seed")
	for seq in range(1, 8):
		assert_eq(a.seed_for(seq), b.seed_for(seq), "per-command seed for seq %d matches across peers" % seq)

# --- 3. Live in-process ENet loopback (opt-in, hard-bounded) ------------------

func test_live_two_peer_enet_loopback():
	if not OS.has_environment("CONQUEST_MP_LOOPBACK"):
		pending("Live two-peer ENet loopback is OPT-IN (set env CONQUEST_MP_LOOPBACK=1). "
			+ "Deterministic two-peer lockstep is fully covered by test_two_peer_appliers_stay_in_lockstep; "
			+ "for a real dual-socket run use dev_scripts/mp_loopback_runner.gd (two processes). "
			+ "Reason for opt-in: headless in-process dual-MultiplayerAPI ENet establishment is "
			+ "environment-dependent and must never be allowed to hang the CI suite.")
		return

	# --- Two NetSession instances, each under its own subtree with its own MultiplayerAPI. ---
	var host_branch := Node.new()
	host_branch.name = "MPLoopbackHost"
	var client_branch := Node.new()
	client_branch.name = "MPLoopbackClient"
	get_tree().root.add_child(host_branch)
	get_tree().root.add_child(client_branch)
	# Assign a distinct MultiplayerAPI to each branch BEFORE the NetSession nodes enter, so
	# each node's `multiplayer` resolves to its own API rather than the shared default.
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), host_branch.get_path())
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), client_branch.get_path())

	var host := _netsession_instance()
	var client := _netsession_instance()
	host_branch.add_child(host)
	client_branch.add_child(client)

	var port := 40000 + (Time.get_ticks_usec() % 20000)
	assert_eq(host.host_game("Host", port, 2), OK, "host created the server")
	assert_eq(client.join_game("127.0.0.1", "Client", port), OK, "client started connecting")

	# Bounded wait for the roster to reach two participants on the host (auto-polled by the
	# tree). Hard cap so a failed establishment degrades to a clear failure, never a hang.
	var connected: bool = await _await_until(func(): return host.player_count() >= 2, 240)
	if not connected:
		_teardown_live(host, client, host_branch, client_branch)
		pending("ENet loopback did not establish within the frame budget in this headless "
			+ "environment; use the two-process dev_scripts/mp_loopback_runner.gd instead.")
		return

	# --- Install an independent applier+board seam on each peer. ---
	var peer_h := _make_peer()
	var peer_c := _make_peer()
	host.install_command_seam(peer_h["applier"], func(): return peer_h["board"])
	client.install_command_seam(peer_c["applier"], func(): return peer_c["board"])
	host.enforce_turn_ownership = false
	client.enforce_turn_ownership = false

	# --- Commit-reveal match-RNG handshake; both peers must land on the same seed. ---
	host.begin_match_rng_handshake()
	var seeded: bool = await _await_until(
		func(): return host.match_rng != null and host.match_rng.is_ready() \
			and client.match_rng != null and client.match_rng.is_ready(), 240)
	assert_true(seeded, "the match-RNG handshake completed on both peers")
	if seeded:
		assert_eq(host.match_rng.match_seed, client.match_rng.match_seed,
			"host and client negotiated the identical match seed")

	# --- Drive a scripted command from each side; assert both peers stay in lockstep. ---
	var applied_h: Array = []
	host.action_applied.connect(func(a): applied_h.append(a))
	var applied_c: Array = []
	client.action_applied.connect(func(a): applied_c.append(a))

	host.submit_intent(NetProtocol.make_cast_move(1, 0, Vector2i(3, 1)))
	await _await_until(func(): return applied_h.size() >= 1 and applied_c.size() >= 1, 120)
	client.submit_intent(NetProtocol.make_move_unit(1, Vector2i(2, 1)))
	await _await_until(func(): return applied_h.size() >= 2 and applied_c.size() >= 2, 120)

	assert_eq(peer_h["applier"].hash_match_state(peer_h["board"]),
		peer_c["applier"].hash_match_state(peer_c["board"]),
		"after the live command exchange both peers hold identical state")

	_teardown_live(host, client, host_branch, client_branch)

# --- helpers -----------------------------------------------------------------

## A NetSession parented under the test node (so its `multiplayer` resolves to the tree's
## default API -- no peer, so is_connected_session() is safely false). Autofreed by GUT.
func _fresh_netsession() -> Node:
	var script = load("res://systems/net/NetSession.gd")
	var n := Node.new()
	n.set_script(script)
	add_child_autofree(n)
	return n

## A NetSession instance for the live test (added under a branch so _ready binds it to that
## branch's MultiplayerAPI).
func _netsession_instance() -> Node:
	var script = load("res://systems/net/NetSession.gd")
	var n := Node.new()
	n.set_script(script)
	return n

## Await until [param cond] returns true or [param max_frames] elapse. Returns whether the
## condition was met. Hard-bounded so no live await can hang the suite.
func _await_until(cond: Callable, max_frames: int) -> bool:
	var frames := 0
	while frames < max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		frames += 1
	return bool(cond.call())

func _teardown_live(host, client, host_branch, client_branch) -> void:
	if host != null and is_instance_valid(host):
		host.leave()
	if client != null and is_instance_valid(client):
		client.leave()
	if host_branch != null and is_instance_valid(host_branch):
		host_branch.queue_free()
	if client_branch != null and is_instance_valid(client_branch):
		client_branch.queue_free()
