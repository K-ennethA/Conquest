extends GutTest

# The MY BASES screen: three defense slots, the retired bench, the base_limit refusal, the
# per-base ATTACK LOG (with its replay-watching flow) and the PUBLISH flow.
#
# The screen is built for real; the SERVICE is a stand-in in the shape of the pinned client
# contract (my_bases / set_base_active), injected before the node enters the tree so the real
# client -- which would seed and write user://community/ -- is never constructed.
#
# What is pinned here is what a player SEES: which base occupies which slot, that an empty
# slot invites rather than sits blank, that a base nobody has attacked says so instead of
# reading as undefeated, and that a refusal from the service (base_limit, not_owner) lands in
# the notice line as a sentence.
#
# The screen is preloaded by PATH rather than reached through its `class_name`: a brand new
# script is not in the project's global class cache until the project is next imported, and a
# suite that only runs after someone has opened the editor is a suite that does not run.
const MyBasesScript := preload("res://menus/MyBases.gd")
## The shared replay copy. Asserted against directly so a reworded sentence fails ONE place
# (this is the whole point of the file existing).
const ReplayWatch := preload("res://menus/ReplayWatch.gd")

## Stand-in for CommunityClient's base API, plus the attempt-ledger and upload endpoints the
## attack log / publish flows speak to. Every method answers SYNCHRONOUSLY, exactly as the
## offline LocalProvider does.
class StubClient extends RefCounted:
	## What my_bases returns.
	var bases: Array = []
	## What set_base_active answers with.
	var set_active_result: Dictionary = {"ok": true, "data": {}}
	## [{id, active}] in call order.
	var set_active_calls: Array = []
	## Force a failure out of my_bases.
	var load_error: String = ""
	## How many times the screen reloaded its bases. An ARRAY, not an int: a GUT lambda
	## captures by value, so a counter has to be something the closure can mutate in place.
	var my_bases_calls: Array = []

	## attempt_log: page index -> {entries, has_more}. Missing page = an empty last page.
	var log_pages: Dictionary = {}
	## Force a failure out of attempt_log.
	var log_error: String = ""
	## [{id, page}] in call order.
	var log_calls: Array = []

	## fetch_attempt_replay: the base64 blob it hands back...
	var replay_b64: String = ""
	## ...or the error it refuses with.
	var replay_error: String = ""
	## attempt ids asked for, in call order.
	var replay_calls: Array = []

	## upload: the payloads it was handed, in call order.
	var uploads: Array = []
	## What upload answers with.
	var upload_result: Dictionary = {"ok": true, "data": {}}

	func is_local() -> bool:
		return false

	func my_bases(cb: Callable) -> void:
		my_bases_calls.append(true)
		if not load_error.is_empty():
			cb.call({"ok": false, "error": load_error})
			return
		cb.call({"ok": true, "data": bases})

	func set_base_active(id: String, active: bool, cb: Callable) -> void:
		set_active_calls.append({"id": id, "active": active})
		cb.call(set_active_result)

	func attempt_log(id: String, page: int, cb: Callable) -> void:
		log_calls.append({"id": id, "page": page})
		if not log_error.is_empty():
			cb.call({"ok": false, "error": log_error})
			return
		var payload: Dictionary = log_pages.get(page, {"entries": [], "has_more": false})
		cb.call({"ok": true, "data": payload})

	func fetch_attempt_replay(attempt_id: String, cb: Callable) -> void:
		replay_calls.append(attempt_id)
		if not replay_error.is_empty():
			cb.call({"ok": false, "error": replay_error})
			return
		cb.call({"ok": true, "data": replay_b64})

	func upload(payload: Dictionary, cb: Callable) -> void:
		uploads.append(payload)
		cb.call(upload_result)


## Stand-in for the replay container codec: whatever it is told to decode to.
class StubCodec extends RefCounted:
	var log: Dictionary = {}
	## Every byte buffer it was handed, so a test can prove the blob got that far.
	var decoded: Array = []

	func decode_container(bytes: PackedByteArray) -> Dictionary:
		decoded.append(bytes)
		return log


