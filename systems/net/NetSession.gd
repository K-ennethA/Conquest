extends Node
class_name NetSessionNode
## NetSession (class NetSessionNode; the autoload instance is named NetSession) -- the single, host-authoritative multiplayer session.
##
## Transport, lobby and action ORDERING only; game rules live in a pluggable
## "game" object (see [NetGameRules]). Built directly on the scene-tree
## [code]multiplayer[/code] API of wherever this node sits (ENet peer), so:
##   * the autoload at /root/NetSession uses the default MultiplayerAPI, and
##   * tests instance several NetSessions in ONE process, each under its own
##     subtree with its own SceneMultiplayer (SceneTree.set_multiplayer), with
##     identical relative paths so RPCs line up.
##
## Flow:
##   lobby   host_game / join_game -> clients announce their name -> host seats
##           them (peer -> slot map owned by the host) -> set_ready -> host
##           set_match_config -> start_match (only when full + all ready, once).
##   match   submit_intent -> host queue -> game.validate_intent -> accepted
##           actions are stamped (actor, seq) and broadcast; EVERY peer (host
##           included) applies them through game.apply_action, at most ONE per
##           frame so deferred turn logic (auto end-of-turn, death cleanup) settles
##           identically everywhere before the next action. After each action the
##           host broadcasts a checkpoint (seq, turn slot, state digest); clients
##           compare it with their own digest (desync detection) and learn whose
##           turn it is.
##   end     leave() closes the peer and resets everything. A peer dropping
##           mid-match raises [signal match_aborted] on the survivor.

signal roster_changed(roster: Dictionary)
## A player was seated (host + clients). peer_id is the ENet id.
signal player_joined(peer_id: int, slot: int, player_name: String)
signal player_left(peer_id: int, slot: int)
## Client: we were seated by the host (our slot is known).
signal joined(slot: int)
## Client: the host refused us (lobby full / match in progress) -- session closed.
signal join_rejected(reason: String)
## The lobby config (map / turn system) changed. Host and clients.
signal config_changed(config: Dictionary)
## The match started; [param config] is the host's authoritative match config
## (map_path, turn_system, seed, slots: {slot:int -> name}).
signal match_started(config: Dictionary)
## An accepted action was applied locally (after game.apply_action ran).
signal action_applied(action: Dictionary, result: Dictionary)
## An intent this peer submitted was rejected by the host.
signal intent_rejected(action: Dictionary, reason: String)
## Whose turn it is changed (slot).
signal turn_changed(slot: int)
## Our digest disagreed with the host's after action [param seq].
signal desync_detected(seq: int, local_digest: int, host_digest: int)
## Mid-match: the other side is gone (host: a client dropped; client: host dropped).
signal match_aborted(reason: String)
## The connection to the host was lost (client) -- session already closed.
signal disconnected(reason: String)
## A join attempt failed to connect -- session already closed.
signal connection_failed()

enum Role { NONE, HOST, CLIENT }
enum State { IDLE, LOBBY, IN_MATCH }

const DEFAULT_PORT := 8910
const DEFAULT_ADDRESS := "127.0.0.1"
const SERVER_PEER_ID := 1

## Seats in a match. Versus is 1v1.
@export var max_players: int = 2

var role: Role = Role.NONE
var state: State = State.IDLE
## The rules object for the running match (see class docs). Null until the game
## world attached it; accepted actions queue until then.
var game = null

## peer_id -> { "slot": int, "name": String, "ready": bool }
var _roster: Dictionary = {}
var _config: Dictionary = {}
var _match_config: Dictionary = {}
var _local_slot: int = -1
var _current_turn_slot: int = -1
var _pending_name: String = "Player"
var _peer: ENetMultiplayerPeer = null

# Host-side ordering.
var _seq: int = 0
var _intent_queue: Array = []          # [ [slot, action], ... ]
var _last_checkpoint_seq: int = 0
var _kick_after: Dictionary = {}       # peer_id -> frames left before disconnect
# Every peer.
var _apply_queue: Array = []           # accepted actions awaiting apply
var _last_applied_seq: int = 0
var _local_digests: Dictionary = {}    # seq -> digest (clients, for checkpoints)
var _pending_checkpoints: Dictionary = {}  # seq -> host digest awaiting our digest
var _digest_seq: int = 0
var _signals_wired: bool = false


func _ready() -> void:
	_wire_multiplayer_signals()


func _wire_multiplayer_signals() -> void:
	if _signals_wired:
		return
	_signals_wired = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Public API -- session
# ---------------------------------------------------------------------------

