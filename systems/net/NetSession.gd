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
##   join    a client's FIRST message is a hello (name + PROTOCOL_VERSION + game
##           version, [method NetProtocol.make_hello]); the host runs the build gate
##           ([method NetProtocol.validate_hello]) BEFORE seating it -- a protocol
##           mismatch is refused with a reason the client can show
##           ([signal join_rejected] + [method NetProtocol.describe_rejection]).
##   lobby   host seats peers (peer -> slot map owned by the host) -> set_ready ->
##           config -> start_match (only when full + all ready, once). Free-form
##           pre-match traffic (map votes, profile / loadout cards) rides the LOBBY
##           CHANNEL ([method send_lobby_message] / [signal lobby_message]): relayed by
##           the host, never echoed to the sender, never applied to game state.
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
##           mid-match raises [signal opponent_left] (a loss for the leaver -- the
##           battle HUD turns it into the survivor's victory) and then
##           [signal match_aborted]; a deliberate [method forfeit_match] is announced
##           first as [signal opponent_forfeited].
##
## Outside a match this node also carries the BATTLE SEAM every battle (solo too)
## installs ([method install_command_seam]): the [CommandApplier] replays drive, and
## the solo per-command RNG stream ([member match_rng], [method begin_solo_match_rng]).

signal roster_changed(roster: Dictionary)
## A player was seated (host + clients). peer_id is the transport peer id.
signal player_joined(peer_id: int, slot: int, player_name: String)
signal player_left(peer_id: int, slot: int)
## Client: we were seated by the host (our slot is known).
signal joined(slot: int)
## Client: the host refused us -- session closed. [param reason] is one of
## NetProtocol's REJECT_* constants; [param info] is the version detail dictionary
## [method NetProtocol.validate_hello] produced (may be empty), ready for
## [method NetProtocol.describe_rejection].
signal join_rejected(reason: String, info: Dictionary)
## Host: a joining peer was refused, so a host UI can say why.
signal peer_join_refused(peer_id: int, reason: String, info: Dictionary)
## The lobby config (map / turn system) changed. Host and clients.
signal config_changed(config: Dictionary)
## The match started; [param config] is the host's authoritative match config
## (map_path, turn_system, seed (setup RNG), slots: {slot:int -> name}, anchors,
## plus whatever the player-host's lobby added: map_payload, host_squad, ...).
signal match_started(config: Dictionary)
## An accepted action was applied locally (after game.apply_action ran).
signal action_applied(action: Dictionary, result: Dictionary)
## An intent this peer submitted was rejected by the host. [param reason] is a
## NetProtocol.INTENT_* wire string (see [method NetProtocol.describe_intent_rejection]).
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
## "match_complete" (dedicated server closed a finished match),
## [constant ABORT_UNDRIVEN_TURN] (the rules handed the turn to a slot no seat occupies).
signal match_aborted(reason: String)
## The connection to the host was lost (client) -- session already closed.
signal disconnected(reason: String)
## A join attempt failed to connect -- session already closed.
signal connection_failed()
## A free-form LOBBY message arrived from another participant. This is the pre-match
## channel (map votes, ready flags, profile / loadout cards) -- deliberately separate
## from the gameplay vocabulary in [NetProtocol], which is validated, sequenced and
## RNG-stamped. Lobby messages are relayed by the host, never applied to game state,
## and only ever delivered to peers OTHER than the sender. [param from_slot] is the
## sender's roster slot as the HOST stamped it (-1 if it had none yet). Treat
## [param data] as untrusted peer input.
signal lobby_message(message_type: String, data: Dictionary, from_slot: int)
## Another participant FORFEITED the live match (the pause menu's "Forfeit Match").
## [param slot] is the forfeiting player's roster slot, taken from the HOST's relay
## stamp rather than the sender's payload. The battle HUD turns it into a defeat for
## that slot so the remaining player gets the normal victory flow.
signal opponent_forfeited(slot: int)
## A participant vanished from a live match without forfeiting (crash, alt-F4, lost
## connection). Deliberately indistinguishable from a forfeit in OUTCOME -- leaving a
## live match is a loss either way. Emitted BEFORE [signal match_aborted] and while
## [method local_slot] is still valid, so the battle can resolve the win first.
signal opponent_left()
## Solo: the per-command RNG stream for this battle is ready (see
## [method begin_solo_match_rng]). Networked play has no single stream -- every
## accepted action carries its own commit-reveal seed.
signal match_rng_ready()