## Stand-in for the playback launcher. THE reason no test here changes scene.
class StubPlayback extends RefCounted:
	var result: Dictionary = {"ok": true}
	## The logs it was asked to play, in call order.
	var launched: Array = []

	func launch(log: Dictionary) -> Dictionary:
		launched.append(log)
		return result


## Stand-in for the local challenge library (ChallengeCodec.list_saved's shape), so a test
## never reads or writes the player's real user://challenges/.
class StubChallenges extends RefCounted:
	var entries: Array = []

	func list_saved() -> Array:
		return entries


var screen: Control
## Named `service`, not `stub`: GutTest already owns a member called `stub` (its doubling
## helper), and shadowing it is a parse error rather than a warning.
var service: StubClient
var playback: StubPlayback
var codec: StubCodec
var challenges: StubChallenges


func _make_base(id: String, name: String, active: bool, attempts: int, clears: int) -> Dictionary:
	return {
		"id": id, "name": name, "type": CommunityProvider.TYPE_CHALLENGE, "active": active,
		"attempts": attempts, "clears": clears, "votes": 4,
	}


## One ledger entry in the pinned attempt_log shape.
func _make_attempt(id: String, cleared: bool, score: int, turns: int, at: String,
		has_replay: bool) -> Dictionary:
	return {
		"attempt_id": id, "cleared": cleared, "score": score, "turns": turns,
		"at": at, "has_replay": has_replay,
	}


## A local challenge entry in ChallengeCodec.list_saved's shape. Hand-built rather than
## produced by the codec: this suite is about the SCREEN, and a real challenge needs a
## MapResource, the character catalogue and a file on disk.
func _make_challenge(challenge_name: String, map_name: String, defenders: int) -> Dictionary:
	var spawns: Array = []
	for i in defenders:
		spawns.append({"player_id": 1, "character_id": "defender_%d" % i, "x": i, "y": 0})
	return {
		"path": "user://challenges/%s.json" % challenge_name.to_lower(),
		"challenge": {
			"format_version": 2,
			"name": challenge_name,
			"author": "Ada",
			"created": "2026-07-30T18:00:00",
			"checksum": "hash_%s" % challenge_name.to_lower(),
			"map": {
				"map_info": {"name": map_name, "author": "Ada"},
				"dimensions": {"width": 8, "height": 8},
				"layout": {"unit_spawns": spawns},
			},
			"rules": {
				"challenger_squad_size": 4, "turn_system": 0, "ai_difficulty": 1,
				"mode": "breach", "survive_turns": 10, "par_turns": 7,
			},
		},
	}


func _open() -> void:
	screen = Control.new()
	screen.set_script(MyBasesScript)
	screen.set_community_client(service)
	screen.set_replay_playback(playback)
	screen.set_replay_codec(codec)
	screen.set_challenge_source(challenges)
	add_child_autofree(screen)
	await get_tree().process_frame


func before_each() -> void:
	service = StubClient.new()
	playback = StubPlayback.new()
	codec = StubCodec.new()
	challenges = StubChallenges.new()


func after_each() -> void:
	screen = null
	service = null
	playback = null
	codec = null
	challenges = null


# --- the three slots ---------------------------------------------------------

func test_three_active_bases_fill_the_three_slots():
	service.bases = [
		_make_base("b1", "Thornhold", true, 42, 12),
		_make_base("b2", "Ashfall", true, 8, 8),
		_make_base("b3", "Quiet Fen", true, 5, 0),
	]

	await _open()

	assert_true(screen.slot_text(0).contains("Thornhold"), "the first base holds slot 1")
	assert_true(screen.slot_text(1).contains("Ashfall"), "the second holds slot 2")
	assert_true(screen.slot_text(2).contains("Quiet Fen"), "the third holds slot 3")
	assert_eq(screen.bench_titles().size(), 0, "with nothing left on the bench")

