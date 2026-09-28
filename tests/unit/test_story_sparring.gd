extends GutTest

## DUELS IN STORY, pure pieces (docs/design/DECISIONS.md #33; docs/STORY_MODE.md "Duels in story"):
##   * the SPARRING PARTNER cooldown (StorySparring + the spar_ready() condition): a partner
##     sparred once is ready again only after the ruleset's rests / steps; a flee or an abort
##     never starts the cooldown; StoryResultApplier stamps every fought spar, never a real battle;
##   * REMATCH SCALING on a BattleSpec (scale_flag / scale_step / scale_max_steps), applied by a
##     script's StartBattle / StartDuel;
##   * BattleSpec validation: a duel opponent must be duel-eligible.


class FakeSession extends RefCounted:
	var requests: Array = []

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		return BattleResult.make(request.encounter_id, BattleResult.OUTCOME_VICTORY)


const PARTNER := "crownhaven.spar.test"


func _state() -> StoryState:
	var s := StoryState.new()
	s.add_member("vineweave")
	return s


func _rules(rests: int = 1, steps: int = 0) -> StoryRuleset:
	var rs := StoryRuleset.new()
	rs.spar_cooldown_rests = rests
	rs.spar_cooldown_steps = steps
	return rs


func _spar_request(id: String = PARTNER) -> BattleRequest:
	var r := BattleRequest.new()
	r.kind = BattleRequest.KIND_DUEL
	r.encounter_id = id
	r.source = BattleRequest.SOURCE_SCRIPT
	r.rules = {"spar": true, "defeat_policy": "continue"}
	r.party = [{"member_id": "vineweave", "character_id": "vineweave"}]
	return r


func _result(outcome: String, id: String = PARTNER) -> BattleResult:
	var r := BattleResult.make(id, outcome)
	r.party_after = [{"member_id": "vineweave", "current_hp": 20, "wounded": false}]
	return r


# --- The cooldown ------------------------------------------------------------------------

func test_a_partner_never_sparred_is_ready() -> void:
	var s := _state()
	assert_true(StorySparring.is_ready(s, PARTNER, _rules()), "ready before the first bout")
	assert_false(StorySparring.has_sparred(s, PARTNER), "and never sparred")


func test_a_bout_waits_for_a_rest() -> void:
	var s := _state()
	var rs := _rules(1)
	StorySparring.note_bout(s, PARTNER)
	assert_false(StorySparring.is_ready(s, PARTNER, rs), "tired right after a bout")
	assert_eq(StorySparring.wait_reason(s, PARTNER, rs), "rest", "because you have not rested")
	s.steps += 500
	assert_false(StorySparring.is_ready(s, PARTNER, rs), "walking alone does not refresh a partner")
	s.heal_party()
	assert_true(StorySparring.is_ready(s, PARTNER, rs), "one rest later: ready again")
	assert_true(StorySparring.is_ready(s, "crownhaven.spar.other", rs), "other partners were never affected")


func test_the_step_knob_and_a_zero_cooldown() -> void:
	var s := _state()
	StorySparring.note_bout(s, PARTNER)
	var walk := _rules(0, 50)
	assert_eq(StorySparring.wait_reason(s, PARTNER, walk), "steps", "rests 0 / steps 50: walk first")
	s.steps += 49
	assert_false(StorySparring.is_ready(s, PARTNER, walk), "49 steps is not enough")
	s.steps += 1
	assert_true(StorySparring.is_ready(s, PARTNER, walk), "50 steps is")
	assert_true(StorySparring.is_ready(s, PARTNER, _rules(0, 0)), "a zero cooldown: always ready")


func test_the_condition_vocabulary_reads_the_cooldown() -> void:
	var s := _state()
	var cond := "spar_ready(\"%s\")" % PARTNER
	assert_true(bool(ConditionContext.check(cond)["valid"]), "spar_ready() parses and dry-runs")
	assert_true(ConditionContext.evaluate(cond, s), "true before any bout")
	StorySparring.note_bout(s, PARTNER)
	# The shipped ruleset (one rest).
	assert_false(ConditionContext.evaluate(cond, s), "false after a bout")
	s.heal_party()
	assert_true(ConditionContext.evaluate(cond, s), "true again after a rest")


