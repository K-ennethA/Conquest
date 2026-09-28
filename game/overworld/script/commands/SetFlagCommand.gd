class_name SetFlagCommand
extends StoryCommand

## Set a story flag (quest stages, opened chests, moved guards). Tells the world to re-evaluate
## visibility / blocking afterwards.

@export var key: String = ""
@export var value: int = 1


static func make(p_key: String, p_value: int = 1) -> SetFlagCommand:
	var c := SetFlagCommand.new()
	c.key = p_key
	c.value = p_value
	return c


func run(ctx: ScriptContext) -> void:
	ctx.state.set_flag(key, value)
	ctx.world_changed()


func describe() -> String:
	return "Set %s = %d" % [key, value]


func validate(issues: Array[String]) -> void:
	if key.strip_edges().is_empty():
		issues.append("has no flag key")
