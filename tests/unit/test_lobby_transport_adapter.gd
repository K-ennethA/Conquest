extends GutTest

# CollaborativeLobby's transport adapter.
#
# The lobby has TWO possible carriers for its vote / ready / lobby-state / game-start
# messages: NetSession (the consolidated server-authoritative transport that Host/Join now
# run on, and the same session the battle's command seam reads) and the legacy
# GameModeManager.submit_action envelope. The rule pinned here: NetSession wins WHENEVER it
# holds a live connected peer, and the legacy path carries everything else -- so the three
# older lobby suites, which drive the legacy path, stay meaningful.
#
# Both transports are stand-ins. That is the point: the adapter must be decided by
# "is there a live session", never by which concrete object is plugged in.

## Stand-in for the NetSession autoload. `live` drives the branch under test.
class MockNetSession extends Node:
	signal lobby_message(message_type: String, data: Dictionary, from_slot: int)
	## The lobby retries a parked start_match on the next roster change.
	signal roster_changed(roster: Dictionary)
	var live: bool = true
	var sent: Array = []
	## Roster size. Left at 1 (host only) so the host's connection POLL never fires during a
	## test -- admission is driven explicitly via deliver("lobby_hello", ...) instead, which
	## keeps every assertion synchronous.
	var players: int = 1
	var server: bool = true
	## What start_match answers (false = "a ready flag has not landed yet").
	var start_ok: bool = true
	var start_calls: Array = []

	func is_connected_session() -> bool:
		return live
	func is_host() -> bool:
		return server
	func is_server() -> bool:
		return server
	func is_dedicated_server() -> bool:
		return false
	func player_count() -> int:
		return players
	func send_lobby_message(message_type: String, data: Dictionary) -> void:
		sent.append({ "type": message_type, "data": data })
	func start_match(final_config: Dictionary = {}) -> bool:
		start_calls.append(final_config)
		return start_ok
	## Deliver a message as if it arrived from the other participant.
	func deliver(message_type: String, data: Dictionary) -> void:
		lobby_message.emit(message_type, data, 1)

## Stand-in for the GameModeManager autoload (the legacy envelope).
class MockGameModeManager extends Node:
	var sent: Array = []
	func submit_action(action_type: String, action_data: Dictionary) -> bool:
		sent.append({ "type": action_type, "data": action_data })
		return true
	func get_game_status() -> Dictionary:
		return { "network_stats": { "connected_peers": 0, "connection_status": "disconnected" } }

const MAP_A := "res://game/maps/resources/default_skirmish.tres"

const Guard := preload("res://tests/helpers/global_state_guard.gd")

var lobby: Control
var net: MockNetSession
var gmm: MockGameModeManager
## Untyped on purpose (see test_lobby_loadout_exchange.gd): the finalize tests write the
## selected map, an autoload field, so it is snapshotted and restored.
var _guard

func before_each():
	_guard = Guard.new()
	_guard.watch_setting("selected_map_path")
	net = MockNetSession.new()
	add_child_autofree(net)
	gmm = MockGameModeManager.new()
	add_child_autofree(gmm)

	lobby = Control.new()
	lobby.set_script(load("res://menus/CollaborativeLobby.gd"))
	add_child_autofree(lobby)
	await get_tree().process_frame

	# Swap both transports for stand-ins AFTER _ready has bound the real autoloads.
	lobby.set_net_session(net)
	lobby.game_mode_manager = gmm

func after_each():
	_guard.restore()
	lobby = null
	net = null
	gmm = null

# --- which transport carries a send ------------------------------------------

func test_sends_prefer_netsession_when_the_session_is_live():
	net.live = true

	lobby.local_player_name = "Host"
	lobby._broadcast_map_vote(MAP_A)
	lobby._broadcast_ready()

	assert_eq(net.sent.size(), 2, "both messages rode NetSession")
	assert_eq(gmm.sent.size(), 0, "and none fell through to the legacy envelope")
	assert_eq(net.sent[0]["type"], "map_vote", "the vote kept its message type")
	assert_eq(str(net.sent[0]["data"].get("map_path", "")), MAP_A, "the vote carried the map path")
	assert_eq(str(net.sent[0]["data"].get("player_name", "")), "Host", "the vote carried the sender's name")
	assert_eq(net.sent[1]["type"], "player_ready", "the ready flag kept its message type")

func test_sends_fall_back_to_the_legacy_envelope_when_no_session_is_live():
	net.live = false

	lobby.local_player_name = "Host"
	lobby._broadcast_map_vote(MAP_A)
	lobby._broadcast_ready()

	assert_eq(net.sent.size(), 0, "nothing was pushed at a dead session")
	assert_eq(gmm.sent.size(), 2, "both messages fell through to GameModeManager.submit_action")
	assert_eq(gmm.sent[0]["type"], "map_vote", "the legacy envelope kept the message type")

func test_game_start_settings_ride_the_live_session():
	net.live = true
	lobby.is_host = true

	lobby._broadcast_game_start(MAP_A)

	assert_eq(net.sent.size(), 1, "the host's game_start rode NetSession")
	assert_eq(net.sent[0]["type"], "game_start", "it is the game_start message")
	var payload: Dictionary = net.sent[0]["data"]
	assert_eq(str(payload.get("map", "")), MAP_A, "the MatchSettings payload names the agreed map")
	assert_true(payload.has("turn_system"), "the payload carries the host's turn system")
	assert_true(payload.has("versus_rounds"), "the payload carries the host's round count")

func test_a_client_never_broadcasts_host_only_messages():
	net.live = true
	lobby.is_host = false

	lobby._broadcast_game_start(MAP_A)
	lobby._broadcast_lobby_state("map_selection")

	assert_eq(net.sent.size(), 0, "host-only messages stay host-only on either transport")

