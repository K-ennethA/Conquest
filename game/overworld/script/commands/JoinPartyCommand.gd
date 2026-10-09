class_name JoinPartyCommand
extends StoryCommand

## A story recruit joins the party (a new RosterLedger-style member with a stable member_id).
## [member flag_on_join] marks it done so the recruit's entity can disappear (visible_if).
##
## HUMANS (docs/design/HUMANS.md; DECISIONS.md #6, #61): a human is a unique individual -- a
## second join of one already in the party does nothing (ctx.vars["joined"] false, reason
## "already_in_party"). A TEMPORARY join ([member temporary]: the main rivals / allies) is a Guest
## who leaves when the story flag [member guest_until] is set (or by a [LeavePartyCommand]); the
## same guest joining again later comes back as its old record (level, XP, growth kept).

@export var character_id: StringName = &""
@export var nickname: String = ""
@export var flag_on_join: String = ""
## EVOLUTION Growth the recruit joins with (a companion who has already been growing), written
## once into its member record. 0 = a fresh recruit.
@export var growth: int = 0
## The STORY LEVEL the recruit joins at (docs/design/PROGRESSION.md). 0 = the progression rules'
## [member ProgressionRules.starter_level] (the starter joins this way).
@export_range(0, 200) var level: int = 0
## A TEMPORARY join (DECISIONS.md #61): shown as a Guest, deployable in tactical battles, and it
## leaves when [member guest_until] is set.
@export var temporary: bool = false
## The story flag that ends a temporary stay ("" = only a LeaveParty command ends it).
@export var guest_until: String = ""


## The level this command's recruit joins at ([member level], else the starter level).
func join_level() -> int:
	return level if level > 0 else ProgressionRules.current().starter_level


func run(ctx: ScriptContext) -> void:
	var cap: int = 6
	if ctx.has_session_method(&"party_cap"):
		cap = int(ctx.session.party_cap())
	var res: Dictionary = ctx.state.join(String(character_id), nickname, cap, join_level(), temporary, guest_until)
	var m: StoryPartyMember = res.get("member", null)
	ctx.vars["join_reason"] = String(res.get("reason", ""))
	if m == null:
		ctx.vars["joined"] = false
		return
	m.add_growth(growth)
	ctx.vars["joined"] = true
	if not flag_on_join.is_empty():
		ctx.state.set_flag(flag_on_join, 1)
	ctx.world_changed()
	if ctx.has_host_method(&"toast"):
		ctx.host.toast("%s %s!" % [m.display_name(), "joins you for now" if temporary else "joined your party"], "quest")


func describe() -> String:
	return "Join party: %s (Lv %d%s)" % [character_id, join_level(), ", guest" if temporary else ""]


func validate(issues: Array[String]) -> void:
	if CharacterLibrary.get_character(character_id) == null:
		issues.append("character '%s' does not exist" % character_id)
	if level > ProgressionRules.current().max_level:
		issues.append("join level %d is above the level cap" % level)
	if not guest_until.is_empty() and not temporary:
		issues.append("guest_until '%s' set on a permanent join" % guest_until)
