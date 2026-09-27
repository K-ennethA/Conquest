extends Node
class_name NetSessionNode
## NetSession (class NetSessionNode; the autoload instance is named NetSession) -- the single, host-authoritative multiplayer session.
##
## Transport, lobby, action ORDERING and the commit-reveal combat RNG; game rules
## live in a pluggable "game" object (see [NetGameRules]). Built on the
## scene-tree [code]multiplayer[/code] API of wherever this node sits; the concrete
## peer comes from a [NetTransport] (ENet by default), so:
##   * the autoload at /root/NetSession uses the default MultiplayerAPI, and
##   * tests instance several NetSessions in ONE process, each under its own
##     subtree with its own SceneMultiplayer (SceneTree.set_multiplayer), with
##     identical relative paths so RPCs line up.
##
## Two hosting modes share every code path:
##   * PLAYER-HOSTED ([method host_game]): the host is also seat 0.
##   * DEDICATED ([method host_dedicated]): the host (server, peer 1) has NO seat;
##     the first two clients take slots 0 and 1. The map / turn system come from
##     the server's settings or, when not locked, from the slot-0 client (lobby
##     leader); the match auto-starts once both are ready. After a match the
##     server returns to an empty lobby for the next pair.
##
## Flow:
##   lobby   host_* / join_game -> clients announce their name -> host seats
##           them (peer -> slot map owned by the host) -> set_ready -> config ->
##           start_match (only when full + all ready, once).
##   commit  every RNG contributor publishes the anchor of a secret hash chain
##           ([NetCommitReveal]); the match starts once all anchors are known.
##   match   submit_intent -> host queue -> game.validate_intent -> accepted
##           actions are stamped (actor, seq) and broadcast WITH the host's share
##           for seq; the other contributors reveal their share only after that
##           (the action is already irrevocable), the host relays them, and every
##           peer verifies each share against its chain before deriving the
##           action's RNG seed. EVERY peer (host included) then applies it through
##           game.apply_action, at most ONE per frame. After each action the host
##           broadcasts a checkpoint (seq, turn slot, state digest) for desync
##           detection. A share that fails verification ends the match.
##   end     leave() closes the peer and resets everything. A seat dropping
##           mid-match raises [signal match_aborted] on the survivor(s).

signal roster_changed(roster: Dictionary)
## A player was seated (host + clients). peer_id is the transport peer id.
signal player_joined(peer_id: int, slot: int, player_name: String)
signal player_left(peer_id: int, slot: int)
## Client: we were seated by the host (our slot is known).
signal joined(slot: int)
## Client: the host refused us (lobby full / match in progress) -- session closed.
signal join_rejected(reason: String)
## The lobby config (map / turn system) changed. Host and clients.
signal config_changed(config: Dictionary)
## The match started; [param config] is the host's authoritative match config
## (map_path, turn_system, seed (setup RNG), slots: {slot:int -> name}, anchors).
signal match_started(config: Dictionary)
## An accepted action was applied locally (after game.apply_action ran).
signal action_applied(action: Dictionary, result: Dictionary)
## An intent this peer submitted was rejected by the host.
signal intent_rejected(action: Dictionary, reason: String)
## Whose turn it is changed (slot).
signal turn_changed(slot: int)
## Our digest disagreed with the host's after action [param seq].
signal desync_detected(seq: int, local_digest: int, host_digest: int)
## Randomness verification failed: [param peer_id] sent a share / commitment
## that does not match its committed chain (or withheld it). Followed by
## [signal match_aborted].
signal cheat_detected(peer_id: int, reason: String)
## Mid-match: the match cannot continue. Reasons: "opponent_disconnected",
## "host_disconnected", "rng_verification_failed" (a player's randomness failed
## verification -- raised on the host / server and told to the clients),
## "host_verification_failed" (a client caught the HOST: bad randomness, an
## illegal accepted action, or an action forged in the client's seat),
## "reveal_timeout",
## "match_complete" (dedicated server closed a finished match).
signal match_aborted(reason: String)
## The connection to the host was lost (client) -- session already closed.
signal disconnected(reason: String)
## A join attempt failed to connect -- session already closed.
signal connection_failed()