func test_a_filled_slot_shows_attacks_defends_and_the_derived_rate():
	service.bases = [_make_base("b1", "Thornhold", true, 42, 12)]

	await _open()

	var text: String = screen.slot_text(0)
	assert_true(text.contains("Attacked 42 times"), "the slot shows how many players attacked")
	assert_true(text.contains("Defended 30"), "how many it turned away (42 - 12)")
	assert_true(text.contains("Defense rate 71%"), "and the rate derived from the two counters")

func test_a_base_nobody_has_attacked_says_so_rather_than_reading_undefeated():
	service.bases = [_make_base("b1", "Fresh Fort", true, 0, 0)]

	await _open()

	var text: String = screen.slot_text(0)
	assert_true(text.contains("Not attacked yet"), "zero attempts is stated in words")
	assert_false(text.contains("100%"), "never as a perfect defense rate it has not earned")
	assert_false(text.contains("Defense rate"), "and no rate line is printed at all")

func test_unclaimed_slots_invite_a_publish():
	service.bases = [_make_base("b1", "Thornhold", true, 3, 1)]

	await _open()

	assert_true(screen.slot_text(0).contains("Thornhold"), "the one active base takes slot 1")
	assert_true(screen.slot_text(1).contains(MyBasesScript.EMPTY_SLOT_INVITE),
		"slot 2 asks to be filled instead of sitting blank")
	assert_true(screen.slot_text(2).contains(MyBasesScript.EMPTY_SLOT_INVITE), "and so does slot 3")

func test_a_player_with_nothing_published_sees_three_invitations():
	service.bases = []

	await _open()

	for i in MyBasesScript.MAX_SLOTS:
		assert_true(screen.slot_text(i).contains(MyBasesScript.EMPTY_SLOT_INVITE),
			"slot %d invites a first publish" % (i + 1))

# --- the bench ---------------------------------------------------------------

func test_retired_bases_are_listed_below_the_slots():
	service.bases = [
		_make_base("b1", "Thornhold", true, 42, 12),
		_make_base("b2", "Old Redoubt", false, 20, 19),
		_make_base("b3", "Cellar Door", false, 0, 0),
	]

	await _open()

	var bench: PackedStringArray = screen.bench_titles()
	assert_eq(bench.size(), 2, "both retired bases are on the bench")
	assert_eq(bench[0], "Old Redoubt", "in the order the service returned them")
	assert_eq(bench[1], "Cellar Door", "including one nobody ever attacked")

func test_a_retired_base_can_be_fielded_while_a_slot_is_free():
	service.bases = [
		_make_base("b1", "Thornhold", true, 4, 1),
		_make_base("b2", "Old Redoubt", false, 20, 19),
	]

	await _open()

	assert_eq(screen.bench_action_text(0), "Reactivate", "the bench offers to field it again")
	assert_true(screen.bench_action_enabled(0), "which is allowed while two slots stand empty")

func test_reactivate_is_closed_off_while_all_three_slots_are_full():
	service.bases = [
		_make_base("b1", "Thornhold", true, 4, 1),
		_make_base("b2", "Ashfall", true, 4, 1),
		_make_base("b3", "Quiet Fen", true, 4, 1),
		_make_base("b4", "Old Redoubt", false, 20, 19),
	]

	await _open()

	assert_false(screen.bench_action_enabled(0),
		"a fourth base cannot be fielded until one of the three is retired")

func test_reactivating_asks_the_service_to_field_that_base():
	service.bases = [_make_base("b2", "Old Redoubt", false, 20, 19)]

	await _open()
	screen._set_active("b2", true)
	await get_tree().process_frame   # let the repaint's queue_free()d cards actually go

	assert_eq(service.set_active_calls.size(), 1, "one call went out")
	assert_eq(str(service.set_active_calls[0]["id"]), "b2", "naming the base")
	assert_true(bool(service.set_active_calls[0]["active"]), "and asking for it to be active")

