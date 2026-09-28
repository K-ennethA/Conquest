class_name WarpCommand
extends StoryCommand

## Scripted area change. TERMINAL: a warp reloads the scene, so the rest of the script stops
## here (put any follow-up in the target area's on_enter).

@export var area_id: StringName = &""
@export var entry: StringName = &""


func run(ctx: ScriptContext) -> void:
	if ctx.has_session_method(&"warp_to"):
		ctx.session.warp_to(String(area_id), String(entry))
	ctx.stop("warped")


func describe() -> String:
	return "Warp to %s/%s" % [area_id, entry]


func validate(issues: Array[String]) -> void:
	if String(area_id).is_empty() or String(entry).is_empty():
		issues.append("has no target")