enum Role { NONE, HOST, CLIENT }
enum State { IDLE, LOBBY, STARTING, IN_MATCH }
## Who contributes randomness. ALL (default): the host / server AND every seated
## client. SERVER_ONLY: only the host -- allowed for a DEDICATED (trusted)
## server only, since a player-host would then know every future roll.
enum RngMode { ALL, SERVER_ONLY }

const DEFAULT_PORT := 8910
const DEFAULT_ADDRESS := "127.0.0.1"
const SERVER_PEER_ID := 1
## Config keys a lobby leader may set on a dedicated server.
const CONFIG_KEYS := ["map_path", "turn_system", "auto_end_turn"]

## Seats in a match. Versus is 1v1.
@export var max_players: int = 2
## Hash-chain length per epoch (see [NetCommitReveal]); a new chain is committed
## when one runs out. Small values are only useful to exercise re-commits in tests.
@export var rng_chain_length: int = NetCommitReveal.DEFAULT_CHAIN_LENGTH
## A contributor that has not revealed its share this long after the action was
## accepted forfeits the match ("reveal_timeout"). 0 disables.
@export var reveal_timeout_ms: int = 30000
## Host: stop accepting intents once this many actions were accepted (0 = no
## limit). A dedicated-server knob for scripted runs / benchmarks.
var max_actions: int = 0
## How peers are created. Swap before hosting / joining (see [NetTransport]).
var transport: NetTransport = ENetTransport.new()

var role: Role = Role.NONE
var state: State = State.IDLE
## The rules object for the running match (see class docs). Null until the game
## world attached it; accepted actions queue until then.
var game = null
## Dedicated server: the host holds no seat.
var dedicated: bool = false
var rng_mode: RngMode = RngMode.ALL
## Dedicated: start automatically once the lobby is full and everyone is ready.
var auto_start: bool = true
## Dedicated: the config was fixed by the server (clients cannot change it).
var config_locked: bool = false

## Clients re-validate every accepted action against their own state before
## applying it, and check that actions in THEIR seat are ones they submitted.
var verify_host_actions: bool = true

## TEST HOOKS (never set in production code). tamper: corrupt every share this
## peer sends (a cheater); hold: keep our shares back until
## [method release_held_shares] (to observe what is derivable meanwhile).
var debug_tamper_shares: bool = false
var debug_hold_shares: bool = false
## TEST HOOK: a cheating host that accepts every well-formed intent.
var debug_accept_everything: bool = false

## peer_id -> { "slot": int, "name": String, "ready": bool }
var _roster: Dictionary = {}
var _config: Dictionary = {}
var _match_config: Dictionary = {}
var _pending_cfg: Dictionary = {}
var _server_meta: Dictionary = {}      # clients: {"dedicated": bool, "locked": bool}
var _local_slot: int = -1
var _current_turn_slot: int = -1
var _pending_name: String = "Player"
var _peer: MultiplayerPeer = null
var _rng: NetCommitReveal = null

# Host-side ordering.
var _seq: int = 0
var _intent_queue: Array = []          # [ [slot, action], ... ]
var _last_checkpoint_seq: int = 0
var _kick_at: Dictionary = {}          # peer_id -> ticks_msec deadline
var _pending_round: Dictionary = {}    # host: {seq, action, deadline}
# Every peer.
var _apply_queue: Array = []           # accepted actions (randomness stamped) awaiting apply
var _awaiting_rng: Dictionary = {}     # clients: seq -> accepted action awaiting shares
var _last_accepted_seq: int = 0        # clients: last seq announced by the host
var _last_applied_seq: int = 0
var _local_digests: Dictionary = {}    # seq -> digest (clients, for checkpoints)
var _pending_checkpoints: Dictionary = {}  # seq -> host digest awaiting our digest
var _digest_seq: int = 0
var _held_shares: Array = []
var _my_intents: Array = []            # clients: submitted, not yet answered (in order)
var _closing_reason: String = ""       # clients: close once the apply queue drained
var _signals_wired: bool = false


func _ready() -> void:
	# The protocol must keep flowing while the tree is paused (game-over screen,
	# pause menus): otherwise a paused peer stops applying / checkpointing and a
	# server stops closing finished matches.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	var err := _open_host(port)
	if err != OK:
		return err
	dedicated = false
	rng_mode = RngMode.ALL
	config_locked = false
	_pending_name = player_name
	_roster[SERVER_PEER_ID] = {"slot": 0, "name": player_name, "ready": false}
	_local_slot = 0
	player_joined.emit(SERVER_PEER_ID, 0, player_name)
	_broadcast_lobby()
	return OK


