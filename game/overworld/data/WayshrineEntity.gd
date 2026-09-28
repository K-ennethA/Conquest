class_name WayshrineEntity
extends OverworldEntity

## A Wayshrine (the fountain in a town square): touching it heals the party, clears wounds, sets
## your respawn point (where a whiteout sends you) and saves. Lit once -> flag
## wayshrine.<area>.<id>.lit (fast travel between lit shrines is M3).

## Entry point (in this area) a whiteout respawns you at.
@export var respawn_entry: StringName = &"wayshrine"
@export_multiline var message: String = "The Wayshrine's light washes over your party. Your wounds close, and your journey is recorded."


func kind() -> StringName:
	return &"wayshrine"


func auto_flag(area_id: String) -> String:
	return "wayshrine.%s.%s.lit" % [area_id, String(id)]


func is_interactable() -> bool:
	return true


func prompt_verb() -> String:
	return "Touch"


func interact_script(area_id: String, _state: StoryState) -> Array:
	var out: Array = []
	var lit := SetFlagCommand.new()
	lit.key = auto_flag(area_id)
	lit.value = 1
	out.append(lit)
	out.append(HealPartyCommand.new())
	var respawn := SetRespawnCommand.new()
	respawn.area_id = StringName(area_id)
	respawn.entry = respawn_entry
	respawn.wayshrine_key = "%s.%s" % [area_id, String(id)]
	out.append(respawn)
	out.append(SaveGameCommand.new())
	var say := SayCommand.new()
	say.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR,
		display_name if not display_name.is_empty() else "Wayshrine", message)])
	out.append(say)
	out.append_array(on_interact)
	return out