func test_an_overflow_active_base_lands_on_the_bench_with_a_retire_action():
	# The service should never report a 4th active base. If it does, the player must still be
	# able to see and retire it -- dropping it would leave a slot they cannot reclaim.
	service.bases = [
		_make_base("b1", "Thornhold", true, 1, 0),
		_make_base("b2", "Ashfall", true, 1, 0),
		_make_base("b3", "Quiet Fen", true, 1, 0),
		_make_base("b4", "Ghost Slot", true, 1, 0),
	]

	await _open()

	assert_eq(screen.bench_titles()[0], "Ghost Slot", "the overflow base is still shown")
	assert_eq(screen.bench_action_text(0), "Retire", "with the action that resolves it")
	assert_true(screen.bench_action_enabled(0), "and that action is available")

# --- refusals ----------------------------------------------------------------

func test_the_base_limit_refusal_is_an_inline_sentence_not_a_crash():
	service.bases = [_make_base("b2", "Old Redoubt", false, 20, 19)]
	service.set_active_result = {"ok": false, "error": "base_limit"}

	await _open()
	screen._set_active("b2", true)
	await get_tree().process_frame   # let the repaint's queue_free()d cards actually go

	var notice: String = screen.notice_text()
	assert_true(notice.contains("3 bases"), "the notice states the actual rule")
	assert_true(notice.contains("Retire"), "and what to do about it")
	assert_eq(screen.bench_titles().size(), 1,
		"the screen reloaded and is still standing after the refusal")

func test_a_base_that_is_not_yours_is_refused_in_plain_words():
	service.bases = [_make_base("b2", "Someone Elses", false, 1, 0)]
	service.set_active_result = {"ok": false, "error": "not_owner"}

	await _open()
	screen._set_active("b2", true)
	await get_tree().process_frame   # let the repaint's queue_free()d cards actually go

	assert_eq(screen.notice_text(), "That base is not yours to change.",
		"not_owner reads as a sentence, never as a raw error code")

func test_an_unknown_refusal_still_reports_something_useful():
	assert_eq(MyBasesScript.notice_for_error("teapot"), "That base could not be updated: teapot",
		"an unrecognised code is surfaced rather than swallowed")
	assert_eq(MyBasesScript.notice_for_error(""), "That base could not be updated.",
		"and a refusal with no reason still says that it failed")

func test_a_failed_load_reports_instead_of_rendering_a_lie():
	service.load_error = "offline"

	await _open()

	assert_true(screen.notice_text().contains("offline"), "the load failure is reported")
	assert_true(screen.slot_text(0).contains(MyBasesScript.EMPTY_SLOT_INVITE),
		"and the slots fall back to empty rather than showing stale bases")

func test_a_client_without_the_base_api_degrades_to_a_message():
	# A build whose client predates the base endpoints must not take the screen down.
	screen = Control.new()
	screen.set_script(MyBasesScript)
	screen.set_community_client(RefCounted.new())
	add_child_autofree(screen)
	await get_tree().process_frame

	assert_true(screen.notice_text().contains("not available"),
		"a client with no my_bases says so instead of erroring")
	assert_eq(screen.bench_titles().size(), 0, "and renders an empty, honest screen")


# =============================================================================
# ATTACK LOG
# =============================================================================
# The defender's half of the ledger: who attacked this base, how it went, and -- when the
# attempt kept one -- the replay. The panel is an OVERLAY, so every assertion here is on the
# overlay's own read-backs (overlay_mode / attack_log_rows / overlay_notice), never on the
# page's notice line.