## Host a DEDICATED server: no seat; the first two clients play. [param config]
## (map_path / turn_system / auto_end_turn) is locked when it names a map;
## otherwise the slot-0 client picks. [param mode] chooses the RNG contributors.
func host_dedicated(port: int = DEFAULT_PORT, config: Dictionary = {}, mode: RngMode = RngMode.ALL) -> Error:
	var err := _open_host(port)
	if err != OK:
		return err
	dedicated = true
	rng_mode = mode
	_config = _sanitize_config(config)
	config_locked = String(_config.get("map_path", "")) != ""
	_pending_name = "Server"
	_local_slot = -1
	_broadcast_lobby()
	return OK


func _open_host(port: int) -> Error:
	leave()
	# Leave headroom above max_players so an extra peer can CONNECT and be told
	# politely that the lobby is full (rather than the transport silently refusing it).
	_peer = transport.create_host(port, max_players + 2)
	if _peer == null:
		var err: Error = transport.last_error if transport.last_error != OK else FAILED
		push_warning("NetSession: %s host on %d failed: %s" % [transport.id(), port, error_string(err)])
		return err
	_disable_relay()
	multiplayer.multiplayer_peer = _peer
	role = Role.HOST
	state = State.LOBBY
	return OK


## Clients only ever talk to the host (rpc_id 1) and the host broadcasts, so the
## SceneMultiplayer client-to-client relay is off: a client can neither address
## nor even enumerate the other client (and the host never forwards packets to
## a peer that is already gone).
func _disable_relay() -> void:
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false


## Join a host (player-hosted or dedicated) as a client. Connection completes
## asynchronously: listen for [signal joined] / [signal join_rejected] /
## [signal connection_failed].
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	_peer = transport.create_client(address if address != "" else DEFAULT_ADDRESS, port)
	if _peer == null:
		var err: Error = transport.last_error if transport.last_error != OK else FAILED
		push_warning("NetSession: %s client failed: %s" % [transport.id(), error_string(err)])
		return err
	_disable_relay()
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
	dedicated = false
	config_locked = false
	_server_meta.clear()
	_roster.clear()
	_config.clear()
	_local_slot = -1
	_kick_at.clear()
	_closing_reason = ""
	_reset_match_state()
	if had_session:
		roster_changed.emit({})


func _reset_match_state() -> void:
	game = null
	_match_config.clear()
	_pending_cfg.clear()
	_current_turn_slot = -1
	_seq = 0
	_intent_queue.clear()
	_apply_queue.clear()
	_awaiting_rng.clear()
	_pending_round.clear()
	_held_shares.clear()
	_my_intents.clear()
	_last_accepted_seq = 0
	_last_applied_seq = 0
	_last_checkpoint_seq = 0
	_local_digests.clear()
	_pending_checkpoints.clear()
	_digest_seq = 0
	_rng = null


# ---------------------------------------------------------------------------
# Public API -- lobby
# ---------------------------------------------------------------------------

func set_ready(is_ready: bool) -> void:
	if state != State.LOBBY:
		return
	if is_host():
		if _roster.has(SERVER_PEER_ID):
			_host_set_ready(SERVER_PEER_ID, is_ready)
	elif role == Role.CLIENT:
		_rpc_set_ready.rpc_id(SERVER_PEER_ID, is_ready)


## Set lobby options (map_path, turn_system, ...): the player-host, or the lobby
## leader on a dedicated server (sent to the server, which may refuse).
## Changing them clears everyone's ready flag so nobody starts on settings they
## did not see.
func set_match_config(config: Dictionary) -> void:
	if state != State.LOBBY:
		return
	if is_host():
		_host_apply_config(config)
	elif is_lobby_leader():
		_rpc_request_config.rpc_id(SERVER_PEER_ID, config)


func _host_apply_config(config: Dictionary) -> void:
	if not is_host() or state != State.LOBBY:
		return
	var clean := _sanitize_config(config) if dedicated else config.duplicate(true)
	if clean == _config:
		return
	_config = clean
	for pid in _roster:
		_roster[pid]["ready"] = false
	_broadcast_lobby()