enum Role { NONE, HOST, CLIENT }
enum State { IDLE, LOBBY, STARTING, IN_MATCH }
## Who contributes randomness. ALL (default): the host / server AND every seated
## client. SERVER_ONLY: only the host -- allowed for a DEDICATED (trusted)
## server only, since a player-host would then know every future roll.
enum RngMode { ALL, SERVER_ONLY }

const DEFAULT_PORT := 8910
## Host abort reason: the rules say it is the turn of a slot NO seat occupies (an AI /
## neutral faction -- network play runs no AI), so nobody could ever submit the next
## action. The host ends the match instead of waiting forever. Offline-only maps are
## refused before a match starts (MapCatalog.network_refusal); this is the backstop.
const ABORT_UNDRIVEN_TURN := "undriven_turn"
const DEFAULT_ADDRESS := "127.0.0.1"
const SERVER_PEER_ID := 1
## Config keys a lobby leader may set on a dedicated server.
const CONFIG_KEYS := ["map_path", "turn_system", "auto_end_turn"]
## Lobby-channel message type for a deliberate forfeit. It rides the LOBBY channel,
## not the action vocabulary: a forfeit is a session event, not a board mutation, and
## it has to survive being sent by a peer that is about to disconnect itself.
const MSG_MATCH_FORFEIT := "match_forfeit"
## How long a gracefully closed transport peer is kept polling so its last reliable
## packets (a forfeit) are delivered before the socket goes away.
const DRAIN_MS := 600

## Seats in a match. Versus is 1v1 (no local map fields more than two human sides).
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
## Dedicated auto-start: func() -> Dictionary, the start's last word (the final config
## [method start_match] merges -- e.g. the seats' duel picks, DedicatedServer). Optional.
var auto_start_config: Callable = Callable()
## Dedicated: the config was fixed by the server (clients cannot change it).
var config_locked: bool = false
## What this lobby plays ([constant NetProtocol.MODE_CONQUEST] / [constant NetProtocol.MODE_DUEL]).
## Set BEFORE hosting / joining (the Versus screen's choice, a dedicated server's --mode):
## a joiner's hello names it and the host refuses another mode's joiner
## ([constant NetProtocol.REJECT_MODE_MISMATCH]); the host stamps it into the match config
## ([constant NetProtocol.CONFIG_MODE]) so every peer boots the same kind of battle. Not reset
## by [method leave] -- it is the screen's choice, not the connection's state.
var lobby_mode: String = NetProtocol.MODE_CONQUEST

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
## TEST HOOK: announce this PROTOCOL_VERSION in the join hello instead of ours (-1 = ours),
## to exercise the host's build gate over a real socket.
var debug_hello_protocol_version: int = -1

# --- Battle seam (every battle; see install_command_seam) ---------------------
## The battle's [CommandApplier] (THE apply path, bound to the live board) -- what
## replay playback drives. Null outside a battle.
var command_applier = null
## Source of the live board for [member command_applier]: func() -> board.
var board_provider: Callable = Callable()
## Solo / replay per-command RNG stream ([MatchRng]). Null in network play.
var match_rng: MatchRng = null

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
## Client: the last join refusal, kept AFTER the host drops us so the UI can explain
## the disconnect. { "reason": String, "info": Dictionary }; cleared by join_game.
var _last_join_rejection: Dictionary = {}

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
var _draining: Array = []              # [{peer, until}] peers closing gracefully (forfeit)


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
## [param players_max] > 0 overrides [member max_players] (versus is 2).
func host_game(player_name: String, port: int = DEFAULT_PORT, players_max: int = 0) -> Error:
	if players_max > 0:
		max_players = players_max
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


