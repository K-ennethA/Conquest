extends GutTest

# Leaving a live networked match is a LOSS -- deliberately (forfeit) or not (disconnect).
#
# What this pins is the SESSION half of that rule: the forfeit announcement rides the
# lobby relay and arrives on the other side as opponent_forfeited(slot), and a peer that
# simply vanishes mid-match raises opponent_left(). Turning either of those into a defeat
# is the battle HUD's job (UILayoutManager._eliminate_absent_players), which routes them
# through the ordinary PlayerManager.player_eliminated -> GameOverScreen flow.
#
# Only the SERVER half is exercised, following the pattern in
# tests/integration/test_mp_loopback.gd: a bound listen socket with no dialling, so there
# is no connection to wait on and nothing that can hang a headless run. A peer is seated
# by driving _server_admit_peer directly (the RPC wrapper only supplies the sender id),
# and messages are driven through the relay entry point rather than over the wire --
# RPCing a peer id that was never really connected raises engine errors, which GUT
# (correctly) fails the run on.


# --- fixtures ----------------------------------------------------------------

## Bind a NetSession listen server under its own MultiplayerAPI branch. Returns {} (after
## reporting pending) when a socket cannot be bound in this environment.
func _open_host() -> Dictionary:
	var branch := Node.new()
	branch.name = "MPForfeitHost%d" % (Time.get_ticks_usec() % 100000)
	get_tree().root.add_child(branch)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), branch.get_path())
	var host := _netsession_instance()
	branch.add_child(host)

	var port: int = 40000 + (Time.get_ticks_usec() % 20000)
	var err: int = host.host_game("Host", port, 2)
	if err != OK:
		host.leave()
		# free(), not queue_free(): GUT counts orphans before a deferred free lands.
		branch.free()
		pending("Could not bind a local ENet server socket in this environment (%s). "
			% error_string(err)
			+ "The forfeit/disconnect rules are transport-independent; this test only needs a "
			+ "bound listen socket so is_connected_session() can be true.")
		return {}
	return { "host": host, "branch": branch }

func _close_host(session: Dictionary) -> void:
	var host = session.get("host", null)
	if host != null and is_instance_valid(host):
		host.leave()
	var branch = session.get("branch", null)
	if branch != null and is_instance_valid(branch):
		# free() frees the NetSession child with it; queue_free() would defer past the
		# point where GUT counts orphans.
		branch.free()

func _netsession_instance() -> Node:
	var script = load("res://systems/net/NetSession.gd")
	var n := Node.new()
	n.set_script(script)
	return n

## A NetSession parented under the test node, so its `multiplayer` is the tree's default
## API with no peer installed -- is_connected_session() is safely false. Autofreed by GUT.
func _fresh_netsession() -> Node:
	var n := Node.new()
	n.set_script(load("res://systems/net/NetSession.gd"))
	add_child_autofree(n)
	return n

## A host with one seated opponent (slot 1) -- the minimum shape of a live match.
func _host_with_opponent() -> Dictionary:
	var session := _open_host()
	if session.is_empty():
		return {}
	session["host"]._server_admit_peer(2, NetProtocol.make_hello("Client"))
	return session


# --- Forfeit: announcement -> the other side --------------------------------

func test_a_clients_forfeit_arrives_as_opponent_forfeited():
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]
	assert_true(host.is_networked_match(), "host + one seated peer is a live networked match")

	var forfeits: Array = []
	host.opponent_forfeited.connect(func(slot): forfeits.append(slot))
	var lobby: Array = []
	host.lobby_message.connect(func(t, _d, _s): lobby.append(t))

	host._server_relay_lobby_message(2, NetSession.MSG_MATCH_FORFEIT, { "slot": 1 })

	assert_eq(forfeits.size(), 1, "the forfeit reached the other participant exactly once")
	assert_eq(int(forfeits[0]), 1, "and it names the forfeiting player's roster slot")
	assert_eq(str(lobby), str([NetSession.MSG_MATCH_FORFEIT]),
		"a forfeit is still a lobby message, so a lobby UI can see it go past")

	_close_host(session)

func test_the_forfeited_slot_comes_from_the_server_not_the_payload():
	# The payload is untrusted peer input: a client must not be able to forfeit ON BEHALF
	# of someone else by lying about the slot. The relay stamps the sender's real slot.
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]

	var forfeits: Array = []
	host.opponent_forfeited.connect(func(slot): forfeits.append(slot))

	host._server_relay_lobby_message(2, NetSession.MSG_MATCH_FORFEIT, { "slot": 0 })

	assert_eq(forfeits.size(), 1, "the message was delivered")
	assert_eq(int(forfeits[0]), 1,
		"the SERVER-derived slot (1) wins over the slot the sender claimed (0)")

	_close_host(session)

