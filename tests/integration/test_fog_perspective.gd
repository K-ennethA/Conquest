extends GutTest

## WHOSE EYES: [method FogOfWarOverlay.local_perspective], the single definition of "the
## player this screen belongs to", and the gates that hang off it.
##
## This is the rule the whole fog layer is built on, so it is pinned on its own: every hook
## in the HUD asks this one function, and getting it wrong is not a cosmetic bug -- it is a
## wallhack (hotseat showing player 1 the board through player 0's eyes) or a blindfold
## (solo snapping to the bot's vision the moment the bot's turn starts).
##
## Integration, not unit, by tests/README's split: it reads and drives real autoload state
## (GameSettings.game_mode, PlayerManager's roster, ReplayPlayback's process-wide flag).
## Every one of those is snapshot-and-restored from `after_each`, which GUT runs even when a
## test fails.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const FogDoubles := preload("res://tests/helpers/fog_doubles.gd")

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard

## PlayerManager's roster is global and has no injection API, so it is snapshotted by hand.
var _saved_players: Array = []
var _saved_index: int = 0


func before_each() -> void:
	_guard = Guard.new()
	_saved_players = PlayerManager.players.duplicate()
	_saved_index = PlayerManager.current_player_index
	FogOfWarOverlay.reset_for_tests()


func after_each() -> void:
	FogOfWarOverlay.reset_for_tests()
	ReplayPlayback.end_playback()
	PlayerManager.players.assign(_saved_players)
	PlayerManager.current_player_index = _saved_index
	_guard.restore()


# --- Fixture ------------------------------------------------------------------

## Install a roster of [param seats], each entry { id: int, ai: bool }, and put the turn on
## [param active_index]. Players are plain [Player] RefCounted-free objects... they extend
## Resource, so nothing here can orphan.
func _seat(seats: Array, active_index: int) -> void:
	var roster: Array[Player] = []
	for entry in seats:
		var player := Player.new(int(entry["id"]), "Seat%d" % int(entry["id"]))
		player.is_ai = bool(entry.get("ai", false))
		player.is_neutral = bool(entry.get("neutral", false))
		roster.append(player)
	PlayerManager.players.assign(roster)
	PlayerManager.current_player_index = active_index


func _fog_on() -> FogDoubles.StubVision:
	var vision := FogDoubles.StubVision.new()
	vision.set_board(4, 4)
	FogOfWarOverlay.set_vision_override(vision)
	return vision


# =============================================================================
# SOLO
# =============================================================================

func test_solo_uses_the_humans_own_eyes() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": true}], 0)

	assert_eq(FogOfWarOverlay.local_perspective(), 0,
		"solo shows the board through the one human seat")


func test_solo_keeps_the_humans_eyes_through_the_ai_turn() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": true}], 1)  # the BOT is acting

	assert_eq(FogOfWarOverlay.local_perspective(), 0,
		"watching the enemy turn through your OWN fog is the point -- never the bot's eyes")


func test_a_versus_match_with_one_human_seat_is_solo_not_hotseat() -> void:
	# GameSettings.game_mode DEFAULTS to VERSUS, so a skirmish that never set the mode would
	# otherwise be mistaken for hotseat and hand the player the bot's vision on its turn.
	# Seats, not the enum, decide.
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": true}], 1)

	assert_eq(FogOfWarOverlay.local_perspective(), 0,
		"one human seat is solo however the mode enum is set")


# =============================================================================
# HOTSEAT
# =============================================================================

func test_hotseat_shows_the_active_seat_its_own_vision() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": false}], 0)

	assert_eq(FogOfWarOverlay.local_perspective(), 0,
		"player 0 is at the controls, so the screen is player 0's")


func test_hotseat_swaps_the_perspective_when_the_seat_changes() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": false}], 0)
	assert_eq(FogOfWarOverlay.local_perspective(), 0, "player 0's turn")

	PlayerManager.current_player_index = 1  # the seat changes hands

	assert_eq(FogOfWarOverlay.local_perspective(), 1,
		"player 1 takes the controls and sees ONLY their own vision -- two humans on one "
		+ "screen means neither may keep the other's eyes")


func test_hotseat_holds_the_last_human_seat_through_a_bot_seat() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": false}, {"id": 2, "ai": true}], 1)
	assert_eq(FogOfWarOverlay.local_perspective(), 1, "player 1 is acting")

	PlayerManager.current_player_index = 2  # a bot seat takes its turn

	assert_eq(FogOfWarOverlay.local_perspective(), 1,
		"an AI seat is nobody's eyes -- the last human at the controls keeps the screen")


