extends GutTest

## DuelController (docs/design/DUEL_BATTLE.md §8.1): start() refuses a bad request with a
## returned {success:false, reason} and no engine error (rule 1), finish() reports exactly
## once, a rematch re-rolls from fresh entropy, and the strict importer refuses unknown ids
## (rule 8).


func before_each() -> void:
	DuelController.reset()
	DuelController.record_profile = false


func after_each() -> void:
	DuelController.reset()
	DuelController.record_profile = true


func test_start_rejects_bad_requests_as_values() -> void:
	var none := DuelController.start(null, false)
	assert_false(bool(none["success"]))
	assert_eq(String(none["reason"]), "no_request")
	var bad := DuelRequest.standalone(&"vineweave", &"not_a_unit")
	var res := DuelController.start(bad, false)
	assert_false(bool(res["success"]), "an unknown foe is refused")
	assert_eq(String(res["reason"]), "unknown_character")
	assert_false(DuelController.is_active(), "and nothing is staged")
	var empty := DuelRequest.new()
	assert_eq(String(DuelController.start(empty, false)["reason"]), "empty_party")


func test_start_stages_a_valid_request() -> void:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	var res := DuelController.start(req, false)
	assert_true(bool(res["success"]))
	assert_true(DuelController.is_active())
	assert_eq(DuelController.active_request(), req)


func test_finish_reports_exactly_once() -> void:
	DuelController.start(DuelRequest.standalone(&"vineweave", &"gem_knight"), false)
	watch_signals(DuelController)
	var r := DuelResult.new()
	r.outcome = DuelResult.OUTCOME_VICTORY
	r.winner_side = 0
	DuelController.finish(r)
	DuelController.finish(r)
	assert_signal_emit_count(DuelController, "duel_finished", 1, "one duel, one result")
	assert_eq(DuelController.last_result(), r)
	assert_false(DuelController.is_active())


func test_rematch_rerolls_the_same_matchup() -> void:
	var req := DuelRequest.standalone(&"vineweave", &"gem_knight")
	req.seed = 4242
	DuelController.start(req, false)
	var res := DuelController.rematch(false)
	assert_true(bool(res["success"]))
	var again := DuelController.active_request()
	assert_ne(again, req, "a fresh request")
	assert_eq(again.seed, 0, "retrying re-rolls (fresh entropy)")
	assert_eq(again.player_party[0].character_id, &"vineweave")
	assert_eq(again.foe_party[0].character_id, &"gem_knight")


func test_importer_refuses_unknown_ids() -> void:
	var d := DuelRequest.standalone(&"vineweave", &"gem_knight").to_dict()
	d["player_party"][0]["character_id"] = "../../evil"
	assert_false(bool(DuelRequest.from_dict(d)["success"]))
	var story := DuelController.launch_from_story({"party": [], "opponent": {}})
	assert_false(bool(story["success"]), "a malformed BattleRequest is refused as a value")
