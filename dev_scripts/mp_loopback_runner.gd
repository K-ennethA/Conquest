extends SceneTree

# Manual two-PROCESS MP loopback runner (real ENet sockets).
#
# The in-suite test (tests/integration/test_mp_loopback.gd) proves two-peer lockstep
# deterministically in one process; this script proves the SAME thing over a real socket pair
# by running as two separate OS processes. Use it whenever you want to eyeball the live
# NetSession -> CommandApplier path end to end.
#
# HOW TO RUN (two terminals, from the project root):
#
#   Terminal 1 (host):
#     godot --headless --script res://dev_scripts/mp_loopback_runner.gd -- host
#
#   Terminal 2 (client, within a few seconds):
#     godot --headless --script res://dev_scripts/mp_loopback_runner.gd -- client
#
# Optional 3rd arg = port (default 8917):
#     ... -- host 9001      /      ... -- client 9001
#
# EXPECTED: both processes print "MATCH SEED = <same number>" and, after the scripted
# command exchange, "STATE HASH = <same number>". Equal seeds + equal hashes on both sides =
# the peers are in lockstep. Each process exits 0 on success, 1 on failure/timeout.

const NetSessionScript := preload("res://systems/net/NetSession.gd")
const NetProtocolScript := preload("res://systems/net/NetProtocol.gd")
const CommandApplierScript := preload("res://systems/net/CommandApplier.gd")

const DEFAULT_PORT := 8917
const MAX_WAIT_FRAMES := 600   # ~10s at 60fps-equivalent idle ticks

# --- duck-typed board + unit (no MoveExecutor dependency; MOVE/WAIT only) -----

class MockUnit:
	var hp: int = 100
	var max_health: int = 100
	var moved: bool = false
	var acted: bool = false
	func get_hp() -> int: return hp
	func mark_moved() -> void: moved = true
	func mark_action_completed(_a: String) -> void: acted = true

class MockBoard:
	var placements: Array = []
	func place(u, c: Vector2i) -> void: placements.append({ "unit": u, "cell": c })
	func cell_of(u) -> Vector2i:
		for p in placements:
			if p.unit == u: return p.cell
		return Vector2i(-999, -999)
	func move_unit(u, to: Vector2i) -> void:
		for p in placements:
			if p.unit == u: p.cell = to

var _net: Node
var _applier
var _board: MockBoard
var _role: String = "host"
var _port: int = DEFAULT_PORT
var _applied: int = 0
var _frames: int = 0
var _done: bool = false

func _initialize() -> void:
	var args := _user_args()
	if args.size() >= 1:
		_role = str(args[0]).to_lower()
	if args.size() >= 2:
		_port = int(str(args[1]))

	print("[MP-LOOPBACK] role=%s port=%d" % [_role, _port])

	# One NetSession on the process's default MultiplayerAPI (separate processes = separate
	# sockets, so no set_multiplayer juggling needed here).
	_net = Node.new()
	_net.set_script(NetSessionScript)
	root.add_child(_net)

	# Identical board on both sides: two units at fixed cells, deterministic net_ids 1..2.
	_board = MockBoard.new()
	var a := MockUnit.new()
	var b := MockUnit.new()
	_board.place(a, Vector2i(1, 1))
	_board.place(b, Vector2i(3, 1))
	var reg = CommandApplierScript.UnitRegistry.new()
	reg.assign_map_units([a, b])
	_applier = CommandApplierScript.new(reg, null)
	_net.install_command_seam(_applier, func(): return _board)
	_net.enforce_turn_ownership = false
	_net.action_applied.connect(_on_applied)
	_net.match_rng_ready.connect(_on_seed_ready)

	if _role == "host":
		var err = _net.host_game("Host", _port, 2)
		if err != OK:
			_fail("host_game failed: %s" % err)
			return
	else:
		var err = _net.join_game("127.0.0.1", "Client", _port)
		if err != OK:
			_fail("join_game failed: %s" % err)
			return

	# Drive polling/timeout off the tree's own idle frame signal, so SceneTree keeps pumping
	# nodes + multiplayer normally (do NOT override _process on a SceneTree -- that would
	# suppress its internal processing and the peer would never connect).
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _done:
		return
	_frames += 1
	if _frames > MAX_WAIT_FRAMES:
		_fail("timed out waiting for the peer / handshake / command exchange")
		return

	# Host: once the client is seated, kick the match-RNG handshake exactly once.
	if _role == "host" and not _handshake_started and _net.player_count() >= 2:
		_handshake_started = true
		print("[MP-LOOPBACK] peer connected; starting match-RNG handshake")
		_net.begin_match_rng_handshake()

var _handshake_started: bool = false
var _sent_command: bool = false

func _on_seed_ready() -> void:
	if _net.match_rng == null or not _net.match_rng.is_ready():
		return
	print("[MP-LOOPBACK] MATCH SEED = %d" % _net.match_rng.match_seed)
	# Host drives one scripted command after the seed is set; the client just observes apply.
	if _role == "host" and not _sent_command:
		_sent_command = true
		_net.submit_intent(NetProtocolScript.make_move_unit(1, Vector2i(2, 1)))
		_net.submit_intent(NetProtocolScript.make_wait_unit(2))

func _on_applied(_action: Dictionary) -> void:
	_applied += 1
	# Both scripted commands applied -> report the state hash and finish.
	if _applied >= 2:
		var h: int = _applier.hash_match_state(_board)
		print("[MP-LOOPBACK] STATE HASH = %d" % h)
		print("[MP-LOOPBACK] OK -- compare MATCH SEED and STATE HASH against the other process.")
		_finish(0)

func _finish(code: int) -> void:
	_done = true
	if _net != null and is_instance_valid(_net):
		_net.leave()
	quit(code)

func _fail(msg: String) -> void:
	push_error("[MP-LOOPBACK] FAIL: " + msg)
	print("[MP-LOOPBACK] FAIL: " + msg)
	_finish(1)

func _user_args() -> Array:
	# Everything after the "--" separator on the command line.
	var out: Array = []
	var seen := false
	for a in OS.get_cmdline_args():
		if seen:
			out.append(a)
		elif a == "--":
			seen = true
	# Fallback: also accept trailing bare args (some launchers drop the "--").
	if out.is_empty():
		for a in OS.get_cmdline_user_args():
			out.append(a)
	return out
