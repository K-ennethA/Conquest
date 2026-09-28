extends GutTest

## The network lobby screen joined to a DEDICATED server: the real
## NetworkMultiplayerSetup scene drives the NetSession autoload, the server is a
## seatless NetSessionNode in its own MultiplayerAPI branch of this process.
## Once seated, the screen embeds the CollaborativeLobby; the assertions read it through
## its small query helpers (map_pick_enabled / selected_map_path / start_button_visible).

const H := preload("res://tests/integration/net_test_harness.gd")
const SCREEN := preload("res://menus/NetworkMultiplayerSetup.tscn")
## Joining remembers address / port / name; keep the test's out of the player's user://net.cfg.
const PREFS_PATH := "user://test_net_lobby_ui_net.cfg"

var _srv: Dictionary = {}
var _screen: Node = null
var _port: int = 0


func before_each() -> void:
	_port = H.random_port()
	_srv = H.make_peer(self, "ServerPeer")


func after_each() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
	GameModeManager.end_network_session()
	GameModeManager.consume_menu_message()
	H.free_peer(_srv)
	if FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	await H.wait_frames(get_tree(), 3)


func _open_and_join() -> bool:
	_screen = SCREEN.instantiate()
	add_child(_screen)
	await H.wait_frames(get_tree(), 2)
	_screen.net_prefs_path = PREFS_PATH
	_screen.port_input.text = str(_port)
	_screen.address_input.text = "127.0.0.1"
	_screen.player_name_input.text = "Uiy"
	_screen._on_join_pressed()
	return await H.wait_until(get_tree(), func(): return NetSession.local_slot() == 0)


func test_first_player_leads_an_unlocked_dedicated_lobby() -> void:
	var ss: NetSessionNode = _srv["session"]
	assert_eq(ss.host_dedicated(_port, {}), OK, "server up")
	assert_true(await _open_and_join(), "seated in slot 0")
	await H.wait_until(get_tree(), func(): return ss.get_match_config().has("map_path"))
	var lobby = _screen.collaborative_lobby
	assert_not_null(lobby, "lobby shown")
	assert_true(lobby != null and lobby.is_visible_in_tree(), "lobby shown")
	assert_true(lobby.map_pick_enabled(), "leader may pick the map")
	assert_false(lobby.start_button_visible(), "no Start button: the server auto-starts")
	assert_true(NetSession.is_dedicated_server(), "client knows it is on a dedicated server")
	assert_eq(ss.get_match_config()["map_path"], lobby.selected_map_path(),
		"leader's defaults were pushed to the server")
	assert_eq(ss.player_count(), 1, "the server itself holds no seat")


func test_locked_dedicated_lobby_disables_the_pickers() -> void:
	var ss: NetSessionNode = _srv["session"]
	assert_eq(ss.host_dedicated(_port, {"map_path": "res://game/maps/resources/proving_grounds.tres"}), OK, "server up")
	assert_true(await _open_and_join(), "seated in slot 0")
	await H.wait_frames(get_tree(), 3)
	var lobby = _screen.collaborative_lobby
	assert_not_null(lobby, "lobby shown")
	assert_false(lobby.map_pick_enabled(), "server fixed the map")
	assert_eq(lobby.selected_map_path(), "res://game/maps/resources/proving_grounds.tres",
		"the picker mirrors the server's map")
