class_name IncFlagCommand
extends StoryCommand

## Add to an int flag (counters, quest stages).

@export var key: String = ""
@export var by: int = 1


func run(ctx: ScriptContext) -> void:
	ctx.state.inc_flag(key, by)
	ctx.world_changed()


func describe() -> String:
	return "Inc %s by %d" % [key, by]


func validate(issues: Array[String]) -> void:
	if key.strip_edges().is_empty():
		issues.append("has no flag key")
