class_name ScriptContext
extends RefCounted

## What a running story script can see. Handed to every [StoryCommand.run].
##
## TWO COLLABORATORS, split on purpose:
##   * [member host]    -- the WORLD: dialogue, choices, actor moves, emotes, toasts. The live
##                         host is the [code]OverworldController[/code] node; tests pass a
##                         [StoryScriptHost] double that completes instantly. It is a scene
##                         node, so it DIES on a scene change -- which is why nothing that
##                         outlives a scene change (a battle) is ever awaited on it.
##   * [member session] -- the JOURNEY: state, battles, saves, warps. The live session is the
##                         StoryController AUTOLOAD, which survives the battle round trip, so a
##                         StartBattle can await it across two scene changes and the script
##                         resumes on the NEW overworld's host afterwards (the controller
##                         swaps [member host] when the overworld re-attaches).
##
## Every host / session call is duck-typed and guarded, so a script runs to completion with no
## host at all (validation dry-runs, headless tools).

var host = null
var session = null
var state: StoryState = null
var area_id: String = ""
## The entity whose script this is ("" for area / generated scripts). "self" in commands.
var owner_id: String = ""
## The last battle's [BattleResult] (null before any) -- If commands branch on it.
var last_result = null
## Scratch values ("last_choice", ...).
var vars: Dictionary = {}
var stopped: bool = false
var stop_reason: String = ""


func _init(p_state: StoryState = null, p_host = null, p_session = null, p_area_id: String = "") -> void:
	state = p_state if p_state != null else StoryState.new()
	host = p_host
	session = p_session
	area_id = p_area_id


## Stop the script after the current command (a warp, a whiteout, an error).
func stop(reason: String = "") -> void:
	stopped = true
	if stop_reason.is_empty():
		stop_reason = reason


func has_host_method(method: StringName) -> bool:
	return host != null and is_instance_valid(host) and host.has_method(method)


func has_session_method(method: StringName) -> bool:
	return session != null and is_instance_valid(session) and session.has_method(method)


func condition(expr: String) -> bool:
	return ConditionContext.evaluate(expr, state, last_result)


## Resolve an actor reference: "self" -> the owner, else as written ("player" or an id).
func resolve_actor(actor: String) -> String:
	if actor == "self" or actor.is_empty():
		return owner_id
	return actor


## Text substitution done BEFORE a beat is handed to the dialogue: {hero}, {lead}, {gold}.
func substitute(text: String) -> String:
	if not text.contains("{"):
		return text
	var out: String = text
	out = out.replace("{gold}", str(state.gold))
	var lead: StoryPartyMember = state.lead()
	out = out.replace("{lead}", lead.display_name() if lead != null else "your party")
	var hero_name: String = "Warden"
	if has_session_method(&"hero_name"):
		hero_name = String(session.hero_name())
	out = out.replace("{hero}", hero_name)
	return out


## Tell the host flags changed (visible_if / blocking / chest lids re-evaluate).
func world_changed() -> void:
	if has_host_method(&"refresh_world"):
		host.refresh_world()