## Older name of [method host_dedicated] (no config, every seat contributes RNG).
func start_dedicated_server(port: int = DEFAULT_PORT, players_max: int = 0) -> Error:
	if players_max > 0:
		max_players = players_max
	return host_dedicated(port)


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
## a peer that is already gone). The lobby channel is relayed by the host itself.
func _disable_relay() -> void:
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).server_relay = false


## Join a host (player-hosted or dedicated) as a client. Connection completes
## asynchronously: listen for [signal joined] / [signal join_rejected] /
## [signal connection_failed]. The version handshake runs the moment the socket
## comes up (see [method _on_connected_to_server]).
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	_last_join_rejection = {}
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
## Safe to call at any time, repeatedly. The battle seam and the solo RNG stream
## are NOT touched (they belong to the battle, not the connection).
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


## Concede the live match and tear the session down. Quitting a networked battle is a
## LOSS, never a quiet exit, so this is the only way the pause menu leaves one.
##
## Announces first, leaves second: the forfeit rides the reliable LOBBY channel before
## [method leave] closes the peer. Even if that announcement were lost, the disconnect
## the other side then observes raises [signal opponent_left] -- which the battle treats
## identically -- so the match cannot hang on a dropped announcement.
##
## No-op (and returns false) outside a live networked match, so a solo caller is safe.
func forfeit_match() -> bool:
	if not is_networked_match():
		return false
	send_lobby_message(MSG_MATCH_FORFEIT, {"slot": _local_slot})
	_leave_gracefully()
	return true


## [method leave], but the transport peer is not slammed shut: ENet peers are asked to
## disconnect once their queued reliable packets (the forfeit announcement) are delivered,
## and the old peer is polled a moment longer from [method _process]. A hard close
## (disconnect_now) would drop what is still queued. The session itself is closed at once.
func _leave_gracefully() -> void:
	var draining := _peer
	var remote_ids: Array = []
	var connected: PackedInt32Array = multiplayer.get_peers() if is_connected_session() else PackedInt32Array()
	if is_host():
		for pid in _roster:
			if int(pid) != SERVER_PEER_ID and connected.has(int(pid)):
				remote_ids.append(int(pid))
	elif connected.has(SERVER_PEER_ID):
		remote_ids.append(SERVER_PEER_ID)
	_peer = null   # leave() must not close it
	leave()
	if draining is ENetMultiplayerPeer:
		var enet := draining as ENetMultiplayerPeer
		for pid in remote_ids:
			var pp: ENetPacketPeer = enet.get_peer(pid)
			if pp != null:
				pp.peer_disconnect_later()
		_draining.append({"peer": enet, "until": Time.get_ticks_msec() + DRAIN_MS})
	elif draining != null:
		draining.close()


func _tick_draining() -> void:
	if _draining.is_empty():
		return
	var now := Time.get_ticks_msec()
	var keep: Array = []
	for entry in _draining:
		var enet: ENetMultiplayerPeer = entry["peer"]
		enet.poll()
		if now >= int(entry["until"]) or enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			enet.close()
		else:
			keep.append(entry)
	_draining = keep


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
	# A refused map pick keeps the map already chosen, never "no map" (which every peer would
	# then resolve from its OWN GameSettings -- two different boards).
	if dedicated and not clean.has("map_path") and _config.has("map_path"):
		clean["map_path"] = _config["map_path"]
	if clean == _config:
		return
	_config = clean
	for pid in _roster:
		_roster[pid]["ready"] = false
	_broadcast_lobby()


