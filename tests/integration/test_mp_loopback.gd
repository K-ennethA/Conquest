extends GutTest

# MP -- the two-peer lockstep deliverable, on the merged network core.
#
# The guarantee this proves: two INDEPENDENT peers (each its own board + applier) that receive
# the SAME accepted-action stream end up with byte-identical state after EVERY action, and
# observe the actions in the SAME seq order. That is what makes NetSession's host-ordered
# broadcast safe -- every peer (host included) resolves each accepted action through the ONE
# deterministic apply path (NetGameRules.apply_action; CommandApplier is the battle / replay
# seam that extends it) with the action's own seed.
#
# Coverage here:
#   1. DETERMINISTIC two-peer lockstep (no sockets, can never hang). Two appliers driven from
#      the SAME resolved stream (monotonic seq + a per-action seed, via
#      NetProtocol.stamp_resolution). Equal state hashes after every action, identical seq order.
#   2. Validation on the same rules object: an out-of-turn / foreign-unit intent is refused
#      (replaces the retired turn-ownership BRIDGE -- turns are now derived from the rules'
#      turn system on every peer, so the validator reads the turn directly).
#   3. NetSession battle-seam wiring (install / clear, net_id_for) and the lobby transport
#      (the build-gated seating, the lobby-message relay).
#
# The LIVE two-socket loopback that used to be an opt-in test here (plus its two-process
# runner, dev_scripts/mp_loopback_runner.gd) is superseded by the always-on real-ENet suites
# of the merged core -- tests/integration/test_net_match.gd, test_net_rng.gd, test_net_dedicated.gd
# (host + client(s) in one process, full commit-reveal) -- and the multi-process
# dev_scripts/net_multiprocess_check.sh.
#
# Mock style mirrors tests/unit/test_command_determinism.gd (duck-typed board + units with a
# seeded RNG injected into MoveExecutor via the action's stamped seed).

const _SEED := 0x5EED1E

# --- mocks (duck-typed, same shape as test_command_determinism) --------------

class MockUnit:
	var team: int
	var stats: Dictionary
	var max_health: int
	var hp: int
	var moveset: Dictionary
	var has_moved_this_turn: bool = false
	var has_acted_this_turn: bool = false

	func _init(p_team: int, p_stats: Dictionary, p_moveset: Dictionary = {}) -> void:
		team = p_team
		stats = p_stats
		max_health = int(p_stats.get("health", 100))
		hp = max_health
		moveset = p_moveset

	func get_team() -> int:
		return team
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
		has_moved_this_turn = true
	func mark_action_completed(_action: String) -> void:
		has_acted_this_turn = true
	func perform_move(slot: int, aim_cell: Vector3i, board, rng: RandomNumberGenerator = null) -> Dictionary:
		var move = moveset.get(slot, null)
		if move == null:
			return { "success": false, "reason": "no_move_in_slot", "events": [], "cells": [] }
		return MoveExecutor.execute(move, self, board, aim_cell, rng)

