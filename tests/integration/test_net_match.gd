extends GutTest

## End-to-end network MATCH tests: a host and a client NetSessionNode in ONE
## process (real ENet over 127.0.0.1, see net_test_harness.gd), each driving its
## OWN copy of the game -- real CharacterResource-backed [Unit]s on a per-peer
## [BoardAdapter], a per-peer turn system node, and a [NetGameRules]. Proves:
## host-side validation (turn, ownership, reachability), identical application of
## accepted moves/attacks on both peers, turn sync, deterministic seeded combat,
## desync detection and mid-match disconnect handling.

const H := preload("res://tests/integration/net_test_harness.gd")
const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

const FIGHTER_ID: StringName = &"test_net_fighter"
const SLOW_ID: StringName = &"test_net_slow"
const SEED := 424242

var _host: Dictionary = {}
var _client: Dictionary = {}
var _hw: Dictionary = {}   # host world
var _cw: Dictionary = {}   # client world
var _port: int = 0


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	CharacterLibrary._cache[FIGHTER_ID] = _make_character(FIGHTER_ID, "Fighter", 12)
	CharacterLibrary._cache[SLOW_ID] = _make_character(SLOW_ID, "Slowpoke", 5)
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


# --- Fixtures -----------------------------------------------------------------

## Two moves: slot 0 a sure-hit range-1 strike, slot 1 a 50% "coin" strike at
## range 1-4 (so the RNG decides whether it lands).
func _make_character(id: StringName, display: String, speed: int) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 1000
	c.base_attack = 20
	c.base_defense = 5
	c.base_magic = 4
	c.base_magic_defense = 5
	c.base_speed = speed
	c.base_movement = 3
	c.attack_range = 1
	c.moveset = [_strike(&"net_sure", 5.0, 1), _strike(&"net_coin", 0.5, 4)] as Array[MoveResource]
	return c


func _strike(id: StringName, accuracy: float, max_range: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id
	m.display_name = String(id)
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.accuracy = accuracy
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = max_range
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = 10
	d.scaling_stat = "attack"
	d.scale = 1.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


## Standard layout: slot 0 owns a Fighter at (0,0) and a Fighter at (4,0);
## slot 1 owns a Fighter at (0,1) (adjacent to 0:0) and one at (4,4).
const LAYOUT := [
	{"id": FIGHTER_ID, "cell": Vector3i(0, 0, 0), "owner": 0},
	{"id": FIGHTER_ID, "cell": Vector3i(4, 0, 0), "owner": 0},
	{"id": FIGHTER_ID, "cell": Vector3i(0, 1, 0), "owner": 1},
	{"id": FIGHTER_ID, "cell": Vector3i(4, 4, 0), "owner": 1},
]


## Build one peer's copy of the game under its peer root.
func _build_world(parent: Node, layout: Array, speed_first: bool = false, seed_value: int = SEED, configure: Callable = Callable()) -> Dictionary:
	var world := Node3D.new()
	world.name = "World"
	parent.add_child(world)
	var map := Node3D.new()
	map.name = "Map"
	world.add_child(map)
	var players: Array = [Player.new(0, "Host"), Player.new(1, "Client")]
	for spec in layout:
		var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
		unit.character_resource = CharacterLibrary.get_character(spec["id"])
		unit.position = BoardAdapter.new(GRID, []).cell_to_world(spec["cell"])
		map.add_child(unit)
		players[spec["owner"]].add_unit(unit)
	var ts: TurnSystemBase = SpeedFirstTurnSystem.new() if speed_first else TraditionalTurnSystem.new()
	world.add_child(ts)
	for p in players:
		ts.register_player(p)
	ts.start_turn_system()
	var board := BoardAdapter.new(GRID, map)
	if configure.is_valid():
		configure.call(board)
	var rules := NetGameRules.new(func(): return board, func(): return ts, seed_value)
	rules.assign_initial_ids()
	return {"world": world, "map": map, "players": players, "ts": ts, "board": board, "rules": rules}


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _hr() -> NetGameRules:
	return _hw["rules"]


func _cr() -> NetGameRules:
	return _cw["rules"]


## Connect, ready up, start, and attach a game world on both peers.
func _start_match(layout: Array = LAYOUT, speed_first: bool = false, configure: Callable = Callable()) -> bool:
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	if not await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1):
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match(SEED)
	if not await H.wait_until(get_tree(), func(): return _cs().is_in_match()):
		return false
	_hw = _build_world(_host["root"], layout, speed_first, int(_hs().get_match_config()["seed"]), configure)
	_cw = _build_world(_client["root"], layout, speed_first, int(_cs().get_match_config()["seed"]), configure)
	# Let deferred turn-system kickoff (Speed First) settle before attaching.
	await H.wait_frames(get_tree(), 2)
	_hs().attach_game(_hr())
	_cs().attach_game(_cr())
	return true


