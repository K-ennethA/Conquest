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
## The server refused this peer's join (client side). [param reason] is one of
## NetProtocol's REJECT_* constants; [param info] is the version detail dictionary
## [method NetProtocol.validate_hello] produced, ready for
## [method NetProtocol.describe_rejection].
signal join_rejected(reason: String, info: Dictionary)
## The server refused a joining peer (server side), so a host UI can say why.
signal peer_join_refused(peer_id: int, reason: String, info: Dictionary)
## The commit-reveal match-RNG handshake completed on this peer; [member match_rng]
## is now READY and per-command seeds are derivable. Emitted on host and each client.
signal match_rng_ready()
## A free-form LOBBY message arrived from another participant. This is the pre-match
## channel (map votes, ready flags, the game-start MatchSettings payload) -- deliberately
## separate from the gameplay command vocabulary in [NetProtocol], which is validated,
## sequenced and RNG-stamped. Lobby messages are relayed by the server, never applied to
## game state, and are only ever delivered to peers OTHER than the sender.
## [param from_slot] is the sender's roster slot (-1 if it had none yet).
signal lobby_message(message_type: String, data: Dictionary, from_slot: int)
## Another participant FORFEITED the live match (they used the pause menu's "Forfeit
## Match"). [param slot] is the forfeiting player's roster slot, taken from the SERVER's
## relay stamp rather than the sender's payload. The battle UI turns this into a defeat
## for that slot so the remaining player gets the normal victory flow.
signal opponent_forfeited(slot: int)
## A participant vanished from a live networked match without forfeiting -- they crashed,
## alt-F4'd, or lost the connection. Deliberately indistinguishable from a forfeit in
## OUTCOME (leaving a live match is a loss either way); it is a separate signal only
## because there is no reliable slot to name when a socket simply drops.
signal opponent_left()

enum Role { NONE, LISTEN_SERVER, DEDICATED_SERVER, CLIENT }

const DEFAULT_PORT := 8910
const SERVER_PEER_ID := 1

## Lobby-channel message type for a deliberate forfeit. It rides the LOBBY channel, not
## the command vocabulary: a forfeit is a session event, not a board mutation, and it has
## to survive being sent by a peer that is about to disconnect itself.
const MSG_MATCH_FORFEIT := "match_forfeit"

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

## Client side: the last join refusal received from a server, kept AFTER the server
## drops us so the UI can explain the disconnect. Shape: { "reason": String,
## "info": Dictionary }; empty until a join is refused. Cleared by [method join_game].
var _last_join_rejection: Dictionary = {}

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

# --- Turn-ownership bridge (task 2) -----------------------------------------
# Nothing in the real game drives NetSession's own [member _current_turn_slot]; the actual
# turn state lives in the active [TurnSystemBase] via [TurnSystemManager]. When the command
# seam is installed we SUBSCRIBE to that turn system's [signal turn_started] and map the
# active player -> a peer slot, so [method _validate_intent] can reject out-of-turn intents
# server-side. Both turn systems hand a [Player] to turn_started -- Traditional's current
# player, Speed First's acting-unit owner -- so one hook covers both.

## True only while the seam is installed AND the bridge is live. Turn-ownership enforcement
## is gated on this so a dev/legacy session with no seam is never gated by a stale slot.
var _turn_bridge_active: bool = false
## The turn SYSTEM whose turn_started we are currently connected to (re-hooked when the
## manager activates a new system). Null when unhooked.
var _bridged_turn_system = null
## The manager (TurnSystemManager or an injected stand-in) whose turn_system_activated we
## watch so we can re-hook on a system switch. Null when the source was a bare system.
var _bridge_manager = null
## Optional override for player -> peer slot. Signature: func(player) -> int. When invalid
## the default maps player.player_id directly to the slot (host = player 0 = slot 0).
var turn_slot_mapper: Callable = Callable()


# ---------------------------------------------------------------------------
# Battle seam (installed by GameWorldManager at battle start; cleared on exit)
# ---------------------------------------------------------------------------