class MockBoard:
	var placements: Array = []
	var blocked: Array = []
	var bounds: Rect2i = Rect2i(0, 0, 12, 12)
	func place(unit, cell: Vector3i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector3i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector3i(-999, -999, 0)
	func units_at(cell: Vector3i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(a, b) -> bool:
		return a.team != b.team
	func are_allies(a, b) -> bool:
		return a.team == b.team
	func set_tile(_cell: Vector3i, _tile_id) -> void:
		pass
	func move_unit(unit, to_cell: Vector3i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell
	func in_bounds(cell: Vector3i) -> bool:
		return cell.z == 0 and bounds.has_point(Cells.flat(cell))
	func is_blocked(cell: Vector3i) -> bool:
		return cell in blocked
	func is_occupied(cell: Vector3i) -> bool:
		return not units_at(cell).is_empty()
	func can_fit(unit, anchor: Vector3i) -> bool:
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

## A minimal Player stand-in: only the player_id the rules map to a seat.
class MockPlayer extends RefCounted:
	var player_id: int
	func _init(p_id: int) -> void:
		player_id = p_id

## The turn-system surface the apply / validate path reads: whose turn it is, End Turn, and
## marking a waiting unit as acted.
class MockTurn:
	var calls: int = 0
	var is_active: bool = true
	var active_player = MockPlayer.new(0)
	func end_turn_manually() -> bool:
		calls += 1
		return true
	func can_end_turn_manually() -> bool:
		return true
	func mark_unit_acted(unit) -> void:
		unit.has_acted_this_turn = true
	func get_current_active_player():
		return active_player
	func can_unit_act(unit) -> bool:
		return not unit.has_acted_this_turn

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

## One "peer": an identically-arranged battle plus its own applier. Ids come from the board,
## so both peers name the same units the same way: attacker "0:0", defender "1:0",
## bystander "1:1".
func _make_peer() -> Dictionary:
	var board := MockBoard.new()
	var attacker := MockUnit.new(0, { "health": 100, "crit": 0 }, { 0: _strike() })
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	var bystander := MockUnit.new(1, { "health": 80 })
	board.place(attacker, Vector3i(1, 1, 0))
	board.place(defender, Vector3i(3, 1, 0))
	board.place(bystander, Vector3i(6, 6, 0))

	var turn := MockTurn.new()
	var applier := CommandApplier.new(null, null, func(): return board, func(): return turn)
	applier.assign_initial_ids()
	return { "board": board, "applier": applier, "turn": turn }

## The accepted-action stream, built ONCE with monotonic seqs from 1 and a per-action seed
## -- exactly what every peer holds after NetSession's commit-reveal round for each action.
func _authority_stream() -> Array:
	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var seq := 0
	var out: Array = []
	# attacker casts at defender (rolls hit/crit through the seeded rng)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_cast_move("0:0", 0, Vector3i(3, 1, 0), 0), seq, mr.seed_for(seq)))
	# defender waits
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_wait_unit("1:0", 1), seq, mr.seed_for(seq)))
	# attacker steps up to (2,1)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_move_unit("0:0", Vector3i(2, 1, 0), 0), seq, mr.seed_for(seq)))
	# player 0 ends turn
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_end_turn(0, 0), seq, mr.seed_for(seq)))
	# attacker casts again from its new cell (rolls again)
	seq += 1
	out.append(NetProtocol.stamp_resolution(NetProtocol.make_cast_move("0:0", 0, Vector3i(3, 1, 0), 0), seq, mr.seed_for(seq)))
	return out

func after_each():
	# The apply path installs each action's generator as CombatServices.match_rng.
	if CombatServices != null:
		CombatServices.match_rng = null

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
		var res_a: Dictionary = applier_a.apply_command(cmd.duplicate(true), board_a)
		var res_b: Dictionary = applier_b.apply_command(cmd.duplicate(true), board_b)
		seqs_a.append(int(res_a.get("seq", -1)))
		seqs_b.append(int(res_b.get("seq", -1)))
		# The invariant: after EVERY applied action, both peers' state hashes match.
		assert_eq(applier_a.hash_match_state(board_a), applier_b.hash_match_state(board_b),
			"peers stay in lockstep after action seq %d" % int(cmd.get(NetProtocol.KEY_SEQ, -1)))

	# seq ordering is identical and strictly the stamped order 1..N on both peers.
	assert_eq(str(seqs_a), str(seqs_b), "both peers observed the actions in the identical seq order")
	assert_eq(str(seqs_a), str([1, 2, 3, 4, 5]), "the applied seq order is the host's monotonic order")

func test_lockstep_actually_mutated_state():
	# Guards against a vacuous pass where nothing changed and every hash trivially matched.
	var stream := _authority_stream()
	var peer := _make_peer()
	var applier: CommandApplier = peer["applier"]
	var board = peer["board"]
	var start := applier.hash_match_state(board)
	for cmd in stream:
		applier.apply_command(cmd, board)
	assert_ne(applier.hash_match_state(board), start, "the scripted stream changed board state")
	assert_eq(peer["turn"].calls, 1, "END_TURN drove the turn system exactly once")