## Host a listen-server game: this instance is the authority AND slot 0.
func host_game(player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	# Leave headroom above max_players so an extra peer can CONNECT and be told
	# politely that the lobby is full (rather than ENet silently refusing it).
	var err := _peer.create_server(port, max_players + 2)
	if err != OK:
		push_warning("NetSession: create_server(%d) failed: %s" % [port, error_string(err)])
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	state = State.LOBBY
	_pending_name = player_name
	_roster[SERVER_PEER_ID] = {"slot": 0, "name": player_name, "ready": false}
	_local_slot = 0
	player_joined.emit(SERVER_PEER_ID, 0, player_name)
	_broadcast_lobby()
	return OK


## Join a host as a client. Connection completes asynchronously: listen for
## [signal joined] / [signal join_rejected] / [signal connection_failed].
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address if address != "" else DEFAULT_ADDRESS, port)
	if err != OK:
		push_warning("NetSession: create_client failed: %s" % error_string(err))
		_peer = null
		return err
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	state = State.LOBBY
	_pending_name = player_name
	return OK


## Tear down the session (close the peer) and reset to a clean IDLE state.
## Safe to call at any time, repeatedly.
func leave() -> void:
	var had_session := role != Role.NONE
	if _peer != null:
		_peer.close()
	if multiplayer != null and multiplayer.multiplayer_peer != null \
			and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	role = Role.NONE
	state = State.IDLE
	game = null
	_roster.clear()
	_config.clear()
	_match_config.clear()
	_local_slot = -1
	_current_turn_slot = -1
	_seq = 0
	_intent_queue.clear()
	_apply_queue.clear()
	_last_applied_seq = 0
	_last_checkpoint_seq = 0
	_local_digests.clear()
	_pending_checkpoints.clear()
	_digest_seq = 0
	_kick_after.clear()
	if had_session:
		roster_changed.emit({})


# ---------------------------------------------------------------------------
# Public API -- lobby
# ---------------------------------------------------------------------------

func set_ready(is_ready: bool) -> void:
	if state != State.LOBBY:
		return
	if is_host():
		_host_set_ready(SERVER_PEER_ID, is_ready)
	elif role == Role.CLIENT:
		_rpc_set_ready.rpc_id(SERVER_PEER_ID, is_ready)


## Host: set lobby options (map_path, turn_system, ...). Changing them clears
## everyone's ready flag so nobody starts on settings they did not see.
func set_match_config(config: Dictionary) -> void:
	if not is_host() or state != State.LOBBY:
		return
	if config == _config:
		return
	_config = config.duplicate(true)
	for pid in _roster:
		_roster[pid]["ready"] = false
	_broadcast_lobby()


func get_match_config() -> Dictionary:
	return (_match_config if state == State.IN_MATCH else _config).duplicate(true)


## Host: true when the lobby is full and every seated player is ready.
func can_start_match() -> bool:
	if not is_host() or state != State.LOBBY:
		return false
	if _roster.size() != max_players:
		return false
	for pid in _roster:
		if not bool(_roster[pid]["ready"]):
			return false
	return true


## Host: start the match (single-shot guard: returns false if not startable or
## already started). [param seed_value] 0 = pick a random seed.
func start_match(seed_value: int = 0) -> bool:
	if not can_start_match():
		return false
	var cfg := _config.duplicate(true)
	cfg["seed"] = seed_value if seed_value != 0 else (randi() | 1)
	var slots := {}
	for pid in _roster:
		slots[int(_roster[pid]["slot"])] = String(_roster[pid]["name"])
	cfg["slots"] = slots
	state = State.IN_MATCH  # guard BEFORE broadcasting: a second call is a no-op
	_rpc_match_started.rpc(cfg)
	return true


# ---------------------------------------------------------------------------
# Public API -- match
# ---------------------------------------------------------------------------

## Plug in the rules object once the game world is ready (every peer). Actions
## that arrived earlier are applied from the next frame on.
func attach_game(rules) -> void:
	game = rules
	if is_host() and game != null:
		_set_turn_slot(int(game.current_turn_slot()))


## Submit an intent. Never mutates state directly -- the accepted action comes
## back through [signal action_applied] (or [signal intent_rejected]).
func submit_intent(action: Dictionary) -> bool:
	if state != State.IN_MATCH:
		return false
	if not NetProtocol.is_well_formed(action):
		push_warning("NetSession: refusing to submit malformed action")
		return false
	var a := action.duplicate(true)
	a[NetProtocol.KEY_ACTOR] = _local_slot
	a[NetProtocol.KEY_SEQ] = 0
	if is_host():
		_intent_queue.append([_local_slot, a])
	else:
		_rpc_intent.rpc_id(SERVER_PEER_ID, a)
	return true


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_host() -> bool:
	return role == Role.HOST

func is_active() -> bool:
	return role != Role.NONE