## Submit and wait until the action (by host seq) was applied on BOTH peers or
## the submitter got a rejection. Returns the rejection reason ("" = accepted).
func _submit(session: NetSessionNode, action: Dictionary) -> String:
	var rejected := []
	var cb := func(_a, reason): rejected.append(reason)
	session.intent_rejected.connect(cb)
	var target := _hs().last_applied_seq() + 1
	session.submit_intent(action)
	await H.wait_until(get_tree(), func():
		return rejected.size() > 0 or (_hs().last_applied_seq() >= target and _cs().last_applied_seq() >= target))
	session.intent_rejected.disconnect(cb)
	# Two more frames: digests/checkpoints and deferred turn logic settle.
	await H.wait_frames(get_tree(), 3)
	return String(rejected[0]) if rejected.size() > 0 else ""


## Mark expected push_warning()s (which GUT tracks as engine errors) handled.
func _expect_warning(text: String) -> int:
	var n := 0
	for e in get_errors():
		if text in str(e.code) or text in str(e.rationale):
			e.handled = true
			n += 1
	return n


func _cell(world: Dictionary, unit_id: String) -> Vector3i:
	var u = world["rules"].find_unit(unit_id)
	return world["board"].cell_of(u) if u != null else Vector3i(-99, -99, 0)


func _hp(world: Dictionary, unit_id: String) -> int:
	var u = world["rules"].find_unit(unit_id)
	return u.get_hp() if u != null else -1


# --- Tests --------------------------------------------------------------------

func test_unit_ids_are_stable_and_unique_on_mirror_layout() -> void:
	assert_true(await _start_match(), "match started")
	var ids := []
	for u in _hw["board"].all_units():
		ids.append(NetUnitIds.id_of(u))
	ids.sort()
	assert_eq(ids, ["0:0", "0:1", "1:0", "1:1"], "one unique id per unit despite identical display names")
	for id in ids:
		assert_eq(_cell(_hw, id), _cell(_cw, id), "id %s names the same unit on both peers" % id)


func test_out_of_turn_intent_is_rejected() -> void:
	assert_true(await _start_match(), "match started")
	assert_eq(_hr().current_turn_slot(), 0, "slot 0 opens")
	var reason := await _submit(_cs(), NetProtocol.move("1:1", Vector3i(3, 4, 0)))
	assert_eq(reason, "not_your_turn", "client cannot act on the host's turn")
	assert_eq(_cell(_hw, "1:1"), Vector3i(4, 4, 0), "host state untouched")
	assert_eq(_cell(_cw, "1:1"), Vector3i(4, 4, 0), "client state untouched")


func test_foreign_unit_is_rejected() -> void:
	assert_true(await _start_match(), "match started")
	var reason := await _submit(_hs(), NetProtocol.move("1:1", Vector3i(3, 4, 0)))
	assert_eq(reason, "not_your_unit", "host cannot command the client's unit")
	assert_eq(_cell(_cw, "1:1"), Vector3i(4, 4, 0), "unit did not move")