static func _sanitize_config(config: Dictionary) -> Dictionary:
	var out := {}
	var map_path = config.get("map_path", "")
	# Shipped maps only, and only ones a two-seat, AI-free match can run: an offline-only
	# map (an AI neutral faction, AI-driven Siege creeps -- MapCatalog.network_refusal) is
	# dropped like any other unacceptable pick (_host_apply_config then keeps the previous map).
	if map_path is String and map_path.begins_with("res://") and not ".." in map_path \
			and MapCatalog.network_eligible(map_path):
		out["map_path"] = map_path
	var ts = config.get("turn_system", null)
	if typeof(ts) == TYPE_INT and ts >= 0 and ts <= 8:
		out["turn_system"] = ts
	var aet = config.get("auto_end_turn", null)
	if typeof(aet) == TYPE_BOOL:
		out["auto_end_turn"] = aet
	# Online duels: stage / weather / the seats' unit picks, whitelisted (DuelNetConfig).
	out.merge(DuelNetConfig.sanitize(config), true)
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
##
## [param final_config] (player-host) is merged into the lobby config for this match
## WITHOUT clearing ready flags -- the lobby's last word (the map the vote / coin flip
## settled on, a custom map's content, the host's squad, best-of rounds). A dedicated
## server sanitises it like any other config.
func start_match(final_config: Dictionary = {}) -> bool:
	if not can_start_match():
		return false
	var per_match := {}
	if not final_config.is_empty():
		var extra := _sanitize_config(final_config) if dedicated else final_config.duplicate(true)
		# The seats' duel picks belong to THIS match only (never the standing lobby config),
		# and a locked server config still takes them: they are the players' own choice.
		if extra.has(DuelNetConfig.KEY_UNITS):
			per_match[DuelNetConfig.KEY_UNITS] = extra[DuelNetConfig.KEY_UNITS]
			extra.erase(DuelNetConfig.KEY_UNITS)
		if not (dedicated and config_locked):
			_config.merge(extra, true)
	var cfg := _config.duplicate(true)
	cfg.merge(per_match, true)
	# The lobby's mode is the host's, whatever a config said (NetProtocol.CONFIG_MODE).
	cfg[NetProtocol.CONFIG_MODE] = lobby_mode
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


## Send a LOBBY message (map vote, ready flag, profile / loadout card, forfeit) to
## every OTHER participant. The host relays it; the sender never receives its own
## message back, so a lobby UI can broadcast unconditionally without filtering its
## own echo. NOT the gameplay path: lobby messages are not validated, sequenced or
## RNG-stamped and must never mutate battle state. Silent no-op without a live
## connected session, so a solo / menu caller is safe.
func send_lobby_message(message_type: String, data: Dictionary) -> void:
	if not is_connected_session():
		return
	if is_host():
		_host_relay_lobby_message(local_peer_id(), message_type, data)
	elif role == Role.CLIENT:
		_rpc_lobby_message.rpc_id(SERVER_PEER_ID, message_type, data)


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
	a.erase(NetProtocol.KEY_PV)
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
# Battle seam (installed per battle by GameWorldManager; cleared on exit)
# ---------------------------------------------------------------------------

## Install the battle's command seam: [param applier] (a [CommandApplier] -- THE apply
## path, bound to the live board) and [param provider] (func() -> board). Replay
## playback drives recorded commands through it; network play applies through the
## rules object GameModeManager attaches ([method attach_game]) -- the same class.
## Idempotent. [param _turn_source] is accepted for older callers and ignored: turns
## are derived from the rules' turn system, not bridged.
func install_command_seam(applier, provider: Callable = Callable(), _turn_source = null) -> void:
	command_applier = applier
	board_provider = provider
	_sync_applier_rng()


## Drop the battle seam so a stale applier never outlives the board it mutated.
func clear_command_seam() -> void:
	command_applier = null
	board_provider = Callable()


## The stable id ([NetUnitIds], "<slot>:<n>") naming [param unit] on every peer, or ""
## if it has none yet. The UI uses it to name the acting unit in an action.
func net_id_for(unit) -> String:
	return NetUnitIds.id_of(unit)


## Solo / hotseat: seed this battle's per-command stream from a fresh local source
## (the degenerate local case of lockstep; replays record [member MatchRng.match_seed]).
func begin_solo_match_rng() -> void:
	match_rng = MatchRng.new()
	match_rng.begin_solo(MatchRng.fresh_entropy())
	_local_command_seq = 0
	_local_command_seed = 0
	_sync_applier_rng()
	match_rng_ready.emit()


