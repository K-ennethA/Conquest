extends GutTest

## ATTEMPT REPORTING: every finished attempt at a COMMUNITY-installed challenge is reported
## back to the community service, win OR loss, exactly once.
##
## What is pinned here:
##   * a win reports cleared = true, a loss reports cleared = false -- a failed attempt is
##     precisely what the defending author wants to know about, so both go up;
##   * both FORFEIT paths (the end-of-day rollover and walking out through the pause menu)
##     report a played-and-lost attempt, because both spend the attempt;
##   * a challenge that arrived as a friend SHARE CODE carries no "community_id" and is
##     NEVER reported -- silently, changing nothing else about the finish;
##   * one attempt == one report, whatever combination of end signals arrives;
##   * the payload is { cleared, score, turns } with the score + turns taken from the SAME
##     source of truth the local record uses ([ChallengeScoring] and the challenger turn tally);
##   * a report that fails, or never answers at all (offline), cannot disturb the finish flow:
##     the local record is still written and nothing is retried.
##
## HOW IT IS ISOLATED: the controller under test is built with .new() and never added to the
## tree, so its _ready never runs and the real ChallengeController autoload is untouched (same
## approach as test_challenge_survive_capture.gd). The community front door and the profile
## recorder are STAND-INS injected through set_community_client() / set_profile() -- mirroring
## the MockNetSession injection in test_lobby_transport_adapter.gd -- so no test ever reaches
## the real community store or the player's profile. Results go to a `user://test_*` file via
## set_results_path(), and GameSettings.selected_map_path is guarded.


## Stand-in for [CommunityClient]. Records what it was asked to report and answers the
## callback the way the pinned contract does.
class StubCommunityClient extends RefCounted:
	## One entry per report: { "id": String, "outcome": Dictionary }.
	var reports: Array = []
	## What the async callback reports back. `false` is the offline / rejected case.
	var ok: bool = true
	## When true the callback is NEVER invoked -- a request that hangs (no network at all).
	var silent: bool = false

	func report_attempt(id: String, outcome: Dictionary, cb: Callable) -> void:
		reports.append({ "id": id, "outcome": outcome.duplicate(true) })
		if silent or not cb.is_valid():
			return
		cb.call({ "ok": ok } if ok else { "ok": false, "error": "offline" })


## A client that predates the report API entirely (an older/partial front door). The
## controller must notice and do nothing rather than crash the finish.
class ClientWithoutReportApi extends RefCounted:
	var touched: bool = false


## Stand-in for the PlayerProfile autoload -- only the one hook the controller uses.
class StubProfile extends RefCounted:
	## One entry per recorded battle: { "mode": String, "won": bool, "meta": Dictionary }.
	var results: Array = []

	func notify_battle_result(mode: String, won: bool, meta: Dictionary = {}) -> void:
		results.append({ "mode": mode, "won": won, "meta": meta.duplicate(true) })