static func _sanitize_config(config: Dictionary) -> Dictionary:
	var out := {}
	var map_path = config.get("map_path", "")
	if map_path is String and map_path.begins_with("res://") and not ".." in map_path:
		out["map_path"] = map_path
	var ts = config.get("turn_system", null)
	if typeof(ts) == TYPE_INT and ts >= 0 and ts <= 8:
		out["turn_system"] = ts
	var aet = config.get("auto_end_turn", null)
	if typeof(aet) == TYPE_BOOL:
		out["auto_end_turn"] = aet
	return out


func get_match_config() -> Dictionary:
	return (_match_config if state == State.IN_MATCH else _config).duplicate(true)


## True when this peer may edit the lobby config: the player-host, or the slot-0
## client of a dedicated server whose config is not locked.
func is_lobby_leader() -> bool:
	if is_host():
		return not dedicated or not config_locked
	if role == Role.CLIENT and bool(_server_meta.get("dedicated", false)):
		return _local_slot == 0 and not bool(_server_meta.get("locked", false))
	return false


## True when the host of this session is a dedicated (seatless) server.
func is_dedicated_server() -> bool:
	if is_host():
		return dedicated
	return bool(_server_meta.get("dedicated", false))


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
## already started). Runs the commitment round first; [signal match_started]
## fires on every peer once all RNG contributors have committed.
func start_match() -> bool:
	if not can_start_match():
		return false
	var cfg := _config.duplicate(true)
	var slots := {}
	for pid in _roster:
		slots[int(_roster[pid]["slot"])] = String(_roster[pid]["name"])
	cfg["slots"] = slots
	var contributors: Array = [SERVER_PEER_ID]
	if not (dedicated and rng_mode == RngMode.SERVER_ONLY):
		for pid in _roster:
			if pid != SERVER_PEER_ID:
				contributors.append(int(pid))
	contributors.sort()
	cfg["rng_contributors"] = contributors
	state = State.STARTING  # guard BEFORE broadcasting: a second call is a no-op
	_pending_cfg = cfg
	_rng = NetCommitReveal.new(rng_chain_length)
	var anchor := _rng.begin(SERVER_PEER_ID, contributors)
	_rpc_commit_request.rpc(contributors, _rng.chain_length, anchor)
	_host_try_finish_commit()
	return true


func _host_try_finish_commit() -> void:
	if state != State.STARTING or _rng == null or not _rng.has_all_anchors():
		return
	var cfg := _pending_cfg
	_pending_cfg = {}
	cfg["anchors"] = _rng.anchors()
	cfg["seed"] = _rng.setup_seed()
	state = State.IN_MATCH
	_rpc_match_started.rpc(cfg)


## Host: end the running match for everyone with [param reason] (e.g.
## "match_complete"). A dedicated server then returns to an empty lobby.
func end_match(reason: String) -> void:
	if not is_host() or state == State.LOBBY or state == State.IDLE:
		return
	_rpc_match_ended.rpc(reason)
	if dedicated:
		reset_to_lobby()
	else:
		_reset_match_state()
		state = State.LOBBY


## Dedicated server: drop every client (after a short flush) and reopen an empty
## lobby for the next pair. Keeps the listening peer and the (locked) config.
func reset_to_lobby() -> void:
	if not is_host():
		return
	_reset_match_state()
	for pid in _roster.keys():
		if pid != SERVER_PEER_ID:
			_kick_at[pid] = Time.get_ticks_msec() + 500
	_roster.clear()
	if not config_locked:
		_config.clear()
	state = State.LOBBY
	_broadcast_lobby()


# ---------------------------------------------------------------------------
# Public API -- match
# ---------------------------------------------------------------------------

## Plug in the rules object once the game world is ready (every peer). Actions
## that arrived earlier are applied from the next frame on.
func attach_game(rules) -> void:
	game = rules
	# Opening turn: every peer derives it from the identical initial board (the
	# host's checkpoints take over from the first action on).
	if game != null and _last_applied_seq == 0:
		_set_turn_slot(int(game.current_turn_slot()))


## Submit an intent. Never mutates state directly -- the accepted action comes
## back through [signal action_applied] (or [signal intent_rejected]).
func submit_intent(action: Dictionary) -> bool:
	if state != State.IN_MATCH or _local_slot < 0:
		return false
	if not NetProtocol.is_well_formed(action):
		push_warning("NetSession: refusing to submit malformed action")
		return false
	var a := action.duplicate(true)
	a[NetProtocol.KEY_ACTOR] = _local_slot
	a[NetProtocol.KEY_SEQ] = 0
	a.erase(NetProtocol.KEY_RNG)
	if is_host():
		_intent_queue.append([_local_slot, a])
	else:
		_my_intents.append(a)
		_rpc_intent.rpc_id(SERVER_PEER_ID, a)
	return true


