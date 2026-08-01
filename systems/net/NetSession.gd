extends Node
## NetSession — the single, server-authoritative multiplayer session manager.
##
## Consolidates the old NetworkManager / MultiplayerManager / MultiplayerGameState /
## MultiplayerNetworkHandler stack into one node built directly on Godot's
## high-level multiplayer (ENetMultiplayerPeer + scene-tree RPC).
##
## Design:
##   • Server-authoritative. Clients never mutate shared state directly — they
##     [method submit_intent]. The server validates via [member action_validator]
##     and, if legal, broadcasts the resolved action to everyone (including
##     itself) via an authority RPC. This is the model that scales safely to
##     more players and prevents cheating/desync.
##   • N players. The roster is a peer_id → slot map owned by the server; nothing
##     is hardcoded to 2. Change [member max_players] before hosting.
##   • One MultiplayerAPI. Uses [code]multiplayer[/code] (the scene tree's default
##     interface). It does NOT create a second MultiplayerAPI — a bug in the old
##     P2P backend that caused double-polling.
##
## Register as an autoload named "NetSession" (see systems/net/README.md).

## Emitted on the server AND clients whenever the roster changes (join/leave/ready).
signal roster_changed(roster: Dictionary)
## A player fully joined (has a slot and a name). peer_id is the ENet id.
signal player_joined(peer_id: int, slot: int, player_name: String)
## A player disconnected.
signal player_left(peer_id: int, slot: int)
## The session moved from lobby into an active match.
signal match_started()
## A validated action was applied locally — the game should mutate state here.
signal action_applied(action: Dictionary)
## An intent this peer submitted was rejected by the server.
signal intent_rejected(action: Dictionary, reason: String)
## Whose turn it is changed. slot is the active player's slot.
signal turn_changed(slot: int)
## Connection to the server was lost (client side), or hosting stopped.
signal disconnected()
## A join attempt failed to connect.
signal connection_failed()
## The commit-reveal match-RNG handshake completed on this peer; [member match_rng]
## is now READY and per-command seeds are derivable. Emitted on host and each client.
signal match_rng_ready()

enum Role { NONE, LISTEN_SERVER, DEDICATED_SERVER, CLIENT }

const DEFAULT_PORT := 8910
const SERVER_PEER_ID := 1

@export var max_players: int = 4

## Optional gameplay hook. Signature: func(action: Dictionary, actor_slot: int) -> bool.
## Runs only on the server. Return false to reject an intent. When null, the only
## checks are protocol well-formedness and turn ownership.
var action_validator: Callable = Callable()

## Set false if your game manages turns entirely itself and you don't want
## NetSession to gate intents by turn ownership.
@export var enforce_turn_ownership: bool = true

var role: Role = Role.NONE
## peer_id -> { "slot": int, "name": String, "ready": bool }
var _roster: Dictionary = {}
var _local_slot: int = -1
var _current_turn_slot: int = -1
var _seq: int = 0
var _pending_name: String = "Player"

var _peer: ENetMultiplayerPeer = null

## Commit-reveal match RNG (see [MatchRng]). Built by the handshake below; null until
## a match's seed is negotiated. The authority derives per-command seeds from it.
var match_rng: MatchRng = null

## Optional: the ONE mutation point. When set, [method _rpc_apply_action] drives
## resolved commands through it (using [member board_provider] for the board). Left
## null in this phase so existing behaviour is unchanged — UI/board wiring lands later.
var command_applier: CommandApplier = null
## Optional source of the live board for [member command_applier]. Signature:
## func() -> board. Null (the default) means no board is applied.
var board_provider: Callable = Callable()


# ---------------------------------------------------------------------------
# Battle seam (installed by GameWorldManager at battle start; cleared on exit)
# ---------------------------------------------------------------------------

## Install the live command seam for the current battle: [param applier] is the ONE
## mutation point every peer funnels resolved commands through, and [param provider] is
## a Callable returning the live board it applies against. Called by [GameWorldManager]
## after the map + units are spawned and the registry is populated. Idempotent -- a second
## install simply replaces the hooks.
func install_command_seam(applier: CommandApplier, provider: Callable) -> void:
	command_applier = applier
	board_provider = provider

## Drop the battle seam so a stale applier never outlives the board it mutated (called on
## battle end / scene exit). Leaves the RNG/roster alone -- only the apply hooks are cleared.
func clear_command_seam() -> void:
	command_applier = null
	board_provider = Callable()

