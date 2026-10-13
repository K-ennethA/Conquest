class_name SignEntity
extends OverworldEntity

## A signpost: pressing Confirm facing it shows [member text] in the grove text box (a narrator
## beat titled with the sign's display name -- the Pokémon text box read).

@export_multiline var text: String = ""
## "post" = a wooden signpost; "stone" = a carved standing stone (a memorial, a waymarker); "note" =
## a scrap of paper on the ground (a dropped clue); "grave" = a gravestone (the graveyard).
@export_enum("post", "stone", "note", "grave") var look: String = "post"


func kind() -> StringName:
	return &"sign"


func is_interactable() -> bool:
	return true


func prompt_verb() -> String:
	return "Read"


func interact_script(_area_id: String, _state: StoryState) -> Array:
	var say := SayCommand.new()
	say.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR,
		display_name if not display_name.is_empty() else "Signpost", text)])
	var out: Array = [say]
	out.append_array(on_interact)
	return out