func test_a_divergent_command_breaks_lockstep_detectably():
	# The hash oracle must be able to SEE a divergence, else lockstep equality is meaningless.
	# Feed peer B a different move destination on the step-up action and assert the hashes part.
	var stream := _authority_stream()
	var peer_a := _make_peer()
	var peer_b := _make_peer()
	var applier_a: CommandApplier = peer_a["applier"]
	var applier_b: CommandApplier = peer_b["applier"]
	var board_a = peer_a["board"]
	var board_b = peer_b["board"]

	# Action index 2 is the MOVE; give B a different destination.
	var divergent: Dictionary = (stream[2] as Dictionary).duplicate(true)
	divergent[NetProtocol.KEY_DATA] = { NetProtocol.KEY_UNIT_ID: "0:0", NetProtocol.KEY_DEST_CELL: [5, 5, 0] }

	applier_a.apply_command(stream[2], board_a)
	applier_b.apply_command(divergent, board_b)
	assert_ne(applier_a.hash_match_state(board_a), applier_b.hash_match_state(board_b),
		"a peer that applied a different destination hashes differently -- the oracle detects desync")

func test_two_peers_consume_action_flags_identically():
	# Apply-semantics lockstep: driven from the same stream, two independent peers end every
	# action with IDENTICAL per-unit [acted, has_moved] flags -- so a networked cast greys the
	# caster (and would advance Speed First) the same way on every box.
	var stream := _authority_stream()
	var peer_a := _make_peer()
	var peer_b := _make_peer()
	var applier_a: CommandApplier = peer_a["applier"]
	var applier_b: CommandApplier = peer_b["applier"]
	for cmd in stream:
		applier_a.apply_command(cmd.duplicate(true), peer_a["board"])
		applier_b.apply_command(cmd.duplicate(true), peer_b["board"])
		assert_eq(str(_peer_flags(peer_a["board"])), str(_peer_flags(peer_b["board"])),
			"both peers hold identical acted/has_moved flags after action seq %d"
				% int(cmd.get(NetProtocol.KEY_SEQ, -1)))
	# Deterministic consumption proof (independent of the seed-dependent cast hit/miss):
	# the WAIT consumed the defender's action and the MOVE marked the caster moved --
	# identically on both peers.
	for peer in [peer_a, peer_b]:
		assert_true(NetUnitIds.find(peer["board"], "1:0").has_acted_this_turn, "WAIT consumed the defender's action")
		assert_true(NetUnitIds.find(peer["board"], "0:0").has_moved_this_turn, "MOVE marked the caster moved")

func _peer_flags(board) -> Dictionary:
	var out: Dictionary = {}
	for id in ["0:0", "1:0", "1:1"]:
		var u = NetUnitIds.find(board, id)
		out[id] = null if u == null else [u.has_acted_this_turn, u.has_moved_this_turn]
	return out

func test_shared_seed_layer_is_reproducible_across_peers():
	# The solo / replay stream: both peers derive the SAME per-action seed from the SAME match
	# seed (in network play each accepted action carries its own commit-reveal seed instead).
	var a := MatchRng.new()
	a.begin_solo(_SEED)
	var b := MatchRng.new()
	b.begin_solo(_SEED)
	assert_eq(a.match_seed, b.match_seed, "identical local seed -> identical match seed")
	for seq in range(1, 8):
		assert_eq(a.seed_for(seq), b.seed_for(seq), "per-action seed for seq %d matches across peers" % seq)

# --- 2. Validation reads the turn from the rules' own turn system -------------