func is_in_match() -> bool:
	return role != Role.NONE and state == State.IN_MATCH

func local_peer_id() -> int:
	return multiplayer.get_unique_id() if _peer != null else -1

func local_slot() -> int:
	return _local_slot

func current_turn_slot() -> int:
	return _current_turn_slot

func is_my_turn() -> bool:
	return _local_slot != -1 and _local_slot == _current_turn_slot

func get_roster() -> Dictionary:
	return _roster.duplicate(true)

func player_count() -> int:
	return _roster.size()

func last_applied_seq() -> int:
	return _last_applied_seq

func has_pending_actions() -> bool:
	return not _apply_queue.is_empty() or not _intent_queue.is_empty()


# ---------------------------------------------------------------------------
# Frame pump: at most one applied action per frame, on every peer
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_tick_kicks()
	if state != State.IN_MATCH or game == null:
		return
	# 1. The previous action (and everything it deferred) has settled: publish /
	#    record the digest for it.
	if _last_applied_seq > _digest_seq:
		_record_digest(_last_applied_seq)
	# 2. Apply one queued accepted action (clients, or a host backlog).
	if not _apply_queue.is_empty():
		_apply_now(_apply_queue.pop_front())
		return
	# 3. Host: validate one intent and, if legal, broadcast + apply it.
	if is_host() and not _intent_queue.is_empty():
		var entry: Array = _intent_queue.pop_front()
		_host_handle_intent(int(entry[0]), entry[1])


func _host_handle_intent(actor_slot: int, action: Dictionary) -> void:
	var reason := _validate(actor_slot, action)
	if reason != "":
		var pid := _peer_for_slot(actor_slot)
		if pid == SERVER_PEER_ID:
			intent_rejected.emit(action, reason)
		elif pid != -1:
			_rpc_intent_rejected.rpc_id(pid, action, reason)
		return
	_seq += 1
	action[NetProtocol.KEY_SEQ] = _seq
	action[NetProtocol.KEY_ACTOR] = actor_slot
	_rpc_accepted.rpc(action)   # call_remote: clients queue it
	_apply_now(action)          # host applies in the same step


func _validate(actor_slot: int, action: Dictionary) -> String:
	if not NetProtocol.is_well_formed(action):
		return "malformed"
	if actor_slot < 0:
		return "unknown_actor"
	if game == null:
		return "no_game"
	return String(game.validate_intent(action, actor_slot))


func _apply_now(action: Dictionary) -> void:
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	if seq <= _last_applied_seq:
		return  # duplicate / stale
	var result = game.apply_action(action)
	_last_applied_seq = seq
	action_applied.emit(action, result if result is Dictionary else {})


func _record_digest(seq: int) -> void:
	_digest_seq = seq
	var digest := int(game.state_digest())
	var turn_slot := int(game.current_turn_slot())
	if is_host():
		_set_turn_slot(turn_slot)
		_last_checkpoint_seq = seq
		_rpc_checkpoint.rpc(seq, turn_slot, digest)
	else:
		_local_digests[seq] = digest
		if _pending_checkpoints.has(seq):
			_compare_checkpoint(seq, _pending_checkpoints[seq])
			_pending_checkpoints.erase(seq)


func _compare_checkpoint(seq: int, host_digest: int) -> void:
	var mine: int = int(_local_digests.get(seq, 0))
	_local_digests.erase(seq)
	if mine != host_digest:
		push_warning("NetSession: DESYNC after action %d (local %d, host %d)" % [seq, mine, host_digest])
		desync_detected.emit(seq, mine, host_digest)


func _set_turn_slot(slot: int) -> void:
	if slot == _current_turn_slot:
		return
	_current_turn_slot = slot
	turn_changed.emit(slot)


# ---------------------------------------------------------------------------
# Connection lifecycle
# ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		return
	# Seat on _rpc_announce; refuse early when there is no room at all.
	if state == State.IN_MATCH:
		_reject(peer_id, "match_in_progress")
	elif _roster.size() >= max_players:
		_reject(peer_id, "lobby_full")


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	_kick_after.erase(peer_id)
	if not _roster.has(peer_id):
		return
	var slot: int = _roster[peer_id]["slot"]
	_roster.erase(peer_id)
	player_left.emit(peer_id, slot)
	if state == State.IN_MATCH:
		# A seated player dropped mid-match: the match cannot continue.
		match_aborted.emit("opponent_disconnected")
	else:
		for pid in _roster:
			_roster[pid]["ready"] = false
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	_rpc_announce.rpc_id(SERVER_PEER_ID, _pending_name)


# These fire from inside the MultiplayerAPI poll, so the peer is torn down on the
# next idle step (call_deferred) rather than closed mid-poll.
func _on_connection_failed() -> void:
	call_deferred("_close_and_emit", "connection_failed", "")


