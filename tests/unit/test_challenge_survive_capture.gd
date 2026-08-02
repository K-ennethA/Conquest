extends GutTest

## Unit tests for [b]ChallengeController[/b]'s SURVIVE-mode outcome capture.
##
## A survive run is won by outlasting the defense: each of the CHALLENGER's own turn starts
## is one round survived, and reaching rules.survive_turns latches a win that a later wipe
## can no longer flip (the recorder is idempotent per battle). These tests drive that latch
## directly on a controller instance rather than through a live battle, so they need no
## scene, no map load and no AI.
##
## The instance under test is created with .new() and never added to the tree, so its _ready
## (which subscribes to the autoloads) never runs -- it cannot disturb the real
## ChallengeController singleton or double-count anything.
##
## STATE THIS TOUCHES, and how it is put back: capture is gated on GameSettings pointing at
## the run's map, and a latched win writes user://challenges/results.json. Both are snapshot
## in before_each and restored in after_each so the suite leaves no trace.

const CONTROLLER_SCRIPT := preload("res://game/challenge/ChallengeController.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## A map path that no real run will ever use, so the capture gate can be opened without
## pointing GameSettings at anything loadable.
const FAKE_MAP_PATH := "user://challenges/active/__survive_capture_test.tres"

var _controller: Node = null

## RUNTIME-DESIGN GAP: ChallengeController.RESULTS_PATH is a const with no injection API
## (contrast ItemInventory.set_save_path / PlayerProfile.set_source_paths), so these tests
## cannot be pointed at a temp file -- they must write the REAL results.json and put it
## back. The guard does that from after_each, which GUT runs even on a failing test.
## Untyped on purpose: a `: RefCounted` annotation would make the static analyser reject
## _guard.set_setting() / .watch_file() as "not found in base RefCounted".
var _guard


# --- Fixture ----------------------------------------------------------------

func before_each() -> void:
	_controller = CONTROLLER_SCRIPT.new()
	_guard = Guard.new()
	_guard.watch_setting("selected_map_path")
	_guard.watch_file(CONTROLLER_SCRIPT.RESULTS_PATH)


func after_each() -> void:
	_guard.restore()

	if _controller != null:
		_controller.free()
		_controller = null


# --- Helpers ----------------------------------------------------------------

func _a_character_id() -> String:
	var ids: Array = CharacterLibrary.all_ids()
	assert_gt(ids.size(), 0, "roster must have at least one character for these tests")
	return String(ids[0])


func _make_map() -> MapResource:
	var res := MapResource.new()
	res.map_name = "Survive Capture Test Map"
	res.author = "Tester"
	res.width = 5
	res.height = 5
	res.max_players = 2
	res.create_default_layout()
	var cid: String = _a_character_id()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(4, 4), 1, cid)
	return res


func _make_challenge(mode: String, survive_turns: int, par: int) -> Dictionary:
	return ChallengeCodec.build_challenge(
		_make_map(), "Capture Test", "Tester", "2026-08-01T00:00:00", {
			"challenger_squad_size": 3,
			"turn_system": 0,
			"ai_difficulty": 1,
			"mode": mode,
			"survive_turns": survive_turns,
			"par_turns": par,
		})


## Arm the controller for [param challenge] exactly the way begin() does, minus the map
## materialisation (which would need a real resource write and a scene change).
func _arm(challenge: Dictionary) -> void:
	_controller._active = challenge
	_controller._active_map_path = FAKE_MAP_PATH
	_controller._result_recorded = false
	_controller._turns = 0
	_controller._units_lost = 0
	GameSettings.selected_map_path = FAKE_MAP_PATH


func _player(player_id: int) -> Player:
	var p := Player.new(player_id)
	p.is_ai = player_id != 0
	return p


## Fire [param count] challenger turn starts.
func _take_turns(count: int) -> void:
	var challenger: Player = _player(0)
	for i in count:
		_controller._on_turn_started(challenger)


# --- Survive latch ----------------------------------------------------------

func test_survive_latches_exactly_at_the_round_target() -> void:
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)

	_take_turns(5)
	assert_eq(_controller._turns, 5, "each challenger turn start is one round survived")
	assert_false(_controller._result_recorded,
		"the run must NOT be decided before the round target is reached")

	_take_turns(1)
	assert_eq(_controller._turns, 6)
	assert_true(_controller._result_recorded, "reaching survive_turns must latch the outcome")

	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_false(record.is_empty(), "the latched run must be written to results.json")
	assert_true(bool(record.get("won", false)), "outlasting the defense is a WIN")
	assert_eq(String(record.get("mode", "")), ChallengeCodec.MODE_SURVIVE)
	assert_eq(int(record.get("last_turns", -1)), 6)
	assert_eq(int(record.get("last_score", -1)),
		ChallengeScoring.score(true, 6, ChallengeCodec.rules_par_turns(challenge), 0),
		"the recorded score must come from the shared formula")
	assert_true(bool(record.get("last_perfect", false)), "no units lost -> a perfect run")


func test_the_latched_win_survives_further_turns() -> void:
	# Once latched, extra turns must not re-record (and so must not re-score) the run.
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)
	_take_turns(10)

	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_eq(int(record.get("last_turns", -1)), 6,
		"the outcome is frozen at the round it latched, not at the last turn played")
	assert_eq(int(record.get("attempts", -1)), 1, "one battle records exactly one attempt")


func test_a_later_wipe_cannot_flip_a_latched_survive_win() -> void:
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)
	_take_turns(6)
	assert_true(_controller._result_recorded)

	# An elimination arriving after the latch must be ignored by the recorder.
	_controller._on_player_eliminated(_player(0))

	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_true(bool(record.get("won", false)), "the survive win must stand")
	assert_eq(int(record.get("attempts", -1)), 1, "the post-latch elimination must not re-record")


func test_defender_turns_do_not_count_as_rounds() -> void:
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)

	var defender: Player = _player(1)
	for i in 12:
		_controller._on_turn_started(defender)

	assert_eq(_controller._turns, 0, "only the challenger's own turns are rounds survived")
	assert_false(_controller._result_recorded, "defender turns must never latch a win")


func test_breach_mode_never_latches_on_turn_count() -> void:
	# In breach mode the turn tally only feeds the score; the outcome waits for eliminations.
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_BREACH, 6, 10)
	_arm(challenge)
	_take_turns(30)

	assert_eq(_controller._turns, 30, "breach still tallies turns for the score")
	assert_false(_controller._result_recorded, "a breach run is never decided by turn count")


func test_capture_is_inert_when_the_run_is_not_armed() -> void:
	# GameSettings pointing somewhere else means this is a DIFFERENT match: nothing records.
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)
	GameSettings.selected_map_path = "res://game/maps/resources/default_skirmish.tres"

	_take_turns(12)
	assert_eq(_controller._turns, 0, "turns in an unrelated match must not be counted")
	assert_false(_controller._result_recorded, "an unrelated match must never record a result")


# --- Units lost feeds the score ---------------------------------------------

func test_units_lost_lowers_the_latched_score() -> void:
	var challenge: Dictionary = _make_challenge(ChallengeCodec.MODE_SURVIVE, 6, 10)
	_arm(challenge)
	_controller._units_lost = 2
	_take_turns(6)

	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_eq(int(record.get("last_units_lost", -1)), 2)
	assert_false(bool(record.get("last_perfect", true)), "losing a unit is not perfect")
	assert_eq(int(record.get("last_score", -1)),
		ChallengeScoring.score(true, 6, ChallengeCodec.rules_par_turns(challenge), 2))