# ---------------------------------------------------------------------------
# The LOCAL command stream (solo / hot-seat live play)
# ---------------------------------------------------------------------------
#
# A replay re-applies each recorded command through the command seam, which rolls from a
# generator seeded by the command's stamped seed (NetGameRules.rng_for_action) and leaves it
# installed as CombatServices.match_rng for whatever the command sets off (a status tick at
# the turn it opened, a trap sprung by a move). Live LOCAL play resolves commands directly
# (UnitActionsPanel, BotTurnDriver) rather than through that seam, so it must roll from the
# very same generator or the replay re-decides every hit, miss and crit. Each local commit
# site therefore BEGINS its command here before resolving it, and the recorder stamps the
# seed it was given onto the recorded command -- the live battle and its playback then draw
# the identical sequence. Network play never uses this: every accepted action carries its own
# verified seed.

## Seq of the last local command begun this battle (the solo stream's per-command index).
var _local_command_seq: int = 0
## Seed of the local command begun and not yet recorded; 0 when there is none.
var _local_command_seed: int = 0

## Domain of the solo stream the pre-first-command setup generator is drawn from (commands
## start at seq 1, so this never collides with one).
const LOCAL_SETUP_SEQ := 0
## Domain of the solo stream a local battle's dynamic weather is seeded from.
const LOCAL_WEATHER_SEQ := -1


## True when this session has a ready solo stream and is NOT in a network match.
func has_local_stream() -> bool:
	return match_rng != null and match_rng.is_ready() and not is_networked_match()


## BEGIN one locally-committed command: derive its generator from the next seed of the solo
## stream, install it as [member CombatServices.match_rng] (exactly where the apply path
## installs an applied command's), remember the seed for the recorder, and return it for the
## caller to hand to [method Unit.perform_move]. Null -- and nothing touched -- when there is
## no solo stream (a network match, a headless harness), so the caller rolls as it always did.
func begin_local_command() -> RandomNumberGenerator:
	_local_command_seed = 0
	if not has_local_stream():
		return null
	_local_command_seq += 1
	var seed_value: int = match_rng.seed_for(_local_command_seq)
	# 0 is "unstamped" on the wire (the applier would fall back to the seq stream), so a 0
	# seed -- one in 2^64 -- is nudged rather than silently changing meaning on playback.
	if seed_value == 0:
		seed_value = 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_local_command_seed = seed_value
	NetGameRules._install_rng(rng)
	return rng


## The seed of the local command begun and not yet recorded, CONSUMED (a second read is 0).
## The recorder stamps it onto the command it records; 0 means "nothing was begun", which
## records an unstamped command exactly as before.
func take_local_command_seed() -> int:
	var s: int = _local_command_seed
	_local_command_seed = 0
	return s


## Install the generator every roll made BEFORE the first local command draws from (the
## opening turn's ticks), derived from the match seed -- so the live battle and its playback
## (which re-seeds the recorded match seed first) roll those identically too. No-op without a
## solo stream.
func install_local_setup_rng() -> void:
	if not has_local_stream():
		return
	NetGameRules.install_setup_rng(match_rng.seed_for(LOCAL_SETUP_SEQ))


## Seed for a LOCAL battle's dynamic weather: derived from the match seed, so a replay (which
## restores the recorded match seed before the weather is configured) rolls the same sky.
## Falls back to fresh entropy without a solo stream.
func local_weather_seed() -> int:
	if has_local_stream():
		return match_rng.seed_for(LOCAL_WEATHER_SEQ)
	return randi()


## [method begin_local_command] on the autoload, for the local commit sites; null when there
## is no NetSession autoload (a headless unit test).
static func begin_local_command_rng() -> RandomNumberGenerator:
	var ns = _autoload()
	return ns.begin_local_command() if ns != null else null