func test_out_of_turn_intent_rejected_by_the_rules():
	# Replaces the retired turn-ownership bridge: every peer derives whose turn it is from the
	# same turn system the rules read, so the host's validator (re-run by every client) gates
	# directly on it.
	var peer := _make_peer()
	var rules: CommandApplier = peer["applier"]
	var turn: MockTurn = peer["turn"]

	turn.active_player = MockPlayer.new(0)
	assert_eq(rules.current_turn_slot(), 0, "player 0 is the active seat")
	assert_eq(rules.validate_intent(NetProtocol.wait("1:0"), 1), NetProtocol.INTENT_NOT_YOUR_TURN,
		"slot 1 acting during slot 0's turn is rejected")
	assert_eq(rules.validate_intent(NetProtocol.wait("1:0"), 0), NetProtocol.INTENT_NOT_YOUR_UNIT,
		"the active seat still cannot command the other seat's unit")

	turn.active_player = MockPlayer.new(1)
	assert_eq(rules.validate_intent(NetProtocol.wait("1:0"), 1), NetProtocol.INTENT_OK,
		"once the turn passes to slot 1 its own unit may act")
	assert_eq(rules.validate_intent(NetProtocol.end_turn(), 0), NetProtocol.INTENT_NOT_YOUR_TURN,
		"and slot 0 is now out of turn")

# --- 3. NetSession battle seam + lobby transport -------------------------------

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

	# net_id_for reads the unit's NetUnitIds name (attacker is "0:0").
	assert_eq(net.net_id_for(NetUnitIds.find(board, "0:0")), "0:0", "net_id_for names the unit")
	assert_eq(net.net_id_for(null), "", "net_id_for is null-safe")

	net.begin_solo_match_rng()
	assert_eq(applier.match_rng, net.match_rng, "a solo stream is handed to the installed applier")

	net.clear_command_seam()
	assert_null(net.command_applier, "clear_command_seam drops the applier")
	assert_false(net.board_provider.is_valid(), "clear_command_seam drops the board provider")

func test_apply_through_installed_seam_mutates_the_provided_board():
	# Replay playback drives the installed seam exactly like this (ReplayDriver ->
	# NetSession.command_applier.apply_command(cmd, board)).
	var net := _fresh_netsession()
	var peer := _make_peer()
	var applier: CommandApplier = peer["applier"]
	var board = peer["board"]
	net.install_command_seam(applier, func(): return board)

	var mr := MatchRng.new()
	mr.begin_solo(_SEED)
	var cmd := NetProtocol.stamp_resolution(NetProtocol.make_move_unit("0:0", Vector3i(4, 4, 0), 0), 1, mr.seed_for(1))

	var unit = NetUnitIds.find(board, "0:0")
	var before: Vector3i = board.cell_of(unit)
	net.command_applier.apply_command(cmd, net.board_provider.call(), null)
	var after: Vector3i = board.cell_of(unit)
	assert_eq(before, Vector3i(1, 1, 0), "unit started at its spawn cell")
	assert_eq(after, Vector3i(4, 4, 0), "the resolved MOVE mutated the provider's board")

# What these pin: Host/Join run on NetSession, so the ROSTER (after the build gate) is what
# seats a joiner; and the lobby channel delivers to the OTHER participants only. Only the host
# half is exercised (a bound socket, no dialling), so nothing can hang.

func test_host_plus_join_hello_seats_the_joiner():
	var session := _open_host()
	if session.is_empty():
		return  # _open_host already reported why.
	var host = session["host"]

	assert_eq(host.player_count(), 1, "the host occupies slot 0 the moment it hosts")
	assert_false(host.is_networked_match(), "a lone host is not a networked match")

	# A joining peer's FIRST message is the hello the build gate runs on; admitting it is
	# what seats the peer. (The RPC wrapper only supplies the sender id.)
	host._server_admit_peer(2, NetProtocol.make_hello("Client"))

	assert_eq(host.player_count(), 2, "the admitted peer took a roster slot")
	var slots: Array = []
	for pid in host.get_roster():
		slots.append(int(host.get_roster()[pid]["slot"]))
	slots.sort()
	assert_eq(str(slots), str([0, 1]), "slots are 0 (host) and 1 (joiner)")
	assert_eq(host.get_roster()[2]["name"], "Client", "the roster carries the joiner's name")
	assert_false(host.is_networked_match(),
		"a full LOBBY is not yet a match -- start_match's commit round makes it one")
	host.state = NetSessionNode.State.IN_MATCH
	assert_true(host.is_networked_match(),
		"host + one seated peer IN A MATCH is a networked match -- the gate the battle UI reads "
		+ "to route commands through NetSession instead of resolving them locally")

	_close_host(session)

