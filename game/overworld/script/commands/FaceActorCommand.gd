class_name FaceActorCommand
extends StoryCommand

## Turn an actor: facing is "north"/"south"/"east"/"west", or "toward:<actor>" (the player turning
## to face the trainer who just walked up).

@export var actor: String = "self"
@export var facing: String = "south"


func run(ctx: ScriptContext) -> void:
	var who: String = ctx.resolve_actor(actor)
	var f: String = facing
	if f.begins_with("toward:"):
		f = "toward:" + ctx.resolve_actor(f.substr(7))
	if ctx.has_host_method(&"face_actor"):
		ctx.host.face_actor(who, f)


func describe() -> String:
	return "Face %s %s" % [actor, facing]