const CONTROLLER_SCRIPT := preload("res://game/challenge/ChallengeController.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## A map path no real run will use, so the capture gate can be opened without pointing
## GameSettings at anything loadable.
const FAKE_MAP_PATH := "user://challenges/active/__attempt_report_test.tres"

## Results go here, never the player's real file (ChallengeController.set_results_path).
const TEMP_RESULTS_PATH := "user://test_challenge_attempt_report_results.json"

## The community id a downloaded challenge is stamped with by the install path.
const COMMUNITY_ID := "svc-challenge-4711"

var _controller: Node = null
var _client: StubCommunityClient = null
var _profile: StubProfile = null
## Untyped on purpose: a `: RefCounted` annotation makes the analyser reject the guard's
## dynamically-dispatched helpers.
var _guard


# --- Fixture ----------------------------------------------------------------

func before_each() -> void:
	_controller = CONTROLLER_SCRIPT.new()
	_controller.set_results_path(TEMP_RESULTS_PATH)
	_client = StubCommunityClient.new()
	_controller.set_community_client(_client)
	_profile = StubProfile.new()
	_controller.set_profile(_profile)

	_guard = Guard.new()
	_guard.watch_setting("selected_map_path")


func after_each() -> void:
	_guard.restore()

	if _controller != null:
		_controller.free()
		_controller = null
	_client = null
	_profile = null

	if FileAccess.file_exists(TEMP_RESULTS_PATH):
		DirAccess.remove_absolute(TEMP_RESULTS_PATH)


# --- Helpers ----------------------------------------------------------------

func _a_character_id() -> String:
	var ids: Array = CharacterLibrary.all_ids()
	assert_gt(ids.size(), 0, "roster must have at least one character for these tests")
	return String(ids[0])


func _make_map() -> MapResource:
	var res := MapResource.new()
	res.map_name = "Attempt Report Test Map"
	res.author = "Tester"
	res.width = 5
	res.height = 5
	res.max_players = 2
	res.create_default_layout()
	var cid: String = _a_character_id()
	res.set_character_spawn_at_position(Vector2i(0, 0), 0, cid)
	res.set_character_spawn_at_position(Vector2i(4, 4), 1, cid)
	return res


## A challenge as it exists AFTER a community install: the codec blob plus the stamped
## "community_id" the install path adds.
func _community_challenge(mode: String = ChallengeCodec.MODE_SURVIVE) -> Dictionary:
	var challenge: Dictionary = _share_code_challenge(mode)
	challenge["community_id"] = COMMUNITY_ID
	return challenge


## A challenge as it exists after a FRIEND SHARE CODE import: no community id, by design.
func _share_code_challenge(mode: String = ChallengeCodec.MODE_SURVIVE) -> Dictionary:
	return ChallengeCodec.build_challenge(
		_make_map(), "Attempt Report Test", "Tester", "2026-08-01T00:00:00", {
			"challenger_squad_size": 3,
			"turn_system": 0,
			"ai_difficulty": 1,
			"mode": mode,
			"survive_turns": 6,
			"par_turns": 10,
		})


## Arm the controller for [param challenge] exactly the way begin() does, minus the map
## materialisation (which would need a real resource write and a scene change).
func _arm(challenge: Dictionary) -> void:
	_controller._active = challenge
	_controller._active_map_path = FAKE_MAP_PATH
	_controller._result_recorded = false
	_controller._attempt_reported = false
	_controller._turns = 0
	_controller._units_lost = 0
	GameSettings.selected_map_path = FAKE_MAP_PATH


## Fire [param count] challenger turn starts (player 0 -- the challenger's slot).
func _take_turns(count: int) -> void:
	var challenger := Player.new(0)
	for i in count:
		_controller._on_turn_started(challenger)


func _only_report() -> Dictionary:
	assert_eq(_client.reports.size(), 1, "exactly one attempt report")
	if _client.reports.is_empty():
		return {}
	return _client.reports[0]


func _only_outcome() -> Dictionary:
	var report: Dictionary = _only_report()
	return report.get("outcome", {})


# --- A win reports a clear ---------------------------------------------------

func test_a_win_reports_one_cleared_attempt() -> void:
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)

	# Outlasting the defense latches the win through the ordinary capture path.
	_take_turns(6)
	assert_true(_controller._result_recorded, "the survive target latches the outcome")

	var report: Dictionary = _only_report()
	assert_eq(String(report.get("id", "")), COMMUNITY_ID,
		"the report is keyed by the COMMUNITY id, not the local content checksum")
	var outcome: Dictionary = report.get("outcome", {})
	assert_true(bool(outcome.get("cleared", false)), "a win is reported as cleared")


func test_the_outcome_payload_matches_the_scoring_source_of_truth() -> void:
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_controller._units_lost = 2
	_take_turns(6)

	var outcome: Dictionary = _only_outcome()
	assert_eq(outcome.keys().size(), 3, "the payload carries exactly cleared / score / turns")
	assert_true(outcome.has("cleared") and outcome.has("score") and outcome.has("turns"),
		"the payload keys are the pinned contract's")
	assert_eq(int(outcome.get("turns", -1)), 6,
		"turns is the CHALLENGER's own turn tally, the same one the record stores")
	assert_eq(int(outcome.get("score", -1)),
		ChallengeScoring.score(true, 6, ChallengeCodec.rules_par_turns(challenge), 2),
		"the reported score comes from the shared formula, not a second calculation")

	# ...and it agrees with what was written locally, so the defender and the attacker are
	# never looking at two different numbers for one attempt.
	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_eq(int(outcome.get("score", -1)), int(record.get("last_score", -2)))
	assert_eq(int(outcome.get("turns", -1)), int(record.get("last_turns", -2)))