func test_a_participant_never_receives_its_own_forfeit_back():
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]

	var forfeits: Array = []
	host.opponent_forfeited.connect(func(slot): forfeits.append(slot))

	host._server_relay_lobby_message(host.local_peer_id(), NetSession.MSG_MATCH_FORFEIT, { "slot": 0 })

	assert_eq(forfeits.size(), 0,
		"the forfeiter does not lose the match to its own announcement -- it is only fanned out")

	_close_host(session)

func test_client_side_delivery_raises_the_same_signal():
	# The client half of the round trip. _rpc_lobby_deliver is the server -> client entry
	# point; called directly here (a plain local call) so no socket is involved.
	var net := _fresh_netsession()
	var forfeits: Array = []
	net.opponent_forfeited.connect(func(slot): forfeits.append(slot))

	net._rpc_lobby_deliver(NetSession.MSG_MATCH_FORFEIT, { "slot": 0 }, 0)

	assert_eq(forfeits.size(), 1, "a delivered forfeit raises opponent_forfeited on the client too")
	assert_eq(int(forfeits[0]), 0, "carrying the slot the server stamped on the relay")

func test_an_unrelated_lobby_message_is_not_a_forfeit():
	var net := _fresh_netsession()
	var forfeits: Array = []
	net.opponent_forfeited.connect(func(slot): forfeits.append(slot))

	net._rpc_lobby_deliver("map_vote", { "map_path": "res://m.tres" }, 1)

	assert_eq(forfeits.size(), 0, "only the forfeit message type raises the forfeit signal")


# --- Forfeit: the local action ----------------------------------------------

func test_forfeit_match_announces_then_tears_the_session_down():
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]

	assert_true(host.forfeit_match(), "forfeiting a live match reports that it acted")
	assert_false(host.is_connected_session(), "and leaves the session -- the match is over for us")
	assert_eq(host.player_count(), 0, "the roster is dropped with the session")

	_close_host(session)

func test_forfeit_match_is_a_no_op_outside_a_live_match():
	# Solo / menu safety: the pause menu calls this unconditionally on its forfeit row, so
	# it must never tear down a session that is not a match.
	var net := _fresh_netsession()
	assert_false(net.forfeit_match(), "with no session there is nothing to forfeit")

	var session := _open_host()
	if session.is_empty():
		return
	var host = session["host"]
	assert_false(host.forfeit_match(), "a lone host is not a match either")
	assert_true(host.is_connected_session(), "and its session is left intact")

	_close_host(session)


# --- Disconnect = the same outcome, without an announcement ------------------

func test_a_peer_vanishing_mid_match_raises_opponent_left():
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]

	# Arrays, not ints: a lambda captures locals BY VALUE, so `left += 1` would bump a
	# private copy and the assertion would always read 0. Appending mutates the shared
	# Array the capture references.
	var left: Array = []
	host.opponent_left.connect(func(): left.append(true))

	host._on_peer_disconnected(2)

	assert_eq(left.size(), 1, "a peer dropping out of a live match is reported as an opponent leaving")
	assert_eq(host.player_count(), 1, "and it loses its roster slot")

	_close_host(session)

func test_a_peer_leaving_the_lobby_is_not_an_opponent_leaving_a_match():
	# Before a match is live there is nothing to lose, so a lobby churn must not fire the
	# signal that ends a battle.
	var net := _fresh_netsession()
	var left: Array = []
	net.opponent_left.connect(func(): left.append(true))

	net._on_peer_disconnected(2)

	assert_eq(left.size(), 0, "with no live match, a disconnecting peer does not end anything")

func test_losing_the_other_end_mid_match_raises_opponent_left():
	# The client-side entry point (_on_server_disconnected), driven on a bound session:
	# "was this a live match?" is sampled BEFORE leave() clears the roster, so the peer
	# that got dropped still knows it lost something.
	var session := _host_with_opponent()
	if session.is_empty():
		return
	var host = session["host"]

	var left: Array = []
	host.opponent_left.connect(func(): left.append(true))
	var disconnects: Array = []
	host.disconnected.connect(func(): disconnects.append(true))

	host._on_server_disconnected()

	assert_eq(left.size(), 1, "losing the other end of a live match reports an opponent leaving")
	assert_eq(disconnects.size(), 1, "and still reports the plain disconnect a menu listens for")
	assert_false(host.is_connected_session(), "the session is torn down either way")

	_close_host(session)

func test_a_disconnect_outside_a_match_reports_only_the_disconnect():
	var net := _fresh_netsession()
	var left: Array = []
	net.opponent_left.connect(func(): left.append(true))
	var disconnects: Array = []
	net.disconnected.connect(func(): disconnects.append(true))

	net._on_server_disconnected()

	assert_eq(left.size(), 0, "no live match -> nothing was lost")
	assert_eq(disconnects.size(), 1, "the disconnect itself is still announced")
