class_name StorySparring
extends RefCounted

## PURE: the SPARRING PARTNER COOLDOWN (docs/design/DECISIONS.md #33, docs/STORY_MODE.md "Duels in
## story"). A friendly spar never causes permadeath (#29) but it DOES award Growth by the ordinary
## story rules (StoryGrowth: the lead that fought and won earns growth_per_win), so a partner who
## would spar forever is an endless Growth farm. Instead each partner is ready once per cooldown:
##
##   * every spar that was actually FOUGHT (won or lost -- not fled / aborted) stamps its encounter
##     id with the journey's rest and step counters ([method note_bout], called by
##     [StoryResultApplier] for every spar result);
##   * the partner is READY again once the journey has rested [member StoryRuleset.spar_cooldown_rests]
##     times and walked [member StoryRuleset.spar_cooldown_steps] steps since ([method is_ready]).
##
## Content opts in: a partner's script asks the condition [code]spar_ready("<encounter id>")[/code]
## ([ConditionContext]) and says its "catch my breath" line otherwise. A spar that never asks (a
## tournament bout, a story beat) is simply stamped and never gated.
##
## The stamps are ordinary int FLAGS ("sparred.<id>.rest" = rests + 1, "sparred.<id>.step" = steps + 1),
## so they save with the journey and need no save-format change; an old save has none (every
## partner ready).

const PREFIX := "sparred."


static func rest_key(encounter_id: String) -> String:
	return "%s%s.rest" % [PREFIX, encounter_id]


static func step_key(encounter_id: String) -> String:
	return "%s%s.step" % [PREFIX, encounter_id]


## Has this partner ever been sparred?
static func has_sparred(state: StoryState, encounter_id: String) -> bool:
	return state != null and state.get_flag_int(rest_key(encounter_id)) > 0


## Stamp a FOUGHT spar with [param encounter_id] (the rest counter is stored +1 so 0 = never).
static func note_bout(state: StoryState, encounter_id: String) -> void:
	if state == null or encounter_id.strip_edges().is_empty():
		return
	state.set_flag(rest_key(encounter_id), state.rests + 1)
	state.set_flag(step_key(encounter_id), state.steps + 1)


## Is [param encounter_id] ready to spar again under [param ruleset] (null = the shipped ruleset)?
static func is_ready(state: StoryState, encounter_id: String, ruleset: StoryRuleset = null) -> bool:
	return wait_reason(state, encounter_id, ruleset).is_empty()


## Why the partner is not ready: "rest" (rest first), "steps" (walk a while), or "" (ready).
static func wait_reason(state: StoryState, encounter_id: String, ruleset: StoryRuleset = null) -> String:
	if state == null or not has_sparred(state, encounter_id):
		return ""
	var rs: StoryRuleset = ruleset if ruleset != null else StoryRuleset.load_default()
	var rested: int = state.rests - (state.get_flag_int(rest_key(encounter_id)) - 1)
	if rested < maxi(0, rs.spar_cooldown_rests):
		return "rest"
	var walked: int = state.steps - (state.get_flag_int(step_key(encounter_id)) - 1)
	if rs.spar_cooldown_steps > 0 and walked < rs.spar_cooldown_steps:
		return "steps"
	return ""


## Did [param result] actually get FOUGHT (a win or a loss -- a flee / abort does not count)?
static func was_fought(result: BattleResult) -> bool:
	return result != null and (result.is_victory() or result.is_defeat())