# --- A loss reports too ------------------------------------------------------

func test_a_loss_reports_an_uncleared_attempt() -> void:
	var challenge: Dictionary = _community_challenge(ChallengeCodec.MODE_BREACH)
	_arm(challenge)
	_take_turns(4)

	# The challenger was wiped: the capture funnel records the defeat.
	_controller._record_result(false)

	var outcome: Dictionary = _only_outcome()
	assert_false(bool(outcome.get("cleared", true)),
		"a failed attempt is reported -- that is what the defender wants to know")
	assert_eq(int(outcome.get("turns", -1)), 4, "a loss still carries how far they got")
	assert_eq(int(outcome.get("score", -1)), 0, "and a loss scores 0, as the formula says")


func test_the_end_of_day_forfeit_reports_an_uncleared_attempt() -> void:
	# The EOD rollover forfeits a paused attempt from the MAIN MENU -- no live battle, no
	# armed capture; the stored counters come in as arguments.
	var challenge: Dictionary = _community_challenge()

	assert_true(_controller.forfeit_expired_attempt(challenge, 5, 1),
		"a forfeitable attempt is accepted")

	var outcome: Dictionary = _only_outcome()
	assert_false(bool(outcome.get("cleared", true)), "an expired attempt was played and lost")
	assert_eq(int(outcome.get("turns", -1)), 5, "the turns come from the saved attempt")
	assert_eq(int(outcome.get("score", -1)), 0)


func test_quitting_out_of_the_battle_forfeits_and_reports() -> void:
	var challenge: Dictionary = _community_challenge(ChallengeCodec.MODE_BREACH)
	_arm(challenge)
	_take_turns(3)

	assert_true(_controller.forfeit_active_attempt(), "the live attempt is forfeitable")

	var outcome: Dictionary = _only_outcome()
	assert_false(bool(outcome.get("cleared", true)), "abandoning the battle is a failed attempt")
	assert_eq(int(outcome.get("turns", -1)), 3)

	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_eq(int(record.get("attempts", -1)), 1, "and it counts as an attempt locally too")
	assert_false(_controller.is_capturing(), "the run is disarmed once the player walks out")


func test_forfeiting_is_inert_outside_a_live_challenge() -> void:
	# The pause menu calls this on EVERY quit-to-menu, including skirmish and Arena exits.
	assert_false(_controller.forfeit_active_attempt(), "nothing is armed, so nothing happens")
	assert_eq(_client.reports.size(), 0, "an unrelated quit must never report an attempt")

	# ...and it is inert again once the battle has already ended on its own.
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)
	assert_false(_controller.forfeit_active_attempt(),
		"a decided run cannot be forfeited on the way out")
	assert_eq(_client.reports.size(), 1, "and the finished attempt is still reported once")


# --- Share codes are never reported ------------------------------------------

func test_a_share_code_challenge_is_never_reported() -> void:
	var challenge: Dictionary = _share_code_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_true(_controller._result_recorded, "the run still ends normally")
	assert_eq(_client.reports.size(), 0,
		"a friend share code has no community id -- that path is serverless by design")

	# Silently: the local record is written exactly as before.
	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_true(bool(record.get("won", false)), "the local personal best is unaffected")


func test_an_empty_community_id_is_treated_as_absent() -> void:
	var challenge: Dictionary = _share_code_challenge()
	challenge["community_id"] = "   "
	_arm(challenge)
	_take_turns(6)

	assert_eq(_client.reports.size(), 0, "a blank id is not an id")


# --- Exactly once ------------------------------------------------------------

func test_an_attempt_is_never_reported_twice() -> void:
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)
	assert_eq(_client.reports.size(), 1, "the latch fires the report once")

	# Every other end signal that could still arrive for this battle:
	_take_turns(4)                              # more turns after the survive latch
	_controller._on_player_eliminated(Player.new(0))  # a wipe arriving after the latch
	_controller.forfeit_active_attempt()        # the player quits out of the summary
	assert_eq(_client.reports.size(), 1, "no later signal can report the same attempt again")