## The deterministic net_id bound to [param unit] for this match, or -1 if unknown. Reads
## the live registry when the seam is installed, falling back to the "net_id" metadata the
## registry stamps on each unit. The UI uses this to name the acting unit in a command.
func net_id_for(unit) -> int:
	if unit == null:
		return -1
	if command_applier != null and command_applier.registry != null:
		var rid: int = command_applier.registry.id_for(unit)
		if rid != -1:
			return rid
	if unit is Object and (unit as Object).has_meta("net_id"):
		return int((unit as Object).get_meta("net_id"))
	return -1


func _ready() -> void:
	name = "NetSession"
	# Wire the scene-tree multiplayer signals once. These fire for whichever
	# peer we install below.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Host a listen-server game: this instance is both the authority and slot 0.
func host_game(player_name: String, port: int = DEFAULT_PORT, players_max: int = 0) -> Error:
	if players_max > 0:
		max_players = players_max
	var err := _create_server(port)
	if err != OK:
		return err
	role = Role.LISTEN_SERVER
	_pending_name = player_name
	# The host occupies slot 0 immediately.
	_roster[SERVER_PEER_ID] = { "slot": 0, "name": player_name, "ready": false }
	_local_slot = 0
	_emit_roster()
	player_joined.emit(SERVER_PEER_ID, 0, player_name)
	return OK


## Start a headless authority with no local player (all slots for clients).
func start_dedicated_server(port: int = DEFAULT_PORT, players_max: int = 0) -> Error:
	if players_max > 0:
		max_players = players_max
	var err := _create_server(port)
	if err != OK:
		return err
	role = Role.DEDICATED_SERVER
	_local_slot = -1
	_emit_roster()
	return OK