func test_the_attack_log_lists_every_attempt_with_its_result_score_turns_and_time():
	service.bases = [_make_base("b1", "Thornhold", true, 2, 1)]
	service.log_pages = {0: {"entries": [
		_make_attempt("a1", true, 1450, 9, "2026-08-01T12:03:11", true),
		_make_attempt("a2", false, 300, 14, "2026-07-31T08:00:00", false),
	], "has_more": false}}

	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_ATTACK_LOG, "the log panel is open")
	assert_eq(screen.overlay_title(), "Thornhold", "naming the base it belongs to")
	var rows: PackedStringArray = screen.attack_log_rows()
	assert_eq(rows.size(), 2, "both attempts are listed")
	assert_true(rows[0].contains("1450 pts"), "the attacker's score is shown")
	assert_true(rows[0].contains("9 turns"), "and how long they took")
	assert_true(rows[0].contains("2026-08-01 12:03:11"), "and when it happened, readably")

func test_an_attempt_reads_from_the_defenders_side_not_the_attackers():
	service.bases = [_make_base("b1", "Thornhold", true, 2, 1)]
	service.log_pages = {0: {"entries": [
		_make_attempt("a1", true, 10, 9, "2026-08-01T12:00:00", false),
		_make_attempt("a2", false, 10, 9, "2026-08-01T11:00:00", false),
	], "has_more": false}}

	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame

	var rows: PackedStringArray = screen.attack_log_rows()
	assert_true(rows[0].begins_with(MyBasesScript.RESULT_CLEARED),
		"an attempt the attacker CLEARED is a loss for this base, and says so")
	assert_true(rows[1].begins_with(MyBasesScript.RESULT_DEFENDED),
		"and one they failed is a DEFENDED")

func test_watch_is_offered_only_for_the_attempts_that_kept_a_replay():
	service.bases = [_make_base("b1", "Thornhold", true, 2, 1)]
	service.log_pages = {0: {"entries": [
		_make_attempt("a1", true, 10, 9, "2026-08-01T12:00:00", true),
		_make_attempt("a2", false, 10, 9, "2026-08-01T11:00:00", false),
	], "has_more": false}}

	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame

	assert_true(screen.attack_log_watch_enabled(0), "the attempt with a replay can be watched")
	assert_false(screen.attack_log_watch_enabled(1),
		"the one without keeps a dead button rather than promising a replay it has not got")

func test_the_attack_log_pages_and_appends_rather_than_replacing():
	service.bases = [_make_base("b1", "Thornhold", true, 3, 1)]
	service.log_pages = {
		0: {"entries": [_make_attempt("a1", true, 10, 9, "2026-08-03T12:00:00", false)],
			"has_more": true},
		1: {"entries": [_make_attempt("a2", false, 20, 8, "2026-08-02T12:00:00", false)],
			"has_more": false},
	}

	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame
	assert_eq(screen.attack_log_rows().size(), 1, "page 0 lands first")
	assert_true(screen.attack_log_has_more(), "and the service says there is more")

	screen.attack_log_load_more()
	await get_tree().process_frame

	assert_eq(screen.attack_log_rows().size(), 2, "page 1 is APPENDED, not swapped in")
	assert_false(screen.attack_log_has_more(), "and the last page ends the list")
	assert_eq(service.log_calls.size(), 2, "exactly one request per page")
	assert_eq(int(service.log_calls[1]["page"]), 1, "asking for the next one by index")

func test_a_base_nobody_has_attacked_says_so_instead_of_showing_a_blank_panel():
	service.bases = [_make_base("b1", "Fresh Fort", true, 0, 0)]
	service.log_pages = {0: {"entries": [], "has_more": false}}

	await _open()
	screen.open_attack_log("b1", "Fresh Fort")
	await get_tree().process_frame

	assert_eq(screen.attack_log_rows().size(), 0, "no rows are invented")
	assert_eq(screen.overlay_notice(), "", "and nothing is reported as an error")

func test_an_attack_log_that_is_not_yours_is_refused_in_plain_words():
	service.bases = [_make_base("b1", "Someone Elses", true, 1, 0)]
	service.log_error = "not_owner"

	await _open()
	screen.open_attack_log("b1", "Someone Elses")
	await get_tree().process_frame

	assert_true(screen.overlay_notice().contains("not yours"),
		"not_owner reads as a sentence, never as a raw error code")
	assert_eq(screen.attack_log_rows().size(), 0, "and no rows are rendered")