func test_a_forced_re_record_still_reports_only_once() -> void:
	# _record_result is the single funnel; if anything ever re-enters it for the SAME attempt
	# (the forfeit paths deliberately reset the result latch), the report latch must hold.
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	_controller._result_recorded = false
	_controller._record_result(false)

	assert_eq(_client.reports.size(), 1, "one attempt, one report")
	assert_true(bool(_only_outcome().get("cleared", false)),
		"and it is still the FIRST, real outcome that was sent")


func test_a_new_attempt_reports_again() -> void:
	# The latch is per attempt, not per install: replaying the challenge reports the replay.
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	_arm(challenge)
	_take_turns(6)

	assert_eq(_client.reports.size(), 2, "each attempt is its own report")


# --- Fire and forget ---------------------------------------------------------

func test_a_rejected_report_does_not_disturb_the_finish() -> void:
	_client.ok = false
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_eq(_client.reports.size(), 1, "the attempt was still handed off")
	var record: Dictionary = _controller.result_for(ChallengeCodec.challenge_id(challenge))
	assert_true(bool(record.get("won", false)),
		"a rejected report cannot stop the local record from being written")
	assert_eq(int(record.get("attempts", -1)), 1)


func test_a_report_that_never_answers_does_not_block_the_finish() -> void:
	# Offline: the callback never comes back at all. The finish flow is synchronous and must
	# not be waiting on it. (No retry queue by design -- see _report_attempt's note.)
	_client.silent = true
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_true(_controller._result_recorded, "the run finished without waiting for an answer")
	assert_false(_controller.result_for(ChallengeCodec.challenge_id(challenge)).is_empty(),
		"and the local record is on disk regardless")
	assert_eq(_client.reports.size(), 1, "the attempt is dropped, not queued for retry")


func test_a_client_without_the_report_api_is_ignored() -> void:
	var old_client := ClientWithoutReportApi.new()
	_controller.set_community_client(old_client)
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_true(_controller._result_recorded, "the finish flow is unaffected")
	assert_false(old_client.touched, "and nothing was invented on the older client")


func test_a_detached_controller_never_builds_a_real_client() -> void:
	# Safety net for every OTHER suite: an instance outside the tree with no stub injected
	# must not reach the real community store.
	_controller.set_community_client(null)
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_null(_controller._get_community_client(),
		"a detached controller builds no community client")
	assert_true(_controller._result_recorded, "and the run still finishes")


# --- The attacker's own profile ---------------------------------------------

func test_the_attempt_is_mirrored_onto_the_attacker_profile() -> void:
	var challenge: Dictionary = _community_challenge()
	_arm(challenge)
	_take_turns(6)

	assert_eq(_profile.results.size(), 1, "one attempt, one profile record")
	var entry: Dictionary = _profile.results[0]
	assert_eq(String(entry.get("mode", "")), "challenge", "tagged as a challenge battle")
	assert_true(bool(entry.get("won", false)), "a clear is recorded as a win")
	var meta: Dictionary = entry.get("meta", {})
	assert_eq(int(meta.get("score", -1)),
		ChallengeScoring.score(true, 6, ChallengeCodec.rules_par_turns(challenge), 0),
		"the profile is paid off the same score the report carries")
	assert_true(bool(meta.get("perfect", false)), "losing no units is a perfect clear")


func test_a_failed_attempt_is_mirrored_as_a_loss() -> void:
	# Attempts on a SHARE-CODE challenge count locally too -- only the REPORT is gated on
	# the community id.
	var challenge: Dictionary = _share_code_challenge(ChallengeCodec.MODE_BREACH)
	_arm(challenge)
	_take_turns(2)
	_controller._record_result(false)

	assert_eq(_profile.results.size(), 1, "a loss is recorded on the profile too")
	assert_false(bool(_profile.results[0].get("won", true)), "as a loss")
	assert_eq(_client.reports.size(), 0, "but it is still never reported anywhere")
