class_name JoinPartyCommand
extends StoryCommand

## A story recruit joins the party (a new RosterLedger-style member with a stable member_id).
## [member flag_on_join] marks it done so the recruit's entity can disappear (visible_if).

@export var character_id: StringName = &""
@export var nickname: String = ""
@export var flag_on_join: String = ""
## EVOLUTION Growth the recruit joins with (a companion who has already been growing), written
## once into its member record. 0 = a fresh recruit.
@export var growth: int = 0


func run(ctx: ScriptContext) -> void:
	var cap: int = 6
	if ctx.has_session_method(&"party_cap"):
		cap = int(ctx.session.party_cap())
	var m: StoryPartyMember = ctx.state.add_member(String(character_id), nickname, cap)
	if m == null:
		ctx.vars["joined"] = false
		return
	m.add_growth(growth)
	ctx.vars["joined"] = true
	if not flag_on_join.is_empty():
		ctx.state.set_flag(flag_on_join, 1)
	ctx.world_changed()
	if ctx.has_host_method(&"toast"):
		ctx.host.toast("%s joined your party!" % m.display_name(), "quest")


func describe() -> String:
	return "Join party: %s" % character_id


func validate(issues: Array[String]) -> void:
	if CharacterLibrary.get_character(character_id) == null:
		issues.append("character '%s' does not exist" % character_id)