static func _autoload():
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree):
		return null
	var node = (loop as SceneTree).root.get_node_or_null("NetSession")
	return node if node is NetSessionNode else null


## Hand the CURRENT solo stream to an installed applier (every path that replaces
## [member match_rng] calls this, so an applier never rolls a stale stream).
func _sync_applier_rng() -> void:
	if command_applier != null and "match_rng" in command_applier:
		command_applier.match_rng = match_rng


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_host() -> bool:
	return role == Role.HOST

## Older name of [method is_host] (lobby / test doubles).
func is_server() -> bool:
	return is_host()

func is_active() -> bool:
	return role != Role.NONE

func is_in_match() -> bool:
	return role != Role.NONE and state == State.IN_MATCH

## True when a REAL transport peer is installed and connected. The tree's default
## OfflineMultiplayerPeer reports CONNECTION_CONNECTED with id 1, so a naive status
## check reads "connected" in every solo process -- which once made the lobby RPC to
## itself and drop votes.
func is_connected_session() -> bool:
	if multiplayer == null:
		return false
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

## True in a live, connected network match with more than one seated participant --
## the single gate the battle uses to decide "route this command through
## submit_intent instead of executing it locally" (and MapLoader / ItemSystem / fog /
## save / pause read it too). False for solo / hotseat / local versus and in the lobby.
func is_networked_match() -> bool:
	return is_connected_session() and player_count() > 1 \
		and (state == State.IN_MATCH or state == State.STARTING)

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

## Client: why the last join was refused, or {} when it was not. { "reason": String,
## "info": Dictionary }. Survives the disconnect that follows a refusal (and
## [method leave]); [method join_game] clears it.
func last_join_rejection() -> Dictionary:
	return _last_join_rejection.duplicate(true)

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
	_tick_draining()
	_tick_kicks()
	if is_host() and dedicated and auto_start and state == State.LOBBY and can_start_match():
		start_match(auto_start_config.call() if auto_start_config.is_valid() else {})
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
	# 1b. Host: the settled turn belongs to a slot nobody sits in -- no intent can ever
	#     arrive for it, so end the match rather than deadlock (see ABORT_UNDRIVEN_TURN).
	if is_host() and _apply_queue.is_empty() and _pending_round.is_empty() \
			and _current_turn_slot >= 0 and not _slot_is_seated(_current_turn_slot):
		_host_abort(ABORT_UNDRIVEN_TURN)
		return
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
		reason = NetProtocol.INTENT_ACTION_LIMIT
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


## Why [param action] may not be applied for [param actor_slot], or "" when legal
## (a NetProtocol.INTENT_* wire string).
func _validate(actor_slot: int, action: Dictionary) -> String:
	if not NetProtocol.is_well_formed(action):
		return NetProtocol.INTENT_MALFORMED
	if debug_accept_everything and is_host():
		return NetProtocol.INTENT_OK
	if actor_slot < 0:
		return NetProtocol.INTENT_UNKNOWN_ACTOR
	if game == null:
		return NetProtocol.INTENT_NO_GAME
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


## Host: end the running match for everyone with the abort [param reason] (clients raise
## [signal match_aborted] with it; so does the host). A dedicated server reopens its lobby.
func _host_abort(reason: String) -> void:
	push_warning("NetSession: ending the match (%s)" % reason)
	_rpc_match_ended.rpc(reason)
	if dedicated:
		reset_to_lobby()
	else:
		_reset_match_state()
		state = State.LOBBY
	match_aborted.emit(reason)