## Install the live command seam for the current battle: [param applier] is the ONE
## mutation point every peer funnels resolved commands through, and [param provider] is
## a Callable returning the live board it applies against. Called by [GameWorldManager]
## after the map + units are spawned and the registry is populated. Idempotent -- a second
## install simply replaces the hooks.
## [param turn_source] (optional) is where the turn-ownership bridge reads turn state from:
## null uses the live [TurnSystemManager] autoload; a manager-like object (has
## turn_system_activated) or a bare turn system (has turn_started) may be injected for tests.
func install_command_seam(applier: CommandApplier, provider: Callable, turn_source = null) -> void:
	command_applier = applier
	board_provider = provider
	_activate_turn_bridge(turn_source)

## Drop the battle seam so a stale applier never outlives the board it mutated (called on
## battle end / scene exit). Leaves the RNG/roster alone -- only the apply hooks are cleared.
func clear_command_seam() -> void:
	command_applier = null
	board_provider = Callable()
	_deactivate_turn_bridge()


# ---------------------------------------------------------------------------
# Turn-ownership bridge
# ---------------------------------------------------------------------------

## Start driving [member _current_turn_slot] from the real turn system so the validator can
## gate out-of-turn intents. Idempotent; safe when no turn source exists (bridge simply stays
## armed but slot-less, so gating is inert until a turn actually starts).
func _activate_turn_bridge(turn_source = null) -> void:
	_deactivate_turn_bridge()
	_turn_bridge_active = true
	var src = turn_source if turn_source != null else _live_turn_manager()
	if src == null:
		return
	if src.has_signal("turn_started"):
		# A bare turn SYSTEM was injected directly (tests, or a system with no manager).
		_bridge_hook_system(src)
	elif src.has_signal("turn_system_activated"):
		_bridge_manager = src
		if not src.turn_system_activated.is_connected(_on_bridge_turn_system_activated):
			src.turn_system_activated.connect(_on_bridge_turn_system_activated)
		# Hook whatever system is already active so the first slot is seeded immediately.
		if src.has_method("has_active_turn_system") and src.has_active_turn_system() \
				and src.has_method("get_active_turn_system"):
			_bridge_hook_system(src.get_active_turn_system())

## Stop driving the slot and disconnect every bridge signal. Resets the slot to -1 so a
## seam-less (dev/legacy) session is never gated by a stale value.
func _deactivate_turn_bridge() -> void:
	_bridge_unhook_system()
	if _bridge_manager != null and is_instance_valid(_bridge_manager) \
			and _bridge_manager.has_signal("turn_system_activated") \
			and _bridge_manager.turn_system_activated.is_connected(_on_bridge_turn_system_activated):
		_bridge_manager.turn_system_activated.disconnect(_on_bridge_turn_system_activated)
	_bridge_manager = null
	_turn_bridge_active = false
	_current_turn_slot = -1

## The live TurnSystemManager autoload, or null when it is unavailable (some headless runs).
func _live_turn_manager():
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null:
		return TurnSystemManager
	return null

## Connect to [param system]'s turn_started (dropping any prior hook) and seed the slot from
## whoever is already acting, so a mid-battle seam install lands on the correct turn.
func _bridge_hook_system(system) -> void:
	if system == null or _bridged_turn_system == system:
		return
	_bridge_unhook_system()
	_bridged_turn_system = system
	if system.has_signal("turn_started") and not system.turn_started.is_connected(_on_bridge_turn_started):
		system.turn_started.connect(_on_bridge_turn_started)
	if system.has_method("get_current_active_player"):
		var p = system.get_current_active_player()
		if p != null:
			_set_turn_slot_from_player(p)

func _bridge_unhook_system() -> void:
	if _bridged_turn_system != null and is_instance_valid(_bridged_turn_system) \
			and _bridged_turn_system.has_signal("turn_started") \
			and _bridged_turn_system.turn_started.is_connected(_on_bridge_turn_started):
		_bridged_turn_system.turn_started.disconnect(_on_bridge_turn_started)
	_bridged_turn_system = null

## The manager activated a new turn system -- re-hook onto it (a battle can switch systems).
func _on_bridge_turn_system_activated(system) -> void:
	_bridge_hook_system(system)