func _on_server_disconnected() -> void:
	var was_in_match := state == State.IN_MATCH
	call_deferred("_close_and_emit", "host_lost", "in_match" if was_in_match else "")


func _close_and_emit(kind: String, detail: String) -> void:
	leave()
	match kind:
		"connection_failed":
			connection_failed.emit()
		"host_lost":
			if detail == "in_match":
				match_aborted.emit("host_disconnected")
			disconnected.emit("host_disconnected")
		"rejected":
			join_rejected.emit(detail)


func _reject(peer_id: int, reason: String) -> void:
	_rpc_join_rejected.rpc_id(peer_id, reason)
	# Give the rejection a few frames to flush before dropping the peer.
	_kick_after[peer_id] = 10


func _tick_kicks() -> void:
	if _kick_after.is_empty() or _peer == null:
		return
	for pid in _kick_after.keys():
		_kick_after[pid] = int(_kick_after[pid]) - 1
		if _kick_after[pid] <= 0:
			_kick_after.erase(pid)
			if _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
				_peer.disconnect_peer(pid)


# ---------------------------------------------------------------------------
# RPCs: client -> host
# ---------------------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_announce(player_name: String) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _roster.has(peer_id) or _kick_after.has(peer_id):
		return
	if state != State.LOBBY:
		_reject(peer_id, "match_in_progress")
		return
	var slot := _first_free_slot()
	if slot == -1:
		_reject(peer_id, "lobby_full")
		return
	var clean := player_name.strip_edges().left(24)
	if clean == "":
		clean = "Player %d" % (slot + 1)
	_roster[peer_id] = {"slot": slot, "name": clean, "ready": false}
	player_joined.emit(peer_id, slot, clean)
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(is_ready: bool) -> void:
	if not is_host() or state != State.LOBBY:
		return
	_host_set_ready(multiplayer.get_remote_sender_id(), is_ready)


func _host_set_ready(peer_id: int, is_ready: bool) -> void:
	if _roster.has(peer_id):
		_roster[peer_id]["ready"] = is_ready
		_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(action: Dictionary) -> void:
	if not is_host() or state != State.IN_MATCH:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	# The actor is ALWAYS derived from the sender's seat, never from the payload.
	var slot: int = int(_roster[peer_id]["slot"]) if _roster.has(peer_id) else -1
	_intent_queue.append([slot, action])


# ---------------------------------------------------------------------------
# RPCs: host -> clients
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_lobby(roster: Dictionary, config: Dictionary) -> void:
	var was_seated := _local_slot != -1
	_roster = roster
	var my_id := local_peer_id()
	if _roster.has(my_id):
		_local_slot = int(_roster[my_id]["slot"])
	if config != _config:
		_config = config
		config_changed.emit(_config.duplicate(true))
	roster_changed.emit(get_roster())
	if not was_seated and _local_slot != -1:
		joined.emit(_local_slot)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_rejected(reason: String) -> void:
	call_deferred("_close_and_emit", "rejected", reason)


@rpc("authority", "call_local", "reliable")
func _rpc_match_started(config: Dictionary) -> void:
	state = State.IN_MATCH
	_match_config = config.duplicate(true)
	_seq = 0
	_last_applied_seq = 0
	_digest_seq = 0
	_apply_queue.clear()
	_intent_queue.clear()
	match_started.emit(_match_config.duplicate(true))


@rpc("authority", "call_remote", "reliable")
func _rpc_accepted(action: Dictionary) -> void:
	if state != State.IN_MATCH:
		return
	_apply_queue.append(action)


@rpc("authority", "call_remote", "reliable")
func _rpc_intent_rejected(action: Dictionary, reason: String) -> void:
	intent_rejected.emit(action, reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_checkpoint(seq: int, turn_slot: int, digest: int) -> void:
	if state != State.IN_MATCH:
		return
	_set_turn_slot(turn_slot)
	if _local_digests.has(seq):
		_compare_checkpoint(seq, digest)
	else:
		_pending_checkpoints[seq] = digest


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _broadcast_lobby() -> void:
	roster_changed.emit(get_roster())
	config_changed.emit(_config.duplicate(true))
	if is_host():
		_rpc_sync_lobby.rpc(_roster, _config)


func _first_free_slot() -> int:
	var taken: Array = []
	for pid in _roster:
		taken.append(int(_roster[pid]["slot"]))
	for s in range(max_players):
		if s not in taken:
			return s
	return -1


func _peer_for_slot(slot: int) -> int:
	for peer_id in _roster:
		if int(_roster[peer_id]["slot"]) == slot:
			return peer_id
	return -1
