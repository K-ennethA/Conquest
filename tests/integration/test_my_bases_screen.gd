extends GutTest

# The MY BASES screen: three defense slots, the retired bench, and the base_limit refusal.
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

## Stand-in for CommunityClient's base API.
class StubClient extends RefCounted:
	## What my_bases returns.
	var bases: Array = []
	## What set_base_active answers with.
	var set_active_result: Dictionary = {"ok": true, "data": {}}
	## [{id, active}] in call order.
	var set_active_calls: Array = []
	## Force a failure out of my_bases.
	var load_error: String = ""

	func is_local() -> bool:
		return false

	func my_bases(cb: Callable) -> void:
		if not load_error.is_empty():
			cb.call({"ok": false, "error": load_error})
			return
		cb.call({"ok": true, "data": bases})

	func set_base_active(id: String, active: bool, cb: Callable) -> void:
		set_active_calls.append({"id": id, "active": active})
		cb.call(set_active_result)


var screen: Control
## Named `service`, not `stub`: GutTest already owns a member called `stub` (its doubling
## helper), and shadowing it is a parse error rather than a warning.
var service: StubClient


func _make_base(id: String, name: String, active: bool, attempts: int, clears: int) -> Dictionary:
	return {
		"id": id, "name": name, "type": CommunityProvider.TYPE_CHALLENGE, "active": active,
		"attempts": attempts, "clears": clears, "votes": 4,
	}


func _open() -> void:
	screen = Control.new()
	screen.set_script(MyBasesScript)
	screen.set_community_client(service)
	add_child_autofree(screen)
	await get_tree().process_frame


func before_each() -> void:
	service = StubClient.new()


func after_each() -> void:
	screen = null
	service = null


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
