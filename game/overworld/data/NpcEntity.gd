class_name NpcEntity
extends OverworldEntity

## A person (or creature) you can talk to. What they SAY lives in the [DialogueBank]
## (game/overworld/content/dialogue.json, keyed by area id + this id): the first variant whose
## condition passes plays. An NPC with NO bank entry falls back to [member dialogue], the
## authored .tres scene. Anything richer (a ceremony, a spar offer) goes in
## [member OverworldEntity.on_interact] -- it runs after the line. The speaker name/id fill any
## beat that leaves them blank.

@export var speaker_id: StringName = &""
@export var speaker_name: String = ""
@export var dialogue: StoryScene
## The procedural figure's silhouette ([method OverworldProps.figure] kind) when no
## visual_character is set: villager, elder, guard, officer, trainer, raider, scholar, noble or
## child. "" = guessed from the id (elder / guard / villager).
@export var figure: String = ""


func kind() -> StringName:
	return &"npc"


func is_interactable() -> bool:
	return dialogue != null or not on_interact.is_empty()


## Talkable in [param area_id]: the authored dialogue / script, or a dialogue-bank entry (an NPC
## the owner gave lines in dialogue.json without rebuilding the content).
func is_interactable_in(area_id: String) -> bool:
	return is_interactable() or DialogueBank.has_entry(area_id, String(id))


func interact_script(area_id: String, state: StoryState) -> Array:
	var out: Array = talk_script(area_id, state)
	out.append_array(on_interact)
	return out


## The TALK part of an interaction: the bank's line for this NPC now (nothing when it has an entry
## but no variant matches), else the authored .tres [member dialogue].
func talk_script(area_id: String, state: StoryState) -> Array:
	var out: Array = []
	if DialogueBank.has_entry(area_id, String(id)):
		var say: SayCommand = DialogueBank.say_command(area_id, String(id), state if state != null else StoryState.new())
		if say != null:
			out.append(say)
	elif dialogue != null:
		out.append(SayCommand.from_scene(dialogue))
	return out


## The name dialogue beats use when they leave speaker_name blank.
func speaker_label() -> String:
	if not speaker_name.is_empty():
		return speaker_name
	return display_name