## Join an existing host as a client.
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		push_error("NetSession: create_client failed: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	role = Role.CLIENT
	_pending_name = player_name
	return OK


## Tear down the current session and return to a clean state.
func leave() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	role = Role.NONE
	_roster.clear()
	_local_slot = -1
	_current_turn_slot = -1
	_seq = 0
	match_rng = null
	_emit_roster()


## Submit an intent to the server. On the server this validates immediately;
## on a client it is sent to the server for validation. Never mutates state
## directly — the resolved action arrives back via [signal action_applied].
func submit_intent(action: Dictionary) -> void:
	if not NetProtocol.is_well_formed(action):
		push_warning("NetSession: refusing to submit malformed action")
		return
	action[NetProtocol.KEY_ACTOR] = _local_slot
	if is_server():
		_server_handle_intent(_local_slot, action)
	else:
		_rpc_intent.rpc_id(SERVER_PEER_ID, action)


## Mark the local player ready in the lobby.
func set_ready(ready: bool) -> void:
	if is_server():
		_server_set_ready(local_peer_id(), ready)
	else:
		_rpc_set_ready.rpc_id(SERVER_PEER_ID, ready)


## Server-only: begin the match once players are ready.
func start_match() -> void:
	if not is_server():
		push_warning("NetSession: only the server can start the match")
		return
	# Turn order = slots in ascending order; first occupied slot goes first.
	var slots := _occupied_slots()
	_current_turn_slot = slots[0] if not slots.is_empty() else -1
	_rpc_match_started.rpc(_current_turn_slot)


## Server-only: advance to the next player's turn (round-robin over occupied slots).
func advance_turn() -> void:
	if not is_server():
		return
	var slots := _occupied_slots()
	if slots.is_empty():
		return
	var idx := slots.find(_current_turn_slot)
	_current_turn_slot = slots[(idx + 1) % slots.size()]
	_rpc_turn_changed.rpc(_current_turn_slot)


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

func is_server() -> bool:
	return role == Role.LISTEN_SERVER or role == Role.DEDICATED_SERVER

func is_connected_session() -> bool:
	return multiplayer.multiplayer_peer != null \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

## True when this is a live, connected networked match with more than one participant --
## the single gate the UI uses to decide "route this command through submit_intent instead
## of executing it locally". False for solo/hotseat/versus-on-one-box play (peer absent or a
## lone participant), so those paths stay on their existing direct execution UNCHANGED.
func is_networked_match() -> bool:
	return is_connected_session() and player_count() > 1

func local_peer_id() -> int:
	return multiplayer.get_unique_id() if multiplayer.multiplayer_peer != null else -1

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


# ---------------------------------------------------------------------------
# Server-side logic
# ---------------------------------------------------------------------------

func _create_server(port: int) -> Error:
	_peer = ENetMultiplayerPeer.new()
	# max_connections excludes the server itself.
	var err := _peer.create_server(port, max_players)
	if err != OK:
		push_error("NetSession: create_server failed: %s" % error_string(err))
		return err
	multiplayer.multiplayer_peer = _peer
	return OK


func _on_peer_connected(peer_id: int) -> void:
	# Only the server manages the roster. The client will announce its name via
	# _rpc_announce; we assign the slot when that arrives so names are correct.
	if not is_server():
		return
	# If the lobby is full, drop the newcomer.
	if _occupied_slots().size() >= max_players:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return


func _on_peer_disconnected(peer_id: int) -> void:
	if not is_server():
		return
	if _roster.has(peer_id):
		var slot: int = _roster[peer_id]["slot"]
		_roster.erase(peer_id)
		player_left.emit(peer_id, slot)
		_broadcast_roster()
		# If it was their turn, move on.
		if _current_turn_slot == slot:
			advance_turn()


## Server: a client announced its display name — assign a slot and sync everyone.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_announce(player_name: String) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _roster.has(peer_id):
		return
	var slot := _first_free_slot()
	if slot == -1:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return
	_roster[peer_id] = { "slot": slot, "name": player_name, "ready": false }
	player_joined.emit(peer_id, slot, player_name)
	_broadcast_roster()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not is_server():
		return
	_server_set_ready(multiplayer.get_remote_sender_id(), ready)


func _server_set_ready(peer_id: int, ready: bool) -> void:
	if _roster.has(peer_id):
		_roster[peer_id]["ready"] = ready
		_broadcast_roster()


## Server: receive an intent from a client, validate, and broadcast if legal.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(action: Dictionary) -> void:
	if not is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var actor_slot: int = _roster[peer_id]["slot"] if _roster.has(peer_id) else -1
	_server_handle_intent(actor_slot, action)


func _server_handle_intent(actor_slot: int, action: Dictionary) -> void:
	var reason := _validate_intent(actor_slot, action)
	if reason != "":
		# Tell just the origin peer it was rejected.
		var peer_id := _peer_for_slot(actor_slot)
		if peer_id == local_peer_id():
			intent_rejected.emit(action, reason)
		elif peer_id != -1:
			_rpc_intent_rejected.rpc_id(peer_id, action, reason)
		return
	# Stamp authoritative ordering + per-command RNG seed + protocol version, then
	# actor, then broadcast to everyone (including the host, via call_local). The seed
	# comes from the negotiated match RNG so every peer resolves this command's
	# accuracy/crit rolls identically; 0 when no match RNG has been negotiated yet
	# (e.g. lobby-phase actions), which the applier treats as "no injected seed".
	_seq += 1
	var rng_seed: int = match_rng.seed_for(_seq) if (match_rng != null and match_rng.is_ready()) else 0
	NetProtocol.stamp_resolution(action, _seq, rng_seed)
	action[NetProtocol.KEY_ACTOR] = actor_slot
	_rpc_apply_action.rpc(action)


func _validate_intent(actor_slot: int, action: Dictionary) -> String:
	if not NetProtocol.is_well_formed(action):
		return "malformed"
	if actor_slot == -1:
		return "unknown_actor"
	if enforce_turn_ownership and _current_turn_slot != -1 and actor_slot != _current_turn_slot:
		return "not_your_turn"
	if action_validator.is_valid() and not action_validator.call(action, actor_slot):
		return "rejected_by_game"
	return ""


# ---------------------------------------------------------------------------
# Client-visible RPCs (authority → everyone)
# ---------------------------------------------------------------------------

@rpc("authority", "call_local", "reliable")
func _rpc_apply_action(action: Dictionary) -> void:
	# When a command applier is wired (a later phase), drive the resolved command
	# through the single mutation point BEFORE announcing it, so observers see state
	# that already reflects the command. Inert by default (command_applier == null),
	# leaving today's emit-only behaviour untouched.
	if command_applier != null and NetProtocol.is_command_well_formed(action):
		var board = _resolve_board()
		command_applier.apply_command(action, board, null)
	action_applied.emit(action)


func _resolve_board():
	if board_provider.is_valid():
		return board_provider.call()
	return null


# ---------------------------------------------------------------------------
# Match-RNG commit-reveal handshake (see MatchRng)
# ---------------------------------------------------------------------------

## Solo/local: negotiate a match seed from a single local source. Same public
## surface as the networked path, so single-player is the degenerate case.
func begin_solo_match_rng() -> void:
	match_rng = MatchRng.new()
	match_rng.begin_solo(MatchRng.fresh_entropy())
	match_rng_ready.emit()

## Server: kick off the commit-reveal handshake. The host commits to hidden entropy
## and broadcasts only the commit; clients answer with their own entropy; the host
## then reveals and everyone finalises the same seed. Call after the roster is set,
## before the first gameplay command.
func begin_match_rng_handshake() -> void:
	if not is_server():
		push_warning("NetSession: only the server starts the match-RNG handshake")
		return
	match_rng = MatchRng.new()
	var commit: int = match_rng.begin_host(MatchRng.fresh_entropy())
	# A dedicated server with no local player still needs a seed if it ever resolves
	# solo; but normally at least one client answers. Broadcast the commit.
	_rpc_rng_commit.rpc(commit)


## Server -> clients: here is my commit; send me your entropy.
@rpc("authority", "call_remote", "reliable")
func _rpc_rng_commit(commit: int) -> void:
	match_rng = MatchRng.new()
	match_rng.begin_client(commit)
	var client_entropy: int = MatchRng.fresh_entropy()
	match_rng.set_own_client_entropy(client_entropy)
	_rpc_rng_client_entropy.rpc_id(SERVER_PEER_ID, client_entropy)


## Client -> server: my entropy (in the clear). The server folds it in, reveals, and
## broadcasts the reveal so clients can verify against the commit.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_rng_client_entropy(client_entropy: int) -> void:
	if not is_server() or match_rng == null:
		return
	match_rng.set_client_entropy(client_entropy)
	var host_entropy: int = match_rng.host_reveal()   # finalises the seed on the host
	_rpc_rng_reveal.rpc(host_entropy)
	match_rng_ready.emit()


## Server -> clients: the revealed host entropy. Each client verifies it against the
## commit it holds; a mismatch means the host tampered and the match must abort.
@rpc("authority", "call_remote", "reliable")
func _rpc_rng_reveal(host_entropy: int) -> void:
	if match_rng == null:
		return
	if match_rng.accept_reveal(host_entropy):
		match_rng_ready.emit()
	else:
		push_error("NetSession: match-RNG reveal failed verification -- host entropy did not match its commit")
		disconnected.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_sync_roster(roster: Dictionary) -> void:
	_roster = roster
	# A client learns its own slot from the roster.
	if not is_server():
		var my_id := local_peer_id()
		if _roster.has(my_id):
			_local_slot = _roster[my_id]["slot"]
	_emit_roster()


@rpc("authority", "call_local", "reliable")
func _rpc_match_started(first_slot: int) -> void:
	_current_turn_slot = first_slot
	match_started.emit()
	turn_changed.emit(_current_turn_slot)


@rpc("authority", "call_local", "reliable")
func _rpc_turn_changed(slot: int) -> void:
	_current_turn_slot = slot
	turn_changed.emit(slot)


@rpc("authority", "call_remote", "reliable")
func _rpc_intent_rejected(action: Dictionary, reason: String) -> void:
	intent_rejected.emit(action, reason)


# ---------------------------------------------------------------------------
# Client-side connection lifecycle
# ---------------------------------------------------------------------------

func _on_connected_to_server() -> void:
	# We're a client; tell the server our name so it can seat us.
	_rpc_announce.rpc_id(SERVER_PEER_ID, _pending_name)


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	leave()
	disconnected.emit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _broadcast_roster() -> void:
	_emit_roster()
	if is_server():
		_rpc_sync_roster.rpc(_roster)


func _emit_roster() -> void:
	roster_changed.emit(get_roster())


func _occupied_slots() -> Array[int]:
	var slots: Array[int] = []
	for peer_id in _roster:
		slots.append(_roster[peer_id]["slot"])
	slots.sort()
	return slots


func _first_free_slot() -> int:
	var taken := _occupied_slots()
	for s in range(max_players):
		if s not in taken:
			return s
	return -1


func _peer_for_slot(slot: int) -> int:
	for peer_id in _roster:
		if _roster[peer_id]["slot"] == slot:
			return peer_id
	return -1
