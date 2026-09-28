class_name SayCommand
extends StoryCommand

## Plays dialogue through the host's [StoryDialogue]: an authored [member scene], or inline
## [member beats]. Beats are COPIED before substitution (never mutate a shared resource --
## CONQUEST.md rule 7):
##   * speaker_id "self"  -> the NPC running the script (its speaker id + name);
##   * speaker_id "hero"  -> the player's hero (HeroResource);
##   * {hero} / {lead} / {gold} in the text are filled in.

## Speaker-id placeholders.
const SELF_ID := &"self"
const HERO_ID := &"hero"

@export var scene: StoryScene
@export var beats: Array[Resource] = []


static func from_scene(p_scene: StoryScene) -> SayCommand:
	var s := SayCommand.new()
	s.scene = p_scene
	return s


## A beat builder for code-built scripts (signs, chests, generated prompts).
static func beat(speaker_id: StringName, speaker_name: String, text: String,
		side: StringName = StoryBeat.SIDE_LEFT) -> StoryBeat:
	var b := StoryBeat.new()
	b.speaker_id = speaker_id
	b.speaker_name = speaker_name
	b.text = text
	b.side = side
	return b


func source_beats() -> Array[StoryBeat]:
	var out: Array[StoryBeat] = []
	if scene != null:
		out.append_array(scene.playable_beats())
	for b in beats:
		var sb := b as StoryBeat
		if sb != null:
			out.append(sb)
	return out


## The scene actually shown: copies with placeholders resolved.
func resolved_scene(ctx: ScriptContext) -> StoryScene:
	var out := StoryScene.new()
	out.scene_id = scene.scene_id if scene != null else &"say"
	var typed: Array[Resource] = []
	for b in source_beats():
		typed.append(resolve_beat(b, ctx))
	out.beats = typed
	return out


static func resolve_beat(b: StoryBeat, ctx: ScriptContext) -> StoryBeat:
	var copy: StoryBeat = b.duplicate() as StoryBeat
	if copy.speaker_id == SELF_ID:
		copy.speaker_id = StringName(String(ctx.vars.get("owner_speaker_id", "")))
		if copy.speaker_name.is_empty():
			copy.speaker_name = String(ctx.vars.get("owner_speaker_name", ""))
		if String(copy.speaker_id).is_empty():
			copy.speaker_id = StringName("npc_" + ctx.owner_id)
	elif copy.speaker_id == HERO_ID:
		if copy.speaker_name.is_empty() and ctx.has_session_method(&"hero_name"):
			copy.speaker_name = String(ctx.session.hero_name())
		if ctx.has_session_method(&"hero_speaker_id"):
			copy.speaker_id = StringName(String(ctx.session.hero_speaker_id()))
	copy.text = ctx.substitute(copy.text)
	copy.speaker_name = ctx.substitute(copy.speaker_name)
	return copy


func run(ctx: ScriptContext) -> void:
	var shown: StoryScene = resolved_scene(ctx)
	if shown.is_empty():
		return
	if ctx.has_host_method(&"show_dialogue"):
		await ctx.host.show_dialogue(shown)


func describe() -> String:
	var bs: Array[StoryBeat] = source_beats()
	var who: String = ""
	for b in bs:
		if not b.is_narrator():
			who = b.speaker_name if not b.speaker_name.is_empty() else String(b.speaker_id)
			break
	return "Say: %s(%d line%s)" % ["%s " % who if not who.is_empty() else "", bs.size(),
		"" if bs.size() == 1 else "s"]


func validate(issues: Array[String]) -> void:
	if source_beats().is_empty():
		issues.append("has no lines")