func test_illegal_destination_is_rejected() -> void:
	assert_true(await _start_match(), "match started")
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(0, 4, 0))), "illegal_destination",
		"beyond movement range")
	assert_eq(await _submit(_hs(), NetProtocol.move("0:0", Vector3i(0, 1, 0))), "illegal_destination",
		"occupied by an enemy")
	assert_eq(await _submit(_hs(), NetProtocol.use_move("0:1", 0, Vector3i(4, 4, 0))), "illegal_target",
		"strike out of range")
	assert_eq(await _submit(_hs(), NetProtocol.use_move("0:0", 3, Vector3i(0, 1, 0))), "no_move_in_slot",
		"empty move slot")
	assert_eq(_cell(_hw, "0:1"), Vector3i(4, 0, 0), "nothing moved on the host")
	assert_eq(_cell(_cw, "0:1"), Vector3i(4, 0, 0), "nothing moved on the client")


func test_malformed_intent_never_reaches_the_host_queue() -> void:
	assert_true(await _start_match(), "match started")
	assert_false(_cs().submit_intent({"type": NetProtocol.Action.MOVE, "data": {"unit_id": "1:0"}}),
		"missing destination is refused locally")
	assert_eq(_expect_warning("malformed"), 1, "refusal warned once")


func test_accepted_move_is_applied_identically() -> void:
	assert_true(await _start_match(), "match started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(3, 1, 0))), "", "legal move accepted")
	assert_eq(_cell(_hw, "0:1"), Vector3i(3, 1, 0), "host moved the unit")
	assert_eq(_cell(_cw, "0:1"), Vector3i(3, 1, 0), "client moved the same unit to the same cell")
	assert_true(_hr().find_unit("0:1").has_moved_this_turn, "move consumed on host")
	assert_true(_cr().find_unit("0:1").has_moved_this_turn, "move consumed on client")
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(2, 1, 0))), "unit_cannot_move",
		"a unit moves once per turn")
	assert_eq(_hr().state_digest(), _cr().state_digest(), "digests agree")
	assert_eq(desyncs, [], "no desync reported")


func test_attack_applied_identically_and_turn_passes() -> void:
	assert_true(await _start_match(), "match started")
	var turns := []
	_cs().turn_changed.connect(func(slot): turns.append(slot))
	var hp_before := _hp(_cw, "1:0")
	assert_eq(await _submit(_hs(), NetProtocol.use_move("0:0", 0, Vector3i(0, 1, 0))), "", "sure strike accepted")
	assert_lt(_hp(_hw, "1:0"), hp_before, "target damaged on host")
	assert_eq(_hp(_cw, "1:0"), _hp(_hw, "1:0"), "identical HP on client")
	assert_eq(await _submit(_hs(), NetProtocol.use_move("0:0", 0, Vector3i(0, 1, 0))), "unit_cannot_act",
		"a unit acts once per turn")
	# Last slot-0 unit waits -> Traditional auto-ends the turn on both peers.
	assert_eq(await _submit(_hs(), NetProtocol.wait("0:1")), "", "wait accepted")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
	assert_eq(_hr().current_turn_slot(), 1, "host turn system advanced to slot 1")
	assert_eq(_cr().current_turn_slot(), 1, "client turn system advanced to slot 1")
	assert_eq(_hs().current_turn_slot(), 1, "host session knows")
	assert_eq(_cs().current_turn_slot(), 1, "client session learned it from the checkpoint")
	assert_true(_cs().is_my_turn(), "client: my turn")
	assert_false(_hs().is_my_turn(), "host: not my turn")
	assert_true(turns.has(1), "turn_changed(1) emitted on client")
	# Now the host is the one out of turn, and the client may act.
	assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "not_your_turn", "host out of turn")
	assert_eq(await _submit(_cs(), NetProtocol.move("1:1", Vector3i(3, 3, 0))), "", "client move accepted")
	assert_eq(_cell(_hw, "1:1"), Vector3i(3, 3, 0), "client's move applied on host")
	assert_eq(_cell(_cw, "1:1"), Vector3i(3, 3, 0), "client's move applied on client")


