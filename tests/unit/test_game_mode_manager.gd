extends GutTest

## GameModeManager outside a network match must answer exactly like local play,
## and ending a session must restore local defaults (a former network client must
## not keep its old seat / MULTIPLAYER mode into a later single-player game).

var _saved_mode: int
var _saved_difficulty: int


func before_each() -> void:
	_saved_mode = GameSettings.game_mode
	_saved_difficulty = GameSettings.ai_difficulty


func after_each() -> void:
	GameSettings.game_mode = _saved_mode
	GameSettings.ai_difficulty = _saved_difficulty
	CombatServices.match_rng = null


func test_local_play_defaults() -> void:
	GameSettings.game_mode = GameSettings.GameMode.VERSUS
	assert_false(GameModeManager.is_multiplayer_active(), "no network match")
	assert_eq(GameModeManager.get_local_player_id(), 0, "local seat is 0")
	assert_true(GameModeManager.is_my_turn(), "turn gating is the turn system's job locally")
	assert_false(GameModeManager.request_end_turn(), "intents are refused outside a network match")


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
