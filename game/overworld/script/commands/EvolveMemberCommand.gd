class_name EvolveMemberCommand
extends StoryCommand

## A SCRIPTED EVOLUTION (docs/design/EVOLUTION.md §6 "evolve_member(uid_or_line, edge_id)"): a
## story beat -- "the shrine awakens Sprig" -- offers party member [member member] the evolution
## [member edge_id] on the Evolution screen, past the edge's usual triggers ([member scripted]).
## The member must currently BE the edge's from-form; otherwise nothing happens. Evolving follows
## the story rule (the member becomes the form; the form unlocks for open modes) and saves.
## ctx.vars["evolved"] says whether it did (for a later If).

## A member id ("tree_grunt#2") or a line / character id ("tree_grunt": the first party member
## of that line).
@export var member: String = ""
@export var edge_id: StringName = &""
## Skip the edge's triggers (Growth etc.): the story itself is the trigger.
@export var scripted: bool = true


func run(ctx: ScriptContext) -> void:
	ctx.vars["evolved"] = false
	var m: StoryPartyMember = find_member(ctx.state, member)
	var edge: EvolutionResource = EvolutionLibrary.get_edge(edge_id)
	if m == null or edge == null or StringName(m.character_id) != edge.from_id:
		return
	if not scripted and StoryGrowth.available_for(m, StoryGrowth.evolution_context(ctx.state)).is_empty():
		return
	if not ctx.has_session_method(&"offer_evolution"):
		return
	var extra: Dictionary = StoryGrowth.evolution_context(ctx.state, {"trigger": "script"})
	ctx.vars["evolved"] = bool(await ctx.session.offer_evolution(m.member_id, [edge], extra, scripted))
	ctx.world_changed()


## The party member [param key] names: an exact member id, else the first member of that line
## (or currently that character). null when none.
static func find_member(state: StoryState, key: String) -> StoryPartyMember:
	if state == null or key.is_empty():
		return null
	var exact: StoryPartyMember = state.member(key)
	if exact != null:
		return exact
	for m in state.party:
		if m.line == key or m.character_id == key:
			return m
	return null


func describe() -> String:
	return "Evolve member: %s -> %s" % [member, edge_id]


func validate(issues: Array[String]) -> void:
	if member.strip_edges().is_empty():
		issues.append("names no party member")
	if EvolutionLibrary.get_edge(edge_id) == null:
		issues.append("evolution edge '%s' does not exist" % edge_id)