## TEST HOOK: send the shares held back while [member debug_hold_shares] was on.
func release_held_shares() -> void:
	debug_hold_shares = false
	var held := _held_shares
	_held_shares = []
	for entry in held:
		_rpc_share.rpc_id(SERVER_PEER_ID, int(entry[0]), entry[1])


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
	return not _apply_queue.is_empty() or not _intent_queue.is_empty() \
		or not _pending_round.is_empty() or not _awaiting_rng.is_empty()

## Peer ids contributing randomness in the running match.
func rng_contributors() -> Array:
	return _rng.contributors.duplicate() if _rng != null else []

## True once THIS peer can compute the RNG seed of accepted action [param seq]
## (i.e. every contributor's share for it has been verified here), or the
## action was already applied.
func randomness_known(seq: int) -> bool:
	if seq <= _last_applied_seq:
		return true
	for a in _apply_queue:
		if int(a.get(NetProtocol.KEY_SEQ, 0)) == seq:
			return true
	return _rng != null and _rng.seed_for(seq) != null


# ---------------------------------------------------------------------------
# Frame pump: at most one applied action per frame, on every peer
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_tick_kicks()
	if is_host() and dedicated and auto_start and state == State.LOBBY and can_start_match():
		start_match()
	if role == Role.CLIENT and _closing_reason != "" and _apply_queue.is_empty() \
			and (game == null or _last_applied_seq <= _digest_seq):
		_close_and_emit("ended", _closing_reason)
		return
	if state != State.IN_MATCH:
		return
	if is_host() and not _pending_round.is_empty() and reveal_timeout_ms > 0 \
			and Time.get_ticks_msec() > int(_pending_round["deadline"]):
		_host_cheat(_first_missing_contributor(int(_pending_round["seq"])), "reveal_timeout")
		return
	if game == null:
		return
	# 1. The previous action (and everything it deferred) has settled: publish /
	#    record the digest for it.
	if _last_applied_seq > _digest_seq:
		_record_digest(_last_applied_seq)
	# 2. Apply one queued accepted action (its randomness is complete).
	if not _apply_queue.is_empty():
		_apply_now(_apply_queue.pop_front())
		return
	# 3. Host: validate one intent -- only when no RNG round is in flight, so
	#    every intent is validated against the state after all earlier actions.
	if is_host() and _pending_round.is_empty() and not _intent_queue.is_empty():
		var entry: Array = _intent_queue.pop_front()
		_host_handle_intent(int(entry[0]), entry[1])


func _host_handle_intent(actor_slot: int, action: Dictionary) -> void:
	var reason := _validate(actor_slot, action)
	if reason == "" and max_actions > 0 and _seq >= max_actions:
		reason = "action_limit"
	if reason != "":
		var pid := _peer_for_slot(actor_slot)
		if pid == SERVER_PEER_ID:
			intent_rejected.emit(action, reason)
		elif pid != -1:
			_rpc_intent_rejected.rpc_id(pid, action, reason)
		return
	# ACCEPT: from here the action is irrevocable. Only now does the host reveal
	# its share for this seq, and only after seeing it do the other contributors
	# reveal theirs -- so nobody could know the roll when the action was chosen.
	_seq += 1
	action[NetProtocol.KEY_SEQ] = _seq
	action[NetProtocol.KEY_ACTOR] = actor_slot
	action.erase(NetProtocol.KEY_RNG)
	var share := _rng.own_share(_seq)
	var own_err := _rng.accept_own(_seq, share)
	if own_err != "":
		push_error("NetSession: own RNG share rejected (%s)" % own_err)
	_rpc_accepted.rpc(action, _outgoing(share))   # call_remote: clients verify + reveal
	_pending_round = {"seq": _seq, "action": action,
		"deadline": Time.get_ticks_msec() + reveal_timeout_ms}
	_host_try_finish_round()


