extends GutTest

## The NetSession BACKSTOP for a turn no seat can take. Network versus seats two humans and
## runs no AI, so if the rules ever hand the turn to a slot nobody sits in (an AI / neutral
## faction that slipped past the offline-only map gate), no intent could ever arrive for it and
## the match used to hang forever (Riftwood: "state=IN_MATCH seq=35" until the timeout). The
## host now ends the match for everyone with NetSessionNode.ABORT_UNDRIVEN_TURN instead.
##
## Real ENet on 127.0.0.1 (net_test_harness.gd), a player-host + one client, over a tiny
## deterministic stub ruleset whose turn rotates 0 -> 1 -> 2 on END_TURN: slot 2 is the
## unseated "neutral".

const H := preload("res://tests/integration/net_test_harness.gd")


## The four calls NetSession makes on its game. Every END_TURN hands the turn to the next of
## [member slots] slots; the digest is a pure function of the (identical) applied history.
class RotatingRules extends RefCounted:
	var slots: int = 3
	var slot: int = 0
	var applied: int = 0

	func validate_intent(_action: Dictionary, actor_slot: int) -> String:
		return NetProtocol.INTENT_OK if actor_slot == slot else NetProtocol.INTENT_NOT_YOUR_TURN

	func apply_action(_action: Dictionary) -> Dictionary:
		applied += 1
		slot = (slot + 1) % slots
		return {"ok": true, "events": []}

	func current_turn_slot() -> int:
		return slot

	func state_digest() -> int:
		return applied * 10 + slot


var _host: Dictionary = {}
var _client: Dictionary = {}
var _port: int = 0


func before_each() -> void:
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")


func after_each() -> void:
	H.free_peer(_client)
	H.free_peer(_host)
	await H.wait_frames(get_tree(), 2)


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _start(slots: int) -> Array:
	var rules: Array = [RotatingRules.new(), RotatingRules.new()]
	rules[0].slots = slots
	rules[1].slots = slots
	assert_eq(_hs().host_game("Host", _port), OK, "hosting")
	_cs().join_game("127.0.0.1", "Client", _port)
	assert_true(await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1),
		"client seated")
	_hs().set_ready(true)
	_cs().set_ready(true)
	assert_true(await H.wait_until(get_tree(), func(): return _hs().can_start_match()), "startable")
	_hs().start_match()
	assert_true(await H.wait_until(get_tree(), func(): return _cs().is_in_match()), "match started")
	_hs().attach_game(rules[0])
	_cs().attach_game(rules[1])
	return rules


## Mark the host's expected push_warning (GUT tracks it as an engine error) handled.
func _expect_warning(text: String) -> int:
	var n := 0
	for e in get_errors():
		if text in str(e.code) or text in str(e.rationale):
			e.handled = true
			n += 1
	return n


func test_a_turn_handed_to_an_unseated_slot_ends_the_match_instead_of_hanging() -> void:
	var rules := await _start(3)
	var host_aborts: Array = []
	var client_aborts: Array = []
	_hs().match_aborted.connect(func(r): host_aborts.append(r))
	_cs().match_aborted.connect(func(r): client_aborts.append(r))

	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await H.wait_until(get_tree(), func(): return _cs().last_applied_seq() >= 1 and _cs().is_my_turn()),
		"slot 0 ended its turn; slot 1 (seated) is up")
	await H.wait_frames(get_tree(), 3)
	assert_eq(host_aborts, [], "a seated slot's turn is normal play")

	_cs().submit_intent(NetProtocol.end_turn())
	assert_true(await H.wait_until(get_tree(), func(): return not host_aborts.is_empty() and not client_aborts.is_empty()),
		"the turn reached unseated slot 2 and the match was ended")
	assert_eq(host_aborts, [NetSessionNode.ABORT_UNDRIVEN_TURN], "the host says why")
	assert_eq(client_aborts, [NetSessionNode.ABORT_UNDRIVEN_TURN], "and the client hears the same reason")
	assert_eq(rules[0].applied, 2, "both END_TURNs applied on the host")
	assert_eq(rules[1].applied, 2, "and on the client -- the abort came after the identical state")
	assert_false(_hs().is_in_match(), "the host left the match")
	assert_eq(_expect_warning(NetSessionNode.ABORT_UNDRIVEN_TURN), 1, "the host logged the abort once")


func test_a_two_seat_rotation_never_trips_the_backstop() -> void:
	await _start(2)
	var aborts: Array = []
	_hs().match_aborted.connect(func(r): aborts.append(r))
	_hs().submit_intent(NetProtocol.end_turn())
	assert_true(await H.wait_until(get_tree(), func(): return _cs().last_applied_seq() >= 1 and _cs().is_my_turn()),
		"slot 1 is up")
	_cs().submit_intent(NetProtocol.end_turn())
	assert_true(await H.wait_until(get_tree(), func(): return _hs().last_applied_seq() >= 2 and _hs().is_my_turn()),
		"back to slot 0")
	await H.wait_frames(get_tree(), 5)
	assert_eq(aborts, [], "no abort while every turn belongs to a seat")
	assert_true(_hs().is_in_match(), "the match goes on")
