class_name MoveActorCommand
extends StoryCommand

## Walk an actor ("player", "self" or an entity id) to [member to] along a grid path (cutscene
## staging, a trainer walking up, a guard stepping aside). [member persist] records the new spot
## in the save (a guard who moved stays moved); otherwise it lasts until you leave the area.

@export var actor: String = "self"
@export var to: Vector3i = Vector3i.ZERO
@export var persist: bool = false


func run(ctx: ScriptContext) -> void:
	var who: String = ctx.resolve_actor(actor)
	if who != "player":
		# Recorded before the walk (and even with no host), so the state is right either way.
		var facing: String = "south"
		var ov: Dictionary = ctx.state.actor_override(ctx.area_id, who)
		if not ov.is_empty():
			facing = String(ov.get("facing", "south"))
		ctx.state.set_actor_position(ctx.area_id, who, to, facing, persist)
	if ctx.has_host_method(&"move_actor"):
		await ctx.host.move_actor(who, to, persist)


func describe() -> String:
	return "Move %s to %s%s" % [actor, str(to), " (persist)" if persist else ""]