func _host_try_finish_round() -> void:
	if _pending_round.is_empty():
		return
	var seq: int = int(_pending_round["seq"])
	if not _rng.has_round(seq):
		return
	var action: Dictionary = _pending_round["action"]
	_pending_round = {}
	var shares := {}
	for p in _rng.contributors:
		if p != SERVER_PEER_ID:
			shares[p] = _rng.share_of(p, seq)
	if not shares.is_empty():
		_rpc_round.rpc(seq, shares)
	action[NetProtocol.KEY_RNG] = int(_rng.seed_for(seq))
	_rng.consume(seq)
	_apply_queue.append(action)


func _validate(actor_slot: int, action: Dictionary) -> String:
	if not NetProtocol.is_well_formed(action):
		return "malformed"
	if debug_accept_everything and is_host():
		return ""
	if actor_slot < 0:
		return "unknown_actor"
	if game == null:
		return "no_game"
	return String(game.validate_intent(action, actor_slot))


func _apply_now(action: Dictionary) -> void:
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	if seq <= _last_applied_seq:
		return  # duplicate / stale
	if role == Role.CLIENT and verify_host_actions:
		# Clients re-check the host's decision on their own (identical) state: a
		# host that accepts an illegal action is caught, not obeyed.
		var why := _validate(int(action.get(NetProtocol.KEY_ACTOR, -1)), action)
		if why != "":
			_client_cheat("illegal_action:" + why)
			return
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


## A share on its way out (TEST HOOK: a tampering peer flips a bit).
func _outgoing(share: Dictionary) -> Dictionary:
	if not debug_tamper_shares or share.is_empty():
		return share
	var bad := share.duplicate(true)
	var r: PackedByteArray = bad[NetCommitReveal.K_REVEAL].duplicate()
	r[0] = r[0] ^ 0x01
	bad[NetCommitReveal.K_REVEAL] = r
	return bad


func _first_missing_contributor(seq: int) -> int:
	for p in _rng.contributors:
		if not _rng.has_share(p, seq):
			return p
	return -1


## Host / server caught [param peer_id] cheating (bad share, bad commitment,
## withheld reveal): end the match for everyone.
func _host_cheat(peer_id: int, reason: String) -> void:
	push_warning("NetSession: randomness verification FAILED for peer %d (%s) -- ending the match" % [peer_id, reason])
	cheat_detected.emit(peer_id, reason)
	var public_reason := "reveal_timeout" if reason == "reveal_timeout" else "rng_verification_failed"
	_rpc_match_ended.rpc(public_reason)
	if dedicated:
		reset_to_lobby()
	else:
		_reset_match_state()
		state = State.LOBBY
	match_aborted.emit(public_reason)


## A client caught the HOST cheating: randomness that does not verify, an
## accepted action that is illegal on the (identical) client state, or an
## action in the client's seat the client never submitted.
func _client_cheat(reason: String) -> void:
	push_warning("NetSession: host verification FAILED (%s) -- leaving the match" % reason)
	cheat_detected.emit(SERVER_PEER_ID, reason)
	call_deferred("_close_and_emit", "ended", "host_verification_failed")
	state = State.LOBBY  # stop applying anything else from this host


# ---------------------------------------------------------------------------
# Connection lifecycle
# ---------------------------------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if not is_host():
		return
	# Seat on _rpc_announce; refuse early when there is no room at all.
	if state == State.IN_MATCH or state == State.STARTING:
		_reject(peer_id, "match_in_progress")
	elif _roster.size() >= max_players:
		_reject(peer_id, "lobby_full")


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	_kick_at.erase(peer_id)
	if not _roster.has(peer_id):
		return
	var slot: int = _roster[peer_id]["slot"]
	_roster.erase(peer_id)
	player_left.emit(peer_id, slot)
	if state == State.IN_MATCH or state == State.STARTING:
		# A seated player dropped mid-match: the match cannot continue. Tell the
		# other seat(s) (dedicated server: the remaining client).
		_rpc_match_ended.rpc("opponent_disconnected")
		if dedicated:
			reset_to_lobby()
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
	if _closing_reason != "":
		call_deferred("_close_and_emit", "ended", _closing_reason)
		return
	var was_in_match := state == State.IN_MATCH or state == State.STARTING
	call_deferred("_close_and_emit", "host_lost", "in_match" if was_in_match else "")


func _close_and_emit(kind: String, detail: String) -> void:
	if role == Role.NONE and kind != "rejected":
		return  # already closed (e.g. match_ended then the server's kick)
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
		"ended":
			match_aborted.emit(detail)
			disconnected.emit(detail)