## True when some seated peer (the player-host included) holds [param slot].
func _slot_is_seated(slot: int) -> bool:
	for pid in _roster:
		if int(_roster[pid]["slot"]) == slot:
			return true
	return false


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
	# Seat on _rpc_hello (after the build gate); refuse early when there is no room.
	if state == State.IN_MATCH or state == State.STARTING:
		_refuse_peer(peer_id, NetProtocol.REJECT_MATCH_IN_PROGRESS, {})
	elif _roster.size() >= max_players:
		_refuse_peer(peer_id, NetProtocol.REJECT_LOBBY_FULL, {})


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_host():
		return
	_kick_at.erase(peer_id)
	if not _roster.has(peer_id):
		return
	var was_live := state == State.IN_MATCH or state == State.STARTING
	if was_live and not dedicated:
		# A seat vanished mid-match: a loss for them. Raised while our own seat and the
		# roster are still intact, so the battle can resolve the win before the abort.
		opponent_left.emit()
	var slot: int = _roster[peer_id]["slot"]
	_roster.erase(peer_id)
	player_left.emit(peer_id, slot)
	if was_live:
		# The match cannot continue. Tell the other seat(s) (dedicated server: the
		# remaining client, who raises opponent_left on its side).
		_rpc_match_ended.rpc("opponent_disconnected")
		if dedicated:
			reset_to_lobby()
		match_aborted.emit("opponent_disconnected")
	else:
		for pid in _roster:
			_roster[pid]["ready"] = false
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	# Our FIRST message is the hello (name + version stamps). The host seats us only
	# if the build matches -- see _rpc_hello.
	var hello := NetProtocol.make_hello(_pending_name, "", lobby_mode)
	if debug_hello_protocol_version >= 0:
		hello[NetProtocol.KEY_HELLO_PV] = debug_hello_protocol_version
	_rpc_hello.rpc_id(SERVER_PEER_ID, hello)


# These fire from inside the MultiplayerAPI poll, so the peer is torn down on the
# next idle step (call_deferred) rather than closed mid-poll.
func _on_connection_failed() -> void:
	call_deferred("_close_and_emit", "connection_failed", "")


func _on_server_disconnected() -> void:
	if _closing_reason != "":
		call_deferred("_close_and_emit", "ended", _closing_reason)
		return
	if not _last_join_rejection.is_empty() and _local_slot == -1:
		return  # the refusal already explained (and closed) this attempt
	var was_in_match := state == State.IN_MATCH or state == State.STARTING
	call_deferred("_close_and_emit", "host_lost", "in_match" if was_in_match else "")


func _close_and_emit(kind: String, detail: String) -> void:
	if role == Role.NONE and kind != "rejected":
		return  # already closed (e.g. match_ended then the server's kick)
	# Leaving a live match (the other side vanished) is a loss for the leaver: say so
	# while our seat is still known, before the session is torn down.
	var opponent_gone := (kind == "host_lost" and detail == "in_match") \
		or (kind == "ended" and detail == "opponent_disconnected")
	if opponent_gone and _local_slot >= 0:
		opponent_left.emit()
	leave()
	match kind:
		"connection_failed":
			connection_failed.emit()
		"host_lost":
			if detail == "in_match":
				match_aborted.emit("host_disconnected")
			disconnected.emit("host_disconnected")
		"rejected":
			join_rejected.emit(detail, _last_join_rejection.get("info", {}))
		"ended":
			match_aborted.emit(detail)
			disconnected.emit(detail)


## Host: tell [param peer_id] why it may not join, then drop it after a short flush
## so the rejection actually arrives before the socket closes.
func _refuse_peer(peer_id: int, reason: String, info: Dictionary) -> void:
	if _kick_at.has(peer_id):
		return
	peer_join_refused.emit(peer_id, reason, info)
	if _peer != null:
		_rpc_join_rejected.rpc_id(peer_id, reason, info)
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

## A client said hello (display name + version stamps). The build gate runs BEFORE
## it gets a roster slot.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(hello: Dictionary) -> void:
	if not is_host():
		return
	_host_admit_peer(multiplayer.get_remote_sender_id(), hello)


