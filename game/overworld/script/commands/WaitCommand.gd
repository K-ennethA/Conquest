class_name WaitCommand
extends StoryCommand

@export var seconds: float = 0.5


func run(ctx: ScriptContext) -> void:
	if ctx.has_host_method(&"wait"):
		await ctx.host.wait(seconds)


func describe() -> String:
	return "Wait %.2fs" % seconds
