class_name EmoteCommand
extends StoryCommand

## A "!", "?" or "..." bubble over an actor (a trainer spotting you).

@export var actor: String = "self"
@export var glyph: String = "!"


func run(ctx: ScriptContext) -> void:
	if ctx.has_host_method(&"emote"):
		await ctx.host.emote(ctx.resolve_actor(actor), glyph)


func describe() -> String:
	return "Emote %s over %s" % [glyph, actor]