## The active turn system started [param player]'s turn (Traditional: current player; Speed
## First: the acting unit's owner). Map it to a peer slot and drive the validator's gate.
func _on_bridge_turn_started(player) -> void:
	_set_turn_slot_from_player(player)

func _set_turn_slot_from_player(player) -> void:
	var slot: int = _slot_for_player(player)
	if slot == _current_turn_slot:
		return
	_current_turn_slot = slot
	turn_changed.emit(slot)

## Map [param player] to its peer slot. Uses [member turn_slot_mapper] when set, else the
## player's own 0-based player_id (host = player 0 = slot 0), which is the natural alignment.
func _slot_for_player(player) -> int:
	if player == null:
		return -1
	if turn_slot_mapper.is_valid():
		return int(turn_slot_mapper.call(player))
	if player is Object and (player as Object).get("player_id") != null:
		return int((player as Object).get("player_id"))
	return -1

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


## Join an existing host as a client. The version handshake runs the moment the socket
## comes up (see [method _on_connected_to_server]); a build mismatch surfaces as
## [signal join_rejected] followed by the server dropping us.
func join_game(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	_last_join_rejection = {}
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
	# Drop the turn bridge too so a torn-down session never keeps a stale turn hook.
	_deactivate_turn_bridge()
	_emit_roster()


## Concede the live match and tear the session down. Quitting a networked battle is a
## LOSS, never a quiet exit, so this is the only way the pause menu is allowed to leave
## one (see [PauseMenu]).
##
## Announces first, leaves second: the forfeit rides the reliable LOBBY channel, and
## [method leave] closes the ENet peer, which flushes queued reliable packets before the
## disconnect. Even if that flush were lost, the disconnect the other side then observes
## raises [signal opponent_left] -- which the battle treats identically -- so the match
## cannot end up hanging on a dropped announcement.
##
## No-op (and returns false) outside a live networked match, so a solo/menu caller is safe.
func forfeit_match() -> bool:
	if not is_networked_match():
		return false
	send_lobby_message(MSG_MATCH_FORFEIT, { "slot": _local_slot })
	leave()
	return true


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


## Send a LOBBY message (map vote, ready flag, game-start settings) to every OTHER
## participant. The server relays it; the sender never receives its own message back, so a
## lobby UI can broadcast unconditionally without having to filter its own echo.
##
## This is NOT the gameplay path: lobby messages are not validated, sequenced or RNG-stamped
## and must never mutate battle state -- that is [method submit_intent]'s job. Treat the
## payload as UNTRUSTED peer input in the handler (it is a plain Dictionary off the wire).
## Silent no-op when there is no live session, so a solo/menu caller is safe.
func send_lobby_message(message_type: String, data: Dictionary) -> void:
	if not is_connected_session():
		return
	if is_server():
		_server_relay_lobby_message(local_peer_id(), message_type, data)
	else:
		_rpc_lobby_message.rpc_id(SERVER_PEER_ID, message_type, data)


## Client -> server: please relay this lobby message to the others.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_lobby_message(message_type: String, data: Dictionary) -> void:
	if not is_server():
		return
	_server_relay_lobby_message(multiplayer.get_remote_sender_id(), message_type, data)


## Server: fan [param message_type] out to every participant except [param from_peer].
## The host itself is a participant, so it emits locally when the message came from a client.
func _server_relay_lobby_message(from_peer: int, message_type: String, data: Dictionary) -> void:
	if not is_server():
		return
	var from_slot: int = int(_roster[from_peer]["slot"]) if _roster.has(from_peer) else -1
	if multiplayer.multiplayer_peer != null:
		for peer_id in multiplayer.get_peers():
			if peer_id == from_peer:
				continue
			_rpc_lobby_deliver.rpc_id(peer_id, message_type, data, from_slot)
	# The listen-server host is a player too: deliver locally unless it was the sender.
	if from_peer != local_peer_id():
		_deliver_lobby_message(message_type, data, from_slot)


## Server -> one client: a lobby message from another participant.
@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_deliver(message_type: String, data: Dictionary, from_slot: int) -> void:
	_deliver_lobby_message(message_type, data, from_slot)


## The ONE local delivery point for an incoming lobby message -- the host-side relay and
## the client-side RPC both funnel through here. Emits the raw [signal lobby_message] for
## lobby UIs, then routes the small set of SYSTEM message types into their own typed
## signals.
##
## [param data] is UNTRUSTED peer input, so the slot reported for a forfeit is taken from
## [param from_slot] -- which the SERVER derived from its own roster -- whenever that is
## valid. The payload's own "slot" is only a fallback for the case where the sender had no
## seat to be stamped with.
func _deliver_lobby_message(message_type: String, data: Dictionary, from_slot: int) -> void:
	lobby_message.emit(message_type, data, from_slot)
	if message_type == MSG_MATCH_FORFEIT:
		var slot: int = from_slot if from_slot >= 0 else int(data.get("slot", -1))
		opponent_forfeited.emit(slot)


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
	# OfflineMultiplayerPeer - the tree's DEFAULT when no session exists - reports
	# CONNECTION_CONNECTED with peer id 1, so a naive status check reads "connected"
	# in every solo process. That false positive made the lobby prefer NetSession
	# and RPC-to-self (engine error, dropped votes). A session only counts when a
	# REAL transport peer is installed.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

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

## Client side: why the last join was refused, or an empty dictionary when it was not.
## Shape { "reason": String, "info": Dictionary }. Survives the disconnect that follows
## a refusal (and [method leave]), so a menu can explain a connection that just dropped;
## [method join_game] clears it on the next attempt.
func last_join_rejection() -> Dictionary:
	return _last_join_rejection.duplicate(true)


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
	# _rpc_hello; we assign the slot when that arrives, so names are correct AND the
	# build gate has run before anyone is seated.
	if not is_server():
		return
	# If the lobby is full, drop the newcomer.
	if _occupied_slots().size() >= max_players:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
		return


func _on_peer_disconnected(peer_id: int) -> void:
	# A peer vanishing from a LIVE networked match is a loss for them, exactly like a
	# forfeit -- announce it before the roster shrinks (is_networked_match() reads the
	# roster, so it must be sampled first). Emitted for every role: a client watching
	# another client drop needs to see it too.
	var was_live: bool = is_networked_match() and _roster.has(peer_id)
	if was_live:
		opponent_left.emit()
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


## Server: a client said hello (display name + version stamps). Validate the build
## BEFORE it gets a roster slot — a peer on a different protocol version is refused
## with a reason it can show, then dropped, rather than being admitted and desyncing
## on the first command.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(hello: Dictionary) -> void:
	if not is_server():
		return
	_server_admit_peer(multiplayer.get_remote_sender_id(), hello)


## Server: run the build gate on [param hello] and seat [param peer_id] if it passes.
## Split out of [method _rpc_hello] so the seating rules can be driven directly (the
## RPC wrapper only supplies the sender id) -- same shape as [method _server_handle_intent].
func _server_admit_peer(peer_id: int, hello: Dictionary) -> void:
	if not is_server():
		return
	if _roster.has(peer_id):
		return
	var check: Dictionary = NetProtocol.validate_hello(hello)
	if not bool(check.get("accepted", false)):
		_refuse_peer(peer_id, String(check.get("reason", NetProtocol.REJECT_MALFORMED_HELLO)), check)
		return
	var slot := _first_free_slot()
	if slot == -1:
		_refuse_peer(peer_id, NetProtocol.REJECT_LOBBY_FULL, check)
		return
	if bool(check.get("build_differs", false)):
		# Not fatal (an editor run joining an exported build is a legitimate test setup),
		# but worth saying out loud when someone is chasing a desync. Deliberately a
		# print, not push_warning: this is a handled, expected state.
		print("[NET] Peer %d joined on game version '%s' while this host runs '%s'." % [
			peer_id, String(check.get("client_game", "?")), String(check.get("host_game", "?"))])
	var player_name: String = String(check.get("name", "Player"))
	_roster[peer_id] = { "slot": slot, "name": player_name, "ready": false }
	player_joined.emit(peer_id, slot, player_name)
	_broadcast_roster()


## Server: tell [param peer_id] why it may not join, then disconnect it. The peer is
## dropped gracefully (ENet flushes queued reliable packets first) so the rejection
## message actually arrives before the socket closes.
func _refuse_peer(peer_id: int, reason: String, info: Dictionary) -> void:
	print("[NET] Refusing peer %d: %s" % [peer_id, reason])
	peer_join_refused.emit(peer_id, reason, info)
	_rpc_join_rejected.rpc_id(peer_id, reason, info)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## Server -> one client: your join was refused, and why. Remembered so the
## server-disconnect that follows can still be explained.
@rpc("authority", "call_remote", "reliable")
func _rpc_join_rejected(reason: String, info: Dictionary) -> void:
	_last_join_rejection = { "reason": reason, "info": info }
	join_rejected.emit(reason, info)


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


## Why [param action] may not be applied, or "" when it is legal. The strings are the
## NetProtocol.INTENT_* wire vocabulary; the client turns one into a player-facing line with
## [method NetProtocol.describe_intent_rejection] (see the battle HUD's rejection toast).
func _validate_intent(actor_slot: int, action: Dictionary) -> String:
	if not NetProtocol.is_well_formed(action):
		return NetProtocol.INTENT_MALFORMED
	if actor_slot == -1:
		return NetProtocol.INTENT_UNKNOWN_ACTOR
	# Turn-ownership gating is driven by the real turn system through the seam bridge. It is
	# ON by default for a networked match (enforce_turn_ownership defaults true) once a seam
	# is installed, and OFF for a dev/legacy session with no seam (_turn_bridge_active false)
	# so a stale slot can never wrongly reject.
	if enforce_turn_ownership and _turn_bridge_active and _current_turn_slot != -1 and actor_slot != _current_turn_slot:
		return NetProtocol.INTENT_NOT_YOUR_TURN
	if action_validator.is_valid() and not action_validator.call(action, actor_slot):
		return NetProtocol.INTENT_REJECTED_BY_GAME
	return NetProtocol.INTENT_OK


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
	_sync_applier_rng()
	match_rng_ready.emit()


## Hand the CURRENT match RNG to an already-installed applier. Every path that REPLACES
## [member match_rng] must call this: the seam can be installed before the handshake has
## produced its MatchRng object (battle scene loads while the commit-reveal is still in
## flight), and an applier left holding the previous object would roll a different stream
## from every other peer. No-op when no seam is installed.
func _sync_applier_rng() -> void:
	if command_applier != null:
		command_applier.match_rng = match_rng

## Server: kick off the commit-reveal handshake. The host commits to hidden entropy
## and broadcasts only the commit; clients answer with their own entropy; the host
## then reveals and everyone finalises the same seed. Call after the roster is set,
## before the first gameplay command.
func begin_match_rng_handshake() -> void:
	if not is_server():
		push_warning("NetSession: only the server starts the match-RNG handshake")
		return
	match_rng = MatchRng.new()
	_sync_applier_rng()
	var commit: int = match_rng.begin_host(MatchRng.fresh_entropy())
	# A dedicated server with no local player still needs a seed if it ever resolves
	# solo; but normally at least one client answers. Broadcast the commit.
	_rpc_rng_commit.rpc(commit)


## Server -> clients: here is my commit; send me your entropy.
@rpc("authority", "call_remote", "reliable")
func _rpc_rng_commit(commit: int) -> void:
	match_rng = MatchRng.new()
	_sync_applier_rng()
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
	# We're a client; our FIRST message is the hello (name + version stamps). The server
	# seats us only if the build matches — see _rpc_hello.
	_rpc_hello.rpc_id(SERVER_PEER_ID, NetProtocol.make_hello(_pending_name))


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	# The host went away mid-match. Sample the "was this a live match?" question BEFORE
	# leave() clears the roster, then report it the same way a peer drop is reported so
	# the battle can end on the standard victory flow instead of stranding the client.
	var was_live: bool = is_networked_match()
	leave()
	if was_live:
		opponent_left.emit()
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