func test_the_applier_stamps_fought_spars_only() -> void:
	var rs := _rules(1)
	var s := _state()
	StoryResultApplier.apply(s, _spar_request(), _result(BattleResult.OUTCOME_FLED), rs)
	assert_false(StorySparring.has_sparred(s, PARTNER), "a fled spar is no bout")
	StoryResultApplier.apply(s, _spar_request(), _result(BattleResult.OUTCOME_ABORTED), rs)
	assert_false(StorySparring.has_sparred(s, PARTNER), "nor is an aborted one")
	StoryResultApplier.apply(s, _spar_request(), _result(BattleResult.OUTCOME_DEFEAT), rs)
	assert_true(StorySparring.has_sparred(s, PARTNER), "a LOST spar was fought: the cooldown starts")
	assert_false(StorySparring.is_ready(s, PARTNER, rs), "and the partner is tired")
	var t := _state()
	var real := _spar_request("trainer.mossway.fenna")
	real.rules["spar"] = false
	StoryResultApplier.apply(t, real, _result(BattleResult.OUTCOME_VICTORY, "trainer.mossway.fenna"), rs)
	assert_false(StorySparring.has_sparred(t, "trainer.mossway.fenna"), "a real battle is never stamped")


# --- Rematch scaling ------------------------------------------------------------------------

func _scaled_spec() -> BattleSpec:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	spec.encounter_id = "rival.test"
	var team: Array[Dictionary] = [{"character_id": "blightcap", "strength": 0.9}]
	spec.opponent_team = team
	spec.scale_flag = "rival.stage"
	spec.scale_step = 0.1
	spec.scale_max_steps = 3
	return spec


func test_scaling_grows_with_the_flag_up_to_the_cap() -> void:
	var spec := _scaled_spec()
	var s := _state()
	assert_almost_eq(spec.scale_factor(s), 1.0, 0.0001, "stage 0: unscaled")
	s.set_flag("rival.stage", 2)
	assert_almost_eq(spec.scale_factor(s), 1.2, 0.0001, "stage 2: +20%")
	var req: BattleRequest = spec.to_request(BattleRequest.SOURCE_SCRIPT)
	spec.apply_scaling(req, s)
	assert_almost_eq(float(req.opponent["team"][0]["strength"]), 1.08, 0.0001, "0.9 x 1.2 on the request")
	assert_almost_eq(float(spec.opponent_team[0]["strength"]), 0.9, 0.0001, "the authored spec is untouched (rule 7)")
	s.set_flag("rival.stage", 99)
	assert_almost_eq(spec.scale_factor(s), 1.3, 0.0001, "capped at scale_max_steps")
	assert_almost_eq(spec.lead_strength(s), 1.17, 0.0001, "what a ladder shows")
	var plain := BattleSpec.new()
	assert_almost_eq(plain.scale_factor(s), 1.0, 0.0001, "no scale_flag: never scaled")


func test_a_script_duel_applies_the_scaling() -> void:
	var s := _state()
	s.set_flag("rival.stage", 1)
	var cmd := StartDuelCommand.new()
	cmd.spec = _scaled_spec()
	var session := FakeSession.new()
	var ctx := ScriptContext.new(s, StoryScriptHost.new(), session, "crownhaven")
	await StoryScriptRunner.new().run([cmd], ctx)
	assert_eq(session.requests.size(), 1, "the duel ran through the session")
	var req: BattleRequest = session.requests[0]
	assert_true(req.is_duel(), "as a duel")
	assert_almost_eq(float(req.opponent["team"][0]["strength"]), 0.99, 0.0001, "0.9 x 1.1 at stage 1")


# --- Validation --------------------------------------------------------------------------

func test_a_duel_opponent_must_be_duel_eligible() -> void:
	var spec := BattleSpec.new()
	spec.kind = BattleSpec.Kind.DUEL
	var team: Array[Dictionary] = [{"character_id": "bastion", "strength": 1.0}]
	spec.opponent_team = team
	var issues: Array[String] = []
	spec.validate(issues)
	assert_eq(issues.size(), 1, "one issue")
	if issues.size() == 1:
		assert_true(issues[0].contains("not duel-eligible"), "Bastion has no offensive duel move (%s)" % issues[0])
	var ok := _scaled_spec()
	var none: Array[String] = []
	ok.validate(none)
	assert_eq(none, [] as Array[String], "an eligible, properly scaled duel validates clean")
	ok.scale_step = 0.0
	var bad: Array[String] = []
	ok.validate(bad)
	assert_eq(bad.size(), 1, "a scale flag without a step is flagged")
