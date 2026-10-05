class_name BefriendPromptCommand
extends StoryCommand

## THE BEFRIEND PROMPT (DECISIONS.md: collecting is in scope). After a battle whose
## [BattleResult] carries an open befriend_offer {character_id, accepted: false}, ask
## "<X> wants to join you!" through the dialogue choice. "Welcome it" -> a new party member
## (stable member_id), offer.accepted = true, result.befriended = the id, [member flag_on_join]
## set. "Not now" / no offer -> nothing. A full party explains itself and declines (the Grove
## storage is M2).
##
## Non-missable story recruits: the recruit's entity is gated on [member flag_on_join], so a
## loss, a flee or a "Not now" leaves it in the world to try again.

const OPTION_ACCEPT := "Welcome it"
const OPTION_DECLINE := "Not now"

@export var flag_on_join: String = ""


func run(ctx: ScriptContext) -> void:
	var result = ctx.last_result
	if result == null or not result.has_open_offer():
		return
	var cid: String = String(result.befriend_offer.get("character_id", ""))
	var c: CharacterResource = CharacterLibrary.get_character(StringName(cid))
	if c == null:
		return
	var who: String = c.display_name
	var prompt: StoryBeat = SayCommand.beat(StringName(cid), who,
		"%s lowers its guard and looks at you for a long moment... %s wants to join you!" % [who, who])
	var picked: int = 1
	if ctx.has_host_method(&"show_choice"):
		picked = int(await ctx.host.show_choice(prompt, PackedStringArray([OPTION_ACCEPT, OPTION_DECLINE]), 1))
	if picked != 0:
		return
	var cap: int = 6
	if ctx.has_session_method(&"party_cap"):
		cap = int(ctx.session.party_cap())
	# A befriended creature keeps the level it was met at (PROGRESSION.md §1); unknown = level 1.
	var met_level: int = maxi(1, int(result.befriend_offer.get("level", 0)))
	var m: StoryPartyMember = ctx.state.add_member(cid, "", cap, met_level)
	if m == null:
		if ctx.has_host_method(&"show_dialogue"):
			var full := StoryScene.new()
			full.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, "",
				"Your party is full. %s wanders back into the grass." % who)])
			await ctx.host.show_dialogue(full)
		return
	result.befriend_offer["accepted"] = true
	result.befriended = cid
	if not flag_on_join.is_empty():
		ctx.state.set_flag(flag_on_join, 1)
	ctx.world_changed()
	if ctx.has_host_method(&"toast"):
		ctx.host.toast("%s joined your party!" % m.display_name(), "quest")


func describe() -> String:
	return "Befriend prompt%s" % (" -> %s" % flag_on_join if not flag_on_join.is_empty() else "")