func test_a_neutral_camp_never_becomes_the_perspective() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": false},
		{"id": 3, "ai": false, "neutral": true}], 0)
	assert_eq(FogOfWarOverlay.local_perspective(), 0, "player 0 is acting")

	PlayerManager.current_player_index = 2  # the dormant neutral faction "acts"

	assert_eq(FogOfWarOverlay.local_perspective(), 0,
		"a neutral faction has no player behind it, so it cannot claim the screen")


# =============================================================================
# REPLAY -- a spectator is not playing
# =============================================================================

func test_a_replay_viewer_sees_everything() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.VERSUS)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": false}], 0)
	var vision := _fog_on()
	vision.hide_cells(0, [Vector2i(1, 1)])
	assert_true(FogOfWarOverlay.fog_active(), "fog is on for a player")

	ReplayPlayback.begin_playback()

	assert_eq(FogOfWarOverlay.local_perspective(), FogOfWarOverlay.SPECTATOR,
		"a replay viewer has no seat -- the perspective is SPECTATOR")
	assert_false(FogOfWarOverlay.fog_active(),
		"nothing is hidden from someone who is not making decisions")
	assert_false(FogOfWarOverlay.cell_hidden(Vector2i(1, 1)),
		"a cell the player could not see is fully visible to the spectator")


func test_leaving_the_replay_puts_the_fog_back() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_seat([{"id": 0, "ai": false}, {"id": 1, "ai": true}], 0)
	var vision := _fog_on()
	vision.hide_cells(0, [Vector2i(2, 2)])

	ReplayPlayback.begin_playback()
	assert_false(FogOfWarOverlay.cell_hidden(Vector2i(2, 2)), "spectating: no fog")
	ReplayPlayback.end_playback()

	assert_true(FogOfWarOverlay.cell_hidden(Vector2i(2, 2)),
		"back in a real battle, the mist is back -- spectator mode is not sticky")


# =============================================================================
# FOG OFF COSTS NOTHING
# =============================================================================

func test_with_no_vision_core_mounted_every_gate_answers_false() -> void:
	# The state of the project until the vision core lands, and the state of every map that
	# never authored fog. Nothing may be hidden and nothing may be dimmed.
	FogOfWarOverlay.set_vision_override(null)

	assert_false(FogOfWarOverlay.fog_active(), "no vision core: fog is off")
	assert_false(FogOfWarOverlay.cell_hidden(Vector2i(3, 3)), "no cell is hidden")
	assert_false(FogOfWarOverlay.world_hidden(Vector3(6.0, 0.0, 6.0)), "no world point is hidden")


func test_a_core_reporting_fog_off_hides_nothing() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_seat([{"id": 0, "ai": false}], 0)
	var vision := _fog_on()
	vision.hide_cells(0, [Vector2i(0, 0), Vector2i(1, 0)])
	vision.enabled = false

	assert_false(FogOfWarOverlay.fog_active(),
		"MapResource.fog_of_war is the toggle -- off means the layer is inert")
	assert_false(FogOfWarOverlay.cell_hidden(Vector2i(0, 0)),
		"fog off = everything visible, whatever the core's hidden sets say")


func test_the_world_to_cell_fold_matches_the_board() -> void:
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_seat([{"id": 0, "ai": false}], 0)
	var vision := _fog_on()
	vision.hide_cells(0, [Vector2i(2, 1)])

	# Cells are 2x2 world units; cell (2,1) spans x 4..6, z 2..4.
	assert_true(FogOfWarOverlay.world_hidden(Vector3(5.0, 0.0, 3.0)),
		"a world point over a hidden cell is hidden (this is the FX/float gate)")
	assert_false(FogOfWarOverlay.world_hidden(Vector3(3.0, 0.0, 3.0)),
		"the cell next door is untouched -- suppression is per cell, not per blast")


# --- The networked seat -------------------------------------------------------

func test_a_networked_match_reads_its_own_slot() -> void:
	# The branch is real and load-bearing (a networked VERSUS match must NOT swap eyes on
	# the opponent's turn the way hotseat does), but proving it needs a live, connected,
	# multi-participant NetSession -- a real socket. Same opt-in boundary
	# integration/test_mp_loopback.gd draws for the transport itself.
	pending("needs a live NetSession (real socket); the slot rule rides "
		+ "NetSession.local_slot(), covered by test_mp_loopback")