# NOTE: the REFUSAL half of the gate (a protocol-mismatched hello never taking a slot) is
# pinned purely in tests/unit/test_net_handshake.gd against NetProtocol.validate_hello, and
# over real sockets by the lobby-full / match-in-progress tests in test_net_lobby.gd.

func test_lobby_message_relay_reaches_others_and_never_the_sender():
	# The lobby's votes / ready flags / profile + loadout cards ride this channel. It must
	# deliver to the OTHER participants and never echo the sender, so a lobby can broadcast
	# unconditionally without filtering its own traffic back out.
	var session := _open_host()
	if session.is_empty():
		return
	var host = session["host"]
	host._server_admit_peer(2, NetProtocol.make_hello("Client"))

	var seen: Array = []
	host.lobby_message.connect(func(t, d, s): seen.append({"type": t, "data": d, "slot": s}))

	# A client's message is relayed; the listen-server host is a participant, so it lands here.
	host._server_relay_lobby_message(2, "map_vote", {"player_name": "Client", "map_path": "res://m.tres"})
	assert_eq(seen.size(), 1, "the host received the client's lobby message")
	assert_eq(seen[0]["type"], "map_vote", "the message type survived the relay")
	assert_eq(seen[0]["slot"], 1, "the sender's roster slot is reported alongside it")
	assert_eq(str(seen[0]["data"].get("map_path", "")), "res://m.tres", "the payload survived the relay")

	# The host's OWN message is fanned out to the clients but never delivered back to itself.
	host._server_relay_lobby_message(host.local_peer_id(), "player_ready", {"player_name": "Host"})
	assert_eq(seen.size(), 1, "a participant never receives its own lobby message back")

	_close_host(session)

## Bind a NetSession listen server under its own MultiplayerAPI branch. No dialling, so this
## completes immediately. Returns {} (after reporting pending) when the socket cannot be
## bound in this environment, so a locked-down box degrades to an explicit deferral.
func _open_host() -> Dictionary:
	var branch := Node.new()
	branch.name = "MPLobbyHost%d" % (Time.get_ticks_usec() % 100000)
	get_tree().root.add_child(branch)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var host := _netsession_instance()
	branch.add_child(host)

	var port: int = 40000 + (Time.get_ticks_usec() % 20000)
	var err: int = host.host_game("Host", port, 2)
	if err != OK:
		host.leave()
		branch.free()
		pending("Could not bind a local ENet server socket in this environment (%s). "
			% error_string(err)
			+ "The roster/relay rules are transport-independent; this test only needs a bound "
			+ "listen socket so is_connected_session() can be true.")
		return {}
	return { "host": host, "branch": branch }

func _close_host(session: Dictionary) -> void:
	var host = session.get("host", null)
	if host != null and is_instance_valid(host):
		host.leave()
	var branch = session.get("branch", null)
	if branch != null and is_instance_valid(branch):
		get_tree().set_multiplayer(null, branch.get_path())
		branch.free()

# --- helpers -----------------------------------------------------------------

## A NetSession parented under the test node (so its `multiplayer` resolves to the tree's
## default API -- no peer, so is_connected_session() is safely false). Autofreed by GUT.
func _fresh_netsession() -> Node:
	var script = load("res://systems/net/NetSession.gd")
	var n := Node.new()
	n.set_script(script)
	add_child_autofree(n)
	return n

## A NetSession instance for a branch with its own MultiplayerAPI (added under the branch so
## _ready binds it to that branch's API).
func _netsession_instance() -> Node:
	var script = load("res://systems/net/NetSession.gd")
	var n := Node.new()
	n.set_script(script)
	return n