func test_a_client_without_the_ledger_endpoints_says_so_rather_than_erroring():
	# A build whose client predates attempt_log must not take the panel down.
	service.bases = [_make_base("b1", "Thornhold", true, 1, 0)]
	await _open()
	screen.set_community_client(RefCounted.new())
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame

	assert_eq(screen.overlay_notice(), ReplayWatch.LOG_UNAVAILABLE,
		"the missing endpoint is stated once, from the shared copy")

func test_closing_the_panel_hands_the_page_back():
	service.bases = [_make_base("b1", "Thornhold", true, 1, 0)]
	service.log_pages = {0: {"entries": [], "has_more": false}}

	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame
	screen.close_overlay()
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_NONE, "no panel is open")
	assert_eq(screen.attack_log_rows().size(), 0, "and its rows are gone with it")


# =============================================================================
# WATCHING AN ATTACK
# =============================================================================
# fetch -> base64 -> container -> playback. Playback is a STAND-IN, so "watching" returns a
# result here and never changes scene.

## A blob that is structurally valid base64 (its contents do not matter -- the codec is a
## stand-in that answers with whatever the test set).
func _some_b64() -> String:
	return Marshalls.raw_to_base64("pretend-this-is-a-replay".to_utf8_buffer())


func _open_log_with_one_watchable_attempt() -> void:
	service.bases = [_make_base("b1", "Thornhold", true, 1, 1)]
	service.log_pages = {0: {"entries": [
		_make_attempt("a1", true, 1450, 9, "2026-08-01T12:00:00", true),
	], "has_more": false}}
	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame


func test_watching_an_attack_reaches_playback_and_dismisses_the_panel():
	service.replay_b64 = _some_b64()
	codec.log = {"format_version": 1, "mode": "challenge", "entries": []}
	playback.result = {"ok": true}
	await _open_log_with_one_watchable_attempt()

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(service.replay_calls.size(), 1, "one replay was fetched")
	assert_eq(String(service.replay_calls[0]), "a1", "the one belonging to that attempt")
	assert_eq(playback.launched.size(), 1, "and the decoded log reached playback")
	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_NONE,
		"a launched replay takes the panel down with it")

func test_a_blob_that_is_not_base64_reports_replay_unavailable():
	# Marshalls.base64_to_raw logs an ENGINE ERROR on malformed input, so the shape is
	# checked first -- this test is also the proof that the decoder is never reached.
	service.replay_b64 = "this is definitely not base64!!"
	await _open_log_with_one_watchable_attempt()

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(screen.overlay_notice(), ReplayWatch.UNAVAILABLE,
		"a blob that cannot be decoded says so, in the shared wording")
	assert_eq(codec.decoded.size(), 0, "and nothing was handed to the container codec")
	assert_eq(playback.launched.size(), 0, "let alone to playback")

func test_a_container_that_decodes_to_nothing_reports_replay_unavailable():
	service.replay_b64 = _some_b64()
	codec.log = {}   # the hardened reader's one failure value
	await _open_log_with_one_watchable_attempt()

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(codec.decoded.size(), 1, "the blob DID reach the codec this time")
	assert_eq(screen.overlay_notice(), ReplayWatch.UNAVAILABLE,
		"and its rejection is the same sentence, not a crash")
	assert_eq(playback.launched.size(), 0, "nothing empty is handed to playback")

func test_a_replay_recorded_on_another_build_says_so_instead_of_crashing():
	service.replay_b64 = _some_b64()
	codec.log = {"format_version": 1, "entries": []}
	playback.result = {"ok": false, "error": "version_mismatch"}
	await _open_log_with_one_watchable_attempt()

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(screen.overlay_notice(), ReplayWatch.VERSION_MISMATCH,
		"the launcher's refusal becomes the one shared version-mismatch sentence")
	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_ATTACK_LOG,
		"and the panel stays up so the player can pick another attempt")