func test_no_transport_at_all_is_a_silent_no_op():
	lobby.set_net_session(null)
	lobby.game_mode_manager = null

	lobby._broadcast_map_vote(MAP_A)
	lobby._broadcast_ready()

	pass_test("a lobby with neither transport sends nothing and does not crash")

# --- inbound: the session's messages land in the one handler -----------------

func test_inbound_session_messages_reach_the_message_handler():
	lobby.initialize(true, "Host")

	net.deliver("map_vote", { "player_name": "Opponent", "map_path": MAP_A })

	assert_eq(lobby.remote_map_vote, MAP_A, "the opponent's vote was applied")
	assert_eq(lobby.remote_player_name, "Opponent", "the opponent's name was recorded")

func test_hello_admits_the_opponent_and_answers_with_the_lobby_state():
	# The joining client announces itself; the host must both open map selection AND answer,
	# which is what closes the race where the host's broadcast went out before the client's
	# lobby node existed.
	lobby.initialize(true, "Host")
	net.sent.clear()

	net.deliver("lobby_hello", { "player_name": "Opponent" })

	assert_true(lobby.is_client_connected, "the host admitted the opponent")
	assert_true(lobby.map_selection_panel.visible, "the host moved to map selection")
	assert_eq(lobby.remote_player_name, "Opponent", "the opponent's name came off the hello")
	# Count by TYPE, not raw sends: the hello answer legitimately carries lobby_state AND
	# the host's profile_info card (the post-match summary's opponent block reads it).
	var states: Array = net.sent.filter(func(m): return m["type"] == "lobby_state")
	assert_eq(states.size(), 1, "the host answered the hello with the lobby state")
	assert_eq(str(states[0]["data"].get("state", "")), "map_selection", "which is map selection")

func test_a_late_hello_is_answered_again():
	# The host may already have flipped to map selection (roster poll) when the hello lands.
	# It must still answer, else the client waits forever.
	lobby.initialize(true, "Host")
	lobby.is_client_connected = true
	net.sent.clear()

	net.deliver("lobby_hello", { "player_name": "Opponent" })

	# Count by TYPE (the answer also carries profile_info - see the hello test above).
	var late_states: Array = net.sent.filter(func(m): return m["type"] == "lobby_state")
	assert_eq(late_states.size(), 1, "a late hello is still answered with the current state")

func test_a_client_ignores_a_hello():
	lobby.initialize(false, "Client")
	net.sent.clear()

	net.deliver("lobby_hello", { "player_name": "Someone" })

	assert_false(lobby.is_client_connected, "a client does not admit players")
	assert_eq(net.sent.size(), 0, "and does not answer the hello")

func test_rebinding_the_session_drops_the_old_subscription():
	lobby.initialize(true, "Host")
	var replacement := MockNetSession.new()
	add_child_autofree(replacement)
	lobby.set_net_session(replacement)

	net.deliver("map_vote", { "player_name": "Opponent", "map_path": MAP_A })

	assert_eq(lobby.remote_map_vote, "", "the replaced session no longer feeds this lobby")

# --- starting the match: the host hands the agreed map to NetSession.start_match ---
#
# (Replaces the old match-RNG handshake gate: the merged NetSession has no separate
# begin_match_rng_handshake -- the commit-reveal round runs inside start_match -- so what the
# lobby must get right is WHO calls start_match, with WHAT, and that it never starts twice.)

func test_start_match_runs_only_for_a_live_host_session():
	net.live = true
	net.server = true
	lobby._begin_net_match(MAP_A)
	assert_eq(net.start_calls.size(), 1, "the host asks the live session to start the match")
	assert_eq(str(net.start_calls[0].get("map_path", "")), MAP_A, "on the agreed map")

	net.server = false
	lobby._begin_net_match(MAP_A)
	assert_eq(net.start_calls.size(), 1, "a client never starts the match")

	net.server = true
	net.live = false
	lobby._begin_net_match(MAP_A)
	assert_eq(net.start_calls.size(), 1, "and neither does a host with no live session")

func test_the_hosts_finalize_hands_the_agreed_match_to_start_match():
	# The panel would write the turn system / best-of into GameSettings; not what this is about.
	lobby.versus_config_panel = null
	lobby.is_host = true
	lobby.local_map_vote = MAP_A
	lobby.remote_map_vote = MAP_A

	lobby._finalize_map_selection()

	var starts: Array = net.sent.filter(func(m): return m["type"] == "game_start")
	assert_eq(starts.size(), 1, "the client is still told which map won (its 'Starting game with' line)")
	assert_eq(net.start_calls.size(), 1, "and the session is asked to start the match")
	var cfg: Dictionary = net.start_calls[0]
	assert_eq(str(cfg.get("map_path", "")), MAP_A, "on the agreed map")
	for key in ["turn_system", "auto_end_turn", "versus_rounds", "host_squad", "map_json"]:
		assert_true(cfg.has(key), "the start config carries '%s' for GameModeManager" % key)
	assert_false(cfg.has("map_payload"), "a builtin ships no content")

func test_a_start_refused_for_a_missing_ready_flag_is_retried_once_and_never_twice():
	lobby.versus_config_panel = null
	lobby.is_host = true
	lobby.local_map_vote = MAP_A
	lobby.remote_map_vote = MAP_A
	net.start_ok = false

	lobby._finalize_map_selection()
	assert_eq(net.start_calls.size(), 1, "the host tried to start")

	net.start_ok = true
	net.roster_changed.emit({})
	assert_eq(net.start_calls.size(), 2, "and tried again once the roster (a ready flag) moved")

	net.roster_changed.emit({})
	lobby._finalize_map_selection()
	assert_eq(net.start_calls.size(), 2, "a started match is never started a second time")