func test_end_turn_round_trip() -> void:
	assert_true(await _start_match(), "match started")
	assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "", "host ends turn")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
	assert_eq(_cs().current_turn_slot(), 1, "client's turn")
	assert_eq(await _submit(_cs(), NetProtocol.end_turn()), "", "client ends turn")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 0)
	assert_eq(_hr().current_turn_slot(), 0, "back to host on host")
	assert_eq(_cr().current_turn_slot(), 0, "back to host on client")
	assert_eq(_hw["ts"].current_turn, _cw["ts"].current_turn, "turn counters agree")


func test_seeded_combat_is_identical_across_peers() -> void:
	assert_true(await _start_match(), "match started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	# Alternate turns; each turn slot 0's (0:1 at 4,0) coin-strikes 1:1 at (4,4)...
	# out of range 4? (4,0)->(4,4) is distance 4 = max range: legal.
	for i in range(6):
		assert_eq(await _submit(_hs(), NetProtocol.use_move("0:1", 1, Vector3i(4, 4, 0))), "", "coin strike %d" % i)
		assert_eq(_hp(_hw, "1:1"), _hp(_cw, "1:1"), "same HP after coin strike %d" % i)
		assert_eq(await _submit(_hs(), NetProtocol.end_turn()), "", "host ends turn %d" % i)
		await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
		assert_eq(await _submit(_cs(), NetProtocol.end_turn()), "", "client ends turn %d" % i)
		await H.wait_until(get_tree(), func(): return _hs().current_turn_slot() == 0)
	assert_eq(_hr().state_digest(), _cr().state_digest(), "final digests agree")
	assert_eq(desyncs, [], "no desync across the whole exchange")


func test_rules_rng_is_a_pure_function_of_seed_and_seq() -> void:
	# No network: three independent worlds replay the same 30 accepted coin strikes.
	var a := _build_world(self, LAYOUT, false, 777)
	var b := _build_world(self, LAYOUT, false, 777)
	var c := _build_world(self, LAYOUT, false, 778)
	var hits := {"a": [], "b": [], "c": []}
	for seq in range(1, 31):
		for key in ["a", "b", "c"]:
			var w: Dictionary = {"a": a, "b": b, "c": c}[key]
			var before := _hp(w, "1:0")
			var act := NetProtocol.use_move("0:0", 1, Vector3i(0, 1, 0))
			act[NetProtocol.KEY_SEQ] = seq
			w["rules"].apply_action(act)
			hits[key].append(_hp(w, "1:0") < before)
	assert_eq(hits["a"], hits["b"], "same seed -> identical hit sequence")
	assert_ne(hits["a"], hits["c"], "different seed -> different hit sequence")
	assert_true(hits["a"].has(true) and hits["a"].has(false), "the coin actually varies")
	for w in [a, b, c]:
		w["world"].queue_free()
	CombatServices.match_rng = null


func test_desync_is_detected() -> void:
	assert_true(await _start_match(), "match started")
	var desyncs := []
	_cs().desync_detected.connect(func(s, _a, _b): desyncs.append(s))
	# Corrupt the CLIENT's copy behind the protocol's back.
	_cr().find_unit("1:1").take_damage(7)
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(3, 0, 0))), "", "move accepted")
	await H.wait_until(get_tree(), func(): return desyncs.size() > 0)
	assert_eq(desyncs.size(), 1, "client flagged the divergence at the next checkpoint")
	assert_eq(_expect_warning("DESYNC"), 1, "desync warned once")


