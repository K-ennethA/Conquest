class_name ConditionContext
extends RefCounted

## THE RESTRICTED PROXY a story condition string is evaluated against (docs/design/OVERWORLD.md
## §4.2). A condition is a Godot [Expression] run with THIS object as its base instance, so the
## only names it can call are the methods below:
##
##   flag("quest.blight_road") >= 1 and not has("oakvale.guard.moved")
##   party_has("petalfang") or item("sagebloom_poultice") > 0
##   outcome() == "victory"
##   spar_ready("crownhaven.spar.rowan")   (legacy id: the General's spar)
##   after('opening.attack') and rests_since('opening.complete') >= 3   (story time: flag_times)
##
## Zero parser to write, and [method check] lets a content test parse + dry-run every condition
## in every area so a typo fails CI, not a playtest. Story content is SHIPPED, trusted data; if
## it ever becomes player-shareable, CONQUEST.md rule 8 applies and this must become a
## whitelisted mini-grammar.
##
## Failures are values: an unparsable / failing condition evaluates FALSE and never logs
## (CONQUEST.md rule 1) -- Expression.execute is called with show_error = false.

var _state: StoryState = null
var _last_result = null


func _init(state: StoryState = null, last_result = null) -> void:
	_state = state if state != null else StoryState.new()
	_last_result = last_result


# --- The condition vocabulary (callable from condition strings) -----------------

func flag(key: String) -> int:
	return _state.get_flag_int(key)


func has(key: String) -> bool:
	return _state.has_flag(key)


## Readable aliases for dialogue conditions: after('opening.attack') == has(...), before(...) its
## negation -- the story-phase words the dialogue editor shows.
func after(key: String) -> bool:
	return _state.has_flag(key)


func before(key: String) -> bool:
	return not _state.has_flag(key)


# --- Story TIME (StoryState.flag_times): "N rests / steps / minutes since a flag was set" -------
# Each is -1 while the flag is unset, so rests_since('x') >= 2 is false until x happens.

func rests_since(key: String) -> int:
	return _state.rests_since(key)


func steps_since(key: String) -> int:
	return _state.steps_since(key)


func minutes_since(key: String) -> int:
	return _state.minutes_since(key)


## The journey's clocks: rests taken (Wayshrine / healer / whiteout), steps walked, minutes played.
func rests() -> int:
	return _state.rests


func steps() -> int:
	return _state.steps


func play_minutes() -> int:
	return int(_state.play_seconds) / 60


func party_has(character_id: String) -> bool:
	return _state.party_has(character_id)


func item(item_id: String) -> int:
	return _state.item_count(item_id)


func gold() -> int:
	return _state.gold


func visited(area_id: String) -> bool:
	return _state.visited_areas.has(area_id)


## Is the sparring partner [param encounter_id] ready for another bout ([StorySparring]: rested
## since the last one)? True for a partner never sparred.
func spar_ready(encounter_id: String) -> bool:
	return StorySparring.is_ready(_state, encounter_id)


## The outcome of the last battle a script ran ("victory", "defeat", "fled", "befriended",
## "aborted"), or "" before any.
func outcome() -> String:
	if _last_result == null:
		return ""
	return String(_last_result.outcome)


# --- Evaluation ---------------------------------------------------------------------

## Evaluate [param condition] against [param state]. Blank = true (no gate). Unparsable or
## failing = false.
static func evaluate(condition: String, state: StoryState, last_result = null) -> bool:
	var text: String = condition.strip_edges()
	if text.is_empty():
		return true
	var expr := Expression.new()
	if expr.parse(text) != OK:
		return false
	var ctx := ConditionContext.new(state, last_result)
	var value = expr.execute([], ctx, false)
	if expr.has_execute_failed():
		return false
	return bool(value)


## Content validation: does [param condition] parse AND run against a blank state? Returns
## {valid, error}. Blank is valid.
static func check(condition: String) -> Dictionary:
	var text: String = condition.strip_edges()
	if text.is_empty():
		return {"valid": true, "error": ""}
	var expr := Expression.new()
	if expr.parse(text) != OK:
		return {"valid": false, "error": expr.get_error_text()}
	expr.execute([], ConditionContext.new(StoryState.new()), false)
	if expr.has_execute_failed():
		return {"valid": false, "error": "execute failed: %s" % expr.get_error_text()}
	return {"valid": true, "error": ""}