func _reject(peer_id: int, reason: String) -> void:
	_rpc_join_rejected.rpc_id(peer_id, reason)
	# Give the rejection a moment to flush before dropping the peer.
	_kick_at[peer_id] = Time.get_ticks_msec() + 250


func _tick_kicks() -> void:
	if _kick_at.is_empty() or _peer == null:
		return
	var now := Time.get_ticks_msec()
	for pid in _kick_at.keys():
		if now >= int(_kick_at[pid]):
			_kick_at.erase(pid)
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
	if _roster.has(peer_id) or _kick_at.has(peer_id):
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


## Dedicated server: the lobby leader (slot 0) asks to change the config.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_config(config: Dictionary) -> void:
	if not is_host() or not dedicated or config_locked or state != State.LOBBY:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _roster.has(peer_id) or int(_roster[peer_id]["slot"]) != 0:
		return
	_host_apply_config(config)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(action: Dictionary) -> void:
	if not is_host() or state != State.IN_MATCH:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	# The actor is ALWAYS derived from the sender's seat, never from the payload.
	var slot: int = int(_roster[peer_id]["slot"]) if _roster.has(peer_id) else -1
	_intent_queue.append([slot, action])


## Commit phase: a contributor's hash-chain anchor.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_commit(anchor: PackedByteArray) -> void:
	if not is_host() or state != State.STARTING or _rng == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _rng.is_contributor(peer_id):
		return
	if not _rng.set_anchor(peer_id, anchor):
		_host_cheat(peer_id, "bad_commitment")
		return
	_host_try_finish_commit()


## Reveal phase: a contributor's share for accepted action [param seq].
@rpc("any_peer", "call_remote", "reliable")
func _rpc_share(seq: int, share: Dictionary) -> void:
	if not is_host() or state != State.IN_MATCH or _rng == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _rng.is_contributor(peer_id):
		return
	if _pending_round.is_empty() or int(_pending_round["seq"]) != seq:
		_host_cheat(peer_id, "unexpected_share")
		return
	var err := _rng.accept_share(peer_id, seq, share)
	if err != "":
		_host_cheat(peer_id, err)
		return
	_host_try_finish_round()


# ---------------------------------------------------------------------------
# RPCs: host -> clients
# ---------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_sync_lobby(roster: Dictionary, config: Dictionary, meta: Dictionary) -> void:
	var was_seated := _local_slot != -1
	_roster = roster
	_server_meta = meta
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


## Commit phase (clients): generate our chain, record the host's anchor, and
## send ours if we contribute.
@rpc("authority", "call_remote", "reliable")
func _rpc_commit_request(contributors: Array, chain_length: int, host_anchor: PackedByteArray) -> void:
	if state != State.LOBBY:
		return
	state = State.STARTING
	_rng = NetCommitReveal.new(chain_length)
	var clean: Array = []
	for p in contributors:
		clean.append(int(p))
	var my_anchor := _rng.begin(local_peer_id(), clean)
	if not _rng.is_contributor(SERVER_PEER_ID) or not _rng.set_anchor(SERVER_PEER_ID, host_anchor):
		_client_cheat("bad_host_commitment")
		return
	if _rng.is_contributor(local_peer_id()):
		_rpc_commit.rpc_id(SERVER_PEER_ID, my_anchor)


@rpc("authority", "call_local", "reliable")
func _rpc_match_started(config: Dictionary) -> void:
	if not is_host():
		# Every anchor must be the one committed to us (the host's from the commit
		# request, ours as generated); others are recorded now. The setup seed must
		# be the one derived from them.
		if _rng == null or state != State.STARTING:
			_client_cheat("no_commitment")
			return
		var anchors: Dictionary = config.get("anchors", {})
		for p in _rng.contributors:
			# set_anchor refuses to CHANGE a known anchor (the host's, ours).
			if not anchors.has(p) or not _rng.set_anchor(int(p), anchors[p]):
				_client_cheat("bad_commitment_set")
				return
		if not _rng.has_all_anchors() or int(config.get("seed", 0)) != _rng.setup_seed():
			_client_cheat("bad_setup_seed")
			return
	state = State.IN_MATCH
	_match_config = config.duplicate(true)
	_seq = 0
	_last_accepted_seq = 0
	_last_applied_seq = 0
	_digest_seq = 0
	_apply_queue.clear()
	_intent_queue.clear()
	match_started.emit(_match_config.duplicate(true))