func test_speed_first_turn_sync() -> void:
	# Slowpoke (speed 5) vs Fighter (speed 12): the client's Fighter acts first.
	var layout := [
		{"id": SLOW_ID, "cell": Vector3i(0, 0, 0), "owner": 0},
		{"id": FIGHTER_ID, "cell": Vector3i(4, 4, 0), "owner": 1},
	]
	assert_true(await _start_match(layout, true), "match started")
	await H.wait_until(get_tree(), func(): return _cs().current_turn_slot() == 1)
	assert_eq(_hr().current_turn_slot(), 1, "fastest unit (client's) acts first on host")
	assert_eq(_cr().current_turn_slot(), 1, "... and on client")
	assert_eq(await _submit(_hs(), NetProtocol.wait("0:0")), "not_your_turn", "host must wait its turn")
	assert_eq(await _submit(_cs(), NetProtocol.move("1:0", Vector3i(4, 2, 0))), "", "client moves")
	assert_eq(await _submit(_cs(), NetProtocol.wait("1:0")), "", "client waits -> next unit")
	await H.wait_until(get_tree(), func(): return _hs().current_turn_slot() == 0)
	assert_eq(_hr().current_turn_slot(), 0, "host's unit is up on host")
	assert_eq(_cr().current_turn_slot(), 0, "host's unit is up on client")
	assert_eq(_cell(_hw, "1:0"), _cell(_cw, "1:0"), "positions agree")
	assert_eq(_hr().state_digest(), _cr().state_digest(), "digests agree")


func test_client_disconnect_mid_match_aborts_on_host() -> void:
	assert_true(await _start_match(), "match started")
	var aborted := []
	_hs().match_aborted.connect(func(reason): aborted.append(reason))
	_cs().leave()
	await H.wait_until(get_tree(), func(): return aborted.size() > 0)
	assert_eq(aborted, ["opponent_disconnected"], "host told the opponent left")


func test_host_disconnect_mid_match_aborts_on_client() -> void:
	assert_true(await _start_match(), "match started")
	var aborted := []
	_cs().match_aborted.connect(func(reason): aborted.append(reason))
	_hs().leave()
	await H.wait_until(get_tree(), func(): return aborted.size() > 0)
	assert_eq(aborted, ["host_disconnected"], "client told the host left")
	assert_false(_cs().is_active(), "client session closed")


## Multi-floor: a floor-1 walkway over (1..3, 0) reached by a stair link
## (4,0,0) <-> (3,0,1). Applied identically to both peers' boards.
static func _add_walkway(board: BoardAdapter) -> void:
	var present := {}
	for x in range(1, 4):
		present[Vector3i(x, 0, 1)] = true
	board.set_present_cells(present)
	board.set_links([{"from": Vector3i(4, 0, 0), "to": Vector3i(3, 0, 1)}])


func test_move_across_floors_via_link() -> void:
	assert_true(await _start_match(LAYOUT, false, _add_walkway), "match started")
	# Air next to the walkway is not a floor: rejected by the floor-aware resolver.
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(2, 1, 1))), "illegal_destination",
		"cannot stop in air on floor 1")
	# Up the stairs (link hop) and along the walkway: [4,0,0] -> [3,0,1] -> [2,0,1].
	assert_eq(await _submit(_hs(), NetProtocol.move("0:1", Vector3i(2, 0, 1))), "", "cross-floor move accepted")
	assert_eq(_cell(_hw, "0:1"), Vector3i(2, 0, 1), "host: unit on floor 1")
	assert_eq(_cell(_cw, "0:1"), Vector3i(2, 0, 1), "client: same unit, same floor")
	var hu: Unit = _hr().find_unit("0:1")
	var cu: Unit = _cr().find_unit("0:1")
	assert_almost_eq(hu.position.y, cu.position.y, 0.001, "same world height on both peers")
	assert_gt(hu.position.y, Cells.floor_y(1) - 0.5, "unit was lifted onto the upper floor")
	# The ground cell under the walkway is a different cell: still free.
	assert_true(_hw["board"].units_at(Vector3i(2, 0, 0)).is_empty(), "ground below the bridge unoccupied")
	assert_eq(_hr().state_digest(), _cr().state_digest(), "digests (which include the floor) agree")
