class_name NpcEntity
extends OverworldEntity

## A person (or creature) you can talk to. [member dialogue] is the shortcut for the common case
## "say this scene"; anything richer goes in [member OverworldEntity.on_interact] (it runs after
## the dialogue). The speaker name/id fill any beat that leaves them blank.

@export var speaker_id: StringName = &""
@export var speaker_name: String = ""
@export var dialogue: StoryScene


func kind() -> StringName:
	return &"npc"


func is_interactable() -> bool:
	return dialogue != null or not on_interact.is_empty()


func interact_script(_area_id: String, _state: StoryState) -> Array:
	var out: Array = []
	if dialogue != null:
		out.append(SayCommand.from_scene(dialogue))
	out.append_array(on_interact)
	return out


## The name dialogue beats use when they leave speaker_name blank.
func speaker_label() -> String:
	if not speaker_name.is_empty():
		return speaker_name
	return display_name