func test_a_replay_the_service_no_longer_holds_is_refused_in_plain_words():
	service.replay_error = "not_found"
	await _open_log_with_one_watchable_attempt()

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(screen.overlay_notice(), ReplayWatch.NOT_FOUND,
		"not_found reads as a sentence, never as a raw error code")

func test_an_attempt_that_kept_no_replay_cannot_be_watched_even_by_hand():
	service.bases = [_make_base("b1", "Thornhold", true, 1, 0)]
	service.log_pages = {0: {"entries": [
		_make_attempt("a1", false, 10, 9, "2026-08-01T12:00:00", false),
	], "has_more": false}}
	await _open()
	screen.open_attack_log("b1", "Thornhold")
	await get_tree().process_frame

	screen.attack_log_watch(0)
	await get_tree().process_frame

	assert_eq(service.replay_calls.size(), 0, "no request goes out for a replay that is not there")
	assert_eq(screen.overlay_notice(), ReplayWatch.NOT_FOUND, "and the panel says why")


# =============================================================================
# PUBLISH
# =============================================================================
# The empty slot's flow, and the game's ONLY caller of CommunityClient.upload.

func test_the_publish_picker_lists_the_players_local_challenges_with_their_map():
	challenges.entries = [
		_make_challenge("Thornhold", "Bramble Hollow", 4),
		_make_challenge("Ashfall", "Cinder Flats", 2),
	]

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_PUBLISH, "the picker is open")
	var rows: PackedStringArray = screen.publish_rows()
	assert_eq(rows.size(), 2, "both authored challenges are offered")
	assert_true(rows[0].contains("Thornhold"), "named by the challenge")
	assert_true(rows[0].contains("4 defenders"), "with the defense the attacker will face")
	assert_true(rows[1].contains("Ashfall"), "and the second is there too")

func test_a_player_with_nothing_authored_is_pointed_at_the_builder():
	challenges.entries = []

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_PUBLISH,
		"the picker still opens rather than doing nothing")
	assert_eq(screen.publish_rows().size(), 0, "with no rows to pick")

func test_picking_a_challenge_asks_before_it_publishes():
	challenges.entries = [_make_challenge("Thornhold", "Bramble Hollow", 4)]

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_CONFIRM,
		"a confirm sheet stands between the pick and the upload")
	assert_eq(service.uploads.size(), 0, "and nothing has been sent yet")

func test_publishing_sends_the_authored_challenge_itself_as_the_payload():
	var entry: Dictionary = _make_challenge("Thornhold", "Bramble Hollow", 4)
	# A challenge that was DOWNLOADED carries our own bookkeeping key. It is client-side
	# metadata about someone else's item, not part of what the author wrote.
	(entry["challenge"] as Dictionary)["community_id"] = "challenge_someone_else"
	challenges.entries = [entry]
	service.upload_result = {"ok": true, "data": {"name": "Thornhold", "active": true}}

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	screen.publish_confirm()
	await get_tree().process_frame

	assert_eq(service.uploads.size(), 1, "exactly one upload went out")
	var payload: Dictionary = service.uploads[0]
	assert_eq(String(payload.get("name", "")), "Thornhold", "the payload IS the challenge dict")
	assert_true(payload.has("map"), "carrying its map")
	assert_true(payload.has("rules"), "and its rules")
	assert_eq(int(payload.get("format_version", 0)), 2, "in the codec's own format")
	assert_false(payload.has("community_id"),
		"but never our client-side service id, which the service is about to assign itself")

func test_a_successful_publish_reloads_the_slots_from_the_service():
	challenges.entries = [_make_challenge("Thornhold", "Bramble Hollow", 4)]
	service.upload_result = {"ok": true, "data": {"name": "Thornhold", "active": true}}

	await _open()
	assert_eq(service.my_bases_calls.size(), 1, "the screen loaded once on open")

	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	screen.publish_confirm()
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_NONE, "the panel closes on success")
	assert_eq(service.my_bases_calls.size(), 2,
		"and the slots are re-read, because where an upload LANDS is the service's call")
	assert_true(screen.notice_text().contains("Thornhold"), "the page confirms what was published")

