extends GutTest

## The ONLINE duel's SCENE ([NetDuelStage]) on both seats of a real in-process ENet match: the
## stage never applies anything itself -- a pick on the HUD becomes an intent, the host
## validates it, both peers apply it -- and it narrates whatever was applied, prompts only its
## own seat, shows each seat its own Victory / Defeat, and turns the opponent's forfeit into
## this seat's win.

const H := preload("res://tests/integration/net_test_harness.gd")
const STAGE := preload("res://game/duel/net/NetDuelStage.tscn")
const UNITS := {0: "vineweave", 1: "gem_knight"}

var _host: Dictionary = {}
var _client: Dictionary = {}
var _port: int = 0
var _hst: NetDuelStage = null
var _cst: NetDuelStage = null


func before_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null
	DuelController.record_profile = false
	_port = H.random_port()
	_host = H.make_peer(self, "HostPeer")
	_client = H.make_peer(self, "ClientPeer")
	_hs().lobby_mode = NetProtocol.MODE_DUEL
	_cs().lobby_mode = NetProtocol.MODE_DUEL


func after_each() -> void:
	H.free_peer(_client)
	H.free_peer(_host)
	DuelController.record_profile = true
	await H.wait_frames(get_tree(), 3)
	CombatServices.match_rng = null
	CombatServices.clear()


func _hs() -> NetSessionNode:
	return _host["session"]


func _cs() -> NetSessionNode:
	return _client["session"]


func _start() -> bool:
	if _hs().host_game("Host", _port) != OK:
		return false
	_cs().join_game("127.0.0.1", "Client", _port)
	if not await H.wait_until(get_tree(), func(): return _hs().player_count() == 2 and _cs().local_slot() == 1):
		return false
	_hs().set_ready(true)
	_cs().set_ready(true)
	if not await H.wait_until(get_tree(), func(): return _hs().can_start_match()):
		return false
	_hs().start_match(DuelNetConfig.final_config(UNITS, "grove", "clear"))
	if not await H.wait_until(get_tree(), func(): return _cs().is_in_match() and _hs().is_in_match()):
		return false
	_hst = _stage(_host, _hs().get_match_config())
	_cst = _stage(_client, _cs().get_match_config())
	await H.wait_frames(get_tree(), 3)
	return _hst.rules != null and _cst.rules != null


func _stage(peer: Dictionary, cfg: Dictionary) -> NetDuelStage:
	var st: NetDuelStage = STAGE.instantiate()
	st.session = peer["session"]
	st.net_request = DuelNetConfig.build_request(cfg)["request"]
	st.instant = true
	(peer["root"] as Node).add_child(st)
	return st


func _labels(root: Node) -> String:
	return "\n".join(root.find_children("*", "Label", true, false).map(func(l): return (l as Label).text))


func test_each_seat_picks_on_its_own_hud_and_both_play_the_same_duel() -> void:
	assert_true(await _start(), "both stages up and attached")
	assert_eq(_hst.local_slot, 0, "the host is side A")
	assert_eq(_cst.local_slot, 1, "the client is side B")
	assert_eq(_cst.hud.perspective_side, 1, "the client's HUD looks from side B")
	var picks := {0: 0, 1: 0}
	var n := 0
	while not (_hst.battle.is_over and _cst.battle.is_over) and n < 3000:
		n += 1
		await get_tree().process_frame
		for st in [_hst, _cst]:
			if st._prompted and st.hud._accepting:
				var other: NetDuelStage = _cst if st == _hst else _hst
				assert_false(other._prompted, "only the acting seat is prompted")
				var actor = st.battle.current_actor()
				assert_eq(st.battle.side_of(actor), st.local_slot, "a seat is only prompted for its own unit")
				picks[st.local_slot] += 1
				st.hud._choose(st.battle.legal_slots(actor)[0])
	assert_true(_hst.battle.is_over and _cst.battle.is_over, "decided on both seats")
	assert_gt(picks[0], 0, "the host picked on its HUD")
	assert_gt(picks[1], 0, "the client picked on its HUD")
	assert_eq(_hst.battle.result.commands, _cst.battle.result.commands, "one command log")
	assert_eq(_hst.rules.state_digest(), _cst.rules.state_digest(), "one final state")
	await H.wait_until(get_tree(), func(): return _hst.hud.results_visible() and _cst.hud.results_visible(), 8000)
	var winner := _hst.battle.result.winner_side
	var host_text := _labels(_hst.hud).to_upper()
	var client_text := _labels(_cst.hud).to_upper()
	if winner == 0:
		assert_true(host_text.contains("VICTORY") and client_text.contains("DEFEAT"), "each seat reads its own outcome")
	elif winner == 1:
		assert_true(host_text.contains("DEFEAT") and client_text.contains("VICTORY"), "each seat reads its own outcome")
	var way_out := _hst.hud.find_child("Menu", true, false) as Button
	assert_true(way_out != null and way_out.text == "Back to Online", "online: the only way on is back to Online")
	assert_null(_hst.hud.find_child("Rematch", true, false), "no local rematch of a network duel")


func test_the_opponents_forfeit_is_this_seats_win() -> void:
	assert_true(await _start(), "both stages up and attached")
	assert_true(_cs().forfeit_match(), "the client forfeits")
	await H.wait_until(get_tree(), func(): return _hst.battle.is_over, 5000)
	assert_true(_hst.battle.is_over, "the host's duel ends")
	assert_eq(_hst.battle.result.winner_side, 0, "won by the seat that stayed")
	await H.wait_until(get_tree(), func(): return _hst.hud.results_visible(), 5000)
	assert_true(_labels(_hst.hud).to_upper().contains("VICTORY"), "Victory on the host's screen")
	assert_true(_labels(_hst.hud).contains("forfeited"), "and it says why")