## An accepted action + the host's (verifiable) share for it.
@rpc("authority", "call_remote", "reliable")
func _rpc_accepted(action: Dictionary, host_share: Dictionary) -> void:
	if state != State.IN_MATCH or _rng == null:
		return
	var seq: int = int(action.get(NetProtocol.KEY_SEQ, 0))
	if seq != _last_accepted_seq + 1 or not NetProtocol.is_well_formed(action):
		_client_cheat("out_of_order_action")
		return
	var err := _rng.accept_share(SERVER_PEER_ID, seq, host_share)
	if err != "":
		_client_cheat(err)
		return
	# An action in OUR seat must be the next intent we actually submitted: the
	# host cannot puppet our units.
	if verify_host_actions and int(action.get(NetProtocol.KEY_ACTOR, -1)) == _local_slot:
		var mine: Dictionary = _my_intents.pop_front() if not _my_intents.is_empty() else {}
		if mine.is_empty() or int(mine[NetProtocol.KEY_TYPE]) != int(action[NetProtocol.KEY_TYPE]) \
				or mine[NetProtocol.KEY_DATA] != action[NetProtocol.KEY_DATA]:
			_client_cheat("forged_action")
			return
	_last_accepted_seq = seq
	action.erase(NetProtocol.KEY_RNG)  # never trust a seed on the wire
	_awaiting_rng[seq] = action
	var me := local_peer_id()
	if _rng.is_contributor(me):
		# The action is already accepted (irrevocable): now reveal ours.
		var share := _rng.own_share(seq)
		var own_err := _rng.accept_own(seq, share)
		if own_err != "":
			push_error("NetSession: own RNG share rejected (%s)" % own_err)
		if debug_hold_shares:
			_held_shares.append([seq, _outgoing(share)])
		else:
			_rpc_share.rpc_id(SERVER_PEER_ID, seq, _outgoing(share))
	_client_try_finish_round(seq)


## The other contributors' shares for [param seq], relayed by the host.
@rpc("authority", "call_remote", "reliable")
func _rpc_round(seq: int, shares: Dictionary) -> void:
	if state != State.IN_MATCH or _rng == null or not _awaiting_rng.has(seq):
		return
	var me := local_peer_id()
	for p in _rng.contributors:
		if p == SERVER_PEER_ID:
			continue
		if not shares.has(p):
			_client_cheat("missing_share")
			return
		if p == me:
			# The host must relay OUR share untouched.
			var mine = _rng.share_of(me, seq).get(NetCommitReveal.K_REVEAL)
			if mine == null or not (shares[p] is Dictionary) or shares[p].get(NetCommitReveal.K_REVEAL) != mine:
				_client_cheat("altered_share")
				return
			continue
		var err := _rng.accept_share(int(p), seq, shares[p])
		if err != "":
			_client_cheat(err)
			return
	_client_try_finish_round(seq)


func _client_try_finish_round(seq: int) -> void:
	if not _awaiting_rng.has(seq) or not _rng.has_round(seq):
		return
	var action: Dictionary = _awaiting_rng[seq]
	_awaiting_rng.erase(seq)
	action[NetProtocol.KEY_RNG] = int(_rng.seed_for(seq))
	_rng.consume(seq)
	_apply_queue.append(action)


@rpc("authority", "call_remote", "reliable")
func _rpc_intent_rejected(action: Dictionary, reason: String) -> void:
	if not _my_intents.is_empty():
		_my_intents.pop_front()   # answers arrive in submission order
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


## The host ended the match. "match_complete" waits until every accepted action
## was applied locally; anything else closes at once.
@rpc("authority", "call_remote", "reliable")
func _rpc_match_ended(reason: String) -> void:
	if role != Role.CLIENT:
		return
	if reason == "match_complete":
		_closing_reason = reason
	else:
		state = State.LOBBY
		call_deferred("_close_and_emit", "ended", reason)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _broadcast_lobby() -> void:
	roster_changed.emit(get_roster())
	config_changed.emit(_config.duplicate(true))
	if is_host():
		_rpc_sync_lobby.rpc(_roster, _config, {"dedicated": dedicated, "locked": config_locked})


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