func test_publishing_past_the_slot_cap_says_where_the_base_actually_landed():
	# The provider's documented invariant: a 4th upload is ACCEPTED but lands retired.
	challenges.entries = [_make_challenge("Thornhold", "Bramble Hollow", 4)]
	service.upload_result = {"ok": true, "data": {"name": "Thornhold", "active": false}}

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	screen.publish_confirm()
	await get_tree().process_frame

	assert_true(screen.notice_text().contains("bench"),
		"an accepted-but-retired upload is reported as waiting, never as active")

func test_a_duplicate_publish_is_an_inline_sentence_and_the_sheet_stays_up():
	challenges.entries = [_make_challenge("Thornhold", "Bramble Hollow", 4)]
	# The offline sandbox's prose; the live service's code is matched by the same helper.
	service.upload_result = {"ok": false, "error": "Item already exists."}

	await _open()
	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	screen.publish_confirm()
	await get_tree().process_frame

	assert_eq(screen.overlay_mode(), MyBasesScript.OVERLAY_CONFIRM,
		"a refusal leaves the sheet up rather than dropping the player somewhere else")
	assert_true(screen.overlay_notice().contains("already published"),
		"and the duplicate is explained in words")
	assert_eq(service.my_bases_calls.size(), 1, "nothing was reloaded, because nothing changed")

func test_a_client_without_upload_degrades_to_a_message():
	challenges.entries = [_make_challenge("Thornhold", "Bramble Hollow", 4)]

	await _open()
	screen.set_community_client(RefCounted.new())
	screen.open_publish_picker()
	await get_tree().process_frame
	screen.publish_select(0)
	screen.publish_confirm()
	await get_tree().process_frame

	assert_true(screen.overlay_notice().contains("not available"),
		"a client with no upload says so instead of erroring")


# =============================================================================
# THE SHARED COPY (pure; no screen in the tree)
# =============================================================================

func test_version_mismatch_and_divergence_have_exactly_one_source():
	assert_eq(ReplayWatch.playback_notice("version_mismatch"), ReplayWatch.VERSION_MISMATCH,
		"the launcher's version refusal maps to the one version-mismatch sentence")
	assert_eq(ReplayWatch.playback_notice("diverged"), ReplayWatch.DIVERGED,
		"and a divergence to the one divergence sentence")
	assert_eq(ReplayWatch.playback_notice("checksum_mismatch"), ReplayWatch.DIVERGED,
		"under either name the contract might use")
	assert_true(ReplayWatch.playback_notice("teapot").contains("teapot"),
		"an unrecognised refusal is surfaced rather than swallowed")

func test_a_malformed_base64_blob_is_rejected_before_the_decoder_sees_it():
	assert_false(ReplayWatch.is_base64("not base64!!"), "spaces and punctuation are refused")
	assert_false(ReplayWatch.is_base64("QUJ"), "a truncated quantum is refused")
	assert_false(ReplayWatch.is_base64("Q==="), "and so is over-padding")
	assert_false(ReplayWatch.is_base64(""), "and so is nothing at all")
	assert_true(ReplayWatch.is_base64(Marshalls.raw_to_base64("abc".to_utf8_buffer())),
		"while what the engine itself encodes is accepted, padding and all")

func test_an_attempt_time_reads_as_a_date_whichever_way_the_service_sends_it():
	assert_eq(MyBasesScript.format_when("2026-08-01T12:03:11"), "2026-08-01 12:03:11",
		"an ISO stamp loses its machine-readable T")
	assert_eq(MyBasesScript.format_when(""), "unknown",
		"and a missing time says so rather than printing an epoch")
	assert_eq(MyBasesScript.format_when(0), "unknown", "including a zero unix stamp")
