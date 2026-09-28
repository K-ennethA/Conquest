extends GutTest

## GameModeManager outside a network match must answer exactly like local play,
## and ending a session must restore local defaults (a former network client must
## not keep its old seat / MULTIPLAYER mode into a later single-player game).
## Also pinned: how the host's match config lands in this peer's GameSettings
## (apply_match_config -- the testable half of match_started), including the
## squad replication rule and the custom-map boot gate.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const BUILTIN_MAP := "res://game/maps/resources/default_skirmish.tres"

var _saved_mode: int
var _saved_difficulty: int
var _guard


func before_each() -> void:
	_saved_mode = GameSettings.game_mode
	_saved_difficulty = GameSettings.ai_difficulty
	_guard = Guard.new()
	for prop in ["selected_squad", "host_squad", "selected_map_path", "selected_turn_system",
			"player_names", "player_count", "auto_end_turn", "versus_rounds", "custom_map_json"]:
		_guard.watch_setting(prop)
	MatchLoadouts.clear()


func after_each() -> void:
	GameModeManager.end_network_session()
	GameModeManager.consume_menu_message()
	GameSettings.game_mode = _saved_mode
	GameSettings.ai_difficulty = _saved_difficulty
	CombatServices.match_rng = null
	_guard.restore()
	MatchLoadouts.clear()


func test_local_play_defaults() -> void:
	GameSettings.game_mode = GameSettings.GameMode.VERSUS
	assert_false(GameModeManager.is_multiplayer_active(), "no network match")
	assert_eq(GameModeManager.get_local_player_id(), 0, "local seat is 0")
	assert_true(GameModeManager.is_my_turn(), "turn gating is the turn system's job locally")
	assert_false(GameModeManager.request_end_turn(), "intents are refused outside a network match")
	assert_false(GameModeManager.submit_action("end_turn", {}), "the legacy envelope refuses too")


func test_stale_multiplayer_flag_without_session_is_not_a_match() -> void:
	GameSettings.game_mode = GameSettings.GameMode.MULTIPLAYER
	assert_false(GameModeManager.is_multiplayer_active(), "no live session -> not a network match")
	assert_eq(GameModeManager.get_local_player_id(), 0, "no stale network seat leaks out")


func test_end_network_session_restores_local_defaults() -> void:
	GameSettings.game_mode = GameSettings.GameMode.MULTIPLAYER
	CombatServices.match_rng = RandomNumberGenerator.new()
	GameModeManager.end_network_session("bye")
	assert_eq(GameSettings.game_mode, GameSettings.GameMode.VERSUS, "mode reset to local versus")
	assert_null(CombatServices.match_rng, "shared combat RNG dropped")
	assert_false(NetSession.is_active(), "session closed")
	assert_eq(GameModeManager.consume_menu_message(), "bye", "menu message kept for the main menu")
	assert_eq(GameModeManager.consume_menu_message(), "", "message is one-shot")


func test_status_reads_as_disconnected_outside_a_session() -> void:
	var status: Dictionary = GameModeManager.get_game_status()
	assert_false(bool(status.get("is_active", true)), "no match")
	assert_eq(int(status["network_stats"]["connected_peers"]), 0, "nobody connected")


# --- The host's match config on this peer --------------------------------------

func test_match_config_lands_in_game_settings() -> void:
	var boot := GameModeManager.apply_match_config({
		"map_path": BUILTIN_MAP, "turn_system": 0, "auto_end_turn": false, "versus_rounds": 3,
		"slots": {0: "Ada", 1: "Bo"}, "seed": 77,
	})
	assert_eq(boot, BUILTIN_MAP, "a builtin map boots from its own path")
	assert_eq(GameSettings.game_mode, GameSettings.GameMode.MULTIPLAYER, "network mode")
	assert_eq(GameSettings.get_selected_map(), BUILTIN_MAP, "the host's map")
	assert_eq(GameSettings.player_names, ["Ada", "Bo"] as Array[String], "seat names in slot order")
	assert_false(GameSettings.auto_end_turn, "the host's rules toggle")
	assert_eq(GameSettings.versus_rounds, 3, "the host's best-of")
	assert_not_null(CombatServices.match_rng, "the public setup RNG is installed for board setup")


func test_a_non_builtin_map_without_content_is_refused() -> void:
	var boot := GameModeManager.apply_match_config({"map_path": "user://maps/not_here.json", "seed": 1})
	assert_eq(boot, "", "a map this peer cannot verify never becomes a board")


func test_replicated_squads_survive_the_match_start() -> void:
	# A player-hosted lobby exchanged match_loadout cards (MatchLoadouts active): the local
	# pick and the host's replicated squad are what MapLoader resolves from.
	MatchLoadouts.set_local_slot(1)
	GameSettings.set_selected_squad(["gem_knight"])
	GameModeManager.apply_match_config({"map_path": BUILTIN_MAP, "host_squad": ["necromancer"], "seed": 1})
	assert_eq(GameSettings.get_selected_squad(), ["gem_knight"], "our own pick is kept")
	assert_eq(GameSettings.get_host_squad(), ["necromancer"], "the host's squad is applied for slot 0")


func test_without_a_loadout_exchange_every_peer_fields_map_rosters() -> void:
	# A dedicated server (no lobby UI, no seat) or a lobby that skipped the exchange: nobody
	# may field a locally picked squad the other peers never heard of.
	GameSettings.set_selected_squad(["gem_knight"])
	GameModeManager.apply_match_config({"map_path": BUILTIN_MAP, "host_squad": ["necromancer"], "seed": 1})
	assert_eq(GameSettings.get_selected_squad(), [], "local pick cleared")
	assert_eq(GameSettings.get_host_squad(), [], "and no replicated host squad")
