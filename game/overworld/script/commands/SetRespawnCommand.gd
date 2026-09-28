class_name SetRespawnCommand
extends StoryCommand

## Where a whiteout sends the party (the last Wayshrine touched), and light that shrine.

@export var area_id: StringName = &""
@export var entry: StringName = &""
## "<area>.<id>" of the shrine to mark lit ("" = none).
@export var wayshrine_key: String = ""


func run(ctx: ScriptContext) -> void:
	ctx.state.respawn = {"area_id": String(area_id), "entry": String(entry)}
	ctx.state.light_wayshrine(wayshrine_key)


func describe() -> String:
	return "Respawn at %s/%s" % [area_id, entry]
