class_name LeavePartyCommand
extends StoryCommand

## A party member LEAVES (docs/design/HUMANS.md; DECISIONS.md #61): the first member whose form or
## line is [member character_id] -- typically a temporary guest whose part of the journey is over.
## A temporary guest's record is kept for a later re-join; the HERO never leaves (the command does
## nothing for him). ctx.vars["left"] says whether someone left.

@export var character_id: StringName = &""


func run(ctx: ScriptContext) -> void:
	ctx.vars["left"] = false
	var cid: String = String(character_id)
	for m in ctx.state.party:
		if m.character_id != cid and m.line != cid:
			continue
		if bool(ctx.state.remove_member(m.member_id)["ok"]):
			ctx.vars["left"] = true
			ctx.world_changed()
			if ctx.has_host_method(&"toast"):
				ctx.host.toast("%s left the party." % m.display_name(), "quest")
		return


func describe() -> String:
	return "Leave party: %s" % character_id


func validate(issues: Array[String]) -> void:
	if CharacterLibrary.get_character(character_id) == null:
		issues.append("character '%s' does not exist" % character_id)