## Host: run the build gate on [param hello] and seat [param peer_id] if it passes.
## Split out of [method _rpc_hello] so the seating rules can be driven directly.
func _host_admit_peer(peer_id: int, hello: Dictionary) -> void:
	if not is_host():
		return
	if _roster.has(peer_id) or _kick_at.has(peer_id):
		return
	var check: Dictionary = NetProtocol.validate_hello(hello, NetProtocol.PROTOCOL_VERSION, "", lobby_mode)
	if not bool(check.get("accepted", false)):
		_refuse_peer(peer_id, String(check.get("reason", NetProtocol.REJECT_MALFORMED_HELLO)), check)
		return
	if state != State.LOBBY:
		_refuse_peer(peer_id, NetProtocol.REJECT_MATCH_IN_PROGRESS, check)
		return
	var slot := _first_free_slot()
	if slot == -1:
		_refuse_peer(peer_id, NetProtocol.REJECT_LOBBY_FULL, check)
		return
	if bool(check.get("build_differs", false)):
		# Not fatal (an editor run joining an exported build is a legitimate test
		# setup), but worth saying when someone is chasing a desync.
		print("[NET] Peer %d joined on game version '%s' while this host runs '%s'." % [
			peer_id, String(check.get("client_game", "?")), String(check.get("host_game", "?"))])
	var clean := String(check.get("name", "")).strip_edges().left(24)
	if clean == "":
		clean = "Player %d" % (slot + 1)
	_roster[peer_id] = {"slot": slot, "name": clean, "ready": false}
	player_joined.emit(peer_id, slot, clean)
	_broadcast_lobby()


## Older name of [method _host_admit_peer].
func _server_admit_peer(peer_id: int, hello: Dictionary) -> void:
	_host_admit_peer(peer_id, hello)


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


## Client -> host: please relay this lobby message to the others.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_lobby_message(message_type: String, data: Dictionary) -> void:
	if not is_host():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if not _roster.has(peer_id):
		return  # unseated (not past the build gate) peers have no voice in the lobby
	_host_relay_lobby_message(peer_id, message_type, data)


## Host: fan [param message_type] out to every participant except [param from_peer],
## stamped with the sender's slot from the HOST's roster. A player-host is a
## participant too, so it receives messages that came from a client.
func _host_relay_lobby_message(from_peer: int, message_type: String, data: Dictionary) -> void:
	if not is_host():
		return
	var from_slot: int = int(_roster[from_peer]["slot"]) if _roster.has(from_peer) else -1
	if is_connected_session():
		var connected: PackedInt32Array = multiplayer.get_peers()
		for peer_id in _roster:
			if peer_id == from_peer or peer_id == SERVER_PEER_ID or not connected.has(peer_id):
				continue
			_rpc_lobby_deliver.rpc_id(peer_id, message_type, data, from_slot)
	if from_peer != local_peer_id() and from_peer != SERVER_PEER_ID:
		_deliver_lobby_message(message_type, data, from_slot)


## Older name of [method _host_relay_lobby_message].
func _server_relay_lobby_message(from_peer: int, message_type: String, data: Dictionary) -> void:
	_host_relay_lobby_message(from_peer, message_type, data)


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


## Host -> one client: your join was refused, and why. Remembered so the
## disconnect that follows can still be explained.
@rpc("authority", "call_remote", "reliable")
func _rpc_join_rejected(reason: String, info: Dictionary) -> void:
	_last_join_rejection = {"reason": reason, "info": info}
	call_deferred("_close_and_emit", "rejected", reason)


## Host -> one client: a lobby message from another participant.
@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_deliver(message_type: String, data: Dictionary, from_slot: int) -> void:
	_deliver_lobby_message(message_type, data, from_slot)


## The ONE local delivery point for an incoming lobby message (host relay and client
## RPC both land here): the raw [signal lobby_message] for lobby UIs, then the system
## types routed to their own signals. [param data] is UNTRUSTED -- a forfeit names the
## slot the HOST stamped whenever it has one; the payload's slot is only a fallback.
func _deliver_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	lobby_message.emit(message_type, data, from_slot)
	if message_type == MSG_MATCH_FORFEIT:
		var slot: int = from_slot if from_slot >= 0 else int(data.get("slot", -1))
		opponent_forfeited.emit(slot)


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
	if is_host() and _peer != null:
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
